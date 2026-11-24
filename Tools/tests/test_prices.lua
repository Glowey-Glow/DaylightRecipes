-- Prices.Get with "Scanned Prices" handed over: ours, or Professionally Lost's when it was seen
-- later; its prices older than two weeks are not used; without the switch (or with DaylightMogul,
-- which Calc asks instead) nothing of its is read.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB
-- luacheck: read globals NS T Fire NewObj InstallProfLost
local ns = NS
local Prices = ns.Prices
local DAY = 24 * 3600
local now = GAME.clock

local book = { items = {} }
GAME.db.prices["Realm-A"] = book

-- Ours only.
book.items[2589] = { p = 100, t = now - 3 * DAY }
T.eq(Prices.Get(2589), 100, "our own price")
T.eq(Prices.Get(9999), nil, "no price")
T.eq(Prices.Has(), true, "we have prices")
book.items[2592] = { p = 300, t = now - 15 * DAY }
T.eq(Prices.Get(2592), nil, "ours older than two weeks is not used")

-- How old a price is, and "Stale" past a day (Calc.STALE); none, or too old to use, has no age.
local Calc = ns.Calc
T.eq(Prices.Age(2589), 3 * DAY, "a price's age")
T.eq(Prices.Age(2592), nil, "one too old to use has none")
T.eq(Prices.Age(9999), nil, "no price, no age")
book.items[2590] = { p = 50, t = now - 3600 }
T.eq(Calc.STALE, DAY, "stale after a day")
T.eq((Calc.Stale(2590)), false, "an hour old: not stale")
local old, age = Calc.Stale(2589)
T.eq(old, true, "three days old: stale")
T.eq(age, 3 * DAY, "and its age with it")
T.eq((Calc.Stale(9999)), false, "no price: not stale")
book.items[2590] = nil

-- Professionally Lost loaded, the switch off: nothing of its is read.
local reads = 0
InstallProfLost({ prices = {
	[2589] = { 80, now - 1 * DAY },      -- seen later than ours
	[2592] = { 250, now - 2 * DAY },     -- ours is too old
	[4306] = { 500, now - 5 * DAY },     -- we have none
	[2318] = { 40, now - 20 * DAY },     -- its own is too old
	[2319] = { 60, now - 6 * DAY },      -- ours was seen later
} })
local price = ProfLost.Scan.Price
ProfLost.Scan.Price = function(itemID)
	reads = reads + 1
	return price(itemID)
end
T.snapshot()
book.items[2319] = { p = 70, t = now - 1 * DAY }
GAME.settings.plPrices = false
T.eq(Prices.Get(2589), 100, "switch off: ours")
T.eq(Prices.Get(4306), nil, "switch off: its price is not used")
T.eq(reads, 0, "and not even read")

-- The switch on.
GAME.settings.plPrices = true
T.eq(Prices.Get(2589), 80, "its price, seen later than ours")
T.eq(Prices.Get(2592), 250, "its price where ours is too old")
T.eq(Prices.Get(4306), 500, "its price where we have none")
T.eq(Prices.Get(2318), nil, "its price older than two weeks is not used either")
T.eq(Prices.Get(2319), 70, "ours, seen later than its")
T.eq(Prices.Get(9999), nil, "neither has one")
T.ok(reads > 0, "its scan was read")

-- "Any prices at all": its count too while the switch is on.
book.items = {}
T.eq(Prices.Has(), true, "none of ours, but its are used")
GAME.settings.plPrices = false
T.eq(Prices.Has(), false, "switch off: none")

-- Its next version answers something else: ours is used, no error.
GAME.settings.plPrices = true
book.items[2589] = { p = 100, t = now - 3 * DAY }
ProfLost.Scan.Price = function() return "soon", {} end
T.eq(Prices.Get(2589), 100, "an odd answer falls back to ours")
ProfLost.Scan.Price = function() error("renamed") end
T.eq(Prices.Get(2589), 100, "a raising call falls back to ours")
local scan = ProfLost.Scan
ProfLost.Scan = nil
T.eq(Prices.Get(2589), 100, "a missing table falls back to ours")
T.eq(Prices.Has(), true, "and ours still count")
-- (The test's own changes to the stand-in are undone before its tables are compared.)
ProfLost.Scan = scan
scan.Price = price
T.untouched("the whole test")

return T.done()
