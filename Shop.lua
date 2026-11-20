-- Small windows where you shop and train, from your plans (the route each profession's Leveling
-- Guide works out, kept per character: Plan.Get saves what it needs and which recipes it learns)
-- and your crafting queue.
-- The buy list is two lists, picked with the two tabs under the panel's title: "Queue List" (what
-- the crafting queue needs) and "Guide List" (what the Leveling Guide plans need, every profession),
-- each tab with how many items it still has to buy. The pick is kept per account
-- (DaylightRecipesDB.shopList, beside the folds) and is the same at vendors and the Auction House;
-- Guide List until one is picked. A window opened while the kept list has nothing to buy and the
-- other has shows the other for that visit, the kept pick unchanged.
-- Each panel lists only what is cheapest where you stand (Calc.Unit's answer): the rest is left
-- out and counted in one quiet line under the list ("3 more are cheaper at a vendor: show them"),
-- which a click shows for that visit and hides again.
-- Under the tabs, when the list shown has items for two professions or more, a row of profession
-- tags: "All" and one for each. A tag shows only that profession's items, each with that
-- profession's share of what's still to buy; the tag again, or "All", shows everything. Kept per
-- account (DaylightRecipesDB.shopTag), the same in both panels; a list without that profession
-- shows All and leaves the kept tag alone. The tab counts stay the whole lists'.
-- Shift held with the mouse on a row turns its right text to "Remove"; Shift-click (a controller:
-- Y) takes the item off the list shown, for this character (c.shopRemoved, beside its plans),
-- until that list stops needing it or needs more than it did. A quiet last line counts the removed
-- and puts them back ("2 removed from this list: put them back").
-- Auction House prices follow what is really for sale when an item's price steps are known
-- (Prices.Steps: read from any search result, and for the whole list by the panel's "Check Prices"
-- button): a row's cost walks the steps cheapest first (Calc.AHCost), says "only 40 for sale" when
-- there are fewer than needed, and its tooltip lists the steps the purchase takes. Without steps
-- the cost is the count times the lowest price, said as "about". Where a vendor sells the item
-- too, only the units cheaper than the vendor are the Auction House's (Calc.Split): the rest is the
-- vendor panel's, counted here in the "cheaper at a vendor" line, so the two panels ask for the
-- whole between them and nothing twice.
-- What you buy comes off the lists at once: at a vendor through the panel (settled against each
-- read of the bags), and on the Auction House, whose purchases come by mail (kept per character
-- until the mailbox is next read). Bought by hand at a vendor, looted, crafted, traded or taken
-- from the bank or mail: with the Store's next read of the bags, half a second after they settle.
--   Vendor:   under the vendor's window, the picked list: every material it still needs that this
--             character doesn't have (in bags, bank or mail; an alt holding some is only mentioned,
--             "[Mira has 12]"). What this vendor sells is a double-click to buy, exactly the
--             number needed ("Buy All Here" for the lot); what a vendor is cheapest for but this
--             one doesn't sell is grayed out, [Not Available]. Left out: what's cheaper on the
--             Auction House, and what has no known price and isn't sold here.
--   Auction House: under its window, the picked list with the Auction House and vendor prices
--             side by side. A click puts the item in the game's search box, or searches for it in
--             DaylightUI 2.0's own Auction House window when that's the one up; with the mouse on
--             a row its right text says so, "Left Click to Search". Left out: what a
--             vendor is cheapest for (vendor-only items too); what has no known price stays.
--   Trainer:  beside a profession trainer, "Recommended": only the recipes your leveling route
--             learns, with the skill range it uses each for ("All Leveling Recipes Known" when
--             there are none left). A click learns one; "Learn all" the lot. Not shown once the
--             profession is at its top skill.
-- Each docks to whichever window is showing: DaylightMogul's, DaylightUI's, or the game's own, and
-- folds away to a small tab on that window's edge (remembered, each on its own).
local _, ns = ...
if not ns.ok then return end
local L, Plural = ns.L, ns.Plural

local API = ns.API
local Doc, Calc = ns.Doc, ns.Calc
local Color = Doc.Color

local Shop = {}
ns.Shop = Shop

local WIDTH = 320
local TOP = 300           -- a profession's top skill
local MAX_H = 440
local HEAD, FOOT = 38, 44

-- ---------------------------------------------------------------------------------------------
-- What your plans need
-- ---------------------------------------------------------------------------------------------

-- Bought and not yet where the Store counts it (its bags, bank and mail snapshots), so the lists
-- drop by what was bought at once and never count it twice.
--
-- At a vendor, through the panel: itemID -> { count, base, at }, in memory. count is what was
-- asked of the vendor and hasn't shown up in the bags yet; base is the bag snapshot's count for
-- the item when that was last looked at. Every bag read (Store's, half a second after the bags
-- settle) takes what arrived since off the count (Shop.BagsRead), so a purchase that lands in two
-- reads, or a read that had nothing to do with it, never puts the items back on the list, and what
-- the bags hold is never counted along with it. A purchase the vendor refused (bags full, a unique
-- item) is given up WAIT seconds after the last one asked for, and the list drawn again.
local bought = {}
local WAIT = 5

-- What the bags hold of an item now: the Store's snapshot, raised to the game's own count
-- (C_Item.GetItemCount: bags only by default, ItemDocumentation.lua:451-467) when that is higher.
-- The snapshot is read half a second after the bags settle; in that half second something bought
-- by hand in the merchant's window is in the bags and not in the snapshot, and a press here would
-- buy it again. Only ever raised: what left the bags is the snapshot's to say.
local function InBags(itemID)
	local c = ns.Store and ns.Store.Char()
	local n = c and type(c.bags) == "table" and c.bags[itemID] or 0
	local get = C_Item and C_Item.GetItemCount
	if type(get) == "function" then
		local ok, live = pcall(get, itemID)
		if ok and type(live) == "number" and live > n then n = live end
	end
	return n
end

-- Store.Count's answer with the bags as they are now (InBags).
local function Have(itemID)
	local have = ns.Store.Count(itemID)
	local live = InBags(itemID)
	if live > (have.bags or 0) then
		have.mine = (have.mine or 0) + live - (have.bags or 0)
		have.bags = live
	end
	return have
end

local function NoteBought(itemID, count)
	if count <= 0 then return end
	local b = bought[itemID]
	if b and GetTime() - b.at <= WAIT then
		b.count = b.count + count
	else
		b = { count = count, base = InBags(itemID) }
		bought[itemID] = b
	end
	b.at = GetTime()
	-- (Still not in the bags by then: back on the list, without waiting for another event.)
	C_Timer.After(WAIT + 0.1, function() Shop.Refresh() end)
end

-- Store.lua, after every read of the bags (bags: itemID -> count, the new snapshot).
function Shop.BagsRead(bags)
	for itemID, b in pairs(bought) do
		local now = type(bags) == "table" and bags[itemID] or 0
		if now > b.base then b.count = b.count - (now - b.base) end
		b.base = now
		if b.count <= 0 then bought[itemID] = nil end
	end
end

-- On the Auction House: what's bought there comes by mail (the game's mail window has the
-- buyer's invoice for it, Blizzard_MailFrame\MailFrame.lua:790-803), and the mailbox is only read
-- while it's open (Store.lua's ReadMail). So what was bought is kept here until then, per
-- character and between sessions (c.ahBought: itemID -> { count, at }): the lists count it as held
-- from the moment the game says the purchase went through. The next read of an open mailbox
-- clears it all: by then every purchase is either in the inbox, which that read counts, or taken
-- out of it and in the bags. Never collected: forgotten after MAIL_DAYS, as long as the game keeps
-- such mail.
local MAIL_DAYS = 30
local mailOpen = false

local function Mailed(make)
	local c = ns.Store and ns.Store.Char()
	if not c then return nil end
	if type(c.ahBought) ~= "table" then
		if not make then return nil end
		c.ahBought = {}
	end
	return c.ahBought
end

function Shop.Mailed(itemID)
	local t = Mailed()
	local e = t and t[itemID]
	if type(e) ~= "table" then return 0 end
	if time() - (tonumber(e.at) or 0) > MAIL_DAYS * 86400 then
		t[itemID] = nil
		return 0
	end
	return tonumber(e.count) or 0
end

-- `count` of an item bought on the Auction House just now.
function Shop.NoteAuction(itemID, count)
	if type(itemID) ~= "number" or type(count) ~= "number" or count <= 0 then return end
	local t = Mailed(true)
	if not t then return end
	local had = Shop.Mailed(itemID)
	t[itemID] = { count = had + count, at = time() }
	-- (And gone from the item's price steps: what's left for sale starts at the next price.)
	if ns.Prices and ns.Prices.Took then ns.Prices.Took(itemID, count) end
	Shop.Refresh()
end

-- Store.lua, after every read of the mailbox.
function Shop.MailRead()
	-- (Only a mailbox that's open: the inbox answers nothing away from one.)
	if not mailOpen then return end
	local t = Mailed()
	if t and next(t) then wipe(t) end
end

-- How many of an item were bought and aren't in the Store's counts yet: at a vendor a moment ago,
-- and on the Auction House since the mailbox was last read (the second answer: that part).
function Shop.Bought(itemID)
	local n = 0
	local b = bought[itemID]
	if b then
		if GetTime() - b.at > WAIT then
			bought[itemID] = nil
		else
			-- (Less what has reached the bags since, read or not: the bags count that themselves.)
			n = math.max(0, b.count - math.max(0, InBags(itemID) - b.base))
		end
	end
	local mailed = Shop.Mailed(itemID)
	return n + mailed, mailed
end

-- Items the player took off a list (Shift-click a row, or a controller's Y): kept per character
-- beside its plans, c.shopRemoved[which][itemID] = what that list needed of it then. The plan and
-- the queue stay as they are. It ends by itself when the list stops needing the item (the step
-- done, the queue entry gone), so a later need shows again, and when the list needs more of it
-- than it did then (a new step or queue entry).
local function RemovedOf(c, which, make)
	local all = c.shopRemoved
	if type(all) ~= "table" then
		if not make then return nil end
		all = {}
		c.shopRemoved = all
	end
	local t = all[which]
	if type(t) ~= "table" then
		if not make then return nil end
		t = {}
		all[which] = t
	end
	return t
end

-- The removals of a list that still stand, given what it needs now (need: itemID -> count).
local function Standing(c, which, need)
	local t = RemovedOf(c, which)
	if not t then return nil end
	for itemID, was in pairs(t) do
		local n = need[itemID]
		if not n or type(was) ~= "number" or n > was then t[itemID] = nil end
	end
	return t
end

-- Every material this character still has to buy:
-- { { itemID, need, have (Store.Count), buy, bought, mailed, lines = { [line] = n },
--     byLine = { [profession] = n } } } most needed first.
-- which: "guide" (only what the Leveling Guide plans need, every profession), "queue" (only what
-- the crafting queue needs), or nothing ("all") for the two together, an item in both counted once.
-- (What you hold is counted against each list by itself: 20 in the bags cover a queue needing 20
-- and a guide needing 20 alike.)
-- lines is for the tooltip ("queue" for the queue's share); byLine is what each profession needs
-- of the item (the plan's line, or the queued recipes' profession), for the profession tags.
-- bought: of what's needed, how many were bought and aren't in the bags or the mailbox's count
-- yet (Shop.Bought); mailed: the Auction House's part of that.
-- Second answer: what the player removed from the list(s) asked for and would be on it otherwise,
-- { { itemID, byLine } }.
function Shop.List(which)
	local c = ns.Store and ns.Store.Char()
	local out, gone = {}, {}
	if not c then return out, gone end
	-- Each list's need by itself, then its removals taken out.
	local parts = {}
	if which ~= "queue" then
		local need, by = {}, {}
		for line, plan in pairs(type(c.plans) == "table" and c.plans or {}) do
			if type(plan) == "table" and type(plan.need) == "table" then
				for itemID, n in pairs(plan.need) do
					if type(n) == "number" and n > 0 then
						need[itemID] = (need[itemID] or 0) + n
						by[itemID] = by[itemID] or {}
						by[itemID][line] = n
					end
				end
			end
		end
		parts[#parts + 1] = { which = "guide", need = need, by = by }
	end
	if ns.Queue and which ~= "guide" then
		local need, by = {}, {}
		for itemID, n in pairs(ns.Queue.Needs()) do
			if type(n) == "number" and n > 0 then need[itemID] = n end
		end
		if ns.Queue.NeedsByLine then
			for line, items in pairs(ns.Queue.NeedsByLine()) do
				for itemID, n in pairs(items) do
					if need[itemID] and n > 0 then
						by[itemID] = by[itemID] or {}
						by[itemID][line] = n
					end
				end
			end
		end
		parts[#parts + 1] = { which = "queue", need = need, by = by }
	end
	-- (A Leveling Guide step queued is in both: with the two together, the larger of the two is
	-- what's needed, not the sum.)
	local need, lines, byLine, taken = {}, {}, {}, {}
	for _, part in ipairs(parts) do
		local removed = Standing(c, part.which, part.need)
		for itemID, n in pairs(part.need) do
			if removed and removed[itemID] then
				taken[itemID] = taken[itemID] or {}
				taken[itemID][#taken[itemID] + 1] = { need = n, by = part.by[itemID] or {} }
			else
				need[itemID] = math.max(need[itemID] or 0, n)
				lines[itemID] = lines[itemID] or {}
				byLine[itemID] = byLine[itemID] or {}
				for line, m in pairs(part.by[itemID] or {}) do
					if part.which == "guide" then lines[itemID][line] = m end
					byLine[itemID][line] = math.max(byLine[itemID][line] or 0, m)
				end
				if part.which == "queue" then lines[itemID].queue = n end
			end
		end
	end
	for itemID, n in pairs(need) do
		local have = Have(itemID)
		-- (What this character lacks: an alt's are only mentioned. Just bought, not in the bag
		-- or mail snapshot yet: taken off already.)
		local pending, mailed = Shop.Bought(itemID)
		local buy = math.max(0, n - have.mine - pending)
		if buy > 0 then
			out[#out + 1] = { itemID = itemID, need = n, have = have, buy = buy, lines = lines[itemID],
				byLine = byLine[itemID], bought = pending, mailed = mailed,
				alert = ns.Pages and ns.Pages.AltAlert(have) }
		end
	end
	table.sort(out, function(a, b)
		if a.buy ~= b.buy then return a.buy > b.buy end
		return a.itemID < b.itemID
	end)
	-- What's removed and would be listed (still short of it, and not on the list through the
	-- other list's need).
	for itemID, list in pairs(taken) do
		if not need[itemID] then
			local most, by = 0, {}
			for _, t in ipairs(list) do
				most = math.max(most, t.need)
				for line, m in pairs(t.by) do by[line] = math.max(by[line] or 0, m) end
			end
			if most - Have(itemID).mine - Shop.Bought(itemID) > 0 then
				gone[#gone + 1] = { itemID = itemID, byLine = by }
			end
		end
	end
	table.sort(gone, function(a, b) return a.itemID < b.itemID end)
	return out, gone
end

-- Takes an item off a list ("queue" or "guide"); need: what that list needs of it now.
function Shop.Remove(which, itemID, need)
	local c = ns.Store and ns.Store.Char()
	if not c or (which ~= "queue" and which ~= "guide") or type(itemID) ~= "number" then return end
	RemovedOf(c, which, true)[itemID] = tonumber(need) or 0
	Shop.Redraw()
end

-- Puts removed items back on a list: the ones in `ids` ({ itemID, ... }), or all of them.
function Shop.Restore(which, ids)
	local c = ns.Store and ns.Store.Char()
	local t = c and RemovedOf(c, which)
	if not t then return end
	if ids then
		for _, itemID in ipairs(ids) do t[itemID] = nil end
	else
		wipe(t)
	end
	Shop.Redraw()
end

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

-- Whether the DaylightUI installed is at least `want` ({ major, minor, patch }), by its .toc
-- version ("2.0", "1.9.6"). When that can't be read, no.
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

-- The tooltip of a buy list row: the item, then what each plan needs of it and what you hold.
-- more(tip): lines of the panel's own after those (the Auction House's price steps).
local function RowTip(r, hint, more)
	return function(tip)
		tip:SetItemByID(r.itemID)
		if hint then tip:AddLine(hint, Color("ACCENT")) end
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
		-- (Bought on the Auction House and not seen in the mailbox yet: counted as held.)
		if (r.mailed or 0) > 0 then
			tip:AddLine(L["Bought on the Auction House, in the mail: %d"]:format(r.mailed), Color("TEXT"))
		end
		if more then more(tip) end
	end
end

-- A buy list row's Shift action (Doc's D:Row): Shift-click takes the item off the list shown.
-- r.need is the whole list's need of it, also for a row showing one profession's share.
local function RemoveAction(which, r)
	return { text = L["Remove"], ink = "WARN", tip = L["Shift-click to remove this from the list."],
		onClick = function() Shop.Remove(which, r.itemID, r.need) end }
end

-- ---------------------------------------------------------------------------------------------
-- A panel: title, a page of rows, a footer with one button
-- ---------------------------------------------------------------------------------------------

local function Visible(f)
	if type(f) ~= "table" or not f.IsVisible or not f:IsVisible() then return false end
	if f.GetEffectiveAlpha and f:GetEffectiveAlpha() < 0.05 then return false end
	local left = f:GetLeft()
	return left ~= nil and left > -200
end

local function FirstShown(list)
	for _, get in ipairs(list) do
		local ok, f = pcall(get)
		if ok and Visible(f) then return f end
	end
end

local function Folds()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	db.shopFolds = type(db.shopFolds) == "table" and db.shopFolds or {}
	return db.shopFolds
end

-- Which of the two buy lists shows: "queue" or "guide". The player's pick is kept per account
-- beside the folds (DaylightRecipesDB.shopList), one for the vendor's and the Auction House's
-- panel; "guide" until there is one.
local OTHER = { queue = "guide", guide = "queue" }
local function Picked()
	Folds()
	return DaylightRecipesDB.shopList == "queue" and "queue" or "guide"
end

-- One visit to a vendor or the Auction House (from its window opening to its closing): the list
-- shown (which) and whether what the source filter leaves out is shown after all (reveal).
local visit = { vendor = {}, auction = {} }

-- The list a panel shows this visit, settled the first time it's drawn: the kept pick, or the
-- other list when the kept one has nothing to buy and the other has (the kept pick stays as it
-- is). It then stays put until the player picks a tab, also when its last item is bought.
local function Which(key, lists)
	local v = visit[key]
	if not v.which then
		local w = Picked()
		if #lists[w] == 0 and #lists[OTHER[w]] > 0 then w = OTHER[w] end
		v.which = w
	end
	return v.which
end

-- The fold tab: DaylightUI's look for a fold (a small bordered tab with a grip), against the
-- panel's outer edge while it's open, against the window's edge while it's folded away.
local function PaintGrip(t, hover)
	local r, g, b
	if hover then r, g, b = API.Accent() else r, g, b = Color("LABEL") end
	for _, bar in ipairs(t.bars) do bar:SetColorTexture(r, g, b, 1) end
end

-- Run every frame by a panel and by its tab, whichever is up. The window it hangs from gone: it
-- goes too (p.lost, when set, then looks for another host: the Auction House's two windows can
-- swap while it stays open). With p.follow, a host that was moved or scaled gets the panel docked
-- again once it has been still for a moment.
local function Watch(p, piece)
	local host = piece.host
	if not Visible(host) then
		piece:Hide()
		if p.lost then p.lost() end
		return
	end
	if not p.follow then return end
	local l, t, s = host:GetLeft(), host:GetTop(), host:GetEffectiveScale()
	if l ~= p.hostL or t ~= p.hostT or s ~= p.hostS then
		p.hostL, p.hostT, p.hostS = l, t, s
		p.moved = GetTime()
	elseif p.moved and GetTime() - p.moved > 0.3 then
		p.moved = nil
		if p.redraw then p.redraw() end
	end
end

local function MakeTab(p)
	local t = CreateFrame("Button", nil, UIParent)
	t:SetFrameStrata("HIGH")
	t:Hide()
	API.Skin(t, { noBevel = true })
	t.bars = {}
	for i = 1, 3 do t.bars[i] = t:CreateTexture(nil, "OVERLAY") end
	PaintGrip(t, false)
	t:SetScript("OnClick", function()
		local folds = Folds()
		if p.tight then
			-- (No room beside the window, Dock: the tab opens the list over it and puts it away
			-- again, remembered apart from the fold.)
			local over = p.key .. "Over"
			if p.folded then
				folds[over], folds[p.key] = true, nil
			else
				folds[over] = nil
			end
		else
			folds[p.key] = not folds[p.key] or nil
		end
		GameTooltip:Hide()
		if p.redraw then p.redraw() end
	end)
	t:SetScript("OnEnter", function(self)
		PaintGrip(self, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText((p.folded and L["Show %s"] or L["Hide %s"]):format(p.label))
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function(self)
		PaintGrip(self, false)
		GameTooltip:Hide()
	end)
	t:SetScript("OnUpdate", function(self) Watch(p, self) end)
	-- A controller: the tab is one more stop the triggers reach (LT / RT), never taking the cursor
	-- as it shows; A folds or opens the panel. Guide.lua's Pad
	t.padSecond = true
	ns.Pad.Follow(t)
	p.tab = t
	return t
end

local function PlaceTab(p, host, folded)
	local t = p.tab or MakeTab(p)
	t.host = host
	t:SetScale(p:GetScale())
	t:ClearAllPoints()
	local anchor = folded and host or p
	local across = p.edge == "below"
	t:SetSize(across and 34 or 14, across and 14 or 34)
	for i, bar in ipairs(t.bars) do
		bar:ClearAllPoints()
		if across then
			bar:SetSize(2, 6)
			bar:SetPoint("CENTER", t, "CENTER", (i - 2) * 4, 0)
		else
			bar:SetSize(6, 2)
			bar:SetPoint("CENTER", t, "CENTER", 0, (2 - i) * 4)
		end
	end
	if across then
		-- (At the window's left corner, out of the way of the middle of its edge.)
		t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 14, 3)
	elseif p.edge == "left" then
		-- (At the top corner of the side it hangs from, like the bottom ones at their left corner.)
		t:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 3, -14)
	else
		t:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -3, -14)
	end
	t:Show()
end

-- A window's main action in DaylightUI's look (its Accept, Create, Train): a lifted band, green
-- text and two lights circling its edge. Only with a DaylightUI that has it (1.8 on).
local function Main(button)
	if type(API.MainButton) == "function" then pcall(API.MainButton, button, true) end
end

-- The two list tabs under a buy list's title, in the look of our window's and pane's tabs (the
-- picked one bright over an accent line). A click picks that list, here and in the other buy list,
-- and keeps the pick. With a controller they're stops like the rows, and LB / RB step through them
-- (the kit's padTabs).
local function PaintListTabs(p)
	for _, b in ipairs(p.tabs) do
		if b.key == p.which then
			b.text:SetTextColor(Color("VALUE"))
			b.line:SetColorTexture(API.Accent())
			b.line:Show()
		else
			b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
			b.line:Hide()
		end
	end
end

local TAB_H, TAB_TOP = 24, 32

local function AddListTabs(p)
	p.tabs = {}
	for i, spec in ipairs({ { "queue", L["Queue List (%d)"] }, { "guide", L["Guide List (%d)"] } }) do
		local b = CreateFrame("Button", nil, p)
		b.key, b.words = spec[1], spec[2]
		b:SetHeight(TAB_H)
		b.text = Doc.Text(b, "body")
		b.text:SetPoint("CENTER", 0, 1)
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 6, 0)
		b.line:SetPoint("BOTTOMRIGHT", -6, 0)
		b:SetScript("OnClick", function() Shop.Pick(b.key) end)
		b:SetScript("OnEnter", function() PaintListTabs(p) end)
		b:SetScript("OnLeave", function() PaintListTabs(p) end)
		p.tabs[i] = b
	end
	p.padTabs = function()
		for i, b in ipairs(p.tabs) do
			if b.key == p.which then return p.tabs, i end
		end
		return p.tabs, nil
	end
end

-- The tabs' words with each list's count, as wide as their words and side by side; in a language
-- or a font where the two don't fit the panel's width, one under the other (never cut off).
-- p.extra: the room they take under the title.
local function FitListTabs(p, which, lists)
	p.which = which
	local a, b = p.tabs[1], p.tabs[2]
	for _, t in ipairs(p.tabs) do
		t.text:SetText(t.words:format(#lists[t.key]))
		t:SetWidth(math.ceil(t.text:GetStringWidth()) + 16)
		t:ClearAllPoints()
	end
	a:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -TAB_TOP)
	if a:GetWidth() + 2 + b:GetWidth() <= WIDTH - 12 then
		b:SetPoint("LEFT", a, "RIGHT", 2, 0)
		p.extra = TAB_H + 2
	else
		b:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -2)
		p.extra = TAB_H * 2 + 4
	end
	PaintListTabs(p)
end

-- The profession tags under the list tabs, in the look of our window's filter words (small; the
-- picked one in the accent over a thin line): "All", then one for each profession with something
-- to buy on the list shown. Only with two professions or more. They run left to right and on to
-- a new row at the panel's edge, never cut off. tags: { { line, name }, ... }; tag: the one picked
-- (nil: All). Adds the room they take to p.extra (after FitListTabs).
local TAG_H = 20

local function PaintTags(p)
	for _, b in ipairs(p.tags or {}) do
		if b:IsShown() then
			if b.key == (p.tag or false) then
				b.text:SetTextColor(API.Accent())
				b.line:SetColorTexture(API.Accent())
				b.line:Show()
			else
				b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
				b.line:Hide()
			end
		end
	end
end

local function TagButton(p, i)
	local b = p.tags[i]
	if b then return b end
	b = CreateFrame("Button", nil, p)
	b:SetHeight(TAG_H)
	b.text = Doc.Text(b, "small")
	b.text:SetPoint("CENTER", 0, 1)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetHeight(1)
	b.line:SetPoint("BOTTOMLEFT", 4, 0)
	b.line:SetPoint("BOTTOMRIGHT", -4, 0)
	b:SetScript("OnClick", function() Shop.Tag(b.key, p.tag) end)
	b:SetScript("OnEnter", function() PaintTags(p) end)
	b:SetScript("OnLeave", function() PaintTags(p) end)
	p.tags[i] = b
	return b
end

local function FitTags(p, tags, tag)
	p.tags = p.tags or {}
	p.tag = tag
	local used = 0
	if #tags >= 2 then
		local x, y = 8, TAB_TOP + p.extra
		local function place(key, text)
			used = used + 1
			local b = TagButton(p, used)
			b.key = key
			b.text:SetText(text)
			local w = math.ceil(b.text:GetStringWidth()) + 14
			b:SetWidth(w)
			if x > 8 and x + w > WIDTH - 8 then
				x, y = 8, y + TAG_H + 2
			end
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y)
			b:Show()
			x = x + w + 2
		end
		place(false, L["All"])
		for _, t in ipairs(tags) do place(t.line, t.name) end
		p.extra = y + TAG_H + 4 - TAB_TOP
	end
	for i = used + 1, #p.tags do p.tags[i]:Hide() end
	PaintTags(p)
end

-- lists: a buy list, with the two list tabs under its title.
local function NewPanel(name, title, key, lists)
	local p = CreateFrame("Frame", name, UIParent)
	p.key, p.label = key, title
	p:SetSize(WIDTH, 200)
	p:SetFrameStrata("HIGH")
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	p:Hide()
	ns.SkinWindow(p)
	-- (The first time each panel shows, on this account: its short tour. RecipesGuide.lua)
	p:HookScript("OnShow", function() if ns.Guide then ns.Guide.Offer("shop-" .. key) end end)
	p.title = Doc.Text(p, "head")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
	p.title:SetText(title)
	p.note = Doc.Text(p, "small", "RIGHT")
	p.note:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -15)
	p.doc = Doc.New(p, { pad = 10, width = WIDTH })
	-- (Under the title, or under the list tabs of a panel that has them: Paint.)
	p.doc.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -HEAD + 6)
	if lists then AddListTabs(p) end
	-- (The Auction House's list: "Check Prices" and what it's doing, under the tabs and tags.)
	if key == "auction" then
		p.check = API.Button(p, "", 22)
		p.check:Hide()
		p.checkNote = Doc.Text(p, "small")
		p.checkNote:SetJustifyH("LEFT")
		p.checkNote:SetWordWrap(true)
		p.checkNote:Hide()
	end
	p.doc.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, FOOT)
	-- (The total sits beside the button, wrapping onto a second line rather than running under it:
	-- FitFoot sizes both.)
	p.total = Doc.Text(p, "small")
	p.total:SetPoint("LEFT", p, "BOTTOMLEFT", 14, 22)
	p.total:SetJustifyH("LEFT")
	p.total:SetWordWrap(true)
	p.total:SetMaxLines(2)
	p.total:SetWidth(WIDTH - 28)
	p.button = API.Button(p, "", 24)
	-- (Buy all here and Learn all are the panel's main action; the auction house's list isn't.)
	if key ~= "auction" then Main(p.button) end
	p.button:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 10)
	p.line = p:CreateTexture(nil, "ARTWORK")
	p.line:SetHeight(1)
	p.line:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, FOOT - 2)
	p.line:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, FOOT - 2)
	p.line:SetColorTexture(1, 1, 1, 0.06)
	-- Gone with the window it hangs from.
	p:SetScript("OnUpdate", function(self) Watch(p, self) end)
	-- A controller (Guide.lua's Pad): the cursor moves over the panel's rows and button once the
	-- triggers (LT / RT) bring it from the window it hangs on (it never takes the cursor as it
	-- shows), A presses, X buys a row's item (its double-click), B folds the panel away.
	p.padSecond = true
	p.padKeys = { { key = "X", label = L["Buy"],
		when = function(at) return type(at) == "table" and type(at.onDouble) == "function" end,
		run = function(at) if type(at) == "table" and at.onDouble then at.onDouble(at) end end },
		-- (Y on a buy list row: its Shift action, Remove. Y is the kit's "more actions" button,
		-- which these rows have no other use for; X buys, A selects, B folds the panel.)
		{ key = "Y", label = L["Remove"],
		when = function(at) return type(at) == "table" and type(at.shift) == "table" end,
		run = function(at)
			if type(at) == "table" and type(at.shift) == "table" then at.shift.onClick() end
		end } }
	ns.Pad.Follow(p, function()
		Folds()[p.key] = true
		if p.redraw then p.redraw() else p:Hide() end
	end)
	return p
end

-- The footer's button fitted to its words (at least `least` wide), and the total beside it given
-- the rest of the footer.
local function FitFoot(p, least)
	p.button.FitWidth(least)
	local room = WIDTH - 28
	if p.button:IsShown() then room = room - p.button:GetWidth() - 10 end
	p.total:SetWidth(math.max(40, room))
end

-- Where a panel with no room on any edge of its host opens, when the player asks for it: over
-- the host's top right corner, this far down, under a DaylightUI window's header and its close
-- button, swap icon and tabs (the header is Win.HEADER = 56 tall and the pages start 57 down:
-- DaylightUI 2.0 Windows\Frame.lua:17, :298-299).
local OVER_TOP = 58

-- Places a panel by its host: under it (side = "below") or beside it, wherever there's room,
-- 6 away from that edge with the tops (beside) or the left edges (under) level. A panel with
-- p.tuck and no room on any edge (DaylightUI 2.0's Auction House window is 960 wide: on a
-- narrower screen, or scaled up, neither side has 320 free) is "tight": Paint then shows only
-- its tab, and a click on that opens it over the window.
local function Dock(p, host, side)
	if p.host ~= host then
		p.host = host
		p:SetParent(UIParent)
	end
	p:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
	local h, w = p:GetHeight(), p:GetWidth()
	p:ClearAllPoints()
	p.tight = false
	local k = host:GetEffectiveScale() / p:GetEffectiveScale()
	local bottom = (host:GetBottom() or 0) * k
	local right = (host:GetRight() or 0) * k
	local left = (host:GetLeft() or 0) * k
	local screenW = UIParent:GetWidth() / p:GetScale()
	if side == "below" and bottom > h + 8 then
		p:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -6)
		p.edge = "below"
	elseif right + w + 8 < screenW then
		p:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0)
		p.edge = "right"
	elseif not p.tuck or left - w - 8 > 0 then
		p:SetPoint("TOPRIGHT", host, "TOPLEFT", -6, 0)
		p.edge = "left"
	else
		p:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -OVER_TOP)
		p.edge = "right"
		p.tight = true
	end
end

-- Draws a panel's rows with fill(doc), sizes it to them, docks it; folded, only its tab shows.
local function Paint(p, host, side, fill)
	local folds = Folds()
	if folds[p.key] == true then
		Dock(p, host, side)
		p:Hide()
		p.folded = true
		PlaceTab(p, host, true)
		return
	end
	local d = p.doc
	d:Begin()
	local ok, err = pcall(fill, d)
	if not ok then
		geterrorhandler()(err)
		d:Line(L["Something went wrong drawing this list."], "small", "BAD")
	end
	d:Finish()
	-- (A panel with nothing in its footer ends under its rows.)
	local foot = p.footless and 10 or FOOT
	-- (And one with list tabs starts its rows under them.)
	local head = HEAD + (p.extra or 0)
	d.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -head + 6)
	d.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, foot)
	p:SetHeight(math.min(MAX_H, head + d.y + foot))
	Dock(p, host, side)
	-- (No room on any edge of the host: only the tab, until the player opens the list over the
	-- window with it. Never over the host's own controls by itself.)
	if p.tight and not folds[p.key .. "Over"] then
		p:Hide()
		p.folded = true
		PlaceTab(p, host, true)
		return
	end
	p.folded = false
	p:Show()
	PlaceTab(p, host, false)
end

-- A panel and its tab put away (its window closed, nothing to show).
function Shop.HidePanel(p)
	if not p then return end
	p:Hide()
	if p.tab then p.tab:Hide() end
end

-- Tries to show a panel a few times: the window it docks to may show a moment after the event.
local function Soon(show)
	local tries = 0
	local function try()
		tries = tries + 1
		if not show() and tries < 6 then C_Timer.After(0.2, try) end
	end
	C_Timer.After(0, try)
end

-- ---------------------------------------------------------------------------------------------
-- The two buy lists and the source filter
-- ---------------------------------------------------------------------------------------------

-- Both lists, as the panels and their tabs' counts want them, and what was removed from each.
local function Lists()
	local lists, gone = {}, {}
	lists.queue, gone.queue = Shop.List("queue")
	lists.guide, gone.guide = Shop.List("guide")
	return lists, gone
end

-- The professions with something to buy on a list: { { line, name }, ... } by name.
local function TagsOf(list)
	local seen, out = {}, {}
	for _, r in ipairs(list) do
		for line, n in pairs(r.byLine or {}) do
			if n > 0 and not seen[line] then
				seen[line] = true
				out[#out + 1] = { line = line, name = ns.Tips and ns.Tips.LineName(line) or tostring(line) }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return tostring(a.line) < tostring(b.line)
	end)
	return out
end

-- The profession tag in use: the one kept (per account, DaylightRecipesDB.shopTag, beside the
-- list pick; one for both buy lists) when the list shown has a tag for it, else none ("All" for
-- now, the kept one unchanged).
local function TagFor(tags)
	Folds()
	local kept = DaylightRecipesDB.shopTag
	if kept == nil or #tags < 2 then return nil end
	for _, t in ipairs(tags) do
		if t.line == kept then return kept end
	end
	return nil
end

-- A list as one profession's tag shows it: only the items that profession needs, each with its
-- share, the lesser of what's still to buy in all and what the profession needs of it. (The rows
-- are views of the list's own: everything else, the whole need too, reads through.)
local function Tagged(list, tag)
	if tag == nil then return list end
	local out = {}
	for _, r in ipairs(list) do
		local n = r.byLine and r.byLine[tag]
		if n and n > 0 then
			out[#out + 1] = setmetatable({ buy = math.min(r.buy, n) }, { __index = r })
		end
	end
	table.sort(out, function(a, b)
		if a.buy ~= b.buy then return a.buy > b.buy end
		return a.itemID < b.itemID
	end)
	return out
end

-- What a buy list panel shows now: the list picked (which), its rows as the tag in use shows
-- them (list), and the removed items the put-back line counts (back: itemIDs, the tag's only
-- under a tag). Sets the panel's tabs and tags. nil when there is nothing at all, bought or
-- removed, on either list: the panel is put away.
local function View(p, key)
	local lists, gone = Lists()
	if #lists.queue == 0 and #lists.guide == 0 and #gone.queue == 0 and #gone.guide == 0 then
		Shop.HidePanel(p)
		return nil
	end
	local which = Which(key, lists)
	FitListTabs(p, which, lists)
	local tags = TagsOf(lists[which])
	local tag = TagFor(tags)
	FitTags(p, tags, tag)
	local back = {}
	for _, g in ipairs(gone[which]) do
		if tag == nil or (g.byLine[tag] or 0) > 0 then back[#back + 1] = g.itemID end
	end
	return { which = which, list = Tagged(lists[which], tag), back = back }
end

-- A list with nothing left to buy says so.
local function NothingToBuy(which)
	return which == "queue" and L["Your crafting queue needs nothing you don't have."]
		or L["Your Leveling Guides need nothing you don't have."]
end

-- Whether an item is listed at the Auction House: not when a vendor is its cheapest source
-- (Calc.Unit: a vendor-only item, a vendor cheaper than the auctions, or one nearly sold out there).
-- One with no price anywhere stays: the Auction House is where to go look.
function Shop.AtAuction(itemID)
	local _, kind = Calc.Unit(itemID)
	return kind ~= "vendor"
end

-- Whether an item is listed at a vendor; `unit` is this vendor's price for one, nil when it
-- doesn't sell it. Listed: what a vendor is the cheapest source of (this one or another: another's
-- shows as [Not Available] with where to go), and what has no known price when it's sold here.
-- Not listed: what the Auction House is cheapest for, unless this vendor's own price, read off its
-- shelf, is no higher. The second answer says why not: "ah" (cheaper there), or "unknown" (no
-- price known and not sold here).
function Shop.AtVendor(itemID, unit)
	local best, kind = Calc.Unit(itemID)
	if kind == "vendor" then return true end
	if kind == "ah" then
		if unit and unit <= best then return true end
		return false, "ah"
	end
	if unit then return true end
	return false, "unknown"
end

-- The quiet line under a list that leaves items out: how many and why (`text`), and a click shows
-- them for this visit; then it offers to hide them again. Nothing is left out without it.
local function LeftOut(d, key, count, text, redraw)
	if count <= 0 then return end
	local v = visit[key]
	d:Gap(4)
	d:Link(v.reveal and L["Hide what isn't cheapest here"] or text, function()
		v.reveal = not v.reveal or nil
		redraw()
		-- (A controller: the game finds the rows that came or went.)
		ns.Pad.Settle()
	end)
end

-- A row showing part of what its item still needs (the Auction House's share, or the vendor's):
-- a view of the list's row with its own buy; everything else reads through.
local function Part(r, n)
	return setmetatable({ buy = n }, { __index = r })
end

-- A list as one of the two places shows it. place: "auction" or "vendor"; reveal: what the source
-- filter leaves out is shown after all; shelf: what this vendor sells (the vendor's panel).
-- With an item's price steps known (Calc.Split) the Auction House's rows ask for the units cheaper
-- than a vendor and the vendor's for the rest, so the two together ask for the whole and nothing
-- twice; an item with a share for the other place is also counted as left out here. Without steps
-- the item is one place's as a whole (Shop.AtAuction, Shop.AtVendor).
-- Answers: rows (listed, then the revealed), out (the items left out, whole or in part), own (how
-- many rows are this place's own, not revealed ones), unknown (left out at a vendor for having no
-- price anywhere).
local function Placed(list, place, reveal, shelf)
	local rows, out, tail, own, unknown = {}, {}, {}, 0, 0
	for _, r in ipairs(list) do
		local atAH, atVendor, known = Calc.Split(r.itemID, r.buy)
		if known then
			local mine, theirs = atAH, atVendor
			if place == "vendor" then mine, theirs = atVendor, atAH end
			if mine > 0 then
				own = own + 1
				rows[#rows + 1] = (reveal or theirs == 0) and r or Part(r, mine)
			end
			if theirs > 0 then
				out[#out + 1] = r
				if mine == 0 then tail[#tail + 1] = r end
			end
		else
			local listed, why
			if place == "vendor" then
				local s = shelf and shelf[r.itemID]
				listed, why = Shop.AtVendor(r.itemID, s and s.unit)
			else
				listed = Shop.AtAuction(r.itemID)
			end
			if listed then
				own = own + 1
				rows[#rows + 1] = r
			else
				out[#out + 1] = r
				tail[#tail + 1] = r
				if why == "unknown" then unknown = unknown + 1 end
			end
		end
	end
	if reveal then
		for _, r in ipairs(tail) do rows[#rows + 1] = r end
	end
	return rows, out, own, unknown
end

-- The lines an Auction House row's tooltip adds when the item's price steps are known: the steps
-- buying r.buy of it takes (the first few, then how many more), the average for one, a warning
-- when there aren't that many, and when the prices were read.
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

-- The Auction House panel's "Check Prices" row, under its tabs and tags: the button (it reads
-- "Stop" while a check runs) and beside it what's going on ("Checking prices: 3 of 12"), when the
-- rows' prices were last checked, or what the button is for. Only where prices can be checked
-- (Prices.CanCheck: not with DaylightMogul's prices, nor with Auction House prices off). rows: the
-- rows shown; sig: what the list is made of now, so a check started on another list is stopped.
-- Adds its room to p.extra (after FitTags).
local function FitCheck(p, rows, sig)
	local P = ns.Prices
	if not (p.check and P and P.CanCheck and P.CanCheck()) then
		if p.check then
			p.check:Hide()
			p.checkNote:Hide()
		end
		return
	end
	-- (The list changed under a check: it stops, cleanly, and says so by going back to its words.)
	if P.Checking() and p.checkSig ~= sig then P.StopCheck() end
	local done, total = P.Checking()
	local ids, seen, oldest = {}, {}, nil
	for _, r in ipairs(rows) do
		if not seen[r.itemID] then
			seen[r.itemID] = true
			ids[#ids + 1] = r.itemID
			local steps = Calc.Steps(r.itemID)
			if steps and (not oldest or steps.at < oldest) then oldest = steps.at end
		end
	end
	local b, note = p.check, p.checkNote
	b.text:SetText(done and L["Stop"] or L["Check Prices"])
	b.FitWidth(90)
	b.SetOff(not done and #ids == 0)
	b:SetScript("OnClick", function()
		if P.Checking() then
			P.StopCheck()
		else
			p.checkSig = sig
			P.Check(ids, function() Shop.Refresh() end)
		end
		Shop.Auction()
	end)
	local y = TAB_TOP + (p.extra or 0) + 2
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -y)
	b:Show()
	if done then
		note:SetText(L["Checking prices: %d of %d"]:format(math.min(done + 1, total), total))
		note:SetTextColor(Color("VALUE"))
	elseif oldest then
		note:SetText(L["Prices checked %s"]:format(Doc.Ago(oldest)))
		note:SetTextColor(Color("LABEL"))
	else
		note:SetText(L["Reads how many are for sale at each price."])
		note:SetTextColor(Color("OFF"))
	end
	note:SetWidth(math.max(60, WIDTH - 10 - b:GetWidth() - 8 - 12))
	note:ClearAllPoints()
	note:SetPoint("TOPLEFT", p, "TOPLEFT", 10 + b:GetWidth() + 8, -y - 3)
	note:Show()
	p.extra = (p.extra or 0) + math.max(22, math.ceil(note:GetStringHeight()) + 6) + 6
end

-- The quiet line at the end of a list with removed items: how many, and a click puts them back.
local function PutBack(d, which, back)
	if #back == 0 then return end
	d:Gap(4)
	d:Link(Plural(#back, "%d removed from this list: put it back", "%d removed from this list: put them back"):format(#back),
		function() Shop.Restore(which, back) end)
end

-- ---------------------------------------------------------------------------------------------
-- Vendor
-- ---------------------------------------------------------------------------------------------

local vendor
local merchantOpen = false

-- What this vendor sells: itemID -> { index, unit, stack, left (nil: no limit), maxStack }.
local function Shelf()
	local out = {}
	local n = GetMerchantNumItems and GetMerchantNumItems() or 0
	for i = 1, n do
		local itemID = GetMerchantItemID and GetMerchantItemID(i)
		if itemID then
			local price, stack, avail, buyable, extended
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

-- How many of an item this vendor will sell you now, and for how much (rounded up to its stacks,
-- what's left on the shelf and your gold).
local function CanBuy(s, want)
	local stacks = math.ceil(want / s.stack)
	if s.left then stacks = math.min(stacks, s.left) end
	local price = s.unit * s.stack
	local money = GetMoney and GetMoney() or 0
	if price > 0 then stacks = math.min(stacks, math.floor(money / price)) end
	return stacks * s.stack, stacks * price, stacks
end

local function BuyOne(s, want)
	local count, _, stacks = CanBuy(s, want)
	if count <= 0 then return 0 end
	if s.stack > 1 then
		-- (Sold in stacks: one stack a call.)
		for _ = 1, stacks do BuyMerchantItem(s.index) end
	else
		local left = count
		local most = math.max(1, s.maxStack or 1)
		while left > 0 do
			local q = math.min(left, most)
			BuyMerchantItem(s.index, q)
			left = left - q
		end
	end
	return count
end

-- What a list still has to buy right now, itemID -> count: asked again at the moment of a press
-- and of its "Yes", so a row drawn before something arrived (bought by hand in the merchant's
-- window, taken from the mail) never buys more than is still short.
local function WantedNow(which)
	local out = {}
	for _, r in ipairs((Shop.List(which))) do out[r.itemID] = r.buy end
	return out
end

-- Where a material not sold here comes from: the vendor that sells it, or only how many more.
local function Elsewhere(r)
	local _, who = Calc.Vendor(r.itemID)
	if who and who ~= "Vendor" and who ~= L["Vendor"] then return L["Buy %d from %s"]:format(r.buy, who) end
	if who then return L["Buy %d elsewhere"]:format(r.buy) end
	if Calc.AH(r.itemID) then return L["Buy %d on the Auction House"]:format(r.buy) end
	return L["Need %d more"]:format(r.buy)
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
	-- (Solid, whatever the window opacity: the list under it doesn't show through.)
	API.Skin(f, { bgAlpha = 1 })
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
	local money = GetMoney and GetMoney() or 0
	local short = total ~= nil and total > money
	f.title:SetText(opts and opts.title or L["Are you sure?"])
	f.title:SetWidth(228)
	f.title:SetWordWrap(true)
	f.what:SetText(what)
	f.what:SetTextColor(Color(opts and opts.warn and "WARN" or "TEXT"))
	if total then
		f.cost:SetText(L["Total Cost: %s"]:format(Calc.Money(total)))
		f.cost:SetTextColor(Color(short and "BAD" or "VALUE"))
		f.cost:Show()
	else
		f.cost:SetText("")
		f.cost:Hide()
	end
	f.title:SetTextColor(Color("VALUE"))
	f.yes.text:SetText(opts and opts.yes or L["Yes"])
	f.yes:SetWidth(math.max(90, math.ceil(f.yes.text:GetStringWidth()) + 24))
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

local function VendorHost()
	return FirstShown({
		function() return _G.DaylightMogulVendor end,
		function() return API.GetFrame and API.GetFrame("npc") end,
		function() return _G.MerchantFrame end,
	})
end

function Shop.Vendor()
	if not merchantOpen then return true end
	local host = VendorHost()
	if not host then return false end
	vendor = vendor or NewPanel("DaylightRecipesBuyList", L["Buy List"], "vendor", true)
	vendor.redraw = Shop.Vendor
	-- Nothing to buy at all, on either list: the window stays out of the way.
	local view = View(vendor, "vendor")
	if not view then return true end
	local which, list, back = view.which, view.list, view.back
	local shelf = Shelf()
	-- What's listed here, and what the source filter leaves out (shown after the rest once the
	-- player asks for it): cheaper on the Auction House, or (unknown) no price known and not here.
	-- (With an item's Auction House steps known, a row here asks only for what isn't cheaper there.)
	local rows, out, _, unknown = Placed(list, "vendor", visit.vendor.reveal, shelf)
	-- here: the listed rows this vendor sells (what "Buy All Here" buys); ready: how many of them
	-- it can sell you now (not sold out, not past your gold), the "N to buy" at the top.
	local here, cost, ready = {}, 0, 0
	Paint(vendor, host, "below", function(d)
		if #list == 0 then
			-- (Everything on it removed: the put-back line says so.)
			if #back == 0 then d:Line(NothingToBuy(which), "small", "OFF") end
		elseif #rows == 0 then
			d:Line(L["Nothing on this list is cheapest here."], "small", "OFF")
		end
		for _, r in ipairs(rows) do
			local name, icon = Doc.ItemName(r.itemID, d)
			local s = shelf[r.itemID]
			-- (What's bought and on its way counts as held, as it does in the number to buy.)
			local sub = L["Need %d · you have %d"]:format(r.need, r.have.mine + (r.bought or 0))
			local shift = RemoveAction(which, r)
			if r.alert then sub = sub .. " · " .. r.alert end
			if s then
				local count, price = CanBuy(s, r.buy)
				local short = count < r.buy
				here[#here + 1] = { s = s, want = r.buy, itemID = r.itemID, price = price }
				cost = cost + price
				if count > 0 then ready = ready + 1 end
				local why = s.left == 0 and L["Sold out"] or L["Can't afford"]
				d:Row({ icon = icon, left = name, right = count > 0 and L["Buy %d for %s"]:format(count, Calc.Money(price)) or why,
					rightInk = count > 0 and "VALUE" or "BAD", sub = short and count > 0 and (sub .. " · " .. L["only %d here"]:format(count)) or sub,
					subInk = "TEXT", tip = RowTip(r, count > 0 and L["Double-click to buy."] or nil), shift = shift,
					onDouble = count > 0 and function()
						-- (Less to buy than this row says: drawn again first, nothing bought.)
						if (WantedNow(which)[r.itemID] or 0) < r.buy then
							Shop.Vendor()
							return
						end
						local itemName = Calc.ItemInfo(r.itemID) or ns.ItemNameOf(r.itemID) or L["it"]
						Confirm(vendor, L["Buy %d %s?"]:format(count, itemName), price, function()
							-- (And again at the Yes: never more than is still short, nor than asked about.)
							local want = math.min(r.buy, WantedNow(which)[r.itemID] or 0)
							if want > 0 then NoteBought(r.itemID, BuyOne(s, want)) end
							Shop.Vendor()
						end)
					end or nil })
			else
				d:Row({ icon = icon, dim = true, left = name, leftInk = "OFF", right = L["[Not Available]"], rightInk = "OFF",
					sub = Elsewhere(r) .. (r.alert and (" · " .. r.alert) or ""), subInk = "OFF",
					tip = RowTip(r), shift = shift })
			end
		end
		LeftOut(d, "vendor", #out, unknown > 0
			and Plural(#out, "%d more to look for on the Auction House: show it", "%d more to look for on the Auction House: show them"):format(#out)
			or Plural(#out, "%d more is cheaper on the Auction House: show it", "%d more are cheaper on the Auction House: show them"):format(#out),
			Shop.Vendor)
		PutBack(d, which, back)
	end)
	vendor.note:SetText(L["%d to buy"]:format(ready))
	vendor.note:SetTextColor(Color("LABEL"))
	vendor.total:SetText(#here > 0 and L["Here: %s"]:format(Calc.Money(cost)) or L["Nothing Available"])
	-- (Rows listed and none of them sold here: the whole list grayed out, the title too.)
	vendor.doc.scroll:SetAlpha((#here > 0 or #rows == 0) and 1 or 0.45)
	vendor.title:SetTextColor(Color(#here > 0 and "VALUE" or "OFF"))
	vendor.total:SetTextColor(Color(#here > 0 and "VALUE" or "OFF"))
	vendor.button.text:SetText(L["Buy All Here"])
	-- (Nothing sold here: the footer says so, no button to press.)
	vendor.button:SetShown(#here > 0)
	FitFoot(vendor, 120)
	local money = GetMoney and GetMoney() or 0
	vendor.button.SetOff(#here == 0 or cost <= 0)
	vendor.button:SetScript("OnClick", function()
		-- (What fits in your gold, in list order: the total asked about is what will be spent.)
		-- (Anything listed short by less than its row says now: drawn again first, nothing bought.)
		local wanted = WantedNow(which)
		for _, h in ipairs(here) do
			if (wanted[h.itemID] or 0) < h.want then
				Shop.Vendor()
				return
			end
		end
		local picks, total, left = {}, 0, money
		for _, h in ipairs(here) do
			if h.price > 0 and h.price <= left then
				left = left - h.price
				total = total + h.price
				picks[#picks + 1] = h
			end
		end
		if #picks == 0 then return end
		Confirm(vendor, Plural(#picks, "Buy all %d item on your list sold here?", "Buy all %d items on your list sold here?"):format(#picks), total, function()
			-- (Your gold drops only when the server answers: the picks were sized to it above.)
			local still = WantedNow(which)
			for _, h in ipairs(picks) do
				local want = math.min(h.want, still[h.itemID] or 0)
				if want > 0 then NoteBought(h.itemID, BuyOne(h.s, want)) end
			end
			Shop.Vendor()
		end)
	end)
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Auction House
-- ---------------------------------------------------------------------------------------------

local auction
local ahOpen = false

-- The window the list hangs from went away with the Auction House still open: DaylightUI 2.0's
-- window and the game's can swap in place (the swap icon on DaylightUI's header and the link back
-- on the game's, DaylightUI_AuctionHouse\Window.lua:376-399; another addon taking the game's
-- frame, :365-374), and no game event says so. The list then looks for the one that's up now.
local rehosting = false

-- DaylightUI 2.0 has an Auction House window of its own, the frame "DaylightUIAuctionHouse"
-- (DaylightUI_AuctionHouse\Window.lua:33, made by Win.New at :430, 960 x 620 at :34, opening at
-- the screen's TOPLEFT 16, -116 at :277-282 or where the player dragged it; nothing of it hangs
-- outside that frame: its tabs are in its header, Windows\Frame.lua:239-256). While it is up the
-- game's AuctionHouseFrame stays shown but parked under a veil at alpha 0 (Window.lua:1-10, :449;
-- Windows\Follow.lua:38-43, :110-121), which Visible turns down, so DaylightUI's window is the host.
-- The game's frame is the host when it is the one on screen: DaylightUI's Auction House off or
-- swapped away (Window.lua:376-399), an Auction House opened in a fight (:409-412), or a
-- DaylightUI before 2.0, which has no such frame (not in the v1.9.6 tag: the global is nil there).
-- With DaylightMogul loaded DaylightUI builds none of it (Module.lua:17-22) and Mogul's is first.
-- Told by the frame being there, not by a version.
local function DaylightAH() return _G.DaylightUIAuctionHouse end

local function AHHost()
	return FirstShown({
		function() return _G.DaylightMogulMain end,
		DaylightAH,
		function() return _G.AuctionHouseFrame end,
	})
end

-- A search in DaylightUI 2.0's Auction House window, as if the name were typed in its Buy tab's
-- box and Enter pressed. DaylightUI has no public call for this (nothing about the Auction House
-- in its API.md or API.lua), so this goes through its module's own, internal functions, which a
-- later DaylightUI may rename or change without notice:
--   DaylightUI:GetModule("AuctionHouse") (Core.lua:721) is the module, registered with ns = ns
--     (DaylightUI_AuctionHouse\Module.lua:5-8);
--   ns.Window.ShowTab("buy") is what a click on the Buy tab runs (Window.lua:225-233, :438); the
--     window's shown tab is its frame's .tab (Windows\Frame.lua:217-222; read at Window.lua:255);
--   ns.BuyPage.Submit(text) (BuyPage.lua:542-547) is what Enter in the search box and a click on a
--     recent search run (:1772, :1533): it writes the box and starts the search.
-- Safe from plugin code as read in 2.0: Submit only queues a browse query in DaylightUI's own
-- request line (BuyPage.lua:518-538 > Browse.lua:204-224 > AH.Request, AH.lua:228), which sends it
-- when the game is ready and keeps to the game's limits; the game call at the end,
-- C_AuctionHouse.SendBrowseQuery (Browse.lua:187), is not a protected or click-only one (no
-- HasRestrictions on it in the game's AuctionHouseDocumentation.lua, unlike PlaceBid, PostItem or
-- StartCommoditiesPurchase), and DaylightUI itself sends it from its queue, outside any click.
-- Nothing here is bought, bid on or posted. So: only on DaylightUI 2.0 or later, every step
-- type-checked and in pcall; false when any of it isn't as read (the caller then says so in chat).
local function SearchDaylight(name)
	if not DaylightAtLeast({ 2, 0, 0 }) then return false end
	local DUI = _G.DaylightUI
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
	return (pcall(page.Submit, name))
end

-- The item searched for in the Auction House window that's up: DaylightUI 2.0's own (searched
-- at once), else the game's (the name put in its search box).
local function SearchFor(itemID)
	local name = Calc.ItemInfo(itemID) or ns.ItemNameOf(itemID)
	if type(name) ~= "string" or name == "" then return false end
	if Visible(DaylightAH()) then
		if SearchDaylight(name) then return true end
		-- (DaylightUI's search couldn't be reached, a later version having changed it: the click
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

function Shop.Auction()
	if not ahOpen then return true end
	local host = AHHost()
	if not host then return false end
	auction = auction or NewPanel("DaylightRecipesAHList", L["Buy List"], "auction", true)
	auction.redraw = Shop.Auction
	auction.lost = Shop.AuctionLost
	-- (DaylightUI's window can be dragged and scaled, Window.lua:446-447: the list follows it. And
	-- it is wide: with no room on any edge the list tucks away to its tab rather than cover it.)
	local daylight = host == DaylightAH()
	auction.follow, auction.tuck = daylight, daylight
	local view = View(auction, "auction")
	if not view then
		if ns.Prices and ns.Prices.StopCheck then ns.Prices.StopCheck() end
		return true
	end
	local which, list, back = view.which, view.list, view.back
	-- What's listed here, and what the source filter leaves out (shown after the rest once the
	-- player asks for it): everything a vendor is the cheapest source of, and with an item's
	-- price steps known, the part of it a vendor sells for less.
	-- (own, the "N to buy" at the top: the Auction House's own, not what a vendor is cheapest for.)
	local rows, out, own = Placed(list, "auction", visit.auction.reveal)
	do
		local sig = { which, tostring(auction.tag) }
		for _, r in ipairs(list) do sig[#sig + 1] = r.itemID end
		table.sort(sig, function(a, b) return tostring(a) < tostring(b) end)
		FitCheck(auction, rows, table.concat(sig, ","))
	end
	-- (about: some row's cost is the count times the lowest price, its steps not read.)
	local ahTotal, saved, about = 0, 0, false
	Paint(auction, host, "below", function(d)
		if #list == 0 then
			if #back == 0 then d:Line(NothingToBuy(which), "small", "OFF") end
		elseif #rows == 0 then
			d:Line(L["Nothing on this list is cheapest here."], "small", "OFF")
		end
		for _, r in ipairs(rows) do
			local name, icon = Doc.ItemName(r.itemID, d)
			local ah = Calc.AH(r.itemID)
			local vend, who = Calc.Vendor(r.itemID)
			-- With the price steps known: what r.buy of them cost, step by step, and how many of
			-- them are for sale. Else the count times the lowest price, said as "about".
			local cost, covered, known = Calc.AHCost(r.itemID, r.buy)
			local right, ink
			local parts = { L["Buy %d"]:format(r.buy) }
			local subInk = "TEXT"
			if r.alert then parts[#parts + 1] = r.alert end
			if known then
				local low = covered > 0 and cost / covered or nil
				if not low then
					right, ink = vend and L["Vendor only"] or L["None for sale"], "OFF"
				elseif vend and low >= vend then
					right, ink = L["Vendor is cheaper"], "WARN"
				else
					right, ink = vend and L["AH is cheaper"] or L["Auction House"], vend and "GOOD" or "VALUE"
					ahTotal = ahTotal + cost
					if vend then saved = saved + math.max(0, vend * covered - cost) end
				end
				if low then parts[#parts + 1] = L["AH %s"]:format(Calc.Money(cost)) end
				if covered < r.buy then
					parts[#parts + 1] = L["only %d for sale"]:format(covered)
					subInk = "WARN"
				end
			elseif ah and vend then
				if ah < vend then
					right, ink = L["AH is cheaper"], "GOOD"
					ahTotal = ahTotal + ah * r.buy
					saved = saved + (vend - ah) * r.buy
					about = true
				else
					right, ink = L["Vendor is cheaper"], "WARN"
				end
			elseif ah then
				right, ink = L["Auction House"], "VALUE"
				ahTotal = ahTotal + ah * r.buy
				about = true
			elseif vend then
				right, ink = L["Vendor only"], "OFF"
			else
				right, ink = L["No price"], "OFF"
			end
			if not known and ah then parts[#parts + 1] = L["AH about %s"]:format(Calc.Money(ah * r.buy)) end
			if vend then parts[#parts + 1] = L["Vendor %s (%s)"]:format(Calc.Money(vend * r.buy), who or L["vendor"]) end
			d:Row({ icon = icon, left = name, right = right, rightInk = ink,
				sub = table.concat(parts, " · "), subInk = subInk, tip = RowTip(r, nil, StepLines(r)),
				shift = RemoveAction(which, r),
				-- (With the mouse on the row its right text says what the click does; Shift: Remove.)
				hint = { text = L["Left Click to Search"], ink = "ACCENT" },
				onClick = function() SearchFor(r.itemID) end })
		end
		if not Calc.HasAH() then
			d:Line(L["No Auction House prices yet: scan from the Leveling Guide."], "tiny", "OFF")
		end
		LeftOut(d, "auction", #out,
			Plural(#out, "%d more is cheaper at a vendor: show it", "%d more are cheaper at a vendor: show them"):format(#out),
			Shop.Auction)
		PutBack(d, which, back)
	end)
	auction.note:SetText(L["%d to buy"]:format(own))
	auction.note:SetTextColor(Color("LABEL"))
	if ahTotal > 0 then
		-- (Any row's cost an estimate: so is the total, and it says so.)
		auction.total:SetText(about and L["On the AH: about %s"]:format(Calc.Money(ahTotal))
			or saved > 0 and L["On the AH: %s (saves %s)"]:format(Calc.Money(ahTotal), Calc.Money(saved))
			or L["On the AH: %s"]:format(Calc.Money(ahTotal)))
		auction.total:SetTextColor(Color("VALUE"))
	else
		auction.total:SetText(L["Nothing here is cheaper on the AH."])
		auction.total:SetTextColor(Color("OFF"))
	end
	-- With Auctionator loaded: the list as one of its shopping lists (its own search does the rest).
	local A = _G.Auctionator
	local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
	if type(api) == "table" and type(api.CreateShoppingList) == "function" and type(api.ConvertToSearchString) == "function" then
		auction.button.text:SetText(L["Auctionator List"])
		-- (The rows listed: nothing listed, nothing to make a list of.)
		auction.button.SetOff(#rows == 0)
		auction.button:Show()
		auction.button:SetScript("OnClick", function()
			local searches = {}
			for _, r in ipairs(rows) do
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
		end)
	else
		auction.button:Hide()
	end
	FitFoot(auction, 140)
	return true
end

function Shop.AuctionLost()
	if rehosting or not ahOpen then return end
	rehosting = true
	Soon(Shop.Auction)
	C_Timer.After(1.5, function() rehosting = false end)
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
		function() return API.GetFrame and API.GetFrame("npc") end,
		function() return _G.ClassTrainerFrame end,
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
local function Learn(s)
	local name = GetTrainerServiceInfo(s.index)
	if name ~= s.name then return end
	BuyTrainerService(s.index)
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

function Shop.Trainer()
	if not trainerOpen then return true end
	if IsTradeskillTrainer and not IsTradeskillTrainer() then return true end
	local host = TrainerHost()
	if not host then return false end
	trainer = trainer or NewPanel("DaylightRecipesTrainer", L["Recommended"], "trainer")
	trainer.redraw = Shop.Trainer
	local list, used, lines = Services()
	local line = TrainerLine(lines)
	local c = ns.Store and ns.Store.Char()
	-- Maxed out, a profession you don't have, or one the data doesn't know: nothing to recommend.
	local prof = line and c and type(c.prof) == "table" and c.prof[line]
	if not line or type(prof) ~= "table" or (prof.skill or 0) >= TOP then
		Shop.HidePanel(trainer)
		return true
	end
	local plan = c and type(c.plans) == "table" and c.plans[line]
	if type(plan) ~= "table" or type(plan.learn) ~= "table" then plan = nil end
	-- Only what the leveling route learns: the rest is no use for leveling.
	local rec = {}
	for _, s in ipairs(list) do
		local use = plan and s.spell and plan.learn[s.spell]
		if use and s.line == line and not KnowsSpell(s.spell, used) then
			s.use = use
			rec[#rec + 1] = s
		end
	end
	table.sort(rec, function(a, b) return (a.use[1] or 0) < (b.use[1] or 0) end)
	-- At your cap: the next rank comes first (the trainer's own step service).
	local rankRow
	if plan and plan.rank and (prof.max or 0) <= plan.rank.at and GetTrainerServiceStepIndex then
		local i = GetTrainerServiceStepIndex()
		if type(i) == "number" and i > 0 then
			local name, kind, icon = GetTrainerServiceInfo(i)
			-- (Offered once the game lets you train it, or once you're at the cap anyway.)
			if name and kind ~= "used" and kind ~= "header" and (kind == "available" or (prof.skill or 0) >= plan.rank.at) then
				local _, req = nil, nil
				if GetTrainerServiceSkillReq then _, req = GetTrainerServiceSkillReq(i) end
				rankRow = { index = i, name = name, icon = icon, available = kind == "available", req = req,
					cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0, use = { plan.rank.at, plan.rank.at }, rank = true }
				table.insert(rec, 1, rankRow)
			end
		end
	end
	-- The route's recipes this trainer doesn't have (taught elsewhere, or by a vendor or a drop).
	local elsewhere = 0
	if plan then
		local here = {}
		for _, s in ipairs(list) do if s.spell then here[s.spell] = true end end
		for spell in pairs(plan.learn) do
			local known = c and type(c.known) == "table" and c.known[line]
			if not here[spell] and not (known and known[spell]) and not KnowsSpell(spell, used) then elsewhere = elsewhere + 1 end
		end
	end
	local learnAll, learnCost = {}, 0
	-- (Nothing to learn: no footer, the panel just as tall as its message.)
	trainer.footless = #rec == 0
	Paint(trainer, host, "beside", function(d)
		if not plan then
			d:Line(L["Open %s once to work out its Leveling Guide: the recipes it uses are listed here."]:format(
				ns.Tips and ns.Tips.LineName(line) or L["this profession"]), "small", "OFF")
			return
		end
		if #rec == 0 then
			if elsewhere > 0 then
				d:Line(L["This trainer teaches none of the recipes your Leveling Guide still needs."], "small", "OFF")
			else
				d:Line(L["All Leveling Recipes Known"], "body", "GOOD")
			end
			return
		end
		for _, s in ipairs(rec) do
			local sub = s.rank and L["Your next rank: you're capped at %d"]:format(s.use[1] or 0)
				or L["For skill %d to %d"]:format(s.use[1] or 0, s.use[2] or 0)
			if not s.available then sub = sub .. " · " .. (s.req and L["needs skill %d"]:format(s.req) or L["not yet"]) end
			if s.available then
				learnAll[#learnAll + 1] = s
				learnCost = learnCost + (s.cost or 0)
			end
			d:Row({ icon = s.icon, dim = not s.available, left = s.name, leftInk = s.available and "VALUE" or "TEXT",
				right = s.available and Calc.Money(s.cost or 0) or L["Later"], rightInk = s.available and "GOOD" or "OFF",
				sub = sub, subInk = s.available and "GOOD" or "OFF", tip = function(tip) tip:SetTrainerService(s.index) end,
				onClick = s.available and function() Learn(s) end or nil })
		end
		if elsewhere > 0 then
			d:Line(L["%d more come from elsewhere: see the Missing tab."]:format(elsewhere), "tiny", "OFF")
		end
	end)
	trainer.note:SetText(#rec > 0 and L["%d to learn"]:format(#rec) or "")
	trainer.note:SetTextColor(Color("GOOD"))
	trainer.total:SetText(#learnAll > 0 and Calc.Money(learnCost) or "")
	trainer.total:SetTextColor(Color("VALUE"))
	trainer.button.text:SetText(L["Learn All"])
	trainer.button:SetShown(#rec > 0)
	FitFoot(trainer, 110)
	trainer.line:SetShown(#rec > 0)
	trainer.button.SetOff(#learnAll == 0 or (GetMoney and GetMoney() < learnCost))
	trainer.button:SetScript("OnClick", function()
		-- (Last first: learning one moves the ones after it up the list.)
		table.sort(learnAll, function(a, b) return a.index > b.index end)
		for _, s in ipairs(learnAll) do Learn(s) end
	end)
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

local Hide = Shop.HidePanel

-- A list tab clicked: that list in both buy lists from now on (kept per account), from its top.
function Shop.Pick(which)
	if not OTHER[which] then return end
	Folds()
	DaylightRecipesDB.shopList = which
	local changed = false
	for _, v in pairs(visit) do
		if v.which ~= which then changed = true end
		v.which = which
	end
	if not changed then return end
	if vendor then vendor.doc:Top() end
	if auction then auction.doc:Top() end
	Shop.Redraw()
end

-- A profession tag clicked (key: its line, false for "All"; shown: the tag in use where it was
-- clicked): only that profession's items, in both buy lists from now on (kept per account). The
-- tag in use again, or "All": everything.
function Shop.Tag(key, shown)
	Folds()
	if key == false or key == nil or key == shown then
		DaylightRecipesDB.shopTag = nil
	else
		DaylightRecipesDB.shopTag = key
	end
	if vendor then vendor.doc:Top() end
	if auction then auction.doc:Top() end
	Shop.Redraw()
end

-- The buy lists that are up, drawn again now (a pick, a removal: the player is looking at it).
function Shop.Redraw()
	if merchantOpen then Shop.Vendor() end
	if ahOpen then Shop.Auction() end
	-- (A controller: the game finds the rows that came or went; the cursor stays where it is.)
	ns.Pad.Settle()
end

-- ---------------------------------------------------------------------------------------------
-- Bought on the Auction House: what the game says went through
-- ---------------------------------------------------------------------------------------------

-- A commodity (anything that stacks) is bought in two steps, a quote and its confirmation. The
-- game then sends COMMODITY_PURCHASED with the item and how many, and COMMODITY_PURCHASE_SUCCEEDED
-- with nothing (AuctionHouseDocumentation.lua:1380-1395). DaylightUI's own Auction House notes
-- that the first "didn't always come in play" (DaylightUI_AuctionHouse\Buy.lua:194), so the
-- confirmation asked for is remembered too (a hook after C_AuctionHouse.ConfirmCommoditiesPurchase,
-- which the game's window and DaylightUI's both call) and counted when the second event comes.
-- Whichever tells of a purchase first counts it; the other telling of the same one is let go.
local asked, told

local function Credit(itemID, count, by)
	if type(itemID) ~= "number" or type(count) ~= "number" or count <= 0 then return end
	if told and told.by ~= by and told.itemID == itemID and told.count == count and GetTime() - told.at < 10 then
		told = nil
		return
	end
	told = { itemID = itemID, count = count, by = by, at = GetTime() }
	Shop.NoteAuction(itemID, count)
end

if type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ConfirmCommoditiesPurchase) == "function"
	and type(hooksecurefunc) == "function" then
	pcall(hooksecurefunc, C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, count)
		asked = { itemID = itemID, count = count, at = GetTime() }
	end)
end

-- Whether a purchase on the Auction House is being confirmed right now (asked of the game and not
-- answered yet): Prices' check of prices sends nothing meanwhile.
function Shop.Buying()
	return asked ~= nil and GetTime() - asked.at < 60
end

local function AuctionEvent(event, a, b)
	if event == "COMMODITY_PURCHASED" then
		Credit(a, b, "event")
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		local q = asked
		asked = nil
		if q and GetTime() - q.at < 60 then Credit(q.itemID, q.count, "confirm") end
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		asked = nil
	elseif event == "ITEM_PURCHASED" then
		-- An auction of one item bought out: the game names the item (ITEM_PURCHASED(itemID),
		-- AuctionHouseDocumentation.lua:1443-1450). Counted from this event alone, so it is counted
		-- once (AUCTION_HOUSE_PURCHASE_COMPLETED, which names only the auction, is not listened to).
		Shop.NoteAuction(a, 1)
	end
end

-- Bags, gold, prices or plans changed: the panels up are drawn again (once, a moment later, after
-- the bag snapshot has been read).
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
	end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "AUCTION_HOUSE_SHOW",
	"AUCTION_HOUSE_CLOSED", "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "BAG_UPDATE_DELAYED",
	"PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "COMMODITY_PURCHASED", "COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED", "ITEM_PURCHASED", "MAIL_SHOW", "MAIL_CLOSED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, itemID, count)
	if event == "MAIL_SHOW" or event == "MAIL_CLOSED" then
		mailOpen = event == "MAIL_SHOW"
		return
	end
	if event == "COMMODITY_PURCHASED" or event == "COMMODITY_PURCHASE_SUCCEEDED"
		or event == "COMMODITY_PURCHASE_FAILED" or event == "ITEM_PURCHASED" then
		AuctionEvent(event, itemID, count)
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		-- (Not ipairs: a panel not made yet this session would end the walk before the others.)
		local panels = { vendor or false, auction or false, trainer or false }
		for i = 1, 3 do
			local p = panels[i]
			if p and p:IsShown() and p.doc:Waiting(itemID) then Shop.Refresh() return end
		end
		return
	end
	if event == "MERCHANT_SHOW" then
		-- (A new visit: the kept list again, the source filter on. The event again while the
		-- window is up is the same visit.)
		if not merchantOpen then visit.vendor = {} end
		merchantOpen = true
		Soon(Shop.Vendor)
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
		Hide(vendor)
		if confirm then confirm:Hide() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		if not ahOpen then visit.auction = {} end
		ahOpen = true
		Soon(Shop.Auction)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		ahOpen = false
		Hide(auction)
	elseif event == "TRAINER_SHOW" then
		trainerOpen = true
		Soon(Shop.Trainer)
	elseif event == "TRAINER_CLOSED" then
		trainerOpen = false
		Hide(trainer)
	elseif event == "TRAINER_UPDATE" then
		if trainerOpen then Soon(Shop.Trainer) end
	else
		Shop.Refresh()
	end
end)
