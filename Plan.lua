-- The plan for the open profession: what to craft next, the cheapest way to your target skill, and
-- what that takes.
--   Craft next: your recipes that still give points now, cheapest expected cost per point first
--               (the game's own color and points per craft for each).
--   The route:  for every skill point from yours to the target, the recipe with the cheapest
--               expected cost per point at that skill, among the ones you know and the ones a
--               trainer will teach by then (its training cost spread over the points it's useful
--               for). The chance at each skill comes from its thresholds, so a yellow or green one
--               counts its misses: the crafts are what you can expect to make, not one per point.
--               At a rank cap it stops for the next rank. Points in a row on one recipe make a step.
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

local LOW_CHANCE = 0.10       -- a goal of selling skips recipes below this chance of a point
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

local function Owns(tool)
	return ns.Store and ns.Store.Count(tool.item).mine > 0
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

-- { spell, t (thresholds), cost (per craft, after its value), mats (its materials' cost), complete,
-- known, learnAt, learnCost, source ("trainer", "vendor", "auction"), ups, tool } for every recipe of
-- the open profession the plan can use. credit: itemID -> price, for what the route itself needs (a
-- recipe making one is worth what it saves buying).
local function Candidates(goal, credit)
	local out = {}
	local known = ns.Where.KnownSet()
	local mine = ns.Faction()
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
					-- (A value far beyond what goes in is a bad price, not a bargain.)
					local wild = goal ~= "cost" and value > 0 and (mats <= 0 or value > mats * WILD_MARGIN)
					if not wild then
						local learnAt = ns.Where.Required(spell) or t[1] or 0
						out[#out + 1] = { spell = spell, t = t, cost = mats - value, mats = mats, complete = complete,
							known = isKnown or auto and true or false, learnAt = learnAt,
							learnCost = learnCost, source = source, ups = isKnown and Calc.SkillUps(spell) or 1,
							tool = ToolFor(spell, data, learnAt) }
					end
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
-- best first, at most `count`.
function Plan.CraftNext(count)
	local out = {}
	if not S.line or S.linked then return out end
	local known = ns.Where.KnownSet()
	for spell in pairs(known) do
		local data = ns.Recipes and ns.Recipes[spell]
		if data and data[1] == S.line then
			local chance = Calc.Chance(spell, S.skill or 0, S.max)
			if chance and chance > 0 then
				local cost = Calc.Cost(spell)
				local points = chance * Calc.SkillUps(spell)
				out[#out + 1] = { spell = spell, chance = chance, cost = cost.total, complete = cost.complete,
					perPoint = cost.complete and cost.total / points or nil }
			end
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
	return out
end

-- ---------------------------------------------------------------------------------------------
-- The route
-- ---------------------------------------------------------------------------------------------

-- steps: { kind = "craft", spell, from, to, crafts, cost, complete, learn = copper or nil, source,
--          alts = { { spell, perPoint }, ... } (the next best when the step began) }
--        { kind = "tool", spell, at, cost, complete, learn, source, item } (a rod or tool to make first)
--        { kind = "rank", at, cap, name, level }
--        { kind = "gap", at, to } (no recipe in the data gives points from `at`; planning goes on at `to`)
-- plus total (copper), complete, crafts.
local function Route(from, target, cap, goal, credit)
	local cands = Candidates(goal, credit)
	local bySpell = {}
	for _, r in ipairs(cands) do bySpell[r.spell] = r end
	local overtime = (ns.Get("talents") and Calc.Talents()) or 0
	local steps = {}
	local learned = {}
	local owned = {}
	local k = from
	local guard = 0

	-- A recipe's cost a point at k (nil: it can't be used there).
	local function Score(r, p)
		local have = r.known or learned[r.spell]
		local perPoint = (r.complete and r.cost or (r.cost + UNPRICED)) / (p * r.ups)
		-- Learning it now is spread over the points it can still give.
		if not have and r.learnCost and r.learnCost > 0 then
			perPoint = perPoint + r.learnCost / max(1, min(r.t[4], target) - k)
		end
		-- So is the tool it needs, when you haven't got it.
		local tool = r.tool
		if tool and not owned[tool] and not Owns(tool) then
			local made = bySpell[tool.spell]
			if not made or not (made.known or learned[made.spell] or made.learnAt <= k) then return nil end
			local extra = made.mats + ((made.known or learned[made.spell]) and 0 or (made.learnCost or 0))
			perPoint = perPoint + extra / max(1, min(r.t[4], target) - k)
		end
		return perPoint
	end

	while k < target and guard < 600 do
		guard = guard + 1
		if cap > 0 and k >= cap then
			if cap >= TOP then break end
			local nextCap = cap + 75
			for _, c in ipairs(RANK_CAPS) do if c > cap then nextCap = c break end end
			steps[#steps + 1] = { kind = "rank", at = k, cap = nextCap, name = RANK_SHOWN[nextCap], level = RANK_LEVEL[nextCap] }
			cap = nextCap
		else
			-- The cheapest three a point here (the best and the next two, for the alternatives).
			local top = {}
			local scoreOf = {}
			for _, r in ipairs(cands) do
				local have = r.known or learned[r.spell]
				if (have or r.learnAt <= k) and not isTool[r.spell] then
					local p = ChanceAt(r, k, overtime)
					if p > 0 and not (goal ~= "cost" and p < LOW_CHANCE) then
						local s = Score(r, p)
						if s then
							scoreOf[r] = { s, p }
							local i = #top + 1
							while i > 1 and top[i - 1][2] > s do i = i - 1 end
							if i <= 3 then
								table.insert(top, i, { r, s, p })
								top[4] = nil
							end
						end
					end
				end
			end
			if #top == 0 then
				-- Nothing gives points here: said, and planning goes on where something does.
				local nextAt
				for _, r in ipairs(cands) do
					if not isTool[r.spell] and r.learnAt > k and r.learnAt < target and (not nextAt or r.learnAt < nextAt) then
						nextAt = r.learnAt
					end
				end
				steps[#steps + 1] = { kind = "gap", at = k, to = nextAt or target }
				if not nextAt then break end
				k = nextAt
			else
				local best, bestScore, bestChance = top[1][1], top[1][2], top[1][3]
				-- The step's recipe stays unless another is clearly cheaper (no flip-flopping).
				local last = steps[#steps]
				if last and last.kind == "craft" and last.spell ~= best.spell then
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
				if not (last and last.kind == "craft" and last.spell == best.spell) then
					local alts = {}
					for i = 1, #top do
						if top[i][1] ~= best and #alts < 2 then alts[#alts + 1] = { spell = top[i][1].spell, perPoint = top[i][2] } end
					end
					local have = best.known or learned[best.spell]
					last = { kind = "craft", spell = best.spell, from = k, to = k, exp = {},
						unit = best.cost, complete = best.complete, alts = alts,
						learn = (not have) and (best.learnCost or 0) or nil, source = (not have) and best.source or nil }
					steps[#steps + 1] = last
					if not have then learned[best.spell] = true end
				end
				-- (Each point's expected crafts kept: a skill-up trims the route rather than redo it.)
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
					alts = s.alts }
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
					row.cost = floor(unit * buy + 0.5)
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

-- { target, route, shopping } for the open profession, or nil (none open, someone else's).
function Plan.Get()
	if not S.line or S.linked or not ns.Recipes then return nil end
	local target = Plan.Target()
	local known = ns.Where.KnownSet()
	local count = 0
	for _ in pairs(known) do count = count + 1 end
	local skill = S.skill or 0
	-- The route's choice at each point doesn't hang on where you started, so a skill-up only trims
	-- it; anything else it rests on (cap, target, a recipe learned, prices, talents) works it out anew.
	local goal = Plan.Goal()
	-- (The tools you hold change which recipes need a tool made first.)
	local tools = {}
	for _, tool in ipairs(TOOLS[S.line] or {}) do tools[#tools + 1] = Owns(tool) and 1 or 0 end
	local routeKey = table.concat({ S.line, S.max or 0, target, count, Calc.version, tostring(ns.Get("talents")),
		goal, table.concat(tools) }, ":")
	if not full or fullKey ~= routeKey or skill < full.from then
		-- Twice: the first route says what it uses of things a recipe makes (bolts, bars, vials);
		-- the second counts a recipe making one of those as worth what it saves buying it.
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
		full, fullKey = credit and Route(skill, target, S.max or 0, goal, credit) or first, routeKey
	end
	local key = routeKey .. ":" .. skill .. ":" .. ns.Store.version
	if kept and keptKey == key then return kept end
	local route = Trim(full, skill)
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
		c.plans[S.line] = { target = target, need = need, learn = learn, rank = rank, at = time() }
	end
	return kept
end

-- Rank names for a cap (for text).
function Plan.RankName(cap) return RANK_SHOWN[cap] end
-- The character level a rank asks (nil for Apprentice).
function Plan.RankLevel(cap) return RANK_LEVEL[cap] end
