-- Daylight Recipes: a DaylightUI plugin.
-- A profession window of its own in place of the game's and DaylightUI's (Window.lua, Take.lua):
-- your professions and alts on the left; Recipes, Plan, Materials and Missing tabs. Or, by choice
-- (and always while DaylightMogul runs the professions), a pane on the right of the profession
-- window: DaylightUI's own (docked through me.AttachCraftPane), or DaylightMogul's. Its pages:
--   Recipe:  the picked recipe's skill-up chance, what its materials cost (each one priced from
--            the Auction House through DaylightMogul, or a vendor), what it sells and vendors for,
--            what it disenchants into, and the profit each way.
--   Missing: every recipe of the open profession you don't know yet, with where it's taught,
--            sold, dropped or given, and a waypoint to it.
-- The recipe, source and disenchant tables in Data/ are ForeverRecipes' (GPL-3.0, by Ismail),
-- built from ForeverDB.app and CMaNGOS Classic DB, unchanged; Data/Polestar.lua is generated from
-- Polestar's data (GPL-3.0) by Tools/polestar.py. This plugin is GPL-3.0 too
-- (LICENSE.md). Built on DaylightUI.API only.

local ADDON, ns = ...
local L = ns.L

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
	window = "recipes",
	winScale = 1,
	paneWidth = 300,
	useAH = true,
	priceSource = "market",
	talents = true,
	learnableOnly = false,
	tomtom = true,
	tooltips = true,
	reminders = true,
	marks = true,
	guideGlow = true,
	vendorMarks = true,
	mastercraftTips = true,
	duiOpacity = true,
	opacity = 0.85,
}
ns.DEFAULTS = DEFAULTS

function ns.Get(path)
	local ok, value = pcall(API.GetSetting, ADDON, path)
	if ok and value ~= nil then return value end
	return DEFAULTS[path]
end

-- ---------------------------------------------------------------------------------------------
-- Window opacity
-- ---------------------------------------------------------------------------------------------
-- Every window and panel of ours is dressed through here: DaylightUI's window shell, its
-- background at DaylightUI's window opacity (opts.window), or at the player's own (opts.bgAlpha)
-- with "Use DaylightUI's opacity" off. Each one is kept with the look it asked for, so a change
-- of either dresses them all again.

local skinned = setmetatable({}, { __mode = "k" })

function ns.SkinWindow(frame, extra)
	if not frame then return end
	skinned[frame] = extra or false
	local opts = { window = true }
	if extra then for k, v in pairs(extra) do opts[k] = v end end
	if ns.Get("duiOpacity") == false and not opts.noBackground then opts.bgAlpha = ns.Get("opacity") end
	API.Skin(frame, opts)
end

function ns.ReskinWindows()
	for frame, extra in pairs(skinned) do ns.SkinWindow(frame, extra or nil) end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDaylight Recipes|r: " .. msg)
end

-- ---------------------------------------------------------------------------------------------
-- Names in the client's language
-- ---------------------------------------------------------------------------------------------
-- The data's names (ns.RecipeNames, ns.ItemNames) are English. Whatever is shown or searched takes
-- the game's own name instead, which is in the client's language, and the English one only when
-- the game doesn't have it (a spell it doesn't know, an item not cached yet). Matching data to data
-- (the route's left-out recipes) keeps the English names.

-- A recipe's (or any spell's) name in the client's language.
function ns.SpellName(spell)
	if not spell then return nil end
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, spell)
		if ok then name = n end
	elseif GetSpellInfo then
		name = GetSpellInfo(spell)
	end
	if type(name) == "string" and name ~= "" then return name end
	return ns.RecipeNames and ns.RecipeNames[spell] or nil
end

-- An item's name in the client's language (the English one while it isn't cached yet).
function ns.ItemNameOf(itemID)
	if not itemID then return nil end
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, n = pcall(C_Item.GetItemNameByID, itemID)
		if ok then name = n end
	end
	if not name and GetItemInfo then name = GetItemInfo(itemID) end
	if type(name) == "string" and name ~= "" then return name end
	return ns.ItemNames and ns.ItemNames[itemID] or nil
end

-- Lower case for searches. string.lower only folds A to Z: the capitals of German, French, Spanish
-- (Latin-1 and Latin Extended-A) and Russian (Cyrillic) are two bytes in UTF-8, folded here from a
-- table made once, so "Ä" finds "ä" and "Б" finds "б". Korean and Chinese have no case.
local FOLD = {}
do
	local function utf8(cp) return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
	local function pair(upper, lower) FOLD[utf8(upper)] = utf8(lower) end
	for cp = 0xC0, 0xDE do
		if cp ~= 0xD7 then pair(cp, cp + 0x20) end          -- À to Þ (not ×)
	end
	for cp = 0x100, 0x137, 2 do                            -- Ā to ķ: capital, then small
		if cp ~= 0x130 then pair(cp, cp + 1) end           -- (not Turkish İ: its small one isn't ı)
	end
	for cp = 0x139, 0x148, 2 do pair(cp, cp + 1) end       -- Ĺ to ň
	for cp = 0x14A, 0x177, 2 do pair(cp, cp + 1) end       -- Ŋ to ŷ
	pair(0x178, 0xFF)                                      -- Ÿ to ÿ
	for cp = 0x179, 0x17E, 2 do pair(cp, cp + 1) end       -- Ź to ž
	for cp = 0x400, 0x40F do pair(cp, cp + 0x50) end       -- Ѐ to Џ (Ё among them)
	for cp = 0x410, 0x42F do pair(cp, cp + 0x20) end       -- А to Я
end

function ns.Fold(text)
	if type(text) ~= "string" then return "" end
	text = text:lower()
	-- (Only text with a two-byte letter from those blocks is gone over again.)
	if text:find("[\195-\209]") then text = (text:gsub("[\195-\209][\128-\191]", FOLD)) end
	return text
end

-- Names in alphabetical order the client's way (accents next to their letter, not after Z), where
-- the game offers it; byte order otherwise.
local cmp = type(strcmputf8i) == "function" and strcmputf8i or nil
function ns.NameLess(a, b)
	if cmp then
		local c = cmp(a, b)
		if c ~= 0 then return c < 0 end
	end
	return a < b
end

-- ---------------------------------------------------------------------------------------------
-- The open profession and the picked recipe
-- ---------------------------------------------------------------------------------------------

-- The professions the data covers, by their classic skill line.
ns.LINES = { [164] = true, [165] = true, [171] = true, [185] = true, [186] = true, [197] = true,
	[202] = true, [333] = true, [129] = true, [40] = true }

-- The data's skill line for a profession the game gives by its line and name: the line itself when
-- the data covers it, else the data's profession of that name (a client numbering a line its own
-- way). Mining's trade skill may go by Smelting, its crafting spell. Nil for a profession the data
-- has no recipes for (Herbalism, Skinning, Fishing).
local SMELTING = 2656
function ns.DataLine(line, name)
	if type(line) == "number" and ns.LINES[line] then return line end
	if type(name) ~= "string" or name == "" or not ns.Tips then return nil end
	local folded = ns.Fold(name)
	for l in pairs(ns.LINES) do
		if ns.Fold(ns.Tips.LineName(l)) == folded then return l end
	end
	if ns.Fold(ns.SpellName(SMELTING) or "") == folded then return 186 end
	return nil
end

-- mode: "win" (our own window), "dui" (DaylightUI's window) or "mogul" (DaylightMogul's), nil while
-- none is open.
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
	-- (No line the data knows: matched by the profession's name instead.)
	if not line and type(info) == "table" and type(name) == "string" then line = ns.DataLine(nil, name) end
	local skill = type(info) == "table" and tonumber(info.skillLevel) or 0
	local max = type(info) == "table" and tonumber(info.maxSkillLevel) or 0
	local linked = Ask("IsTradeSkillLinked") == true or Ask("IsTradeSkillGuild") == true
	local changed = line ~= S.line or name ~= S.name or skill ~= S.skill or max ~= S.max or linked ~= S.linked
	-- Another profession, or someone else's recipes: the known recipes are read again.
	if line ~= S.line or linked ~= S.linked then
		-- (Another profession's recipe isn't this one's: forgotten until one is picked.)
		if line ~= S.line then S.recipe = nil end
		if ns.Where then ns.Where.ForgetKnown() end
	end
	local was = S.skill or 0
	local rose = line and line == S.line and not linked and skill > was
	S.line, S.name, S.skill, S.max, S.linked = line, name, skill, max, linked
	if rose and ns.Tips then pcall(ns.Tips.SkillUp, line, was, skill, max) end
	-- Your own profession (not someone's linked recipes): kept for the plan and your alts' view.
	if line and not linked and changed and ns.Store then ns.Store.SaveProfession(line, skill, max) end
	-- (The plan is kept with the character: the buy list and the trainer's list read it away from
	-- the profession window. Worked out a moment later, once the known recipes are read.)
	if line and not linked and changed and ns.Plan then
		C_Timer.After(0, function()
			if S.line == line and not S.linked and S.mode then pcall(ns.Plan.Get) end
			if ns.Shop then ns.Shop.Refresh() end
		end)
	end
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
		if ns.Window then ns.Window.Render() end
		if ns.Shop then ns.Shop.Refresh() end
		-- (A controller: the window with its cursor finds the buttons just drawn. Guide.lua's Pad)
		if ns.Pad then ns.Pad.Settle() end
	end)
end

-- Whichever is in use: the pane or our window.
function ns.Shown()
	return (ns.Pane and ns.Pane.Shown()) or (ns.Window and ns.Window.Shown()) or false
end

-- A page showing the plan, your materials or prices is up (bags, bank, mail and prices redraw it).
function ns.ShowingPlan()
	return (ns.Pane and ns.Pane.ShowingPlan()) or (ns.Window and ns.Window.ShowingPlan()) or false
end

function ns.ShowingMissing()
	return (ns.Pane and ns.Pane.ShowingMissing()) or (ns.Window and ns.Window.ShowingMissing()) or false
end

-- The page drawn is waiting on this item's data.
function ns.Waiting(itemID)
	return (ns.Pane and ns.Pane.Waiting(itemID)) or (ns.Window and ns.Window.Waiting(itemID)) or false
end

function ns.MogulOwns()
	local M = _G.DaylightMogul
	local craft = type(M) == "table" and type(M.API) == "table" and M.API.Craft
	if type(craft) ~= "table" or type(craft.Owns) ~= "function" then return false end
	local ok, owns = pcall(craft.Owns)
	return ok and owns == true
end

-- DaylightUI's window.
-- Each opening starts from what you know now (a trainer may have taught you something since).
me.On("CraftShown", function()
	S.mode = "dui"
	if ns.Where then ns.Where.ForgetKnown() end
	ns.ReadProfession()
	ns.Changed()
end)
me.On("CraftProfessionChanged", function()
	S.mode = "dui"
	ns.ReadProfession()
	ns.Changed()
end)
-- Closed: nothing is read for the pane until a profession window opens again (a weapon skill-up
-- with the window shut would otherwise read "no profession" and forget the known recipes).
me.On("CraftHidden", function()
	if S.mode == "dui" then S.mode = nil end
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
events:RegisterEvent("NEW_RECIPE_LEARNED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("PLAYER_LOGIN")

local PaneShown = ns.Shown

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
		-- (Our own window is Take.lua's and Window.lua's.)
		if not ns.MogulOwns() or (ns.Take and ns.Take.Wanted()) then return end
		-- Mogul shows its window as the game opens the trade skill: look for it a frame later.
		C_Timer.After(0, function()
			if not MogulShown() then return end
			S.mode = "mogul"
			if ns.Where then ns.Where.ForgetKnown() end
			ns.ReadProfession()
			if not S.recipe then S.recipe = lastAsked end
			if ns.Pane then ns.Pane.AttachMogul(_G.DaylightMogulCraft) end
			ns.Changed()
		end)
	elseif event == "TRADE_SKILL_CLOSE" then
		if S.mode == "mogul" then S.mode = nil end
	elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "SKILL_LINES_CHANGED" or event == "NEW_RECIPE_LEARNED" then
		-- (A skill-up while you gather: the window's list of professions and a gathering page show it,
		-- with no trade skill open. Only drawn when the window is up.)
		if event == "SKILL_LINES_CHANGED" and ns.Window and ns.Window.Shown() and not S.mode then
			ns.Changed()
		end
		if not S.mode then return end
		-- (The list updates on every bag change and craft; the known recipes are only read again
		-- when the game says one was learned. A new profession reads them anew by itself.)
		if event == "NEW_RECIPE_LEARNED" and ns.Where then ns.Where.MarkStale() end
		local changed = ns.ReadProfession()
		-- Drawn again only when something shown changed: the skill or profession, or (with the
		-- missing list up) a recipe learned.
		if ns.Where and ns.ShowingMissing() and ns.Where.Refresh() then changed = true end
		-- A recipe learned changes the plan too, on any tab.
		if event == "NEW_RECIPE_LEARNED" and ns.Where and ns.Where.Refresh() then changed = true end
		if changed and PaneShown() then ns.Changed() end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		-- Any addon's item asks bring this; only one the recipe page is waiting on redraws it.
		if ns.Waiting(itemID) then ns.Changed() end
	elseif event == "TRAIT_CONFIG_UPDATED" or event == "UPDATE_FACTION" then
		if ns.Calc then ns.Calc.Forget() end
		if PaneShown() then ns.Changed() end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- DaylightUI: plugin, options page
-- ---------------------------------------------------------------------------------------------

local SOURCES = {
	market = L["Market Value"],
	minbuyout = L["Lowest Buyout"],
	daily = L["Today's Average"],
}

local function NoAH(get) return get("useAH") == false end
local function PaneOff(get) return get("window") == "recipes" end
local function WindowOff(get) return get("window") ~= "recipes" end
local function FollowOpacity(get) return get("duiOpacity") ~= false end

local WINDOWS = {
	recipes = L["Recipes Window"],
	game = L["The Game's Window"],
	pane = L["Docked Pane"],
}

local pages = {
	{ id = "recipes", label = L["Recipes"],
	  desc = L["Your profession window, leveling plan and missing recipes."],
	  groups = {
		{ label = L["Profession Window"], items = {
			{ type = "dropdown", key = "window", label = L["Profession Window"], values = WINDOWS, order = { "recipes", "game", "pane" },
			  desc = L["Recipes Window: Daylight Recipes' own (Daylight UI's profession window is switched off for it). The Game's Window: Blizzard's own, as the swap button beside the X picks. Docked Pane: Daylight UI's or DaylightMogul's window with a pane beside it (Daylight UI's comes back after a reload)."] },
			{ type = "slider", key = "winScale", label = L["Window Size"], min = 0.7, max = 1.2, step = 0.05,
			  desc = L["How large Daylight Recipes' window is."], disabled = WindowOff },
			{ type = "slider", key = "paneWidth", label = L["Pane Width"], min = 260, max = 400, step = 10,
			  desc = L["How wide the pane beside Daylight UI's or DaylightMogul's profession window is."], disabled = PaneOff },
		} },
		{ label = L["Look"], items = {
			{ type = "toggle", key = "duiOpacity", label = L["Use Daylight UI's Opacity"],
			  desc = L["Our windows and panels follow Daylight UI's window opacity."] },
			{ type = "slider", key = "opacity", label = L["Window Opacity"], min = 0.1, max = 1, step = 0.05, unit = "%",
			  desc = L["How solid our windows' backgrounds are, with Daylight UI's opacity off."], disabled = FollowOpacity },
		} },
		{ label = L["Prices"], items = {
			{ type = "toggle", key = "useAH", label = L["Use Auction House Prices"],
			  desc = L["Materials, sales and disenchants are priced from the Auction House: DaylightMogul's prices when it's loaded, else what you've browsed or scanned from the Leveling Guide. Off, only vendor prices are used."] },
			{ type = "dropdown", key = "priceSource", label = L["DaylightMogul's Price"], values = SOURCES,
			  desc = L["Which of DaylightMogul's prices to use, when it's loaded."], disabled = NoAH },
			{ type = "toggle", key = "talents", label = L["Count My Profession Talents"],
			  desc = L["Overtime raises the skill-up chance and Bartering lowers vendor prices, by the ranks you've bought."] },
		} },
		{ label = L["Help Around the Game"], items = {
			{ type = "toggle", key = "tooltips", label = L["Item Tooltips"],
			  desc = L["What uses a material, what your plans need of it, and who knows or can learn a recipe item."] },
			{ type = "toggle", key = "vendorMarks", label = L["Mark Recipes at Vendors"],
			  desc = L["A small square on a recipe at a vendor that you or an alt can learn: bright if you can now."] },
			{ type = "toggle", key = "mastercraftTips", label = L["Hide Mastercraft's Recipe Lines"],
			  hidden = function() return not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Mastercraft")) end,
			  disabled = function(get) return get("tooltips") == false end,
			  desc = L["Mastercraft's list of who knows a recipe item stays off while ours shows."] },
			{ type = "toggle", key = "reminders", label = L["Trainer Reminders"],
			  desc = L["A chat line when a skill-up opens new recipes at a trainer, or a profession reaches its cap."] },
			{ type = "toggle", key = "marks", label = L["Mark the Best Recipe"],
			  desc = L["A small mark in the recipe list on the cheapest recipe to skill up with now."] },
			{ type = "toggle", key = "guideGlow", label = L["Light Up the Guide's Step"],
			  hidden = function() return type(API.GlowAround) ~= "function" end,
			  desc = L["A light runs round the Leveling Guide's current step and round its recipe in the recipe list, in the glow style Daylight UI uses for its main buttons."] },
		} },
		{ label = L["Missing Recipes"], items = {
			{ type = "toggle", key = "learnableOnly", label = L["Only Ones My Skill Allows"],
			  desc = L["List only the recipes your skill is high enough to learn now."] },
			{ type = "toggle", key = "tomtom", label = L["Waypoints with TomTom"],
			  desc = L["Clicking a place sets a TomTom waypoint when TomTom is installed. Off, or without it, the game's own map pin is used."] },
		} },
	  } },
}

-- The "Tell me when a newer version is out" switch (Update.lua), on the first page.
if ns.UpdateGroup and pages[1] then table.insert(pages[1].groups, ns.UpdateGroup()) end
-- Help: Retake Tour, What's new, Revert to the profession window you had (Guide.lua, RecipesGuide.lua).
if ns.Guide and ns.Guide.HelpGroup and pages[1] then table.insert(pages[1].groups, ns.Guide.HelpGroup()) end

pcall(function()
	DUI:RegisterPlugin(ADDON, {
		icon = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon-glyph.png",
		needs = { 1, 2 },
		short = L["Recipes"],
		color = { 0.95, 0.75, 0.35 },
		blurb = L["A profession window with costs, skill-up chances, a leveling plan and missing recipes."],
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = L["Recipes"], defaults = DEFAULTS, options = { pages = pages } })
end)

me.On("SettingChanged", function(scope, path)
	-- DaylightUI's main button glow style is the guide's too.
	if scope == "general" and path == "buttonGlow" then
		ns.Changed()
		return
	end
	if scope ~= ADDON then return end
	if path == "guideGlow" then
		ns.Changed()
		return
	end
	if path == "vendorMarks" then
		if ns.Learn then ns.Learn.Refresh() end
		return
	end
	if path == "tooltips" or path == "mastercraftTips" then
		if ns.Tips then ns.Tips.ApplyMastercraft() end
		return
	end
	if path == "paneWidth" then
		if ns.Pane then ns.Pane.Resize() end
		return
	end
	if path == "window" then
		if ns.Take then ns.Take.Recheck() end
		if ns.Swap then ns.Swap.Picked(ns.Get("window")) end
		return
	end
	if path == "winScale" then
		if ns.Window then ns.Window.Rescale() end
		return
	end
	if path == "duiOpacity" or path == "opacity" then
		ns.ReskinWindows()
		return
	end
	if ns.Calc then ns.Calc.Forget() end
	if PaneShown() then ns.Changed() end
end)

me.On("StyleChanged", function()
	ns.ReskinWindows()
	if ns.Doc then ns.Doc.Restyle() end
	if ns.Pane then ns.Pane.Restyle() end
	if ns.Window then ns.Window.Restyle() end
end)

-- /recipes (or /dr): the window, on the open profession or the last one you had open.
SLASH_DAYLIGHTRECIPES1 = "/recipes"
SLASH_DAYLIGHTRECIPES2 = "/dr"
SlashCmdList.DAYLIGHTRECIPES = function()
	if ns.Get("window") ~= "recipes" then
		ns.Print(L["The pane beside the profession window is in use: pick Daylight Recipes' window in its options."])
		return
	end
	if ns.Window then ns.Window.Toggle() end
end

ns.ok = true
