-- Daylight Recipes' welcome, what's new and tours (the engine: Guide.lua). Loaded before Core.lua,
-- so its options can show the Help card; Window.lua and the rest are looked up when needed.
-- luacheck: read globals C_AddOns
local ADDON, ns = ...
local Guide = ns.Guide
if not Guide then return end
local L = ns.L
local DUI = _G.DaylightUI
local Pop = Guide.Pop

local function Loaded(name)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false
end

-- DaylightUI's own profession window is the one to go back to: it's on, or Daylight Recipes
-- switched it off (Swap.lua records that). Read after login, when DaylightUI's modules are up.
local function DaylightHasCraft()
	local db = _G.DaylightRecipesDB
	if type(db) == "table" and db.duiCraftWas then return true end
	local ok, on = pcall(DUI.Get, DUI, "Professions", "enabled")
	return ok and on ~= false and on ~= nil
end

-- The window Daylight Recipes takes the place of, and the "Profession window" choice that gives it
-- back ("pane": DaylightUI's or DaylightMogul's window, which Swap.lua turns back on).
local function Theirs()
	if Loaded("DaylightMogul") then return L["DaylightMogul's profession window"], "pane", L["Revert to DaylightMogul's Window"] end
	if DaylightHasCraft() then return L["DaylightUI's profession window"], "pane", L["Revert to DaylightUI's Window"] end
	return L["the game's profession window"], "game", L["Revert to the Game's Window"]
end
local function GiveBack()
	local _, mode = Theirs()
	DUI:Set(ADDON, "window", mode)
end

local function Get(key) return ns.Get and ns.Get(key) end
local function Parts() return ns.Window and ns.Window.TourParts and ns.Window.TourParts() or {} end

local NEWS = {
	{ version = "2.3.0", lines = {
		L["Tracking: Find Minerals and Find Herbs under your professions on the left. Click one to turn it on or off."],
	} },
	{ version = "2.2.0", lines = {
		L["Tours: the window, the Leveling Guide, the Missing and Queue tabs, the shopping panels and enchanting runs each explain themselves the first time. Retake Tour in the options shows the window's again."],
		L["Shift-click your profession's icon (or the profession on the left) to link it to chat."],
		L["Recipes marked at vendors, and \"Can learn\" in recipe tooltips with your characters who could use them."],
		L["Tells you when a newer version is out (once a session; switch it off under Updates)."],
		L["Revert in the options gives you back the profession window you had."],
	} },
	{ version = "2.1.0", lines = {
		L["Leveling Guide: a light runs round the step you're on, and round its recipe in the list."],
	} },
}

Guide.Setup({
	name = "Daylight Recipes",
	db = function() return _G.DaylightRecipesDB end,
	existing = function()
		local db = _G.DaylightRecipesDB
		if type(db) ~= "table" then return false end
		for k in pairs(db) do
			if k ~= "guide" and k ~= "updateCheck" and k ~= "windowAsked" then return true end
		end
		return false
	end,
	intro = L["A profession window with costs, skill-up chances, a Leveling Guide, a crafting queue and the recipes you're missing. Open a profession, or type /recipes."],
	takes = function()
		local list = {
			string.format(L["Your profession window: Daylight Recipes' own opens in place of %s. The swap button beside its X opens the game's window any time."], (Theirs())),
			L["Vendors, the auction house and trainers: a panel beside them with what to buy or learn for your plan."],
			L["Recipe tooltips: who knows the recipe and who can still learn it."],
		}
		if DaylightHasCraft() and not Loaded("DaylightMogul") then
			list[#list + 1] = L["DaylightUI's profession window is switched off while ours is in use (back after a reload when you revert)."]
		end
		if Loaded("Mastercraft") then
			list[#list + 1] = L["Mastercraft's list of your characters on recipe items is hidden while ours shows."]
		end
		return list
	end,
	tour = "window",
	accept = function()
		if Get("window") == "recipes" then
			if ns.Swap then ns.Swap.Picked("recipes") end
		else
			DUI:Set(ADDON, "window", "recipes")
		end
	end,
	-- (Someone who already uses another window keeps exactly that one.)
	decline = { label = L["Keep My Window"], fn = function() if Get("window") == "recipes" then GiveBack() end end },
	news = NEWS,
	-- (2026-11-16: everyone gets the welcome and the tours once more with this release.)
	reset = "2026-11-16",
	revert = {
		label = L["Profession window"],
		text = function() local _, _, label = Theirs() return label end,
		desc = L["Puts the profession window you had back in place of Daylight Recipes' window. Daylight Recipes' window comes back from the Profession window choice above."],
		available = function() return Get("window") == "recipes" end,
		fn = GiveBack,
	},
})

local function Settings()
	return string.format(L["Everything is in DaylightUI's options: %s. %s there shows this tour again."], Pop(L["Plugins > Recipes"]), Pop(L["Retake Tour"]))
end

-- A tab opened for its step, lit with the page under it.
local function OnTab(key)
	return function() if ns.Window and ns.Window.SetTab then ns.Window.SetTab(key) end end
end
local function TabPage(key)
	return function()
		local p = Parts()
		local b = p.tabOf and p.tabOf[key]
		if b and p.body then return { b, p.body } end
		return p.body
	end
end

Guide.AddTour("window", {
	start = function() if Get("window") == "recipes" and ns.Window then ns.Window.ShowForTour() end end,
	finished = function(how)
		if ns.Window and ns.Window.TourDone then ns.Window.TourDone() end
		-- (The tabs' own first-visit tours say what this one just showed.)
		if how then Guide.MarkSeen("tab-guide", "tab-missing", "tab-queue") end
		if ns.Window and ns.Window.SetTab then ns.Window.SetTab("recipes") end
	end,
	steps = {
		{ title = L["Your professions"],
		  text = L["Click one to open it. Shift-click links it to chat; right-click a main profession to unlearn it. Your alts' professions are listed below, as of their last visit."],
		  part = function() return Parts().side end },
		{ title = L["Tabs"],
		  text = L["Recipes, the Leveling Guide, Materials, your Queue and Missing recipes: everything for this profession in one window. Next shows each one."],
		  part = function() return Parts().tabs end },
		-- Recipes
		{ title = L["Recipes"],
		  text = L["Every recipe you know, sorted by skill-up color. The small mark is the cheapest recipe to skill up with now. Click one to see its materials, cost and chance to skill up; Shift-click links it."],
		  enter = OnTab("recipes"),
		  part = function()
			local p = Parts()
			local b = p.tabOf and p.tabOf.recipes
			return { b, p.list }
		  end },
		{ title = L["Crafting"],
		  text = L["Make one, make all, or add it to the queue. The queue builds a buy list for vendors and the auction house."],
		  enter = OnTab("recipes"),
		  part = function() return Parts().craft end },
		-- Leveling Guide
		{ title = L["Leveling Guide"],
		  text = L["The cheapest way from your skill to the next goal, step by step, with trainer visits and what to buy. The step you're on is lit."],
		  enter = OnTab("guide"), part = TabPage("guide") },
		{ title = L["Each step"],
		  text = string.format(L["%s crafts it, %s adds it to your queue, and %s picks the recipe in the list."], Pop(L["Make"]), Pop(L["Queue"]), Pop(L["Show recipe"])),
		  enter = OnTab("guide"), part = TabPage("guide") },
		-- Materials
		{ title = L["Materials"],
		  text = L["Everything the Leveling Guide's route needs, what you already have of it, and what's left to get, with its price."],
		  enter = OnTab("materials"), part = TabPage("materials") },
		-- Queue
		{ title = L["Queue"],
		  text = L["What you plan to craft, for this character. Its materials go on the buy list at vendors and the auction house, and you can make the next one from here."],
		  enter = OnTab("queue"), part = TabPage("queue") },
		-- Missing
		{ title = L["Missing recipes"],
		  text = L["Every recipe you don't know yet, with where it comes from: trainers, vendors, drops and quests."],
		  enter = OnTab("missing"), part = TabPage("missing") },
		{ title = L["Find it"],
		  text = L["Click a place to put a pin on your map (a TomTom waypoint when TomTom is installed). The search box above narrows the list."],
		  enter = OnTab("missing"), part = TabPage("missing") },
		{ title = L["The swap button"],
		  text = L["Opens the game's profession window instead. On that window, the same button brings this one back."],
		  enter = OnTab("recipes"),
		  part = function() return Parts().swap end },
		{ title = L["Settings"], text = Settings },
	},
})

Guide.AddTour("tab-guide", { steps = {
	{ title = L["Leveling Guide"],
	  text = L["The cheapest way from your skill to the next goal, step by step, with trainer visits and what to buy. The step you're on is lit."],
	  part = function() return Parts().body end },
	{ title = L["Each step"],
	  text = string.format(L["%s crafts it, %s adds it to your queue, and %s picks the recipe in the list."], Pop(L["Make"]), Pop(L["Queue"]), Pop(L["Show recipe"])),
	  part = function() return Parts().body end },
} })

Guide.AddTour("tab-missing", { steps = {
	{ title = L["Missing recipes"],
	  text = L["Every recipe you don't know yet, with where it comes from: trainers, vendors, drops and quests."],
	  part = function() return Parts().body end },
	{ title = L["Find it"],
	  text = L["Click a place to put a pin on your map (a TomTom waypoint when TomTom is installed). The search box above narrows the list."],
	  part = function() return Parts().body end },
} })

Guide.AddTour("tab-queue", { steps = {
	{ title = L["Queue"],
	  text = L["What you plan to craft, for this character. Its materials go on the buy list at vendors and the auction house."],
	  part = function() return Parts().body end },
} })

Guide.AddTour("shop-vendor", { steps = {
	{ title = L["Buy list"],
	  text = string.format(L["What this vendor sells for your queue and Leveling Guide, counted against your bags, bank and mail. %s buys the lot; anything the vendor doesn't have is grayed out."], Pop(L["Buy all here"])),
	  part = function() return _G.DaylightRecipesBuyList end },
} })

Guide.AddTour("shop-auction", { steps = {
	{ title = L["Buy list"],
	  text = L["What your queue and Leveling Guide still need, with auction and vendor prices. Click an item to search for it."],
	  part = function() return _G.DaylightRecipesAHList end },
} })

Guide.AddTour("shop-trainer", { steps = {
	{ title = L["Recommended"],
	  text = L["Only the recipes your Leveling Guide uses next. Learn them here; the rest can wait."],
	  part = function() return _G.DaylightRecipesTrainer end },
} })

Guide.AddTour("enchant", { steps = {
	{ title = L["Enchanting runs"],
	  text = string.format(L["The game needs a click for every enchant, so a run goes one at a time: %s for the next one, %s to stop."], Pop(L["Next"]), Pop(L["Done"])),
	  part = function() return Parts().craft end },
} })
