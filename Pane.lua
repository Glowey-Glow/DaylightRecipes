-- The pane: three tabs (Recipe, Plan, Missing) over one scrolling page (a doc, Doc.lua; what the
-- pages say is Pages.lua). It sits in the frame DaylightUI docks to its profession window, or in one
-- of ours hung on DaylightMogul's window while Mogul runs the professions; the same page moves to
-- whichever is in use. With Glowey's Recipes' own profession window in use (Window.lua) the pane
-- isn't used at all.
-- With an enchant picked in the window beside, an enchant section sits flush along the pane's
-- bottom edge: the item it goes on (EnchantRow.lua, as in our own window's craft bar), Auto-replace,
-- and our own Enchant (the window's own Create can't use the kept item; Craft.Make can), with Next /
-- Done during a run. It stays while a run of ours is under way, on any tab.
-- Beside Daylight UI's own profession window, which from 2.1.2 shows a recipe's materials cost,
-- what it sells for and the profit itself, the Recipe tab leaves those to it (Pane.ProfitHanded;
-- asked once, the setting "duiProfit") and keeps what Daylight UI doesn't show.
local ADDON, ns = ...
if not ns.ok then return end
local DUI = ns.DUI or _G.DaylightUI   -- (ns.DUI: Host.lua; the global only in the offline tests)

local API, me = ns.API, ns.me
local L = ns.L
local Doc, Pages, Craft = ns.Doc, ns.Pages, ns.Craft
local S = ns.state
local Color, Hex, Text = Doc.Color, Doc.Hex, Doc.Text

local Pane = {}
ns.Pane = Pane

local PAD = 14

local root, doc

-- The fold tab: DaylightUI's look for its damage meter's fold (a small bordered tab on the panel's
-- outer edge with a grip on it, tucked under the edge). Folded, the pane slides away and fades
-- out, and the tab stays against the profession window's edge to bring it back. Always shown.
-- Remembered between sessions in DaylightRecipesDB.
-- It sits at the host's top corner on the side the pane hangs from (never mid-edge), 14 down from
-- the corner, the same spot open (on the pane's edge) and folded (on the window's edge): the place
-- the shop panels' tabs have had since 2.5 (Shop.lua's PlaceTab was the reference).
-- Docked means flush: the pane we hang ourselves (on DaylightMogul's window) sits against its
-- host's visible edge with no gap, and shares the host's border line when the host wears
-- DaylightUI's shell (Seam, below). On DaylightUI's own window the pane is DaylightUI's frame,
-- placed by DaylightUI with its own gap (Craft.PANE_GAP = 6: DaylightUI/Craft/Window.lua:726,
-- 759-760), and its frames are not ours to move (API.md, "The game's rules still apply"): that
-- gap stays.
-- luacheck: read globals GetPhysicalScreenSize
local FOLDED_WIDTH = 1          -- AttachCraftPane takes no 0; at 1 the pane is out of sight
local TAB_W, TAB_H = 14, 34
local TAB_TUCK = 3              -- how far the tab sits under the edge it hangs from
local TAB_DROP = 14             -- how far below the host's top corner it sits
local DUI_GAP = 6               -- DaylightUI's own gap between its window and a docked pane
local mogulSeam = 0             -- how far our pane on DaylightMogul's window tucks into it now
local shownWidth                -- the width the pane has now, while it slides
local foldTab
local slider                    -- drives the fold's slide
local function DB()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	return DaylightRecipesDB
end
local function Folded() return DB().folded == true end
local function TargetWidth() return Folded() and FOLDED_WIDTH or ns.Get("paneWidth") end
local duiPane, mogulPane
local tab = "recipe"
local filter = ""
local searchSerial = 0

-- What the pages are handed: a pick in DaylightUI's window, a redraw, the search.
local ctx = {
	make = true,
	redraw = function() Pane.Render() end,
	pick = function(spell)
		if S.mode == "dui" and API.SelectCraftRecipe then API.SelectCraftRecipe(spell) end
	end,
}

-- ---------------------------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------------------------

-- Professionally Lost has the open profession's Leveling Guide (ProfLost.lua): the Guide tab is
-- left out, and its guide's own window is a press away where the tab was.
local function Handed()
	local PL = ns.ProfLost
	if not (PL and PL.Handed) or S.linked then return false end
	return PL.Handed("guide", S.line) == true
end

local function PaintTabs()
	local handed = Handed()
	if handed and tab == "plan" then tab = "recipe" end
	local last
	for _, b in ipairs(root.tabs) do
		local shown = not (handed and b.key == "plan")
		b:SetShown(shown)
		if shown then
			b:ClearAllPoints()
			if last then
				b:SetPoint("LEFT", last, "RIGHT", 2, 0)
			else
				b:SetPoint("TOPLEFT", root, "TOPLEFT", PAD - 8, -10)
			end
			last = b
		end
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

-- ---------------------------------------------------------------------------------------------
-- The enchant section (along the bottom edge)
-- ---------------------------------------------------------------------------------------------

local ENCH_BAR = 44       -- its buttons' line, under the item
local ench                -- the section, built with the pane
local PaintEnchant

-- The enchant the section is for: a run of ours under way (on any tab), else the enchant picked in
-- the window beside while the Recipe tab is up. Never for someone else's linked recipes.
local function EnchantSpell()
	local run = Craft.Making()
	if run then return run.spell end
	local spell = S.recipe
	if S.linked or tab ~= "recipe" or type(spell) ~= "number" then return nil end
	if Craft.IsEnchant(spell) then return spell end
	return nil
end

local function EnchantCount()
	local n = tonumber(ench.count:GetText() or "") or 1
	return math.max(1, math.floor(n))
end

local function BuildEnchant()
	local f = CreateFrame("Frame", nil, root)
	f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
	f:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
	f:Hide()
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", 0, 0)
	line:SetColorTexture(1, 1, 1, 0.06)
	f.row = ns.EnchantRow.New(f, { pad = PAD, stacked = true, onChange = function() PaintEnchant() end })
	f.row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f.row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	f.row:Show()
	f:SetHeight(f.row:GetHeight() + ENCH_BAR)

	-- Enchant (Next during a run). A plain button: the window beside has its own main one.
	f.make = API.Button(f, L["Enchant"], 26)
	f.make:SetPoint("RIGHT", f, "BOTTOMRIGHT", -PAD, ENCH_BAR / 2)
	f.make:SetScript("OnClick", function()
		local run = Craft.Making()
		if run then
			if run.paused then Craft.Continue() end
			return
		end
		local spell = EnchantSpell()
		-- (It goes on the kept item, as many times as asked: Craft.Make finds it.)
		if spell then Craft.Make(spell, EnchantCount()) end
	end)
	f.done = API.Button(f, L["Done"], 26)
	f.done:SetPoint("RIGHT", f.make, "LEFT", -8, 0)
	f.done:SetScript("OnClick", function() Craft.Cancel() end)
	f.done:Hide()

	f.plus = API.Button(f, "+", 26)
	f.plus:SetWidth(26)
	f.plus:SetPoint("RIGHT", f.make, "LEFT", -12, 0)
	f.count = API.Input(f, { numeric = true })
	f.count:SetSize(46, 26)
	f.count:SetPoint("RIGHT", f.plus, "LEFT", -4, 0)
	f.count:SetText("1")
	f.count:SetJustifyH("CENTER")
	f.minus = API.Button(f, "-", 26)
	f.minus:SetWidth(26)
	f.minus:SetPoint("RIGHT", f.count, "LEFT", -4, 0)
	local function Step(by) f.count:SetText(tostring(math.max(1, EnchantCount() + by))) end
	f.plus:SetScript("OnClick", function() Step(IsShiftKeyDown() and 10 or 1) end)
	f.minus:SetScript("OnClick", function() Step(IsShiftKeyDown() and -10 or -1) end)

	f.status = Text(f, "body", "LEFT")
	f.status:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, ENCH_BAR / 2)
	f.status:SetWordWrap(false)
	f.status:Hide()
	return f
end

-- The section shown (or not) for what's picked and what's being made; the page above ends at it.
PaintEnchant = function()
	if not ench then return end
	local scroll = doc.scroll
	local spell = EnchantSpell()
	if not spell then
		ench:Hide()
		scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
		return
	end
	ench:Show()
	scroll:SetPoint("BOTTOMRIGHT", ench, "TOPRIGHT", 0, 0)
	-- (The item's name and hint wrap inside the pane's width; the section is as tall as they need.)
	local target = ench.row:Update(spell, shownWidth or TargetWidth())
	ench:SetHeight(ench.row:GetHeight() + ENCH_BAR)
	local run = Craft.Making()
	local f = ench
	local counting = not run and target ~= nil
	f.minus:SetShown(counting)
	f.count:SetShown(counting)
	f.plus:SetShown(counting)
	f.done:SetShown(run ~= nil and run.paused == true)
	f.status:Hide()
	if run then
		if run.paused then
			-- Between two enchants of a run: Next (one enchant a click) and Done.
			f.make.text:SetText(L["Next (%d Left)"]:format(run.count - run.done))
			f.make.SetOff(false)
			f.make:Show()
			f.status:SetText(L["%d of %d done"]:format(run.done, run.count))
			f.status:SetTextColor(Color("LABEL"))
			if ns.Guide then ns.Guide.Offer("enchant") end
		else
			f.make:Hide()
			f.status:SetText(L["Making %d of %d"]:format(math.min(run.done + 1, run.count), run.count))
			f.status:SetTextColor(API.Accent())
		end
	else
		local info = Craft.TS("GetRecipeInfo", spell)
		local verb = type(info) == "table" and info.alternateVerb
		if type(verb) ~= "string" or verb == "" then verb = L["Enchant"] end
		f.make.text:SetText(verb)
		f.make.SetOff((type(info) == "table" and info.disabled == true) or Craft.Count(spell) < 1)
		f.make:Show()
	end
	if f.make.FitWidth then f.make.FitWidth(96) end
	if f.done.FitWidth then f.done.FitWidth(80) end
	-- (The run's count on the left, only where it fits whole: Next says what's left as well.)
	if run then
		local room = (shownWidth or TargetWidth()) - 2 * PAD - 12
		if f.make:IsShown() then room = room - f.make:GetWidth() end
		if f.done:IsShown() then room = room - f.done:GetWidth() - 8 end
		f.status:SetShown(f.status:GetStringWidth() <= room)
	end
end

-- What the tour of enchanting runs lights while the pane is in use (RecipesGuide.lua).
function Pane.EnchantPart()
	if ench and ench:IsVisible() then return ench end
	return nil
end

-- A craft of ours started, moved on or ended, or the kept item or Auto-replace changed (Craft.lua).
function Pane.CraftChanged()
	if not (ench and root:IsVisible()) or Folded() then return end
	local was = ench:IsShown()
	PaintEnchant()
	-- (The section came or went: the page above takes the room. Else only buttons changed: the
	-- controller's cursor finds them again.)
	if ench:IsShown() ~= was then
		ns.Changed()
	elseif ns.Pad and ns.Pad.On() then
		ns.Pad.Settle()
	end
end

local function Build()
	root = CreateFrame("Frame", nil, UIParent)
	root:Hide()
	-- Drawn while its window was shut: draw again once it shows.
	root:SetScript("OnShow", function() ns.Changed() end)
	root.tabs = {}
	for i, spec in ipairs({ { "recipe", L["Recipe"] }, { "plan", L["Guide"] }, { "missing", L["Missing"] } }) do
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
			if doc then doc:Top() end
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
	-- "Open Professionally Lost", for a profession whose Leveling Guide is handed to it: after the
	-- tabs when it fits there, else on a line of its own under them (Pane.Render places it).
	root.pl = CreateFrame("Button", nil, root)
	root.pl:SetHeight(26)
	root.pl.text = Text(root.pl, "small")
	root.pl.text:SetPoint("CENTER", 0, 1)
	root.pl.text:SetWordWrap(false)
	root.pl:SetScript("OnEnter", function(self) self.text:SetTextColor(Color("VALUE")) end)
	root.pl:SetScript("OnLeave", function(self) self.text:SetTextColor(Color("ACCENT")) end)
	root.pl:SetScript("OnClick", function()
		local PL = ns.ProfLost
		if PL and PL.OpenGuide then PL.OpenGuide(S.line) end
	end)
	root.pl:Hide()
	root.skill = Text(root, "small", "RIGHT")
	root.skill:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, -18)
	root:SetClipsChildren(true)

	root.search = API.Input(root, { search = true, hint = L["Search"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == filter then return end
			filter = text
			-- One search a moment after the last key, not one per key (each goes over every recipe).
			searchSerial = searchSerial + 1
			local serial = searchSerial
			C_Timer.After(0.15, function()
				if serial ~= searchSerial then return end
				if doc then doc:Top() end
				Pane.Render()
			end)
		end })
	root.search:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -44)
	root.search:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, -44)

	doc = Doc.New(root, { pad = PAD, redraw = function() Pane.Render() end, idle = Folded })
	doc.scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
	ench = BuildEnchant()
end

-- The pane in use: DaylightUI's docked one, or ours on Mogul's window.
local function Host()
	if S.mode == "mogul" then return mogulPane end
	if not duiPane then
		shownWidth = TargetWidth()
		duiPane = me.AttachCraftPane(shownWidth)
	end
	return duiPane
end

-- The window DaylightUI's docked pane hangs on (DaylightUI's profession window), once it exists.
function Pane.HostWindow()
	local parent = duiPane and duiPane:GetParent()
	if parent and parent ~= UIParent then return parent end
	return nil
end

-- How far a pane of ours tucks into its host so the two share one border line, the way
-- DaylightUI's threat meter hangs on its damage meter (DaylightUI_InfoPanel/ThreatMeter.lua:458-466:
-- moved in by the host's border, Pixel.Px(h, Style.BorderPx(h))). 0 for a host without DaylightUI's
-- bordered shell: flush at its edge, no overlap.
--   - Whether the host wears that shell: Style.GetShell(frame) (DaylightUI/Style.lua:988), which the
--     threat meter asks of its host the same way. It is not part of DaylightUI's API, so it is read
--     guarded and nothing is ever changed through it; without it there is no overlap.
--   - The border's thickness: the player's setting "general" > borderPx (default 8: DaylightUI/
--     DB.lua:52), read the sanctioned way (API.GetSetting: API.md, "Read settings"), in screen
--     pixels; one screen pixel is 768 / the screen's physical height, over the frame's effective
--     scale (DaylightUI/Pixel.lua:11-28; GetPhysicalScreenSize: Blizzard_APIDocumentationGenerated/
--     ScreenDocumentation.lua:19).
--   - A shell can have a thickness of its own (its opts.borderPx: DaylightUI/Style.lua:994-1003), and
--     DaylightUI's own docking asks the host's shell for it (Style.BorderPx(h): ThreatMeter.lua:420,
--     459). Asked first, guarded the same way; the general setting is the fallback.
local function Seam(host)
	local D = _G.DaylightUI
	local style = type(D) == "table" and D.Style
	local get = type(style) == "table" and style.GetShell
	if type(get) ~= "function" then return 0 end
	local ok, shell = pcall(get, host)
	if not ok or type(shell) ~= "table" then return 0 end
	if type(shell.opts) == "table" and shell.opts.noBorder == true then return 0 end
	local px
	local own = style.BorderPx
	if type(own) == "function" then
		local got, value = pcall(own, host)
		if got and type(value) == "number" then px = value end
	end
	if px == nil then
		local okPx, value = pcall(API.GetSetting, "general", "borderPx")
		if okPx then px = value end
	end
	if type(px) ~= "number" or px <= 0 then return 0 end
	local height
	if type(GetPhysicalScreenSize) == "function" then
		local _, h = GetPhysicalScreenSize()
		height = h
	end
	if type(height) ~= "number" or height <= 0 then return 0 end
	local scale = host:GetEffectiveScale()
	if type(scale) ~= "number" or scale <= 0 then return 0 end
	return px * 768 / height / scale
end

-- Our pane on DaylightMogul's window: flush against its visible right edge (no gap), one border
-- line between them. Placed again whenever it's drawn (the border's thickness is a setting).
local function PlaceMogul()
	local win = mogulPane and mogulPane:GetParent()
	if not win then return end
	mogulSeam = Seam(win)
	mogulPane:ClearAllPoints()
	mogulPane:SetPoint("TOPLEFT", win, "TOPRIGHT", -mogulSeam, 0)
	mogulPane:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", -mogulSeam, 0)
end

function Pane.AttachMogul(win)
	if type(win) ~= "table" or not win.CreateTexture then return end
	if not mogulPane then
		mogulPane = CreateFrame("Frame", "DaylightRecipesPane", win)
		mogulPane:SetWidth(shownWidth or TargetWidth())
		mogulPane:EnableMouse(true)
		ns.SkinWindow(mogulPane)
	end
	PlaceMogul()
end

function Pane.Shown()
	return root ~= nil and root:IsVisible()
end

-- Whether the pane is the one in use (not Glowey's Recipes' own window).
local function InUse() return S.mode == "dui" or S.mode == "mogul" end

-- ---------------------------------------------------------------------------------------------
-- Cost and profit: Daylight UI's window shows them too
-- ---------------------------------------------------------------------------------------------
-- Daylight UI 2.1.2's profession window has a Profit section on its recipe side (Materials, Sells
-- for, Auction House cut, Profit: DaylightUI\Craft\Recipe.lua:411-437) and a Profit chip over its
-- list (Craft\List.lua:92-124). Both show while its Profit.On() holds (Craft\Profit.lua:27-30):
-- its Auction House's prices are published (DaylightUI.AuctionPrices, set at login by
-- DaylightUI_AuctionHouse\Bridge.lua:36-40 unless DaylightMogul owns the house) and its setting
-- "profit" isn't off (the Professions module's, on by default: Craft\Defaults.lua:13,
-- Craft\Options.lua:25-27, Craft\Module.lua:25). With our pane docked to that window the Recipe
-- tab then said the same twice, with slightly different numbers (its prices are the usual ones,
-- its materials the cheapest of buying and making; ours the lowest seen).
-- So by default the pane leaves the materials total and the Auction House's "sells for" and
-- profit to Daylight UI's window, and keeps what that doesn't show: each material's price and
-- where from, the cost per skill point, the vendor's and disenchanting's value. Asked once, the
-- first time both would show (the answer kept per account: DaylightRecipesDB.duiProfitAsked, the
-- setting "duiProfit"), and changed any time in the options.
-- Only beside Daylight UI's own window (S.mode "dui"): never in our own window, nor beside
-- DaylightMogul's (Daylight UI shows no profit there: Craft\Options.lua:27).

local function DaylightAtLeast(a, b, c)
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	if type(meta) ~= "function" then return false end
	local ok, version = pcall(meta, "DaylightUI", "Version")
	if not ok or type(version) ~= "string" then return false end
	local x, y, z = version:match("^(%d+)%.(%d+)%.?(%d*)")
	if not x then return false end
	x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
	if x ~= a then return x > a end
	if y ~= b then return y > b end
	return z >= c
end

-- Whether Daylight UI's profession window can show a recipe's cost and profit at all: 2.1.2 or
-- later, its Professions module on, not handed to DaylightMogul, and its Auction House's prices
-- published. (For the option: there's nothing to choose without it.)
function Pane.ProfitCould()
	if type(DUI) ~= "table" or DUI.craftMogul == true then return false end
	if not DaylightAtLeast(2, 1, 2) then return false end
	local prices = DUI.AuctionPrices
	if type(prices) ~= "table" or type(prices.Item) ~= "function" then return false end
	local ok, on = pcall(API.IsModuleEnabled, "Professions")
	return ok and on == true
end

-- Whether it is showing them right now beside our pane: all of the above, the pane docked to
-- its window, and its own "Profit" setting not switched off.
function Pane.ProfitApplies()
	if S.mode ~= "dui" or not Pane.ProfitCould() then return false end
	local ok, profit = pcall(API.GetSetting, "Professions", "profit")
	return ok and profit ~= false
end

-- Whether the pane's Recipe tab leaves cost and profit to Daylight UI's window: it shows them,
-- and the player hasn't asked to keep both.
function Pane.ProfitHanded()
	return Pane.ProfitApplies() and ns.Get("duiProfit") ~= false
end

-- Something else of Daylight UI's or of a Daylight plugin is up (its setup guide, tour or a
-- question; a plugin's welcome, What's New or tour, ours included: _G.DaylightGuides, Guide.lua),
-- or a fight is on: our question waits.
-- The face lift's order at login is the welcome or What's New first, then Professionally Lost's
-- "which addon does what" window, each only once the one before is closed (Guide.Busy, ProfLost.lua).
-- This question takes its turn after both: it waits while Guide.Busy holds (the welcome or the
-- note not yet decided or still up, a tour, Daylight UI's own guides), while that window is still
-- to come at this login (ProfLost.Due) and while it is up (it holds our mark in _G.DaylightGuides,
-- looked at below). And while this question is up it holds that mark itself (Guide.Hold), which
-- Guide.Busy counts, so that window waits for it in turn: the two are never up together.
local DAYLIGHT_DIALOGS = { "DaylightUIInstaller", "DaylightUITour", "DaylightUITourAsk", "DaylightUIAsk",
	"DaylightUIQuestieChoice" }
local function Busy()
	if InCombatLockdown() then return true end
	if ns.Guide and ns.Guide.Busy and ns.Guide.Busy() then return true end
	if ns.Guide and ns.Guide.Welcoming and ns.Guide.Welcoming() then return true end
	if ns.ProfLost and ns.ProfLost.Due and ns.ProfLost.Due() then return true end
	if ns.Sources and ns.Sources.Due and ns.Sources.Due() then return true end
	for _, name in ipairs(DAYLIGHT_DIALOGS) do
		local f = _G[name]
		if type(f) == "table" and f.IsShown and f:IsShown() and (not f.GetAlpha or (f:GetAlpha() or 0) > 0.05) then return true end
	end
	local guides = _G.DaylightGuides
	if type(guides) == "table" then
		for _, on in pairs(guides) do
			if on then return true end
		end
	end
	return false
end

-- Asked once, the first time the pane's Recipe tab and Daylight UI's Profit section would show
-- side by side. (The game's own question box, as our other one-time questions: Swap.lua's,
-- Tips.lua's; a controller answers it as it does the game's.)
local asking = false
local function AskProfit()
	local db = DB()
	if db.duiProfitAsked or asking or not Pane.ProfitApplies() then return end
	asking = true
	local tries = 0
	local function try()
		tries = tries + 1
		if db.duiProfitAsked or not Pane.ProfitApplies() then
			asking = false
			return
		end
		if Busy() then
			-- (A while longer; given up for now after a few minutes, asked again another time.)
			if tries < 60 then C_Timer.After(3, try) else asking = false end
			return
		end
		asking = false
		db.duiProfitAsked = true
		StaticPopupDialogs.DAYLIGHTRECIPES_DUI_PROFIT = {
			text = L["Daylight UI's profession window now shows a recipe's materials cost and profit. Leave those to it in the Docked Pane?\n\nThe pane keeps what Daylight UI doesn't show: each material's price, the cost per skill point, and the vendor and disenchant value. You can change this later in Glowey's Recipes' options."],
			button1 = L["Use Daylight UI's"],
			button2 = L["Keep Both"],
			OnAccept = function() pcall(DUI.Set, DUI, ADDON, "duiProfit", true) end,
			OnCancel = function(_, _, reason)
				if reason == "clicked" then pcall(DUI.Set, DUI, ADDON, "duiProfit", false) end
			end,
			-- (Answered or put away: Professionally Lost's window, if it was waiting, may come.)
			OnHide = function() if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("profit", false) end end,
			timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
		}
		if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("profit", true) end
		StaticPopup_Show("DAYLIGHTRECIPES_DUI_PROFIT")
	end
	C_Timer.After(1, try)
end
Pane.AskProfit = AskProfit

-- Whether the page now drawn is waiting on this item's data.
function Pane.Waiting(itemID)
	return doc ~= nil and doc:Waiting(itemID)
end

-- Whether the Leveling Guide is what's on show (bags, bank, mail and prices only redraw that page).
function Pane.ShowingPlan()
	return Pane.Shown() and tab == "plan" and not Folded()
end

-- Whether the missing list is what's on show.
function Pane.ShowingMissing()
	return Pane.Shown() and tab == "missing" and not Folded()
end

function Pane.Render()
	if not InUse() then return end
	local host = Host()
	if not host then return end
	if not root then Build() end
	if root:GetParent() ~= host then
		root:SetParent(host)
		root:ClearAllPoints()
		root:SetAllPoints(host)
	end
	root:Show()
	if host == mogulPane then PlaceMogul() end
	if not host:IsVisible() then return end

	-- Folded (after a reload, or the window reopened): out of sight at once. A slide fades it itself.
	if not (slider and slider:GetScript("OnUpdate")) then host:SetAlpha(Folded() and 0 or 1) end
	Pane.PlaceTab(host)
	if Folded() then return end

	PaintTabs()
	local width = shownWidth or TargetWidth()
	-- The tabs' width, and "Open Professionally Lost" where the Guide tab was: on the tabs' row when
	-- it fits there, else on a row of its own under them (the page starts that much lower).
	local tabsW = PAD - 8
	for _, b in ipairs(root.tabs) do
		if b:IsShown() then tabsW = tabsW + b:GetWidth() + 2 end
	end
	local PL = ns.ProfLost
	local offer = Handed() and PL.OpenGuide and (not PL.CanOpenGuide or PL.CanOpenGuide())
	local drop = 0          -- how much lower the page starts
	root.pl:SetShown(offer and true or false)
	if offer then
		root.pl.text:SetText(L["Open Professionally Lost"])
		root.pl.text:SetTextColor(Color(root.pl:IsMouseOver() and "VALUE" or "ACCENT"))
		local bw = math.ceil(root.pl.text:GetUnboundedStringWidth()) + 16
		root.pl:SetWidth(bw)
		root.pl:ClearAllPoints()
		if tabsW + bw <= width - PAD + 8 then
			root.pl:SetPoint("TOPLEFT", root, "TOPLEFT", tabsW, -10)
			tabsW = tabsW + bw + 2
		else
			root.pl:SetPoint("TOPLEFT", root, "TOPLEFT", PAD - 8, -36)
			drop = 26
		end
	end
	local missing = tab == "missing"
	root.search:SetShown(missing)
	root.search:ClearAllPoints()
	root.search:SetPoint("TOPLEFT", root, "TOPLEFT", PAD, -44 - drop)
	root.search:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAD, -44 - drop)
	local scroll = doc.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, (missing and -(44 + root.search:GetHeight() + 8) or -40) - drop)
	scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
	-- (An enchant picked, or a run of ours under way: the enchant section, the page ending above it.)
	PaintEnchant()

	if S.name and (S.max or 0) > 0 then
		root.skill:SetText(Hex(Color("LABEL")) .. S.name .. "|r  " .. S.skill .. " / " .. S.max)
		root.skill:SetTextColor(Color("VALUE"))
		-- (Too long for the room right of the tabs, in a narrow pane: the skill alone, or nothing when
		-- even that would run into them; the profession window beside shows it too.)
		local room = width - PAD - tabsW - 8
		if root.skill:GetStringWidth() > room then root.skill:SetText(S.skill .. " / " .. S.max) end
		if root.skill:GetStringWidth() > room then root.skill:SetText("") end
	else
		root.skill:SetText("")
	end

	doc:Begin()
	ctx.filter = filter
	local ok, err
	if missing then
		ok, err = pcall(Pages.Missing, doc, ctx)
	elseif tab == "plan" then
		ok, err = pcall(Pages.Guide, doc, ctx)
	else
		-- (Beside Daylight UI's window, which shows cost and profit itself: without ours, by
		-- default; the first time, asked.)
		ok, err = pcall(Pages.Recipe, doc, Pane.ProfitHanded())
		AskProfit()
	end
	if not ok then
		geterrorhandler()(err)
		doc:Line(L["Something went wrong drawing this page."], "small", "BAD")
	end
	doc:Finish()
end

-- The pane's width now, on whichever host there is (DaylightUI's through AttachCraftPane, so its
-- window and the ones beside it make room).
local function ApplyWidth(w)
	shownWidth = w
	if duiPane then me.AttachCraftPane(w) end
	if mogulPane then
		mogulPane:SetWidth(w)
		ns.SkinWindow(mogulPane)
	end
end

function Pane.Resize()
	ApplyWidth(TargetWidth())
	if Pane.Shown() then ns.Changed() end
end

-- The grip on the tab: three short bars, gray, in the accent under the mouse (Host.Tint: drawn
-- again in the new colors after a look change).
local function PaintGrip(hover)
	if not foldTab then return end
	for _, bar in ipairs(foldTab.bars) do ns.Host.Tint(bar, hover and "pop" or "LABEL", 1) end
end

local function BuildTab()
	foldTab = CreateFrame("Button", nil, UIParent)
	foldTab:SetSize(TAB_W, TAB_H)
	foldTab:SetIgnoreParentAlpha(true)   -- it stays while the folded pane fades out
	-- (Host.Skin: dressed again after a look change.)
	ns.Host.Skin(foldTab, { noBevel = true })
	foldTab.bars = {}
	for i = 1, 3 do
		local bar = foldTab:CreateTexture(nil, "OVERLAY")
		bar:SetSize(6, 2)
		bar:SetPoint("CENTER", foldTab, "CENTER", 0, (2 - i) * 4)
		foldTab.bars[i] = bar
	end
	PaintGrip(false)
	foldTab:SetScript("OnClick", function() Pane.SetFolded(not Folded()) end)
	foldTab:SetScript("OnEnter", function(self)
		PaintGrip(true)
		ns.Host.Tip(self, Folded() and L["Open Glowey's Recipes"] or L["Fold Glowey's Recipes away"], nil, nil, "ANCHOR_RIGHT")
	end)
	foldTab:SetScript("OnLeave", function()
		PaintGrip(false)
		GameTooltip:Hide()
	end)
end

-- The tab at the host's top corner, on the side the pane hangs from: on the pane's outer edge
-- while it's open, on the window's edge (where the pane folds into) while folded, 14 down from the
-- corner either way, and under the edge's border.
function Pane.PlaceTab(host)
	if not host then return end
	if not foldTab then BuildTab() end
	if foldTab:GetParent() ~= host then
		foldTab:SetParent(host)
		foldTab:SetIgnoreParentAlpha(true)
	end
	foldTab:SetFrameStrata(host:GetFrameStrata())
	foldTab:SetFrameLevel(math.max(0, host:GetFrameLevel() - 1))
	foldTab:ClearAllPoints()
	if Folded() then
		-- (The window's own right edge: the host's left, less the gap its dock has.)
		local gap = host == mogulPane and -mogulSeam or DUI_GAP
		foldTab:SetPoint("TOPLEFT", host, "TOPLEFT", -gap - TAB_TUCK, -TAB_DROP)
	else
		foldTab:SetPoint("TOPLEFT", host, "TOPRIGHT", -TAB_TUCK, -TAB_DROP)
	end
	foldTab:Show()
end

-- Folds the pane away or brings it back, sliding at DaylightUI's NORMAL speed: folding narrows the
-- pane as it fades out, opening widens it as it fades in and draws the page at the end.
function Pane.SetFolded(folded)
	DB().folded = folded and true or nil
	GameTooltip:Hide()
	local host = Host()
	local from, to = shownWidth or TargetWidth(), TargetWidth()
	local duration = (API.Speed and API.Speed.NORMAL) or 0.2
	if host then API.Fade(host, folded and 0 or 1, duration) end
	if root and not folded then Pane.Render() end
	if from == to then
		ApplyWidth(to)
		if host then Pane.PlaceTab(host) end
		return
	end
	slider = slider or CreateFrame("Frame")
	local elapsed = 0
	slider:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		local t = math.min(1, elapsed / duration)
		t = 1 - (1 - t) * (1 - t)   -- ease out
		ApplyWidth(math.floor(from + (to - from) * t + 0.5))
		if t >= 1 then
			self:SetScript("OnUpdate", nil)
			if host then Pane.PlaceTab(host) end
			if not Folded() then ns.Changed() end
		end
	end)
end

-- The player's font changed: every string we made takes it, at its size.
function Pane.Restyle()
	if Pane.Shown() then ns.Changed() end
end

-- DaylightUI's pane is asked for at login, so it's docked before the window first opens.
me.On("Login", function() Host() end)
