-- The Blizzard Layout's rules (WindowLayout.lua's top part, plain arithmetic): its size, the side
-- tabs' places and which of them show, the page tabs' widths, the craft bar's rows, the clamp and
-- the skill-up arrows. Each number from the client's own FrameXML (branch "forever"), as the file's
-- header cites. Its frames run end to end in test_window_smoke.lua ("Blizzard Layout").
-- Runs in Tools/tests/run.py, and alone: any Lua 5.1 with the plugin's folder as the working directory.
local ns = { ok = true }   -- (no ns.Win: the file stops after its arithmetic)
local chunk
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	chunk = loadfile(root .. "/WindowLayout.lua")
	if chunk then break end
end
assert(chunk, "WindowLayout.lua not found: run from the plugin's folder")
chunk("DaylightRecipes", ns)
local Lay = assert(ns.WinLayout, "the layout's rules")

local n = 0
local function eq(got, want, what)
	n = n + 1
	if got ~= want then error(("FAILED: %s (got %s, wanted %s)"):format(tostring(what), tostring(got), tostring(want)), 2) end
end
local function ok(cond, what)
	n = n + 1
	if not cond then error("FAILED: " .. tostring(what), 2) end
end

-- ---- the frame -------------------------------------------------------------------------------
eq(Lay.W, 673, "the game's frame is 673 wide (Camelot/Blizzard_ProfessionsFrame.xml:11)")
eq(Lay.LIST_W, 304, "the list 304 (Camelot/Blizzard_ProfessionsCrafting.lua:25)")
eq(Lay.DETAIL_W - 1, 360, "the details the game's 360 and their edge")
local w, h = Lay.Size(560)
ok(w == 673 and h == 560, "the player's height kept")
eq(select(2, Lay.Size(400)), Lay.MIN_H, "never under its least")
eq(select(2, Lay.Size(nil)), 560, "no setting: the default height")
eq(Lay.ListTop(true), 72 - 24, "Blizzard Style: the game's -72, its title bar outside our frame")
ok(Lay.ListTop(false) > 36, "another look: under the header")

-- ---- the side tabs: on the left, 60 under the top, each next 2 under the last ----------------
eq(Lay.SideY(1, 55, 2), 60, "the first 60 under the frame's top (Camelot xml:20-21)")
eq(Lay.SideY(2, 55, 2), 60 + 57, "each next 2 under the last (xml:28-29)")
eq(Lay.SideY(4, 38, 2), 60 + 3 * 40, "the same steps at another size")
-- Which show: all when there is room, else whole tabs, "+N" and the dots, the open one kept.
local list, left = Lay.SideFit(6, 3, true, 600, 55, 2)
ok(#list == 6 and left == 0, "seven tabs fit 600: all of them")
list, left = Lay.SideFit(8, nil, true, 300, 55, 2)
-- (300 holds 5: three professions, "+N" and the dots.)
ok(#list == 3 and left == 5, "a short window: three, +5 and the dots: " .. #list .. " " .. left)
list, left = Lay.SideFit(8, 7, true, 300, 55, 2)
eq(list[#list], 7, "the open profession is never behind +N")
eq(left, 5, "the rest behind it")
list, left = Lay.SideFit(8, nil, false, 300, 55, 2)
ok(#list == 4 and left == 4, "no dots: one more profession shows")
list, left = Lay.SideFit(3, 1, true, 30, 55, 2)
ok(#list == 1 and left == 2, "never fewer than one")
for need = 0, 9 do
	for room = 0, 700, 50 do
		local l2, rest = Lay.SideFit(need, need > 0 and need or nil, true, room, 55, 2)
		eq(#l2 + rest, need, "every profession is a tab or behind +N")
	end
end

-- ---- the page tabs under the window: never cut, at least 100 in Blizzard Style ----------------
local widths, xs, whole = Lay.TabWidths({ 40, 90, 60 }, true)
ok(widths[1] == 100 and widths[2] == 110 and widths[3] == 100, "words plus 20, at least 100 (TabSystemTemplates.lua:225-253)")
ok(xs[1] == 0 and xs[2] == 101 and xs[3] == 212, "1 apart (TabSystemTemplate's spacing)")
eq(whole, 312, "the row's width")
widths, xs = Lay.TabWidths({ 40, 90 }, false)
ok(widths[1] == 64 and widths[2] == 114 and xs[2] == 66, "another look: words plus 24, 2 apart")
for tw = 0, 400, 7 do
	local wb = Lay.TabWidths({ tw }, true)[1]
	local wo = Lay.TabWidths({ tw }, false)[1]
	ok(wb >= tw + 20 and wo >= tw + 24, "a tab always holds its words")
end

-- ---- the craft bar: Create All, the spinner and Create on one row when they fit ---------------
local bar = { all = 110, minus = 26, count = 46, plus = 26, make = 96 }
eq(Lay.BarTwoRows(bar, Lay.DETAIL_W), false, "English fits one row in the details' 361")
bar.all = 160
eq(Lay.BarTwoRows(bar, Lay.DETAIL_W), true, "a long Create All takes a row of its own")

-- ---- the clamp: the art and the tabs on the screen -------------------------------------------
local l, r, t, b = Lay.ClampInsets(9, 6, 24, 4, 45, 34)
ok(l == -54 and r == 6 and t == 24 and b == -34, "side tabs left of the art, page tabs under the frame")
l, r, t, b = Lay.ClampInsets(0, 0, 0, 0, 0, 0)
ok(l == 0 and r == 0 and t == 0 and b == 0, "nothing hanging: the frame's own")
l, r, t, b = Lay.ClampInsets(9, 6, 24, 4, 0, 0)
ok(l == -9 and r == 6 and t == 24 and b == -4, "no tabs: the art alone, as Host's own clamp")

-- ---- the rows' skill-up arrows (Blizzard_ProfessionsRecipeList.lua:294-303) -------------------
eq(Lay.Arrow(1, true), "Professions-Icon-Skill-High", "orange: the high arrow")
eq(Lay.Arrow(2, true), "Professions-Icon-Skill-Medium", "yellow")
eq(Lay.Arrow(3, true), "Professions-Icon-Skill-Low", "green")
eq(Lay.Arrow(4, true), nil, "gray: none")
eq(Lay.Arrow(1, false), nil, "one that can't skill up: none")
eq(Lay.KITS[164], "Blacksmithing", "a profession's art kit by its skill line")
eq(Lay.KITS[129], nil, "First Aid has none (the default fill)")

return ("ok, %d checks"):format(n)
