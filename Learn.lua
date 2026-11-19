-- Recipes your characters can learn, marked at vendors.
-- For a recipe item (a pattern, plans, a formula...): which of your characters it can reach (this
-- one and the alts on this realm and faction, the ones it can be mailed to) have its profession and
-- don't know it yet, and whether their skill is high enough to learn it. This drives:
--   * a small badge on the item at a vendor: in your accent when this character can learn it now,
--     fainter when it's for later (more skill needed) or for an alt. On DaylightUI's vendor page
--     through its API ("shoptile" paint, redone on every fill of the shelf); on the game's own
--     vendor window through a post-hook on its shelf update (nothing of the game's written: our
--     own small frames ride over its item buttons). DaylightMogul's vendor window: from
--     DaylightUI 1.9.4 Mogul hands its tiles to DaylightUI as "shoptile" frames too (DaylightUI's
--     MogulShop, API.md "the vendor's tiles"), so the same paint badges them, and API.RefreshShop
--     refills Mogul's shelf; on an older DaylightUI or Mogul, no badges there (the tooltip still
--     says it all).
--   * the "Can learn" line under "Known by" in item tooltips (Tips.lua).
-- This character's skill is read live from the game; an alt's is what it had when last played.
-- A character whose recipe list was never read (its profession window not opened yet) counts as
-- not knowing it.
local _, ns = ...
if not ns.ok then return end

local API, me = ns.API, ns.me
local Learn = {}
ns.Learn = Learn

-- ---------------------------------------------------------------------------------------------
-- Who can learn it
-- ---------------------------------------------------------------------------------------------

-- This character's professions now: skill line -> skill (cleared when its skills change).
local live
local function LiveSkills()
	if live then return live end
	live = {}
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			local index = list[i]
			if index then
				local ok, _, _, skill, _, _, _, line = pcall(GetProfessionInfo, index)
				if ok and type(line) == "number" and type(skill) == "number" then live[line] = skill end
			end
		end
	end
	return live
end

-- The skill learning a recipe asks for: the first of its skill-up colors in the recipe data.
local function Need(recipe)
	local colors = type(recipe) == "table" and recipe[2]
	local need = type(colors) == "table" and colors[1]
	return type(need) == "number" and need or 0
end

local function Entry(c, line, spell, need, mine)
	local p = type(c.prof) == "table" and c.prof[line]
	local skill = type(p) == "table" and p.skill or nil
	if mine then skill = LiveSkills()[line] or skill end
	if not skill then return nil end
	local known = type(c.known) == "table" and c.known[line]
	return {
		name = c.name or "?", class = c.class, mine = mine,
		knows = type(known) == "table" and known[spell] == true,
		skill = skill, short = skill < need and (need - skill) or 0,
	}
end

-- For a recipe item: { spell, line, need, list = { entry, ... } } (this character first, then alts
-- by name), or nil for an item that teaches no recipe in our data, or one nobody has the
-- profession for.
function Learn.For(itemID)
	local spell = ns.Tips and ns.Tips.Teaches(itemID)
	local recipe = spell and ns.Recipes and ns.Recipes[spell]
	if not recipe then return nil end
	local line, need = recipe[1], Need(recipe)
	local list = {}
	local mine = ns.Store.Char()
	if mine then
		local e = Entry(mine, line, spell, need, true)
		if e then list[#list + 1] = e end
	end
	local alts = {}
	for _, c in pairs(ns.Store.Alts()) do
		local e = Entry(c, line, spell, need, false)
		if e then alts[#alts + 1] = e end
	end
	table.sort(alts, function(a, b) return ns.NameLess(a.name, b.name) end)
	for _, e in ipairs(alts) do list[#list + 1] = e end
	if #list == 0 then return nil end
	return { spell = spell, line = line, need = need, list = list }
end

-- The badge an item gets: "now" (this character can learn it now), "later" (someone without it:
-- this character short of skill, or an alt), or nil.
local function Badge(itemID)
	if type(itemID) ~= "number" then return nil end
	local info = Learn.For(itemID)
	if not info then return nil end
	local later = false
	for _, e in ipairs(info.list) do
		if not e.knows then
			if e.mine and e.short == 0 then return "now" end
			later = true
		end
	end
	return later and "later" or nil
end
Learn.Badge = Badge

-- A name in its class color.
function Learn.ClassName(e)
	local color = e.class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(e.class)
	if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(e.name) end
	return e.name
end

-- ---------------------------------------------------------------------------------------------
-- The badge
-- ---------------------------------------------------------------------------------------------

local SIZE, EDGE = 8, 1

-- A small square in the accent with a dark edge, over the icon's top-right corner.
local function MakeBadge(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(SIZE + EDGE * 2, SIZE + EDGE * 2)
	b.edge = b:CreateTexture(nil, "OVERLAY", nil, 6)
	b.edge:SetAllPoints()
	b.edge:SetColorTexture(0, 0, 0, 0.85)
	b.fill = b:CreateTexture(nil, "OVERLAY", nil, 7)
	b.fill:SetPoint("TOPLEFT", EDGE, -EDGE)
	b.fill:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	b:Hide()
	return b
end

local function ShowBadge(b, kind, icon)
	if not b then return end
	if not kind or not ns.Get("vendorMarks") then
		b:Hide()
		return
	end
	b:ClearAllPoints()
	b:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1)
	local r, g, bl = API.Accent()
	b.fill:SetColorTexture(r, g, bl, 1)
	b:SetAlpha(kind == "now" and 1 or 0.45)
	b:Show()
end

-- DaylightUI's vendor page: a badge on each shop tile, redone on every fill (API's paint).
local tileBadges = setmetatable({}, { __mode = "k" })
local function PaintTile(tile, parts, info)
	local holder = API.Attach and API.Attach(tile)
	if not holder then return end
	local b = tileBadges[holder]
	local kind
	if type(info) == "table" and info.tab == "buy" then kind = Badge(info.id) end
	if not kind and not b then return end
	if not b then
		b = MakeBadge(holder)
		tileBadges[holder] = b
	end
	b:SetFrameLevel(holder:GetFrameLevel() + 2)
	local icon = type(parts) == "table" and parts.icon or (API.GetPart and API.GetPart(tile, "icon"))
	ShowBadge(b, kind, icon or holder)
end

-- The game's own vendor window: our frames over its item buttons, filled after each shelf update.
local gameBadges = {}
local function GameItemID(index)
	if GetMerchantItemID then
		local ok, id = pcall(GetMerchantItemID, index)
		if ok and type(id) == "number" then return id end
	end
	if GetMerchantItemLink then
		local ok, link = pcall(GetMerchantItemLink, index)
		local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then return id end
	end
	return nil
end

local function PaintGame()
	local frame = _G.MerchantFrame
	if type(frame) ~= "table" then return end
	local per = _G.MERCHANT_ITEMS_PER_PAGE or 10
	local page = tonumber(frame.page) or 1
	for i = 1, per do
		local button = _G["MerchantItem" .. i .. "ItemButton"]
		local b = gameBadges[i]
		if type(button) == "table" and button.GetObjectType then
			local index = (page - 1) * per + i
			local kind = button:IsShown() and Badge(GameItemID(index)) or nil
			if kind and not b then
				b = MakeBadge(frame)
				gameBadges[i] = b
			end
			if b then
				b:SetFrameLevel(button:GetFrameLevel() + 5)
				ShowBadge(b, kind, button)
			end
		elseif b then
			b:Hide()
		end
	end
end

local function HideGame()
	for _, b in pairs(gameBadges) do b:Hide() end
end

-- Every badge again (a setting, a recipe learned, a skill-up), while a vendor is open.
local atVendor = false
function Learn.Refresh()
	if not atVendor then return end
	if API.RefreshShop then pcall(API.RefreshShop) end
	local frame = _G.MerchantFrame
	if type(frame) == "table" and frame:IsShown() and (frame.selectedTab or 1) == 1 then PaintGame() else HideGame() end
end

-- ---------------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------------

local hooked = false
local function HookGame()
	if hooked then return end
	if type(_G.MerchantFrame_UpdateMerchantInfo) == "function" then
		hooked = true
		hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() pcall(PaintGame) end)
		if type(_G.MerchantFrame_UpdateBuybackInfo) == "function" then
			hooksecurefunc("MerchantFrame_UpdateBuybackInfo", HideGame)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("NEW_RECIPE_LEARNED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event, spell)
	if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
		atVendor = event == "MERCHANT_SHOW"
		if not atVendor then HideGame() end
		return
	elseif event == "SKILL_LINES_CHANGED" then
		live = nil
	elseif type(spell) == "number" then
		-- Learned (from the vendor, a trainer or the book itself): this character knows it now,
		-- before its profession window is next read.
		local recipe = ns.Recipes and ns.Recipes[spell]
		local c = recipe and ns.Store.Char()
		if c then
			c.known = type(c.known) == "table" and c.known or {}
			local set = c.known[recipe[1]] or {}
			c.known[recipe[1]] = set
			set[spell] = true
			ns.Store.version = ns.Store.version + 1
		end
	end
	Learn.Refresh()
end)

me.On("Login", function()
	if type(me.Paint) == "function" then pcall(me.Paint, "shoptile", PaintTile) end
	HookGame()
end)
