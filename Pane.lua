-- The pane: two tabs (Recipe, Missing) over one scrolling page, drawn from pooled rows. It sits
-- in the frame DaylightUI docks to its profession window, or in one of ours hung on DaylightMogul's
-- window while Mogul runs the professions; the same page moves to whichever is in use.
local _, ns = ...
if not ns.ok then return end

local API, me = ns.API, ns.me
local Calc, Where = ns.Calc, ns.Where
local S = ns.state

local Pane = {}
ns.Pane = Pane

local PAD = 14
local SIZES = { tiny = 10, small = 12, body = 13, head = 15, title = 18 }

local root, scroll, child, thumb
local duiPane, mogulPane
local tab = "recipe"
local open = {}        -- missing recipe -> its sources are shown
local filter = ""
local fonts = {}       -- font string -> its size name (to follow a font change)

-- ---------------------------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------------------------

local function Color(name)
	if name == "ACCENT" then return API.Accent() end
	local c = API.Colors()[name or "TEXT"] or API.Colors().TEXT
	return c[1], c[2], c[3]
end

local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- The game's skill-up colours (orange, yellow, green, grey), DaylightUI's inks without them.
local DIFF = { "optimal", "medium", "easy", "trivial" }
local DIFF_INK = { "BAD", "WARN", "GOOD", "OFF" }
local function DiffColor(i)
	local game = _G.TradeSkillTypeColor
	local c = type(game) == "table" and game[DIFF[i]]
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return Color(DIFF_INK[i])
end

local function Text(parent, size, justify)
	local fs = API.Text(parent, size, justify)
	fonts[fs] = size
	return fs
end

-- ---------------------------------------------------------------------------------------------
-- The page: a stack of pooled pieces, top to bottom
-- ---------------------------------------------------------------------------------------------

local pools = {}       -- kind -> { list, used }
local y, width = 0, 200

local function Take(kind, make)
	local p = pools[kind]
	if not p then p = { list = {}, used = 0 } pools[kind] = p end
	p.used = p.used + 1
	local piece = p.list[p.used]
	if not piece then
		piece = make()
		p.list[p.used] = piece
	end
	piece:ClearAllPoints()
	piece:Show()
	return piece
end

local function Begin()
	for _, p in pairs(pools) do
		for i = 1, #p.list do p.list[i]:Hide() end
		p.used = 0
	end
	y = 8
	width = child:GetWidth()
end

local function Gap(n) y = y + n end

local function Line(text, size, ink, indent)
	size = size or "body"
	indent = indent or 0
	local fs = Take("text:" .. size, function()
		local f = Text(child, size)
		f:SetJustifyH("LEFT")
		f:SetWordWrap(true)
		return f
	end)
	fs:SetPoint("TOPLEFT", child, "TOPLEFT", PAD + indent, -y)
	fs:SetWidth(width - PAD * 2 - indent)
	fs:SetText(text)
	fs:SetTextColor(Color(ink))
	y = y + math.ceil(fs:GetStringHeight()) + 4
	return fs
end

local function Heading(text)
	Gap(10)
	Line(text, "small", "LABEL")
	Gap(2)
end

-- A row: icon, a left and right text, a line under them; hover wash when it does something.
local function MakeRow()
	local r = CreateFrame("Button", nil, child)
	r.wash = r:CreateTexture(nil, "BACKGROUND")
	r.wash:SetAllPoints()
	r.wash:SetColorTexture(1, 1, 1, 0.05)
	r.wash:Hide()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.left = Text(r, "body")
	r.left:SetJustifyH("LEFT")
	r.left:SetWordWrap(false)
	r.right = Text(r, "body", "RIGHT")
	r.sub = Text(r, "small")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(false)
	r:SetScript("OnEnter", function(self)
		if self.onClick or self.tip then self.wash:Show() end
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			pcall(self.tip, GameTooltip)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	r:SetScript("OnClick", function(self)
		if self.onClick then self.onClick() end
	end)
	return r
end

-- o: icon, left, right, sub, leftInk, rightInk, subInk, indent, onClick, tip(tooltip)
local function Row(o)
	local r = Take("row", MakeRow)
	local indent = o.indent or 0
	local h = o.sub and 34 or 20
	r:SetPoint("TOPLEFT", child, "TOPLEFT", PAD - 4 + indent, -y)
	r:SetSize(width - PAD * 2 + 8 - indent, h)
	r.onClick, r.tip = o.onClick, o.tip
	r.icon:ClearAllPoints()
	r.left:ClearAllPoints()
	r.right:ClearAllPoints()
	r.sub:ClearAllPoints()
	local x = 4
	if o.icon then
		r.icon:SetTexture(o.icon)
		r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
		r.icon:Show()
		x = 26
	else
		r.icon:Hide()
	end
	r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
	r.right:SetText(o.right or "")
	r.right:SetTextColor(Color(o.rightInk or "VALUE"))
	r.left:SetPoint("TOPLEFT", r, "TOPLEFT", x, -3)
	r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
	r.left:SetText(o.left or "")
	r.left:SetTextColor(Color(o.leftInk or "VALUE"))
	if o.sub then
		r.sub:SetPoint("TOPLEFT", r.left, "BOTTOMLEFT", 0, -3)
		r.sub:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		r.sub:SetText(o.sub)
		r.sub:SetTextColor(Color(o.subInk or "TEXT"))
		r.sub:Show()
	else
		r.sub:Hide()
	end
	y = y + h + 2
	return r
end

local function Bar(value)
	local b = Take("bar", function()
		local bar = API.Bar(child)
		bar:SetMinMaxValues(0, 1)
		return bar
	end)
	b:SetPoint("TOPLEFT", child, "TOPLEFT", PAD, -y)
	b:SetSize(width - PAD * 2, 8)
	b:SetValue(value or 0)
	y = y + 14
	return b
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

local function ItemTip(itemID)
	return function(tip) tip:SetItemByID(itemID) end
end

local function SpellTip(spell)
	return function(tip) tip:SetSpellByID(spell) end
end

local function ItemName(itemID)
	local name, _, quality, icon = Calc.ItemInfo(itemID)
	if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
	if name and quality and C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and r then name = Hex(r, g, b) .. name .. "|r" end
	end
	return name or (ns.ItemNames and ns.ItemNames[itemID]) or ("Item " .. itemID), icon
end

local function Pct(v)
	if v >= 0.995 or v == 0 then return ("%d%%"):format(v * 100 + 0.5) end
	return ("%.1f%%"):format(v * 100)
end

-- ---------------------------------------------------------------------------------------------
-- Recipe page
-- ---------------------------------------------------------------------------------------------

local function SkillPart(spell)
	Heading("Skill-up")
	local chance, base, state = Calc.Chance(spell, S.skill or 0, S.max)
	if state == "unknown" then
		Line("Its skill-up range isn't known.", "small", "OFF")
		return chance
	end
	local t = Calc.Thresholds(spell)
	local step = 4
	for i = 1, 3 do if (S.skill or 0) < t[i + 1] then step = i break end end
	local r, g, b = DiffColor(step)
	local row = Row({ left = "Chance of a point", right = Pct(chance) })
	row.right:SetTextColor(r, g, b)
	Bar(chance)
	local marks = {}
	local words = { "orange", "yellow", "green", "grey" }
	for i = 1, 4 do
		local cr, cg, cb = DiffColor(i)
		marks[#marks + 1] = Hex(cr, cg, cb) .. words[i] .. " " .. t[i] .. "|r"
	end
	Line(table.concat(marks, "  "), "small", "TEXT")
	if state == "cap" then
		Line(("You're at your cap (%d): train the next rank for more points."):format(S.max), "small", "WARN")
	elseif chance > 0 and chance < 1 then
		Line(("About %.1f crafts a point."):format(1 / chance), "small", "TEXT")
	elseif chance <= 0 then
		Line("Grey: it gives no more points.", "small", "OFF")
	end
	local overtime, _, talents = Calc.Talents()
	if overtime > 0 and base and base > 0 and base < 1 then
		Line(("Overtime rank %d: +%d%% included."):format(talents.overtimeRank, overtime * 100 + 0.5), "small", "OFF")
	end
	return chance
end

local function CostPart(spell, chance)
	Heading("Materials")
	local cost = Calc.Cost(spell)
	if #cost.rows == 0 then
		Line("It takes no materials.", "small", "OFF")
		return cost
	end
	for _, m in ipairs(cost.rows) do
		local name, icon = ItemName(m.itemID)
		local sub
		if m.kind == "ah" then
			sub = ("Auction House, %s each"):format(Calc.Money(m.unit))
		elseif m.kind == "vendor" then
			sub = ("%s, %s each"):format(m.who or "Vendor", Calc.Money(m.unit))
		else
			sub = "No price known"
		end
		Row({ icon = icon, left = name .. (m.count > 1 and ("  x" .. m.count) or ""),
			right = m.total and Calc.Money(m.total) or "?", rightInk = m.total and "VALUE" or "OFF",
			sub = sub, subInk = m.unit and "TEXT" or "OFF", tip = ItemTip(m.itemID) })
	end
	Row({ left = "Total", leftInk = "LABEL", right = Calc.Money(cost.total) })
	if not cost.complete then
		Line("Some materials have no price, so the total is short.", "small", "WARN")
	elseif chance and chance > 0 and chance < 1 then
		Row({ left = "Per skill point", leftInk = "LABEL", right = Calc.Money(cost.total / chance) })
	end
	if not Calc.HasAH() then
		Line("Vendor prices only. Load DaylightMogul for Auction House prices.", "small", "OFF")
	end
	return cost
end

local function WorthPart(spell)
	local worth = Calc.Worth(spell)
	Heading("Value")
	if not worth then
		Line("It makes no item to sell.", "small", "OFF")
		return
	end
	local name, icon = ItemName(worth.itemID)
	local made = worth.count ~= 1 and ("  x" .. (worth.count % 1 == 0 and worth.count or ("%.1f"):format(worth.count))) or ""
	Row({ icon = icon, left = name .. made, tip = ItemTip(worth.itemID) })
	if worth.bound then Line("It binds when made: no Auction House.", "small", "OFF") end
	if #worth.routes == 0 then
		Line("No price is known for it.", "small", "OFF")
	end
	for _, route in ipairs(worth.routes) do
		local sub, ink
		if route.profit then
			if route.profit >= 0 then
				sub, ink = Calc.Money(route.profit) .. " profit", "GOOD"
			else
				sub, ink = Calc.Money(-route.profit) .. " loss", "BAD"
			end
			if route.label == "Auction House" then sub = sub .. ", after the 5% cut" end
		end
		Row({ left = route.label, leftInk = "TEXT", right = Calc.Money(route.value), sub = sub, subInk = ink })
	end
	local de = worth.de
	if de then
		Heading("Disenchants into")
		for _, m in ipairs(de.mats) do
			local mname, micon = ItemName(m.itemID)
			local range = m.lo == m.hi and tostring(m.lo) or (m.lo .. "-" .. m.hi)
			Row({ icon = micon, left = mname, right = m.value and Calc.Money(m.value) or "?",
				rightInk = m.value and "VALUE" or "OFF",
				sub = ("%s at a time, %s of the time"):format(range, Pct(m.chance)), tip = ItemTip(m.itemID) })
		end
		Line("Classic yields: not yet checked on Forever.", "tiny", "OFF")
	end
end

local function RecipePage()
	local spell = S.recipe
	if not spell then
		Line("Pick a recipe.", "body", "OFF")
		return
	end
	local info = ns.Ask("GetRecipeInfo", spell)
	local name = type(info) == "table" and info.name or (ns.RecipeNames and ns.RecipeNames[spell]) or ("Recipe " .. spell)
	Line(name, "head", "VALUE")
	local chance = SkillPart(spell)
	CostPart(spell, chance)
	WorthPart(spell)
end

-- ---------------------------------------------------------------------------------------------
-- Missing page
-- ---------------------------------------------------------------------------------------------

local function PlaceText(place)
	if not place then return nil end
	if place.mapID then return ("%s (%d, %d)"):format(place.zone, place.x + 0.5, place.y + 0.5) end
	return place.zone
end

local function MissingPage()
	if S.linked then
		Line("These are someone else's recipes. Missing recipes are listed for your own.", "small", "OFF")
		return
	end
	if not S.line then
		Line("There's no recipe data for this profession.", "small", "OFF")
		return
	end
	local list = Where.Missing(filter)
	local count = #list
	Line(count == 0 and (filter ~= "" and "No missing recipe matches." or "You know every recipe there is.")
		or ("%d recipe%s you don't know"):format(count, count == 1 and "" or "s"), "small", "LABEL")
	Gap(2)
	for _, e in ipairs(list) do
		local sub = e.summary or ""
		if e.level then sub = sub .. (sub ~= "" and " · " or "") .. "Level " .. e.level end
		Row({ left = e.name, leftInk = e.reachable and "VALUE" or "OFF",
			right = e.required and ("Skill " .. e.required) or "", rightInk = e.reachable and "GOOD" or "OFF",
			sub = sub, subInk = "TEXT",
			tip = e.item and ItemTip(e.item) or SpellTip(e.spell),
			onClick = function()
				open[e.spell] = not open[e.spell] or nil
				Pane.Render()
			end })
		if open[e.spell] then
			for _, g in ipairs(e.groups) do
				Line(g.title, "small", "LABEL", 12)
				for _, l in ipairs(g.lines) do
					local located = l.place and l.place.mapID
					Row({ indent = 12, left = l.name, leftInk = "TEXT", right = l.note or "", rightInk = "VALUE",
						sub = PlaceText(l.place), subInk = located and "ACCENT" or "OFF",
						tip = located and function(tip)
							tip:SetText(l.name)
							tip:AddLine(PlaceText(l.place), 1, 1, 1)
							tip:AddLine("Click for a waypoint.", Color("LABEL"))
						end or nil,
						onClick = located and function() Where.Go(l.name, l.place) end or nil })
				end
				if g.more > 0 then Line(("and %d more"):format(g.more), "tiny", "OFF", 16) end
			end
			Gap(6)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------------------------

local function PaintTabs()
	for _, b in ipairs(root.tabs) do
		local on = b.key == tab
		if on then
			b.text:SetTextColor(Color("VALUE"))
			b.line:SetColorTexture(API.Accent())
			b.line:Show()
		else
			b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
			b.line:Hide()
		end
		b:SetWidth(math.ceil(b.text:GetStringWidth()) + 16)
	end
end

local function FitThumb()
	local range = scroll:GetVerticalScrollRange() or 0
	local h = scroll:GetHeight()
	if range <= 0.5 or h <= 0 then thumb:Hide() return end
	local size = math.max(24, h * h / (h + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -3, -((h - size) * (scroll:GetVerticalScroll() / range)))
	thumb:Show()
end

local function Build()
	root = CreateFrame("Frame", nil, UIParent)
	root:Hide()
	-- Drawn while its window was shut: draw again once it shows.
	root:SetScript("OnShow", function() ns.Changed() end)
	root.tabs = {}
	for i, spec in ipairs({ { "recipe", "Recipe" }, { "missing", "Missing" } }) do
		local b = CreateFrame("Button", nil, root)
		b.key = spec[1]
		b:SetHeight(26)
		b.text = Text(b, "body")
		b.text:SetPoint("CENTER", 0, 1)
		b.text:SetText(spec[2])
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 6, 0)
		b.line:SetPoint("BOTTOMRIGHT", -6, 0)
		b:SetScript("OnClick", function()
			if tab == b.key then return end
			tab = b.key
			if scroll then scroll:SetVerticalScroll(0) end
			Pane.Render()
		end)
		b:SetScript("OnEnter", PaintTabs)
		b:SetScript("OnLeave", PaintTabs)
		if i == 1 then
			b:SetPoint("TOPLEFT", root, "TOPLEFT", PAD - 8, -10)
		else
			b:SetPoint("LEFT", root.tabs[i - 1], "RIGHT", 2, 0)
		end
		root.tabs[i] = b
	end
	root.skill = Text(root, "small", "RIGHT")
	root.skill:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, -18)

	root.search = API.Input(root, { search = true, hint = "Search",
		onChange = function(text)
			text = (text or ""):lower()
			if text == filter then return end
			filter = text
			if scroll then scroll:SetVerticalScroll(0) end
			Pane.Render()
		end })
	root.search:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -44)
	root.search:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, -44)

	scroll = CreateFrame("ScrollFrame", nil, root)
	scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(200, 1)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local to = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
		self:SetVerticalScroll(to)
		FitThumb()
	end)
	scroll:SetScript("OnScrollRangeChanged", FitThumb)
	scroll:SetScript("OnSizeChanged", function(_, w)
		if w and w > 0 then child:SetWidth(w) end
	end)
	thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	thumb:Hide()
end

-- The pane in use: DaylightUI's docked one, or ours on Mogul's window.
local function Host()
	if S.mode == "mogul" then return mogulPane end
	if not duiPane then duiPane = me.AttachCraftPane(ns.Get("paneWidth")) end
	return duiPane
end

function Pane.AttachMogul(win)
	if type(win) ~= "table" or not win.CreateTexture then return end
	if not mogulPane then
		mogulPane = CreateFrame("Frame", "DaylightRecipesPane", win)
		mogulPane:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
		mogulPane:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", 6, 0)
		mogulPane:SetWidth(ns.Get("paneWidth"))
		mogulPane:EnableMouse(true)
		API.Skin(mogulPane, { window = true })
	end
end

function Pane.Shown()
	return root ~= nil and root:IsVisible()
end

function Pane.Render()
	local host = Host()
	if not host then return end
	if not root then Build() end
	if root:GetParent() ~= host then
		root:SetParent(host)
		root:ClearAllPoints()
		root:SetAllPoints(host)
	end
	root:Show()
	if not host:IsVisible() then return end

	PaintTabs()
	local missing = tab == "missing"
	root.search:SetShown(missing)
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, missing and -(44 + root.search:GetHeight() + 8) or -40)
	scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
	local w = scroll:GetWidth()
	child:SetWidth(w and w > 0 and w or ns.Get("paneWidth"))
	thumb:SetColorTexture(API.Accent())
	thumb:SetAlpha(0.5)

	if S.name and (S.max or 0) > 0 then
		root.skill:SetText(Hex(Color("LABEL")) .. S.name .. "|r  " .. S.skill .. " / " .. S.max)
		root.skill:SetTextColor(Color("VALUE"))
	else
		root.skill:SetText("")
	end

	Begin()
	local ok, err = pcall(missing and MissingPage or RecipePage)
	if not ok then
		geterrorhandler()(err)
		Line("Something went wrong drawing this page.", "small", "BAD")
	end
	Gap(8)
	child:SetHeight(math.max(1, y))
	local range = scroll:GetVerticalScrollRange() or 0
	if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
	FitThumb()
end

function Pane.Resize()
	local w = ns.Get("paneWidth")
	if duiPane then me.AttachCraftPane(w) end
	if mogulPane then
		mogulPane:SetWidth(w)
		API.Skin(mogulPane, { window = true })
	end
	if Pane.Shown() then ns.Changed() end
end

-- The player's font changed: every string we made takes it, at its size.
function Pane.Restyle()
	local font = API.Font()
	for fs, size in pairs(fonts) do
		local _, _, flags = fs:GetFont()
		fs:SetFont(font, SIZES[size] or 13, flags or "")
	end
	if mogulPane then API.Skin(mogulPane, { window = true }) end
	if Pane.Shown() then ns.Changed() end
end

-- DaylightUI's pane is asked for at login, so it's docked before the window first opens.
me.On("Login", function() Host() end)
