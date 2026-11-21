-- Glowey's Recipes' profession window: in place of the game's (and DaylightUI's) while it's the one
-- chosen (Take.lua holds the game's out of sight; it keeps running the trade skill).
-- The Compact Window (design\facelift.md, direction A), one column at the left of the screen:
--   Header 36: the profession's icon and name (the name is a menu: your professions, Camping, your
--              alts, Cooldowns and Tracking; WindowMenu.lua), its skill as "187 / 225" with a 2 px
--              skill line along the header's foot, then Details, Roll Up, the swap button and the X.
--   Tabs 28:   Recipes, Leveling Guide, Materials, Queue (3), Missing.
--   Body:      the tab's page in one column (the recipe list is WindowList.lua's; the other pages
--              are drawn on docs, Doc.lua, from Pages.lua).
--   Foot:      the picked recipe in one line, and the craft bar (WindowList.lua).
-- Its three states (WindowState.lua has the rules, the tests check them):
--   Compact    the column alone: 420 x 560 by default, 400 to 720 tall (drag its bottom edge, or
--              the Window Height setting), as wide as its tab row needs (520 at most)
--   Expanded   the 360 detail column slid out of its right edge (the Details button, a press on
--              the summary line, Y on a controller); open or closed is remembered per tab
--   Rolled Up  the header and the craft bar only (420 x 80, a line more with the picked recipe's
--              name): what the bar acts on (a run, the queue's next, else the pick), and Stop
-- Opening a profession opens it in the state it was left; everything is remembered in
-- DaylightRecipesDB.win. It is an ordinary frame: nothing here is protected, the game's panel
-- layout is never written to (no SetUIPanelAttribute: see Take.lua), and the secure Stop is never
-- its child or anchored to it (Craft.lua), so it moves, resizes, rolls up and closes in a fight.
-- luacheck: read globals GetCursorPosition
local ADDON, ns = ...
if not ns.ok then return end

local API = ns.API
local Doc, Pages, Craft = ns.Doc, ns.Pages, ns.Craft
local State, List, Menu = ns.WinState, ns.WinList, ns.WinMenu
local S = ns.state
local L = ns.L
local Color, Text = Doc.Color, Doc.Text
local Pad = ns.Pad     -- the window on a controller (Guide.lua)
local W = ns.Win
local DB, Linked = W.DB, W.Linked

local Window = {}
ns.Window = Window

local HEADER, PAD = State.HEADER, State.PAD
local win, header, col, tabRow, body, side
local tabButtons, tabOf = {}, {}
local detail, pageDoc, pageSearch, altDoc
local want = "recipes"     -- the tab asked for (the one shown is W.tab: a handed-off one gives way)
local liveHeight           -- the height while its edge is dragged
local slideW               -- the width while the detail column slides
local missingPick          -- the missing recipe shown in the detail column (its spell)

local function TS(name, ...)
	return Craft.TS(name, ...)
end

-- The window's scale: the "Window Size" setting, made smaller when the widest state wouldn't fit
-- on the screen at it (a large setting with a large UI scale), so no part of it is ever off screen.
local function Scale()
	local s = ns.Get("winScale") or 1
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if sw and sw > 0 and sh and sh > 0 then
		s = math.min(s, sw / (W.col + State.DETAIL), sh / State.MIN_H)
	end
	return s
end

-- Its height: while its edge is dragged, else the Window Height setting (Core.lua; the drag sets
-- it), within the limits and the screen.
local function Height()
	local h = liveHeight or ns.Get("winHeight") or State.H
	local sh = UIParent:GetHeight()
	return State.ClampHeight(h, sh and sh > 0 and sh / Scale() or nil)
end

local function Other() return W.alt ~= nil or W.gather ~= nil end

-- (Rolled up only while there is a craft bar to roll up to and no tour is showing the window:
-- W.Rolled, WindowList.lua.)
local function Mode()
	return State.Mode(DB(), W.tab, Other(), ns.Get("detailsDefault") == true, W.Rolled())
end

function Window.Width() return (win and win:GetWidth() or W.col) * Scale() end
function Window.Shown() return win ~= nil and win:IsShown() end
function Window.Mode() return Mode() end

-- Professionally Lost has this profession's Leveling Guide (ProfLost.lua; guarded: the file may
-- be absent, and its answer changes the moment the player flips the hand-off).
local function Handed()
	local PL = ns.ProfLost
	if not (PL and PL.Handed) or not W.Own() then return false end
	return PL.Handed("guide", S.line) == true
end

-- ---------------------------------------------------------------------------------------------
-- Small drawn pieces (ours: bars of flat color, no art of the game's or DaylightUI's)
-- ---------------------------------------------------------------------------------------------

-- A header button: 20 x 20, its glyph drawn by `draw(b, r, g, b, a)` from flat bars; label ink at
-- rest, the accent under the mouse, its name after the mouse rests (and on a controller's hint
-- bar: the window's padKeys).
local function IconButton(parent, name, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	b.bars = {}
	function b.Bar(i)
		local t = b.bars[i]
		if not t then
			t = b:CreateTexture(nil, "ARTWORK")
			b.bars[i] = t
		end
		t:ClearAllPoints()
		t:Show()
		return t
	end
	function b.Paint(over)
		local r, g, bl
		if over then r, g, bl = API.Accent() else r, g, bl = Color("LABEL") end
		for _, t in ipairs(b.bars) do t:SetColorTexture(r, g, bl, t.faint and 0.35 or 1) end
	end
	b:SetScript("OnEnter", function(self)
		self.Paint(true)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(name) == "function" and name() or name, 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.Paint(false)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", onClick)
	return b
end

-- Details: a window outline with its right column filled while the details are open.
local function DrawDetails(b, open)
	for _, t in ipairs(b.bars) do t:Hide() end
	local top, bottom, left, right = b.Bar(1), b.Bar(2), b.Bar(3), b.Bar(4)
	top:SetSize(12, 1)
	top:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -5)
	bottom:SetSize(12, 1)
	bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 5)
	left:SetSize(1, 10)
	left:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -5)
	right:SetSize(1, 10)
	right:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -5)
	local fill = b.Bar(5)
	fill:SetSize(open and 5 or 1, 10)
	fill:SetPoint("TOPRIGHT", b, "TOPRIGHT", open and -4 or -8, -5)
	fill.faint = false
	b.Paint(b:IsMouseOver())
end

-- Roll Up: a bar (the window folded to a strip); rolled up: a plus (unroll).
local function DrawRoll(b, rolled)
	for _, t in ipairs(b.bars) do t:Hide() end
	local across = b.Bar(1)
	across:SetSize(10, 2)
	across:SetPoint("CENTER", b, "CENTER", 0, 0)
	if rolled then
		local up = b.Bar(2)
		up:SetSize(2, 10)
		up:SetPoint("CENTER", b, "CENTER", 0, 0)
	end
	b.Paint(b:IsMouseOver())
end

-- ---------------------------------------------------------------------------------------------
-- Place and size
-- ---------------------------------------------------------------------------------------------

-- The window where it was left: its top-left corner, kept in the screen's units from the screen's
-- bottom-left corner, so a change of state or size grows it right and down from the same corner.
local function Place()
	win:ClearAllPoints()
	local spot = DB().spot
	local s = win:GetScale()
	if type(spot) == "table" and type(spot[1]) == "number" and type(spot[2]) == "number" and s > 0 then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot[1] / s, spot[2] / s)
	else
		-- (The design's default: the left of the screen, clear of its middle third.)
		win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
end

local function SavePlace()
	local left, top = win:GetLeft(), win:GetTop()
	local s = win:GetScale()
	if not (left and top) then return end
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local x, y = State.ClampSpot(left * s, top * s, win:GetWidth() * s, sw, sh)
	DB().spot = { x, y }
	Place()
end

local sizedW, sizedH
-- The window's size for its state, and the column's parts shown for it. foot: the craft bar's
-- height now. The shell is dressed again after a change of size (API.Skin: "Call it again after
-- resizing", DaylightUI/API.md).
local function Size(mode, foot)
	local w, h = State.Size(mode, W.col, Height(), foot)
	if slideW then w = slideW end
	if w ~= sizedW or h ~= sizedH then
		sizedW, sizedH = w, h
		win:SetSize(w, h)
		ns.SkinWindow(win)
	end
	col:SetWidth(W.col)
end

-- The detail column sliding out of the right edge (or back), at DaylightUI's NORMAL speed, the
-- way the docked pane's fold slides (Pane.lua). The detail page is a fixed 360 wide, so it's drawn
-- once and only uncovered.
local slider
local function Slide(open)
	local from = win:GetWidth()
	local to = W.col + (open and State.DETAIL or 0)
	if not win:IsVisible() or math.abs(from - to) < 1 then
		slideW = nil
		return false
	end
	local duration = (API.Speed and API.Speed.NORMAL) or 0.2
	slider = slider or CreateFrame("Frame")
	local elapsed = 0
	slideW = from
	side:Show()
	slider:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(1, elapsed / duration)
		t = 1 - (1 - t) * (1 - t)   -- ease out
		slideW = math.floor(from + (to - from) * t + 0.5)
		if t >= 1 then
			self:SetScript("OnUpdate", nil)
			slideW = nil
			Window.Render()
			return
		end
		sizedW = slideW
		win:SetWidth(slideW)
		ns.SkinWindow(win)
	end)
	return true
end

-- ---------------------------------------------------------------------------------------------
-- The header
-- ---------------------------------------------------------------------------------------------

local headIcon, headDot, nameButton, headSkill, skillLine, skillBack
local detailsButton, rollButton, closeButton
local nameTexts = {}

-- The name in the largest size of the type scale that fits (18, 15, 13: WindowState.NameSize),
-- then the skill after it when there is room for it too (it drops first: the 2 px line under the
-- header still shows it).
local function FitName(text, r, g, b, skill, skillInk)
	local buttons = 2 + (win.swapButton and 1 or 0) + 1
	local room = State.HeaderRoom(W.col, buttons)
	local widths = {}
	for size, fs in pairs(nameTexts) do
		fs:SetText(text)
		fs:SetTextColor(r, g, b)
		fs:Hide()
		widths[size] = fs:GetUnboundedStringWidth()
	end
	headSkill:SetText(skill or "")
	headSkill:SetTextColor(Color(skillInk or "LABEL"))
	headSkill:SetWidth(0)
	headSkill:SetWordWrap(false)
	local sw = (skill or "") ~= "" and math.ceil(headSkill:GetUnboundedStringWidth()) or 0
	-- (The warning note, "<name>'s recipes", is the only mark that a linked profession is not
	-- yours: it is never dropped. The name steps down a size or wraps to make room for it, and a
	-- note too long even then wraps itself: WindowState.HeaderFit.)
	local size, nameW, showNote, noteW = State.HeaderFit(widths, room, sw, skillInk == "WARN")
	local fs = nameTexts[size]
	-- (At 13 it fits any profession's name; one longer still wraps to two lines rather than be cut.)
	fs:SetWidth(nameW)
	fs:Show()
	nameButton:SetWidth(nameW + 6 + 8 + 4)
	nameButton.chevron:ClearAllPoints()
	nameButton.chevron:SetPoint("LEFT", fs, "RIGHT", 6, -1)
	if noteW then
		headSkill:SetWidth(noteW)
		headSkill:SetWordWrap(true)
	end
	headSkill:SetShown(showNote)
end

local function SkillLine(value)
	if not value then
		skillLine:Hide()
		return
	end
	skillLine:SetColorTexture(API.Accent())
	skillLine:SetWidth(math.max(1, W.col * math.max(0, math.min(1, value))))
	skillLine:Show()
end

local function PaintHead()
	local vr, vg, vb = Color("VALUE")
	headDot:SetShown(Menu.CooldownReady())
	headDot:SetColorTexture(Color("GOOD"))
	local alt, gather = W.alt, W.gather
	if alt then
		local c = ns.Store and ns.Store.Alts()[alt.guid]
		local p = c and type(c.prof) == "table" and c.prof[alt.line] or {}
		headIcon:Hide()
		FitName(L["%s's %s"]:format((c and c.name) or "?", ns.Tips and ns.Tips.LineName(alt.line) or ""), vr, vg, vb,
			("%d / %d"):format(p.skill or 0, p.max or 0))
		SkillLine((p.max or 0) > 0 and (p.skill or 0) / p.max or nil)
		return
	end
	if gather == W.CAMP then
		local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(Menu.CAMP_ICON) or nil
		headIcon:SetTexture(icon)
		headIcon:SetShown(icon ~= nil)
		FitName(L["Camping"], vr, vg, vb)
		SkillLine(nil)
		return
	end
	if gather then
		local p = Menu.GatherEntry()
		headIcon:SetTexture(p and p.icon or nil)
		headIcon:SetShown(p ~= nil and p.icon ~= nil)
		FitName(p and p.name or L["Profession"], vr, vg, vb, p and p.max > 0 and ("%d / %d"):format(p.skill, p.max) or nil)
		SkillLine(p and p.max > 0 and p.skill / p.max or nil)
		return
	end
	local open = S.mode == "win"
	local icon = open and S.line and TS("GetTradeSkillTexture", S.line) or nil
	if not icon and open then
		for _, p in ipairs(W.MyProfessions()) do if p.line == S.line then icon = p.icon end end
	end
	headIcon:SetTexture(icon)
	headIcon:SetShown(icon ~= nil)
	local skill, ink
	if open and Linked() then
		-- (Someone else's recipes: said where the skill would be, in the warning ink.)
		local _, who = TS("IsTradeSkillLinked")
		skill = type(who) == "string" and L["%s's recipes"]:format(who) or L["Someone else's recipes"]
		ink = "WARN"
	elseif open and (S.max or 0) > 0 then
		skill = ("%d / %d"):format(S.skill or 0, S.max)
	end
	FitName(open and (S.name or L["Profession"]) or "Glowey's Recipes", vr, vg, vb, skill, ink)
	SkillLine(open and (S.max or 0) > 0 and (S.skill or 0) / S.max or nil)
end

local function BuildHeader()
	header = CreateFrame("Frame", nil, win)
	header:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
	header:SetHeight(HEADER)
	local under = header:CreateTexture(nil, "ARTWORK")
	under:SetHeight(1)
	under:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	under:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	under:SetColorTexture(1, 1, 1, 0.06)
	-- The skill line: 2 px in the accent along the header's foot, over a faint track the column wide.
	skillBack = header:CreateTexture(nil, "ARTWORK", nil, 1)
	skillBack:SetHeight(2)
	skillBack:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	skillBack:SetColorTexture(1, 1, 1, 0.08)
	skillLine = header:CreateTexture(nil, "ARTWORK", nil, 2)
	skillLine:SetHeight(2)
	skillLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	skillLine:Hide()

	headIcon = header:CreateTexture(nil, "ARTWORK")
	headIcon:SetSize(20, 20)
	headIcon:SetPoint("LEFT", header, "LEFT", 10, 0)
	headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A ready cooldown: a dot on the icon's corner (the tiles are in the menu).
	headDot = header:CreateTexture(nil, "OVERLAY")
	headDot:SetSize(6, 6)
	headDot:SetPoint("CENTER", headIcon, "TOPRIGHT", -1, -1)
	headDot:Hide()
	-- Shift-click the icon: your open profession linked to chat, as the game's link button does
	-- (also "Link to Chat" in the professions menu, so it isn't only said here).
	local iconHit = CreateFrame("Button", nil, header)
	iconHit:SetAllPoints(headIcon)
	iconHit:SetScript("OnClick", function()
		if IsModifiedClick("CHATLINK") then Window.LinkOpen() else Menu.Toggle() end
	end)
	iconHit:SetScript("OnEnter", function(self)
		if not headIcon:IsShown() or not W.Own() then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(S.name or L["Profession"])
		GameTooltip:AddLine(L["Shift-click: link to chat"], Color("LABEL"))
		GameTooltip:Show()
	end)
	iconHit:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	Pad.Skip(iconHit)   -- (the name beside it is the stop)

	-- The name: the professions menu's button.
	nameButton = CreateFrame("Button", nil, header)
	nameButton:SetHeight(24)
	nameButton:SetPoint("LEFT", header, "LEFT", 38, 0)
	for _, size in ipairs({ "title", "head", "body" }) do
		local fs = Text(nameButton, size)
		fs:SetPoint("LEFT", nameButton, "LEFT", 0, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(size == "body")
		fs:Hide()
		nameTexts[size] = fs
	end
	nameButton.chevron = Doc.Chevron(nameButton)
	nameButton.wash = W.Wash(nameButton, "BACKGROUND", 0.05)
	nameButton.wash:SetPoint("TOPLEFT", -4, 0)
	nameButton.wash:SetPoint("BOTTOMRIGHT", 0, 0)
	nameButton.wash:Hide()
	nameButton:SetScript("OnEnter", function(self)
		self.wash:Show()
		self.chevron.Paint("ACCENT")
	end)
	nameButton:SetScript("OnLeave", function(self)
		self.wash:Hide()
		self.chevron.Paint("LABEL")
	end)
	nameButton:SetScript("OnClick", function() Menu.Toggle() end)
	W.nameButton = nameButton
	headSkill = Text(header, "small")
	headSkill:SetPoint("LEFT", nameButton, "RIGHT", 6, 0)
	headSkill:SetWordWrap(false)

	closeButton = API.Close(win, function() win:Hide() end)
	closeButton:SetPoint("RIGHT", header, "RIGHT", -10, 0)
	-- (Beside the X: the swap button, back to the game's or DaylightUI's profession window.)
	if ns.Swap then win.swapButton = ns.Swap.OnWindow(win, closeButton) end
	rollButton = IconButton(header, function() return W.Rolled() and L["Unroll"] or L["Roll Up"] end,
		function() Window.SetRolled(not W.Rolled()) end)
	rollButton:SetPoint("RIGHT", win.swapButton or closeButton, "LEFT", -6, 0)
	detailsButton = IconButton(header, L["Details"], function() Window.ToggleDetails() end)
	detailsButton:SetPoint("RIGHT", rollButton, "LEFT", -6, 0)
end

-- ---------------------------------------------------------------------------------------------
-- The tabs
-- ---------------------------------------------------------------------------------------------

local TAB_WORDS = { recipes = L["Recipes"], guide = L["Leveling Guide"], materials = L["Materials"],
	queue = L["Queue"], missing = L["Missing"] }
local plButton       -- "Open Professionally Lost", where the Leveling Guide tab was

local function TabLabel(key)
	if key == "queue" then
		local n = ns.Queue and ns.Queue.Count() or 0
		if n > 0 then return L["Queue (%d)"]:format(n) end
	end
	return TAB_WORDS[key]
end

-- The tab row laid out for the tabs that show (WindowState.TabLayout: the column grows with it
-- to 520, then its padding shrinks, then it takes a second row; a label is never cut). Sets W.col
-- and W.tab; returns the row's height (0 with no tabs: an alt's or a gathering page).
local function PaintTabs()
	local handed = Handed()
	W.tab = State.TabFor(want, handed)
	local other = Other()
	local shown = {}
	for _, key in ipairs(State.Tabs(handed)) do shown[key] = true end
	-- widths: the labels as they read now (the tabs are laid out from these); reserve: the same
	-- with the queue's tab at its reserved longest, "Queue (99)" (the column's width comes from
	-- these, so it does not move as the queue fills and empties).
	local pieces, widths, reserve = {}, {}, {}
	for _, b in ipairs(tabButtons) do
		local on = shown[b.key] and not other
		b:SetShown(on)
		if on then
			local n = #pieces + 1
			pieces[n] = b
			local longest = 0
			if b.key == "queue" then
				b.text:SetText(L["Queue (%d)"]:format(99))
				longest = b.text:GetUnboundedStringWidth()
			end
			b.text:SetText(TabLabel(b.key))
			widths[n] = b.text:GetUnboundedStringWidth()
			reserve[n] = math.max(longest, widths[n])
		end
	end
	-- Where the Leveling Guide tab was: its guide's own window, a press away (ProfLost.lua).
	local PL = ns.ProfLost
	local offer = handed and not other and PL and PL.OpenGuide and (not PL.CanOpenGuide or PL.CanOpenGuide())
	plButton:SetShown(offer and true or false)
	if offer then
		plButton.text:SetText(L["Open Professionally Lost"])
		pieces[#pieces + 1] = plButton
		widths[#pieces] = plButton.text:GetUnboundedStringWidth()
		reserve[#pieces] = widths[#pieces]
	end
	-- A page without tabs (an alt's recipes, a gathering profession, camping) keeps the column as
	-- wide as it was: nothing snaps narrower and back as you look at an alt.
	if other or #pieces == 0 then return 0 end
	-- The column: what the tab row asks at its reserved widths, and what the craft bar's one row
	-- asks at its (WindowState.Column; WindowList's CraftBarNeed). The tabs are then laid out from
	-- their own words in a column at least that wide: never cut, and never wider than 520 for it.
	local least = State.Column(State.TabLayout(reserve).col, List.CraftBarNeed())
	local layout = State.TabLayout(widths, { min = least, max = math.max(State.MAX_W, least) })
	W.col = layout.col
	for i, b in ipairs(pieces) do
		local t = layout.tabs[i]
		b:ClearAllPoints()
		b:SetSize(t.w, 26)
		b:SetPoint("BOTTOMLEFT", tabRow, "TOPLEFT", t.x, -(t.row * State.TABS))
		if b ~= plButton then
			if b.key == W.tab then
				b.text:SetTextColor(Color("VALUE"))
				b.line:SetColorTexture(API.Accent())
				b.line:Show()
			else
				b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
				b.line:Hide()
			end
		else
			b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "ACCENT"))
		end
	end
	return layout.rows * State.TABS
end

local function BuildTabs()
	tabRow = CreateFrame("Frame", nil, col)
	tabRow:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
	tabRow:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0)
	tabRow:SetHeight(State.TABS)
	local under = tabRow:CreateTexture(nil, "ARTWORK")
	under:SetHeight(1)
	under:SetPoint("BOTTOMLEFT", tabRow, "BOTTOMLEFT", 0, 0)
	under:SetPoint("BOTTOMRIGHT", tabRow, "BOTTOMRIGHT", 0, 0)
	under:SetColorTexture(1, 1, 1, 0.06)
	for i, key in ipairs(State.TAB_KEYS) do
		local b = CreateFrame("Button", nil, tabRow)
		b.key = key
		b.text = Text(b, "small")
		b.text:SetPoint("CENTER", 0, 1)
		b.text:SetWordWrap(false)
		b.text:SetText(TAB_WORDS[key])
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 6, 0)
		b.line:SetPoint("BOTTOMRIGHT", -6, 0)
		b:SetScript("OnClick", function() Window.SetTab(b.key) end)
		b:SetScript("OnEnter", function() b.text:SetTextColor(Color("VALUE")) end)
		b:SetScript("OnLeave", function()
			if b.key ~= W.tab then b.text:SetTextColor(Color("LABEL")) end
		end)
		tabButtons[i] = b
		tabOf[key] = b
	end
	plButton = CreateFrame("Button", nil, tabRow)
	plButton.text = Text(plButton, "small")
	plButton.text:SetPoint("CENTER", 0, 1)
	plButton.text:SetWordWrap(false)
	plButton:SetScript("OnEnter", function(self) self.text:SetTextColor(Color("VALUE")) end)
	plButton:SetScript("OnLeave", function(self) self.text:SetTextColor(Color("ACCENT")) end)
	plButton:SetScript("OnClick", function()
		local PL = ns.ProfLost
		if PL and PL.OpenGuide then PL.OpenGuide(S.line) end
	end)
	plButton:Hide()
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- B on a controller, one level at a time (the design: "B closes Details first, then the
-- window"): the professions menu, then the details, then the window.
local function CloseOne()
	if Menu.Shown() then
		Menu.Close()
	elseif not W.Rolled() and Mode() == "expanded" then
		Window.SetDetails(false)
	else
		win:Hide()
	end
end

-- The window on a controller. Its own function: one Build alone would reach more than the 60
-- outside locals Lua 5.1 lets one function use, and the file would not load at all.
local function BuildPad()
	-- A controller (Guide.lua's Pad, DaylightUI.Pad behind it): the game's cursor moves over the
	-- window's rows and buttons while it's shown, A presses, B closes one level, LB / RB step
	-- through the tabs, X is Create, Y opens the details (Y on a row with its own menu opens that:
	-- DaylightUI's own "More"), the left menu button goes to the search box (the kit finds the box
	-- itself, by the mark API.Input gives a search box: DaylightUI/Pad.lua:946-966, Options/
	-- Widgets.lua:1404; nothing is set here for it), the right stick scrolls the list the cursor is
	-- in. While the professions menu is open the window's own keys do nothing and LB / RB step no
	-- tab: X, Y and the tabs would act on the window under the menu, on a row the cursor is not on. Every Button is a stop of the game's cursor whether or not
	-- it takes the mouse (SmartNavigation_CanFocusFrame: Blizzard_GamepadSmartNavigation/
	-- Utility.lua:263-275), so the look-alike Stop is one, and A on it is the secure Stop's action.
	local listPad = List.PadScroller()
	win.padTabs = function()
		local list, at = {}, nil
		-- (The kit steps nothing with fewer than two: DaylightUI/Pad.lua:141-146.)
		if Menu.Shown() then return list, at end
		for _, b in ipairs(tabButtons) do
			if b:IsVisible() then
				list[#list + 1] = b
				if b.key == W.tab then at = #list end
			end
		end
		return list, at
	end
	-- The cursor starts on Stop while rolled up and making, else on the picked recipe (else the
	-- list's first row, else the professions menu).
	win.padFirst = function()
		local cb = W.craftBar
		if W.Rolled() and cb and cb.stop:IsVisible() then return cb.stop end
		return List.FirstStop() or nameButton
	end
	local function Make()
		local cb = W.craftBar
		if cb and cb:IsVisible() and cb.make:IsVisible() and not cb.make.off then return cb.make end
		return nil
	end
	local function HasMore(at)
		return type(at) == "table" and type(at.padMore) == "function" and at.padMore(at) ~= nil
	end
	win.padKeys = {
		-- A on Stop: the secure Stop's own action, through DaylightUI's secure key (the Stop drawn
		-- here only shows it). A on a profession's row in the menu: that profession's spell, the
		-- same way (Menu.PadCast; the hint stays "Select", Daylight UI's own word for A).
		{ key = "A", label = function() if Menu.Shown() then return nil end return L["Stop"] end,
			secure = function(at)
				if Menu.Shown() then return Menu.PadCast(at) end
				local cb = W.craftBar
				if cb and at == cb.stop and cb.stop:IsVisible() and not cb.stop.off then
					return { type = "macro", macrotext = "/stopcasting" }
				end
				return nil
			end },
		{ key = "X", label = function() local b = Make() return b and b.text:GetText() or L["Create"] end,
			when = function() return not Menu.Shown() and Make() ~= nil end,
			run = function() local b = Make() if b and not Menu.Shown() then b:Click() end end },
		-- Y: the details (unrolls a rolled-up window). On a stop with a menu of its own, DaylightUI's
		-- default Y ("More") comes after this entry and takes it.
		{ key = "Y", label = function() return W.Rolled() and L["Unroll"] or L["Details"] end,
			when = function(at)
				if Menu.Shown() or HasMore(at) then return false end
				return W.Rolled() or State.HasDetails(W.tab, Other())
			end,
			run = function()
				if W.Rolled() then Window.SetRolled(false) else Window.ToggleDetails() end
			end },
	}
	Pad.Follow(win, CloseOne)
	win.listPad = listPad
end

-- The bottom edge's grip: three short bars (the fold tab's grip, lying down). Dragging it sets the
-- height the way DaylightUI's own grip sizes its windows: the height at the start plus the mouse's
-- travel, not StartSizing (DaylightUI/Windows/Frame.lua:392-412), saved on release.
local function BuildGrip()
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(40, 8)
	grip:SetPoint("BOTTOM", col, "BOTTOM", 0, 0)
	grip:SetFrameLevel(win:GetFrameLevel() + 20)
	grip.bars = {}
	for i = 1, 3 do
		local bar = grip:CreateTexture(nil, "OVERLAY")
		bar:SetSize(6, 2)
		bar:SetPoint("CENTER", grip, "CENTER", (i - 2) * 9, 0)
		grip.bars[i] = bar
	end
	function grip.Paint(over)
		local r, g, b
		if over then r, g, b = API.Accent() else r, g, b = Color("LABEL") end
		for _, bar in ipairs(grip.bars) do bar:SetColorTexture(r, g, b, over and 1 or 0.6) end
	end
	grip.Paint(false)
	local function CursorY()
		-- (GetCursorPosition: the mouse in screen pixels; Blizzard_APIDocumentationGenerated/
		-- InputDocumentation.lua:30. Divided by the window's effective scale for its own units.)
		local _, y = GetCursorPosition()
		local s = win:GetEffectiveScale()
		if type(s) ~= "number" or s <= 0 then s = 1 end
		return (tonumber(y) or 0) / s
	end
	local function Stop()
		if not grip.grab then return end
		grip.grab = nil
		grip:SetScript("OnUpdate", nil)
		local h = liveHeight
		liveHeight = nil
		if not grip:IsMouseOver() then grip.Paint(false) end
		if h then Window.SetHeight(h) end
	end
	grip:SetScript("OnEnter", function() grip.Paint(true) end)
	grip:SetScript("OnLeave", function() if not grip.grab then grip.Paint(false) end end)
	grip:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		grip.grab = { y = CursorY(), h = Height() }
		grip:SetScript("OnUpdate", function()
			local g = grip.grab
			if not g then return end
			local sh = UIParent:GetHeight()
			local h = State.ClampHeight(g.h + (g.y - CursorY()), sh and sh > 0 and sh / Scale() or nil)
			if h ~= liveHeight then
				liveHeight = h
				Window.Relayout()
			end
		end)
	end)
	grip:SetScript("OnMouseUp", Stop)
	grip:SetScript("OnHide", Stop)
	-- (A controller sets the height with the Window Height setting: no stop here.)
	Pad.Skip(grip)
	win.grip = grip
end

local function Draggable()
	-- Dragged by its header, and a right-click on the header puts it back at its default place and
	-- height: DaylightUI's own windows' way (Win.Drag, DaylightUI/Windows/Frame.lua:521-545).
	local function OnHeader()
		local top, s = win:GetTop(), win:GetEffectiveScale()
		local _, y = GetCursorPosition()
		if type(top) ~= "number" or type(y) ~= "number" or not s or s <= 0 then return false end
		return y / s >= top - HEADER
	end
	local function Stop()
		if not win.dragging then return end
		win.dragging = nil
		win:StopMovingOrSizing()
		win:SetUserPlaced(false)   -- (the place is kept in our saved variables, not the game's layout cache)
		SavePlace()
		Window.Relayout()
	end
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self)
		if not OnHeader() then return end
		self.dragging = true
		self:StartMoving()
	end)
	win:SetScript("OnDragStop", Stop)
	win:HookScript("OnHide", Stop)
	win:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and OnHeader() then Window.ResetPlace() end
	end)
end

local function BuildBody()
	col = CreateFrame("Frame", nil, win)
	col:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -HEADER)
	col:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	col:SetWidth(W.col)
	BuildTabs()
	body = CreateFrame("Frame", nil, col)
	body:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -State.TABS)
	body:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0)
	W.body = body

	List.Build(body)
	List.BuildSummary(body)
	local craftBar = List.BuildCraftBar(body)
	craftBar:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	craftBar:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	-- The other tabs: one page down the column, the missing list with its search above it.
	pageSearch = API.Input(body, { search = true, hint = L["Search missing recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == (pageSearch.filter or "") then return end
			pageSearch.filter = text
			W.Debounce(function()
				if pageDoc then pageDoc:Top() end
				Window.Render()
			end)
		end })
	pageSearch:SetPoint("TOPLEFT", body, "TOPLEFT", PAD - 2, -8)
	pageSearch:SetPoint("RIGHT", body, "RIGHT", -(PAD - 2), 0)
	pageDoc = Doc.New(body, { pad = PAD, redraw = function() Window.Render() end })

	altDoc = Doc.New(body, { pad = PAD, redraw = function() Window.Render() end })
	altDoc.search = API.Input(body, { search = true, hint = L["Search their recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == Menu.altFilter then return end
			Menu.altFilter = text
			W.Debounce(function() Window.Render() end)
		end })
	altDoc.search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD - 2, -8)
	altDoc.search:SetPoint("RIGHT", body, "RIGHT", -(PAD - 2), 0)

	-- The detail column: out of the right edge, under the header, a fixed 360 wide (so its page is
	-- drawn once and the slide only uncovers it).
	side = CreateFrame("Frame", nil, win)
	side:SetPoint("TOPLEFT", col, "TOPRIGHT", 0, 0)
	side:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
	side:SetClipsChildren(true)
	side:Hide()
	local edge = side:CreateTexture(nil, "ARTWORK")
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetColorTexture(1, 1, 1, 0.06)
	detail = Doc.New(side, { pad = PAD, width = State.DETAIL - 1 })
	detail.scroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -4)
	detail.scroll:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 1, 4)
	detail.scroll:SetWidth(State.DETAIL - 1)
	W.side = side
end

local function Build()
	win = CreateFrame("Frame", "DaylightRecipesWindow", UIParent)
	W.win = win
	win:SetSize(State.Size(Mode(), W.col, Height(), State.FOOT))
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:Hide()
	win:SetScale(Scale())
	ns.SkinWindow(win)
	Place()
	Draggable()
	-- Esc closes it like any window (and ends the trade skill with it).
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightRecipesWindow") end
	win:HookScript("OnHide", function()
		Menu.Close()
		Menu.StopTicker()
		-- (A secure Stop a fight keeps out shows its own face where it is: WindowList's SyncStop.)
		List.SyncStop(false)
		if ns.Take and ns.Take.OursNow() then ns.Take.Close() end
	end)
	win:SetScript("OnShow", function()
		ns.Changed()
		-- (A tour is showing the window: above DaylightUI's options, where Retake Tour is clicked,
		-- and on its Recipes tab. Window.ShowForTour)
		if Window.tourRaised then Window.TourRaise() end
		-- (The first time, on this account: the window's tour. RecipesGuide.lua)
		if ns.Guide then ns.Guide.Offer("window") end
	end)
	BuildHeader()
	BuildBody()
	BuildGrip()
	BuildPad()
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local pageCtx = {
	make = true,
	redraw = function() Window.Render() end,
	pick = function(spell)
		Window.SetTab("recipes")
		Window.Select(spell)
	end,
}

local function Draw(d, fn, ...)
	d:Begin()
	local ok, err = pcall(fn, d, ...)
	if not ok then
		geterrorhandler()(err)
		d:Line(L["Something went wrong drawing this page."], "small", "BAD")
	end
	d:Finish()
end

local function NoSession(d)
	d:Line(L["Open a profession from the menu on the name above (or cast it from your spellbook)."], "body", "OFF")
end

-- The detail column's page for the tab: the picked missing recipe's sources on Missing, the picked
-- recipe everywhere else.
local function DetailPage(d)
	if S.mode ~= "win" then return NoSession(d) end
	if W.tab == "missing" then return Pages.MissingDetail(d, missingPick) end
	return List.DetailPage(d)
end

local Render
local stuckTo      -- the page the right stick was last put on

function Window.Render()
	if not Window.Shown() then return end
	Render()
	-- A controller: the game finds the window's buttons again (they come and go with the page),
	-- and the stick goes to the new page's list (a row the cursor enters takes it after).
	if Pad.On() then
		local page = Other() and "other" or W.tab
		if page ~= stuckTo then
			stuckTo = page
			Pad.Stick(win, page == "recipes" and win.listPad or page == "other" and altDoc.scroll or pageDoc.scroll)
		end
		Pad.Settle()
	end
end

-- Only the sizes and places again (a drag of the edge or the window, the craft bar growing).
function Window.Relayout()
	if Window.Shown() then Render() end
end

Render = function()
	-- (A profession just opened with the window rolled up or on another tab: its first recipe is
	-- picked all the same, as the game does, so the craft bar has one.)
	if S.mode == "win" and not S.recipe then List.Count() end
	local tabsH = PaintTabs()
	PaintHead()
	local other = Other()
	local mode = Mode()
	local rolled = mode == "rolled"
	local open = S.mode == "win"
	local recipes = not other and W.tab == "recipes"
	skillBack:SetWidth(W.col)
	DrawDetails(detailsButton, mode == "expanded")
	detailsButton:SetShown(not rolled and State.HasDetails(W.tab, other))
	DrawRoll(rollButton, rolled)
	-- (Nothing to roll up to, someone's linked recipes or no profession open: no Roll Up button.
	-- Details then sits where it would have.)
	local canRoll = List.CanRoll()
	rollButton:SetShown(canRoll)
	detailsButton:ClearAllPoints()
	detailsButton:SetPoint("RIGHT", canRoll and rollButton or (win.swapButton or closeButton), "LEFT", -6, 0)
	win.grip:SetShown(not rolled)

	local foot = List.PaintCraftBar()
	Size(mode, foot > 0 and foot or State.FOOT)
	tabRow:SetShown(not rolled and tabsH > 0)
	tabRow:SetHeight(math.max(1, tabsH))
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", col, "TOPLEFT", 0, rolled and 0 or -tabsH)
	body:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0)
	side:SetShown(not rolled and (mode == "expanded" or slideW ~= nil))

	-- Rolled up: the header and the craft bar, nothing else.
	local list = W.list
	if rolled then
		W.search:Hide()
		for _, b in ipairs(W.filters) do b:Hide() end
		list:Hide()
		pageSearch:Hide()
		pageDoc.scroll:Hide()
		altDoc.scroll:Hide()
		altDoc.search:Hide()
		List.PaintSummary(false)
		return
	end

	local summary = List.PaintSummary(recipes and open)
	local craftBar = W.craftBar
	-- What the page ends at: the summary line, else the craft bar, else the column's foot.
	local below, belowPoint, gap = body, "BOTTOMLEFT", 8
	if summary > 0 then
		W.summary:ClearAllPoints()
		if foot > 0 then
			W.summary:SetPoint("BOTTOMLEFT", craftBar, "TOPLEFT", 0, 0)
			W.summary:SetPoint("BOTTOMRIGHT", craftBar, "TOPRIGHT", 0, 0)
		else
			W.summary:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 8)
			W.summary:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
		end
		below, belowPoint, gap = W.summary, "TOPLEFT", 0
	elseif foot > 0 then
		below, belowPoint, gap = craftBar, "TOPLEFT", 0
	end

	W.search:SetShown(recipes)
	for _, b in ipairs(W.filters) do
		b:SetShown(recipes)
		b.Paint()
	end
	list:SetShown(recipes)
	pageSearch:SetShown(not other and W.tab == "missing")
	pageDoc.scroll:SetShown(not other and not recipes)
	altDoc.scroll:SetShown(other)
	altDoc.search:SetShown(W.alt ~= nil)

	-- The detail column, for the tab's pick.
	if mode == "expanded" or slideW then Draw(detail, DetailPage) end

	if other then
		-- (A gathering profession's page has no search above it.)
		local scroll = altDoc.scroll
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, W.alt and -List.UnderSearch(altDoc.search) or -4)
		scroll:SetPoint("RIGHT", body, "RIGHT", 0, 0)
		scroll:SetPoint("BOTTOM", below, belowPoint == "TOPLEFT" and "TOP" or "BOTTOM", 0, gap)
		Draw(altDoc, W.alt and Menu.AltPage or (W.gather == W.CAMP and Menu.CampPage) or Menu.GatherPage)
		return
	end
	if recipes then
		list:ClearAllPoints()
		list:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -List.Top())
		list:SetPoint("RIGHT", body, "RIGHT", 0, 0)
		list:SetPoint("BOTTOM", below, belowPoint == "TOPLEFT" and "TOP" or "BOTTOM", 0, gap)
		if not open then
			list:Hide()
			W.search:Hide()
			for _, b in ipairs(W.filters) do b:Hide() end
			pageDoc.scroll:Show()
			pageDoc.scroll:ClearAllPoints()
			pageDoc.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -4)
			pageDoc.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
			Draw(pageDoc, NoSession)
			return
		end
		List.Paint()
		return
	end
	local scroll = pageDoc.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, W.tab == "missing" and -List.UnderSearch(pageSearch) or -4)
	scroll:SetPoint("RIGHT", body, "RIGHT", 0, 0)
	scroll:SetPoint("BOTTOM", below, belowPoint == "TOPLEFT" and "TOP" or "BOTTOM", 0, gap)
	if not open then
		Draw(pageDoc, NoSession)
	elseif W.tab == "guide" then
		Draw(pageDoc, Pages.Guide, pageCtx)
	elseif W.tab == "queue" then
		Draw(pageDoc, Pages.Queue, pageCtx)
	elseif W.tab == "materials" then
		Draw(pageDoc, Pages.Materials)
	else
		pageCtx.filter = pageSearch.filter or ""
		-- (With the details open a missing recipe's sources show there, and the list stays whole.)
		if mode == "expanded" then
			pageCtx.detailSpell = missingPick
			pageCtx.detail = function(e)
				missingPick = e.spell
				detail:Top()
				Window.Render()
			end
		else
			pageCtx.detail, pageCtx.detailSpell = nil, nil
		end
		Draw(pageDoc, Pages.Missing, pageCtx)
	end
end

-- ---------------------------------------------------------------------------------------------
-- States
-- ---------------------------------------------------------------------------------------------

-- The details open or closed on the tab that's up (remembered for that tab), sliding.
function Window.SetDetails(open)
	if not win or not State.HasDetails(W.tab, Other()) then return end
	local db = DB()
	if State.DetailsOpen(db, W.tab, Other(), ns.Get("detailsDefault") == true) == (open and true or false) then return end
	State.SetDetails(db, W.tab, open)
	if not Window.Shown() or W.Rolled() then return end
	if open then
		-- (Opening: drawn first, then uncovered.)
		slideW = win:GetWidth()
		Window.Render()
		if not Slide(true) then Window.Render() end
	else
		if not Slide(false) then Window.Render() end
	end
end

function Window.ToggleDetails()
	if W.Rolled() then
		Window.SetRolled(false)
		return
	end
	Window.SetDetails(Mode() ~= "expanded")
end

function Window.SetRolled(rolled)
	local db = DB()
	if (db.rolled == true) == (rolled and true or false) then return end
	State.SetRolled(db, rolled)
	Menu.Close()
	if slider then slider:SetScript("OnUpdate", nil) end
	slideW = nil
	Window.Render()
end

-- The Window Height setting, from a drag of the bottom edge (the options slider writes it itself).
function Window.SetHeight(h)
	h = State.ClampHeight(h)
	local DUI = _G.DaylightUI
	-- (DaylightUI:Set(scope, path, value), as Swap.lua and RecipesGuide.lua set "window".)
	if type(DUI) == "table" and type(DUI.Set) == "function" then pcall(DUI.Set, DUI, ADDON, "winHeight", h) end
	Window.Relayout()
end

-- A right-click on the header: the default place and height again.
function Window.ResetPlace()
	if not win then return end
	DB().spot = nil
	Place()
	Window.SetHeight(State.H)
end

ns.me.On("SettingChanged", function(scope, path)
	if scope ~= ADDON then return end
	if path == "winHeight" or path == "detailsDefault" or path == nil then Window.Relayout() end
end)

-- A hand-off to Professionally Lost flipped, or its guide moved to another step: ProfLost.lua calls
-- ns.Changed() itself after each (its Changed and Soon), which draws the window again, and the
-- tabs (Handed, asked on every draw) and the list's mark (Plan.CurrentSpell, asked on every paint)
-- follow at once. The window keeps no copy of either answer, so it registers no ProfLost.OnChange.

-- ---------------------------------------------------------------------------------------------
-- What the rest of the plugin calls
-- ---------------------------------------------------------------------------------------------

function Window.Dirty()
	List.Dirty()
	ns.Changed()
end

function Window.SetTab(key)
	if W.tab == key and want == key and not Other() then return end
	want = key
	W.alt, W.gather = nil, nil
	if win then DB().tab = key end
	if pageDoc then pageDoc:Top() end
	Window.Render()
	-- (A tab's own short tour, the first time it opens: RecipesGuide.lua.)
	if ns.Guide then ns.Guide.Offer("tab-" .. key) end
end

-- Your open profession's link (C_TradeSkillUI.GetTradeSkillListLink, as the game's own link
-- button) into the open chat box. Only for your own profession: not a linked one, not an alt's.
function Window.LinkOpen()
	if not W.Own() then return false end
	local ok, link = pcall(C_TradeSkillUI.GetTradeSkillListLink)
	if not ok or not link then return false end
	return ns.InsertLink(link)
end

-- "Link to Chat" on a profession in the menu (or a Shift-click on it): linked at once when it's
-- the open one, else opened and linked as soon as it's open (the game only links the open trade
-- skill).
function Window.LinkProfession(line, game)
	if S.mode == "win" and S.line == line and W.Own() then
		Window.LinkOpen()
		return
	end
	Window.OpenProfession(line, game)
	Window.LinkOnceOpen(line)
end

-- Links your profession once the game has it open (asked for a moment ago: by OpenProfession, or
-- by its spell from the menu's row).
function Window.LinkOnceOpen(line)
	local tries = 0
	local function wait()
		tries = tries + 1
		if S.mode == "win" and S.line == line and not Linked() then
			Window.LinkOpen()
		elseif tries < 20 then
			C_Timer.After(0.1, wait)
		end
	end
	C_Timer.After(0.1, wait)
end

Window.MyProfessions = W.MyProfessions
function Window.Unlearn(p) Menu.Unlearn(p) end

-- What the tours light (RecipesGuide.lua): the window, the professions menu's button (`side`: the
-- name it gave the old sidebar; `menu` is the same), the tabs, the recipe list, the craft bar, the
-- page under the tabs, the swap button beside the X, and the new parts: Details, Roll Up, the
-- summary line.
function Window.TourParts()
	local tabs = {}
	for _, b in ipairs(tabButtons) do
		if b:IsVisible() then tabs[#tabs + 1] = b end
	end
	return { win = win, side = nameButton, menu = nameButton, tabs = tabs, tabOf = tabOf, list = W.list,
		craft = W.craftBar, body = body, swap = win and win.swapButton, tab = W.tab,
		details = detailsButton, roll = rollButton, summary = W.summary }
end

-- Opens the window for a tour (on the open profession, else the last one, else your professions).
-- Until the tour ends (Window.TourDone) the window sits above DaylightUI's options (Retake Tour is
-- clicked there) on its Recipes tab, unrolled, whenever it shows: opening a profession shows it a
-- moment later, once the game says the trade skill is open.
-- Nothing the player left is overwritten by it: the tab and the rolled-up choice they had are back
-- when the tour ends (the tab is put back by TourDone; rolled up is only set aside while
-- tourRaised is up: W.Rolled).
local tourBefore        -- { want, tab }: the tab asked for and the tab saved when the tour began
function Window.ShowForTour()
	if not Window.tourRaised then tourBefore = { want = want, tab = win and DB().tab or nil, had = win ~= nil } end
	Window.tourRaised = true
	if Window.Shown() then Window.TourRaise() else Window.Toggle(true) end
end

function Window.TourRaise()
	if not win then return end
	win:SetFrameStrata("FULLSCREEN")
	want, W.alt, W.gather = "recipes", nil, nil
	Window.Render()
end

function Window.TourDone()
	local was = tourBefore
	tourBefore = nil
	Window.tourRaised = nil
	if not win then return end
	win:SetFrameStrata("MEDIUM")
	if was then
		want = was.want
		if was.had then DB().tab = was.tab end
	end
	Window.Render()
end

function Window.Select(spell)
	if type(spell) ~= "number" then return end
	if S.recipe ~= spell then
		S.recipe = spell
		Window.RecipeChanged()
	end
	List.ShowInList(spell)
	ns.Changed()
end

-- Another recipe picked: its page from the top.
function Window.RecipeChanged()
	if detail then detail:Top() end
end

-- What the page now drawn is waiting on (an item's data).
function Window.Waiting(itemID)
	if not Window.Shown() then return false end
	return (detail and detail:Waiting(itemID)) or (pageDoc and pageDoc:Waiting(itemID)) or false
end

-- Whether a page showing prices, your materials or the plan is up.
function Window.ShowingPlan()
	return Window.Shown() and not Other() and W.tab ~= "missing"
end

function Window.ShowingMissing()
	return Window.Shown() and not Other() and W.tab == "missing"
end

-- A craft of ours started, moved on or ended (Craft.lua); afterFight: a fight just ended, and a
-- secure Stop left where it was through it goes where it belongs now, or away.
function Window.CraftChanged(afterFight)
	if not Window.Shown() then
		List.SyncStop(false)
		return
	end
	-- (The bar comes and goes with a run on every tab, and changes the window's size rolled up.)
	Render()
	if Pad.On() then Pad.Settle() end
	-- (A finished craft changes the counts in the list.)
	if not afterFight and not Craft.Making() then Window.Dirty() end
end

-- The cooldowns were read again (Cooldowns.lua): the header's dot, and the menu while it's open.
function Window.PaintCooldowns()
	if not Window.Shown() then return end
	headDot:SetShown(Menu.CooldownReady())
	if Menu.Shown() then Menu.Paint() end
end

local closing = 0       -- counts closings: one put off a frame is dropped if a session started

-- A trade skill opened that belongs in our window (Take.lua). The window opens by itself, in the
-- state it was left: compact, expanded or rolled up, on the tab last open.
function Window.SessionStarted()
	local first = not win
	if first then
		local saved = DB().tab
		if type(saved) == "string" and TAB_WORDS[saved] then want = saved end
		Build()
	end
	closing = closing + 1
	W.alt, W.gather = nil, nil
	S.mode = "win"
	if ns.Where then ns.Where.ForgetKnown() end
	ns.ReadProfession()
	-- (The one /recipes opens next time, away from a crafting station.)
	if S.line and not Linked() then DaylightRecipesDB.lastLine = S.line end
	List.Reset()
	if not win:IsShown() then
		win:SetAlpha(0)
		win:Show()
		API.Fade(win, 1, "FAST")
	end
	ns.Changed()
end

-- The trade skill closed (or moved to the game's window): our window closes with it.
-- (A frame later: another profession picked in the menu closes the trade skill and opens the next
-- one at once, and the window stays up through it.)
function Window.SessionEnded()
	if S.mode == "win" then S.mode = nil end
	if not (win and win:IsShown()) then return end
	closing = closing + 1
	local serial = closing
	C_Timer.After(0, function()
		if serial ~= closing or S.mode == "win" then return end
		if win:IsShown() then win:Hide() end
	end)
end

-- The list's counts follow your bags (the game updates the trade skill on every bag change), and
-- a recipe learned joins it.
local listEvents = CreateFrame("Frame")
listEvents:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
listEvents:RegisterEvent("NEW_RECIPE_LEARNED")
listEvents:SetScript("OnEvent", function()
	if S.mode == "win" and Window.Shown() then Window.Dirty() end
end)

local function Ensure()
	if win then return end
	local saved = DB().tab
	if type(saved) == "string" and TAB_WORDS[saved] then want = saved end
	Build()
end

-- Opens one of your professions (a press: the game asks for one to open a trade skill). line: the
-- data's skill line; game: the game's own for it, the one the game opens (the same, mostly).
function Window.OpenProfession(line, game)
	if not line then return end
	game = game or line
	if S.mode == "win" and S.line == line and not Linked() then
		if Other() then
			W.alt, W.gather = nil, nil
			Window.Render()
		end
		return
	end
	W.alt, W.gather = nil, nil
	local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, game)
	if not ok or opened == false then
		-- (Its page says how to open it instead, with its skill and rank.)
		ns.Print(L["The game didn't open that profession."])
		Window.ShowGather(game)
	end
end

-- Opens one of your recipes (a cooldown tile's press): its profession first when another is
-- open, then the recipe on the Recipes tab, as a pick from the Leveling Guide does.
function Window.OpenRecipe(line, spell)
	if not (line and type(spell) == "number") then return end
	local function Pick()
		Window.SetTab("recipes")
		Window.Select(spell)
	end
	if S.mode == "win" and S.line == line and not Linked() then
		Pick()
		return
	end
	local game
	for _, p in ipairs(W.MyProfessions()) do
		if p.line == line and p.crafts then game = p.game end
	end
	if not game then return end
	Window.OpenProfession(line, game)
	-- (Picked once the game says it's open: it opens a moment after the press.)
	local tries = 0
	local function wait()
		tries = tries + 1
		if S.mode == "win" and S.line == line and not Linked() then
			Pick()
		elseif tries < 20 then
			C_Timer.After(0.1, wait)
		end
	end
	C_Timer.After(0.1, wait)
end

function Window.ShowAlt(guid, line)
	W.alt, W.gather = { guid = guid, line = line }, nil
	Ensure()
	if altDoc then altDoc:Top() end
	-- (Its page has no place rolled up: it unrolls.)
	State.SetRolled(DB(), false)
	if not win:IsShown() then win:Show() end
	Window.Render()
end

-- A gathering profession of yours (by the game's skill line): its page, in place of the tabs.
function Window.ShowGather(game)
	if not game then return end
	W.alt, W.gather = nil, game
	Ensure()
	if altDoc then altDoc:Top() end
	State.SetRolled(DB(), false)
	if not win:IsShown() then win:Show() end
	Window.Render()
end

-- /recipes: the window, on the profession open now, or the one you had open last.
-- noGame: the window alone, without asking the game to open a profession (a tour that starts by
-- itself: the game opens a trade skill only from a click, and blocks it from a timer).
function Window.Toggle(noGame)
	if Window.Shown() then
		win:Hide()
		return
	end
	if ns.Take and ns.Take.OursNow() then
		Ensure()
		win:Show()
		return
	end
	local last = DaylightRecipesDB and DaylightRecipesDB.lastLine
	local game = last
	for _, p in ipairs(W.MyProfessions()) do
		-- (The game's own line for the one last open, else your first with recipes.)
		if (last and p.line == last) or (not last and p.crafts) then
			game = p.game
			break
		end
	end
	if game and not noGame then
		local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, game)
		if ok and opened ~= false then return end
	end
	-- No profession to open: the window shows anyway, its menu a press away.
	Ensure()
	win:Show()
end

function Window.Restyle()
	Menu.Restyle()
	if Window.Shown() then Window.Render() end
end

function Window.Rescale()
	if not win then return end
	local old, new = win:GetScale(), Scale()
	local left, top = win:GetLeft(), win:GetTop()
	win:SetScale(new)
	if left and top and DB().spot then
		-- (The same spot on the screen at the new scale.)
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / new, top * old / new)
		SavePlace()
	else
		Place()
	end
	Window.Relayout()
end

-- The screen got smaller or larger (the UI scale, the game's window): the window fits it again.
local screen = CreateFrame("Frame")
screen:RegisterEvent("UI_SCALE_CHANGED")
screen:RegisterEvent("DISPLAY_SIZE_CHANGED")
screen:SetScript("OnEvent", function()
	-- (A frame later: UIParent takes its new size after the event.)
	C_Timer.After(0, Window.Rescale)
end)
