-- The numbers: what a material costs (Auction House through DaylightMogul, or a vendor with your
-- reputation and Bartering), the chance a craft gives a skill point (with Overtime), what the
-- made item sells, vendors and disenchants for. Every answer is kept until something it hangs
-- on changes (prices, talents, reputation, a setting): Calc.Forget().
local _, ns = ...
if not ns.ok then return end

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

-- The recipe's four skill thresholds (orange from, yellow, green, gray), or nil when unknown.
function Calc.Thresholds(spell)
	local data = ns.Recipes and ns.Recipes[spell]
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if not data or type(data[2]) ~= "table" then return nil end
	if meta and meta.thresholdsKnown == false then return nil end
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
			-- The game says yellow or green but the data says sure or none: the data is off here.
			if color and COLOR_GUESS[color] and (base >= 1 or base <= 0) then base = COLOR_GUESS[color] end
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
					best, who = unit, seller.name or (npc and npc[1]) or "Vendor"
				end
			end
		end
		local seen = Mogul(itemID, "vendorbuy")
		if seen and (not best or seen < best) then best, who = seen, "Vendor" end
		-- A vendor you've been to yourself (your discounts already in its price).
		local visited, name
		if ns.Store then visited, name = ns.Store.SeenVendor(itemID) end
		if visited and (not best or visited < best) then best, who = visited, name or "Vendor" end
		if best then return { unit = best, who = who } end
	end)
	if v then return v.unit, v.who end
end

-- The cheaper of the two: unit, "ah" | "vendor", the vendor's name.
-- (A vendor wins over an Auction House a little cheaper but nearly sold out: a route needs more than
-- a handful, and the vendor always has them.)
local THIN = 10
function Calc.Unit(itemID)
	local vendor, who = Calc.Vendor(itemID)
	local ah = Calc.AH(itemID)
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

-- { itemID, count, bound, ah, vendor, de (Calc.Disenchant's), routes = { { label, value, profit } } }
function Calc.Worth(spell)
	local itemID, count = Calc.Output(spell)
	if not itemID then return nil end
	local name, _, _, _, sell, bind = ItemInfo(itemID)
	local out = { itemID = itemID, count = count, bound = bind == 1, routes = {} }
	local cost = Calc.Cost(spell)
	local function route(label, value)
		if not value then return end
		out.routes[#out.routes + 1] = { label = label, value = value,
			profit = cost.complete and (value - cost.total) or nil }
	end
	if not out.bound then
		local ah = Calc.AH(itemID)
		if ah then
			out.ah = ah * count
			route("Auction House", floor(out.ah * (1 - Calc.AH_CUT) + 0.5))
		end
	end
	if name and type(sell) == "number" and sell > 0 then
		out.vendor = sell * count
		route("Vendor", out.vendor)
	end
	local de = Calc.Disenchant(itemID)
	if de then
		out.de = de
		if de.value > 0 then route("Disenchant", floor(de.value * count + 0.5)) end
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
	if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
	if s > 0 then return ("%ds %dc"):format(s, c) end
	return ("%dc"):format(c)
end
