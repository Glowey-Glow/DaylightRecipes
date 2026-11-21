-- Buying: what a press picks within gold, stock and bag space; the calls it makes; and whole
-- presses played against the strict vendor of mocks.lua (which raises on any purchase the game
-- would refuse), checking that nothing over the need or over the gold is ever bought.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB
-- luacheck: read globals NS T Fire NewObj InstallProfLost
local ns = NS
local Shop = ns.Shop

local function bought()
	local count, cost = {}, 0
	for _, b in ipairs(GAME.bought) do
		count[b.itemID] = (count[b.itemID] or 0) + b.count
		cost = cost + b.cost
	end
	return count, cost
end

local function printed(text)
	for _, line in ipairs(PRINTS) do
		if line:find(text, 1, true) then return line end
	end
end

-- ---- Picks: within gold, in list order -------------------------------------------------------
local A = { index = 1, unit = 10, stack = 1, maxStack = 20 }
local B = { index = 2, unit = 100, stack = 5, maxStack = 5 }
local C = { index = 3, unit = 100, stack = 1, maxStack = 20 }
local list = {
	{ itemID = 1, buy = 30 },
	{ itemID = 2, buy = 4 },
	{ itemID = 3, buy = 10 },
}
local here = Shop.Offer(list, { [1] = A, [2] = B, [3] = C })
local picks, out, total = Shop.Picks(here, 100000)
T.eq(#picks, 3, "with enough gold everything is picked")
T.eq(#out, 0, "and nothing is left out")
T.eq(total, 300 + 500 + 1000, "the total is what will be spent")

picks, out, total = Shop.Picks(here, 900)
T.eq(picks[1].count, 30, "the first row in full")
T.eq(picks[2].count, 5, "the second: one lot")
T.eq(picks[3].count, 1, "the third: what the rest of the gold pays for")
T.eq(total, 900, "never more than the gold")
T.eq(#out, 1, "one row is short")
T.eq(out[1].itemID, 3, "the short one")
T.eq(out[1].count, 9, "how many of it were left out")
T.eq(out[1].why, "gold", "and why")

picks, out, total = Shop.Picks(here, 450)
T.eq(#picks, 2, "a lot that the gold doesn't reach is skipped whole, and cheaper rows after it still bought")
T.eq(picks[2].itemID, 3, "the third row gets what is left")
T.eq(picks[2].count, 1, "150 copper left pays for one")
T.eq(total, 400, "within gold")
T.eq(out[1].itemID, 2, "the lot is reported")
T.eq(out[1].count, 4, "with the number still needed")

picks, out, total = Shop.Picks(here, 5)
T.eq(#picks, 0, "no gold: nothing is picked")
T.eq(total, 0, "and nothing spent")
T.eq(#out, 3, "everything is reported")

-- Stock: a vendor with 2 left of a need of 10.
local limited = Shop.Offer({ { itemID = 3, buy = 10 } }, { [3] = { index = 3, unit = 100, stack = 1, maxStack = 20, left = 2 } })
picks, out = Shop.Picks(limited, 100000)
T.eq(picks[1].count, 2, "no more than the vendor has")
T.eq(out[1].why, "stock", "the rest is left out for stock")
T.eq(out[1].count, 8, "eight of them")
local soldOut = Shop.Offer({ { itemID = 3, buy = 10 } }, { [3] = { index = 3, unit = 100, stack = 1, maxStack = 20, left = 0 } })
T.ok(soldOut[1].soldOut, "none left: sold out")
picks, out = Shop.Picks(soldOut, 100000)
T.eq(#picks, 0, "nothing is bought of a sold-out item")
T.eq(out[1].count, 10, "all of it is left out")

-- Bags: two free slots, 20 to a slot.
picks, out = Shop.Picks(here, 100000, 2, function(itemID) return itemID == 1 and 20 or 5 end)
T.eq(picks[1].count, 30, "30 of a 20-stack item take the two slots")
T.eq(#picks, 1, "and nothing else fits")
T.eq(out[1].why, "bags", "left out for bag space")
picks = Shop.Picks(here, 100000, 2, function() return nil end)
T.eq(#picks, 3, "an item the game can't size yet is not held back for bag space")

-- ---- Calls ------------------------------------------------------------------------------------
picks = Shop.Picks(Shop.Offer({ { itemID = 1, buy = 45 }, { itemID = 2, buy = 12 } }, { [1] = A, [2] = B }), 100000)
local calls = Shop.Calls(picks)
T.eq(#calls, 3 + 3, "45 single goods at 20 a purchase: three calls; 12 from lots of 5: three lots")
T.eq(calls[1].quantity, 20, "a full purchase")
T.eq(calls[3].quantity, 5, "then the rest")
T.eq(calls[4].quantity, nil, "a lot is bought with the plain call, as the game's right-click does")
T.eq(calls[4].count, 5, "and counts as its items")

-- ---- A whole press: Buy All Needed -----------------------------------------------------------
GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
GAME.settings.askBuyAll = true
GAME.plans = { [197] = { need = { [2320] = 45, [4291] = 4, [3371] = 10, [8343] = 3 } } }
GAME.queue = {}
-- (8343 is another vendor's: "not sold here". One with no price anywhere would be left out as
-- the Auction House's: test_lists.lua.)
GAME.vendorPrice = { [8343] = 50 }
GAME.bags = { [2320] = 5 }
GAME.stackSize = { [2320] = 20, [4291] = 20, [3371] = 20 }
local function vendor()
	GAME.bought = {}
	GAME.merchant = true
	GAME.shelf = {
		{ id = 2320, price = 10, stack = 1, max = 20 },
		{ id = 4291, price = 500, stack = 5, max = 5 },
		{ id = 3371, price = 4, stack = 1, max = 20, left = 6 },
	}
	Fire("MERCHANT_SHOW")
	T.run(1)
	return _G.DaylightRecipesBuyStrip
end

GAME.money = 100000
local strip = vendor()
T.ok(strip:IsShown(), "the strip is up")
strip.main:Click()
local confirm = _G.DaylightRecipesConfirm
T.ok(confirm and confirm:IsShown(), "Buy All Needed asks first")
T.eq(#GAME.bought, 0, "and buys nothing until answered")
confirm.no:Click()
T.run(5)
T.eq(#GAME.bought, 0, "No buys nothing")
strip.main:Click()
confirm.yes:Click()
T.eq(#GAME.bought, 1, "Yes: the first purchase is made inside the press")
T.run(0.1)
T.eq(#GAME.bought, 1, "the next waits its turn")
T.run(5)
local count, cost = bought()
T.eq(count[2320], 40, "exactly the 40 still needed (45 less the 5 held)")
T.eq(count[4291], 5, "one lot of 5 for a need of 4")
T.eq(count[3371], 6, "all 6 the vendor had of a need of 10")
T.eq(#GAME.bought, 2 + 1 + 1, "40 in two purchases, one lot, one purchase of 6")
T.eq(cost, 400 + 500 + 24, "what was spent")
T.eq(GAME.money, 100000 - 924, "and paid")
T.ok(printed("Left out:") and printed("Item 3371 x 4"), "chat says what was left out: 4 the vendor didn't have")
-- The strip is drawn again after the run, from what is still needed: the 4 the vendor ran out of.
T.ok(strip:IsShown(), "the strip stays up: one needed item is left, sold out here")
T.ok(strip.lead:GetText():find("1 Needed Here", 1, true) or strip.lead:GetText():find("1|r Needed Here", 1, true), "it counts that one item")
T.ok(not strip.main:IsEnabled(), "and its button is off: there is nothing to buy")
T.eq(ns.Shop.Buying(), false, "the run is over")
T.noErrors("a whole press")
Fire("MERCHANT_CLOSED")

-- The same press with the question switched off.
PRINTS = {}
GAME.settings.askBuyAll = false
GAME.money = 100000
-- (The last purchases are still "just bought" for a moment; a later visit starts clean.)
T.run(10)
strip = vendor()
strip.main:Click()
T.ok(not confirm:IsShown(), "with Ask Before Buying All off there is no question")
T.run(5)
count = bought()
T.eq(count[2320], 40, "and it buys the same")
Fire("MERCHANT_CLOSED")
T.run(10)

-- Short of gold: the button says so, buys within the gold, and says what it left out.
PRINTS = {}
GAME.settings.askBuyAll = true
GAME.money = 450
strip = vendor()
T.eq(strip.main.text:GetText(), "Buy What I Can Afford", "short of gold, the button says what it will do")
T.ok(strip.cost:GetText():find("You Have", 1, true), "and the cost shows what you have")
strip.main:Click()
T.ok(confirm:IsShown(), "it still asks")
confirm.yes:Click()
T.run(5)
count, cost = bought()
T.eq(count[2320], 40, "the first row in full: 400")
T.eq(count[4291], nil, "the lot at 500 is out of reach")
T.eq(count[3371], 6, "the cheap row after it is still bought: 24")
T.eq(cost, 424, "424 of 450 spent")
T.ok(GAME.money >= 0, "never more than the gold")
T.ok(printed("Item 4291 x 4") and printed("not enough gold"), "chat names what the gold didn't reach")
Fire("MERCHANT_CLOSED")
T.run(10)

-- A single row: one press, no question, exactly the number needed.
PRINTS = {}
GAME.money = 100000
strip = vendor()
if not strip.list:IsShown() then strip.listButton:Click() end
T.eq(#strip.doc.rows, 4, "three rows sold here and the folded heading")
T.eq(strip.doc.rows[4].left, "Not Sold Here (1)", "the heading")
T.eq(strip.doc.rows[1].left:sub(1, 14), "Item 2320 x 40", "a row names the item and the number needed")
strip.doc.rows[1].onClick()
T.ok(not confirm:IsShown(), "a single row never asks")
T.run(5)
count = bought()
T.eq(count[2320], 40, "it buys that row")
T.eq(count[4291], nil, "and only that row")
Fire("MERCHANT_CLOSED")
T.run(10)

-- A row the game itself would ask about (150g or more a purchase) is asked about here too.
GAME.plans = { [197] = { need = { [7777] = 1 } } }
GAME.money = 5000000
GAME.bought = {}
GAME.merchant = true
GAME.shelf = { { id = 7777, price = 2000000, stack = 1, max = 1 } }
Fire("MERCHANT_SHOW")
T.run(1)
strip = _G.DaylightRecipesBuyStrip
strip.doc.rows[1].onClick()
T.ok(confirm:IsShown(), "a dear row asks, as the game's own window does")
T.eq(#GAME.bought, 0, "and waits for the answer")
confirm.yes:Click()
T.run(2)
T.eq(#GAME.bought, 1, "Yes buys it")
Fire("MERCHANT_CLOSED")
T.run(10)

-- The shelf changes under a run (a limited item sells out and the slots move up): it stops.
PRINTS = {}
GAME.settings.askBuyAll = false
GAME.plans = { [197] = { need = { [2320] = 100 } } }
GAME.bags = {}
GAME.freeSlots = 16
GAME.money = 100000
GAME.bought = {}
GAME.merchant = true
GAME.shelf = { { id = 2320, price = 10, stack = 1, max = 20 } }
Fire("MERCHANT_SHOW")
T.run(1)
strip = _G.DaylightRecipesBuyStrip
strip.main:Click()
T.eq(#GAME.bought, 1, "the first purchase")
GAME.shelf[1] = { id = 4444, price = 1, stack = 1, max = 20 }
T.run(5)
T.eq(#GAME.bought, 1, "another item in the slot: nothing more is bought there")
T.ok(printed("Item 2320 x 80"), "and what the run did not get to is said")
Fire("MERCHANT_CLOSED")
T.run(10)

-- The vendor closes under a run: it ends without an error.
GAME.bought = {}
GAME.merchant = true
GAME.shelf = { { id = 2320, price = 10, stack = 1, max = 20 } }
Fire("MERCHANT_SHOW")
T.run(1)
_G.DaylightRecipesBuyStrip.main:Click()
GAME.merchant = false
Fire("MERCHANT_CLOSED")
T.run(5)
T.eq(#GAME.bought, 1, "closing the vendor ends the run")
T.noErrors("a run cut short")

return T.done()
