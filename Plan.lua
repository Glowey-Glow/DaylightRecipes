-- The plan for the open profession: what to craft next, the cheapest way to your target skill, and
-- what that takes.
--   Craft next: your recipes that still give points now, cheapest expected cost per point first
--               (the game's own color and points per craft for each).
--   The route:  for every skill point from yours to the target, the recipe with the cheapest
--               expected cost per point at that skill, among the ones you know and the ones a
--               trainer will teach by then (its training cost spread over the points it's useful
--               for) that give a point at least every other craft there (orange or yellow). The
--               chance at each skill comes from its thresholds, so a yellow one counts its misses:
--               the crafts are what you can expect to make, not one per point. Only where nothing
--               gives a point that often does it take a recipe that gives one less often, and the
--               step says so. For a recipe you know, the game's own color at your skill overrules
--               the data. At a rank cap it stops for the next rank. Points in a row on one recipe
--               make a step.
--   Shopping:   what the route's crafts use, less what the route itself makes on the way (bars,
--               bolts), split into what's in your bags, bank and mail, what your alts on this realm
--               hold, and what's left to buy, with its price.
-- Worked out when asked for and kept until something it depends on changes (the skill, the cap,
-- the target, a recipe learned, prices).
local _, ns = ...
if not ns.ok then return end
local L = ns.L

local Plan = {}
ns.Plan = Plan

local Calc = ns.Calc
local S = ns.state
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local RANK_CAPS = { 75, 150, 225, 300 }
local RANK_NAMES = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }   -- kept in saved plans
local RANK_SHOWN = { [75] = L["Apprentice"], [150] = L["Journeyman"], [225] = L["Expert"], [300] = L["Artisan"] }
local RANK_LEVEL = { [150] = 10, [225] = 20, [300] = 35 }   -- the character level each rank asks
local TOP = 300
local UNPRICED = 1e9          -- added to a recipe's cost per point when a material has no price

-- ---------------------------------------------------------------------------------------------
-- Targets: per character and profession
-- ---------------------------------------------------------------------------------------------

-- The skills worth aiming for from here: each rank cap above your skill, up to the top.
function Plan.Targets()
	local out = {}
	for _, cap in ipairs(RANK_CAPS) do
		if cap > (S.skill or 0) then out[#out + 1] = cap end
	end
	return out
end

function Plan.Target()
	local c = ns.Store.Char()
	local saved = c and c.targets and c.targets[S.line]
	local skill = S.skill or 0
	if type(saved) == "number" and saved > skill then return saved end
	-- Your cap, or the next rank's once you're at it.
	local cap = S.max or 0
	if cap > skill then return cap end
	return min(TOP, max(cap, skill) + 75)
end

function Plan.SetTarget(v)
	local c = ns.Store.Char()
	if not c or not S.line then return end
	c.targets = c.targets or {}
	c.targets[S.line] = v
	ns.Changed()
end

-- ---------------------------------------------------------------------------------------------
-- What the route aims for
-- ---------------------------------------------------------------------------------------------
-- Its goal: the cheapest materials (as it was), or the least it costs once the crafts are vendored,
-- disenchanted or sold on the Auction House (each craft's value taken off its materials' cost).
-- Kept per account (DaylightRecipesDB.routeGoal).

Plan.GOALS = { "cost", "vendor", "disenchant", "auction" }
Plan.GOAL_WORDS = { cost = L["Cheapest"], vendor = L["Vendor"], disenchant = L["Disenchant"], auction = L["Auction House"] }
Plan.GOAL_LONG = { cost = L["cheapest materials"], vendor = L["after vendoring what you make"],
	disenchant = L["after disenchanting what you make"], auction = L["after selling what you make"] }

function Plan.Goal()
	local db = DaylightRecipesDB
	local g = type(db) == "table" and db.routeGoal or nil
	return Plan.GOAL_WORDS[g] and g or "cost"
end

function Plan.SetGoal(g)
	if not Plan.GOAL_WORDS[g] then return end
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	DaylightRecipesDB.routeGoal = g
	Plan.Forget()
	ns.Changed()
end

-- A recipe "gives skill-ups" at a skill while the game shows it orange or yellow there: a sure point,
-- then a chance that runs down to one craft in two. Green runs from there down to none ("sometimes a
-- skill point"), gray gives none. Whatever the goal, the route and Craft Next only take a green
-- recipe where nothing you know or can learn is orange or yellow, and then say so. So no step asks
-- for more than two crafts a point unless it is marked as a low chance.
local YELLOW, GREEN = 2, 3    -- Calc.Step's colors: 1 orange, 2 yellow, 3 green, 4 gray
-- A green recipe is only planned while it still gives a point one craft in five: under that the
-- guide says that nothing gives points often enough there, rather than ask for dozens of crafts
-- (and their materials) for one point.
local RARE = 0.2
local WILD_MARGIN = 6         -- a value over 6x the materials (a 500% margin) is taken for a bad price
local SWITCH = 0.05           -- a step's recipe gives way only to one this much cheaper a point

-- Recipes left out of every route: ones on a cooldown (a route can't wait days between crafts) and
-- the holiday ones (their materials and vendors are only there for a few weeks a year).
local EXCLUDE = { "^Transmute", "Mooncloth$", "Campfire", "Firework", "Winter Veil", "Gingerbread", "Egg Nog",
	"Smokywood", "Snowball", "Holiday", "Hallow" }
local excluded = {}
local function Excluded(spell)
	local v = excluded[spell]
	if v ~= nil then return v end
	v = false
	-- (Data/Client.lua's recipes say so themselves.)
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if meta and meta.cooldown then v = true end
	local name = ns.RecipeNames and ns.RecipeNames[spell]
	if type(name) == "string" then
		for _, pattern in ipairs(EXCLUDE) do
			if string.find(name, pattern) then v = true break end
		end
	end
	excluded[spell] = v
	return v
end

-- ---------------------------------------------------------------------------------------------
-- Tools the recipes need (Enchanting's rods, Engineering's tools)
-- ---------------------------------------------------------------------------------------------
-- The recipe data doesn't say which recipe needs which tool: the game's own list of a recipe's
-- requirements does (GetRecipeRequirements), and where it says nothing, an enchant needs the best
-- rod there is at the skill it's learned at (Copper from the start, Silver from 100, Golden from 150,
-- Truesilver from 200). A route that picks a recipe needing a tool you haven't got makes the tool
-- first (the step before), so the guide never sends you to an enchant you can't cast.

local TOOLS = {
	[333] = { { spell = 7421, item = 6218, at = 1 }, { spell = 7795, item = 6339, at = 100 },
		{ spell = 13628, item = 11130, at = 150 }, { spell = 13702, item = 11145, at = 200 } },
	[202] = { { spell = 7430, item = 6219, at = 50 }, { spell = 12590, item = 10498, at = 175 } },
}
local isTool = {}
for _, list in pairs(TOOLS) do
	for _, tool in ipairs(list) do isTool[tool.spell] = tool end
end

-- The game's list gives the tool's name in the client's language, so the names matched are the
-- game's too (the rod's recipe and the rod itself), folded the same way on both sides. An item name
-- the game hasn't cached yet leaves the table to be made again on the next ask.
local toolNames     -- folded name -> tool
local toolNamesWhole = false
local function ToolByName(name)
	if not toolNames or not toolNamesWhole then
		toolNames, toolNamesWhole = {}, true
		for _, tool in pairs(isTool) do
			local a = ns.SpellName(tool.spell)
			local b
			if C_Item and C_Item.GetItemNameByID then
				local ok, n = pcall(C_Item.GetItemNameByID, tool.item)
				if ok then b = n end
			end
			if not b and GetItemInfo then b = GetItemInfo(tool.item) end
			if not b then
				toolNamesWhole = false
				b = ns.ItemNames and ns.ItemNames[tool.item]
			end
			if a then toolNames[ns.Fold(a)] = tool end
			if b then toolNames[ns.Fold(b)] = tool end
		end
	end
	return type(name) == "string" and toolNames[ns.Fold(name)] or nil
end

local toolOf = {}   -- spell -> its tool, or false
local function ToolFor(spell, data, learnAt)
	local v = toolOf[spell]
	if v ~= nil then return v or nil end
	v = false
	local tools = TOOLS[data[1]]
	if tools and not isTool[spell] then
		local reqs = ns.Ask("GetRecipeRequirements", spell)
		if type(reqs) == "table" then
			for _, r in ipairs(reqs) do
				local tool = type(r) == "table" and ToolByName(r.name)
				if tool then v = tool break end
			end
		end
		-- (An enchant the list names no rod for, whether it's empty or only names something else,
		-- such as a place: the best rod there is at the skill it's learned at.)
		if not v and data[1] == 333 and data[4] == false then
			for _, tool in ipairs(tools) do
				if tool.at <= (learnAt or 0) then v = tool end
			end
		end
	end
	toolOf[spell] = v
	return v or nil
end

-- (Store.Count goes through your bags, bank, mail and every alt, and a route asks about the same
-- few tools at every point for every recipe, twice over. Plan.Get starts each working-out with an
-- empty `holding`, so each tool is counted once a working-out; nothing else asks Owns.)
local holding = {}    -- tool -> whether you have one, for the working-out under way
local function Owns(tool)
	local v = holding[tool]
	if v == nil then
		v = (ns.Store and ns.Store.Count(tool.item).mine > 0) or false
		holding[tool] = v
	end
	return v
end

-- ---------------------------------------------------------------------------------------------
-- The recipes the plan can use
-- ---------------------------------------------------------------------------------------------

-- The cheapest of a recipe's trainers you can reach (your faction's): copper, or nil.
local function TrainerCost(spell)
	local list = ns.Trainers and ns.Trainers[spell]
	if type(list) ~= "table" then return nil end
	local best
	for _, rec in ipairs(list) do
		if type(rec) == "table" and ns.Where.Npc(rec[1]) then
			local copper = type(rec[2]) == "number" and rec[2] or 0
			if not best or copper < best then best = copper end
		end
	end
	return best
end

-- itemID -> { spell, ... }: the recipes that make an item (made once).
local makers
local function Makers(itemID)
	if not makers then
		makers = {}
		for spell, data in pairs(ns.Recipes or {}) do
			local out = data[4]
			if type(out) == "table" and out[1] then
				local list = makers[out[1]] or {}
				makers[out[1]] = list
				list[#list + 1] = spell
			end
		end
	end
	return makers[itemID]
end

-- One material's price for the route: the cheaper of buying it and making it with a recipe of this
-- profession you know (a bolt from cloth, a bar from ore), one level down.
local function MatUnit(itemID, known, depth)
	local best = Calc.Unit(itemID)
	if depth > 0 then
		for _, spell in ipairs(Makers(itemID) or {}) do
			local data = ns.Recipes[spell]
			if known[spell] and data and data[1] == S.line then
				local total, ok = 0, true
				for _, m in ipairs(Calc.Materials(spell)) do
					local u = MatUnit(m[1], known, depth - 1)
					if not u then ok = false break end
					total = total + u * m[2]
				end
				local _, each = Calc.Output(spell)
				local unit = total / max(1, each or 1)
				if ok and (not best or unit < best) then best = unit end
			end
		end
	end
	return best
end

-- What one craft is worth for the route's goal (nothing for "cheapest materials"); a disenchant
-- goal falls back on the vendor for what can't be disenchanted.
local function Value(spell, goal)
	if goal == "cost" then return 0 end
	local w = Calc.Worth(spell)
	if not w then return 0 end
	local want = goal == "vendor" and "Vendor" or goal == "disenchant" and "Disenchant" or "Auction House"
	-- (Calc's labels, in English or shown in the player's language.)
	local shown = Plan.GOAL_WORDS[goal]
	local vendor
	for _, r in ipairs(w.routes) do
		if r.label == want or r.label == shown then return r.value end
		if r.label == "Vendor" or r.label == L["Vendor"] then vendor = r.value end
	end
	if goal == "disenchant" and vendor then return vendor end
	return 0
end

-- At your rank's cap nothing can give a point until the next rank is trained, and the game may show
-- every recipe as giving none: its word on a recipe is not taken there.
local function Capped()
	return (S.max or 0) > 0 and (S.skill or 0) >= S.max
end

-- { spell, t (thresholds), cost (per craft, after its value), mats (its materials' cost), complete,
-- known, learnAt, learnCost, source ("trainer", "vendor", "auction", "unknown"), ups, tool, live } for every
-- recipe of the open profession the plan can use. credit: itemID -> price, for what the route itself
-- needs (a recipe making one is worth what it saves buying). For a recipe you know, the game's own
-- word at your skill now, nil when the game doesn't say: liveStep (its color, Calc.Step) and live
-- (its chance of a point by that color, Calc.Chance).
local function Candidates(goal, credit)
	local out = {}
	local known = ns.Where.KnownSet()
	local mine = ns.Faction()
	local capped = Capped()
	for spell, data in pairs(ns.Recipes or {}) do
		if data[1] == S.line and not Excluded(spell) then
			local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
			local variant = meta and meta.variantFaction
			local t = Calc.Thresholds(spell)
			if t and t[4] and t[4] > 0 and (not variant or variant == mine) then
				local isKnown = known[spell] or false
				local auto = ns.AutomaticRecipes and ns.AutomaticRecipes[spell]
				local learnCost, source
				if not isKnown and not auto then
					learnCost = TrainerCost(spell)
					if learnCost then
						source = "trainer"
					elseif meta and meta.trainerUnknown then
						-- (Taught by a trainer nobody has reported yet: planned, with no place or price.)
						learnCost, source = 0, "unknown"
					elseif data[5] then
						-- (A recipe item: from a vendor, or the Auction House.)
						local v = Calc.Vendor(data[5])
						local a = Calc.AH(data[5])
						if v and (not a or v <= a) then learnCost, source = v, "vendor"
						elseif a then learnCost, source = a, "auction" end
					end
				end
				if isKnown or auto or learnCost then
					local mats, complete = 0, true
					for _, m in ipairs(Calc.Materials(spell)) do
						local u = MatUnit(m[1], known, 1)
						if u then mats = mats + u * m[2] else complete = false end
					end
					local value = Value(spell, goal)
					local made, each = Calc.Output(spell)
					if credit and made and credit[made] then value = value + credit[made] * (each or 1) end
					-- (A value far beyond what goes in is a bad price, not a bargain: the recipe counts
					-- for its materials alone. It still gives its points.)
					if goal ~= "cost" and value > 0 and (mats <= 0 or value > mats * WILD_MARGIN) then value = 0 end
					local learnAt = ns.Where.Required(spell) or t[1] or 0
					local liveStep = isKnown and not capped and Calc.Step(spell) or nil
					local live = liveStep and Calc.Chance(spell, S.skill or 0) or nil
					out[#out + 1] = { spell = spell, t = t, cost = mats - value, mats = mats, complete = complete,
						known = isKnown or auto and true or false, learnAt = learnAt,
						learnCost = learnCost, source = source, ups = isKnown and Calc.SkillUps(spell) or 1,
						tool = ToolFor(spell, data, learnAt), live = live, liveStep = liveStep }
				end
			end
		end
	end
	return out
end

-- The chance of a point at skill k, from the thresholds (talents in).
local function ChanceAt(r, k, overtime)
	local t = r.t
	local yellow, grey = t[2], t[4]
	local base
	if k >= grey then
		base = 0
	elseif k < yellow then
		base = 1
	elseif grey <= yellow then
		base = 1
	else
		base = (grey - k) / (grey - yellow)
	end
	return min(1, base * (1 + overtime))
end

-- The skill a recipe turns green at by its thresholds (gray, for one that goes straight to gray):
-- up to there it is orange or yellow.
local function GoodTo(r)
	local t = r.t
	return min(t[3] or t[4], t[4])
end

-- ---------------------------------------------------------------------------------------------
-- Craft next
-- ---------------------------------------------------------------------------------------------

local function Craftable(spell)
	local n = ns.Ask("GetCraftableCount", spell)
	if type(n) == "number" then return n end
	local info = ns.Ask("GetRecipeInfo", spell)
	return type(info) == "table" and tonumber(info.numAvailable) or 0
end

-- { { spell, chance, perPoint (copper, nil when unpriced), cost, can (how many you can make now) } },
-- best first, at most `count`. Only recipes that are orange or yellow now; when none of yours is,
-- the green ones that come nearest the best chance there is (each with low = true).
-- (Asked on every draw of the Leveling Guide, and for the recipe list's mark: the list is kept
-- until the profession, skill, cap, known recipes, prices or the game's colors change; how many you
-- can make is asked again each time. Read-only to the callers.)
local nextKept = {}   -- count -> { key, list }
function Plan.CraftNext(count)
	local out = {}
	if not S.line or S.linked then return out end
	local known = ns.Where.KnownSet()
	local key = table.concat({ S.line, S.skill or 0, S.max or 0, Calc.version, Calc.liveVersion,
		ns.Store and ns.Store.version or 0, tostring(known) }, ":")
	local kept = nextKept[count or 5]
	if kept and kept[1] == key then
		for _, e in ipairs(kept[2]) do e.can = Craftable(e.spell) end
		return kept[2]
	end
	for spell in pairs(known) do
		local data = ns.Recipes and ns.Recipes[spell]
		if data and data[1] == S.line then
			local chance = Calc.Chance(spell, S.skill or 0, S.max)
			if chance and chance > 0 then
				local cost = Calc.Cost(spell)
				local points = chance * Calc.SkillUps(spell)
				-- (Its color: the game's own, else the data's.)
				local step = Calc.Step(spell)
				if not step then
					local t = Calc.Thresholds(spell)
					step = t and (S.skill or 0) >= min(t[3] or t[4], t[4]) and GREEN or YELLOW
				end
				out[#out + 1] = { spell = spell, chance = chance, step = step, cost = cost.total, complete = cost.complete,
					perPoint = cost.complete and cost.total / points or nil }
			end
		end
	end
	-- (A cheap recipe that hardly ever gives a point is no way to skill up: a green one is left out
	-- while another is orange or yellow. With none that is, those within half of the best chance.)
	local good, top = false, 0
	for _, e in ipairs(out) do
		if e.step <= YELLOW then good = true end
		top = max(top, e.chance)
	end
	for i = #out, 1, -1 do
		local e = out[i]
		if good and e.step > YELLOW or not good and e.chance < top / 2 then
			table.remove(out, i)
		elseif not good then
			e.low = true
		end
	end
	table.sort(out, function(a, b)
		if (a.perPoint ~= nil) ~= (b.perPoint ~= nil) then return a.perPoint ~= nil end
		if a.perPoint and b.perPoint and a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
		if a.chance ~= b.chance then return a.chance > b.chance end
		return a.spell < b.spell
	end)
	for i = #out, (count or 5) + 1, -1 do out[i] = nil end
	-- (Only the ones kept are asked how many you can make.)
	for _, e in ipairs(out) do e.can = Craftable(e.spell) end
	nextKept[count or 5] = { key, out }
	return out
end

-- ---------------------------------------------------------------------------------------------
-- The route
-- ---------------------------------------------------------------------------------------------

-- steps: { kind = "craft", spell, from, to, crafts, cost, complete, learn = copper or nil, source,
--          low = true (no recipe gives a point every other craft there: this one comes nearest),
--          alts = { { spell, perPoint }, ... } (the next best at the skill the step is cut to) }
--        { kind = "tool", spell, at, cost, complete, learn, source, item } (a rod or tool to make first)
--        { kind = "rank", at, cap, name, level }
--        { kind = "gap", at, to, rare } (no recipe in the data gives points from `at`, or with rare
--          only under one craft in five; planning goes on at `to`)
-- plus total (copper), complete, crafts.
--
-- At each point the recipes that are orange or yellow there are ranked by what a point costs, and
-- the cheapest is taken:
--   a cost:   the craft's cost over its chance (the misses are paid for too);
--   a profit: the craft's profit times its chance. A profit over the chance would grow as the chance
--             falls (a nearly gray recipe with a copper of profit would beat everything, and the step
--             would ask for hundreds of crafts), and the profit of crafts that give no point is no
--             reason to pick a recipe for skilling up. Times the chance, a profit counts for the
--             crafts that give the point: the same figure at a sure point, less the lower the chance.
-- Either way a better chance never ranks a recipe lower, and a cheaper craft never does.
-- Where no recipe is orange or yellow, the green one with the best chance there is taken (the cheapest
-- of them, when several share it), and the step is marked low; where even the best is under one craft in five (RARE),
-- no step is made at all (a gap). The costs shown (a step's, an alternative's a point) are the real
-- expected ones, not the ranking's.
-- A working-out spread over frames (Plan.Warm): inside its coroutine, Route gives the frame back
-- once it has used SLICE_MS of it, and goes on the next frame. Called anywhere else (Plan.Get, the
-- tests), it never yields: the route is worked out at once, as before.
local SLICE_MS = 4
local function Clock()
	local f = _G.debugprofilestop
	return f and f() or os.clock() * 1000
end
local sliceCo, sliceFrom
local function Slice()
	if not sliceCo or coroutine.running() ~= sliceCo then return end
	local now = Clock()
	if now - sliceFrom >= SLICE_MS then
		coroutine.yield()
		sliceFrom = Clock()
	end
end

local function Route(from, target, cap, goal, credit)
	local cands = Candidates(goal, credit)
	local bySpell = {}
	local overtime = (ns.Get("talents") and Calc.Talents()) or 0
	for _, r in ipairs(cands) do
		bySpell[r.spell] = r
		r.goodTo = GoodTo(r)
	end
	local steps = {}
	local learned = {}
	local owned = {}
	local k = from
	local guard = 0

	-- A recipe's chance of a point at a skill. For one you know, the game's own color at your skill
	-- now stands in for the data there, and the chance never rises with skill: one the game shows
	-- green or gray today is not planned as yellow tomorrow on the data's word.
	local function Chance(r, at)
		local p = ChanceAt(r, at, overtime)
		local live = r.live
		if live then
			if at <= from then return live end
			if live < p then return live end
		end
		return p
	end

	-- Whether a recipe is orange or yellow at a skill: by the game's color at your skill now for one
	-- you know (green today is never yellow later), by its thresholds from there on.
	local function Good(r, at)
		local step = r.liveStep
		if step then
			if step >= GREEN then return false end
			if at <= from then return true end
		end
		return at < r.goodTo
	end

	-- A recipe's cost a point at k (nil: it can't be used there): for ranking, and as shown.
	local function Score(r, p, low)
		local have = r.known or learned[r.spell]
		local each = r.complete and r.cost or (r.cost + UNPRICED)
		local points = p * r.ups
		local shown = each / points
		local rank = each >= 0 and shown or each * points
		-- Learning it now is spread over the points it can still give (while orange or yellow).
		local useful = max(1, min(low and r.t[4] or r.goodTo, target) - k)
		local extra = 0
		if not have and r.learnCost and r.learnCost > 0 then extra = r.learnCost / useful end
		-- So is the tool it needs, when you haven't got it.
		local tool = r.tool
		if tool and not owned[tool] and not Owns(tool) then
			local made = bySpell[tool.spell]
			if not made or not (made.known or learned[made.spell] or made.learnAt <= k) then return nil end
			extra = extra + (made.mats + ((made.known or learned[made.spell]) and 0 or (made.learnCost or 0))) / useful
		end
		return rank + extra, shown + extra
	end

	while k < target and guard < 600 do
		guard = guard + 1
		Slice()
		if cap > 0 and k >= cap then
			if cap >= TOP then break end
			local nextCap = cap + 75
			for _, c in ipairs(RANK_CAPS) do if c > cap then nextCap = c break end end
			steps[#steps + 1] = { kind = "rank", at = k, cap = nextCap, name = RANK_SHOWN[nextCap], level = Plan.RankLevel(nextCap) }
			cap = nextCap
		else
			-- The cheapest three a point here (the best and the next two, for the alternatives), among
			-- the orange and yellow ones; with none, among the green ones with the best chance there is.
			local top = {}
			local scoreOf = {}
			local low = false
			local function Rank(least)
				for _, r in ipairs(cands) do
					local have = r.known or learned[r.spell]
					if (have or r.learnAt <= k) and not isTool[r.spell] and (low or Good(r, k)) then
						local p = Chance(r, k)
						if p > 0 and p >= least then
							local s, shown = Score(r, p, low)
							if s then
								scoreOf[r] = { s, p }
								local i = #top + 1
								while i > 1 and top[i - 1][2] > s do i = i - 1 end
								if i <= 3 then
									table.insert(top, i, { r, s, p, shown })
									top[4] = nil
								end
							end
						end
					end
				end
			end
			Rank(0)
			local most = 0
			if #top == 0 then
				-- (The best chance there is among the ones usable here: a tool that can't be made yet
				-- rules a recipe out, so it's found by ranking them all once.)
				low = true
				Rank(0)
				for _, v in pairs(scoreOf) do most = max(most, v[2]) end
				top, scoreOf = {}, {}
				-- (Only the ones with that best chance: the step says nothing does better, so nothing may.)
				if most >= RARE then Rank(most - 1e-9) end
			end
			if #top == 0 then
				-- Nothing gives points here: said, and planning goes on where something does.
				local nextAt
				for _, r in ipairs(cands) do
					if not isTool[r.spell] and r.learnAt > k and r.learnAt < target and (not nextAt or r.learnAt < nextAt)
						and ChanceAt(r, r.learnAt, overtime) > 0 then
						nextAt = r.learnAt
					end
				end
				-- (rare: recipes do give points here, but under one craft in five.)
				steps[#steps + 1] = { kind = "gap", at = k, to = nextAt or target, rare = most > 0 or nil }
				if not nextAt then break end
				k = nextAt
			else
				local best, bestScore, bestChance = top[1][1], top[1][2], top[1][3]
				-- The step's recipe stays unless another is clearly cheaper (no flip-flopping). Only
				-- while it is still among the ones ranked here: never held into a low chance.
				local last = steps[#steps]
				if last and last.kind == "craft" and last.spell ~= best.spell and (last.low or false) == low then
					local cur = bySpell[last.spell]
					local held = cur and scoreOf[cur]
					if held and held[1] <= bestScore + math.abs(bestScore) * SWITCH then
						best, bestChance = cur, held[2]
					end
				end
				-- Its tool first, when you haven't got it.
				local tool = best.tool
				if tool and not owned[tool] and not Owns(tool) then
					local made = bySpell[tool.spell]
					local have = made.known or learned[made.spell]
					steps[#steps + 1] = { kind = "tool", spell = tool.spell, item = tool.item, at = k,
						unit = made.mats, complete = made.complete,
						learn = (not have) and (made.learnCost or 0) or nil, source = (not have) and made.source or nil }
					if not have then learned[made.spell] = true end
					owned[tool] = true
					last = nil
				end
				local expect = 1 / (bestChance * best.ups)
				if not (last and last.kind == "craft" and last.spell == best.spell and (last.low or false) == low) then
					local have = best.known or learned[best.spell]
					last = { kind = "craft", spell = best.spell, from = k, to = k, exp = {}, alts = {}, low = low or nil,
						unit = best.cost, complete = best.complete,
						learn = (not have) and (best.learnCost or 0) or nil, source = (not have) and best.source or nil }
					steps[#steps + 1] = last
					if not have then learned[best.spell] = true end
				end
				-- (Each point's expected crafts kept: a skill-up trims the route rather than redo it.
				-- So are the next best at each point: the ones offered instead are the ones that are
				-- good at the skill you're at, not at the skill the step began.)
				local alts = {}
				for i = 1, #top do
					if top[i][1] ~= best and #alts < 2 then alts[#alts + 1] = { spell = top[i][1].spell, perPoint = top[i][4],
						complete = top[i][1].complete } end
				end
				last.alts[k] = alts
				last.exp[k] = expect
				last.to = k + 1
				k = k + 1
			end
		end
	end
	return { steps = steps, from = from }
end

-- The route from `skill` on: the steps already behind you dropped, the one you're in cut to the
-- points left (its crafts are the sum of those points' own), then counted and priced. A tool you've
-- made since is dropped too.
local function Trim(full, skill)
	local steps, total, complete, crafts = {}, 0, true, 0
	for _, s in ipairs(full.steps) do
		if s.kind == "craft" then
			if s.to > skill then
				local from = max(s.from, skill)
				local expect = 0
				for k = from, s.to - 1 do expect = expect + (s.exp[k] or 0) end
				local count = ceil(expect - 0.05)
				local step = { kind = "craft", spell = s.spell, from = from, to = s.to, crafts = expect, count = count,
					unit = s.unit, cost = count * s.unit, complete = s.complete, learn = s.learn, source = s.source,
					low = s.low, alts = s.alts[from] or {} }
				steps[#steps + 1] = step
				total = total + step.cost + (step.learn or 0)
				crafts = crafts + count
				if not s.complete then complete = false end
			end
		elseif s.kind == "tool" then
			local tool = isTool[s.spell]
			if s.at >= skill and not (tool and Owns(tool)) then
				local step = { kind = "tool", spell = s.spell, item = s.item, at = s.at, from = s.at, to = s.at, count = 1,
					unit = s.unit, cost = s.unit, complete = s.complete, learn = s.learn, source = s.source }
				steps[#steps + 1] = step
				total = total + step.cost + (step.learn or 0)
				crafts = crafts + 1
				if not s.complete then complete = false end
			end
		elseif s.at >= skill then
			steps[#steps + 1] = s
		elseif s.kind == "gap" and s.to > skill then
			-- (A gap you're inside of is still one: said from your skill on.)
			steps[#steps + 1] = { kind = "gap", at = skill, to = s.to, rare = s.rare }
		end
	end
	return { steps = steps, total = total, complete = complete, crafts = crafts }
end

-- ---------------------------------------------------------------------------------------------
-- Shopping
-- ---------------------------------------------------------------------------------------------

-- Who on your account can make an item: { names }, or nil.
function Plan.MadeBy(itemID)
	local list = Makers(itemID)
	if not list then return nil end
	local seen, out = {}, {}
	for _, spell in ipairs(list) do
		for _, name in ipairs(ns.Store.WhoKnows(spell)) do
			if not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	return #out > 0 and out or nil
end

-- rows: { itemID, need, have (Store.Count), short (after your own), buy (after alts too), unit,
-- kind, cost } most expensive first; plus buyTotal, complete.
local function Shopping(route)
	local need, made = {}, {}
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" or s.kind == "tool" then
			for _, m in ipairs(Calc.Materials(s.spell)) do
				need[m[1]] = (need[m[1]] or 0) + m[2] * s.count
			end
			local out, each = Calc.Output(s.spell)
			if out then made[out] = (made[out] or 0) + floor((each or 1) * s.count) end
		end
	end
	local rows, buyTotal, complete = {}, 0, true
	for itemID, n in pairs(need) do
		local net = n - (made[itemID] or 0)
		if net > 0 then
			local have = ns.Store.Count(itemID)
			local short = max(0, net - have.mine)
			-- (What this character lacks is bought: an alt holding some is only mentioned.)
			local buy = short
			local unit, kind, who = Calc.Unit(itemID)
			local row = { itemID = itemID, need = net, have = have, short = short, buy = buy, unit = unit, kind = kind,
				vendor = kind == "vendor" and who or nil, makers = Plan.MadeBy(itemID) }
			if buy > 0 then
				if unit then
					-- (With the item's Auction House steps read: what `buy` of them really cost,
					-- step by step and a vendor's for the rest. Else the count times one's price.)
					row.cost, row.exact = Calc.BuyCost(itemID, buy)
					row.cost = row.cost or floor(unit * buy + 0.5)
					buyTotal = buyTotal + row.cost
				else
					complete = false
				end
			end
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b)
		local ac, bc = a.cost or 0, b.cost or 0
		if ac ~= bc then return ac > bc end
		return a.itemID < b.itemID
	end)
	return { rows = rows, buyTotal = buyTotal, complete = complete, need = need, made = made }
end

-- ---------------------------------------------------------------------------------------------
-- The whole plan, kept until it's out of date
-- ---------------------------------------------------------------------------------------------

local full, fullKey       -- the whole route from the skill it was worked out at
local kept, keptKey       -- the plan as shown (route trimmed to your skill, shopping)

function Plan.Forget()
	full, fullKey, kept, keptKey = nil, nil, nil, nil
end

-- The recipe the Leveling Guide's current step makes: nil when there's no plan, the goal is
-- reached, or the step is training the next rank.
function Plan.CurrentSpell()
	-- The guide is Professionally Lost's for this profession (ProfLost.lua): its step is the one
	-- lit, when the player asked for that and the recipe is one of ours; else nothing is.
	local P = ns.ProfLost
	if P and P.Handed and P.Handed("guide", S.line) then
		local theirs = P.Handed("step", S.line) and P.NextStepSpell and P.NextStepSpell(S.line) or nil
		return theirs and ns.Recipes and ns.Recipes[theirs] and theirs or nil
	end
	local ok, plan = pcall(Plan.Get)
	if not ok or type(plan) ~= "table" or (S.skill or 0) >= plan.target then return nil end
	for _, s in ipairs(plan.route.steps) do
		if s.kind == "rank" then return nil end
		if s.kind == "craft" or s.kind == "tool" then return s.spell end
	end
	return nil
end

-- The route's choice of recipes is made on one price an item (Calc.Unit). Its steps' costs and
-- its total, as shown, then follow the Auction House's price steps where those are known: each
-- step's materials are costed walking the steps cheapest first, the steps before it having taken
-- the cheapest ones (so step 1 isn't costed at the price step 3 will pay), a vendor's price for
-- what the Auction House has dearer. Only materials the route buys there: not ones it makes
-- itself, a vendor's, or ones whose steps weren't read (those keep the count times one's price).
local function Repriced(route)
	local made = {}
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" or s.kind == "tool" then
			local out = Calc.Output(s.spell)
			if out then made[out] = true end
		end
	end
	local taken = {}       -- itemID -> how many the steps so far use
	for _, s in ipairs(route.steps) do
		if (s.kind == "craft" or s.kind == "tool") and s.complete then
			local delta = 0
			for _, m in ipairs(Calc.Materials(s.spell)) do
				local itemID, n = m[1], m[2] * s.count
				if not made[itemID] and Calc.Steps(itemID) then
					local unit, kind = Calc.Unit(itemID)
					if unit and kind == "ah" then
						local cost = Calc.BuyCost(itemID, n, taken[itemID] or 0)
						if cost then delta = delta + cost - unit * n end
						taken[itemID] = (taken[itemID] or 0) + n
					end
				end
			end
			if delta ~= 0 then
				s.cost = s.cost + delta
				route.total = route.total + delta
			end
		end
	end
end

-- The whole route from `skill`. Twice: the first route says what it uses of things a recipe makes
-- (bolts, bars, vials); the second counts a recipe making one of those as worth what it saves buying it.
local function Build(skill, target, goal)
	local first = Route(skill, target, S.max or 0, goal, nil)
	local credit
	for _, st in ipairs(first.steps) do
		if st.kind == "craft" or st.kind == "tool" then
			for _, m in ipairs(Calc.Materials(st.spell)) do
				if Makers(m[1]) then
					local unit = Calc.Unit(m[1])
					if unit then
						credit = credit or {}
						credit[m[1]] = unit
					end
				end
			end
		end
	end
	return credit and Route(skill, target, S.max or 0, goal, credit) or first
end

-- Whether the game shows the recipe of the step `skill` is in gray, or green in a step not marked
-- low; or, in a step marked low, shows one of your recipes orange or yellow after all.
local function GameDisagrees(route, skill)
	if Capped() then return false end
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" and s.from <= skill and skill < s.to then
			local step = Calc.Step(s.spell)
			if step ~= nil and (step > GREEN or (step == GREEN and not s.low)) then return true end
			if s.low then
				for spell in pairs(ns.Where.KnownSet()) do
					local data = ns.Recipes[spell]
					if data and data[1] == S.line and not isTool[spell] and not Excluded(spell) then
						local color = Calc.Step(spell)
						if color and color <= YELLOW then return true end
					end
				end
			end
			return false
		end
	end
	return false
end

-- The recipes offered instead of the step you're in: without the ones the game now shows gray (or,
-- in a step not marked low, green).
local function Offered(route, skill)
	if Capped() then return end
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" then
			if s.from == skill and #s.alts > 0 then
				local list = {}
				for _, a in ipairs(s.alts) do
					local step = Calc.Step(a.spell)
					if step == nil or step < GREEN or (step == GREEN and s.low) then list[#list + 1] = a end
				end
				s.alts = list
			end
			return
		end
		if s.kind == "rank" then return end
	end
end

-- What the whole route rests on (a skill-up only trims it): the profession, its cap, the target,
-- the recipes known, prices, talents, the goal, and the tools you hold (they change which recipes
-- need a tool made first).
local function RouteKey(target, count, goal)
	local tools = {}
	for _, tool in ipairs(TOOLS[S.line] or {}) do tools[#tools + 1] = Owns(tool) and 1 or 0 end
	return table.concat({ S.line, S.max or 0, target, count, Calc.version, tostring(ns.Get("talents")),
		goal, table.concat(tools) }, ":")
end

-- { target, route, shopping } for the open profession, or nil (none open, someone else's).
function Plan.Get()
	if not S.line or S.linked or not ns.Recipes then return nil end
	holding = {}
	local target = Plan.Target()
	local known = ns.Where.KnownSet()
	local count = 0
	for _ in pairs(known) do count = count + 1 end
	local skill = S.skill or 0
	-- The route's choice at each point doesn't hang on where you started, so a skill-up only trims
	-- it; anything else it rests on (cap, target, a recipe learned, prices, talents) works it out anew.
	local goal = Plan.Goal()
	local routeKey = RouteKey(target, count, goal)
	if not full or fullKey ~= routeKey or skill < full.from then
		full, fullKey = Build(skill, target, goal), routeKey
	end
	local key = routeKey .. ":" .. skill .. ":" .. ns.Store.version
	if kept and keptKey == key then
		-- (Worked out for exactly this: the one saved with the character is current, so it rests
		-- no longer. ProfLost.RestPlan marks one that was not kept up; a new one, below, has no mark.)
		local c = ns.Store.Char()
		local saved = c and type(c.plans) == "table" and c.plans[S.line]
		if type(saved) == "table" then saved.rested = nil end
		return kept
	end
	-- A route worked out some points ago rests on the data from there on. Where the game now shows
	-- the recipe of the step you're in gray, or green in a step not marked low, the data is off for
	-- it: the route is worked out again from here, with the game's word for every recipe you know.
	if skill > full.from and GameDisagrees(full, skill) then
		full = Build(skill, target, goal)
	end
	local route = Trim(full, skill)
	Offered(route, skill)
	Repriced(route)
	local shopping = Shopping(route)
	kept, keptKey = { target = target, route = route, shopping = shopping }, key
	-- What it needs, kept for the item tooltips (yours and, on an alt, theirs).
	local c = ns.Store.Char()
	if c then
		c.plans = c.plans or {}
		local need = {}
		for _, row in ipairs(shopping.rows) do need[row.itemID] = row.need end
		-- The recipes the route learns, with the skill range it uses each for: spell -> { from, to }.
		local learn = {}
		for _, s in ipairs(route.steps) do
			if s.kind == "craft" or s.kind == "tool" then
				local use = learn[s.spell]
				if use then
					use[2] = math.max(use[2], s.to)
				elseif s.learn then
					learn[s.spell] = { s.from, s.to }
				end
			end
		end
		-- The first rank the route trains (the trainer's list offers it once you're at its cap).
		local rank
		for _, s in ipairs(route.steps) do
			if s.kind == "rank" then
				rank = { at = s.at, name = RANK_NAMES[s.cap] }
				break
			end
		end
		-- The recipes the route has you buy (a vendor's, or the Auction House's): their items, one
		-- each, with the materials, so the Buy List's Guide List offers them where they are sold.
		-- (One you hold but haven't read yet is in your bags: the list counts it as had.)
		for _, s in ipairs(route.steps) do
			if (s.kind == "craft" or s.kind == "tool") and s.learn and (s.source == "vendor" or s.source == "auction") then
				local item = ns.Where.Teach(s.spell)
				if item then need[item] = math.max(need[item] or 0, 1) end
			end
		end
		c.plans[S.line] = { target = target, need = need, learn = learn, rank = rank, at = time() }
	end
	return kept
end

-- Whether Plan.Get would answer without working the whole route out (it's worked out already).
local function RouteReady()
	if not S.line or S.linked or not ns.Recipes then return true end
	if not full then return false end
	holding = {}
	local known = ns.Where.KnownSet()
	local count = 0
	for _ in pairs(known) do count = count + 1 end
	return fullKey == RouteKey(Plan.Target(), count, Plan.Goal()) and (S.skill or 0) >= full.from
end

-- The route worked out a slice at a time, SLICE_MS a frame (a profession opening, ProfLost handing
-- a guide back): the whole working-out at once held a frame up a tenth of a second or more (Perfy,
-- 2026-11-25). When it's done, Plan.Get answers at once and the pages are drawn again. Nothing runs
-- once it's done: the driver hides itself.
local driver
local function Done()
	sliceCo = nil
	if driver then driver:Hide() end
	pcall(Plan.Get)
	if ns.Changed then ns.Changed() end
end
function Plan.Warm()
	if sliceCo then return end
	if RouteReady() then
		pcall(Plan.Get)
		return
	end
	holding = {}
	local skill, target, goal = S.skill or 0, Plan.Target(), Plan.Goal()
	local known = ns.Where.KnownSet()
	local count = 0
	for _ in pairs(known) do count = count + 1 end
	local key = RouteKey(target, count, goal)
	local co
	co = coroutine.create(function()
		local built = Build(skill, target, goal)
		-- (Kept only if nothing worked one out meanwhile, at once.)
		if sliceCo == co and not (full and fullKey == key and full.from <= skill) then full, fullKey = built, key end
	end)
	sliceCo = co
	if not driver then
		driver = CreateFrame("Frame")
		driver:Hide()
		driver:SetScript("OnUpdate", function(self)
			local c = sliceCo
			if not c then return self:Hide() end
			sliceFrom = Clock()
			local ok, err = coroutine.resume(c)
			if not ok then
				sliceCo = nil
				self:Hide()
				geterrorhandler()(err)
				return
			end
			if coroutine.status(c) == "dead" then Done() end
		end)
	end
	driver:Show()
end

-- The plan when it's ready, else nil with the working-out started (Plan.Warm): for the pages, so
-- opening one never works the whole route out in a single frame.
function Plan.Peek()
	if sliceCo then return nil end
	if RouteReady() then return Plan.Get() end
	Plan.Warm()
	return nil
end
function Plan.Working() return sliceCo ~= nil end

-- Rank names for a cap (for text).
function Plan.RankName(cap) return RANK_SHOWN[cap] end
-- The character level a rank asks (nil for Apprentice).
-- (Ranks.lua's word for the open profession where it has one: Cooking, First Aid and Mining ask
-- for no level.)
function Plan.RankLevel(cap)
	local ranks = ns.Ranks and S.line and ns.Ranks[S.line]
	local rec = ranks and ranks[cap]
	if type(rec) == "table" then return rec.level end
	return RANK_LEVEL[cap]
end
