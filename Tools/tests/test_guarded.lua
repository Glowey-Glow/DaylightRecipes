-- Guarded reads: every call into Professionally Lost survives its table being missing, renamed,
-- emptied, of the wrong type, or raising; a failed call hides a button (false) or falls back to
-- our own behavior (nil), and never errors. Its tables are never written to.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB MerchantFrame IsShiftKeyDown
-- luacheck: read globals NS T Fire NewObj InstallProfLost
local ns = NS
local PL = ns.ProfLost
local ALL = { plGuide = true, plShop = true, plTrainer = true, plTips = true, plPrices = true, plStep = true }
for k, v in pairs(ALL) do GAME.settings[k] = v end

local function quiet(what)
	T.eq(PL.Handed("guide", 197), false, what .. ": the guide is ours")
	T.eq(PL.Handed("buy", 197), false, what .. ": the buy list is ours")
	T.eq(PL.NextStepSpell(197), nil, what .. ": no step of its")
	T.eq(PL.Price(2589), nil, what .. ": no price of its")
	T.eq(PL.HasPrices(), false, what .. ": no prices of its")
	T.eq(PL.OpenGuide(197), false, what .. ": its guide can't be opened")
	T.eq(PL.OpenGathering(), false, what .. ": nor its gathering panel")
	T.eq(PL.OpenSettings(), false, what .. ": nor its settings")
	T.eq(PL.CanOpenGuide(), false, what .. ": no button for its guide")
	T.eq(PL.CanOpenGathering(), false, what .. ": no button for its gathering panel")
	T.eq(PL.CanOpenSettings(), false, what .. ": no button for its settings")
	T.noErrors(what)
end

-- 1. Not installed at all.
quiet("absent")

-- 2. Its folder is loaded but its handle is gone (renamed in a later version).
GAME.addons.ProfessionallyLost = true
quiet("no handle")

-- 3. The handle is not a table.
ProfLost = "1.3.0"
quiet("a handle of the wrong type")
ProfLost = 42
quiet("a number for a handle")

-- 4. The handle is there but empty: everything inside was renamed.
ProfLost = {}
ProfLostCharDB = nil
T.eq(PL.Loaded(), true, "an empty handle still counts as loaded")
T.eq(PL.Covers(197), false, "no Guides table: it covers nothing")
T.eq(PL.Handed("guide", 197), false, "so our own guide stays for every profession")
T.eq(PL.Handed("guide"), false, "for any profession")
T.eq(PL.Handed("prices"), true, "prices are handed off by the switch alone")
T.eq(PL.Price(2589), nil, "but there is no price to read: ours is used")
T.eq(PL.NextStepSpell(197), nil, "no saved data: no step")
T.eq(PL.OpenGuide(197), false, "no Window.Open and no launcher function: false")
T.eq(PL.OpenGathering(), false, "no GatherPanel")
T.eq(PL.OpenSettings(), false, "no Panel")
T.eq(PL.CanOpenGuide(), false, "so no buttons")
PL.Listen()
T.noErrors("an empty handle")

-- 5. Parts of the wrong type.
ProfLost = { Guides = true, Window = "gone", Scan = 7, Panel = function() end, GatherPanel = false, On = "no" }
T.eq(PL.Covers(197), false, "Guides is not a table")
T.eq(PL.OpenGuide(197), false, "Window is not a table")
T.eq(PL.Price(2589), nil, "Scan is not a table")
T.eq(PL.OpenSettings(), false, "Panel is not a table")
T.noErrors("parts of the wrong type")

-- 6. A handle that raises on every read, and functions that raise when called.
ProfLost = setmetatable({}, { __index = function(_, k) error("no " .. tostring(k)) end })
T.eq(PL.Covers(197), false, "a raising handle covers nothing")
T.eq(PL.OpenGuide(197), false, "and opens nothing")
T.eq(PL.Price(2589), nil, "and prices nothing")
T.noErrors("a raising handle")
local boom = function() error("changed in 1.3") end
ProfLost = { Guides = { [197] = {} }, Window = { Pick = boom, Open = boom }, GatherPanel = { Open = boom },
	Panel = { OpenSettings = boom }, Scan = { Price = boom, HasData = boom, OnChange = boom }, On = boom }
T.eq(PL.Handed("guide", 197), true, "its guide table is still there: the hand-off stands")
T.eq(PL.OpenGuide(197), false, "a raising Open: false, no error")
T.eq(PL.OpenGathering(), false, "a raising GatherPanel.Open")
T.eq(PL.OpenSettings(), false, "a raising OpenSettings")
T.eq(PL.Price(2589), nil, "a raising Scan.Price")
T.eq(PL.HasPrices(), false, "a raising Scan.HasData")
T.noErrors("functions that raise")

-- 7. Saved data of odd shapes.
ProfLost = { Guides = { [197] = {} } }
for _, db in ipairs({ false, 5, "x", {}, { nextStep = 3 }, { nextStep = { [197] = 3852 } }, { nextStep = { [197] = {} } },
	{ nextStep = { [197] = { spell = "3852" } } }, { nextStep = { [197] = { spell = -1 } } },
	{ nextStep = { [197] = { spell = 12.5 } } } }) do
	ProfLostCharDB = db
	T.eq(PL.NextStepSpell(197), nil, "an odd saved shape gives no step")
end
ProfLostCharDB = { nextStep = { [197] = { spell = 3852 } } }
T.eq(PL.NextStepSpell(197), 3852, "the documented shape gives its step")
T.eq(PL.NextStepSpell("197"), nil, "a line that is not a number: nil")

-- 8. Prices of odd shapes.
local answers = { { nil }, { "12" }, { 0, GAME.clock }, { -5, GAME.clock }, { 120 }, { 120, "then" }, { 0 / 0, GAME.clock } }
for _, a in ipairs(answers) do
	ProfLost = { Scan = { Price = function() return a[1], a[2] end } }
	T.eq(PL.Price(2589), nil, "an odd price answer gives none")
end
ProfLost = { Scan = { Price = function() return 120.6, GAME.clock - 60 end } }
local copper, age = PL.Price(2589)
T.eq(copper, 120, "a good answer: its price, in whole copper")
T.eq(age, 60, "and how old it is")
ProfLost = { Scan = { Price = function() return 120, GAME.clock + 500 end } }
copper, age = PL.Price(2589)
T.eq(copper, 120, "a stamp from the future: the price stands")
T.eq(age, 0, "and counts as seen now")

-- 9. The documented shapes work, on the player's click, and nothing of its is written.
local CP = InstallProfLost({ prices = { [2589] = { 95, GAME.clock - 10 } } })
T.snapshot()
T.eq(PL.OpenGuide(197), true, "its guide opens")
T.eq(CP.calls[1], "Pick 197", "pointed at the profession first")
T.eq(CP.calls[2], "Open", "then opened")
T.eq(PL.OpenGuide(186), true, "a profession it has no guide for still opens its window")
T.eq(CP.calls[3], "Open", "without a pick")
T.eq(PL.OpenGathering(), true, "its gathering panel opens")
T.eq(PL.OpenSettings(), true, "its settings open (as a method call)")
T.eq(CP.calls[#CP.calls], "Settings", "through Panel:OpenSettings")
T.eq(PL.HasPrices(), true, "it has prices")
-- Its signals reach us, gathered into one change a moment later.
local heard = {}
PL.OnChange(function(what) heard[#heard + 1] = what end)
PL.Listen()
CP:Emit("ProfLost_NEEDS")
CP:Emit("ProfLost_NEEDS")
CP.Scan.notify()
CP.Scan.notify()
T.eq(#heard, 0, "nothing at once")
T.run(5)
T.eq(#heard, 2, "one change for its step, one for its prices")
-- With the launcher's own toggle as the only way in, it is pressed only while its window is shut.
CP.Window = nil
local presses = 0
ProfLost_Open = function() presses = presses + 1 end
ProfLost_Panel = NewObj("Frame")
ProfLost_Panel.shown = true
T.eq(PL.OpenGuide(197), false, "its window is up: the toggle is not pressed (it would close it)")
T.eq(presses, 0, "no press")
ProfLost_Panel.shown = false
T.eq(PL.OpenGuide(197), true, "its window is shut: the toggle opens it")
T.eq(presses, 1, "one press")
-- With Shift held its launcher toggles the gathering panel instead of the guide: not pressed then.
IsShiftKeyDown = function() return true end
T.eq(PL.OpenGuide(197), false, "Shift held: the toggle would open another panel, so the answer is false")
T.eq(presses, 1, "and nothing is pressed")
IsShiftKeyDown = function() return false end
T.eq(PL.OpenGuide(197), true, "Shift let go: it opens again")
T.eq(presses, 2, "by one press")
IsShiftKeyDown = nil
-- Everything above was reads and its own functions called: nothing of its was written.
CP.Window = { Pick = function() end, Open = function() end }
T.snapshot()
T.eq(PL.OpenGuide(197), true, "its guide opens again through its own Window.Open")
T.eq(PL.OpenGathering(), true, "and its gathering panel")
T.eq(PL.Covers(197), true, "its guides are read")
T.eq(PL.NextStepSpell(197), nil, "its saved step is read (none saved)")
T.eq(PL.HasPrices(), true, "its prices are asked for")
T.eq((PL.Price(2589)), 95, "and read")
T.untouched("opening its windows and reading its data")
-- Its vendor button: read, never touched; unreadable counts as "it's there".
T.eq(PL.VendorButtonShown(), true, "no Buying table to read: taken as there")
CP.Buying = { vendor = {} }
T.eq(PL.VendorButtonShown(), false, "its button is not made yet")
CP.Buying.vendor.button = NewObj("Button")
T.eq(PL.VendorButtonShown(), true, "its button is on show")
CP.Buying.vendor.button.shown = false
T.eq(PL.VendorButtonShown(), false, "its button is hidden")
CP.Buying.vendor = "moved"
T.eq(PL.VendorButtonShown(), true, "a changed shape: taken as there")
-- On the game's own vendor window our strip then stands beside it, not under the window.
MerchantFrame = NewObj("Frame", "MerchantFrame")
MerchantFrame.w, MerchantFrame.h = 336, 444
GAME.settings.plShop = false
GAME.plans = { [197] = { need = { [2320] = 3 } } }
GAME.merchant = true
GAME.money = 1000
GAME.shelf = { { id = 2320, price = 10, stack = 1, max = 20 } }
Fire("MERCHANT_SHOW")
T.run(2)
local strip = _G.DaylightRecipesBuyStrip
T.ok(strip and strip:IsShown(), "the strip shows on the game's vendor window")
T.eq(strip.fit, true, "beside the window while its button hangs under it")
T.eq(strip.rows, 2, "as a two-row piece")
CP.Buying = { vendor = {} }
Fire("PLAYER_MONEY")
T.run(2)
T.eq(strip.fit, false, "its button gone: under the window, as wide as it")
T.eq(strip.wide, 336, "the game's vendor window is 336 wide")
Fire("MERCHANT_CLOSED")

-- A listener of ours that raises is reported, and the others still hear.
PL.OnChange(function() error("a listener of ours broke") end)
local later = 0
PL.OnChange(function() later = later + 1 end)
CP:Emit("ProfLost_NEEDS")
T.run(5)
T.eq(later, 1, "the listener after a broken one still hears")
T.eq(#ERRORS, 1, "and the broken one is reported, not swallowed")
ERRORS = {}
-- (Its vendor button was read and our strip moved beside it: still nothing of its written. The
-- test itself replaced CP.Buying above, so the picture is taken again from here.)
T.snapshot()
T.eq(PL.VendorButtonShown(), false, "its button is read once more")
CP:Emit("ProfLost_NEEDS")
T.run(5)
T.eq(#ERRORS, 1, "(the broken listener, reported once more)")
ERRORS = {}
T.untouched("its signals heard and its vendor button read")

return T.done()
