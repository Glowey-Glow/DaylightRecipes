-- What a player sees at login, and in which order: the What's New note for a player updating from
-- 2.5.2 (the window is suddenly small: they are told why), then, only after it is closed and only
-- with Professionally Lost loaded, the hand-off window. Never two at once, never over Daylight UI's
-- own guide or another Daylight plugin's. Loads Guide.lua and RecipesGuide.lua itself, over the
-- ProfLost.lua the runner loaded.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightRecipesDB NS DaylightGuides DaylightUIInstaller ProfLost ProfLostCharDB
-- luacheck: read globals T Fire NewObj ADDON_ROOT ALL InstallProfLost
local ns = NS

ns.API.Fade = function(region, alpha) region.fadedTo = alpha end
ns.API.MainButton = function() return true end
DaylightUI = { API = ns.API, Set = function(_, _, key, value) GAME.settings[key] = value end,
	Get = function() return true end }
InstallProfLost()

-- As 2.5.2 left an account: the welcome answered, its notes read up to 2.5.0, the old window used.
local function From252()
	return { guide = { welcomed = true, reset = "2026-11-16", newsSeen = "2.5.0", tours = {} }, chars = {}, lastLine = 197,
		win = { point = { "CENTER", 0, 0 } } }
end
DaylightRecipesDB = From252()

for _, file in ipairs({ "Guide.lua", "RecipesGuide.lua" }) do
	local chunk = assert(loadfile(ADDON_ROOT .. "/" .. file))
	chunk("DaylightRecipes", ns)
end
local Guide, PL = ns.Guide, ns.ProfLost
Fire("ADDON_LOADED", "DaylightRecipes")

-- The note (the welcome and What's New share one frame, made the first time one shows).
local function Note()
	for _, o in ipairs(ALL) do
		if rawget(o, "body") and rawget(o, "main") and rawget(o, "title") and rawget(o, "other") then return o end
	end
end
local function NoteUp()
	local n = Note()
	return n ~= nil and n:IsShown()
end
local function DialogUp()
	local d = _G.DaylightRecipesProfLost
	return d ~= nil and d:IsShown()
end
local function Login()
	Fire("PLAYER_LOGIN")
	GAME.on.Login()
end
-- Time played forward a step at a time, checking at each that the two are never up together.
local function Play(seconds, what)
	local steps = math.ceil(seconds / 0.5)
	for _ = 1, steps do
		T.run(seconds / steps)
		T.ok(not (NoteUp() and DialogUp()), "never two at once (" .. what .. ")")
	end
end
-- Everything of the last case put away, and its timers run out (the hand-off window looks for
-- its moment for five minutes).
local function Reset(db)
	T.run(400)
	if NoteUp() then Note():Hide() end
	if DialogUp() then _G.DaylightRecipesProfLost:Hide() end
	DaylightRecipesDB = db
	GAME.settings.plGuide, GAME.settings.plShop, GAME.settings.plTrainer = false, false, false
	GAME.settings.plTips, GAME.settings.plPrices, GAME.settings.plStep = false, false, false
end

T.case("M4: a player updating from 2.5.2 is told what changed", function()
	Reset(From252())
	Login()
	T.run(3.5)
	T.ok(not NoteUp(), "nothing in the first seconds")
	T.run(1)
	T.ok(NoteUp(), "four seconds in: the What's New note")
	local n = Note()
	T.eq(n.title:GetText(), "What's New in Glowey's Recipes", "its title")
	local body = n.body:GetText()
	T.ok(body:find("3.0.2", 1, true), "this release's entry")
	T.ok(body:find("A compact window: one column at the left of the screen", 1, true), "says why the window is small now")
	T.ok(body:find("Queue List and Guide List", 1, true) and body:find("Check Prices", 1, true), "what the strips carry from 2.6 to 2.8, in one line")
	T.ok(body:find("thin strip", 1, true), "the strips")
	T.ok(body:find("Tours no longer start by themselves", 1, true), "the tours")
	T.ok(body:find("Professionally Lost", 1, true), "the hand-off")
	T.ok(not body:find("2.5.0", 1, true), "and not the notes they read before")
	T.eq(DaylightRecipesDB.guide.newsSeen, "3.0.2", "read now: not shown again at the next login")
	n.main:Click()
	T.ok(not NoteUp(), "Okay closes it")
	Reset(DaylightRecipesDB)
	Login()
	T.run(30)
	T.ok(not NoteUp(), "the next login: no note")
end)

T.case("M5: What's New first, the hand-off window only after it is closed", function()
	Reset(From252())
	Login()
	Play(6, "after login")
	T.ok(NoteUp(), "the note is up")
	T.ok(not DialogUp(), "and the hand-off window is not")
	T.eq(DaylightGuides.DaylightRecipes, true, "the other Daylight plugins' guides wait for the note")
	Play(120, "two minutes with the note left open")
	T.ok(NoteUp() and not DialogUp(), "the hand-off window waits as long as the note is open")
	Note().main:Click()
	T.ok(not NoteUp(), "the note closed")
	Play(2.5, "after the note")
	T.ok(DialogUp(), "now the hand-off window opens")
	T.eq(DaylightGuides.DaylightRecipes, true, "and holds the shared mark while it is up")
	_G.DaylightRecipesProfLost.later:Click()
	T.eq(DaylightGuides.DaylightRecipes, nil, "closed: the mark is given up")
	T.eq(PL.Asked(), false, "Ask Me Later: asked again at the next login")
end)

T.case("M5: the hand-off window never opens over a note already up", function()
	Reset(From252())
	Login()
	T.run(5)
	-- (Whatever the note says: the options' What's New shows the latest notes when asked.)
	if NoteUp() then Note():Hide() end
	Guide.News(true)
	T.ok(NoteUp(), "a note is up")
	Play(60, "a note up through the hand-off window's moment")
	T.ok(not DialogUp(), "the hand-off window waits for it")
	Note().main:Click()
	Play(2.5, "after it")
	T.ok(DialogUp(), "and opens once it is closed")
end)

T.case("M5: both wait for Daylight UI's own guide, then come in order", function()
	Reset(From252())
	DaylightUIInstaller = NewObj("Frame", "DaylightUIInstaller")
	rawset(DaylightUIInstaller, "GetAlpha", function() return 1 end)
	local ok, err = pcall(function()
		Login()
		Play(40, "Daylight UI's guide up")
		T.ok(not NoteUp() and not DialogUp(), "nothing of ours over Daylight UI's guide")
		DaylightUIInstaller:Hide()
		Play(6, "its guide closed")
		T.ok(NoteUp(), "the note comes first")
		T.ok(not DialogUp(), "the hand-off window still waits")
		Play(30, "the note open")
		Note().main:Click()
		Play(2.5, "the note closed")
		T.ok(DialogUp(), "then the hand-off window")
	end)
	DaylightUIInstaller.shown = false
	if not ok then error(err, 0) end
end)

T.case("M5: another Daylight plugin's guide is waited for too", function()
	local db = From252()
	db.guide.newsSeen = "3.0.2"
	Reset(db)
	DaylightGuides.DaylightFishing = true
	local ok, err = pcall(function()
		Login()
		Play(40, "Glowey's Fishing's welcome up")
		T.ok(not DialogUp(), "the hand-off window waits for another plugin's guide")
		DaylightGuides.DaylightFishing = nil
		-- (Guide.lua looks again every 5 seconds while another guide is up, the window every 2.)
		Play(8, "it closed")
		T.ok(DialogUp(), "and opens after it")
	end)
	DaylightGuides.DaylightFishing = nil
	if not ok then error(err, 0) end
end)

T.case("nothing new to read: the hand-off window comes by itself, once answered never again", function()
	local db = From252()
	db.guide.newsSeen = "3.0.2"
	Reset(db)
	Login()
	Play(7.5, "before its moment")
	T.ok(not NoteUp() and not DialogUp(), "nothing in the first seconds")
	Play(1.5, "its moment")
	T.ok(DialogUp(), "eight seconds in: the hand-off window")
	_G.DaylightRecipesProfLost.apply:Click()
	T.eq(PL.Asked(), true, "Apply answers it")
	Reset(DaylightRecipesDB)
	Login()
	Play(60, "the next login")
	T.ok(not DialogUp(), "answered: not asked again")
end)

T.case("a new install: the welcome, and the hand-off window only once it is answered", function()
	Reset(nil)
	Fire("ADDON_LOADED", "DaylightRecipes")
	Login()
	Play(6, "after login")
	T.ok(NoteUp(), "the welcome")
	T.eq(Note().title:GetText(), "Welcome to Glowey's Recipes", "its title")
	Play(60, "the welcome left unanswered")
	T.ok(not DialogUp(), "the hand-off window waits for its answer")
	Note().other:Click()
	T.ok(not NoteUp(), "Keep My Window answers it")
	Play(2.5, "after the welcome")
	T.ok(DialogUp(), "then the hand-off window")
	T.eq(Guide.Running(), false, "and no tour started by itself")
end)

T.case("another question of ours up (the Docked Pane's, about Daylight UI's profit): the hand-off window waits for it", function()
	local db = From252()
	db.guide.newsSeen = "3.0.2"
	Reset(db)
	T.eq(PL.Due(), false, "before login nothing is to come")
	Login()
	T.eq(PL.Due(), true, "from login on the hand-off window is to come: that question waits for it (test_profit.lua)")
	-- (That question is up all the same, asked at a login before this one's window was due, say:
	-- it holds the plugin's mark, as Pane.lua does while its box is shown.)
	Guide.Hold("profit", true)
	T.eq(Guide.Busy(), true, "a held window of ours counts for Guide.Busy")
	Play(60, "the profit question up")
	T.ok(not DialogUp(), "the hand-off window does not open over it")
	T.eq(PL.Due(), true, "it is still to come")
	Guide.Hold("profit", false)
	Play(3, "the question answered")
	T.ok(DialogUp(), "and opens once it is answered")
	T.eq(PL.Due(), false, "up now: no longer to come (it holds the mark itself while it shows)")
	T.eq(Guide.Busy(), true, "and Guide.Busy holds while it is up, so the other question waits in turn")
	_G.DaylightRecipesProfLost.later:Click()
	T.eq(Guide.Busy(), false, "closed: nothing is up")
	-- Not installed, or answered: never to come.
	Reset({ guide = { welcomed = true, newsSeen = "3.0.2", tours = {} }, proflost = { asked = true } })
	Login()
	T.eq(PL.Due(), false, "answered at an earlier login: not to come")
end)

Reset({ guide = { welcomed = true, newsSeen = "3.0.2", tours = {} }, proflost = { asked = true } })
return T.done()
