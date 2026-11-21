-- The two lists (Queue List, Guide List), the automatic source filter, Remove and the profession
-- tags of the vendor's and the Auction House's strip (Shop.lua: Shop.List(kind, tag), Shop.Sift,
-- Shop.Remove, Picked, SetPick, SetTag), and that the rules of buying hold with all of them: Buy
-- All Needed never buys what the filter left out or the player removed, and a run keeps to the
-- list, the tag and the numbers of its press when another is picked under it. Played through the
-- strips' own buttons and rows against the strict vendor of mocks.lua (GAME.limit makes the vendor
-- itself raise on the first item bought over a number). Each case stands alone (T.case).
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightRecipesDB NS AuctionHouseFrame Auctionator
-- luacheck: read globals T Fire NewObj
local ns = NS
local Shop = ns.Shop

local THREAD, VIAL, DYE, CLOTH, GEM = 2320, 3371, 2604, 2589, 7777
-- A vendor that sells thread, vials and a gem; dye and cloth it doesn't.
local function shelf()
	return {
		{ id = THREAD, price = 10, stack = 1, max = 20 },
		{ id = VIAL, price = 4, stack = 1, max = 20 },
		{ id = GEM, price = 50, stack = 1, max = 20 },
	}
end

GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
AuctionHouseFrame = NewObj("Frame", "AuctionHouseFrame")
AuctionHouseFrame.w, AuctionHouseFrame.h = 800, 538
AuctionHouseFrame.shown = false

local book = { items = {} }
GAME.db.prices["Realm-A"] = book
-- An Auction House price, with how many are up (50 unless said: 10 or more is "enough up").
local function ah(itemID, copper, up)
	book.items[itemID] = copper and { p = copper, t = GAME.clock, q = up or 50 } or nil
	ns.Calc.Forget()
end

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

-- A clean start: nothing open, every timer and every "just bought" note run out, both lists open,
-- nothing picked, no prices.
local function fresh()
	if GAME.merchant then T.leave() end
	if ahOpen then closeAH() end
	GAME.deliver = nil
	T.run(30)
	GAME.bought, GAME.total, GAME.limit = {}, {}, {}
	GAME.bags, GAME.queue, GAME.plans, GAME.prof = {}, {}, {}, {}
	GAME.vendorPrice = {}
	GAME.removed, GAME.queueBy = {}, nil
	book.items = {}
	GAME.deliver = 0.3
	GAME.money, GAME.freeSlots, GAME.stackSize = 1000000, 200, {}
	GAME.settings.askBuyAll = false
	PRINTS = {}
	Auctionator = nil
	DaylightRecipesDB = { shop = { vendor = true, auction = true } }
end

local function strip() return _G.DaylightRecipesBuyStrip end
local function ahStrip() return _G.DaylightRecipesAHStrip end
local function question() return _G.DaylightRecipesConfirm end
local function up(s) return s ~= nil and s:IsShown() end
-- The row of an item in a strip's open list (any row: also one that does nothing when pressed).
local function row(s, itemID)
	if not (up(s) and s.list:IsShown()) then return nil end
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find("Item " .. itemID .. " x", 1, true) then return r end
	end
end
-- The list's last line when the filter left something out: its row, or nil.
local function quiet(s)
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find("cheaper", 1, true) then return r end
	end
end
-- A quiet line of the list by a word of it ("look for", "removed"), or nil.
local function line(s, word)
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find(word, 1, true) then return r end
	end
end
-- A profession tag of the list by its words ("All", "Prof 197"), or nil; the lit one's words.
local function tag(s, text)
	for _, b in ipairs(s.head.tags) do
		if b.text == text then return b end
	end
end
local function litTag(s)
	local out
	for _, b in ipairs(s.head.tags) do
		if b.active then out = out and "more than one" or b.text end
	end
	return out
end
-- The pair at the list's top: the button of a list, and which one is lit.
local function button(s, kind) return s.head.buttons[kind == "queue" and 1 or 2] end
local function lit(s)
	local q, g = s.head.buttons[1], s.head.buttons[2]
	if q.active and not g.active then return "queue" end
	if g.active and not q.active then return "guide" end
	return "neither or both"
end
local function key(s, name)
	for _, e in ipairs(s.padKeys) do
		if e.key == name then return e end
	end
end
local function said(text)
	for _, printed in ipairs(PRINTS) do
		if printed:find(text, 1, true) then return true end
	end
	return false
end
local function ids(list)
	local out = {}
	for _, r in ipairs(list) do out[r.itemID] = true end
	return out
end

-- ---- the source filter, by itself ---------------------------------------------------------------
T.case("the filter: what each place lists and what it leaves out", function()
	fresh()
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [DYE] = 100 }
	ah(THREAD, 8)            -- cheaper on the Auction House than at its vendor
	ah(CLOTH, 30)            -- only the Auction House has it
	ah(DYE, 90, 3)           -- a little cheaper there, but nearly sold out: the vendor wins
	-- (VIAL: only a vendor has a price. GEM: no price from either.)
	local list = {}
	for i, id in ipairs({ THREAD, VIAL, DYE, CLOTH, GEM }) do list[i] = { itemID = id, buy = 1 } end
	local shown, hidden = Shop.Sift(list, "auction")
	shown, hidden = ids(shown), ids(hidden)
	T.ok(shown[THREAD], "Auction House: what is cheapest there is listed")
	T.ok(shown[CLOTH], "what only the Auction House has a price for is listed")
	T.ok(shown[GEM], "what has no price from either stays on the Auction House's list")
	T.ok(hidden[VIAL], "what only a vendor has a price for is left out")
	T.ok(hidden[DYE], "what a vendor wins (the auction nearly sold out) is left out")
	T.ok(not shown[VIAL] and not shown[DYE] and not hidden[THREAD], "each row is in one of the two")
	-- At a vendor that sells thread, vials and the gem.
	local sells = { [THREAD] = {}, [VIAL] = {}, [GEM] = {} }
	shown, hidden = Shop.Sift(list, "vendor", sells)
	shown, hidden = ids(shown), ids(hidden)
	T.ok(hidden[THREAD], "vendor: what is cheapest on the Auction House is left out, sold here or not")
	T.ok(hidden[CLOTH], "what only the Auction House has is left out")
	T.ok(shown[VIAL], "what is cheapest at a vendor is listed")
	T.ok(shown[DYE], "also when this vendor doesn't sell it (it goes under Not Sold Here)")
	T.ok(shown[GEM], "what has no price is listed where this vendor sells it")
	local _, _, look = Shop.Sift(list, "vendor", sells)
	T.eq(#look, 0, "nothing to look for where the vendor sells every unpriced item")
	shown, hidden, look = Shop.Sift(list, "vendor", { [THREAD] = {} })
	T.ok(ids(look)[GEM] and not ids(shown)[GEM] and not ids(hidden)[GEM],
		"and is something to look for on the Auction House where this vendor doesn't: not called cheaper there")
	T.eq(list[1].src, "ah", "a row keeps its cheaper source")
	T.eq(list[5].src, nil, "none for a row with no price")
end)

-- ---- the two lists on the vendor's strip --------------------------------------------------------
T.case("before any pick the Guide List shows; each list has its own count", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.queue = { [THREAD] = 40 }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.ok(up(s), "the strip shows")
	T.eq(lit(s), "guide", "the Guide List is on show")
	T.eq(button(s, "queue").text, "Queue List (1)", "the Queue List's button counts what it needs here")
	T.eq(button(s, "guide").text, "Guide List (2)", "the Guide List's its own")
	T.ok(s.lead:GetText():find("2", 1, true), "the strip counts the list on show")
	T.eq(s.cost:GetText(), "320c", "and its cost: 30 thread and 5 vials, not the queue's 40 thread")
	T.ok(row(s, THREAD).left:find("x 30", 1, true), "a row has the Guide List's number")
	T.eq(DaylightRecipesDB.shop.pick, nil, "nothing is saved until the player picks")
end)

T.case("an empty remembered list gives way to the other for the visit, and nothing is saved", function()
	fresh()
	GAME.queue = { [THREAD] = 40 }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.ok(up(s), "the strip shows for the queue alone")
	T.eq(lit(s), "queue", "the Guide List is empty: the Queue List shows")
	T.eq(button(s, "guide").text, "Guide List (0)", "the empty one says so on its button")
	T.eq(DaylightRecipesDB.shop.pick, nil, "the remembered pick is not written over")
	T.eq(Shop.Picked("vendor"), "queue", "for this visit")
	T.leave()
	-- The other way round: the Queue List remembered and empty.
	GAME.queue = {}
	GAME.plans = { [197] = { need = { [VIAL] = 5 } } }
	DaylightRecipesDB.shop.pick = "queue"
	T.vendor(shelf())
	T.run(1)
	T.eq(lit(strip()), "guide", "an empty Queue List gives way to the Guide List")
	T.eq(DaylightRecipesDB.shop.pick, "queue", "and stays the remembered one")
	T.leave()
	-- With both holding something, the remembered one shows.
	GAME.queue = { [THREAD] = 3 }
	T.vendor(shelf())
	T.run(1)
	T.eq(lit(strip()), "queue", "the remembered list shows when it has something")
end)

T.case("a pick is remembered, shows at once, and is the Auction House's too", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.queue = { [THREAD] = 40, [GEM] = 2 }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	button(s, "queue").onClick()
	T.eq(DaylightRecipesDB.shop.pick, "queue", "the pick is saved beside the strips' other state")
	T.eq(lit(s), "queue", "and on show at once")
	T.ok(row(s, THREAD).left:find("x 40", 1, true), "with the queue's numbers")
	T.ok(row(s, GEM) ~= nil and row(s, VIAL) == nil, "and the queue's items only")
	T.eq(s.cost:GetText(), "500c", "the strip's cost is the queue's: 40 thread and 2 gems")
	T.leave()
	ah(THREAD, 5)
	openAH()
	local a = ahStrip()
	T.ok(up(a), "the Auction House's strip shows")
	T.eq(lit(a), "queue", "with the list picked at the vendor")
	button(a, "guide").onClick()
	T.eq(DaylightRecipesDB.shop.pick, "guide", "a pick there is saved the same way")
	T.eq(lit(a), "guide", "and shows")
end)

T.case("a list with nothing to buy says so in a sentence, and a list bought empty stays on show", function()
	fresh()
	GAME.plans = { [197] = { need = { [VIAL] = 5 } } }
	GAME.queue = { [THREAD] = 40 }
	GAME.limit[VIAL], GAME.limit[THREAD] = 5, 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(lit(s), "guide", "the Guide List")
	T.eq(#s.doc.lines, 0, "no sentence while it has rows")
	s.main:Click()
	T.run(5)
	T.eq((T.boughtOf(VIAL)), 5, "Buy All Needed buys the Guide List")
	T.eq((T.boughtOf(THREAD)), 0, "and nothing of the Queue List")
	T.ok(up(s), "the strip stays: the other list still has something here")
	T.eq(lit(s), "guide", "the list on show does not change by itself")
	T.eq(s.doc.lines[1], "Nothing on this list to buy here.", "the empty list says so")
	T.ok(s.lead:GetText():find("0", 1, true), "the strip counts none")
	T.eq(s.main.off, true, "and Buy All Needed is off")
	T.eq(button(s, "queue").text, "Queue List (1)", "the other list is one press away")
end)

T.case("a controller: Menu-right shows the other list, named with its count", function()
	fresh()
	GAME.plans = { [197] = { need = { [VIAL] = 5 } } }
	GAME.queue = { [THREAD] = 40, [GEM] = 1 }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	local e = key(s, "MENU_RIGHT")
	T.ok(e ~= nil, "the strip binds Menu-right")
	T.eq(e.when(), true, "on a strip with two lists")
	T.eq(e.label(), "Queue List (2)", "its hint names the list it shows")
	e.run()
	T.eq(lit(s), "queue", "a press shows the other list")
	T.eq(DaylightRecipesDB.shop.pick, "queue", "and it is remembered like a click")
	T.eq(e.label(), "Guide List (1)", "the hint then names the first one")
	T.ok(key(s, "X") and key(s, "Y"), "X and Y are the strip's as before")
	-- (A on a controller is a click: the pair's buttons and the list's rows are stops like any.)
end)

-- ---- the filter on the vendor's strip -----------------------------------------------------------
-- Thread is cheaper on the Auction House (and sold here); vials are a vendor's; the gem has no
-- price and is sold here; cloth has no price and isn't; dye is another vendor's.
local function mixed()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5, [GEM] = 2, [CLOTH] = 7, [DYE] = 3 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [DYE] = 100 }
	ah(THREAD, 8)
end

T.case("vendor: what is cheaper on the Auction House is left out, with one line that says so", function()
	mixed()
	GAME.plans[197].need[9001] = 4      -- a second unsold item cheaper on the Auction House
	ah(9001, 3)
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.ok(s.lead:GetText():find("2", 1, true), "the strip counts what is listed and sold here: vials and the gem")
	T.eq(s.cost:GetText(), "120c", "its cost is theirs alone")
	T.eq(s.note:GetText(), "+1 Not Sold Here", "another vendor's item is not sold here, as before")
	T.eq(button(s, "guide").text, "Guide List (2)", "the list's button counts the same")
	T.ok(row(s, VIAL) and row(s, GEM), "the vendor's item and the unpriced one sold here are rows")
	T.eq(row(s, THREAD), nil, "the thread is not: it is cheaper on the Auction House")
	T.eq(row(s, CLOTH), nil, "nor the unpriced item this vendor doesn't sell")
	local cheaper, look = quiet(s), line(s, "look for")
	T.eq(cheaper.left, "2 more are cheaper on the Auction House", "one line says how many are cheaper there")
	T.eq(cheaper.right, "Show", "and offers to show them")
	T.eq(look.left, "1 more to look for on the Auction House", "the unpriced one has a line of its own: it is not called cheaper")
	T.eq(look.right, "Show", "which offers the same")
	T.eq(s.doc.rows[#s.doc.rows], look, "the two are the list's last lines, in that order")
	cheaper.onClick()
	T.ok(row(s, THREAD) and row(s, 9001), "a press shows the cheaper ones")
	T.eq(row(s, CLOTH), nil, "not the other line's")
	T.ok(row(s, THREAD).onClick ~= nil, "one this vendor sells can be bought from its row")
	T.eq(row(s, 9001).onClick, nil, "one it doesn't sell does nothing")
	T.eq(row(s, 9001).right, "Auction House", "and says where it comes from")
	T.eq(quiet(s).right, "Hide", "the line then offers to hide them again")
	T.ok(s.lead:GetText():find("2", 1, true), "the count stays what is listed")
	T.eq(s.cost:GetText(), "120c", "and so does the cost")
	line(s, "look for").onClick()
	T.eq(row(s, CLOTH).right, "Elsewhere", "the other line shows its own, with where it comes from as far as that is known")
	T.eq(row(s, CLOTH).onClick, nil, "it cannot be bought here")
	quiet(s).onClick()
	T.eq(row(s, THREAD), nil, "a second press hides them")
	T.ok(row(s, CLOTH), "each line by itself")
	quiet(s).onClick()
	T.ok(row(s, THREAD), "(shown again)")
	T.walk(shelf())
	T.run(1)
	T.eq(row(strip(), THREAD), nil, "shown for one visit only: hidden again at the next")
	T.eq(row(strip(), CLOTH), nil, "both lines")
	T.eq(DaylightRecipesDB.shop.reveal, nil, "nothing of it is saved")
end)

T.case("vendor: one left out is said in the singular", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	ah(THREAD, 8)
	T.vendor(shelf())
	T.run(1)
	T.eq(quiet(strip()).left, "1 more is cheaper on the Auction House", "one")
end)

T.case("vendor: with everything sold here cheaper on the Auction House the strip stays and says so", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30 } } }
	GAME.vendorPrice = { [THREAD] = 10 }
	GAME.limit[THREAD] = 0
	ah(THREAD, 8)
	T.vendor(shelf())
	T.run(2)
	local s = strip()
	T.ok(up(s), "the strip shows: there is something to tell")
	T.ok(s.lead:GetText():find("0", 1, true), "it counts none needed here")
	T.eq(s.cost:GetText(), "", "no cost")
	T.eq(s.main.off, true, "Buy All Needed is off")
	T.eq(s.doc.lines[1], "Nothing on this list to buy here.", "the list says it is empty")
	T.eq(quiet(s).left, "1 more is cheaper on the Auction House", "and why")
	s.main.scripts.OnClick(s.main)
	T.run(2)
	T.eq(#GAME.bought, 0, "a press on the dead button buys nothing")
	T.leave()
	-- (The same thread with nearly none up: the vendor wins, and it is listed.)
	ah(THREAD, 8, 3)
	T.vendor(shelf())
	T.run(2)
	T.ok(strip().lead:GetText():find("1", 1, true), "with the auction nearly sold out the vendor is the cheaper source")
end)

T.case("vendor: still nothing at a vendor that sells nothing either list needs", function()
	fresh()
	GAME.plans = { [197] = { need = { [CLOTH] = 7, [DYE] = 3, [9001] = 4 } } }
	GAME.queue = { [9001] = 2 }
	GAME.vendorPrice = { [DYE] = 100 }
	ah(9001, 3)
	Shop.Remove("guide", DYE)
	T.vendor(shelf())
	T.run(2)
	T.ok(not up(strip()), "an item of another vendor, one to look for, one cheaper on the Auction House, one removed: none sold here, no strip")
end)

-- ---- buying with the filter ---------------------------------------------------------------------
T.case("Buy All Needed never buys what the filter left out, hidden or shown", function()
	mixed()
	GAME.limit[THREAD], GAME.limit[VIAL], GAME.limit[GEM] = 0, 5, 2
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	s.main:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 0, "no thread: it is cheaper on the Auction House")
	T.eq((T.boughtOf(VIAL)), 5, "the vials")
	T.eq((T.boughtOf(GEM)), 2, "and the gems")
	T.ok(not said("Item " .. THREAD), "and chat does not call the thread left out for stock, gold or bags")
	-- Again with the rows shown: the button still covers only what is listed.
	mixed()
	GAME.limit[THREAD], GAME.limit[VIAL], GAME.limit[GEM] = 0, 5, 2
	T.vendor(shelf())
	T.run(1)
	s = strip()
	quiet(s).onClick()
	T.ok(row(s, THREAD), "the thread's row is on show")
	s.main:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 0, "Buy All Needed still buys none of it")
	T.eq((T.boughtOf(VIAL)), 5, "only the listed items")
end)

T.case("Buy All Needed asks about the listed items only", function()
	mixed()
	GAME.settings.askBuyAll = true
	GAME.limit[THREAD] = 0
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	local q = question()
	T.ok(q and q:IsShown(), "it asks")
	T.ok(q.what:GetText():find("Buy 2 items", 1, true), "about the two listed items")
	T.eq(q.cost:GetText(), "Total Cost: 120c", "with their total, the thread not in it")
	q.yes:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 0, "and Yes buys none of the thread")
	T.eq(#GAME.bought > 0, true, "but the rest")
end)

T.case("a row the player asked to see buys that item, exactly the number needed", function()
	mixed()
	GAME.limit[THREAD], GAME.limit[VIAL], GAME.limit[GEM] = 30, 0, 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	quiet(s).onClick()
	row(s, THREAD).onClick()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 30, "the thread: the player's own press on its row")
	T.eq(#GAME.bought, 2, "in two purchases of that item, and nothing else")
end)

T.case("a row from an older drawing buys nothing once its rows are hidden again", function()
	mixed()
	GAME.limit[THREAD] = 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	quiet(s).onClick()
	local press = row(s, THREAD).onClick
	quiet(s).onClick()
	T.eq(row(s, THREAD), nil, "hidden again")
	press()
	T.run(5)
	T.eq(#GAME.bought, 0, "the old row's press buys nothing")
	-- And at the next vendor, where nothing was asked to be shown.
	quiet(s).onClick()
	press = row(s, THREAD).onClick
	T.walk(shelf())
	T.run(1)
	press()
	T.run(5)
	T.eq(#GAME.bought, 0, "nor at another vendor")
end)

T.case("an item that becomes cheaper on the Auction House under a Buy All Needed run is not bought further", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	GAME.limit[THREAD], GAME.limit[VIAL] = 20, 5
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	T.eq((T.boughtOf(THREAD)), 20, "the first purchase, inside the press")
	-- (A scan lands: the thread is cheaper there now.)
	ah(THREAD, 2)
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 20, "no more of it is bought")
	T.eq((T.boughtOf(VIAL)), 5, "the run goes on with what is still listed")
	T.ok(not said("Item " .. THREAD), "and the thread is not reported as out of stock")
	T.ok(up(strip()), "the strip stays")
	T.ok(strip().lead:GetText():find("0", 1, true), "counting none")
	T.eq(quiet(strip()).left, "1 more is cheaper on the Auction House", "the thread is on the last line instead")
end)

-- ---- the two lists and the rules of buying -------------------------------------------------------
T.case("the other list picked under a run: the run keeps its own list and its press's numbers", function()
	fresh()
	GAME.queue = { [THREAD] = 30 }
	GAME.plans = { [197] = { need = { [THREAD] = 200, [VIAL] = 50 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	DaylightRecipesDB.shop.pick = "queue"
	-- (The vendor itself raises on the 31st thread and on any vial.)
	GAME.limit[THREAD], GAME.limit[VIAL] = 30, 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(lit(s), "queue", "the Queue List: 30 thread")
	s.main:Click()
	T.eq((T.boughtOf(THREAD)), 20, "the first purchase")
	button(s, "guide").onClick()
	T.eq(lit(s), "guide", "the Guide List is picked while the run is under way")
	T.eq(Shop.Buying(), true, "the run goes on")
	T.eq(s.main.off, true, "Buy All Needed is off while it does")
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 30, "it bought what its press showed: the queue's 30, not the guide's 200")
	T.eq((T.boughtOf(VIAL)), 0, "and nothing that is only on the other list")
	T.eq(Shop.Buying(), false, "the run is over")
	-- The Guide List now: what it needs less what the queue's run brought.
	GAME.limit[THREAD], GAME.limit[VIAL] = 200, 50
	T.run(1)
	T.ok(row(s, THREAD).left:find("x 170", 1, true), "the Guide List counts what is held now")
	s.main:Click()
	T.run(30)
	T.eq((T.boughtOf(THREAD)), 200, "a press on it buys the rest: never over the larger need")
	T.eq((T.boughtOf(VIAL)), 50, "and its own items")
end)

T.case("a larger list picked under a run of the smaller one, pressed all through", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 40 } } }
	GAME.queue = { [THREAD] = 500 }
	GAME.vendorPrice = { [THREAD] = 10 }
	GAME.limit[THREAD] = 40
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(lit(s), "guide", "the Guide List: 40 thread")
	local main = s.main.scripts.OnClick
	main(s.main)
	button(s, "queue").onClick()
	-- (Every press there is while the run lasts: the button, the new list's row, the pair.)
	for _ = 1, 8 do
		T.run(0.05)
		main(s.main)
		local r = row(s, THREAD)
		if r and r.onClick then r.onClick() end
	end
	T.eq(Shop.Buying(), true, "one run, still the first")
	T.eq((T.boughtOf(THREAD)) <= 40, true, "never over what its press showed")
	T.run(0.45)
	T.eq((T.boughtOf(THREAD)), 40, "the run ends at its own 40")
end)

T.case("a question asked about one list goes when the other is picked", function()
	fresh()
	GAME.settings.askBuyAll = true
	GAME.plans = { [197] = { need = { [VIAL] = 5 } } }
	GAME.queue = { [THREAD] = 40 }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	s.main:Click()
	local q = question()
	T.ok(q and q:IsShown(), "Buy All Needed asks about the Guide List")
	button(s, "queue").onClick()
	T.ok(not q:IsShown(), "picking the other list puts the question away")
	T.run(5)
	T.eq(#GAME.bought, 0, "and nothing was bought")
	s.main:Click()
	T.ok(q:IsShown() and q.cost:GetText() == "Total Cost: 400c", "a new press asks about the list on show")
end)

-- ---- the Auction House's strip -------------------------------------------------------------------
T.case("Auction House: what is cheaper at a vendor is left out, with one line that says so", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5, [GEM] = 2, [CLOTH] = 7, [DYE] = 3 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [DYE] = 100 }
	ah(THREAD, 8)
	ah(CLOTH, 30)
	ah(DYE, 90, 3)
	local made
	Auctionator = { API = { v1 = {
		ConvertToSearchString = function(_, o) return o.searchString end,
		CreateShoppingList = function(_, _, searches) made = searches end,
	} } }
	openAH()
	local a = ahStrip()
	T.ok(up(a), "the strip shows")
	T.ok(a.lead:GetText():find("3", 1, true), "it counts what is listed: thread, cloth and the unpriced gem")
	T.eq(a.cost:GetText(), "AH about 450c", "the cost is the listed items': 30 thread at 8 and 7 cloth at 30 (an estimate: no price steps read)")
	T.eq(a.note:GetText(), "Saves 60c", "and what the thread saves over its vendor")
	T.eq(button(a, "guide").text, "Guide List (3)", "the list's button counts the same")
	T.eq(row(a, THREAD).right, "AH about 240c", "a row cheaper here has its price here, said as about while its steps are not read")
	T.eq(row(a, GEM).right, "No Price", "an item with no price from either stays on this list")
	T.eq(row(a, VIAL), nil, "a vendor's item is not listed")
	T.eq(row(a, DYE), nil, "nor one a vendor wins with the auction nearly sold out")
	local last = a.doc.rows[#a.doc.rows]
	T.eq(last.left, "2 more are cheaper at a vendor", "the last line says how many and why")
	T.eq(last.right, "Show", "and offers to show them")
	a.main:Click()
	T.eq(made and #made, 3, "Auctionator's list is made of the listed items only")
	last.onClick()
	T.eq(row(a, VIAL).right, "Vendor 20c", "shown, a row has the vendor's price")
	T.ok(row(a, DYE), "both of them")
	T.eq(quiet(a).right, "Hide", "the line offers to hide them again")
	T.ok(a.lead:GetText():find("3", 1, true), "the count stays what is listed")
	made = nil
	a.main:Click()
	T.eq(made and #made, 3, "and so does Auctionator's list")
	closeAH()
	openAH()
	T.eq(row(ahStrip(), VIAL), nil, "shown for one visit only")
	T.eq(quiet(ahStrip()).right, "Show", "the line is back to offering")
end)

T.case("Auction House: one left out is said in the singular; with only vendor goods the strip says so", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	ah(THREAD, 8)
	openAH()
	T.eq(quiet(ahStrip()).left, "1 more is cheaper at a vendor", "one")
	closeAH()
	ah(THREAD, nil)
	openAH()
	local a = ahStrip()
	T.ok(up(a), "everything needed is a vendor's: the strip stays, to say so")
	T.ok(a.lead:GetText():find("0", 1, true), "it counts none to buy")
	T.eq(a.doc.lines[1], "Nothing on this list to buy here.", "the list says it is empty")
	T.eq(quiet(a).left, "2 more are cheaper at a vendor", "and why")
	closeAH()
	GAME.plans = {}
	openAH()
	T.ok(not up(ahStrip()), "with both lists empty nothing of ours shows")
end)

T.case("Auction House: an empty remembered list gives way to the other; an empty one says so", function()
	fresh()
	GAME.queue = { [CLOTH] = 4 }
	GAME.plans = { [197] = { need = { [VIAL] = 5 } } }
	GAME.vendorPrice = { [VIAL] = 4 }
	ah(CLOTH, 30)
	openAH()
	local a = ahStrip()
	T.eq(lit(a), "queue", "the Guide List holds only a vendor's item: the Queue List shows")
	T.eq(DaylightRecipesDB.shop.pick, nil, "nothing is saved")
	button(a, "guide").onClick()
	T.eq(lit(a), "guide", "the player's own pick is kept, empty or not")
	T.eq(a.doc.lines[1], "Nothing on this list to buy here.", "the empty list says so")
	T.eq(quiet(a).left, "1 more is cheaper at a vendor", "and the line under it says what was left out")
	T.ok(a.lead:GetText():find("0", 1, true), "the strip counts none")
end)

-- ---- Remove ---------------------------------------------------------------------------------------
-- (A Shift-click on a row runs the row's shift.run and nothing else: Doc.lua's own press path,
-- played on the real file in test_shiftrow.lua. Here: what every row offers, and what it does.)
T.case("Remove: every row offers it; it takes the item off that list only, and buys nothing", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5, [DYE] = 3 } } }
	GAME.queue = { [THREAD] = 40 }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [DYE] = 100 }
	GAME.limit[THREAD], GAME.limit[VIAL] = 0, 5
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	line(s, "Not Sold Here").onClick()
	for _, id in ipairs({ THREAD, VIAL, DYE }) do
		local r = row(s, id)
		T.eq(r.hover, nil, "a vendor's row has no search hint (item " .. id .. ")")
		T.eq(r.shift and r.shift.text, "Remove", "a row's Shift action reads Remove (item " .. id .. ")")
		T.eq(r.shift.tip, "Shift-click to remove this from the list.", "and its tooltip line says what it does")
	end
	T.eq(line(s, "Not Sold Here").shift, nil, "a line that is not an item has none")
	T.eq(line(s, "removed"), nil, "no removed line while nothing is removed")
	row(s, THREAD).shift.run()
	T.run(2)
	T.eq(#GAME.bought, 0, "removing buys nothing")
	T.eq(row(s, THREAD), nil, "the row is gone")
	T.ok(s.lead:GetText():find("1", 1, true), "the strip counts one fewer")
	T.eq(s.cost:GetText(), "20c", "its cost is without it")
	T.eq(button(s, "guide").text, "Guide List (1)", "so does the list's button")
	T.eq(button(s, "queue").text, "Queue List (1)", "the other list still has it")
	T.eq(GAME.removed.guide[THREAD], 30, "kept with the character: the item, and the list's need of it then")
	T.eq(GAME.plans[197].need[THREAD], 30, "the plan is not changed")
	T.eq(GAME.queue[THREAD], 40, "nor the queue")
	local last = s.doc.rows[#s.doc.rows]
	T.eq(last.left, "1 removed from this list: put it back", "the list's last line says one was removed")
	T.eq(last.shift, nil, "that line has no Remove")
	s.main:Click()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 0, "Buy All Needed buys none of the removed item")
	T.eq((T.boughtOf(VIAL)), 5, "only what is on the list")
	-- The other list still lists it, and it can be removed there too.
	button(s, "queue").onClick()
	T.ok(row(s, THREAD).left:find("x 40", 1, true), "the Queue List has its own thread")
	T.eq(line(s, "removed"), nil, "and nothing removed")
	button(s, "guide").onClick()
	-- Two removed: the plural; a press puts both back.
	line(s, "Not Sold Here").onClick()
	line(s, "Not Sold Here").onClick()
	row(s, DYE).shift.run()
	T.eq(line(s, "removed").left, "2 removed from this list: put them back", "two removed, said in the plural")
	T.eq(s.note:GetText(), "", "a removed item is not counted as not sold here either")
	line(s, "removed").onClick()
	T.ok(row(s, THREAD), "a press on the line puts them back")
	T.eq(GAME.removed.guide, nil, "all of that list's")
	T.eq(line(s, "removed"), nil, "and the line is gone")
end)

T.case("Remove: it ends by itself when the list needs the item no more, or more than it did", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	T.eq(Shop.Remove("guide", THREAD), true, "removed")
	T.eq(Shop.Remove("guide", GEM), false, "an item not on the list cannot be")
	T.eq(Shop.Remove(nil, THREAD), false, "nor from no list")
	local list, gone = Shop.List("guide")
	T.eq(#list, 1, "the list is without it")
	T.eq(gone[1].itemID, THREAD, "and names it as removed")
	T.eq(#Shop.List(), 2, "the list of everything (no kind) is not touched by removals")
	GAME.plans[197].need[THREAD] = 12
	T.eq(#Shop.List("guide"), 1, "needing less of it: still removed")
	GAME.plans[197].need[THREAD] = 30
	T.eq(#Shop.List("guide"), 1, "back to what it was: still removed")
	GAME.plans[197].need[THREAD] = 31
	T.eq(#Shop.List("guide"), 2, "needing more than when it was removed: it is back on the list")
	T.eq(GAME.removed.guide[THREAD], nil, "and the removal is over for good")
	GAME.plans[197].need[THREAD] = 30
	T.eq(#Shop.List("guide"), 2, "also when the need falls again")
	Shop.Remove("guide", THREAD)
	GAME.plans[197].need[THREAD] = nil
	Shop.List("guide")
	T.eq(GAME.removed.guide[THREAD], nil, "the list needs it no more: the removal ends")
	GAME.plans[197].need[THREAD] = 5
	T.eq(#Shop.List("guide"), 2, "needed again later, it is listed")
	-- Held in full is not "no longer needed": the removal stays while the plan still asks for it.
	Shop.Remove("guide", VIAL)
	GAME.bags[VIAL] = 5
	Shop.List("guide")
	T.eq(GAME.removed.guide[VIAL], 5, "an item held in full stays removed while the list needs it")
end)

T.case("Remove: an item removed under a run is not bought further", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	GAME.limit[THREAD], GAME.limit[VIAL] = 20, 5
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	local remove = row(s, THREAD).shift.run
	s.main:Click()
	T.eq((T.boughtOf(THREAD)), 20, "the first purchase, inside the press")
	remove()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 20, "removed under the run: no more of it is bought")
	T.eq((T.boughtOf(VIAL)), 5, "the run goes on with the rest")
	T.ok(not said("Item " .. THREAD), "and it is not reported as left out")
	-- A row's own run stops the same way.
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100 } } }
	GAME.vendorPrice = { [THREAD] = 10 }
	GAME.limit[THREAD] = 20
	T.vendor(shelf())
	T.run(1)
	s = strip()
	remove = row(s, THREAD).shift.run
	row(s, THREAD).onClick()
	remove()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 20, "a row's run too")
end)

T.case("Remove: with everything removed the strip stays and offers to put it back", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30 } } }
	GAME.vendorPrice = { [THREAD] = 10 }
	GAME.limit[THREAD] = 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	row(s, THREAD).shift.run()
	T.run(1)
	T.ok(up(s), "the strip stays")
	T.ok(s.lead:GetText():find("0", 1, true), "counting none")
	T.eq(s.main.off, true, "Buy All Needed is off")
	T.eq(s.doc.lines[1], "Nothing on this list to buy here.", "the list says it is empty")
	T.eq(line(s, "removed").left, "1 removed from this list: put it back", "and offers the removed one back")
	T.walk(shelf())
	T.run(1)
	T.ok(up(strip()), "at the next vendor that sells it too: removed is kept")
	T.eq(row(strip(), THREAD), nil, "still off the list")
	T.leave()
	-- The Auction House's strip: the same item, removed from the same list.
	GAME.plans[197].need[CLOTH] = 7
	ah(CLOTH, 30)
	local made
	Auctionator = { API = { v1 = {
		ConvertToSearchString = function(_, o) return o.searchString end,
		CreateShoppingList = function(_, _, searches) made = searches end,
	} } }
	openAH()
	local a = ahStrip()
	T.eq(row(a, CLOTH).shift.text, "Remove", "an Auction House row offers Remove too")
	T.eq(row(a, CLOTH).hover.text, "Left Click to Search", "and, under the mouse, says what a click does")
	T.ok(row(a, CLOTH).onClick ~= nil, "which it does: a press there searches")
	T.eq(line(a, "removed").hover, nil, "a line that is not an item has no such hint")
	T.eq(line(a, "removed").left, "1 removed from this list: put it back", "the thread removed at the vendor is removed here")
	local searched = false
	local was = row(a, CLOTH).onClick
	row(a, CLOTH).shift.run()
	T.eq(row(a, CLOTH), nil, "removed there")
	T.ok(a.lead:GetText():find("0", 1, true), "the strip counts none")
	T.eq(a.cost:GetText(), "", "no cost")
	T.eq(line(a, "removed").left, "2 removed from this list: put them back", "both on the last line")
	a.main:Click()
	T.eq(made, nil, "Auctionator's list is not made of removed items")
	T.ok(was ~= nil and not searched, "(removing searched for nothing)")
	line(a, "removed").onClick()
	a.main:Click()
	T.eq(made and #made, 1, "put back, the cloth is on Auctionator's list again (the thread is a vendor's)")
end)

T.case("Remove with a controller: the Menu button on the left, on a row", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	GAME.limit[THREAD] = 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	local e = key(s, "MENU_LEFT")
	T.ok(e ~= nil, "the strip binds Menu-left")
	T.eq(e.label, "Remove", "its hint reads Remove")
	T.eq(e.when(row(s, THREAD)), true, "with the cursor on an item's row")
	T.eq(e.when(nil), false, "not with the cursor on no stop")
	T.eq(e.when(s.listButton), false, "nor on the strip's own buttons")
	e.run(row(s, THREAD))
	T.run(2)
	T.eq(row(s, THREAD), nil, "a press removes the row's item")
	T.eq(#GAME.bought, 0, "and buys nothing")
	T.eq(e.when(line(s, "removed")), false, "the put-back line is not a row to remove")
	T.ok(line(s, "removed").onClick ~= nil, "it is a stop that A presses")
	e.run(nil)
	e.run(line(s, "removed"))
	T.eq(GAME.removed.guide[THREAD], 30, "Menu-left elsewhere does nothing")
end)

-- ---- the profession tags ---------------------------------------------------------------------------
-- Tailoring (197) needs thread and vials, Alchemy (171) vials and gems: the vials are shared.
local function twoProfessions()
	fresh()
	GAME.plans = {
		[197] = { need = { [THREAD] = 30, [VIAL] = 5 } },
		[171] = { need = { [VIAL] = 10, [GEM] = 2 } },
	}
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [GEM] = 50 }
end

T.case("tags: the Guide List by profession, with a shared item's share", function()
	twoProfessions()
	local all = Shop.List("guide")
	T.eq(#all, 3, "three items in all")
	local tailoring, alchemy = {}, {}
	for _, r in ipairs((Shop.List("guide", 197))) do tailoring[r.itemID] = r.buy end
	for _, r in ipairs((Shop.List("guide", 171))) do alchemy[r.itemID] = r.buy end
	T.eq(tailoring[THREAD], 30, "Tailoring: its thread")
	T.eq(tailoring[VIAL], 5, "and its share of the vials, not all 15")
	T.eq(tailoring[GEM], nil, "nothing of Alchemy's alone")
	T.eq(alchemy[VIAL], 10, "Alchemy: its share of the vials")
	T.eq(alchemy[GEM], 2, "and its gems")
	T.eq(alchemy[THREAD], nil, "no thread")
	-- Some held: the share is the smaller of what is still to buy in all and what the profession needs.
	GAME.bags[VIAL] = 12
	tailoring, alchemy = {}, {}
	for _, r in ipairs((Shop.List("guide", 197))) do tailoring[r.itemID] = r.buy end
	for _, r in ipairs((Shop.List("guide", 171))) do alchemy[r.itemID] = r.buy end
	T.eq(tailoring[VIAL], 3, "3 of 15 still to buy: Tailoring's 5 is cut to 3")
	T.eq(alchemy[VIAL], 3, "and Alchemy's 10 to 3: never more than is missing in all")
	GAME.bags[VIAL] = 15
	T.eq(#Shop.List("guide", 171), 1, "held in full, the shared item is on neither")
	T.eq(#Shop.List("guide", 333), 0, "a profession with no plan has nothing")
end)

T.case("tags: the Queue List by the profession of each queued recipe", function()
	fresh()
	GAME.queue = { [THREAD] = 40, [VIAL] = 16 }
	GAME.queueBy = { [197] = { [THREAD] = 40, [VIAL] = 6 }, [171] = { [VIAL] = 10 } }
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4 }
	local t, a = {}, {}
	for _, r in ipairs((Shop.List("queue", 197))) do t[r.itemID] = r.buy end
	for _, r in ipairs((Shop.List("queue", 171))) do a[r.itemID] = r.buy end
	T.eq(t[THREAD], 40, "Tailoring's queued thread")
	T.eq(t[VIAL], 6, "and its share of the vials")
	T.eq(a[VIAL], 10, "Alchemy's share")
	T.eq(a[THREAD], nil, "and none of the thread")
	T.eq(#Shop.List("queue"), 2, "the whole Queue List is as it was")
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(lit(s), "queue", "the Queue List shows")
	T.eq(#s.head.tags, 3, "All and its two professions")
	tag(s, "Prof 171").onClick()
	T.eq(row(s, THREAD), nil, "under Alchemy's tag: no thread")
	T.ok(row(s, VIAL).left:find("x 10", 1, true), "its 10 vials")
end)

T.case("tags: All first, one a profession; a press shows only that profession's items", function()
	twoProfessions()
	GAME.limit[THREAD], GAME.limit[VIAL], GAME.limit[GEM] = 30, 5, 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(#s.head.tags, 3, "three tags")
	T.eq(s.head.tags[1].text, "All", "All first")
	T.eq(s.head.tags[2].text, "Prof 171", "then the professions, by name")
	T.eq(s.head.tags[3].text, "Prof 197", "each as the plugin names it")
	T.eq(litTag(s), "All", "All is lit before any pick")
	T.eq(s.lead:GetText():find("Needed Here", 1, true) ~= nil, true, "the strip reads as ever")
	T.ok(row(s, VIAL).left:find("x 15", 1, true), "the shared item with its whole number")
	T.eq(s.cost:GetText(), "460c", "the whole list's cost: 300 + 60 + 100")
	tag(s, "Prof 197").onClick()
	T.eq(litTag(s), "Prof 197", "the picked tag is lit, and only it")
	T.eq(DaylightRecipesDB.shop.tag, 197, "the pick is saved beside the list's")
	T.ok(row(s, THREAD) and row(s, GEM) == nil, "only that profession's items")
	T.ok(row(s, VIAL).left:find("x 5", 1, true), "the shared item with that profession's share")
	T.ok(s.lead:GetText():find("2", 1, true) and s.lead:GetText():find("Prof 197", 1, true),
		"the strip says whose items it counts")
	T.eq(s.lead:GetText():find("Needed Here", 1, true), nil, "in the place of its usual words: no wider")
	T.eq(s.cost:GetText(), "320c", "and its cost is theirs: 300 + 20")
	T.eq(button(s, "guide").text, "Guide List (3)", "the pair still counts the whole list")
	-- Buy All Needed under the tag buys what the strip counts, and no more.
	s.main:Click()
	T.run(10)
	T.eq((T.boughtOf(THREAD)), 30, "Tailoring's thread")
	T.eq((T.boughtOf(VIAL)), 5, "its 5 vials, not all 15")
	T.eq((T.boughtOf(GEM)), 0, "and nothing of the other profession's")
	T.run(2)
	T.eq(row(s, THREAD), nil, "the thread's row is gone")
	-- (Holdings are not any one profession's: 10 of the 15 vials are still to buy in all, and a
	-- tag shows the smaller of that and its profession's need. So Tailoring's tag still lists 5.)
	T.ok(row(s, VIAL).left:find("x 5", 1, true), "the shared item: the smaller of what is missing in all (10) and the tag's need (5)")
	tag(s, "Prof 171").onClick()
	T.ok(row(s, VIAL).left:find("x 10", 1, true), "under the other tag: all 10 still missing")
	tag(s, "All").onClick()
	T.ok(row(s, VIAL).left:find("x 10", 1, true), "and under All: never more than the list needs in all")
end)

T.case("tags: a press on the lit one, or on All, shows everything; it is the Auction House's too", function()
	twoProfessions()
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	tag(s, "Prof 171").onClick()
	T.eq(litTag(s), "Prof 171", "picked")
	tag(s, "Prof 171").onClick()
	T.eq(litTag(s), "All", "pressed again: All")
	T.eq(DaylightRecipesDB.shop.tag, nil, "and nothing remembered")
	T.ok(row(s, THREAD), "everything shows")
	tag(s, "Prof 171").onClick()
	tag(s, "All").onClick()
	T.eq(litTag(s), "All", "All shows everything")
	tag(s, "Prof 171").onClick()
	T.leave()
	GAME.vendorPrice = {}
	ah(THREAD, 8)
	ah(VIAL, 3)
	ah(GEM, 40)
	local made
	Auctionator = { API = { v1 = {
		ConvertToSearchString = function(_, o) return o.searchString .. "=" .. o.quantity end,
		CreateShoppingList = function(_, _, searches) made = searches end,
	} } }
	openAH()
	local a = ahStrip()
	T.eq(litTag(a), "Prof 171", "the tag picked at the vendor is picked here")
	T.ok(a.lead:GetText():find("2", 1, true) and a.lead:GetText():find("Prof 171", 1, true), "the strip says so")
	T.eq(a.cost:GetText(), "AH about 110c", "its cost is that profession's: 10 vials at 3 and 2 gems at 40")
	T.eq(button(a, "guide").text, "Guide List (3)", "the pair counts the whole list")
	a.main:Click()
	T.eq(made and #made, 2, "Auctionator's list is the tag's items")
	table.sort(made)
	T.eq(made[1], "Item " .. VIAL .. "=10", "with that profession's share")
end)

T.case("tags: a remembered profession with no tag on this list shows All and is not forgotten", function()
	twoProfessions()
	DaylightRecipesDB.shop.tag = 333
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(#s.head.tags, 3, "the tags of this list")
	T.eq(litTag(s), "All", "All is lit")
	T.ok(row(s, THREAD) and row(s, GEM), "everything shows")
	T.eq(s.lead:GetText():find("Needed Here", 1, true) ~= nil, true, "and the strip names no profession")
	T.eq(DaylightRecipesDB.shop.tag, 333, "the pick is kept")
	T.leave()
	-- One profession on the list: no tag row at all, whatever is remembered.
	GAME.plans = { [197] = { need = { [THREAD] = 30, [VIAL] = 5 } } }
	DaylightRecipesDB.shop.tag = 197
	T.vendor(shelf())
	T.run(1)
	T.eq(#strip().head.tags, 0, "a list of one profession has no tags")
	T.ok(row(strip(), THREAD) and row(strip(), VIAL), "and shows all of it")
end)

T.case("tags: the filter's lines and the removed line follow the tag; Remove takes the item off the whole list", function()
	twoProfessions()
	GAME.plans[197].need[CLOTH] = 7
	GAME.plans[171].need[9001] = 4
	GAME.plans[171].need[9002] = 1
	ah(9001, 3)
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(quiet(s).left, "1 more is cheaper on the Auction House", "under All: Alchemy's auction item")
	T.eq(line(s, "look for").left, "2 more to look for on the Auction House", "and both unpriced ones")
	tag(s, "Prof 197").onClick()
	T.eq(quiet(s), nil, "under Tailoring's tag: nothing of its is cheaper there")
	T.eq(line(s, "look for").left, "1 more to look for on the Auction House", "and one of its own to look for")
	row(s, VIAL).shift.run()
	T.eq(GAME.removed.guide[VIAL], 15, "removed under a tag: off the list as a whole, with the list's whole need")
	T.eq(line(s, "removed").left, "1 removed from this list: put it back", "the tag's removed line")
	tag(s, "Prof 171").onClick()
	T.eq(row(s, VIAL), nil, "it is gone under the other profession's tag too")
	T.eq(line(s, "removed").left, "1 removed from this list: put it back", "which counts it as well")
	row(s, GEM).shift.run()
	tag(s, "Prof 197").onClick()
	T.eq(line(s, "removed").left, "1 removed from this list: put it back", "a tag's line counts only what that profession needs")
	tag(s, "All").onClick()
	T.eq(line(s, "removed").left, "2 removed from this list: put them back", "All counts both")
end)

T.case("tags: another tag picked under a run does not widen it", function()
	fresh()
	GAME.plans = {
		[197] = { need = { [THREAD] = 100, [VIAL] = 5 } },
		[171] = { need = { [VIAL] = 50, [GEM] = 2 } },
	}
	GAME.vendorPrice = { [THREAD] = 10, [VIAL] = 4, [GEM] = 50 }
	-- (The vendor itself raises on the 6th vial and on any gem.)
	GAME.limit[THREAD], GAME.limit[VIAL], GAME.limit[GEM] = 100, 5, 0
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	tag(s, "Prof 197").onClick()
	local main = s.main.scripts.OnClick
	main(s.main)
	T.eq(Shop.Buying(), true, "a run under Tailoring's tag")
	tag(s, "Prof 171").onClick()
	T.eq(litTag(s), "Prof 171", "Alchemy's tag picked under it")
	for _ = 1, 6 do
		T.run(0.05)
		main(s.main)
		local r = row(s, GEM)
		if r and r.onClick then r.onClick() end
	end
	tag(s, "All").onClick()
	T.run(20)
	T.eq((T.boughtOf(THREAD)), 100, "the run bought its own tag's thread")
	T.eq((T.boughtOf(VIAL)), 5, "that tag's share of the shared item: 5, not the 55 the list needs")
	T.eq((T.boughtOf(GEM)), 0, "and nothing of the tag picked later")
	T.eq(Shop.Buying(), false, "the run is over")
	-- A row's run under a tag is held to the row's number the same way.
	fresh()
	GAME.plans = { [197] = { need = { [VIAL] = 5 } }, [171] = { need = { [VIAL] = 50 } } }
	GAME.vendorPrice = { [VIAL] = 4 }
	GAME.limit[VIAL] = 5
	GAME.deliver = nil
	T.vendor(shelf())
	T.run(1)
	s = strip()
	tag(s, "Prof 197").onClick()
	T.ok(row(s, VIAL).left:find("x 5", 1, true), "the row shows the tag's 5")
	row(s, VIAL).onClick()
	tag(s, "All").onClick()
	T.run(5)
	T.eq((T.boughtOf(VIAL)), 5, "pressed under the tag, it buys the 5 it showed")
end)

T.case("tags: a question asked under a tag goes when another is picked", function()
	twoProfessions()
	GAME.settings.askBuyAll = true
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	tag(s, "Prof 197").onClick()
	s.main:Click()
	local q = question()
	T.ok(q and q:IsShown() and q.cost:GetText() == "Total Cost: 320c", "Buy All Needed asks about the tag's items")
	tag(s, "Prof 171").onClick()
	T.ok(not q:IsShown(), "picking another tag puts the question away")
	T.eq(#GAME.bought, 0, "nothing bought")
end)

return T.done()
