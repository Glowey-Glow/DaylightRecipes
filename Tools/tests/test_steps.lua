-- Auction House price steps and "Check Prices" (carried over from 2.7.0: Prices.lua's Steps /
-- SetSteps / Took, its reading of every search result, its check run; Calc.lua's Steps, AHCost,
-- Split, BuyCost and Unit's rule with steps known), on the plugin's real Calc.lua and Prices.lua,
-- and what the strips make of them (Shop.lua: an item shared out between the Auction House's and
-- the vendor's strip, costs that walk the steps, the Check Prices line and button), with the
-- rules of buying under a shared item.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightMogul DaylightRecipesDB NS AuctionHouseFrame Auctionator C_AuctionHouse Enum
-- luacheck: read globals T Fire NewObj
local ns = NS
local Shop, Prices, Calc = ns.Shop, ns.Prices, ns.Calc

local THREAD, VIAL, CLOTH, GEM, ORE = 2320, 3371, 2589, 7777, 2770
GAME.reagents = { [THREAD] = true, [VIAL] = true, [CLOTH] = true, [GEM] = true, [ORE] = true }

-- ---- the game's Auction House, as much as Prices.lua asks of it ---------------------------------
local AH = { ready = true, sent = {}, commodity = {}, item = {}, full = {}, keyInfo = true }
C_AuctionHouse = {
	GetNumCommoditySearchResults = function(itemID) return #(AH.commodity[itemID] or {}) end,
	GetCommoditySearchResultInfo = function(itemID, i) return (AH.commodity[itemID] or {})[i] end,
	HasFullCommoditySearchResults = function(itemID) return AH.full[itemID] ~= false end,
	GetNumItemSearchResults = function(key) return #(AH.item[key.itemID] or {}) end,
	GetItemSearchResultInfo = function(key, i) return (AH.item[key.itemID] or {})[i] end,
	IsThrottledMessageSystemReady = function() return AH.ready end,
	MakeItemKey = function(itemID) return { itemID = itemID } end,
	GetItemKeyInfo = function() return AH.keyInfo and {} or nil end,
	SendSearchQuery = function(key, sorts, separate)
		-- (The game takes one message at a time: a search sent while it is not ready is an error.)
		if not AH.ready then error("SendSearchQuery: the Auction House is not ready", 2) end
		AH.sent[#AH.sent + 1] = { itemID = key.itemID, sorts = sorts, separate = separate, at = GAME.now }
	end,
}
Enum = { AuctionHouseSortOrder = { Price = 4 } }
-- A commodity's rows as the game gives them, and the game saying a search for it was answered.
local function rows(list)
	local out = {}
	for i, r in ipairs(list) do
		out[i] = { quantity = r[1], unitPrice = r[2], numOwnerItems = r[3], containsOwnerItem = r[3] ~= nil }
	end
	return out
end
local function answer(itemID, list)
	AH.commodity[itemID] = rows(list)
	Fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemID)
end

Fire("PLAYER_LOGIN")

GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
AuctionHouseFrame = NewObj("Frame", "AuctionHouseFrame")
AuctionHouseFrame.w, AuctionHouseFrame.h = 800, 538
AuctionHouseFrame.shown = false
AuctionHouseFrame.BuyDialog = NewObj("Frame")
AuctionHouseFrame.BuyDialog.shown = false

local ahOpen = false
local function openAH()
	ahOpen = true
	AuctionHouseFrame.shown = true
	Fire("AUCTION_HOUSE_SHOW")
	T.run(2)
end
local function closeAH()
	ahOpen = false
	AuctionHouseFrame.shown = false
	Fire("AUCTION_HOUSE_CLOSED")
end
local function shelf()
	return {
		{ id = THREAD, price = 110, stack = 1, max = 20 },
		{ id = VIAL, price = 4, stack = 1, max = 20 },
	}
end
local function fresh()
	if GAME.merchant then T.leave() end
	if ahOpen then closeAH() end
	Prices.StopCheck()
	GAME.deliver = nil
	T.run(30)
	-- (Price steps are kept for the session: an hour on, every one of an earlier case is too old.)
	GAME.clock = GAME.clock + 3600
	GAME.bought, GAME.total, GAME.limit = {}, {}, {}
	GAME.bags, GAME.queue, GAME.plans, GAME.prof = {}, {}, {}, {}
	GAME.vendorPrice, GAME.removed, GAME.queueBy = {}, {}, nil
	GAME.db.prices = {}
	GAME.deliver = 0.3
	GAME.money, GAME.freeSlots, GAME.stackSize = 1000000, 200, {}
	GAME.settings.askBuyAll, GAME.settings.useAH = false, true
	AH.ready, AH.sent, AH.commodity, AH.item, AH.full, AH.keyInfo = true, {}, {}, {}, {}, true
	AuctionHouseFrame.BuyDialog.shown = false
	ns.Store.Confirming = nil
	DaylightUI, DaylightMogul, Auctionator = nil, nil, nil
	PRINTS = {}
	DaylightRecipesDB = { shop = { vendor = true, auction = true } }
	Calc.Forget()
end
local function strip() return _G.DaylightRecipesBuyStrip end
local function ahStrip() return _G.DaylightRecipesAHStrip end
local function row(s, itemID)
	if not (s and s:IsShown() and s.list:IsShown()) then return nil end
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find("Item " .. itemID .. " x", 1, true) then return r end
	end
end
local function shows(s, itemID)
	local r = row(s, itemID)
	return r and tonumber(r.left:match("x (%d+)")) or nil
end
local function line(s, word)
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find(word, 1, true) then return r end
	end
end
-- The list's Check Prices line (in the list's head, which stays put over the rows): the row whose
-- right word is the button's.
local function checkRow(s)
	for _, r in ipairs(s.head.rows) do
		if r.right == "Check Prices" or r.right == "Stop" then return r end
	end
end
-- What a row's tooltip says (the lines it adds).
local function tipOf(r)
	local out = {}
	r.tip({ SetItemByID = function() end, SetText = function(_, text) out[#out + 1] = text end,
		AddLine = function(_, text) out[#out + 1] = text end,
		AddDoubleLine = function(_, a, b) out[#out + 1] = a .. " " .. b end })
	return out
end
local function has(list, text)
	for _, l in ipairs(list) do
		if l == text then return true end
	end
	return false
end

-- A case about Prices.lua's check alone: started here, not from the strip, so the strip (which
-- stops a check that is not for the list it shows) is kept out of it.
local function alone(name, fn)
	T.case(name, function()
		local real = Shop.Auction
		Shop.Auction = function() return true end
		local ok, err = pcall(fn)
		Shop.Auction = real
		if not ok then error(err, 0) end
	end)
end

-- ---- Calc: walking the steps ---------------------------------------------------------------------
T.case("steps: a purchase is costed by what is for sale, cheapest first", function()
	fresh()
	Prices.SetSteps(THREAD, { { q = 51, p = 120 }, { q = 4, p = 100 }, { q = 30, p = 150 } })
	local steps = Calc.Steps(THREAD)
	T.eq(#steps.list, 3, "three steps")
	T.eq(steps.list[1].p, 100, "sorted cheapest first")
	T.eq(Prices.Get(THREAD), 100, "the lowest price kept between sessions is the first step's")
	local cost, covered, known, used = Calc.AHCost(THREAD, 10)
	T.eq(known, true, "the steps are known")
	T.eq(cost, 4 * 100 + 6 * 120, "exact: 4 at the first price, 6 at the second, not 10 times the lowest")
	T.eq(covered, 10, "all 10 are for sale")
	T.eq(#used, 2, "two steps taken")
	T.eq(used[2].q, 6, "6 of the second")
	-- More than are for sale.
	cost, covered = Calc.AHCost(THREAD, 100)
	T.eq(covered, 85, "short: only 85 are for sale")
	T.eq(cost, 400 + 51 * 120 + 30 * 150, "and they cost what is there")
	local total, exact = Calc.BuyCost(THREAD, 100)
	T.eq(total, 400 + 51 * 120 + 30 * 150 + 15 * 150, "with no vendor the rest is counted at the dearest step read")
	T.eq(exact, false, "which is an estimate")
	-- The route's earlier steps took the cheapest already.
	cost, covered = Calc.AHCost(THREAD, 10, nil, 4)
	T.eq(cost, 10 * 120, "with the first 4 taken already, 10 more cost the second price")
	T.eq(covered, 10, "all of them")
	-- Rows of one price are one step; nonsense rows are left out.
	Prices.SetSteps(VIAL, { { q = 3, p = 50 }, { q = 2, p = 50 }, { q = 0, p = 10 }, { q = 5, p = 0 }, { q = "x", p = 5 } })
	T.eq(#Calc.Steps(VIAL).list, 1, "rows of one price are joined, bad rows dropped")
	T.eq(Calc.Steps(VIAL).list[1].q, 5, "their numbers added")
	Prices.SetSteps(99999, { { q = 1, p = 1 } })
	T.eq(Calc.Steps(99999), nil, "an item no recipe uses is not kept")
end)

T.case("steps: none for sale, a vendor cheaper than some steps, and steps too old", function()
	fresh()
	-- None for sale.
	Prices.SetSteps(THREAD, {})
	local cost, covered, known = Calc.AHCost(THREAD, 10)
	T.eq(known, true, "an empty ladder is known: none are for sale")
	T.eq(cost, 0, "nothing to pay")
	T.eq(covered, 0, "nothing covered")
	T.eq((Calc.Unit(THREAD)), nil, "no price at all: no vendor, none for sale, never seen")
	local a, v, split = Calc.Split(THREAD, 10)
	T.eq(split, true, "the split is known")
	T.eq(a, 10, "with no vendor all 10 are the Auction House's, for sale or not")
	T.eq(v, 0, "none a vendor's")
	GAME.vendorPrice[THREAD] = 110
	local unit, kind = Calc.Unit(THREAD)
	T.eq(kind, "vendor", "none for sale and a vendor: the vendor's")
	T.eq(unit, 110, "at its price")
	a, v = Calc.Split(THREAD, 10)
	T.eq(a, 0, "none the Auction House's")
	T.eq(v, 10, "all 10 the vendor's")
	-- A vendor at 110: only the steps under that are worth buying.
	Prices.SetSteps(THREAD, { { q = 4, p = 100 }, { q = 51, p = 120 } })
	unit, kind = Calc.Unit(THREAD)
	T.eq(kind, "ah", "the cheapest step is under the vendor: the Auction House is the cheaper source")
	T.eq(unit, 100, "at the first step's price")
	cost, covered = Calc.AHCost(THREAD, 10, 110)
	T.eq(covered, 4, "above the vendor's price nothing is taken: 4 of 10")
	T.eq(cost, 400, "at 100 each")
	a, v = Calc.Split(THREAD, 10)
	T.eq(a, 4, "4 are the Auction House's")
	T.eq(v, 6, "6 the vendor's")
	a, v = Calc.Split(THREAD, 3)
	T.eq(a, 3, "a need the cheap step covers is all the Auction House's")
	T.eq(v, 0, "none the vendor's")
	local total, exact = Calc.BuyCost(THREAD, 10)
	T.eq(total, 400 + 6 * 110, "bought the cheapest way: 4 there, 6 at the vendor")
	T.eq(exact, true, "and that is exact")
	-- Every step at or over the vendor's price.
	Prices.SetSteps(THREAD, { { q = 9, p = 110 }, { q = 51, p = 120 } })
	T.eq(select(2, Calc.Unit(THREAD)), "vendor", "no step under the vendor: the vendor's")
	a, v = Calc.Split(THREAD, 10)
	T.eq(a, 0, "nothing for the Auction House")
	T.eq(v, 10, "everything for the vendor")
	-- Too old: fifteen minutes.
	Prices.SetSteps(THREAD, { { q = 4, p = 100 }, { q = 51, p = 120 } })
	GAME.clock = GAME.clock + 14 * 60
	T.ok(Calc.Steps(THREAD) ~= nil, "fourteen minutes on: still believed")
	GAME.clock = GAME.clock + 2 * 60
	T.eq(Calc.Steps(THREAD), nil, "sixteen: not any more")
	T.eq(select(3, Calc.AHCost(THREAD, 10)), false, "so a cost is not known by steps")
	T.eq(select(3, Calc.Split(THREAD, 10)), false, "nor a split")
	total, exact = Calc.BuyCost(THREAD, 10)
	T.eq(total, 1000, "the old estimate stands: 10 times the lowest price")
	T.eq(exact, false, "and says it is one")
	-- Auction House prices switched off, or DaylightMogul's in use: no steps.
	Prices.SetSteps(THREAD, { { q = 4, p = 100 } })
	GAME.settings.useAH = false
	T.eq(Calc.Steps(THREAD), nil, "with Auction House prices off there are no steps")
	GAME.settings.useAH = true
	DaylightMogul = { API = { Price = function() return nil end } }
	T.eq(Calc.Steps(THREAD), nil, "nor with DaylightMogul's prices in use")
	DaylightMogul = nil
end)

-- ---- Prices: reading every search result ---------------------------------------------------------
T.case("any search result is read: the whole ladder, without the player's own auctions", function()
	fresh()
	openAH()
	answer(CLOTH, { { 4, 1175 }, { 51, 1200 }, { 20, 1300, 20 }, { 10, 1400, 3 } })
	local list = Prices.Steps(CLOTH).list
	T.eq(#list, 3, "three steps: the row that is all the player's own is left out")
	T.eq(list[1].q, 4, "4 at the lowest")
	T.eq(list[3].q, 7, "a row partly the player's own counts without those")
	T.eq(list[3].p, 1400, "at its price")
	T.eq(Prices.Steps(CLOTH).full, true, "the whole ladder was read")
	T.eq(Prices.Get(CLOTH), 1175, "and the lowest price follows")
	AH.full[CLOTH] = false
	answer(CLOTH, { { 4, 1175 } })
	T.eq(Prices.Steps(CLOTH).full, false, "a result the game has not all of is marked so")
	-- A search for single items: each auction with a buyout that is not the player's own.
	AH.item[GEM] = {
		{ quantity = 1, buyoutAmount = 900 },
		{ quantity = 1, buyoutAmount = 0 },                              -- bid only
		{ quantity = 1, buyoutAmount = 500, containsOwnerItem = true },  -- the player's own
		{ quantity = 1, buyoutAmount = 700 },
	}
	Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = GEM })
	list = Prices.Steps(GEM).list
	T.eq(#list, 2, "two buyouts that can be bought")
	T.eq(list[1].p, 700, "sorted here: the rows follow the player's sort")
	T.eq(Prices.Get(GEM), 700, "the lowest of them is the price")
	-- A search that finds none.
	answer(ORE, {})
	T.eq(#Prices.Steps(ORE).list, 0, "a result with no rows: none are for sale, and that is known")
end)

T.case("a purchase takes its units off the cheapest steps", function()
	fresh()
	Prices.SetSteps(CLOTH, { { q = 4, p = 100 }, { q = 51, p = 120 }, { q = 30, p = 150 } })
	Prices.Took(CLOTH, 3)
	T.eq(Prices.Steps(CLOTH).list[1].q, 1, "3 bought: 1 left at the lowest price")
	Prices.Took(CLOTH, 11)
	local list = Prices.Steps(CLOTH).list
	T.eq(#list, 2, "11 more: the first step is gone")
	T.eq(list[1].q, 41, "and 10 of the second")
	T.eq((Calc.AHCost(CLOTH, 5)), 600, "the next 5 cost the second price")
	Prices.Took(CLOTH, 500)
	T.eq(#Prices.Steps(CLOTH).list, 0, "more than there were: none left")
	Prices.Took(VIAL, 5)
	T.eq(Prices.Steps(VIAL), nil, "an item with no steps read is not touched")
end)

-- ---- Prices: the check run ------------------------------------------------------------------------
alone("Check Prices: one search an item, one at a time, each when the game is ready", function()
	fresh()
	T.eq(Prices.CanCheck(), false, "not with the Auction House closed")
	T.eq(Prices.Check({ THREAD }), false, "so no check starts")
	openAH()
	T.eq(Prices.CanCheck(), true, "with it open")
	local told = 0
	T.eq(Prices.Check({ THREAD, VIAL, CLOTH }, function() told = told + 1 end), true, "a check starts")
	T.eq(Prices.Check({ GEM }), false, "and a second one does not while it runs")
	T.eq(#AH.sent, 1, "the first search is sent at once")
	T.eq(AH.sent[1].itemID, THREAD, "for the first item")
	T.eq(AH.sent[1].sorts[1].sortOrder, 4, "by price")
	T.eq(AH.sent[1].separate, false, "owner's items not apart")
	local done, total = Prices.Checking()
	T.eq(done, 0, "none done yet")
	T.eq(total, 3, "of three")
	T.run(3)
	T.eq(#AH.sent, 1, "nothing more is sent before the answer")
	answer(THREAD, { { 4, 100 }, { 51, 120 } })
	T.eq(#AH.sent, 1, "nor in the moment it comes")
	T.eq((Prices.Checking()), 1, "one done")
	T.run(0.5)
	T.eq(#AH.sent, 1, "the next waits its gap")
	-- (The game is busy when the gap is over: the search waits until it is ready.)
	AH.ready = false
	T.run(2)
	T.eq(#AH.sent, 1, "not while the game is not ready")
	AH.ready = true
	T.run(0.5)
	T.eq(#AH.sent, 2, "sent once it is")
	T.eq(AH.sent[2].itemID, VIAL, "the second item")
	-- An answer for another item (the player's own search) is read, and is not this one's.
	answer(GEM, { { 1, 5 } })
	T.eq((Prices.Checking()), 1, "another item's answer does not move the check on")
	T.ok(Prices.Steps(GEM) ~= nil, "though it is read like any")
	-- No answer at all: after a while the next item is asked.
	T.run(8.5)
	T.eq(#AH.sent, 3, "an item never answered is passed over")
	T.eq(AH.sent[3].itemID, CLOTH, "for the third")
	T.eq(Prices.Steps(VIAL), nil, "its steps stay unknown")
	answer(CLOTH, {})
	T.run(1)
	T.eq(Prices.Checking(), nil, "the list done: the check is over")
	T.ok(told >= 4, "its listener heard each step and the end")
	T.eq(#AH.sent, 3, "three searches for three items")
	for i = 2, #AH.sent do
		T.ok(AH.sent[i].at - AH.sent[i - 1].at >= 0.7, "never two searches closer than the gap")
	end
end)

alone("Check Prices: an item the game has no key info for yet, and what stops a check", function()
	fresh()
	openAH()
	AH.keyInfo = false
	Prices.Check({ THREAD, VIAL })
	T.eq(#AH.sent, 0, "no search for a key the game has no info on")
	T.run(1)
	AH.keyInfo = true
	T.run(0.5)
	T.eq(#AH.sent, 1, "sent once it has")
	-- Stop.
	Prices.StopCheck()
	T.eq(Prices.Checking(), nil, "Stop ends it")
	answer(THREAD, { { 1, 1 } })
	T.run(20)
	T.eq(#AH.sent, 1, "and nothing more is sent")
	-- The Auction House closing.
	Prices.Check({ THREAD, VIAL })
	T.eq(#AH.sent, 2, "another check")
	closeAH()
	T.eq(Prices.Checking(), nil, "the window closing ends it")
	T.run(20)
	T.eq(#AH.sent, 2, "nothing is sent to a closed Auction House")
	-- Never known: an item whose key info never comes is passed over.
	openAH()
	AH.keyInfo = false
	Prices.Check({ THREAD, VIAL })
	T.run(10)
	T.eq(Prices.Checking(), nil, "items the game never learns are passed over, and the check ends")
	T.eq(#AH.sent, 2, "with nothing sent")
	-- Not with Auction House prices off, nor with DaylightMogul.
	AH.keyInfo = true
	GAME.settings.useAH = false
	T.eq(Prices.CanCheck(), false, "not with Auction House prices off")
	GAME.settings.useAH = true
	DaylightMogul = { API = { Price = function() return nil end } }
	T.eq(Prices.CanCheck(), false, "nor with DaylightMogul")
	DaylightMogul = nil
end)

alone("Check Prices: nothing is asked while something is being bought", function()
	fresh()
	openAH()
	-- A purchase of ours confirmed and not answered (Store.lua).
	local confirming = true
	ns.Store.Confirming = function() return confirming end
	Prices.Check({ THREAD, VIAL })
	T.run(5)
	T.eq(#AH.sent, 0, "nothing sent while a purchase is being confirmed")
	T.eq((Prices.Checking()), 0, "the check waits")
	confirming = false
	T.run(0.6)
	T.eq(#AH.sent, 1, "and goes on after it")
	-- The game's buy dialog up.
	answer(THREAD, { { 1, 1 } })
	AuctionHouseFrame.BuyDialog.shown = true
	T.run(5)
	T.eq(#AH.sent, 1, "nothing sent while the game's buy dialog is up")
	AuctionHouseFrame.BuyDialog.shown = false
	T.run(0.6)
	T.eq(#AH.sent, 2, "on after it")
	Prices.StopCheck()
end)

alone("Check Prices: through Daylight UI's own search line when its Auction House runs", function()
	fresh()
	local asked, busy = {}, false
	local house = { enabled = true, ns = {
		Search = { Item = function(itemID, done) asked[#asked + 1] = { itemID = itemID, done = done } end },
		Buy = { Pending = function() return busy and "confirm" or nil end },
	} }
	DaylightUI = { GetModule = function(_, name) return name == "AuctionHouse" and house or nil end }
	openAH()
	busy = true
	Prices.Check({ THREAD, VIAL, CLOTH })
	T.run(3)
	T.eq(#asked, 0, "nothing while Daylight UI is buying")
	busy = false
	T.run(0.6)
	T.eq(#asked, 1, "then the first search, on its line")
	T.eq(#AH.sent, 0, "and none sent to the game beside it")
	-- Its answer: the raw rows, cheapest first; the player's own left out; a bid-only row (unit 0) too.
	asked[1].done({}, nil, { { unit = 100, qty = 4, own = 0 }, { unit = 120, qty = 60, own = 9 }, { unit = 0, qty = 5 } })
	local list = Prices.Steps(THREAD).list
	T.eq(#list, 2, "its rows are the steps")
	T.eq(list[2].q, 51, "without the player's own")
	T.run(0.1)
	T.eq(#asked, 2, "the next is queued when the first is answered")
	-- A search of its that failed: the item stays unknown, the check goes on.
	asked[2].done(nil, "timeout")
	T.eq(Prices.Steps(VIAL), nil, "a failed search leaves the item unknown")
	T.run(0.1)
	T.eq(#asked, 3, "and the check goes on")
	-- An answer that comes after Stop is not ours any more.
	Prices.StopCheck()
	asked[3].done({}, nil, { { unit = 5, qty = 5 } })
	T.eq(Prices.Steps(CLOTH), nil, "an answer after Stop is not read as the check's")
	-- Its line there but no search of its to call: the game is asked, only while its line is idle.
	house.ns.Search = nil
	local lineBusy = true
	house.ns.AH = { Busy = function() return lineBusy end }
	Prices.Check({ THREAD })
	T.run(3)
	T.eq(#AH.sent, 0, "not while its line is busy")
	lineBusy = false
	T.run(0.6)
	T.eq(#AH.sent, 1, "and directly once it is idle")
	Prices.StopCheck()
	-- Its module switched off: the game's own window, asked directly.
	house.enabled = false
	Prices.Check({ THREAD })
	T.eq(#AH.sent, 2, "with its Auction House off the game is asked directly")
	Prices.StopCheck()
end)

-- ---- the Auction House's strip ---------------------------------------------------------------------
T.case("Auction House strip: a row's cost walks the steps; short supply and none for sale are said", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 10, [CLOTH] = 100, [ORE] = 5, [VIAL] = 8 } } }
	GAME.db.prices["Realm-A"] = { items = { [VIAL] = { p = 3, t = GAME.clock, q = 50 } } }
	Calc.Forget()
	openAH()
	answer(THREAD, { { 4, 100 }, { 51, 120 } })
	answer(CLOTH, { { 40, 30 }, { 15, 40 } })
	answer(ORE, {})
	T.run(1)
	local a = ahStrip()
	T.eq(row(a, THREAD).right, "AH 1120c", "10 thread: 4 at 100 and 6 at 120, not 10 times the lowest")
	T.eq(row(a, CLOTH).right, "AH 1800c · only 55 for sale", "100 cloth with 55 for sale: what is there, and that it is short")
	T.eq(row(a, CLOTH).rightInk, "WARN", "in the warning ink")
	T.eq(row(a, ORE).right, "None for sale", "an item with none for sale says so")
	T.eq(row(a, VIAL).right, "AH about 24c", "an item whose steps were not read: about, the count times the lowest price")
	T.eq(a.cost:GetText(), "AH about 2944c", "the strip's cost: an estimate while any row's is")
	T.ok(a.lead:GetText():find("4", 1, true), "four items to buy")
	-- The tooltip: the steps the purchase takes, the average, when they were read.
	local tip = tipOf(row(a, THREAD))
	T.ok(has(tip, "4 at 100c each") and has(tip, "6 at 120c each"), "the tooltip lists the steps the purchase takes")
	T.ok(has(tip, "Average: 112c each"), "and the average for one")
	T.ok(not has(tip, "only 10 for sale"), "no warning when there are enough")
	tip = tipOf(row(a, CLOTH))
	T.ok(has(tip, "only 55 for sale"), "the short one's tooltip says how many there are")
	local stamped = false
	for _, l in ipairs(tip) do
		if l:find("Prices checked", 1, true) then stamped = true end
	end
	T.ok(stamped, "and when the prices were read")
	T.eq(#tipOf(row(a, VIAL)) < #tip, true, "a row without steps adds none of that")
	-- Every row's steps known: the cost is exact and says so by not saying "about".
	answer(VIAL, { { 50, 3 } })
	T.run(1)
	T.eq(a.cost:GetText(), "AH 2944c", "with every row's steps read the cost is exact")
	-- Many steps: the first four, then how many more.
	answer(THREAD, { { 1, 100 }, { 1, 101 }, { 1, 102 }, { 1, 103 }, { 1, 104 }, { 1, 105 }, { 50, 106 } })
	T.run(1)
	tip = tipOf(row(a, THREAD))
	T.ok(has(tip, "1 at 103c each") and not has(tip, "1 at 104c each"), "four steps are listed")
	T.ok(has(tip, "and 3 more steps"), "and the rest counted")
end)

-- What a strip button's tooltip says.
local function tipOfButton(b)
	local out = {}
	if type(b.tipFn) ~= "function" then return out end
	b.tipFn({ SetText = function(_, text) out[#out + 1] = text end, AddLine = function(_, text) out[#out + 1] = text end })
	return out
end

T.case("Check Prices is the strip's button, not a line of the list; its note; what stops it", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 10, [CLOTH] = 7 } }, [171] = { need = { [VIAL] = 8 } } }
	GAME.queue = { [ORE] = 3 }
	GAME.db.prices["Realm-A"] = { items = {
		[THREAD] = { p = 100, t = GAME.clock, q = 50 }, [CLOTH] = { p = 30, t = GAME.clock, q = 50 },
		[VIAL] = { p = 3, t = GAME.clock, q = 50 }, [ORE] = { p = 9, t = GAME.clock, q = 50 } } }
	Calc.Forget()
	openAH()
	local a = ahStrip()
	T.eq(checkRow(a), nil, "the list's head has no Check Prices line")
	T.eq(#a.head.rows, 0, "nothing in the head but the pair and the tags")
	T.eq(a.main.text:GetText(), "Check Prices", "the strip's own button, beside List, is Check Prices")
	T.ok(not a.second:IsShown(), "one button: no second")
	T.eq(a.rows, 1, "and the strip is one row")
	T.ok(has(tipOfButton(a.main), "Reads how many are for sale at each price."), "what it is for is its tooltip")
	local x
	for _, e in ipairs(a.padKeys) do
		if e.key == "X" then x = e end
	end
	T.eq(x.label(), "Check Prices", "a controller's X is the strip's button: its hint reads Check Prices")
	-- Pressed: a check of the items listed, in list order.
	a.main:Click()
	T.eq(#AH.sent, 1, "a press starts the check")
	T.eq(AH.sent[1].itemID, THREAD, "with the first item listed")
	T.eq(Prices.Checking() ~= nil, true, "it runs")
	T.eq(a.main.text:GetText(), "Stop", "the button reads Stop while it does")
	T.eq(a.note:GetText(), "Checking prices: 1 of 3", "and the strip's note says how far it is")
	T.ok(a.note:IsShown(), "which shows: it is not dropped from the compact strip while a check runs")
	T.eq(a.rows, 1, "still one row")
	T.eq(checkRow(a), nil, "and still nothing of it in the list")
	answer(THREAD, { { 4, 100 }, { 51, 120 } })
	T.run(1)
	T.eq(a.note:GetText(), "Checking prices: 2 of 3", "it moves on")
	T.eq(row(a, THREAD).right, "AH 1120c", "and the row answered already shows its real cost")
	-- Stop, from the strip's button.
	a.main:Click()
	T.eq(Prices.Checking(), nil, "the strip's button stops it")
	T.eq(a.main.text:GetText(), "Check Prices", "and is back to its word")
	local told = false
	for _, l in ipairs(tipOfButton(a.main)) do
		if l:find("Prices checked", 1, true) then told = true end
	end
	T.ok(told, "its tooltip says when prices were last checked")
	local sent = #AH.sent
	T.run(20)
	T.eq(#AH.sent, sent, "nothing more is sent after Stop")
	-- A check is for the list it was started on: the other list picked, a tag, an item removed.
	a.main:Click()
	T.ok(Prices.Checking() ~= nil, "(a check runs)")
	a.head.buttons[1].onClick()
	T.eq(Prices.Checking(), nil, "picking the other list stops it")
	a.head.buttons[2].onClick()
	a.main:Click()
	a.head.tags[2].onClick()
	T.eq(Prices.Checking(), nil, "so does a tag")
	a.head.tags[1].onClick()
	a.main:Click()
	row(a, CLOTH).shift.run()
	T.eq(Prices.Checking(), nil, "and removing an item")
	-- Closing the Auction House.
	a.main:Click()
	closeAH()
	T.eq(Prices.Checking(), nil, "the window closing stops it")
	-- With Auctionator, the strip's main button is Auctionator List: Check Prices is a second
	-- button on the strip beside it, where the strip is still one row with it.
	Auctionator = { API = { v1 = { ConvertToSearchString = function(_, o) return o.searchString end,
		CreateShoppingList = function() end } } }
	openAH()
	a = ahStrip()
	T.eq(a.main.text:GetText(), "Auctionator List", "with Auctionator the strip's main button is its list")
	T.ok(a.second:IsShown() and a.second.text:GetText() == "Check Prices", "and Check Prices is a second button on the strip")
	T.eq(a.rows, 1, "the strip is one row with the three buttons")
	T.eq(checkRow(a), nil, "no line of the list for it")
	T.ok(a.w >= a.listButton.w + a.second.w + a.main.w + 16, "the strip is wide enough for all three: none is cut")
	a.second:Click()
	T.ok(Prices.Checking() ~= nil, "a press on it starts the check")
	T.eq(a.second.text:GetText(), "Stop", "and it reads Stop")
	T.eq(a.main.text:GetText(), "Auctionator List", "the main button stays Auctionator's while a check runs")
	T.eq(a.note:GetText(), "Checking prices: 1 of 2", "the note says how far the check is")
	Prices.StopCheck()
	closeAH()
	-- A window too narrow for the three on one row: only then is Check Prices a line of the list.
	AuctionHouseFrame.w = 330
	openAH()
	a = ahStrip()
	T.ok(not a.second:IsShown(), "no room for a second button on one row: it is not squeezed in")
	T.ok(a.secondGone == true, "the strip says so")
	local c = checkRow(a)
	T.ok(c ~= nil and c.right == "Check Prices", "and the list's head has the Check Prices line, in that case only")
	T.ok(c.onClick ~= nil and c.shift == nil and c.hover == nil, "a line that acts, not an item's row")
	c.onClick()
	T.ok(Prices.Checking() ~= nil, "which starts the check")
	T.eq(checkRow(a).right, "Stop", "and reads Stop")
	Prices.StopCheck()
	closeAH()
	AuctionHouseFrame.w = 800
	-- Where prices cannot be checked there is no button and no line.
	Auctionator = nil
	GAME.settings.useAH = false
	openAH()
	T.eq(checkRow(ahStrip()), nil, "with Auction House prices off: no Check Prices line")
	T.ok(not ahStrip().main:IsShown() and not ahStrip().second:IsShown(), "and no button")
end)

-- ---- an item shared out between the two strips -----------------------------------------------------
-- 10 thread needed; 4 for sale at 100, then 51 at 120; a vendor sells it at 110.
local function shared()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 10, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 110, [VIAL] = 4 }
	Prices.SetSteps(THREAD, { { q = 4, p = 100 }, { q = 51, p = 120 } })
end

T.case("a shared item: the Auction House asks for the cheaper units, the vendor for the rest", function()
	shared()
	openAH()
	local a = ahStrip()
	T.eq(shows(a, THREAD), 4, "Auction House: the 4 that are cheaper than the vendor")
	T.eq(row(a, THREAD).right, "AH 400c", "at their price")
	T.eq(a.cost:GetText(), "AH 400c", "the strip's cost is theirs")
	T.eq(a.note:GetText(), "Saves 40c", "and what they save over the vendor")
	T.ok(a.lead:GetText():find("1", 1, true), "one item to buy there")
	T.eq(line(a, "cheaper").left, "2 more are cheaper at a vendor", "the vendor's share of the thread and the vials: two items")
	line(a, "cheaper").onClick()
	local extra
	for _, r in ipairs(a.doc.rows) do
		if type(r.left) == "string" and r.left:find("Item " .. THREAD .. " x 6", 1, true) then extra = r end
	end
	T.ok(extra ~= nil, "shown, the vendor's 6 are a row of their own")
	T.eq(extra.right, "Vendor 660c", "with the vendor's price")
	closeAH()
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(shows(s, THREAD), 6, "vendor: the other 6")
	T.eq(s.cost:GetText(), "680c", "the strip's cost: 6 thread and 5 vials")
	T.ok(s.lead:GetText():find("2", 1, true), "two items needed here")
	T.eq(line(s, "cheaper").left, "1 more is cheaper on the Auction House", "the Auction House's share is one item left out")
	T.eq(4 + shows(s, THREAD), 10, "the two strips ask for the whole between them, and nothing twice")
end)

T.case("a shared item: Buy All Needed buys the vendor's share, a row its share, the rest only when asked for", function()
	shared()
	-- (The vendor itself raises on the 7th thread.)
	GAME.limit[THREAD], GAME.limit[VIAL] = 6, 5
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	s.main:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 6, "Buy All Needed buys the vendor's 6, not all 10")
	T.eq((T.boughtOf(VIAL)), 5, "and the vials")
	T.run(2)
	T.eq(row(s, THREAD), nil, "the vendor's share bought: the thread's row is gone here")
	T.eq(line(s, "cheaper").left, "1 more is cheaper on the Auction House", "the 4 cheaper ones are still the Auction House's")
	T.eq(Shop.List("guide")[1].buy, 4, "4 are still to buy in all")
	s.main.scripts.OnClick(s.main)
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 6, "another press buys none of them")
	-- Asked for: the row of the Auction House's share buys that share, here, on the player's own press.
	GAME.limit[THREAD] = 10
	line(s, "cheaper").onClick()
	T.eq(shows(s, THREAD), 4, "shown, the other 4 are a row")
	row(s, THREAD).onClick()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 10, "a press on it buys those 4: exactly the need in all")
	-- A row's press, by itself.
	shared()
	GAME.limit[THREAD], GAME.limit[VIAL] = 6, 0
	T.vendor(shelf())
	T.run(1)
	s = strip()
	local press = row(s, THREAD).onClick
	press()
	press()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 6, "a row's press buys its 6, pressed twice or not")
	T.run(5)
	press()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 6, "and its old drawing buys nothing more")
end)

T.case("a shared item: the share is worked out anew before every purchase", function()
	-- The Auction House gets cheaper stock under a run: the vendor's share shrinks, and so does the run.
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100 } } }
	GAME.vendorPrice = { [THREAD] = 110 }
	Prices.SetSteps(THREAD, { { q = 4, p = 100 }, { q = 51, p = 120 } })
	GAME.limit[THREAD] = 40
	GAME.deliver = nil
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(shows(s, THREAD), 96, "the vendor's share: 96 of 100")
	s.main:Click()
	T.eq((T.boughtOf(THREAD)), 20, "the first purchase")
	T.run(0.25)
	T.eq((T.boughtOf(THREAD)), 40, "the second")
	-- (A search lands: 60 are for sale under the vendor's price now. Of the 60 still to buy,
	-- all are the Auction House's.)
	Prices.SetSteps(THREAD, { { q = 60, p = 90 } })
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 40, "the run buys no more: what is left is cheaper on the Auction House")
	T.ok(not (PRINTS[1] or ""):find("Item " .. THREAD, 1, true), "and it is not reported as left out")
	-- The other way: the cheap ones are sold under the run. The run does not grow past its press.
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30 } } }
	GAME.vendorPrice = { [THREAD] = 110 }
	Prices.SetSteps(THREAD, { { q = 10, p = 100 } })
	GAME.limit[THREAD] = 20
	GAME.deliver = nil
	T.vendor(shelf())
	T.run(1)
	s = strip()
	T.eq(shows(s, THREAD), 20, "the vendor's share: 20 of 30")
	s.main:Click()
	Prices.SetSteps(THREAD, {})
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 20, "the share grew to 30 under the run: it still buys the 20 its press showed")
	T.run(2)
	T.eq(shows(s, THREAD), 10, "the rest is on the row for another press")
end)

T.case("a vendor's own price no higher than the Auction House's keeps the item at the vendor", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 10 } } }
	-- (The vendor known to the data asks 200; the Auction House's lowest, with no steps read, is 110.)
	GAME.vendorPrice = { [THREAD] = 200 }
	GAME.db.prices["Realm-A"] = { items = { [THREAD] = { p = 110, t = GAME.clock, q = 50 } } }
	Calc.Forget()
	T.vendor(shelf())      -- this vendor's thread is 110
	T.run(1)
	T.eq(shows(strip(), THREAD), 10, "sold here for no more than the Auction House's price: listed here")
	T.leave()
	GAME.db.prices["Realm-A"].items[THREAD].p = 90
	Calc.Forget()
	T.vendor(shelf())
	T.run(1)
	T.eq(row(strip(), THREAD), nil, "cheaper on the Auction House than here: left out")
	T.eq(line(strip(), "cheaper").left, "1 more is cheaper on the Auction House", "and said so")
end)

return T.done()
