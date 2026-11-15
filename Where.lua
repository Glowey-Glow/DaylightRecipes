-- Missing recipes: the open profession's recipes this character doesn't know, from the data,
-- and for each one where it comes from (trainers, vendors, drops, quests) with the place on the
-- map. Only your faction's people and places are listed; a recipe only the other faction can get
-- is left out.
local _, ns = ...
if not ns.ok then return end
local L = ns.L

local Where = {}
ns.Where = Where

local known       -- recipe -> true, this character's, for the open profession (read once per list)
local knownCount = 0
local stale = false       -- a recipe may have been learned: read the known ones again before use
local baseKey, base       -- the open profession's missing recipes (skill-independent), and their key
local sources = {}        -- recipe -> its source groups (static data: made once per window opening)

-- A new profession opened (or settings changed): everything is read again.
function Where.ForgetKnown()
	known, knownCount, stale = nil, 0, false
	baseKey, base = nil, nil
	wipe(sources)
end

-- A recipe may have been learned (the game says so, or the skill line changed). Only then are the
-- known recipes read again: the game's list also updates on every bag change and craft, which
-- never changes what you know.
function Where.MarkStale()
	stale = true
end

local function SpellKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
		if ok then return yes end
	end
	return IsSpellKnown and IsSpellKnown(id) or false
end

local function ReadKnown()
	local set, count = {}, 0
	local ids = ns.Ask("GetAllRecipeIDs")
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		local info = ns.Ask("GetRecipeInfo", id)
		if type(info) == "table" and info.learned then
			set[id] = true
			count = count + 1
		end
	end
	-- Your own recipes (not a linked list), kept for the plan, tooltips and your alts.
	local S = ns.state
	if count > 0 and S.line and not S.linked and ns.Store then ns.Store.SaveKnown(S.line, set) end
	return set, count
end

-- The known recipes now (read if they haven't been since the window opened).
function Where.KnownSet()
	if stale and known then Where.Refresh() end
	if not known then
		known, knownCount = ReadKnown()
		stale = false
	end
	return known
end

-- Reads the known recipes again if the game's list may have changed. True when they did (a recipe
-- learned or unlearned): then the missing list is made again.
function Where.Refresh()
	if not stale then return false end
	stale = false
	if not known then return false end
	local set, count = ReadKnown()
	local changed = count ~= knownCount
	if not changed then
		for id in pairs(set) do
			if not known[id] then changed = true break end
		end
	end
	known, knownCount = set, count
	if changed then baseKey, base = nil, nil end
	return changed
end

local function Known()
	if stale and known then Where.Refresh() end
	if known then return known end
	known, knownCount = ReadKnown()
	stale = false
	return known
end

-- Whether you know a spell (a recipe away from its profession window: a camping item's).
function Where.SpellKnown(spell)
	if IsPlayerSpell then
		local ok, yes = pcall(IsPlayerSpell, spell)
		if ok and yes then return true end
	end
	return SpellKnown(spell) == true
end

function Where.Knows(spell)
	return Known()[spell] or SpellKnown(spell)
end

-- The skill a recipe can be learned at, or nil when the data doesn't say. A trainer's own
-- requirement wins (the lowest any trainer asks): it differs from the orange threshold for a few
-- hundred recipes. Otherwise the orange threshold, unless the data marks it unknown (or 0).
local required = {}      -- spell -> its learn skill (false: none known); the data never changes
local Required
function Where.Required(spell)
	local v = required[spell]
	if v == nil then
		v = Required(spell) or false
		required[spell] = v
	end
	return v or nil
end

function Required(spell)
	local data = ns.Recipes[spell]
	if not data then return nil end
	local trainers = ns.Trainers and ns.Trainers[spell]
	local best
	if type(trainers) == "table" then
		for _, rec in ipairs(trainers) do
			local req = type(rec) == "table" and rec[3]
			-- (Only trainers you can use: the other faction's may teach it earlier.)
			if type(req) == "number" and (not best or req < best) and Where.Npc(rec[1]) then best = req end
		end
	end
	if best then return best end
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if meta and (meta.levelRequired or meta.requirementKnown == false) then return nil end
	local t = data[2]
	local orange = type(t) == "table" and t[1] or nil
	if type(orange) == "number" and orange > 0 then return orange end
	return nil
end

-- A character level the recipe asks for, if any.
function Where.Level(spell)
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	return meta and (meta.levelRequired or meta.minCharacterLevel) or nil
end

-- ---------------------------------------------------------------------------------------------
-- Nearest first. Places are ranked by map, never by world coordinates: 0 = the zone you're in (then
-- by distance on that map), 1 = your continent, 2 = elsewhere. Read once per list.
-- ---------------------------------------------------------------------------------------------

local continentOf = {}    -- uiMapID -> its continent's uiMapID (false: none), memoized
local function Continent(mapID)
	if not mapID then return nil end
	local c = continentOf[mapID]
	if c ~= nil then return c or nil end
	c = false
	local id, guard = mapID, 0
	while id and guard < 10 and C_Map and C_Map.GetMapInfo do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		if Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Continent then c = id break end
		id, guard = info.parentMapID, guard + 1
	end
	continentOf[mapID] = c
	return c or nil
end

local here = {}           -- the player's map, continent and position on that map
local function ReadHere()
	wipe(here)
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not map then return end
	here.map, here.continent = map, Continent(map)
	local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
	if pos then here.x, here.y = pos:GetXY() end
end

-- Lower is nearer: rank, then distance on your map.
local function Near(place)
	if not place or not place.mapID then return 3, 0 end
	if place.mapID == here.map then
		if here.x and type(place.x) == "number" then
			local dx, dy = place.x / 100 - here.x, place.y / 100 - here.y
			return 0, dx * dx + dy * dy
		end
		return 0, 0
	end
	if here.continent and Continent(place.mapID) == here.continent then return 1, 0 end
	return 2, 0
end

-- A zone's name in the client's language, from its map (the data's English name when the game has
-- no map by that ID). Memoized: an NPC list asks it for every spawn.
local zoneName = {}       -- uiMapID -> its name (false: the game has none)
local function ZoneName(mapID, english)
	local v = zoneName[mapID]
	if v == nil then
		v = false
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then v = info.name end
		zoneName[mapID] = v
	end
	return v or english
end

-- Of an NPC record's spawns ({ name, faction, { zone, uiMapID, x, y } or { place }, ... }), the
-- nearest one with a spot on the map, else a place without one.
local function NearestPlace(npc)
	local best, bestRank, bestDist, zoneOnly
	for i = 3, #npc do
		local l = npc[i]
		if type(l) == "table" then
			if l[2] then
				local place = { zone = ZoneName(l[2], l[1]), mapID = l[2], x = l[3], y = l[4] }
				local rank, dist = Near(place)
				if not best or rank < bestRank or (rank == bestRank and dist < bestDist) then
					best, bestRank, bestDist = place, rank, dist
				end
			elseif l[1] and l[1] ~= "" then
				zoneOnly = zoneOnly or { zone = l[1] }
			end
		end
	end
	return best, zoneOnly
end

-- name, place ({ zone, mapID, x, y } or { zone }) of one of the data's NPCs, nil when it's the
-- other faction's. Of an NPC's spawns, the nearest one with a spot on the map. ForeverRecipes'
-- NPCs first, Polestar's for the ones it lacks or has no spot for. NPC names stay the data's
-- (English): the game only knows an NPC's name once you've seen it.
function Where.Npc(id)
	local npc = ns.Npcs and ns.Npcs[id]
	local other = ns.PolestarNpcs and ns.PolestarNpcs[id]
	if not npc and not other then return nil end
	local mine = ns.Faction()
	if npc and npc[2] and npc[2] ~= mine then return nil end
	if not npc and other[2] and other[2] ~= mine then return nil end
	local best, zoneOnly
	if npc then best, zoneOnly = NearestPlace(npc) end
	if not best and other then
		local b, z = NearestPlace(other)
		best, zoneOnly = b, zoneOnly or z
	end
	return (npc and npc[1]) or other[1], best or zoneOnly
end

-- The item that teaches a recipe: ForeverRecipes', else Polestar's.
function Where.Teach(spell)
	local data = ns.Recipes and ns.Recipes[spell]
	return (data and data[5]) or (ns.PolestarTeach and ns.PolestarTeach[spell]) or nil
end

-- ---------------------------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------------------------
-- What a recipe item asks for: Polestar's data, else the item's own tooltip ("Requires Nightclaw
-- Druids - Friendly"), read once per item while the item is in the game's cache.

local function Global(name) return type(_G[name]) == "string" and _G[name] or nil end

-- "Friendly" -> 5, the game's own words for each standing (and their female forms).
local standingOf
local function StandingID(word)
	if not standingOf then
		standingOf = {}
		for i = 1, 8 do
			for _, key in ipairs({ "FACTION_STANDING_LABEL" .. i, "FACTION_STANDING_LABEL" .. i .. "_FEMALE" }) do
				local w = Global(key)
				if w then standingOf[w] = i end
			end
		end
	end
	return standingOf[word]
end

function Where.StandingName(id)
	return Global("FACTION_STANDING_LABEL" .. tostring(id)) or tostring(id)
end

-- "Requires %s - %s" as a pattern.
local REQ_PATTERN
local function ReqPattern()
	if REQ_PATTERN == nil then
		local fmt = Global("ITEM_REQ_REPUTATION") or "Requires %s - %s"
		fmt = fmt:gsub("%%%d%$s", "%%s")      -- (a language that numbers its holes: "%1$s")
		REQ_PATTERN = "^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
	end
	return REQ_PATTERN
end

local tipRep = {}         -- item -> { name, standing } or false (its tooltip asks for none)
local function TooltipRep(item)
	local v = tipRep[item]
	if v ~= nil then return v end
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, item)
	local lines = ok and type(data) == "table" and data.lines
	-- (Not in the game's cache yet: asked for, and read again when the page is drawn next.)
	if type(lines) ~= "table" or #lines < 2 then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
		return nil
	end
	v = false
	local pattern = ReqPattern()
	for _, line in ipairs(lines) do
		local text = type(line.leftText) == "string" and line.leftText or nil
		local name, word = nil, nil
		if text then name, word = text:match(pattern) end
		if name and StandingID(word) then
			v = { name = name, standing = StandingID(word) }
			break
		end
	end
	tipRep[item] = v
	return v
end

-- A faction's name in the client's language, and your standing with it (1..8; nil when you haven't
-- met it).
function Where.Faction(factionID)
	local name, reaction
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, f = pcall(C_Reputation.GetFactionDataByID, factionID)
		if ok and type(f) == "table" then name, reaction = f.name, f.reaction end
	elseif _G.GetFactionInfoByID then
		local ok, n, _, standing = pcall(_G.GetFactionInfoByID, factionID)
		if ok then name, reaction = n, standing end
	end
	if type(name) ~= "string" or name == "" then
		name = ns.PolestarNames and ns.PolestarNames.faction[factionID] or L["Faction %d"]:format(factionID)
	end
	return name, type(reaction) == "number" and reaction > 0 and reaction or nil
end

-- Your standing with a faction known by its name only (a tooltip's): read from your reputation list.
local function StandingByName(name)
	if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return nil end
	local ok, n = pcall(C_Reputation.GetNumFactions)
	if not ok or type(n) ~= "number" then return nil end
	for i = 1, n do
		local got, f = pcall(C_Reputation.GetFactionDataByIndex, i)
		if got and type(f) == "table" and f.name == name and not f.isHeader then return f.reaction end
	end
	return nil
end

-- What a recipe item asks for: { faction (id, or nil from a tooltip), name, standing, mine (your
-- standing, nil when not met) }, or nil. waiting: true when its tooltip isn't loaded yet.
function Where.Rep(item)
	if not item then return nil end
	local rep = ns.PolestarRep and ns.PolestarRep[item]
	if rep then
		local name, mine = Where.Faction(rep[1])
		return { faction = rep[1], name = name, standing = rep[2], mine = mine }
	end
	local tip = TooltipRep(item)
	if tip == nil then return nil, true end
	if not tip then return nil end
	return { name = tip.name, standing = tip.standing, mine = StandingByName(tip.name) }
end

-- Whether the data has any source at all for a recipe (any faction's).
local function AnySource(spell, teach)
	if ns.Trainers and ns.Trainers[spell] and #ns.Trainers[spell] > 0 then return true end
	if ns.AutomaticRecipes and ns.AutomaticRecipes[spell] then return true end
	if ns.AutomaticQuests and ns.AutomaticQuests[spell] then return true end
	if teach then
		for _, t in ipairs({ ns.Sellers, ns.Drops, ns.OtherDrops, ns.QuestRewards }) do
			local list = t and t[teach]
			if list and #list > 0 then return true end
		end
	end
	return false
end

-- A quest's title in the client's language once the game has it cached; until then the data's
-- English one, with the quest asked for so the next list made (the window opened again) has it.
local function QuestName(id)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
		if ok and type(title) == "string" and title ~= "" then return title end
		if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
	end
	local q = ns.Quests and ns.Quests[id]
	local meta = ns.QuestMeta and ns.QuestMeta[id]
	return (q and q[1]) or (meta and meta.name) or L["Quest %d"]:format(id)
end

-- "180 copper" (how the data writes a vendor's price) as money; anything else as it is.
local function PriceText(text)
	if type(text) ~= "string" then return nil end
	local copper = tonumber(text:match("^(%d+) copper$"))
	if copper then return ns.Calc.Money(copper) end
	return text
end

-- The places a recipe comes from, in groups:
-- { { kind, title, lines = { { name, place, note, chance } }, more = n }, ... }
local MAX_LINES = 6

-- Nearest first (your zone, then your continent), then by zone and name: the lines past the cut
-- are the far ones.
local function NearestFirst(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	if a.dist ~= b.dist then return a.dist < b.dist end
	local az, bz = a.place and a.place.zone or "", b.place and b.place.zone or ""
	if az ~= bz then return az < bz end
	return a.name < b.name
end

-- A group adder for `groups`: group(kind, title, list, note, sort) lists the NPCs of `list` (ids,
-- or records whose first field is one) that your faction can reach, nearest first, the far ones
-- cut. note(rec, id) gives a line's right-hand text.
local function Grouper(groups)
	return function(kind, title, list, note, sort)
		local lines = {}
		for _, rec in ipairs(list or {}) do
			local id = type(rec) == "table" and rec[1] or rec
			local name, place = Where.Npc(id)
			if name then
				local rank, dist = Near(place)
				lines[#lines + 1] = { name = name, place = place, note = note and note(rec, id), rank = rank, dist = dist,
					chance = type(rec) == "table" and kind == "drop" and rec[2] or nil }
			end
		end
		if #lines == 0 then return end
		table.sort(lines, sort or NearestFirst)
		local more = 0
		if #lines > MAX_LINES then
			more = #lines - MAX_LINES
			for i = #lines, MAX_LINES + 1, -1 do lines[i] = nil end
		end
		groups[#groups + 1] = { kind = kind, title = title, lines = lines, more = more }
	end
end

local function ByChance(a, b)
	local ac, bc = a.chance or -1, b.chance or -1
	if ac ~= bc then return ac > bc end
	return a.name < b.name
end

local function ChanceText(chance)
	return type(chance) == "number" and chance > 0 and L["%s%%"]:format(chance) or nil
end

-- An instance's or object's English name from Polestar's data (the game has no lookup for them).
local function PolestarName(kind, id)
	local names = ns.PolestarNames and ns.PolestarNames[kind]
	return names and names[id] or nil
end

-- Where Polestar says a recipe item comes from (only asked for the items ForeverRecipes has no
-- source for), and the reputation it asks for, added to `groups`.
local function AddPolestar(item, groups)
	local group = Grouper(groups)
	local rep = ns.PolestarRep and ns.PolestarRep[item]
	local list = ns.PolestarSources and ns.PolestarSources[item]
	local vendors, drops, found, quests, given, world, repNpc = {}, {}, {}, {}, {}, nil, nil
	for _, s in ipairs(list or {}) do
		local k = s[1]
		if k == "v" then vendors[#vendors + 1] = { s[2], s[3] }
		elseif k == "d" then drops[#drops + 1] = { s[2], s[3], s[4] }
		elseif k == "o" then
			found[#found + 1] = { name = PolestarName("object", s[2]) or L["Somewhere"], note = ChanceText(s[3]) }
		elseif k == "n" then
			found[#found + 1] = { name = ns.ItemNameOf(s[2]) or PolestarName("item", s[2]) or L["Item %d"]:format(s[2]),
				note = ChanceText(s[3]), item = s[2] }
		elseif k == "q" then quests[#quests + 1] = s[2]
		elseif k == "g" then given[#given + 1] = s[2]
		elseif k == "w" then world = s
		elseif k == "r" then
			rep = rep or { s[2], s[3] }
			if s[4] and s[4] > 0 then repNpc = s[4] end
		end
	end
	-- (A reputation's vendor: the one the data names, else the faction's own vendors.)
	if rep and #vendors == 0 then
		local who = repNpc and { repNpc } or (ns.FactionVendors and ns.FactionVendors[rep[1]])
		if who then
			local word = Where.StandingName(rep[2])
			group("vendor", L["Reputation vendor"], who, function() return word end)
		end
	end
	group("vendor", L["Sold by"], vendors, function(rec)
		return type(rec[2]) == "number" and rec[2] > 0 and ns.Calc.Money(rec[2]) or nil
	end)
	group("drop", L["Dropped by"], drops, function(rec)
		local inst = rec[3] and rec[3] ~= "" and PolestarName("instance", rec[3])
		local chance = ChanceText(rec[2])
		if inst and chance then return L["%s, %s"]:format(chance, inst) end
		return chance or inst or nil
	end, ByChance)
	group("gift", L["Given by"], given)
	if #found > 0 then groups[#groups + 1] = { kind = "drop", title = L["Found in"], lines = found, more = 0 } end
	if world then
		local lines = { { name = L["Enemies of level %d to %d"]:format(world[2], world[3]) } }
		groups[#groups + 1] = { kind = "drop", title = L["World drop"], lines = lines, more = 0 }
	end
	if #quests > 0 then
		local lines = {}
		for _, id in ipairs(quests) do lines[#lines + 1] = { name = QuestName(id), quest = id } end
		groups[#groups + 1] = { kind = "quest", title = L["Quest reward"], lines = lines, more = 0 }
	end
	-- The reputation itself: first, as the condition the rest is under. (Your standing is read as
	-- the page is drawn: Where.Rep.)
	if rep then
		table.insert(groups, 1, { kind = "rep", title = L["Reputation"], lines = {}, more = 0, item = item })
	end
end

-- One group of NPCs (your faction's, nearest first), or nil when none is yours.
function Where.NpcGroup(kind, title, list, note)
	ReadHere()
	local out = {}
	Grouper(out)(kind, title, list, note)
	return out[1]
end

-- Where a recipe item comes from by Polestar's data alone (a camping blueprint): its groups.
local itemSources = {}
function Where.ItemSources(item)
	local g = itemSources[item]
	if not g then
		ReadHere()
		g = {}
		AddPolestar(item, g)
		itemSources[item] = g
	end
	return g
end

local function BuildSources(spell)
	local data = ns.Recipes[spell]
	local groups = {}
	if not data then return groups end
	local group = Grouper(groups)

	local automatic = ns.AutomaticRecipes and ns.AutomaticRecipes[spell]
	local trainers = ns.Trainers and ns.Trainers[spell]
	if trainers and #trainers > 0 then
		group("trainer", L["Trainer"], trainers, function(rec)
			if automatic then return L["With the profession"] end
			return type(rec[2]) == "number" and ns.Calc.Money(rec[2]) or nil
		end)
	elseif automatic then
		groups[#groups + 1] = { kind = "auto", title = L["Learned with the profession"], lines = {}, more = 0 }
	end

	local teach = data[5]
	if teach then
		local costs = ns.RecipeVendorCosts and ns.RecipeVendorCosts[teach]
		group("vendor", L["Sold by"], ns.Sellers and ns.Sellers[teach], function(_, id)
			return costs and PriceText(costs[id]) or nil
		end)
		group("drop", L["Dropped by"], ns.Drops and ns.Drops[teach], function(rec)
			return type(rec[2]) == "number" and L["%s%%"]:format(rec[2]) or nil
		end, ByChance)
		local others = ns.OtherDrops and ns.OtherDrops[teach]
		if others and #others > 0 then
			local lines = {}
			for _, row in ipairs(others) do
				lines[#lines + 1] = { name = row.name or L["Somewhere"], note = type(row.chance) == "number" and L["%s%%"]:format(row.chance) or nil }
			end
			groups[#groups + 1] = { kind = "drop", title = L["Found in"], lines = lines, more = 0 }
		end
	end

	local quests = (teach and ns.QuestRewards and ns.QuestRewards[teach]) or (ns.AutomaticQuests and ns.AutomaticQuests[spell])
	if quests and #quests > 0 then
		local lines = {}
		for _, id in ipairs(quests) do lines[#lines + 1] = { name = QuestName(id), quest = id } end
		groups[#groups + 1] = { kind = "quest", title = L["Quest reward"], lines = lines, more = 0 }
	end

	-- Nothing in ForeverRecipes' tables: Polestar's (for Forever's own recipes, reputation ones).
	teach = Where.Teach(spell)
	if teach and not AnySource(spell, data[5]) then
		AddPolestar(teach, groups)
	elseif teach and ns.PolestarRep and ns.PolestarRep[teach] then
		-- (Sold by a faction's vendor the tables know: the reputation it asks for, on top.)
		table.insert(groups, 1, { kind = "rep", title = L["Reputation"], lines = {}, more = 0, item = teach })
	end
	return groups
end

-- A recipe's sources: the data never changes, so each is made once per window opening.
function Where.Sources(spell)
	local g = sources[spell]
	if not g then
		g = BuildSources(spell)
		sources[spell] = g
	end
	return g
end

local KIND_WORD = { trainer = L["Trainer"], vendor = L["Vendor"], drop = L["Drop"], quest = L["Quest"], auto = L["With the profession"],
	rep = L["Reputation"], gift = L["Given"] }

-- "Trainer · Vendor", for the list.
function Where.Summary(groups)
	local seen, words = {}, {}
	for _, g in ipairs(groups) do
		local w = KIND_WORD[g.kind]
		if w and not seen[w] then
			seen[w] = true
			words[#words + 1] = w
		end
	end
	if #words == 0 then return nil end
	return table.concat(words, " · ")
end

-- The open profession's missing recipes: { { spell, name, required, level, reachable, item,
-- groups, summary } }, by the skill they need, then name. filter: lower-case text to match.
local UNKNOWN_SOURCE = L["Source not known yet"]

-- The open profession's missing recipes, everything that doesn't depend on your skill or level:
-- made once per profession opening and again only when a recipe is learned (a skill point only
-- changes which are reachable, worked out per list below).
local function Base()
	local S = ns.state
	local key = S.line .. ":" .. ns.Faction()
	if base and baseKey == key then return base end
	ReadHere()
	local mine = ns.Faction()
	local out = {}
	for spell, data in pairs(ns.Recipes or {}) do
		if data[1] == S.line then
			local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
			local variant = meta and meta.variantFaction
			if (not variant or variant == mine) and not Where.Knows(spell) then
				local name = ns.SpellName(spell) or L["Recipe %d"]:format(spell)
				local groups = Where.Sources(spell)
				local teach = Where.Teach(spell)
				-- Only the other faction can get it: not a recipe for you. Nothing in the data at
				-- all (ForeverRecipes' or Polestar's): listed, saying so, rather than left out.
				local unknown = #groups == 0 and not AnySource(spell, data[5])
					and not (teach and ns.PolestarSources and ns.PolestarSources[teach])
				if #groups > 0 or unknown then
					out[#out + 1] = { spell = spell, name = name, lower = ns.Fold(name),
						required = Where.Required(spell), level = Where.Level(spell), item = teach,
						groups = groups, unknown = unknown, hasRep = (teach and ns.PolestarRep and ns.PolestarRep[teach]) and true or nil,
						summary = unknown and UNKNOWN_SOURCE or Where.Summary(groups) }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ar, br = a.required or 9999, b.required or 9999
		if ar ~= br then return ar < br end
		return ns.NameLess(a.name, b.name)
	end)
	base, baseKey = out, key
	return out
end

-- The list shown: the base list with what your skill and level allow worked out, and the
-- name filter (lower-case text) applied. Cheap: no data is read here.
local shown = {}
function Where.Missing(filter)
	local S = ns.state
	wipe(shown)
	if not S.line or S.linked then return shown end
	Where.Refresh()
	local only = ns.Get("learnableOnly")
	local level = UnitLevel("player") or 0
	local skill = S.skill or 0
	for _, e in ipairs(Base()) do
		if not filter or filter == "" or e.lower:find(filter, 1, true) then
			e.reachable = (not e.required or skill >= e.required) and (not e.level or level >= e.level)
			if not only or e.reachable then shown[#shown + 1] = e end
		end
	end
	return shown
end

-- ---------------------------------------------------------------------------------------------
-- Waypoints
-- ---------------------------------------------------------------------------------------------

function Where.Go(name, place)
	if not place or not place.mapID or type(place.x) ~= "number" then return false end
	local x, y = place.x / 100, place.y / 100
	local tomtom = _G.TomTom
	if ns.Get("tomtom") and type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
		pcall(tomtom.AddWaypoint, tomtom, place.mapID, x, y, { title = name, from = "Daylight Recipes" })
		ns.Print(L["Waypoint: %s, %s (%d, %d)."]:format(name, place.zone, place.x + 0.5, place.y + 0.5))
		return true
	end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(place.mapID) then
		ns.Print(L["%s is in %s (%d, %d); the map there takes no pins."]:format(name, place.zone, place.x + 0.5, place.y + 0.5))
		return false
	end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(place.mapID, x, y))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	if ok then ns.Print(L["Map pin: %s, %s (%d, %d)."]:format(name, place.zone, place.x + 0.5, place.y + 0.5)) end
	return ok
end
