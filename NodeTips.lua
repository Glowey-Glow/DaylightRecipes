-- Mastercraft's gathering node tooltips (its map pins: "Copper Vein", "Requires 1 (you have 71)",
-- and the game's own tooltip of a vein or herb in the world, which it adds the same lines to)
-- say how far the next skill color is as "Turns grey at +30 skill". Read with our words instead:
-- "Turns gray in 30 more skill", the color's name in its own color (and "Gatherable in 5 more
-- skill" for a node you can't gather yet). Mastercraft is another author's addon and its code is
-- never touched. Only while Mastercraft is loaded, and only its English lines (with another
-- language picked in Mastercraft the line is in that language and stays as it is).
--
-- The line is reworded the moment it is added, not when the tooltip shows. Mastercraft adds it
-- with GameTooltip:AddLine(text, r, g, b), called as a method of the game's tooltip each time
-- (read in Mastercraft 2.0.7: Nodes.lua:681 calls its stand-in for the tooltip, whose AddLine
-- is Locale.lua:530-534 and :551, "tooltip:AddLine(t, ...)" on the real GameTooltip), and shows
-- the tooltip afterward (Nodes.lua:703 for a map pin, :808 for a node in the world). So a
-- post-hook on GameTooltip's AddLine sees it, and the tooltip then lays itself out with the new
-- words. This is what DaylightUI 2.0's Rich tooltip look needs: its card reads the tooltip's
-- lines when the tooltip shows (DaylightUI_Tooltip\Tooltip.lua:153 > Rich\Rich.lua:128-134 >
-- Rich\Read.lua:45-74) and is built again only when lines come or go (Rich.lua:164-165), so
-- words changed after the show, as before 2.5.3, never reached the card. The same hook serves
-- the Simple look and DaylightUI 1.9.x (whose tooltip is the game's own, laid out at its show):
-- no version is asked.
-- luacheck: read globals C_AddOns GameTooltip hooksecurefunc
local _, ns = ...
local L = ns.L

local COLORS = {
	yellow = { "ffffff00", L["yellow"] },
	green = { "ff40c040", L["green"] },
	grey = { "ff808080", L["gray"] },
	gray = { "ff808080", L["gray"] },
}

local secret = _G.issecretvalue

local function Reword(text)
	local color, n = text:match("^Turns (%a+) at %+(%d+) skill$")
	if color and COLORS[color] then
		local c = COLORS[color]
		return string.format(L["Turns %s in %d more skill"], "|c" .. c[1] .. c[2] .. "|r", tonumber(n))
	end
	n = text:match("^Gatherable at %+(%d+) skill$")
	if n then return string.format(L["Gatherable in %d more skill"], tonumber(n)) end
end

-- The line just added (the tooltip's last one), reworded when it holds exactly the words passed in.
local function Fix(tip, text, new)
	local name = tip.GetName and tip:GetName()
	local lines = tip.NumLines and tip:NumLines()
	if not name or (secret and secret(lines)) or type(lines) ~= "number" or lines < 2 then return end
	local fs = _G[name .. "TextLeft" .. lines]
	local now = fs and fs.GetText and fs:GetText()
	if (secret and secret(now)) or now ~= text then return end
	fs:SetText(new)
end

-- After every GameTooltip:AddLine, anyone's: nearly all are out at the first tests. A line the
-- game keeps secret (in a fight) is never read.
local function Added(tip, text)
	if secret and secret(text) then return end
	if type(text) ~= "string" or not text:find("skill$") then return end
	local new = Reword(text)
	if new then pcall(Fix, tip, text, new) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Mastercraft")) then return end
	hooksecurefunc(GameTooltip, "AddLine", Added)
end)
