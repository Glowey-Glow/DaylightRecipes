-- The swap button (two arrows) beside the X of every profession window Daylight Recipes stands in
-- for: on ours it hands the profession to the game's own window ("game"); on that one (or
-- DaylightUI's or DaylightMogul's, in "pane") it brings Daylight Recipes' window back. It flips the
-- "Profession window" choice, so the window picked stays picked, and reopens the profession that
-- was open so it shows in the other window at once.
-- The first time Daylight Recipes loads it asks once: "Use Daylight Recipes' profession window?"
-- Yes makes ours the one, and switches DaylightUI's own profession window off (its Professions
-- module's "enabled", which it reads at login: one reload), so a swap shows the game's window.
-- What DaylightUI's switch was is recorded; picking "Docked pane" (theirs with our pane) in our
-- options turns it back on. No keeps the window in use now, with our pane beside it.
-- The icon is ours (Media\ui-swap.png), drawn in the line style of DaylightUI's icons; the button
-- behaves like DaylightUI's small icon buttons: label ink at rest, the accent under the mouse, its
-- name after the mouse rests a moment.
local ADDON, ns = ...
if not ns.ok then return end

local API, L = ns.API, ns.L
local DUI = _G.DaylightUI

local Swap = {}
ns.Swap = Swap

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\ui-swap.png"
local SIZE, ICON_SIZE, GAP, TIP_WAIT = 20, 14, 6, 0.6

local function Ink(name)
	local ok, colors = pcall(API.Colors)
	local c = ok and type(colors) == "table" and colors[name]
	if type(c) == "table" then return c[1], c[2], c[3] end
	return 0.7, 0.7, 0.7
end

local function Paint(b, over)
	local r, g, bl
	if over then r, g, bl = API.Accent() else r, g, bl = Ink("LABEL") end
	b.icon:SetVertexColor(r, g, bl, b:IsEnabled() and 1 or 0.4)
end

-- What a click does: the other window, and the words for the tooltip.
local function Target()
	if ns.Get("window") == "recipes" then return "game", L["Use the game's profession window"] end
	return "recipes", L["Use Daylight Recipes' window"]
end

-- ---------------------------------------------------------------------------------------------
-- DaylightUI's own profession window, off while ours is the one (recorded, given back)
-- ---------------------------------------------------------------------------------------------

local function DB()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	return DaylightRecipesDB
end

local function AskReload(text)
	StaticPopupDialogs.DAYLIGHTRECIPES_RELOAD = {
		text = text, button1 = L["Reload Now"], button2 = L["Later"],
		OnAccept = function() ReloadUI() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopup_Show("DAYLIGHTRECIPES_RELOAD")
end

local function DuiCraftOn()
	local ok, on = pcall(DUI.Get, DUI, "Professions", "enabled")
	return ok and on ~= false
end

-- Ours is the one: DaylightUI's profession window goes off (after a reload).
local function TakeFromDaylightUI()
	if not DuiCraftOn() then return end
	DB().duiCraftWas = true
	if pcall(DUI.Set, DUI, "Professions", "enabled", false) then
		AskReload(L["DaylightUI's profession window turns off after a reload, so the swap button shows the game's window. Reload now?"])
	end
end

-- Theirs again ("Docked pane" picked): DaylightUI's profession window back as it was.
local function GiveToDaylightUI()
	local db = DB()
	if not db.duiCraftWas then return end
	db.duiCraftWas = nil
	if not DuiCraftOn() and pcall(DUI.Set, DUI, "Professions", "enabled", true) then
		AskReload(L["DaylightUI's profession window comes back after a reload. Reload now?"])
	end
end

local swapping = false   -- the swap button is changing the choice (no reload asked for that)

-- The "Profession window" choice changed (Core.lua's settings handler).
function Swap.Picked(value)
	if swapping then return end
	if value == "recipes" then TakeFromDaylightUI()
	elseif value == "pane" then GiveToDaylightUI() end
end

local function Ask()
	local db = DB()
	if db.windowAsked then return end
	db.windowAsked = true
	StaticPopupDialogs.DAYLIGHTRECIPES_WINDOW = {
		text = L["Use Daylight Recipes' profession window?\n\nIt takes the place of the game's and DaylightUI's profession windows. The swap button beside its X switches to the game's window and back any time. You can change this later in Daylight Recipes' options."],
		button1 = L["Use Recipes' Window"],
		button2 = L["Keep My Window"],
		OnAccept = function()
			if ns.Get("window") == "recipes" then TakeFromDaylightUI() else DUI:Set(ADDON, "window", "recipes") end
		end,
		OnCancel = function(_, _, reason)
			if reason == "clicked" then DUI:Set(ADDON, "window", "pane") end
		end,
		timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
	}
	StaticPopup_Show("DAYLIGHTRECIPES_WINDOW")
end
ns.me.On("Login", function() C_Timer.After(2, Ask) end)

-- The open profession's line as the game knows it (Mining's may not be the one our data uses).
local function OpenLine()
	local fn = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo
	if type(fn) == "function" then
		local ok, info = pcall(fn)
		if ok and type(info) == "table" and type(info.professionID) == "number" then return info.professionID end
	end
	return ns.state and ns.state.line or nil
end

local function Flip()
	if InCombatLockdown() then
		ns.Print(L["Profession windows can be switched once the fight ends."])
		return
	end
	local to = Target()
	local open = ns.Take and ns.Take.Open()
	local line = OpenLine()
	-- The open profession stays open and moves across: the choice changing makes Take let the
	-- game's window go to the screen (to the game's) or hold it again for ours (Take.Recheck).
	swapping = true
	DUI:Set(ADDON, "window", to)
	swapping = false
	local own = _G.DaylightRecipesWindow
	if to == "recipes" then
		-- (No profession open: ours opens on the last one, as /recipes does.)
		if not open and ns.Window and not ns.Window.Shown() then ns.Window.Toggle() end
		return
	end
	if open then
		if ns.Take then ns.Take.ToScreen() end
		-- (No new profession opens, so the button goes on the game's window here, once it shows.)
		C_Timer.After(0.05, function() if Swap.PlaceOther then Swap.PlaceOther() end end)
		C_Timer.After(0.3, function() if Swap.PlaceOther then Swap.PlaceOther() end end)
		return
	end
	-- Ours was up with no profession open (a gathering profession's page, an alt's recipes): the
	-- game's window opens on the profession it showed. Within the click, which the game asks for.
	if own and own:IsShown() then own:Hide() end
	if line then pcall(C_TradeSkillUI.OpenTradeSkill, line) end
end

local buttons = {}

local function Make(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SIZE, SIZE)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON_SIZE, ICON_SIZE)
	b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.icon:SetTexture(ICON)
	local token = 0
	b:SetScript("OnEnter", function(self)
		Paint(self, true)
		token = token + 1
		local mine = token
		C_Timer.After(TIP_WAIT, function()
			if mine ~= token or not self:IsMouseOver() or not GameTooltip then return end
			local _, words = Target()
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(words, 1, 1, 1)
			if InCombatLockdown() then
				GameTooltip:AddLine(L["Profession windows can be switched once the fight ends."], Ink("OFF"))
			end
			GameTooltip:Show()
		end)
	end)
	b:SetScript("OnLeave", function(self)
		Paint(self, false)
		token = token + 1
		if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", Flip)
	Paint(b, false)
	buttons[#buttons + 1] = b
	return b
end

-- The button left of `close` on `host` (made once per host).
local onHost = setmetatable({}, { __mode = "k" })
local function Place(host, close)
	if type(host) ~= "table" or not host.CreateTexture or type(close) ~= "table" or not close.GetPoint then return nil end
	local b = onHost[host]
	if not b then
		b = Make(host)
		onHost[host] = b
	end
	b:ClearAllPoints()
	b:SetPoint("RIGHT", close, "LEFT", -GAP, 0)
	b:SetFrameLevel(close:GetFrameLevel())
	b:Show()
	-- A DaylightUI window's header tabs run leftward from its X (or from the one icon its header
	-- keeps beside the X: headerRight, headerRoom). Ours takes that place when it's free, so tabs
	-- made later start left of it, and the ones there now (and the title's right end) move over.
	if host.title and host.close == close and (host.headerRight == nil or host.headerRight == b) then
		host.headerRight, host.headerRoom = b, SIZE + GAP
		local tabs = type(host.tabs) == "table" and host.tabs or nil
		local gap = 14
		local room = 40 + host.headerRoom
		if tabs and tabs[#tabs] and tabs[#tabs].SetPoint then
			tabs[#tabs]:SetPoint("RIGHT", b, "LEFT", -gap, 0)
			for _, t in ipairs(tabs) do room = room + (t:GetWidth() or 0) + gap end
		end
		host.title:SetPoint("RIGHT", host, "RIGHT", -room, 0)
		if host.sub and host.sub.SetPoint then host.sub:SetPoint("RIGHT", host, "RIGHT", -room, 0) end
	end
	return b
end

-- On Daylight Recipes' own window (Window.lua calls this once it has its X).
function Swap.OnWindow(win, close)
	return Place(win, close)
end

-- The window that shows the profession while ours isn't in use: DaylightMogul's, DaylightUI's (the
-- one our docked pane hangs on), else the game's own.
local function OtherHost()
	local mogul = _G.DaylightMogulCraft
	if type(mogul) == "table" and mogul.IsShown and mogul:IsShown() and mogul.close then return mogul, mogul.close end
	local pane = ns.Pane and ns.Pane.HostWindow and ns.Pane.HostWindow()
	if type(pane) == "table" and pane.IsShown and pane:IsShown() and pane.close then return pane, pane.close end
	local game = _G.ProfessionsFrame
	if type(game) == "table" and game.IsShown and game:IsShown() then
		local close = game.CloseButton or (game.NineSlice and _G.ProfessionsFrameCloseButton)
		if close then return game, close end
	end
	return nil
end

-- A profession opened in the other window: the button goes on it (a frame later, once that window
-- has shown). Only for your own professions: someone's linked list and an NPC's stay as they are.
local function OnOther()
	-- (Not in a fight: the game's window is a protected panel, nothing of ours is added to it then.)
	if ns.Get("window") == "recipes" or InCombatLockdown() then return end
	local host, close = OtherHost()
	if host then Place(host, close) end
end

Swap.PlaceOther = OnOther

function Swap.Repaint()
	for _, b in ipairs(buttons) do Paint(b, b:IsMouseOver()) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "TRADE_SKILL_SHOW" then
		C_Timer.After(0, OnOther)
		C_Timer.After(0.3, OnOther)
	else
		-- (Grayed in a fight: switching moves the game's window, which a fight forbids.)
		local fight = event == "PLAYER_REGEN_DISABLED"
		for _, b in ipairs(buttons) do
			b:SetEnabled(not fight)
			Paint(b, false)
		end
	end
end)

ns.me.On("StyleChanged", Swap.Repaint)
