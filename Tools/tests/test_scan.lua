-- Professionally Lost's scan tells its listeners of every step and of the Auction House opening
-- and closing. With "Scanned Prices" handed over, our prices are thrown away and the window drawn
-- again only when a scan of its has ended or its "last finished scan" stamp moved: not every two
-- seconds all through a scan.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI ProfLost ProfLostCharDB ProfLost_Open ProfLost_Panel DaylightRecipesDB
-- luacheck: read globals NS T Fire NewObj InstallProfLost
local ns = NS
local PL = ns.ProfLost

local CP = InstallProfLost({ prices = { [2589] = { 95, GAME.clock - 10 } }, scan = true })
GAME.settings.plPrices = true
GAME.scan.last = GAME.clock - 3600           -- it finished a scan an hour ago
T.snapshot()

local heard = 0
PL.OnChange(function(what) if what == "prices" then heard = heard + 1 end end)
PL.Listen()
local forgot = ns.Calc.version

-- The Auction House opens: its listener runs, nothing of its changed.
CP.Scan.notify()
T.run(5)
T.eq(heard, 0, "the Auction House opening is not a change of prices")
T.eq(ns.Calc.version, forgot, "our prices are not thrown away for it")

-- A scan: it starts, then steps twice a second for twenty seconds.
GAME.scan.running = true
CP.Scan.notify()
for _ = 1, 40 do
	T.run(0.5)
	CP.Scan.notify()
end
T.eq(heard, 0, "nothing while its scan runs, however often it steps")
T.eq(ns.Calc.version, forgot, "and our prices stay as they are through it")
T.eq(GAME.redraws or 0, 0, "the window is not drawn again and again")

-- It finishes: one change.
GAME.scan.running = false
GAME.scan.last = GAME.clock
CP.Scan.notify()
T.run(5)
T.eq(heard, 1, "its scan ended: one change")
T.eq(ns.Calc.version, forgot + 1, "our prices are thrown away once, so its new ones count")

-- The Auction House closes: nothing.
CP.Scan.notify()
T.run(5)
T.eq(heard, 1, "the Auction House closing is not a change")

-- A search stopped by hand keeps what it priced but leaves no stamp: its end still counts.
GAME.scan.running = true
CP.Scan.notify()
T.run(1)
GAME.scan.running = false
CP.Scan.notify()
T.run(5)
T.eq(heard, 2, "a stopped search: one change at its end")

-- Not handed over: its scans are none of ours.
GAME.settings.plPrices = false
GAME.scan.running = true
CP.Scan.notify()
GAME.scan.running = false
GAME.scan.last = GAME.clock + 60
CP.Scan.notify()
T.run(5)
T.eq(heard, 2, "with Scanned Prices off nothing is heard")
GAME.settings.plPrices = true

-- A later version of its where neither can be asked: every call counts, gathered to one, as before.
CP.Scan.Running, CP.Scan.LastTime = nil, nil
CP.Scan.notify()
CP.Scan.notify()
T.run(5)
T.eq(heard, 3, "neither readable: its calls count again, gathered to one")
CP.Scan.Running = function() error("changed in a later version") end
CP.Scan.LastTime = function() error("changed in a later version") end
CP.Scan.notify()
T.run(5)
T.noErrors("functions of its that raise")
T.untouched("listening to its scan")

return T.done()
