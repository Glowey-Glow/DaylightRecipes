-- The title bar's professions (3.1.0): a chip for each of your professions and one for Camping, in
-- the menu's order, each its abbreviation. The one on show is lit in the accent and carries its
-- skill ("Cook 153 / 225"); the others are the abbreviation alone, with the name and skill in the
-- tooltip. A press opens the profession, the way the menu's rows do: they are the same entries
-- (Menu.Entries, WindowMenu.lua) and the same secure button comes over the chip under the mouse
-- (Menu.PlaceCaster: out of a fight it casts the profession's spell; in one the chip's own click
-- asks the game by skill line). A right-click (a controller's Y) opens the profession's More menu:
-- Link to Chat, Unlearn.
-- When they do not all fit between the bar's left edge and the window's buttons, the last ones go
-- behind a "+N" chip that opens the menu with those listed (WindowState.ChipFit: whole chips only,
-- nothing is cut, and the one on show is never among those left out). At the end a "more" chip
-- (three dots) opens the rest of what the menu held: your professions' Link to Chat and Unlearn,
-- your alts, the Cooldowns and Tracking tiles. It carries the dot that says a cooldown is ready.
-- A profession with no abbreviation here (one this client adds) shows its icon alone.
local _, ns = ...
if not ns.ok then return end

local API = ns.API
local Doc = ns.Doc
local State = ns.WinState
local L = ns.L
local Color, Text = Doc.Color, Doc.Text
local W = ns.Win
local Menu = ns.WinMenu

local Chips = {}
ns.WinChips = Chips
W.Chips = Chips

-- The abbreviations, by skill line (the data's lines, ns.LINES, and the gathering ones), and
-- Camping's. Each is a locale key: every language has its own (Locales/*.lua, where a comment says
-- which are the ones players of that language write and which were made up for this bar).
local ABBR = {
	[171] = L["Alch"], [164] = L["BS"], [333] = L["Ench"], [202] = L["Eng"], [182] = L["Herb"],
	[165] = L["LW"], [186] = L["Mine"], [393] = L["Skin"], [197] = L["Tail"], [185] = L["Cook"],
	[129] = L["FA"], [356] = L["Fish"], [40] = L["Pois"],
}
local CAMP_ABBR = L["Camp"]
Chips.ABBR, Chips.CAMP_ABBR = ABBR, CAMP_ABBR

local HEIGHT, PADX, GAP = 22, 5, 3
local ICON = 16
local LEFT = 8                  -- the first chip's place from the header's left edge
local MORE_W = 20               -- the "more" chip's width
Chips.GAP, Chips.LEFT, Chips.MORE_W = GAP, LEFT, MORE_W

local bar                       -- the row: a frame as wide as the chips on show
local chips = {}                -- the chips made so far (reused by place in the row)
local plus, more
local shownList = {}            -- the chips on show now, in order (the tests and the tour)

-- A profession's abbreviation, or nil for one with none here.
function Chips.Abbr(e)
	if e.camp then return CAMP_ABBR end
	local p = e.prof
	if not p then return nil end
	return ABBR[p.line] or ABBR[p.game]
end

local function Lit(c, on, over)
	local ar, ag, ab = API.Accent()
	if on then
		c.back:SetColorTexture(ar, ag, ab, over and 0.30 or 0.22)
		c.text:SetTextColor(ar, ag, ab)
	else
		c.back:SetColorTexture(1, 1, 1, over and 0.14 or 0.06)
		c.text:SetTextColor(Color(over and "VALUE" or "TEXT"))
	end
end

local function Tip(c)
	local e = c.entry
	if not e then return end
	GameTooltip:SetOwner(c, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(e.name or "")
	if (e.sub or "") ~= "" then GameTooltip:AddLine(e.sub, Color("TEXT")) end
	if e.picked then
		if e.prof and e.prof.crafts and W.Own() then GameTooltip:AddLine(L["Shift-click: link to chat"], Color("LABEL")) end
	elseif e.prof and e.prof.crafts then
		GameTooltip:AddLine(L["Click: open"], Color("LABEL"))
	else
		GameTooltip:AddLine(L["Click: show its page"], Color("LABEL"))
	end
	if e.more then GameTooltip:AddLine(L["Right-click: %s"]:format(e.more), Color("LABEL")) end
	GameTooltip:Show()
end

local function Base(parent)
	local c = CreateFrame("Button", nil, parent)
	c:SetHeight(HEIGHT)
	c.back = c:CreateTexture(nil, "BACKGROUND")
	c.back:SetAllPoints()
	c.wash = W.Wash(c, "BORDER", 0.06)
	c.wash:SetAllPoints()
	c.wash:Hide()
	return c
end

local function Chip(i)
	local c = chips[i]
	if c then return c end
	c = Base(bar)
	c.chip = true
	c.text = Text(c, "small")
	c.text:SetWordWrap(false)
	c.text:SetPoint("LEFT", c, "LEFT", PADX, 0)
	c.skill = Text(c, "small")
	c.skill:SetWordWrap(false)
	c.skill:SetPoint("LEFT", c.text, "RIGHT", 5, 0)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(ICON, ICON)
	c.icon:SetPoint("CENTER", c, "CENTER", 0, 0)
	c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	c:SetScript("OnEnter", function(self)
		Lit(self, self.lit, true)
		Tip(self)
		-- (The secure button over it, for one a spell opens: Menu.PlaceCaster.)
		Menu.PlaceCaster(self)
	end)
	c:SetScript("OnLeave", function(self)
		Lit(self, self.lit, false)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	c:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if self.onRight then self.onRight(self) end
			return
		end
		if self.onClick then self.onClick(self) end
	end)
	-- (With the secure button over it the mouse is on that: it keeps the chip's light and tooltip.)
	c.hover = function(self, on)
		Lit(self, self.lit, on)
		if on then Tip(self) elseif GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end
	-- A controller's Y: what a right-click does (Link to Chat, Unlearn).
	c.padMore = function(self) return self.onRight end
	chips[i] = c
	return c
end

-- A chip filled for an entry; its width is c.want.
local function Fill(c, e)
	c.entry, c.lit = e, e.picked == true
	c.cast, c.prof, c.onClick, c.onRight = e.cast, e.prof, e.onClick, e.onRight
	local abbr = Chips.Abbr(e)
	local w
	if abbr then
		c.icon:Hide()
		c.text:SetText(abbr)
		c.text:Show()
		w = PADX + math.ceil(c.text:GetUnboundedStringWidth()) + PADX
		-- (The one on show carries its skill.)
		if c.lit and e.prof and (e.sub or "") ~= "" then
			c.skill:SetText(e.sub)
			c.skill:SetTextColor(Color("VALUE"))
			c.skill:Show()
			w = w + 5 + math.ceil(c.skill:GetUnboundedStringWidth())
		else
			c.skill:Hide()
		end
	elseif e.icon then
		-- (No abbreviation for it: its icon alone, the one its row in the menu has.)
		c.text:Hide()
		c.skill:Hide()
		c.icon:SetTexture(e.icon)
		c.icon:Show()
		w = ICON + 8
	else
		-- (Neither: its whole name, never a cut one.)
		c.icon:Hide()
		c.skill:Hide()
		c.text:SetText(e.name or "?")
		c.text:Show()
		w = PADX + math.ceil(c.text:GetUnboundedStringWidth()) + PADX
	end
	c.want = w
	Lit(c, c.lit, false)
end

local function PlusWidth(n)
	plus.text:SetText(("+%d"):format(n))
	return PADX + math.ceil(plus.text:GetUnboundedStringWidth()) + PADX
end

function Chips.Build(header)
	bar = CreateFrame("Frame", nil, header)
	bar:SetHeight(HEIGHT)
	bar:SetPoint("LEFT", header, "LEFT", LEFT, 0)
	bar:SetWidth(1)
	-- (The window closes or the bar goes: the secure button over a chip goes with it, out of a
	-- fight; in one it was put away as the fight began.)
	bar:SetScript("OnHide", function() Menu.HideCaster() end)
	W.chipBar = bar

	-- "+N": the professions the bar had no room for, in the menu.
	plus = Base(bar)
	plus.text = Text(plus, "small")
	plus.text:SetWordWrap(false)
	plus.text:SetPoint("CENTER", plus, "CENTER", 0, 0)
	plus:SetScript("OnEnter", function(self)
		Lit(self, false, true)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(L["Professions"])
		for _, e in ipairs(self.left or {}) do
			GameTooltip:AddLine((e.sub or "") ~= "" and e.prof and ("%s  %s"):format(e.name, e.sub) or e.name, Color("TEXT"))
		end
		GameTooltip:Show()
	end)
	plus:SetScript("OnLeave", function(self)
		Lit(self, false, false)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	plus:SetScript("OnClick", function(self) Menu.Toggle(self.set, self) end)
	plus:Hide()
	W.chipPlus = plus

	-- "More": three dots. The rest of the menu.
	more = Base(bar)
	more:SetWidth(MORE_W)
	more.text = Text(more, "small")     -- (unused: Lit colors a chip's text)
	more.text:Hide()
	more.dots = {}
	for i = 1, 3 do
		local dot = more:CreateTexture(nil, "ARTWORK")
		dot:SetSize(2, 2)
		dot:SetPoint("CENTER", more, "CENTER", (i - 2) * 4, 0)
		more.dots[i] = dot
	end
	function more.Paint(over)
		Lit(more, false, over)
		local cr, cg, cb
		if over then cr, cg, cb = API.Accent() else cr, cg, cb = Color("LABEL") end
		for _, dot in ipairs(more.dots) do dot:SetColorTexture(cr, cg, cb, 1) end
	end
	-- A ready cooldown: a dot on its corner (the tiles are in its menu).
	more.ready = more:CreateTexture(nil, "OVERLAY")
	more.ready:SetSize(6, 6)
	more.ready:SetPoint("CENTER", more, "TOPRIGHT", -2, -2)
	more.ready:Hide()
	more:SetScript("OnEnter", function(self)
		self.Paint(true)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetText(("%s, %s"):format(L["Link to Chat"], L["Unlearn"]))
		GameTooltip:AddLine(L["Your Alts"], Color("TEXT"))
		GameTooltip:AddLine(L["Cooldowns"], Color("TEXT"))
		GameTooltip:AddLine(L["Tracking"], Color("TEXT"))
		if self.ready:IsShown() then GameTooltip:AddLine(L["Ready to craft"], Color("GOOD")) end
		GameTooltip:Show()
	end)
	more:SetScript("OnLeave", function(self)
		self.Paint(false)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	more:SetScript("OnClick", function(self) Menu.Toggle(nil, self) end)
	more.Paint(false)
	more:Hide()
	W.chipMore = more
end

function Chips.Hide()
	if not bar then return end
	Menu.HideCaster()
	bar:Hide()
end

-- The cooldown dot alone (the cooldowns were read again).
function Chips.PaintReady()
	if not more then return end
	more.ready:SetColorTexture(Color("GOOD"))
	more.ready:SetShown(Menu.CooldownReady())
end

-- The bar drawn in `room` (the width between its left edge and the window's buttons).
function Chips.Paint(room)
	if not bar then return end
	-- (The chips are filled anew, maybe at other places: the secure button comes back with the
	-- next chip the mouse is on.)
	Menu.HideCaster()
	bar:Show()
	local entries = Menu.Entries()
	local widths, open = {}, nil
	for i, e in ipairs(entries) do
		local c = Chip(i)
		Fill(c, e)
		widths[i] = c.want
		if e.picked then open = i end
	end
	for i = #entries + 1, #chips do chips[i]:Hide() end
	local hasMore = Menu.HasMore()
	local list, left = State.ChipFit(widths, open, room - (hasMore and MORE_W + GAP or 0), GAP, PlusWidth)
	local on = {}
	for _, index in ipairs(list) do on[index] = true end
	shownList = {}
	local x = 0
	local function Place(c, w)
		c:ClearAllPoints()
		c:SetPoint("LEFT", bar, "LEFT", x, 0)
		c:SetWidth(w)
		c:Show()
		x = x + w + GAP
		shownList[#shownList + 1] = c
	end
	for _, index in ipairs(list) do Place(chips[index], widths[index]) end
	local set, rest = {}, {}
	for i, e in ipairs(entries) do
		if not on[i] then
			chips[i]:Hide()
			set[e.key] = true
			rest[#rest + 1] = e
		end
	end
	if left > 0 then
		plus.set, plus.left = set, rest
		Lit(plus, false, false)
		Place(plus, PlusWidth(left))
	else
		plus:Hide()
	end
	if hasMore then
		Place(more, MORE_W)
		more.Paint(false)
		Chips.PaintReady()
	else
		more:Hide()
	end
	bar:SetWidth(math.max(1, x - GAP))
	Chips.left = left
end

-- The chips on show now, left to right ("+N" and "more" included), for the tour and the tests.
function Chips.Shown() return shownList end

-- (A controller: a chip is a stop like any button of the window. A on one a spell opens goes
-- through DaylightUI's secure key: Menu.PadCast, the window's padKeys. Y opens its More menu.)
