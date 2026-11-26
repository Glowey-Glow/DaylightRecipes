-- Glowey's Recipes' own profession window in place of the game's (and DaylightUI's).
-- The game's window (ProfessionsFrame) keeps running the trade skill: every way of opening and
-- closing a profession still goes through the game's own code. While ours is in use the game's is
-- held under a "veil" of ours: shown, see-through and clipped to a pixel off screen, so nothing of
-- it is seen or clicked, and nothing of the game's is hooked or replaced.
-- DaylightUI (and DaylightMogul) park the same window under one of their own for their profession
-- windows. They read the window being moved under another parent as "taken by another addon",
-- close their own and leave the trade skill alone (Windows\Follow.lua, "Away"), so none fight.
-- Held only out of combat (the game's panel layout is protected in a fight): a profession opened in
-- a fight shows the game's own window until the fight ends.
-- Left to the game: the whole guild's crafters and an NPC's crafting (the game's window has their
-- own controls). Someone's linked recipes and a guild member's show in ours, to look at only.
local _, ns = ...
if not ns.ok then return end

local Take = {}
ns.Take = Take

local veil = CreateFrame("Frame", nil, UIParent)
veil:SetSize(1, 1)
veil:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -64, -64)
veil:SetAlpha(0)
veil:SetClipsChildren(true)
veil:EnableMouse(false)

local holding = false
local before          -- the game window's parent before we held it (UIParent, or DaylightUI's veil)
local open = false    -- a trade skill is open (TRADE_SKILL_SHOW until TRADE_SKILL_CLOSE)
local ours = false    -- this session shows in our window

local function Game()
	local f = _G.ProfessionsFrame
	return type(f) == "table" and f.SetParent and f or nil
end

local function TS(name, ...)
	local fn = C_TradeSkillUI and C_TradeSkillUI[name]
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	return ok and v or nil
end

-- Whether Glowey's Recipes' window is the one in use. It takes DaylightMogul's place as it takes
-- DaylightUI's: Mogul parks the game's window the same way and backs off the same way (its own
-- Look\Windows\Follow.lua, "Away"); Mogul's prices are still the ones used.
function Take.Wanted()
	return ns.Get("window") == "recipes"
end

-- Whether the open trade skill belongs in our window: your own, someone's linked recipes, a guild
-- member's. Not the whole guild's list, not an NPC's crafting.
function Take.Ours()
	if TS("IsNPCCrafting") == true then return false end
	if TS("IsTradeSkillGuild") == true and TS("IsTradeSkillGuildMember") ~= true then return false end
	return true
end

-- The game's panel layout is never written to (no SetUIPanelAttribute): a layout attribute keeps
-- the taint of the addon that wrote it, the game's next ShowUIPanel reads it back and runs
-- tainted, and in a fight the game is then blocked from what it does next ("action blocked" on
-- opening a game window). The game sets this window's layout width itself for each page, so the
-- next game window opens beside the game's width, as it does under DaylightUI's own profession
-- window (which stopped writing it in 1.9.6).

local function Hold()
	local f = Game()
	if not f or InCombatLockdown() then return false end
	if f:GetParent() ~= veil then
		before = f:GetParent()
		f:SetParent(veil)
	end
	holding = true
	return true
end

-- The game window back where it was (the game's, or DaylightUI's to show again). inFight: a hidden
-- window, as a fight starts (its parent can still be set then).
-- toGame: to the screen itself, never back under DaylightUI's (or DaylightMogul's) holder: the
-- game's own window is the one wanted ("The game's window", the swap button). They read it moved
-- under another parent as taken (their "Away" rule) and step aside, as they do for ours.
local function Release(inFight, toGame)
	local f = Game()
	if not f or not holding then return false end
	if not inFight and InCombatLockdown() then return false end
	holding = false
	if f:GetParent() == veil then f:SetParent(toGame and UIParent or before or UIParent) end
	before = nil
	-- (A controller: back on the game's list, if it's showing on the screen itself.)
	if ns.Pad and f:GetParent() == UIParent then ns.Pad.Remember(f) end
	return true
end
function Take.Release() return Release(false, ns.Get("window") == "game") end

function Take.Holding() return holding end

-- Closes the trade skill the way the game does (our window's X): the game's window hides and its
-- own OnHide ends the session. In a fight the panel can't be hidden: the session is ended directly.
function Take.Close()
	local f = Game()
	if f and f:IsShown() and not InCombatLockdown() and type(HideUIPanel) == "function" then
		HideUIPanel(f)
	else
		TS("CloseTradeSkill")
	end
end

-- "The game's window": a profession opened while DaylightUI's own window is still running this
-- session (it is switched off at the next login) is parked by DaylightUI under its holder. Handed
-- to the screen a frame later, so DaylightUI steps aside (its "Away" rule) and the game's own
-- window shows. Out of combat only (the panel's parent can't be set in a fight).
function Take.ToScreen()
	if ns.Get("window") ~= "game" then return end
	C_Timer.After(0, function()
		local f = Game()
		if not f or InCombatLockdown() or ns.Get("window") ~= "game" then return end
		if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
	end)
end

-- A session that belongs in our window, held (or to be held once the fight ends).
local function Start()
	ours = Take.Wanted() and Take.Ours()
	if not ours then
		-- (Ours was held for the last profession: the game's or DaylightUI's window shows this one.)
		Take.Release()
		if ns.Window then ns.Window.SessionEnded() end
		Take.ToScreen()
		return
	end
	-- (In a fight the game's own window shows it: ours takes over once the fight ends.)
	if Hold() and ns.Window then ns.Window.SessionStarted() end
end

-- While a session is open: keep the game's window held (DaylightUI parks it again when it loads,
-- and a fight may have kept it out), and off the controller's list. No polling: what moves it is
-- a call that is hooked. Its SetParent (DaylightUI or DaylightMogul parking it again), its OnShow,
-- and the game listing a window for the controller (Blizzard_GamepadSharedUtility-- FrameControlsManager.lua:192-197, :384: every ShowUIPanel, and every page that re-lists it,
-- goes through FrameControlsManager:FrameShown). The fight's end is PLAYER_REGEN_ENABLED below.
local function Keep()
	if not open then return end
	local f = Game()
	if ours and f and not InCombatLockdown() and (f:GetParent() ~= veil or not holding) then Hold() end
	-- (A controller: the held window off the game's list, so its cursor stays in ours. Guide.lua)
	if holding and f and ns.Pad and f:IsShown() then ns.Pad.KeepOff(f) end
end

local keepSoon = false
local function KeepSoon()
	if keepSoon or not open then return end
	keepSoon = true
	C_Timer.After(0, function()
		keepSoon = false
		Keep()
	end)
end

local hookedGame, hookedPad
local function HookWatch()
	local f = Game()
	if f and hookedGame ~= f then
		hookedGame = f
		-- (A frame later: the one moving it finishes first, as it would have with a look each frame.)
		hooksecurefunc(f, "SetParent", KeepSoon)
		f:HookScript("OnShow", KeepSoon)
	end
	local G = rawget(_G, "GamepadMode")
	local m = type(G) == "table" and G.FrameControlsManager or nil
	if not hookedPad and type(m) == "table" and type(m.FrameShown) == "function" then
		hookedPad = true
		-- (Any window listed: the held one, or ours, without which it can't be taken off.)
		hooksecurefunc(m, "FrameShown", function()
			-- (Caught: it runs inside the game's ShowUIPanel for every window.)
			if open and holding then pcall(Keep) end
		end)
	end
end

-- Between sessions the game's window goes back: on Forever it is the professions book too (K and
-- the micro menu open it with no trade skill), which must show. Put off a frame, so another
-- profession picked in the window's menu (a close and an open at once) keeps it held.
local function ReleaseAfter()
	C_Timer.After(0, function()
		local f = Game()
		if open or not f or f:IsShown() then return end
		Release(false, ns.Get("window") == "game")
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "TRADE_SKILL_SHOW" then
		open = true
		Start()
		HookWatch()
		Keep()
		-- (The game's window can load with this very event: looked at once more a frame later.)
		C_Timer.After(0, function()
			HookWatch()
			Keep()
		end)
	elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
		-- (Another profession, or a link opened with the window up: whose list it is may change.)
		if open then Start() end
	elseif event == "TRADE_SKILL_CLOSE" then
		open, ours = false, false
		if ns.Window then ns.Window.SessionEnded() end
		ReleaseAfter()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- A fight starts: a held window that isn't showing goes back now, so anything opened in the
		-- fight (a profession, the book, an NPC's crafting) shows as the game's own. (The lockdown
		-- may already be on here: a hidden window's parent can still be set.)
		local f = Game()
		if holding and f and not f:IsShown() then Release(true, ns.Get("window") == "game") end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if open and ours and Hold() and ns.Window then ns.Window.SessionStarted() end
	end
end)

function Take.Open() return open end
function Take.OursNow() return open and ours end

-- The choice changed (or DaylightMogul came or went): an open session moves to the window now in
-- use; the game's window is handed back when ours isn't wanted.
function Take.Recheck()
	if not Take.Wanted() then
		Take.Release()
		-- (Not ours any more before our window closes: its closing mustn't end the trade skill.)
		local was = ours
		ours = false
		if was and ns.Window then ns.Window.SessionEnded() end
		return
	end
	if open then Start() end
end
