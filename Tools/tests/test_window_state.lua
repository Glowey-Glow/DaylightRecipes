-- The window's rules (WindowState.lua): its three states and what is remembered, which tabs show
-- for each hand-off answer, and the layout sums that guarantee no label is cut at the designed
-- maxima. WindowState.lua is pure arithmetic, so this proves the rules, not the drawing: what only
-- the game can show is in design/in-game-check.md under "Window".
-- Runs in Tools/tests/run.py (it loads WindowState.lua itself when the runner hasn't), and alone:
-- any Lua 5.1 with the worktree as the working directory.
local ns = rawget(_G, "NS") or {}
if not ns.WinState then
	local chunk
	for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
		chunk = loadfile(root .. "/WindowState.lua")
		if chunk then break end
	end
	assert(chunk, "WindowState.lua not found: run from the plugin's folder")
	chunk("DaylightRecipes", ns)
end
local State = ns.WinState

local T = rawget(_G, "T")
if not T then
	T = { n = 0 }
	function T.ok(cond, what)
		T.n = T.n + 1
		if not cond then error("FAILED: " .. tostring(what), 2) end
	end
	function T.eq(got, want, what)
		T.n = T.n + 1
		if got ~= want then error(("FAILED: %s (got %s, wanted %s)"):format(tostring(what), tostring(got), tostring(want)), 2) end
	end
	function T.done() return ("ok, %d checks"):format(T.n) end
end

-- ---- the design's sizes ----------------------------------------------------------------------
T.eq(State.W, 420, "the column is 420")
T.eq(State.H, 560, "the default height is 560")
T.eq(State.DETAIL, 360, "the detail column is 360")
T.eq(State.HEADER + State.FOOT, 80, "rolled up is the header and the craft bar: 80")

-- ---- what is remembered: an existing player gets the compact default once --------------------
do
	local old = { point = { "TOPLEFT", "TOPLEFT", 300, -200 }, folded = { ["12"] = true }, canMake = true }
	T.ok(State.Migrate(old) == true, "a state saved for the old window is migrated, and says so")
	T.eq(old.point, nil, "the old window's place is dropped")
	T.eq(old.spot, nil, "no place: the default at the left of the screen")
	T.eq(old.rolled, nil, "not rolled up")
	T.eq(next(old.details), nil, "no details open")
	T.eq(old.v, State.VERSION, "marked as this layout's")
	T.ok(old.folded["12"] == true and old.canMake == true, "the list's own choices are kept")
	T.eq(State.Mode(old, "recipes", false, false), "compact", "an existing player's first open is compact")
	local w, h = State.Size(State.Mode(old, "recipes", false, false), State.W, State.H, State.FOOT)
	T.ok(w == 420 and h == 560, "420 x 560")
	-- It happens once: what the player does next is kept.
	old.spot = { 40, 900 }
	State.SetDetails(old, "recipes", true)
	State.SetRolled(old, true)
	T.ok(State.Migrate(old) == false, "the second time nothing is dropped")
	T.ok(old.spot[1] == 40 and old.details.recipes == true and old.rolled == true, "state kept across sessions")

	local fresh = {}
	T.ok(State.Migrate(fresh) == false, "a new install has nothing to say sorry for")
	T.eq(fresh.v, State.VERSION, "and is this layout's")
	T.ok(type(fresh.folded) == "table" and type(fresh.details) == "table", "its tables are there")
	T.ok(State.Migrate(nil) == false, "no table: nothing")
end

-- ---- the state machine: compact / expanded / rolled up ---------------------------------------
do
	local win = {}
	State.Migrate(win)
	T.eq(State.Mode(win, "recipes", false, false), "compact", "the default is compact")
	T.eq(State.Mode(win, "recipes", false, true), "expanded", "Open Details by Default opens them")
	State.SetDetails(win, "recipes", true)
	T.eq(State.Mode(win, "recipes", false, false), "expanded", "details open on Recipes")
	T.eq(State.Mode(win, "guide", false, false), "compact", "open or closed is remembered per tab")
	State.SetDetails(win, "guide", false)
	T.eq(State.Mode(win, "guide", false, true), "compact", "a tab closed by the player stays closed over the default")
	T.eq(State.Mode(win, "missing", false, true), "expanded", "a tab never touched follows the default")
	-- Rolled up wins, and the details are back when it unrolls.
	State.SetRolled(win, true)
	for _, tab in ipairs(State.TAB_KEYS) do
		T.eq(State.Mode(win, tab, false, true), "rolled", "rolled up on " .. tab)
	end
	T.eq(State.Mode(win, "recipes", true, true), "rolled", "rolled up on an alt's page too")
	State.SetRolled(win, false)
	T.eq(State.Mode(win, "recipes", false, false), "expanded", "unrolled: the details as they were left")
	-- An alt's recipes, a gathering page, the camping page: nothing to detail.
	T.eq(State.Mode(win, "recipes", true, true), "compact", "no detail column on an alt's or a gathering page")
	T.ok(not State.HasDetails("recipes", true), "HasDetails is false there")
	T.ok(not State.HasDetails("nonsense", false), "and for a tab that isn't one")
	for _, tab in ipairs(State.TAB_KEYS) do T.ok(State.HasDetails(tab, false), "details on " .. tab) end

	-- The three sizes.
	local w, h = State.Size("compact", 420, 560, 44)
	T.ok(w == 420 and h == 560, "compact is 420 x 560")
	w, h = State.Size("expanded", 420, 560, 44)
	T.ok(w == 780 and h == 560, "expanded is 780 x 560")
	w, h = State.Size("rolled", 420, 560, 44)
	T.ok(w == 420 and h == 80, "rolled up is 420 x 80")
	w, h = State.Size("rolled", 448, 700, 44 + 46)
	T.ok(w == 448 and h == 126, "rolled up with an enchant's item row is the header and that bar")
	w, h = State.Size("expanded", 476, 640, 44)
	T.ok(w == 836 and h == 640, "expanded follows the column and the height")

	-- The height: 400 to 720, and never taller than the screen.
	T.eq(State.ClampHeight(nil), 560, "no height: the default")
	T.eq(State.ClampHeight(100), 400, "at least 400")
	T.eq(State.ClampHeight(2000), 720, "at most 720")
	T.eq(State.ClampHeight(613.4), 613, "whole units")
	T.eq(State.ClampHeight(720, 600), 600, "never taller than the screen")
	T.eq(State.ClampHeight(720, 300), 400, "but never under 400")

	-- The place: the header stays on screen.
	local x, y = State.ClampSpot(-50, 5000, 420, 1920, 1080)
	T.ok(x == 0 and y == 1080, "a place off the top-left comes back on")
	x, y = State.ClampSpot(5000, 10, 420, 1920, 1080)
	T.ok(x == 1500 and y == State.HEADER, "a place off the bottom-right comes back on, header showing")
	x, y = State.ClampSpot(16, 964, 420, 1920, 1080)
	T.ok(x == 16 and y == 964, "the default place is left alone")
end

-- ---- tabs for each hand-off answer -----------------------------------------------------------
do
	local all = State.Tabs(false)
	T.eq(table.concat(all, " "), "recipes guide materials queue missing", "not handed off: all five, in order")
	local handed = State.Tabs(true)
	T.eq(table.concat(handed, " "), "recipes queue missing", "handed off: Leveling Guide and Materials are left out")
	T.eq(State.TabFor("guide", true), "recipes", "the Leveling Guide tab gives way to Recipes while handed off")
	T.eq(State.TabFor("materials", true), "recipes", "so does Materials")
	T.eq(State.TabFor("queue", true), "queue", "Queue stays")
	T.eq(State.TabFor("missing", true), "missing", "Missing stays")
	T.eq(State.TabFor("guide", false), "guide", "and they are back the moment the answer changes")
	T.eq(State.TabFor("materials", false), "materials", "Materials too")
	T.eq(State.TabFor("nonsense", false), "recipes", "an unknown tab is Recipes")

	-- Through the real ProfLost.lua when the runner loaded it (Tools/tests/mocks.lua's stand-in):
	-- the window asks Handed("guide", line) for the open profession, nothing else.
	local PL, install, game = ns.ProfLost, rawget(_G, "InstallProfLost"), rawget(_G, "GAME")
	if PL and PL.Handed and install and game then
		T.eq(table.concat(State.Tabs(PL.Handed("guide", 197)), " "), "recipes guide materials queue missing",
			"Professionally Lost not loaded: all five")
		install({ guides = { 197 }, step = { [197] = 3852 } })
		T.eq(#State.Tabs(PL.Handed("guide", 197)), 5, "loaded but the player hasn't handed the guide off: all five")
		game.settings.plGuide = true
		T.eq(table.concat(State.Tabs(PL.Handed("guide", 197)), " "), "recipes queue missing",
			"handed off, and it has a Tailoring guide: three tabs")
		T.eq(#State.Tabs(PL.Handed("guide", 186)), 5, "a profession it has no guide for keeps all five")
		T.eq(PL.Handed("step", 197), false, "the step isn't lit until that row is on")
		game.settings.plStep = true
		T.ok(PL.Handed("step", 197) == true and PL.NextStepSpell(197) == 3852, "its step's recipe is the one to mark")
		T.eq(PL.NextStepSpell(186), nil, "none for a profession with no step")
		game.settings.plGuide = false
		T.eq(#State.Tabs(PL.Handed("guide", 197)), 5, "put back: all five again")
		T.eq(PL.Handed("step", 197), false, "and nothing of its is lit (the step follows the guide)")
	end
end

-- ---- the tab row: no label cut -----------------------------------------------------------------
do
	-- No two tabs of a row overlap, every tab is inside the column, every tab is its text plus
	-- its padding (so the text is never squeezed).
	local function sound(widths, layout, what)
		T.ok(State.TabsFit(layout), what .. ": every tab inside the column")
		T.ok(layout.pad >= State.TAB_MIN_PAD and layout.pad <= State.TAB_PAD, what .. ": padding within its limits")
		for i, t in ipairs(layout.tabs) do
			T.ok(t.w >= math.ceil(widths[i]) + 2 * State.TAB_MIN_PAD, what .. ": tab " .. i .. " holds its whole label")
			local prev = layout.tabs[i - 1]
			if prev and prev.row == t.row then
				T.ok(t.x >= prev.x + prev.w + State.TAB_GAP, what .. ": tab " .. i .. " clear of the one before")
			end
			T.ok(t.row >= 1 and t.row <= layout.rows, what .. ": tab " .. i .. " on a row that exists")
		end
	end

	-- The designed maxima: the five labels in each of the seven languages, with the queue at its
	-- longest ("(99)"), at the widths the design measured with: 6.4 px a Latin letter at size 12,
	-- 7.2 a Cyrillic one, 12 a Hangul or Han one (design\facelift.md 3.1 "Widths", section 8 item 7).
	-- These are estimates a letter, generous on purpose: they prove the sums hold with room to
	-- spare, not what the game draws. Measured in Daylight UI's default font the tab row asks 420
	-- in English, German, French, Spanish, Korean and Chinese and about 440 in Russian (the audit,
	-- design\audit-facelift.md L24); design\in-game-check.md expects those, not these.
	local LATIN, CYR, WIDE = 6.4, 7.2, 12
	local function px(n, per) return n * per end
	local sets = {
		enUS = { px(7, LATIN), px(14, LATIN), px(9, LATIN), px(10, LATIN), px(7, LATIN) },      -- Recipes, Leveling Guide, Materials, Queue (99), Missing
		deDE = { px(7, LATIN), px(9, LATIN), px(11, LATIN), px(18, LATIN), px(7, LATIN) },      -- Rezepte, Leitfaden, Materialien, Warteschlange (99), Fehlend
		frFR = { px(8, LATIN), px(5, LATIN), px(10, LATIN), px(9, LATIN), px(10, LATIN) },      -- Recettes, Guide, Composants, File (99), Manquantes
		esES = { px(7, LATIN), px(14, LATIN), px(10, LATIN), px(9, LATIN), px(6, LATIN) },      -- Recetas, Guía de subida, Materiales, Cola (99), Faltan
		ruRU = { px(7, CYR), px(11, CYR), px(9, CYR), px(12, CYR), px(11, CYR) },               -- Рецепты, Руководство, Материалы, Очередь (99), Неизученные
		koKR = { px(3, WIDE), px(5, WIDE) + 4, px(2, WIDE), px(3, WIDE) + 30, px(3, WIDE) },    -- 제조법, 레벨업 안내, 재료, 대기열 (99), 미습득
		zhCN = { px(2, WIDE), px(4, WIDE), px(2, WIDE), px(2, WIDE) + 30, px(2, WIDE) },        -- 配方, 升级指南, 材料, 队列 (99), 缺少
	}
	local widest = 0
	for lang, widths in pairs(sets) do
		local layout = State.TabLayout(widths)
		sound(widths, layout, lang)
		T.eq(layout.rows, 1, lang .. ": one row at the designed maxima")
		T.eq(layout.pad, State.TAB_PAD, lang .. ": at the design's padding")
		T.ok(layout.col >= State.W and layout.col <= State.MAX_W, lang .. ": the column is 420 to 520")
		widest = math.max(widest, layout.col)
	end
	-- English: 420 with a one-digit queue ("Queue (3)", the design's own sum), 4 px more with two.
	T.ok(State.TabLayout({ px(7, LATIN), px(14, LATIN), px(9, LATIN), px(9, LATIN), px(7, LATIN) }).col == 420,
		"English fits the 420 column")
	T.ok(State.TabLayout(sets.enUS).col <= 424, "and is 424 at most with a two-digit queue")
	T.ok(widest <= 500, "the widest designed language (Russian) stays under 500: " .. widest)

	-- Handed off: three tabs and "Open Professionally Lost" (24 letters) still fit 420 in English.
	local handed = { px(7, LATIN), px(10, LATIN), px(7, LATIN), px(24, LATIN) }
	local layout = State.TabLayout(handed)
	sound(handed, layout, "handed off")
	T.ok(layout.col == 420 and layout.rows == 1, "three tabs and the Professionally Lost button fit 420")

	-- Past the maxima: the padding gives first, then a second row; never a cut label.
	local long = { 120, 110, 100, 76, 34 }          -- 440 of text: 520 needs the padding at 4 a side
	layout = State.TabLayout(long)
	sound(long, layout, "long labels")
	T.ok(layout.rows == 1 and layout.pad < State.TAB_PAD and layout.col <= State.MAX_W, "long labels: tighter padding, still one row")
	local longer = { 150, 150, 130, 120, 110 }
	layout = State.TabLayout(longer)
	sound(longer, layout, "longer labels")
	T.ok(layout.rows == 2 and layout.col <= State.MAX_W, "longer labels: a second row inside 520")
	T.eq(layout.pad, State.TAB_PAD, "the second row is back at the design's padding")
	local huge = { 600 }
	layout = State.TabLayout(huge)
	sound(huge, layout, "one huge label")
	T.ok(layout.col >= 600 + 2 * State.TAB_PAD, "a label wider than 520 widens the column rather than lose a letter")
	layout = State.TabLayout({})
	T.ok(layout.col == 420 and #layout.tabs == 0, "no tabs (an alt's page): the 420 column")

	-- Any widths at all (a fixed pseudo-random run): always sound.
	local seed = 7
	local function rnd(lo, hi)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return lo + seed % (hi - lo + 1)
	end
	for run = 1, 300 do
		local widths = {}
		for i = 1, rnd(1, 6) do widths[i] = rnd(10, 260) + rnd(0, 9) / 10 end
		layout = State.TabLayout(widths)
		sound(widths, layout, "run " .. run)
	end
end

-- ---- the craft bar and the header --------------------------------------------------------------
do
	local least = State.LEAST
	local w = { make = least.make, max = least.max, plus = least.plus, count = least.count, minus = least.minus, queue = least.queue }
	T.ok(State.CraftBarNeed(w) <= 420, "the design's buttons fit one row of 420: " .. State.CraftBarNeed(w))
	T.ok(not State.CraftBarTwoRows(w, 420), "so the bar is one row")
	-- The designed maximum: each button's words up to half again as wide still fit one row at 520.
	local wide = { make = 130, max = 84, plus = 26, count = 46, minus = 26, queue = 110 }
	T.ok(not State.CraftBarTwoRows(wide, 520), "longer words still fit one row of a 520 column")
	-- Past it the count and Queue go on a row of their own, and each row fits the column.
	local long = { make = 170, max = 110, plus = 26, count = 46, minus = 26, queue = 150 }
	T.ok(State.CraftBarTwoRows(long, 420), "words too long for one row: two rows")
	local bottom, top = State.CraftBarRowWidths(long)
	T.ok(bottom <= 420 and top <= 420, "and each row fits 420: " .. bottom .. ", " .. top)

	-- The header: four buttons leave 246 for the name and skill at 420.
	T.eq(State.HeaderRoom(420, 4), 246, "the header's room at 420")
	T.eq(State.NameSize({ title = 90, head = 76, body = 66 }, 246), "title", "Tailoring is drawn at 18")
	T.eq(State.NameSize({ title = 280, head = 232, body = 201 }, 246), "head", "a long name steps down to 15")
	T.eq(State.NameSize({ title = 330, head = 275, body = 238 }, 246), "body", "a longer one to 13")
	T.eq(State.NameSize({ title = 900, head = 750, body = 650 }, 246), "body", "and never below the type scale (it wraps)")

	-- The professions menu: as wide as its longest line, 210 at least, inside the column.
	T.eq(State.MenuWidth(80, 420), 210, "short names: the design's 210")
	T.eq(State.MenuWidth(250, 420), 250 + 58, "longer names widen it")
	T.eq(State.MenuWidth(900, 420), 416, "never wider than the column less its margins")
	T.eq(State.MenuWidth(900, 520), 516, "which follows the column")
end

-- ---- the column: the tab row's width, and the craft bar's one row -------------------------------
do
	T.eq(State.Column(420, nil), 420, "no craft bar to measure: the tab row's column")
	T.eq(State.Column(420, 396), 420, "a bar that fits 420: 420")
	T.eq(State.Column(452, 396), 452, "a tab row wider than the bar: the tab row's")
	T.eq(State.Column(420, 441), 441, "a bar wider than the tab row: the bar's")
	T.eq(State.Column(420, 440.2), 441, "rounded up to a whole unit")
	T.eq(State.Column(420, 700), 520, "never over 520 for the bar (it has its two-row fallback past that)")
	T.eq(State.Column(600, 700), 600, "a single tab wider than 520 still has its room")
	T.eq(State.Column(300, 300), 420, "and never under 420")

	-- Each language's bar at its reserved longest: the longer of Create and Enchant, "Max 999",
	-- Queue (Locales\*.lua; a button is its words plus 32, never under the design's width:
	-- DaylightUI/Options/Widgets.lua:506-510). German's are the audit's measured widths (Queue
	-- 107 for "Warteschlange", "Max. 20" 74, so "Max. 999" 80); the others are 6 px a Latin
	-- letter, 6.8 a Cyrillic one, 12 a Hangul or Han one at size 13.
	local least = State.LEAST
	local function button(text, min) return math.max(min, text + 32) end
	local bars = {
		enUS = { make = button(6 * 7, least.make), max = button(6 * 7, least.max), queue = button(6 * 5, least.queue) },      -- Enchant, Max 999, Queue
		deDE = { make = 96, max = 80, queue = 107 },                                                                           -- Verzaubern, Max. 999, Warteschlange
		frFR = { make = button(6 * 9, least.make), max = button(6 * 7, least.max), queue = button(6 * 4, least.queue) },      -- Enchanter, Max 999, File
		esES = { make = button(6 * 8, least.make), max = button(6 * 8, least.max), queue = button(6 * 4, least.queue) },      -- Encantar, Máx. 999, Cola
		ruRU = { make = button(6.8 * 10, least.make), max = button(6.8 * 9, least.max), queue = button(6.8 * 7, least.queue) }, -- Зачаровать, Макс. 999, Очередь
		koKR = { make = button(12 * 4, least.make), max = button(12 * 2 + 24, least.max), queue = button(12 * 3, least.queue) }, -- 마법부여, 최대 999, 대기열
		zhCN = { make = button(12 * 2, least.make), max = button(12 * 2 + 24, least.max), queue = button(12 * 2, least.queue) }, -- 附魔, 最大 999, 队列
	}
	for lang, w in pairs(bars) do
		w.plus, w.minus, w.count = least.plus, least.minus, least.count
		local col = State.Column(State.W, State.CraftBarNeed(w))
		T.ok(col >= State.W and col <= State.MAX_W, lang .. ": the column for its craft bar is 420 to 520: " .. col)
		T.ok(not State.CraftBarTwoRows(w, col), lang .. ": its craft bar is one row in that column")
	end
	-- German, the case that was two rows: "Warteschlange" makes Queue 107, and with "Max. 20" the
	-- bar asks 435 of a 420 column.
	local de = { make = 96, max = 74, queue = 107, plus = 26, minus = 26, count = 46 }
	T.eq(State.CraftBarNeed(de), 435, "German with Max. 20: 435")
	T.ok(State.CraftBarTwoRows(de, 420), "which is two rows in a 420 column (the defect)")
	local col = State.Column(State.W, State.CraftBarNeed(bars.deDE))
	T.eq(col, 441, "German's column is 441, from the bar at Max. 999")
	T.ok(not State.CraftBarTwoRows(de, col), "one row there with Max. 20")
	de.max = 56
	T.ok(not State.CraftBarTwoRows(de, col), "and with Max. alone: the same column, the same one row")
end

-- ---- the header: the name and the note after it ----------------------------------------------
do
	local room = State.HeaderRoom(420, 4)
	local tailoring = { title = 90, head = 76, body = 66 }
	-- The skill: shown when it fits after the name, dropped when it doesn't (the 2 px line says it).
	local size, nameW, show, noteW = State.HeaderFit(tailoring, room, 54, false)
	T.ok(size == "title" and nameW == 92 and show == true and noteW == nil, "Tailoring 187 / 225: the name at 18, the skill after it")
	size, nameW, show = State.HeaderFit({ title = 230, head = 196, body = 170 }, room, 54, false)
	T.ok(size == "title" and nameW == 232 and show == false, "a long name: the skill drops, the name keeps its size")
	size, nameW, show = State.HeaderFit(tailoring, room, 0, false)
	T.ok(size == "title" and nameW == 92 and show == false, "no skill to show: none shown")
	-- "<name>'s recipes" on a linked profession may not drop: it is the only "not yours" mark.
	size, nameW, show, noteW = State.HeaderFit(tailoring, room, 96, true)
	T.ok(size == "title" and show == true and noteW == nil and nameW + 10 + 96 <= room, "a short owner's name: both at full size")
	size, nameW, show, noteW = State.HeaderFit(tailoring, room, 160, true)
	T.ok(show == true and size ~= "title" and nameW + 10 + 160 <= room, "a 12-letter owner's name: the name steps down, the note stays whole")
	T.eq(noteW, nil, "unwrapped")
	size, nameW, show, noteW = State.HeaderFit({ title = 200, head = 170, body = 148 }, room, 170, true)
	T.ok(show == true and size == "body", "a long profession name and a long owner's: the name at 13")
	T.ok(nameW >= State.NAME_LEAST and nameW + 10 + (noteW or 170) <= room, "the two share the room, the name wrapping in what the note leaves")
	size, nameW, show, noteW = State.HeaderFit(tailoring, room, 400, true)
	T.ok(size == "body" and show == true and noteW ~= nil and noteW >= 40 and nameW + 10 + noteW <= room, "a note longer than the header: it wraps, still shown")
	for _, w in ipairs({ 0, 30, 96, 160, 230, 400, 900 }) do
		local _, n, shown, nw = State.HeaderFit(tailoring, room, w, true)
		T.ok(w == 0 or shown == true, "a note that must show is never dropped (" .. w .. ")")
		T.ok(w == 0 or n + 10 + (nw or w) <= room, "and the two never overrun the header (" .. w .. ")")
	end
end

-- ---- a list's thumb -----------------------------------------------------------------------------
do
	T.eq(State.Thumb(300, 200, 0), nil, "everything fits: no thumb")
	T.eq(State.Thumb(300, 300, 0), nil, "exactly fits: none")
	T.eq(State.Thumb(0, 300, 0), nil, "no room known: none")
	local size, down = State.Thumb(300, 600, 0)
	T.ok(size == 150 and down == 0, "half of it on show: a thumb half the track, at its top")
	size, down = State.Thumb(300, 600, 300)
	T.ok(size == 150 and down == 150, "scrolled to the end: at its foot")
	size, down = State.Thumb(300, 600, 150)
	T.ok(size == 150 and down == 75, "half way: half way down")
	size = State.Thumb(300, 30000, 0)
	T.eq(size, 24, "a very long list: never smaller than 24")
	size, down = State.Thumb(300, 600, 9999)
	T.ok(size == 150 and down == 150, "scrolled past the end counts as the end")
end

-- ---- rolled up only with something to roll up to --------------------------------------------------
do
	local win = { rolled = true, details = { recipes = true } }
	T.eq(State.Mode(win, "recipes", false, false), "rolled", "as saved: rolled up")
	T.eq(State.Mode(win, "recipes", false, false, true), "rolled", "rolled up now: rolled up")
	T.eq(State.Mode(win, "recipes", false, false, false), "expanded", "nothing to roll up to: as it would be unrolled (the details were open)")
	T.eq(win.rolled, true, "and the saved choice is untouched")
	T.eq(State.Mode({ details = {} }, "recipes", false, false, false), "compact", "not rolled: compact")
	T.eq(State.Mode({ details = {} }, "recipes", false, false, true), "rolled", "the caller's answer decides")
end

-- ---- the secure Stop -----------------------------------------------------------------------------
do
	T.ok(State.SameRect({ 300, 120, 96, 24 }, { 300.2, 119.8, 96, 24 }), "the same spot to half a unit")
	T.ok(not State.SameRect({ 300, 120, 96, 24 }, { 300, 600, 96, 24 }), "another spot is another spot")
	T.ok(not State.SameRect(nil, { 1, 2, 3, 4 }), "no rectangle is no match")
	T.ok(not State.SameRect({ 1, 2, 3 }, { 1, 2, 3, 4 }), "nor is half of one")

	-- Out of a fight the secure Stop goes where the window's Stop is, or away.
	T.eq(State.StopAction(false, false, true, false), "place", "out of a fight, wanted: placed")
	T.eq(State.StopAction(false, true, true, false), "place", "out of a fight, wanted, elsewhere: placed again")
	T.eq(State.StopAction(false, true, true, true), "place", "out of a fight, already there: placed (harmless)")
	T.eq(State.StopAction(false, true, false, false), "hide", "out of a fight, not wanted: put away")
	T.eq(State.StopAction(false, false, false, false), "hide", "out of a fight, nothing: nothing")
	-- In a fight it can't be moved: it is never asked to be.
	for _, shown in ipairs({ true, false }) do
		for _, wanted in ipairs({ true, false }) do
			for _, same in ipairs({ true, false }) do
				local act = State.StopAction(true, shown, wanted, same)
				T.ok(act ~= "place" and act ~= "hide", "in a fight the secure Stop is never moved, shown or hidden")
			end
		end
	end
	T.eq(State.StopAction(true, true, true, true), "keep", "in a fight, under the window's Stop: left alone")
	T.eq(State.StopAction(true, true, true, false), "face", "in a fight, the window moved or changed state: it shows its own face")
	T.eq(State.StopAction(true, true, false, false), "face", "in a fight, the craft ended or the window closed: its own face")
	T.eq(State.StopAction(true, false, true, false), "none", "a craft begun in a fight: no secure Stop can be brought")
	T.eq(State.StopAction(true, false, false, false), "none", "in a fight, nothing out, nothing wanted")
end

-- ---- what the rolled-up window's bar is for --------------------------------------------------------
do
	local m = State.RolledBar(false, nil, { can = 4 })
	T.eq(m.kind, "pick", "nothing queued, a recipe picked: the bar is the picked recipe's")
	T.eq(m.off, false, "which can be made: Create is on")
	m = State.RolledBar(false, nil, { can = 0 })
	T.eq(m.off, true, "a picked recipe you can make none of: Create is off (the first report's dim Create)")
	m = State.RolledBar(false, nil, { can = 4, blocked = true })
	T.eq(m.off, true, "one the game has disabled: off")
	m = State.RolledBar(false, { count = 5, can = 12 }, { can = 0 })
	T.eq(m.kind, "queue", "something queued for this profession: the bar is the queue's next, whatever is picked")
	T.eq(m.make, 5, "a press makes what is queued of it")
	T.eq(m.off, false, "and the button is on although the picked recipe can't be made")
	T.eq(m.short, false, "not short of anything")
	m = State.RolledBar(false, { count = 5, can = 3 }, nil)
	T.eq(m.make, 3, "fewer makeable than queued: a press makes what can be made, as the Queue tab's Craft Next")
	T.eq(m.off, false, "the button is on")
	m = State.RolledBar(false, { count = 5, can = 0 }, { can = 9 })
	T.eq(m.kind, "queue", "the queue's next can't be made: still the queue's next (nothing is skipped, as on the Queue tab)")
	T.eq(m.off, true, "the button is off")
	T.eq(m.short, true, "and the bar says you are short of materials")
	T.eq(m.make, 0, "nothing would be made")
	m = State.RolledBar(false, { count = 5, can = 5, blocked = true }, nil)
	T.eq(m.off, true, "a queued recipe the game has disabled: off")
	T.eq(m.short, false, "but not for materials")
	m = State.RolledBar(true, { count = 5, can = 5 }, { can = 4 })
	T.eq(m.kind, "run", "while something is being made the bar is the run's (Stop), whatever is queued or picked")
	m = State.RolledBar(false, nil, nil)
	T.eq(m.kind, "none", "nothing made, queued or picked: no bar (the window is then not rolled up)")
	T.eq(m.off, true, "and nothing to press")
	m = State.RolledBar(false, { count = "x", can = nil }, nil)
	T.eq(m.make, 0, "nonsense numbers make nothing")
end

return T.done()
