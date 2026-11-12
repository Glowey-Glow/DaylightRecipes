-- Missing recipes: the open profession's recipes this character doesn't know, from the data,
-- and for each one where it comes from (trainers, vendors, drops, quests) with the place on the
-- map. Only your faction's people and places are listed; a recipe only the other faction can get
-- is left out.
local _, ns = ...
if not ns.ok then return end

local Where = {}
ns.Where = Where

local known       -- recipe -> true, this character's, for the open profession (read once per list)
local lastKey, lastList   -- the last missing list, and what it was made for

function Where.ForgetKnown()
	known = nil
	lastKey, lastList = nil, nil
end

local function SpellKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
		if ok then return yes end
	end
	return IsSpellKnown and IsSpellKnown(id) or false
end

local function Known()
	if known then return known end
	known = {}
	local ids = ns.Ask("GetAllRecipeIDs")
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		local info = ns.Ask("GetRecipeInfo", id)
		if type(info) == "table" and info.learned then known[id] = true end
	end
	return known
end

function Where.Knows(spell)
	return Known()[spell] or SpellKnown(spell)
end

-- The skill a recipe can be learned at, or nil when the data doesn't say.
function Where.Required(spell)
	local data = ns.Recipes[spell]
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if not data then return nil end
	if meta and (meta.levelRequired or meta.requirementKnown == false) then return nil end
	local t = data[2]
	return type(t) == "table" and t[1] or nil
end

-- A character level the recipe asks for, if any.
function Where.Level(spell)
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	return meta and (meta.levelRequired or meta.minCharacterLevel) or nil
end

-- name, place ({ zone, mapID, x, y } or { zone }) of one of the data's NPCs, nil when it's the
-- other faction's.
function Where.Npc(id)
	local npc = ns.Npcs and ns.Npcs[id]
	if not npc then return nil end
	if npc[2] and npc[2] ~= ns.Faction() then return nil end
	local zoneOnly
	for i = 3, #npc do
		local l = npc[i]
		if type(l) == "table" then
			if l[2] then return npc[1], { zone = l[1], mapID = l[2], x = l[3], y = l[4] } end
			zoneOnly = zoneOnly or { zone = l[1] }
		end
	end
	return npc[1], zoneOnly
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

function Where.Sources(spell)
	local data = ns.Recipes[spell]
	local groups = {}
	if not data then return groups end
	local function group(kind, title, list, note, sort)
		local lines = {}
		for _, rec in ipairs(list or {}) do
			local id = type(rec) == "table" and rec[1] or rec
			local name, place = Where.Npc(id)
			if name then
				lines[#lines + 1] = { name = name, place = place, note = note and note(rec, id),
					chance = type(rec) == "table" and kind == "drop" and rec[2] or nil }
			end
		end
		if #lines == 0 then return end
		table.sort(lines, sort or function(a, b)
			local az, bz = a.place and a.place.zone or "", b.place and b.place.zone or ""
			if az ~= bz then return az < bz end
			return a.name < b.name
		end)
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
function Where.Missing(filter)
	local S = ns.state
	local out = {}
	if not S.line or S.linked then return out end
	local mine = ns.Faction()
	local only = ns.Get("learnableOnly")
	local level = UnitLevel("player") or 0
	local key = table.concat({ S.line, S.skill, level, tostring(only), filter or "" }, ":")
	if key == lastKey then return lastList end
	for spell, data in pairs(ns.Recipes or {}) do
		if data[1] == S.line then
			local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
			local variant = meta and meta.variantFaction
			if (not variant or variant == mine) and not Where.Knows(spell) then
				local name = ns.RecipeNames and ns.RecipeNames[spell] or ("Recipe " .. spell)
				if not filter or filter == "" or name:lower():find(filter, 1, true) then
					local required = Where.Required(spell)
					local needLevel = Where.Level(spell)
					local reachable = (not required or S.skill >= required) and (not needLevel or level >= needLevel)
					if not only or reachable then
						local groups = Where.Sources(spell)
						-- Nothing your faction can reach: not a recipe for you.
						if #groups > 0 then
							out[#out + 1] = { spell = spell, name = name, required = required, level = needLevel,
								reachable = reachable, item = data[5] or nil, groups = groups,
								summary = Where.Summary(groups) }
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ar, br = a.required or 9999, b.required or 9999
		if ar ~= br then return ar < br end
		return a.name < b.name
	end)
	lastKey, lastList = key, out
	return out
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
