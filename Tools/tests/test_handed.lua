-- What ns.ProfLost.Handed answers for each switch and profession, the first-load window's
-- suggestions (with and without a controller), Apply and Put Everything Back, and that the buy
-- list follows the hand-off. Professionally Lost's own tables are never written to.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB NS
-- luacheck: read globals T Fire NewObj InstallProfLost
local ns = NS
local PL = ns.ProfLost
local KEYS = { "guide", "buy", "trainer", "tooltip", "prices", "step" }
local SETTING = { guide = "plGuide", buy = "plShop", trainer = "plTrainer", tooltip = "plTips", prices = "plPrices", step = "plStep" }

local function set(values)
	for _, key in ipairs(KEYS) do GAME.settings[SETTING[key]] = values[key] == true end
end
local ALL = { guide = true, buy = true, trainer = true, tooltip = true, prices = true, step = true }

-- Absent: nothing is handed off, whatever the switches say.
set(ALL)
T.eq(PL.Loaded(), false, "not loaded")
for _, key in ipairs(KEYS) do
	T.eq(PL.Handed(key, 197), false, key .. " is not handed off without Professionally Lost")
	T.eq(PL.Handed(key), false, key .. ", any profession: not handed off without it")
end
T.eq(PL.PlanQuiet(197), false, "our plan is kept up without it")

-- Loaded, with its eight crafting guides (no smelting 186, no Poisons 40).
InstallProfLost({ step = { [197] = 3852 } })
T.snapshot()
T.eq(PL.Loaded(), true, "loaded")
T.eq(PL.Covers(197), true, "it covers Tailoring")
T.eq(PL.Covers(186), false, "it has no guide for smelting")
T.eq(PL.Covers(40), false, "nor for Poisons")
T.eq(PL.Covers(nil), false, "no profession: not covered")

-- Every switch off (the default until the window is answered): nothing changes.
set({})
for _, key in ipairs(KEYS) do T.eq(PL.Handed(key, 197), false, key .. " is off by default") end

-- Each switch alone.
for _, key in ipairs(KEYS) do
	set({ [key] = true })
	local follows = key == "buy" or key == "trainer" or key == "step"
	T.eq(PL.Handed(key, 197), not follows, key .. " alone: " .. (follows and "means nothing without the guide" or "handed off"))
	for _, other in ipairs(KEYS) do
		if other ~= key then T.eq(PL.Handed(other, 197), false, other .. " stays ours while only " .. key .. " is on") end
	end
end

-- With the guide on, the three that follow it work; and all of it is per profession.
set(ALL)
for _, key in ipairs(KEYS) do
	T.eq(PL.Handed(key, 197), true, key .. " is handed off for a profession it covers")
	T.eq(PL.Handed(key), true, key .. " is handed off for some profession")
end
for _, key in ipairs({ "guide", "buy", "trainer", "tooltip", "step" }) do
	T.eq(PL.Handed(key, 186), false, key .. " stays ours for smelting, which it has no guide for")
	T.eq(PL.Handed(key, 40), false, key .. " stays ours for Poisons")
end
T.eq(PL.Handed("prices", 186), true, "prices are not a profession's: the line is ignored")
T.eq(PL.Handed("nonsense", 197), false, "an unknown job is never handed off")
T.eq(PL.PlanQuiet(197), true, "guide, buy list and trainer piece all handed off: our plan rests")
T.eq(PL.PlanQuiet(186), false, "not for a profession we still guide")
set({ guide = true, buy = true })
T.eq(PL.PlanQuiet(197), false, "the trainer piece still reads our plan: it is kept up")

-- The tooltip line follows its own tooltip switch too: with its item block off, ours stays.
set(ALL)
GAME.dui["ProfLost.itemTooltip"] = false
T.eq(PL.Handed("tooltip", 197), false, "its item tooltips are off: our guide line stays")
GAME.dui["ProfLost.itemTooltip"] = true
T.eq(PL.Handed("tooltip", 197), true, "and on again")

-- Its step.
T.eq(PL.NextStepSpell(197), 3852, "the recipe its guide is on")
T.eq(PL.NextStepSpell(171), nil, "no saved step: nil")

-- The buy list: a handed-off profession's plan is left out, the queue and other plans stay.
GAME.plans = { [197] = { need = { [2320] = 24 } }, [186] = { need = { [2770] = 20 } } }
GAME.queue = { [2320] = 5, [4306] = 2 }
GAME.bags = {}
local function need()
	local out = {}
	for _, r in ipairs(ns.Shop.List()) do out[r.itemID] = r.buy end
	return out
end
set({})
local n = need()
T.eq(n[2320], 24, "not handed off: the plan's need (the larger of plan and queue)")
T.eq(n[2770], 20, "and the smelting plan's")
set(ALL)
n = need()
T.eq(n[2320], 5, "handed off: only what the queue needs of it")
T.eq(n[4306], 2, "the queue is always counted")
T.eq(n[2770], 20, "a profession it doesn't cover keeps its plan on the list")
set({ buy = true })
T.eq(need()[2320], 24, "Buy Lists on without the guide: nothing is handed off")

-- A plan rests while its profession is handed off whole, and counts again only once it has been
-- worked out anew: after a partial put-back nothing is offered for skill already passed.
set(ALL)
GAME.plans = { [197] = { need = { [2320] = 24 } }, [186] = { need = { [2770] = 20 } } }
T.eq(PL.RestPlan(197), true, "handed off whole: the plan rests (Core.lua works nothing out)")
T.eq(GAME.plans[197].rested, true, "and the saved one is marked")
T.eq(PL.RestPlan(186), false, "a profession we still guide: its plan is kept up")
T.eq(GAME.plans[186].rested, nil, "and not marked")
T.eq(PL.RestPlan(171), true, "handed off with no plan saved: nothing to mark, no error")
T.eq(PL.RestPlan(nil), false, "no profession: nothing rests")
local worked = 0
ns.Plan = { Get = function()
	worked = worked + 1
	-- (As Plan.Get does: a new table for the open profession, at the skill of now.)
	GAME.plans[ns.state.line] = { need = { [2320] = 9 } }
end }
ns.state.line, ns.state.mode, ns.state.linked = 197, "win", false
PL.Changed()
T.eq(worked, 0, "a switch flipped with everything still handed off: the plan goes on resting")
-- Buy Lists switched back, the guide and the trainer piece still handed off.
set({ guide = true, trainer = true })
T.eq(need()[2320], 5, "before it is worked out again the resting plan counts for nothing: the queue's 5")
PL.Changed()
T.eq(worked, 1, "the open profession's plan is worked out again at the put-back")
T.eq(GAME.plans[197].rested, nil, "the new one carries no mark")
T.eq(need()[2320], 9, "and the list counts from your skill now, not from the 24 of the old plan")
-- With the profession not open, it can't be worked out: it stays left out until it is opened.
GAME.plans[197] = { need = { [2320] = 24 }, rested = true }
ns.state.mode = nil
PL.Changed()
T.eq(worked, 1, "no profession open: nothing is worked out")
T.eq(need()[2320], 5, "and the resting plan stays left out")
-- Someone's linked recipes are open: not ours to plan from.
ns.state.mode, ns.state.linked = "win", true
PL.Changed()
T.eq(worked, 1, "a linked profession open: nothing is worked out")
ns.state.line, ns.state.mode, ns.state.linked = nil, nil, nil
ns.Plan = nil
GAME.plans = { [197] = { need = { [2320] = 24 } }, [186] = { need = { [2770] = 20 } } }

-- The first-load window's suggestions.
local s = PL.Suggested(false)
for _, key in ipairs(KEYS) do T.eq(s[key], true, key .. " is suggested on") end
s = PL.Suggested(true)
T.eq(s.guide, false, "with a controller the guide stays ours")
T.eq(s.buy, false, "and the buy lists")
T.eq(s.trainer, false, "and the trainer piece")
T.eq(s.tooltip, true, "the tooltip line is still suggested")
T.eq(s.prices, true, "and the prices")
T.eq(s.step, true, "and its step (dimmed while the guide is ours)")

-- The window itself: Apply sets our six settings through Daylight UI and nothing else.
local writes = {}
DaylightUI = { Set = function(_, scope, key, value)
	writes[#writes + 1] = scope .. "." .. key
	GAME.settings[key] = value
end }
local changes = {}
PL.OnChange(function(what) changes[#changes + 1] = what end)
set({})
T.eq(PL.Asked(), false, "not answered yet")
GAME.pad = true
T.ok(PL.ShowDialog(), "the window opens")
local dialog = _G.DaylightRecipesProfLost
T.ok(dialog:IsShown(), "and shows")
T.eq(dialog.rows.guide.switch.on, false, "controller: row 1 starts off")
T.eq(dialog.rows.tooltip.switch.on, true, "row 4 starts on")
T.eq(dialog.rows.step.switch:IsEnabled(), false, "row 6 is dimmed while row 1 is off")
T.eq(dialog.rows.buy.switch:IsEnabled(), false, "row 2 too")
T.eq(dialog.rows.prices.switch:IsEnabled(), true, "row 5 is not")
T.eq(GAME.settings.plTips, false, "nothing is switched before Apply")
dialog.later:Click()
T.eq(PL.Asked(), false, "Ask Me Later leaves it unanswered")
T.eq(#writes, 0, "and sets nothing")
GAME.pad = false
PL.ShowDialog()
for _, key in ipairs(KEYS) do T.eq(dialog.rows[key].switch.on, true, key .. " starts on without a controller") end
dialog.rows.guide.switch:Click()
T.eq(dialog.rows.trainer.switch:IsEnabled(), false, "switching row 1 off dims rows 2, 3 and 6")
dialog.apply:Click()
T.eq(PL.Asked(), true, "Apply answers it")
T.eq(#writes, 6, "six settings are set")
for _, w in ipairs(writes) do T.ok(w:match("^DaylightRecipes%.pl"), "only our own settings are written (" .. w .. ")") end
T.eq(GAME.settings.plGuide, false, "row 1 as picked")
T.eq(GAME.settings.plShop, false, "a dimmed row is saved off")
T.eq(GAME.settings.plStep, false, "a dimmed row is saved off")
T.eq(GAME.settings.plTips, true, "row 4 as picked")
T.eq(GAME.settings.plPrices, true, "row 5 as picked")
T.eq(#changes, 1, "everyone is told once, not six times")
T.eq(changes[1], "settings", "that the switches changed")

-- Put Everything Back.
set(ALL)
PL.PutBack()
for _, key in ipairs(KEYS) do
	T.eq(GAME.settings[SETTING[key]], false, key .. " is off after Put Everything Back")
	T.eq(PL.Handed(key, 197), false, key .. " is ours again")
end
T.untouched("the whole test")

return T.done()
