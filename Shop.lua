-- Where you shop and train: one 32 px strip, docked flush to the window you are at, from your
-- plans (the route each profession's Leveling Guide works out, kept per character: Plan.Get saves
-- what it needs and which recipes it learns) and your crafting queue.
--   Vendor:   under the vendor's window, as wide as it: how many needed items this vendor sells,
--             their total cost, List, and Buy All Needed. Nothing at all shows at a vendor that
--             sells nothing you need. List drops a 320-wide list of one-line rows under the strip's
--             left end (six rows, then it scrolls); a press on a row buys that item at once, exactly
--             the number needed; what this vendor doesn't sell is folded under "Not Sold Here".
--             Buy All Needed asks once, with the total (the "Ask Before Buying All" option), and
--             buys in list order what your gold, the vendor's stock and your bags allow, then says
--             in chat what was left out. Counts are this character's (bags, bank, mail); an alt's
--             stock is a note in brackets, never taken off.
--   Trainer:  under the trainer's window: how many of the route's recipes you can learn here now,
--             their cost, and Learn All Recommended. Hidden when there is nothing to learn here.
--   Auction House: a compact strip flush under the window's bottom RIGHT corner (its right edge
--             on the window's; the same on Daylight UI's window, the game's and DaylightMogul's):
--             how many items are still to buy, what they cost there, List (a press on a row
--             searches for the item) and Check Prices or, with Auctionator, a shopping list. Buying
--             on the Auction House stays your own action. Beside the window's right edge instead
--             where there is no room under Daylight UI's window, and on the game's window with
--             Professionally Lost's button under that corner (see "Auction House" below).
--   Every strip's list hangs from its right end, at the host's bottom right corner: under it,
--             else beside the host's right edge, else upward over the host's lower right corner
--             (Shop.ListPlace). Never on the host's left.
-- Each strip docks to whichever window is showing: DaylightMogul's, Daylight UI's, or the game's.
-- With Professionally Lost's hand-offs (ProfLost.lua) the lists leave out what it covers.
--
-- Two lists, one on show: the vendor's and the Auction House's strip each show the Queue List
-- (what the crafting queue needs) or the Guide List (what the Leveling Guides' plans need), picked
-- with the pair of buttons at the top of the strip's list, each with its own count of items to buy
-- there (a controller: the Menu-right button on the strip, or A on either button). The pick is
-- remembered account-wide (DaylightRecipesDB.shop.pick) and shared by both strips; before any pick
-- it is the Guide List. Where the remembered list has nothing to buy and the other has, the other
-- shows for that visit and the remembered pick stays as it was. (Picked, SetPick.)
-- An automatic source filter (Shop.Sift, by Calc.Unit's cheaper source): the Auction House strip
-- leaves out what is cheapest at a vendor, the vendor's strip what is cheapest on the Auction
-- House; an item with no price from either stays on the Auction House's list and shows at a vendor
-- only when that vendor sells it. Nothing is dropped unsaid: a line at the list's end says how
-- many were left out and why ("N more are cheaper..."; at a vendor, apart from it, "N more to look
-- for on the Auction House" for the unpriced ones it doesn't sell), and a press on it shows them
-- for this visit (and again hides them). The lead's count, the cost and Buy All Needed cover only
-- what is listed: Buy All Needed never buys what the filter left out, shown or not (Begin,
-- NextCall); a press on such a row, once the player has asked to see it, buys that one.
-- Remove: a Shift-click on a row (Doc's o.shift; the row reads "Remove" while Shift is held over
-- it), or the Menu button on the left of a controller, takes the item off that list for this
-- character (Shop.Remove: c.removed[kind][itemID] = the need then; neither plan nor queue is
-- changed), out of its rows, counts, cost, Buy All Needed (looked at again before every purchase,
-- since NextCall reads Shop.List) and Auctionator's list. It ends when the list needs the item no
-- more or more than then; the list's last line, "N removed from this list: put them back", puts
-- all of that list's back.
-- On the Auction House's list a row under the mouse reads "Left Click to Search" in its right
-- text's place (Doc's o.hover), since a press there searches and buys nothing.
-- Profession tags, under the pair, where the list on show has items for two or more professions:
-- "All" and one a profession (Tags, TagRow, SetTag). A tag shows only that profession's items,
-- each with its share (Shop.List(kind, tag): the smaller of what is still to buy in all and what
-- the profession needs); the strip's count, cost, Buy All Needed, Auctionator's list and the
-- lines at the list's end follow it, the pair's counts stay the whole list's, and the strip names
-- the profession in the place of "Needed Here" / "To Buy". Remembered account-wide
-- (DaylightRecipesDB.shop.tag), one for both strips. A run keeps the tag of its press.
-- A strip stays up while there is anything to say: at a vendor while it sells anything either list
-- needs (listed, left out by the filter, or removed), at the Auction House while either list has
-- anything; counting none ("0 Needed Here") where nothing is listed.
-- Auction House prices follow what is really for sale when an item's price steps are known
-- (Prices.Steps: read from any search result, and for the whole list by "Check Prices"; carried
-- over from 2.7.0): an Auction House row's cost walks the steps cheapest first (Calc.AHCost), says
-- "only 40 for sale" when there are fewer than needed, and its tooltip lists the steps the
-- purchase takes. Without steps the cost is the count times the lowest price, said as "about".
-- Where a vendor sells the item too, only the units cheaper than the vendor are the Auction
-- House's (Calc.Split, in Shop.Sift): the rest is the vendor strip's, so the two ask for the whole
-- between them and nothing twice. Check Prices / Stop is a line of the Auction House strip's list
-- (under the pair and the tags) and the strip's own button where Auctionator List doesn't have it.
-- A purchase at the Auction House takes its units off the item's steps (Store.NoteWon).
-- The countdown: what a list still needs is the need less what this character holds (Have: the
-- snapshot of bags, bank and mail, the game's own bag count where that is more, and what was
-- bought at the Auction House since the mailbox was read: Store.lua), less what was bought here
-- and is not in the bags yet (Shop.Bought). A row leaves when that reaches zero.
--
-- Buying, read from the source before it was written:
--   * BuyMerchantItem(index [, quantity]) is a plain global: it has no entry in the client's API
--     documentation (Blizzard_APIDocumentationGenerated has no "BuyMerchantItem"), and the game's own
--     right-click calls it straight from Lua (Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua:704).
--   * Both references make several purchases from one press by spacing them on a timer, none of
--     them needing a click of their own: Daylight UI buys a stack every 0.2 s (DaylightUI/Npc/
--     Shop.lua:138, 178-196, checking the slot still holds the same item) and Professionally Lost
--     makes "the first purchase inside the click, the rest one per 0.2 s" (ProfessionallyLost/UI/
--     Buying.lua:150, 200-227). So the same is done here: the first inside the press, the next
--     every 0.2 s, each one checked against the shelf and your gold just before it is made.
--   * quantity counts items and is capped by GetMerchantItemMaxStack(index); goods sold in lots
--     (stackCount > 1) are only sold by the whole lot: the game's own amount box steps by the lot
--     (MerchantFrame.lua:735: OpenStackSplitFrame(max, self, ..., info.stackCount)). So a lot is
--     bought with one plain call each, and a need of 3 from lots of 5 buys one lot.
--   * Limits that are the server's, each looked at before a call: stock (numAvailable, in lots;
--     -1 or less = no limit: MerchantFrameDocumentation.lua:134, DaylightUI/Npc/Shop.lua:163),
--     gold (GetMoney), bag space (C_Container.GetContainerNumFreeSlots: ContainerDocumentation.lua
--     :297), goods paid in tokens (hasExtendedCost: never bought from here), goods you may not buy
--     (isPurchasable false).
--   * The game asks before a purchase of MERCHANT_HIGH_PRICE_COST (150g) or more, in Lua, before
--     it calls BuyMerchantItem (MerchantFrame.lua:672, 701-704): a direct call would skip that
--     question, so a row that dear is asked about here too, even though single rows otherwise buy
--     on one press.
-- luacheck: read globals GetPhysicalScreenSize
local _, ns = ...
if not ns.ok then return end
local L, Plural = ns.L, ns.Plural

local API = ns.API
local Doc, Calc = ns.Doc, ns.Calc
local Color = Doc.Color

local Shop = {}
ns.Shop = Shop

local TOP = 300              -- a profession's top skill
local STRIP_H = 32
local EDGE, GAP = 14, 8      -- the strip's side padding, the gap between its buttons
local LIST_W = 320
local LIST_ROWS = 6          -- one-line rows a list shows at the least (when it has as many)
local LIST_MOST = 16         -- and at the most, where there is room: past that it scrolls
local ROW_H = 22             -- Doc's one-line row: 20, and 2 to the next
local STEP = 0.2             -- seconds between two purchases of one press (both references' pace)

-- ---------------------------------------------------------------------------------------------
-- What your plans and queue need
-- ---------------------------------------------------------------------------------------------

local function Handed(key, line)
	local P = ns.ProfLost
	return P ~= nil and P.Handed(key, line) == true
end

-- RULE 5, LATE BAGS (the rules of buying are listed above "The game's side of buying"). What was
-- bought here and is not in the bag snapshot yet: itemID -> { count, base, at }. A purchase is
-- noted the moment it is made, with the number of that item the bag snapshot held then (base); the
-- need is worked out less what is still in flight: count - (bags now - base). So it does not matter
-- when the bags are read again, or how often other things make them be read (the snapshot is read
-- half a second after any bag, bank or mail event: Store.lua's Soon): the note only shrinks by what
-- has really arrived. A note the bags never answer (a purchase the server refused) is dropped
-- FLIGHT seconds after the last purchase of that item.
local FLIGHT = 10
local flight = {}

-- What this character holds of an item: Store.Count's answer (bags, bank, mail, and what was
-- bought at the Auction House since the mailbox was read), with the bags' number raised to what
-- the game counts in them this moment where that is more. The snapshot is read half a second
-- after the bags settle (Store.lua's Soon); the game's own count has what was just bought by hand
-- at the vendor's window, looted or made, at once, so a press that follows it straight away buys
-- no more than is still missing. (C_Item.GetItemCount(itemInfo) -> count, the bags only by
-- default: Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:451-467. Only ever raised:
-- should the two count different bags, the larger is the safe side of rule 1.)
local function Have(itemID)
	local have = ns.Store.Count(itemID)
	local get = C_Item and C_Item.GetItemCount
	if type(get) == "function" then
		local ok, live = pcall(get, itemID)
		if ok and type(live) == "number" and live > (have.bags or 0) then
			have.mine = (have.mine or 0) + live - (have.bags or 0)
			have.bags = live
		end
	end
	return have
end

local function BagsOf(itemID, have)
	have = have or (ns.Store and Have(itemID))
	return type(have) == "table" and tonumber(have.bags) or 0
end

-- How many of an item were bought here and have not shown in the bags yet. have: Store.Count's
-- answer for it, when the caller holds one.
function Shop.Bought(itemID, have)
	local b = flight[itemID]
	if not b then return 0 end
	local left = b.count - math.max(0, BagsOf(itemID, have) - b.base)
	if left <= 0 or GetTime() - b.at > FLIGHT then
		flight[itemID] = nil
		return 0
	end
	return left
end

local function NoteBought(itemID, count)
	if count <= 0 then return end
	-- (An older note is settled first: what of it arrived is taken off, one out of time dropped.)
	Shop.Bought(itemID)
	local b = flight[itemID]
	if b then
		b.count = b.count + count
		b.at = GetTime()
	else
		flight[itemID] = { count = count, base = BagsOf(itemID), at = GetTime() }
	end
end

-- REMOVED FROM A LIST. What the player took off the Queue List or the Guide List (a Shift-click
-- on its row, or the Menu button on the left of a controller): c.removed[kind][itemID] = the
-- list's need of it then, kept with the character beside its plans. It changes neither the plan
-- nor the queue: the item is only left out of that list (its rows, counts, cost, Buy All Needed,
-- Auctionator's list). It ends by itself when that list no longer needs the item at all, and when
-- it needs more of it than when it was removed; and when the player puts the list's removed
-- items back (the list's last line).
local function Removed(c, kind, make)
	if type(c.removed) ~= "table" then
		if not make then return nil end
		c.removed = {}
	end
	local t = c.removed[kind]
	if type(t) ~= "table" then
		if not make then return nil end
		t = {}
		c.removed[kind] = t
	end
	return t
end

-- Every material this character still has to buy:
-- { { itemID, need, have (Have), buy, lines = { [line] = n, queue = n }, by = { [line] = n } } }
-- most needed first.
-- kind: "guide" (only what the Leveling Guides' plans need), "queue" (only what the crafting queue
-- needs), or nil for both in one (per item the larger of the two, not their sum: the total, which
-- no strip shows any more; kept for a caller that wants everything, and the tests ask for it).
-- by: the list's need of the item profession by profession (the plan's line; the profession of
-- each queued recipe, Queue.NeedsByLine), for the strips' profession tags.
-- tag: a profession (its line) of that list: only its items, each with that profession's share,
-- buy = the smaller of what is still to buy in all and what that profession needs of it.
-- Second answer: the rows the player removed from that list (the same shape, not in the first).
-- A profession whose buy list is handed to Professionally Lost leaves its plan out; the crafting
-- queue is always counted.
function Shop.List(kind, tag)
	local c = ns.Store and ns.Store.Char()
	local out, gone = {}, {}
	if not c then return out, gone end
	local need, lines, by = {}, {}, {}
	for line, plan in pairs(kind ~= "queue" and type(c.plans) == "table" and c.plans or {}) do
		-- (plan.rested: a plan not worked out since it was handed off whole, Core.lua and
		-- ProfLost.RestPlan; it says nothing true about your skill now, so it is left out until
		-- its profession is read again.)
		if type(plan) == "table" and type(plan.need) == "table" and not plan.rested and not Handed("buy", line) then
			for itemID, n in pairs(plan.need) do
				if type(n) == "number" and n > 0 then
					need[itemID] = (need[itemID] or 0) + n
					lines[itemID] = lines[itemID] or {}
					lines[itemID][line] = n
					if kind == "guide" then
						by[itemID] = by[itemID] or {}
						by[itemID][line] = n
					end
				end
			end
		end
	end
	-- The queue's too ("queue" in lines: its share). (A Leveling Guide step queued is in both: the
	-- larger of the two is what's needed, not the sum.)
	if ns.Queue and kind ~= "guide" then
		for itemID, n in pairs(ns.Queue.Needs()) do
			need[itemID] = math.max(need[itemID] or 0, n)
			lines[itemID] = lines[itemID] or {}
			lines[itemID].queue = n
		end
		if kind == "queue" and type(ns.Queue.NeedsByLine) == "function" then
			for line, items in pairs(ns.Queue.NeedsByLine()) do
				for itemID, n in pairs(items) do
					if type(n) == "number" and n > 0 then
						by[itemID] = by[itemID] or {}
						by[itemID][line] = (by[itemID][line] or 0) + n
					end
				end
			end
		end
	end
	-- (A removal that has ended: the list needs the item no more, or more than it did then.)
	local removed = kind and Removed(c, kind)
	if removed then
		for itemID, was in pairs(removed) do
			local n = need[itemID]
			if not n or type(was) ~= "number" or n > was then removed[itemID] = nil end
		end
	end
	for itemID, n in pairs(need) do
		local have = Have(itemID)
		-- (What this character lacks: an alt's are only mentioned. Just bought, not in the bag
		-- snapshot yet: taken off already.)
		local buy = math.max(0, n - have.mine - Shop.Bought(itemID, have))
		if tag ~= nil then
			local share = by[itemID] and by[itemID][tag]
			buy = share and math.min(buy, share) or 0
		end
		if buy > 0 then
			local row = { itemID = itemID, need = n, have = have, buy = buy, lines = lines[itemID], by = by[itemID],
				alert = ns.Pages and ns.Pages.AltAlert(have) }
			if removed and removed[itemID] then gone[#gone + 1] = row else out[#out + 1] = row end
		end
	end
	local function most(a, b)
		if a.buy ~= b.buy then return a.buy > b.buy end
		return a.itemID < b.itemID
	end
	table.sort(out, most)
	table.sort(gone, most)
	return out, gone
end

-- Takes an item off a list ("queue" | "guide") for this character: true when it was on it. What
-- the list needs of it now is kept, so the removal can end when that grows.
function Shop.Remove(kind, itemID)
	if kind ~= "queue" and kind ~= "guide" then return false end
	local c = ns.Store and ns.Store.Char()
	if not c then return false end
	for _, r in ipairs((Shop.List(kind))) do
		if r.itemID == itemID then
			Removed(c, kind, true)[itemID] = r.need
			return true
		end
	end
	return false
end

-- Puts back everything removed from a list.
function Shop.PutBack(kind)
	local c = ns.Store and ns.Store.Char()
	if c and type(c.removed) == "table" then c.removed[kind] = nil end
end

-- A row showing part of what its item still needs (the Auction House's share, or the vendor's):
-- a view of the list's row with its own buy; everything else reads through. split: "own" (this
-- place's share, listed) or "other" (the other place's, left out here). (As 2.7.0's Part.)
local function Part(r, n, split)
	return setmetatable({ buy = n, split = split }, { __index = r })
end

-- THE SOURCE FILTER. A list's rows for a place ("vendor", with its shelf, or "auction"):
--   shown:  what that place lists;
--   hidden: what it leaves out because it is cheaper at the other kind of place;
--   look:   at a vendor, what has no price from either and this vendor doesn't sell: something
--           to look for on the Auction House (nothing says it is cheaper there).
-- With an item's Auction House price steps known (Calc.Split, from Prices.Steps: "Check Prices",
-- or any search) the item is shared out between the two: the units cheaper than a vendor are the
-- Auction House's, the rest a vendor's. Each place then lists a row for its own share (a Part with
-- that share as its buy) and leaves the other share out (a Part in `hidden`, counted in the "N
-- more are cheaper..." line as one item, whole or in part), so the two strips together ask for
-- the whole and nothing twice. (As 2.7.0's Placed.)
-- Without steps the item is one place's as a whole, by Calc.Unit's cheaper source (kept on the
-- row, r.src: "ah" | "vendor" | nil; a vendor wins over a nearly sold-out auction there): the
-- Auction House leaves out what is cheapest at a vendor (also what only a vendor has a price
-- for); a vendor leaves out what is cheapest on the Auction House, unless this vendor's own price
-- is no higher than that (2.7.0's Shop.AtVendor). An item with no price from either stays on the
-- Auction House's list and is listed at a vendor only when that vendor sells it. What is a
-- vendor's but not sold by this one stays in `shown`: Offer puts it under "Not Sold Here".
function Shop.Sift(list, place, shelf)
	local shown, hidden, look = {}, {}, {}
	for _, r in ipairs(list) do
		local best, src = Calc.Unit(r.itemID)
		r.src = src
		local atAH, atVendor, known = Calc.Split(r.itemID, r.buy)
		if known then
			local mine, theirs = atAH, atVendor
			if place ~= "auction" then mine, theirs = atVendor, atAH end
			if mine > 0 then shown[#shown + 1] = theirs > 0 and Part(r, mine, "own") or r end
			if theirs > 0 then hidden[#hidden + 1] = mine > 0 and Part(r, theirs, "other") or r end
		elseif place == "auction" then
			if src == "vendor" then hidden[#hidden + 1] = r else shown[#shown + 1] = r end
		elseif src == "ah" then
			local sold = shelf and shelf[r.itemID]
			if type(sold) == "table" and sold.unit and best and sold.unit <= best then
				shown[#shown + 1] = r
			else
				hidden[#hidden + 1] = r
			end
		elseif src == nil and not (shelf and shelf[r.itemID]) then
			look[#look + 1] = r
		else
			shown[#shown + 1] = r
		end
	end
	return shown, hidden, look
end

-- ---------------------------------------------------------------------------------------------
-- What a vendor can sell of it (no game calls from here to "The game's side": tested offline,
-- Tools/tests)
-- ---------------------------------------------------------------------------------------------

-- A list against a vendor's shelf (Shop.Shelf: itemID -> { index, unit, stack, left, maxStack }):
--   here:  { { itemID, r (the list's row), s (the shelf's), want (items needed), lots (whole lots
--            the vendor has for it), count (items those lots hold), price, soldOut, only (items
--            the vendor has, when fewer than needed) } } in list order;
--   away:  the list's rows this vendor doesn't sell;
--   cost:  what everything needed here costs.
function Shop.Offer(list, shelf)
	local here, away, cost = {}, {}, 0
	for _, r in ipairs(list) do
		local s = shelf[r.itemID]
		if not s then
			away[#away + 1] = r
		else
			-- (Sold by the lot: the fewest whole lots that cover the need.)
			local lots = math.ceil(r.buy / s.stack)
			local only
			if s.left and s.left < lots then
				lots = math.max(0, s.left)
				only = lots * s.stack
			end
			local h = { itemID = r.itemID, r = r, s = s, want = r.buy, lots = lots, count = lots * s.stack,
				price = lots * s.unit * s.stack, soldOut = lots == 0, only = only }
			here[#here + 1] = h
			cost = cost + h.price
		end
	end
	return here, away, cost
end

-- What a press buys of `here`, in list order: never more than needed (Offer's whole lots), never
-- more than the vendor has, than `money` pays for, or than `slots` free bag slots hold
-- (stackOf(itemID): how many of it fit one slot; nil for either = not counted).
--   picks: { { itemID, s, lots, count, price } };
--   out:   what was left out: { { itemID, count (items still needed), why = "stock" | "gold" | "bags" } };
--   total: what the picks cost.
function Shop.Picks(here, money, slots, stackOf)
	local picks, out, total = {}, {}, 0
	for _, h in ipairs(here) do
		local lots, why = h.lots, nil
		local lot = h.s.unit * h.s.stack
		if h.lots * h.s.stack < h.want then why = "stock" end
		if lots > 0 and lot > 0 then
			local can = math.floor(money / lot + 1e-6)
			if can < lots then lots, why = can, "gold" end
		end
		local per = slots and stackOf and stackOf(h.itemID) or nil
		if lots > 0 and per and per > 0 then
			-- (A slot takes `per` of it; partly filled stacks in the bags are not counted on.)
			local fit = math.floor(slots * per / h.s.stack)
			if fit < lots then lots, why = fit, "bags" end
		end
		if lots > 0 then
			local price = lots * lot
			picks[#picks + 1] = { itemID = h.itemID, s = h.s, lots = lots, count = lots * h.s.stack, price = price }
			money = money - price
			total = total + price
			if per and per > 0 then slots = slots - math.ceil(lots * h.s.stack / per) end
		end
		local missing = h.want - lots * h.s.stack
		if missing > 0 then out[#out + 1] = { itemID = h.itemID, count = missing, why = why or "stock" } end
	end
	return picks, out, total
end

-- The purchases for `picks`: { { index, quantity (nil: one lot), itemID, count, price } }. A lot a
-- call for goods sold in lots; single goods in calls of at most the vendor's cap a purchase.
function Shop.Calls(picks)
	local calls = {}
	for _, p in ipairs(picks) do
		local s = p.s
		if s.stack > 1 then
			for _ = 1, p.lots do
				calls[#calls + 1] = { index = s.index, itemID = p.itemID, count = s.stack, price = s.unit * s.stack }
			end
		else
			local left = p.count
			local most = math.max(1, s.maxStack or 1)
			while left > 0 do
				local q = math.min(left, most)
				calls[#calls + 1] = { index = s.index, quantity = q, itemID = p.itemID, count = q, price = s.unit * q }
				left = left - q
			end
		end
	end
	return calls
end

-- ---------------------------------------------------------------------------------------------
-- The game's side of buying
-- ---------------------------------------------------------------------------------------------
-- THE RULES OF BUYING. Whatever is pressed, however fast, with a mouse or a controller, and
-- whenever the bags, the gold or the vendor change under it, these hold; each is kept in ONE place,
-- named here, and Tools/tests/test_buysafety.lua plays each of them against a vendor that raises
-- on any purchase the game would refuse:
--   1. NEVER MORE THAN NEEDED ............ NextCall. No purchase is made from a number worked out
--      earlier (not at the press, not when the list was drawn, not for the question): the size of
--      every single purchase is worked out just before it is made, from what the plans and the
--      queue need now, less what this character holds now, less what is in flight (rule 5), on
--      the shelf as it stands now. Goods sold in lots are the one case that can end over the
--      number: the game sells no part of a lot, so a need of 3 from lots of 5 buys one lot.
--      The need is that of the list the press was made on (the Queue List or the Guide List: the
--      run carries it), and a Buy All Needed run buys nothing the source filter leaves out,
--      looked at again before every purchase.
--   2. NEVER MORE THAN THE PRESS SHOWED ... NextCall's cap and budget. A run buys of each item at
--      most the number, and in all at most the gold, that were worked out at its press (what the
--      row or the question said), even if the need grows while it runs or the other list is
--      picked under it: the run goes on with the list of its press and that press's numbers.
--   3. ONLY AT THE VENDOR OF THE PRESS .... Live. Every visit to a vendor has a number (session:
--      one more on every MERCHANT_SHOW and every MERCHANT_CLOSED, the two events the game's own
--      vendor window opens and closes on: Blizzard_APIDocumentationGenerated/
--      MerchantFrameDocumentation.lua:96, 112; Daylight UI's the same, DaylightUI/Npc/Window.lua:
--      692-696). A press, a question and a run carry the number they began in, and nothing is
--      bought under another: a run whose vendor closed is dead for good, also when another
--      vendor opens in the same moment and sells the same goods in the same slot.
--   4. ONE RUN AT A TIME .................. Begin. There is one `run`; while it is set, every
--      press is refused. It stays set until one STEP after its last purchase, so a second press
--      that comes faster than the step timer finds it set, and one that comes later finds the
--      purchase in flight (rule 5) and nothing left to buy.
--   5. LATE BAGS .......................... Shop.Bought (the ledger above Shop.List). A purchase
--      counts as held from the moment it is made until the bag snapshot shows it, however late
--      that is read and whatever else makes it be read in between.
-- What is not ours to rule: a purchase the server takes more than FLIGHT (10) seconds to put in
-- the bags is forgotten by rule 5 (it could not be told from one the server refused).

local merchantOpen = false

-- What this vendor sells: itemID -> { index, unit, stack, left (lots; nil: no limit), maxStack }.
function Shop.Shelf()
	local out = {}
	local n = GetMerchantNumItems and GetMerchantNumItems() or 0
	for i = 1, n do
		local itemID = GetMerchantItemID and GetMerchantItemID(i)
		if itemID then
			local price, stack, avail, buyable, extended
			-- (C_MerchantFrame.GetItemInfo(index) -> MerchantItemInfo: price, stackCount, numAvailable,
			-- isPurchasable, hasExtendedCost: MerchantFrameDocumentation.lua:27, 126-140.)
			local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
			if type(info) == "table" then
				price, stack, avail, buyable, extended = info.price, info.stackCount, info.numAvailable,
					info.isPurchasable, info.hasExtendedCost
			elseif GetMerchantItemInfo then
				local _, _, p, q, a, b, _, e = GetMerchantItemInfo(i)
				price, stack, avail, buyable, extended = p, q, a, b, e
			end
			-- (Only gold prices: an item that costs tokens or currency isn't bought from here.)
			if price and price > 0 and buyable ~= false and not extended then
				stack = math.max(1, stack or 1)
				out[itemID] = { index = i, unit = price / stack, stack = stack,
					left = (avail and avail >= 0) and avail or nil,
					maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or stack }
			end
		end
	end
	return out
end

-- Free slots in your ordinary bags (a bag for one kind of goods, its family not 0, isn't counted),
-- or nil when the game can't say.
local function FreeSlots()
	local get = C_Container and C_Container.GetContainerNumFreeSlots
	if type(get) ~= "function" then return nil end
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local ok, n, family = pcall(get, bag)
		if ok and type(n) == "number" and (family == nil or family == 0) then free = free + n end
	end
	return free
end

-- How many of an item fit one bag slot, or nil while the game doesn't know the item yet (then its
-- bag room isn't counted, and the game's own "inventory is full" stops a purchase that doesn't fit).
local function StackOf(itemID)
	-- (C_Item.GetItemMaxStackSizeByID(itemInfo) -> stackSize or nil: ItemDocumentation.lua:816.)
	local get = C_Item and C_Item.GetItemMaxStackSizeByID
	if type(get) ~= "function" then return nil end
	local ok, n = pcall(get, itemID)
	return ok and type(n) == "number" and n > 0 and n or nil
end

local function Money() return GetMoney and GetMoney() or 0 end

local WHY = { gold = L["not enough gold"], stock = L["the vendor has no more"], bags = L["no bag space"] }

local function Name(itemID)
	return Calc.ItemInfo(itemID) or ns.ItemNameOf(itemID) or L["Item %d"]:format(itemID)
end

-- Says in chat what a press left out, and why.
local function SayLeftOut(out)
	if #out == 0 then return end
	local parts = {}
	for i, o in ipairs(out) do
		if i > 6 then
			parts[#parts + 1] = L["+%d more"]:format(#out - 6)
			break
		end
		parts[#parts + 1] = L["%s x %d (%s)"]:format(Name(o.itemID), o.count, WHY[o.why] or WHY.stock)
	end
	ns.Print(L["Left out: %s."]:format(table.concat(parts, ", ")))
end

local session = 0          -- the vendor visit (rule 3)
local run                  -- the one buy run under way, or nil (rule 4)
-- What holds for one visit to a vendor, and for one to the Auction House: kind (the list on show
-- there, once settled: Picked), reveal (the rows the source filter left out are shown), look
-- (so are the ones to look for on the Auction House).
local visit = { vendor = {}, auction = {} }
function Shop.Buying() return run ~= nil end

-- RULE 3, ONLY AT THE VENDOR OF THE PRESS: whether `r` is the run under way, at the vendor visit
-- it began in, with that vendor still open. Asked before every purchase.
local function Live(r)
	return r ~= nil and r == run and merchantOpen and r.session == session
end

-- A vendor opened (open) or closed: another visit. A run of the last one is dead from here on
-- (its timer finds Live false and does nothing more); it says nothing in chat.
local function NewSession(open)
	session = session + 1
	merchantOpen = open
	run = nil
	visit.vendor = {}
end

-- Some of an item a run did not get to: added to what the press already left out of it (the two
-- never overlap: the press's count is what it could not pick, this is what it picked and missed).
local function Missed(out, itemID, count, why)
	for _, o in ipairs(out) do
		if o.itemID == itemID then
			o.count = o.count + count
			return
		end
	end
	out[#out + 1] = { itemID = itemID, count = count, why = why }
end

-- RULES 1 AND 2, NEVER MORE THAN NEEDED / THAN THE PRESS SHOWED: the next purchase of an item, or
-- nil (and why, when something of it is still needed: "stock", "gold" or "bags"). Everything is
-- read now: the need (Shop.List: plans and queue, less what this character holds, less what is
-- in flight), the shelf (which slot holds the item now, its price, stock and cap), the gold and
-- the bag space. cap: how many of it this run may still buy; budget: the gold it may still spend.
-- kind: the list the run's press was made on ("queue" | "guide"), whichever is on show now; tag:
-- the profession tag it was made under (nil: none), whichever is picked now. mode: what of the
-- item the run buys, looked at again here as prices stand now (Shop.Sift): "all" (a Buy All Needed
-- run) and "row" (a listed row's press) buy this vendor's share of it, which is all of it unless
-- its price steps say some is cheaper on the Auction House, and nothing once the filter leaves it
-- out; "extra" (a press on a row the player asked to see) buys the share the filter left out.
-- No such share: nil, and no reason, as for an item no longer needed. An item the player removed
-- from the list since the press is not on Shop.List's rows any more: nil the same way.
-- Returns { index, quantity (nil: one lot), itemID, count, price }.
local function NextCall(itemID, cap, budget, kind, mode, tag)
	local row
	for _, r in ipairs((Shop.List(kind, tag))) do
		if r.itemID == itemID then
			row = r
			break
		end
	end
	if not row then return nil end
	local s = Shop.Shelf()[itemID]
	if not s then return nil, "stock" end
	local shown, hidden = Shop.Sift({ row }, "vendor", { [itemID] = s })
	if mode == "extra" then row = hidden[1] else row = shown[1] end
	if not row then return nil end
	local here = Shop.Offer({ row }, { [itemID] = s })
	local picks, out = Shop.Picks(here, math.min(Money(), budget), FreeSlots(), StackOf)
	local call = Shop.Calls(picks)[1]
	if not call then return nil, out[1] and out[1].why or "stock" end
	if call.count > cap then
		-- (A lot larger than the press counted on: the shelf changed under the run.)
		if not call.quantity then return nil, "stock" end
		call.quantity, call.count, call.price = cap, cap, s.unit * cap
	end
	return call
end

local function Finish(r)
	if run == r then run = nil end
	SayLeftOut(r.out)
	Shop.Refresh()
end

-- One purchase of the run, then the next a STEP later (both references' pace: the header). The
-- first is made inside the press. The run ends one STEP after its last purchase (rule 4).
local function Step(r)
	if not Live(r) then return end
	while true do
		local w = r.want[r.at]
		if not w then return Finish(r) end
		local call, why
		if w.left > 0 then call, why = NextCall(w.itemID, w.left, r.budget, r.kind, r.mode, r.tag) end
		if call then
			-- (BuyMerchantItem(index [, quantity]): the header. Guarded, so an error can never
			-- leave the run set; Professionally Lost calls it guarded too, UI/Buying.lua:155-159,
			-- 186-196.)
			local ok, err
			if call.quantity then
				ok, err = pcall(BuyMerchantItem, call.index, call.quantity)
			else
				ok, err = pcall(BuyMerchantItem, call.index)
			end
			if not ok then
				geterrorhandler()(err)
				return Finish(r)
			end
			NoteBought(w.itemID, call.count)
			w.left = w.left - call.count
			r.budget = r.budget - call.price
			C_Timer.After(STEP, function() Step(r) end)
			return
		end
		if w.left > 0 and why then Missed(r.out, w.itemID, w.left, why) end
		r.at = r.at + 1
	end
end

-- RULE 4, ONE RUN AT A TIME: begins a run, unless one is under way or the vendor is not the one
-- of the press any more (token: the visit's number at the press, rule 3). only: one item (a row),
-- nil for everything needed here. What it may buy is worked out here, at the press (or at the
-- question's Yes): in list order, what your gold, the vendor's stock and your bags allow.
-- kind: the list of the press ("queue" | "guide"), tag: the profession tag of the press (nil:
-- none); the run keeps both, whichever are picked later, so it never grows past what its press
-- showed. Everything needed here is what the source filter lists (Shop.Sift) of what is on the
-- list (not removed from it), each item with this vendor's share of it. One item (only) is its
-- listed share, or, with extra, the share the filter left out, but that only while the player has
-- those rows shown (this visit's `reveal`).
local function Begin(token, only, kind, tag, extra)
	if run ~= nil or not merchantOpen or token ~= session then return false end
	if kind ~= "queue" and kind ~= "guide" then return false end
	local shelf = Shop.Shelf()
	local shown, hidden = Shop.Sift((Shop.List(kind, tag)), "vendor", shelf)
	local here = Shop.Offer(shown, shelf)
	if only then
		local from = here
		if extra then from = visit.vendor.reveal and (Shop.Offer(hidden, shelf)) or {} end
		local one = {}
		for _, h in ipairs(from) do
			if h.itemID == only then one[1] = h end
		end
		here = one
	end
	local picks, out, total = Shop.Picks(here, Money(), FreeSlots(), StackOf)
	if #picks == 0 then
		SayLeftOut(out)
		return false
	end
	local r = { session = session, want = {}, out = out, budget = total, at = 1, kind = kind, tag = tag,
		mode = only == nil and "all" or (extra and "extra" or "row") }
	for i, p in ipairs(picks) do r.want[i] = { itemID = p.itemID, left = p.count } end
	run = r
	Step(r)
	Shop.Refresh()
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Helpers of every strip
-- ---------------------------------------------------------------------------------------------

-- Whether DaylightUI's bags list every character's holdings under an item's tooltip: DaylightUI
-- 1.8.3 or later, its Bags module on and its bank and alts viewer not switched off. When that can't
-- be told for sure, no: then our own line stays.
local function AtLeast(version, want)
	if type(version) ~= "string" then return false end
	local a = { version:match("^(%d+)%.(%d+)%.?(%d*)") }
	if not a[1] then return false end
	for i = 1, 3 do
		local x, y = tonumber(a[i]) or 0, want[i]
		if x ~= y then return x > y end
	end
	return true
end

-- Whether the Daylight UI installed is at least `want` ({ major, minor, patch }), by its .toc
-- version ("2.0", "1.9.6"). When that can't be read, no. (As 2.5.3 on main.)
local function DaylightAtLeast(want)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	if type(meta) ~= "function" then return false end
	local ok, version = pcall(meta, "DaylightUI", "Version")
	return ok and AtLeast(version, want)
end

local function DuiListsHoldings()
	if not DaylightAtLeast({ 1, 8, 3 }) then return false end
	local on, bags = pcall(API.IsModuleEnabled, "Bags")
	if not on or not bags then return false end
	local got, viewer = pcall(API.GetSetting, "Bags", "viewer.enabled")
	if not got then return false end
	-- (Its "Item counts on tooltips" switch off: it adds nothing, DaylightUI_Bags\Saved.lua:265.)
	local read, counts = pcall(API.GetSetting, "Bags", "viewer.tipCounts")
	if read and counts == false then return false end
	return viewer ~= false
end

-- The tooltip of a list row (extra to the row, which says everything needed to act): the item,
-- then what each plan needs of it and what you hold.
-- more(tip): lines of the strip's own after those (the Auction House's price steps).
local function RowTip(r, more)
	return function(tip)
		tip:SetItemByID(r.itemID)
		tip:AddLine(" ")
		for line, n in pairs(r.lines or {}) do
			local label = line == "queue" and L["Crafting Queue"] or L["%s Leveling Guide"]:format(ns.Tips and ns.Tips.LineName(line) or "")
			tip:AddDoubleLine(label, tostring(n), Color("LABEL"))
		end
		local where, have = nil, nil
		if ns.Pages then where, have = ns.Pages.HaveText(r.itemID) end
		-- DaylightUI's bags (1.8.3) add every character's bags and bank to an item's tooltip when an
		-- alt holds it in theirs, and from 2.1.1 also when only your own bank or the account's holds
		-- some (2.1.1 DaylightUI_Bags\Saved.lua:259-273; 2.0 asked for an alt, :266-271): then only
		-- the mail is said here, which DaylightUI doesn't count.
		local listed = (have and have.altHeld or 0) > 0
			or ((have and have.bank or 0) > 0 and DaylightAtLeast({ 2, 1, 1 }))
		if where and have and listed and DuiListsHoldings() then
			where = have.mail > 0 and L["%d in the mail"]:format(have.mail) or nil
		end
		if where then tip:AddLine(L["You have %s"]:format(where), Color("TEXT")) end
		if more then more(tip) end
	end
end

-- The lines an Auction House row's tooltip adds when the item's price steps are known: the steps
-- buying r.buy of it takes (the first few, then how many more), the average for one, a warning
-- when there aren't that many, and when the prices were read. (As 2.7.0's.)
local STEP_LINES = 4
local function StepLines(r)
	return function(tip)
		local cost, covered, known, used = Calc.AHCost(r.itemID, r.buy)
		if not known then return end
		tip:AddLine(" ")
		for i = 1, math.min(#used, STEP_LINES) do
			tip:AddLine(L["%d at %s each"]:format(used[i].q, Calc.Money(used[i].p)), Color("TEXT"))
		end
		if #used > STEP_LINES then
			local rest = #used - STEP_LINES
			tip:AddLine(Plural(rest, "and %d more step", "and %d more steps"):format(rest), Color("LABEL"))
		end
		if covered > 0 then tip:AddLine(L["Average: %s each"]:format(Calc.Money(cost / covered)), Color("TEXT")) end
		if covered < r.buy then tip:AddLine(L["only %d for sale"]:format(covered), Color("WARN")) end
		local steps = Calc.Steps(r.itemID)
		if steps then tip:AddLine(L["Prices checked %s"]:format(Doc.Ago(steps.at)), Color("LABEL")) end
	end
end

-- An Auction House row's tooltip line for a price seen over a day ago (Calc.Stale), with Check
-- Prices to read it again. After StepLines (which adds nothing then: a stale price has no steps).
local function StaleLine(r, more)
	return function(tip)
		if more then more(tip) end
		local old, age = Calc.Stale(r.itemID)
		if old and ns.Pages then
			tip:AddLine(ns.Pages.StaleText(age), Color("WARN"))
			tip:AddLine(L["Check Prices or browse the Auction House to update it."], Color("TEXT"))
		end
	end
end

local function Visible(f)
	if type(f) ~= "table" or not f.IsVisible or not f:IsVisible() then return false end
	if f.GetEffectiveAlpha and f:GetEffectiveAlpha() < 0.05 then return false end
	local left = f:GetLeft()
	return left ~= nil and left > -200
end

-- The first of the hosts on show: the frame, and its kind ("daylight": a window in Daylight UI's
-- shell, whose border a docked strip shares; "game": the game's own).
local function FirstShown(list)
	for _, h in ipairs(list) do
		local ok, f = pcall(h[1])
		if ok and Visible(f) then return f, h[2] end
	end
end

-- What is remembered, account-wide: which strips' lists are open, the "Not Sold Here" fold, and
-- the list picked (pick: "queue" | "guide", nil before any pick; one for both strips).
local function Saved()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	-- (2.5's panels folded to a tab, kept here: the strips have none.)
	db.shopFolds = nil
	db.shop = type(db.shop) == "table" and db.shop or {}
	return db.shop
end

-- The two lists, in the order of their buttons.
local KINDS = { "queue", "guide" }
local function Other(kind) return kind == "queue" and "guide" or "queue" end

-- The list on show at a place ("vendor" | "auction"): the one remembered (the Guide List before
-- any pick). counts: { queue = n, guide = n }, how many items each lists there; where the
-- remembered one lists none and the other does, the other shows, for this visit only (nothing is
-- saved). settle: the strip is being shown; the answer then holds for the visit, so the list on
-- show never changes by itself under the player (a list bought empty stays, saying so); after that
-- only the player's own pick changes it (SetPick). Without counts: what is settled, else the
-- remembered one.
local function Picked(place, counts, settle)
	local v = visit[place]
	if v.kind then return v.kind end
	local kind = Saved().pick == "queue" and "queue" or "guide"
	if counts and counts[kind] == 0 and counts[Other(kind)] > 0 then kind = Other(kind) end
	if settle then v.kind = kind end
	return kind
end
function Shop.Picked(place) return Picked(place) end

-- The pair at the top of a strip's list: Queue List and Guide List, each with its count, the one
-- on show lit (Doc's line of buttons, the look List has while its list is open).
local function ListName(kind, n)
	return ("%s (%d)"):format(kind == "queue" and L["Queue List"] or L["Guide List"], n)
end

-- (Small chips, for the list's head: 20 tall, 12 wider than their words, 4 apart. The head is three
-- short lines at most where the tags fit one line: the pair, the tags, Check Prices.)
local CHIPS = { height = 20, gap = 4, pad = 12 }

local function PickRow(d, kind, counts, onPick)
	local buttons = {}
	for i, k in ipairs(KINDS) do
		buttons[i] = { text = ListName(k, counts[k]), active = k == kind, onClick = function() onPick(k) end }
	end
	d:Buttons(buttons, nil, CHIPS)
end

-- THE PROFESSION TAGS, under the pair: "All", then one for each profession the list on show has
-- something to buy for (rows' `by`), by name. Only where there are two or more professions. A
-- press on one shows only that profession's items, each with that profession's share; the one
-- picked is lit; a press on it again, or on All, shows everything. The pick is remembered
-- account-wide beside the list's (DaylightRecipesDB.shop.tag: the profession's line) and is the
-- same on both strips; where the list on show has no tag for it, All shows and the pick is kept.
local function ProfName(line)
	local name = ns.Tips and ns.Tips.LineName and ns.Tips.LineName(line)
	return type(name) == "string" and name or tostring(line)
end

-- The professions of a list's rows: { { line, name } } by name.
local function Tags(list)
	local seen, out = {}, {}
	for _, r in ipairs(list) do
		for line in pairs(r.by or {}) do
			if not seen[line] then
				seen[line] = true
				out[#out + 1] = { line = line, name = ProfName(line) }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.line) < tostring(b.line)
	end)
	return out
end

-- The tag in force for those tags: the remembered one where it is among them, else none (All).
local function Tagged(tags)
	if #tags < 2 then return nil end
	local want = Saved().tag
	if want == nil then return nil end
	for _, t in ipairs(tags) do
		if t.line == want then return want end
	end
	return nil
end

local function TagRow(d, tags, tag, onTag)
	if #tags < 2 then return end
	local buttons = { { text = L["All"], min = 32, active = tag == nil, onClick = function() onTag(nil) end } }
	for _, t in ipairs(tags) do
		local line = t.line
		buttons[#buttons + 1] = { text = t.name, min = 32, active = line == tag, onClick = function() onTag(line) end }
	end
	-- (Doc's line of buttons puts one that doesn't fit on a new line: the tags wrap, none is cut.)
	d:Buttons(buttons, nil, CHIPS)
end

-- One quiet line at a list's end: what was left out or removed, and what a press does about it.
-- open: true / false for a line that shows and hides rows (its right word says which), nil for
-- one that only acts.
local function QuietRow(d, text, open, onPress)
	local right
	if open ~= nil then right = open and L["Hide"] or L["Show"] end
	d:Row({ left = text, leftInk = "LABEL", right = right, rightInk = "LABEL",
		onClick = function()
			onPress()
			ns.Pad.Settle()
		end })
end

-- A window's main action in DaylightUI's look (its Accept, Create, Train): a lifted band, green
-- text and two lights circling its edge. Only with a DaylightUI that has it (1.8 on).
local function Main(button)
	if type(API.MainButton) == "function" then pcall(API.MainButton, button, true) end
end

local function Hex(ink)
	return Doc.Hex(Color(ink))
end

-- Whether a frame wears Daylight UI's shell with a border itself: true / false, or nil when that
-- can't be asked. Daylight UI's own windows do (Windows/Frame.lua:295), and so may a game window its
-- Skins module dressed. Style.GetShell is not part of its API (Style.lua:988; its own threat meter
-- asks the same of its host, ThreatMeter.lua:458), so it is read guarded, never called to change
-- anything, and without it the host's kind decides.
local function Shelled(frame)
	local D = _G.DaylightUI
	local style = type(D) == "table" and D.Style
	local get = type(style) == "table" and style.GetShell
	if type(get) ~= "function" then return nil end
	local ok, shell = pcall(get, frame)
	if not ok then return nil end
	if type(shell) ~= "table" then return false end
	return not (type(shell.opts) == "table" and shell.opts.noBorder == true)
end

-- How far a strip tucks into a host in Daylight UI's shell, so the two share one border line, the
-- way Daylight UI's threat meter hangs on its damage meter (DaylightUI_InfoPanel/ThreatMeter.lua:
-- 455-466: moved in by the host's border). The border's thickness is the player's setting, in
-- screen pixels ("general" > borderPx, default 8: DaylightUI/DB.lua:52; read the sanctioned way,
-- API.GetSetting); a screen pixel is 768 / the screen's height at scale 1 (DaylightUI/Pixel.lua:
-- 11-28; GetPhysicalScreenSize: ScreenDocumentation.lua:19). A host without that shell (the game's
-- own windows, undressed) has no such border: docked at its edge with no gap and no overlap.
-- A shell can have a border thickness of its own (Style.lua:994-1003: its opts.borderPx, a number
-- or a function of the general one), and Daylight UI's own docking asks the host for it
-- (Style.BorderPx(h): ThreatMeter.lua:420, 459): asked the same way here, guarded like GetShell
-- (it is not part of the API either), with the general setting as the fallback.
local function Seam(host, kind)
	local shelled = Shelled(host)
	if shelled == nil then shelled = kind == "daylight" end
	if not shelled then return 0 end
	local px
	local D = _G.DaylightUI
	local style = type(D) == "table" and D.Style
	local own = type(style) == "table" and style.BorderPx
	if type(own) == "function" then
		local got, value = pcall(own, host)
		if got and type(value) == "number" then px = value end
	end
	if px == nil then
		local ok, value = pcall(API.GetSetting, "general", "borderPx")
		if ok then px = value end
	end
	if type(px) ~= "number" or px <= 0 then return 0 end
	local height
	if type(GetPhysicalScreenSize) == "function" then
		local _, h = GetPhysicalScreenSize()
		height = h
	end
	if type(height) ~= "number" or height <= 0 then return 0 end
	local scale = host:GetEffectiveScale()
	if type(scale) ~= "number" or scale <= 0 then return 0 end
	return px * 768 / height / scale
end

-- ---------------------------------------------------------------------------------------------
-- A strip: a lead ("3 Needed Here"), a cost, a note that drops first, List, one main button
-- ---------------------------------------------------------------------------------------------

local strips = {}

local function Width(fs)
	if not fs:IsShown() then return 0 end
	local w = fs:GetStringWidth()
	return type(w) == "number" and math.ceil(w) or 0
end

-- Lays the strip's pieces out in the width it has: everything on one row; else without the note
-- (it drops first); else the words above the buttons; else, where the words are wider than the
-- strip (the game's 336-wide vendor window with "You Have ..." in the cost), the cost on a row of
-- its own under the lead, without its "You Have" half if even that is too wide; else each button
-- on a row of its own. Nothing is ever cut: the strip grows down instead. `fit`: the strip is as
-- wide as its pieces (beside a host, where no width is given).
local function Layout(s)
	local lead, cost, note = s.lead, s.cost, s.note
	note:SetShown(s.noteText ~= nil)
	-- (From the whole cost each time: a wider host gets the "You Have" half back.)
	cost:SetText(s.costText or "")
	local lw, cw, nw = Width(lead), Width(cost), s.noteText and Width(note) or 0
	local listW = s.listButton:GetWidth()
	local mainW = s.main:IsShown() and s.main:GetWidth() or 0
	-- (A second button, between List and the main one: Check Prices where Auctionator List is the
	-- main one. Only ever kept on a strip of one row: Show takes it away again otherwise.)
	local secondW = s.second:IsShown() and s.second:GetWidth() or 0
	local buttons = listW + (secondW > 0 and GAP + secondW or 0) + (mainW > 0 and GAP + mainW or 0)
	local words = lw + (cw > 0 and 12 + cw or 0)
	local wide = s.fit and math.huge or (s.wide or 0)
	-- A compact strip (the Auction House's, at its host's bottom right corner): as wide as its
	-- one row needs and never wider than the host. Its note comes along only while the strip
	-- then still ends right of the host's middle (a note that must be seen, s.noteMust: how far
	-- a check of prices is, up to the host's whole width). Where even the row without the note
	-- is wider than the host, it is as wide as the host and laid out like any strip of that
	-- width: nothing is cut for being compact.
	if s.compact then
		local one = EDGE + words + 16 + buttons + GAP
		local all = one + (nw > 0 and 12 + nw or 0)
		local noteRoom = s.noteMust and wide or wide / 2
		wide = (all <= noteRoom and all) or (one <= wide and one) or wide
		s:SetWidth(wide)
	end
	local rows, showNote, stacked, costRow
	showNote = nw > 0
	if s.fit then
		-- (Beside its host: the words above the buttons, as wide as the wider of the two.)
		rows, showNote = 2, false
		s:SetWidth(math.max(EDGE + words + EDGE, GAP + buttons + GAP))
	elseif EDGE + words + (nw > 0 and 12 + nw or 0) + 16 + buttons + GAP <= wide then
		rows = 1   -- (all of it on one row)
	elseif EDGE + words + 16 + buttons + GAP <= wide then
		rows, showNote = 1, false
	else
		if cw > 0 and EDGE + words + EDGE > wide then
			if EDGE + cw + EDGE > wide and s.costShort and s.costShort ~= s.costText then
				cost:SetText(s.costShort)
				cw = Width(cost)
				words = lw + 12 + cw
			end
			costRow = EDGE + words + EDGE > wide
		end
		local first = costRow and lw or words
		showNote = nw > 0 and EDGE + first + 12 + nw + EDGE <= wide
		stacked = GAP + buttons + GAP > wide and mainW > 0
		rows = 1 + (costRow and 1 or 0) + (stacked and 2 or 1)
	end
	note:SetShown(showNote)
	lead:ClearAllPoints()
	cost:ClearAllPoints()
	note:ClearAllPoints()
	s.listButton:ClearAllPoints()
	s.main:ClearAllPoints()
	s.second:ClearAllPoints()
	if rows == 1 then
		lead:SetPoint("LEFT", s, "LEFT", EDGE, 0)
	else
		lead:SetPoint("LEFT", s, "TOPLEFT", EDGE, -14)
	end
	if costRow then
		cost:SetPoint("LEFT", s, "TOPLEFT", EDGE, -42)
	else
		cost:SetPoint("LEFT", lead, "RIGHT", 12, 0)
	end
	note:SetPoint("LEFT", (cw > 0 and not costRow) and cost or lead, "RIGHT", 12, 0)
	-- (Where the second button stands when it shows: left of the main one, List left of it.)
	s.second:SetPoint("RIGHT", s.main, "LEFT", -GAP, 0)
	if rows == 1 then
		s.main:SetPoint("RIGHT", s, "RIGHT", -GAP, 0)
		if secondW > 0 then
			s.listButton:SetPoint("RIGHT", s.second, "LEFT", -GAP, 0)
		elseif mainW > 0 then
			s.listButton:SetPoint("RIGHT", s.main, "LEFT", -GAP, 0)
		else
			s.listButton:SetPoint("RIGHT", s, "RIGHT", -GAP, 0)
		end
	elseif stacked then
		s.main:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -GAP, 4)
		s.listButton:SetPoint("BOTTOMRIGHT", s.main, "TOPRIGHT", 0, 4)
	else
		s.main:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -GAP, 4)
		if mainW > 0 then
			s.listButton:SetPoint("RIGHT", s.main, "LEFT", -GAP, 0)
		else
			s.listButton:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -GAP, 4)
		end
	end
	-- (One row: 32. Else 28 a row: the words, the cost when it has its own, the buttons, and one
	-- more when each button has its own.)
	s:SetHeight(rows == 1 and STRIP_H or (rows * 28))
	s.rows, s.costRow = rows, costRow or false
end

-- Where a strip's list goes and how tall it is. The list is a head that stays put (the pair of
-- lists, the profession tags, Check Prices: `head` tall, 0 for a list without one) over the rows,
-- which scroll only when there are more of them than fit. The list is as tall as its head and
-- all of its rows where there is room for that (sixteen rows at most: LIST_MOST); six rows, or
-- all of fewer, is the least it is given (LIST_ROWS), and what it shows always ends on a whole
-- row (PlaceList cuts at a row's foot). The head never takes from the rows.
-- THE RIGHT CORNER, the same on every window and for every player: the list hangs from the
-- strip's right end, which is the host's bottom right corner, its right edge on the host's.
--   "below": under the strip, while the head and six rows (or all of them) fit above the screen's
--            foot;
--   "right": else beside the host's right edge, its foot level with the host's foot, where the
--            screen has the list's width there;
--   "up":    else upward from the strip's top, over the host's lower RIGHT corner: only ever on
--            the player's own press of List, and List again puts it away.
-- Never left of the host, and never over its lower left: what a player keeps at the bottom left
-- of the screen (the chat) is neither covered by the list nor covers it.
-- Plain sums, so the tests check them:
--   want: the height the rows ask for; below: the room under the strip (nil: not known, taken as
--   enough); right: the room beside the host; up: from the list's foot to the screen's top.
--   (left: the room on the host's left. Not used any more: the list never goes there. Kept in
--   its place so a caller's numbers still mean what they did.)
-- Returns "below" | "right" | "up", and the list's height (head and rows).
function Shop.ListPlace(want, below, right, left, up, head)   -- luacheck: ignore 212
	head = head or 0
	-- (All the rows where there is room for them, LIST_MOST at most; six, or all of fewer, at least.)
	local full = head + math.min(want, 16 + LIST_MOST * ROW_H)
	local least = head + math.min(want, 16 + LIST_ROWS * ROW_H)
	if below == nil or below >= least then return "below", math.min(full, below or full) end
	-- (Beside the host the list stands on the host's foot: never taller than the screen above it.)
	if (right or 0) >= LIST_W then return "right", math.min(full, up or full) end
	-- (Over the host's corner: six rows and a part at most, to cover no more of it than that.)
	return "up", math.min(head + math.min(want, 16 + (LIST_ROWS + 1) * ROW_H), up or math.huge)
end

-- Where the strip itself goes at a host that may leave no room under it (Daylight UI 2.0's
-- Auction House window: 620 tall from 116 down, so 32 are left on a 768-high UI space and fewer
-- when the window is scaled up or dragged down). tall: the strip's height less what it tucks into
-- the host; below: the room under the host; right: the room beside it. Under the host while it
-- fits there; else against the host's right edge at its foot, where a strip's width (the list's,
-- at most) fits; else under it all the same, held on the screen by its clamp, which then lays it
-- over the host's lowest edge. Returns "below" | "side".
function Shop.StripPlace(tall, below, right)
	if below == nil or below >= tall then return "below" end
	if (right or 0) >= LIST_W then return "side" end
	return "below"
end

-- A number a frame answers about its place, or nil (a frame not laid out yet answers nothing).
local function Edge(frame, method)
	local fn = frame and frame[method]
	if type(fn) ~= "function" then return nil end
	local v = fn(frame)
	return type(v) == "number" and v or nil
end

-- The list placed for the room there is (Shop.ListPlace). The strip is at its host's effective
-- scale (Dock), so the host's, the strip's and the list's numbers are in the same units; the
-- screen's are UIParent's, brought to them.
local function PlaceList(s, want, head)
	local list, host = s.list, s.host
	head = head or s.listHead or 0
	local beside = s.fit and s or host      -- (a strip beside its host: the list beside the strip)
	local bottom = Edge(s, "GetBottom")
	local below, right, up
	local scale, ui = s:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if bottom and host and type(scale) == "number" and scale > 0 and type(ui) == "number" then
		local sw, sh = UIParent:GetWidth() * ui / scale, UIParent:GetHeight() * ui / scale
		below = bottom - 4
		-- (Beside the host the list stands on the host's foot; over its corner, on the strip's top.)
		up = sh - (Edge(beside, "GetBottom") or bottom) - 4
		local r = Edge(beside, "GetRight")
		right = r and sw - r or nil
	end
	local mode, h = Shop.ListPlace(want, below, right, nil, up, head)
	-- (Not all of the rows fit: the list ends at the foot of the last row that does, never
	-- through one. Doc keeps where each row ends: marks.)
	if h - head < want then
		local foot
		for _, y in ipairs(s.doc.marks or {}) do
			if y <= h - head then foot = y else break end
		end
		if foot then h = head + foot end
	end
	list:ClearAllPoints()
	if mode == "right" then
		-- (Against the host's right edge, foot to foot.)
		list:SetPoint("BOTTOMLEFT", beside, "BOTTOMRIGHT", 0, 0)
	elseif mode == "up" then
		-- (From the strip's right end upward: over the host's lower right corner.)
		list:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, -Seam(s, "daylight"))
	else
		-- (Flush under the strip's right end, which is the host's bottom right corner, sharing the
		-- strip's bottom border: ours is always Daylight UI's shell.)
		list:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, Seam(s, "daylight"))
	end
	list:SetHeight(h)
	-- (Kept, so the strip's Check places the list again when the strip has moved: its host
	-- dragged, or its place not known yet on the frame it first showed.)
	s.listAt, s.listWant, s.listHead, s.listFrom = mode, want, head, bottom
end

local Level                     -- (below: "The layers of a strip")

-- The list: drawn by s.fill(head, rows): its head, and under it six one-line rows and a part at most.
local function DrawList(s)
	local open = Saved()[s.key] == true and s.fill ~= nil
	s.listButton.SetActive(open)
	if not open then
		s.list:Hide()
		return
	end
	-- The head (s.head: what picks and acts on the list) stays put above the rows (s.doc), which
	-- scroll under it: drawn by s.fill(head, rows). A list with nothing in its head has none.
	local h, d = s.head, s.doc
	h:Begin()
	d:Begin()
	local empty = h.y
	local ok, err = pcall(s.fill, h, d)
	if not ok then
		geterrorhandler()(err)
		d:Line(L["Something went wrong drawing this list."], "small", "BAD")
	end
	-- (The head is a plain area, exactly as tall as what was drawn in it: it never scrolls and
	-- has no thumb. Doc's opts.still.)
	local headH = h.y > empty and h.y or 0
	h:Finish()
	d:Finish()
	h.scroll:SetShown(headH > 0)
	h.scroll:SetHeight(math.max(1, headH))
	d.scroll:ClearAllPoints()
	d.scroll:SetPoint("TOPLEFT", s.list, "TOPLEFT", 0, -headH)
	d.scroll:SetPoint("BOTTOMRIGHT", s.list, "BOTTOMRIGHT", 0, 0)
	PlaceList(s, d.y, headH)
	s.list:Show()
	-- (Rows and chips made just now: every one of them over its window's background. Level.)
	s.leveled = false
	if s.host then Level(s, s.host) end
end

local function ToggleList(s)
	local saved = Saved()
	saved[s.key] = not saved[s.key] or nil
	DrawList(s)
	-- (A controller: the rows just shown are stops now; the cursor stays on List.)
	ns.Pad.Settle(s.listButton)
end

-- B on a controller: the list shut first; then the cursor back to the window the strip hangs on
-- (told to the game again as a second window, which leaves the other one the focus: DaylightUI/
-- Pad.lua:1039-1057, through Guide.lua's guarded Pad).
local function PadBack(s)
	if s.list:IsShown() then
		Saved()[s.key] = nil
		DrawList(s)
		ns.Pad.Settle(s.listButton)
		return
	end
	ns.Pad.Back(s)
end

-- THE LAYERS OF A STRIP. A strip and its list are drawn over the window they hang on and over
-- whatever else is on screen there (the chat, the bars: a strip under a window near the screen's
-- foot lies on them), and inside each of the two every piece is over its background:
--   * One layer up from the host's (a MEDIUM window's strip is HIGH, as 2.5's panels were; a host
--     already in DIALOG or above keeps its layer and the strip takes levels well over it).
--     It used to sit in the host's own layer three levels BEHIND the host, so the host's shadow
--     fell on it: that put it, and its list three more behind, at the very bottom of that layer,
--     under every other frame there, and what it wrote showed through their backgrounds, dim.
--   * Every frame of it is given its level here, by name, each time: the strip, then everything on
--     it one above, then the list above all of that, its head and rows above the list. A window's
--     background is DaylightUI's shell, a child frame it makes one level under the window when the
--     window is dressed (DaylightUI/Style.lua:1019-1021) and its corner caps one ten above (:1085-
--     1087); neither is moved again by DaylightUI when the window's level is, which is why its own
--     code sets them again wherever it re-levels a window (DaylightUI_InfoPanel/ThreatView.lua:139,
--     DaylightUI_Tooltip/Rich/Panel.lua:230-238, Ghost.lua:313-316). So here too: the shell one
--     under its window, the caps over the window's contents, nothing left to how the client
--     carries a level on to a frame's children.
local ABOVE = { BACKGROUND = "HIGH", LOW = "HIGH", MEDIUM = "HIGH", HIGH = "DIALOG" }
local BASE = 10                 -- the strip's level in a layer of its own

-- DaylightUI's shell of a frame (its background and border), or nil. Style.GetShell is not part
-- of its API: read guarded, as Shelled does.
local function ShellOf(frame)
	local D = _G.DaylightUI
	local style = type(D) == "table" and D.Style
	local get = type(style) == "table" and style.GetShell
	if type(get) ~= "function" then return nil end
	local ok, shell = pcall(get, frame)
	return ok and type(shell) == "table" and shell or nil
end

-- Puts a frame at `level` in `strata` with its shell one under it and every frame on it above it
-- (each child one above its parent, its own shell under it, and so on down), its shell's caps
-- over all of those. skip: a child stacked by itself (the strip's list). Returns the highest
-- level used.
local function Stack(frame, level, strata, skip)
	frame:SetFrameStrata(strata)
	frame:SetFrameLevel(level)
	local shell = ShellOf(frame)
	if shell and not shell.SetFrameLevel then shell = nil end
	if shell then
		shell:SetFrameStrata(strata)
		shell:SetFrameLevel(math.max(0, level - 1))
	end
	local top = level
	for _, child in ipairs({ frame:GetChildren() }) do
		if child ~= shell and child ~= skip and type(child) == "table" and child.SetFrameLevel then
			top = math.max(top, Stack(child, level + 1, strata))
		end
	end
	if shell and type(shell.over) == "table" and shell.over.SetFrameLevel then
		top = top + 1
		shell.over:SetFrameStrata(strata)
		shell.over:SetFrameLevel(top)
	end
	return top
end

function Level(s, host)
	local hostStrata = host:GetFrameStrata()
	local strata = ABOVE[hostStrata] or hostStrata
	-- (In the host's own layer, a DIALOG's: well over the host and what is on it.)
	local base = strata == hostStrata and host:GetFrameLevel() + 40 or BASE
	if s.leveled and s.levelBase == base and s.levelStrata == strata then return end
	s.leveled, s.levelBase, s.levelStrata = true, base, strata
	local top = Stack(s, base, strata, s.list)
	-- (The list over the strip and all that is on it: where it opens upward it covers the strip's
	-- top edge and the host's corner, and under the strip it shares the strip's border line.)
	s.listTop = Stack(s.list, top + 2, strata)
end
Shop.Stack = Stack

-- WHEN A STRIP LOOKS AGAIN at its host (its Check). No polling: the host's own calls and scripts
-- say it changed. Daylight UI steps its windows by hand with SetAlpha and SetPoint
-- (DaylightUI/Windows/Feel.lua), drags them with StartMoving / StopMovingOrSizing
-- (Windows/Frame.lua Win.Drag) and scales them with SetScale; the game's panels are placed with SetPoint; a window
-- clicked is raised; Daylight UI's NPC window changes size between pages (OnSizeChanged). Each is
-- hooked once per host; Glowey's Gear's window, which docks against the same edge, the same way.
local BURST = { 0, 0.5, 1, 2, 3 }   -- seconds after a strip shows
local watched = setmetatable({}, { __mode = "k" })

local function Wake()
	for _, s in ipairs(strips) do
		if s:IsShown() and s.Check then s.Check(s) end
	end
end
local waking = false
local function WakeSoon()
	if waking then return end
	waking = true
	C_Timer.After(0, function()
		waking = false
		Wake()
	end)
end

local function WatchHost(f)
	if type(f) ~= "table" or watched[f] then return end
	watched[f] = true
	local hook = rawget(_G, "hooksecurefunc")
	if hook then
		for _, method in ipairs({ "SetPoint", "SetAlpha", "SetScale", "StopMovingOrSizing", "SetFrameStrata",
			"SetFrameLevel", "Raise", "Lower" }) do
			if type(f[method]) == "function" then pcall(hook, f, method, WakeSoon) end
		end
	end
	if type(f.HookScript) == "function" then
		-- (Hidden: looked at at once, so the strip goes with it on the same frame.)
		pcall(f.HookScript, f, "OnHide", Wake)
		for _, script in ipairs({ "OnShow", "OnSizeChanged", "OnMouseDown" }) do
			pcall(f.HookScript, f, script, WakeSoon)
		end
	end
end
Shop.WatchHost = WatchHost
Shop.Wake = Wake

local function NewStrip(name, key)
	local s = CreateFrame("Frame", name, UIParent)
	s.key = key
	s:SetSize(LIST_W, STRIP_H)
	s:SetClampedToScreen(true)
	s:EnableMouse(true)
	s:Hide()
	ns.SkinWindow(s)
	s.lead = Doc.Text(s, "body")
	s.cost = Doc.Text(s, "body")
	s.note = Doc.Text(s, "small")
	for _, fs in ipairs({ s.lead, s.cost, s.note }) do
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
	end
	s.listButton = API.Button(s, L["List"], 24)
	s.listButton.FitWidth(56)
	s.listButton:SetScript("OnClick", function() ToggleList(s) end)
	s.main = API.Button(s, "", 24)
	Main(s.main)
	s.second = API.Button(s, "", 24)
	s.second:Hide()
	-- (What a button is for and how things stand with it, when its strip says so: its tooltip.)
	for _, b in ipairs({ s.main, s.second }) do
		b:HookScript("OnEnter", function(self)
			if type(self.tipFn) ~= "function" then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			pcall(self.tipFn, GameTooltip)
			GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function(self)
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
		end)
	end

	-- The list: a child of the strip, hanging flush under its left end (the corner nearest where
	-- the strip is attached), in its own shell.
	local list = CreateFrame("Frame", nil, s)
	list:SetWidth(LIST_W)
	list:EnableMouse(true)
	-- (Kept on the screen whatever its host does after it is placed, as the strip is.)
	list:SetClampedToScreen(true)
	list:Hide()
	-- (Solid, whatever the window opacity: it opens over the game's window, the chat or the
	-- world, and none of that shows through its rows. The strip's bar follows the opacity.)
	ns.SkinWindow(list, { solid = true })
	s.list = list
	-- Its head (the pair of lists, the profession tags, Check Prices) stays at the top; the rows
	-- scroll under it (DrawList gives the head its height and hangs the rows from its foot).
	s.head = Doc.New(list, { pad = 10, width = LIST_W, still = true })
	s.head.scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	s.head.scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	s.head.scroll:SetHeight(1)
	s.doc = Doc.New(list, { pad = 10, width = LIST_W })
	s.doc.scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
	s.doc.scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)

	-- (The first time a strip shows, on this account: one line saying where its tour is. Guide.lua)
	s:HookScript("OnShow", function() if ns.Guide then ns.Guide.Offer("shop") end end)
	-- Gone with the window it hangs from; drawn in that window's layer, tucked under it. A strip as
	-- wide as its host follows the host's width (Daylight UI's NPC window changes size between its
	-- pages). Looked at when something says the host changed (WatchHost, below: its own calls and
	-- scripts), never on every frame.
	local function Check(self)
		if not self:IsShown() then return end
		local host = self.host
		WatchHost(rawget(_G, "GloweyGearWindow"))
		if not Visible(host) then
			self:Hide()
			-- (The Auction House's two windows can swap while it stays open: s.lost then looks for
			-- the one that is up now.)
			if self.lost then self.lost() end
			return
		end
		-- (s.follow: a host the player can drag and scale. Still for a moment after either, the
		-- strip is docked again for the room there is now. As 2.5.3's panel did, main's Watch;
		-- the moment after is a one-shot timer, Settle.)
		if self.follow then
			local l, t, sc = Edge(host, "GetLeft"), Edge(host, "GetTop"), host:GetEffectiveScale()
			if l ~= self.hostL or t ~= self.hostT or sc ~= self.hostS then
				if self.hostS ~= nil then
					self.moved = GetTime()
					self.Settle(self)
				end
				self.hostL, self.hostT, self.hostS = l, t, sc
			elseif self.moved and GetTime() - self.moved > 0.3 then
				self.moved = nil
				if self.redraw then self.redraw() end
				return
			end
		end
		-- (Tabs that come after the strip showed, Auctionator's made as the window opens, and
		-- Glowey's Gear's window docking beside the host or going: looked for at each of these
		-- looks, a few times in the seconds after the strip shows (Burst), and when Gear's window
		-- shows, hides or moves.)
		if (self.under or self.beside) and self.redraw then
			local gear = self.beside ~= nil and (self.beside() ~= nil) or false
			if (self.compact and self.under and self.under(self)) or gear ~= (self.besideWas == true) then
				self.redraw()
				return
			end
		end
		Level(self, host)
		-- (The open list follows the strip: placed again for the room there is where it stands now.)
		if self.list:IsShown() and self.listWant then
			local bottom = Edge(self, "GetBottom")
			if bottom and (not self.listFrom or math.abs(bottom - self.listFrom) > 0.5) then PlaceList(self, self.listWant) end
		end
		local w = self.widthOf and self.widthOf(host)
		if w and math.abs(w - (self.wide or 0)) > 0.5 then
			self.wide = w
			if self.sized then self:SetWidth(w) end
			Layout(self)
		end
	end
	s.Check = Check
	-- (A drag or a scale: looked at again once it has been still for a moment.)
	s.Settle = function(self)
		if self.settling then return end
		self.settling = true
		local function again()
			self.settling = false
			if not (self:IsShown() and self.moved) then return end
			local left = 0.31 - (GetTime() - self.moved)
			if left > 0.005 then
				self.settling = true
				return C_Timer.After(left, again)
			end
			Check(self)
		end
		C_Timer.After(0.31, again)
	end
	-- (As it shows: its place is not known on that very frame, and the host's tabs and Gear's
	-- window can come a moment later. A few one-shot looks, then nothing until something changes.)
	s:HookScript("OnShow", function(self)
		local shown = (self.shownAt or 0) + 1
		self.shownAt = shown
		for _, t in ipairs(BURST) do
			C_Timer.After(t, function()
				if self.shownAt == shown then Check(self) end
			end)
		end
	end)

	-- A controller (Guide.lua's Pad): the cursor reaches the strip with the triggers (LT / RT) from
	-- the window it hangs on (it never takes the cursor as it shows); X is the main action, Y opens
	-- or shuts the list, A presses a row (or one of the list's two buttons, a profession tag, or
	-- one of its last lines), Menu-right shows the other of the two lists, Menu-left on a row
	-- removes it from the list, B goes back.
	s.padSecond = true
	s.padKeys = {
		{ key = "X", label = function() return s.main.text:GetText() or "" end,
		  when = function() return s.main:IsShown() and not s.main.off end,
		  run = function() s.main:Click() end },
		{ key = "Y", label = L["List"], run = function() ToggleList(s) end },
		-- (Menu-right: the other of the two lists, named with its count. Only a strip with two
		-- lists has it: the vendor's and the Auction House's, s.switch set by Show.)
		{ key = "MENU_RIGHT", label = function() return s.switchName or "" end,
		  when = function() return s.switch ~= nil end,
		  run = function() if s.switch then s.switch() end end },
		-- (Menu-left on a list row that can be removed from its list: what a Shift-click on it
		-- does with a mouse. The kit hands the stop the cursor is on to when and run:
		-- DaylightUI/Pad.lua's entryFor and Pad.Press. Free here: its default, Search, needs a search box.)
		{ key = "MENU_LEFT", label = L["Remove"],
		  when = function(stop) return type(stop) == "table" and type(stop.shift) == "table" end,
		  run = function(stop)
			if type(stop) == "table" and type(stop.shift) == "table" and stop.shift.run then stop.shift.run() end
		  end },
	}
	ns.Pad.Follow(s, function() PadBack(s) end)
	strips[#strips + 1] = s
	return s
end

-- Docks a strip to its host. mode: "below" (flush under it, as wide as it), "corner" (flush under
-- its bottom right corner, their right edges one line, as wide as its one row needs and no wider
-- than the host: Layout's compact), "side" (flush against its right edge, at its foot).
-- The edge is fixed per host: a strip never moves to another side by itself.
local function Dock(s, host, kind, mode, drop, at)
	s.host = host
	WatchHost(host)
	s.fit = mode == "side"
	s.compact = mode == "corner"
	-- (At the host's scale, so its width is the host's own number.)
	s:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
	s.leveled = false
	Level(s, host)
	local seam = Seam(host, kind)
	s:ClearAllPoints()
	s.widthOf, s.sized, s.wide = nil, false, nil
	if mode == "side" and at then
		-- (at: a window docked against the host's right edge already, Glowey's Gear's: the strip
		-- hangs flush under it, their left edges one line. Show.)
		s:SetPoint("TOPLEFT", at, "BOTTOMLEFT", 0, 0)
	elseif mode == "side" then
		s:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", -seam, 0)
	elseif mode == "corner" then
		-- (drop: how far under the host's foot, to stand clear of a tab row hanging there: Show.)
		s:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, seam - (drop or 0))
		-- (The most it may be: Layout gives it the width its row needs, up to this.)
		s.widthOf = function(h) return h:GetWidth() end
		s.wide = s.widthOf(host)
	else
		s:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, seam)
		s:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, seam)
		s.widthOf = function(h) return h:GetWidth() end
		s.wide = s.widthOf(host)
	end
	-- (The list is placed when it is drawn, for the room there is then: PlaceList.)
end

-- Shows a strip. o: lead, cost (text or nil), costInk, note (text or nil), noteInk, main (the
-- button's words, or nil for none), mainOff, onMain, fill(head, rows) (the list: what stays at
-- its top, and the rows that scroll under it); switch() and
-- switchName for a strip with two lists (the other one shown, and its name with its count).
local function Show(s, host, kind, mode, o)
	s.lead:SetText(o.lead)
	s.lead:SetTextColor(Color("VALUE"))
	s.costText, s.costShort = o.cost, o.costShort
	s.cost:SetText(o.cost or "")
	s.cost:SetShown(o.cost ~= nil)
	s.cost:SetTextColor(Color(o.costInk or "VALUE"))
	s.noteText = o.note
	s.note:SetText(o.note or "")
	s.note:SetTextColor(Color(o.noteInk or "OFF"))
	s.main:SetShown(o.main ~= nil)
	if o.main then
		s.main.text:SetText(o.main)
		s.main.FitWidth(96)
		s.main.SetOff(o.mainOff == true)
		s.main:SetScript("OnClick", o.onMain)
	end
	s.main.tipFn = o.mainTip
	-- (o.second = { text, off, onClick, tip }: a second button, kept only where the strip is then
	-- still one row; s.secondGone tells the list it was not, so the list can offer it instead.)
	local second = o.second
	s.second:SetShown(second ~= nil)
	s.second.tipFn = second and second.tip or nil
	if second then
		s.second.text:SetText(second.text)
		s.second.FitWidth(64)
		s.second.SetOff(second.off == true)
		s.second:SetScript("OnClick", second.onClick)
	end
	s.secondGone = false
	s.noteMust = o.noteMust == true
	s.fill = o.fill
	s.switch, s.switchName = o.switch, o.switchName
	Dock(s, host, kind, mode)
	s:Show()
	Layout(s)
	-- (o.under(s): how deep something of the host's hangs under its foot where this compact
	-- strip lies, or nil: the game's Auction House tab row, with Auctionator's tabs on it. Then
	-- beside the host's right edge at its foot where the screen has room for the strip, else
	-- under that row. Measured once laid out, since only then is the strip's left end known.)
	-- That place may be taken: Glowey's Gear docks its Upgrades for Sale window against the same
	-- right edge, tops level (o.beside() gives it while it does). Then the strip hangs under that
	-- window, where there is room for it below; else under the tab row.
	local drop = s.compact and o.under and o.under(s)
	local beside = o.beside and o.beside() or nil
	if drop then
		local room = o.roomRight and o.roomRight()
		if beside and o.roomUnder and o.roomUnder(beside) >= s:GetHeight() then
			Dock(s, host, kind, "side", nil, beside)
		elseif not beside and (room == nil or room >= s:GetWidth()) then
			Dock(s, host, kind, "side")
		else
			Dock(s, host, kind, "corner", drop + Seam(host, kind))
		end
		Layout(s)
	elseif mode == "side" and beside and o.roomUnder and o.roomUnder(beside) >= s:GetHeight() then
		-- (Beside Daylight UI's window for want of room under it: under Gear's there too.)
		Dock(s, host, kind, "side", nil, beside)
		Layout(s)
	end
	s.under, s.beside, s.besideWas = o.under, o.beside, beside ~= nil
	if second and s.rows > 1 then
		s.second:Hide()
		s.secondGone = true
		Layout(s)
	end
	DrawList(s)
end

local function HideStrip(s)
	if s then s:Hide() end
end

-- The strip on show, for the tour (RecipesGuide.lua).
function Shop.TourPart()
	for _, s in ipairs(strips) do
		if s:IsShown() then return s end
	end
end

-- Tries to show a strip a few times: the window it docks to may show a moment after the event.
local function Soon(show)
	local tries = 0
	local function try()
		tries = tries + 1
		if not show() and tries < 6 then C_Timer.After(0.2, try) end
	end
	C_Timer.After(0, try)
end

-- ---------------------------------------------------------------------------------------------
-- "Are you sure?": what's bought, its total cost, Yes / No (Esc is No)
-- ---------------------------------------------------------------------------------------------

local confirm
local function BuildConfirm()
	local f = CreateFrame("Frame", "DaylightRecipesConfirm", UIParent)
	f:SetSize(260, 150)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:Hide()
	-- (Solid, whatever the window opacity: what's under it doesn't show through. Host.Skin: dressed
	-- again after a look change.)
	ns.Host.Skin(f, { bgAlpha = 1 })
	f.title = Doc.Text(f, "head")
	f.title:SetPoint("TOP", f, "TOP", 0, -18)
	f.title:SetText(L["Are you sure?"])
	f.what = Doc.Text(f, "body")
	f.what:SetPoint("TOP", f.title, "BOTTOM", 0, -12)
	f.what:SetWidth(228)
	f.what:SetWordWrap(true)
	f.what:SetJustifyH("CENTER")
	f.cost = Doc.Text(f, "body")
	f.cost:SetPoint("TOP", f.what, "BOTTOM", 0, -8)
	f.yes = API.Button(f, L["Yes"], 26)
	Main(f.yes)
	f.yes:SetWidth(90)
	f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
	f.no = API.Button(f, L["No"], 26)
	f.no:SetWidth(90)
	f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 18)
	f.no:SetScript("OnClick", function() f:Hide() end)
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightRecipesConfirm") end
	-- A controller: the cursor starts on No (the safe answer), B is No. Guide.lua's Pad
	f.padFirst = function() return f.no end
	ns.Pad.Follow(f, function() f:Hide() end)
	return f
end

-- Asks before buying: what (a line of words), total (copper; nil for none: not a purchase),
-- onYes(). Over `owner`'s middle. opts: title (in place of "Are you sure?"), yes (the Yes button's
-- word), warn (the question in the warning ink).
local function Confirm(owner, what, total, onYes, opts)
	confirm = confirm or BuildConfirm()
	local f = confirm
	local money = Money()
	local short = total ~= nil and total > money
	-- (Whose question it is: a vendor closing takes only the vendor's away, not the Unlearn question
	-- WindowMenu.lua asks through here.)
	f.owner = owner
	f.yes.text:SetText(opts and opts.yes or L["Yes"])
	local yesW = math.max(90, math.ceil(f.yes.text:GetStringWidth()) + 24)
	f.yes:SetWidth(yesW)
	-- (Yes ends 6 left of the middle and keeps 16 clear of the edge: a longer word for it widens
	-- the box rather than run out of it.)
	local wide = math.max(260, 2 * yesW + 44)
	f:SetWidth(wide)
	f.what:SetWidth(wide - 32)
	f.title:SetText(opts and opts.title or L["Are you sure?"])
	f.title:SetWidth(wide - 32)
	f.title:SetWordWrap(true)
	f.what:SetText(what)
	-- (Host.Ink: in its role's color again after a look change while the box is up.)
	ns.Host.Ink(f.what, opts and opts.warn and "WARN" or "TEXT")
	if total then
		f.cost:SetText(L["Total Cost: %s"]:format(Calc.Money(total)))
		ns.Host.Ink(f.cost, short and "BAD" or "VALUE")
		f.cost:Show()
	else
		f.cost:SetText("")
		f.cost:Hide()
	end
	ns.Host.Ink(f.title, "VALUE")
	-- (Top 18, the title, 12, the question, 8, the cost, 20 clear above the buttons, 18 under them.)
	local titleExtra = math.max(0, math.ceil(f.title:GetStringHeight()) - 16)
	f:SetHeight((total and 134 or 110) + titleExtra + math.ceil(f.what:GetStringHeight()))
	f.yes.SetOff(short)
	f.yes:SetScript("OnClick", function()
		f:Hide()
		onYes()
	end)
	f:ClearAllPoints()
	if owner and owner:IsVisible() then
		f:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
		f:SetPoint("CENTER", owner, "CENTER", 0, 0)
	else
		f:SetScale(1)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	f:Show()
end
Shop.Confirm = Confirm

-- ---------------------------------------------------------------------------------------------
-- Vendor
-- ---------------------------------------------------------------------------------------------

local vendor

local function VendorHost()
	return FirstShown({
		{ function() return _G.DaylightMogulVendor end, "daylight" },
		-- (API.GetFrame("npc"): Daylight UI's NPC window, DaylightUI/API.md "Fitting in around Daylight UI".)
		{ function() return API.GetFrame and API.GetFrame("npc") end, "daylight" },
		{ function() return _G.MerchantFrame end, "game" },
	})
end

-- Professionally Lost's "Buy for guide" button hangs under the game's vendor window's bottom-left
-- corner, where our strip goes; under Daylight UI's window it sits inside the footer and nothing
-- meets (ProfLost.lua's VendorButtonShown reads it, guarded). There our strip stands flush against
-- the window's right edge at its foot instead.
local function TheirButtonUnder(host)
	local P = ns.ProfLost
	if not P or host ~= _G.MerchantFrame then return false end
	return P.VendorButtonShown()
end

-- Where a material not sold here comes from, in a word or a name.
local function Elsewhere(r)
	-- (Left out by the source filter as cheapest on the Auction House: that is where. Not the
	-- vendor's own share of an item the two share: that comes from a vendor.)
	if r.src == "ah" and r.split ~= "own" then return L["Auction House"] end
	local _, who = Calc.Vendor(r.itemID)
	if who and who ~= "Vendor" and who ~= L["Vendor"] then return who end
	if not who and Calc.AH(r.itemID) then return L["Auction House"] end
	return L["Elsewhere"]
end

-- A purchase the game's own vendor window asks about before it makes it: a slot whose price (a
-- lot's) is MERCHANT_HIGH_PRICE_COST (150g) or more (Blizzard_UIPanels_Game/Mainline/
-- MerchantFrame.lua:672, 701-704: asked in Lua, before BuyMerchantItem, so a direct call skips it).
local function Dear(s)
	return s.unit * s.stack >= (_G.MERCHANT_HIGH_PRICE_COST or 1500000)
end

-- What one of the two lists holds at the open vendor (under a profession tag, or nil for all of
-- it): list (its rows, not removed), gone (the removed ones), here, away and cost (Shop.Offer) of
-- what the source filter lists, hidden (cheaper on the Auction House) and look (no price, not sold
-- here: to look for on the Auction House).
local function AtVendor(kind, shelf, tag)
	local list, gone = Shop.List(kind, tag)
	local shown, hidden, look = Shop.Sift(list, "vendor", shelf)
	local here, away, cost = Shop.Offer(shown, shelf)
	return { list = list, gone = gone, here = here, away = away, cost = cost, hidden = hidden, look = look }
end

-- The strips drawn again after the player changed what they show (a list picked, a tag, an item
-- removed or put back). A Buy All Needed question still up was asked about what showed before:
-- it goes. A run under way goes on with the list, the tag and the numbers of its press (rule 2).
local function Redraw(top)
	if confirm and vendor ~= nil and confirm.owner == vendor then confirm:Hide() end
	if top then
		for _, s in ipairs(strips) do
			if s.switch and s:IsShown() then s.doc:Top() end
		end
	end
	Shop.Vendor()
	Shop.Auction()
	ns.Pad.Settle()
end

-- The player's pick of a list ("queue" | "guide"), from either strip: remembered for both, and on
-- show at once in both.
local function SetPick(kind)
	if kind ~= "queue" and kind ~= "guide" then return end
	Saved().pick = kind
	visit.vendor.kind, visit.auction.kind = kind, kind
	Redraw(true)
end
Shop.Pick = SetPick

-- The player's pick of a profession tag (its line; nil, or the one picked already: All).
local function SetTag(line)
	local saved = Saved()
	if line == saved.tag then line = nil end
	saved.tag = line
	Redraw(true)
end
Shop.Tag = SetTag

-- A row's Shift action (Doc's o.shift): Remove. The item leaves the list it is drawn for, as a
-- whole, whatever tag is picked; nothing is bought. With a controller it is the Menu button on
-- the left (the strip's padKeys).
local function Remover(kind, itemID)
	return { text = L["Remove"], tip = L["Shift-click to remove this from the list."], run = function()
		if Shop.Remove(kind, itemID) then Redraw() end
	end }
end

-- The list's last line when something was removed from it: how many; a press puts them all back.
local function RemovedRow(d, kind, n)
	if n <= 0 then return end
	QuietRow(d, Plural(n, "%d removed from this list: put it back", "%d removed from this list: put them back"):format(n), nil,
		function()
			Shop.PutBack(kind)
			Redraw()
		end)
end

-- A press on a row: that item, bought now (rule 4's Begin works out how many), on one press with
-- no question, unless the game itself would ask about it (Dear). Only the item's number and the
-- list and tag it was drawn for are taken from the row: what was drawn there is not trusted.
-- extra: the row is one the source filter left out and the player asked to see (the share that
-- is cheaper on the Auction House): Begin buys that share, and only while those rows are shown.
local function BuyRow(itemID, kind, tag, extra)
	if run ~= nil then return end
	local token = session
	local s = Shop.Shelf()[itemID]
	if s and Dear(s) then
		-- (For the question's words: the share a press would buy, as Begin will work it out.)
		local shown, hidden = Shop.Sift((Shop.List(kind, tag)), "vendor", { [itemID] = s })
		local here = {}
		for _, h in ipairs((Shop.Offer(extra and hidden or shown, { [itemID] = s }))) do
			if h.itemID == itemID then here[1] = h end
		end
		local p = Shop.Picks(here, Money(), FreeSlots(), StackOf)[1]
		if p then
			Confirm(vendor, L["Buy %d %s?"]:format(p.count, Name(itemID)), p.price,
				function() Begin(token, itemID, kind, tag, extra) end)
			return
		end
	end
	Begin(token, itemID, kind, tag, extra)
end

-- A press on Buy All Needed: asks first, with the total (the "Ask Before Buying All" option; with
-- it off, still asked when one of the purchases is one the game itself would ask about). What it
-- buys is what the strip counts at the press: the list on show, under the tag picked, less what
-- the source filter left out and what was removed.
local function BuyAll(kind, tag)
	if run ~= nil then return end
	local token = session
	-- (Worked out at the press, for the question's words; again at its Yes, by Begin.)
	local here = AtVendor(kind, Shop.Shelf(), tag).here
	local p, o, t = Shop.Picks(here, Money(), FreeSlots(), StackOf)
	if #p == 0 then return end
	local dear = false
	for _, pick in ipairs(p) do
		if Dear(pick.s) then dear = true end
	end
	if ns.Get("askBuyAll") == false and not dear then
		Begin(token, nil, kind, tag)
		return
	end
	local what = Plural(#p, "Buy %d item on your list from this vendor?", "Buy %d items on your list from this vendor?"):format(#p)
	if #o > 0 then what = what .. "\n" .. L["Not bought in full: %d (gold, stock or bag space)."]:format(#o) end
	Confirm(vendor, what, t, function() Begin(token, nil, kind, tag) end, { title = L["Buy All Needed"] })
end

function Shop.Vendor()
	if not merchantOpen then return true end
	local host, hostKind = VendorHost()
	if not host then return false end
	local shelf = Shop.Shelf()
	-- Both lists, whole (no tag): for the pair's counts, and for whether this vendor sells
	-- anything either of them needs, listed, left out by the filter or removed.
	local at, counts, sells = {}, {}, false
	for _, k in ipairs(KINDS) do
		at[k] = AtVendor(k, shelf)
		counts[k] = #at[k].here
		for _, rows in ipairs({ at[k].list, at[k].gone }) do
			for _, r in ipairs(rows) do
				if shelf[r.itemID] then sells = true end
			end
		end
	end
	-- This vendor sells nothing either list needs: nothing of ours shows at all. (Where it sells
	-- only what the filter leaves out or the player removed, the strip stays, counting none, so
	-- its list can say so.)
	if not sells then
		HideStrip(vendor)
		return true
	end
	local kind = Picked("vendor", counts, true)
	local tags = Tags(at[kind].list)
	local tag = Tagged(tags)
	local a = tag ~= nil and AtVendor(kind, shelf, tag) or at[kind]
	local here, away, cost, hidden, look, gone = a.here, a.away, a.cost, a.hidden, a.look, a.gone
	vendor = vendor or NewStrip("DaylightRecipesBuyStrip", "vendor")
	local money = Money()
	local picks, out = Shop.Picks(here, money, FreeSlots(), StackOf)
	local short = cost > money
	-- (Short of gold for some of it: the button says what it will do.)
	local shortOfGold = false
	for _, o in ipairs(out) do
		if o.why == "gold" then shortOfGold = true end
	end
	-- One row of the list: an item this vendor sells. A press buys it (BuyRow works it out anew).
	-- extra: a row the filter left out, shown because the player asked.
	local function HereRow(d, h, extra)
		local r = h.r
		local name, icon = Doc.ItemName(r.itemID, d)
		local left = name .. " x " .. r.buy
		if h.only and not h.soldOut then left = left .. " · " .. L["Only %d Here"]:format(h.only) end
		if r.alert then left = left .. " " .. Hex("LABEL") .. r.alert .. "|r" end
		-- (What a press on this row would buy now.)
		local p = Shop.Picks({ h }, money, nil, nil)[1]
		local right, ink
		if h.soldOut then
			right, ink = L["Sold Out"], "OFF"
		elseif not p then
			right, ink = L["Can't Afford"], "BAD"
		else
			right, ink = L["Buy %d · %s"]:format(p.count, Calc.Money(p.price)), "VALUE"
		end
		local itemID = r.itemID
		d:Row({ icon = icon, dim = p == nil, left = left, right = right, rightInk = ink, tip = RowTip(r),
			shift = Remover(kind, itemID), onClick = p and function() BuyRow(itemID, kind, tag, extra) end or nil })
	end
	-- One the vendor doesn't sell: where it comes from.
	local function AwayRow(d, r)
		local name, icon = Doc.ItemName(r.itemID, d)
		d:Row({ icon = icon, dim = true, left = name .. " x " .. r.buy .. (r.alert and (" " .. r.alert) or ""), leftInk = "OFF",
			right = Elsewhere(r), rightInk = "OFF", tip = RowTip(r), shift = Remover(kind, r.itemID) })
	end
	local v = visit.vendor
	-- (With a tag picked the strip says whose items it counts: the profession's name in the place
	-- of "Needed Here", which is about as long, so the strip is no wider for it.)
	local count = Hex("ACCENT") .. #here .. "|r"
	Show(vendor, host, hostKind, TheirButtonUnder(host) and "side" or "below", {
		lead = tag ~= nil and (count .. " " .. ProfName(tag)) or L["%s Needed Here"]:format(count),
		cost = #here > 0 and (short and L["%s · You Have %s"]:format(Calc.Money(cost), Calc.Money(money)) or Calc.Money(cost)) or nil,
		-- (Without the "You Have" half, for a strip too narrow for both: Layout.)
		costShort = #here > 0 and Calc.Money(cost) or nil,
		costInk = short and "BAD" or "VALUE",
		note = #away > 0 and L["+%d Not Sold Here"]:format(#away) or nil,
		main = (shortOfGold and #picks > 0) and L["Buy What I Can Afford"] or L["Buy All Needed"],
		mainOff = #picks == 0 or run ~= nil,
		onMain = function() BuyAll(kind, tag) end,
		switch = function() SetPick(Other(kind)) end,
		switchName = ListName(Other(kind), counts[Other(kind)]),
		fill = function(head, d)
			PickRow(head, kind, counts, SetPick)
			TagRow(head, tags, tag, SetTag)
			if #here == 0 then d:Line(L["Nothing on this list to buy here."], "small", "OFF") end
			for _, h in ipairs(here) do HereRow(d, h) end
			if #away > 0 then
				local open = Saved().away == true
				QuietRow(d, L["Not Sold Here (%d)"]:format(#away), open, function()
					local saved = Saved()
					saved.away = not saved.away or nil
					Shop.Vendor()
				end)
				if open then
					for _, r in ipairs(away) do AwayRow(d, r) end
				end
			end
			-- What the source filter left out: one quiet line each for what is cheaper on the
			-- Auction House and for what has no price and isn't sold here; shown under it when
			-- asked for, for this visit. One this vendor sells can then be bought from its row
			-- (never by Buy All Needed).
			if #hidden > 0 then
				local n = #hidden
				QuietRow(d, Plural(n, "%d more is cheaper on the Auction House", "%d more are cheaper on the Auction House"):format(n),
					v.reveal == true, function()
						visit.vendor.reveal = not visit.vendor.reveal or nil
						Shop.Vendor()
					end)
				if v.reveal then
					local sold, rest = Shop.Offer(hidden, shelf)
					for _, h in ipairs(sold) do HereRow(d, h, true) end
					for _, r in ipairs(rest) do AwayRow(d, r) end
				end
			end
			if #look > 0 then
				QuietRow(d, L["%d more to look for on the Auction House"]:format(#look), v.look == true, function()
					visit.vendor.look = not visit.vendor.look or nil
					Shop.Vendor()
				end)
				if v.look then
					for _, r in ipairs(look) do AwayRow(d, r) end
				end
			end
			-- What the player removed from this list: the last line; a press puts them back.
			RemovedRow(d, kind, #gone)
		end,
	})
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Auction House
-- ---------------------------------------------------------------------------------------------

local auction
local ahOpen = false

-- Daylight UI 2.0 has an Auction House window of its own, the frame "DaylightUIAuctionHouse"
-- (DaylightUI_AuctionHouse/Window.lua:33, 960 x 620 at :34, opening at the screen's TOPLEFT 16,
-- -116 at :277-282 or where the player dragged it; it wears Daylight UI's shell, so the seam is
-- shared as on its other windows). While it is up the game's AuctionHouseFrame stays shown but
-- parked under a veil at alpha 0 (Window.lua:1-10, :449), which Visible turns down, so Daylight
-- UI's window is the host. The game's frame is the host when it is the one on screen: Daylight
-- UI's Auction House off or swapped away (Window.lua:376-399), or a Daylight UI before 2.0, which
-- has no such frame (the global is nil there). With DaylightMogul loaded Daylight UI builds none of
-- it and Mogul's is first. Told by the frame being there and on screen, not by a version.
-- (Read for 2.5.3 on main, whose Shop.lua has the same host and the same search.)
local function DaylightAH() return _G.DaylightUIAuctionHouse end

-- The tabs hanging under the game's Auction House window: its own (AuctionHouseFrame.Tabs: Buy,
-- Sell, Auctions; Blizzard_AuctionHouseFrame.xml/.lua on the forever branch, anchored LEFT to
-- RIGHT along its foot) and Auctionator's beside them (LibAHTab's, AuctionatorAHTabsContainer.Tabs,
-- as Addon Skins' Auctionator pack reads them). Our corner strip used to lie over the end of
-- that row: Show moves it (o.under).
local function TabsUnder(s)
	local host = s.host
	local sl, st, hb = Edge(s, "GetLeft"), Edge(s, "GetTop"), Edge(host, "GetBottom")
	if not sl or not st or not hb then return nil end
	local ss, hs = s:GetEffectiveScale(), host:GetEffectiveScale()
	local deepest
	local function look(tabs)
		if type(tabs) ~= "table" then return end
		for _, tab in ipairs(tabs) do
			if type(tab) == "table" and type(tab.IsShown) == "function" and tab:IsShown() then
				local r, b = Edge(tab, "GetRight"), Edge(tab, "GetBottom")
				local ts = r and b and tab:GetEffectiveScale()
				-- (Reaching right of the strip's left end, and hanging under the host's foot past
				-- the strip's top.)
				if ts and r * ts > sl * ss + 1 and b * ts < hb * hs - 1 and b * ts < st * ss - 1 then
					local depth = (hb * hs - b * ts) / ss
					if not deepest or depth > deepest then deepest = depth end
				end
			end
		end
	end
	look(host.Tabs)
	local box = _G.AuctionatorAHTabsContainer
	if type(box) == "table" then look(box.Tabs) end
	return deepest
end

-- Glowey's Gear's Upgrades for Sale window while it stands docked against the host's right edge
-- (GloweyGear Window.lua, Place: its TOPLEFT on the host's TOPRIGHT, out by its Blizzard Style
-- frame at most), or nil.
local function GearBeside(host)
	local g = _G.GloweyGearWindow
	if type(g) ~= "table" or type(g.IsVisible) ~= "function" or not g:IsVisible() then return nil end
	local gl, hr = Edge(g, "GetLeft"), Edge(host, "GetRight")
	if not gl or not hr then return nil end
	local gs, hs = g:GetEffectiveScale(), host:GetEffectiveScale()
	if math.abs(gl * gs - hr * hs) > 24 * hs then return nil end
	return g
end

-- The screen's room under a frame, in the host's units (the strip is at the host's scale).
local function RoomUnder(frame, host)
	local b = Edge(frame, "GetBottom")
	if not b then return 0 end
	return b * frame:GetEffectiveScale() / host:GetEffectiveScale()
end

-- The screen's room right of a host, in the host's units (nil: not known yet).
local function RoomRight(host)
	local right = Edge(host, "GetRight")
	local scale, ui = host:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if right and type(scale) == "number" and scale > 0 and type(ui) == "number" then
		return UIParent:GetWidth() * ui / scale - right
	end
end

local function AHHost()
	return FirstShown({
		{ function() return _G.DaylightMogulMain end, "daylight" },
		{ DaylightAH, "daylight" },
		{ function() return _G.AuctionHouseFrame end, "game" },
	})
end

-- A search in Daylight UI 2.0's Auction House window, as if the name were typed in its Buy tab's
-- box and Enter pressed. Daylight UI has no public call for this (nothing about the Auction House
-- in its API.md or API.lua), so this goes through its module's own, internal functions, which a
-- later Daylight UI may rename or change without notice:
--   DaylightUI:GetModule("AuctionHouse") (Core.lua:721) is the module, registered with ns = ns
--     (DaylightUI_AuctionHouse/Module.lua:5-8);
--   ns.Window.ShowTab("buy") is what a click on the Buy tab runs (Window.lua:225-233, :438); the
--     window's shown tab is its frame's .tab (Windows/Frame.lua:217-222; read at Window.lua:255);
--   ns.BuyPage.Submit(text) (BuyPage.lua:542-547) is what Enter in the search box and a click on a
--     recent search run (:1772, :1533): it writes the box and starts the search.
-- Safe from plugin code as read in 2.0: Submit only queues a browse query in Daylight UI's own
-- request line (BuyPage.lua:518-538 > Browse.lua:204-224 > AH.Request, AH.lua:228), which sends it
-- when the game is ready and keeps to the game's limits; the game call at the end,
-- C_AuctionHouse.SendBrowseQuery (Browse.lua:187), is not a protected or click-only one, and
-- Daylight UI itself sends it from its queue, outside any click. Nothing here is bought, bid on or
-- posted. So: only on Daylight UI 2.0 or later, every step type-checked and in pcall; false when
-- any of it isn't as read (the caller then says so in chat). Exactly as main's 2.5.3 does it.
local function SearchDaylight(name)
	if not DaylightAtLeast({ 2, 0, 0 }) then return false end
	local DUI = ns.DUI or _G.DaylightUI   -- (ns.DUI: Host.lua; the global only in the offline tests)
	if type(DUI) ~= "table" or type(DUI.GetModule) ~= "function" then return false end
	local got, mod = pcall(DUI.GetModule, DUI, "AuctionHouse")
	local m = got and type(mod) == "table" and mod.ns
	if type(m) ~= "table" then return false end
	local page, win = m.BuyPage, m.Window
	if type(page) ~= "table" or type(page.Submit) ~= "function" then return false end
	-- (On Sell or My Auctions the search would run unseen: the Buy tab first. Without it the
	-- search still runs and shows when the player picks Buy.)
	if type(win) == "table" and type(win.ShowTab) == "function" and type(win.frame) == "table"
		and win.frame.tab ~= "buy" then
		pcall(win.ShowTab, "buy")
	end
	-- (Submit answers false when it couldn't start, and has then said why on its own page.)
	-- (Daylight UI 2.1.2 gave Submit a second argument, `anywhere` (BuyPage.lua:558-566): without it the
	-- search stays inside the category picked on the Buy page, as the game's own does, and a
	-- material outside that category is not found. Its own link search passes true (Window.lua:371);
	-- 2.0 and 2.1 take one argument and ignore the second.)
	return (pcall(page.Submit, name, true))
end

-- The item searched for in the Auction House window that's up: Daylight UI 2.0's own (searched
-- at once), else the game's (the name put in its search box).
local function SearchFor(itemID)
	local name = Calc.ItemInfo(itemID) or ns.ItemNameOf(itemID)
	if type(name) ~= "string" or name == "" then return false end
	if Visible(DaylightAH()) then
		if SearchDaylight(name) then return true end
		-- (Daylight UI's search couldn't be reached, a later version having changed it: the press
		-- isn't silent, the player is told what to type.)
		ns.Print(L["Couldn't start the search. Type %s in the Auction House's search box."]:format(name))
		return false
	end
	local f = _G.AuctionHouseFrame
	if not Visible(f) or type(f.SearchBar) ~= "table" then return false end
	local box = f.SearchBar.SearchBox
	if type(box) == "table" and box.SetText then
		box:SetText(name)
		box:SetFocus()
		return true
	end
	return false
end

-- The window the strip hangs from went away with the Auction House still open: Daylight UI 2.0's
-- window and the game's can swap in place (the swap icon on Daylight UI's header and the link back
-- on the game's, DaylightUI_AuctionHouse/Window.lua:376-399), and no game event says so. The strip
-- then looks for the one that's up now (once: the strip's own Check calls this as it hides).
local rehosting = false
function Shop.AuctionLost()
	if rehosting or not ahOpen then return end
	rehosting = true
	Soon(Shop.Auction)
	C_Timer.After(1.5, function() rehosting = false end)
end

function Shop.Auction()
	if not ahOpen then return true end
	local host, kind = AHHost()
	if not host then return false end
	-- The two lists, whole (no tag), as the Auction House lists them (Shop.Sift: without what is
	-- cheapest at a vendor): for the pair's counts, and for whether there is anything to say.
	local function At(k, tag)
		local list, gone = Shop.List(k, tag)
		local shown, left = Shop.Sift(list, "auction")
		return { list = list, gone = gone, shown = shown, hidden = left }
	end
	local at, counts, any = {}, {}, false
	for _, k in ipairs(KINDS) do
		at[k] = At(k)
		counts[k] = #at[k].shown
		if #at[k].list + #at[k].gone > 0 then any = true end
	end
	-- Both lists are empty: no strip. (With everything on them cheaper at a vendor, or removed,
	-- the strip stays, counting none, so its list can say so.)
	if not any then
		HideStrip(auction)
		-- (A check of prices has no list left to be for.)
		if ns.Prices and ns.Prices.StopCheck then ns.Prices.StopCheck() end
		return true
	end
	local pick = Picked("auction", counts, true)
	local tags = Tags(at[pick].list)
	local tag = Tagged(tags)
	local a = tag ~= nil and At(pick, tag) or at[pick]
	local list, hidden, gone = a.shown, a.hidden, a.gone
	auction = auction or NewStrip("DaylightRecipesAHStrip", "auction")
	-- Daylight UI 2.0's own window is the host: the strip follows it when it is dragged or scaled
	-- and looks for the other window when the two swap; and it sits under the window only where
	-- it fits there (Shop.StripPlace).
	local daylightAH = host == DaylightAH()
	auction.redraw, auction.lost, auction.follow = Shop.Auction, Shop.AuctionLost, daylightAH
	-- AT THE HOST'S BOTTOM RIGHT CORNER, a compact strip (Dock's "corner"): its right edge on the
	-- window's, flush under it, as wide as its count, cost, List and button need. The same on
	-- every Auction House window and for every player; what sits at the bottom left of the screen
	-- (the chat, for most) is then clear of the strip and of its list, which hangs from the same
	-- corner (Shop.ListPlace). Two cases stand beside the window's right edge at its foot instead
	-- (Dock's "side"): Daylight UI's own window with no room under it (Shop.StripPlace), and the
	-- game's window with Professionally Lost loaded, whose Scan Prices button hangs under that
	-- very corner (its vendor button is met the same way: TheirButtonUnder).
	local mode = "corner"
	if daylightAH then
		local bottom, room = Edge(host, "GetBottom"), RoomRight(host)
		if Shop.StripPlace(STRIP_H - Seam(host, kind), bottom, room) == "side" then mode = "side" end
	elseif host == _G.AuctionHouseFrame and ns.ProfLost and ns.ProfLost.Loaded() then
		mode = "side"
	end
	-- A row's price. A vendor's (a row the player asked to see: the item, or its share, that a
	-- vendor sells for less): the vendor's. On the Auction House, with the item's price steps
	-- known: what r.buy of them cost, step by step (Calc.AHCost), and how many of them are for
	-- sale; else the count times the lowest price, said as "about" (est). (As 2.7.0's rows.)
	local function Priced(r)
		local ah = Calc.AH(r.itemID)
		local vend = Calc.Vendor(r.itemID)
		if vend and (r.split == "other" or r.src == "vendor") then
			return { r = r, right = L["Vendor %s"]:format(Calc.Money(vend * r.buy)), ink = "WARN" }
		end
		local cost, covered, known = Calc.AHCost(r.itemID, r.buy)
		if known then
			if covered <= 0 then return { r = r, right = L["None for sale"], ink = "OFF" } end
			local right, ink = L["AH %s"]:format(Calc.Money(cost)), "GOOD"
			if covered < r.buy then
				right, ink = right .. " · " .. L["only %d for sale"]:format(covered), "WARN"
			end
			return { r = r, right = right, ink = ink, ah = cost, saved = vend and vend * covered - cost or 0 }
		elseif r.src == "ah" and ah then
			-- (A price seen over a day ago, Calc.Stale: "Stale" beside it, in the warning ink.)
			local old = Calc.Stale(r.itemID)
			local right = L["AH about %s"]:format(Calc.Money(ah * r.buy))
			if old then right = right .. " · " .. L["Stale"] end
			return { r = r, right = right, ink = old and "WARN" or "GOOD", ah = ah * r.buy,
				est = true, stale = old or nil, saved = vend and (vend - ah) * r.buy or 0 }
		end
		return { r = r, right = L["No Price"], ink = "OFF" }
	end
	-- What the list costs on the Auction House, and what that saves over a vendor. (about: some
	-- row's cost is an estimate, so the total is one too, and says so.)
	local ahTotal, saved, about, stale = 0, 0, false, 0
	local rows = {}
	for i, r in ipairs(list) do
		rows[i] = Priced(r)
		ahTotal = ahTotal + (rows[i].ah or 0)
		saved = saved + math.max(0, rows[i].saved or 0)
		if rows[i].est then about = true end
		if rows[i].stale then stale = stale + 1 end
	end
	-- "Check Prices" (Prices.Check, as 2.7.0's FitCheck): asks the Auction House for the price
	-- steps of every item listed, one after another; Stop while it runs. Only where prices can be
	-- checked (Prices.CanCheck: not with DaylightMogul's prices, nor with Auction House prices
	-- off). A check started on another list (the other of the pair, another tag, other items) is
	-- stopped: sig is what this one is made of.
	local P = ns.Prices
	local check
	if P and P.CanCheck and P.CanCheck() then
		local sig = { pick, tostring(tag) }
		for _, r in ipairs(a.list) do sig[#sig + 1] = r.itemID end
		table.sort(sig, function(x, y) return tostring(x) < tostring(y) end)
		sig = table.concat(sig, ",")
		if P.Checking() and auction.checkSig ~= sig then P.StopCheck() end
		local done, total = P.Checking()
		local ids, seen, oldest = {}, {}, nil
		for _, r in ipairs(list) do
			if not seen[r.itemID] then
				seen[r.itemID] = true
				ids[#ids + 1] = r.itemID
				local steps = Calc.Steps(r.itemID)
				if steps and (not oldest or steps.at < oldest) then oldest = steps.at end
			end
		end
		check = { word = done and L["Stop"] or L["Check Prices"], off = not done and #ids == 0 }
		if done then
			check.status, check.ink = L["Checking prices: %d of %d"]:format(math.min(done + 1, total), total), "VALUE"
			check.busy = check.status
		elseif oldest then
			check.status, check.ink = L["Prices checked %s"]:format(Doc.Ago(oldest)), "LABEL"
		end
		local stamp = oldest
		check.tip = function(tip)
			tip:SetText(L["Check Prices"])
			tip:AddLine(L["Reads how many are for sale at each price."], Color("TEXT"))
			if stamp then tip:AddLine(L["Prices checked %s"]:format(Doc.Ago(stamp)), Color("LABEL")) end
		end
		check.run = function()
			if P.Checking() then
				P.StopCheck()
			elseif #ids > 0 then
				auction.checkSig = sig
				P.Check(ids, function() Shop.Refresh() end)
			end
			Shop.Auction()
			ns.Pad.Settle()
		end
	end
	-- With Auctionator loaded: the list as one of its shopping lists (its own search does the rest).
	local A = _G.Auctionator
	local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
	local lister = type(api) == "table" and type(api.CreateShoppingList) == "function" and type(api.ConvertToSearchString) == "function"
	-- (Auctionator's Shopping tab is on the game's window, parked while Daylight UI's is up: no
	-- button for a list that could not be opened from here.)
	if daylightAH then lister = false end
	local function Row(d, row)
		local r = row.r
		local name, icon = Doc.ItemName(r.itemID, d)
		local left = name .. " x " .. r.buy
		if r.alert then left = left .. " " .. Hex("LABEL") .. r.alert .. "|r" end
		-- (While the mouse, or a controller's cursor, is on the row its right text says what a
		-- press does: every row here searches. Doc's o.hover; Shift held shows Remove instead.)
		d:Row({ icon = icon, left = left, right = row.right, rightInk = row.ink, tip = RowTip(r, StaleLine(r, StepLines(r))),
			hover = { text = L["Left Click to Search"], ink = "ACCENT" },
			shift = Remover(pick, r.itemID), onClick = function() SearchFor(r.itemID) end })
	end
	-- (With a tag picked the strip says whose items it counts, in the place of "To Buy".)
	local count = Hex("ACCENT") .. #list .. "|r"
	local gameAH = host == _G.AuctionHouseFrame
	Show(auction, host, kind, mode, {
		under = gameAH and TabsUnder or nil,
		roomRight = function() return RoomRight(host) end,
		beside = function() return GearBeside(host) end,
		roomUnder = function(f) return RoomUnder(f, host) end,
		lead = tag ~= nil and (count .. " " .. ProfName(tag)) or L["%s To Buy"]:format(count),
		cost = ahTotal > 0 and (about and L["AH about %s"] or L["AH %s"]):format(Calc.Money(ahTotal)) or nil,
		-- (While a check runs the note says how far it is; it drops first where the strip is narrow.)
		-- (Prices seen over a day ago, Calc.Stale: how many, before what the list saves. Check
		-- Prices reads them again.)
		note = check and check.busy or (stale > 0 and Plural(stale, "%d Stale Price", "%d Stale Prices"):format(stale))
			or (saved > 0 and L["Saves %s"]:format(Calc.Money(saved)))
			or (not Calc.HasAH() and L["No Auction House Prices Yet"] or nil),
		noteInk = (check and check.busy) and "VALUE" or (stale > 0 and "WARN") or (saved > 0 and "GOOD" or "OFF"),
		noteMust = check ~= nil and check.busy ~= nil,
		-- Check Prices / Stop is the strip's, beside List, not a line of the list: the strip's main
		-- button (a controller's X), or, where Auctionator List is the main one (the game's
		-- window with Auctionator), a second button between List and it. How far a check is, is
		-- the strip's note; what the button is for and when prices were last checked, its tooltip.
		main = lister and L["Auctionator List"] or (check and check.word) or nil,
		mainOff = lister and #list == 0 or (not lister and check ~= nil and check.off),
		mainTip = (not lister and check) and check.tip or nil,
		second = (lister and check) and { text = check.word, off = check.off, onClick = check.run, tip = check.tip } or nil,
		onMain = (not lister and check) and check.run or lister and function()
			local searches = {}
			for _, r in ipairs(list) do
				local name = Calc.ItemInfo(r.itemID) or ns.ItemNameOf(r.itemID)
				if name then
					local ok, text = pcall(api.ConvertToSearchString, "Glowey's Recipes",
						{ searchString = name, isExact = true, quantity = r.buy })
					if ok and type(text) == "string" then searches[#searches + 1] = text end
				end
			end
			if #searches == 0 then return end
			local ok = pcall(api.CreateShoppingList, "Glowey's Recipes", "Glowey's Recipes", searches)
			ns.Print(ok and Plural(#searches, "Auctionator list \"Glowey's Recipes\" made: %d item.",
				"Auctionator list \"Glowey's Recipes\" made: %d items."):format(#searches)
				or L["Auctionator didn't take the list."])
		end or nil,
		switch = function() SetPick(Other(pick)) end,
		switchName = ListName(Other(pick), counts[Other(pick)]),
		fill = function(head, d)
			PickRow(head, pick, counts, SetPick)
			TagRow(head, tags, tag, SetTag)
			-- (Check Prices is the strip's button. Only where the strip had no room for it on its
			-- one row beside Auctionator List is it a line of the list's head instead.)
			if check and auction.secondGone then
				head:Row({ left = check.status or "", leftInk = check.ink, right = check.word,
					rightInk = check.off and "OFF" or "ACCENT", tip = check.tip,
					onClick = not check.off and check.run or nil })
			end
			if #rows == 0 then d:Line(L["Nothing on this list to buy here."], "small", "OFF") end
			for _, row in ipairs(rows) do Row(d, row) end
			-- What the source filter left out: one quiet line; shown under it when asked for (a
			-- press still searches, as on any row).
			if #hidden > 0 then
				local n = #hidden
				local open = visit.auction.reveal == true
				QuietRow(d, Plural(n, "%d more is cheaper at a vendor", "%d more are cheaper at a vendor"):format(n), open, function()
					visit.auction.reveal = not visit.auction.reveal or nil
					Shop.Auction()
				end)
				if open then
					for _, r in ipairs(hidden) do Row(d, Priced(r)) end
				end
			end
			-- What the player removed from this list: the last line; a press puts them back.
			RemovedRow(d, pick, #gone)
		end,
	})
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Trainer
-- ---------------------------------------------------------------------------------------------

local trainer
local trainerOpen = false

-- A trainer's service as a recipe: its spell (from the service's tooltip data, else its name).
-- The trainer's names are in the client's language, so the names matched are the game's own for
-- the data's recipes (the English ones only where the game has none). Made once, the first time a
-- name is needed: one name per recipe of the data, a few thousand lookups.
local byName
local function SpellOf(index, name)
	if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
		local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
		if ok and type(data) == "table" and type(data.id) == "number" and ns.Recipes and ns.Recipes[data.id] then
			return data.id
		end
	end
	if not name then return nil end
	if not byName then
		byName = {}
		for spell in pairs(ns.Recipes or {}) do
			local n = ns.SpellName(spell)
			if n then byName[n] = byName[n] or spell end
		end
	end
	return byName[name]
end

local function TrainerHost()
	return FirstShown({
		{ function() return API.GetFrame and API.GetFrame("npc") end, "daylight" },
		{ function() return _G.ClassTrainerFrame end, "game" },
	})
end

-- The trainer's recipes you don't know: { index, spell, name, line, icon, available, cost, req }.
-- Also: the spells of the ones you know already (spell -> true), and every recipe's profession it
-- teaches, known or not, for telling which profession the trainer is for.
local function Services()
	local out, used, lines = {}, {}, {}
	local n = GetNumTrainerServices and GetNumTrainerServices() or 0
	for i = 1, n do
		local name, kind, icon = GetTrainerServiceInfo(i)
		local known = kind == "used"
		if name and known then
			local spell = SpellOf(i, name)
			if spell then
				used[spell] = true
				local data = ns.Recipes and ns.Recipes[spell]
				if data then lines[#lines + 1] = { line = data[1] } end
			end
		elseif name and kind ~= "header" then
			local spell = SpellOf(i, name)
			local data = spell and ns.Recipes and ns.Recipes[spell]
			local _, rank = nil, nil
			if GetTrainerServiceSkillReq then _, rank = GetTrainerServiceSkillReq(i) end
			out[#out + 1] = { index = i, spell = spell, name = name, line = data and data[1] or nil, icon = icon,
				available = kind == "available", cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
				req = rank }
			if data then lines[#lines + 1] = { line = data[1] } end
		end
	end
	return out, used, lines
end

-- A spell you know (learned at this trainer a moment ago, or anywhere).
local function KnowsSpell(spell, used)
	if used[spell] then return true end
	return IsPlayerSpell ~= nil and IsPlayerSpell(spell) == true
end

-- Learns a service, if it's still the one at its place (the list moves up as you learn).
-- (BuyTrainerService(index): the game's own Train button calls it from plain Lua,
-- Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua:876; Daylight UI's the same, Npc/Train.lua:144.)
local function Learn(s)
	local name = GetTrainerServiceInfo(s.index)
	if name ~= s.name then return false end
	BuyTrainerService(s.index)
	return true
end

-- The trainer's profession: the one most of its recipes belong to (in the recipe data), or nil.
local function TrainerLine(list)
	local votes, best, most = {}, nil, 0
	for _, s in ipairs(list) do
		if s.line then
			votes[s.line] = (votes[s.line] or 0) + 1
			if votes[s.line] > most then best, most = s.line, votes[s.line] end
		end
	end
	return best
end

-- THE RULES OF LEARNING, the same shape as the rules of buying (above "The game's side of
-- buying"), each kept in one place:
--   1. ONLY WHAT THE PRESS SHOWED ....... BeginLearn's `allowed`: the recommended services that
--      could be learned at the press, by recipe (or "the next rank"). A run learns those and
--      nothing that becomes available while it runs (a rank learned opens more: another press).
--   2. ONLY AT THE TRAINER OF THE PRESS .. Learning. Every visit has a number (trainerSession: one
--      more on every TRAINER_SHOW and every TRAINER_CLOSED, the events the game's and Daylight
--      UI's trainer windows open and close on: Blizzard_APIDocumentationGenerated/
--      TrainerDocumentation.lua:45, 63; DaylightUI/Npc/Window.lua:697-714). A run carries the
--      number it began in and learns nothing under another.
--   3. ONE RUN AT A TIME ................. BeginLearn. A row's press is a run of one, so it obeys
--      the same rule; the run stays set until one STEP after its last service.
--   4. EACH SERVICE ONCE A VISIT ......... `taught`: what was sent to the trainer this visit is
--      not recommended, shown or sent again until the trainer is opened anew, however late the
--      trainer's own list drops it.
-- Each service is looked at again just before it is learned: still at its place in the trainer's
-- list (Learn), still available, your gold still enough.
local trainerSession = 0
local learnRun
local taught = {}

local function ServiceKey(s) return s.rank and "rank" or s.spell end

-- What to learn at the open trainer: rec (the route's recipes and the next rank this trainer
-- offers, in the order the route uses them; each with .use, .available), the trainer's profession.
-- With the trainer piece handed to Professionally Lost for that profession: the next rank only.
local function Recommended()
	local list, used, lines = Services()
	local line = TrainerLine(lines)
	local c = ns.Store and ns.Store.Char()
	-- Maxed out, a profession you don't have, or one the data doesn't know: nothing to recommend.
	local prof = line and c and type(c.prof) == "table" and c.prof[line]
	if not line or type(prof) ~= "table" or (prof.skill or 0) >= TOP then return {}, line end
	local handed = Handed("trainer", line)
	local plan = c and type(c.plans) == "table" and c.plans[line]
	-- (A plan that rests says nothing true about your skill now: Shop.List.)
	if type(plan) ~= "table" or plan.rested then plan = nil end
	-- Only what the leveling route learns: the rest is no use for leveling.
	local rec = {}
	if plan and type(plan.learn) == "table" and not handed then
		for _, s in ipairs(list) do
			local use = s.spell and plan.learn[s.spell]
			if use and s.line == line and not KnowsSpell(s.spell, used) and not taught[s.spell] then
				s.use = use
				rec[#rec + 1] = s
			end
		end
		table.sort(rec, function(a, b) return (a.use[1] or 0) < (b.use[1] or 0) end)
	end
	-- At your cap: the next rank comes first (the trainer's own step service: the game's trainer
	-- window draws GetTrainerServiceStepIndex()'s service apart from the list the same way,
	-- Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua:462, 830-838). `at`: the cap it lifts.
	-- Ours is the first rank the route trains. With the trainer piece handed off the plan rests
	-- and its rank is the one it knew last, so the cap is the profession's own, as last read: the
	-- strip then offers the next rank at every cap, not only the first.
	local at
	if handed then
		at = (prof.max or 0) > 0 and prof.max or nil
	elseif plan and type(plan.rank) == "table" and (prof.max or 0) <= (plan.rank.at or 0) then
		at = plan.rank.at
	end
	if at and GetTrainerServiceStepIndex and not taught.rank then
		local i = GetTrainerServiceStepIndex()
		if type(i) == "number" and i > 0 then
			local name, kind, icon = GetTrainerServiceInfo(i)
			-- (Offered once the game lets you train it, or once you're at the cap anyway.)
			if name and kind ~= "used" and kind ~= "header" and (kind == "available" or (prof.skill or 0) >= at) then
				local _, req = nil, nil
				if GetTrainerServiceSkillReq then _, req = GetTrainerServiceSkillReq(i) end
				table.insert(rec, 1, { index = i, name = name, icon = icon, available = kind == "available", req = req,
					cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0, use = { at, at }, rank = true })
			end
		end
	end
	return rec, line
end

-- RULE 2, ONLY AT THE TRAINER OF THE PRESS: whether `r` is the run under way, at the trainer
-- visit it began in, with that trainer still open. Asked before every service.
local function Learning(r)
	return r ~= nil and r == learnRun and trainerOpen and r.session == trainerSession
end

-- A trainer opened (open) or closed: another visit; a run of the last one is dead from here on.
local function NewTrainerSession(open)
	trainerSession = trainerSession + 1
	trainerOpen = open
	learnRun = nil
	taught = {}
end

-- The run's next service: the first of its own that can still be learned, the trainer's list read
-- again each time because learning moves its places (the way Daylight UI's own Train All goes
-- about it: Npc/Train.lua:219-232, one every 0.2 s). What your gold doesn't reach is said in chat.
local function LearnStep(r)
	if not Learning(r) then return end
	for _, s in ipairs((Recommended())) do
		local key = ServiceKey(s)
		if key and r.allowed[key] and s.available then
			r.allowed[key] = nil
			if (s.cost or 0) > Money() then
				r.skipped[#r.skipped + 1] = s.name
			elseif Learn(s) then
				taught[key] = true
				C_Timer.After(STEP, function() LearnStep(r) end)
				return
			end
		end
	end
	learnRun = nil
	if #r.skipped > 0 then
		ns.Print(L["Left out: %s."]:format(table.concat(r.skipped, ", ") .. " (" .. L["not enough gold"] .. ")"))
	end
	Shop.Refresh()
end

-- RULES 1 AND 3: begins a run of what is recommended and can be learned now (only: one of them,
-- a row's press), unless one is under way or the trainer is not the one of the press any more.
local function BeginLearn(token, only)
	if learnRun ~= nil or not trainerOpen or token ~= trainerSession then return false end
	local allowed, n = {}, 0
	for _, s in ipairs((Recommended())) do
		local key = ServiceKey(s)
		if key and s.available and (only == nil or only == key) then
			allowed[key] = true
			n = n + 1
		end
	end
	if n == 0 then return false end
	local r = { session = trainerSession, allowed = allowed, skipped = {} }
	learnRun = r
	LearnStep(r)
	Shop.Refresh()
	return true
end

function Shop.Learning() return learnRun ~= nil end

function Shop.Trainer()
	if not trainerOpen then return true end
	if IsTradeskillTrainer and not IsTradeskillTrainer() then return true end
	local host, kind = TrainerHost()
	if not host then return false end
	local rec = Recommended()
	local now, later, cost = 0, 0, 0
	for _, s in ipairs(rec) do
		if s.available then
			now = now + 1
			cost = cost + (s.cost or 0)
		else
			later = later + 1
		end
	end
	-- Nothing to learn here now: nothing of ours shows.
	if now == 0 then
		HideStrip(trainer)
		return true
	end
	trainer = trainer or NewStrip("DaylightRecipesTrainStrip", "trainer")
	local money = Money()
	Show(trainer, host, kind, "below", {
		lead = L["%s Recommended"]:format(Hex("ACCENT") .. now .. "|r"),
		cost = Calc.Money(cost),
		costInk = cost > money and "BAD" or "VALUE",
		note = later > 0 and L["+%d Later"]:format(later) or nil,
		main = L["Learn All Recommended"],
		mainOff = learnRun ~= nil,
		onMain = function() BeginLearn(trainerSession) end,
		fill = function(_, d)
			for _, s in ipairs(rec) do
				local left = s.rank and L["%s · Next Rank"]:format(s.name)
					or L["%s · Skill %d to %d"]:format(s.name, s.use[1] or 0, s.use[2] or 0)
				local right, ink
				if not s.available then
					right, ink = s.req and L["Needs Skill %d"]:format(s.req) or L["Later"], "OFF"
				elseif (s.cost or 0) > money then
					right, ink = Calc.Money(s.cost or 0), "BAD"
				else
					right, ink = L["Learn · %s"]:format(Calc.Money(s.cost or 0)), "GOOD"
				end
				-- (A press takes the service's key only: a run of one, worked out anew.)
				local key = ServiceKey(s)
				d:Row({ icon = s.icon, dim = not s.available, left = left, leftInk = s.available and "VALUE" or "TEXT",
					right = right, rightInk = ink, tip = function(tip) tip:SetTrainerService(s.index) end,
					onClick = (key and s.available and (s.cost or 0) <= money)
						and function() BeginLearn(trainerSession, key) end or nil })
			end
		end,
	})
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

-- Bags, gold, prices, plans or a hand-off changed: the strips up are drawn again (once, a moment
-- later, after the bag snapshot has been read).
local queued = false
function Shop.Refresh()
	if queued then return end
	if not (merchantOpen or ahOpen or trainerOpen) then return end
	queued = true
	C_Timer.After(0.2, function()
		queued = false
		if merchantOpen then Shop.Vendor() end
		if ahOpen then Shop.Auction() end
		if trainerOpen then Shop.Trainer() end
		-- (A controller: a list drawn again has other rows than the cursor was on. The game finds
		-- its stops again and the cursor leaves one that is gone: DaylightUI/Pad.lua:1153-1175,
		-- through Guide.lua's guarded Pad.)
		for _, s in ipairs(strips) do
			if s:IsShown() and s.list:IsShown() then
				ns.Pad.Settle()
				break
			end
		end
	end)
end

-- The question put away, if it is `owner`'s (a strip's): the Unlearn question, asked over the
-- profession window through the same box (WindowMenu.lua), stays up when a vendor closes.
local function HideQuestion(owner)
	if confirm and owner ~= nil and confirm.owner == owner then confirm:Hide() end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "BAG_UPDATE_DELAYED",
	"PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, itemID)
	if event == "GET_ITEM_INFO_RECEIVED" then
		for _, s in ipairs(strips) do
			if s:IsShown() and s.list:IsShown() and s.doc:Waiting(itemID) then Shop.Refresh() return end
		end
		return
	end
	if event == "MERCHANT_SHOW" then
		-- (Another visit, rule 3: also when it comes with no MERCHANT_CLOSED before it.)
		NewSession(true)
		HideQuestion(vendor)
		Soon(Shop.Vendor)
		-- (Professionally Lost puts its own button under the game's vendor window a moment after it
		-- opens: looked for once more, so our strip stands beside it, not on it.)
		if ns.ProfLost and ns.ProfLost.Loaded() then
			C_Timer.After(0.6, function() if merchantOpen then Shop.Vendor() end end)
		end
	elseif event == "MERCHANT_CLOSED" then
		NewSession(false)
		HideStrip(vendor)
		HideQuestion(vendor)
	elseif event == "AUCTION_HOUSE_SHOW" then
		ahOpen = true
		-- (Another visit: the list on show is settled anew, what the filter left out is hidden again.)
		visit.auction = {}
		Soon(Shop.Auction)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen = false
		visit.auction = {}
		HideStrip(auction)
	elseif event == "TRAINER_SHOW" then
		NewTrainerSession(true)
		Soon(Shop.Trainer)
	elseif event == "TRAINER_CLOSED" then
		NewTrainerSession(false)
		HideStrip(trainer)
	elseif event == "TRAINER_UPDATE" then
		if trainerOpen then Soon(Shop.Trainer) end
	else
		Shop.Refresh()
	end
end)
