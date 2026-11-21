-- The rules of buying and of learning (Shop.lua, "THE RULES OF BUYING" / "THE RULES OF LEARNING"),
-- each played against the strict vendor and trainer of mocks.lua the way it broke before:
--   a vendor closing and another opening under a run, a question answered at another vendor,
--   presses that come faster than the step timer, a row pressed from an old drawing of the list,
--   purchases that reach the bags late, and other bag events in between.
-- Every purchase is made through the strip's own buttons and rows, as a mouse or a controller
-- makes them (a controller's A is the same OnClick). GAME.limit makes the vendor itself raise on
-- the first item bought over the need. Each case stands alone (T.case), so one run against an
-- older Shop.lua names every rule it breaks.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB MerchantFrame GetPhysicalScreenSize NS
-- luacheck: read globals T Fire NewObj InstallProfLost ALL
local ns = NS
local Shop = ns.Shop

local THREAD, VIAL, DYE = 2320, 3371, 2604
local function shelf()
	return {
		{ id = THREAD, price = 10, stack = 1, max = 20 },
		{ id = VIAL, price = 4, stack = 1, max = 20 },
		{ id = DYE, price = 500, stack = 5, max = 5 },
	}
end

GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540

-- A clean start: nothing open, every timer and every "just bought" note run out, the list open.
local function fresh()
	if GAME.merchant then T.leave() end
	if GAME.trainer then T.leaveTrainer() end
	GAME.deliver = nil
	T.run(30)
	GAME.bought, GAME.total, GAME.limit, GAME.learned, GAME.known = {}, {}, {}, {}, {}
	GAME.bags, GAME.queue, GAME.plans, GAME.prof = {}, {}, {}, {}
	GAME.deliver, GAME.trainLag = 0.3, 0
	GAME.money, GAME.freeSlots, GAME.stackSize = 1000000, 200, {}
	GAME.settings.askBuyAll = false
	GAME.settled = 0
	PRINTS = {}
	DaylightRecipesDB = { shop = { vendor = true, trainer = true } }
end

local function strip() return _G.DaylightRecipesBuyStrip end
local function question() return _G.DaylightRecipesConfirm end
local function row(itemID)
	local s = strip()
	if not (s and s:IsShown() and s.list:IsShown()) then return nil end
	for _, r in ipairs(s.doc.rows) do
		if type(r.left) == "string" and r.left:find("Item " .. itemID .. " x", 1, true) and r.onClick then return r end
	end
end
local function needed(itemID)
	for _, r in ipairs(Shop.List()) do
		if r.itemID == itemID then return r.buy end
	end
	return 0
end

-- ---- rule 3: only at the vendor of the press ----------------------------------------------------
T.case("H1: a run does not follow you to the next vendor", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 200 } } }
	GAME.limit[THREAD] = 200
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	T.eq(#GAME.bought, 1, "the first purchase is made inside the press")
	T.run(0.25)
	T.eq(#GAME.bought, 2, "the second a step later")
	local first = GAME.vendorID
	T.walk(shelf())
	T.run(5)
	local n, where = T.boughtOf(THREAD)
	T.eq(where[GAME.vendorID], nil, "nothing is bought at the second vendor without a press there")
	T.eq(n, 40, "the run ended where the first vendor closed")
	T.eq(where[first], 40, "all of it at the vendor of the press")
	T.eq(Shop.Buying(), false, "and no run is under way")
	T.ok(strip():IsShown(), "the strip shows at the second vendor")
	T.eq(needed(THREAD), 160, "counting only what is still missing")
	strip().main:Click()
	T.run(15)
	n, where = T.boughtOf(THREAD)
	T.eq(n, 200, "a press there buys the rest: exactly the number needed in all")
	T.eq(where[GAME.vendorID], 160, "the rest at the second vendor")
end)

T.case("H1: a vendor that closes and opens again under a run", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100, [VIAL] = 60 } } }
	GAME.limit[THREAD], GAME.limit[VIAL] = 100, 60
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	-- Closed and opened again five times, faster than the step timer, a press each time.
	for _ = 1, 5 do
		T.walk(shelf())
		T.run(0.05)
		if strip():IsShown() then strip().main:Click() end
		T.run(0.05)
	end
	T.run(20)
	T.eq((T.boughtOf(THREAD)), 100, "never over the need, however the vendors change")
	T.eq((T.boughtOf(VIAL)), 60, "of either item")
end)

T.case("H1: a question asked at one vendor buys nothing at the next", function()
	fresh()
	GAME.settings.askBuyAll = true
	GAME.plans = { [197] = { need = { [THREAD] = 30 } } }
	GAME.limit[THREAD] = 30
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	local q = question()
	T.ok(q and q:IsShown(), "Buy All Needed asks first")
	local yes = q.yes.scripts.OnClick
	T.walk(shelf())
	T.ok(not q:IsShown(), "the question goes with the vendor it was asked at")
	-- (Its Yes pressed all the same, as a press already on its way would.)
	yes(q.yes)
	T.run(5)
	T.eq(#GAME.bought, 0, "and its Yes buys nothing at another vendor")
end)

-- ---- rule 4: one run at a time; a press twice buys once ------------------------------------------
T.case("presses faster than the step timer start one run", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 100, [VIAL] = 40 } } }
	GAME.limit[THREAD], GAME.limit[VIAL] = 100, 40
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	local main, thread = s.main.scripts.OnClick, row(THREAD).onClick
	main(s.main)
	main(s.main)
	thread()
	T.eq(#GAME.bought, 1, "three presses in one moment: one purchase")
	for _ = 1, 40 do
		T.run(0.05)
		main(s.main)
		thread()
	end
	T.run(20)
	T.eq((T.boughtOf(THREAD)), 100, "pressed all through the run: exactly the need")
	T.eq((T.boughtOf(VIAL)), 40, "of both items")
end)

T.case("M2: a row pressed three times buys once", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 10 } } }
	GAME.limit[THREAD] = 10
	T.vendor(shelf())
	T.run(1)
	-- (The row as it was drawn: the same closure pressed again and again, as a controller's A
	-- on a row does before the list is drawn anew.)
	local press = row(THREAD).onClick
	press()
	press()
	press()
	T.eq((T.boughtOf(THREAD)), 10, "three presses inside one frame: bought once")
	T.run(0.1)
	press()
	T.run(0.15)
	press()
	T.eq((T.boughtOf(THREAD)), 10, "pressed again before and after the list is drawn anew: still once")
	T.run(5)
	press()
	T.run(5)
	T.eq((T.boughtOf(THREAD)), 10, "and the old row buys nothing once the bags hold it")
	T.eq(row(THREAD), nil, "the list has no row for it any more")
end)

T.case("M2: a dear row's question buys what is needed when answered, not what was drawn", function()
	fresh()
	local GEM = 7777
	GAME.plans = { [197] = { need = { [GEM] = 2 } } }
	GAME.limit[GEM] = 2
	GAME.money = 9000000
	T.vendor({ { id = GEM, price = 2000000, stack = 1, max = 1 } })
	T.run(1)
	local press = row(GEM).onClick
	press()
	local q = question()
	T.ok(q and q:IsShown(), "a purchase of 150g or more is asked about")
	T.eq(#GAME.bought, 0, "and waits")
	-- One arrives another way while the question stands.
	GAME.bags[GEM] = 1
	T.bagEvent()
	q.yes:Click()
	T.run(5)
	T.eq((T.boughtOf(GEM)), 1, "Yes buys what is still needed, not the number on the old row")
end)

-- ---- rule 5: late bags ---------------------------------------------------------------------------
T.case("M1: another bag event does not bring a bought item back", function()
	fresh()
	GAME.deliver = 6
	GAME.plans = { [197] = { need = { [THREAD] = 40 } } }
	GAME.limit[THREAD] = 40
	T.vendor(shelf())
	T.run(1)
	row(THREAD).onClick()
	T.run(1)
	T.eq((T.boughtOf(THREAD)), 40, "the row bought the 40 needed")
	-- Something else changes in the bags before the purchase gets there.
	T.bagEvent()
	T.run(1)
	T.eq(needed(THREAD), 0, "what is on its way is not needed again")
	T.ok(not strip():IsShown(), "so the strip has gone: nothing needed here")
	T.bagEvent()
	T.bagEvent()
	T.run(2)
	T.eq(needed(THREAD), 0, "however many times the bags are read before it lands")
	T.run(10)
	T.eq(GAME.bags[THREAD], 40, "it landed")
	T.eq(needed(THREAD), 0, "and is counted from the bags now")
	T.eq((T.boughtOf(THREAD)), 40, "bought once")
end)

T.case("M1: two rows half a second apart", function()
	fresh()
	GAME.deliver = 0.6
	GAME.plans = { [197] = { need = { [THREAD] = 10, [VIAL] = 10 } } }
	GAME.limit[THREAD], GAME.limit[VIAL] = 10, 10
	T.vendor(shelf())
	T.run(1)
	row(THREAD).onClick()
	T.run(0.5)
	row(VIAL).onClick()
	-- The first lands 0.1 s later and the bags are read: the second is still on its way.
	T.run(0.2)
	T.eq(GAME.bags[THREAD], 10, "the first has landed")
	T.eq(GAME.bags[VIAL], nil, "the second has not")
	T.eq(needed(VIAL), 0, "and is not asked for again")
	T.run(0.2)
	if row(VIAL) then row(VIAL).onClick() end
	if strip():IsShown() then strip().main:Click() end
	T.run(5)
	T.eq((T.boughtOf(VIAL)), 10, "pressed again in between: still bought once")
	T.eq((T.boughtOf(THREAD)), 10, "like the first")
end)

T.case("a purchase that lands late, part of it, is counted as it lands", function()
	fresh()
	GAME.deliver = 4
	GAME.plans = { [197] = { need = { [THREAD] = 100 } } }
	GAME.limit[THREAD] = 100
	GAME.bags[THREAD] = 15
	T.vendor(shelf())
	T.run(1)
	T.eq(needed(THREAD), 85, "85 still to buy")
	strip().main:Click()
	T.run(2)
	T.eq((T.boughtOf(THREAD)), 85, "bought in five purchases")
	T.eq(needed(THREAD), 0, "nothing more is needed while they are on their way")
	T.run(2.3)
	T.ok((GAME.bags[THREAD] or 0) > 15 and GAME.bags[THREAD] < 100, "some have landed: " .. tostring(GAME.bags[THREAD]))
	T.eq(needed(THREAD), 0, "the rest is still counted as on its way")
	strip().main:Click()
	T.run(10)
	T.eq(GAME.bags[THREAD], 100, "all landed")
	T.eq((T.boughtOf(THREAD)), 85, "and nothing was bought twice")
end)

T.case("goods sold in lots: one lot covers it, pressed again or not", function()
	fresh()
	GAME.plans = { [197] = { need = { [DYE] = 7 } } }
	GAME.limit[DYE] = 10          -- two whole lots of 5 is the least the game sells for a need of 7
	T.vendor(shelf())
	T.run(1)
	local press = row(DYE).onClick
	press()
	press()
	T.run(0.05)
	press()
	T.run(5)
	T.eq((T.boughtOf(DYE)), 10, "two lots, once")
end)

-- ---- the question -------------------------------------------------------------------------------
T.case("L3: with the question switched off, a purchase of 150g or more is still asked about", function()
	fresh()
	local GEM = 7777
	GAME.plans = { [197] = { need = { [GEM] = 1, [THREAD] = 5 } } }
	GAME.money = 9000000
	T.vendor({ { id = GEM, price = 2000000, stack = 1, max = 1 }, { id = THREAD, price = 10, stack = 1, max = 20 } })
	T.run(1)
	strip().main:Click()
	local q = question()
	T.ok(q and q:IsShown(), "Buy All Needed asks, as the game's own window would for that item")
	T.eq(#GAME.bought, 0, "and buys nothing until answered")
	q.no:Click()
	T.run(2)
	T.eq(#GAME.bought, 0, "No buys nothing")
	-- Without anything that dear on the list the switch stands: no question.
	T.leave()
	GAME.plans = { [197] = { need = { [THREAD] = 5 } } }
	T.vendor(shelf())
	T.run(1)
	strip().main:Click()
	T.ok(not q:IsShown(), "nothing dear: no question with the switch off")
	T.run(3)
	T.eq((T.boughtOf(THREAD)), 5, "bought on the press")
end)

T.case("L5: a vendor closing leaves another window's question up", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 5 } } }
	T.vendor(shelf())
	T.run(1)
	local unlearned = false
	-- (The Unlearn question, asked over the profession window through the same box: WindowMenu.lua.)
	Shop.Confirm(nil, "Unlearn Tailoring?", nil, function() unlearned = true end, { yes = "Unlearn", warn = true })
	local q = question()
	T.ok(q:IsShown(), "the Unlearn question is up")
	T.leave()
	T.ok(q:IsShown(), "and stays up when the vendor closes")
	q.yes:Click()
	T.eq(unlearned, true, "its Yes still answers it")
end)

T.case("L6: a long word for Yes widens the box", function()
	fresh()
	Shop.Confirm(nil, "Unlearn Tailoring?", nil, function() end, { yes = "Verlernen und alles vergessen" })
	local q = question()
	T.ok(q.w >= 2 * q.yes.w + 44, "Yes fits its half of the box: " .. q.w .. " for a Yes of " .. q.yes.w)
	T.ok(q.yes.w >= q.yes.text:GetStringWidth() + 24, "and holds its word")
	Shop.Confirm(nil, "Unlearn Tailoring?", nil, function() end, { yes = "Yes" })
	T.eq(q.w, 260, "a short word: the design's 260")
	q:Hide()
end)

-- ---- the strip's layout -------------------------------------------------------------------------
T.case("L2: on the game's 336-wide vendor window the words never overhang the strip", function()
	fresh()
	local was, npc = ns.Calc.Money, GAME.npc
	GAME.npc = nil
	MerchantFrame = NewObj("Frame", "MerchantFrame")
	MerchantFrame.w, MerchantFrame.h = 336, 444
	local function fits(s, what)
		local lw, cw = s.lead:GetStringWidth(), s.cost:GetStringWidth()
		if s.costRow then
			T.ok(14 + lw + 14 <= s.wide, what .. ": the lead fits its row")
			T.ok(14 + cw + 14 <= s.wide, what .. ": the cost fits its own row (" .. cw .. " in " .. s.wide .. ")")
		elseif s.rows == 1 then
			T.ok(14 + lw + 12 + cw + 16 + s.listButton.w + 8 + s.main.w + 8 <= s.wide, what .. ": one row holds it all")
		else
			T.ok(14 + lw + 12 + cw + 14 <= s.wide, what .. ": lead and cost fit one row (" .. (lw + cw) .. " in " .. s.wide .. ")")
		end
		T.eq(s.h, s.rows == 1 and 32 or s.rows * 28, what .. ": the strip is as tall as its rows")
	end
	local ok, err = pcall(function()
		ns.Calc.Money = function(copper)
			return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
		end
		GAME.plans = { [197] = { need = { [THREAD] = 200 } } }
		GAME.money = 1234567
		T.vendor({ { id = THREAD, price = 987654, stack = 1, max = 20 } })
		T.run(1)
		local s = strip()
		T.eq(s.wide, 336, "the strip is as wide as the game's vendor window")
		T.ok(s.cost:GetText():find("You Have", 1, true), "short of gold: the cost says what you have")
		T.eq(s.costRow, true, "too wide for the lead's row: the cost has a row of its own")
		fits(s, "short of gold")
		-- Sums too long even for a row of their own: the "You Have" half goes, nothing is cut.
		ns.Calc.Money = function(copper)
			return ("%d gold %d silver %d copper"):format(math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
		end
		Fire("PLAYER_MONEY")
		T.run(1)
		T.ok(not s.cost:GetText():find("You Have", 1, true), "wider than the strip: the cost alone")
		fits(s, "long sums")
		-- Enough gold: one sum, the ordinary rows.
		ns.Calc.Money = was
		GAME.money = 1000000000
		Fire("PLAYER_MONEY")
		T.run(1)
		fits(s, "enough gold")
	end)
	-- (Put back whatever came of it: the cases after this one use Daylight UI's window.)
	ns.Calc.Money = was
	if GAME.merchant then T.leave() end
	MerchantFrame.shown = false
	GAME.npc = npc
	if not ok then error(err, 0) end
end)

T.case("L4: a list drawn again settles a controller's cursor", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 5, [VIAL] = 5 } } }
	T.vendor(shelf())
	T.run(1)
	T.ok(strip().list:IsShown(), "the list is open")
	GAME.settled = 0
	Fire("PLAYER_MONEY")
	T.run(1)
	T.ok(GAME.settled >= 1, "drawn again with the list open: the cursor is settled")
	strip().listButton:Click()
	T.run(1)
	GAME.settled = 0
	Fire("PLAYER_MONEY")
	T.run(1)
	T.eq(GAME.settled, 0, "with the list shut there is nothing to settle")
end)

T.case("M8: the list never hangs off the screen", function()
	-- The sums: a list of 170 with room under the strip, with little, with none.
	local mode, h = Shop.ListPlace(170, 400, 1000, 16, 700)
	T.ok(mode == "below" and h == 170, "room under the strip: under it, whole")
	mode, h = Shop.ListPlace(170, 150, 1000, 16, 700)
	T.ok(mode == "below" and h == 150, "six rows fit: under it, as tall as the room (it scrolls)")
	mode, h = Shop.ListPlace(170, 120, 1000, 16, 700)
	T.ok(mode == "right" and h == 170, "fewer than six rows would fit under it: beside the window instead, whole")
	mode, h = Shop.ListPlace(170, 400, 1000, 16, 700, 80)
	T.ok(mode == "below" and h == 250, "with a head of 80 over the rows: the head is added, the rows keep their six and a part")
	mode, h = Shop.ListPlace(170, 200, 1000, 16, 700, 80)
	T.ok(mode == "right" and h == 250, "the head and six rows don't fit under the strip: beside, whole; the head never squeezes the rows")
	mode, h = Shop.ListPlace(170, 76, 100, 100, 120, 80)
	T.ok(mode == "up" and h == 120, "upward with little screen above: no taller than the screen")
	mode, h = Shop.ListPlace(170, 76, 1000, 16, 700)
	T.ok(mode == "right" and h == 170, "Daylight UI's vendor window at 768: beside it on the right, whole")
	mode, h = Shop.ListPlace(170, 76, 100, 900, 700)
	T.ok(mode == "up" and h == 170, "no room on the right: upward over the host's corner, never on its left however much room is there")
	mode, h = Shop.ListPlace(170, 76, 100, 100, 700)
	T.ok(mode == "up" and h == 170, "no room on either side: upward from the strip, over the host's corner")
	mode, h = Shop.ListPlace(60, 40, 1000, 16, 700)
	T.ok(mode == "right" and h == 60, "a short list that doesn't fit under: beside, at its own height")
	mode, h = Shop.ListPlace(900, nil, nil, nil, nil)
	T.ok(mode == "below" and h == 16 + 16 * 22, "the room not known yet: under it, sixteen rows at most")
	mode, h = Shop.ListPlace(16 + 11 * 22, 400, 1000, 16, 700, 56)
	T.ok(mode == "below" and h == 56 + 16 + 11 * 22, "eleven rows and room for them: all eleven, not six (six is the least, not the most)")
	mode, h = Shop.ListPlace(16 + 11 * 22, 56 + 200, 1000, 16, 700, 56)
	T.ok(mode == "below" and h == 56 + 200, "room for the head and some of them (six or more): as tall as the room")
	mode, h = Shop.ListPlace(16 + 11 * 22, 100, 100, 100, 700, 56)
	T.ok(mode == "up" and h == 56 + 16 + 7 * 22, "upward over the host's corner: six rows and a part at most, to cover no more of it")
	-- On a strip 80 above the screen's foot.
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 5, [VIAL] = 5, [DYE] = 5 } } }
	T.vendor(shelf())
	T.run(1)
	local s = strip()
	T.eq(s.listAt, "below", "400 above the screen's foot: the list is under the strip")
	T.ok(s.list.points[1][1] == "TOPRIGHT" and s.list.points[1][2] == s and s.list.points[1][3] == "BOTTOMRIGHT",
		"flush under its right end: the window's bottom right corner")
	s.bottom = 80
	Fire("PLAYER_MONEY")
	T.run(1)
	T.eq(s.listAt, "right", "80 above the foot: beside the vendor window")
	local at = s.list.points[1]
	T.ok(at[1] == "BOTTOMLEFT" and at[2] == GAME.npc and at[3] == "BOTTOMRIGHT", "against its right edge")
	T.eq(at[5], 0, "its foot level with the window's")
	T.ok(s.list.h <= 170 and s.list.h >= 60, "as tall as its rows")
	s.bottom = nil
end)

T.case("L20: the seam is the host's own border where its shell has one", function()
	fresh()
	GAME.dui["general.borderPx"] = 8
	GetPhysicalScreenSize = function() return 1920, 1080 end
	DaylightUI = { Style = { GetShell = function(f) return f == GAME.npc and { opts = {} } or nil end } }
	GAME.plans = { [197] = { need = { [THREAD] = 5 } } }
	T.vendor(shelf())
	T.run(1)
	local at = strip().points[1]
	T.ok(at[1] == "TOPLEFT" and at[2] == GAME.npc and at[3] == "BOTTOMLEFT", "docked under the host")
	T.ok(math.abs(at[5] - 8 * 768 / 1080) < 0.001, "without a border of the shell's own: the general setting's")
	T.leave()
	DaylightUI.Style.BorderPx = function(f) return f == GAME.npc and 4 or 8 end
	T.vendor(shelf())
	T.run(1)
	at = strip().points[1]
	T.ok(math.abs(at[5] - 4 * 768 / 1080) < 0.001, "a shell with its own border: tucked in by exactly that")
	DaylightUI.Style.BorderPx = function() error("changed in a later version") end
	T.leave()
	T.vendor(shelf())
	T.run(1)
	at = strip().points[1]
	T.ok(math.abs(at[5] - 8 * 768 / 1080) < 0.001, "a BorderPx that raises: the general setting's, no error")
	T.leave()
	DaylightUI, GetPhysicalScreenSize = nil, nil
	GAME.dui["general.borderPx"] = nil
end)

-- ---- the trainer --------------------------------------------------------------------------------
ns.Recipes = { [3915] = { 197 }, [3916] = { 197 }, [3917] = { 197 }, [3918] = { 197 } }
local function services()
	return {
		{ name = "Spell 3915", kind = "available", cost = 100, spell = 3915 },
		{ name = "Spell 3916", kind = "available", cost = 200, spell = 3916 },
		{ name = "Spell 3917", kind = "available", cost = 300, spell = 3917 },
		{ name = "Spell 3918", kind = "unavailable", cost = 400, spell = 3918, req = 90 },
	}
end
local function route()
	GAME.prof = { [197] = { skill = 60, max = 75 } }
	GAME.plans = { [197] = { need = {}, learn = { [3915] = { 60, 65 }, [3916] = { 65, 70 }, [3917] = { 70, 80 }, [3918] = { 90, 95 } } } }
end
local function trainStrip() return _G.DaylightRecipesTrainStrip end
local function learnedAt(trainer)
	local n = 0
	for _, l in ipairs(GAME.learned) do
		if l.trainer == trainer then n = n + 1 end
	end
	return n
end

T.case("H1: Learn All Recommended does not follow you to the next trainer", function()
	fresh()
	route()
	GAME.trainLag = 1
	T.trainer(services())
	T.run(1)
	local s = trainStrip()
	T.ok(s and s:IsShown(), "the strip is up at the trainer")
	T.ok(s.lead:GetText():find("3", 1, true), "three can be learned now")
	s.main:Click()
	T.eq(#GAME.learned, 1, "the first is learned inside the press")
	local first = GAME.trainerID
	T.leaveTrainer()
	T.trainer(services())
	T.run(5)
	T.eq(learnedAt(GAME.trainerID), 0, "nothing is learned at the second trainer without a press there")
	T.eq(learnedAt(first), 1, "the run ended where the first trainer closed")
	T.eq(Shop.Learning(), false, "and no run is under way")
end)

T.case("Learn All Recommended: each once, only what the press showed, however it is pressed", function()
	fresh()
	route()
	GAME.trainLag = 2          -- the trainer's list is slow to drop what was learned
	T.trainer(services())
	T.run(1)
	local s = trainStrip()
	local press = s.main.scripts.OnClick
	press(s.main)
	press(s.main)
	for _ = 1, 30 do
		T.run(0.05)
		press(s.main)
	end
	T.run(10)
	T.eq(#GAME.learned, 3, "the three that could be learned, each once (the strict trainer raises on a second)")
	T.eq(GAME.money, 1000000 - 600, "and paid for once")
	T.ok(not s:IsShown(), "nothing left to learn here now: the strip has gone")
end)

T.case("a trainer row pressed twice learns once", function()
	fresh()
	route()
	GAME.trainLag = 3
	T.trainer(services())
	T.run(1)
	local s = trainStrip()
	local press = s.doc.rows[1].onClick
	T.ok(press, "the first recommended row can be pressed")
	press()
	press()
	T.run(0.5)
	press()
	T.run(1)
	T.eq(#GAME.learned, 1, "learned once")
	T.eq(GAME.learned[1].name, "Spell 3915", "the one pressed")
	T.run(5)
	T.eq(#GAME.learned, 1, "and the others wait for a press of their own")
end)

T.case("Learn All Recommended leaves out what the gold doesn't reach, and says so", function()
	fresh()
	route()
	GAME.money = 350
	T.trainer(services())
	T.run(1)
	trainStrip().main:Click()
	T.run(5)
	T.eq(#GAME.learned, 2, "100 and 200 of 350: two learned")
	local said
	for _, line in ipairs(PRINTS) do
		if line:find("Spell 3917", 1, true) and line:find("not enough gold", 1, true) then said = true end
	end
	T.ok(said, "chat names the one left out")
end)

-- ---- handed to Professionally Lost: the plan rests ------------------------------------------------
T.case("M3: a plan that rests is not counted from", function()
	fresh()
	GAME.plans = { [197] = { need = { [THREAD] = 30 }, rested = true }, [171] = { need = { [VIAL] = 4 } } }
	GAME.queue = { [THREAD] = 6 }
	T.eq(needed(THREAD), 6, "a resting plan's materials are left out: only the queue's count")
	T.eq(needed(VIAL), 4, "another profession's plan counts as ever")
	GAME.plans[197].rested = nil
	T.eq(needed(THREAD), 30, "worked out again (no mark): it counts")
	-- The trainer strip reads no recipes from a resting plan either.
	route()
	GAME.plans[197].rested = true
	T.trainer(services())
	T.run(1)
	T.ok(not (trainStrip() and trainStrip():IsShown()), "a resting plan recommends nothing at the trainer")
	T.leaveTrainer()
end)

T.case("L1: with the trainer piece handed off, the next rank is offered at every cap", function()
	fresh()
	InstallProfLost({ guides = { 197 } })
	for _, key in ipairs({ "plGuide", "plShop", "plTrainer" }) do GAME.settings[key] = true end
	T.snapshot()
	-- The plan was last worked out before the hand-off, at the first cap; the character is two
	-- ranks on by now.
	GAME.plans = { [197] = { need = {}, learn = { [3915] = { 60, 65 } }, rank = { at = 75 }, rested = true } }
	GAME.prof = { [197] = { skill = 225, max = 225 } }
	T.trainer({
		{ name = "Spell 3915", kind = "used", cost = 100, spell = 3915 },
		{ name = "Spell 3916", kind = "available", cost = 200, spell = 3916 },
		{ name = "Artisan", kind = "available", cost = 5000, step = true },
	})
	T.run(1)
	local s = trainStrip()
	T.ok(s and s:IsShown(), "the strip shows: the next rank can be trained")
	T.ok(s.lead:GetText():find("1", 1, true), "one thing recommended")
	T.eq(#s.doc.rows, 1, "the rank alone: its recipes are Professionally Lost's to name")
	T.ok(s.doc.rows[1].left:find("Next Rank", 1, true), "the next rank")
	s.main:Click()
	T.run(2)
	T.eq(#GAME.learned, 1, "Learn All Recommended trains it")
	T.eq(GAME.learned[1].name, "Artisan", "the rank, not a recipe")
	T.untouched("the trainer strip with everything handed off")
	T.leaveTrainer()
	for _, key in ipairs({ "plGuide", "plShop", "plTrainer" }) do GAME.settings[key] = false end
end)

fresh()
return T.done()
