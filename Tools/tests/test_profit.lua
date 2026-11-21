-- The Docked Pane's cost-and-profit hand-off to Daylight UI's profession window (carried over from
-- the released line): the decision (Pane.lua: ProfitCould / ProfitApplies / ProfitHanded), the
-- question asked once and what it waits for, in the face lift's order at login (after the welcome
-- or What's New and after Professionally Lost's window, never over either), and what the Recipe
-- tab draws with and without it (Pages.lua), on the plugin's real Pane.lua and Pages.lua over a
-- mocked game. (As the released copy's own decision test, with the face lift's waiting added.)
-- luacheck: globals GAME NS ADDON_ROOT DaylightRecipesDB DaylightUI DaylightGuides DaylightUIAsk DaylightUIInstaller
-- luacheck: globals C_AddOns StaticPopupDialogs StaticPopup_Show InCombatLockdown wipe GameTooltip
-- luacheck: read globals T NewObj
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Pane.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Pane.lua not found")
local function read(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	return src
end

-- Anything: a value that can be indexed and called without error (what the two files touch at
-- load and these cases don't look at). It is truthy, so nothing a case decides on is left to it.
local Any
Any = setmetatable({}, { __index = function() return Any end, __call = function() return Any end })

local W             -- the world of one case
local popups = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
GameTooltip = Any
StaticPopupDialogs = {}
function StaticPopup_Show(name) popups[#popups + 1] = name end
function InCombatLockdown() return W.combat end
C_AddOns.GetAddOnMetadata = function(addon, field)
	if W.versionRaises then error("boom") end
	if addon == "DaylightUI" and field == "Version" then return W.version end
end

local ns, Pane, Pages, S
local holds = {}
local function world()
	W = { version = "2.1.2", combat = false, settings = {}, dui = { profit = true }, module = true, set = 0,
		welcoming = false, guideBusy = false, due = false }
	popups, holds = {}, {}
	StaticPopupDialogs = {}
	DaylightGuides, DaylightUIAsk, DaylightUIInstaller = nil, nil, nil
	DaylightRecipesDB = {}
	DaylightUI = { AuctionPrices = { Item = function() end, CUT = 0.05 },
		Set = function(_, _, key, value)
			W.settings[key] = value
			W.set = W.set + 1
		end }
	ns = { ok = true, state = { mode = "dui", recipe = 1 }, L = setmetatable({}, { __index = function(_, k) return k end }) }
	ns.Plural = function(_, one) return one end
	ns.API = setmetatable({
		IsModuleEnabled = function(name) return name == "Professions" and W.module end,
		GetSetting = function(scope, path)
			if W.settingRaises then error("boom") end
			if scope == "Professions" then
				if not W.module then return nil end
				return W.dui[path]
			end
			return W.settings[path]
		end }, { __index = function() return Any end })
	ns.me = Any
	ns.Get = function(path)
		local v = W.settings[path]
		if v ~= nil then return v end
		if path == "duiProfit" then return true end     -- (Core.lua's default)
		return nil
	end
	-- The face lift's Guide.lua, as much as the question asks of it: Busy (the welcome or What's
	-- New not decided or still up, a tour, a window of ours held up), Welcoming, Hold.
	ns.Guide = {
		Busy = function() return W.guideBusy or next(holds) ~= nil end,
		Welcoming = function() return W.welcoming end,
		Hold = function(key, on) holds[key] = on and true or nil end,
		Offer = function() end,
	}
	-- Professionally Lost's hand-off: whether its first-load window is still to come at this login.
	ns.ProfLost = { Due = function() return W.due end, Handed = function() return false end }
	ns.Doc = setmetatable({ Color = function() return 1, 1, 1 end, Hex = function() return "" end,
		ItemName = function(id) return "Item" .. id, "icon" end, ItemTip = function() return function() end end,
		SpellTip = function() return function() end end, Pct = function(v) return tostring(v) end,
		RecipeName = function(id) return "Recipe" .. id end }, { __index = function() return Any end })
	ns.Calc = setmetatable({ Money = function(c) return math.floor(c + 0.5) .. "c" end, HasAH = function() return true end,
		SkillUps = function() return 1 end }, { __index = function() return Any end })
	setmetatable(ns, { __index = function() return Any end })
	assert(loadstring(read("Pages.lua"), "@Pages.lua"))("DaylightRecipes", ns)
	assert(loadstring(read("Pane.lua"), "@Pane.lua"))("DaylightRecipes", ns)
	Pane, Pages, S = ns.Pane, ns.Pages, ns.state
end
-- The question's timers played forward (it looks again every 3 seconds while something is up).
local function run(seconds) T.run(seconds or 1.5) end
local function asked() return #popups end
local function question() return StaticPopupDialogs.DAYLIGHTRECIPES_DUI_PROFIT end

-- A doc that keeps what was drawn.
local function NewDoc()
	local d = { out = {} }
	function d:Heading(t) self.out[#self.out + 1] = "H:" .. t end
	function d:Line(t) self.out[#self.out + 1] = "L:" .. t end
	function d:Row(o)
		self.out[#self.out + 1] = "R:" .. tostring(o.left) .. "=" .. tostring(o.right or "") .. (o.sub and ("|" .. o.sub) or "")
	end
	function d.Gap() end
	function d.Bar() return Any end
	function d.Buttons() end
	return d
end
local function Has(d, text)
	for _, l in ipairs(d.out) do
		if l:find(text, 1, true) then return true end
	end
	return false
end
local function Headings(d)
	local n = 0
	for _, l in ipairs(d.out) do
		if l:sub(1, 2) == "H:" then n = n + 1 end
	end
	return n
end

-- ---- when it applies ------------------------------------------------------------------------------
T.case("applies: only beside Daylight UI's own window, 2.1.2 or later, with its profit showing", function()
	world()
	T.ok(Pane.ProfitApplies() == true and Pane.ProfitHanded() == true, "the pane beside Daylight UI 2.1.2's window, prices published, its Profit on")
	for _, mode in ipairs({ "mogul", "win", false }) do
		S.mode = mode or nil
		T.ok(Pane.ProfitApplies() == false and Pane.ProfitHanded() == false, "not beside " .. tostring(mode) .. " (our own window, DaylightMogul's, or none)")
	end
	S.mode = "dui"
	for _, v in ipairs({ { "2.1.1", false }, { "2.1", false }, { "2.0", false }, { "1.9.6", false }, { "2.1.2", true },
		{ "2.1.3", true }, { "2.2", true }, { "2.2.0", true }, { "3.0", true }, { "", false }, { "dev", false } }) do
		W.version = v[1]
		T.eq(Pane.ProfitApplies(), v[2], ("Daylight UI %q"):format(v[1]))
	end
	W.version = nil
	T.eq(Pane.ProfitApplies(), false, "no version to read: does not apply")
	W.version, W.versionRaises = "2.1.2", true
	T.eq(Pane.ProfitApplies(), false, "the version call raising: does not apply, and no error")
	W.versionRaises = false
	DaylightUI.AuctionPrices = nil
	T.ok(not Pane.ProfitApplies() and not Pane.ProfitCould(), "no price bridge (its Auction House off, or DaylightMogul's): does not apply")
	DaylightUI.AuctionPrices = {}
	T.ok(not Pane.ProfitApplies(), "a bridge without Item: does not apply")
	DaylightUI.AuctionPrices = { Item = function() end }
	W.dui.profit = false
	T.ok(not Pane.ProfitApplies() and Pane.ProfitCould(), "Daylight UI's own Profit switched off: ours shows; but it could")
	W.dui.profit = nil
	T.ok(Pane.ProfitApplies(), "its Profit never set (on by default): applies")
	W.dui.profit, W.module = true, false
	T.ok(not Pane.ProfitApplies() and not Pane.ProfitCould(), "its Professions module off: does not apply")
	W.module, DaylightUI.craftMogul = true, true
	T.ok(not Pane.ProfitApplies(), "DaylightMogul runs the professions: does not apply")
	DaylightUI.craftMogul = nil
	W.settingRaises = true
	T.ok(not Pane.ProfitApplies(), "the setting read raising: does not apply, and no error")
	W.settingRaises = false
	W.settings.duiProfit = false
	T.ok(Pane.ProfitApplies() and not Pane.ProfitHanded(), "Keep Both saved: applies, not handed")
	W.settings.duiProfit = true
	T.ok(Pane.ProfitHanded(), "Use Daylight UI's saved: handed")
	W.settings.duiProfit = nil
	T.ok(Pane.ProfitHanded(), "no answer yet: handed (Daylight UI's by default)")
end)

-- ---- the question ---------------------------------------------------------------------------------
T.case("asked once, with both answers", function()
	world()
	Pane.AskProfit()
	T.eq(asked(), 0, "not in the moment the pane draws")
	run()
	T.eq(asked(), 1, "asked the first time it applies")
	T.eq(popups[1], "DAYLIGHTRECIPES_DUI_PROFIT", "through the game's question box")
	T.eq(DaylightRecipesDB.duiProfitAsked, true, "and marked asked, with the account")
	local q = question()
	T.eq(q.button1, "Use Daylight UI's", "its first button")
	T.eq(q.button2, "Keep Both", "its second")
	T.ok(q.timeout == 0 and q.hideOnEscape == false, "no timeout, not closed by Escape: an answer, not a dismissal")
	q.OnAccept()
	T.eq(W.settings.duiProfit, true, "Use Daylight UI's: saved on")
	q.OnCancel(nil, nil, "clicked")
	T.eq(W.settings.duiProfit, false, "Keep Both: saved off")
	W.set = 0
	q.OnCancel(nil, nil, "override")
	T.eq(W.set, 0, "closed by something else: nothing saved")
	Pane.AskProfit()
	run(10)
	T.eq(asked(), 1, "never asked twice")
	-- Not where it does not apply.
	world()
	S.mode = "win"
	Pane.AskProfit()
	run(10)
	T.ok(asked() == 0 and DaylightRecipesDB.duiProfitAsked == nil, "not asked in our own window")
	world()
	W.version = "2.1.1"
	Pane.AskProfit()
	run(10)
	T.eq(asked(), 0, "not asked on Daylight UI 2.1.1")
	world()
	Pane.AskProfit()
	S.mode = nil
	run(5)
	T.ok(asked() == 0 and DaylightRecipesDB.duiProfitAsked == nil, "the window closed before its turn: not asked, not marked")
	S.mode = "dui"
	Pane.AskProfit()
	run()
	T.eq(asked(), 1, "asked the next time it applies")
end)

T.case("it waits its turn: a fight, the welcome and What's New, tours, Daylight UI's dialogs", function()
	local shown = { IsShown = function() return true end, GetAlpha = function() return 1 end }
	for _, c in ipairs({
		{ "in a fight", function() W.combat = true end, function() W.combat = false end },
		{ "while the welcome is unanswered", function() W.welcoming = true end, function() W.welcoming = false end },
		{ "while the welcome or What's New has not had its turn, is up, or a tour runs (Guide.Busy)",
			function() W.guideBusy = true end, function() W.guideBusy = false end },
		{ "while another Daylight plugin's note or tour is up", function() DaylightGuides = { DaylightFishing = true } end,
			function() DaylightGuides = {} end },
		{ "while Daylight UI asks something", function() DaylightUIAsk = shown end, function() DaylightUIAsk = nil end },
		{ "while Daylight UI's setup guide is up", function() DaylightUIInstaller = shown end, function() DaylightUIInstaller = nil end },
	}) do
		world()
		c[2]()
		Pane.AskProfit()
		run(20)
		T.ok(asked() == 0 and DaylightRecipesDB.duiProfitAsked == nil, "not asked " .. c[1])
		c[3]()
		run(4)
		T.eq(asked(), 1, "asked once that is over (" .. c[1] .. ")")
	end
	world()
	DaylightUIAsk = { IsShown = function() return true end, GetAlpha = function() return 0 end }
	Pane.AskProfit()
	run()
	T.eq(asked(), 1, "a faded-out Daylight UI window doesn't hold it up")
	-- Drawn again and again while it waits: one wait, one question.
	world()
	W.combat = true
	for _ = 1, 20 do
		Pane.AskProfit()
		run(0.5)
	end
	W.combat = false
	run(4)
	T.eq(asked(), 1, "the pane drawn twenty times while waiting: asked once")
	-- Held up for minutes: given up for now, asked another time.
	world()
	W.combat = true
	Pane.AskProfit()
	run(400)
	W.combat = false
	run(10)
	T.ok(asked() == 0 and DaylightRecipesDB.duiProfitAsked == nil, "held up for minutes: given up for now, not marked asked")
	Pane.AskProfit()
	run()
	T.eq(asked(), 1, "and asked the next time the pane draws")
end)

T.case("never over Professionally Lost's window, nor it over this", function()
	-- Its window is still to come at this login (ProfLost.Due): ours waits for it.
	world()
	W.due = true
	Pane.AskProfit()
	run(20)
	T.eq(asked(), 0, "not asked while Professionally Lost's window is still to come")
	-- It opens: it holds our mark (Guide.Hold, as ProfLost.lua's window does on show).
	W.due = false
	ns.Guide.Hold("proflost", true)
	run(20)
	T.eq(asked(), 0, "nor while that window is up")
	-- It is answered and closed.
	ns.Guide.Hold("proflost", false)
	run(4)
	T.eq(asked(), 1, "asked once it is closed")
	-- While this question is up it holds the mark itself, so that window waits in turn
	-- (Guide.Busy counts a held window of ours: test_login.lua plays that on the real Guide.lua).
	T.eq(holds.profit, true, "the question up: it holds our mark")
	T.eq(ns.Guide.Busy(), true, "so Guide.Busy holds, which Professionally Lost's window waits on")
	question().OnAccept()
	question().OnHide()
	T.eq(holds.profit, nil, "answered: the mark is let go")
	T.eq(ns.Guide.Busy(), false, "and that window may come")
	-- Put away without an answer (the game closing it): let go too.
	world()
	Pane.AskProfit()
	run()
	question().OnHide()
	T.eq(holds.profit, nil, "put away without an answer: the mark is let go all the same")
end)

-- ---- what the Recipe tab draws --------------------------------------------------------------------
T.case("the Recipe tab with and without the hand-off", function()
	world()
	ns.Calc.Cost = function()
		return { rows = { { itemID = 1, count = 2, unit = 10, total = 20, kind = "ah" },
			{ itemID = 2, count = 1, unit = 5, total = 5, kind = "vendor", who = "Vendy" } }, total = 25, complete = true }
	end
	local WORTH = { itemID = 9, count = 1, routes = {
		{ label = "Auction House", text = "Auction House", value = 95, profit = 70 },
		{ label = "Vendor", text = "Vendor", value = 12, profit = -13 },
		{ label = "Disenchant", text = "Disenchant", value = 30, profit = 5 } },
		de = { mats = { { itemID = 3, lo = 1, hi = 2, chance = 0.5, value = 30 } }, value = 30, complete = true } }
	ns.Calc.Worth = function() return WORTH end
	local both, handed = NewDoc(), NewDoc()
	Pages.Cost(both, 1, 0.5)
	Pages.Worth(both, 1)
	Pages.Cost(handed, 1, 0.5, { handed = true })
	Pages.Worth(handed, 1, true)
	T.ok(Has(both, "R:Total=25c") and Has(both, "R:Auction House=95c"), "both: the Total row and the Auction House row")
	T.ok(not Has(handed, "R:Total"), "handed: no Total row")
	T.ok(Has(handed, "R:Item1") and Has(handed, "=20c") and Has(handed, "R:Item2=5c"), "handed: each material still there with its price")
	T.ok(Has(handed, "R:Per Skill Point=50c"), "handed: the cost per skill point stays")
	T.ok(not Has(handed, "R:Auction House"), "handed: no Auction House row")
	T.ok(Has(handed, "R:Vendor=12c") and Has(handed, "R:Disenchant=30c"), "handed: the vendor's and disenchanting's value stay")
	T.ok(Has(handed, "R:Item3"), "handed: what it disenchants into stays")
	T.ok(Has(handed, "H:Materials") and Has(handed, "H:Value"), "handed: both headings have rows under them")
	-- Only the Auction House had a value: no empty Value heading.
	WORTH = { itemID = 9, count = 1, routes = { { label = "Auction House", text = "Auction House", value = 95, profit = 70 } } }
	both, handed = NewDoc(), NewDoc()
	Pages.Worth(both, 1)
	Pages.Worth(handed, 1, true)
	T.ok(Has(both, "H:Value"), "only the Auction House had a value: both shows the section")
	T.eq(#handed.out, 0, "handed draws none of it: no heading left with nothing under it")
	-- An item that binds.
	WORTH = { itemID = 9, count = 1, bound = true, routes = { { label = "Vendor", text = "Vendor", value = 12, profit = 2 } } }
	both, handed = NewDoc(), NewDoc()
	Pages.Worth(both, 1)
	Pages.Worth(handed, 1, true)
	T.ok(Has(both, "no Auction House") and not Has(handed, "no Auction House") and Has(handed, "R:Vendor=12c"),
		"an item that binds: the Auction House note only where the Auction House row could be")
	-- An enchant: nothing made.
	WORTH = nil
	both, handed = NewDoc(), NewDoc()
	Pages.Worth(both, 1)
	Pages.Worth(handed, 1, true)
	T.ok(Has(both, "It makes no item to sell.") and Has(handed, "It makes no item to sell."), "an enchant (nothing made): the same line either way")
	-- A material with no price (also what Professionally Lost's prices, handed over, can leave):
	-- the note on the short total goes with the total; the material's row stays; no orphaned heading.
	ns.Calc.Cost = function() return { rows = { { itemID = 1, count = 2 } }, total = 0, complete = false } end
	both, handed = NewDoc(), NewDoc()
	Pages.Cost(both, 1, 0.5)
	Pages.Cost(handed, 1, 0.5, { handed = true })
	T.ok(Has(both, "the total is short") and not Has(handed, "total"), "no price for a material: the note goes with the total")
	T.ok(Has(handed, "R:Item1"), "its row stays under the Materials heading")
	T.eq(Headings(handed), 1, "one heading, with its row: none orphaned")
	ns.Calc.Cost = function() return { rows = {}, total = 0, complete = true } end
	handed = NewDoc()
	Pages.Cost(handed, 1, 0.5, { handed = true })
	T.ok(Has(handed, "It takes no materials."), "no materials: as before")
	-- Pages.Recipe passes it on; the compact window's own detail never asks for it.
	ns.Calc.Cost = function() return { rows = { { itemID = 1, count = 2, unit = 10, total = 20, kind = "ah" } }, total = 20, complete = true } end
	WORTH = { itemID = 9, count = 1, routes = { { label = "Auction House", text = "Auction House", value = 95, profit = 70 } } }
	Pages.Skill = function() return 0.5 end
	local a, b = NewDoc(), NewDoc()
	Pages.Recipe(a, false)
	Pages.Recipe(b, true)
	T.ok(Has(a, "R:Total=20c") and Has(a, "R:Auction House"), "Pages.Recipe without: the total and the Auction House row")
	T.ok(not Has(b, "R:Total") and not Has(b, "Auction House=") and Has(b, "R:Per Skill Point"), "Pages.Recipe with: neither; the cost per point stays")
	local c = NewDoc()
	Pages.Recipe(c)
	T.ok(Has(c, "R:Total=20c") and Has(c, "R:Auction House"), "called as the window calls it (no word about the hand-off): everything shows")
end)

return T.done()
