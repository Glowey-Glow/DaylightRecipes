-- The numbers: what a material costs (Auction House through DaylightMogul, or a vendor with your
-- reputation and Bartering), the chance a craft gives a skill point (with Overtime), what the
-- made item sells, vendors and disenchants for. Every answer is kept until something it hangs
-- on changes (prices, talents, reputation, a setting): Calc.Forget().
local _, ns = ...
if not ns.ok then return end
local L = ns.L

local Calc = {}
ns.Calc = Calc

local floor, max, min = math.floor, math.max, math.min

local cache = {}   -- "kind:id" -> answer
local NONE = {}

-- Bumped whenever the answers are thrown away (prices, talents, reputation, a setting): the plan
-- keys its own cache on it.
Calc.version = 0

function Calc.Forget()
	cache = {}
	Calc.version = Calc.version + 1
end

local function Kept(key, fn)
	local v = cache[key]
	if v == nil then
		v = fn()
		cache[key] = v == nil and NONE or v
	end
	if v == NONE then return nil end
	return v
end

-- ---------------------------------------------------------------------------------------------
-- Profession talents (Forever's legacy profession tree)
-- ---------------------------------------------------------------------------------------------

local OVERTIME, BARTERING = 1225451, 1225459
local RANKS = {
	[OVERTIME] = { 0.04, 0.08, 0.12, 0.16, 0.20 },   -- skill-up chance, x (1 + this)
	[BARTERING] = { 0.05, 0.10 },                     -- vendor prices, x (1 - this)
}

local function ReadRanks()
	if not C_Traits or not C_Traits.GetConfigIDByTreeID then return nil end
	local tree = Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_TREE_PROFESSIONS_ID or 1187
	local config = C_Traits.GetConfigIDByTreeID(tree)
	if not config then return nil end
	local nodes = C_Traits.GetTreeNodes(tree)
	if type(nodes) ~= "table" then return nil end
	local ranks = {}
	for _, nodeID in ipairs(nodes) do
		local node = C_Traits.GetNodeInfo(config, nodeID)
		for _, entryID in ipairs(node and node.entryIDs or {}) do
			local entry = C_Traits.GetEntryInfo(config, entryID)
			local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			local spell = def and (def.spellID or def.overriddenSpellID)
			if RANKS[spell] then
				-- Only ranks already learned count, not ones picked but not yet applied.
				local committed = false
				for _, id in ipairs(node.entryIDsWithCommittedRanks or {}) do
					if id == entryID then committed = true break end
				end
				ranks[spell] = committed and (node.ranksPurchased or 0) or 0
			end
		end
	end
	return ranks
end

-- overtime, bartering: the bonus each gives now (0 with none, or with the setting off).
function Calc.Talents()
	local t = Kept("talents", function()
		local ok, ranks = pcall(ReadRanks)
		ranks = ok and ranks or {}
		return { overtime = RANKS[OVERTIME][ranks[OVERTIME] or 0] or 0, overtimeRank = ranks[OVERTIME] or 0,
			bartering = RANKS[BARTERING][ranks[BARTERING] or 0] or 0, barteringRank = ranks[BARTERING] or 0 }
	end)
	if not ns.Get("talents") then return 0, 0, t end
	return t.overtime, t.bartering, t
end

-- ---------------------------------------------------------------------------------------------
-- Skill-up chance
-- ---------------------------------------------------------------------------------------------

-- Recipes whose yellow and gray skill ForeverRecipes' table has otherwise than the game are set right
-- from ns.ClientRanges (Data/Client.lua, made by Tools/client.py from the client's own table):
-- { yellow, gray }. Most are Forever's own additions (First Aid Kit, Anvil, ...), which the table
-- gives five points of range (20 to 25, 140 to 145) where the game gives none: yellow and gray at
-- one skill is gray from there on.
local fixed = {}   -- spell -> its thresholds set right (made once)

-- The recipe's four skill thresholds (orange from, yellow, green, gray), or nil when unknown.
function Calc.Thresholds(spell)
	local data = ns.Recipes and ns.Recipes[spell]
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if not data or type(data[2]) ~= "table" then return nil end
	if meta and meta.thresholdsKnown == false then return nil end
	local range = ns.ClientRanges and ns.ClientRanges[spell]
	if range then
		local t = fixed[spell]
		if not t then
			-- (Green is halfway, as the game has it and as every recipe of the data does.)
			t = { data[2][1], range[1], floor((range[1] + range[2]) / 2), range[2] }
			fixed[spell] = t
		end
		return t
	end
	return data[2]
end

-- The game's own word on a recipe you know: its difficulty (0 orange, 1 yellow, 2 green, 3 gray),
-- whether it can still give points, and how many one craft gives. nil for one you don't know (the
-- game only rates those) or a client without it.
local function Live(spell)
	local info = ns.Ask("GetRecipeInfo", spell)
	if type(info) ~= "table" or not info.learned then return nil end
	return info.relativeDifficulty, info.canSkillUp, tonumber(info.numSkillUps)
end

-- The game's color step for a recipe you know: 1 orange, 2 yellow, 3 green, 4 gray (nil otherwise).
function Calc.Step(spell)
	local color, canSkillUp = Live(spell)
	if canSkillUp == false then return 4 end
	if type(color) == "number" and color >= 0 and color <= 3 then return color + 1 end
	return nil
end

-- Skill points one craft gives (some give two or more), 1 when the game doesn't say.
function Calc.SkillUps(spell)
	local _, _, n = Live(spell)
	return (n and n > 0) and n or 1
end

-- The chance on yellow and green when the data's thresholds disagree with the game's color (the
-- data is Classic's; Forever retuned some): a typical value for that color.
local COLOR_GUESS = { [1] = 0.75, [2] = 0.25 }

-- chance (0-1, talents in), base (without talents), state: "ok", "cap" (no points left at this
-- skill), "unknown" (no thresholds for it). For a recipe you know, the game's own color decides:
-- orange is a sure point, gray none; on yellow and green the thresholds give the odds.
function Calc.Chance(spell, skill, cap)
	if cap and cap > 0 and skill >= cap then return 0, 0, "cap" end
	local color, canSkillUp = Live(spell)
	if canSkillUp == false or color == 3 then return 0, 0, "ok" end
	local base
	if color == 0 then
		base = 1
	else
		local t = Calc.Thresholds(spell)
		if t then
			local yellow, grey = t[2], t[4]
			if grey <= yellow then
				base = skill < grey and 1 or 0
			else
				base = max(0, min(1, (grey - skill) / (grey - yellow)))
			end
			-- The game says yellow or green where the data has another color: the data is off here.
			-- (By color, not by the odds: the first yellow point is still a sure one, and a recipe
			-- the game shows green is never taken for a yellow one on the data's word.)
			if color and COLOR_GUESS[color] then
				local mine = skill >= grey and 3 or skill < yellow and 0 or skill < t[3] and 1 or 2
				if mine ~= color then base = COLOR_GUESS[color] end
			end
		elseif color and COLOR_GUESS[color] then
			base = COLOR_GUESS[color]
		else
			return nil, nil, "unknown"
		end
	end
	local overtime = Calc.Talents()
	return min(1, base * (1 + overtime)), base, "ok"
end

-- ---------------------------------------------------------------------------------------------
-- Prices
-- ---------------------------------------------------------------------------------------------

local function Mogul(itemID, source)
	if not ns.Get("useAH") and source ~= "vendorbuy" then return nil end
	local M = _G.DaylightMogul
	local price = type(M) == "table" and type(M.API) == "table" and M.API.Price
	if type(price) ~= "function" then return nil end
	local ok, copper = pcall(price, itemID, source)
	if ok and type(copper) == "number" and copper > 0 then return copper end
end

-- Whether Auction House prices are in use: DaylightMogul's when it's loaded, else our own (read
-- while you browse, or by a scan from the Leveling Guide).
function Calc.HasAH()
	if not ns.Get("useAH") then return false end
	if ns.Prices and ns.Prices.Mogul() then return true end
	return ns.Prices ~= nil and ns.Prices.Has()
end

-- One item on the Auction House, or nil.
function Calc.AH(itemID)
	return Kept("ah:" .. itemID, function()
		if not ns.Get("useAH") then return nil end
		if ns.Prices and not ns.Prices.Mogul() then return ns.Prices.Get(itemID) end
		return Mogul(itemID, ns.Get("priceSource") or "market")
	end)
end

local DISCOUNT = { [5] = 0.05, [6] = 0.10, [7] = 0.15, [8] = 0.20 }   -- friendly .. exalted

local function Reputation(factionID)
	if not factionID or factionID <= 0 or not C_Reputation or not C_Reputation.GetFactionDataByID then return 0 end
	local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
	return ok and data and DISCOUNT[data.reaction] or 0
end

local function SellerAllowed(seller, mine)
	local npc = ns.Npcs and ns.Npcs[seller.npc]
	local side = seller.faction or (npc and npc[2])
	if side and side ~= mine then return false end
	local group = mine == "H" and 4 or 2
	if seller.factionGroup and seller.factionGroup ~= group then return false end
	if seller.enemyGroup and seller.enemyGroup > 0 and bit and bit.band(seller.enemyGroup, group) ~= 0 then return false end
	return true
end

-- One item from the cheapest vendor you can buy from: unit price, the vendor's name.
function Calc.Vendor(itemID)
	local v = Kept("vendor:" .. itemID, function()
		local _, bartering = Calc.Talents()
		local mine = ns.Faction()
		local best, who
		for _, seller in ipairs(ns.VendorSellers and ns.VendorSellers[itemID] or {}) do
			if seller.price and seller.price > 0 and SellerAllowed(seller, mine) then
				local stack = max(1, seller.stack or 1)
				local unit
				if seller.reported then
					unit = seller.price / stack   -- a price someone saw: discounts unknown, already in
				else
					unit = seller.price * (1 - Reputation(seller.repFactionID)) * (1 - bartering) / stack
				end
				if not best or unit < best then
					local npc = ns.Npcs and ns.Npcs[seller.npc]
					best, who = unit, seller.name or (npc and npc[1]) or L["Vendor"]
				end
			end
		end
		local seen = Mogul(itemID, "vendorbuy")
		if seen and (not best or seen < best) then best, who = seen, L["Vendor"] end
		-- A vendor you've been to yourself (your discounts already in its price).
		local visited, name
		if ns.Store then visited, name = ns.Store.SeenVendor(itemID) end
		if visited and (not best or visited < best) then best, who = visited, name or L["Vendor"] end
		if best then return { unit = best, who = who } end
	end)
	if v then return v.unit, v.who end
end

-- An item's price steps on the Auction House as last read, while they're fresh (Prices.Steps):
-- { at, list = { { q, p }, ... } cheapest first, full }, an empty list when none were for sale.
-- nil when not read lately, with Auction House prices off, or with DaylightMogul's prices in use
-- (it gives one price an item, no steps).
function Calc.Steps(itemID)
	if not ns.Get("useAH") or not ns.Prices or not ns.Prices.Steps then return nil end
	if ns.Prices.Mogul() then return nil end
	return ns.Prices.Steps(itemID)
end

-- What buying n of an item on the Auction House costs, walking its steps cheapest first:
--   cost     copper for the ones the steps cover
--   covered  how many of n that is (less than n: not that many for sale, or not below `below`)
--   known    whether steps were known (false: cost and covered are nil)
--   used     the steps the purchase takes, { { q, p }, ... }
-- below: only steps cheaper than this (a vendor's price for one: dearer steps aren't worth buying).
-- skip: this many of the cheapest are taken already (the route's earlier steps).
function Calc.AHCost(itemID, n, below, skip)
	local steps = Calc.Steps(itemID)
	if not steps then return nil, nil, false end
	local cost, covered, used = 0, 0, {}
	local left, over = max(0, n or 0), max(0, skip or 0)
	for _, s in ipairs(steps.list) do
		if left <= 0 or (below and s.p >= below) then break end
		local q = s.q
		if over > 0 then
			local gone = min(over, q)
			over, q = over - gone, q - gone
		end
		if q > 0 then
			local take = min(left, q)
			cost = cost + take * s.p
			covered, left = covered + take, left - take
			used[#used + 1] = { q = take, p = s.p }
		end
	end
	return floor(cost + 0.5), covered, true, used
end

-- Where n of an item are best bought, with its steps known: how many on the Auction House (the
-- ones cheaper than the cheapest vendor, as far as they go), how many from a vendor (the rest,
-- when one sells it), and true. With no vendor all n are the Auction House's, for sale or not.
-- Steps not known: nil, nil, false (Calc.Unit's one answer for the item stands).
function Calc.Split(itemID, n)
	local steps = Calc.Steps(itemID)
	if not steps then return nil, nil, false end
	local vendor = Calc.Vendor(itemID)
	if not vendor then return n, 0, true end
	local _, covered = Calc.AHCost(itemID, n, vendor)
	return covered, n - covered, true
end

-- What n of an item cost bought the cheapest way, and whether that is exact (worked out from
-- fresh steps) or the old estimate, n times Calc.Unit's price. With steps: the Auction House's
-- ones cheaper than a vendor, the rest at the vendor's price; with no vendor, what isn't for sale
-- is counted at the dearest step read (then not exact). nil when the item has no price.
-- skip: as Calc.AHCost's.
function Calc.BuyCost(itemID, n, skip)
	local vendor = Calc.Vendor(itemID)
	local cost, covered, known, used = Calc.AHCost(itemID, n, vendor, skip)
	if not known then
		local unit = Calc.Unit(itemID)
		if not unit then return nil, false end
		return floor(unit * n + 0.5), false
	end
	local rest = n - covered
	if rest <= 0 then return cost, true end
	if vendor then return floor(cost + rest * vendor + 0.5), true end
	local last = used[#used] and used[#used].p
	if not last then
		local steps = Calc.Steps(itemID)
		local top = steps.list[#steps.list]
		last = top and top.p or Calc.AH(itemID)
	end
	if not last then return nil, false end
	return floor(cost + rest * last + 0.5), false
end

-- The cheaper of the two: unit, "ah" | "vendor", the vendor's name.
-- With the item's steps known they decide: the Auction House when its cheapest step is under the
-- vendor's price (how many that holds for is Calc.Split's to say), else the vendor.
-- Without them: a vendor wins over an Auction House a little cheaper but nearly sold out (a route
-- needs more than a handful, and the vendor always has them).
local THIN = 10
function Calc.Unit(itemID)
	local vendor, who = Calc.Vendor(itemID)
	local ah = Calc.AH(itemID)
	local steps = Calc.Steps(itemID)
	if steps then
		local first = steps.list[1]
		if first and (not vendor or first.p < vendor) then return first.p, "ah" end
		if vendor then return vendor, "vendor", who end
		-- (None for sale and no vendor: the last price seen, as before.)
		if ah then return ah, "ah" end
		return nil
	end
	if ah and vendor and ah < vendor and ns.Prices and ns.Prices.Quantity then
		local q = ns.Prices.Quantity(itemID)
		if q and q < THIN then ah = nil end
	end
	if ah and (not vendor or ah < vendor) then return ah, "ah" end
	if vendor then return vendor, "vendor", who end
end

-- ---------------------------------------------------------------------------------------------
-- A recipe: materials, what it makes
-- ---------------------------------------------------------------------------------------------

-- { { itemID, count }, ... } from the game's schematic, else the data.
function Calc.Materials(spell)
	local list = {}
	local s = ns.Ask("GetRecipeSchematic", spell, false)
	if type(s) == "table" and type(s.reagentSlotSchematics) == "table" then
		for _, slot in ipairs(s.reagentSlotSchematics) do
			local r = slot.reagents and slot.reagents[1]
			local basic = slot.reagentType == nil or slot.reagentType == 1
			if basic and r and r.itemID and (slot.quantityRequired or 0) > 0 then
				list[#list + 1] = { r.itemID, slot.quantityRequired }
			end
		end
		if #list > 0 then return list end
	end
	local data = ns.Recipes and ns.Recipes[spell]
	local mats = data and data[3]
	for i = 1, #(mats or {}), 2 do list[#list + 1] = { mats[i], mats[i + 1] } end
	return list
end

-- itemID, count made (nil for an enchant or a recipe that makes nothing).
function Calc.Output(spell)
	local s = ns.Ask("GetRecipeSchematic", spell, false)
	if type(s) == "table" and type(s.outputItemID) == "number" and s.outputItemID > 0 then
		local lo = s.quantityMin or 1
		local hi = max(lo, s.quantityMax or lo)
		return s.outputItemID, (lo + hi) / 2
	end
	local data = ns.Recipes and ns.Recipes[spell]
	local out = data and data[4]
	if type(out) == "table" and out[1] then return out[1], out[2] or 1 end
end

-- { rows = { { itemID, count, unit, total, kind, who } }, total, complete }
function Calc.Cost(spell)
	return Kept("cost:" .. spell, function()
		local out = { rows = {}, total = 0, complete = true }
		for _, m in ipairs(Calc.Materials(spell)) do
			local unit, kind, who = Calc.Unit(m[1])
			local row = { itemID = m[1], count = m[2], unit = unit, kind = kind, who = who }
			if unit then
				row.total = floor(unit * m[2] + 0.5)
				out.total = out.total + row.total
			else
				out.complete = false
			end
			out.rows[#out.rows + 1] = row
		end
		return out
	end)
end

local function ItemInfo(itemID)
	local get = C_Item and C_Item.GetItemInfo or GetItemInfo
	if not get then return nil end
	local name, link, quality, _, _, _, _, _, _, icon, sell, _, _, bind = get(itemID)
	if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
	return name, link, quality, icon, sell, bind
end
Calc.ItemInfo = ItemInfo

-- ---------------------------------------------------------------------------------------------
-- Disenchanting
-- ---------------------------------------------------------------------------------------------

-- { mats = { { itemID, chance, lo, hi, each (expected count), price, value } }, value, complete }
-- or nil and why: "excluded", "none" (not gear the data knows), "unsupported".
-- The yields are the data's Classic baseline, not yet checked on Forever.
function Calc.Disenchant(itemID)
	if ns.DisenchantExcluded and ns.DisenchantExcluded[itemID] then return nil, "excluded" end
	local known = ns.DisenchantItems and ns.DisenchantItems[itemID]
	if not known then return nil, "none" end
	local profile = known[1] and ns.DisenchantProfiles and ns.DisenchantProfiles[known[1]]
	if not profile then return nil, "unsupported" end
	return Kept("de:" .. itemID, function()
		local out = { mats = {}, value = 0, complete = true }
		for _, row in ipairs(profile) do
			local each = row[2] * (row[3] + row[4]) / 2
			local price = Calc.AH(row[1])
			local m = { itemID = row[1], chance = row[2], lo = row[3], hi = row[4], each = each, price = price }
			if price then
				m.value = each * price
				out.value = out.value + m.value
			else
				out.complete = false
			end
			out.mats[#out.mats + 1] = m
		end
		return out
	end)
end

-- ---------------------------------------------------------------------------------------------
-- What one craft is worth, each way
-- ---------------------------------------------------------------------------------------------

Calc.AH_CUT = 0.05

-- { itemID, count, bound, ah, vendor, de (Calc.Disenchant's), routes = { { label, text, value, profit } } }
-- label is the English name the code compares ("Auction House"), text the one to show.
function Calc.Worth(spell)
	local itemID, count = Calc.Output(spell)
	if not itemID then return nil end
	local name, _, _, _, sell, bind = ItemInfo(itemID)
	local out = { itemID = itemID, count = count, bound = bind == 1, routes = {} }
	local cost = Calc.Cost(spell)
	local function route(label, text, value)
		if not value then return end
		out.routes[#out.routes + 1] = { label = label, text = text, value = value,
			profit = cost.complete and (value - cost.total) or nil }
	end
	if not out.bound then
		local ah = Calc.AH(itemID)
		if ah then
			out.ah = ah * count
			route("Auction House", L["Auction House"], floor(out.ah * (1 - Calc.AH_CUT) + 0.5))
		end
	end
	if name and type(sell) == "number" and sell > 0 then
		out.vendor = sell * count
		route("Vendor", L["Vendor"], out.vendor)
	end
	local de = Calc.Disenchant(itemID)
	if de then
		out.de = de
		if de.value > 0 then route("Disenchant", L["Disenchant"], floor(de.value * count + 0.5)) end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Money text
-- ---------------------------------------------------------------------------------------------

function Calc.Money(copper)
	copper = max(0, floor((copper or 0) + 0.5))
	local fn = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
	if fn then
		local ok, text = pcall(fn, copper)
		if ok and text then return text end
	end
	local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
	if g > 0 then return L["%dg %ds %dc"]:format(g, s, c) end
	if s > 0 then return L["%ds %dc"]:format(s, c) end
	return L["%dc"]:format(c)
end
