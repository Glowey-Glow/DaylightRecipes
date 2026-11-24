-- The profession window in Blizzard Style: without Daylight UI, with /glowey > General > Look set to
-- Blizzard Style (Host.lua's "game" look). Host.lua draws the frame, its title bar and the close
-- button (Host.Chrome); this file puts the rest of the window on Blizzard's own art, each piece from
-- the game's FrameXML (Gethe/wow-ui-source, branch "forever"; paths under Interface/AddOns):
--   ground       the profession window's background, "Profession-Background-Template2"
--                (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:68-78)
--   title        the profession's name, as the game's window titles it
--   Roll Up      the minimize / maximize button (Blizzard_SharedXML/Mainline/
--                SharedUIPanelTemplates.xml:1070-1100, 28 x 28 on this client: Camelot/
--                SharedUIPanelTemplates.lua:7-9)
--   tabs, chips  PanelTopTabButtonTemplate's tabs (Host.Tab). Blizzard shows your professions as
--                side tabs with their icons (Camelot/Blizzard_ProfessionsFrame.xml:13-61); the chips
--                stay in the title bar here, as tabs, because the secure button that casts a
--                profession comes over the chip under the mouse (WindowMenu.lua's PlaceCaster).
--                Each is sized as PanelTemplates_TabResize sizes a tab: its words plus 20, never
--                narrower than its two end caps (Mainline/SharedUIPanelTemplates.lua:475-487; the
--                caps are 35 and 37 wide, uiframe-tab-left / -right at their atlas size, xml:951-960),
--                and its words sit where PanelTemplates_SelectTab / DeselectTab put a top tab's
--                (lua:611-641). Narrower, the right cap covered the left one's edge.
--   the shelf    the tab rows stand on InsetFrameTemplate's top edge ("_UI-Frame-InnerTopTile",
--                Mainline/NineSliceLayouts.lua:87), in place of our 1-pixel lines and skill line
--   Details,     UIPanelSquareButton's square, pushed square and highlight (Blizzard_UIPanelTemplates/
--   Swap         Mainline/UIPanelTemplates.xml:39-77); Details carries its left / right arrow
--                (SQUARE_BUTTON_TEXCOORDS, Shared/UIPanelTemplatesShared.lua:50-56), Swap its own icon
--   the list     ProfessionsRecipeListTemplate's ground and inset (Blizzard_ProfessionsTemplates/
--                Blizzard_ProfessionsRecipeList.xml:3-30), its category headers
--                (ListHeaderVisualTemplate, Blizzard_SharedXML/ListTemplates.xml:22-42, with the
--                -/+ of CollapseButtonMixin, ListTemplates.lua:11-16) and its rows' picked and
--                hover art (Blizzard_ProfessionsRecipeList.xml:190-204); the minimal scroll bar
--                (Host.ScrollArt)
--   filters      Can Make and Skill-ups as check boxes (UICheckButtonArtTemplate, Blizzard_SharedXML/
--                Shared/Button/CheckButtonTemplates.xml:42-48), as the game's Filter menu lists its
--                own ("Have Materials", "Has Skill Up")
--   the count    - and + as NumericInputSpinnerTemplate's arrows (Shared/InputBox/
--                InputBoxTemplates.xml:276-345); the box is InputBoxTemplate's (Host's edit box)
--   details      the recipe's frame, "common-insideframe" (Blizzard_ProfessionsTemplates/Camelot/
--                Blizzard_ProfessionsRecipeSchematicForm.xml:4-11)
-- With Daylight UI, or in another look, nothing here draws: every call answers at once.
local _, ns = ...
if not ns.ok then return end

local W = ns.Win
local S = ns.state
local Color = ns.Doc.Color

local Blz = {}
W.Blz = Blz

local function H() return ns.Host end
local function On()
	local h = H()
	return h and h.Blizzard and h.Blizzard() == true or false
end

-- A tab's least width: its two end caps, as PanelTemplates_TabResize takes them (tab.Left:GetWidth()
-- + tab.Right:GetWidth(), Mainline/SharedUIPanelTemplates.lua:486-487): the atlases' own widths,
-- since the caps are put on at their atlas size (xml:951-960). 35 + 37 on this client.
local TAB_TEXT_PAD = 20         -- TAB_SIDES_PADDING (lua:475)
local TEXT_Y, TEXT_Y_ON = 8, 12 -- a top tab's words above its foot: CENTER -8 / -4 on a 32-high tab
                                -- (DeselectTab -(2)-6, SelectTab -(-3)-7: lua:617-620, 636-639; xml:933)
local function Sides()
	if Blz.sides then return Blz.sides end
	local C = rawget(_G, "C_Texture")
	local w = 0
	for _, atlas in ipairs({ "uiframe-tab-left", "uiframe-tab-right" }) do
		local ok, info = false, nil
		if type(C) == "table" and type(C.GetAtlasInfo) == "function" then ok, info = pcall(C.GetAtlasInfo, atlas) end
		local aw = ok and type(info) == "table" and tonumber(info.width) or nil
		if not aw or aw <= 0 then return 35 + 37 end
		w = w + aw
	end
	Blz.sides = w
	return w
end

-- The page tabs' least width (WindowState.TabLayout's minTab), nil in another look.
function Blz.TabMin()
	if not On() then return nil end
	return Sides()
end

-- A title-bar chip (a profession, "+N" or "more") sized and lettered as a top tab. w: its width in
-- the other looks; inner: the width of what it shows (words, icon or dots). Returns its width now.
function Blz.ChipFit(c, w, inner)
	local on = On()
	local padx = W.Chips and W.Chips.PADX or 5
	inner = math.max(0, math.ceil(inner or 0))
	local y = 0
	if on then
		w = math.max(inner + TAB_TEXT_PAD, Sides())
		y = c.lit and TEXT_Y_ON or TEXT_Y
	end
	local x = on and math.floor((w - inner) / 2) or padx
	local at = on and "BOTTOM" or "CENTER"
	if c.text then
		c.text:ClearAllPoints()
		if on or c.chip then
			c.text:SetPoint("LEFT", c, on and "BOTTOMLEFT" or "LEFT", x, y)
		else
			c.text:SetPoint("CENTER", c, "CENTER", 0, 0)
		end
	end
	if c.icon then
		c.icon:ClearAllPoints()
		c.icon:SetPoint("CENTER", c, at, 0, y)
	end
	for i, dot in ipairs(c.dots or {}) do
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", c, at, (i - 2) * 4, y)
	end
	return w
end

-- The room for the chips. In Blizzard Style the window's buttons are up in the title bar, so the
-- row runs the column's width: from the bar's left margin to 10 short of the right edge (where the X
-- stood), less the last tab's right cap reaching 8 past its edge (RightActive, lua:304).
function Blz.ChipRoom(room)
	local close = W.closeButton
	if not (On() and close and close.__bzTitle and W.col) then return room end
	return math.max(room, W.col - (W.Chips and W.Chips.LEFT or 8) - 10 - 8)
end

-- UIPanelSquareButton's art on a header button (Blizzard_UIPanelTemplates/Mainline/
-- UIPanelTemplates.xml:39-77): 26 x 26, its square and pushed square from SquareButtonTextures,
-- the common mouse highlight added over it, and the icon a pixel down-left while held (xml:53-60).
-- icon: the texture that moves (Details: the arrow made here; Swap: its own icon).
local SQUARE = "Interface\\Buttons\\SquareButtonTextures"
local SQUARE_HI = "Interface\\Buttons\\UI-Common-MouseHilight"
local SQUARE_N = { 0.015625, 0.421875, 0.234375, 0.640625 }
local SQUARE_P = { 0.453125, 0.859375, 0.234375, 0.640625 }
local ARROW = { LEFT = { 0.234375, 0.421875, 0.015625, 0.203125 }, RIGHT = { 0.421875, 0.234375, 0.015625, 0.203125 } }
local SQUARE_SIZE, BAR_SIZE = 26, 20

local function SquareState(b)
	local a = b.__blzSq
	if not a then return end
	local down = a.on and a.down and b:IsEnabled()
	a.n:SetShown(a.on and not down)
	a.p:SetShown(a.on and down and true or false)
	a.hi:SetShown(a.on)
	if a.icon then
		a.icon:ClearAllPoints()
		a.icon:SetPoint("CENTER", b, "CENTER", down and -1 or 0, down and -1 or 0)
	end
end

local function Square(b, on, icon)
	local a = b.__blzSq
	if on and not a then
		a = { n = b:CreateTexture(nil, "BACKGROUND", nil, 1), p = b:CreateTexture(nil, "BACKGROUND", nil, 1),
			hi = b:CreateTexture(nil, "HIGHLIGHT") }
		a.n:SetTexture(SQUARE)
		a.n:SetTexCoord(unpack(SQUARE_N))
		a.p:SetTexture(SQUARE)
		a.p:SetTexCoord(unpack(SQUARE_P))
		a.hi:SetTexture(SQUARE_HI)
		a.hi:SetBlendMode("ADD")
		for _, k in ipairs({ "n", "p", "hi" }) do a[k]:SetAllPoints() end
		b:HookScript("OnMouseDown", function(self)
			local x = self.__blzSq
			if x then x.down = true SquareState(self) end
		end)
		b:HookScript("OnMouseUp", function(self)
			local x = self.__blzSq
			if x then x.down = nil SquareState(self) end
		end)
		b.__blzSq = a
	end
	if not a then return false end
	a.on = on and true or false
	a.icon = icon
	local size = a.on and SQUARE_SIZE or BAR_SIZE
	b:SetSize(size, size)
	SquareState(b)
	return a.on
end

-- Details: the square with Blizzard's arrow, right to open the column, left to fold it (our drawn
-- outline out of sight meanwhile).
local function DressDetails(b, on, open)
	local a = b.__blzSq
	if on and not (a and a.arrow) then
		Square(b, true)
		a = b.__blzSq
		a.arrow = b:CreateTexture(nil, "ARTWORK", nil, 1)
		a.arrow:SetTexture(SQUARE)
		a.arrow:SetSize(12, 12)
	end
	if a and a.arrow then
		a.arrow:SetShown(on)
		if on then a.arrow:SetTexCoord(unpack(open and ARROW.LEFT or ARROW.RIGHT)) end
	end
	if a then Square(b, on, a.arrow) end
	for _, t in ipairs(b.bars or {}) do t:SetAlpha(on and 0 or 1) end
end

-- The window's title: the open profession's name, else the plugin's.
local function Title()
	-- (The Blizzard Layout names an alt's or a gathering page there too: WindowLayout.lua.)
	if W.Lay and W.Lay.Active() then return W.Lay.TitleText() end
	if S.mode == "win" and type(S.name) == "string" and S.name ~= "" then return S.name end
	return "Glowey's Recipes"
end

-- Once, with the window built: its title bar, the list's inset and the detail column's frame.
local function Setup()
	local h = H()
	if Blz.ready or not (h and h.Chrome and W.win) then return end
	Blz.ready = true
	h.Chrome(W.win, { title = Title, close = W.closeButton, ground = "Profession-Background-Template2" })
	if W.list and h.Inset then
		local inset = h.Inset(W.list, "Professions-background-summarylist")
		if inset then
			inset:SetPoint("TOPLEFT", W.list, "TOPLEFT", -2, 3)
			inset:SetPoint("BOTTOMRIGHT", W.list, "BOTTOMRIGHT", 2, -3)
			-- (The Blizzard Layout puts its own round the whole list column: WindowLayout.lua.)
			Blz.listInset = inset
		end
	end
	if W.side then
		local frame = W.side:CreateTexture(nil, "BORDER")
		frame:SetPoint("TOPLEFT", W.side, "TOPLEFT", 2, -2)
		frame:SetPoint("BOTTOMRIGHT", W.side, "BOTTOMRIGHT", -2, 2)
		if h.Atlas(frame, "common-insideframe") then Blz.sideFrame = frame else frame:Hide() end
	end
	-- The shelves the tab rows stand on (InsetFrameTemplate's top edge, NineSliceLayouts.lua:87):
	-- under the page tabs, the column wide, and under the chips, from the header's left edge.
	local function Shelf(parent)
		local t = parent:CreateTexture(nil, "BORDER")
		if not h.Atlas(t, "_UI-Frame-InnerTopTile", true) then
			t:Hide()
			return nil
		end
		if t.SetHorizTile then t:SetHorizTile(true) end
		t:SetHeight(3)
		return t
	end
	if W.tabRow then
		Blz.tabShelf = Shelf(W.tabRow)
		if Blz.tabShelf then
			Blz.tabShelf:SetPoint("TOPLEFT", W.tabRow, "BOTTOMLEFT", 0, 0)
			Blz.tabShelf:SetPoint("TOPRIGHT", W.tabRow, "BOTTOMRIGHT", 0, 0)
		end
	end
	local bar = W.chipBar
	if bar and bar:GetParent() then
		Blz.chipShelf = Shelf(bar:GetParent())
		if Blz.chipShelf then
			Blz.chipShelf:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -(W.Chips and W.Chips.LEFT or 8), 0)
		end
	end
	-- (Every part again when the look changes; a reload shows the rest of the window's colors.)
	if h.Looked then h.Looked(Blz, function() if W.win and W.win:IsShown() and ns.Window then ns.Window.Render() end end) end
end

-- Each render: the title, the tabs, Roll Up, Details, Swap, the count's arrows, the shelves and the
-- detail column's frame. expanded: the detail column open.
function Blz.Paint(rolled, expanded)
	local h = H()
	if not (h and h.Blizzard) then return end
	Setup()
	local on = On()
	if h.Retitle then h.Retitle(W.win) end
	for _, b in ipairs(W.tabButtons or {}) do
		if b:IsShown() then
			local picked = b.key == W.tab
			local drawn = h.Tab(b, picked, { b.line })
			-- (The words where Blizzard's top tab has them: centered in the art that shows.)
			b.text:ClearAllPoints()
			if drawn then
				b.text:SetPoint("CENTER", b, "BOTTOM", 0, picked and TEXT_Y_ON or TEXT_Y)
			else
				b.text:SetPoint("CENTER", 0, 1)
			end
		end
	end
	-- Ours out of sight meanwhile: the 1-pixel lines under the header and the tab row, and the skill
	-- line (the chip on show reads the skill: "Mine 101 / 150").
	for _, region in ipairs({ W.headUnder, W.skillBack, W.skillLine, W.tabUnder }) do
		region:SetAlpha(on and 0 or 1)
	end
	if Blz.tabShelf then Blz.tabShelf:SetShown(on) end
	if Blz.chipShelf then
		local bar = W.chipBar
		Blz.chipShelf:SetShown(on and bar ~= nil and bar:IsShown())
		Blz.chipShelf:SetWidth(math.max(1, W.col or 1))
	end
	local roll = W.rollButton
	if roll then
		-- (The red button's own size, as the X beside it: the gaps between them even.)
		roll:SetSize(on and 28 or 20, on and 28 or 20)
		h.Dress(roll, rolled and "maximize" or "minimize", roll.bars, 28)
	end
	if W.detailsButton then DressDetails(W.detailsButton, on, expanded) end
	local swap = W.win and W.win.swapButton
	if swap and (on or swap.__blzSq) then Square(swap, on, swap.icon) end
	local cb = W.craftBar
	if cb and cb.minus and cb.plus then
		h.Dress(cb.minus, "prev")
		h.Dress(cb.plus, "next")
	end
	if Blz.sideFrame then Blz.sideFrame:SetShown(on) end
end

-- A recipe list row (e nil: a row put away).
function Blz.Row(r, e)
	local h = H()
	if not (h and h.Atlas) then return end
	local on = On() and e ~= nil
	local a = r.__blz
	if on and not a then
		a = {}
		a.head = r:CreateTexture(nil, "BACKGROUND", nil, 1)
		a.head:SetAllPoints()
		h.Atlas(a.head, "common-button-list-collapseExpand")
		a.headHi = r:CreateTexture(nil, "HIGHLIGHT")
		a.headHi:SetAllPoints()
		h.Atlas(a.headHi, "common-button-list-collapseExpand")
		a.headHi:SetBlendMode("ADD")
		a.headHi:SetAlpha(0.4)
		a.fold = r:CreateTexture(nil, "ARTWORK")
		a.fold:SetPoint("CENTER", r, "RIGHT", -16, 0)
		a.sel = r:CreateTexture(nil, "BACKGROUND", nil, 2)
		a.sel:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
		a.sel:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, -1)
		h.Atlas(a.sel, "Professions_Recipe_Active")
		a.hover = r:CreateTexture(nil, "HIGHLIGHT")
		a.hover:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -1)
		a.hover:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, -1)
		h.Atlas(a.hover, "Professions_Recipe_Hover")
		a.hover:SetAlpha(0.5)
		r.__blz = a
	end
	if not a then return end
	local cat = on and e.cat ~= nil
	local recipe = on and not cat
	a.head:SetShown(cat)
	a.headHi:SetShown(cat)
	a.fold:SetShown(cat)
	a.sel:SetShown(recipe and e.spell == S.recipe)
	a.hover:SetShown(recipe)
	-- Ours out of sight meanwhile: the sign, the picked row's wash and the hover wash.
	r.sign:SetAlpha(cat and 0 or 1)
	r.ground:SetAlpha(on and 0 or 1)
	r.wash:SetAlpha(on and 0 or 1)
	r.right:ClearAllPoints()
	if cat then
		h.Atlas(a.fold, e.fold and "common-button-list-plus" or "common-button-list-minus", true)
		r.name:ClearAllPoints()
		r.name:SetPoint("LEFT", r, "LEFT", 8, 0)
		r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
		r.right:SetPoint("RIGHT", r, "RIGHT", -30, 0)
	else
		r.right:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	end
end

-- The list's thumb: the game's own scroll bar in its place (Host.ScrollArt), its own color
-- hidden. ctl: how it scrolls (the list's rows from an offset: WindowList.lua's ScrollCtl).
function Blz.Thumb(thumb, list, ctl)
	local h = H()
	if not (h and h.ScrollArt) then return end
	if h.ScrollArt(thumb, list, 3.5, ctl) then thumb:SetAlpha(0) end
end

-- Can Make / Skill-ups: a check box before the word.
local CHECK_UP, CHECK_ON = "Interface\\Buttons\\UI-CheckBox-Up", "Interface\\Buttons\\UI-CheckBox-Check"
local CHECK_HI = "Interface\\Buttons\\UI-CheckBox-Highlight"
function Blz.Toggle(b, on)
	local bz = On()
	local box = b.__blzBox
	if bz and not box then
		box = { up = b:CreateTexture(nil, "BACKGROUND"), check = b:CreateTexture(nil, "ARTWORK"),
			hi = b:CreateTexture(nil, "HIGHLIGHT") }
		box.up:SetTexture(CHECK_UP)
		box.check:SetTexture(CHECK_ON)
		box.hi:SetTexture(CHECK_HI)
		box.hi:SetBlendMode("ADD")
		for _, t in pairs(box) do
			t:SetSize(22, 22)
			t:SetPoint("LEFT", b, "LEFT", -2, 0)
		end
		b.__blzBox = box
	end
	if box then
		box.up:SetShown(bz)
		box.hi:SetShown(bz)
		box.check:SetShown(bz and on and true or false)
	end
	b.line:SetAlpha(bz and 0 or 1)
	b.text:ClearAllPoints()
	if bz then
		b.text:SetPoint("LEFT", b, "LEFT", 20, 1)
		b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
		b:SetWidth(math.ceil(b.text:GetStringWidth()) + 26)
	else
		b.text:SetPoint("CENTER", 0, 1)
	end
end

-- A profession chip as a top tab, the one on show selected (gold words, white on the picked one).
function Blz.Chip(c, on, over)
	local h = H()
	if not (h and h.Tab) then return end
	if h.Tab(c, on, { c.back }) and c.text then
		c.text:SetTextColor(Color((on or over) and "VALUE" or "LABEL"))
	end
end
