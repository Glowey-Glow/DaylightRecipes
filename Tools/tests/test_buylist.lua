-- What the buy list holds for given plans, queue and bags; what a vendor's shelf makes of it; and
-- that nothing of ours shows at a vendor that sells nothing needed.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB
-- luacheck: read globals NS T Fire NewObj InstallProfLost
local ns = NS
local Shop = ns.Shop

local function byItem(list)
	local out = {}
	for _, r in ipairs(list) do out[r.itemID] = r end
	return out
end

-- Two plans (Tailoring 197, Alchemy 171) and a queue; some of it held already; an alt holds some.
GAME.plans = {
	[197] = { need = { [2320] = 24, [2604] = 30, [4291] = 5 } },
	[171] = { need = { [3371] = 10, [2320] = 6 } },
}
GAME.queue = { [2320] = 40, [14341] = 2 }
GAME.bags = { [2320] = 10, [2604] = 30, [4291] = 1 }
GAME.alts = { [4291] = 12 }

local list = Shop.List()
local rows = byItem(list)
T.eq(#list, 4, "four items still to buy")
T.eq(rows[2320].need, 40, "the larger of the plans' sum (30) and the queue's (40), not their total")
T.eq(rows[2320].buy, 30, "what this character holds is taken off")
T.eq(rows[2604], nil, "an item held in full is not on the list")
T.eq(rows[4291].buy, 4, "an alt's stock is never taken off")
T.eq(rows[4291].alert, "[Mira Has 12]", "an alt's stock is a note")
T.eq(rows[3371].buy, 10, "the second plan's item")
T.eq(rows[14341].buy, 2, "an item only the queue needs")
T.eq(rows[2320].lines[197], 24, "which plan needs how many is kept")
T.eq(rows[2320].lines.queue, 40, "and the queue's share")
T.eq(list[1].itemID, 2320, "most needed first")
T.eq(list[4].itemID, 14341, "least needed last")

-- The two lists apart: the Guide List is the plans alone, the Queue List the queue alone; the
-- list with no word asked for is both in one, as above.
local guide, queue = byItem(Shop.List("guide")), byItem(Shop.List("queue"))
T.eq(#Shop.List("guide"), 3, "the Guide List: what the plans need")
T.eq(guide[2320].need, 30, "the plans' sum for an item two of them need")
T.eq(guide[2320].buy, 20, "less what this character holds")
T.eq(guide[2320].lines.queue, nil, "the queue has no share in it")
T.eq(guide[14341], nil, "an item only the queue needs is not on it")
T.eq(#Shop.List("queue"), 2, "the Queue List: what the queue needs")
T.eq(queue[2320].need, 40, "the queue's own number")
T.eq(queue[2320].buy, 30, "less what this character holds")
T.eq(queue[2320].lines[197], nil, "no plan has a share in it")
T.eq(queue[3371], nil, "an item only a plan needs is not on it")
T.eq(queue[14341].buy, 2, "the queue's own item")

-- A vendor's shelf: single goods, goods sold in lots of 5, limited stock; one item it doesn't sell.
GAME.merchant = true
GAME.shelf = {
	{ id = 2320, price = 10, stack = 1, max = 20 },
	{ id = 4291, price = 500, stack = 5, max = 5 },
	{ id = 3371, price = 4, stack = 1, max = 20, left = 4 },
	{ id = 9999, price = 77, stack = 1 },
	{ id = 14341, price = 100, stack = 1, extended = true },
}
local shelf = Shop.Shelf()
T.eq(shelf[9999].index, 4, "the shelf is read by slot")
T.eq(shelf[14341], nil, "an item that costs tokens is never ours to buy")
T.eq(shelf[4291].unit, 100, "a lot's price is divided over its items")
local here, away, cost = Shop.Offer(list, shelf)
T.eq(#here, 3, "three needed items are sold here")
T.eq(#away, 1, "one is not")
T.eq(away[1].itemID, 14341, "the one not sold here")
local h = {}
for _, row in ipairs(here) do h[row.itemID] = row end
T.eq(h[2320].count, 30, "single goods: exactly the number needed")
T.eq(h[2320].price, 300, "and their price")
T.eq(h[4291].lots, 1, "4 needed from lots of 5: one whole lot (the game sells no part of a lot)")
T.eq(h[4291].count, 5, "a lot's items")
T.eq(h[3371].lots, 4, "limited stock: no more than the vendor has")
T.eq(h[3371].only, 4, "and the row can say how many are here")
T.eq(cost, 300 + 500 + 16, "the total of what is needed and sold here")

-- The same list at a vendor that sells none of it: nothing of ours appears.
GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
GAME.shelf = { { id = 9999, price = 77, stack = 1 }, { id = 9998, price = 5, stack = 1 } }
Fire("MERCHANT_SHOW")
T.run(2)
T.eq(_G.DaylightRecipesBuyStrip, nil, "no strip at a vendor that sells nothing needed")
T.eq(GAME.offered, nil, "and no tour offered there")
Fire("MERCHANT_CLOSED")

-- At one that sells something needed, the strip shows, as wide as its host, with the count. It
-- shows the Guide List (nothing was ever picked); what other vendors sell cheapest is "not sold
-- here" (the items with no price anywhere: test_lists.lua).
GAME.vendorPrice = { [2320] = 10, [4291] = 100, [3371] = 4, [14341] = 100 }
GAME.shelf = { { id = 2320, price = 10, stack = 1, max = 20 }, { id = 9999, price = 77, stack = 1 } }
GAME.money = 100000
Fire("MERCHANT_SHOW")
T.run(2)
local strip = _G.DaylightRecipesBuyStrip
T.ok(strip and strip:IsShown(), "the strip shows where something needed is sold")
T.ok(strip.lead:GetText():find("1", 1, true), "it counts the needed items sold here")
T.eq(strip.note:GetText(), "+2 Not Sold Here", "and the ones not sold here are one quiet note")
T.eq(strip.main.text:GetText(), "Buy All Needed", "the main button")
T.eq(strip.host, GAME.npc, "docked to the vendor window")
T.ok(not strip.list:IsShown(), "the list is shut until asked for")
T.eq(GAME.offered, "shop", "the first strip offers its tour by toast, not the tour itself")
-- Y / List opens the list: one row a needed item, then the folded "Not Sold Here".
strip.listButton:Click()
T.ok(strip.list:IsShown(), "List opens the list")
T.eq(strip.head.buttons[1].text, "Queue List (1)", "the list's top: the Queue List with what it needs here")
T.eq(strip.head.buttons[2].text, "Guide List (1)", "and the Guide List with its own")
T.eq(strip.head.buttons[2].active, true, "the Guide List is the one on show")
T.eq(#strip.doc.rows, 2, "one row for the item sold here, one folded heading for the rest")
T.eq(strip.doc.rows[1].left:sub(1, 14), "Item 2320 x 20", "the Guide List's number of it, not the queue's")
T.eq(strip.doc.rows[2].left, "Not Sold Here (2)", "the folded heading counts them")
strip.doc.rows[2].onClick()
T.eq(#strip.doc.rows, 4, "opened, the heading is followed by its two rows")
T.eq(strip.doc.rows[3].onClick, nil, "a row not sold here does nothing when pressed")
T.eq(DaylightRecipesDB.shop.vendor, true, "the open list is remembered")
T.eq(DaylightRecipesDB.shop.away, true, "and so is the open fold")
Fire("MERCHANT_CLOSED")
T.ok(not strip:IsShown(), "the strip goes with the vendor")

return T.done()
