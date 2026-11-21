-- The Missing tab over every profession, on the plugin's real data files (Data/Client.lua's 424
-- recipes the upstream data dropped among them), its real Calc.lua, Where.lua and Pages.lua, with
-- a character who knows nothing: every recipe listed has a name of its own, thresholds, a chance
-- and materials with item names in the data; and the compact window's pages for it (the list, and
-- the detail column's page for each recipe) draw without an error. Also what Data/Client.lua must
-- hold to: its recipes are in the plugin's tables, its threshold corrections are read by
-- Calc.Thresholds, a known-only recipe is not listed as missing, a nameless trainer record is no one.
-- luacheck: globals GAME NS ADDON_ROOT DaylightRecipesDB C_TradeSkillUI GetItemInfo UnitFactionGroup UnitLevel wipe bit GameTooltip
-- luacheck: read globals T
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Data/Client.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Data/Client.lua not found")

function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 60 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
bit = nil
-- (The game knows no item by name here: an item's name must come from the plugin's own data.)
function GetItemInfo() return nil end
C_TradeSkillUI = {
	GetAllRecipeIDs = function() return {} end,
	GetRecipeInfo = function() return { learned = false, canSkillUp = false, numSkillUps = 0 } end,
}

local Any
Any = setmetatable({}, { __index = function() return Any end, __call = function() return Any end })
GameTooltip = Any

local ns = { ok = true, state = {} }
local S = ns.state
local function load(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	assert(loadstring(src, "@" .. file))("DaylightRecipes", ns)
end
load("Locales/Locales.lua")
-- The data files in the .toc's order (run.py has checked the files under test against it; these
-- are read from the .toc here, so a data file added to it is loaded, and one dropped from it is not).
local toc = assert(io.open(ROOT .. "/DaylightRecipes.toc", "r"))
local dataFiles = {}
for line in toc:lines() do
	local name = line:gsub("\r", ""):match("^Data[\\/](.+%.lua)$")
	if name then dataFiles[#dataFiles + 1] = name end
end
toc:close()
local hasClient = false
for _, name in ipairs(dataFiles) do
	if name == "Client.lua" then hasClient = true end
	load("Data/" .. name)
end
T.ok(hasClient, "Data\\Client.lua is in the .toc")
T.ok(#dataFiles >= 7, "with the other six data files")

ns.Get = function(key)
	if key == "useAH" or key == "talents" then return true end
	return nil
end
ns.Ask = function(name, ...)
	local fn = C_TradeSkillUI[name]
	if type(fn) ~= "function" then return nil end
	return fn(...)
end
ns.Faction = function() return "A" end
ns.SpellName = function(id) return ns.RecipeNames[id] end
ns.Fold = function(s) return type(s) == "string" and s:lower() or "" end
-- (Core.lua's: the game's name for an item. The game knows none here, so the data's own is used.)
ns.ItemNameOf = function() return nil end
ns.NameLess = function(a, b) return tostring(a) < tostring(b) end
ns.Changed = function() end
ns.Print = function() end
ns.Store = {
	version = 0,
	Char = function() return { targets = {}, plans = {} } end,
	Count = function() return { mine = 0, bags = 0, bank = 0, mail = 0, alts = {}, altTotal = 0 } end,
	WhoKnows = function() return {} end,
	SeenVendor = function() return nil end,
	SaveKnown = function() end,
}
ns.Prices = { Mogul = function() return false end, Has = function() return true end, Get = function() return 100 end }
load("Calc.lua")
load("Where.lua")
local Calc, Where = ns.Calc, ns.Where
Calc.Talents = function() return 0, 0, { overtime = 0, overtimeRank = 0, bartering = 0, barteringRank = 0 } end

-- Pages.lua, on a doc that keeps what was drawn.
ns.Doc = setmetatable({ Color = function() return 1, 1, 1 end, Hex = function() return "" end,
	ItemName = function(id) return ns.ItemNames and ns.ItemNames[id] or ("Item " .. id), "icon" end,
	ItemTip = function() return function() end end, SpellTip = function() return function() end end,
	Pct = function(v) return tostring(v) end,
	RecipeName = function(id) return ns.RecipeNames[id] end }, { __index = function() return Any end })
setmetatable(ns, { __index = function() return Any end })
load("Pages.lua")
local Pages = ns.Pages
local function NewDoc()
	local d = { rows = {}, lines = {}, state = {}, waiting = {} }
	function d:Heading(t) self.lines[#self.lines + 1] = t end
	function d:Line(t) self.lines[#self.lines + 1] = t end
	function d:Row(o) self.rows[#self.rows + 1] = o end
	function d.Gap() end
	function d.Bar() return Any end
	function d.Buttons() end
	function d.Pickers() end
	return d
end

local LINES = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [185] = "Cooking", [186] = "Mining",
	[197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [129] = "First Aid", [40] = "Poisons" }

-- ---- the generated data carries every table the plugin reads ------------------------------------------
-- The Data files are generated (Tools/*.py) and regenerated when their sources update. A table one
-- of them stops writing would go unnoticed: every reader guards with "ns.X or {}", so its feature
-- just goes quiet (the Camping page, a source on the Missing tab). So: every table the plugin's
-- code reads from the data is named here, must be in the data, and must hold something; and the
-- code is read for the names, so one it starts reading has to be added here.
local READ = {
	-- Data/Recipes.lua
	"Recipes", "RecipeMeta", "RecipeNames", "ItemNames",
	-- Data/Sources.lua
	"Trainers", "AutomaticRecipes", "AutomaticQuests", "Sellers", "Drops", "OtherDrops", "QuestRewards",
	"VendorSellers", "RecipeVendorCosts",
	-- Data/Client.lua
	"ClientRanges",
	-- Data/Npcs.lua
	"Npcs", "Quests", "QuestMeta",
	-- Data/Polestar.lua
	"PolestarTeach", "PolestarRep", "PolestarSources", "PolestarNpcs", "PolestarNames", "FactionVendors",
	"CampTrainers", "Camping", "CampReagents",
	-- Data/Corrections.lua
	"CorrectionSources", "CorrectionNpcs", "CorrectionNames",
	-- Data/Disenchant.lua
	"DisenchantProfiles", "DisenchantExcluded", "DisenchantItems",
}
-- (Written empty by their generators today: nothing of the kind is in the sources.)
local MAY_BE_EMPTY = { AutomaticQuests = true, OtherDrops = true }
T.case("the generated data carries every table the plugin reads", function()
	local listed = {}
	for _, name in ipairs(READ) do
		listed[name] = true
		local t = ns[name]
		T.ok(type(t) == "table", "ns." .. name .. " is in the data")
		if type(t) == "table" and not MAY_BE_EMPTY[name] then
			T.ok(next(t) ~= nil, "ns." .. name .. " holds something")
		end
	end
	-- The tables the data files write, and which of them the plugin's own files read.
	local written = {}
	for _, name in ipairs(dataFiles) do
		local f = assert(io.open(ROOT .. "/Data/" .. name, "rb"))
		for line in f:lines() do
			local t = line:match("^ns%.([%w_]+)%s*=")
			if t then written[t] = name end
		end
		f:close()
	end
	local toc2 = assert(io.open(ROOT .. "/DaylightRecipes.toc", "r"))
	local files = 0
	for line in toc2:lines() do
		local file = line:gsub("\r", ""):match("^([%w_]+%.lua)$")
		if file then
			files = files + 1
			local f = assert(io.open(ROOT .. "/" .. file, "rb"))
			local src = f:read("*a")
			f:close()
			for t in src:gmatch("ns%.([%w_]+)") do
				if written[t] and not listed[t] then
					T.ok(false, file .. " reads ns." .. t .. " (Data/" .. written[t] .. "): name it in this test's READ list")
					listed[t] = true
				end
			end
		end
	end
	toc2:close()
	T.ok(files >= 25, "the plugin's files were read for the names: " .. files)
	for _, name in ipairs(READ) do
		T.ok(written[name] ~= nil, "ns." .. name .. " is written by a data file in the .toc")
	end
	-- The shapes the Camping page and the menu read (Camp.lua, WindowMenu.lua).
	T.ok(#ns.Camping >= 30, "camping items for every profession: " .. #ns.Camping)
	local lines = {}
	for i, c in ipairs(ns.Camping) do
		T.ok(type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" and type(c[4]) == "number"
			and (c[5] == false or type(c[5]) == "number"), "camping item " .. i .. ": { spell, line, skill, item, blueprint or false }")
		lines[c[2]] = true
	end
	for _, line in ipairs({ 129, 164, 165, 171, 185, 186, 197, 202, 333, 182, 393, 356 }) do
		T.ok(lines[line], "camping items for skill line " .. line)
	end
	T.ok(type(ns.PolestarNames.quest) == "table", "quest names (a gathering page's rank quest)")
end)

-- ---- Data/Client.lua ------------------------------------------------------------------------------
T.case("Data/Client.lua: its recipes are in the plugin's tables, its corrections in Calc.Thresholds", function()
	T.ok(type(ns.ClientRanges) == "table" and next(ns.ClientRanges) ~= nil, "the client's threshold corrections are loaded")
	-- A recipe the upstream data dropped: Runecloth Bandage (gray past 300).
	local runecloth
	for spell, name in pairs(ns.RecipeNames) do
		local data = ns.Recipes[spell]
		if name == "Runecloth Bandage" and data and data[1] == 129 then runecloth = spell end
	end
	T.ok(runecloth ~= nil, "Runecloth Bandage is a First Aid recipe again")
	local t = Calc.Thresholds(runecloth)
	T.ok(type(t) == "table" and t[4] > 300, "with thresholds, gray past 300")
	T.ok(#Calc.Materials(runecloth) > 0, "and materials")
	-- A correction: Coarse Grinding Stone gives points to 90, not 75 (2.8.0's changelog), now from
	-- the data, not from a list in Calc.lua.
	local stone
	for spell, name in pairs(ns.RecipeNames) do
		if name == "Coarse Grinding Stone" and ns.Recipes[spell] then stone = spell end
	end
	T.ok(stone ~= nil, "(Coarse Grinding Stone is in the data)")
	T.eq(Calc.Thresholds(stone)[4], 90, "Coarse Grinding Stone is gray from 90, by the client's ranges")
	T.ok(ns.ClientRanges[stone] ~= nil, "which is where that comes from")
	local n = 0
	for _ in pairs(ns.Recipes) do n = n + 1 end
	T.ok(n > 2000, "the recipes of both sources are one table (" .. n .. ")")
end)

-- ---- the Missing tab, every profession -------------------------------------------------------------
T.case("Missing: every recipe of every profession has a name, thresholds, a chance and named materials", function()
	local total, knownOnly = 0, 0
	for line, prof in pairs(LINES) do
		S.line, S.name, S.skill, S.max, S.linked = line, prof, 1, 300, false
		ns.Store.version = ns.Store.version + 1
		Where.Refresh()
		local list = Where.Missing("")
		T.ok(#list > 0, prof .. ": there are recipes to list")
		local seen = {}
		for _, e in ipairs(list) do
			total = total + 1
			local what = ("%s %d"):format(prof, e.spell)
			T.ok(not seen[e.spell], what .. ": listed once")
			seen[e.spell] = true
			T.ok(type(e.name) == "string" and e.name ~= "" and not e.name:find("^Recipe %d"), what .. ": a name of its own (" .. tostring(e.name) .. ")")
			local meta = ns.RecipeMeta[e.spell]
			T.ok(not (meta and meta.knownOnly), what .. ": not a known-only recipe")
			local t = Calc.Thresholds(e.spell)
			if not (meta and meta.thresholdsKnown == false) then
				T.ok(type(t) == "table" and type(t[2]) == "number" and type(t[4]) == "number", what .. ": thresholds")
				local chance, _, state = Calc.Chance(e.spell, math.max(1, (t[2] or 1) - 1), 0)
				T.ok(type(chance) == "number" and chance >= 0 and chance <= 1 and state ~= nil, what .. ": a chance")
			end
			for _, m in ipairs(Calc.Materials(e.spell)) do
				local name = ns.ItemNames[m[1]]
				T.ok(type(name) == "string" and name ~= "", ("%s (%s): material %d has an item name"):format(what, e.name, m[1]))
				T.ok(type(m[2]) == "number" and m[2] > 0, what .. ": and a count")
			end
			-- (Its sources, as the page draws them: every trainer or vendor named is someone.)
			for _, group in ipairs(e.groups or {}) do
				T.ok(type(group) == "table", what .. ": a source group")
			end
		end
		for spell, data in pairs(ns.Recipes) do
			local meta = ns.RecipeMeta[spell]
			if data[1] == line and meta and meta.knownOnly then
				knownOnly = knownOnly + 1
				T.ok(not seen[spell], ("%s %d: a known-only recipe is not listed as missing"):format(prof, spell))
			end
		end
	end
	T.ok(total > 1500, "recipes checked: " .. total)
	T.ok(knownOnly >= 0, "known-only recipes left out: " .. knownOnly)
end)

T.case("Missing: the compact window's list and its detail column draw for every recipe", function()
	local drawn = 0
	for line, prof in pairs(LINES) do
		S.line, S.name, S.skill, S.max, S.linked = line, prof, 1, 300, false
		ns.Store.version = ns.Store.version + 1
		Where.Refresh()
		local list = {}
		for i, e in ipairs(Where.Missing("")) do list[i] = { spell = e.spell, name = e.name } end
		-- The list, every page of it (it shows a page at a time, with "Show N More").
		local d = NewDoc()
		local ctx = { filter = "", redraw = function() end, detail = function() end }
		Pages.Missing(d, ctx)
		for _ = 1, 200 do
			local more = d.rows[#d.rows]
			if not (more and type(more.left) == "string" and more.left:find("Show", 1, true) and more.onClick) then break end
			more.onClick()
			d.rows, d.lines = {}, {}
			Pages.Missing(d, ctx)
		end
		local rows = {}
		for _, r in ipairs(d.rows) do rows[r.left] = (rows[r.left] or 0) + 1 end
		for _, e in ipairs(list) do
			T.ok(rows[e.name] ~= nil, ("%s: the list has a row for %s"):format(prof, e.name))
		end
		-- The detail column's page of each.
		for _, e in ipairs(list) do
			local page = NewDoc()
			local ok, err = pcall(Pages.MissingDetail, page, e.spell)
			T.ok(ok, ("%s: the detail page of %s draws (%s)"):format(prof, e.name, tostring(err)))
			T.eq(page.rows[1] and page.rows[1].left, e.name, prof .. ": headed by the recipe's name")
			drawn = drawn + 1
		end
		-- With the list's own rows opened (the pane's way: the sources under the row).
		d = NewDoc()
		d.state.open = {}
		for _, e in ipairs(list) do d.state.open[e.spell] = true end
		local ok, err = pcall(Pages.Missing, d, { filter = "", redraw = function() end })
		T.ok(ok, prof .. ": the list with every row opened draws (" .. tostring(err) .. ")")
	end
	T.ok(drawn > 1500, "detail pages drawn: " .. drawn)
end)

T.case("Where: a trainer record with no name is no one; a source named twice shows once", function()
	T.eq((Where.Npc(-12345)), nil, "an id the data has no record of: no one, and no error")
	-- Every trainer the data names for a recipe is someone or no one, never an error.
	local asked = 0
	for _, list in pairs(ns.Trainers or {}) do
		for _, rec in ipairs(type(list) == "table" and list or {}) do
			local id = type(rec) == "table" and rec[1] or rec
			local ok, name = pcall(Where.Npc, id)
			T.ok(ok and (name == nil or (type(name) == "string" and name ~= "")), "trainer " .. tostring(id) .. ": a name or no one")
			asked = asked + 1
		end
	end
	T.ok(asked > 0, "trainer records asked: " .. asked)
	-- Sources: within one kind of a recipe's sources no one is named twice.
	for line, prof in pairs(LINES) do
		S.line, S.name, S.skill, S.max, S.linked = line, prof, 1, 300, false
		ns.Store.version = ns.Store.version + 1
		Where.Refresh()
		for _, e in ipairs(Where.Missing("")) do
			for _, group in ipairs(e.groups or {}) do
				local seen = {}
				for _, l in ipairs(group.lines or {}) do
					T.ok(type(l.name) == "string" and l.name ~= "", ("%s %s: a source line has a name (%s: %s, %s)"):format(prof, e.name, tostring(group.kind), type(l.name), tostring(group.title)))
					local place = type(l.place) == "table" and l.place or {}
					local key = table.concat({ l.name, tostring(l.note), tostring(place.mapID), tostring(place.zone),
						tostring(place.x), tostring(place.y) }, "|")
					-- (People: a trainer or a vendor at one place is one line, also when two of the data's
					-- sources name them. Quests and chests of one name can be several: not held to it.)
					if group.kind == "trainer" or group.kind == "vendor" then
						T.ok(not seen[key], ("%s %s, %s: %s shows once"):format(prof, e.name, tostring(group.title), key))
					end
					seen[key] = true
				end
			end
		end
	end
end)

return T.done()
