-- Ranks.lua on the plugin's real Where.lua and data files: every rank of every profession names
-- someone each faction can reach (a trainer, a book's vendor, a quest's giver), every NPC id it
-- lists is one the NPC tables place, and the answers the research was checked against hold.
-- luacheck: globals ADDON_ROOT UnitFactionGroup wipe C_Map Enum
-- luacheck: read globals T
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Where.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Where.lua not found")

local faction = "Horde"
function UnitFactionGroup() return faction end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- The player stands in Orgrimmar (map 1454); every other map is "elsewhere".
C_Map = {
	GetBestMapForUnit = function() return 1454 end,
	GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end,
	GetMapInfo = function(id) return { name = "map" .. id, mapType = 3, parentMapID = nil } end,
}
Enum = { UIMapType = { Continent = 2 } }

local ns = { ok = true, state = {} }
local function load(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	assert(loadstring(src, "@" .. file))("DaylightRecipes", ns)
end
load("Locales/Locales.lua")
for _, f in ipairs({ "Recipes", "Sources", "Client", "Npcs", "Polestar", "Corrections" }) do load("Data/" .. f .. ".lua") end
ns.Faction = function() return faction == "Horde" and "H" or "A" end
ns.Get = function() return false end
ns.Ask = function() return nil end
ns.Print = function() end
ns.Fold = string.lower
ns.SpellName = function() return nil end
load("Ranks.lua")
load("Where.lua")
local Where = ns.Where

local LINES = { [171] = "Alchemy", [164] = "Blacksmithing", [185] = "Cooking", [333] = "Enchanting", [202] = "Engineering",
	[129] = "First Aid", [165] = "Leatherworking", [186] = "Mining", [197] = "Tailoring" }
local CAPS = { 150, 225, 300 }

T.case("every profession has all three ranks, each learnable before its cap", function()
	for line, name in pairs(LINES) do
		local ranks = ns.Ranks[line]
		T.ok(type(ranks) == "table", name .. " is in Ranks.lua")
		for _, cap in ipairs(CAPS) do
			local rec = ranks and ranks[cap]
			T.ok(type(rec) == "table", name .. " " .. cap)
			if rec then T.eq(rec.at, cap - 100, name .. " " .. cap .. " is learned from 100 under its cap") end
		end
	end
end)

T.case("every NPC a rank names is one the tables place, for some faction", function()
	local function seen(id)
		for _, f in ipairs({ "Horde", "Alliance" }) do
			faction = f
			local who, place = Where.Npc(id)
			if who and place then return true end
		end
		return false
	end
	for line, name in pairs(LINES) do
		for _, cap in ipairs(CAPS) do
			local rec = ns.Ranks[line][cap]
			for _, id in ipairs(rec.who or {}) do T.ok(seen(id), name .. " " .. cap .. ": NPC " .. id) end
			for _, q in ipairs(rec.quests or {}) do
				for _, id in ipairs(q.who or {}) do T.ok(seen(id), name .. " " .. cap .. " quest: NPC " .. id) end
			end
		end
	end
	faction = "Horde"
end)

T.case("each faction is sent somewhere for every rank", function()
	for _, f in ipairs({ "Horde", "Alliance" }) do
		faction = f
		for line, name in pairs(LINES) do
			for _, cap in ipairs(CAPS) do
				local info = Where.RankInfo(line, cap)
				T.ok(info ~= nil, f .. " " .. name .. " " .. cap .. ": a record")
				local who = info and info.who or Where.NearestRankTrainer(line, cap - 75)
				T.ok(who ~= nil and who.name ~= nil, f .. " " .. name .. " " .. cap .. ": someone to go to")
			end
		end
	end
	faction = "Horde"
end)

T.case("the answers the research was checked against", function()
	faction = "Horde"
	-- Tailoring in Orgrimmar: Magar trains Journeyman; Expert is Josef Gregorian's (Undercity), not hers.
	T.eq(Where.RankInfo(197, 150).who.name, "Magar", "Journeyman Tailoring, in Orgrimmar")
	-- (Both far from Orgrimmar: either is right; never Magar.)
	local expert = Where.RankInfo(197, 225).who.name
	T.ok(expert == "Josef Gregorian" or expert == "Daryl Stack", "Expert Tailoring for the Horde: " .. tostring(expert))
	T.eq(Where.RankInfo(197, 300).who.name, "Daryl Stack", "Artisan Tailoring for the Horde")
	T.eq(Where.RankInfo(333, 225).who.name, "Hgarth", "Expert Enchanting for the Horde")
	T.eq(Where.RankInfo(333, 300).who.name, "Annora", "Artisan Enchanting")
	T.eq(Where.RankInfo(164, 300).who.name, "Brikk Keencraft", "Artisan Blacksmithing")
	T.eq(Where.RankInfo(186, 300).who.name, "Makaru", "Mining, any rank, in Orgrimmar")
	-- Cooking and First Aid: a trainer, then a book, then a quest.
	local cook = Where.RankInfo(185, 150)
	T.eq(cook.how, "trainer", "Journeyman Cooking is a trainer's"); T.eq(cook.who, nil, "any trainer: none named")
	T.ok(Where.NearestRankTrainer(185, 75) ~= nil, "found from the recipe data")
	T.eq(Where.NearestRankTrainer(185, 150), nil, "the fallback answers nothing past a book rank")
	local book = Where.RankInfo(185, 225)
	T.eq(book.how, "book", "Expert Cooking is a book"); T.eq(book.item, 16072, "the Expert Cookbook")
	T.eq(book.who.name, "Wulan", "the Horde's vendor"); T.eq(book.cost, 10000, "one gold")
	local quest = Where.RankInfo(185, 300)
	T.eq(quest.how, "quest", "Artisan Cooking is a quest"); T.eq(quest.quest, 6610, "Clamlette Surprise")
	T.eq(quest.who.name, "Dirge Quikcleave", "its giver"); T.eq(#quest.bring, 3, "three things to bring")
	T.eq(Where.RankInfo(129, 300).who.name, "Doctor Gregory Victor", "the Horde's Triage")
	faction = "Alliance"
	T.eq(Where.RankInfo(129, 300).quest, 6624, "the Alliance's Triage"); T.eq(Where.RankInfo(129, 300).who.name, "Doctor Gustaf VanHowzen", "its doctor")
	T.eq(Where.RankInfo(185, 225).who.name, "Shandrina", "the Alliance's cookbook vendor")
	expert = Where.RankInfo(197, 225).who.name
	T.ok(expert == "Georgio Bolero" or expert == "Timothy Worthington", "Expert Tailoring for the Alliance: " .. tostring(expert))
	-- A profession Ranks.lua doesn't hold: no record.
	T.eq(Where.RankInfo(356, 150), nil, "Fishing has none here")
	faction = "Horde"
end)

return T.done()
