-- Auction House prices of Glowey's Recipes' own, for when DaylightMogul isn't loaded. With Mogul
-- loaded its prices are used and nothing here runs at all: no events heard, no scan offered, so
-- the two never read the Auction House twice.
-- Prices come from what you look at anyway (every browse and search result while the Auction House
-- is open), and from one full scan you can start from the pane: a single "everything" browse, its
-- pages asked for as the server allows, the results gone through a few hundred a frame. Only items
-- recipes use, make or disenchant into are kept (lowest buyout and when it was seen), per realm and
-- faction.
-- Price steps: besides the lowest price, an item's whole ladder as last seen, "4 at 11s 75c, 51 at
-- 12s...", cheapest first (Prices.Steps), so a purchase of many is costed by what's really for sale
-- (Calc.AHCost). Read from every search result that passes while the Auction House is open, and
-- from "Check Prices" on the Auction House's buy list (Prices.Check: one search an item, one at a
-- time). Kept for the session only and trusted for FRESH seconds: a ladder changes with every
-- purchase and undercut, so one from an earlier session would be wrong more often than right.
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

-- This character's price book: its rules key's (Store.PriceBook: one Auction House for a set of
-- rules, both factions). What's read goes there.
local function Book()
	if ns.Store.PriceBook then return ns.Store.PriceBook() end
	local db = ns.Store.DB()
	local key = ns.Store.RealmKey()
	local book = db.prices[key]
	if not book then
		book = { items = {} }
		db.prices[key] = book
	end
	return book
end

-- An item's row for reading: the book's, or the one in an old "Realm-Faction" book of this
-- character's that couldn't be placed (Store.OldPriceBook), when that is the later sighting.
local function Row(itemID)
	local row = Book().items[itemID]
	local old = ns.Store.OldPriceBook and ns.Store.OldPriceBook()
	local was = old and old.items[itemID]
	if type(was) == "table" and (type(row) ~= "table" or (row.t or 0) < (was.t or 0)) then return was end
	return row
end

-- Professionally Lost's own scanned price for an item, while "Scanned Prices" is handed over
-- (ProfLost.lua: a guarded read of its Scan.Price; nothing of its is written): copper and how old
-- it is, or nil. Its prices have no age limit of their own, so ours (two weeks) is applied here.
local function Theirs(itemID)
	local P = ns.ProfLost
	if not (P and P.Handed("prices")) then return nil end
	local copper, age = P.Price(itemID)
	if not copper or not age or age > STALE then return nil end
	return copper, age
end

-- The lowest buyout seen for one item, or nil (none, or too old): ours (what you browsed or
-- scanned), or Professionally Lost's when it was seen later than ours.
function Prices.Get(itemID)
	local row = Row(itemID)
	local mine, age
	if row and row.p then
		age = time() - (row.t or 0)
		if age <= STALE then mine = row.p end
	end
	local theirs, theirAge = Theirs(itemID)
	if theirs and (not mine or theirAge < age) then return theirs end
	return mine
end

-- How long ago the price Prices.Get gives (of these two) was seen, in seconds, or nil.
local function OwnAge(itemID)
	local row = Row(itemID)
	local age
	if row and row.p then
		age = time() - (row.t or 0)
		if age > STALE then age = nil end
	end
	local theirs, theirAge = Theirs(itemID)
	if theirs and (not age or theirAge < age) then return theirAge end
	return age
end

-- Whether any price is known (for the "no Auction House prices" note): ours, or Professionally
-- Lost's while its prices are used.
function Prices.Has()
	if next(Book().items) ~= nil then return true end
	local old = ns.Store.OldPriceBook and ns.Store.OldPriceBook()
	if old and next(old.items) ~= nil then return true end
	local P = ns.ProfLost
	return P ~= nil and P.Handed("prices") and P.HasPrices() or false
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
	local row = Row(itemID)
	if not row or time() - (row.t or 0) > STALE then return nil end
	return row.q
end

local Touched             -- (below) prices changed: what's drawn from them is drawn again

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

-- How long ago the price Prices.Get gives was seen, in seconds, or nil (no price). For the
-- "Stale" mark (Calc.Stale).
function Prices.Age(itemID)
	if DaylightWins(itemID) then
		local _, age = Daylight(itemID)
		return age
	end
	return OwnAge(itemID)
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

-- Daylight UI's daily lows of an item (its Store.Lows, Store.lua:147: the lowest unit buyout of
-- each day, its newest 14 days, a flat list day, low, ... newest last; Market.lua:1-9), as a copy,
-- or nil (none, Daylight UI's prices not read, Auction House prices off). For a plugin's price
-- history (API.lua's DaylightLows).
function Prices.DaylightLows(itemID)
	if not ns.Get("useAH") then return nil end
	local store, rkey = DaylightBook()
	if not store or type(store.Lows) ~= "function" then return nil end
	local ok, lows = pcall(store.Lows, rkey, tostring(itemID))
	if not ok or type(lows) ~= "table" then return nil end
	local out, n = {}, 0
	for i = 1, #lows - 1, 2 do
		local day, copper = lows[i], lows[i + 1]
		if type(day) == "number" and type(copper) == "number" and copper > 0 then
			out[n + 1], out[n + 2] = day, copper
			n = n + 2
		end
	end
	return n > 0 and out or nil
end

function Prices.Has()
	if OwnHas() then return true end
	local store, rkey = DaylightBook()
	if not store or type(store.Count) ~= "function" then return false end
	local ok, n = pcall(store.Count, rkey)
	return ok and type(n) == "number" and n > 0 or false
end

-- Prices changed (Daylight UI's, a scan's batch or a search of its; a price ladder read): what's
-- worked out from prices is forgotten now, which costs nothing until someone asks, and the buy
-- lists follow at once. The Leveling Guide, whose route is the costly part, is worked out and
-- drawn again once things have been quiet for half a second, and not at all while a check of
-- prices runs: once, when it ends (now = true).
local later = false
local function Redraw()
	later = false
	if Prices.Checking() then return end
	-- (A plugin hears of it once things are quiet: API.lua's OnPrices.)
	if ns.PricesHeard then ns.PricesHeard() end
	if ns.Plan and ns.Plan.Forget then ns.Plan.Forget() end
	if ns.ShowingPlan() then ns.Changed() end
end
local quietAt = 0
local function Wait()
	local left = quietAt - GetTime()
	if left > 0.01 then
		C_Timer.After(left, Wait)
	else
		Redraw()
	end
end
function Touched(now)
	if ns.Calc then ns.Calc.Forget() end
	if ns.Shop then ns.Shop.Refresh() end
	if now then return Redraw() end
	quietAt = GetTime() + 0.5
	if later then return end
	later = true
	C_Timer.After(0.5, Wait)
end

local function DaylightChanged() Touched() end

-- Prices changed somewhere else (PriceSources.lua: the picked addon's).
function Prices.Changed() Touched() end

local function HearDaylight()
	local D = _G.DaylightUI
	if type(D) ~= "table" or type(D.GetModule) ~= "function" then return end
	local ok, mod = pcall(D.GetModule, D, "AuctionHouse")
	local m = ok and type(mod) == "table" and mod.ns or nil
	if type(m) == "table" and type(m.On) == "function" then pcall(m.On, "PricesChanged", DaylightChanged) end
end

-- ---------------------------------------------------------------------------------------------
-- Price steps
-- ---------------------------------------------------------------------------------------------

-- A ladder is believed this long. Long enough to check prices, walk the list and buy; short enough
-- that the list doesn't cost a purchase by auctions that were sold a while ago. Past it the buy
-- list goes back to "about": the lowest price times the count.
local FRESH = 15 * 60

local steps = {}          -- realm key -> itemID -> { at, list = { { q, p }, ... } cheapest first, full }

local function Ladders()
	local key = ns.Store.RealmKey()
	local t = steps[key]
	if not t then
		t = {}
		steps[key] = t
	end
	return t
end

-- An item's steps as last read, when that was no longer than FRESH ago:
-- { at = time(), list = { { q = how many, p = copper each }, ... }, full = the whole ladder was read }.
-- An empty list: none were for sale. nil: not read, or too long ago.
function Prices.Steps(itemID)
	local e = Ladders()[itemID]
	if not e or time() - e.at > FRESH then return nil end
	return e
end

-- Keeps an item's steps: rows = { { q, p }, ... } in any order (rows of one price are joined).
function Prices.SetSteps(itemID, rows, full)
	if type(itemID) ~= "number" or type(rows) ~= "table" or not Wanted()[itemID] then return end
	local list = {}
	for _, r in ipairs(rows) do
		local q, price = tonumber(r.q), tonumber(r.p)
		if q and price and q > 0 and price > 0 then list[#list + 1] = { q = q, p = price } end
	end
	table.sort(list, function(a, b) return a.p < b.p end)
	local joined = {}
	for _, r in ipairs(list) do
		local last = joined[#joined]
		if last and last.p == r.p then last.q = last.q + r.q else joined[#joined + 1] = r end
	end
	Ladders()[itemID] = { at = time(), list = joined, full = full ~= false }
	-- (The lowest price kept between sessions follows: the first step's.)
	if joined[1] then Seen(itemID, joined[1].p, Book().items, time()) end
	Touched()
end

-- `count` of an item bought just now: gone from its cheapest steps (what a purchase takes).
function Prices.Took(itemID, count)
	local e = Ladders()[itemID]
	if not e or type(count) ~= "number" then return end
	while count > 0 and e.list[1] do
		local first = e.list[1]
		if first.q > count then
			first.q = first.q - count
			count = 0
		else
			count = count - first.q
			table.remove(e.list, 1)
		end
	end
	Touched()
end

-- A commodity's search result, every row (GetNumCommoditySearchResults /
-- GetCommoditySearchResultInfo, AuctionHouseDocumentation.lua:504-517, :240-254; a row is
-- { quantity, unitPrice, numOwnerItems, containsOwnerItem, ... } :1620-1634). What's the player's
-- own in a row (numOwnerItems) is left out: it can't be bought.
local function ReadCommodity(itemID)
	local count, get = C_AuctionHouse.GetNumCommoditySearchResults, C_AuctionHouse.GetCommoditySearchResultInfo
	if type(count) ~= "function" or type(get) ~= "function" or type(itemID) ~= "number" then return end
	local ok, n = pcall(count, itemID)
	if not ok or type(n) ~= "number" then return end
	local rows = {}
	for i = 1, n do
		local got, r = pcall(get, itemID, i)
		if got and type(r) == "table" and type(r.unitPrice) == "number" and type(r.quantity) == "number" then
			local own = r.containsOwnerItem and tonumber(r.numOwnerItems) or 0
			rows[#rows + 1] = { q = r.quantity - math.min(own, r.quantity), p = r.unitPrice }
		end
	end
	local full = true
	if type(C_AuctionHouse.HasFullCommoditySearchResults) == "function" then
		local got, all = pcall(C_AuctionHouse.HasFullCommoditySearchResults, itemID)
		if got and all == false then full = false end
	end
	Prices.SetSteps(itemID, rows, full)
end

-- An item search's result (auctions of single items, :374-388; a row is { quantity, buyoutAmount,
-- containsOwnerItem, ... } :1665-1684): each auction with a buyout that isn't the player's own is
-- a step of its quantity at its buyout (the price of one).
local function ReadItem(itemKey)
	local count, get = C_AuctionHouse.GetNumItemSearchResults, C_AuctionHouse.GetItemSearchResultInfo
	if type(count) ~= "function" or type(get) ~= "function" or type(itemKey) ~= "table" or not itemKey.itemID then return end
	local ok, n = pcall(count, itemKey)
	if not ok or type(n) ~= "number" then return end
	local rows = {}
	for i = 1, n do
		local got, r = pcall(get, itemKey, i)
		if got and type(r) == "table" and type(r.buyoutAmount) == "number" and r.buyoutAmount > 0
			and r.containsOwnerItem ~= true then
			rows[#rows + 1] = { q = tonumber(r.quantity) or 1, p = r.buyoutAmount }
		end
	end
	local full = true
	if type(C_AuctionHouse.HasFullItemSearchResults) == "function" then
		local got, all = pcall(C_AuctionHouse.HasFullItemSearchResults, itemKey)
		if got and all == false then full = false end
	end
	Prices.SetSteps(itemKey.itemID, rows, full)
end

-- ---------------------------------------------------------------------------------------------
-- "Check Prices": the steps of a list of items, one search each, one at a time
-- ---------------------------------------------------------------------------------------------
-- The game takes one Auction House message at a time (C_AuctionHouse.IsThrottledMessageSystemReady,
-- :825-832) and 100 searches a minute (SendSearchQuery's note, :1031-1044; it is not a
-- hardware-only call: no HasRestrictions on it, unlike PlaceBid or StartCommoditiesPurchase).
--
-- With Daylight UI's own Auction House running, every request of its goes through its one line
-- (DaylightUI_AuctionHouse\AH.lua:1-58: one in flight, first in first out, sent only when the
-- game is ready, the searches counted against the 100 a minute). A search of ours sent beside that
-- line would take the game's one slot from under it. So ours go through it: its
-- ns.Search.Item(itemID, done) (Search.lua:1-33, :413-435) queues a search on that line, waits for
-- the item's key, reads every page and answers done(rows, reason, auctions), auctions being the
-- raw rows cheapest first, a commodity's { unit, qty, own } per price, an item's { unit (0: bid
-- only), qty, own } (Search.lua:192-232). Its Buy page shows only what its own calls answered
-- (each caller gets its own copy of the rows, Search.lua:111-129), so a search of ours changes
-- nothing on it. Not part of Daylight UI's API: every step is checked and wrapped, and without it
-- the game is asked directly, as below.
--
-- Without it (the game's own window, a Daylight UI before 2.0): SendSearchQuery(MakeItemKey(id),
-- price order, false) once the game says it is ready and knows the item's key (it ignores a search
-- for a key it has no info on: GetItemKeyInfo first, as Daylight UI found, Search.lua:36-40); the
-- answer is COMMODITY_SEARCH_RESULTS_UPDATED(itemID) or ITEM_SEARCH_RESULTS_UPDATED(itemKey), read
-- by the same code as any other search result. The game's window doesn't change what it shows for
-- a result it didn't ask for: its frame only clears width caches (Blizzard_AuctionHouseFrame.lua:
-- 422-432) and an open price list draws its own item again (Blizzard_AuctionHouseCommoditiesList
-- .lua:46-55).
--
-- Never while a purchase is being made (ours heard through Shop.Buying, Daylight UI's
-- ns.Buy.Pending(), Buy.lua:101, the game's buy dialog or buyout question up), never with
-- DaylightMogul owning the Auction House, and it ends when the window closes.
local GAP = 0.7            -- seconds between two searches of ours (the game's limit is 100 a minute)
local ANSWER = 8           -- seconds an answer is waited for before the next item is asked
local run                  -- { ids, at, total, token, onChange }
local ahOpen = false       -- (also the full scan's, below)

local function DaylightHouse()
	local D = _G.DaylightUI
	if type(D) ~= "table" or D.ahMogul == true or type(D.GetModule) ~= "function" then return nil end
	local ok, mod = pcall(D.GetModule, D, "AuctionHouse")
	if not ok or type(mod) ~= "table" or mod.enabled ~= true or type(mod.ns) ~= "table" then return nil end
	return mod.ns
end

-- Whether something is being bought right now: nothing is asked of the Auction House then.
local function Buying()
	-- (Ours: the purchase Store.lua heard confirmed and not answered yet, Store.Confirming; a
	-- vendor's buy run, Shop.Buying, which can't be under way at the Auction House but costs nothing
	-- to ask.)
	if ns.Store and ns.Store.Confirming and ns.Store.Confirming() then return true end
	if ns.Shop and ns.Shop.Buying and ns.Shop.Buying() then return true end
	local m = DaylightHouse()
	if m and type(m.Buy) == "table" and type(m.Buy.Pending) == "function" then
		local ok, kind = pcall(m.Buy.Pending)
		if ok and kind ~= nil then return true end
	end
	local f = _G.AuctionHouseFrame
	local dialog = type(f) == "table" and f.BuyDialog
	if type(dialog) == "table" and dialog.IsShown and dialog:IsShown() then return true end
	local visible = _G.StaticPopup_Visible
	if type(visible) == "function" then
		local ok, shown = pcall(visible, "BUYOUT_AUCTION")
		if ok and shown then return true end
	end
	return false
end

-- AHDB holds its own Auction House requests while ours run (PriceSources.lua: Sources.Busy).
local function Hold(key, on)
	if ns.Sources then ns.Sources.Busy(key, on) end
end

function Prices.CanCheck()
	return ahOpen and not Prices.Mogul() and C_AuctionHouse ~= nil and ns.Get("useAH") and true or false
end

-- done, total while a check runs; nil otherwise.
function Prices.Checking()
	if not run then return nil end
	return run.at - 1, run.total
end

local function Told()
	if run and run.onChange then pcall(run.onChange) end
end

function Prices.StopCheck()
	if not run then return end
	local was = run
	run = nil
	Hold("check", false)
	Touched(true)
	if was.onChange then pcall(was.onChange) end
end

local Next

-- One item answered (or given up on): on to the next, a moment later.
local function Advance(token, wait)
	if not run or run.token ~= token then return end
	run.at = run.at + 1
	run.token = run.token + 1
	run.waiting, run.tries = nil, 0
	Told()
	C_Timer.After(wait or 0, Next)
end

-- What Daylight UI's search answered, as steps.
local function FromDaylight(itemID, rows, auctions)
	if rows == nil then return end           -- (failed: closed, timeout, uncached... not known)
	local list = {}
	for _, a in ipairs(type(auctions) == "table" and auctions or {}) do
		local unit, qty, own = tonumber(a.unit), tonumber(a.qty), tonumber(a.own) or 0
		if unit and qty and unit > 0 and qty - own > 0 then list[#list + 1] = { q = qty - own, p = unit } end
	end
	Prices.SetSteps(itemID, list, true)
end

function Next()
	if not run then return end
	if not ahOpen or not Prices.CanCheck() then return Prices.StopCheck() end
	local itemID = run.ids[run.at]
	if not itemID then return Prices.StopCheck() end
	if Buying() then
		C_Timer.After(0.5, Next)
		return
	end
	local token = run.token
	local m = DaylightHouse()
	if m and type(m.Search) == "table" and type(m.Search.Item) == "function" then
		-- (Its line: it waits its turn there, and its answer comes here, once.)
		local ok = pcall(m.Search.Item, itemID, function(rows, _, auctions)
			if not run or run.token ~= token then return end
			FromDaylight(itemID, rows, auctions)
			Advance(token, 0)
		end)
		if not ok then Advance(token, 0) end
		return
	end
	-- The game asked directly. (Daylight UI's line there but not its search: only while it's idle.)
	if m and type(m.AH) == "table" and type(m.AH.Busy) == "function" then
		local ok, busy = pcall(m.AH.Busy)
		if ok and busy then
			C_Timer.After(0.5, Next)
			return
		end
	end
	local ready = C_AuctionHouse.IsThrottledMessageSystemReady
	if type(ready) == "function" and not ready() then
		C_Timer.After(0.3, Next)
		return
	end
	if type(C_AuctionHouse.MakeItemKey) ~= "function" or type(C_AuctionHouse.SendSearchQuery) ~= "function" then
		return Prices.StopCheck()
	end
	local made, key = pcall(C_AuctionHouse.MakeItemKey, itemID)
	if not made or type(key) ~= "table" then return Advance(token, 0) end
	if type(C_AuctionHouse.GetItemKeyInfo) == "function" then
		local got, info = pcall(C_AuctionHouse.GetItemKeyInfo, key)
		if not got or info == nil then
			-- (Asked for by that call: looked at again shortly, a few times, then passed over.)
			run.tries = (run.tries or 0) + 1
			if run.tries > 10 then return Advance(token, 0) end
			C_Timer.After(0.3, Next)
			return
		end
	end
	local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
	local sorts = order and { { sortOrder = order, reverseSort = false } } or {}
	if not pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false) then return Advance(token, 0) end
	run.waiting = itemID
	C_Timer.After(ANSWER, function() Advance(token, 0) end)
end

-- Reads the steps of every item in ids ({ itemID, ... }), in order. onChange() after each one and
-- when it ends (for the panel's "Checking prices: 3 of 12"). False when it can't start.
function Prices.Check(ids, onChange)
	if run or not Prices.CanCheck() or type(ids) ~= "table" or #ids == 0 then return false end
	local list = {}
	for _, itemID in ipairs(ids) do
		if type(itemID) == "number" then list[#list + 1] = itemID end
	end
	if #list == 0 then return false end
	run = { ids = list, at = 1, total = #list, token = 1, tries = 0, onChange = onChange }
	Hold("check", true)
	Told()
	Next()
	return true
end

-- A search result came for an item (ours or anyone's): when it's the one a check waits for, on.
local function Answered(itemID)
	if run and run.waiting == itemID then Advance(run.token, GAP) end
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
		-- (Through the quiet wait like every other price change: a scan's pages come one after
		-- another, and each redrawing the route at once worked it out again per page.)
		Touched()
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

local scanning = false
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
		and not (ns.Sources and ns.Sources.ScanHandedOff())
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
	Hold("scan", false)
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
	if not scanning or not ahOpen then
		scanning = false
		Hold("scan", false)
		return
	end
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
	Hold("scan", true)
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
		Hold("scan", false)
		Prices.StopCheck()
		-- (What Daylight UI saw in its searches this visit is read from here on.)
		if Prices.Daylight() then Touched(true) end
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
		-- (Every row, not the first alone: the whole ladder, and its first step the lowest price.)
		ReadCommodity(arg)
		Answered(arg)
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		-- (The rows follow your sort and some are bids only: the buyouts, sorted here.)
		ReadItem(arg)
		if type(arg) == "table" then Answered(arg.itemID) end
	end
end)
