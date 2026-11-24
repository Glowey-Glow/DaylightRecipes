-- The Blizzard Layout (the "Blizzard Layout" setting, off by default): the window laid out the way
-- the game's own profession window is, with the professions as tabs on its LEFT side (the player's
-- one change: the game hangs them on the right). The same frames as the compact window (Window.lua,
-- WindowList.lua): this file only lays them out and adds what the shape needs. The art is the look's:
-- Blizzard Style without Daylight UI draws the game's own pieces (Host.lua's helpers, and the ones
-- below that Host has no helper for yet), every other look draws them in its own colors.
-- Its shape, each piece from the client's FrameXML (Gethe/wow-ui-source, branch "forever"; paths
-- under Interface/AddOns):
--   the frame      ProfessionsFrame, 673 wide (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.xml:
--                  10-11), a PortraitFrameTemplate (Blizzard_ProfessionsFrameBase.xml:5)
--   portrait       the open profession's icon in the round corner (PortraitFrameBaseTemplate:
--                  Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:566-591, its 62 x 62
--                  portrait at -5, 7 under the circle mask; the corner "UI-Frame-PortraitMetal-
--                  CornerTopLeft" at -13, 16: Mainline/NineSliceLayouts.lua:17-21). A press opens
--                  the professions menu, a Shift-press links the profession, as the header's icon did
--   title          the profession's name in the title bar (Host.Chrome's, in Blizzard Style)
--   rank bar       "Blacksmithing 86/150" under the title (ProfessionsRankBarTemplate:
--                  Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRankBar.xml:5-64, placed at
--                  110, -40: Camelot/Blizzard_ProfessionsCrafting.lua:9-11; its words
--                  TRADESKILL_NAME_RANK, Blizzard_ProfessionsRankBar.lua:6-12; its fill the first
--                  frame of the profession's "Skillbar_Fill_Flipbook_<kit>", :146-163), and the
--                  link button after it (Blizzard_ProfessionsCrafting.xml:356-382, its art
--                  Blizzard_ProfessionsCrafting.lua:31-51)
--   recipe list    ProfessionsRecipeListTemplate, 304 wide (Camelot/Blizzard_ProfessionsCrafting.lua:25),
--                  from 5, -72 to the foot (Blizzard_ProfessionsCrafting.xml:135-141): search box
--                  at 13, -8 up to the Filter button at -8, -9 (Blizzard_ProfessionsRecipeList.xml:
--                  32-74), the rows from 8, -35 (:76-81); the Filter button's art and its red
--                  reset X (Blizzard_Menu/Mainline/MenuTemplates.xml:66-104, Mainline/
--                  MenuConstants.lua:1-6, UIResetButtonTemplate: SharedUIPanelTemplates.xml:867-871).
--                  Its menu holds our two filters, Can Make and Skill-ups
--   recipe rows    the skill-up arrow before the name and the count after it ("Coarse Grinding
--                  Stone [10]"): ProfessionsRecipeListRecipeMixin:Init, Blizzard_ProfessionsRecipeList.lua:
--                  285-333 (atlases Professions-Icon-Skill-High / -Medium / -Low, the number of
--                  points beside an orange one that gives more than one) and :357-368 (" [%d] ")
--   details        SchematicFormCraftingTemplate, 360 wide beside the list (Camelot/
--                  Blizzard_ProfessionsCrafting.lua:5-7, Blizzard_ProfessionsCrafting.xml:143-148)
--                  in "common-insideframe" (Camelot/Blizzard_ProfessionsRecipeSchematicForm.xml:4-11),
--                  on the profession's own background (Blizzard_ProfessionsCrafting.lua:1032):
--                  the recipe's icon, name and description (Blizzard_ProfessionsRecipeSchematicForm.xml:
--                  30-38, 190-239), "Reagents:" and a slot per reagent saying have/need
--                  (ProfessionsReagentSlotBaseTemplate, Blizzard_ProfessionsRecipeReagentSlotBase.xml:
--                  7-33; ProfessionsButtonTemplate, Blizzard_ProfessionsTemplates.xml:41-54;
--                  Blizzard_ProfessionsRecipeReagentSlot.lua:240-252). Then ours, in the page's text
--                  styles: what each reagent costs and where you hold it, the total, the skill-up
--                  chance, the value and who else knows it (Pages.lua)
--   craft bar      Create All [N], the count's spinner and Create at the details' foot
--                  (Camelot/Blizzard_ProfessionsCrafting.lua:32-38, Blizzard_ProfessionsCrafting.lua:
--                  248-262, 776-785). Our Queue sits where the game's Track Recipe box does, in the
--                  details' bottom right corner (Camelot/Blizzard_ProfessionsCrafting.lua:20-23): our
--                  window has no recipe tracking for it to stand in for
--   side tabs      LargeSideTabButtonTemplate (SharedUIPanelTemplates.xml:1008-1068; its size,
--                  SharedUIPanelTemplates.lua:311-331; its icon 30 x 30, Blizzard_ProfessionsTemplates/
--                  Blizzard_ProfessionsTemplates.lua:951-956, set 4 to the side, Camelot/
--                  SharedUIPanelTemplates.lua:11-14), one per profession of yours, the first 60 under
--                  the frame's top and each next 2 under it (Camelot/Blizzard_ProfessionsFrame.xml:
--                  13-61), mirrored to hang off the LEFT edge. A press opens the profession by its
--                  spell through the secure button the chips use (WindowMenu.lua's PlaceCaster, out of
--                  a fight; ProfessionsLargeRightTabMixin:CastProfessionSpell, Blizzard_Professions
--                  Templates.lua:958-964). Camping, "+N" and the three dots (alts, Cooldowns,
--                  Tracking) are tabs too, as they were chips
--   page tabs      Recipes, Leveling Guide, Materials, Queue and Missing under the window, as the
--                  mainline profession window hangs its own pages' tabs (Blizzard_Professions/Mainline/
--                  Blizzard_ProfessionsFrame.xml:12-20: TabSystemTemplate at 22, 2 under its foot,
--                  tabs at least 100 wide; TabSystemButtonArtTemplate, Blizzard_SharedXML/Shared/
--                  TabSystem/TabSystemTemplates.xml:3-123, its words' places TabSystemTemplates.lua:
--                  32-41 and widths :225-253)
-- Rolled up, the window is the compact window's rolled-up bar (nothing of the game's to copy).
-- Switching the setting lays the same window out again at once: no reload (Window.lua's
-- SettingChanged).
-- The top part of this file is plain arithmetic: the offline tests load it alone.
local _, ns = ...
if not ns.ok then return end

local Lay = {}
ns.WinLayout = Lay

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ---------------------------------------------------------------------------------------------
-- Its shape, as numbers (in the window's own units, from its top-left corner)
-- ---------------------------------------------------------------------------------------------

Lay.LIST_X = 2            -- the recipe list's left (the game's 5, less the 3 our frame starts inside its art)
Lay.LIST_W = 304          -- Camelot/Blizzard_ProfessionsCrafting.lua:25
Lay.GAP = 2               -- the details 2 right of the list (Blizzard_ProfessionsCrafting.xml:148)
Lay.DETAIL_W = 361        -- the game's 360 (Camelot/Blizzard_ProfessionsCrafting.lua:5-7) and its edge
Lay.RIGHT = 4
Lay.W = Lay.LIST_X + Lay.LIST_W + Lay.GAP + Lay.DETAIL_W + Lay.RIGHT   -- 673 (Camelot xml:11)
Lay.MIN_H = 520
Lay.H = 560               -- (the Window Height setting's own default, WindowState.lua's H)
-- Where the list starts under the window's top: in Blizzard Style the title bar is above our frame
-- (Host.lua's chrome, 24), so the game's -72 is -48 here; in another look the header (36) and the
-- rank bar's row are inside it.
Lay.TOP_BZ = 48
Lay.TOP = 62
Lay.RANK_W = 453          -- Blizzard_ProfessionsRankBar.xml:6
Lay.SIDE_TOP = 60         -- the first side tab under the frame's visible top
Lay.SIDE_GAP = 2
Lay.SIDE_ICON = 34        -- a side tab's icon in Blizzard Style (the game's 30 read small in its well)
Lay.TAB_X, Lay.TAB_Y = 22, 2   -- the page tabs: TOPLEFT at the frame's BOTTOMLEFT + 22, 2
Lay.TAB_MIN = 100         -- minTabWidth
Lay.TAB_H = 32            -- TabSystemButtonTemplate's height
Lay.TAB_SPACING = 1       -- TabSystemTemplate's spacing (TabSystemTemplates.xml:155)
Lay.OWN_TAB_H = 26        -- the page tabs and side tabs in another look
Lay.OWN_SIDE = 38
Lay.BAR_PAD = 8           -- the craft bar's buttons from its edges

-- The window's size: the game's width, the player's height (the Window Height setting, its drag),
-- never under MIN_H.
function Lay.Size(h, least, w)
	return w or Lay.W, max(Lay.MIN_H, tonumber(least) or 0, floor((tonumber(h) or Lay.H) + 0.5))
end

function Lay.ListTop(bz) return bz and Lay.TOP_BZ or Lay.TOP end

-- The side tabs that show: n professions (picked: the index of the one on show, or nil), extra:
-- how many tabs follow them (Alts, Cooldowns, Tracking; true counts as one), room: the height they
-- may take, size, gap. Returns the indices shown in order and how many go behind a "+N" tab. As the
-- chips' rule (WindowState.ChipFit): whole tabs only, and the one on show is never among those left
-- out. (The window is made tall enough for all of them, Lay.SideNeed: "+N" is the last resort.)
function Lay.SideFit(n, picked, extra, room, size, gap)
	local step = size + gap
	local slots = max(0, floor((room + gap) / step))
	local list = {}
	extra = extra == true and 1 or (tonumber(extra) or 0)
	if n + extra <= slots then
		for i = 1, n do list[i] = i end
		return list, 0
	end
	-- (One slot for "+N", one each for the tabs after them.)
	local keep = min(n, max(1, slots - 1 - extra))
	for i = 1, keep do list[i] = i end
	if picked and picked > keep then list[keep] = picked end
	return list, n - keep
end

-- The window's least height for k side tabs of `size` to fit down its edge (outT: how far its art
-- reaches above our frame, the tabs starting SIDE_TOP under that), with a little to spare.
function Lay.SideNeed(k, size, gap, outT)
	if k <= 0 then return 0 end
	return Lay.SIDE_TOP - (outT or 0) + k * (size + gap) - gap + 4
end

-- The k-th side tab's top under the frame's visible top.
function Lay.SideY(k, size, gap)
	return Lay.SIDE_TOP + (k - 1) * (size + gap)
end

-- The page tabs' widths and places from their words' widths: in Blizzard Style the words plus 20,
-- never under 100 (TabSystemButtonMixin:UpdateTabWidth, TabSystemTemplates.lua:225-253: words,
-- padding 10 and 10 more; minTabWidth 100), 1 apart; else the words plus 24, 2 apart. Never cut:
-- there is no most. Returns widths, lefts and the row's whole width.
function Lay.TabWidths(textWidths, bz)
	local widths, xs, x = {}, {}, 0
	local gap = bz and Lay.TAB_SPACING or 2
	for i, tw in ipairs(textWidths) do
		local w = ceil(tonumber(tw) or 0)
		w = bz and max(Lay.TAB_MIN, w + 20) or (w + 24)
		widths[i], xs[i] = w, x
		x = x + w + gap
	end
	return widths, xs, max(0, x - gap)
end

-- The craft bar's buttons in one row: Create All at the left, the spinner and Create at the right,
-- as the game has them. w: { all, minus, count, plus, make }. Returns the width they need.
function Lay.BarNeed(w)
	local pad = Lay.BAR_PAD
	return pad + w.all + 12 + w.minus + 4 + w.count + 4 + w.plus + 12 + w.make + pad
end

-- Whether they need two rows in `bar` wide.
function Lay.BarTwoRows(w, bar)
	return Lay.BarNeed(w) > bar
end

-- The details' width: the game's 361, wider when the craft bar needs it with a count of three
-- digits on Create All ("Create All [999]", in the player's font and size), so it never takes a
-- second row. barNeed: Lay.BarNeed's answer for that.
function Lay.DetailWidth(barNeed)
	return max(Lay.DETAIL_W, ceil(tonumber(barNeed) or 0))
end

-- The whole window's width for a details' width.
function Lay.Width(detailW)
	return Lay.LIST_X + Lay.LIST_W + Lay.GAP + (detailW or Lay.DETAIL_W) + Lay.RIGHT
end

-- The clamp: the frame's art (out*: how far it reaches past our frame), the side tabs (sideW wide,
-- hung off the art's left edge) and the page tabs (reaching tabsDown below our frame) stay on the
-- screen. SetClampRectInsets' own order: left, right, top, bottom.
function Lay.ClampInsets(outL, outR, outT, outB, sideW, tabsDown)
	return -((outL or 0) + (sideW or 0)), outR or 0, outT or 0, -max(outB or 0, tabsDown or 0)
end

-- The arrow for a recipe's skill-up step (1 orange, 2 yellow, 3 green; gray none), as the game's
-- list picks it (Blizzard_ProfessionsRecipeList.lua:294-303).
Lay.ARROWS = { "Professions-Icon-Skill-High", "Professions-Icon-Skill-Medium", "Professions-Icon-Skill-Low" }
function Lay.Arrow(step, can)
	if can == false then return nil end
	return Lay.ARROWS[step]
end

-- A profession's art kit, by the data's skill line: the names of Enum.Profession, as
-- Professions.GetAtlasKitSpecifier reads them (Blizzard_ProfessionsTemplates/Blizzard_Professions.lua:
-- 1433-1436). First Aid has none: the rank bar's default fill.
Lay.KITS = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
	[356] = "Fishing", [393] = "Skinning" }

-- ---------------------------------------------------------------------------------------------
-- The window's side of it (the rest of the plugin is loaded)
-- ---------------------------------------------------------------------------------------------

local W = ns.Win
if not W then return end
W.Lay = Lay

local API = ns.API
local Doc, Pages, Calc, Craft = ns.Doc, ns.Pages, ns.Calc, ns.Craft
local List, Menu = ns.WinList, ns.WinMenu
local S = ns.state
local L = ns.L
local Color, Text = Doc.Color, Doc.Text

local function H() return ns.Host end
local function TS(name, ...) return Craft.TS(name, ...) end

-- Blizzard Style now (only without Daylight UI: Host.Blizzard answers false with it).
local function Bz()
	local h = H()
	return h and h.Blizzard and h.Blizzard() == true or false
end

-- How far the titled window's Blizzard Style art reaches past our frame (Host.Outset): 0s otherwise.
local function Outset(win)
	local h = H()
	if h and h.Outset then
		local ok, l, r, t, b = pcall(h.Outset, win)
		if ok and type(l) == "number" then return l, r or 0, t or 0, b or 0 end
	end
	return 0, 0, 0, 0
end

-- An atlas on a texture: Host's (Blizzard Style), else the texture's own call, guarded.
local function Atlas(tex, atlas, useSize)
	local h = H()
	if h and h.Atlas and h.Atlas(tex, atlas, useSize) then return true end
	return pcall(tex.SetAtlas, tex, atlas, useSize and true or false) and true or false
end

-- An atlas's own size (C_Texture.GetAtlasInfo), or nil.
local function AtlasSize(atlas)
	local C = rawget(_G, "C_Texture")
	if type(C) ~= "table" or type(C.GetAtlasInfo) ~= "function" then return nil end
	local ok, info = pcall(C.GetAtlasInfo, atlas)
	if ok and type(info) == "table" and tonumber(info.width) and tonumber(info.height) then
		return tonumber(info.width), tonumber(info.height)
	end
	return nil
end

-- On: the setting, with the window built.
function Lay.On()
	return W.win ~= nil and ns.Get("blizzardLayout") == true
end

-- On and not rolled up (rolled up it is the compact window's bar).
function Lay.Active()
	return Lay.On() and not W.Rolled()
end

-- Where the recipe list starts under the window's top (the professions menu opens there).
function Lay.Top() return Lay.ListTop(Bz()) end

-- The title: the open profession's name; an alt's ("Mira's Alchemy"), a gathering profession's or
-- Camping's on their pages.
function Lay.TitleText()
	if W.alt then
		local c = ns.Store and ns.Store.Alts()[W.alt.guid]
		return L["%s's %s"]:format((c and c.name) or "?", ns.Tips and ns.Tips.LineName(W.alt.line) or "")
	end
	if W.gather == W.CAMP then return L["Camping"] end
	if Menu.IsPartPage(W.gather) then return (Menu.PartTitle(W.gather)) end
	if W.gather then
		local p = Menu.GatherEntry()
		return p and p.name or L["Profession"]
	end
	if S.mode == "win" and type(S.name) == "string" and S.name ~= "" then return S.name end
	return "Glowey's Recipes"
end

-- What the portrait and the rank bar show: icon, name, skill, max, the data's line (its art kit),
-- and a note in place of the skill (someone else's recipes).
local function Shown()
	if W.alt then
		local c = ns.Store and ns.Store.Alts()[W.alt.guid]
		local p = c and type(c.prof) == "table" and c.prof[W.alt.line] or {}
		return nil, ns.Tips and ns.Tips.LineName(W.alt.line) or "", p.skill or 0, p.max or 0, W.alt.line
	end
	if W.gather == W.CAMP then
		local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(Menu.CAMP_ICON) or nil
		return icon, L["Camping"]
	end
	if Menu.IsPartPage(W.gather) then
		local name, icon = Menu.PartTitle(W.gather)
		return icon, name
	end
	if W.gather then
		local p = Menu.GatherEntry()
		if not p then return nil end
		return p.icon, p.name, p.skill, p.max, p.line
	end
	if S.mode ~= "win" then return nil end
	local icon = S.line and TS("GetTradeSkillTexture", S.line) or nil
	if not icon then
		for _, p in ipairs(W.MyProfessions()) do
			if (S.line and p.line == S.line) or (not S.line and S.name and p.name == S.name) then icon = p.icon end
		end
	end
	if W.Linked() then
		local _, who = TS("IsTradeSkillLinked")
		return icon, S.name, nil, nil, S.line, type(who) == "string" and L["%s's recipes"]:format(who) or L["Someone else's recipes"]
	end
	-- (The game's own line for one the data has none for, as Fishing: its rank bar's art kit.)
	return icon, S.name, S.skill or 0, S.max or 0, S.line or S.game
end

-- ---------------------------------------------------------------------------------------------
-- Its pieces, made once
-- ---------------------------------------------------------------------------------------------

local built, laid
local portrait, titles, rank, linkButton, listBox, listInset, filterBz, filterOwn, resetButton, sideArt, sideBox
local sideTabs, bottomTabs, shownTabs, tabOf = {}, {}, {}, {}

-- A frame skinned in the look (Host.Skin) behind a button of ours, a sibling under it: hidden in
-- Blizzard Style, where the button wears the game's art. (A sibling, so its shell is never drawn
-- over the button's own words and icon.)
local function Holder(b, opts)
	local f = CreateFrame("Frame", nil, b:GetParent())
	f:SetAllPoints(b)
	f:EnableMouse(false)
	f:SetFrameLevel(b:GetFrameLevel())
	b:SetFrameLevel(b:GetFrameLevel() + 2)
	if ns.Host and ns.Host.Skin then ns.Host.Skin(f, opts or { noBevel = true }) end
	return f
end

-- The round portrait (PortraitFrameBaseTemplate's portrait and circle mask), its corner in Blizzard
-- Style, and the ready-cooldown dot.
local function BuildPortrait(win)
	local p = CreateFrame("Button", nil, win)
	p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetAllPoints()
	local okMask, mask = pcall(p.CreateMaskTexture, p)
	if okMask and mask then
		pcall(mask.SetTexture, mask, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetPoint("TOPLEFT", p.icon, "TOPLEFT", 2, 0)
		mask:SetPoint("BOTTOMRIGHT", p.icon, "BOTTOMRIGHT", -2, 4)
		pcall(p.icon.AddMaskTexture, p.icon, mask)
	end
	p.ring = p:CreateTexture(nil, "OVERLAY")
	p.ring:Hide()
	p.dot = p:CreateTexture(nil, "OVERLAY", nil, 2)
	p.dot:SetSize(6, 6)
	p:SetScript("OnClick", function(self)
		if IsModifiedClick("CHATLINK") then
			if ns.Window then ns.Window.LinkOpen() end
			return
		end
		Menu.Toggle(true, self)
	end)
	p:SetScript("OnEnter", function(self)
		ns.Host.Tip(self, Lay.TitleText(), L["Click: open the professions menu"],
			W.Own() and L["Shift-click: link to chat"] or nil, "ANCHOR_RIGHT")
	end)
	p:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	return p
end

-- The rank bar: the game's skill bar art in Blizzard Style, else a track and fill in the look.
local function BuildRank(win)
	local r = CreateFrame("Frame", nil, win)
	r:SetHeight(18)
	r.bg = r:CreateTexture(nil, "ARTWORK", nil, 1)
	r.bg:SetPoint("TOPLEFT")
	r.fill = r:CreateTexture(nil, "ARTWORK", nil, 2)
	r.fill:SetPoint("TOPLEFT", r, "TOPLEFT", 5, -3)
	r.border = r:CreateTexture(nil, "ARTWORK", nil, 3)
	r.border:SetPoint("TOPLEFT")
	r.track = r:CreateTexture(nil, "BACKGROUND")
	r.track:SetAllPoints()
	r.bar = r:CreateTexture(nil, "ARTWORK")
	r.bar:SetPoint("TOPLEFT")
	r.bar:SetPoint("BOTTOMLEFT")
	r.text = Text(r, "small")
	r.text:SetWordWrap(false)
	return r
end

-- The link button's press, as the game's (Blizzard_ProfessionsCrafting.lua:99-112, 356-384): into
-- the chat box when one is open, else a "Post In" menu of where to post it (Guild, Party, Raid
-- while you're in one, then your channels), which opens the chat with it there.
local function ChatOpen()
	local U = rawget(_G, "ChatFrameUtil")
	local get = (type(U) == "table" and U.GetActiveWindow) or rawget(_G, "ChatEdit_GetActiveWindow")
	if type(get) ~= "function" then return false end
	local ok, box = pcall(get)
	return ok and box ~= nil
end

local function PostIn(slash, link)
	local text = ("%s %s"):format(slash, link)
	local U = rawget(_G, "ChatFrameUtil")
	if type(U) == "table" and type(U.OpenChat) == "function" then
		pcall(U.OpenChat, text, _G.DEFAULT_CHAT_FRAME)
	elseif type(_G.ChatFrame_OpenChat) == "function" then
		pcall(_G.ChatFrame_OpenChat, text, _G.DEFAULT_CHAT_FRAME)
	end
end

-- A game function's answer, or false when this client has none.
local function G(name)
	local fn = rawget(_G, name)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn)
	return ok and v or false
end

-- Whisper: the game's own dialog with a box for whom (StaticPopup with hasEditBox, as the game's
-- own name prompts are made), then the chat opened whispering them the link, to send with Enter.
local WHISPER = "DAYLIGHTRECIPES_WHISPER_LINK"
local function WhisperTo(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then return end
	local ok, link = pcall(C_TradeSkillUI.GetTradeSkillListLink)
	if ok and link then PostIn("/w " .. name, link) end
end
local function BoxOf(dialog)
	if type(dialog.GetEditBox) == "function" then
		local ok, box = pcall(dialog.GetEditBox, dialog)
		if ok and box then return box end
	end
	return dialog.editBox or dialog.EditBox
end
local function AskWhisper()
	local dialogs = rawget(_G, "StaticPopupDialogs")
	local show = rawget(_G, "StaticPopup_Show")
	if type(dialogs) ~= "table" or type(show) ~= "function" then return end
	if not dialogs[WHISPER] then
		dialogs[WHISPER] = {
			text = L["Whisper your profession's link to:"],
			button1 = L["Whisper"], button2 = _G.CANCEL or L["Cancel"],
			hasEditBox = true, maxLetters = 48, timeout = 0, whileDead = true, hideOnEscape = true,
			OnShow = function(self)
				local box = BoxOf(self)
				if box then box:SetText("") box:SetFocus() end
			end,
			OnAccept = function(self)
				local box = BoxOf(self)
				if box then WhisperTo(box:GetText()) end
			end,
			EditBoxOnEnterPressed = function(box)
				local dialog = box:GetParent()
				WhisperTo(box:GetText())
				if dialog then dialog:Hide() end
			end,
			EditBoxOnEscapePressed = function(box)
				local dialog = box:GetParent()
				if dialog then dialog:Hide() end
			end,
		}
	end
	pcall(show, WHISPER)
end

local function LinkPress(owner)
	if not W.Own() then return end
	if ChatOpen() then
		if ns.Window then ns.Window.LinkOpen() end
		return
	end
	local keys, words = {}, {}
	local function Add(slash, word, enabled)
		if not enabled or type(slash) ~= "string" then return end
		keys[#keys + 1] = slash
		words[slash] = word
	end
	Add(_G.SLASH_GUILD1 or "/g", _G.GUILD or L["Guild"], G("IsInGuild"))
	Add(_G.SLASH_PARTY1 or "/p", _G.PARTY or L["Party"], (tonumber(G("GetNumSubgroupMembers")) or 0) > 0)
	Add(_G.SLASH_RAID1 or "/raid", _G.RAID or L["Raid"], G("IsInRaid"))
	local list = rawget(_G, "GetChannelList")
	local channels = type(list) == "function" and { list() } or {}
	local U = rawget(_G, "ChatFrameUtil")
	for i = 1, #channels, 3 do
		local name = channels[i + 1]
		if type(U) == "table" and type(U.ResolveChannelName) == "function" then
			local ok, resolved = pcall(U.ResolveChannelName, name)
			if ok and type(resolved) == "string" then name = resolved end
		end
		Add("/" .. tostring(channels[i]), ("%s. %s"):format(tostring(channels[i]), tostring(name)), not channels[i + 2])
	end
	-- (Nowhere to post: Say, the chat box opened with the link in it.)
	if #keys == 0 then
		Add("/s", _G.SAY or L["Say"], true)
	end
	-- Whisper someone: their name asked in a box.
	Add("whisper", L["Whisper..."], true)
	API.Menu(owner, keys, words, nil, function(slash)
		if slash == "whisper" then
			AskWhisper()
			return
		end
		local ok, link = pcall(C_TradeSkillUI.GetTradeSkillListLink)
		if ok and link then PostIn(slash, link) end
	end, 160)
end

-- The link button after the rank bar (Blizzard Style: its square and chat-link icon).
local function BuildLink(win)
	local b = CreateFrame("Button", nil, win)
	b:SetSize(23, 23)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetPoint("CENTER")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER")
	local function Face(self, down)
		local over = self:IsMouseOver()
		Atlas(self.bg, down and "common-button-tertiary-square-pressed"
			or (over and "common-button-tertiary-square-hover" or "common-button-tertiary-square-normal"), true)
		Atlas(self.icon, "common-icon-chatlink", true)
	end
	b.Face = Face
	b:SetScript("OnEnter", function(self)
		Face(self)
		ns.Host.Tip(self, L["Link to Chat"], L["Click: post it in a channel, or into the open chat box"], nil, "ANCHOR_TOPLEFT")
	end)
	b:SetScript("OnLeave", function(self)
		Face(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnMouseDown", function(self) Face(self, true) end)
	b:SetScript("OnMouseUp", function(self) Face(self) end)
	b:SetScript("OnClick", function(self) LinkPress(self) end)
	return b
end

-- The two filters (Can Make, Skill-ups: the list's own, saved where they always were), in the
-- Filter button's menu: Daylight UI's dropdown (or Host's), each word with a check box before it.
local FILTERS = { "canMake", "skillUps" }
local CHECK_ON = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16:0:0|t "
local CHECK_OFF = "|TInterface\\Buttons\\UI-CheckBox-Up:16:16:0:0|t "
local function FilterOn() return W.DB().canMake == true or W.DB().skillUps == true end
local function OpenFilters(owner)
	local db = W.DB()
	local words = { canMake = L["Can Make"], skillUps = L["Skill-ups"] }
	local keys = {}
	for _, key in ipairs(FILTERS) do
		keys[#keys + 1] = key
		words[key] = (db[key] == true and CHECK_ON or CHECK_OFF) .. words[key]
	end
	if FilterOn() then
		keys[#keys + 1] = "clear"
		words.clear = L["Clear Filters"]
	end
	-- (Its width from its words, the check box's 16 included: the menu takes the Filter button's
	-- otherwise, and cut them.)
	local meter = owner.__meter
	if not meter then
		meter = Text(owner, "body")
		meter:Hide()
		owner.__meter = meter
	end
	local widest = 0
	for _, key in ipairs(keys) do
		meter:SetText(words[key])
		widest = max(widest, ceil(meter:GetUnboundedStringWidth()))
	end
	API.Menu(owner, keys, words, nil, function(key)
		local d = W.DB()
		if key == "clear" then
			d.canMake, d.skillUps = nil, nil
		else
			d[key] = not d[key] or nil
		end
		if ns.Window then ns.Window.Dirty() end
	end, widest + 16 + 40)
end

local function BuildFilter(box)
	-- Blizzard Style: the filter dropdown's own button (its states' atlases) and its words.
	local b = CreateFrame("Button", nil, box)
	b:SetHeight(18)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
	b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
	b.text = Text(b, "small")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text:SetText(L["Filter"])
	local function Face(self, down)
		local over = self:IsMouseOver()
		Atlas(self.bg, down and (over and "common-dropdown-b-button-pressedhover" or "common-dropdown-b-button-pressed")
			or (over and "common-dropdown-b-button-hover" or "common-dropdown-b-button"))
		self.text:SetTextColor(Color(over and "VALUE" or "TITLE"))
	end
	b.Face = Face
	b:SetScript("OnEnter", function(self) Face(self) end)
	b:SetScript("OnLeave", function(self) Face(self) end)
	b:SetScript("OnMouseDown", function(self) Face(self, true) end)
	b:SetScript("OnMouseUp", function(self) Face(self) end)
	b:SetScript("OnClick", function(self) OpenFilters(self) end)
	filterBz = b
	-- Another look: one of the look's own buttons.
	filterOwn = API.Button(box, L["Filter"], 22)
	filterOwn:SetScript("OnClick", function(self) OpenFilters(self) end)
	-- The red X while a filter is on (UIResetButtonTemplate), on both: it clears them.
	local x = CreateFrame("Button", nil, box)
	x:SetSize(23, 23)
	x.tex = x:CreateTexture(nil, "ARTWORK")
	x.tex:SetAllPoints()
	x.hi = x:CreateTexture(nil, "HIGHLIGHT")
	x.hi:SetAllPoints()
	if not Atlas(x.tex, "auctionhouse-ui-filter-redx") then x.tex:SetColorTexture(0.8, 0.1, 0.1, 1) end
	if Atlas(x.hi, "auctionhouse-ui-filter-redx") then x.hi:SetBlendMode("ADD") x.hi:SetAlpha(0.4) end
	x:SetScript("OnClick", function()
		local d = W.DB()
		d.canMake, d.skillUps = nil, nil
		if ns.Window then ns.Window.Dirty() end
	end)
	x:SetScript("OnEnter", function(self) ns.Host.Tip(self, L["Clear Filters"], nil, nil, "ANCHOR_TOP") end)
	x:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	resetButton = x
end

local function Build(P)
	if built then return end
	built = true
	local win = P.win
	portrait = BuildPortrait(win)
	portrait:SetFrameLevel(win:GetFrameLevel() + 8)
	titles = {}
	for _, size in ipairs({ "head", "body" }) do
		local fs = Text(P.header, size)
		fs:SetPoint("CENTER", P.header, "CENTER", 0, 0)
		fs:SetWordWrap(true)
		fs:SetJustifyH("CENTER")
		fs:Hide()
		titles[size] = fs
	end
	rank = BuildRank(win)
	linkButton = BuildLink(win)
	-- The list's column: the game's list ground and inset in Blizzard Style (Host.Inset).
	listBox = CreateFrame("Frame", nil, P.body)
	local h = H()
	listInset = h and h.Inset and h.Inset(listBox, "Professions-background-summarylist") or nil
	if listInset then listInset:SetAllPoints(listBox) end
	BuildFilter(listBox)
	-- The profession's own background in the details (Blizzard Style).
	sideArt = P.side:CreateTexture(nil, "BACKGROUND", nil, 1)
	sideArt:SetPoint("TOPLEFT", P.side, "TOPLEFT", 2, -2)
	sideArt:SetPoint("BOTTOMRIGHT", P.side, "BOTTOMRIGHT", -2, 2)
	sideArt:Hide()
	-- What the tours light for "your professions": round the side tabs that show.
	sideBox = CreateFrame("Frame", nil, win)
	sideBox:EnableMouse(false)
	sideBox:Hide()
	-- (A look change: the Blizzard pieces drawn again. Host.Looked, as WindowBlizzard.lua asks it.)
	if h and h.Looked then h.Looked(Lay, function() if W.win and W.win:IsShown() and ns.Window then ns.Window.Render() end end) end
end

-- ---------------------------------------------------------------------------------------------
-- The side tabs
-- ---------------------------------------------------------------------------------------------

-- The game's side tab art, mirrored to hang off the left edge.
local function SideArt(t)
	local a = t.art
	if a then return a end
	a = { bg = t:CreateTexture(nil, "BACKGROUND"), sel = t:CreateTexture(nil, "OVERLAY"),
		hover = t:CreateTexture(nil, "OVERLAY", nil, 1) }
	Atlas(a.bg, "common-sidetab", true)
	Atlas(a.sel, "common-sidetab-selected", true)
	Atlas(a.hover, "common-sidetab-hover", true)
	for _, tex in pairs(a) do
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", t, "CENTER", 0, 0)
		tex:SetTexCoord(1, 0, 0, 1)
	end
	t.art = a
	return a
end

-- The game's side tab size: its art's width, and its height less the 5 of empty space
-- (SidePanelTabButtonMixin.CalculateTabSizeBasedOnTabArt, SharedUIPanelTemplates.lua:311-321).
local function SideSize(bz)
	if not bz then return Lay.OWN_SIDE, Lay.OWN_SIDE end
	local w, h = AtlasSize("common-sidetab")
	if not w then return 45, 55 end
	return w, max(1, h - 5)
end

local function SideLit(t, over)
	t.over = over and true or nil
	if t.art then
		t.art.sel:SetShown(t.bzOn and t.lit == true)
		t.art.hover:SetShown(t.bzOn and over and t.lit ~= true or false)
	end
	if t.wash then t.wash:SetShown(not t.bzOn and over and true or false) end
	if t.edge then
		t.edge:SetShown(not t.bzOn and t.lit == true)
		t.edge:SetColorTexture(API.Accent())
	end
	if t.text then t.text:SetTextColor(Color((over or t.lit) and "VALUE" or "LABEL")) end
	if t.dots then
		local cr, cg, cb
		if over then cr, cg, cb = API.Accent() else cr, cg, cb = Color("LABEL") end
		for _, dot in ipairs(t.dots) do dot:SetColorTexture(cr, cg, cb, 1) end
	end
end

local function SideTip(t)
	local e = t.entry
	if t.tabKind == "plus" then
		ns.Host.TipLines(t, function(tip)
			tip.Line(L["Professions"], "TITLE")
			for _, x in ipairs(t.left or {}) do
				tip.Line((x.sub or "") ~= "" and x.prof and ("%s  %s"):format(x.name, x.sub) or x.name, "TEXT")
			end
		end, "ANCHOR_LEFT")
	elseif t.tabKind == "alts" then
		ns.Host.TipLines(t, function(tip)
			tip.Line(L["Your Alts"], "TITLE")
			tip.Line(L["Click: your alts' professions"], "TEXT")
		end, "ANCHOR_LEFT")
	elseif t.tabKind == "cooldowns" then
		local ready = t.ready:IsShown()
		ns.Host.TipLines(t, function(tip)
			tip.Line(L["Cooldowns"], "TITLE")
			tip.Line(L["Click: your recipes that can only be made once in a while"], "TEXT")
			if ready then tip.Line(L["Ready to craft"], "GOOD") end
		end, "ANCHOR_LEFT")
	elseif t.tabKind == "tracking" then
		ns.Host.TipLines(t, function(tip)
			tip.Line(L["Tracking"], "TITLE")
			tip.Line(L["Click: turn your professions' minimap tracking on or off"], "TEXT")
		end, "ANCHOR_LEFT")
	elseif e then
		local lines = W.Chips.TipLines(e)
		ns.Host.TipLines(t, function(tip)
			tip.Line(lines[1], "TITLE")
			for i = 2, #lines do tip.Line(lines[i], (i == 2 and (e.sub or "") ~= "") and "TEXT" or "pop") end
		end, "ANCHOR_LEFT")
	end
end

local function SideTab(i)
	local t = sideTabs[i]
	if t then return t end
	local win = W.win
	t = CreateFrame("Button", nil, win)
	t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	t.holder = Holder(t)
	t.wash = W.Wash(t, "BORDER", 0.08)
	t.wash:SetAllPoints()
	t.wash:Hide()
	-- (The one on show: an accent bar along its outer edge, in another look.)
	t.edge = t:CreateTexture(nil, "OVERLAY")
	t.edge:SetWidth(2)
	t.edge:SetPoint("TOPLEFT")
	t.edge:SetPoint("BOTTOMLEFT")
	t.edge:Hide()
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.text = Text(t, "small")
	t.text:SetPoint("CENTER")
	t.text:Hide()
	t.dots = {}
	for d = 1, 3 do
		local dot = t:CreateTexture(nil, "ARTWORK")
		dot:SetSize(3, 3)
		dot:Hide()
		t.dots[d] = dot
	end
	t.ready = t:CreateTexture(nil, "OVERLAY", nil, 3)
	t.ready:SetSize(6, 6)
	t.ready:SetPoint("CENTER", t, "TOPLEFT", 6, -6)
	t.ready:Hide()
	t:SetScript("OnEnter", function(self)
		SideLit(self, true)
		SideTip(self)
		-- (The secure button over it, for a profession its spell opens: WindowMenu.lua's PlaceCaster.)
		if self.cast then Menu.PlaceCaster(self) end
	end)
	t:SetScript("OnLeave", function(self)
		SideLit(self, false)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	t:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if self.onRight then self.onRight(self) end
			return
		end
		if self.onClick then self.onClick(self) end
	end)
	-- (With the secure button over it the mouse is on that: it keeps the tab's light and tooltip.)
	t.hover = function(self, on)
		SideLit(self, on)
		if on then SideTip(self) elseif GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end
	-- A controller's Y: what a right-click does (Link to Chat, Unlearn), as on a chip.
	t.padMore = function(self) return self.onRight end
	-- (Menu.PadCast's mark: A on it casts the profession's spell, as on a chip.)
	t.chip = true
	sideTabs[i] = t
	return t
end

-- A tab dressed for what it is: a profession (entry), "+N" (kind "plus"), or one of the menu's
-- parts (kind "alts", "cooldowns", "tracking": Menu.Parts, e its { icon }).
local function DressSide(t, bz, size, h, kind, e)
	t.tabKind, t.entry = kind, e
	t.bzOn = bz
	t:SetSize(size, h)
	t.holder:SetShown(not bz)
	local a = bz and SideArt(t) or t.art
	if a then a.bg:SetShown(bz) end
	t.icon:ClearAllPoints()
	t.text:Hide()
	for _, dot in ipairs(t.dots) do dot:Hide() end
	t.icon:Hide()
	t.cast, t.prof, t.onClick, t.onRight, t.lit = nil, nil, nil, nil, nil
	if kind == "entry" then
		t.cast, t.prof, t.onClick, t.onRight, t.lit = e.cast, e.prof, e.onClick, e.onRight, e.picked == true
		if e.icon then
			t.icon:SetTexture(e.icon)
			t.icon:SetDesaturated(false)
			-- (34 x 34, a size over the game's 30 so it fills the tab's well, 4 off center toward the
			-- frame, the tab art's empty side away from it.)
			if bz then
				t.icon:SetSize(Lay.SIDE_ICON, Lay.SIDE_ICON)
				t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- (past the icon's own drawn edge: the tab's well is its frame)
				t.icon:SetPoint("CENTER", t, "CENTER", 4, 0)
			else
				t.icon:SetSize(size - 8, size - 8)
				t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				t.icon:SetPoint("CENTER", t, "CENTER", 0, 0)
			end
			t.icon:Show()
		else
			-- (No icon: its abbreviation, as its chip had.)
			t.text:SetText(W.Chips.Abbr(e) or e.name or "?")
			t.text:Show()
		end
	elseif kind == "plus" then
		t.text:ClearAllPoints()
		t.text:SetPoint("CENTER", t, "CENTER", bz and 4 or 0, 0)
		t.text:Show()
		t.onClick = function(self) Menu.Toggle(self.set, self) end
	else
		-- (One of the menu's parts: its icon, and the menu showing that part alone. Lit while it's
		-- the part open.)
		t.icon:SetTexture(e and e.icon or nil)
		t.icon:SetDesaturated(false)
		if bz then
			t.icon:SetSize(Lay.SIDE_ICON, Lay.SIDE_ICON)
			t.icon:SetPoint("CENTER", t, "CENTER", 4, 0)
		else
			t.icon:SetSize(size - 8, size - 8)
			t.icon:SetPoint("CENTER", t, "CENTER", 0, 0)
		end
		t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t.icon:Show()
		t.lit = W.gather == kind
		t.onClick = function()
			Menu.Close()
			ns.Window.ShowGather(kind)
		end
	end
	t.ready:SetShown(kind == "cooldowns" and Menu.CooldownReady())
	t.ready:SetColorTexture(Color("GOOD"))
	SideLit(t, t:IsMouseOver())
end

local function HideSide()
	-- (The secure button over a tab goes with it, out of a fight.)
	if #sideTabs > 0 then Menu.HideCaster() end
	for _, t in ipairs(sideTabs) do t:Hide() t.holder:Hide() end
	if sideBox then sideBox:Hide() end
end

-- The side tabs placed down the left edge: the professions (and Camping), then "+N", then Alts,
-- Cooldowns and Tracking, each its own tab (Menu.Parts).
local function PaintSide(win, h, bz, outL, outT)
	Menu.HideCaster()
	local entries = Menu.Entries()
	local parts = Menu.Parts()
	local size, tabH = SideSize(bz)
	local picked
	for i, e in ipairs(entries) do if e.picked then picked = i end end
	local room = h + outT - Lay.SIDE_TOP
	local list, left = Lay.SideFit(#entries, picked, #parts, room, tabH, Lay.SIDE_GAP)
	local k, used = 0, {}
	local function Place(t)
		k = k + 1
		t:ClearAllPoints()
		t:SetPoint("TOPRIGHT", win, "TOPLEFT", -outL, -(Lay.SideY(k, tabH, Lay.SIDE_GAP) - outT))
		t:Show()
		return t
	end
	local on = {}
	for _, index in ipairs(list) do
		on[index] = true
		local t = SideTab(k + 1)
		DressSide(t, bz, size, tabH, "entry", entries[index])
		Place(t)
	end
	if left > 0 then
		local set, rest = {}, {}
		for i, e in ipairs(entries) do
			if not on[i] then
				set[e.key] = true
				rest[#rest + 1] = e
			end
		end
		local t = SideTab(k + 1)
		DressSide(t, bz, size, tabH, "plus")
		t.text:SetText(("+%d"):format(left))
		t.set, t.left = set, rest
		Place(t)
	end
	for _, part in ipairs(parts) do
		DressSide(SideTab(k + 1), bz, size, tabH, part.kind, part)
		Place(sideTabs[k + 1])
	end
	for i = k + 1, #sideTabs do
		sideTabs[i]:Hide()
		sideTabs[i].holder:Hide()
	end
	for i = 1, k do used[i] = sideTabs[i] end
	shownTabs.side = used
	-- (The tours' "professions": round the ones that show.)
	if k > 0 then
		sideBox:ClearAllPoints()
		sideBox:SetPoint("TOPLEFT", used[1], "TOPLEFT", 0, 0)
		sideBox:SetPoint("BOTTOMRIGHT", used[k], "BOTTOMRIGHT", 0, 0)
		sideBox:Show()
	else
		sideBox:Hide()
	end
	return k > 0 and size or 0
end

-- ---------------------------------------------------------------------------------------------
-- The page tabs under the window
-- ---------------------------------------------------------------------------------------------

-- TabSystemButtonArtTemplate's pieces, hanging below (not turned: its isTabOnTop is false).
local TAB_ART = {
	{ "Left", "uiframe-tab-left", "TOPLEFT", 0 }, { "Right", "uiframe-tab-right", "TOPRIGHT", 6 },
	{ "LeftActive", "uiframe-activetab-left", "TOPLEFT", 0 }, { "RightActive", "uiframe-activetab-right", "TOPRIGHT", 7 },
}
local function TabArt(t)
	local a = t.art
	if a then return a end
	a = {}
	for _, p in ipairs(TAB_ART) do
		local tex = t:CreateTexture(nil, "BACKGROUND")
		Atlas(tex, p[2], true)
		tex:SetPoint(p[3], t, p[3], p[4], 0)
		a[p[1]] = tex
	end
	a.Middle = t:CreateTexture(nil, "BACKGROUND")
	Atlas(a.Middle, "_uiframe-tab-center", true)
	a.Middle:SetPoint("TOPLEFT", a.Left, "TOPRIGHT")
	a.Middle:SetPoint("TOPRIGHT", a.Right, "TOPLEFT")
	a.MiddleActive = t:CreateTexture(nil, "BACKGROUND")
	Atlas(a.MiddleActive, "_uiframe-activetab-center", true)
	a.MiddleActive:SetPoint("TOPLEFT", a.LeftActive, "TOPRIGHT")
	a.MiddleActive:SetPoint("TOPRIGHT", a.RightActive, "TOPLEFT")
	for _, k in ipairs({ "Middle", "MiddleActive" }) do
		if a[k].SetHorizTile then a[k]:SetHorizTile(true) end
	end
	-- (The hover: the unpicked art again, added at 0.4.)
	a.hi = {}
	for _, k in ipairs({ "Left", "Middle", "Right" }) do
		local tex = t:CreateTexture(nil, "HIGHLIGHT")
		Atlas(tex, k == "Left" and "uiframe-tab-left" or (k == "Right" and "uiframe-tab-right" or "_uiframe-tab-center"), true)
		tex:SetAllPoints(a[k])
		tex:SetBlendMode("ADD")
		tex:SetAlpha(0.4)
		a.hi[k] = tex
	end
	t.art = a
	return a
end

local function TabInk(t)
	if t.pl then
		t.text:SetTextColor(Color(t:IsMouseOver() and "VALUE" or "ACCENT"))
		return
	end
	-- (Blizzard Style: the game's gold, white when picked; GameFontNormal / GameFontHighlight.)
	local picked = t.key == W.tab
	if t.bzOn then
		t.text:SetTextColor(Color((picked or t:IsMouseOver()) and "VALUE" or "TITLE"))
	else
		t.text:SetTextColor(Color((picked or t:IsMouseOver()) and "VALUE" or "LABEL"))
	end
end

local function BottomTab(i)
	local t = bottomTabs[i]
	if t then return t end
	t = CreateFrame("Button", nil, W.win)
	t.holder = Holder(t)
	t.text = Text(t, "small")
	t.text:SetWordWrap(false)
	t.line = t:CreateTexture(nil, "ARTWORK")
	t.line:SetHeight(2)
	t.line:SetPoint("TOPLEFT", t, "TOPLEFT", 6, 0)
	t.line:SetPoint("TOPRIGHT", t, "TOPRIGHT", -6, 0)
	t.line:Hide()
	t:SetScript("OnEnter", TabInk)
	t:SetScript("OnLeave", TabInk)
	t:SetScript("OnClick", function(self)
		if self.pl then
			if W.plButton then W.plButton:Click() end
		elseif self.key and ns.Window then
			ns.Window.SetTab(self.key)
		end
	end)
	bottomTabs[i] = t
	return t
end

local function HideTabs()
	for _, t in ipairs(bottomTabs) do t:Hide() t.holder:Hide() end
	wipe(tabOf)
	shownTabs.bottom = {}
end

-- The page tabs, from the compact window's own (their words as they read now: "Queue (3)"), and
-- "Open Professionally Lost" where the Leveling Guide is handed to it. Returns how far they hang
-- below the frame's art.
local function PaintTabs(win, bz, outL, outB)
	local pieces = {}
	for _, b in ipairs(W.tabButtons or {}) do
		if b:IsShown() then pieces[#pieces + 1] = { key = b.key, text = b.text:GetText() } end
	end
	local pl = W.plButton
	if pl and pl:IsShown() then pieces[#pieces + 1] = { pl = true, text = pl.text:GetText() } end
	wipe(tabOf)
	local list = {}
	if #pieces == 0 then
		HideTabs()
		return 0
	end
	local words = {}
	for i, p in ipairs(pieces) do
		local t = BottomTab(i)
		t.text:SetText(p.text or "")
		words[i] = t.text:GetUnboundedStringWidth()
	end
	local widths, xs = Lay.TabWidths(words, bz)
	local tabH = bz and Lay.TAB_H or Lay.OWN_TAB_H
	-- (Blizzard Style: 22 in and 2 up from the art's foot; another look: flush under the frame.)
	local x0 = bz and (Lay.TAB_X - outL) or 13
	local y0 = bz and (Lay.TAB_Y - outB) or 0
	for i, p in ipairs(pieces) do
		local t = BottomTab(i)
		t.key, t.pl = p.key, p.pl
		t.bzOn = bz
		t:SetSize(widths[i], tabH)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", win, "BOTTOMLEFT", x0 + xs[i], y0)
		t.holder:SetShown(not bz)
		local picked = p.key ~= nil and p.key == W.tab
		local a = bz and TabArt(t) or t.art
		if a then
			a.Left:SetShown(bz and not picked)
			a.Middle:SetShown(bz and not picked)
			a.Right:SetShown(bz and not picked)
			a.LeftActive:SetShown(bz and picked)
			a.MiddleActive:SetShown(bz and picked)
			a.RightActive:SetShown(bz and picked)
			for _, tex in pairs(a.hi) do tex:SetShown(bz and not picked) end
		end
		-- (The words: centered, 0 up when picked and 5 when not, TabSystemTemplates.lua:32-41 with the
		-- professions' textOffsetY 3; in another look centered, the picked one's accent line along
		-- its top, where it meets the window.)
		t.text:ClearAllPoints()
		t.text:SetPoint("CENTER", t, "CENTER", 0, bz and (picked and 0 or 5) or 0)
		t.line:SetShown(not bz and picked)
		t.line:SetColorTexture(API.Accent())
		TabInk(t)
		t:Show()
		if p.key then
			tabOf[p.key] = t
			list[#list + 1] = t
		end
	end
	for i = #pieces + 1, #bottomTabs do
		bottomTabs[i]:Hide()
		bottomTabs[i].holder:Hide()
	end
	shownTabs.bottom = list
	-- (How far below our frame they reach: they hang from y0 under it.)
	return tabH - y0
end

-- ---------------------------------------------------------------------------------------------
-- The head: portrait, title, rank bar, link button
-- ---------------------------------------------------------------------------------------------

local function PaintHead(P, bz, outL, outT)
	local win, header = P.win, P.header
	-- (The compact window's header pieces, left of its buttons, away.)
	W.named = false
	if W.Chips then W.Chips.Hide() end
	for _, k in ipairs({ "nameButton", "iconHit", "headIcon", "headDot", "headSkill", "skillLine", "skillBack", "headUnder" }) do
		local f = W[k]
		if f then f:Hide() end
	end
	local icon, name, skill, most, line, note = Shown()
	-- Portrait.
	portrait:ClearAllPoints()
	if bz then
		portrait:SetSize(62, 62)
		portrait:SetPoint("TOPLEFT", win, "TOPLEFT", -outL - 5, outT + 7)
		Atlas(portrait.ring, "UI-Frame-PortraitMetal-CornerTopLeft", true)
		portrait.ring:ClearAllPoints()
		portrait.ring:SetPoint("TOPLEFT", portrait, "TOPLEFT", -8, 9)
		portrait.ring:Show()
	else
		portrait:SetSize(28, 28)
		portrait:SetPoint("LEFT", header, "LEFT", 8, 0)
		portrait.ring:Hide()
	end
	portrait.icon:SetTexture(icon)
	portrait.icon:SetShown(icon ~= nil)
	portrait:Show()
	Lay.PaintReady()
	-- Title: in Blizzard Style the title bar's (Host.Chrome, asked again by WindowBlizzard.lua's
	-- Paint); else ours, centered in the header, a size down rather than cut.
	local text = Lay.TitleText()
	local room = Lay.Width(Lay.detailW) - 2 * 110
	local pick
	for _, size in ipairs({ "head", "body" }) do
		local fs = titles[size]
		fs:SetText(text)
		fs:SetTextColor(Color("VALUE"))
		fs:SetWidth(room)
		fs:Hide()
		if not pick and fs:GetUnboundedStringWidth() <= room then pick = fs end
	end
	if not bz then (pick or titles.body):Show() end
	-- Rank bar.
	local hasSkill = type(most) == "number" and most > 0
	rank:ClearAllPoints()
	if not (hasSkill or note) then
		rank:Hide()
		linkButton:Hide()
		return
	end
	local width
	if bz then
		width = min(Lay.RANK_W, Lay.Width(Lay.detailW) - (110 - outL) - 40)
		rank:SetPoint("TOPLEFT", win, "TOPLEFT", 110 - outL, -40 + outT)
		rank:SetSize(width, 18)
	else
		width = Lay.Width(Lay.detailW) - 16
		rank:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -(36 + 4))
		rank:SetSize(width, 16)
	end
	local ratio = hasSkill and max(0, min(1, (skill or 0) / most)) or 0
	rank.bg:SetShown(bz)
	rank.border:SetShown(bz)
	rank.track:SetShown(not bz)
	rank.bar:SetShown(not bz and hasSkill and ratio > 0)
	rank.fill:SetShown(bz and hasSkill and ratio > 0)
	if bz then
		Atlas(rank.bg, "Professions-skillbar-bg", true)
		Atlas(rank.border, "Professions-skillbar-frame", true)
		rank.bg:SetWidth(width - 2)
		rank.border:SetWidth(width - 2)
		-- (The fill: the first frame of the profession's flipbook, cut at the skill, not squeezed:
		-- the game masks it the same way. Two columns of 34-high frames.)
		local kit = Lay.KITS[line]
		local atlas = kit and ("Skillbar_Fill_Flipbook_" .. kit) or nil
		local ah = atlas and select(2, AtlasSize(atlas)) or nil
		if not ah then
			atlas = "Skillbar_Fill_Flipbook_DefaultBlue"
			ah = select(2, AtlasSize(atlas))
		end
		if ratio > 0 and Atlas(rank.fill, atlas) then
			local full = width - 12
			rank.fill:SetSize(max(1, full * ratio), 18)
			rank.fill:SetTexCoord(0, 0.5 * ratio, 0, ah and ah > 0 and min(1, 34 / ah) or 1)
		else
			rank.fill:Hide()
		end
	else
		rank.track:SetColorTexture(1, 1, 1, 0.08)
		rank.bar:SetColorTexture(API.Accent())
		rank.bar:SetAlpha(0.6)
		rank.bar:SetWidth(max(1, width * ratio))
	end
	rank.text:ClearAllPoints()
	rank.text:SetPoint("CENTER", rank, "CENTER", 0, bz and -3 or 0)
	if note then
		rank.text:SetText(note)
		rank.text:SetTextColor(Color("WARN"))
	else
		local fmt = type(_G.TRADESKILL_NAME_RANK) == "string" and _G.TRADESKILL_NAME_RANK or "%s %d/%d"
		local ok, words = pcall(string.format, fmt, name or "", skill or 0, most)
		rank.text:SetText(ok and words or ("%s %d/%d"):format(name or "", skill or 0, most))
		rank.text:SetTextColor(Color("VALUE"))
	end
	rank:Show()
	-- (The link button: the game's, for your own open profession, in Blizzard Style.)
	local link = bz and W.Own()
	linkButton:SetShown(link and true or false)
	if link then
		linkButton:ClearAllPoints()
		linkButton:SetPoint("LEFT", rank, "RIGHT", -2, -4)
		linkButton.Face(linkButton)
	end
end

-- The menu opened or closed (WindowMenu.lua's Open and Close): the Alts, Cooldowns and Tracking
-- tabs lit while their page shows, the others not.
function Lay.Relight()
	for _, t in ipairs(sideTabs) do
		if t:IsShown() and (t.tabKind == "alts" or t.tabKind == "cooldowns" or t.tabKind == "tracking") then
			t.lit = W.gather == t.tabKind
			SideLit(t, t:IsMouseOver())
		end
	end
end

function Lay.PaintReady()
	if not portrait then return end
	local ready = Menu.CooldownReady()
	portrait.dot:ClearAllPoints()
	portrait.dot:SetPoint("CENTER", portrait, "TOPRIGHT", -6, -6)
	portrait.dot:SetColorTexture(Color("GOOD"))
	portrait.dot:SetShown(ready and portrait:IsShown() or false)
	for _, t in ipairs(sideTabs) do
		if t.tabKind == "cooldowns" then t.ready:SetShown(ready) end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The list's rows and the craft bar
-- ---------------------------------------------------------------------------------------------

-- A list row (e nil: put away). The arrow before the name, the count after it ("[10]") in the
-- name's white (PROFESSION_RECIPE_COLOR), the guide's square at the row's right end; the compact
-- window's look comes back when the layout is off.
function Lay.Row(r, e)
	local on = e ~= nil and not e.cat and Lay.Active()
	local a = r.__lay
	if on and not a then
		a = { arrow = r:CreateTexture(nil, "OVERLAY"), ups = Text(r, "small") }
		a.ups:SetJustifyH("RIGHT")
		a.ups:SetWordWrap(false)
		r.__lay = a
	end
	if not a then return end
	if not on then
		a.arrow:Hide()
		a.ups:Hide()
		if a.moved then
			a.moved = nil
			r.step:ClearAllPoints()
			r.step:SetPoint("LEFT", r, "LEFT", 11, 0)
		end
		return
	end
	-- The arrow (Init: SkillUps at -9, its icon on its right; the name 4 after it).
	local atlas = Lay.Arrow(e.step, e.can)
	a.arrow:ClearAllPoints()
	if atlas and pcall(a.arrow.SetAtlas, a.arrow, atlas, true) then
		a.arrow:SetPoint("RIGHT", r, "LEFT", 20, e.step == 1 and 1 or 0)
		a.arrow:Show()
	else
		a.arrow:Hide()
	end
	-- (An orange one giving more than one point: how many, before the arrow.)
	local ups = tonumber(e.ups) or 0
	if atlas and e.step == 1 and ups > 1 then
		a.ups:ClearAllPoints()
		a.ups:SetPoint("RIGHT", a.arrow, "LEFT", 0, 1)
		a.ups:SetText(tostring(ups))
		a.ups:SetTextColor(Doc.DiffColor(1))
		a.ups:Show()
	else
		a.ups:Hide()
	end
	-- The right end: the gear arrow, then the guide's square.
	local edge, gap = r, -10
	local point = "RIGHT"
	if r.up:IsShown() then
		r.up:ClearAllPoints()
		r.up:SetPoint("RIGHT", r, "RIGHT", -10, 0)
		edge, gap, point = r.up, -4, "LEFT"
	end
	if r.step:IsShown() then
		r.step:ClearAllPoints()
		r.step:SetPoint("RIGHT", edge, point, gap, 0)
		a.moved = true
		edge, gap, point = r.step, -4, "LEFT"
	end
	r.right:Hide()
	local text = e.name .. ((e.count or 0) > 0 and (" [" .. e.count .. "]") or "")
	local vr, vg, vb = Color("VALUE")
	local function Fit(fs)
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", r, "LEFT", 24, 0)
		fs:SetPoint("RIGHT", edge, point, gap, 0)
		fs:SetText(text)
		fs:SetTextColor(vr, vg, vb)
		fs:Show()
		return not fs:IsTruncated()
	end
	r.nameSmall:Hide()
	if Fit(r.name) then return end
	r.name:Hide()
	if Fit(r.nameSmall) then return end
	-- (Too long even at 12: the name alone; the count is on Create All.)
	text = e.name
	Fit(r.nameSmall)
end

-- The craft bar's buttons on the game's places (WindowList.lua's FitButtons asks): Create All [N]
-- at the left, the spinner and Create at the right, Queue in the details' corner. True when Create
-- All needs a row of its own above (a long word), false when one row holds them, nil when it isn't
-- the layout's to do (off, or the bar shows a run's buttons: then the compact places stand).
function Lay.FitBar(cb, count)
	if not (Lay.Active() and cb.queue:IsShown()) then return nil end
	local least = ns.WinState.LEAST
	local spell = S.recipe
	local info = spell and TS("GetRecipeInfo", spell) or nil
	local enchant = type(info) == "table" and info.isEnchantingRecipe == true
	local can = spell and Craft.Count(spell) or 0
	cb.max.text:SetText((enchant and L["Enchant All [%d]"] or L["Create All [%d]"]):format(can))
	cb.make.FitWidth(least.make)
	cb.max.FitWidth(80)
	cb.queue.FitWidth(least.queue)
	local pad = Lay.BAR_PAD
	local mid = 22                       -- the buttons' row: the bar's foot + 22 (its 44 / 2)
	local two = Lay.BarTwoRows({ all = cb.max:GetWidth(), minus = cb.minus:GetWidth(), count = count:GetWidth(),
		plus = cb.plus:GetWidth(), make = cb.make:GetWidth() }, Lay.detailW or Lay.DETAIL_W)
	cb.make:ClearAllPoints()
	cb.make:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -pad, mid)
	cb.plus:ClearAllPoints()
	cb.plus:SetPoint("RIGHT", cb.make, "LEFT", -12, 0)
	count:ClearAllPoints()
	count:SetPoint("RIGHT", cb.plus, "LEFT", -4, 0)
	cb.minus:ClearAllPoints()
	cb.minus:SetPoint("RIGHT", count, "LEFT", -4, 0)
	cb.max:ClearAllPoints()
	cb.max:SetPoint("LEFT", cb, "BOTTOMLEFT", pad, two and (mid + 32) or mid)
	-- (Queue: in the details' bottom right corner, where the game's Track Recipe box sits.)
	cb.queue:ClearAllPoints()
	local side = W.side
	if side and side:IsShown() then
		cb.queue:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -10, 10)
	else
		cb.queue:SetPoint("RIGHT", cb.minus, "LEFT", -8, 0)
	end
	return two
end

-- ---------------------------------------------------------------------------------------------
-- The details: the game's schematic, then ours
-- ---------------------------------------------------------------------------------------------

local SLOT, SLOT_ICON = 42, 37

local function MakeHead(child)
	local f = CreateFrame("Button", nil, child)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(47, 47)
	f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.name = Text(f, "head")
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(true)
	f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, -4)
	f:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(self.tip, GameTooltip)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	f:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick("CHATLINK") then ns.InsertLink(self.link) end
	end)
	return f
end

local function MakeSlot(child)
	local f = CreateFrame("Button", nil, child)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetSize(SLOT_ICON + 2, SLOT_ICON + 2)
	f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(SLOT_ICON - 4, SLOT_ICON - 4)
	f.icon:SetPoint("CENTER", f.bg, "CENTER", 0, 0)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetAllPoints(f.bg)
	f.name = Text(f, "body")
	f.name:SetJustifyH("LEFT")
	f.name:SetWordWrap(true)
	f.name:SetPoint("TOPLEFT", f.bg, "TOPRIGHT", 7, -3)
	f.right = Text(f, "small", "RIGHT")
	f.right:SetWordWrap(false)
	f.sub = Text(f, "small")
	f.sub:SetJustifyH("LEFT")
	f.sub:SetWordWrap(true)
	f:SetScript("OnEnter", function(self)
		if not self.itemID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
	f:SetScript("OnClick", function(self)
		if not (self.itemID and IsModifiedClick("CHATLINK")) then return end
		local link = C_Item and C_Item.GetItemLinkByID and C_Item.GetItemLinkByID(self.itemID) or nil
		if link then ns.InsertLink(link) end
	end)
	return f
end

-- What you hold of an item in your bags (where crafting takes it from).
local function InBags(itemID)
	if ns.Store and ns.Store.Count then
		local have = ns.Store.Count(itemID)
		if type(have) == "table" and type(have.bags) == "number" then return have.bags end
	end
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID)
		if ok and type(n) == "number" then return n end
	end
	return 0
end

local function Description(spell)
	local C = rawget(_G, "C_Spell")
	if type(C) ~= "table" or type(C.GetSpellDescription) ~= "function" then return nil end
	local ok, text = pcall(C.GetSpellDescription, spell)
	if ok and type(text) == "string" and text ~= "" then return text end
	return nil
end

local function Schematic(d, shown)
	local spell = shown or S.recipe
	if not spell then
		d:Line(List.Count() == 0 and L["No recipe matches."] or L["Pick a recipe."], "body", "OFF")
		return
	end
	local bz = Bz()
	local child = d.child
	local info = TS("GetRecipeInfo", spell)
	local out = TS("GetRecipeOutputItemData", spell)
	local itemID = type(out) == "table" and out.itemID or nil
	local name = type(info) == "table" and info.name or Doc.RecipeName(spell)
	local icon = (type(out) == "table" and out.icon) or (type(info) == "table" and info.icon) or nil
	-- The recipe: its big icon and its name beside it (OutputIcon, OutputText).
	local head = d:Take("lay-head", function() return MakeHead(child) end)
	local wide = d.width - 2 * d.pad
	head:SetPoint("TOPLEFT", child, "TOPLEFT", d.pad, -d.y)
	head.icon:SetTexture(icon)
	head.name:SetWidth(max(40, wide - 47 - 12))
	head.name:SetText(name)
	head.name:SetTextColor(Color("VALUE"))
	head.tip = itemID and Doc.ItemTip(itemID) or Doc.SpellTip(spell)
	head.link = (type(out) == "table" and out.hyperlink) or TS("GetRecipeLink", spell)
	local tall = max(47, 4 + ceil(head.name:GetStringHeight()))
	head:SetSize(wide, tall)
	d:Gap(tall + 8)
	-- Its description, then how many it makes, the tools it needs, its cooldown, why it can't be made.
	local desc = Description(spell)
	if desc then d:Line(desc, "small", "VALUE") end
	local schematic = TS("GetRecipeSchematic", spell, false)
	if type(schematic) == "table" and schematic.quantityMax and schematic.quantityMax > 1 then
		local lo, hi = schematic.quantityMin or 1, schematic.quantityMax
		d:Line(L["Makes %s at a time."]:format(lo == hi and tostring(lo) or (lo .. "-" .. hi)), "small", "TEXT")
	end
	local reqs = TS("GetRecipeRequirements", spell)
	if type(reqs) == "table" and #reqs > 0 then
		local words = {}
		for _, r in ipairs(reqs) do
			if type(r) == "table" and r.name then
				local cr, cg, cb = Color(r.met and "GOOD" or "BAD")
				words[#words + 1] = Doc.Hex(cr, cg, cb) .. r.name .. "|r"
			end
		end
		if #words > 0 then d:Line(L["Needs %s"]:format(table.concat(words, ", ")), "small", "TEXT") end
	end
	local cd = TS("GetRecipeCooldown", spell)
	if type(cd) == "number" and cd > 0 then
		local words = cd >= 3600 and L["Ready in %d h %d min"]:format(floor(cd / 3600), floor(cd % 3600 / 60))
			or L["Ready in %d min"]:format(max(1, floor(cd / 60)))
		d:Line(words, "small", "WARN")
	end
	if type(info) == "table" and info.disabled and info.disabledReason then
		d:Line(info.disabledReason, "small", "BAD")
	end
	-- "Reagents:", a slot for each: have/need and its name, then ours: where you hold it and what
	-- it costs, with the price at the right.
	d:Gap(6)
	d:Line(L["Reagents:"], "small", "TITLE")
	local cost = Calc.Cost(spell)
	local chance = Calc.Chance(spell, S.skill or 0, S.max)
	if #cost.rows == 0 then
		d:Line(L["It takes no materials."], "small", "OFF")
	end
	for _, m in ipairs(cost.rows) do
		local slot = d:Take("lay-slot", function() return MakeSlot(child) end)
		slot:SetPoint("TOPLEFT", child, "TOPLEFT", d.pad, -d.y)
		local mname, micon = Doc.ItemName(m.itemID, d)
		slot.itemID = m.itemID
		slot.icon:SetTexture(micon)
		slot.bg:SetShown(bz)
		slot.border:SetShown(bz)
		if bz then
			Atlas(slot.bg, "Professions-Slot-bg")
			Atlas(slot.border, "Professions-Slot-Frame")
		end
		local held = InBags(m.itemID)
		local enough = held >= m.count
		slot.right:SetText(m.total and Calc.Money(m.total) or "?")
		slot.right:SetTextColor(Color(m.total and "VALUE" or "OFF"))
		local rw = ceil(slot.right:GetStringWidth())
		local textW = max(40, wide - (SLOT_ICON + 2) - 7 - rw - 6)
		slot.name:SetWidth(textW)
		-- (TRADESKILL_REAGENT_COUNT's "have/need", then the name; gray while you're short, as the game's.)
		local countText = ("%d/%d"):format(held, m.count)
		slot.name:SetText(enough and (countText .. " " .. mname) or (countText .. " " .. (mname:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))))
		slot.name:SetTextColor(Color(enough and "VALUE" or "OFF"))
		slot.right:ClearAllPoints()
		slot.right:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -3)
		local sub, subInk = Pages.MaterialSub(m, true)
		local nameH = ceil(slot.name:GetStringHeight())
		slot.sub:ClearAllPoints()
		slot.sub:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -2)
		slot.sub:SetWidth(max(40, wide - (SLOT_ICON + 2) - 7))
		slot.sub:SetText(sub)
		slot.sub:SetTextColor(Color(subInk))
		local h = max(SLOT, 3 + nameH + 2 + ceil(slot.sub:GetStringHeight()) + 2)
		slot:SetSize(wide, h)
		d:Gap(h + 4)
	end
	if #cost.rows > 0 then Pages.CostFoot(d, spell, cost, chance, { have = true }) end
	-- Ours: the skill-up chance, the value, and who else knows it.
	Pages.Skill(d, spell)
	Pages.Worth(d, spell)
	local who = ns.Store and ns.Store.WhoKnows(spell, false, true)
	if type(who) == "table" and #who > 0 then
		d:Heading(L["Also Known By"])
		d:Line(table.concat(who, ", "), "small", "TEXT")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Laying the window out
-- ---------------------------------------------------------------------------------------------

-- The details' width now (Lay.DetailWidth): Create All measured with "[999]" on it, in both its
-- words (Create All, Enchant All), the spinner and Create as they are.
local function MeasureDetail()
	local cb = W.craftBar
	if not (cb and cb.max and cb.max.text and cb.max.FitWidth and cb.count and cb.make and cb.make.FitWidth) then
		return Lay.DETAIL_W
	end
	local keep = cb.max.text:GetText()
	local widest = 0
	for _, word in ipairs({ L["Create All [%d]"], L["Enchant All [%d]"] }) do
		cb.max.text:SetText(word:format(999))
		cb.max.FitWidth(80)
		widest = max(widest, cb.max:GetWidth())
	end
	cb.max.text:SetText(keep)
	cb.max.FitWidth(80)
	cb.make.FitWidth(ns.WinState.LEAST.make)
	return Lay.DetailWidth(Lay.BarNeed({ all = widest, minus = cb.minus:GetWidth(), count = cb.count:GetWidth(),
		plus = cb.plus:GetWidth(), make = cb.make:GetWidth() }))
end

-- The clamp: the art, the side tabs and the page tabs on the screen.
local function Clamp(win, sideW, tabsH)
	if not win.SetClampRectInsets then return end
	local l, r, t, b = Outset(win)
	win:SetClampRectInsets(Lay.ClampInsets(l, r, t, b, sideW, tabsH))
end

-- The compact window's places, back (the layout turned off or the window rolled up). Each as the
-- file that made it placed it: Window.lua's BuildBody and BuildGrip, WindowList.lua's List.Build.
local function Restore(P)
	laid = false
	local PAD = ns.WinState.PAD
	local win, col, body, side = P.win, P.col, P.body, P.side
	col:ClearAllPoints()
	col:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -ns.WinState.HEADER)
	col:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	side:ClearAllPoints()
	side:SetPoint("TOPLEFT", col, "TOPRIGHT", 0, 0)
	side:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
	for _, box in ipairs({ W.search, P.pageSearch, P.altDoc.search }) do
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", body, "TOPLEFT", PAD - 2, -8)
		box:SetPoint("RIGHT", body, "RIGHT", -(PAD - 2), 0)
	end
	local cb = W.craftBar
	cb:ClearAllPoints()
	cb:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	cb:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	if win.grip then
		win.grip:ClearAllPoints()
		win.grip:SetPoint("BOTTOM", col, "BOTTOM", 0, 0)
	end
	W.skillBack:Show()
	W.headUnder:Show()
	if W.Blz and W.Blz.listInset then W.Blz.listInset:SetShown(Bz()) end
	if win.SetClampRectInsets then
		local l, r, t, b = Outset(win)
		win:SetClampRectInsets(-l, r, t, -b)
	end
end

local function HideAll()
	if not built then return end
	portrait:Hide()
	for _, fs in pairs(titles) do fs:Hide() end
	rank:Hide()
	linkButton:Hide()
	listBox:Hide()
	sideArt:Hide()
	HideSide()
	HideTabs()
end

-- The details' page: no profession open, a missing recipe's sources on Missing, else the recipe.
-- Whether the game knows a recipe as one of the open profession's (its info has a name).
local function Ask(spell)
	local info = TS("GetRecipeInfo", spell)
	return type(info) == "table" and info.name ~= nil
end

local function DetailPage(P)
	return function(d)
		if S.mode ~= "win" then return P.NoSession(d) end
		if W.tab == "missing" then return Pages.MissingDetail(d, P.GetPick()) end
		-- (The Leveling Guide: the recipe its current step makes, not the one last picked in the
		-- list; that one again when the guide has no step to make: trained out, or a rank to learn.)
		if W.tab == "guide" then
			local step = List.StepSpell and List.StepSpell() or nil
			if step and Ask(step) then return Schematic(d, step) end
		end
		return Schematic(d)
	end
end

-- Lays the window out, from Window.lua's Render (after its tabs are worked out). True when it did;
-- false when the layout is off or the window rolled up: its places are back, and Render goes on.
function Lay.Shape(P)
	if not P then return false end
	if not Lay.Active() then
		if laid then Restore(P) end
		HideAll()
		return false
	end
	Build(P)
	laid = true
	local win, col, body, side = P.win, P.col, P.body, P.side
	local bz = Bz()
	local other = W.alt ~= nil or W.gather ~= nil
	local open = S.mode == "win"
	local recipes = not other and W.tab == "recipes"
	local top = Lay.ListTop(bz)
	Lay.detailW = MeasureDetail()
	W.col = Lay.detailW
	-- The header: Roll Up stays, Details goes (always open here); the compact window's left side away.
	P.DrawRoll(W.rollButton, false)
	W.rollButton:SetShown(List.CanRoll())
	W.detailsButton:Hide()
	if W.Blz then W.Blz.Paint(false, true) end
	-- (How far the frame's art reaches, read only now: Blizzard Style's title bar is put on by the
	-- Paint above, and the window's first drawing read 0 before it, which laid the rank bar and the
	-- list 24 too low over each other until a tab was clicked.)
	local outL, _, outT, outB = Outset(win)
	-- (The window's first drawing after it opens: drawn once more on the next frame, when its art
	-- and size have settled, as a click on a tab used to do.)
	if not Lay.settled and not Lay.retried then
		Lay.retried = true
		C_Timer.After(0, function()
			Lay.retried = nil
			Lay.settled = true
			if W.win and W.win:IsShown() and ns.Window then ns.Window.Render() end
		end)
	end
	if not win.__laySettle then
		win.__laySettle = true
		win:HookScript("OnHide", function() Lay.settled = nil end)
	end
	if W.Blz and W.Blz.listInset then W.Blz.listInset:Hide() end
	P.tabRow:Hide()
	PaintHead(P, bz, outL, outT)
	-- Its size: the game's width, the player's height.
	local foot = List.PaintCraftBar()
	-- (Tall enough for every side tab: your professions, Camping, Alts, Cooldowns and Tracking.)
	local _, sideH = SideSize(bz)
	local least = Lay.SideNeed(#Menu.Entries() + #Menu.Parts(), sideH, Lay.SIDE_GAP, outT)
	local w, h = Lay.Size(P.Height(), least, Lay.Width(Lay.detailW))
	P.Size("layout", foot > 0 and foot or ns.WinState.FOOT, w, h)
	col:ClearAllPoints()
	col:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -top)
	col:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
	body:ClearAllPoints()
	body:SetAllPoints(col)
	-- The list's column, the whole width on a page with nothing to detail (an alt's, a gathering
	-- profession's, Camping).
	listBox:ClearAllPoints()
	listBox:SetPoint("TOPLEFT", col, "TOPLEFT", Lay.LIST_X, 0)
	if other then
		listBox:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -Lay.RIGHT, 2)
	else
		listBox:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", Lay.LIST_X, 2)
		listBox:SetWidth(Lay.LIST_W)
	end
	listBox:Show()
	if listInset then listInset:SetShown(bz) end
	if win.grip then
		win.grip:ClearAllPoints()
		win.grip:SetPoint("BOTTOM", listBox, "BOTTOM", 0, -2)
		win.grip:Show()
	end
	-- The craft bar at the details' foot, the details over it.
	local cb = W.craftBar
	local detailLeft = Lay.LIST_X + Lay.LIST_W + Lay.GAP
	cb:ClearAllPoints()
	cb:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", detailLeft, 0)
	cb:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -Lay.RIGHT, 0)
	List.PaintSummary(false)
	side:ClearAllPoints()
	side:SetPoint("TOPLEFT", col, "TOPLEFT", detailLeft, 0)
	if foot > 0 then
		side:SetPoint("BOTTOMRIGHT", cb, "TOPRIGHT", 0, 0)
	else
		side:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -Lay.RIGHT, 2)
	end
	side:SetShown(not other)
	-- (Queue sits in the details' corner: placed again now the details are.)
	if foot > 0 and cb.queue:IsShown() then
		cb.queue:ClearAllPoints()
		cb.queue:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -10, 10)
	end
	-- The profession's own background in the details (Blizzard Style, your own profession).
	local kit = Lay.KITS[S.line or S.game]
	local art = bz and open and not other and W.tab ~= "missing" and kit
		and Atlas(sideArt, "Professions-Recipe-Background-" .. kit)
	sideArt:SetShown(art and true or false)
	-- The search and Filter, the list.
	local fb = bz and filterBz or filterOwn
	filterBz:SetShown(bz and recipes and open)
	filterOwn:SetShown(not bz and recipes and open)
	fb:ClearAllPoints()
	fb:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -8, -9)
	if bz then
		filterBz:SetWidth(ceil(filterBz.text:GetUnboundedStringWidth()) + 60)
		filterBz.Face(filterBz)
	elseif filterOwn.FitWidth then
		filterOwn.FitWidth(72)
	end
	resetButton:ClearAllPoints()
	resetButton:SetPoint("CENTER", fb, "TOPRIGHT", -3, 0)
	resetButton:SetShown(recipes and open and FilterOn())
	local search = W.search
	search:ClearAllPoints()
	search:SetPoint("TOPLEFT", listBox, "TOPLEFT", 13, -8)
	search:SetPoint("RIGHT", fb, "LEFT", -4, 0)
	search:SetShown(recipes and open)
	for _, b in ipairs(W.filters) do b:Hide() end
	local sh = search:GetHeight()
	sh = (sh and sh > 0) and sh or 24
	local list = W.list
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", listBox, "TOPLEFT", 8, -(8 + sh + 4))
	list:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -8, 5)
	list:SetShown(recipes and open)
	-- The other pages in the list's column, their searches where the list's is.
	local pageSearch, pageDoc, altDoc = P.pageSearch, P.pageDoc, P.altDoc
	for _, box in ipairs({ pageSearch, altDoc.search }) do
		box:ClearAllPoints()
		box:SetPoint("TOPLEFT", listBox, "TOPLEFT", 13, -8)
		box:SetPoint("RIGHT", listBox, "RIGHT", -8, 0)
	end
	pageSearch:SetShown(not other and W.tab == "missing")
	altDoc.search:SetShown(W.alt ~= nil)
	pageDoc.scroll:SetShown(not other and not (recipes and open))
	altDoc.scroll:SetShown(other)
	-- The side tabs and the page tabs, and the clamp round them.
	local sideW = PaintSide(win, h, bz, outL, outT)
	local tabsH = other and 0 or PaintTabs(win, bz, outL, outB)
	if other then HideTabs() end
	Clamp(win, sideW, tabsH)
	-- Drawing.
	if not other then P.Draw(P.detail, DetailPage(P)) end
	if other then
		local scroll = altDoc.scroll
		scroll:ClearAllPoints()
		scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 0, W.alt and -List.UnderSearch(altDoc.search) or -4)
		scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", 0, 4)
		P.Draw(altDoc, W.alt and Menu.AltPage or (W.gather == W.CAMP and Menu.CampPage) or Menu.PartPage(W.gather) or Menu.GatherPage)
		return true
	end
	if recipes and open then
		List.Paint()
		return true
	end
	local scroll = pageDoc.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", listBox, "TOPLEFT", 0, W.tab == "missing" and -List.UnderSearch(pageSearch) or -4)
	scroll:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", 0, 4)
	local ctx = P.pageCtx
	if not open then
		P.Draw(pageDoc, P.NoSession)
	elseif W.tab == "guide" then
		P.Draw(pageDoc, Pages.Guide, ctx)
	elseif W.tab == "queue" then
		P.Draw(pageDoc, Pages.Queue, ctx)
	elseif W.tab == "materials" then
		P.Draw(pageDoc, Pages.Materials)
	else
		-- (The details are always open: a missing recipe's sources show there.)
		ctx.filter = pageSearch.filter or ""
		ctx.detailSpell = P.GetPick()
		ctx.detail = function(e)
			P.SetPick(e.spell)
			P.detail:Top()
			if ns.Window then ns.Window.Render() end
		end
		P.Draw(pageDoc, Pages.Missing, ctx)
	end
	return true
end

-- What Window.lua asks of it for a controller and the tours: the page tabs under the window (in
-- order), one by its key, and the frame round the side tabs.
function Lay.Tabs() return shownTabs.bottom or {} end
function Lay.Link() return linkButton and linkButton:IsShown() and linkButton or nil end
function Lay.TabOf() return tabOf end
function Lay.Bar() return sideBox and sideBox:IsShown() and sideBox or portrait end

-- (A controller: the side tabs, the page tabs and the portrait are buttons, so stops of the game's
-- cursor like any; A on a profession's side tab casts its spell through Menu.PadCast, as on a chip,
-- and LB / RB step through the page tabs: Window.lua's padTabs asks Lay.Tabs.)
