-- A scrolling page drawn from pooled pieces, top to bottom: lines of text, rows (icon, left and
-- right text, a line under them, a hover wash when they do something), buttons, pickers and bars.
-- The docked pane and the window each draw their pages on one of these; the pages themselves are
-- in Pages.lua. Also the small helpers every page uses (colors, item names, tooltips, percentages).
-- One grid for every page (design\facelift.md, principle 6): type sizes 10 / 12 / 13 / 15 / 18
-- only (Doc.SIZES), edge padding 14, rows 20 (one line) and 34 (two lines), buttons 24 tall.
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

-- A chance's own color: the bad red at none, the title gold at half, the good green at a sure
-- thing (the skill-up chance's percent and its bar, Pages.Skill).
function Doc.ChanceColor(v)
	v = math.max(0, math.min(1, tonumber(v) or 0))
	local lo, hi, t
	if v < 0.5 then lo, hi, t = "BAD", "TITLE", v * 2 else lo, hi, t = "TITLE", "GOOD", (v - 0.5) * 2 end
	local r1, g1, b1 = Color(lo)
	local r2, g2, b2 = Color(hi)
	return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
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

-- A row with a Shift action (o.shift = { text, tip, run }: the strips' "Remove", Shop.lua). While
-- Shift is held with the mouse on the row, its right text reads shift.text in the warning ink and
-- its tooltip gains shift.tip; a Shift-click runs shift.run and nothing else of the row.
-- (IsShiftKeyDown() -> bool: Blizzard_APIDocumentationGenerated/InputDocumentation.lua:236-242.)
local function ShiftHeld(r)
	return r.shift ~= nil and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true
end

-- The row's tooltip, shown anew (also when Shift goes down or up over it).
local function RowTip(r)
	local held = r.hovered and ShiftHeld(r)
	if not (r.tip or held) then
		if GameTooltip:IsOwned(r) then GameTooltip:Hide() end
		return
	end
	GameTooltip:SetOwner(r, "ANCHOR_LEFT")
	if r.tip then pcall(r.tip, GameTooltip) end
	if held and r.shift.tip then GameTooltip:AddLine(r.shift.tip, Color("WARN")) end
	GameTooltip:Show()
end

-- The row's right text as it reads now: the Shift action's word while Shift is held over it
-- (Shift wins), else its hover hint (o.hover = { text, ink }: what a press does, the Auction House
-- strip's "Left Click to Search") while the mouse, or a controller's cursor, is on it, else its
-- own. D:Row keeps room for the longest of the three beside the left text, so none of them ever
-- runs into it or is cut.
local function RowFace(r)
	local face
	if r.hovered then
		if ShiftHeld(r) then face = "shift" elseif r.hover then face = "hover" end
	end
	if face == r.face then return end
	r.face = face
	if face then
		local alt = face == "shift" and r.shift or r.hover
		r.right:SetWidth(0)
		r.right:SetWordWrap(false)
		r.right:SetText(alt.text or "")
		r.right:SetTextColor(Color(face == "shift" and "WARN" or alt.ink or "ACCENT"))
	else
		r.right:SetWidth(r.rightW or 0)
		r.right:SetWordWrap(r.rightWrap == true)
		r.right:SetText(r.rightText or "")
		r.right:SetTextColor(Color(r.rightInk or "VALUE"))
	end
end

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
		self.hovered = true
		if self.onClick or self.onDouble or self.tip or self.shift or self.hover then self.wash:Show() end
		-- (A controller: the right stick scrolls the page this row is on. Guide.lua's Pad)
		if ns.Pad then ns.Pad.Into(self, child:GetParent()) end
		-- (Shift going down or up while the mouse is here: MODIFIER_STATE_CHANGED(key, down),
		-- KeyBindingsDocumentation.lua:158-166. Heard only while the mouse is on a row that has a
		-- Shift action.)
		if self.shift then pcall(self.RegisterEvent, self, "MODIFIER_STATE_CHANGED") end
		RowFace(self)
		RowTip(self)
	end)
	local function Left(self)
		self.hovered = false
		pcall(self.UnregisterEvent, self, "MODIFIER_STATE_CHANGED")
		self.wash:Hide()
		RowFace(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end
	r:SetScript("OnLeave", Left)
	r:SetScript("OnHide", Left)
	r:SetScript("OnEvent", function(self)
		if not self.hovered then return end
		RowFace(self)
		RowTip(self)
	end)
	r:SetScript("OnDoubleClick", function(self, button)
		if ShiftHeld(self) then return end
		if button == "LeftButton" and self.onDouble then self.onDouble(self) end
	end)
	r:SetScript("OnClick", function(self, button)
		-- (A Shift-click on a row with a Shift action is that action and nothing else: it never
		-- reaches the row's own press, with either mouse button. Such rows carry no link, so the
		-- chat-link Shift-click below has nothing to do on them.)
		if ShiftHeld(self) then
			if button == "LeftButton" and self.shift.run then self.shift.run() end
			return
		end
		-- (Shift-click a row with an item or recipe link: into the open chat box.)
		if IsModifiedClick("CHATLINK") and self.link then
			ns.InsertLink(self.link)
			return
		end
		-- (A right click only acts on rows that want one: buying or learning on it would surprise.)
		if button ~= "LeftButton" and not self.rightClick then return end
		if self.onClick then self.onClick(button, self) end
	end)
	-- A controller's Y: what a right-click does on a row that wants one (the queue's Move / Remove).
	r.padMore = function(self)
		if not (self.rightClick and self.onClick) then return nil end
		return function() self.onClick("RightButton", self) end
	end
	return r
end

local function FitThumb(d)
	local scroll, thumb = d.scroll, d.thumb
	-- (A page that never scrolls has no thumb, whatever the scroll frame thinks its range is.)
	-- (Blizzard Style without Daylight UI: the game's own scroll bar, MinimalScrollBar, in its
	-- place: arrows, a thumb to drag, a track to click. Host.ScrollArt.)
	local H = ns.Host
	local function Art()
		if H and H.ScrollArt then thumb:SetAlpha(H.ScrollArt(thumb, scroll, 5) and 0 or 1) end
	end
	if d.still then
		thumb:Hide()
		Art()
		return
	end
	local range = scroll:GetVerticalScrollRange() or 0
	local h = scroll:GetHeight()
	if range <= 0.5 or h <= 0 then thumb:Hide() Art() return end
	local size = math.max(24, h * h / (h + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -3, -((h - size) * (scroll:GetVerticalScroll() / range)))
	thumb:Show()
	Art()
end

-- A new doc in `parent` (placed by the caller: d.scroll is the frame to anchor). opts.pad: the
-- page's side margin (14); opts.width: its width, for a doc that's always as wide; opts.redraw: draws
-- its owner again (only that one: not every window and panel of ours) after a change of width;
-- opts.idle: true while that redraw would draw nothing (a folded pane), then it's skipped.
-- opts.still: a plain area that never scrolls (a list's head, Shop.lua): no wheel, no thumb, and
-- its child exactly as tall as what was drawn (Finish adds no foot to it), so its owner can make
-- the frame that tall and nothing of it is ever out of sight.
function Doc.New(parent, opts)
	local d = setmetatable({}, D)
	d.still = opts and opts.still == true or nil
	d.marks = {}            -- where each piece drawn ends (d.y after it): a page cut there cuts no row
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
	scroll:EnableMouseWheel(not d.still)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		if d.still then return end
		local range = self:GetVerticalScrollRange() or 0
		local to = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
		self:SetVerticalScroll(to)
		FitThumb(d)
	end)
	scroll:SetScript("OnScrollRangeChanged", function() FitThumb(d) end)
	-- (Scrolled by a controller: its right stick, or its cursor moving to a row out of sight.)
	scroll:SetScript("OnVerticalScroll", function() FitThumb(d) end)
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
	wipe(self.marks)
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
	if not self.still then self:Gap(8) end
	self.drawn = true
	self.child:SetHeight(math.max(1, self.y))
	local scroll = self.scroll
	if self.still then
		scroll:SetVerticalScroll(0)
		self.thumb:Hide()
		return
	end
	local range = scroll:GetVerticalScrollRange() or 0
	if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
	self.thumb:SetColorTexture(API.Accent())
	self.thumb:SetAlpha(0.5)
	FitThumb(self)
end

-- The Leveling Guide's glow (its current step's card, and its recipe in the recipe list): DaylightUI's
-- own glow (API.GlowAround, DaylightUI 1.8.4 and later) in the style the player picked for its main
-- buttons. False while it's off: our option, that style set to None, or a DaylightUI without it.
-- (DaylightUI keeps it away by itself while the player has its motion off.)
function Doc.GlowStyle()
	if ns.Get("guideGlow") == false or type(API.GlowAround) ~= "function" then return false end
	local ok, style = pcall(API.GetSetting, "general", "buttonGlow")
	if not ok or style == "none" then return false end
	return type(style) == "string" and style or "circle"
end

-- A frame's glow on or off; r, g, b: in that color (the recipe's skill-up color: the best craft's
-- box in the list and round the guide's step, as its arrow), else the look's. Called again only
-- when that changes (or the style or color does), so a page drawn again doesn't start its light over.
local glowing = setmetatable({}, { __mode = "k" })
function Doc.Glow(frame, on, r, g, b)
	if type(API.GlowAround) ~= "function" then return end
	local style = on and Doc.GlowStyle() or false
	local key = style and (r and ("%s %.3f %.3f %.3f"):format(style, r, g, b) or style) or false
	if (glowing[frame] or false) == key then return end
	glowing[frame] = key
	if style then
		API.GlowAround(frame, true, { style = style, r = r, g = g, b = b })
	else
		API.GlowAround(frame, false)
	end
end

-- A light round the part of the page from `top` (a d.y taken before it was drawn) down to here.
function D:GlowFrom(top, r, g, b)
	if not Doc.GlowStyle() then return end
	local child = self.child
	local box = self:Take("glow", function()
		local f = CreateFrame("Frame", nil, child)
		f:EnableMouse(false)
		return f
	end)
	box:SetFrameLevel(child:GetFrameLevel() + 20)
	box:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad - 8, -top)
	box:SetSize(math.max(1, self.width - self.pad * 2 + 16), math.max(1, self.y - top))
	Doc.Glow(box, true, r, g, b)
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
	self.marks[#self.marks + 1] = self.y
	return fs
end

function D:Heading(text)
	self:Gap(10)
	self:Line(text, "small", "LABEL")
	self:Gap(2)
end

-- o: icon, left, right, sub, leftInk, rightInk, subInk, indent, onClick(button), tip(tooltip),
-- link (shift-click into chat), marked (a faint accent ground: the one picked), dim (a gray icon),
-- rightClick (onClick hears right clicks too), onDouble(row) (a left double click),
-- shift = { text, tip, run } (a Shift action: above MakeRow), hover = { text, ink } (a hint in the
-- right text's place while the mouse is on the row: RowFace).
function D:Row(o)
	local child = self.child
	local r = self:Take("row", function() return MakeRow(child) end)
	local indent = o.indent or 0
	local w = self.width - self.pad * 2 + 8 - indent
	r:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad - 4 + indent, -self.y)
	r.onClick, r.tip, r.link, r.rightClick, r.onDouble = o.onClick, o.tip, o.link, o.rightClick, o.onDouble
	r.shift = type(o.shift) == "table" and o.shift or nil
	r.hover = type(o.hover) == "table" and o.hover or nil
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
	-- (The words that can stand in the right text's place, each on one line: the widest of them
	-- and the right text is the room kept, so the left text is laid out clear of all of them.)
	local alt = 0
	if r.hover and r.hover.text then
		r.right:SetText(r.hover.text)
		alt = math.max(alt, math.ceil(r.right:GetStringWidth() or 0))
	end
	if r.shift and r.shift.text then
		r.right:SetText(r.shift.text)
		alt = math.max(alt, math.ceil(r.right:GetStringWidth() or 0))
	end
	r.right:SetText(o.right or "")
	r.right:SetTextColor(Color(o.rightInk or "VALUE"))
	local rw = (o.right and o.right ~= "") and math.ceil(r.right:GetStringWidth()) or 0
	local half = math.floor(inner / 2)
	local wrapped = false
	if rw > half then
		r.right:SetWidth(half)
		r.right:SetWordWrap(true)
		rw = half
		wrapped = true
	end
	r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
	r.left:SetPoint("TOPLEFT", r, "TOPLEFT", x, -3)
	local room = math.max(rw, alt)
	r.left:SetWidth(math.max(20, inner - (room > 0 and room + 8 or 0)))
	-- (Kept for the words that take the right text's place and give it back: RowFace.)
	r.rightText, r.rightInk = o.right or "", o.rightInk
	r.rightW, r.rightWrap = wrapped and half or 0, wrapped
	r.face = nil
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
	self.marks[#self.marks + 1] = self.y
	-- (Drawn again under the mouse with Shift held: the Shift action's word is back at once.)
	if r.hovered then
		RowFace(r)
		if GameTooltip:IsOwned(r) then RowTip(r) end
	end
	return r
end

-- A line of DaylightUI buttons, left to right: { { text, onClick, off, width, active (lit), min
-- (the least width of one sized to its words: 64) }, ... }. One past the page's edge goes on a new line.
-- opts (for a line of small chips: the strips' list pair and profession tags, Shop.lua):
-- height (24), gap (6: between two buttons, and under the line), pad (a button sized to its words
-- is that much wider than them; without it, DaylightUI's own fit: 32).
function D:Buttons(list, indent, opts)
	local child = self.child
	local left = self.pad + (indent or 0)
	local x = left
	local high = opts and opts.height or 24
	local gap = opts and opts.gap or 6
	local pad = opts and opts.pad or nil
	local tall = high          -- the tallest button on this line
	for _, spec in ipairs(list) do
		local b = self:Take("button", function() return API.Button(child, "", 24) end)
		b:SetHeight(high)
		b.text:SetWidth(0)
		b.text:SetWordWrap(false)
		b.text:SetText(spec.text or "")
		if spec.width then
			b:SetWidth(spec.width)
		elseif pad then
			b:SetWidth(math.max(spec.min or 0, math.ceil(b.text:GetStringWidth() or 0) + pad))
		else
			b.FitWidth(spec.min or 64)
		end
		-- (Words wider than the page: the button as wide as the page, its words on two lines or more.)
		local most = self.width - self.pad - left
		if most > 40 and b:GetWidth() > most then
			b:SetWidth(most)
			b.text:SetWidth(most - 16)
			b.text:SetWordWrap(true)
			b:SetHeight(math.max(high, math.ceil(b.text:GetStringHeight()) + 10))
		end
		-- (Past the page's edge: on to a new line.)
		if x > left and x + b:GetWidth() > self.width - self.pad then
			x = left
			self.y = self.y + tall + gap
			tall = high
		end
		tall = math.max(tall, b:GetHeight())
		b:SetPoint("TOPLEFT", child, "TOPLEFT", x, -self.y)
		b:SetScript("OnClick", function() if spec.onClick then spec.onClick() end end)
		b.SetOff(spec.off == true)
		if b.SetActive then b.SetActive(spec.active == true) end
		x = x + b:GetWidth() + gap
	end
	self.y = self.y + tall + gap
end

-- A small arrow pointing down, drawn from three bars (ours: no art of the game's or DaylightUI's),
-- for a button that opens a menu.
function Doc.Chevron(parent)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(7, 6)
	holder.bars = {}
	for i = 1, 3 do
		local bar = holder:CreateTexture(nil, "OVERLAY")
		bar:SetSize(9 - i * 2, 2)
		bar:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * 2)
		holder.bars[i] = bar
	end
	-- (Host.Tint: drawn again in the new colors after a look change; "ACCENT" is its "pop".)
	function holder.Paint(ink)
		local role = ink == "ACCENT" and "pop" or ink or "LABEL"
		for _, bar in ipairs(holder.bars) do ns.Host.Tint(bar, role, 1) end
	end
	holder.Paint()
	return holder
end

local function MakePicker(child)
	local p = CreateFrame("Frame", nil, child)
	p.label = Doc.Text(p, "small")
	p.label:SetJustifyH("LEFT")
	p.label:SetWordWrap(false)
	p.button = API.Button(p, "", 24)
	p.button.text:ClearAllPoints()
	p.button.text:SetPoint("LEFT", p.button, "LEFT", 12, 0)
	p.button.text:SetJustifyH("LEFT")
	p.chevron = Doc.Chevron(p.button)
	p.chevron:SetPoint("RIGHT", p.button, "RIGHT", -10, 0)
	return p
end

-- A line of pickers, left to right: a label and a button showing the choice, which opens
-- DaylightUI's own menu under it (API.Menu: DaylightUI/API.md, "Look like Daylight UI").
-- list: { { label, keys, values, current, onPick(key) }, ... } (keys, values as API.Menu takes).
-- Each button is as wide as its choice's words; a picker that doesn't fit beside the last goes on
-- a new line, and one wider than the page puts its label above its button; a choice whose words
-- are wider than the page even then wraps inside its button, which grows as tall as they need
-- (the button's look is anchored to its edges and follows: DaylightUI/Options/Widgets.lua:420-436).
-- Nothing is cut.
function D:Pickers(list, indent)
	local child = self.child
	local left = self.pad + (indent or 0)
	local most = self.width - self.pad
	local x, tall = left, 24
	for _, spec in ipairs(list) do
		local p = self:Take("picker", function() return MakePicker(child) end)
		p.label:SetText(spec.label or "")
		p.label:SetTextColor(Color("LABEL"))
		p.button.text:SetWidth(0)
		p.button.text:SetWordWrap(false)
		p.button:SetHeight(24)
		p.button.text:SetText(spec.values[spec.current] or "")
		-- (The button: 12 before its words, 8 between them and the arrow, the arrow's 7, 10 after.)
		local bw = math.max(56, math.ceil(p.button.text:GetStringWidth()) + 12 + 8 + 7 + 10)
		local lw = math.ceil(p.label:GetStringWidth())
		local w, h = lw + 6 + bw, 24
		local stacked = w > most - left
		p.label:ClearAllPoints()
		p.button:ClearAllPoints()
		if stacked then
			-- (Wider than the page: the label above, the button under it, as wide as the page at most.)
			local bh = 24
			if bw > most - left then
				bw = most - left
				-- (Its words in the room the button has for them, on as many lines as they need.)
				p.button.text:SetWidth(math.max(20, bw - (12 + 8 + 7 + 10)))
				p.button.text:SetWordWrap(true)
				bh = math.max(24, math.ceil(p.button.text:GetStringHeight()) + 10)
				p.button:SetHeight(bh)
			end
			w, h = math.max(lw, bw), bh + 16
			p.label:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
			p.button:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
		else
			p.label:SetPoint("LEFT", p, "LEFT", 0, 0)
			p.button:SetPoint("LEFT", p.label, "RIGHT", 6, 0)
		end
		p.button:SetWidth(bw)
		if x > left and x + w > most then
			x = left
			self.y = self.y + tall + 6
			tall = 24
		end
		tall = math.max(tall, h)
		p:SetSize(w, h)
		p:SetPoint("TOPLEFT", child, "TOPLEFT", x, -self.y)
		p.button:SetScript("OnClick", function(owner)
			API.Menu(owner, spec.keys, spec.values, spec.current, function(key)
				if spec.onPick then spec.onPick(key) end
			end)
		end)
		x = x + w + 14
	end
	self.y = self.y + tall + 6
end

-- A bar of the look; r, g, b: its fill in that color instead (the skill-up chance's, Pages.Skill:
-- those come from a pool of their own, so the look's bars keep the look's fill).
function D:Bar(value, r, g, b)
	local child = self.child
	local inked = r ~= nil
	local bar = self:Take(inked and "bar-ink" or "bar", function()
		local made = API.Bar(child)
		made:SetMinMaxValues(0, 1)
		return made
	end)
	if inked and bar.SetStatusBarColor then bar:SetStatusBarColor(r, g, b) end
	-- (Blizzard Style: the profession window's own bar, 14 high, its border reaching 2 past its
	-- ends, ProfessionsStatusBarArtTemplate: Host.lua's A.Bar. Another look: a thin 8.)
	local H = ns.Host
	local bz = H and H.Blizzard and H.Blizzard() == true
	local tall = bz and 14 or 8
	local inset = bz and 3 or 0
	bar:SetPoint("TOPLEFT", child, "TOPLEFT", self.pad + inset, -self.y)
	bar:SetSize(self.width - self.pad * 2 - inset * 2, tall)
	bar:SetValue(value or 0)
	self.y = self.y + tall + 6
	return bar
end
