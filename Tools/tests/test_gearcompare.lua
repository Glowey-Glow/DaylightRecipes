-- Tips.GearCompare: Glowey's Gear's comparison beside our item tooltips (GloweyGearAPI.Compare,
-- its version 2): asked with the item the tooltip shows, taken away for a tooltip without one,
-- nothing at all without Gear or with an older Gear, never an error.
-- luacheck: globals GloweyGearAPI
-- luacheck: read globals NS T ADDON_ROOT
local function read(file)
	local f = assert(io.open(ADDON_ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	return src
end
assert(loadstring(read("Tips.lua"), "@Tips.lua"))("DaylightRecipes", NS)
local Tips = NS.Tips

local asked, hid = {}, 0
local function Tip(link) return { GetItem = function() return link and "Name" or nil, link end } end

T.case("without Gear, or an older Gear: nothing, no error", function()
	rawset(_G, "GloweyGearAPI", nil)
	Tips.GearCompare(Tip("item:1"))
	rawset(_G, "GloweyGearAPI", { version = 1, Upgrade = function() return false end })
	Tips.GearCompare(Tip("item:1"))
	T.ok(true, "no error")
end)

T.case("an item tooltip asks Gear; one without an item takes it away", function()
	rawset(_G, "GloweyGearAPI", { version = 2,
		Compare = function(tip, link) asked[#asked + 1] = { tip = tip, link = link } return true end,
		HideCompare = function() hid = hid + 1 end })
	local tip = Tip("item:2589")
	Tips.GearCompare(tip)
	T.eq(#asked, 1, "asked once")
	T.eq(asked[1].tip, tip, "beside our tooltip")
	T.eq(asked[1].link, "item:2589", "with the item it shows")
	Tips.GearCompare(Tip(nil))
	T.eq(#asked, 1, "no item: not asked")
	T.eq(hid, 1, "and Gear's is taken away")
	Tips.GearCompare({})
	T.eq(hid, 2, "a tooltip that can't say: taken away too")
	GloweyGearAPI.Compare = function() error("raises") end
	Tips.GearCompare(tip)
	T.ok(true, "Gear raising never reaches us")
	rawset(_G, "GloweyGearAPI", nil)
end)

return T.done()
