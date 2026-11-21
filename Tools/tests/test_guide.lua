-- The Leveling Guide's core rule, on the plugin's real Plan.lua, Calc.lua and Where.lua over its
-- real data files, with a mocked game: a step only uses a recipe while it is orange or yellow at
-- that skill, whatever the goal; a profit never makes a low chance the better pick; for a recipe
-- you know, the game's own color now overrules the data; and where nothing is orange or yellow the
-- step says so (low), or, under one craft in five, there is no step at all (a gap line).
-- A few fixed cases; the whole space is played by the simulation harness the fix was built with
-- (not in the repo: 3,997,080 failures before the fix, none after).
-- luacheck: globals GAME NS ADDON_ROOT DaylightRecipesDB C_TradeSkillUI GetItemInfo UnitFactionGroup wipe bit
-- luacheck: read globals T
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Plan.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Plan.lua not found")

-- ---- the game ----------------------------------------------------------------------------------
local W = { known = {}, color = {}, ah = {}, sell = {} }   -- the world now
function UnitFactionGroup() return "Alliance" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
bit = nil
function GetItemInfo(id) return "Item" .. id, nil, 1, nil, nil, nil, nil, nil, nil, nil, W.sell[id], nil, nil, 0 end

-- ---- the plugin: its own namespace, its real data and guide files -------------------------------
local ns = { ok = true, state = {} }
local S = ns.state
local function load(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	assert(loadstring(src, "@" .. file))("DaylightRecipes", ns)
end
load("Locales/Locales.lua")
-- (In the .toc's order: Data/Client.lua, the recipes and threshold corrections read from the client, after Sources.)
for _, f in ipairs({ "Recipes", "Sources", "Client", "Npcs", "Polestar", "Corrections", "Disenchant" }) do load("Data/" .. f .. ".lua") end

-- A recipe's thresholds as the plugin has them (orange from, yellow from, green from, gray from):
-- the data's, with Calc.lua's corrections. (Calc is loaded below; asked only in the cases.)
local function Data(spell) return ns.Calc.Thresholds(spell) or ns.Recipes[spell][2] end
-- The mocked game's color for a recipe you know (0 orange, 1 yellow, 2 green, 3 gray): the data's,
-- unless the case says otherwise (W.color[spell]).
local function GameColor(spell, skill)
	if W.color[spell] then return W.color[spell] end
	local t = Data(spell)
	if skill >= t[4] then return 3 end
	if skill >= t[3] then return 2 end
	if skill >= t[2] then return 1 end
	return 0
end
C_TradeSkillUI = {
	GetAllRecipeIDs = function()
		local out = {}
		for id in pairs(W.known) do out[#out + 1] = id end
		return out
	end,
	GetRecipeInfo = function(id)
		if not W.known[id] then return { learned = false, canSkillUp = false, numSkillUps = 0 } end
		local color = GameColor(id, S.skill)
		local can = color ~= 3 and not (S.max > 0 and S.skill >= S.max)
		return { learned = true, relativeDifficulty = color, canSkillUp = can, numSkillUps = can and 1 or 0 }
	end,
}
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
ns.SpellName = function(id) return ns.RecipeNames[id] or ("Spell" .. id) end
ns.Fold = function(s) return type(s) == "string" and s:lower() or "" end
ns.Changed = function() end
ns.Print = function() end
local char = { targets = {}, plans = {} }
ns.Store = {
	version = 0,
	Char = function() return char end,
	Count = function() return { mine = 0, bags = 0, bank = 0, mail = 0, alts = {}, altTotal = 0 } end,
	WhoKnows = function() return {} end,
	SeenVendor = function() return nil end,
	SaveKnown = function() end,
}
-- Every material is on the Auction House at 1s, unless the case prices it (W.ah).
ns.Prices = {
	Mogul = function() return false end,
	Has = function() return true end,
	Get = function(id) return W.ah[id] or 100 end,
}
load("Calc.lua")
load("Where.lua")
load("Plan.lua")
local Calc, Plan = ns.Calc, ns.Plan
Calc.Talents = function() return 0, 0, { overtime = 0, overtimeRank = 0, bartering = 0, barteringRank = 0 } end

local FIRST_AID, MINING = 129, 186
local LESSER_HEALING = 1244432         -- Lesser Healing Potion (First Aid): {55, 85, 105, 125}
T.eq(Data(LESSER_HEALING)[3], 105, "(the data: Lesser Healing Potion is green from 105)")
T.eq(Data(LESSER_HEALING)[4], 125, "(and gray from 125)")

-- A character: this profession at this skill and cap, knowing every recipe of it learnable by then
-- (known = false: none), aiming for `target`, with this goal.
local function at(line, skill, cap, target, goal, known)
	S.line, S.name, S.skill, S.max, S.linked = line, "Profession", skill, cap, false
	W.known, W.color = {}, {}
	if known ~= false then
		for spell, data in pairs(ns.Recipes) do
			if data[1] == line and type(data[2]) == "table" and (data[2][1] or 0) <= skill then W.known[spell] = true end
		end
	end
	char.targets[line] = target
	DaylightRecipesDB = { routeGoal = goal }
	ns.Store.version = ns.Store.version + 1
	Calc.Forget()
	Plan.Forget()
end
local function crafts(route)
	local out = {}
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" then out[#out + 1] = s end
	end
	return out
end
-- Orange or yellow at a skill, by the data.
local function Good(spell, k) return k < Data(spell)[3] end
-- What a route must hold to: a step not marked low uses its recipe only while it is orange or
-- yellow, and asks for no more than two crafts a point; one marked low never under one in five.
local function sound(route, what)
	for _, s in ipairs(crafts(route)) do
		for k = s.from, s.to - 1 do
			if not s.low then
				T.ok(Good(s.spell, k), ("%s: %s at %d is orange or yellow (step %d to %d)"):format(what, ns.SpellName(s.spell), k, s.from, s.to))
			else
				local chance = Calc.Chance(s.spell, k, 0)
				T.ok(chance >= 0.2 - 1e-9, ("%s: the green step's %s at %d gives a point at least one craft in five"):format(what, ns.SpellName(s.spell), k))
			end
		end
		if not s.low and s.to > s.from then
			T.ok(s.crafts / (s.to - s.from) <= 2 + 1e-6, ("%s: %s asks for no more than two crafts a point"):format(what, ns.SpellName(s.spell)))
		end
	end
end

-- ---- the owner's case: First Aid 83, Auction House goal ------------------------------------------
-- (The potion sells well above its materials: the goal that used to run it down to a 10% chance.)
W.sell[858] = 300
T.case("First Aid 83, Auction House: no step uses Lesser Healing Potion past its yellow range", function()
	for _, goal in ipairs({ "auction", "vendor", "disenchant", "cost" }) do
		at(FIRST_AID, 83, 150, 150, goal)
		W.ah[858] = 2000            -- the potion: 20s each on the Auction House, its materials 4s
		Calc.Forget()
		Plan.Forget()
		local plan = Plan.Get()
		T.ok(plan and #crafts(plan.route) > 0, goal .. ": there is a route")
		for _, s in ipairs(crafts(plan.route)) do
			if s.spell == LESSER_HEALING then
				T.ok(s.to <= 105, goal .. ": Lesser Healing Potion is not made past 105, where it turns green (to " .. s.to .. ")")
				T.ok(s.crafts < 60, goal .. ": nor a hundred times")
			end
		end
		sound(plan.route, goal)
		W.ah[858] = nil
	end
end)

T.case("a profit at a low chance never outranks a recipe that gives points", function()
	-- At 110 the potion is green (37%); its profit is large; other First Aid recipes are orange or
	-- yellow there.
	at(FIRST_AID, 110, 150, 150, "auction")
	W.ah[858] = 2000
	Calc.Forget()
	Plan.Forget()
	local plan = Plan.Get()
	local first = crafts(plan.route)[1]
	T.ok(first ~= nil, "there is a step")
	T.ok(first.spell ~= LESSER_HEALING, "the step at 110 is not the green potion, however well it sells")
	T.ok(not first.low, "it is a recipe that gives points: not marked green")
	T.ok(Good(first.spell, 110), "orange or yellow at 110")
	for _, row in ipairs(Plan.CraftNext(5)) do
		T.ok(row.spell ~= LESSER_HEALING, "Craft Next does not offer the green potion while others give points")
	end
	for _, alt in ipairs(first.alts or {}) do
		T.ok(alt.spell ~= LESSER_HEALING and Good(alt.spell, 110), "nor does Or Instead")
	end
	W.ah[858] = nil
end)

T.case("a recipe you know that the game shows gray is never the step you're on", function()
	at(FIRST_AID, 83, 150, 150, "cost")
	local plan = Plan.Get()
	local was = crafts(plan.route)[1].spell
	T.eq(Plan.CurrentSpell(), was, "the step you're on, by the data")
	-- (The data says orange or yellow; the game, for this known recipe, says gray.)
	W.color[was] = 3
	Calc.Forget()
	Plan.Forget()
	plan = Plan.Get()
	local now = crafts(plan.route)[1]
	T.ok(now.spell ~= was, "with the game showing it gray, another recipe is the step")
	T.ok(Plan.CurrentSpell() ~= was, "and the mark is not on it")
	for _, s in ipairs(crafts(plan.route)) do
		T.ok(s.spell ~= was, "it is in no step at all: gray today is not yellow later")
	end
	-- Green in the game, with others orange or yellow: not used either.
	W.color[was] = 2
	Calc.Forget()
	Plan.Forget()
	plan = Plan.Get()
	T.ok(crafts(plan.route)[1].spell ~= was, "shown green while another gives points: not the step either")
	-- The game's word comes with a skill-up: the route worked out before is worked out again.
	at(FIRST_AID, 83, 150, 150, "cost")
	plan = Plan.Get()
	was = crafts(plan.route)[1].spell
	S.skill = 84
	W.color[was] = 3
	plan = Plan.Get()
	T.ok(crafts(plan.route)[1].spell ~= was, "a point on, the game shows it gray: the route is worked out again without it")
end)

T.case("where nothing is orange or yellow: a step marked green, or a gap line, never a silent grind", function()
	-- Every profession from 1 to 300 and from its last stretch, all four goals: each step holds to
	-- the rule, and the marked steps and gap lines are where the data has nothing better.
	local low, gaps, rare = 0, 0, 0
	for _, line in ipairs({ FIRST_AID, MINING, 164, 165, 171, 185, 197, 202, 333 }) do
		for _, start in ipairs({ { 1, 75 }, { 260, 300 } }) do
			for _, goal in ipairs({ "cost", "auction" }) do
				at(line, start[1], start[2], 300, goal)
				local ok, plan = pcall(Plan.Get)
				T.ok(ok and plan ~= nil, ("profession %d from %d (%s): a plan (%s)"):format(line, start[1], goal, tostring(plan)))
				sound(plan.route, ("profession %d from %d (%s)"):format(line, start[1], goal))
				for _, s in ipairs(plan.route.steps) do
					if s.kind == "craft" and s.low then
						low = low + 1
						T.ok(not Good(s.spell, s.from), "a step marked green is on a recipe that is green there")
					elseif s.kind == "gap" then
						gaps = gaps + 1
						if s.rare then rare = rare + 1 end
						T.ok(type(s.at) == "number" and type(s.to) == "number" and s.to > s.at, "a gap line says from where to where")
					end
				end
			end
		end
	end
	T.ok(low > 0, "some stretches have only green recipes: their steps are marked (" .. low .. ")")
	T.ok(gaps > 0, "and some have nothing worth a step: a gap line (" .. gaps .. ", " .. rare .. " of them for a chance under one in five)")
end)

T.case("a gap line stays after a skill-up inside it", function()
	-- Find a gap from 1 to 300, stand inside it a point further on: it is still said.
	for _, line in ipairs({ MINING, FIRST_AID, 164, 165, 171, 185, 197, 202, 333 }) do
		at(line, 260, 300, 300, "cost")
		local plan = Plan.Get()
		local gap
		for _, s in ipairs(plan.route.steps) do
			if s.kind == "gap" and s.to - s.at >= 2 then gap = s end
		end
		if gap then
			at(line, gap.at, 300, 300, "cost")
			Plan.Get()
			S.skill = gap.at + 1
			plan = Plan.Get()
			local still = false
			for _, s in ipairs(plan.route.steps) do
				if s.kind == "gap" then still = true end
			end
			T.ok(still, ("profession %d: one point into the gap at %d, the line is still there"):format(line, gap.at))
			return
		end
	end
	error("no gap of two points or more in any profession: the case has nothing to stand on")
end)

T.case("the first yellow point is still a sure point", function()
	at(FIRST_AID, 85, 150, 150, "cost", false)
	local chance = Calc.Chance(LESSER_HEALING, 85, 0)
	T.eq(chance, 1, "Lesser Healing Potion at 85, its first yellow point: 100%")
	T.ok(Calc.Chance(LESSER_HEALING, 95, 0) < 1, "inside the yellow range: less")
	T.eq((Calc.Chance(LESSER_HEALING, 125, 0)), 0, "gray: none")
end)

return T.done()
