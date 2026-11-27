-- Prices.DaylightLows (for a plugin's price history, API.lua's DaylightLows): Daylight UI's
-- daily lows of an item, read through its Auction House module's Store.Lows, copied, the bad
-- entries left out; nil without its module, without lows, or with Auction House prices off.
-- luacheck: globals DaylightUI
-- luacheck: read globals NS T GAME
local Prices = NS.Prices
local LOWS = { ["2589"] = { 20400, 100, 20401, 0, 20402, 120, "x", 5 } }
local enabled = true
DaylightUI = {
	GetModule = function(_, name)
		if name ~= "AuctionHouse" then return nil end
		return { enabled = enabled, ns = {
			Ruleset = { Key = function() return "rules" end },
			Store = {
				Min = function() return nil end,
				SeenAt = function() return nil end,
				Lows = function(rkey, key) return rkey == "rules" and LOWS[key] or nil end,
			},
		} }
	end,
}
local lows = Prices.DaylightLows(2589)
T.ok(lows ~= nil, "its lows")
T.eq(#lows, 4, "two good days: a price of 0 and a bad day left out")
T.eq(lows[1], 20400, "the first day")
T.eq(lows[2], 100, "its low")
T.eq(lows[3], 20402, "the next good day")
T.eq(lows[4], 120, "its low")
T.ok(lows ~= LOWS["2589"], "a copy, not its own table")
T.eq(Prices.DaylightLows(9999), nil, "none for an item it hasn't seen")
enabled = false
T.eq(Prices.DaylightLows(2589), nil, "none while its module is off")
DaylightUI = nil
T.eq(Prices.DaylightLows(2589), nil, "none without Daylight UI")
return T.done()
