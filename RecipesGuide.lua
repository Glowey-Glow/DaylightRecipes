-- Glowey's Recipes' welcome, what's new and tours (the engine: Guide.lua). Loaded before Core.lua,
-- so its options can show the Help card; Window.lua and the rest are looked up when needed.
-- luacheck: read globals C_AddOns
local ADDON, ns = ...
local Guide = ns.Guide
if not Guide then return end
local L = ns.L
local DUI = ns.DUI or _G.DaylightUI   -- (ns.DUI: Host.lua; the global only in the offline tests)
local Pop = Guide.Pop

local function Loaded(name)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false
end

-- DaylightUI's own profession window is the one to go back to: it's on, or Glowey's Recipes
-- switched it off (Swap.lua records that). Read after login, when DaylightUI's modules are up.
local function DaylightHasCraft()
	local db = _G.DaylightRecipesDB
	if type(db) == "table" and db.duiCraftWas then return true end
	local ok, on = pcall(DUI.Get, DUI, "Professions", "enabled")
	return ok and on ~= false and on ~= nil
end

-- The window Glowey's Recipes takes the place of, and the "Profession window" choice that gives it
-- back ("pane": DaylightUI's or DaylightMogul's window, which Swap.lua turns back on).
local function Theirs()
	if Loaded("DaylightMogul") then return L["DaylightMogul's profession window"], "pane", L["Revert to DaylightMogul's Window"] end
	if DaylightHasCraft() then return L["Daylight UI's profession window"], "pane", L["Revert to Daylight UI's Window"] end
	return L["the game's profession window"], "game", L["Revert to the Game's Window"]
end
local function GiveBack()
	local _, mode = Theirs()
	pcall(DUI.Set, DUI, ADDON, "window", mode)
end

local function Get(key) return ns.Get and ns.Get(key) end
-- The Blizzard Layout in use now (WindowLayout.lua): some steps say it its own way.
local function Layout()
	local W = ns.Win
	return W ~= nil and W.Lay ~= nil and W.Lay.Active() == true
end
local function Parts() return ns.Window and ns.Window.TourParts and ns.Window.TourParts() or {} end

-- Newest first. An entry is keyed by the release it ships in (CHANGELOG.md's heading), and its
-- lines are in all six language files. A player updating sees every entry above the one they
-- read last (Guide.News), so 3.0.0's is what says why the window is suddenly small.
local NEWS = {
	{ version = "3.2.0", lines = {
		L["Prices from your Auction House addon: Auctionator, TradeSkillMaster, AuctionMaster, AHDB, Auctioneer, ForeverForge Auction or Oribos Exchange. A window asks once whose prices to use; change it in Plugins > Recipes > Prices."],
	} },
	{ version = "3.1.0", lines = {
		L["Works without Daylight UI: its settings are in Glowey's settings (/glowey), and the Blizzard Style look dresses the window in the game's own frames, tabs, bars and scroll bars. With Daylight UI it follows its language, look and scale."],
		L["Blizzard Layout (in the options, off to start): the window laid out like the game's profession window, with your professions as tabs down its left side and Alts, Cooldowns and Tracking as pages of their own. The Leveling Guide shows its step's recipe on the right."],
		L["Chance of Skill Up takes the chance's own color, Also Known By lists only your other characters, Camping folds each profession's items, and Link to Chat can post to a channel or whisper someone."],
	} },
	{ version = "3.0.2", lines = {
		L["Your professions are chips across the title bar: one press opens another, with no menu to open first. A right-click on a chip links or unlearns it, and the three dots at the end have your alts, Cooldowns and Tracking. Menus and lists are solid boxes now, whatever Window Opacity is set to."],
	} },
	{ version = "3.0.0", lines = {
		L["A compact window: one column at the left of the screen. Details slide out from the Details button (Y on a controller), Roll Up folds it to one bar that says what it will make, and your professions are across the title bar, with your alts, Cooldowns and Tracking behind the three dots at its end."],
		L["Vendors, trainers and the auction house: the panels are now a thin strip under the window, only where there is something for you. List shows the items, a press on one buys or learns it, and Buy All Needed asks first."],
		L["The strips carry everything the Buy List gained in 2.6 to 2.8: Queue List and Guide List, profession tags, Remove with a Shift-click, and Check Prices at the auction house."],
		L["Tours no longer start by themselves. Retake Tour, Shop Strip Tour and Enchanting Runs Tour are in Plugins > Recipes > Help."],
		L["With Professionally Lost installed, a window asks once which of the two addons does each job. Nothing changes until you press Apply, and Put Everything Back in the options undoes it."],
	} },
	{ version = "2.5.0", lines = {
		L["Enchanting in the Docked Pane: the item slot, Auto-replace and enchant runs beside Daylight UI's or DaylightMogul's profession window, as in the Recipes window."],
	} },
	{ version = "2.4.0", lines = {
		L["Cooldowns: your recipes with a cooldown (transmutes, Mooncloth and more) above Tracking, with the time left. Click one to open it."],
		L["Controller support: the whole window, the shopping panels and the tours work with a controller."],
	} },
	{ version = "2.3.0", lines = {
		L["Tracking: Find Minerals and Find Herbs under your professions on the left. Click one to turn it on or off."],
	} },
	{ version = "2.2.0", lines = {
		L["Tours: the window, the Leveling Guide, the Missing and Queue tabs, the shopping panels and enchanting runs each explain themselves the first time. Retake Tour in the options shows the window's again."],
		L["Shift-click your profession's icon (or the profession on the left) to link it to chat."],
		L["Recipes marked at vendors, and \"Can Learn\" in recipe tooltips with your characters who could use them."],
		L["Tells you when a newer version is out (once a session; switch it off under Updates)."],
		L["Revert in the options gives you back the profession window you had."],
	} },
	{ version = "2.1.0", lines = {
		L["Leveling Guide: a light runs round the step you're on, and round its recipe in the list."],
	} },
}

Guide.Setup({
	name = "Glowey's Recipes",
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
			string.format(L["Your profession window: Glowey's Recipes' own opens in place of %s. The swap button beside its X opens the game's window any time."], (Theirs())),
			L["Vendors, trainers and the auction house: a thin strip under their window with what to buy or learn, only where there is something for you."],
			L["Recipe tooltips: who knows the recipe and who can still learn it."],
		}
		if DaylightHasCraft() and not Loaded("DaylightMogul") then
			list[#list + 1] = L["Daylight UI's profession window is switched off while ours is in use (back after a reload when you revert)."]
		end
		if Loaded("Mastercraft") then
			list[#list + 1] = L["Mastercraft's list of your characters on recipe items is hidden while ours shows."]
		end
		-- (Nothing is handed over before the player answers that window: ProfLost.lua.)
		if ns.ProfLost and ns.ProfLost.Loaded() then
			list[#list + 1] = L["Professionally Lost is installed too: a window asks you which of the two does each job."]
		end
		return list
	end,
	tour = "window",
	-- Tours are never started for the player: the first time a place shows, a toast names the Help
	-- card, which starts each of them.
	help = L["Plugins > Recipes > Help"],
	offerTour = function(id)
		if id == "shop" or id == "enchant" then return id end
		return "window"
	end,
	moreTours = {
		{ id = "shop", label = L["Shop Strip Tour"],
		  desc = L["What the strip under a vendor, a trainer and the auction house does."] },
		{ id = "enchant", label = L["Enchanting Runs Tour"],
		  desc = L["How a run of enchants goes, one click at a time."] },
	},
	accept = function()
		if Get("window") == "recipes" then
			if ns.Swap then ns.Swap.Picked("recipes") end
		else
			pcall(DUI.Set, DUI, ADDON, "window", "recipes")
		end
	end,
	-- (Someone who already uses another window keeps exactly that one.)
	decline = { label = L["Keep My Window"], fn = function() if Get("window") == "recipes" then GiveBack() end end },
	news = NEWS,
	-- (2026-11-16: everyone gets the welcome and the tours once more with this release.)
	reset = "2026-11-16",
	revert = {
		label = L["Profession Window"],
		text = function() local _, _, label = Theirs() return label end,
		desc = L["Puts the profession window you had back in place of Glowey's Recipes' window. Glowey's Recipes' window comes back from the Profession Window choice above."],
		available = function() return Get("window") == "recipes" end,
		fn = GiveBack,
	},
})

-- The Leveling Guide and Materials tabs are not there for a profession whose guide is handed to
-- Professionally Lost (ProfLost.lua): their steps are left out of a run.
local function OwnGuide()
	local P, S = ns.ProfLost, ns.state
	return not (P and S and P.Handed("guide", S.line))
end

local function Settings()
	if ns.standalone then
		return string.format(L["Everything is in Glowey's settings: %s. %s there shows this tour again."], Pop("/glowey"), Pop(L["Retake Tour"]))
	end
	return string.format(L["Everything is in Daylight UI's options: %s. %s there shows this tour again."], Pop(L["Plugins > Recipes"]), Pop(L["Retake Tour"]))
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
	-- (The window goes back to the tab and the rolled-up state it was left in: Window.TourDone.)
	finished = function()
		if ns.Window and ns.Window.TourDone then ns.Window.TourDone() end
	end,
	steps = {
		-- (The window's parts are Window.TourParts(), as its own comment in Window.lua lists them: `menu`
		-- is the title bar's row of profession chips, which with its "more" chip took the old
		-- sidebar's place (on an alt's page or someone's recipes: the name there); `summary`
		-- the picked recipe's line above the craft bar; `details` and `roll` the header's two buttons.
		-- The window is always unrolled for a tour: Window.ShowForTour.)
		{ title = L["Your Professions"],
		  text = function()
			if Layout() then
				return string.format(L["Your professions are tabs down the window's left side, Camping after them, then %s, %s and %s, each a page of its own. The open one is lit; press another to open it. A right-click on a profession's tab (Y on a controller) has %s and %s."],
					Pop(L["Your Alts"]), Pop(L["Cooldowns"]), Pop(L["Tracking"]), Pop(L["Link to Chat"]), Pop(L["Unlearn"]))
			end
			return string.format(L["Your professions are chips across the title bar, Camping after them. The open one is lit and shows its skill; press another to open it. A right-click on a chip (Y on a controller) has %s and %s. The three dots at the end have your alts' professions, your cooldowns and tracking. %s in the options hides your alts' professions."], Pop(L["Link to Chat"]), Pop(L["Unlearn"]), Pop(L["Show Your Alts' Professions"]))
		  end,
		  part = function()
			local p = Parts()
			return p.menu or p.side
		  end },
		-- Recipes
		{ title = L["Recipes"],
		  text = function()
			if Layout() then
				return string.format(L["Every recipe you know, by category; the arrow before a name is how surely it gives a point, and the number after it how many you can make. The box marks the cheapest recipe to skill up with now. %s narrows the list to what you can make or what gives points. Shift-click links a recipe."], Pop(L["Filter"]))
			end
			return L["Every recipe you know, sorted by skill-up color. The small mark is the cheapest recipe to skill up with now. Pick one: its chance to skill up, material cost and sale value show in one line above the craft bar. Shift-click links it."]
		  end,
		  enter = OnTab("recipes"),
		  part = function()
			local p = Parts()
			local b = p.tabOf and p.tabOf.recipes
			return { b, p.list }
		  end },
		{ title = L["Crafting"],
		  text = string.format(L["Set how many (%s fills in all you can make), then Create, or add it to the queue. What the queue needs shows on the strips at vendors and the auction house."], Pop(L["Max"])),
		  enter = OnTab("recipes"),
		  part = function() return Parts().craft end },
		-- (The Blizzard Layout: the recipe is always on the right, and the rank bar's link button.)
		{ title = L["The Recipe"],
		  text = string.format(L["The picked recipe, on the right: its reagents with what you hold of each, the total cost, %s in the chance's own color (red when a point is unlikely, green when it's sure), what it sells for, and which of your other characters know it."], Pop(L["Chance of Skill Up"])),
		  enter = OnTab("recipes"), when = Layout,
		  part = function() return Parts().detail end },
		{ title = L["Link to Chat"],
		  text = string.format(L["The button after the skill bar links your profession: into the chat box when one is open, else it asks where to post it (Guild, Party, Raid, a channel) or %s someone by name."], Pop(L["Whisper..."])),
		  enter = OnTab("recipes"), when = function() return Layout() and Parts().link ~= nil end,
		  part = function() return Parts().link end },
		{ title = L["Details"],
		  when = function() return not Layout() end,
		  text = string.format(L["The picked recipe's chance, cost and sale value are in one line above the craft bar. Press that line, or %s (Y on a controller), for its full page beside the list. Open or closed is remembered for each tab."], Pop(L["Details"])),
		  enter = OnTab("recipes"),
		  part = function()
			local p = Parts()
			return { p.summary, p.details }
		  end },
		-- (The window is shown unrolled for a tour, so the step lights the button; what the rolled-up
		-- bar says is told in words.)
		{ title = L["Roll Up"],
		  text = string.format(L["Folds the window to its header and one bar while you craft. Rolled up, the bar says what it will make: the next craft in your queue, with %s, or else the picked recipe. Press it again to unroll."], Pop(L["Craft Next"])),
		  enter = OnTab("recipes"),
		  part = function() return Parts().roll end },
		-- Leveling Guide
		{ title = L["Leveling Guide"],
		  text = function()
			local base = string.format(L["The cheapest way from your skill to the next goal, step by step, with trainer visits and what to buy. Every step uses a recipe that still gives skill points at that skill (orange or yellow). %s and %s at the top set where it leads and what it saves on. The step you're on is lit."], Pop(L["Goal"]), Pop(L["Cheapest Route"]))
			if Layout() then return base .. " " .. L["Its recipe shows on the right."] end
			return base
		  end,
		  enter = OnTab("guide"), part = TabPage("guide"), when = OwnGuide },
		{ title = L["Each Step"],
		  text = string.format(L["%s crafts it, %s adds it to your queue, and %s picks the recipe in the list. %s lists other recipes that give points right now."], Pop(L["Make"]), Pop(L["Queue"]), Pop(L["Show Recipe"]), Pop(L["Alternates"])),
		  enter = OnTab("guide"), part = TabPage("guide"), when = OwnGuide },
		-- Materials
		{ title = L["Materials"],
		  text = L["Everything the Leveling Guide's route needs, what you already have of it, and what's left to get, with its price."],
		  enter = OnTab("materials"), part = TabPage("materials"), when = OwnGuide },
		-- Queue
		{ title = L["Queue"],
		  text = L["What you plan to craft, for this character. Its materials are the Queue List on the strips at vendors and the auction house, and you can make the next one from here or from the rolled-up window."],
		  enter = OnTab("queue"), part = TabPage("queue") },
		-- Missing
		{ title = L["Missing Recipes"],
		  text = L["Every recipe you don't know yet, with where it comes from: trainers, vendors, drops and quests. Click a place to put a pin on your map (a TomTom waypoint when TomTom is installed). The search box above narrows the list."],
		  enter = OnTab("missing"), part = TabPage("missing") },
		-- (Camping's page, told while it shows.)
		{ title = L["Camping"],
		  text = L["Every camping item of your professions, and the others' under Other Professions. Click a profession's name to fold its items away, and an item for what it takes, how to learn it and how to make it."],
		  when = function() return ns.Win ~= nil and ns.Win.gather == ns.Win.CAMP end },
		{ title = L["The Swap Button"],
		  text = L["Opens the game's profession window instead. On that window, the same button brings this one back."],
		  enter = OnTab("recipes"),
		  part = function() return Parts().swap end },
		-- Only where they apply: Professionally Lost installed; the Docked Pane in use beside a
		-- Daylight UI window that shows cost and profit itself (Pane.ProfitCould).
		{ title = L["Professionally Lost"],
		  text = string.format(L["Professionally Lost is installed too. Which of the two addons does each job (the Leveling Guide, buy lists, the trainer strip, tooltips, prices) is set by the switches under Professionally Lost in the options. %s there gives everything back to Glowey's Recipes."], Pop(L["Put Everything Back"])),
		  when = function() return ns.ProfLost ~= nil and ns.ProfLost.Loaded() == true end },
		{ title = L["Cost and Profit"],
		  text = string.format(L["Beside Daylight UI's profession window, the Docked Pane leaves a recipe's materials total and Auction House profit to that window, which shows them itself. %s in the options decides it."], Pop(L["Leave Cost and Profit to Daylight UI"])),
		  when = function()
			return Get("window") ~= "recipes" and ns.Pane ~= nil and ns.Pane.ProfitCould ~= nil and ns.Pane.ProfitCould() == true
		  end },
		-- (The option to lay the window out like the game's, told while it's off.)
		{ title = L["Blizzard Layout"],
		  text = string.format(L["%s in the options lays this window out like the game's own profession window: your professions as tabs down its left side, the recipe always on the right, its pages as tabs under it."], Pop(L["Blizzard Layout"])),
		  when = function() return Get("window") == "recipes" and Get("blizzardLayout") ~= true end },
		{ title = L["Settings"], text = Settings },
	},
})

-- The strips at vendors, trainers and the auction house (Shop.lua): the one on show is lit; away
-- from all three the card stands alone.
local function Strip() return ns.Shop and ns.Shop.TourPart and ns.Shop.TourPart() or nil end

-- (A step about the list lights the strip and its list when the list is open, else the strip; with
-- no strip up at all, part() answers nothing and the card stands alone: the same rule for every step.)
local function StripAndList()
	local strip = Strip()
	if strip and strip.list and strip.list:IsShown() then return { strip, strip.list } end
	return strip
end

Guide.AddTour("shop", { steps = {
	{ title = L["The Strip"],
	  text = L["Where a vendor, a trainer or the auction house has something for your queue or Leveling Guide, a thin strip docks under its window (at the auction house, under its bottom right corner): how many items there are for you and what they cost. Where there is nothing for you, nothing shows."],
	  part = Strip },
	{ title = L["Buying and Learning"],
	  text = string.format(L["At a vendor, %s buys everything on the list that the vendor sells, after asking once with the total; short of gold, it reads %s and buys what your gold reaches. At a trainer, %s learns the recipes your Leveling Guide uses."], Pop(L["Buy All Needed"]), Pop(L["Buy What I Can Afford"]), Pop(L["Learn All Recommended"])),
	  part = Strip },
	{ title = L["The List"],
	  text = string.format(L["%s opens the list at the strip's right end. A press on a row buys or learns that one at once, exactly what you need. At the auction house a press searches for the item: the row reads %s under the mouse."], Pop(L["List"]), Pop(L["Left Click to Search"])),
	  part = StripAndList },
	{ title = L["Two Lists"],
	  text = string.format(L["%s is what your crafting queue needs and %s what your Leveling Guides need, each with its count. When a list covers more than one profession, tags under them (%s first) narrow it to one."], Pop(L["Queue List"]), Pop(L["Guide List"]), Pop(L["All"])),
	  part = StripAndList },
	{ title = L["The Cheapest Place"],
	  text = string.format(L["Each place lists only what is cheapest there: a vendor leaves out what the auction house sells for less, and the other way round. A line at the end of the list says how many were left out, and %s brings them back for that visit."], Pop(L["Show"])),
	  part = StripAndList },
	{ title = L["Remove"],
	  text = string.format(L["Hold Shift over a row and Shift-click to take it off that list (the Menu button on the left of a controller): the row reads %s while Shift is held. The last line of the list puts removed items back."], Pop(L["Remove"])),
	  part = StripAndList },
	{ title = L["Check Prices"],
	  text = string.format(L["At the auction house, %s reads how many are for sale at each price, so a row shows what the number you need really costs. A cost that says \"about\" is an estimate from the lowest price, and \"only 40 for sale\" means there are fewer than you need."], Pop(L["Check Prices"])),
	  part = Strip },
	{ title = L["What You Buy"],
	  text = L["What you buy comes off the lists at once: at the vendor, and at the auction house too, where purchases arrive by mail and are counted before you visit a mailbox."],
	  part = StripAndList },
} })

Guide.AddTour("enchant", { steps = {
	{ title = L["Enchanting Runs"],
	  text = string.format(L["The game needs a click for every enchant, so a run goes one at a time: %s for the next one, %s to stop."], Pop(L["Next"]), Pop(L["Done"])),
	  -- (The docked pane's enchant section while the pane is in use, else the window's craft bar.)
	  part = function()
		local pane = ns.Pane and ns.Pane.EnchantPart and ns.Pane.EnchantPart()
		return pane or Parts().craft
	  end },
} })
