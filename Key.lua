-- The Professions key (whatever is bound to TOGGLEPROFESSIONBOOK, K by default) opens Daylight
-- Recipes' window, the way /recipes does: the profession you had open last (else your first with
-- recipes), or the window with your professions when there's none; pressed again, it closes it.
--
-- Why it's needed: with our window picked, Daylight UI's own profession window is switched off,
-- and with it Daylight UI's hold on that key, so the key fell back to the game's professions book.
-- Ours takes the key only while our window is the one in use and Daylight UI's own isn't
-- (DaylightUI.craftOwnWindow), so the two never both hold it. "The Game's Window" or "Docked
-- Pane" picked: the key is the game's (or Daylight UI's) again.
--
-- How: an override binding on the key's current keys (never the player's saved bindings; gone on
-- a reload or when it no longer applies) clicks a plain button of ours, and its click runs
-- Window.Toggle. A key press counts as the player's own action, so the game lets it open a trade
-- skill, as it does for /recipes. Bindings are changed out of a fight only; one changed in a
-- fight waits for its end. Keys are read again when the player rebinds (UPDATE_BINDINGS).
local ADDON, ns = ...
if not ns.ok then return end

local Key = {}
ns.Key = Key

local BINDING = "TOGGLEPROFESSIONBOOK"
local NAME = "DaylightRecipesProfessionKey"

local button, owner
local boundKeys = nil   -- the keys bound now, as one string ("" = none)
local waiting = false

local function KeysNow()
	if type(GetBindingKey) ~= "function" then return "" end
	local out = {}
	for _, key in ipairs({ GetBindingKey(BINDING) }) do
		if type(key) == "string" and key ~= "" then out[#out + 1] = key end
	end
	return table.concat(out, " ")
end

-- Whether the key should open our window now.
local function Wanted()
	if not (ns.Get and ns.Get("window") == "recipes") then return false end
	local D = _G.DaylightUI
	if type(D) == "table" and D.craftOwnWindow == true then return false end   -- Daylight UI's holds it
	return ns.Window ~= nil and type(ns.Window.Toggle) == "function"
end

local function Make()
	button = CreateFrame("Button", NAME, UIParent)
	button:Hide()
	button:RegisterForClicks("AnyDown")
	button:SetScript("OnClick", function()
		if ns.Window and type(ns.Window.Toggle) == "function" then ns.Window.Toggle() end
	end)
	owner = CreateFrame("Frame")
end

function Key.Apply()
	if InCombatLockdown() then
		if not waiting then
			waiting = true
			local f = CreateFrame("Frame")
			f:RegisterEvent("PLAYER_REGEN_ENABLED")
			f:SetScript("OnEvent", function(self)
				self:UnregisterAllEvents()
				waiting = false
				Key.Apply()
			end)
		end
		return
	end
	local keys = Wanted() and KeysNow() or ""
	if keys == boundKeys then return end
	if not button then Make() end
	ClearOverrideBindings(owner)
	boundKeys = keys
	for key in keys:gmatch("%S+") do
		SetOverrideBindingClick(owner, false, key, NAME, "LeftButton")
	end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS" }) do events:RegisterEvent(e) end
-- (A frame later: Daylight UI's own key, when its window is on, is set up by then.)
events:SetScript("OnEvent", function() C_Timer.After(0, Key.Apply) end)

-- The profession window picked in our options changes who holds the key.
ns.me.On("SettingChanged", function(scope, path)
	if scope == ADDON and (path == "window" or path == nil) then C_Timer.After(0, Key.Apply) end
end)
