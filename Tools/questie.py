"""Builds Data/Corrections.lua from QuestieDB (the Questie team's database, used under the GPLv3
terms its LICENSE.md offers): checks every recipe item's sources in this plugin's data (ForeverRecipes'
tables, then Data/Polestar.lua, the way Where.lua merges them) against QuestieDB's, and writes what
to take away, what to add, and the NPC records those need. Run from the repo root with the AddOns
folder:

	python Tools/questie.py "D:/World of Warcraft/_forever_/Interface/AddOns" [--report FILE]

Reads QuestieDB's baked store (QuestieDB/QuestieDB_Forever.toc: every entity is a TOC metadata field,
CBOR in base64, the way QuestieDB/src/read/baked.lua reads it), its Forever zone tables
(support/Forever/Zones), Polestar_Codex (the third source, through Tools/polestar.py) and this
plugin's Data/. --report writes every difference found and what was made of it.

What is written:
- a source QuestieDB has that ours lacks (a vendor, a quest reward, a named drop, a container, a
  specific object): added. Where both name different NPCs and nothing else backs QuestieDB's, ours
  is kept and nothing is added (listed in the report).
- more than WORLD_DROP drop NPCs: a world drop. Written as its level range, and only for an item
  with no other source.
- a vendor of ours QuestieDB says isn't one (no vendor flag, not among its vendors for the item),
  where Polestar's other sources list the item's vendors without it: taken away.
- a vendor or drop NPC no one can travel to: summoned by players (SUMMONED, by name: QuestieDB has
  no flag for it), never added and taken away from ours; with no fixed spawn in QuestieDB (and
  none in ours), not added. Either way, unless it is the item's only source (then kept, and
  listed in the report).
- an NPC our sources name with no place on the map: QuestieDB's spawns. An NPC whose faction both
  QuestieDB and Polestar give otherwise, or with a place neither puts it in: its record corrected.
Facts QuestieDB lacks (it has no drop chances for recipes, no prices, no reputation) are left as
ours.
"""
import base64, collections, math, os, re, struct, sys

sys.dont_write_bytecode = True     # (no __pycache__ left in Tools/)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import polestar as P

ARGS = sys.argv[1:]
REPORT = ARGS[ARGS.index('--report') + 1] if '--report' in ARGS else None
ROOT = P.ROOT
ADDONS = next((a for a in ARGS if not a.startswith('--') and a != REPORT), r'D:\World of Warcraft\_forever_\Interface\AddOns')
P.ADDONS, P.CODEX = ADDONS, os.path.join(ADDONS, 'Polestar_Codex')
QDB = os.path.join(ADDONS, 'QuestieDB')
OUT = os.path.join(ROOT, 'Data', 'Corrections.lua')

WORLD_DROP = 40       # more drop NPCs than this: a world drop
MAX_OBJECTS = 3       # more objects than this: the world's chests, left out
MAX_SPAWNS = 8        # places per NPC record (one per map)
FAR = 10              # map units (of 100) from every known spawn and walk: a wrong spot
CONTINENTS = (1414, 1415)
VENDOR_FLAG = 4       # Classic npcflags: vendor
# Vendors a player summons (engineering bots, Jeeves): no flag of QuestieDB's marks them, so by name.
SUMMONED = ('Reagent Bot', 'Repair Bot', 'Field Repair Bot', 'Portable Repair Bot', 'Jeeves')
PROFESSIONS = {129: 'First Aid', 164: 'Blacksmithing', 165: 'Leatherworking', 171: 'Alchemy', 185: 'Cooking',
	186: 'Mining', 197: 'Tailoring', 202: 'Engineering', 333: 'Enchanting', 40: 'Poisons', 182: 'Herbalism',
	356: 'Fishing', 393: 'Skinning'}

# --------------------------------------------------------------------------------------------
# QuestieDB's baked store: TOC metadata fields "X-<Entity>-<id>-S" (the scalar row) and
# "X-<Entity>-<id>-<field>" (one table field), CBOR in base64; "~N~" joins N numbered parts.
# --------------------------------------------------------------------------------------------


def cbor(b, i=0):
	ib = b[i]
	mt, ai = ib >> 5, ib & 31
	i += 1
	if mt == 7:
		if ai == 25:
			h = struct.unpack('>H', b[i:i + 2])[0]
			e, f = (h >> 10) & 31, h & 1023
			v = (f / 1024) * 2 ** -14 if e == 0 else (1 + f / 1024) * 2 ** (e - 15)
			return (-v if h >> 15 else v), i + 2
		if ai == 26:
			return struct.unpack('>f', b[i:i + 4])[0], i + 4
		if ai == 27:
			return struct.unpack('>d', b[i:i + 8])[0], i + 8
		return {20: False, 21: True}.get(ai), i
	if ai < 24:
		v = ai
	elif ai == 31:
		v = None
	else:
		n = 1 << (ai - 24)
		v = int.from_bytes(b[i:i + n], 'big')
		i += n
	if mt == 0:
		return v, i
	if mt == 1:
		return -1 - v, i
	if mt in (2, 3):
		return b[i:i + v].decode('utf-8', 'replace'), i + v
	if mt == 6:
		return cbor(b, i)
	out = [] if mt == 4 else {}
	count = 0
	while (v is None and b[i] != 0xff) or (v is not None and count < v):
		if mt == 4:
			x, i = cbor(b, i)
			out.append(x)
		else:
			k, i = cbor(b, i)
			x, i = cbor(b, i)
			out[k] = x
		count += 1
	return out, i + (1 if v is None else 0)


def keyed(v):
	"""A Lua table as CBOR gives it: a sequence comes as a list (keys 1..n)."""
	if isinstance(v, list):
		return {i + 1: x for i, x in enumerate(v) if x is not None}
	return v or {}


class Store:
	FIELDS = {'Item': 16, 'Npc': 15, 'Object': 7, 'Quest': 36}

	def __init__(self):
		self.raw = {}
		toc = os.path.join(QDB, 'QuestieDB_Forever.toc')
		for line in open(toc, encoding='utf-8'):
			if line.startswith('## X-'):
				k, _, v = line[5:].partition(':')
				self.raw[k.strip()] = v.strip()
		self.version = self.raw.get('BUILD-COMMIT', '?')
		m = re.search(r'^## Version: (\S+)', open(toc, encoding='utf-8').read(), re.M)
		self.release = m.group(1) if m else '?'
		self.cache = {}

	def stored(self, key):
		v = self.raw.get(key)
		m = v and re.match(r'^~(\d+)~$', v)
		if m:
			v = ''.join(self.raw[key + '-%d' % j] for j in range(1, int(m.group(1)) + 1))
		return v

	def get(self, kind, i):
		key = (kind, i)
		if key in self.cache:
			return self.cache[key]
		s = self.stored('%s-%d-S' % (kind, i))
		row = None
		if s is not None:
			row = keyed(cbor(base64.b64decode(s))[0])
			present = row.pop('p', 0)
			for f in range(1, self.FIELDS[kind] + 1):
				if present >> (f - 1) & 1:
					t = self.stored('%s-%d-%d' % (kind, i, f))
					if t is not None:
						row[f] = cbor(base64.b64decode(t))[0]
		self.cache[key] = row
		return row


def lua_block(path, name):
	s = open(path, encoding='utf-8').read()
	m = re.search(r'ZoneDB\.private\.%s = \[\[return \{(.*?)\}\]\]' % name, s, re.S)
	return m.group(1) if m else ''


def zone_tables():
	zones = os.path.join(QDB, 'support', 'Forever', 'Zones')
	area = {}
	for name in ('areaIdToUiMapId', 'areaIdToUiMapIdOverride'):
		for a, m in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', lua_block(os.path.join(zones, 'areaIdToUiMapId.lua'), name)):
			area[int(a)] = int(m)
	dungeons = {}
	for a, nm in re.findall(r'\[(\d+)\]\s*=\s*\{\s*"((?:[^"\\]|\\.)*)"', open(os.path.join(zones, 'dungeons.lua'), encoding='utf-8').read()):
		dungeons[int(a)] = nm
	return area, dungeons

# --------------------------------------------------------------------------------------------
# Checking
# --------------------------------------------------------------------------------------------


def main():
	L = P.as_list
	qdb = Store()
	area, dungeons = zone_tables()
	cx = P.load_codex()

	data = {}
	for f, names in (('Recipes.lua', ('Recipes',)), ('Npcs.lua', ('Npcs', 'Quests')),
			('Sources.lua', ('Trainers', 'AutomaticRecipes', 'AutomaticQuests', 'Sellers', 'Drops', 'OtherDrops', 'QuestRewards')),
			('Polestar.lua', ('PolestarTeach', 'PolestarSources', 'PolestarNpcs', 'Camping'))):
		data.update(P.lua_tables(os.path.join(ROOT, 'Data', f), names))
	recipes, npcs, psnpcs = data['Recipes'], data['Npcs'], data['PolestarNpcs']

	def table(t, k):
		v = data[t]
		return L(v.get(k)) if isinstance(v, dict) else []

	def cname(group, i):
		return cx.get(group, {}).get('names', {}).get(i)

	def cx_item(i):
		for g in P.ITEM_GROUPS:
			r = cx.get(g, {}).get('recs', {}).get(i)
			if r is not None:
				return P.decode_item(r)
		return None

	def cx_npc(i):
		for g in ('npc', 'rare'):
			r = cx.get(g, {}).get('recs', {}).get(i)
			if r is not None:
				return P.decode_npc(r)
		return None

	def fr_any(spell, teach):
		if table('Trainers', spell) or data['AutomaticRecipes'].get(spell):
			return True
		if isinstance(data['AutomaticQuests'], dict) and data['AutomaticQuests'].get(spell):
			return True
		return bool(teach) and any(table(t, teach) for t in ('Sellers', 'Drops', 'OtherDrops', 'QuestRewards'))

	# Recipe items: what teaches each recipe (ForeverRecipes', else Polestar's), and the camping
	# blueprints.
	items = collections.defaultdict(list)
	for spell, d in recipes.items():
		d = L(d)
		teach = (d[4] if len(d) > 4 and d[4] else None) or data['PolestarTeach'].get(spell)
		if teach:
			items[teach].append(spell)
	for c in L(data['Camping']):
		c = L(c)
		if c[4] and c[4] not in items:
			items[c[4]] = []

	def line_of(item):
		for s in items[item]:
			return L(recipes[s])[0]
		return 0

	# Ours, as Where.lua shows it: ForeverRecipes' tables, else Polestar's.
	def ours(item):
		spells = items[item]
		fr = any(fr_any(s, L(recipes[s])[4] if len(L(recipes[s])) > 4 else None) for s in spells)
		o = {'layer': 'fr' if fr else 'ps', 'v': set(table('Sellers', item)), 'd': {}, 'q': set(table('QuestRewards', item)),
			'o': set(), 'n': set(), 'w': False, 'any': fr}
		for x in table('Drops', item):
			o['d'][L(x)[0]] = L(x)[1]
		for x in table('OtherDrops', item):
			m = re.match(r'Object (\d+)', x.get('name', '') if isinstance(x, dict) else '')
			if m:
				o['o'].add(int(m.group(1)))
		if not fr:
			for s in table('PolestarSources', item):
				s = L(s)
				k = s[0]
				o['any'] = True
				if k == 'v': o['v'].add(s[1])
				elif k == 'd': o['d'][s[1]] = s[2]
				elif k == 'q': o['q'].add(s[1])
				elif k == 'o': o['o'].add(s[1])
				elif k == 'n': o['n'].add(s[1])
				elif k == 'w': o['w'] = True
				elif k == 'r' and len(s) > 3 and s[3]: o['v'].add(s[3])
		return o

	# Polestar's sources for an item that aren't QuestieDB's alone: the third source.
	def third(item):
		it = cx_item(item)
		out = collections.defaultdict(set)
		for s in (it or {}).get('sources', []):
			if s['from'].replace('q', ''):
				who = s.get('npc') or s.get('quest') or s.get('object') or s.get('item')
				if who:
					out[s['type']].add(who)
		return out

	# NPCs: a name and places for any our sources or the additions name.
	def qnpc(i):
		return qdb.get('Npc', i)

	def has_spot(rec):
		return any(len(L(l)) >= 4 and L(l)[1] for l in L(rec)[2:])

	def zone_name(mp):
		return cname('zone', mp) or ''

	def qdb_places(i):
		"""QuestieDB's spawns: { uiMapID: [(x, y)] } on maps, and the dungeons it's in."""
		q = qnpc(i) or {}
		maps, inside = collections.defaultdict(list), []
		for a, pts in keyed(q.get(7)).items():
			mp = area.get(a)
			for p in pts:
				if p[0] < 0 or not mp:
					if a in dungeons and dungeons[a] not in inside:
						inside.append(dungeons[a])
				else:
					maps[mp].append((p[0], p[1]))
		walks = collections.defaultdict(list)
		for a, paths in keyed(q.get(8)).items():
			mp = area.get(a)
			for path in paths or []:
				for p in path or []:
					if mp and p and p[0] >= 0:
						walks[mp].append((p[0], p[1]))
		return maps, walks, inside

	def central(pts):
		cx_, cy_ = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
		return min(pts, key=lambda p: (p[0] - cx_) ** 2 + (p[1] - cy_) ** 2)

	def qdb_locs(i):
		maps, _, inside = qdb_places(i)
		locs = []
		for mp in sorted(maps, key=lambda m: -len(maps[m]))[:MAX_SPAWNS]:
			x, y = central(maps[mp])
			locs.append((zone_name(mp), mp, round(x, 1), round(y, 1)))
		if not locs:
			locs = [(nm,) for nm in inside[:MAX_SPAWNS]]
		return locs

	def faction_of(q):
		f = q.get(13) if q else None
		return f if f in ('A', 'H') else False

	report = []
	counts = collections.Counter()
	per_prof = collections.defaultdict(collections.Counter)

	def note(cls, item, text):
		counts[cls] += 1
		per_prof[PROFESSIONS.get(line_of(item), 'Camping')][cls] += 1
		qi = qdb.get('Item', item) or {}
		report.append('%s\t%d\t%s\t%s' % (cls, item, qi.get(1, ''), text))

	def unreachable(x, theirs=True):
		"""Why no one can travel to an NPC, or None. (Ours are only taken away when summoned: an
		instance or battleground NPC QuestieDB has no spawn for is still fought there.)"""
		n = qnpc(x)
		rec = L(npcs.get(x) or psnpcs.get(x) or [])
		name = (n or {}).get(1) or (rec[0] if rec else '')
		if name in SUMMONED:
			return 'summoned by players'
		if theirs and n is not None and not keyed(n.get(7)) and len(rec) <= 2:
			return 'no fixed spawn in QuestieDB'
		return None

	add, remove = {}, {}
	quests, objects, names_item = {}, {}, {}
	need = set()
	unknown_before, unknown_after = [], []

	for item in sorted(items):
		o = ours(item)
		q = qdb.get('Item', item)
		if not q:
			counts['not in QuestieDB'] += 1
			if not o['any']:
				unknown_before.append(item)
				unknown_after.append(item)
			continue
		t = third(item)
		adds, gone = [], collections.defaultdict(list)
		qv, qd, qo, qn, qq = (set(q.get(f) or []) for f in (14, 2, 3, 4, 6))
		skipped = []     # (kind, npc, why): additions no one can travel to

		# Vendors.
		only_ours, only_qdb, both = o['v'] - qv, qv - o['v'], o['v'] & qv
		conflict = only_ours and len(only_ours) >= len(both)
		for x in sorted(only_qdb):
			if not (qnpc(x) or x in npcs or x in psnpcs):
				continue
			if conflict and x not in t['vendor']:
				note('d', item, 'vendor %d %s: QuestieDB only, ours names others; kept ours' % (x, (qnpc(x) or {}).get(1, '')))
				continue
			if unreachable(x):
				skipped.append(('v', x, unreachable(x)))
				continue
			adds.append(('v', x))
			need.add(x)
			note('b', item, 'vendor %d %s added' % (x, (qnpc(x) or {}).get(1, '')))
		for x in sorted(only_ours):
			n = qnpc(x)
			if n and not (n.get(15, 0) & VENDOR_FLAG) and qv and t['vendor'] and x not in t['vendor']:
				gone['v'].append(x)
				note('a', item, 'vendor %d %s removed: not a vendor in QuestieDB (flags %s), not among its or Polestar\'s vendors' % (
					x, n.get(1, ''), n.get(15, 0)))
			else:
				note('c', item, 'vendor %d %s: ours only, kept%s' % (x, (n or {}).get(1, ''), ' (Polestar agrees)' if x in t['vendor'] else ''))

		# Quest rewards.
		for x in sorted(qq - o['q']):
			adds.append(('q', x))
			quests[x] = (qdb.get('Quest', x) or {}).get(1)
			note('b', item, 'quest %d %s added' % (x, quests[x] or ''))
		for x in sorted(o['q'] - qq):
			note('c', item, 'quest %d: ours only, kept' % x)

		# Drops.
		if len(qd) > WORLD_DROP:
			lv = sorted(l for x in qd for l in ((qnpc(x) or {}).get(4), (qnpc(x) or {}).get(5)) if l)
			if not o['any'] and not o['w'] and not adds and lv:
				lo, hi = lv[len(lv) // 20], lv[-1 - len(lv) // 20]
				adds.append(('w', lo, hi))
				note('b', item, 'world drop, levels %d to %d (QuestieDB: %d NPCs)' % (lo, hi, len(qd)))
		else:
			only_ours, only_qdb, both = set(o['d']) - qd, qd - set(o['d']), set(o['d']) & qd
			conflict = only_ours and qd and len(only_ours) >= len(both)
			for x in sorted(only_qdb):
				if not (qnpc(x) or x in npcs or x in psnpcs):
					continue
				if conflict and x not in t['drop']:
					note('d', item, 'drop %d %s: QuestieDB only, ours names others; kept ours' % (x, (qnpc(x) or {}).get(1, '')))
					continue
				if unreachable(x):
					skipped.append(('d', x, unreachable(x)))
					continue
				adds.append(('d', x))
				need.add(x)
				note('b', item, 'drop %d %s added' % (x, (qnpc(x) or {}).get(1, '')))
			for x in sorted(only_ours):
				note('c', item, 'drop %d: ours only, kept%s' % (x, ' (Polestar agrees)' if x in t['drop'] else ''))

		# Containers and objects.
		for x in sorted(qn - o['n']):
			adds.append(('n', x))
			names_item[x] = (qdb.get('Item', x) or {}).get(1)
			note('b', item, 'container %d %s added' % (x, names_item[x] or ''))
		if len(qo) <= MAX_OBJECTS:
			for x in sorted(qo - o['o']):
				adds.append(('o', x))
				objects[x] = (qdb.get('Object', x) or {}).get(1)
				note('b', item, 'object %d %s added' % (x, objects[x] or ''))

		# NPCs no one can travel to: ours taken away, QuestieDB's left out, unless that leaves the
		# item with no source at all (then kept, and listed).
		kinds = {'v': 'vendor', 'd': 'drop'}
		for k, x in sorted([('v', x) for x in o['v']] + [('d', x) for x in o['d']]):
			why = unreachable(x, False)
			if why and x not in gone[k]:
				gone[k].append(x)
				skipped.append((k, x, why, 'ours'))
		ours_left = len(o['v'] - set(gone['v'])) + len(set(o['d']) - set(gone['d'])) + len(o['q']) + len(o['o']) + len(o['n']) + o['w']
		taught = any(table('Trainers', sp) or data['AutomaticRecipes'].get(sp) for sp in items[item])
		if skipped and not ours_left and not adds and not taught:
			for s in skipped:
				if len(s) > 3:
					gone[s[0]].remove(s[1])
				else:
					adds.append((s[0], s[1]))
					need.add(s[1])
				note('kept-only', item, "%s %d %s: %s, but the item's only source; kept" % (kinds[s[0]], s[1], (qnpc(s[1]) or {}).get(1, ''), s[2]))
		else:
			for s in skipped:
				name = (qnpc(s[1]) or {}).get(1, '')
				if len(s) > 3:
					note('a', item, '%s %d %s removed: %s' % (kinds[s[0]], s[1], name, s[2]))
				else:
					note('skipped', item, '%s %d %s left out: %s' % (kinds[s[0]], s[1], name, s[2]))
		gone = {k: v for k, v in gone.items() if v}
		if adds:
			add[item] = adds
		if gone:
			remove[item] = gone
		if not o['any']:
			unknown_before.append(item)
			if not adds:
				unknown_after.append(item)

	# The NPCs: every one our sources and the additions name.
	refs = set(need)
	for item in items:
		o = ours(item)
		refs |= o['v'] | set(o['d'])
	for spell in data['Trainers']:
		for r in table('Trainers', spell):
			refs.add(L(r)[0])
	fix_npcs = {}
	for i in sorted(refs):
		fr, psr, q = L(npcs.get(i) or []), L(psnpcs.get(i) or []), qnpc(i)
		base = fr or psr
		if not q and not base:
			continue
		maps, walks, inside = qdb_places(i) if q else ({}, {}, [])
		if not base:
			if q:
				fix_npcs[i] = (q.get(1, ''), faction_of(q), qdb_locs(i))
				counts['npc added'] += 1
			continue
		# (Where.lua takes Polestar's places when ForeverRecipes has no spot on the map.)
		nm, fac, locs = base[0], base[1], [tuple(L(l)) for l in base[2:]]
		if fr and psr and not has_spot(fr):
			locs += [tuple(L(l)) for l in psr[2:] if len(L(l)) >= 4 and L(l)[1]]
		changed = []
		# Faction: QuestieDB and Polestar agree on A or H, ours says otherwise.
		c = cx_npc(i)
		if q and faction_of(q) and c and c['faction'] == faction_of(q) and fac != faction_of(q):
			changed.append('faction %s -> %s' % (fac or 'both', faction_of(q)))
			fac = faction_of(q)
		# Places neither QuestieDB nor Polestar puts it in, or far from every spawn and walk.
		if maps:
			ps_maps = collections.defaultdict(list)
			for mp, x, y in (c or {}).get('spawns', []):
				ps_maps[mp].append((x, y))
			kept = []
			for l in locs:
				if len(l) < 4 or not l[1] or l[1] in CONTINENTS:
					kept.append(l)
					continue
				mp, x, y = l[1], l[2], l[3]
				near = maps.get(mp, []) + walks.get(mp, []) + ps_maps.get(mp, [])
				if not near:
					changed.append('place %s (%s %s,%s) removed: QuestieDB has it in %s' % (l[0], mp, x, y, ', '.join(
						zone_name(m) or str(m) for m in maps)))
					continue
				d = min(math.hypot(x - a, y - b) for a, b in near)
				if d > FAR:
					nx, ny = central(maps[mp]) if maps.get(mp) else central(near)
					changed.append('place %s %s,%s -> %.1f,%.1f (%.0f away from every spawn)' % (l[0], x, y, nx, ny, d))
					l = (l[0], mp, round(nx, 1), round(ny, 1))
				kept.append(l)
			if not any(len(l) >= 4 and l[1] for l in kept):
				# No spot on the map left (or never one): QuestieDB's.
				spots = [l for l in qdb_locs(i) if len(l) >= 4]
				if spots:
					changed.append('places from QuestieDB')
					kept = spots + [l for l in kept if not (len(l) >= 4 and l[1])]
			locs = kept
		if changed:
			fix_npcs[i] = (nm, fac, locs)
			for ch in changed:
				cls = 'b' if ch == 'places from QuestieDB' else 'a'
				counts['npc ' + cls] += 1
				report.append('npc-%s\t%d\t%s\t%s' % (cls, i, nm, ch))

	# Recipes listed as "Source not known yet" (any faction's), before and after.
	def spell_unknown(spell, still):
		d = L(recipes[spell])
		teach = (d[4] if len(d) > 4 and d[4] else None) or data['PolestarTeach'].get(spell)
		if fr_any(spell, d[4] if len(d) > 4 else None):
			return False
		return not teach or teach in still
	before, after = set(unknown_before), set(unknown_after)
	spells_before = [s for s in recipes if spell_unknown(s, before)]
	spells_after = [s for s in recipes if spell_unknown(s, after)]
	counts['recipes unknown before'] = len(spells_before)
	counts['recipes unknown after'] = len(spells_after)
	by_line = collections.Counter(PROFESSIONS.get(L(recipes[s])[0], '?') for s in spells_after)

	write(qdb, add, remove, fix_npcs, quests, objects, names_item)

	print('items with additions', len(add), 'with removals', len(remove), 'npc records', len(fix_npcs))
	print('classes', dict(sorted(counts.items())))
	print('unknown before', len(unknown_before), 'after', len(unknown_after))
	if REPORT:
		with open(REPORT, 'w', encoding='utf-8', newline='\n') as f:
			f.write('classes\t%s\n' % dict(sorted(counts.items())))
			for p in sorted(per_prof):
				f.write('profession\t%s\t%s\n' % (p, dict(sorted(per_prof[p].items()))))
			f.write('unknown before\t%d\nunknown after\t%d\n' % (len(unknown_before), len(unknown_after)))
			f.write('recipes still unknown by profession\t%s\n' % dict(by_line))
			for s in sorted(spells_after):
				d = L(recipes[s])
				f.write('recipe still unknown\t%d\t%s\tteach %s\n' % (s, PROFESSIONS.get(d[0], '?'), (d[4] if len(d) > 4 and d[4] else None) or data['PolestarTeach'].get(s)))
			for i in unknown_after:
				f.write('still unknown\t%d\t%s\t%s\n' % (i, (qdb.get('Item', i) or {}).get(1, ''), PROFESSIONS.get(line_of(i), 'Camping')))
			f.write('\n'.join(report) + '\n')


def q(s):
	return '"' + (s or '').replace('\\', '\\\\').replace('"', '\\"') + '"'


def write(qdb, add, remove, npcs, quests, objects, items):
	n = P.n
	L = []
	w = L.append
	w('-- Generated by Tools/questie.py from QuestieDB %s (%s, Forever baked store); do not edit.' % (qdb.release, qdb.version[:12]))
	w('-- Facts from QuestieDB by the Questie team (https://github.com/Questie/QuestieDB), used under the')
	w('-- GPLv3 terms its LICENSE.md offers: see LICENSE.md. Applied by Where.lua after ForeverRecipes\' and')
	w('-- Polestar\'s data: what is taken away first, then what is added.')
	w('local _, ns = ...')
	w('')
	w('-- Recipe item -> { remove = { v = { [npc] = true } }, add = { sources } }, sources as in')
	w('-- ns.PolestarSources: {"v",npc} vendor, {"d",npc} drop, {"q",quest}, {"o",object}, {"n",item} in a')
	w('-- container, {"w",minLevel,maxLevel} world drop.')
	w('ns.CorrectionSources = {')
	for i in sorted(set(add) | set(remove)):
		parts = []
		if i in remove:
			parts.append('remove={%s}' % ','.join('%s={%s}' % (k, ','.join('[%d]=true' % x for x in sorted(v))) for k, v in sorted(remove[i].items())))
		if i in add:
			parts.append('add={%s}' % ','.join('{' + ','.join(q(x) if isinstance(x, str) else n(x) for x in s) + '}' for s in add[i]))
		w('[%d]={%s},' % (i, ','.join(parts)))
	w('}')
	w('-- NPC -> its record in ns.Npcs\' form, in place of ForeverRecipes\' and Polestar\'s: { name, faction')
	w('-- ("A", "H" or false for both), { zone, uiMapID, x, y } or { place } ... }.')
	w('ns.CorrectionNpcs = {')
	for i in sorted(npcs):
		nm, fac, locs = npcs[i]
		ls = ','.join('{' + ','.join(q(x) if isinstance(x, str) else n(x) for x in loc) + '}' for loc in locs)
		w('[%d]={%s,%s%s},' % (i, q(nm), q(fac) if fac else 'false', (',' + ls) if ls else ''))
	w('}')
	w('-- English names of what the sources name (the game\'s own are used where it has them).')
	w('ns.CorrectionNames = {')
	for key, t in (('quest', quests), ('object', objects), ('item', items)):
		w('%s = {' % key)
		for k in sorted(t):
			if t[k]:
				w('[%d]=%s,' % (k, q(t[k])))
		w('},')
	w('}')
	with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
		f.write('\n'.join(L) + '\n')


if __name__ == '__main__':
	main()
