-- The countdown: every way a needed item can arrive, and that the list's number drops by that
-- much at once and the row leaves at zero, nothing counted twice. Played on the plugin's real
-- Store.lua (loaded here over the tests' stand-in, so bags, mail and the Auction House tally are
-- its own code) with the strips of Shop.lua:
--   a) bought through the strip: counted the moment each purchase is made, before the bags show
--      it; exactly the need removes the row; part of it shows the rest; a whole lot for a need
--      smaller than the lot; bags full;
--   b) bought by hand in the vendor's own window: counted from the game's own bag count as soon as
--      the bags settle, before the snapshot is read, so a press right after buys only the rest;
--   c) bought at the Auction House: it comes by mail, so it is counted from the purchase events,
--      before any bag or mail update, once whichever of the two events come and in whichever
--      order; the mailbox read takes over without counting twice; taken out of the mail it is in
--      the bags and still counted once; kept over a relog; dropped after 30 days;
--   d) looted, made, taken from the mail while a strip is up: the strip is drawn again.
-- luacheck: globals GAME PRINTS ERRORS DaylightRecipesDB NS ADDON_ROOT AuctionHouseFrame C_AuctionHouse C_Container C_Item
-- luacheck: globals UnitGUID UnitName GetRealmName UnitClass GetInboxNumItems GetInboxItem GetInboxHeaderInfo hooksecurefunc
-- luacheck: read globals T Fire NewObj
local ns = NS
local Shop = ns.Shop

local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Store.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Store.lua not found")

-- ---- the game, as much as Store.lua reads -------------------------------------------------------
local GUID = "Player-1-0001"
function UnitGUID() return GUID end
function UnitName(unit) return unit == "npc" and "Vendor Bob" or "Glowey" end
function GetRealmName() return "Realm" end
function UnitClass() return "Mage", "MAGE" end
ns.Faction = function() return "A" end
-- The bags: GAME.bags (itemID -> count), one stack a slot in bag 0.
local function slots()
	local out = {}
	for itemID, n in pairs(GAME.bags) do
		if n > 0 then out[#out + 1] = { itemID = itemID, stackCount = n } end
	end
	table.sort(out, function(a, b) return a.itemID < b.itemID end)
	return out
end
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and #slots() or 0 end
C_Container.GetContainerItemInfo = function(bag, slot) return bag == 0 and slots()[slot] or nil end
-- The mailbox: GAME.inbox = { { itemID, count, cod }, ... }, GAME.inboxTotal (letters in all).
GAME.inbox = {}
function GetInboxNumItems() return #GAME.inbox, GAME.inboxTotal or #GAME.inbox end
function GetInboxHeaderInfo(i) return nil, nil, nil, nil, nil, GAME.inbox[i] and GAME.inbox[i][3] or 0 end
function GetInboxItem(i, j)
	local m = GAME.inbox[i]
	if not m or j ~= 1 then return nil end
	return "Item " .. m[1], m[1], nil, m[2]
end
-- The Auction House's purchase call, and the game's hooksecurefunc (the hook runs after the call).
local confirms = 0
C_AuctionHouse = { ConfirmCommoditiesPurchase = function() confirms = confirms + 1 end }
function hooksecurefunc(tbl, name, hook)
	local real = tbl[name]
	tbl[name] = function(...)
		real(...)
		hook(...)
	end
end

-- (Prices.lua keeps price steps only for items a recipe uses: one recipe that uses cloth.)
ns.Recipes = { [900001] = { 197, nil, { 2589, 1 } } }

-- The real Store.lua, in place of the stand-in.
local src = assert(io.open(ROOT .. "/Store.lua", "r"))
local chunk = assert(loadstring(src:read("*a"), "@Store.lua"))
src:close()
chunk("DaylightRecipes", ns)
local Store = ns.Store

local THREAD, VIAL, DYE, CLOTH = 2320, 3371, 2604, 2589
local function shelf()
	return {
		{ id = THREAD, price = 10, stack = 1, max = 20 },
		{ id = VIAL, price = 4, stack = 1, max = 20 },
		{ id = DYE, price = 500, stack = 5, max = 5 },
	}
end
GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
AuctionHouseFrame = NewObj("Frame", "AuctionHouseFrame")
AuctionHouseFrame.w, AuctionHouseFrame.h = 800, 538
AuctionHouseFrame.shown = false

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
local function plans(t)
	GAME.plans = t
	Store.Char().plans = t
end
local function ah(itemID, copper)
	local db = Store.DB()
	local key = Store.RealmKey()
	db.prices[key] = db.prices[key] or { items = {} }
	db.prices[key].items[itemID] = { p = copper, t = GAME.clock, q = 50 }
	ns.Calc.Forget()
end
local function fresh()
	if GAME.merchant then T.leave() end
	if ahOpen then closeAH() end
	GAME.deliver = nil
	T.run(30)
	GAME.bought, GAME.total, GAME.limit = {}, {}, {}
	GAME.bags, GAME.queue, GAME.inbox, GAME.inboxTotal, GAME.live = {}, {}, {}, nil, nil
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [DYE] = 100 }
	GAME.money, GAME.freeSlots, GAME.stackSize = 1000000, 200, {}
	GAME.settings.askBuyAll = false
	C_Item.GetItemCount = nil
	PRINTS = {}
	DaylightRecipesDB = { shop = { vendor = true, auction = true } }
	plans({})
	local c = Store.Char()
	c.won, c.mail, c.bags, c.bank, c.removed = nil, {}, {}, {}, nil
	Store.DB().prices = {}
	-- (The bags as the game has them now, read into the snapshot.)
	Fire("BAG_UPDATE_DELAYED")
	T.run(1)
end
local function strip() return _G.DaylightRecipesBuyStrip end
local function ahStrip() return _G.DaylightRecipesAHStrip end
local function row(s, itemID)
	if not (s and s:IsShown() and s.list:IsShown()) then return nil end
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find("Item " .. itemID .. " x", 1, true) then return r end
	end
end
-- The number a row shows ("Item 2320 x 25" -> 25), or nil with no row.
local function shows(s, itemID)
	local r = row(s, itemID)
	return r and tonumber(r.left:match("x (%d+)")) or nil
end
local function said(text)
	for _, line in ipairs(PRINTS) do
		if line:find(text, 1, true) then return true end
	end
	return false
end
local function needed(itemID)
	for _, r in ipairs((Shop.List("guide"))) do
		if r.itemID == itemID then return r.buy end
	end
	return 0
end

-- ---- a) bought through the strip ----------------------------------------------------------------
T.case("a) exactly the number needed: the row counts down with each purchase and leaves, before the bags show any", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45, [VIAL] = 5 } } })
	GAME.limit[THREAD] = 45
	GAME.deliver = 5          -- the bags are late: five seconds
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(shows(s, THREAD), 45, "45 to buy")
	row(s, THREAD).onClick()
	T.eq(needed(THREAD), 25, "the first purchase (20) is counted the moment it is made")
	T.run(0.21)
	T.eq(needed(THREAD), 5, "the second, a step later")
	T.ok((shows(s, THREAD) or 0) < 45, "and the row has been drawn with less")
	T.run(0.8)
	T.eq((T.boughtOf(THREAD)), 45, "45 bought: exactly the number")
	T.eq(GAME.bags[THREAD], nil, "none of it in the bags yet")
	T.eq(row(s, THREAD), nil, "the row is gone at zero, before any bag update")
	T.eq(shows(s, VIAL), 5, "the other row is untouched")
	T.run(10)
	T.eq(GAME.bags[THREAD], 45, "(the bags have it now)")
	T.eq(row(s, THREAD), nil, "and the row stays gone: nothing is counted twice or comes back")
	T.eq(needed(THREAD), 0, "nothing more is needed")
	T.eq(Store.Count(THREAD).mine, 45, "the snapshot holds what was bought, once")
end)

T.case("a) part of it: the row shows the rest, and still does when the bags catch up", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45 } } })
	GAME.money = 200            -- pays for 20
	GAME.limit[THREAD] = 45
	GAME.deliver = 3
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(s.main.text:GetText(), "Buy What I Can Afford", "short of gold")
	s.main:Click()
	T.run(1)
	T.eq((T.boughtOf(THREAD)), 20, "20 bought")
	T.eq(shows(s, THREAD), 25, "the row shows the 25 still to buy, at once")
	T.ok(said("Item " .. THREAD .. " x 25") and said("not enough gold"), "chat says what was left out")
	T.run(10)
	T.eq(shows(s, THREAD), 25, "the bags caught up: still 25, not 5 and not 45")
	GAME.money = 1000
	Fire("PLAYER_MONEY")
	T.run(1)
	s.main:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 45, "the rest is bought on another press: 45 in all")
	T.eq(row(s, THREAD), nil, "and the row leaves")
end)

T.case("a) a lot larger than the need: one lot, and the row leaves", function()
	fresh()
	plans({ [197] = { need = { [DYE] = 3 } } })
	GAME.limit[DYE] = 5
	GAME.deliver = 2
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(shows(s, DYE), 3, "3 to buy")
	T.ok(row(s, DYE).right:find("Buy 5", 1, true), "the row says a whole lot of 5 is what a press buys")
	row(s, DYE).onClick()
	T.run(1)
	T.eq((T.boughtOf(DYE)), 5, "one lot: the game sells no part of one")
	T.eq(row(s, DYE), nil, "the row is gone")
	T.run(10)
	T.eq(row(s, DYE), nil, "and stays gone with 5 in the bags")
end)

T.case("a) bags full: what fits is bought, the rest stays on the row", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45 } } })
	GAME.freeSlots, GAME.stackSize = 1, { [THREAD] = 20 }
	GAME.limit[THREAD] = 20
	GAME.deliver = 0.3
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 20, "one slot's worth")
	T.eq(shows(strip(), THREAD), 25, "the row shows the rest")
	T.ok(said("no bag space"), "and chat says why")
end)

-- ---- b) bought by hand in the vendor's own window ------------------------------------------------
T.case("b) bought by hand: counted from the game's own bag count as the bags settle", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45 } } })
	GAME.live = {}
	C_Item.GetItemCount = function(itemID) return GAME.live[itemID] or 0 end
	-- (The vendor itself raises on the 26th thread our own purchases bring.)
	GAME.limit[THREAD] = 25
	GAME.deliver = nil
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(shows(s, THREAD), 45, "45 to buy")
	-- The player right-clicks the vendor's own thread: 20 land in the bags; the game says the
	-- bags settled. (Store.lua reads its snapshot half a second after that.)
	GAME.live[THREAD] = 20
	Fire("BAG_UPDATE_DELAYED")
	T.eq(needed(THREAD), 25, "what is needed is 25 the moment the bags hold them")
	T.run(0.25)
	T.eq(Store.Count(THREAD).bags, 0, "(the snapshot has not been read yet)")
	T.eq(shows(s, THREAD), 25, "and the row already shows 25")
	s.main:Click()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 25, "a press right after buys only the rest: 45 in all with the hand-bought")
	-- The snapshot catches up with everything.
	GAME.bags[THREAD] = 45
	GAME.live[THREAD] = 45
	T.bagEvent()
	T.run(2)
	T.eq(row(s, THREAD), nil, "the row is gone, and stays gone when the snapshot is read")
	T.eq(needed(THREAD), 0, "nothing counted twice")
end)

T.case("b) without the game's bag count: the row drops when the snapshot is read", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45 } } })
	T.vendor(shelf())
	T.run(1)
	GAME.bags[THREAD] = 20
	T.bagEvent()
	T.run(1)
	T.eq(shows(strip(), THREAD), 25, "within a second of the bags settling")
	GAME.bags[THREAD] = 45
	T.bagEvent()
	T.run(1)
	T.eq(row(strip(), THREAD), nil, "and leaves at zero")
end)

-- ---- c) bought at the Auction House --------------------------------------------------------------
T.case("c) a commodity bought at the Auction House lowers the count before any bag or mail update", function()
	fresh()
	plans({ [197] = { need = { [CLOTH] = 7, [THREAD] = 3 } } })
	ah(CLOTH, 30)
	openAH()
	local a = ahStrip()
	T.eq(shows(a, CLOTH), 7, "7 to buy")
	-- The buy dialog's Confirm (the game's window or Daylight UI's: both call this), then the
	-- game's answer.
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLOTH, 4)
	T.eq(confirms, 1, "(the game's own call is made as before)")
	T.eq(Store.Won(CLOTH), 0, "nothing is counted until the game says it succeeded")
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	T.eq(Store.Won(CLOTH), 4, "counted the moment it does")
	T.eq(needed(CLOTH), 3, "the list needs 3")
	T.run(0.3)
	T.eq(shows(a, CLOTH), 3, "and the row shows 3, with nothing in bags or mailbox read")
	T.eq(Store.Count(CLOTH).bags, 0, "(not in the bags)")
	T.eq(Store.Count(CLOTH).mail, 4, "counted as in the mail, where it is")
	-- The game's other event for the same purchase, when it comes at all.
	Fire("COMMODITY_PURCHASED", CLOTH, 4)
	T.eq(Store.Won(CLOTH), 4, "its second event is the same purchase: not counted again")
	-- The rest, with the events the other way round.
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLOTH, 3)
	Fire("COMMODITY_PURCHASED", CLOTH, 3)
	T.eq(Store.Won(CLOTH), 7, "counted from the first event")
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	T.eq(Store.Won(CLOTH), 7, "and not again from the second")
	T.run(0.3)
	T.eq(row(a, CLOTH), nil, "bought in full: the row is gone")
	T.eq(needed(THREAD), 3, "the other item is untouched")
end)

T.case("c) a purchase that fails, one the game only reports one way, and a single item", function()
	fresh()
	plans({ [197] = { need = { [CLOTH] = 7, [9100] = 2 } } })
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLOTH, 4)
	Fire("COMMODITY_PURCHASE_FAILED")
	T.eq(Store.Won(CLOTH), 0, "a failed purchase counts nothing")
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	T.eq(Store.Won(CLOTH), 0, "nor does a success with nothing confirmed before it")
	Fire("COMMODITY_PURCHASED", CLOTH, 2)
	T.eq(Store.Won(CLOTH), 2, "a purchase reported only with its item and number is counted")
	Fire("COMMODITY_PURCHASED", CLOTH, 2)
	T.eq(Store.Won(CLOTH), 4, "and a second such purchase is a second purchase")
	Fire("ITEM_PURCHASED", 9100)
	T.eq(Store.Won(9100), 1, "a single item bought counts one")
	T.eq(needed(9100), 1, "and the list needs one fewer")
	Store.NoteWon(CLOTH, 0)
	Store.NoteWon(nil, 3)
	T.eq(Store.Won(CLOTH), 4, "nonsense is not counted")
end)

T.case("c) the mailbox read takes over without counting twice; out of the mail it is in the bags, once", function()
	fresh()
	plans({ [197] = { need = { [CLOTH] = 7 } } })
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLOTH, 4)
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	T.eq(needed(CLOTH), 3, "4 bought: 3 needed")
	-- A relog in between: what was bought is kept with the character.
	T.eq(DaylightRecipesDB.chars[GUID].won[CLOTH].n, 4, "kept in the saved variables, with the character")
	-- At the mailbox: opened, its list not in yet.
	GAME.inbox = {}
	Fire("MAIL_SHOW")
	T.run(1)
	T.eq(needed(CLOTH), 3, "the mailbox open but its list not in: still counted")
	-- Its list comes in, but not all of it fits the inbox.
	GAME.inbox, GAME.inboxTotal = { { VIAL, 2 } }, 60
	Fire("MAIL_INBOX_UPDATE")
	T.run(1)
	T.eq(Store.Won(CLOTH), 4, "an inbox not listed in full does not end the count")
	T.eq(needed(CLOTH), 3, "3 needed")
	-- The whole inbox, with the auction's letter.
	GAME.inbox, GAME.inboxTotal = { { VIAL, 2 }, { CLOTH, 4 } }, nil
	Fire("MAIL_INBOX_UPDATE")
	T.run(1)
	T.eq(Store.Won(CLOTH), 0, "the mailbox holds it: the purchase's own count ends")
	T.eq(Store.Count(CLOTH).mail, 4, "it is counted in the mail, once")
	T.eq(needed(CLOTH), 3, "still 3 needed: not 7, and not minus one")
	-- Taken out of the letter: gone from the mail, in the bags.
	GAME.inbox = { { VIAL, 2 } }
	GAME.bags[CLOTH] = 4
	Fire("MAIL_INBOX_UPDATE")
	T.bagEvent()
	T.run(2)
	T.eq(Store.Count(CLOTH).mail, 0, "out of the mail")
	T.eq(Store.Count(CLOTH).bags, 4, "in the bags")
	T.eq(needed(CLOTH), 3, "and still 3 needed")
	-- A cash-on-delivery letter is not yours yet.
	GAME.inbox = { { CLOTH, 3, 500 } }
	Fire("MAIL_INBOX_UPDATE")
	T.run(1)
	T.eq(needed(CLOTH), 3, "a cash-on-delivery letter is not counted")
end)

T.case("c) a purchase the mailbox never shows is dropped after 30 days", function()
	fresh()
	plans({ [197] = { need = { [CLOTH] = 7 } } })
	Fire("COMMODITY_PURCHASED", CLOTH, 4)
	T.eq(needed(CLOTH), 3, "counted")
	GAME.clock = GAME.clock + 29 * 86400
	T.eq(needed(CLOTH), 3, "still after 29 days")
	GAME.clock = GAME.clock + 2 * 86400
	T.eq(Store.Won(CLOTH), 0, "an auction's letter is gone after 30: so is the count")
	T.eq(needed(CLOTH), 7, "and the list asks for it again")
	GAME.clock = GAME.clock - 31 * 86400
end)

T.case("c) a purchase at the Auction House takes its units off the item's price steps", function()
	fresh()
	plans({ [197] = { need = { [CLOTH] = 10 } } })
	ns.Prices.SetSteps(CLOTH, { { q = 4, p = 100 }, { q = 51, p = 120 } })
	T.eq((ns.Calc.AHCost(CLOTH, 10)), 1120, "10 cost 4 at 100 and 6 at 120")
	C_AuctionHouse.ConfirmCommoditiesPurchase(CLOTH, 4)
	T.eq(Store.Confirming(), true, "a purchase confirmed and not answered: being bought")
	Fire("COMMODITY_PURCHASE_SUCCEEDED")
	T.eq(Store.Confirming(), false, "answered: not any more")
	T.eq(ns.Prices.Steps(CLOTH).list[1].p, 120, "the 4 bought are gone from the cheapest step")
	T.eq(needed(CLOTH), 6, "6 still needed")
	T.eq((ns.Calc.AHCost(CLOTH, 6)), 720, "and they cost the next price")
	Fire("COMMODITY_PURCHASED", CLOTH, 4)
	T.eq(ns.Prices.Steps(CLOTH).list[1].q, 51, "the game's second event for the same purchase takes nothing more off")
end)

-- ---- d) looted, made, taken from the mail while a strip is up -------------------------------------
T.case("d) looted or made while the strip is up: it is drawn again with the new number", function()
	fresh()
	plans({ [197] = { need = { [THREAD] = 45, [VIAL] = 5 } } })
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	GAME.bags[THREAD] = 40
	T.bagEvent()
	T.run(1)
	T.eq(shows(s, THREAD), 5, "40 arrived another way: 5 to buy")
	GAME.bags[THREAD] = 45
	T.bagEvent()
	T.run(1)
	T.eq(row(s, THREAD), nil, "all of it: the row is gone")
	-- Used up again (a craft): the row is back with what is missing.
	GAME.bags[THREAD] = 30
	T.bagEvent()
	T.run(1)
	T.eq(shows(s, THREAD), 15, "used for a craft: the row is back with what is missing")
	-- The plan's own need shrinking (a skill point gained: Plan.Get saves the new need, then
	-- Core.lua asks the strips to draw again).
	Store.Char().plans[197].need[VIAL] = 2
	Shop.Refresh()
	T.run(1)
	T.eq(shows(s, VIAL), 2, "the plan needs fewer: so does the row")
end)

return T.done()
