-- The professions menu: what was the window's sidebar (design\facelift.md 3.1, "Where every
-- feature goes"). Since 3.0.2 your professions are chips across the title bar (WindowChips.lua),
-- and this menu is what the bar's "more" chip opens: your alts and the Cooldowns and Tracking
-- tiles, nothing else. Link to Chat and Unlearn are behind a right-click on a profession's chip
-- (or on its row here; a controller's Y), where the player asks for them on purpose: no row and
-- no line of this menu is ever one of them. It lists your professions themselves only when
-- asked to (Menu.Open's `which`): the ones the bar had no room for (its "+N" chip), or all of them
-- (from the name, on a page whose title bar spells a name out: an alt's or someone's recipes).
-- The chips and the rows are the same entries (Menu.Entries) and open a profession the same way
-- (PlaceCaster). It opens over the window, under the header and inside the window's bounds:
--   your professions (a press opens one; a gathering one shows its own page), Camping, your alts'
--   professions on this realm, and at its foot your craft cooldowns and the tracking spells.
--   A profession opens by its own spell, cast through a secure button laid over its row, as the
--   game's own profession tabs do it ("Opening a profession", below).
--   Each of your professions has a "more" button (and a right-click, and a controller's Y) with
--   Link to Chat and Unlearn, so neither is said only in a tooltip.
-- It is built the way DaylightUI builds its own dropdown (DaylightUI/Options/Widgets.lua:2652-2666:
-- a catcher over the screen with the menu its child, told to the controller as a popup with
-- Pad.Popup), so a press anywhere else, B or picking a row closes it. Unlike that one, the catcher
-- takes no clicks: a press elsewhere closes the menu and still reaches what was pressed. Its catcher is one strata
-- under that dropdown's (Build), so the "more" menu, which is that dropdown, opens wholly over it.
-- Also here: the pages the menu opens that aren't a tab (an alt's recipes, a gathering profession,
-- the camping page), and unlearning a profession.
local _, ns = ...
if not ns.ok then return end

local API = ns.API
local Doc, Calc = ns.Doc, ns.Calc
local State = ns.WinState
local S = ns.state
local L, Plural = ns.L, ns.Plural
local Color, Text, DiffColor = Doc.Color, Doc.Text, Doc.DiffColor
local Pad = ns.Pad
local W = ns.Win
local Wash = W.Wash

local Menu = {}
ns.WinMenu = Menu

local ENTRY = 34          -- a two-line row (the grid's)
local TILE, TILE_GAP = 32, 8
local CAMP_ICON = 279981  -- the Basic Campfire Kit's icon, for the camping page
Menu.CAMP_ICON = CAMP_ICON

local catcher, menu, body, list, track, cool, thumb
local only                      -- the one part the open menu shows: "alts", "cooldowns" or
                                -- "tracking" (the Blizzard Layout's side tab for it), or nil (all)
local listed                    -- which of your professions the open menu lists: true (all), a set
                                -- by the game's skill line (and W.CAMP), or nil (none)
-- The menu's look: DaylightUI's shell, its background fully solid. It lies over the window's page,
-- and none of that may show through it, whatever the window opacity is set to.
local LOOK = { bgAlpha = 1, noBevel = true }
local rows = {}
local used, y = 0, 0
local scroll, tall = 0, 0       -- how far the list is scrolled, how tall it is in all
local widest = 0                -- the longest line drawn, for the menu's width
local menuPad                   -- its stand-in scroll frame for a controller's right stick
local stickMoving = false
local Paint, PaintTrack, PaintCooldowns, PlaceFoot

-- (Your professions as entries, the menu's parts and the tracking list are each asked several
-- times a draw (the chips, the side tabs, the window's size, the menu), and each asks the game
-- again. Kept for one frame, and thrown away as a draw of the window or the menu starts
-- (Menu.Fresh), so what a click changed is always read anew. key: the state an answer goes by.)
local drawn, drawnAt = {}, nil
local function Drawn(what, key, fn)
	local now = GetTime()
	if drawnAt ~= now then drawn, drawnAt = {}, now end
	local e = drawn[what]
	if e and e[1] == key then return e[2] end
	local v = fn()
	drawn[what] = { key, v }
	return v
end
function Menu.Fresh() drawn = {} end

-- ---------------------------------------------------------------------------------------------
-- Your professions
-- ---------------------------------------------------------------------------------------------

-- Your professions now: { name, icon, skill, max, line, game, crafts, spell }, those with recipes
-- first. line: the data's skill line (the game's own when the data doesn't cover it); game: the
-- game's line, the one OpenTradeSkill takes; crafts: the data has recipes for it; spell: the spell
-- that opens its recipe window (OpenSpell). The rest (Herbalism, Skinning, Fishing) have no trade
-- skill window: a press on one shows its own page (GatherPage).

-- The spell that opens a profession's recipe window: the first of its spells in the spellbook,
-- when the game says that one shows a crafting window. It is what the game's own profession tabs
-- read and cast (Blizzard_Professions/Camelot/Blizzard_ProfessionsFrame.lua:42-65: GetProfessionInfo's
-- spellOffset, C_SpellBook.GetSpellBookItemInfo(spellOffset + 1, Enum.SpellBookSpellBank.Player)
-- .spellID, C_TradeSkillUI.CanTradeSkillShowCraftingUI(spellID); Blizzard_ProfessionsTemplates/
-- Blizzard_ProfessionsTemplates.lua:965-971 casts it). Nil when the game has none to offer.
local function OpenSpell(offset)
	if type(offset) ~= "number" then return nil end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo and bank ~= nil) then return nil end
	if not (C_TradeSkillUI and C_TradeSkillUI.CanTradeSkillShowCraftingUI) then return nil end
	local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, offset + 1, bank)
	local spell = ok and type(info) == "table" and info.spellID or nil
	if type(spell) ~= "number" then return nil end
	local got, can = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, spell)
	return got and can == true and spell or nil
end

function W.MyProfessions()
	local out = {}
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
	local all = { GetProfessions() }
	for i = 1, 7 do
		local index = all[i]
		if index then
			local ok, name, icon, skill, max, _, spellOffset, line = pcall(GetProfessionInfo, index)
			if ok and name then
				local data = ns.DataLine(line, name)
				out[#out + 1] = { name = name, icon = icon, skill = skill or 0, max = max or 0, line = data or line,
					game = line, crafts = data ~= nil, offset = spellOffset, index = index, primary = i <= 2,
					spell = OpenSpell(spellOffset) }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.crafts ~= b.crafts then return a.crafts end
		return a.name < b.name
	end)
	return out
end
local MyProfessions = W.MyProfessions

-- ---------------------------------------------------------------------------------------------
-- Unlearning a primary profession
-- ---------------------------------------------------------------------------------------------
-- As the game's professions book does it (its Unlearn button: StaticPopup "UNLEARN_SKILL", whose
-- yes calls AbandonSkill(skillLine)), from the profession's "more" menu, behind our "Are you
-- sure?" box. Only the two primary professions: the book offers none for Cooking, First Aid and
-- Fishing. Once the game drops it, what we kept of it goes too (Forgotten).

local unlearning        -- the profession just unlearned, until the game says it's gone

local function Abandon() return (C_SkillInfo and C_SkillInfo.AbandonSkill) or _G.AbandonSkill end

-- The profession is gone from your list: its saved skill, recipes, Leveling Guide, queue entries
-- and reminders are forgotten, and the window shows another page.
local function Forgotten(p)
	if ns.Store then ns.Store.ForgetProfession(p.line) end
	if ns.Queue then ns.Queue.ForgetLine(p.line) end
	if ns.Tips and ns.Tips.ForgetLine then ns.Tips.ForgetLine(p.line) end
	if W.gather == p.game then W.gather = nil end
	if S.line == p.line then
		S.recipe = nil
		if ns.Where then ns.Where.ForgetKnown() end
	end
	if DaylightRecipesDB and DaylightRecipesDB.lastLine == p.line then DaylightRecipesDB.lastLine = nil end
	if ns.Shop then ns.Shop.Refresh() end
	ns.Changed()
end

function Menu.Unlearn(p)
	local abandon = Abandon()
	if not p or type(abandon) ~= "function" then return end
	local function Go()
		-- (Its trade skill open: closed first, as the game's book is when it unlearns.)
		if S.mode == "win" and S.line == p.line and ns.Take then ns.Take.Close() end
		unlearning = p
		local ok = pcall(abandon, p.game)
		if not ok then unlearning = nil end
	end
	local text = L["Unlearn %s? Your skill in it and every %s recipe you know are lost. Learning it again starts over at skill 1."]:format(p.name, p.name)
	local owner = W.win and W.win:IsShown() and W.win or nil
	-- (The box's title names the profession and the skill that would be lost: "Unlearn Skinning
	-- (225 / 225)". Nothing is unlearned until its Unlearn button is pressed; No, Escape and a
	-- press elsewhere leave everything as it is.)
	local named = (p.max or 0) > 0 and ("%s (%d / %d)"):format(p.name, p.skill or 0, p.max) or p.name
	if ns.Shop and type(ns.Shop.Confirm) == "function" then
		ns.Shop.Confirm(owner, text, nil, Go, { title = L["Unlearn %s"]:format(named), yes = L["Unlearn"], warn = true })
		return
	end
	-- (No confirm box of ours: the game's own, as Swap.lua asks its questions.)
	StaticPopupDialogs.DAYLIGHTRECIPES_UNLEARN = {
		text = text, button1 = L["Unlearn"], button2 = L["No"], OnAccept = Go,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3, showAlert = true,
	}
	StaticPopup_Show("DAYLIGHTRECIPES_UNLEARN")
end

-- A profession's "more" menu: Link to Chat (one with recipes), Unlearn (a primary one).
local function MoreMenu(owner, p)
	local keys, words = {}, { link = L["Link to Chat"], unlearn = L["Unlearn"] }
	if p.crafts then keys[#keys + 1] = "link" end
	if p.primary then keys[#keys + 1] = "unlearn" end
	if #keys == 0 then return end
	Menu.HideCaster()
	API.Menu(owner, keys, words, nil, function(key)
		if key == "link" then
			Menu.Close()
			ns.Window.LinkProfession(p.line, p.game)
		elseif key == "unlearn" then
			Menu.Close()
			Menu.Unlearn(p)
		end
	end, nil, { atCursor = true })
end

-- The game took it off your professions: forgotten here too, and the window stays up on what's
-- left (it closes with a trade skill otherwise).
local unlearnEvents = CreateFrame("Frame")
unlearnEvents:RegisterEvent("SKILL_LINES_CHANGED")
unlearnEvents:SetScript("OnEvent", function()
	local p = unlearning
	if not p then return end
	for _, q in ipairs(MyProfessions()) do
		if q.game == p.game then return end
	end
	unlearning = nil
	Forgotten(p)
	C_Timer.After(0.1, function()
		if W.win and not W.win:IsShown() then W.win:Show() end
		ns.Window.Render()
	end)
end)

-- ---------------------------------------------------------------------------------------------
-- The menu's rows
-- ---------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------
-- Opening a profession
-- ---------------------------------------------------------------------------------------------
-- The game's own profession tabs never ask for a profession by its skill line: each casts the
-- profession's spell (ProfessionsLargeRightTabMixin:CastProfessionSpell, Blizzard_ProfessionsTemplates/
-- Blizzard_ProfessionsTemplates.lua:965-971, C_SpellBook.CastSpellBookItem). This menu asked by line
-- (C_TradeSkillUI.OpenTradeSkill, TradeSkillUIDocumentation.lua:1113-1126), and Cooking and First
-- Aid did not open from it. So a row opens its profession the game's way. Casting a spell is
-- protected, so addon code can't do it from a click of its own: a secure button
-- (SecureActionButtonTemplate, type1 "spell": SECURE_ACTIONS.spell casts it by ID,
-- Blizzard_FrameXML/SecureTemplates.lua:396-405) lies over the row under the mouse and takes the
-- click. By the rules Craft.lua's Stop keeps: UIParent's child, anchored to the screen alone at
-- the row's place, and placed, sized, shown, hidden and given its spell out of a fight only. In a
-- fight it is away (put away as the fight starts) and the row's own click asks by line, as
-- before. A row whose profession is the one open has no spell to cast (casting it again would
-- close it): its own click shows its recipes.
-- A right-click on it opens the row's More menu and a Shift-click links the profession, as on the
-- row; it leaves the row's More button free.

local caster
local PlaceCaster

-- The look of what it covers, with the mouse on the secure button (which has taken the mouse from
-- it): a row's wash; a chip's own hover (r.hover: its light and its tooltip).
local function Hover(r, on)
	if not r then return end
	if r.hover then r.hover(r, on) else r.wash:SetShown(on) end
end

local function HideCaster()
	if not caster or InCombatLockdown() then return end
	local r = caster.row
	caster.row = nil
	if caster:IsShown() then caster:Hide() end
	Hover(r, false)
end
Menu.HideCaster = HideCaster

local function Caster()
	if caster or InCombatLockdown() then return caster end
	caster = CreateFrame("Button", "DaylightRecipesMenuCast", UIParent, "SecureActionButtonTemplate")
	-- (On the release, whatever the player's "cast on key down" setting: SecureActionButton_OnClick,
	-- SecureTemplates.lua:802-811, reads useOnKeyDown first.)
	caster:RegisterForClicks("AnyUp")
	caster:SetAttribute("useOnKeyDown", false)
	caster:Hide()
	caster:SetScript("OnEnter", function(self)
		local r = self.row
		if r and r:IsShown() then Hover(r, true) end
	end)
	caster:SetScript("OnLeave", function() HideCaster() end)
	-- (Before and after the game's own click handler, which casts the spell: the row is kept from
	-- before it, since the profession opening closes the menu and may do so before PostClick.)
	caster:SetScript("PreClick", function(self) self.clicked = self.row end)
	caster:SetScript("PostClick", function(self, button)
		local r = self.clicked
		self.clicked = nil
		if not r then return end
		if button == "RightButton" then
			if r.onRight then r.onRight(r) end
			return
		end
		if button ~= "LeftButton" then return end
		local p = r.prof
		local link = p and p.crafts and IsModifiedClick("CHATLINK")
		Menu.Close()
		-- (Linked once the game has it open: it opens a moment after the press.)
		if link then ns.Window.LinkOnceOpen(p.line) end
	end)
	-- (A fight starts: put away while that is still allowed, so the row's own click is what's left.)
	caster:RegisterEvent("PLAYER_REGEN_DISABLED")
	caster:SetScript("OnEvent", function(self)
		local r = self.row
		self.row = nil
		self:Hide()
		Hover(r, false)
	end)
	return caster
end

-- The secure button over row `r` (the part of it the list shows, left of its More button), set to
-- the row's spell; put away for a row with none.
-- r is a row of the menu or a chip of the title bar: anything with r.cast (the spell), r.prof,
-- r.wash, r.onRight, and optionally r.more (a button of its own to leave free) and r.castClip (a
-- frame it may be scrolled half out of: the menu's list).
Menu.PlaceCaster = function(r) PlaceCaster(r) end
PlaceCaster = function(r)
	if InCombatLockdown() then return end
	if not (r and r.cast and r:IsVisible()) then
		HideCaster()
		return
	end
	local b = Caster()
	if not b then return end
	local left, bottom, top = r:GetLeft(), r:GetBottom(), r:GetTop()
	if not (left and bottom and top) then
		HideCaster()
		return
	end
	local right = left + r:GetWidth()
	if r.more and r.more:IsShown() then
		local moreLeft = r.more:GetLeft()
		if moreLeft then right = math.min(right, moreLeft - 2) end
	end
	local clip = r.castClip
	if clip then
		local clipTop, clipBottom = clip:GetTop(), clip:GetBottom()
		if not (clipTop and clipBottom) then
			HideCaster()
			return
		end
		top, bottom = math.min(top, clipTop), math.max(bottom, clipBottom)
	end
	if top - bottom < 4 or right - left < 4 then
		HideCaster()
		return
	end
	local scale = r:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if b.row and b.row ~= r then Hover(b.row, false) end
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
	b:SetSize((right - left) * scale, (top - bottom) * scale)
	-- (Over the row or chip, in its own layer: a row's is the menu's, under Daylight UI's
	-- dropdown as the rows are; a chip's is the window's.)
	b:SetFrameStrata(r:GetFrameStrata())
	b:SetFrameLevel(r:GetFrameLevel() + 1)
	b:SetAttribute("type1", "spell")
	b:SetAttribute("spell", r.cast)
	b.row = r
	b:Show()
end

-- A controller's A on a profession's row: the same spell, through Daylight UI's secure key (the
-- window's padKeys, Window.lua). Nil for any other stop, and in a fight.
function Menu.PadCast(at)
	if InCombatLockdown() then return nil end
	if type(at) ~= "table" or type(at.cast) ~= "number" or not at.prof then return nil end
	if not (at.chip or Menu.Shown()) then return nil end
	return { type = "spell", spell = at.cast }
end

-- The game opened a profession (a row's spell, a controller's A, the spellbook): the menu has done
-- its work and closes.
local opened = CreateFrame("Frame")
opened:RegisterEvent("TRADE_SKILL_SHOW")
opened:SetScript("OnEvent", function()
	if Menu.Shown() then Menu.Close() end
end)

-- A controller's cursor on a row scrolled out of the list's sight: the list scrolls to it.
local function IntoView(r)
	if not Pad.On() then return end
	local top, bottom = r:GetTop(), r:GetBottom()
	local listTop, listBottom = list:GetTop(), list:GetBottom()
	if not (top and bottom and listTop and listBottom) then return end
	local by = 0
	if bottom < listBottom then by = listBottom - bottom + 4 elseif top > listTop then by = listTop - top - 4 end
	if by == 0 then return end
	local most = math.max(0, tall - list:GetHeight() + 8)
	local to = math.max(0, math.min(most, scroll + by))
	if to ~= scroll then
		scroll = to
		Paint()
	end
end

local function Row()
	used = used + 1
	local r = rows[used]
	if not r then
		r = CreateFrame("Button", nil, list)
		r.ground = r:CreateTexture(nil, "BACKGROUND")
		r.ground:SetAllPoints()
		r.edge = r:CreateTexture(nil, "ARTWORK")
		r.edge:SetWidth(2)
		r.edge:SetPoint("TOPLEFT")
		r.edge:SetPoint("BOTTOMLEFT")
		r.wash = Wash(r, "BORDER", 0.05)
		r.wash:SetAllPoints()
		r.wash:Hide()
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", r, "LEFT", 12, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = Text(r, "body")
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.sub = Text(r, "small")
		r.sub:SetJustifyH("LEFT")
		r.sub:SetWordWrap(false)
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetHeight(2)
		r.barBack = r:CreateTexture(nil, "BORDER")
		r.barBack:SetHeight(2)
		-- "More": three dots, for the mouse what Y is for a controller and a right-click is for both.
		r.more = CreateFrame("Button", nil, r)
		r.more:SetSize(22, 22)
		r.more:SetPoint("RIGHT", r, "RIGHT", -6, 0)
		r.more.dots = {}
		for i = 1, 3 do
			local dot = r.more:CreateTexture(nil, "ARTWORK")
			dot:SetSize(2, 2)
			dot:SetPoint("CENTER", r.more, "CENTER", (i - 2) * 5, 0)
			r.more.dots[i] = dot
		end
		function r.more.Paint(over)
			local cr, cg, cb
			if over then cr, cg, cb = API.Accent() else cr, cg, cb = Color("LABEL") end
			for _, dot in ipairs(r.more.dots) do dot:SetColorTexture(cr, cg, cb, 1) end
		end
		r.more.Paint(false)
		r.more:SetScript("OnEnter", function(self) self.Paint(true) end)
		r.more:SetScript("OnLeave", function(self) self.Paint(false) end)
		r.more:SetScript("OnClick", function(self)
			if r.onRight then r.onRight(self) end
		end)
		-- (A controller reaches the same menu with Y on the row: no stop of its own.)
		Pad.Skip(r.more)
		r:SetScript("OnEnter", function(self)
			if self.onClick then self.wash:Show() end
			Pad.Into(self, menuPad)
			IntoView(self)
			PlaceCaster(self)
			if self.tip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				pcall(self.tip, GameTooltip)
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function(self)
			self.wash:Hide()
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
		end)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				if self.onRight then self.onRight(self) end
				return
			end
			if self.onClick then self.onClick(self) end
		end)
		r.castClip = list
		-- A controller's Y: what a right-click does (Link to Chat, Unlearn).
		r.padMore = function(self) return self.onRight end
		rows[used] = r
	end
	r:ClearAllPoints()
	r:Show()
	return r
end

local function Note(fs)
	local w = fs:GetUnboundedStringWidth()
	if type(w) == "number" and w > widest then widest = w end
end

local function Heading(text)
	y = y + 8
	local r = Row()
	r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
	r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	r.icon:Hide()
	r.bar:Hide()
	r.barBack:Hide()
	r.sub:Hide()
	r.ground:Hide()
	r.edge:Hide()
	r.more:Hide()
	r.onClick, r.tip, r.onRight = nil, nil, nil
	r.cast, r.prof = nil, nil
	-- (A heading wraps onto more lines rather than being cut off, its row as tall as it.)
	r.name:ClearAllPoints()
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -2)
	r.name:SetWidth(math.max(60, list:GetWidth() - 24))
	r.name:SetWordWrap(true)
	r.name:SetText(text)
	r.name:SetTextColor(Color("LABEL"))
	local h = math.max(18, math.ceil(r.name:GetStringHeight()) + 4)
	r:SetHeight(h)
	y = y + h + 2
end

-- o: icon, name, nameColor {r,g,b}, sub, value (0-1 for the bar), picked, onClick, onRight, tip,
-- cast (the spell that opens it: PlaceCaster) and prof (your profession it is)
local function Entry(o)
	local r = Row()
	r:SetHeight(ENTRY)
	r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
	r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	r.onClick, r.tip, r.onRight = o.onClick, o.tip, o.onRight
	r.cast, r.prof = o.cast, o.prof
	r.more:SetShown(o.onRight ~= nil)
	local x = 12
	if o.icon then
		r.icon:SetTexture(o.icon)
		r.icon:Show()
		x = 40
	else
		r.icon:Hide()
	end
	local right = o.onRight and -30 or -10
	r.name:ClearAllPoints()
	r.name:SetWidth(0)
	r.name:SetWordWrap(false)
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x, -3)
	r.name:SetPoint("RIGHT", r, "RIGHT", right, 0)
	r.name:SetText(o.name)
	if o.nameColor then r.name:SetTextColor(o.nameColor[1], o.nameColor[2], o.nameColor[3])
	else r.name:SetTextColor(Color(o.off and "OFF" or "VALUE")) end
	r.sub:ClearAllPoints()
	r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
	r.sub:SetPoint("RIGHT", r, "RIGHT", right, 0)
	r.sub:SetText(o.sub or "")
	r.sub:SetTextColor(Color("LABEL"))
	r.sub:Show()
	-- (The menu is made as wide as its longest line: WindowState.MenuWidth.)
	Note(r.name)
	Note(r.sub)
	local ar, ag, ab = API.Accent()
	if o.value then
		r.barBack:ClearAllPoints()
		r.barBack:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 1)
		r.barBack:SetPoint("RIGHT", r, "RIGHT", -12, 0)
		r.barBack:SetColorTexture(1, 1, 1, 0.08)
		r.barBack:Show()
		local full = (list:GetWidth() > 0 and list:GetWidth() or 210) - x - 12
		r.bar:ClearAllPoints()
		r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 1)
		r.bar:SetWidth(math.max(1, full * math.min(1, o.value)))
		r.bar:SetColorTexture(ar, ag, ab, 0.8)
		r.bar:Show()
	else
		r.bar:Hide()
		r.barBack:Hide()
	end
	if o.picked then
		r.ground:SetColorTexture(ar, ag, ab, 0.12)
		r.ground:Show()
		r.edge:SetColorTexture(ar, ag, ab, 1)
		r.edge:Show()
	else
		r.ground:Hide()
		r.edge:Hide()
	end
	y = y + ENTRY + 2
end

-- ---------------------------------------------------------------------------------------------
-- Tracking: the professions' minimap tracking, at the foot of the menu
-- ---------------------------------------------------------------------------------------------
-- The tracking spells of your professions (Find Minerals, Find Herbs, Find Fish), as the game's
-- minimap tracking menu lists them (C_Minimap.GetTrackingInfo: only the ones you know). Click one
-- to turn it on or off (C_Minimap.SetTracking, as that menu does), or drag it to an action bar
-- (C_Spell.PickupSpell, as the spellbook's buttons do). The one on has an accent ring
-- and DaylightUI's glow, in the style the player picked for its main buttons.

local TRACK_SPELLS = { [2580] = true, [2383] = true, [43308] = true }
local trackTiles = {}

-- Their names in the game's language, so one Forever lists under another spell ID still counts.
local trackNames
local function TrackName(name)
	if not trackNames then
		trackNames = {}
		for spell in pairs(TRACK_SPELLS) do
			local n = ns.SpellName(spell)
			if type(n) == "string" and n ~= "" then trackNames[n] = true end
		end
		if not next(trackNames) then
			trackNames = nil     -- (the spell names weren't in yet: asked again next time)
			return false
		end
	end
	return type(name) == "string" and trackNames[name] == true
end

local function ReadTracking()
	local out = {}
	local M = C_Minimap
	if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo and M.SetTracking) then return out end
	local ok, n = pcall(M.GetNumTrackingTypes)
	if not ok or type(n) ~= "number" then return out end
	for i = 1, n do
		local got, info = pcall(M.GetTrackingInfo, i)
		if got and type(info) == "table" and ((info.spellID and TRACK_SPELLS[info.spellID]) or TrackName(info.name)) then
			out[#out + 1] = { index = i, name = info.name, icon = info.texture, on = info.active == true,
				spell = info.spellID }
		end
	end
	return out
end

local function TrackingList() return Drawn("tracking", "", ReadTracking) end

-- A tracking spell onto the cursor, to drop on an action bar: by its spell ID, else its name (one
-- matched by name only). C_Spell.PickupSpell (SpellDocumentation.lua), as Blizzard's spell buttons
-- call it (SpellFlyout.lua:77); not in combat, where the bars can't take it anyway.
local function PickupTracking(spell, name)
	local CS = C_Spell
	if InCombatLockdown() or not (CS and CS.PickupSpell) then return end
	if spell then pcall(CS.PickupSpell, spell) elseif type(name) == "string" then pcall(CS.PickupSpell, name) end
end

-- The glow style for a tile that's on: the player's main-button style, none when that's None or
-- this DaylightUI has no GlowAround (the ring still shows it's on).
local function TrackGlowStyle()
	if type(API.GlowAround) ~= "function" then return false end
	local ok, style = pcall(API.GetSetting, "general", "buttonGlow")
	if not ok or style == "none" then return false end
	return type(style) == "string" and style or "circle"
end

-- A tile of the two strips: a ring, the icon, a wash under the mouse.
local function Tile(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(TILE, TILE)
	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetPoint("TOPLEFT", -2, 2)
	b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.wash = Wash(b, "OVERLAY", 0.12)
	b.wash:SetAllPoints()
	b.wash:Hide()
	return b
end

local function TrackTile(i)
	local b = trackTiles[i]
	if b then return b end
	b = Tile(track)
	b:SetScript("OnEnter", function(self)
		self.wash:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not (self.spell and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell)) then
			GameTooltip:SetText(self.name or "")
		end
		GameTooltip:AddLine(self.on and L["Click: turn off"] or L["Click: turn on"], Color("LABEL"))
		GameTooltip:AddLine(L["Drag: to an action bar"], Color("LABEL"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function(self)
		if not self.index then return end
		pcall(C_Minimap.SetTracking, self.index, not self.on)
	end)
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self) PickupTracking(self.spell, self.name) end)
	trackTiles[i] = b
	return b
end

-- A strip's title and the line over it, made once.
local function StripTitle(strip, text)
	if not strip.title then
		strip.title = Text(strip, "small")
		strip.title:SetJustifyH("LEFT")
		strip.title:SetPoint("TOPLEFT", strip, "TOPLEFT", 14, -8)
		strip.line = strip:CreateTexture(nil, "ARTWORK")
		strip.line:SetHeight(1)
		strip.line:SetPoint("TOPLEFT", strip, "TOPLEFT", 12, 0)
		strip.line:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -12, 0)
		strip.line:SetColorTexture(1, 1, 1, 0.06)
	end
	strip.title:SetText(text)
	strip.title:SetTextColor(Color("LABEL"))
	Note(strip.title)
	return 8 + math.ceil(strip.title:GetStringHeight()) + 6
end

local function Across()
	local w = menu and menu:GetWidth() or 210
	return math.max(1, math.floor((w - 28 + TILE_GAP) / (TILE + TILE_GAP)))
end

PaintTrack = function()
	if not track then return end
	local all = (only and only ~= "tracking") and {} or TrackingList()
	for i = #all + 1, #trackTiles do
		local b = trackTiles[i]
		b:Hide()
		if b.glow then API.GlowAround(b, false); b.glow = nil end
	end
	if #all == 0 then
		track:Hide()
		PlaceFoot()
		return
	end
	local top = StripTitle(track, L["Tracking"])
	-- (Tiles in rows across the strip, as many as fit.)
	local across = Across()
	local ar, ag, ab = API.Accent()
	local style = TrackGlowStyle()
	for i, t in ipairs(all) do
		local b = TrackTile(i)
		local col, row = (i - 1) % across, math.floor((i - 1) / across)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", track, "TOPLEFT", 14 + col * (TILE + TILE_GAP), -(top + row * (TILE + TILE_GAP)))
		b.index, b.name, b.spell, b.on = t.index, t.name, t.spell, t.on
		b.icon:SetTexture(t.icon)
		b.icon:SetDesaturated(not t.on)
		b.icon:SetAlpha(t.on and 1 or 0.6)
		if t.on then b.ring:SetColorTexture(ar, ag, ab, 1) else b.ring:SetColorTexture(1, 1, 1, 0.08) end
		-- (Started again only when it changes, so a repaint doesn't start its light over.)
		local want = t.on and style or false
		if (b.glow or false) ~= want then
			if b.glow then API.GlowAround(b, false) end
			if want then API.GlowAround(b, true, { style = want, inset = -2 }) end
			b.glow = want or nil
		end
		b:Show()
	end
	local n = math.ceil(#all / across)
	track:SetHeight(top + n * TILE + (n - 1) * TILE_GAP + 12)
	track:Show()
	PlaceFoot()
end

-- ---------------------------------------------------------------------------------------------
-- Craft cooldowns: above the tracking strip
-- ---------------------------------------------------------------------------------------------
-- Your recipes that can only be made once in a while (Cooldowns.lua), one tile each: the item
-- gray with the time left on it while it's cooling down, in full color with a green ring once it's
-- ready. Hover for which recipes and when; click to open the recipe. While a tile is cooling down
-- and the menu shows, it's drawn again every half minute (nothing runs while it's hidden).
-- A ready one also shows as a dot on the header's icon (Menu.CooldownReady), so it's seen with the
-- menu shut.

local coolTiles = {}
local coolTicker
local COOL_TICK = 30

local function StopCoolTicker()
	if coolTicker then
		coolTicker:Cancel()
		coolTicker = nil
	end
end
Menu.StopTicker = StopCoolTicker

local function CoolTile(index)
	local b = coolTiles[index]
	if b then return b end
	b = Tile(cool)
	b.time = Text(b, "tiny")
	b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
	b:SetScript("OnEnter", function(self)
		self.wash:Show()
		local t = self.tile
		if not t then return end
		-- (Host.TipLines: the look's roles, the click hint in the accent.)
		ns.Host.TipLines(self, function(tip)
			for i, name in ipairs(t.names) do tip.Line(name, i == 1 and "TITLE" or "TEXT") end
			if t.readyAt == 0 then
				tip.Line(L["Ready to craft"], "GOOD")
			else
				tip.Line(L["Ready in %s"]:format(ns.Cooldowns.Left(t.readyAt)), "WARN")
			end
			tip.Line(L["Click: show the recipe"], "pop")
		end, "ANCHOR_RIGHT")
	end)
	b:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function(self)
		local t = self.tile
		if t and t.line and t.spells[1] then
			Menu.Close()
			ns.Window.OpenRecipe(t.line, t.spells[1])
		end
	end)
	coolTiles[index] = b
	return b
end

PaintCooldowns = function()
	if not cool then return end
	local all = (only and only ~= "cooldowns") and {} or (ns.Cooldowns and ns.Cooldowns.List() or {})
	for i = #all + 1, #coolTiles do coolTiles[i]:Hide() end
	if #all == 0 then
		StopCoolTicker()
		cool:Hide()
		PlaceFoot()
		return
	end
	local top = StripTitle(cool, L["Cooldowns"])
	local across = Across()
	local gr, gg, gb = Color("GOOD")
	local cooling = false
	for i, t in ipairs(all) do
		local b = CoolTile(i)
		local col, row = (i - 1) % across, math.floor((i - 1) / across)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", cool, "TOPLEFT", 14 + col * (TILE + TILE_GAP), -(top + row * (TILE + TILE_GAP)))
		b.tile = t
		b.icon:SetTexture(t.icon or 134400)
		local ready = t.readyAt == 0
		b.icon:SetDesaturated(not ready)
		b.icon:SetAlpha(ready and 1 or 0.55)
		if ready then
			b.ring:SetColorTexture(gr, gg, gb, 1)
			b.time:SetText("")
		else
			cooling = true
			b.ring:SetColorTexture(1, 1, 1, 0.08)
			-- (One unit on the tile, so it fits its width; the tooltip has the whole time.)
			b.time:SetText(ns.Cooldowns.Short(t.readyAt))
			b.time:SetTextColor(Color("VALUE"))
		end
		b:Show()
	end
	local n = math.ceil(#all / across)
	cool:SetHeight(top + n * TILE + (n - 1) * TILE_GAP + 12)
	cool:Show()
	PlaceFoot()
	-- The countdown: only while something is cooling down and the menu is on screen.
	if not cooling then
		StopCoolTicker()
	elseif not coolTicker then
		coolTicker = C_Timer.NewTicker(COOL_TICK, function()
			if cool and cool:IsVisible() then Menu.Paint() else StopCoolTicker() end
		end)
	end
end

-- Whether one of your cooldown recipes is ready to make now (the dot on the header's icon).
function Menu.CooldownReady()
	local all = ns.Cooldowns and ns.Cooldowns.List() or {}
	for _, t in ipairs(all) do
		if t.readyAt == 0 then return true end
	end
	return false
end

-- The foot of the menu, bottom up: tracking, then cooldowns, then the list above them.
PlaceFoot = function()
	local below, point = menu, "BOTTOM"
	if track and track:IsShown() then
		track:ClearAllPoints()
		track:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 0, 0)
		track:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
		below, point = track, "TOP"
	end
	if cool and cool:IsShown() then
		cool:ClearAllPoints()
		cool:SetPoint("BOTTOMLEFT", below, point == "TOP" and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
		cool:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
		below, point = cool, "TOP"
	end
	list:SetPoint("BOTTOM", below, point, 0, 0)
end

local function FootHeight()
	local h = 0
	if track and track:IsShown() then h = h + track:GetHeight() end
	if cool and cool:IsShown() then h = h + cool:GetHeight() end
	return h
end

-- ---------------------------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------------------------

-- Your professions and Camping as the title bar's chips and the menu's rows show them, in one
-- order (those with recipes first, by name, then Camping): { key (the game's skill line, W.CAMP
-- for Camping), prof (nil for Camping), icon, name, sub, value, picked (it is the page on show),
-- cast (the spell that opens it: PlaceCaster), onClick, onRight (its More menu) }.
local function ReadEntries()
	local out = {}
	local alt, gather = W.alt, W.gather
	for _, p in ipairs(MyProfessions()) do
		local picked
		-- (The open one: by our line, or for one we have no recipes for, as Fishing, by its name.)
		local isOpen = S.line ~= nil and p.line == S.line or (S.line == nil and S.name ~= nil and p.name == S.name)
		if gather then
			picked = not alt and gather == p.game
		else
			picked = not alt and S.mode == "win" and not W.Linked() and isOpen
		end
		-- (One with recipes opens its trade skill; a gathering one shows its own page.)
		-- Its spell opens it (PlaceCaster), unless it is the one open now: casting that again would
		-- close it, and its own click shows its recipes (OpenProfession).
		local openNow = S.mode == "win" and isOpen and not W.Linked()
		local more = p.crafts or p.primary
		-- (One the data has no recipes for, whose recipe window the game still opens, as Fishing's
		-- with its camping recipes: opened as the others are, not shown as a gathering page.)
		local window = p.crafts or p.spell ~= nil
		out[#out + 1] = { key = p.game, prof = p, icon = p.icon, name = p.name,
			sub = p.max > 0 and ("%d / %d"):format(p.skill, p.max) or "",
			value = p.max > 0 and p.skill / p.max or nil, picked = picked,
			cast = window and not openNow and p.spell or nil,
			onClick = function()
				Menu.Close()
				if p.crafts and IsModifiedClick("CHATLINK") then
					ns.Window.LinkProfession(p.line, p.game)
				elseif window then
					ns.Window.OpenProfession(p.line, p.game)
				else
					ns.Window.ShowGather(p.game)
				end
			end,
			-- (Link to Chat for one with recipes, Unlearn for a primary one, as in the game's
			-- professions book: a right-click, a controller's Y, a row's "more" button.)
			onRight = more and function(owner) MoreMenu(owner, p) end or nil }
	end
	-- Every profession's camping items (Camp.lua).
	if ns.Camp and ns.Camping and #ns.Camping > 0 then
		out[#out + 1] = { key = W.CAMP, camp = true,
			icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(CAMP_ICON) or nil,
			name = L["Camping"], sub = L["All professions"],
			picked = not alt and gather == W.CAMP, onClick = function()
				Menu.Close()
				ns.Window.ShowGather(W.CAMP)
			end }
	end
	return out
end

function Menu.Entries()
	local key = table.concat({ tostring(W.alt), tostring(W.gather), tostring(S.line), tostring(S.name),
		tostring(S.mode), tostring(W.Linked()) }, ":")
	return Drawn("entries", key, ReadEntries)
end

-- Your alts' professions on this server (the "Show Your Alts' Professions" option; off: none).
local function AltRows()
	local alts = {}
	for guid, c in pairs(ns.Get("altProfs") ~= false and ns.Store and ns.Store.Alts() or {}) do
		if type(c.prof) == "table" then
			for line, p in pairs(c.prof) do
				if type(p) == "table" and ns.LINES[line] then
					alts[#alts + 1] = { guid = guid, c = c, line = line, skill = p.skill or 0, max = p.max or 0 }
				end
			end
		end
	end
	return alts
end

-- Whether the menu has anything to show with none of your professions listed (the title bar's
-- "more" chip shows only then).
function Menu.HasMore()
	if #AltRows() > 0 then return true end
	if #TrackingList() > 0 then return true end
	return #(ns.Cooldowns and ns.Cooldowns.List() or {}) > 0
end

-- The menu's parts one at a time, for the Blizzard Layout's side tabs (one tab each): the ones
-- with something in them, in the menu's order, each { kind, icon, count }. Its icon is the first
-- entry's own (a tracking spell's, a cooldown recipe's), the alts' a group's.
local function ReadParts()
	local out = {}
	local alts = AltRows()
	if #alts > 0 then
		out[#out + 1] = { kind = "alts", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", count = #alts }
	end
	local cds = ns.Cooldowns and ns.Cooldowns.List() or {}
	if #cds > 0 then
		out[#out + 1] = { kind = "cooldowns", icon = cds[1].icon or "Interface\\Icons\\INV_Misc_PocketWatch_01", count = #cds }
	end
	local tracks = TrackingList()
	if #tracks > 0 then
		local icon = tracks[1].icon
		for _, t in ipairs(tracks) do if t.on and t.icon then icon = t.icon break end end
		out[#out + 1] = { kind = "tracking", icon = icon or "Interface\\Icons\\INV_Misc_Spyglass_03", count = #tracks }
	end
	return out
end
function Menu.Parts() return Drawn("parts", "", ReadParts) end

-- The part the open menu shows alone (Menu.Parts' kind), or nil.
function Menu.Only() return Menu.Shown() and only or nil end

local function PaintRows()
	for i = 1, #rows do rows[i]:Hide() end
	used, y = 0, 6 - scroll
	local alt = W.alt
	local entries = Menu.Entries()
	-- Your professions as rows: all of them, or the ones the title bar had no room for.
	if listed then
		Heading(L["Professions"])
		local n = 0
		for _, e in ipairs(entries) do
			if listed == true or listed[e.key] then
				n = n + 1
				Entry({ icon = e.icon, name = e.name, sub = e.sub, value = e.value, picked = e.picked,
					cast = e.cast, prof = e.prof, onClick = e.onClick, onRight = e.onRight })
			end
		end
		if n == 0 then Heading(L["You have no profession yet."]) end
	end
	-- (Nothing here for the professions that are chips in the title bar: their Link to Chat and
	-- Unlearn are behind a right-click on the chip, never a row or a line of this menu.)
	-- Your alts' professions on this server, from the last time each opened them (the "Show Your
	-- Alts' Professions" option; off: none are listed).
	local alts = (only and only ~= "alts") and {} or AltRows()
	if #alts > 0 then
		table.sort(alts, function(a, b)
			if (a.c.name or "") ~= (b.c.name or "") then return (a.c.name or "") < (b.c.name or "") end
			return a.line < b.line
		end)
		Heading(L["Your Alts"])
		for _, a in ipairs(alts) do
			local color
			if a.c.class and API.ClassColor then
				local ok, r, g, b = pcall(API.ClassColor, a.c.class)
				if ok and r then color = { r, g, b } end
			end
			Entry({ name = a.c.name or "?", nameColor = color,
				sub = ("%s %d"):format(ns.Tips and ns.Tips.LineName(a.line) or "", a.skill),
				value = a.max > 0 and a.skill / a.max or nil,
				picked = alt and alt.guid == a.guid and alt.line == a.line,
				onClick = function()
					Menu.Close()
					ns.Window.ShowAlt(a.guid, a.line)
				end })
		end
	end
	tall = y + scroll
end

-- The menu drawn: its rows and strips measured first, then the menu sized to its longest line
-- (never cut: WindowState.MenuWidth) and to the window's height, then drawn at that size.
Paint = function()
	if not (menu and menu:IsShown() and W.win) then return end
	Menu.Fresh()
	local win = W.win
	-- (The rows are drawn anew, maybe elsewhere: the secure button comes back with the next row
	-- the mouse is on.)
	HideCaster()
	menu:SetScale(win:GetScale())
	-- (Under the header; in the Blizzard Layout under its rank bar, over the recipe list: its Top.)
	local top = W.Lay and W.Lay.Active() and W.Lay.Top() or State.HEADER
	local room = math.max(120, win:GetHeight() - top - 4)
	for _ = 1, 2 do
		widest = 0
		PaintTrack()
		PaintCooldowns()
		PaintRows()
		-- (22 more than the longest words: a row's "more" button takes that off its name's room.)
		local w = State.MenuWidth(widest + 22, W.col)
		local h = math.min(room, tall + 8 + FootHeight())
		local same = math.abs(menu:GetWidth() - w) < 1 and math.abs(menu:GetHeight() - h) < 1
		menu:SetSize(w, h)
		-- (Drawn at another size than it now has: once more at this one.)
		if same then break end
	end
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", win, "TOPLEFT", 2, -(top + 2))
	-- (Fewer rows than before, scrolled past the end: back to the end.)
	local most = math.max(0, tall - list:GetHeight() + 8)
	if scroll > most then
		scroll = most
		PaintRows()
	end
	-- More rows than fit (many alts): a thumb on the list's right edge says so and where you are,
	-- as the recipe list's does (WindowState.Thumb has the sums).
	local view = list:GetHeight()
	local size, down = State.Thumb(view, view + most, scroll)
	if size then
		thumb.bar:SetColorTexture(API.Accent())
		thumb.bar:SetAlpha(0.5)
		thumb:SetSize(3, size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -down)
		thumb:Show()
	else
		thumb:Hide()
	end
	if menuPad and not stickMoving then menuPad.Sync() end
end
Menu.Paint = function() Paint() end

-- A press that isn't the menu's: not on the menu, not on what opened it (its own click toggles it),
-- and not on a menu or tooltip over it (Daylight UI's dropdown, a profession's "more").
local function PressOutside()
	if not (menu and menu:IsVisible()) or menu:IsMouseOver() then return false end
	local from = W.menuFrom
	if from and from.IsVisible and from:IsVisible() and from:IsMouseOver() then return false end
	local getFoci, getFocus = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
	local foci = type(getFoci) == "function" and getFoci() or nil
	local f = type(foci) == "table" and foci[1] or (type(getFocus) == "function" and getFocus() or nil)
	if type(f) == "table" and f.GetFrameStrata then
		local ok, strata = pcall(f.GetFrameStrata, f)
		local over = catcher:GetFrameStrata() == "DIALOG" and { FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }
			or { TOOLTIP = true }
		if ok and over[strata] then return false end
	end
	return true
end

local function Build()
	-- (DaylightUI's own dropdown: a catcher over the screen, the menu its child, a press anywhere
	-- else closes it. DaylightUI/Options/Widgets.lua:2652-2666.)
	-- That dropdown is also what opens over this menu: a profession's "more" (API.Menu). Its
	-- catcher is UIParent's child in FULLSCREEN_DIALOG with its list 5 levels up (:2657-2665). In
	-- the same strata our catcher would have the same level as its catcher, our rows (two frames
	-- deeper than our menu) would lie between its catcher and its list: drawn over its background,
	-- and taking the clicks beside it, so a press beside the "more" box would open a profession
	-- and leave the box up. So ours lives one strata lower, DIALOG: over the window (MEDIUM), and
	-- all of it under everything of that dropdown, whatever the levels (strata come before levels;
	-- their order is Blizzard_SharedXML/UI.xsd:18-29, and Craft.lua's Stop relies on DIALOG over
	-- MEDIUM the same way). Menu.Open sets it, since a tour raises the window to FULLSCREEN.
	-- The catcher only holds the menu's layer: it takes no mouse. A press outside the menu closes
	-- it (the game's own menus close the same way, Blizzard_Menu's GLOBAL_MOUSE_DOWN) and still
	-- goes on to what was pressed, so a data text, a drawer or a button outside works first time.
	-- Heard only while the menu is open.
	catcher = CreateFrame("Frame", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:EnableMouse(false)
	catcher:Hide()
	catcher:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	catcher:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
	catcher:SetScript("OnEvent", function() if PressOutside() then Menu.Close() end end)
	menu = CreateFrame("Frame", "DaylightRecipesMenu", catcher)
	menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
	menu:SetSize(210, 300)
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	menu:SetScript("OnMouseWheel", function(_, delta)
		local most = math.max(0, tall - list:GetHeight() + 8)
		local to = math.max(0, math.min(most, scroll - delta * (ENTRY + 2)))
		if to ~= scroll then
			scroll = to
			Paint()
		end
	end)
	-- A SOLID BOX. 3.0.1's menu was see-through in the game: the window's tabs and page could be
	-- read through it, though it asked for a background of 0.97. Its background is DaylightUI's
	-- shell, a child frame DaylightUI makes one level UNDER the frame it dresses (DaylightUI/
	-- Style.lua:1019-1021), and this menu was the one frame of ours that both wore a shell and
	-- clipped its own children (SetClipsChildren, to keep rows and tiles inside it): a child that
	-- lies under its clipping parent. DaylightUI's own dropdown, which this one is modeled on, does
	-- not clip the frame it dresses (Options/Widgets.lua:2663-2672). So now:
	--   * the menu itself clips nothing and wears the shell, at a background of 1;
	--   * everything in it lives on `body`, a plain frame filling it, and body does the clipping;
	--   * the shell is put under the menu, in the menu's layer, by name each time the menu opens
	--     (SettleShell), as Shop.lua's Stack does for the strips: nothing is left to how the game
	--     carries a layer or a level on to a frame's children.
	API.Skin(menu, LOOK)
	body = CreateFrame("Frame", nil, menu)
	body:SetAllPoints(menu)
	body:SetClipsChildren(true)
	list = CreateFrame("Frame", nil, body)
	list:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
	list:SetPoint("RIGHT", menu, "RIGHT", 0, 0)
	list:SetPoint("BOTTOM", menu, "BOTTOM", 0, 0)
	list:SetClipsChildren(true)
	track = CreateFrame("Frame", nil, body)
	track:Hide()
	cool = CreateFrame("Frame", nil, body)
	cool:Hide()
	-- The list's thumb: a frame of its own above the rows (they are frames, and would cover a
	-- texture of the list's), taking no clicks.
	thumb = CreateFrame("Frame", nil, body)
	thumb:SetFrameLevel(list:GetFrameLevel() + 10)
	thumb:EnableMouse(false)
	thumb.bar = thumb:CreateTexture(nil, "OVERLAY")
	thumb.bar:SetAllPoints(thumb)
	thumb:Hide()
	-- (For the tests: the list whose height decides whether the thumb shows, and the thumb.)
	W.menuList, W.menuThumb = list, thumb
	-- A controller: the menu takes the cursor as DaylightUI's dropdown does, B closes it, the right
	-- stick scrolls its rows through a stand-in (they are drawn from an offset).
	Pad.Popup(menu, function() Menu.Close() end)
	menuPad = Pad.Scroller({
		range = function() return math.max(0, tall - list:GetHeight() + 8) end,
		at = function() return scroll end,
		set = function(v)
			v = math.floor(v + 0.5)
			if v == scroll then return end
			scroll = v
			stickMoving = true
			Paint()
			stickMoving = false
		end })
	W.menu = menu
end

function Menu.Shown() return menu ~= nil and catcher:IsShown() end

-- The menu's background (DaylightUI's shell) one level under the menu, in the menu's own layer.
local function SettleShell()
	local shell = ns.ShellOf and ns.ShellOf(menu)
	if not (shell and shell.SetFrameLevel and shell.SetFrameStrata) then return end
	shell:SetFrameStrata(catcher:GetFrameStrata())
	shell:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
end

-- which: the professions of yours it lists as rows (see `listed`, above); from: what opened it,
-- where a controller's cursor goes back to when it closes; part: the one part to show (`only`).
function Menu.Open(which, from, part)
	if not W.win or not W.win:IsShown() then return end
	listed = which or nil
	only = part or nil
	W.menuFrom = from
	-- (Rolled up there is no room under the header for it: the window unrolls first.)
	if W.Rolled() then ns.Window.SetRolled(false) end
	if not menu then Build() end
	scroll = 0
	-- (Over the window, under Daylight UI's dropdown: Build. A tour holds the window in FULLSCREEN,
	-- where the menu has to go one higher to be seen at all.)
	catcher:SetFrameStrata(W.win:GetFrameStrata() == "FULLSCREEN" and "FULLSCREEN_DIALOG" or "DIALOG")
	catcher:Show()
	menu:Show()
	SettleShell()
	Paint()
	if W.Lay and W.Lay.Relight then W.Lay.Relight() end
	-- (A controller starts on the open profession's row, else the first.)
	if Pad.On() then
		local first
		for i = 1, used do
			local r = rows[i]
			if r:IsShown() and r.onClick then
				first = first or r
				if r.ground:IsShown() then first = r break end
			end
		end
		Pad.Settle(first)
	end
end

function Menu.Close()
	if not Menu.Shown() then return end
	-- (The catcher first: nothing below can leave it up.)
	catcher:Hide()
	StopCoolTicker()
	GameTooltip:Hide()
	HideCaster()
	if W.Lay and W.Lay.Relight then W.Lay.Relight() end
	local from = W.menuFrom
	if not (from and from:IsVisible()) then from = W.nameButton end
	if W.win and W.win:IsShown() and Pad.On() then Pad.Settle(from) end
end

function Menu.Toggle(which, from, part)
	-- (Open on another part, from another side tab: that part instead.)
	if Menu.Shown() and (part or nil) == only then Menu.Close() else Menu.Open(which, from, part) end
end

function Menu.Restyle()
	if menu then
		API.Skin(menu, LOOK)
		if Menu.Shown() then SettleShell() end
	end
	if Menu.Shown() then Paint() end
end

-- Tracking turned on or off (here or from the minimap), a tracking spell learned, or the
-- cooldowns read again: the menu while it's open, and the header's dot.
local trackEvents = CreateFrame("Frame")
trackEvents:RegisterEvent("MINIMAP_UPDATE_TRACKING")
trackEvents:RegisterEvent("SPELLS_CHANGED")
trackEvents:SetScript("OnEvent", function()
	if Menu.Shown() then Paint() end
	if W.gather == "tracking" and W.win and W.win:IsVisible() then ns.Window.Render() end
end)

-- ---------------------------------------------------------------------------------------------
-- An alt's profession
-- ---------------------------------------------------------------------------------------------

Menu.altFilter = ""

function Menu.AltPage(d)
	local alt = W.alt
	local c = ns.Store and ns.Store.Alts()[alt.guid]
	if type(c) ~= "table" then
		d:Line(L["That character isn't on this realm and faction."], "small", "OFF")
		return
	end
	local p = type(c.prof) == "table" and c.prof[alt.line] or {}
	local known = type(c.known) == "table" and c.known[alt.line] or nil
	if type(known) ~= "table" then
		d:Line(L["Open this profession on %s once to see what they know."]:format(c.name or L["them"]), "small", "OFF")
		return
	end
	local skill = p.skill or 0
	local all = {}
	local filter = Menu.altFilter
	for spell in pairs(known) do
		local name = ns.SpellName(spell) or Doc.RecipeName(spell)
		if filter == "" or ns.Fold(name):find(filter, 1, true) then
			all[#all + 1] = { spell = spell, name = name }
		end
	end
	table.sort(all, function(a, b) return ns.NameLess(a.name, b.name) end)
	d:Line(Plural(#all, "%d recipe known", "%d recipes known"):format(#all), "small", "LABEL")
	d:Line(L["As of their last visit"], "tiny", "OFF")
	d:Gap(2)
	for _, e in ipairs(all) do
		local t = Calc.Thresholds(e.spell)
		local step = 4
		if t then for i = 1, 3 do if skill < t[i + 1] then step = i break end end end
		local row = d:Row({ left = e.name, tip = Doc.SpellTip(e.spell) })
		row.left:SetTextColor(DiffColor(step))
	end
end

-- ---------------------------------------------------------------------------------------------
-- A gathering profession of yours
-- ---------------------------------------------------------------------------------------------
-- Herbalism, Skinning and Fishing have no trade skill window, and the recipe data has nothing for
-- them: their page shows the skill, the rank and when the next one is trained. A profession the
-- data covers whose trade skill the game wouldn't open (OpenProfession) shows here too, with how
-- to open it.

local SMELTING = 2656

-- Fishing's Expert rank is a book, sold in Booty Bay, and its Artisan rank a quest from Nat Pagle in
-- Dustwallow Marsh (the fishing trainers of the capitals send you), by the cap they lift.
local FISHING = 356
local FISHING_RANKS = {
	[150] = { item = 16083, npc = 2626, skill = 125, level = 20, rank = 225 },
	[225] = { quest = 6607, npc = 12919, skill = 225, level = 35, rank = 300 },
}

-- Where Fishing's next rank comes from, with a click to set a waypoint to who has it.
local function FishingRank(d, r, now)
	local Plan = ns.Plan
	local name = Plan and Plan.RankName(r.rank) or L["the next rank"]
	local text
	if r.item then
		text = L["%s is a book, not a trainer rank: buy %s and read it (skill %d, level %d)."]:format(name,
			Doc.ItemName(r.item, d), r.skill, r.level)
	else
		local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(r.quest)
		if type(title) ~= "string" or title == "" then
			title = ns.PolestarNames and ns.PolestarNames.quest[r.quest] or L["Quest %d"]:format(r.quest)
		end
		text = L["%s comes from a quest, not a trainer: \"%s\" (skill %d, level %d); the fishing trainer in your capital sends you."]:format(
			name, title, r.skill, r.level)
	end
	d:Line(text, now and "body" or "small", now and "WARN" or "TEXT")
	local who, place
	if ns.Where then who, place = ns.Where.Npc(r.npc) end
	if who then
		local located = place and place.mapID
		d:Row({ left = who, leftInk = "TEXT", sub = place and (located and ("%s (%d, %d)"):format(place.zone, place.x + 0.5, place.y + 0.5)
			or place.zone) or nil, subInk = located and "ACCENT" or "OFF",
			tip = located and function(tip)
				tip:SetText(who)
				tip:AddLine(L["Click for a waypoint."], Color("LABEL"))
			end or nil,
			onClick = located and function() ns.Where.Go(who, place) end or nil })
	end
end

function Menu.GatherEntry()
	for _, p in ipairs(MyProfessions()) do
		if p.game == W.gather then return p end
	end
end

function Menu.GatherPage(d)
	local p = Menu.GatherEntry()
	if not p then
		d:Line(L["You don't have that profession any more."], "body", "OFF")
		return
	end
	local Plan = ns.Plan
	local skill, cap = p.skill or 0, p.max or 0
	d:Heading(L["Skill"])
	local rank = cap > 0 and Plan and Plan.RankName(cap)
	if rank then
		d:Line(L["%s: skill %d of %d."]:format(rank, skill, cap), "body", "VALUE")
	elseif cap > 0 then
		d:Line(L["Skill %d of %d."]:format(skill, cap), "body", "VALUE")
	else
		d:Line(L["Skill %d."]:format(skill), "body", "VALUE")
	end
	d:Bar(cap > 0 and skill / cap or 0)
	-- The next rank: trained at the cap, from a trainer of this profession. Fishing's Expert is a book
	-- and its Artisan a quest (FISHING_RANKS).
	local book = p.game == FISHING and FISHING_RANKS[cap]
	if book and cap < 300 then
		FishingRank(d, book, skill >= cap)
		if skill >= cap then d:Line(L["You're capped at %d until you do."]:format(cap), "small", "TEXT") end
	elseif cap > 0 and cap < 300 then
		local nextCap = cap + 75
		local name = Plan and Plan.RankName(nextCap) or L["the next rank"]
		local level = Plan and Plan.RankLevel(nextCap)
		if skill >= cap then
			d:Line(level and L["Train %s at a %s trainer (it asks level %d)."]:format(name, p.name, level)
				or L["Train %s at a %s trainer."]:format(name, p.name), "body", "WARN")
			d:Line(L["You're capped at %d until you do."]:format(cap), "small", "TEXT")
		else
			d:Line(level and L["At %d: train %s (level %d)."]:format(cap, name, level)
				or L["At %d: train %s."]:format(cap, name), "small", "TEXT")
		end
	elseif cap >= 300 and skill >= cap then
		d:Line(L["%s is at its top skill."]:format(p.name), "small", "GOOD")
	end
	-- Professionally Lost's guide window and its gathering panel, while its Leveling Guide stands
	-- in for ours on any profession (the hand-off study, section 5: "on the gathering profession
	-- pages"; ProfLost.lua: Handed("guide") with no profession asks "any it covers"). Each button
	-- only while the function behind it is there (CanOpenGuide, CanOpenGathering).
	local PL = ns.ProfLost
	if PL and PL.Handed and PL.Handed("guide") then
		local buttons = {}
		if PL.OpenGuide and (not PL.CanOpenGuide or PL.CanOpenGuide()) then
			buttons[#buttons + 1] = { text = L["Open Professionally Lost"], onClick = function() PL.OpenGuide(p.game) end }
		end
		if PL.OpenGathering and PL.CanOpenGathering and PL.CanOpenGathering() then
			buttons[#buttons + 1] = { text = L["Gathering Panel"], onClick = function() PL.OpenGathering() end }
		end
		if #buttons > 0 then
			d:Gap(4)
			d:Buttons(buttons)
		end
	end
	if p.crafts then
		d:Heading(L["Recipes"])
		-- (The game wouldn't open it from here: its own spell does.)
		local spell = p.line == 186 and ns.SpellName(SMELTING) or p.name
		d:Line(L["Cast %s from your spellbook to open its recipes here."]:format(spell or p.name), "small", "TEXT")
	elseif ns.Camp and ns.Camp.Has(p.game) then
		-- (Its only recipes are its camping items: no recipe list, Leveling Guide or Missing tab.)
		d:Line(L["%s's skill rises as you gather; its only recipes are its camping items, below."]:format(p.name), "small", "TEXT")
		ns.Camp.Section(d, p.game, ns.Window.Render)
	else
		d:Heading(L["Recipes"])
		d:Line(L["%s has no recipes: its skill rises as you gather, so there's no recipe list, Leveling Guide or missing recipes for it."]:format(p.name),
			"small", "TEXT")
	end
end

-- Every profession's camping items, in place of a profession's page.
-- ---------------------------------------------------------------------------------------------
-- Alts, Cooldowns and Tracking as pages of the window (the Blizzard Layout's side tabs for them),
-- shown where Camping's page is (W.gather set to their key)
-- ---------------------------------------------------------------------------------------------

W.ALTS, W.COOLS, W.TRACK = "alts", "cooldowns", "tracking"
local PART_PAGE = { alts = true, cooldowns = true, tracking = true }
function Menu.IsPartPage(gather) return gather ~= nil and PART_PAGE[gather] == true end

-- The page's name and icon (the title bar and the portrait).
function Menu.PartTitle(kind)
	local words = { alts = L["Your Alts"], cooldowns = L["Cooldowns"], tracking = L["Tracking"] }
	local icon
	for _, part in ipairs(Menu.Parts()) do if part.kind == kind then icon = part.icon end end
	return words[kind] or "", icon
end

-- Your alts' professions on this server, a heading per character, a row per profession: a click
-- shows its recipes (as the menu's rows did).
local function AltsPage(d)
	local alts = AltRows()
	if #alts == 0 then
		d:Line(L["None of your alts' professions are known yet: log in on an alt and open its professions once."], "small", "OFF")
		return
	end
	table.sort(alts, function(a, b)
		if (a.c.name or "") ~= (b.c.name or "") then return (a.c.name or "") < (b.c.name or "") end
		return a.line < b.line
	end)
	d:Line(L["Your other characters' professions on this server, as each last saw them. Click one to see its recipes."], "small", "TEXT")
	local last
	for _, a in ipairs(alts) do
		if a.c.name ~= last then
			last = a.c.name
			local name = a.c.name or "?"
			if ns.Learn and ns.Learn.ClassName then
				local ok, colored = pcall(ns.Learn.ClassName, a.c)
				if ok and type(colored) == "string" then name = colored end
			end
			d:Heading(name)
		end
		d:Row({ left = ns.Tips and ns.Tips.LineName(a.line) or tostring(a.line), leftInk = "VALUE",
			right = a.max > 0 and ("%d / %d"):format(a.skill, a.max) or tostring(a.skill), rightInk = "TEXT",
			onClick = function() ns.Window.ShowAlt(a.guid, a.line) end })
	end
end

-- Your craft cooldowns: a row each, ready or how long until it is; a click opens the recipe. While
-- one is cooling down the page is drawn again each half minute, only while it shows. (One timer:
-- a draw meanwhile puts the next one off again rather than adding another.)
local coolDue, coolPending
local function CoolDue()
	local left = (coolDue or 0) - GetTime()
	if left > 0.01 then
		C_Timer.After(left, CoolDue)
		return
	end
	coolPending = false
	if W.gather == W.COOLS and W.win and W.win:IsVisible() then ns.Window.Render() end
end
local function CooldownsPage(d)
	local all = ns.Cooldowns and ns.Cooldowns.List() or {}
	if #all == 0 then
		d:Line(L["You know no recipe that can only be made once in a while."], "small", "OFF")
		return
	end
	d:Line(L["Your recipes that can only be made once in a while. Click one to open it."], "small", "TEXT")
	local cooling = false
	for _, t in ipairs(all) do
		local ready = t.readyAt == 0
		if not ready then cooling = true end
		local more = {}
		for i = 2, #(t.names or {}) do more[#more + 1] = t.names[i] end
		d:Row({ icon = t.icon or 134400, left = (t.names and t.names[1]) or "?", leftInk = "VALUE",
			right = ready and L["Ready to craft"] or L["Ready in %s"]:format(ns.Cooldowns.Left(t.readyAt)),
			rightInk = ready and "GOOD" or "WARN",
			sub = #more > 0 and table.concat(more, ", ") or (ns.Tips and t.line and ns.Tips.LineName(t.line)) or nil,
			subInk = "TEXT",
			onClick = function()
				if t.line and t.spells and t.spells[1] then ns.Window.OpenRecipe(t.line, t.spells[1]) end
			end })
	end
	if cooling then
		coolDue = GetTime() + COOL_TICK
		if not coolPending then
			coolPending = true
			C_Timer.After(COOL_TICK, CoolDue)
		end
	end
end

-- Your professions' minimap tracking: a row each, on or off; a click turns it the other way.
local function TrackingPage(d)
	local all = TrackingList()
	if #all == 0 then
		d:Line(L["None of your professions tracks anything on the minimap."], "small", "OFF")
		return
	end
	d:Line(L["Your professions' minimap tracking. Click one to turn it on or off, or drag it to an action bar."], "small", "TEXT")
	for _, t in ipairs(all) do
		d:Row({ icon = t.icon, left = t.name or "?", leftInk = "VALUE",
			right = t.on and L["On"] or L["Off"], rightInk = t.on and "GOOD" or "OFF",
			tip = function(tip)
				if not (t.spell and pcall(tip.SetSpellByID, tip, t.spell)) then tip:SetText(t.name or "") end
				tip:AddLine(L["Drag: to an action bar"], Color("LABEL"))
			end,
			drag = function() PickupTracking(t.spell, t.name) end,
			onClick = function()
				pcall(C_Minimap.SetTracking, t.index, not t.on)
				ns.Window.Render()
			end })
	end
end

-- The page for W.gather when it is one of these, else nil.
function Menu.PartPage(gather)
	if gather == W.ALTS then return AltsPage end
	if gather == W.COOLS then return CooldownsPage end
	if gather == W.TRACK then return TrackingPage end
	return nil
end

function Menu.CampPage(d)
	if ns.Camp then ns.Camp.Page(d, ns.Window.Render) end
end
