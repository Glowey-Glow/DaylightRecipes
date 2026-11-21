"""Builds Data/Polestar.lua from Polestar's data (GPL-3.0): where the recipes come from that
ForeverRecipes' tables have no source for, the reputation a recipe item asks for, the NPCs and names
those need, and every profession's camping items. Run from the repo root with the AddOns folder:

	python Tools/polestar.py "D:/World of Warcraft/_forever_/Interface/AddOns"

Reads Polestar_Codex/*.lua (the facts, decoded the way Polestar/Lookup/Codex.lua does) and this
plugin's Data/Recipes.lua, Sources.lua and Npcs.lua, and Data/Client.lua's recipes (run
Tools/client.py first when the client or ForeverRecipes' tables changed). Facts only Polestar's QuestieDB source has
(provenance "q" alone) are left out: QuestieDB's maintainers ask that their data be treated as all
rights reserved. Pass --questie to keep them anyway.
"""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = next((a for a in sys.argv[1:] if not a.startswith('--')), r'D:\World of Warcraft\_forever_\Interface\AddOns')
KEEP_QUESTIE = '--questie' in sys.argv
CODEX = os.path.join(ADDONS, 'Polestar_Codex')
OUT = os.path.join(ROOT, 'Data', 'Polestar.lua')

GATHERING = (182, 393, 356)
MAX_DROPS, MAX_OBJECTS, MAX_SPAWNS = 10, 3, 8

# Tier one of the gathering professions' camping items: what each takes, from Polestar's own
# profession guides (Polestar_Guides, "Journeyman Herbalism / Skinning / Fishing" steps).
GUIDE_REAGENTS = {
	1229705: (2447, 1, 765, 1),     # Incense Candle: Peacebloom, Silverleaf
	1229517: (2318, 3, 4470, 2),    # Camp Chair: 3 Light Leather, 2 Simple Wood
	1229745: (6291, 1, 3371, 1),    # Fish Bowl: Raw Brilliant Smallfish in an Empty Vial
}
# Fishing's Expert and Artisan ranks: a book and a quest, not a trainer (Polestar's Fishing guide).
FISHING_RANK_NPCS = (2626, 12919)

# --------------------------------------------------------------------------------------------
# Lua tables of this plugin's own data (ns.X = { ... })
# --------------------------------------------------------------------------------------------

TOK = re.compile(r'\s*(?:(--[^\n]*)|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(true|false|nil)|([A-Za-z_]\w*)|(.))', re.S)


def tokens(s):
	pos, out = 0, []
	while pos < len(s):
		m = TOK.match(s, pos)
		if not m:
			break
		pos = m.end()
		if m.group(1) is not None:
			continue
		if m.group(2) is not None:
			out.append(('s', m.group(2)[1:-1]))
		elif m.group(3) is not None:
			v = m.group(3)
			out.append(('n', float(v) if any(c in v for c in '.eE') else int(v)))
		elif m.group(4) is not None:
			out.append(('k', {'true': True, 'false': False, 'nil': None}[m.group(4)]))
		elif m.group(5) is not None:
			out.append(('i', m.group(5)))
		elif m.group(6).strip():
			out.append(('p', m.group(6)))
		if out and out[-1] == ('p', '}') and depth(out) == 0:
			break
	return out


def depth(toks):
	d = 0
	for t in toks:
		if t == ('p', '{'): d += 1
		elif t == ('p', '}'): d -= 1
	return d


class Parser:
	def __init__(self, toks):
		self.t, self.i = toks, 0

	def take(self):
		self.i += 1
		return self.t[self.i - 1]

	def peek(self, k=0):
		return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

	def value(self):
		kind, v = self.take()
		if (kind, v) == ('p', '{'):
			return self.table()
		if (kind, v) == ('p', '-'):
			return -self.take()[1]
		return v

	def table(self):
		arr, d = [], {}
		while True:
			if self.peek() == ('p', '}'):
				self.take()
				break
			if self.peek() == ('p', '['):
				self.take()
				k = self.value()
				self.take()
				self.take()
				d[k] = self.value()
			elif self.peek()[0] == 'i' and self.peek(1) == ('p', '='):
				k = self.take()[1]
				self.take()
				d[k] = self.value()
			else:
				arr.append(self.value())
			if self.peek() in (('p', ','), ('p', ';')):
				self.take()
		if not d:
			return arr
		for i, a in enumerate(arr):
			d[i + 1] = a
		return d


def lua_tables(path, names):
	s = open(path, encoding='utf-8').read()
	out = {}
	for m in re.finditer(r'^ns\.(\w+)\s*=\s*\{', s, re.M):
		if m.group(1) not in names:
			continue
		p = Parser(tokens(s[m.end() - 1:]))
		p.take()
		out[m.group(1)] = p.table()
	return out


def as_list(v):
	if v is None:
		return []
	if isinstance(v, dict):
		return [v[k] for k in sorted(v)]
	return v


def with_client(data):
	"""Adds Data/Client.lua's recipes and trainers (Tools/client.py: the ones ForeverRecipes' tables
	lack) to the tables read from Data/Recipes.lua and Sources.lua, as the plugin does when it loads."""
	path = os.path.join(ROOT, 'Data', 'Client.lua')
	if not os.path.exists(path):
		return data
	extra = lua_tables(path, ('ClientRecipes', 'ClientTrainers'))
	for src, dst in (('ClientRecipes', 'Recipes'), ('ClientTrainers', 'Trainers')):
		rows = extra.get(src)
		if not isinstance(rows, dict):
			continue
		if not isinstance(data.get(dst), dict):
			data[dst] = {}
		for k, v in rows.items():
			data[dst].setdefault(k, v)
	return data

# --------------------------------------------------------------------------------------------
# Polestar's Codex
# --------------------------------------------------------------------------------------------

STR = re.compile(r'"((?:[^"\\]|\\.)*)"|(nil)|(-?\d+)')


def unlua(s):
	return re.sub(r'\\(n|t|\d{1,3}|.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1)) or (chr(int(m.group(1))) if m.group(1).isdigit() else m.group(1)), s)


def load_codex():
	groups = {}
	for f in sorted(glob.glob(os.path.join(CODEX, '*.lua'))):
		if os.path.basename(f) in ('Index.lua', 'Dungeons1.lua', 'Meta.lua'):
			continue
		text = open(f, encoding='utf-8').read()
		for m in re.finditer(r'C\.Register\("(\w+)",', text):
			pos, args = m.end(), []
			while True:
				while text[pos] in ' \t\n,':
					pos += 1
				if text[pos] == ')':
					break
				a = STR.match(text, pos)
				args.append(unlua(a.group(1)) if a.group(1) is not None else (None if a.group(2) else int(a.group(3))))
				pos = a.end()
			g = groups.setdefault(m.group(1), {'names': {}, 'recs': {}})
			for line in (args[0] or '').split('\n'):
				if line:
					p = line.split('\t', 2)
					g['names'][int(p[0]) if p[0].isdigit() else p[0]] = p[2] if len(p) > 2 else ''
			for line in ((args[1] if len(args) > 1 else None) or '').split('\n'):
				if line:
					p = line.split('\t', 1)
					g['recs'][int(p[0]) if p[0].isdigit() else p[0]] = p[1] if len(p) > 1 else ''
	return groups


SOURCE = {
	'v': ('vendor', ('npc', 'cost', 'limited')), 'd': ('drop', ('npc', 'chance', 'instance')),
	'o': ('object', ('object', 'chance')), 'q': ('quest', ('quest', 'choice')),
	'g': ('gift', ('npc', 'spell')), 'c': ('craft', ('spell', 'skillLine', 'skill')),
	'r': ('rep', ('faction', 'standing', 'npc')), 'p': ('pvp', ('rank', 'npc')),
	'n': ('container', ('item', 'chance')), 'w': ('world', ('minLevel', 'maxLevel')),
}


def num(v):
	if v in (None, ''):
		return None
	try:
		return int(v)
	except ValueError:
		try:
			return float(v)
		except ValueError:
			return v


def decode_item(s):
	t = s.split(';')
	m = re.match(r'^(\d*)(\w?)$', t[0])
	it = {'status': m.group(2) if m else '', 'spell': num(t[2]) if len(t) > 2 else None,
		'repFaction': num(t[3]) if len(t) > 3 else None, 'repStanding': num(t[4]) if len(t) > 4 else None,
		'reqSkill': num(t[5]) if len(t) > 5 else None, 'reqSkillRank': num(t[6]) if len(t) > 6 else None, 'sources': []}
	for f in t[7:]:
		d = SOURCE.get(f[:1])
		if not d:
			continue
		parts = f[1:].split(',')
		src = {'type': d[0], 'from': parts[len(d[1])] if len(parts) > len(d[1]) else ''}
		for i, k in enumerate(d[1]):
			if i < len(parts) and parts[i] != '':
				src[k] = parts[i] if k == 'instance' else num(parts[i])
		it['sources'].append(src)
	return it


def decode_npc(s):
	t = s.split(';')
	n = len(t)
	if n >= 8 and t[n - 1][:1] == 't':
		n -= 1
	if n >= 1 and t[n - 1][:1] == 'z':
		n -= 1
	spawns = []
	for i in range(7, n):
		g = t[i].split(',')
		if len(g) < 4 or not g[0].isdigit():
			continue
		for k in range(2, len(g) - 1, 2):
			spawns.append((int(g[0]), float(g[k]) / 10, float(g[k + 1]) / 10))
	return {'faction': t[2] if len(t) > 2 else '', 'instance': t[4] if len(t) > 4 and t[4] else None, 'spawns': spawns}


ITEM_GROUPS = ('recipe', 'item', 'mount', 'pet', 'tabard')

# --------------------------------------------------------------------------------------------
# Building
# --------------------------------------------------------------------------------------------


def main():
	cx = load_codex()

	def item(i):
		for g in ITEM_GROUPS:
			r = cx.get(g, {}).get('recs', {}).get(i)
			if r is not None:
				return decode_item(r)
		return None

	def name(group, i):
		return cx.get(group, {}).get('names', {}).get(i)

	def item_name(i):
		for g in ITEM_GROUPS:
			n = name(g, i)
			if n:
				return n
		return None

	def npc(i):
		for g in ('npc', 'rare'):
			r = cx.get(g, {}).get('recs', {}).get(i)
			if r is not None:
				return decode_npc(r), name(g, i)
		return None, None

	def kept(src):
		return KEEP_QUESTIE or src['from'].replace('q', '') != ''

	data = {}
	for f, names in (('Recipes.lua', ('Recipes',)), ('Npcs.lua', ('Npcs',)),
			('Sources.lua', ('Trainers', 'AutomaticRecipes', 'AutomaticQuests', 'Sellers', 'Drops', 'OtherDrops', 'QuestRewards'))):
		data.update(lua_tables(os.path.join(ROOT, 'Data', f), names))
	with_client(data)
	recipes, npcs = data['Recipes'], data['Npcs']

	# Recipe items by the spell they teach.
	teaches = {}
	for g in ('recipe', 'item'):
		for i, r in cx[g]['recs'].items():
			it = decode_item(r)
			if it['spell'] and it['spell'] not in teaches:
				teaches[it['spell']] = i

	def any_source(spell, teach):
		if as_list(data['Trainers'].get(spell)) or data['AutomaticRecipes'].get(spell):
			return True
		if isinstance(data['AutomaticQuests'], dict) and data['AutomaticQuests'].get(spell):
			return True
		for t in ('Sellers', 'Drops', 'OtherDrops', 'QuestRewards'):
			if teach and isinstance(data[t], dict) and as_list(data[t].get(teach)):
				return True
		return False

	# Camping items: every craft of the 2799xx range (each profession's camp features).
	camping = []
	for i in sorted(cx['item']['recs']):
		if not (279900 <= i <= 280000):
			continue
		for s in decode_item(cx['item']['recs'][i])['sources']:
			if s['type'] == 'craft' and s.get('skillLine'):
				camping.append({'spell': s['spell'], 'line': s['skillLine'], 'skill': s.get('skill') or 0, 'item': i,
					'teach': teaches.get(s['spell'])})
	camping.sort(key=lambda c: (c['line'], c['skill'], c['spell']))

	teach_extra = {}     # spell -> recipe item, for the data's recipes with none
	targets = set()      # recipe items whose sources are written
	rep_items = set()
	for spell, d in recipes.items():
		d = as_list(d)
		teach = d[4] if len(d) > 4 and d[4] else None
		if not teach and spell in teaches:
			teach = teaches[spell]
			teach_extra[spell] = teach
		if teach:
			rep_items.add(teach)
		if not any_source(spell, teach) and teach:
			targets.add(teach)
	for c in camping:
		if c['teach']:
			rep_items.add(c['teach'])
			if c['spell'] not in recipes:
				targets.add(c['teach'])

	rep = {}
	for i in sorted(rep_items):
		it = item(i)
		if it and it['repFaction'] and it['repStanding']:
			rep[i] = (it['repFaction'], it['repStanding'])

	# A faction's vendors: the NPC a reputation source names, or who sells an item of that faction.
	faction_vendors = {}
	for g in ITEM_GROUPS:
		for i, r in cx[g]['recs'].items():
			it = decode_item(r)
			for s in it['sources']:
				if not kept(s):
					continue
				f, who = None, None
				if s['type'] == 'rep' and s.get('npc'):
					f, who = s['faction'], s['npc']
				elif s['type'] == 'vendor' and it['repFaction']:
					f, who = it['repFaction'], s['npc']
				if f and who:
					faction_vendors.setdefault(f, {}).setdefault(who, 0)
					faction_vendors[f][who] += 1

	need_npcs, quests, objects, items, instances, factions = set(), {}, {}, {}, {}, {}
	sources = {}
	for i in sorted(targets):
		it = item(i)
		if not it:
			continue
		out, drops, objs = [], [], []
		for s in it['sources']:
			if s['type'] == 'craft' or not kept(s):
				continue
			t = s['type']
			if t == 'vendor' and s.get('npc'):
				out.append(('v', s['npc'], s.get('cost') or 0))
				need_npcs.add(s['npc'])
			elif t == 'drop' and s.get('npc'):
				drops.append(s)
			elif t == 'object' and s.get('object'):
				objs.append(s)
			elif t == 'quest' and s.get('quest'):
				out.append(('q', s['quest']))
				quests[s['quest']] = name('quest', s['quest'])
			elif t == 'gift' and s.get('npc'):
				out.append(('g', s['npc']))
				need_npcs.add(s['npc'])
			elif t == 'container' and s.get('item'):
				out.append(('n', s['item'], s.get('chance') or 0))
				items[s['item']] = item_name(s['item'])
			elif t == 'world':
				out.append(('w', s.get('minLevel') or 0, s.get('maxLevel') or 0))
			elif t == 'rep' and s.get('faction'):
				out.append(('r', s['faction'], s.get('standing') or 0, s.get('npc') or 0))
				factions[s['faction']] = name('faction', s['faction'])
				if s.get('npc'):
					need_npcs.add(s['npc'])
		drops.sort(key=lambda s: -(s.get('chance') or 0))
		for s in drops[:MAX_DROPS]:
			out.append(('d', s['npc'], s.get('chance') or 0, s.get('instance') or ''))
			need_npcs.add(s['npc'])
			if s.get('instance'):
				instances[s['instance']] = name('instance', s['instance'])
		objs.sort(key=lambda s: -(s.get('chance') or 0))
		for s in objs[:MAX_OBJECTS]:
			out.append(('o', s['object'], s.get('chance') or 0))
			objects[s['object']] = name('object', s['object']) or name('treasure', s['object'])
		if out:
			sources[i] = out

	for f, _ in rep.values():
		factions[f] = name('faction', f)
	# Vendors of the factions a recipe asks for, most items first.
	fv = {}
	for f in sorted(set(f for f, _ in rep.values())):
		who = sorted(faction_vendors.get(f, {}).items(), key=lambda kv: (-kv[1], kv[0]))
		if who:
			fv[f] = [w for w, _ in who[:4]]
			need_npcs.update(fv[f])

	# The gathering professions' trainers (tier one of their camping items is taught there).
	camp_trainers = {}
	for line in GATHERING:
		ids = [int(x) for x in (name('role', 'trainer:%d' % line) or '').split(',') if x]
		camp_trainers[line] = ids
		need_npcs.update(ids)
	need_npcs.update(FISHING_RANK_NPCS)
	quests[6607] = name('quest', 6607)

	def located(n):
		for loc in as_list(n)[2:]:
			loc = as_list(loc)
			if len(loc) >= 4 and loc[1]:
				return True
		return False

	extra_npcs = {}
	for i in sorted(need_npcs):
		if i in npcs and located(npcs[i]):
			continue
		rec, nm = npc(i)
		if not rec:
			continue
		fac = rec['faction'] if rec['faction'] in ('A', 'H') else False
		locs, seen = [], set()
		for mp, x, y in rec['spawns']:
			if mp in seen or len(locs) >= MAX_SPAWNS:
				continue
			seen.add(mp)
			locs.append((name('zone', mp) or '', mp, round(x, 1), round(y, 1)))
		if not locs and rec['instance']:
			instances[rec['instance']] = name('instance', rec['instance'])
			locs.append((name('instance', rec['instance']) or '',))
		extra_npcs[i] = (nm or '', fac, locs)

	write(teach_extra, rep, sources, extra_npcs, quests, objects, items, instances, factions, fv, camp_trainers, camping)
	print('teach', len(teach_extra), 'rep', len(rep), 'sources', len(sources), 'npcs', len(extra_npcs), 'camping', len(camping))


def q(s):
	return '"' + (s or '').replace('\\', '\\\\').replace('"', '\\"') + '"'


def n(v):
	if isinstance(v, float):
		return ('%.2f' % v).rstrip('0').rstrip('.')
	return str(v)


def write(teach, rep, sources, npcs, quests, objects, items, instances, factions, fv, trainers, camping):
	meta = open(os.path.join(CODEX, 'Meta.lua'), encoding='utf-8').read()
	built = re.search(r'builtAt = "([^"]+)"', meta)
	toc = open(os.path.join(ADDONS, 'Polestar', 'Polestar.toc'), encoding='utf-8').read()
	version = re.search(r'## Version: (\S+)', toc)
	L = []
	w = L.append
	w('-- Generated by Tools/polestar.py from Polestar %s (Polestar_Codex built %s); do not edit.' % (
		version.group(1) if version else '?', built.group(1) if built else '?'))
	w('-- Facts from Polestar (https://github.com/fitzforge/polestar), GPL-3.0, by the Polestar authors:')
	w('-- see LICENSE.md. Polestar_Codex\'s own sources are listed in its LICENSE-DATA.txt. Facts only')
	w('-- QuestieDB gave Polestar are %s.' % ('kept (--questie)' if KEEP_QUESTIE else 'left out'))
	w('local _, ns = ...')
	w('')
	w('-- Recipe spell -> the item that teaches it, for recipes ForeverRecipes names no item for.')
	w('ns.PolestarTeach = {')
	for s in sorted(teach):
		w('[%d]=%d,' % (s, teach[s]))
	w('}')
	w('-- Recipe item -> { faction, standing (1 Hated .. 8 Exalted) } it asks for.')
	w('ns.PolestarRep = {')
	for i in sorted(rep):
		w('[%d]={%d,%d},' % (i, rep[i][0], rep[i][1]))
	w('}')
	w('-- Recipe item -> where it comes from, for recipes ForeverRecipes has no source for:')
	w('-- {"v",npc,cost} vendor, {"d",npc,chance,instance} drop, {"o",object,chance}, {"q",quest},')
	w('-- {"g",npc} given, {"n",item,chance} in a container, {"w",minLevel,maxLevel} world drop,')
	w('-- {"r",faction,standing,npc} reputation.')
	w('ns.PolestarSources = {')
	for i in sorted(sources):
		parts = []
		for s in sources[i]:
			parts.append('{' + ','.join(q(x) if isinstance(x, str) else n(x) for x in s) + '}')
		w('[%d]={%s},' % (i, ','.join(parts)))
	w('}')
	w('-- NPCs the tables above name that ForeverRecipes\' ns.Npcs lacks (or has no map spot for), in')
	w('-- its form: { name, faction ("A", "H" or false for both), { zone, uiMapID, x, y } or { place } ... }.')
	w('ns.PolestarNpcs = {')
	for i in sorted(npcs):
		nm, fac, locs = npcs[i]
		ls = ','.join('{' + ','.join(q(x) if isinstance(x, str) else n(x) for x in loc) + '}' for loc in locs)
		w('[%d]={%s,%s%s},' % (i, q(nm), q(fac) if fac else 'false', (',' + ls) if ls else ''))
	w('}')
	w('-- English names of what the sources name (the game\'s own are used where it has them).')
	w('ns.PolestarNames = {')
	for key, table in (('quest', quests), ('object', objects), ('item', items), ('faction', factions)):
		w('%s = {' % key)
		for k in sorted(table):
			if table[k]:
				w('[%d]=%s,' % (k, q(table[k])))
		w('},')
	w('instance = {')
	for k in sorted(instances):
		if instances[k]:
			w('[%s]=%s,' % (q(k), q(instances[k])))
	w('},')
	w('}')
	w('-- Faction -> its vendors (who sells its reputation items), most items first.')
	w('ns.FactionVendors = {')
	for f in sorted(fv):
		w('[%d]={%s},' % (f, ','.join(str(x) for x in fv[f])))
	w('}')
	w('-- Herbalism, Skinning and Fishing: their trainers (who teach tier one of their camping items).')
	w('ns.CampTrainers = {')
	for line in sorted(trainers):
		w('[%d]={%s},' % (line, ','.join(str(x) for x in trainers[line])))
	w('}')
	w('-- Every profession\'s camping items: { spell, skill line, skill, item made, blueprint item or false }.')
	w('ns.Camping = {')
	for c in camping:
		w('{%d,%d,%d,%d,%s},' % (c['spell'], c['line'], c['skill'], c['item'], c['teach'] or 'false'))
	w('}')
	w('-- What a camping item takes, where ForeverRecipes has no recipe for it (Polestar\'s guides).')
	w('ns.CampReagents = {')
	for s in sorted(GUIDE_REAGENTS):
		w('[%d]={%s},' % (s, ','.join(str(x) for x in GUIDE_REAGENTS[s])))
	w('}')
	with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
		f.write('\n'.join(L) + '\n')


if __name__ == '__main__':
	main()
