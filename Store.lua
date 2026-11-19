-- What Glowey's Recipes keeps between sessions, for every character on the account: professions and
-- their skill, the recipes each knows, and what each holds (bags, bank, mail), plus the bank tabs
-- the whole account shares and what vendors you've visited sell. Everything is read when the game
-- says it changed (a bag change settled, the bank or mailbox open, a merchant open), a moment
-- later and once, never on a timer. Nothing needs another addon.
local _, ns = ...
if not ns.ok then return end

local Store = {}
ns.Store = Store

-- Bumped after every read of bags, bank, mail or a merchant: the plan keys its shopping list on it.
Store.version = 0

local DB_VERSION = 1

local function DB()
	local db = _G.DaylightRecipesDB
	if type(db) ~= "table" then
		db = {}
		_G.DaylightRecipesDB = db
	end
	if db.version ~= DB_VERSION then
		db.version = DB_VERSION
		db.chars = type(db.chars) == "table" and db.chars or {}
		db.account = type(db.account) == "table" and db.account or {}
		db.vendors = type(db.vendors) == "table" and db.vendors or {}
		db.prices = type(db.prices) == "table" and db.prices or {}
	end
	return db
end
Store.DB = DB

local me              -- this character's GUID
local function Me()
	if not me then me = UnitGUID("player") end
	return me
end

-- This character's record (made the first time it's asked for).
function Store.Char()
	local guid = Me()
	if not guid then return nil end
	local chars = DB().chars
	local c = chars[guid]
	if not c then
		c = { prof = {}, known = {}, bags = {}, bank = {}, mail = {} }
		chars[guid] = c
	end
	if not c.named then
		c.name = UnitName("player")
		c.realm = GetRealmName and GetRealmName() or c.realm
		c.faction = ns.Faction()
		c.class = select(2, UnitClass("player"))
		c.named = true
	end
	return c
end

-- The key prices and vendors are kept under: realm and faction share an auction house.
function Store.RealmKey()
	return (GetRealmName and GetRealmName() or "?") .. "-" .. ns.Faction()
end

-- ---------------------------------------------------------------------------------------------
-- Professions and known recipes (from Core and Where as they read them)
-- ---------------------------------------------------------------------------------------------

function Store.SaveProfession(line, skill, max)
	if not line then return end
	local c = Store.Char()
	if not c then return end
	c.prof[line] = { skill = skill or 0, max = max or 0 }
end

-- A profession this character unlearned: its skill, known recipes and Leveling Guide are forgotten
-- (its alts' view, the buy lists and the trainer's list read them).
function Store.ForgetProfession(line)
	local c = Store.Char()
	if not c or not line then return end
	if type(c.prof) == "table" then c.prof[line] = nil end
	if type(c.known) == "table" then c.known[line] = nil end
	if type(c.plans) == "table" then c.plans[line] = nil end
	Store.version = Store.version + 1
end

-- set: spell -> true, every recipe of `line` this character knows.
function Store.SaveKnown(line, set)
	if not line or type(set) ~= "table" then return end
	local c = Store.Char()
	if not c then return end
	-- (Only this profession's: a list read just as the window switched profession can hold the
	-- other one's.)
	local copy = {}
	for spell in pairs(set) do
		local data = ns.Recipes and ns.Recipes[spell]
		if data and data[1] == line then copy[spell] = true end
	end
	c.known[line] = copy
	Store.version = Store.version + 1
end

-- The other characters on this realm and faction (the ones you can mail): guid -> record.
local alts, altsAt
function Store.Alts()
	if alts and altsAt == Store.version then return alts end
	local out = {}
	local guid = Me()
	local realm, faction = GetRealmName and GetRealmName(), ns.Faction()
	for g, c in pairs(DB().chars) do
		if g ~= guid and type(c) == "table" and c.realm == realm and c.faction == faction then out[g] = c end
	end
	alts, altsAt = out, Store.version
	return out
end

-- The characters on the account who know a recipe: { name, ... } (this one included), each in its
-- class color when `colored`.
function Store.WhoKnows(spell, colored)
	local data = ns.Recipes and ns.Recipes[spell]
	local line = data and data[1]
	if not line then return {} end
	local out = {}
	for _, c in pairs(DB().chars) do
		local set = type(c) == "table" and c.known and c.known[line]
		if set and set[spell] and c.name then out[#out + 1] = c end
	end
	table.sort(out, function(a, b) return ns.NameLess(a.name, b.name) end)
	for i, c in ipairs(out) do
		out[i] = colored and ns.Learn and ns.Learn.ClassName(c) or c.name
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- What's held: bags, bank, mail
-- ---------------------------------------------------------------------------------------------

local function ReadBag(bag, into)
	local get = C_Container and C_Container.GetContainerNumSlots
	local info = C_Container and C_Container.GetContainerItemInfo
	if not get or not info then return end
	local slots = get(bag) or 0
	for slot = 1, slots do
		local item = info(bag, slot)
		-- (Bound items count too: a soulbound reagent is still yours to use.)
		if item and item.itemID then
			into[item.itemID] = (into[item.itemID] or 0) + (item.stackCount or 1)
		end
	end
end

-- Whether two counts tables hold the same (a craft that used nothing the plan counts changes none).
local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Each read says whether anything changed: only then is the plan's list worked out again.
local function ReadBags()
	local c = Store.Char()
	if not c then return false end
	local bags = {}
	local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
	for bag = 0, math.max(NUM_BAG_SLOTS or 4, last) do ReadBag(bag, bags) end
	c.bagsAt = time()
	if Same(c.bags, bags) then return false end
	c.bags = bags
	return true
end

local bankOpen = false

-- The bank: Forever's tabs (this character's, and the account's shared ones), or the old bank and
-- its bag slots on a client without tabs.
-- A bank tab that does not report its slots yet (just after the bank opens): not read yet.
local function TabsReady(tabs)
	local get = C_Container and C_Container.GetContainerNumSlots
	for _, bag in ipairs(tabs) do
		if not get or (get(bag) or 0) == 0 then return false end
	end
	return true
end

local bankTries = 0
local ReadBank
function ReadBank()
	if not bankOpen then return false end
	local c = Store.Char()
	if not c then return false end
	local mine, shared = {}, nil
	local fetch = C_Bank and C_Bank.FetchPurchasedBankTabIDs
	local types = Enum and Enum.BankType
	if fetch and types then
		local canView = C_Bank.CanViewBank
		local tabs, acct
		if not canView or canView(types.Character) then
			local ok, list = pcall(fetch, types.Character)
			if ok and type(list) == "table" then tabs = list end
		end
		if not canView or canView(types.Account) then
			local ok, list = pcall(fetch, types.Account)
			if ok and type(list) == "table" then acct = list end
		end
		-- Its tabs not filled in yet: asked again shortly (a few times), never saved empty.
		if (tabs and not TabsReady(tabs)) or (acct and not TabsReady(acct)) then
			if bankTries < 5 then
				bankTries = bankTries + 1
				C_Timer.After(0.5, function()
					if bankOpen and ReadBank() then
						Store.version = Store.version + 1
						if ns.ShowingPlan() then ns.Changed() end
					end
				end)
			end
			return false
		end
		bankTries = 0
		for _, bag in ipairs(tabs or {}) do ReadBag(bag, mine) end
		if acct and #acct > 0 then
			shared = {}
			for _, bag in ipairs(acct) do ReadBag(bag, shared) end
		end
	else
		ReadBag(BANK_CONTAINER or -1, mine)
		local first = (NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do ReadBag(bag, mine) end
	end
	c.bankAt = time()
	local changed = not Same(c.bank, mine)
	c.bank = mine
	-- The account's tabs are shared by every character, whatever the realm.
	if shared then
		local db = DB()
		if not Same(db.account.bank, shared) then changed = true end
		db.account.bank = shared
	end
	return changed
end

-- The mailbox: every item waiting, except cash-on-delivery ones (not yours until you pay).
local function ReadMail()
	local c = Store.Char()
	if not c or not GetInboxNumItems or not GetInboxItem then return false end
	local mail = {}
	local n = GetInboxNumItems() or 0
	for i = 1, n do
		local cod = GetInboxHeaderInfo and select(6, GetInboxHeaderInfo(i))
		if not cod or cod == 0 then
			for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
				local _, itemID, _, count = GetInboxItem(i, j)
				if itemID then mail[itemID] = (mail[itemID] or 0) + (count or 1) end
			end
		end
	end
	c.mailAt = time()
	if Same(c.mail, mail) then return false end
	c.mail = mail
	return true
end

-- How many of an item you have: here (bags), bank (this character's and the account's), mail, and
-- each alt on this realm and faction ({ { name, count } }, most first). Totals.
function Store.Count(itemID)
	local c = Store.Char()
	-- (altHeld: the alts' bags and bank only, without their mail: what DaylightUI's bag tooltip counts.)
	local out = { bags = 0, bank = 0, mail = 0, alts = {}, altTotal = 0, altHeld = 0 }
	if not c then return out end
	out.bags = (c.bags and c.bags[itemID]) or 0
	out.bank = (c.bank and c.bank[itemID]) or 0
	local shared = DB().account.bank
	out.bank = out.bank + ((shared and shared[itemID]) or 0)
	out.mail = (c.mail and c.mail[itemID]) or 0
	for _, alt in pairs(Store.Alts()) do
		local held = ((alt.bags and alt.bags[itemID]) or 0) + ((alt.bank and alt.bank[itemID]) or 0)
		local n = held + ((alt.mail and alt.mail[itemID]) or 0)
		if n > 0 then
			out.alts[#out.alts + 1] = { name = alt.name or "?", count = n }
			out.altTotal = out.altTotal + n
			out.altHeld = out.altHeld + held
		end
	end
	table.sort(out.alts, function(a, b) return a.count > b.count end)
	out.mine = out.bags + out.bank + out.mail
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Vendors you've visited: what they sell that recipes use, and for how much (your discounts in).
-- ---------------------------------------------------------------------------------------------

local reagents        -- itemID -> true: every item a recipe in the data uses
local function Reagents()
	if reagents then return reagents end
	reagents = {}
	for _, data in pairs(ns.Recipes or {}) do
		local mats = data[3]
		for i = 1, #(mats or {}), 2 do reagents[mats[i]] = true end
	end
	return reagents
end
Store.Reagents = Reagents

local function ReadMerchant()
	if not GetMerchantNumItems or not GetMerchantItemID then return false end
	local n = GetMerchantNumItems() or 0
	if n == 0 then return false end
	local changed = false
	local want = Reagents()
	local vendors = DB().vendors
	local key = Store.RealmKey()
	local who = UnitName("npc")
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local x, y
	if map and C_Map.GetPlayerMapPosition then
		local pos = C_Map.GetPlayerMapPosition(map, "player")
		if pos then x, y = pos:GetXY() end
	end
	for i = 1, n do
		local itemID = GetMerchantItemID(i)
		if itemID and want[itemID] then
			local price, stack, extended
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local info = C_MerchantFrame.GetItemInfo(i)
				if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
			elseif GetMerchantItemInfo then
				local _, _, p, s, _, _, _, ext = GetMerchantItemInfo(i)
				price, stack, extended = p, s, ext
			end
			if price and price > 0 and not extended then
				local unit = price / math.max(1, stack or 1)
				local byRealm = vendors[key] or {}
				vendors[key] = byRealm
				local old = byRealm[itemID]
				if not old or unit <= old.unit or old.who == who then
					if not old or old.unit ~= unit then changed = true end
					byRealm[itemID] = { unit = unit, who = who, map = map, x = x and x * 100, y = y and y * 100, at = time() }
				end
			end
		end
	end
	-- (Vendor prices are kept by the price math: thrown away so the new ones count.)
	if changed and ns.Calc then ns.Calc.Forget() end
	return changed
end

-- The cheapest vendor you've seen selling an item: unit price, who, place ({ mapID, x, y }).
function Store.SeenVendor(itemID)
	local byRealm = DB().vendors[Store.RealmKey()]
	local v = byRealm and byRealm[itemID]
	if not v then return nil end
	return v.unit, v.who, v.map and { mapID = v.map, x = v.x, y = v.y } or nil
end

-- ---------------------------------------------------------------------------------------------
-- Events: each read once, a moment after the last change
-- ---------------------------------------------------------------------------------------------

local pending = {}
local function Soon(what, fn, delay)
	if pending[what] then return end
	pending[what] = true
	C_Timer.After(delay or 0.5, function()
		pending[what] = nil
		local ok, changed = pcall(fn)
		if not ok then
			geterrorhandler()(changed)
			return
		end
		-- Only what changed, and only the page that shows it (the Leveling Guide's list).
		if not changed then return end
		Store.version = Store.version + 1
		if ns.Changed and ns.ShowingPlan() then ns.Changed() end
		-- (The buy lists at a vendor or the Auction House count from this read, window or not.)
		if ns.Shop then ns.Shop.Refresh() end
	end)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MERCHANT_SHOW" }) do
	pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Store.Char()
		Soon("bags", ReadBags, 2)
	elseif event == "BAG_UPDATE_DELAYED" then
		Soon("bags", ReadBags)
		if bankOpen then Soon("bank", ReadBank) end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		Soon("bank", ReadBank, 0.2)
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" then
		if bankOpen then Soon("bank", ReadBank) end
	elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
		Soon("mail", ReadMail)
	elseif event == "MERCHANT_SHOW" then
		-- (Forever can show the merchant's window a moment after the event.)
		Soon("merchant", ReadMerchant, 0.3)
	end
end)
