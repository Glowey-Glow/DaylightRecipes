-- Missing recipes: the open profession's recipes this character doesn't know, from the data,
-- and for each one where it comes from (trainers, vendors, drops, quests) with the place on the
-- map. Only your faction's people and places are listed; a recipe only the other faction can get
-- is left out.
local _, ns = ...
if not ns.ok then return end

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

-- name, place ({ zone, mapID, x, y } or { zone }) of one of the data's NPCs, nil when it's the
-- other faction's. Of an NPC's spawns, the nearest one with a spot on the map.
function Where.Npc(id)
	local npc = ns.Npcs and ns.Npcs[id]
	if not npc then return nil end
	if npc[2] and npc[2] ~= ns.Faction() then return nil end
	local best, bestRank, bestDist, zoneOnly
	for i = 3, #npc do
		local l = npc[i]
		if type(l) == "table" then
			if l[2] then
				local place = { zone = l[1], mapID = l[2], x = l[3], y = l[4] }
				local rank, dist = Near(place)
				if not best or rank < bestRank or (rank == bestRank and dist < bestDist) then
					best, bestRank, bestDist = place, rank, dist
				end
			else
				zoneOnly = zoneOnly or { zone = l[1] }
			end
		end
	end
	return npc[1], best or zoneOnly
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

local function QuestName(id)
	local q = ns.Quests and ns.Quests[id]
	local meta = ns.QuestMeta and ns.QuestMeta[id]
	return (q and q[1]) or (meta and meta.name) or ("Quest " .. id)
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

local function BuildSources(spell)
	local data = ns.Recipes[spell]
	local groups = {}
	if not data then return groups end
	local function group(kind, title, list, note, sort)
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

	local automatic = ns.AutomaticRecipes and ns.AutomaticRecipes[spell]
	local trainers = ns.Trainers and ns.Trainers[spell]
	if trainers and #trainers > 0 then
		group("trainer", "Trainer", trainers, function(rec)
			if automatic then return "With the profession" end
			return type(rec[2]) == "number" and ns.Calc.Money(rec[2]) or nil
		end)
	elseif automatic then
		groups[#groups + 1] = { kind = "auto", title = "Learned with the profession", lines = {}, more = 0 }
	end

	local teach = data[5]
	if teach then
		local costs = ns.RecipeVendorCosts and ns.RecipeVendorCosts[teach]
		group("vendor", "Sold by", ns.Sellers and ns.Sellers[teach], function(_, id)
			return costs and PriceText(costs[id]) or nil
		end)
		group("drop", "Dropped by", ns.Drops and ns.Drops[teach], function(rec)
			return type(rec[2]) == "number" and (rec[2] .. "%") or nil
		end, function(a, b)
			local ac, bc = a.chance or -1, b.chance or -1
			if ac ~= bc then return ac > bc end
			return a.name < b.name
		end)
		local others = ns.OtherDrops and ns.OtherDrops[teach]
		if others and #others > 0 then
			local lines = {}
			for _, row in ipairs(others) do
				lines[#lines + 1] = { name = row.name or "Somewhere", note = type(row.chance) == "number" and (row.chance .. "%") or nil }
			end
			groups[#groups + 1] = { kind = "drop", title = "Found in", lines = lines, more = 0 }
		end
	end

	local quests = (teach and ns.QuestRewards and ns.QuestRewards[teach]) or (ns.AutomaticQuests and ns.AutomaticQuests[spell])
	if quests and #quests > 0 then
		local lines = {}
		for _, id in ipairs(quests) do lines[#lines + 1] = { name = QuestName(id), quest = id } end
		groups[#groups + 1] = { kind = "quest", title = "Quest reward", lines = lines, more = 0 }
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

local KIND_WORD = { trainer = "Trainer", vendor = "Vendor", drop = "Drop", quest = "Quest", auto = "With the profession" }

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
local UNKNOWN_SOURCE = "Source not known yet"

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
				local name = ns.RecipeNames and ns.RecipeNames[spell] or ("Recipe " .. spell)
				local groups = Where.Sources(spell)
				local teach = data[5] or nil
				-- Only the other faction can get it: not a recipe for you. Nothing in the data at
				-- all (many of Forever's own): listed, saying so, rather than left out.
				local unknown = #groups == 0 and not AnySource(spell, teach)
				if #groups > 0 or unknown then
					out[#out + 1] = { spell = spell, name = name, lower = name:lower(),
						required = Where.Required(spell), level = Where.Level(spell), item = teach,
						groups = groups, unknown = unknown,
						summary = unknown and UNKNOWN_SOURCE or Where.Summary(groups) }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ar, br = a.required or 9999, b.required or 9999
		if ar ~= br then return ar < br end
		return a.name < b.name
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
		ns.Print(("Waypoint: %s, %s (%d, %d)."):format(name, place.zone, place.x + 0.5, place.y + 0.5))
		return true
	end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(place.mapID) then
		ns.Print(("%s is in %s (%d, %d); the map there takes no pins."):format(name, place.zone, place.x + 0.5, place.y + 0.5))
		return false
	end
	local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(place.mapID, x, y))
	if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end
	if ok then ns.Print(("Map pin: %s, %s (%d, %d)."):format(name, place.zone, place.x + 0.5, place.y + 0.5)) end
	return ok
end
