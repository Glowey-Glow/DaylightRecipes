-- Daylight Recipes: a DaylightUI plugin.
-- A pane on the right of the profession window: DaylightUI's own (docked through
-- me.AttachCraftPane), or DaylightMogul's while Mogul runs the professions (then DaylightUI
-- builds no window, so the pane hangs off Mogul's). Two pages:
--   Recipe:  the picked recipe's skill-up chance, what its materials cost (each one priced from
--            the Auction House through DaylightMogul, or a vendor), what it sells and vendors for,
--            what it disenchants into, and the profit each way.
--   Missing: every recipe of the open profession you don't know yet, with where it's taught,
--            sold, dropped or given, and a waypoint to it.
-- The recipe, source and disenchant tables in Data/ are ForeverRecipes' (GPL-3.0, by Ismail),
-- built from ForeverDB.app and CMaNGOS Classic DB, unchanged. This plugin is GPL-3.0 too
-- (LICENSE.md). Built on DaylightUI.API only.

local ADDON, ns = ...

local DUI = _G.DaylightUI
local API = DUI and DUI.API
if not API or API.major ~= 1 then return end

ns.API = API
local me = API.For(ADDON)
ns.me = me

-- ---------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------

local DEFAULTS = {
	paneWidth = 300,
	useAH = true,
	priceSource = "market",
	talents = true,
	learnableOnly = false,
	tomtom = true,
}
ns.DEFAULTS = DEFAULTS

function ns.Get(path)
	local ok, value = pcall(API.GetSetting, ADDON, path)
	if ok and value ~= nil then return value end
	return DEFAULTS[path]
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDaylight Recipes|r: " .. msg)
end

-- ---------------------------------------------------------------------------------------------
-- The open profession and the picked recipe
-- ---------------------------------------------------------------------------------------------

-- The professions the data covers, by their classic skill line.
ns.LINES = { [164] = true, [165] = true, [171] = true, [185] = true, [186] = true, [197] = true,
	[202] = true, [333] = true, [129] = true, [40] = true }

-- mode: "dui" (DaylightUI's window) or "mogul" (DaylightMogul's), nil while neither is open.
local S = { mode = nil, line = nil, name = nil, skill = 0, max = 0, linked = false, recipe = nil }
ns.state = S

function ns.Faction()
	return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end

local function Ask(name, ...)
	local ts = TS()
	local fn = ts and ts[name]
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
end
ns.Ask = Ask

local LINE_KEYS = { "professionID", "parentProfessionID", "skillLineID" }

-- Reads the open profession. True when anything the pane shows changed (another profession, the
-- skill, its cap, someone else's recipes): the game's list updates on every bag change while the
-- window is open, and most of those change none of it.
function ns.ReadProfession()
	local info = Ask("GetBaseProfessionInfo")
	local line
	if type(info) == "table" then
		for _, key in ipairs(LINE_KEYS) do
			local v = info[key]
			if type(v) == "number" and ns.LINES[v] then line = v break end
		end
	end
	local name = type(info) == "table" and info.professionName or nil
	local skill = type(info) == "table" and tonumber(info.skillLevel) or 0
	local max = type(info) == "table" and tonumber(info.maxSkillLevel) or 0
	local linked = Ask("IsTradeSkillLinked") == true or Ask("IsTradeSkillGuild") == true
	local changed = line ~= S.line or name ~= S.name or skill ~= S.skill or max ~= S.max or linked ~= S.linked
	-- Another profession, or someone else's recipes: the known recipes are read again.
	if line ~= S.line or linked ~= S.linked then
		S.recipe = line ~= S.line and nil or S.recipe
		if ns.Where then ns.Where.ForgetKnown() end
	end
	S.line, S.name, S.skill, S.max, S.linked = line, name, skill, max, linked
	return changed
end

-- What changed is drawn once, on the next frame.
local queued = false
function ns.Changed()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		if ns.Pane then ns.Pane.Render() end
	end)
end

function ns.MogulOwns()
	local M = _G.DaylightMogul
	local craft = type(M) == "table" and type(M.API) == "table" and M.API.Craft
	if type(craft) ~= "table" or type(craft.Owns) ~= "function" then return false end
	local ok, owns = pcall(craft.Owns)
	return ok and owns == true
end

-- DaylightUI's window.
me.On("CraftShown", function()
	S.mode = "dui"
	ns.ReadProfession()
	ns.Changed()
end)
me.On("CraftProfessionChanged", function()
	S.mode = "dui"
	ns.ReadProfession()
	ns.Changed()
end)
me.On("CraftRecipeSelected", function(recipeID)
	if type(recipeID) ~= "number" then return end
	S.mode = "dui"
	S.recipe = recipeID
	ns.Changed()
end)

-- DaylightMogul's window. It never says which recipe is picked, but its recipe page is the
-- only thing that asks the game for a recipe's description, and it asks for the picked one
-- each time it fills: that call, heard after it runs, is the pick. Nothing of Mogul's or the
-- game's is changed by listening.
local function MogulShown()
	local win = _G.DaylightMogulCraft
	return type(win) == "table" and win.IsShown and win:IsShown()
end

-- Mogul fills its recipe page as it opens, a frame before we know it's Mogul's window that
-- opened: the last one asked for is kept for then.
local lastAsked
if TS() and type(C_TradeSkillUI.GetRecipeDescription) == "function" then
	hooksecurefunc(C_TradeSkillUI, "GetRecipeDescription", function(recipeID)
		if type(recipeID) ~= "number" then return end
		lastAsked = recipeID
		if S.mode ~= "mogul" or recipeID == S.recipe then return end
		S.recipe = recipeID
		ns.Changed()
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("PLAYER_LOGIN")

local function PaneShown()
	return ns.Pane and ns.Pane.Shown()
end

events:SetScript("OnEvent", function(_, event, itemID)
	if event == "PLAYER_LOGIN" then
		local M = _G.DaylightMogul
		if type(M) == "table" and type(M.API) == "table" and type(M.API.On) == "function" then
			pcall(M.API.On, "PricesChanged", function()
				if ns.Calc then ns.Calc.Forget() end
				if PaneShown() then ns.Changed() end
			end)
		end
		return
	end
	if event == "TRADE_SKILL_SHOW" then
		if not ns.MogulOwns() then return end
		-- Mogul shows its window as the game opens the trade skill: look for it a frame later.
		C_Timer.After(0, function()
			if not MogulShown() then return end
			S.mode = "mogul"
			ns.ReadProfession()
			if not S.recipe then S.recipe = lastAsked end
			if ns.Pane then ns.Pane.AttachMogul(_G.DaylightMogulCraft) end
			ns.Changed()
		end)
	elseif event == "TRADE_SKILL_CLOSE" then
		if S.mode == "mogul" then S.mode = nil end
	elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "SKILL_LINES_CHANGED" then
		if not S.mode then return end
		local changed = ns.ReadProfession()
		-- Drawn again only when something shown changed: the skill or profession, or (with the
		-- missing list up) a recipe learned.
		if ns.Where then
			ns.Where.MarkStale()
			if ns.Pane and ns.Pane.ShowingMissing() and ns.Where.Refresh() then changed = true end
		end
		if changed and PaneShown() then ns.Changed() end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- Any addon's item asks bring this; only one the recipe page is waiting on redraws it.
		if PaneShown() and ns.Pane and ns.Pane.Waiting(itemID) then ns.Changed() end
	elseif event == "TRAIT_CONFIG_UPDATED" or event == "UPDATE_FACTION" then
		if ns.Calc then ns.Calc.Forget() end
		if PaneShown() then ns.Changed() end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- DaylightUI: plugin, options page
-- ---------------------------------------------------------------------------------------------

local SOURCES = {
	market = "Market value",
	minbuyout = "Lowest buyout",
	daily = "Today's average",
}

local function NoAH(get) return get("useAH") == false end

local pages = {
	{ id = "recipes", label = "Recipes",
	  desc = "A pane on the right of the profession window (DaylightUI's, or DaylightMogul's while it runs your professions). Recipe and source data from ForeverRecipes; you can turn ForeverRecipes itself off.",
	  groups = {
		{ label = "Pane", items = {
			{ type = "slider", key = "paneWidth", label = "Pane width", min = 260, max = 400, step = 10,
			  desc = "How wide the pane beside the profession window is." },
		} },
		{ label = "Prices", items = {
			{ type = "toggle", key = "useAH", label = "Use Auction House prices",
			  desc = "Materials, sales and disenchants are priced from DaylightMogul's Auction House data when it's loaded. Off, or without DaylightMogul, only vendor prices are used." },
			{ type = "dropdown", key = "priceSource", label = "Auction House price", values = SOURCES,
			  desc = "Which of DaylightMogul's prices to use.", disabled = NoAH },
			{ type = "toggle", key = "talents", label = "Count my profession talents",
			  desc = "Overtime raises the skill-up chance and Bartering lowers vendor prices, by the ranks you've bought." },
		} },
		{ label = "Missing recipes", items = {
			{ type = "toggle", key = "learnableOnly", label = "Only ones my skill allows",
			  desc = "List only the recipes your skill is high enough to learn now." },
			{ type = "toggle", key = "tomtom", label = "Waypoints with TomTom",
			  desc = "Clicking a place sets a TomTom waypoint when TomTom is installed. Off, or without it, the game's own map pin is used." },
		} },
	  } },
}

pcall(function()
	DUI:RegisterPlugin(ADDON, {
		needs = { 1, 2 },
		short = "Recipes",
		color = { 0.95, 0.75, 0.35 },
		blurb = "Costs, skill-up chances, disenchants and missing recipes beside the profession window.",
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = "Recipes", defaults = DEFAULTS, options = { pages = pages } })
end)

me.On("SettingChanged", function(scope, path)
	if scope ~= ADDON then return end
	if path == "paneWidth" then
		if ns.Pane then ns.Pane.Resize() end
		return
	end
	if ns.Calc then ns.Calc.Forget() end
	if PaneShown() then ns.Changed() end
end)

me.On("StyleChanged", function()
	if ns.Pane then ns.Pane.Restyle() end
end)

ns.ok = true
