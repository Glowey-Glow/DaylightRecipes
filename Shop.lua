-- Small windows where you shop and train, from your plans (the route each profession's Leveling
-- Guide works out, kept per character: Plan.Get saves what it needs and which recipes it learns)
-- and your crafting queue:
--   Vendor:   under the vendor's window, the buy list: every material your plans and queue still
--             need that this character doesn't have (in bags, bank or mail; an alt holding some is
--             only mentioned, "[Mira has 12]"). What this vendor sells is one click to buy, exactly
--             the number needed ("Buy all here" for the lot); what it doesn't is grayed out,
--             [Not Available].
--   Auction House: under its window, the same list with the Auction House and vendor prices side
--             by side and which is cheaper. A click puts the item in the game's search box.
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

-- Bought here a moment ago and not read in the bags yet: itemID -> { count, version }.
local bought = {}
function Shop.Bought(itemID)
	local b = bought[itemID]
	if not b then return 0 end
	-- (Once the bags have been read again, they count it themselves.)
	if not ns.Store or ns.Store.version ~= b.version or GetTime() - b.at > 5 then
		bought[itemID] = nil
		return 0
	end
	return b.count
end
local function NoteBought(itemID, count)
	if count <= 0 then return end
	local b = bought[itemID]
	local version = ns.Store and ns.Store.version or 0
	if b and b.version == version then
		b.count = b.count + count
	else
		bought[itemID] = { count = count, version = version, at = GetTime() }
	end
end

-- Every material this character's plans still have to buy:
-- { { itemID, need, have (Store.Count), buy, lines = { [line] = n } } } most needed first.
function Shop.List()
	local c = ns.Store and ns.Store.Char()
	local out = {}
	if not c then return out end
	local need, lines = {}, {}
	for line, plan in pairs(type(c.plans) == "table" and c.plans or {}) do
		if type(plan) == "table" and type(plan.need) == "table" then
			for itemID, n in pairs(plan.need) do
				if type(n) == "number" and n > 0 then
					need[itemID] = (need[itemID] or 0) + n
					lines[itemID] = lines[itemID] or {}
					lines[itemID][line] = n
				end
			end
		end
	end
	-- The queue's too ("queue" in lines: its share). (A Leveling Guide step queued is in both: the
	-- larger of the two is what's needed, not the sum.)
	if ns.Queue then
		for itemID, n in pairs(ns.Queue.Needs()) do
			need[itemID] = math.max(need[itemID] or 0, n)
			lines[itemID] = lines[itemID] or {}
			lines[itemID].queue = n
		end
	end
	for itemID, n in pairs(need) do
		local have = ns.Store.Count(itemID)
		-- (What this character lacks: an alt's are only mentioned. Just bought, not in the bag
		-- snapshot yet: taken off already.)
		local buy = math.max(0, n - have.mine - Shop.Bought(itemID))
		if buy > 0 then
			out[#out + 1] = { itemID = itemID, need = n, have = have, buy = buy, lines = lines[itemID],
				alert = ns.Pages and ns.Pages.AltAlert(have) }
		end
	end
	table.sort(out, function(a, b)
		if a.buy ~= b.buy then return a.buy > b.buy end
		return a.itemID < b.itemID
	end)
	return out
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

local function DuiListsHoldings()
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	if type(meta) ~= "function" then return false end
	local ok, version = pcall(meta, "DaylightUI", "Version")
	if not ok or not AtLeast(version, { 1, 8, 3 }) then return false end
	local on, bags = pcall(API.IsModuleEnabled, "Bags")
	if not on or not bags then return false end
	local got, viewer = pcall(API.GetSetting, "Bags", "viewer.enabled")
	if not got then return false end
	return viewer ~= false
end

-- The tooltip of a buy list row: the item, then what each plan needs of it and what you hold.
local function RowTip(r, hint)
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
		-- alt holds it in theirs: then only the mail is said here, which DaylightUI doesn't count.
		if where and have and (have.altHeld or 0) > 0 and DuiListsHoldings() then
			where = have.mail > 0 and L["%d in the mail"]:format(have.mail) or nil
		end
		if where then tip:AddLine(L["You have %s"]:format(where), Color("TEXT")) end
	end
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

-- The fold tab: DaylightUI's look for a fold (a small bordered tab with a grip), against the
-- panel's outer edge while it's open, against the window's edge while it's folded away.
local function PaintGrip(t, hover)
	local r, g, b
	if hover then r, g, b = API.Accent() else r, g, b = Color("LABEL") end
	for _, bar in ipairs(t.bars) do bar:SetColorTexture(r, g, b, 1) end
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
		folds[p.key] = not folds[p.key] or nil
		GameTooltip:Hide()
		if p.redraw then p.redraw() end
	end)
	t:SetScript("OnEnter", function(self)
		PaintGrip(self, true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText((Folds()[p.key] and L["Show %s"] or L["Hide %s"]):format(p.label))
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function(self)
		PaintGrip(self, false)
		GameTooltip:Hide()
	end)
	t:SetScript("OnUpdate", function(self)
		if not Visible(self.host) then self:Hide() end
	end)
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

local function NewPanel(name, title, key)
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
	p.doc.scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -HEAD + 6)
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
	p:SetScript("OnUpdate", function(self)
		if not Visible(self.host) then self:Hide() end
	end)
	-- A controller (Guide.lua's Pad): the cursor moves over the panel's rows and button once the
	-- triggers (LT / RT) bring it from the window it hangs on (it never takes the cursor as it
	-- shows), A presses, X buys a row's item (its double-click), B folds the panel away.
	p.padSecond = true
	p.padKeys = { { key = "X", label = L["Buy"],
		when = function(at) return type(at) == "table" and type(at.onDouble) == "function" end,
		run = function(at) if type(at) == "table" and at.onDouble then at.onDouble(at) end end } }
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

-- Places a panel by its host: under it (side = "below") or beside it, wherever there's room.
local function Dock(p, host, side)
	if p.host ~= host then
		p.host = host
		p:SetParent(UIParent)
	end
	p:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
	local h = p:GetHeight()
	p:ClearAllPoints()
	local bottom = host:GetBottom() or 0
	local right = host:GetRight() or 0
	local screenW = UIParent:GetWidth() / p:GetScale()
	if side == "below" and bottom * host:GetEffectiveScale() / p:GetEffectiveScale() > h + 8 then
		p:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -6)
		p.edge = "below"
	elseif right * host:GetEffectiveScale() / p:GetEffectiveScale() + p:GetWidth() + 8 < screenW then
		p:SetPoint("TOPLEFT", host, "TOPRIGHT", 6, 0)
		p.edge = "right"
	else
		p:SetPoint("TOPRIGHT", host, "TOPLEFT", -6, 0)
		p.edge = "left"
	end
end

-- Draws a panel's rows with fill(doc), sizes it to them, docks it; folded, only its tab shows.
local function Paint(p, host, side, fill)
	local folded = Folds()[p.key] == true
	if folded then
		Dock(p, host, side)
		p:Hide()
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
	d.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, foot)
	p:SetHeight(math.min(MAX_H, HEAD + d.y + foot))
	Dock(p, host, side)
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
	vendor = vendor or NewPanel("DaylightRecipesBuyList", L["Buy List"], "vendor")
	vendor.redraw = Shop.Vendor
	local list = Shop.List()
	-- Nothing to buy at all: the window stays out of the way.
	if #list == 0 then
		Shop.HidePanel(vendor)
		return true
	end
	local shelf = Shelf()
	local here, cost = {}, 0
	Paint(vendor, host, "below", function(d)
		for _, r in ipairs(list) do
			local name, icon = Doc.ItemName(r.itemID, d)
			local s = shelf[r.itemID]
			local sub = L["Need %d · you have %d"]:format(r.need, r.have.mine)
			if r.alert then sub = sub .. " · " .. r.alert end
			if s then
				local count, price = CanBuy(s, r.buy)
				local short = count < r.buy
				here[#here + 1] = { s = s, want = r.buy, itemID = r.itemID, price = price }
				cost = cost + price
				local why = s.left == 0 and L["Sold out"] or L["Can't afford"]
				d:Row({ icon = icon, left = name, right = count > 0 and L["Buy %d for %s"]:format(count, Calc.Money(price)) or why,
					rightInk = count > 0 and "VALUE" or "BAD", sub = short and count > 0 and (sub .. " · " .. L["only %d here"]:format(count)) or sub,
					subInk = "TEXT", tip = RowTip(r, count > 0 and L["Double-click to buy."] or nil),
					onDouble = count > 0 and function()
						local itemName = Calc.ItemInfo(r.itemID) or ns.ItemNameOf(r.itemID) or L["it"]
						Confirm(vendor, L["Buy %d %s?"]:format(count, itemName), price, function()
							NoteBought(r.itemID, BuyOne(s, r.buy))
							Shop.Vendor()
						end)
					end or nil })
			else
				d:Row({ icon = icon, dim = true, left = name, leftInk = "OFF", right = L["[Not Available]"], rightInk = "OFF",
					sub = Elsewhere(r) .. (r.alert and (" · " .. r.alert) or ""), subInk = "OFF",
					tip = RowTip(r) })
			end
		end
	end)
	vendor.note:SetText(L["%d to buy"]:format(#list))
	vendor.note:SetTextColor(Color("LABEL"))
	vendor.total:SetText(#here > 0 and L["Here: %s"]:format(Calc.Money(cost)) or L["Nothing Available"])
	-- (Nothing on the list sold here: the whole list grayed out, the title too.)
	vendor.doc.scroll:SetAlpha(#here > 0 and 1 or 0.45)
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
			for _, h in ipairs(picks) do NoteBought(h.itemID, BuyOne(h.s, h.want)) end
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

local function AHHost()
	return FirstShown({
		function() return _G.DaylightMogulMain end,
		function() return _G.AuctionHouseFrame end,
	})
end

-- The item's name in the game's own Auction House search (when it's the window showing).
local function SearchFor(itemID)
	local f = _G.AuctionHouseFrame
	if not Visible(f) or type(f.SearchBar) ~= "table" then return false end
	local name = Calc.ItemInfo(itemID) or ns.ItemNameOf(itemID)
	if not name then return false end
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
	auction = auction or NewPanel("DaylightRecipesAHList", L["Buy List"], "auction")
	auction.redraw = Shop.Auction
	local list = Shop.List()
	if #list == 0 then
		Shop.HidePanel(auction)
		return true
	end
	local ahTotal, saved = 0, 0
	Paint(auction, host, "below", function(d)
		for _, r in ipairs(list) do
			local name, icon = Doc.ItemName(r.itemID, d)
			local ah = Calc.AH(r.itemID)
			local vend, who = Calc.Vendor(r.itemID)
			local right, ink
			if ah and vend then
				if ah < vend then
					right, ink = L["AH is cheaper"], "GOOD"
					ahTotal = ahTotal + ah * r.buy
					saved = saved + (vend - ah) * r.buy
				else
					right, ink = L["Vendor is cheaper"], "WARN"
				end
			elseif ah then
				right, ink = L["Auction House"], "VALUE"
				ahTotal = ahTotal + ah * r.buy
			elseif vend then
				right, ink = L["Vendor only"], "OFF"
			else
				right, ink = L["No price"], "OFF"
			end
			local parts = { L["Buy %d"]:format(r.buy) }
			if r.alert then parts[#parts + 1] = r.alert end
			if ah then parts[#parts + 1] = L["AH %s"]:format(Calc.Money(ah * r.buy)) end
			if vend then parts[#parts + 1] = L["Vendor %s (%s)"]:format(Calc.Money(vend * r.buy), who or L["vendor"]) end
			d:Row({ icon = icon, left = name, right = right, rightInk = ink,
				sub = table.concat(parts, " · "), subInk = "TEXT", tip = RowTip(r),
				onClick = function() SearchFor(r.itemID) end })
		end
		if not Calc.HasAH() then
			d:Line(L["No Auction House prices yet: scan from the Leveling Guide."], "tiny", "OFF")
		end
	end)
	auction.note:SetText(L["%d to buy"]:format(#list))
	auction.note:SetTextColor(Color("LABEL"))
	if ahTotal > 0 then
		auction.total:SetText(saved > 0 and L["On the AH: %s (saves %s)"]:format(Calc.Money(ahTotal), Calc.Money(saved))
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
		auction.button.SetOff(false)
		auction.button:Show()
		auction.button:SetScript("OnClick", function()
			local searches = {}
			for _, r in ipairs(list) do
				local name = Calc.ItemInfo(r.itemID) or ns.ItemNameOf(r.itemID)
				if name then
					local ok, text = pcall(api.ConvertToSearchString, "Daylight Recipes",
						{ searchString = name, isExact = true, quantity = r.buy })
					if ok and type(text) == "string" then searches[#searches + 1] = text end
				end
			end
			if #searches == 0 then return end
			local ok = pcall(api.CreateShoppingList, "Daylight Recipes", "Daylight Recipes", searches)
			ns.Print(ok and Plural(#searches, "Auctionator list \"Daylight Recipes\" made: %d item.",
				"Auctionator list \"Daylight Recipes\" made: %d items."):format(#searches)
				or L["Auctionator didn't take the list."])
		end)
	else
		auction.button:Hide()
	end
	FitFoot(auction, 140)
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
	"PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED" }) do
	pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, itemID)
	if event == "GET_ITEM_INFO_RECEIVED" then
		for _, p in ipairs({ vendor, auction, trainer }) do
			if p and p:IsShown() and p.doc:Waiting(itemID) then Shop.Refresh() return end
		end
		return
	end
	if event == "MERCHANT_SHOW" then
		merchantOpen = true
		Soon(Shop.Vendor)
	elseif event == "MERCHANT_CLOSED" then
		merchantOpen = false
		Hide(vendor)
		if confirm then confirm:Hide() end
	elseif event == "AUCTION_HOUSE_SHOW" then
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
