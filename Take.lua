-- Daylight Recipes' own profession window in place of the game's (and DaylightUI's).
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

-- Whether Daylight Recipes' window is the one in use. It takes DaylightMogul's place as it takes
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

-- The panel width the game gives the next window it opens beside ours.
local GAP = 20
local function WriteWidth(f, width)
	if type(SetUIPanelAttribute) ~= "function" or InCombatLockdown() then return end
	pcall(SetUIPanelAttribute, f, "width", width)
end

local widthOwed = false -- released in a fight: its width is written back after it
local widthBefore       -- the panel width the window had before we held it (the game's or DaylightUI's)

local function Hold()
	local f = Game()
	if not f or InCombatLockdown() then return false end
	if f:GetParent() ~= veil then
		before = f:GetParent()
		widthOwed = false
		widthBefore = f.GetAttribute and f:GetAttribute("UIPanelLayout-width") or nil
		f:SetParent(veil)
	end
	holding = true
	if ns.Window then WriteWidth(f, math.floor(ns.Window.Width() + GAP + 0.5)) end
	return true
end

-- The game window back where it was (the game's, or DaylightUI's to show again), with the panel
-- width it had. inFight: only the parent (a hidden window, as a fight starts: the width waits).
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
	-- (In a fight the width can't be written: it is once the fight ends.)
	if InCombatLockdown() then
		widthOwed = true
	else
		WriteWidth(f, widthBefore)
		widthBefore = nil
	end
	return true
end
function Take.Release() return Release(false, ns.Get("window") == "game") end

function Take.Holding() return holding end

-- Ours is a bit wider or narrower (the window size changed): the next game window opens beside it.
function Take.Rewidth()
	local f = Game()
	if f and holding and ns.Window then WriteWidth(f, math.floor(ns.Window.Width() + GAP + 0.5)) end
end

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
-- and a fight may have kept it out).
local watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", function(self)
	if not open then self:Hide() return end
	local f = Game()
	if ours and f and not InCombatLockdown() and (f:GetParent() ~= veil or not holding) then Hold() end
	-- (A controller: the held window off the game's list, so its cursor stays in ours. Guide.lua)
	if holding and f and ns.Pad and f:IsShown() then ns.Pad.KeepOff(f) end
end)

-- Between sessions the game's window goes back: on Forever it is the professions book too (K and
-- the micro menu open it with no trade skill), which must show. Put off a frame, so another
-- profession picked on the left (a close and an open at once) keeps it held.
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
		watch:Show()
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
		if widthOwed and not holding then
			widthOwed = false
			local f = Game()
			if f then WriteWidth(f, widthBefore) end
			widthBefore = nil
		end
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
