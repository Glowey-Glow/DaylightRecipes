-- The pane: three tabs (Recipe, Plan, Missing) over one scrolling page (a doc, Doc.lua; what the
-- pages say is Pages.lua). It sits in the frame DaylightUI docks to its profession window, or in one
-- of ours hung on DaylightMogul's window while Mogul runs the professions; the same page moves to
-- whichever is in use. With Daylight Recipes' own profession window in use (Window.lua) the pane
-- isn't used at all.
local _, ns = ...
if not ns.ok then return end

local API, me = ns.API, ns.me
local L = ns.L
local Doc, Pages = ns.Doc, ns.Pages
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
local FOLDED_WIDTH = 1          -- AttachCraftPane takes no 0; at 1 the pane is out of sight
local TAB_W, TAB_H = 14, 34
local TAB_TUCK = 3              -- how far the tab sits under the edge it hangs from
local WINDOW_GAP = 6            -- the gap between the window and a docked pane
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

	doc = Doc.New(root, { pad = PAD })
	doc.scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)
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

function Pane.AttachMogul(win)
	if type(win) ~= "table" or not win.CreateTexture then return end
	if not mogulPane then
		mogulPane = CreateFrame("Frame", "DaylightRecipesPane", win)
		mogulPane:SetPoint("TOPLEFT", win, "TOPRIGHT", 6, 0)
		mogulPane:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", 6, 0)
		mogulPane:SetWidth(shownWidth or TargetWidth())
		mogulPane:EnableMouse(true)
		ns.SkinWindow(mogulPane)
	end
end

function Pane.Shown()
	return root ~= nil and root:IsVisible()
end

-- Whether the pane is the one in use (not Daylight Recipes' own window).
local function InUse() return S.mode == "dui" or S.mode == "mogul" end

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
	if not host:IsVisible() then return end

	-- Folded (after a reload, or the window reopened): out of sight at once. A slide fades it itself.
	if not (slider and slider:GetScript("OnUpdate")) then host:SetAlpha(Folded() and 0 or 1) end
	Pane.PlaceTab(host)
	if Folded() then return end

	PaintTabs()
	local missing = tab == "missing"
	root.search:SetShown(missing)
	local scroll = doc.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", root, "TOPLEFT", 0, missing and -(44 + root.search:GetHeight() + 8) or -40)
	scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 10)

	if S.name and (S.max or 0) > 0 then
		root.skill:SetText(Hex(Color("LABEL")) .. S.name .. "|r  " .. S.skill .. " / " .. S.max)
		root.skill:SetTextColor(Color("VALUE"))
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
		ok, err = pcall(Pages.Recipe, doc)
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

-- The grip on the tab: three short bars, gray, in the accent under the mouse.
local function PaintGrip(hover)
	if not foldTab then return end
	local r, g, b
	if hover then r, g, b = API.Accent() else r, g, b = Color("LABEL") end
	for _, bar in ipairs(foldTab.bars) do bar:SetColorTexture(r, g, b, 1) end
end

local function BuildTab()
	foldTab = CreateFrame("Button", nil, UIParent)
	foldTab:SetSize(TAB_W, TAB_H)
	foldTab:SetIgnoreParentAlpha(true)   -- it stays while the folded pane fades out
	API.Skin(foldTab, { noBevel = true })
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
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Folded() and L["Open Daylight Recipes"] or L["Fold Daylight Recipes away"])
		GameTooltip:Show()
	end)
	foldTab:SetScript("OnLeave", function()
		PaintGrip(false)
		GameTooltip:Hide()
	end)
end

-- The tab on the host's outer edge, vertically centered: on the pane's edge while it's open, on the
-- window's edge (where the pane folds into) while folded. Under the edge's border either way.
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
		foldTab:SetPoint("LEFT", host, "LEFT", -WINDOW_GAP - TAB_TUCK, 0)
	else
		foldTab:SetPoint("LEFT", host, "RIGHT", -TAB_TUCK, 0)
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
