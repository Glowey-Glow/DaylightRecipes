-- 3.0.2: every popup of ours has a fully solid background, whatever the opacity settings.
-- ns.SkinWindow (Core.lua) is how windows, panels and popups are dressed. This runs its own text,
-- cut out of Core.lua, against a stand-in for Daylight UI's API.Skin that keeps what was asked:
--   * a window or a strip's bar: Daylight UI's window opacity (opts.window, no bgAlpha), or the
--     player's own (bgAlpha = the Window Opacity setting) with "Use Daylight UI's Opacity" off;
--   * anything dressed with extra.solid (a strip's list, the Professionally Lost question): a
--     background of 1 in every case, and "solid" itself is never handed on to Daylight UI.
-- And the popups that dress themselves ask Daylight UI for 1 outright: the professions menu
-- (WindowMenu.lua, also test_window_smoke.lua) and the "Are you sure?" box (Shop.lua).
-- luacheck: globals ADDON_ROOT
-- luacheck: read globals T
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Core.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Core.lua not found")
local function read(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a"):gsub("\r", "")
	f:close()
	return src
end

local core = read("Core.lua")
local from = assert(core:find("local skinned = setmetatable", 1, true), "Core.lua: the skinned table")
local to = assert(core:find("function ns.Print", from, true), "Core.lua: what follows the skin helpers")
local asked = {}
local settings = {}
local ns = { Get = function(key) return settings[key] end }
local API = { Skin = function(frame, opts) asked[frame] = opts end }
local chunk = assert(loadstring("local ns, API = ... " .. core:sub(from, to - 1), "@Core.lua (skin helpers)"))
chunk(ns, API)

local OPACITIES = {
	{ "Daylight UI's opacity", { duiOpacity = true, opacity = 0.85 } },
	{ "our own, at its lowest", { duiOpacity = false, opacity = 0.1 } },
	{ "our own, at 0.5", { duiOpacity = false, opacity = 0.5 } },
	{ "nothing set", {} },
}
for _, o in ipairs(OPACITIES) do
	T.case("a popup's background is 1 with " .. o[1], function()
		settings = o[2]
		local popup, window = {}, {}
		ns.SkinWindow(popup, { solid = true })
		ns.SkinWindow(window)
		T.eq(asked[popup].bgAlpha, 1, "a popup is asked fully solid")
		T.eq(asked[popup].solid, nil, "\"solid\" is ours: Daylight UI is not handed it")
		T.eq(asked[popup].window, true, "in the window's shell and color")
		if o[2].duiOpacity == false then
			T.eq(asked[window].bgAlpha, o[2].opacity, "a window follows our Window Opacity")
		else
			T.eq(asked[window].bgAlpha, nil, "a window follows Daylight UI's window opacity")
		end
		-- The setting changes: every one is dressed again, the popup still solid.
		settings = { duiOpacity = false, opacity = 0.3 }
		ns.ReskinWindows()
		T.eq(asked[popup].bgAlpha, 1, "dressed again after a change: still solid")
		T.eq(asked[window].bgAlpha, 0.3, "and the window at the new opacity")
	end)
end

T.case("a popup with no background of its own is left without one", function()
	settings = { duiOpacity = false, opacity = 0.4 }
	local bare = {}
	ns.SkinWindow(bare, { noBackground = true })
	T.eq(asked[bare].bgAlpha, nil, "noBackground: no opacity asked")
end)

-- Which of our frames are dressed how: every dressing call in the plugin, by file. A new popup
-- has to be put on one side or the other here.
T.case("every frame the plugin dresses is a window (follows the opacity) or a solid popup", function()
	local SOLID = {
		["Shop.lua"] = { 'ns.SkinWindow(list, { solid = true })', 'ns.Host.Skin(f, { bgAlpha = 1 })' },
		["ProfLost.lua"] = { 'ns.SkinWindow(f, { solid = true })', 'ns.SkinWindow(f, { solid = true })' },
		["PriceSources.lua"] = { 'ns.SkinWindow(f, { solid = true })', 'ns.SkinWindow(f, { solid = true })' },
		["WindowMenu.lua"] = { 'API.Skin(menu, LOOK)', 'API.Skin(menu, LOOK)' },
	}
	local FOLLOWS = {
		["Shop.lua"] = { 'ns.SkinWindow(s)' },
		["Window.lua"] = { 'ns.SkinWindow(win)', 'ns.SkinWindow(win)' },
		["Pane.lua"] = { 'ns.SkinWindow(mogulPane)', 'ns.SkinWindow(mogulPane)', 'ns.Host.Skin(foldTab, { noBevel = true })' },
		["EnchantRow.lua"] = { 'ns.Host.Skin(slot, { noBevel = true })' },
		-- (The tours' cards and notes: Guide.lua is shared with the other plugins, as it is.)
		["Guide.lua"] = { 'API.Skin(card, { window = true })', 'API.Skin(toast, { window = true })', 'API.Skin(toast, { window = true })',
			'API.Skin(card, { window = true })', 'API.Skin(note, { window = true })', 'API.Skin(note, { window = true })' },
		["Core.lua"] = { 'API.Skin(frame, opts)' },
	}
	T.ok(read("WindowMenu.lua"):find("local LOOK = { bgAlpha = 1, noBevel = true }", 1, true), "the menu's look is a background of 1")
	local toc = read("DaylightRecipes.toc")
	local files = 0
	for file in toc:gmatch("\n([%w_]+%.lua)") do
		files = files + 1
		local want = {}
		for _, call in ipairs(SOLID[file] or {}) do want[#want + 1] = call end
		for _, call in ipairs(FOLLOWS[file] or {}) do want[#want + 1] = call end
		table.sort(want)
		local got = {}
		for line in read(file):gmatch("[^\n]+") do
			local code = line:gsub("%-%-.*$", "")
			-- (ns.Host.Skin: Host.lua's API.Skin, dressed again after a look change.)
			local call = code:match("(ns%.SkinWindow%(.-%))%s*$") or code:match("(ns%.Host%.Skin%(.-%))%s*$")
				or code:match("(API%.Skin%(.-%))%s*$")
				or code:match("(API%.Skin%(.-%)) end%s*$")
			if call and not code:find("function ns.SkinWindow", 1, true) and not code:find("pairs(skinned)", 1, true) then
				got[#got + 1] = call
			end
		end
		table.sort(got)
		T.eq(table.concat(got, " | "), table.concat(want, " | "), file .. ": its dressing calls are the ones listed")
	end
	T.ok(files >= 25, "the plugin's files were read: " .. files)
end)

return T.done()
