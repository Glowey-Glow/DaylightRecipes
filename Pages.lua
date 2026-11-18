-- What the pages say, drawn on a doc (Doc.lua): the recipe's skill-up chance, costs and value; the
-- plan (craft next, the route, Auction House prices); the materials the route needs; the recipes
-- you don't know yet and where to get them. Used by the docked pane and by the big window alike.
-- ctx (from whoever draws): pick(spell) picks a recipe (nil: nowhere to pick it), redraw() draws
-- the page again, filter (the missing list's search, lower case).
local _, ns = ...
if not ns.ok then return end

local Calc, Where, Doc = ns.Calc, ns.Where, ns.Doc
local L, Plural = ns.L, ns.Plural
local S = ns.state
local Color, Hex, DiffColor, Pct = Doc.Color, Doc.Hex, Doc.DiffColor, Doc.Pct
local ItemTip, SpellTip, ItemName, RecipeName = Doc.ItemTip, Doc.SpellTip, Doc.ItemName, Doc.RecipeName

local Pages = {}
ns.Pages = Pages

-- ---------------------------------------------------------------------------------------------
-- Recipe
-- ---------------------------------------------------------------------------------------------

function Pages.Skill(d, spell)
	d:Heading(L["Skill-up"])
	local chance, base, state = Calc.Chance(spell, S.skill or 0, S.max)
	if state == "unknown" then
		d:Line(L["Its skill-up range isn't known."], "small", "OFF")
		return chance
	end
	local t = Calc.Thresholds(spell)
	-- The game's own color when it rates the recipe (one you know), else from the thresholds.
	local step = Calc.Step(spell)
	if not step then
		step = 4
		if t then
			for i = 1, 3 do if (S.skill or 0) < t[i + 1] then step = i break end end
		end
	end
	local r, g, b = DiffColor(step)
	local row = d:Row({ left = L["Chance of a Point"], right = Pct(chance) })
	row.right:SetTextColor(r, g, b)
	d:Bar(chance)
	if t then
		local marks = {}
		local words = { L["orange %d"], L["yellow %d"], L["green %d"], L["gray %d"] }
		for i = 1, 4 do
			local cr, cg, cb = DiffColor(i)
			marks[#marks + 1] = Hex(cr, cg, cb) .. words[i]:format(t[i]) .. "|r"
		end
		d:Line(table.concat(marks, "  "), "small", "TEXT")
	end
	local ups = Calc.SkillUps(spell)
	if state == "cap" then
		d:Line(L["You're at your cap (%d): train the next rank for more points."]:format(S.max), "small", "WARN")
	elseif chance <= 0 then
		d:Line(L["Gray: it gives no more points."], "small", "OFF")
	else
		if ups > 1 then d:Line(L["Each craft that skills up gives %d points."]:format(ups), "small", "TEXT") end
		local perPoint = 1 / (chance * ups)
		if perPoint > 1.05 then d:Line(L["About %.1f crafts a point."]:format(perPoint), "small", "TEXT") end
	end
	local overtime, _, talents = Calc.Talents()
	if overtime > 0 and base and base > 0 and base < 1 then
		d:Line(L["Overtime rank %d: +%d%% included."]:format(talents.overtimeRank, overtime * 100 + 0.5), "small", "OFF")
	end
	return chance
end

-- What you hold of an item, in a few words ("12 in bags, 40 in the bank"), or nil.
local function HaveText(itemID)
	if not ns.Store then return nil end
	local have = ns.Store.Count(itemID)
	local where = {}
	if have.bags > 0 then where[#where + 1] = L["%d in bags"]:format(have.bags) end
	if have.bank > 0 then where[#where + 1] = L["%d in the bank"]:format(have.bank) end
	if have.mail > 0 then where[#where + 1] = L["%d in the mail"]:format(have.mail) end

	return #where > 0 and table.concat(where, ", ") or nil, have
end
Pages.HaveText = HaveText

-- "[Mira has 12]" (and how many more the other alts hold), or nil when no alt has any.
function Pages.AltAlert(have)
	if not have or (have.altTotal or 0) <= 0 or not have.alts[1] then return nil end
	local first = have.alts[1]
	if #have.alts > 1 then
		return L["[%s has %d] (+%d on other alts)"]:format(first.name, first.count, have.altTotal - first.count)
	end
	return L["[%s has %d]"]:format(first.name, first.count)
end

-- opts.have: each material says what you hold of it (the big window's recipe page).
function Pages.Cost(d, spell, chance, opts)
	d:Heading(L["Materials"])
	local cost = Calc.Cost(spell)
	if #cost.rows == 0 then
		d:Line(L["It takes no materials."], "small", "OFF")
		return cost
	end
	for _, m in ipairs(cost.rows) do
		local name, icon = ItemName(m.itemID, d)
		local sub
		if m.kind == "ah" then
			sub = L["Auction House, %s each"]:format(Calc.Money(m.unit))
		elseif m.kind == "vendor" then
			sub = L["%s, %s each"]:format(m.who or L["Vendor"], Calc.Money(m.unit))
		else
			sub = L["No price known"]
		end
		local subInk = m.unit and "TEXT" or "OFF"
		if opts and opts.have then
			local text, have = HaveText(m.itemID)
			local bags = have and have.bags or 0
			if text then sub = text .. " · " .. sub end
			local alert = bags < m.count and Pages.AltAlert(have)
			if alert then sub = sub .. " · " .. alert end
			-- (Short in your bags, where crafting takes them from: said in the warning ink.)
			if bags < m.count then subInk = "WARN" end
		end
		d:Row({ icon = icon, left = name .. (m.count > 1 and ("  x" .. m.count) or ""),
			right = m.total and Calc.Money(m.total) or "?", rightInk = m.total and "VALUE" or "OFF",
			sub = sub, subInk = subInk, tip = ItemTip(m.itemID) })
	end
	d:Row({ left = L["Total"], leftInk = "LABEL", right = Calc.Money(cost.total) })
	if not cost.complete then
		d:Line(L["Some materials have no price, so the total is short."], "small", "WARN")
	elseif chance and chance > 0 then
		-- (Expected points per craft: the chance times the points one gives.)
		local points = chance * Calc.SkillUps(spell)
		if points ~= 1 then d:Row({ left = L["Per Skill Point"], leftInk = "LABEL", right = Calc.Money(cost.total / points) }) end
	end
	if not Calc.HasAH() then
		d:Line(L["Vendor prices only: scan the Auction House from the Leveling Guide for its prices."], "small", "OFF")
	end
	return cost
end

function Pages.Worth(d, spell)
	local worth = Calc.Worth(spell)
	d:Heading(L["Value"])
	if not worth then
		d:Line(L["It makes no item to sell."], "small", "OFF")
		return
	end
	local name, icon = ItemName(worth.itemID, d)
	local made = worth.count ~= 1 and ("  x" .. (worth.count % 1 == 0 and worth.count or ("%.1f"):format(worth.count))) or ""
	d:Row({ icon = icon, left = name .. made, tip = ItemTip(worth.itemID) })
	if worth.bound then d:Line(L["It binds when made: no Auction House."], "small", "OFF") end
	if #worth.routes == 0 then
		d:Line(L["No price is known for it."], "small", "OFF")
	end
	for _, route in ipairs(worth.routes) do
		local sub, ink
		if route.profit then
			-- (The label is Calc's English word, text its name in your language; the Auction House's value is after its cut.)
			local ah = route.label == "Auction House"
			if route.profit >= 0 then
				sub, ink = (ah and L["%s profit, after the 5%% cut"] or L["%s profit"]):format(Calc.Money(route.profit)), "GOOD"
			else
				sub, ink = (ah and L["%s loss, after the 5%% cut"] or L["%s loss"]):format(Calc.Money(-route.profit)), "BAD"
			end
		end
		d:Row({ left = route.text or route.label, leftInk = "TEXT", right = Calc.Money(route.value), sub = sub, subInk = ink })
	end
	local de = worth.de
	if de then
		d:Heading(L["Disenchants Into"])
		for _, m in ipairs(de.mats) do
			local mname, micon = ItemName(m.itemID, d)
			local range = m.lo == m.hi and tostring(m.lo) or (m.lo .. "-" .. m.hi)
			d:Row({ icon = micon, left = mname, right = m.value and Calc.Money(m.value) or "?",
				rightInk = m.value and "VALUE" or "OFF",
				sub = L["%s at a time, %s of the time"]:format(range, Pct(m.chance)), tip = ItemTip(m.itemID) })
		end
		d:Line(L["Classic yields: not yet checked on Forever."], "tiny", "OFF")
	end
end

-- The pane's recipe page: name, then the three parts.
function Pages.Recipe(d)
	local spell = S.recipe
	if not spell then
		d:Line(L["Pick a recipe."], "body", "OFF")
		return
	end
	d:Line(RecipeName(spell), "head", "VALUE")
	local chance = Pages.Skill(d, spell)
	Pages.Cost(d, spell, chance)
	Pages.Worth(d, spell)
end

-- ---------------------------------------------------------------------------------------------
-- Missing
-- ---------------------------------------------------------------------------------------------

local PAGE = 60

local function PlaceText(place)
	if not place then return nil end
	if place.mapID then return ("%s (%d, %d)"):format(place.zone, place.x + 0.5, place.y + 0.5) end
	return place.zone
end

-- A standing's word in the game's own reputation colors (FACTION_BAR_COLORS, as on the reputation
-- bars: Hated and Hostile red, Unfriendly orange, Neutral yellow, Friendly to Exalted green), Blizzard's values if the table isn't there.
local REP_COLORS = {
	{ r = 0.8, g = 0.3, b = 0.22 }, { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.75, g = 0.27, b = 0 },
	{ r = 0.9, g = 0.7, b = 0 }, { r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
	{ r = 0, g = 0.6, b = 0.1 }, { r = 0, g = 0.6, b = 0.1 },
}
local function Standing(id)
	local word = Where.StandingName(id)
	local set = type(_G.FACTION_BAR_COLORS) == "table" and _G.FACTION_BAR_COLORS or REP_COLORS
	local c = set[id] or REP_COLORS[id]
	if type(c) ~= "table" or type(c.r) ~= "number" then return word end
	return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), word)
end
Pages.Standing = Standing

-- "Nightclaw Druids: Friendly (Current Rep: Neutral)", for a list's line, the standings in their
-- reputation colors.
function Pages.RepText(rep)
	local need = Standing(rep.standing)
	if rep.mine then
		return L["%s: %s (Current Rep: %s)"]:format(rep.name, need, Standing(rep.mine))
	end
	return L["%s: %s"]:format(rep.name, need)
end

-- The reputation a recipe asks for, on a line of its own: met (good ink), not yet (warning ink),
-- or a faction you haven't met; the standings in their reputation colors.
function Pages.RepLine(d, rep, indent)
	local need = Standing(rep.standing)
	local text, ink
	if not rep.mine then
		text, ink = L["Needs %s with %s; you haven't met them yet."]:format(need, rep.name), "WARN"
	else
		text = L["Needs %s with %s (Current Rep: %s)."]:format(need, rep.name, Standing(rep.mine))
		ink = rep.mine >= rep.standing and "GOOD" or "WARN"
	end
	d:Line(text, "small", ink, indent)
end

-- A recipe's (or blueprint's) source groups: each titled, its places listed (a click on one with a
-- spot on the map sets a waypoint), the reputation it asks for with your standing.
function Pages.SourceGroups(d, groups, indent)
	indent = indent or 0
	for _, g in ipairs(groups) do
		d:Line(g.title, "small", "LABEL", indent)
		if g.kind == "rep" then
			local rep, waiting = Where.Rep(g.item)
			if waiting then d.waiting[g.item] = true end
			if rep then Pages.RepLine(d, rep, indent + 4) end
		end
		for _, l in ipairs(g.lines) do
			local located = l.place and l.place.mapID
			d:Row({ indent = indent, left = l.name, leftInk = "TEXT", right = l.note or "", rightInk = "VALUE",
				sub = PlaceText(l.place), subInk = located and "ACCENT" or "OFF",
				tip = (located and function(tip)
					tip:SetText(l.name)
					tip:AddLine(PlaceText(l.place), 1, 1, 1)
					tip:AddLine(L["Click for a waypoint."], Color("LABEL"))
				end) or (l.item and ItemTip(l.item)) or nil,
				onClick = located and function() Where.Go(l.name, l.place) end or nil })
		end
		if g.more > 0 then d:Line(L["and %d more"]:format(g.more), "tiny", "OFF", indent + 4) end
	end
end

function Pages.Missing(d, ctx)
	local st = d.state
	st.open = st.open or {}
	if S.linked then
		d:Line(L["These are someone else's recipes. Missing recipes are listed for your own."], "small", "OFF")
		return
	end
	if not S.line then
		d:Line(L["There's no recipe data for this profession."], "small", "OFF")
		return
	end
	local filter = ctx.filter or ""
	local list = Where.Missing(filter)
	local count = #list
	-- A new profession or search starts at the first page again.
	local now = tostring(S.line) .. ":" .. filter
	if now ~= st.limitFor then st.limit, st.limitFor = PAGE, now end
	d:Line(count == 0 and (filter ~= "" and L["No missing recipe matches."] or L["You know every recipe there is."])
		or Plural(count, "%d recipe you don't know", "%d recipes you don't know"):format(count), "small", "LABEL")
	d:Gap(2)
	for i, e in ipairs(list) do
		if i > st.limit then
			local left = count - st.limit
			d:Row({ left = L["Show %d More"]:format(math.min(left, PAGE)), leftInk = "ACCENT",
				right = L["%d left"]:format(left), rightInk = "OFF",
				onClick = function()
					st.limit = st.limit + PAGE
					ctx.redraw()
				end })
			break
		end
		-- The reputation it asks for (Polestar's data; for a recipe no data knows, its tooltip's).
		local rep, waiting
		if e.item and (e.unknown or e.hasRep) then rep, waiting = Where.Rep(e.item) end
		if waiting then d.waiting[e.item] = true end
		local sub = e.summary or ""
		if rep and e.unknown then sub = L["Reputation"] end
		if rep then sub = sub .. (sub ~= "" and " · " or "") .. Pages.RepText(rep) end
		if e.level then sub = sub .. (sub ~= "" and " · " or "") .. L["Level %d"]:format(e.level) end
		d:Row({ left = e.name, leftInk = e.reachable and "VALUE" or "OFF",
			right = e.required and L["Skill %d"]:format(e.required) or "", rightInk = e.reachable and "GOOD" or "OFF",
			sub = sub, subInk = "TEXT",
			tip = e.item and ItemTip(e.item) or SpellTip(e.spell),
			onClick = function()
				st.open[e.spell] = not st.open[e.spell] or nil
				ctx.redraw()
			end })
		if st.open[e.spell] then
			if e.unknown and rep then
				Pages.RepLine(d, rep, 12)
				d:Line(L["The recipe data doesn't say where yet: look for that faction's vendor."], "small", "OFF", 12)
			elseif e.unknown then
				d:Line(L["Where to get this isn't in the recipe data yet."], "small", "OFF", 12)
			end
			Pages.SourceGroups(d, e.groups, 12)
			d:Gap(6)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Plan
-- ---------------------------------------------------------------------------------------------

local STALE = 12 * 3600      -- s before the last Auction House scan is called old

function Pages.Prices(d)
	local P = ns.Prices
	if not P or P.Mogul() or not ns.Get("useAH") then return end
	if P.Scanning() then
		d:Line(L["Reading Auction House prices..."], "small", "ACCENT")
	elseif P.CanScan() then
		d:Row({ left = L["Scan Auction House Prices"], leftInk = "ACCENT",
			sub = P.LastScan() and L["Last scan %s"]:format(Doc.Ago(P.LastScan())) or L["Prices for materials, from one full scan"],
			subInk = "TEXT", onClick = function() P.Scan() end })
	elseif not P.Has() then
		d:Line(L["No Auction House prices yet: open the Auction House and scan from here, or browse it."], "small", "OFF")
	elseif P.LastScan() then
		-- (Prices move: a scan over half a day old is said to be, in the warning ink.)
		local old = time() - P.LastScan() > STALE
		d:Line((old and L["Auction House prices from your scan %s: scan again at the Auction House for today's."]
			or L["Auction House prices from your scan %s."]):format(Doc.Ago(P.LastScan())), old and "small" or "tiny", old and "WARN" or "OFF")
	end
end

function Pages.CraftNext(d, ctx, count)
	d:Heading(L["Craft Next"])
	local list = ns.Plan.CraftNext(count or 3)
	if #list == 0 then
		d:Line(L["None of your recipes gives a point now: learn a new one (see the route below)."], "small", "OFF")
		return
	end
	for _, e in ipairs(list) do
		local sub = L["%s chance"]:format(Pct(e.chance))
		if e.can and e.can > 0 then sub = sub .. " · " .. L["you can make %d"]:format(e.can) end
		d:Row({ left = RecipeName(e.spell), leftInk = "VALUE",
			right = e.perPoint and L["%s a point"]:format(Calc.Money(e.perPoint)) or L["no price"],
			rightInk = e.perPoint and "VALUE" or "OFF", sub = sub, subInk = "TEXT", tip = SpellTip(e.spell),
			onClick = ctx.pick and function() ctx.pick(e.spell) end or nil })
	end
end

-- "At 75: train Journeyman (level 10)." for a rank step of the route.
local function TrainAt(s)
	local name = s.name or L["the next rank"]
	if s.level then return L["At %d: train %s (level %d)."]:format(s.at, name, s.level) end
	return L["At %d: train %s."]:format(s.at, name)
end

function Pages.Route(d, ctx, plan)
	local route = plan.route
	d:Heading(L["Route to %d"]:format(plan.target))
	local targets = ns.Plan.Targets()
	if #targets > 1 then
		local nextOne = targets[1]
		for i, v in ipairs(targets) do
			if v == plan.target then nextOne = targets[i % #targets + 1] break end
		end
		d:Row({ left = L["Aim for %d Instead"]:format(nextOne), leftInk = "ACCENT",
			onClick = function() ns.Plan.SetTarget(nextOne) end })
	end
	if route.crafts > 0 then
		d:Line((route.complete and L["About %d crafts, %s."] or L["About %d crafts, %s and up (some materials have no price)."])
			:format(route.crafts, Calc.Money(route.total)), "small", "TEXT")
	end
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" then
			local sub = Plural(s.count, "about %d craft", "about %d crafts"):format(s.count)
			if s.learn then sub = sub .. " · " .. L["learn it first (%s)"]:format(s.learn > 0 and Calc.Money(s.learn) or L["trainer"]) end
			local known = not s.learn
			d:Row({ left = ("%d-%d  %s"):format(s.from, s.to, RecipeName(s.spell)), leftInk = "VALUE",
				right = s.complete and Calc.Money(s.cost) or "?", rightInk = s.complete and "VALUE" or "OFF",
				sub = sub, subInk = s.learn and "WARN" or "TEXT", tip = SpellTip(s.spell),
				onClick = known and ctx.pick and function() ctx.pick(s.spell) end or nil })
		elseif s.kind == "rank" then
			d:Line(TrainAt(s), "small", "WARN")
		elseif s.kind == "gap" then
			d:Line(L["Past %d no recipe in the data gives points."]:format(s.at), "small", "OFF")
		end
	end
end

function Pages.Shopping(d, plan)
	local shop = plan.shopping
	if #shop.rows == 0 then
		d:Line(L["The route needs no materials."], "small", "OFF")
		return
	end
	d:Line(shop.buyTotal > 0 and (shop.complete and L["To buy: %s"] or L["To buy: %s and up"]):format(Calc.Money(shop.buyTotal))
		or L["You have everything the route needs."], "small", shop.buyTotal > 0 and "TEXT" or "GOOD")
	for _, r in ipairs(shop.rows) do
		local name, icon = ItemName(r.itemID, d)
		local have = r.have
		local parts = { L["need %d"]:format(r.need) }
		local more = {}       -- where the rest comes from: on a wrapped line of its own
		if have.mine > 0 then
			local where = {}
			if have.bags > 0 then where[#where + 1] = L["%d in bags"]:format(have.bags) end
			if have.bank > 0 then where[#where + 1] = L["%d in the bank"]:format(have.bank) end
			if have.mail > 0 then where[#where + 1] = L["%d in the mail"]:format(have.mail) end
			parts[#parts + 1] = table.concat(where, ", ")
		end
		-- Where the rest could come from: an alt that holds some, someone who can make it, the vendor.
		if r.short > 0 and have.altTotal > 0 then more[#more + 1] = Pages.AltAlert(have) end
		if r.buy > 0 and r.makers then
			more[#more + 1] = L["%s can make it"]:format(r.makers[1])
		elseif r.buy > 0 and r.vendor then
			more[#more + 1] = L["sold by %s"]:format(r.vendor)
		end
		local right, rightInk
		if r.buy > 0 then
			right = L["buy %d"]:format(r.buy) .. (r.cost and ("  " .. Calc.Money(r.cost)) or "  ?")
			rightInk = r.cost and "VALUE" or "OFF"
		else
			right, rightInk = L["have"], "GOOD"
		end
		d:Row({ icon = icon, left = name, right = right, rightInk = rightInk,
			sub = table.concat(parts, " · "), subInk = "TEXT", tip = ItemTip(r.itemID) })
		if #more > 0 then d:Line(table.concat(more, " · "), "small", "OFF", 26) end
	end
end

-- Why a plan can't be drawn now, or nil.
local function NoPlan()
	if S.linked then return L["These are someone else's recipes. The plan is for your own."] end
	if not S.line then return L["There's no recipe data for this profession."] end
end

-- ---------------------------------------------------------------------------------------------
-- Leveling Guide
-- ---------------------------------------------------------------------------------------------

-- A step's cost for the route's goal, said as what it is: "total" (its materials), "net cost" (after what
-- you make is sold, vendored or disenchanted), or a profit; `per` adds "a point".
local function Net(copper, per)
	if copper < 0 then return (per and L["%s profit a point"] or L["%s profit"]):format(Calc.Money(-copper)), "GOOD" end
	if per then return L["%s a point"]:format(Calc.Money(copper)), "VALUE" end
	return (ns.Plan.Goal() == "cost" and L["%s total"] or L["%s net cost"]):format(Calc.Money(copper)), "VALUE"
end

-- How a recipe the route uses is learned, in a few words.
local function LearnText(s)
	local cost = (s.learn or 0) > 0 and Calc.Money(s.learn) or L["free"]
	if s.source == "vendor" then return L["First buy the recipe from a vendor (%s): see the Missing tab."]:format(cost) end
	if s.source == "auction" then return L["First buy the recipe on the Auction House (%s)."]:format(cost) end
	if S.name then return L["First learn it from a %s trainer (%s): it's marked Recommended there."]:format(S.name, cost) end
	return L["First learn it from a profession trainer (%s): it's marked Recommended there."]:format(cost)
end

-- What's in your hands for one material: "12 / 24", whether you have them all, and a line saying
-- where the rest is (the bank, the mail, an alt) or how many to buy.
local function MaterialRow(d, itemID, need, indent)
	local name, icon = ItemName(itemID, d)
	local have = ns.Store and ns.Store.Count(itemID) or { bags = 0, bank = 0, mail = 0, mine = 0, alts = {}, altTotal = 0 }
	local done = have.mine >= need
	local parts = {}
	if have.bags < need and have.bank > 0 then parts[#parts + 1] = L["%d in the bank"]:format(have.bank) end
	if have.bags < need and have.mail > 0 then parts[#parts + 1] = L["%d in the mail"]:format(have.mail) end
	if not done then
		-- (Bought only where a vendor or the Auction House has it: a fish, an ore, a dust is "more".)
		local short = need - have.mine
		local sold = Calc.Vendor(itemID) or Calc.AH(itemID)
		parts[#parts + 1] = sold and L["buy %d"]:format(short) or L["need %d more"]:format(short)
		local alert = Pages.AltAlert(have)
		if alert then parts[#parts + 1] = alert end
	end
	d:Row({ icon = icon, indent = indent, left = name, right = ("%d / %d"):format(math.min(have.mine, need), need),
		rightInk = done and "GOOD" or "WARN", sub = #parts > 0 and table.concat(parts, " · ") or nil,
		subInk = done and "TEXT" or "WARN", tip = ItemTip(itemID) })
end
Pages.MaterialRow = MaterialRow

-- The step you're on, as a card: what to make and how many, its progress, its materials, and
-- buttons to make it, queue it or look at it. glowTop: where the guide's light round it starts
-- (it ends above the other recipes offered instead).
local function StepCard(d, ctx, s, n, glowTop)
	local skill = S.skill or 0
	d:Heading(L["Step %d · Skill %d to %d"]:format(n, s.from, s.to))
	local out = ns.Ask("GetRecipeOutputItemData", s.spell)
	local icon = type(out) == "table" and out.icon or nil
	if not icon and ns.Recipes and ns.Recipes[s.spell] then
		local made = ns.Recipes[s.spell][4]
		if type(made) == "table" and made[1] then icon = select(2, ItemName(made[1], d)) end
	end
	local money, ink = Net(s.cost)
	d:Row({ icon = icon, left = L["Make %d x %s"]:format(s.count, RecipeName(s.spell)), leftInk = "VALUE",
		right = s.complete and money or "?", rightInk = s.complete and ink or "OFF",
		tip = SpellTip(s.spell) })
	if s.kind == "tool" then
		d:Line(L["The recipes from here on need it: made once, kept in your bags."], "small", "TEXT")
	else
		local span = math.max(1, s.to - s.from)
		d:Bar(math.max(0, math.min(1, (skill - s.from) / span)))
	end
	if s.learn then d:Line(LearnText(s), "small", "WARN") end
	local mats = Calc.Materials(s.spell)
	if #mats > 0 then
		d:Line(L["You Need"], "small", "LABEL")
		for _, m in ipairs(mats) do MaterialRow(d, m[1], m[2] * s.count, 0) end
	end
	local buttons = {}
	local Craft = ns.Craft
	if not s.learn and Craft and ctx.make then
		local can = Craft.Count(s.spell)
		local n2 = math.min(s.count, can)
		buttons[#buttons + 1] = { text = can > 0 and L["Make %d"]:format(n2) or L["Make"], off = can < 1 or Craft.Making() ~= nil,
			onClick = function() Craft.Make(s.spell, n2) end }
	end
	if ns.Queue then
		buttons[#buttons + 1] = { text = L["Queue"], onClick = function() ns.Queue.Add(s.spell, s.count) end }
	end
	if not s.learn and ctx.pick then
		buttons[#buttons + 1] = { text = L["Show Recipe"], onClick = function() ctx.pick(s.spell) end }
	end
	if #buttons > 0 then
		d:Gap(4)
		d:Buttons(buttons)
	end
	if glowTop then d:GlowFrom(glowTop) end
	-- The next best recipes when the step began, for when you'd rather (or lack its materials).
	if s.alts and #s.alts > 0 then
		d:Line(L["Or Instead"], "small", "LABEL")
		for _, a in ipairs(s.alts) do
			local m, k = Net(a.perPoint, true)
			d:Row({ left = RecipeName(a.spell), leftInk = "TEXT", right = m, rightInk = k,
				tip = SpellTip(a.spell), onClick = ctx.pick and function() ctx.pick(a.spell) end or nil })
		end
	end
end

local function RankCard(d, s, n)
	d:Heading(L["Step %d · Skill %d"]:format(n, s.at))
	local name, text = s.name or L["the next rank"]
	if S.name and s.level then
		text = L["Train %s at a %s trainer (it asks level %d)."]:format(name, S.name, s.level)
	elseif S.name then
		text = L["Train %s at a %s trainer."]:format(name, S.name)
	elseif s.level then
		text = L["Train %s at a profession trainer (it asks level %d)."]:format(name, s.level)
	else
		text = L["Train %s at a profession trainer."]:format(name)
	end
	d:Line(text, "body", "WARN")
	d:Line(L["You're capped at %d until you do."]:format(s.at), "small", "TEXT")
end

-- Your goal: the skills worth aiming for, and what the route aims for (cheapest materials, or the
-- least it costs after vendoring, disenchanting or selling what you make), as buttons (picked lit).
local function GoalPart(d, plan)
	local targets = ns.Plan.Targets()
	if #targets >= 2 then
		local list = {}
		for _, v in ipairs(targets) do
			list[#list + 1] = { text = tostring(v), width = 56, active = v == plan.target,
				onClick = function() ns.Plan.SetTarget(v) end }
		end
		d:Line(L["Goal"], "small", "LABEL")
		d:Buttons(list)
	end
	local goal = ns.Plan.Goal()
	local list = {}
	for _, g in ipairs(ns.Plan.GOALS) do
		list[#list + 1] = { text = ns.Plan.GOAL_WORDS[g], active = g == goal, onClick = function() ns.Plan.SetGoal(g) end }
	end
	d:Line(L["Cheapest Route"], "small", "LABEL")
	d:Buttons(list)
end

-- ctx.make: the step's Make button is offered (the trade skill is open here).
function Pages.Guide(d, ctx)
	local why = NoPlan()
	if why then
		d:Line(why, "small", "OFF")
		return
	end
	local plan = ns.Plan.Get()
	if not plan then return end
	local skill = S.skill or 0
	d:Line(L["%s %d to %d"]:format(S.name or L["Your profession"], skill, plan.target), "head", "VALUE")
	GoalPart(d, plan)
	if skill >= plan.target then
		d:Line(L["You've reached your goal."], "body", "GOOD")
		Pages.Prices(d)
		return
	end
	local route = plan.route
	d:Bar(math.max(0, math.min(1, skill / math.max(1, plan.target))))
	if route.crafts > 0 then
		local goal = ns.Plan.Goal()
		local money = route.total < 0 and L["%s profit"]:format(Calc.Money(-route.total)) or Calc.Money(route.total)
		local text
		if goal ~= "cost" then
			text = (route.complete and L["About %d crafts to go, %s %s."] or L["About %d crafts to go, %s and up %s."])
				:format(route.crafts, money, ns.Plan.GOAL_LONG[goal])
		else
			text = (route.complete and L["About %d crafts to go, %s."] or L["About %d crafts to go, %s and up."])
				:format(route.crafts, money)
		end
		d:Line(text, "small", "TEXT")
	end

	-- Now: the first step, as a card. Then the rest, numbered.
	local n, current = 0, nil
	for _, s in ipairs(route.steps) do
		if s.kind == "craft" or s.kind == "tool" or s.kind == "rank" then
			n = n + 1
			if not current then
				current = s
				-- (Its light starts under the heading's gap, round the card itself.)
				local top = d.y + 6
				if s.kind == "rank" then
					RankCard(d, s, n)
					d:GlowFrom(top)
				else
					StepCard(d, ctx, s, n, top)
				end
				if n < #route.steps then
					d:Heading(ns.Plan.Goal() == "cost" and L["Then (Each Step's Materials, All Crafts)"]
						or L["Then (Each Step's Cost After What You Make, All Crafts)"])
				end
			elseif s.kind == "craft" or s.kind == "tool" then
				local sub = s.kind == "tool" and L["make 1: the next recipes need it"] or L["make about %d"]:format(s.count)
				if s.learn then
					local price = s.learn > 0 and Calc.Money(s.learn) or nil
					local how
					if s.source == "vendor" then
						how = price and L["buy the recipe first (%s)"]:format(price) or L["buy the recipe first"]
					elseif s.source == "auction" then
						how = price and L["buy the recipe on the Auction House first (%s)"]:format(price)
							or L["buy the recipe on the Auction House first"]
					else
						how = price and L["learn it first (%s)"]:format(price) or L["learn it first"]
					end
					sub = sub .. " · " .. how
				end
				local range = s.kind == "tool" and L["at %d"]:format(s.at) or L["%d to %d"]:format(s.from, s.to)
				local money, ink = Net(s.cost)
				d:Row({ left = ("%d.  %s   %s"):format(n, range, RecipeName(s.spell)), leftInk = "TEXT",
					right = s.complete and money or "?", rightInk = s.complete and ink or "OFF",
					sub = sub, subInk = s.learn and "WARN" or "OFF", tip = SpellTip(s.spell),
					onClick = not s.learn and ctx.pick and function() ctx.pick(s.spell) end or nil })
			else
				d:Line(("%d.  "):format(n) .. TrainAt(s), "small", "WARN", 4)
			end
		elseif s.kind == "gap" then
			-- (Nothing in the data gives points there: the route goes on where something does.)
			if s.to and s.to > s.at then
				d:Line(L["From %d to %d no recipe in the data gives points: you'll need one it doesn't know of."]:format(s.at, s.to),
					"small", "WARN", 4)
			else
				d:Line(L["Past %d no recipe in the data gives points yet."]:format(s.at), "small", "OFF", 4)
			end
		end
	end

	-- Cheaper than the step right now (prices move): offered, not in the way.
	local picks = ns.Plan.CraftNext(3)
	if current and current.kind == "craft" and picks[1] and picks[1].spell ~= current.spell then
		d:Heading(L["Also Good Right Now"])
		for _, e in ipairs(picks) do
			d:Row({ left = RecipeName(e.spell), leftInk = "TEXT",
				right = e.perPoint and L["%s a point"]:format(Calc.Money(e.perPoint)) or L["no price"],
				rightInk = e.perPoint and "VALUE" or "OFF", sub = L["%s chance"]:format(Pct(e.chance)), subInk = "OFF",
				tip = SpellTip(e.spell), onClick = ctx.pick and function() ctx.pick(e.spell) end or nil })
		end
	end
	d:Gap(6)
	Pages.Prices(d)
end

-- ---------------------------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------------------------

local function QueueMenu(row, i)
	local Q = ns.Queue
	local keys = { "up", "down", "remove" }
	local words = { up = L["Move Up"], down = L["Move Down"], remove = L["Remove"] }
	ns.API.Menu(row, keys, words, nil, function(key)
		if key == "up" then Q.Move(i, -1) elseif key == "down" then Q.Move(i, 1) else Q.Remove(i) end
	end, 140, { atCursor = true })
end

function Pages.Queue(d, ctx)
	local Q, Craft = ns.Queue, ns.Craft
	local list = Q.List()
	if #list == 0 then
		d:Line(L["Nothing queued."], "body", "OFF")
		d:Line(L["Queue a recipe from the Recipes tab, or a step of the Leveling Guide."], "small", "OFF")
		return
	end
	local here, at = Q.NextHere()
	local buttons = {}
	if here and ctx.make then
		local can = Craft.Count(here.spell)
		local n = math.min(here.count, can)
		buttons[#buttons + 1] = { text = can > 0 and L["Craft Next: %s x %d"]:format(RecipeName(here.spell), n) or L["Craft Next"],
			off = can < 1 or Craft.Making() ~= nil, onClick = function() Craft.Make(here.spell, n) end }
	end
	buttons[#buttons + 1] = { text = L["Clear"], onClick = function() Q.Clear() end }
	d:Buttons(buttons)
	if here and ctx.make and Craft.Count(here.spell) < 1 then
		d:Line(L["You're short of materials for the next one: see below."], "small", "WARN")
	end
	d:Heading(L["Queued"])
	for i, e in ipairs(list) do
		local mine = e.line == S.line and not S.linked
		local can = mine and Craft.Count(e.spell) or nil
		local sub = ns.Tips and ns.Tips.LineName(e.line) or ""
		if can then sub = sub .. " · " .. L["you can make %d"]:format(can) end
		d:Row({ left = ("%s x %d"):format(RecipeName(e.spell), e.count), leftInk = mine and "VALUE" or "TEXT",
			marked = i == at, sub = sub, subInk = "OFF", rightClick = true,
			tip = function(tip)
				tip:SetSpellByID(e.spell)
				tip:AddLine(" ")
				tip:AddLine(L["Click to see it · right-click to move or remove"], Color("LABEL"))
			end,
			onClick = function(button, row)
				if button == "RightButton" then
					QueueMenu(row, i)
				elseif mine and ctx.pick then
					ctx.pick(e.spell)
				end
			end })
	end
	local needs = Q.Needs()
	local items = {}
	for itemID, n in pairs(needs) do items[#items + 1] = { itemID = itemID, n = n } end
	if #items == 0 then return end
	table.sort(items, function(a, b) return a.n > b.n end)
	d:Heading(L["Materials for the Queue"])
	for _, it in ipairs(items) do MaterialRow(d, it.itemID, it.n, 0) end
end

-- The big window's Materials tab: what the route needs, and where it comes from.
function Pages.Materials(d)
	local why = NoPlan()
	if why then
		d:Line(why, "small", "OFF")
		return
	end
	Pages.Prices(d)
	local plan = ns.Plan.Get()
	if not plan then return end
	d:Heading(L["For the Route to %d"]:format(plan.target))
	if (S.skill or 0) >= plan.target then
		d:Line(L["You've reached your target."], "small", "GOOD")
		return
	end
	Pages.Shopping(d, plan)
end
