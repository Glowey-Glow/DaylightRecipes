"""Builds Data/Client.lua: what ForeverRecipes' tables leave out or have otherwise than the game.

ForeverRecipes' export (Data/Recipes.lua) drops every recipe whose gray skill is past 300, though
many of those are learned and made well before 300 (Runecloth Bandage: learned at 260, yellow at
260, gray at 320), and it widens recipes whose yellow and gray skill are the same (20/20 becomes
20/22/25). This script puts both right from the game's own tables, without touching the files
ForeverRecipes ships:

  ns.ClientRanges   recipe -> { yellow, gray } where Data/Recipes.lua differs from the client
  ns.ClientRecipes  the recipes it lacks, in its own form (merged into ns.Recipes when loaded),
  ns.ClientMeta     with their meta, English names and the names of their items, and trainers
  ns.ClientNames    where known.
  ...

Run from the repo root:

	python Tools/client.py --db2 <folder> --foreverdb <folder> [--fetch] [--report FILE]
	python Tools/polestar.py "<AddOns folder>"      (afterwards: sources for the new recipe items)

Where each field comes from:
  yellow, gray      the client's SkillLineAbility table (TrivialSkillLineRankLow / High); green is
                    halfway, as the game has it and as every row of Data/Recipes.lua does.
  materials         the client's SpellReagents.
  what it makes     the client's SpellEffect (effect 24, create item) and how many.
  the recipe item   the client's ItemEffect / ItemXItemEffect (the item that teaches the spell).
  names             the client's SpellName and ItemSparse (English; the game's own are shown).
  learn skill       ForeverDB.app's profession pages (learnRank), which is where ForeverRecipes'
                    own tables come from; for a recipe taught by an item it is checked against the
                    item's RequiredSkillRank in the client's ItemSparse.
  trainers          ForeverDB.app (trainerNpcIds), only NPCs the data already places.
  which belong      a recipe is added when the client has it on one of our profession lines with a
                    gray skill, a name and materials, ForeverDB.app lists it, it can be learned
                    at 300 or below, and everything it takes and makes is an item the client has.
                    The client's other rows (unused and unreleased ones, which
                    ForeverDB.app leaves out too) and recipes learned past 300 are not.

--db2: the client tables as CSV (wago.tools, https://wago.tools/db2/<Table>/csv?build=<build>):
SkillLineAbility, SpellName, SpellReagents, SpellEffect, ItemSparse, ItemEffect, ItemXItemEffect.
--foreverdb: the saved pages https://www.foreverdb.app/en/forever/professions/<slug> as <slug>.html.
--fetch downloads whatever of either is missing (BUILD below).
"""
import csv, json, os, re, sys, collections, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Data', 'Client.lua')
BUILD = '1.60.1.71037'
TABLES = ('SkillLineAbility', 'SpellName', 'SpellReagents', 'SpellEffect', 'ItemSparse', 'ItemEffect', 'ItemXItemEffect')
SLUGS = {'alchemy': 171, 'blacksmithing': 164, 'cooking': 185, 'enchanting': 333, 'engineering': 202, 'first-aid': 129,
	'leatherworking': 165, 'mining': 186, 'tailoring': 197}
LINES = {164: 'Blacksmithing', 165: 'Leatherworking', 171: 'Alchemy', 185: 'Cooking', 186: 'Mining', 197: 'Tailoring',
	202: 'Engineering', 333: 'Enchanting', 129: 'First Aid', 40: 'Poisons'}
TOP = 300
CREATE_ITEM = 24

# Taught by a trainer, but nobody has reported which one (ForeverDB.app names none): planned as
# "learn it first" without a place or a price. Only recipes confirmed to be in the game.
TRAINER_UNKNOWN = {
	18629: 'Runecloth Bandage: confirmed in the game by the plugin\'s author, 2026-11-20',
	18630: 'Heavy Runecloth Bandage: confirmed in the game by the plugin\'s author, 2026-11-20',
}


def arg(name):
	return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def fetch(url, path):
	req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
	with urllib.request.urlopen(req, timeout=120) as r:
		data = r.read()
	with open(path, 'wb') as f:
		f.write(data)
	print('fetched', os.path.basename(path), len(data))


def table(folder, name):
	csv.field_size_limit(10 ** 9)
	with open(os.path.join(folder, name + '.csv'), encoding='utf-8') as f:
		return list(csv.DictReader(f))


# --------------------------------------------------------------------------------------------
# ForeverDB.app's profession pages: the recipe objects in the page's data
# --------------------------------------------------------------------------------------------

def page_recipes(path):
	html = open(path, encoding='utf-8').read()
	bs = chr(92)
	chunks = []
	for m in re.finditer(r'self\.__next_f\.push\(\[1,("(?:[^"' + bs + bs + r']|' + bs + bs + r'.)*")\]\)', html):
		try:
			chunks.append(json.loads(m.group(1)))
		except ValueError:
			pass
	text = ''.join(chunks)
	out, i, dec = {}, 0, json.JSONDecoder()
	while True:
		i = text.find('{"skillLineAbilityId":', i)
		if i < 0:
			break
		try:
			obj, i = dec.raw_decode(text, i)
			out[obj['spellId']] = obj
		except ValueError:
			i += 1
	return out


# --------------------------------------------------------------------------------------------
# This plugin's own tables
# --------------------------------------------------------------------------------------------

def own():
	s = open(os.path.join(ROOT, 'Data', 'Recipes.lua'), encoding='utf-8').read()
	rec = s[s.index('ns.Recipes = {'):s.index('ns.RecipeMeta')]
	recipes = {}
	for m in re.finditer(r'^\[(\d+)\]=\{(\d+),\{(\d+),(\d+),(\d+),(\d+)\}', rec, re.M):
		recipes[int(m.group(1))] = (int(m.group(2)),) + tuple(int(m.group(i)) for i in range(3, 7))
	names = s[s.index('ns.ItemNames = {'):]
	items = set(int(x) for x in re.findall(r'^\[(\d+)\]=', names, re.M))
	header = re.search(r'-- Build ([\d.]+); snapshot ([\d-]+)', s)
	n = open(os.path.join(ROOT, 'Data', 'Npcs.lua'), encoding='utf-8').read()
	npcs = set(int(x) for x in re.findall(r'^\[(\d+)\]=\{"', n[n.index('ns.Npcs = {'):n.index('ns.Quests')], re.M))
	return recipes, items, npcs, header


def q(s):
	return '"' + (s or '').replace('\\', '\\\\').replace('"', '\\"') + '"'


def num(v):
	return ('%.1f' % v) if isinstance(v, float) else str(v)


def main():
	db2, pages = arg('--db2'), arg('--foreverdb')
	if not db2 or not pages:
		sys.exit(__doc__)
	if '--fetch' in sys.argv:
		os.makedirs(db2, exist_ok=True)
		os.makedirs(pages, exist_ok=True)
		for t in TABLES:
			p = os.path.join(db2, t + '.csv')
			if not os.path.exists(p):
				fetch('https://wago.tools/db2/%s/csv?build=%s' % (t, BUILD), p)
		for slug in SLUGS:
			p = os.path.join(pages, slug + '.html')
			if not os.path.exists(p):
				fetch('https://www.foreverdb.app/en/forever/professions/' + slug, p)

	recipes, item_names, npcs, header = own()

	# The client.
	sla = collections.defaultdict(list)
	for r in table(db2, 'SkillLineAbility'):
		line = int(r['SkillLine'])
		if line in LINES:
			sla[int(r['Spell'])].append((line, int(r['TrivialSkillLineRankLow']), int(r['TrivialSkillLineRankHigh'])))
	spell_name = {int(r['ID']): r['Name_lang'] for r in table(db2, 'SpellName')}
	reagents = {}
	for r in table(db2, 'SpellReagents'):
		reagents[int(r['SpellID'])] = [(int(r['Reagent_%d' % i]), int(r['ReagentCount_%d' % i])) for i in range(8)
			if int(r['Reagent_%d' % i]) > 0 and int(r['ReagentCount_%d' % i]) > 0]
	made = {}
	for r in table(db2, 'SpellEffect'):
		if int(r['Effect']) == CREATE_ITEM and int(r['EffectItemType']) > 0:
			made.setdefault(int(r['SpellID']), (int(r['EffectItemType']), float(r['EffectBasePointsF'])))
	item = {}
	for r in table(db2, 'ItemSparse'):
		item[int(r['ID'])] = (r['Display_lang'], int(r['RequiredSkill']), int(r['RequiredSkillRank']))
	# (Trigger 6: the item teaches the spell. An item that only casts it when used is no recipe.)
	effect = {int(r['ID']): int(r['SpellID']) for r in table(db2, 'ItemEffect') if int(r['TriggerType']) == 6}
	teaches = collections.defaultdict(list)
	for r in table(db2, 'ItemXItemEffect'):
		spell = effect.get(int(r['ItemEffectID']))
		if spell and int(r['ItemID']) in item:
			teaches[spell].append(int(r['ItemID']))

	# ForeverDB.app.
	site = {}
	for slug, line in SLUGS.items():
		for spell, rec in page_recipes(os.path.join(pages, slug + '.html')).items():
			site[spell] = dict(rec, line=line)

	# 1. Yellow and gray where Data/Recipes.lua has them otherwise than the client.
	ranges = {}
	for spell, (line, _, yellow, _, gray) in sorted(recipes.items()):
		rows = [x for x in sla.get(spell, []) if x[0] == line]
		if rows and gray > 0 and (rows[0][1], rows[0][2]) != (yellow, gray):
			ranges[spell] = (rows[0][1], rows[0][2])

	# 2. The client's recipes Data/Recipes.lua lacks, sorted into what they are.
	why = collections.defaultdict(list)
	added = {}
	for spell, rows in sorted(sla.items()):
		for line, yellow, gray in rows:
			if spell in recipes or spell in added or gray <= 0:
				continue
			name = spell_name.get(spell)
			mats = reagents.get(spell, [])
			s = site.get(spell)
			if not name:
				why['no name in the client (a placeholder)'].append(spell)
			elif not mats:
				why['no materials in the client (not a craft)'].append(spell)
			elif not s or s['line'] != line:
				why['not listed by ForeverDB.app (unused or unreleased)'].append(spell)
			elif (s.get('learnRank') or 0) > TOP:
				why['learned past 300'].append(spell)
			elif any(m[0] not in item or not item[m[0]][0] for m in mats) or (spell in made and made[spell][0] not in item):
				why['a material or product is no item in the client (unfinished)'].append(spell)
			elif (s['trivialRankLow'], s['trivialRankHigh']) != (yellow, gray):
				why['ForeverDB.app and the client disagree on its range'].append(spell)
			else:
				added[spell] = (line, yellow, gray, s)

	rows_out, meta_out, names_out, items_out, trainers_out = [], [], [], {}, []
	kinds = collections.Counter()
	per_line = collections.Counter()
	notes = []
	for spell, (line, yellow, gray, s) in sorted(added.items()):
		learn = s.get('learnRank') or 0
		mats = reagents[spell]
		out = made.get(spell)
		teach = None
		candidates = sorted(teaches.get(spell, []))
		if s.get('sourceItemId') in candidates:
			teach = s['sourceItemId']
		elif candidates:
			teach = candidates[0]
		if teach and item[teach][2] and item[teach][2] != learn:
			notes.append('%d %s: ForeverDB.app says learned at %d, its recipe item asks %d' % (spell, spell_name[spell], learn, item[teach][2]))
		count = 1.0
		if out:
			lo, hi = s.get('numMadeMin'), s.get('numMadeMax')
			count = (lo + hi) / 2.0 if lo and hi else max(1.0, out[1])
		green = (yellow + gray) // 2
		rows_out.append('[%d]={%d,{%d,%d,%d,%d},{%s},%s,%s,0},' % (spell, line, learn, yellow, green, gray,
			','.join('%d,%d' % m for m in mats), ('{%d,%s}' % (out[0], num(count))) if out else 'false', teach or 'false'))
		meta = ['["requirementKnown"]=%s' % ('true' if learn > 0 else 'false'), '["thresholdsKnown"]=true']
		usable = [n for n in (s.get('trainerNpcIds') or []) if n in npcs]
		if (s.get('cooldownMs') or 0) > 0:
			meta.append('["cooldown"]=%d' % (s['cooldownMs'] // 1000))
		if usable:
			kind = 'taught by a trainer the data places'
			cost = s.get('learnCost') or 0
			trainers_out.append('[%d]={%s},' % (spell, ','.join('{%d,%d,%d}' % (n, cost, learn) for n in usable)))
		elif teach:
			kind = 'taught by a recipe item'
		elif spell in TRAINER_UNKNOWN:
			kind = 'taught by a trainer nobody has reported yet (confirmed in the game)'
			meta.append('["trainerUnknown"]=true')
		else:
			kind = 'no way to learn it found (planned only for a character who knows it)'
			meta.append('["knownOnly"]=true')
		kinds[kind] += 1
		per_line[(LINES[line], 'learned below 300' if learn < TOP else 'learned at 300')] += 1
		meta_out.append('[%d]={%s},' % (spell, ','.join(meta)))
		names_out.append('[%d]=%s,' % (spell, q(spell_name[spell])))
		for i in [m[0] for m in mats] + ([out[0]] if out else []) + ([teach] if teach else []):
			if i not in item_names and i in item and item[i][0]:
				items_out[i] = item[i][0]

	L = []
	w = L.append
	w('-- Generated by Tools/client.py; do not edit.')
	w('-- What ForeverRecipes\' tables leave out (recipes whose gray skill is past 300) or have otherwise')
	w('-- than the game (yellow and gray skill). Thresholds, materials, products, recipe items and names')
	w('-- from the game client\'s own tables, build %s (SkillLineAbility, SpellReagents, SpellEffect,' % BUILD)
	w('-- ItemEffect, SpellName, ItemSparse; read through wago.tools). Learn skill and trainers from')
	w('-- ForeverDB.app (https://foreverdb.app/), which ForeverRecipes\' tables are built from.')
	w('-- Game data and assets retain their respective rights.')
	w('local _, ns = ...')
	w('')
	w('-- Recipe -> { yellow, gray } as the client has them, where Data/Recipes.lua differs.')
	w('ns.ClientRanges = {')
	for spell in sorted(ranges):
		w('[%d]={%d,%d},' % (spell, ranges[spell][0], ranges[spell][1]))
	w('}')
	w('-- The recipes Data/Recipes.lua lacks, in its form: { line, { orange, yellow, green, gray },')
	w('-- { item, count, ... }, { made item, count } or false, recipe item or false, 0 }.')
	w('ns.ClientRecipes = {')
	L.extend(rows_out)
	w('}')
	w('-- Their meta, as ns.RecipeMeta\'s. cooldown: seconds between crafts. trainerUnknown: taught by a')
	w('-- trainer nobody has reported yet. knownOnly: no way to learn it is known (not listed as missing).')
	w('ns.ClientMeta = {')
	L.extend(meta_out)
	w('}')
	w('ns.ClientNames = {')
	L.extend(names_out)
	w('}')
	w('ns.ClientItemNames = {')
	for i in sorted(items_out):
		w('[%d]=%s,' % (i, q(items_out[i])))
	w('}')
	w('-- Recipe -> { { npc, copper, skill }, ... }, as ns.Trainers.')
	w('ns.ClientTrainers = {')
	L.extend(trainers_out)
	w('}')
	w('')
	w('-- Into ForeverRecipes\' own tables (a row of theirs always wins), so everything reads one set.')
	w('for _, pair in ipairs({ { "ClientRecipes", "Recipes" }, { "ClientMeta", "RecipeMeta" }, { "ClientNames", "RecipeNames" },')
	w('\t\t{ "ClientItemNames", "ItemNames" }, { "ClientTrainers", "Trainers" } }) do')
	w('\tlocal from, into = ns[pair[1]], ns[pair[2]]')
	w('\tif type(into) == "table" then')
	w('\t\tfor id, row in pairs(from) do')
	w('\t\t\tif into[id] == nil then into[id] = row end')
	w('\t\tend')
	w('\tend')
	w('\tns[pair[1]] = nil')
	w('end')
	with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
		f.write('\n'.join(L) + '\n')

	R = []
	r = R.append
	r('Data/Recipes.lua: %d recipes (ForeverRecipes, build %s). Client build %s.' % (len(recipes), header.group(1) if header else '?', BUILD))
	r('Yellow/gray set right from the client: %d' % len(ranges))
	r('Client recipes on our lines that Data/Recipes.lua lacks: %d' % (len(added) + sum(len(v) for v in why.values())))
	r('  added: %d' % len(added))
	for k, v in sorted(kinds.items()):
		r('    %-75s %d' % (k, v))
	for k, v in sorted(why.items()):
		r('  left out, %-66s %d' % (k, len(v)))
	r('Added, by profession:')
	for k in sorted(per_line):
		r('  %-16s %-20s %d' % (k[0], k[1], per_line[k]))
	r('Item names added: %d' % len(items_out))
	r('Notes: %d' % len(notes))
	R.extend('  ' + n for n in notes)
	r('')
	for k, v in sorted(why.items()):
		r('== left out, ' + k)
		for spell in v:
			rows = sla[spell]
			r('  %d %s (%s, yellow %d, gray %d)' % (spell, spell_name.get(spell) or '?', LINES[rows[0][0]], rows[0][1], rows[0][2]))
	r('== added')
	for spell, (line, yellow, gray, s) in sorted(added.items(), key=lambda kv: (kv[1][0], kv[1][3].get('learnRank') or 0, kv[0])):
		r('  %d %s (%s, learned %d, yellow %d, gray %d, %s)' % (spell, spell_name[spell], LINES[line], s.get('learnRank') or 0, yellow, gray, s.get('source')))
	text = '\n'.join(R)
	rep = arg('--report')
	if rep:
		with open(rep, 'w', encoding='utf-8') as f:
			f.write(text + '\n')
	print('\n'.join(R[:R.index('')]))
	print('wrote', OUT, os.path.getsize(OUT), 'bytes')


if __name__ == '__main__':
	main()
