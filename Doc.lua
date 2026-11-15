-- A scrolling page drawn from pooled pieces, top to bottom: lines of text, rows (icon, left and
-- right text, a line under them, a hover wash when they do something) and bars. The docked pane
-- and the big window each draw their pages on one of these; the pages themselves are in Pages.lua.
-- Also the small helpers every page uses (colors, item names, tooltips, percentages).
local _, ns = ...
if not ns.ok then return end
local L, Plural = ns.L, ns.Plural

local API = ns.API
local Calc = ns.Calc

local Doc = {}
ns.Doc = Doc

Doc.SIZES = { tiny = 10, small = 12, body = 13, head = 15, title = 18 }
local fonts = setmetatable({}, { __mode = "k" })   -- font string -> its size name (to follow a font change)

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function Doc.Color(name)
	if name == "ACCENT" then return API.Accent() end
	local c = API.Colors()[name or "TEXT"] or API.Colors().TEXT
	return c[1], c[2], c[3]
end
local Color = Doc.Color

function Doc.Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- The game's skill-up colors (orange, yellow, green, gray), DaylightUI's inks without them.
local DIFF = { "optimal", "medium", "easy", "trivial" }
local DIFF_INK = { "BAD", "WARN", "GOOD", "OFF" }
function Doc.DiffColor(i)
	local game = _G.TradeSkillTypeColor
	local c = type(game) == "table" and game[DIFF[i]]
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return Color(DIFF_INK[i])
end

-- A font string in the player's font, followed when the font changes.
function Doc.Text(parent, size, justify)
	local fs = API.Text(parent, size, justify)
	fonts[fs] = size
	return fs
end

function Doc.ItemTip(itemID)
	return function(tip) tip:SetItemByID(itemID) end
end

function Doc.SpellTip(spell)
	return function(tip) tip:SetSpellByID(spell) end
end

function Doc.Pct(v)
	if v >= 0.995 or v == 0 then return L["%d%%"]:format(v * 100 + 0.5) end
	return L["%.1f%%"]:format(v * 100)
end

function Doc.RecipeName(spell)
	local info = ns.Ask("GetRecipeInfo", spell)
	return type(info) == "table" and info.name or ns.SpellName(spell) or L["Recipe %d"]:format(spell)
end

function Doc.Ago(stamp)
	local s = time() - (stamp or 0)
	if s < 3600 then return L["%d min ago"]:format(math.max(1, math.floor(s / 60))) end
	if s < 86400 then return L["%d h ago"]:format(math.floor(s / 3600)) end
	local days = math.floor(s / 86400)
	return Plural(days, "%d day ago", "%d days ago"):format(days)
end

-- An item's name in its quality color and its icon. One not cached yet is noted on the doc, so
-- only its arrival draws the page again.
function Doc.ItemName(itemID, d)
	local name, _, quality, icon = Calc.ItemInfo(itemID)
	if not name and d then d.waiting[itemID] = true end
	if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
	if name and quality and C_Item and C_Item.GetItemQualityColor then
		local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
		if ok and r then name = Doc.Hex(r, g, b) .. name .. "|r" end
	end
	return name or ns.ItemNameOf(itemID) or L["Item %d"]:format(itemID), icon
end

-- The player's font changed: every string made here takes it, at its size.
function Doc.Restyle()
	local font = API.Font()
	for fs, size in pairs(fonts) do
		local _, _, flags = fs:GetFont()
		fs:SetFont(font, Doc.SIZES[size] or 13, flags or "")
	end
end

-- ---------------------------------------------------------------------------------------------
-- A doc
-- ---------------------------------------------------------------------------------------------

local D = {}
D.__index = D

-- A row: icon, a left and right text, a line under them; hover wash when it does something.
local function MakeRow(child)
	local r = CreateFrame("Button", nil, child)
	r.wash = r:CreateTexture(nil, "BACKGROUND")
	r.wash:SetAllPoints()
	r.wash:SetColorTexture(1, 1, 1, 0.05)
	r.wash:Hide()
	r.mark = r:CreateTexture(nil, "BORDER")
	r.mark:SetAllPoints()
	r.mark:Hide()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- (Its texts wrap onto more lines rather than being cut off: D:Row sizes the row to them.)
	r.left = Doc.Text(r, "body")
	r.left:SetJustifyH("LEFT")
	r.left:SetWordWrap(true)
	r.right = Doc.Text(r, "body", "RIGHT")
	r.sub = Doc.Text(r, "small")
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(true)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnEnter", function(self)
		if self.onClick or self.onDouble or self.tip then self.wash:Show() end
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
	r:SetScript("OnDoubleClick", function(self, button)
		if button == "LeftButton" and self.onDouble then self.onDouble(self) end
	end)
	r:SetScript("OnClick", function(self, button)
		-- (Shift-click a row with an item or recipe link: into the open chat box.)
		if IsModifiedClick("CHATLINK") and self.link then
			ChatEdit_InsertLink(self.link)
			return
		end
		-- (A right click only acts on rows that want one: buying or learning on it would surprise.)
		if button ~= "LeftButton" and not self.rightClick then return end
		if self.onClick then self.onClick(button, self) end
	end)
	return r
end

local function FitThumb(d)
	local scroll, thumb = d.scroll, d.thumb
	local range = scroll:GetVerticalScrollRange() or 0
	local h = scroll:GetHeight()
	if range <= 0.5 or h <= 0 then thumb:Hide() return end
	local size = math.max(24, h * h / (h + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -3, -((h - size) * (scroll:GetVerticalScroll() / range)))
	thumb:Show()
end

-- A new doc in `parent` (placed by the caller: d.scroll is the frame to anchor). opts.pad: the
-- page's side margin (14); opts.width: its width, for a doc that's always as wide; opts.redraw: draws
-- its owner again (only that one: not every window and panel of ours) after a change of width;
-- opts.idle: true while that redraw would draw nothing (a folded pane), then it's skipped.
function Doc.New(parent, opts)
	local d = setmetatable({}, D)
	d.pad = opts and opts.pad or 14
	d.fixed = opts and opts.width or nil   -- its width, when it never changes
	d.redraw = opts and opts.redraw or nil
	d.idle = opts and opts.idle or nil
	d.pools, d.waiting, d.y, d.width = {}, {}, 0, 200
	d.state = {}            -- the pages' own memory for this doc (open rows, how many shown...)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(200, 1)
	scroll:SetScrollChild(child)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local to = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
		self:SetVerticalScroll(to)
		FitThumb(d)
	end)
	scroll:SetScript("OnScrollRangeChanged", function() FitThumb(d) end)
	-- (Wider or narrower than the page was drawn at: drawn again, so its text wraps to the new width.)
	scroll:SetScript("OnSizeChanged", function(_, w)
		if not w or w <= 0 then return end
		child:SetWidth(w)
		if d.fixed or not d.drawn or not d.redraw then return end
		-- (Once it settles: a pane sliding open changes width every frame.)
		d.sized = (d.sized or 0) + 1
		local serial = d.sized
		C_Timer.After(0.1, function()
			if serial ~= d.sized or not scroll:IsVisible() then return end
			if d.idle and d.idle() then return end
			if math.abs(scroll:GetWidth() - d.width) >= 1 then d.redraw() end
		end)
	end)
	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	thumb:Hide()
	d.scroll, d.child, d.thumb = scroll, child, thumb
	return d
end

function D:Take(kind, make)
	local p = self.pools[kind]
	if not p then p = { list = {}, used = 0 } self.pools[kind] = p end
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

function D:Begin()
	wipe(self.waiting)
	for _, p in pairs(self.pools) do
		for i = 1, #p.list do p.list[i]:Hide() end
		p.used = 0
	end
	self.y = 8
	-- (A doc of a fixed width uses it: a frame just shown may not have its size laid out yet.)
	local w = self.fixed or self.scroll:GetWidth()
	if w and w > 0 then self.child:SetWidth(w) end
	self.width = self.child:GetWidth()
end

function D:Finish()
	self:Gap(8)
	self.drawn = true
	self.child:SetHeight(math.max(1, self.y))
	local scroll = self.scroll
	local range = scroll:GetVerticalScrollRange() or 0
	if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
	self.thumb:SetColorTexture(API.Accent())
	self.thumb:SetAlpha(0.5)
	FitThumb(self)
end

function D:Top()
	self.scroll:SetVerticalScroll(0)
end

function D:Waiting(itemID)
	return type(itemID) == "number" and self.waiting[itemID] == true
end

function D:Gap(n) self.y = self.y + n end

function D:Line(text, size, ink, indent)
	size = size or "body"
	indent = indent or 0
	local child = self.child
	local fs = self:Take("text:" .. size, function()
		local f = Doc.Text(child, size)
		f:SetJustifyH("LEFT")
		f:SetWordWrap(true)
		return f
	end)
	fs:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad + indent, -self.y)
	fs:SetWidth(self.width - self.pad * 2 - indent)
	fs:SetText(text)
	fs:SetTextColor(Color(ink))
	self.y = self.y + math.ceil(fs:GetStringHeight()) + 4
	return fs
end

function D:Heading(text)
	self:Gap(10)
	self:Line(text, "small", "LABEL")
	self:Gap(2)
end

-- o: icon, left, right, sub, leftInk, rightInk, subInk, indent, onClick(button), tip(tooltip),
-- link (shift-click into chat), marked (a faint accent ground: the one picked), dim (a gray icon),
-- rightClick (onClick hears right clicks too), onDouble(row) (a left double click).
function D:Row(o)
	local child = self.child
	local r = self:Take("row", function() return MakeRow(child) end)
	local indent = o.indent or 0
	local w = self.width - self.pad * 2 + 8 - indent
	r:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad - 4 + indent, -self.y)
	r.onClick, r.tip, r.link, r.rightClick, r.onDouble = o.onClick, o.tip, o.link, o.rightClick, o.onDouble
	if o.marked then
		local ar, ag, ab = API.Accent()
		r.mark:SetColorTexture(ar, ag, ab, 0.14)
		r.mark:Show()
	else
		r.mark:Hide()
	end
	r.icon:ClearAllPoints()
	r.left:ClearAllPoints()
	r.right:ClearAllPoints()
	r.sub:ClearAllPoints()
	local x = 4
	if o.icon then
		r.icon:SetTexture(o.icon)
		r.icon:SetDesaturated(o.dim == true)
		r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -2)
		r.icon:Show()
		x = 26
	else
		r.icon:Hide()
	end
	-- The right text on one line, or wrapped in the right half of the row when it's longer; the left
	-- one wraps in what's left of the row, and the sub line under both across the row. The row is
	-- as tall as they are (one line each: 20, with a sub line: 34).
	local inner = w - x - 4
	r.right:SetWidth(0)
	r.right:SetWordWrap(false)
	r.right:SetText(o.right or "")
	r.right:SetTextColor(Color(o.rightInk or "VALUE"))
	local rw = (o.right and o.right ~= "") and math.ceil(r.right:GetStringWidth()) or 0
	local half = math.floor(inner / 2)
	if rw > half then
		r.right:SetWidth(half)
		r.right:SetWordWrap(true)
		rw = half
	end
	r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
	r.left:SetPoint("TOPLEFT", r, "TOPLEFT", x, -3)
	r.left:SetWidth(math.max(20, inner - (rw > 0 and rw + 8 or 0)))
	r.left:SetText(o.left or "")
	r.left:SetTextColor(Color(o.leftInk or "VALUE"))
	local top = 3 + math.max(math.ceil(r.left:GetStringHeight()), rw > 0 and math.ceil(r.right:GetStringHeight()) or 0)
	local h
	if o.sub then
		r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", x, -(top + 3))
		r.sub:SetWidth(math.max(20, inner))
		r.sub:SetText(o.sub)
		r.sub:SetTextColor(Color(o.subInk or "TEXT"))
		r.sub:Show()
		h = math.max(34, top + 3 + math.ceil(r.sub:GetStringHeight()) + 4)
	else
		r.sub:Hide()
		h = math.max(20, top + 4)
	end
	r:SetSize(w, h)
	self.y = self.y + h + 2
	return r
end

-- A line of DaylightUI buttons, left to right: { { text, onClick, off, width }, ... }.
function D:Buttons(list, indent)
	local child = self.child
	local left = self.pad + (indent or 0)
	local x = left
	local tall = 24          -- the tallest button on this line
	for _, spec in ipairs(list) do
		local b = self:Take("button", function() return API.Button(child, "", 24) end)
		b:SetHeight(24)
		b.text:SetWidth(0)
		b.text:SetWordWrap(false)
		b.text:SetText(spec.text or "")
		if spec.width then b:SetWidth(spec.width) else b.FitWidth(64) end
		-- (Words wider than the page: the button as wide as the page, its words on two lines or more.)
		local most = self.width - self.pad - left
		if most > 40 and b:GetWidth() > most then
			b:SetWidth(most)
			b.text:SetWidth(most - 16)
			b.text:SetWordWrap(true)
			b:SetHeight(math.max(24, math.ceil(b.text:GetStringHeight()) + 10))
		end
		-- (Past the page's edge: on to a new line.)
		if x > left and x + b:GetWidth() > self.width - self.pad then
			x = left
			self.y = self.y + tall + 6
			tall = 24
		end
		tall = math.max(tall, b:GetHeight())
		b:SetPoint("TOPLEFT", child, "TOPLEFT", x, -self.y)
		b:SetScript("OnClick", function() if spec.onClick then spec.onClick() end end)
		b.SetOff(spec.off == true)
		if b.SetActive then b.SetActive(spec.active == true) end
		x = x + b:GetWidth() + 6
	end
	self.y = self.y + tall + 6
end

function D:Bar(value)
	local child = self.child
	local b = self:Take("bar", function()
		local bar = API.Bar(child)
		bar:SetMinMaxValues(0, 1)
		return bar
	end)
	b:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad, -self.y)
	b:SetSize(self.width - self.pad * 2, 8)
	b:SetValue(value or 0)
	self.y = self.y + 14
	return b
end
