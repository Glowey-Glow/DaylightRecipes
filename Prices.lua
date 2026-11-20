-- Auction House prices of Glowey's Recipes' own, for when DaylightMogul isn't loaded. With Mogul
-- loaded its prices are used and nothing here runs at all: no events heard, no scan offered, so
-- the two never read the Auction House twice.
-- Prices come from what you look at anyway (every browse and search result while the Auction House
-- is open), and from one full scan you can start from the pane: a single "everything" browse, its
-- pages asked for as the server allows, the results gone through a few hundred a frame. Only items
-- recipes use, make or disenchant into are kept (lowest buyout and when it was seen), per realm and
-- faction.
local _, ns = ...
if not ns.ok then return end
local L = ns.L

local Prices = {}
ns.Prices = Prices

local STALE = 14 * 24 * 3600     -- a price older than two weeks isn't used
local PER_FRAME = 400            -- browse results gone through per frame

-- Whether DaylightMogul's prices are in use (then this module stays quiet).
function Prices.Mogul()
	local M = _G.DaylightMogul
	return type(M) == "table" and type(M.API) == "table" and type(M.API.Price) == "function"
end

local function Book()
	local db = ns.Store.DB()
	local key = ns.Store.RealmKey()
	local book = db.prices[key]
	if not book then
		book = { items = {} }
		db.prices[key] = book
	end
	return book
end

-- The lowest buyout you've seen for one item, or nil (none, or too old).
function Prices.Get(itemID)
	local row = Book().items[itemID]
	if not row or not row.p then return nil end
	if time() - (row.t or 0) > STALE then return nil end
	return row.p
end

-- Whether any price of ours is known (for the "no Auction House prices" note).
function Prices.Has()
	return next(Book().items) ~= nil
end

-- When the last full scan finished, or nil.
function Prices.LastScan()
	return Book().scanned
end

-- itemID -> true: what's worth a price (materials, what recipes make, what disenchanting gives).
local wanted
local function Wanted()
	if wanted then return wanted end
	wanted = {}
	for item in pairs(ns.Store.Reagents()) do wanted[item] = true end
	for _, data in pairs(ns.Recipes or {}) do
		local out = data[4]
		if type(out) == "table" and out[1] then wanted[out[1]] = true end
	end
	for _, profile in pairs(ns.DisenchantProfiles or {}) do
		for _, row in ipairs(profile) do wanted[row[1]] = true end
	end
	return wanted
end

-- quantity: how many are up (a browse result's total), when known: kept as q, added up over an
-- item's keys in one scan.
local function Seen(itemID, copper, items, stamp, quantity)
	if not itemID or not copper or copper <= 0 or not Wanted()[itemID] then return end
	local row = items[itemID]
	if row and row.t == stamp then
		if type(quantity) == "number" then row.q = (row.q or 0) + quantity end
		-- In one scan an item can show under several keys (its suffixes): the lowest wins.
		if row.p <= copper then return end
		row.p = copper
		return
	end
	items[itemID] = { p = copper, t = stamp, q = type(quantity) == "number" and quantity or nil }
end

-- How many of an item were up when its price was read, or nil (not known).
function Prices.Quantity(itemID)
	local row = Book().items[itemID]
	if not row or time() - (row.t or 0) > STALE then return nil end
	return row.q
end

-- ---------------------------------------------------------------------------------------------
-- Daylight UI's prices
-- ---------------------------------------------------------------------------------------------
-- Daylight UI 2.0's own Auction House keeps a price for every item it sees: its searches, its
-- browses and its Full scan. That scan reads the game's whole-house list, which never passes the
-- browse events heard below, so without this a material Daylight UI has a price for could stand
-- here with none (and the guide then rated every recipe using it as unpriced). Its prices are read
-- here, and one wins over ours when it was seen later. Read only: nothing of its is written, and
-- nothing of its is scanned from here.
-- Daylight UI has no public call for prices (nothing in its API.md), so this goes through its
-- module's own tables, which a later Daylight UI may change without notice; every step is checked
-- and wrapped, and when one is missing our own prices are used as before:
--   DaylightUI:GetModule("AuctionHouse") (Core.lua:721), registered with ns = ns
--     (DaylightUI_AuctionHouse\Module.lua:5-8), .enabled once it runs (Core.lua:773);
--   ns.Ruleset.Key() (Ruleset.lua:54) names the price book of this realm's rules;
--   ns.Store.Min / SeenAt / Seen / Count / LastAt (Store.lua:80-131): the lowest unit buyout of the
--     last sighting, when (the server's clock), how many were up (0 when it wasn't told), how many
--     items it knows, when anything was last seen. Keys are the item's ID as text.
--   ns.On("PricesChanged", fn) (Base.lua:21; fired once a batch, Scan.lua:155).
local function DaylightBook()
	local D = _G.DaylightUI
	if type(D) ~= "table" or D.ahMogul == true or type(D.GetModule) ~= "function" then return nil end
	local ok, mod = pcall(D.GetModule, D, "AuctionHouse")
	if not ok or type(mod) ~= "table" or mod.enabled ~= true then return nil end
	local m = mod.ns
	if type(m) ~= "table" or type(m.Store) ~= "table" or type(m.Ruleset) ~= "table" then return nil end
	if type(m.Store.Min) ~= "function" or type(m.Store.SeenAt) ~= "function" or type(m.Ruleset.Key) ~= "function" then
		return nil
	end
	local got, rkey = pcall(m.Ruleset.Key)
	if not got or rkey == nil then return nil end
	return m.Store, rkey
end

local function Now() return _G.GetServerTime and _G.GetServerTime() or time() end

-- Daylight UI's price for an item: copper and how old it is, or nil (none, or over our two weeks).
local function Daylight(itemID)
	if not ns.Get("useAH") then return nil end
	local store, rkey = DaylightBook()
	if not store then return nil end
	local key = tostring(itemID)
	local ok, copper = pcall(store.Min, rkey, key)
	if not ok or type(copper) ~= "number" or copper <= 0 then return nil end
	local got, at = pcall(store.SeenAt, rkey, key)
	if not got or type(at) ~= "number" then return nil end
	local age = Now() - at
	if age > STALE then return nil end
	return copper, age
end

-- Whether its price is the one to use: it has one, and ours isn't the later sighting.
local function DaylightWins(itemID)
	local copper, age = Daylight(itemID)
	if not copper then return nil end
	local row = Book().items[itemID]
	if row and row.p and time() - (row.t or 0) < age then return nil end
	return copper
end

-- Whether Daylight UI's prices are being read, and when it last saw anything (on this clock).
function Prices.Daylight()
	return ns.Get("useAH") and DaylightBook() ~= nil or false
end

function Prices.DaylightAt()
	local store, rkey = DaylightBook()
	if not store or type(store.LastAt) ~= "function" then return nil end
	local ok, at = pcall(store.LastAt, rkey)
	if not ok or type(at) ~= "number" then return nil end
	return time() - math.max(0, Now() - at)
end

local OwnGet, OwnQuantity, OwnHas = Prices.Get, Prices.Quantity, Prices.Has

function Prices.Get(itemID)
	return DaylightWins(itemID) or OwnGet(itemID)
end

function Prices.Quantity(itemID)
	if DaylightWins(itemID) then
		local store, rkey = DaylightBook()
		local seen
		if type(store.Seen) == "function" then
			local ok, v = pcall(store.Seen, rkey, tostring(itemID))
			if ok then seen = v end
		end
		local q = type(seen) == "table" and seen.q or nil
		-- (Its 0 is "not told how many", never "none": an item it saw had at least one up.)
		return type(q) == "number" and q > 0 and q or nil
	end
	return OwnQuantity(itemID)
end

function Prices.Has()
	if OwnHas() then return true end
	local store, rkey = DaylightBook()
	if not store or type(store.Count) ~= "function" then return false end
	local ok, n = pcall(store.Count, rkey)
	return ok and type(n) == "number" and n > 0 or false
end

-- Its prices changed (a scan's batch): everything worked out from prices is worked out again.
local function DaylightChanged()
	if ns.Calc then ns.Calc.Forget() end
	if ns.Plan and ns.Plan.Forget then ns.Plan.Forget() end
	if ns.ShowingPlan() then ns.Changed() end
end

local function HearDaylight()
	local D = _G.DaylightUI
	if type(D) ~= "table" or type(D.GetModule) ~= "function" then return end
	local ok, mod = pcall(D.GetModule, D, "AuctionHouse")
	local m = ok and type(mod) == "table" and mod.ns or nil
	if type(m) == "table" and type(m.On) == "function" then pcall(m.On, "PricesChanged", DaylightChanged) end
end

-- ---------------------------------------------------------------------------------------------
-- Results, a few hundred a frame
-- ---------------------------------------------------------------------------------------------

-- (An explicit end: `#` can't be trusted on a table whose front has been cleared.)
local queue, head, tail = {}, 1, 0
local stamp               -- one time for a whole scan or browse: the lowest of an item's keys wins
local worker = CreateFrame("Frame")
worker:Hide()
local function Work()
	local items = Book().items
	local stop = math.min(tail, head + PER_FRAME - 1)
	for i = head, stop do
		local r = queue[i]
		local key = r and r.itemKey
		if key and r.minPrice then Seen(key.itemID, r.minPrice, items, stamp, r.totalQuantity) end
	end
	head = stop + 1
	if head > tail then
		queue, head, tail = {}, 1, 0
		worker:Hide()
		if ns.Calc then ns.Calc.Forget() end
		if ns.ShowingPlan() then ns.Changed() end
	end
end
worker:SetScript("OnUpdate", Work)

local function Queue(results)
	if type(results) ~= "table" then return end
	if tail == 0 then stamp = time() end
	for _, r in ipairs(results) do
		tail = tail + 1
		queue[tail] = r
	end
	worker:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The full scan
-- ---------------------------------------------------------------------------------------------

local ahOpen, scanning = false, false
local firstRead = false   -- a scan's first page has been read

-- (Not while Daylight UI's own Auction House window is the one in use and its prices are read:
-- its Full scan fills the book above, and two scans would share the game's one request line.)
local function DaylightScans()
	if not Prices.Daylight() then return false end
	local D = _G.DaylightUI
	if type(D) ~= "table" or type(D.ahCovers) ~= "function" then return false end
	local ok, covers = pcall(D.ahCovers)
	return ok and covers and true or false
end

function Prices.CanScan()
	return ahOpen and not scanning and not Prices.Mogul() and C_AuctionHouse ~= nil and not DaylightScans()
end

function Prices.Scanning() return scanning end

local function Ready()
	local ready = C_AuctionHouse.IsThrottledMessageSystemReady
	return not ready or ready()
end

-- A page asked for and no answer for this long: asked again, and after a few tries the scan ends
-- with what it has (the server can drop a request).
local WAIT, TRIES = 5, 3
local asked, tries = 0, 0

local function Finish(text)
	scanning = false
	if text then ns.Print(text) end
	if ns.ShowingPlan() then ns.Changed() end
end

local More
local function Watch(serial)
	C_Timer.After(WAIT, function()
		if not scanning or serial ~= asked then return end
		tries = tries + 1
		if tries >= TRIES then
			Finish(L["The Auction House stopped answering: prices read so far are kept."])
		else
			More()
		end
	end)
end

function More()
	if not scanning or not ahOpen then scanning = false return end
	if C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults() then
		Book().scanned = time()
		Finish(L["Auction House prices read."])
		return
	end
	if not Ready() then C_Timer.After(0.3, More) return end
	pcall(C_AuctionHouse.RequestMoreBrowseResults)
	asked = asked + 1
	Watch(asked)
end

function Prices.Scan()
	if not Prices.CanScan() then return end
	if not Ready() then
		ns.Print(L["The Auction House is busy: try again in a moment."])
		return
	end
	local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
	local ok = pcall(C_AuctionHouse.SendBrowseQuery, { searchString = "", sorts = { { sortOrder = order, reverseSort = false } },
		filters = {}, itemClassFilters = {} })
	if not ok then
		ns.Print(L["The Auction House didn't take the scan."])
		return
	end
	scanning, firstRead, tries = true, false, 0
	asked = asked + 1
	Watch(asked)
	ns.Print(L["Reading Auction House prices..."])
	if ns.ShowingPlan() then ns.Changed() end
end

-- ---------------------------------------------------------------------------------------------
-- Events (only when DaylightMogul isn't there)
-- ---------------------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if not Prices.Mogul() then HearDaylight() end
		if Prices.Mogul() or not C_AuctionHouse then return end
		for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
			"AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
			pcall(self.RegisterEvent, self, e)
		end
		return
	end
	if event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
		if ns.ShowingPlan() then ns.Changed() end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen, scanning = false, false
		-- (What Daylight UI saw in its searches this visit is read from here on.)
		if Prices.Daylight() then DaylightChanged() end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		-- (An answer came: the watch on the last request stands down.)
		if scanning then
			asked = asked + 1
			tries = 0
		end
	end
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		-- The whole list so far: read in full for a browse of yours and for a scan's first page;
		-- a scan's later pages come one by one (ADDED below).
		if not scanning or not firstRead then
			Queue(C_AuctionHouse.GetBrowseResults())
			if scanning then firstRead = true end
		end
		if scanning then C_Timer.After(0.1, More) end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		Queue(arg)
		if scanning then C_Timer.After(0.1, More) end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		local get = C_AuctionHouse.GetCommoditySearchResultInfo
		local info = get and arg and get(arg, 1)
		if info and info.unitPrice then
			Seen(arg, info.unitPrice, Book().items, time())
			if ns.Calc then ns.Calc.Forget() end
		end
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		-- (The rows follow your sort and some are bids only: the lowest buyout among them.)
		local get, count = C_AuctionHouse.GetItemSearchResultInfo, C_AuctionHouse.GetNumItemSearchResults
		if get and count and type(arg) == "table" and arg.itemID then
			local best
			for i = 1, count(arg) or 0 do
				local info = get(arg, i)
				local buy = info and info.buyoutAmount
				if buy and buy > 0 and (not best or buy < best) then best = buy end
			end
			if best then
				Seen(arg.itemID, best, Book().items, time())
				if ns.Calc then ns.Calc.Forget() end
			end
		end
	end
end)
