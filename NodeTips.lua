-- Mastercraft's gathering node tooltips (its map pins: "Copper Vein", "Requires 1 (you have 71)")
-- say how far the next skill color is as "Turns grey at +30 skill". Read with our words instead:
-- "Turns gray in 30 more skill", the color's name in its own color (and "Gatherable in 5 more
-- skill" for a node you can't gather yet). Mastercraft is another author's addon and its code is
-- never touched: right after the game's tooltip shows, its one line is reworded in place. Only
-- while Mastercraft is loaded; its English lines only (it writes these in English on every client).
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

local function Look(tip)
	if not tip.NumLines then return end
	local lines = tip:NumLines() or 0
	if lines < 2 or lines > 30 then return end
	local name = tip:GetName()
	if not name then return end
	local changed = false
	for i = 2, lines do
		local fs = _G[name .. "TextLeft" .. i]
		local text = fs and fs:GetText()
		if type(text) == "string" and not (secret and secret(text)) and text:find("skill$") then
			local new = Reword(text)
			if new then
				fs:SetText(new)
				changed = true
			end
		end
	end
	-- (Wider if the new words need it. Never Show again from here: that could taint the game's
	-- tooltip.)
	if changed then
		local need = 0
		for i = 2, lines do
			local fs = _G[name .. "TextLeft" .. i]
			local right = _G[name .. "TextRight" .. i]
			local w = fs and fs:IsShown() and fs:GetStringWidth() or 0
			if right and right:IsShown() then w = w + (right:GetStringWidth() or 0) + 20 end
			if type(w) == "number" and w > need then need = w end
		end
		if need + 22 > (tip:GetWidth() or 0) then tip:SetWidth(need + 22) end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Mastercraft")) then return end
	hooksecurefunc(GameTooltip, "Show", function(tip) pcall(Look, tip) end)
end)
