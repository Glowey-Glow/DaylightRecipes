-- Tours never start by themselves: Guide.Offer shows one toast per tour and account, after the
-- welcome is answered, and never runs a tour; the Help card starts each of them. Loads Guide.lua
-- and RecipesGuide.lua itself (they are not in the runner's list: they need Daylight UI's table).
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightRecipesDB NS
-- luacheck: read globals T Fire NewObj ADDON_ROOT
local ns = NS

-- Daylight UI, as much of it as the guide's engine touches.
ns.API.Fade = function(region, alpha) region.fadedTo = alpha end
ns.API.MainButton = function() return true end
DaylightUI = { API = ns.API, Set = function(_, _, key, value) GAME.settings[key] = value end,
	Get = function() return true end }

-- A player from before this version: the welcome answered, no tour taken.
DaylightRecipesDB = { guide = { welcomed = true, reset = "2026-11-16", newsSeen = "2.5.0", tours = {} }, chars = {} }

for _, file in ipairs({ "Guide.lua", "RecipesGuide.lua" }) do
	local chunk = assert(loadfile(ADDON_ROOT .. "/" .. file))
	chunk("DaylightRecipes", ns)
end
local Guide = ns.Guide
T.ok(Guide and Guide.Offer, "the guide loaded")
Fire("ADDON_LOADED", "DaylightRecipes")

local function offered() return DaylightRecipesDB.guide.offered or {} end

-- The window shows for the first time: a toast, not a tour.
Guide.Offer("window")
T.run(3)
T.eq(Guide.Running(), false, "no tour starts by itself")
T.eq(offered().window, true, "the window's tour was offered by a toast")
T.eq(DaylightRecipesDB.guide.tours.window, nil, "and is not marked as taken")

-- Its tabs and the same window again: no second toast for the same tour.
local before = offered()
Guide.Offer("tab-guide")
Guide.Offer("tab-missing")
Guide.Offer("window")
T.run(3)
T.eq(Guide.Running(), false, "a tab does not start a tour either")
T.eq(offered(), before, "one toast per tour, ever")
T.eq(offered()["tab-guide"], nil, "a tab belongs to the window's tour")

-- A strip and the enchanting row have tours of their own.
Guide.Offer("shop")
Guide.Offer("enchant")
T.run(3)
T.eq(offered().shop, true, "the strips' tour is offered once")
T.eq(offered().enchant, true, "and the enchanting runs'")
T.eq(Guide.Running(), false, "still no tour running")

-- A tour already taken is not offered.
DaylightRecipesDB.guide.offered = nil
DaylightRecipesDB.guide.tours.window = true
Guide.Offer("window")
Guide.Offer("tab-queue")
T.run(3)
T.eq(offered().window, nil, "no toast for a tour the player has taken")

-- Before the welcome is answered nothing is offered; once it is, the toast comes.
DaylightRecipesDB.guide.tours = {}
DaylightRecipesDB.guide.offered = nil
DaylightRecipesDB.guide.welcomed = nil
Guide.Offer("shop")
T.run(6)
T.eq(offered().shop, nil, "the toast waits for the welcome")
DaylightRecipesDB.guide.welcomed = true
T.run(6)
T.eq(offered().shop, true, "and comes once it is answered")

-- Asked for, a tour runs: the Help card's buttons.
local help = Guide.HelpGroup()
local labels = {}
for _, item in ipairs(help.items) do labels[#labels + 1] = item.label end
T.eq(labels[1], "Retake Tour", "the Help card starts the window's tour")
T.eq(labels[2], "Shop Strip Tour", "and the strips'")
T.eq(labels[3], "Enchanting Runs Tour", "and the enchanting runs'")
T.eq(labels[4], "What's New", "then What's New")
help.items[2].func()
T.eq(Guide.Running(), true, "Shop Strip Tour runs when asked")
-- (Away from a vendor, a trainer and the Auction House: no strip is up, and every step's card
-- stands alone. The tour runs through all the same.)
local walked = 0
for _ = 1, 30 do
	if not Guide.Running() then break end
	T.run(1)
	walked = walked + 1
	Guide.Next()
end
T.eq(Guide.Running(), false, "it runs to its end with nothing to point at")
T.eq(walked, #Guide.Tour("shop").steps, "every one of its steps shown")
T.eq(DaylightRecipesDB.guide.tours.shop, true, "a tour taken is remembered")

-- ==================================================================================================
-- Every step of every tour against what the plugin now is
-- ==================================================================================================
local function read(file)
	local f = assert(io.open(ADDON_ROOT .. "/" .. file, "r"))
	local src = f:read("*a")
	f:close()
	return src
end

-- The plugin's own files (the .toc's), without the one the tours are written in.
local sources = {}
for line in read("DaylightRecipes.toc"):gmatch("[^\r\n]+") do
	local file = line:match("^([%w_]+%.lua)$")
	-- (Guide.lua has the Help card's own buttons, which the tours name: Retake Tour.)
	if file and file ~= "RecipesGuide.lua" then sources[#sources + 1] = read(file) end
end
T.ok(#sources > 20, "the plugin's files are read (" .. #sources .. ")")
local function onScreen(label)
	local needle = 'L["' .. label .. '"]'
	for _, src in ipairs(sources) do
		if src:find(needle, 1, true) then return true end
	end
	return false
end

-- No step names a label that is not on screen any more: every label a tour puts in a pop
-- (Pop(L["..."])) is a string some other file of the plugin still shows.
local guideSrc = read("RecipesGuide.lua")
local popped = 0
for label in guideSrc:gmatch('Pop%(L%["(.-)"%]%)') do
	popped = popped + 1
	-- ("Plugins > Recipes" is the way through Daylight UI's options to ours, not a label of ours.)
	T.ok(label == "Plugins > Recipes" or onScreen(label), ("the tours name \"%s\": it is still a label of the plugin"):format(label))
end
T.ok(popped >= 20, "the tours' labels were found (" .. popped .. ")")
-- And every title that is a control's own name is that control's name.
for _, title in ipairs({ "Roll Up", "Details", "Leveling Guide", "Materials", "Queue", "Recipes", "Remove", "Check Prices",
	"Professionally Lost" }) do
	T.ok(onScreen(title), "a step titled " .. title .. ": the control of that name exists")
end

-- The window's parts, as Window.TourParts really names them (read from Window.lua), each a frame.
local windowSrc = read("Window.lua")
local body = windowSrc:match("function Window%.TourParts%(%)(.-)\nend")
T.ok(body ~= nil, "Window.TourParts is there")
local partKeys = {}
for key in body:match("return (%b{})"):gmatch("([%a_]+) = ") do partKeys[key] = true end
for _, key in ipairs({ "menu", "tabs", "tabOf", "list", "craft", "body", "swap", "details", "roll", "summary" }) do
	T.ok(partKeys[key], "the window still hands the tour its part: " .. key)
end
local TABS = { "recipes", "guide", "materials", "queue", "missing" }
local stateSrc = read("WindowState.lua")
for _, key in ipairs(TABS) do
	T.ok(stateSrc:find('"' .. key .. '"', 1, true), "the window still has the tab: " .. key)
end
local parts, tabbed = {}, {}
for key in pairs(partKeys) do parts[key] = NewObj("Frame") end
parts.tabOf, parts.tabs = {}, {}
for i, key in ipairs(TABS) do
	parts.tabOf[key] = NewObj("Button")
	parts.tabs[i] = parts.tabOf[key]
end
parts.tab = "recipes"
ns.Window = {
	TourParts = function() return parts end,
	SetTab = function(key) tabbed[#tabbed + 1] = key end,
	ShowForTour = function() end, TourDone = function() end,
}
local isTab = {}
for _, key in ipairs(TABS) do isTab[key] = true end

-- A step's part resolved: a frame, or a list of frames with none missing.
local function isFrame(v) return type(v) == "table" and rawget(v, "kind") ~= nil end
local function resolves(got)
	if isFrame(got) then return true end
	if type(got) ~= "table" then return false end
	local n = 0
	for k, v in pairs(got) do
		if type(k) ~= "number" or not isFrame(v) then return false end
		n = n + 1
	end
	return n > 0 and n == #got
end
local function words(step)
	local text = step.text
	if type(text) == "function" then text = text() end
	return text
end
local function sound(id, step, i)
	local what = ("%s step %d (%s)"):format(id, i, tostring(step.title))
	T.ok(type(step.title) == "string" and step.title ~= "", what .. ": a title")
	local text = words(step)
	T.ok(type(text) == "string" and #text > 20, what .. ": its words")
	T.ok(not text:find("%%s") and not text:find("%%d"), what .. ": every blank in them is filled")
	T.ok(#text <= 420, what .. ": short enough for the card (" .. #text .. " letters)")
end

-- ---- the window's tour ---------------------------------------------------------------------------
local window = Guide.Tour("window")
T.ok(window and #window.steps >= 10 and #window.steps <= 20, "the window's tour: every part, compact or Blizzard Layout, some only where they apply (" .. #window.steps .. ")")
local titles = {}
for i, step in ipairs(window.steps) do
	sound("window", step, i)
	titles[step.title] = step
	tabbed = {}
	if step.enter then step.enter() end
	for _, key in ipairs(tabbed) do T.ok(isTab[key], ("window step %d opens a tab that exists: %s"):format(i, key)) end
	if step.part then
		local ok, got = pcall(step.part)
		T.ok(ok and resolves(got), ("window step %d (%s): what it points at is there"):format(i, step.title))
	end
end
for _, title in ipairs({ "Your Professions", "Recipes", "Crafting", "Details", "Roll Up", "Leveling Guide", "Each Step",
	"Materials", "Queue", "Missing Recipes", "The Swap Button", "Professionally Lost", "Cost and Profit", "Settings" }) do
	T.ok(titles[title] ~= nil, "the window's tour has the step: " .. title)
end
-- What is new is said where it is met.
T.ok(words(titles["Your Professions"]):find("Show Your Alts' Professions", 1, true), "the menu's step names the option that hides alts' professions")
T.ok(words(titles["Roll Up"]):find("Craft Next", 1, true) and words(titles["Roll Up"]):find("queue", 1, true),
	"Roll Up's step says the rolled-up bar is the queue's next, with Craft Next")
T.ok(words(titles["Leveling Guide"]):find("orange or yellow", 1, true), "the guide's step says a step only uses recipes that give points")
T.ok(words(titles["Each Step"]):find("Alternates", 1, true), "and names Alternates")
T.ok(words(titles["Queue"]):find("Queue List", 1, true), "the queue's step names the Queue List")
T.ok(words(titles["Missing Recipes"]):find("pin on your map", 1, true), "the Missing step says how to find a source")
-- A missing part is no error: the card stands alone (a part of a window that is not open).
parts.roll, parts.summary, parts.details = nil, nil, nil
for i, step in ipairs(window.steps) do
	if step.part then T.ok((pcall(step.part)), ("window step %d: a part that is not there raises nothing"):format(i)) end
end

-- The two steps that are only for some players: not in a run without what they are about.
local function runLength(id)
	Guide.Run(id)
	local n = 0
	for _ = 1, 40 do
		if not Guide.Running() then break end
		T.run(1)
		n = n + 1
		Guide.Next()
	end
	T.eq(Guide.Running(), false, id .. ": runs to its end")
	return n
end
GAME.settings.window = "recipes"
ns.ProfLost.Loaded = function() return false end
ns.ProfLost.Handed = function() return false end
ns.Pane = { ProfitCould = function() return false end }
local plain = runLength("window")
-- (Nor, in the compact window, the Blizzard Layout's two (The Recipe, Link to Chat) and Camping's,
-- told only on its page.)
T.eq(plain, #window.steps - 5, "without Professionally Lost and the Docked Pane's hand-off: neither of their steps")
ns.ProfLost.Loaded = function() return true end
T.eq(runLength("window"), plain + 1, "with Professionally Lost installed: its step")
ns.ProfLost.Loaded = function() return false end
ns.Pane.ProfitCould = function() return true end
T.eq(runLength("window"), plain, "Daylight UI could show profit, but Recipes' own window is in use: no step about the pane")
GAME.settings.window = "pane"
-- (Its step in, the Blizzard Layout's out: that is about Recipes' own window, not in use here.)
T.eq(runLength("window"), plain, "the Docked Pane beside a Daylight UI that shows cost and profit: its step, and not the Blizzard Layout's")
ns.Pane.ProfitCould = function() return false end
T.eq(runLength("window"), plain - 1, "the pane without that: no step (and no Blizzard Layout step)")
-- A profession whose guide is Professionally Lost's: the steps of the two tabs that are gone are left out.
ns.ProfLost.Handed = function(key) return key == "guide" end
GAME.settings.window = "recipes"
T.eq(runLength("window"), plain - 3, "its Leveling Guide handed over: no Leveling Guide, Each Step or Materials step")
ns.ProfLost.Handed = function() return false end

-- ---- the strips' tour ------------------------------------------------------------------------------
local shop = Guide.Tour("shop")
T.ok(shop and #shop.steps >= 6 and #shop.steps <= 10, "the strips' tour: no more than ten steps (" .. #shop.steps .. ")")
local shopTitles = {}
for i, step in ipairs(shop.steps) do
	sound("shop", step, i)
	shopTitles[step.title] = step
	T.ok(type(step.part) == "function", ("shop step %d points at the strip that is up"):format(i))
	local ok, got = pcall(step.part)
	T.ok(ok and got == nil, ("shop step %d: with no strip up it points at nothing, and raises nothing"):format(i))
end
for _, title in ipairs({ "The Strip", "Buying and Learning", "The List", "Two Lists", "The Cheapest Place", "Remove",
	"Check Prices", "What You Buy" }) do
	T.ok(shopTitles[title] ~= nil, "the strips' tour has the step: " .. title)
end
T.ok(words(shopTitles["The Strip"]):find("bottom right corner", 1, true), "the strip's step says where it is at the Auction House")
T.ok(words(shopTitles["Buying and Learning"]):find("Buy What I Can Afford", 1, true)
	and words(shopTitles["Buying and Learning"]):find("Learn All Recommended", 1, true), "buying and learning names both buttons")
T.ok(words(shopTitles["The List"]):find("right end", 1, true) and words(shopTitles["The List"]):find("Left Click to Search", 1, true),
	"the list's step says where it opens and what a press does at the Auction House")
T.ok(words(shopTitles["Two Lists"]):find("Queue List", 1, true) and words(shopTitles["Two Lists"]):find("Guide List", 1, true), "the two lists")
T.ok(words(shopTitles["Check Prices"]):find("about", 1, true) and words(shopTitles["Check Prices"]):find("for sale", 1, true),
	"Check Prices says what \"about\" and \"only N for sale\" mean")
-- At a vendor with something needed: every step points at the real strip, and the list's steps at
-- the strip and its list once the list is open.
GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540
GAME.plans = { [197] = { need = { [2320] = 5 } } }
GAME.vendorPrice = { [2320] = 10 }
GAME.money = 100000
DaylightRecipesDB.shop = { vendor = true }
T.vendor({ { id = 2320, price = 10, stack = 1, max = 20 } })
T.run(1)
local strip = _G.DaylightRecipesBuyStrip
T.ok(strip and strip:IsShown() and strip.list:IsShown(), "(a vendor's strip is up, its list open)")
for i, step in ipairs(shop.steps) do
	local ok, got = pcall(step.part)
	T.ok(ok and resolves(got), ("shop step %d (%s): it points at the strip"):format(i, step.title))
	if isFrame(got) then
		T.eq(got, strip, ("shop step %d: the strip itself"):format(i))
	else
		T.ok(got[1] == strip and got[2] == strip.list, ("shop step %d: the strip and its list"):format(i))
	end
end
strip.listButton:Click()
for i, step in ipairs(shop.steps) do
	local ok, got = pcall(step.part)
	T.ok(ok and got == strip, ("shop step %d: with the list shut, the strip alone"):format(i))
end
T.leave()

-- ---- the enchanting runs' tour -----------------------------------------------------------------
local enchant = Guide.Tour("enchant")
T.eq(#enchant.steps, 1, "the enchanting runs' tour is its one step")
sound("enchant", enchant.steps[1], 1)
parts.craft = parts.craft or NewObj("Frame")
ns.Pane.EnchantPart = function() return nil end
T.ok(resolves(enchant.steps[1].part()), "it points at the window's craft bar")

return T.done()
