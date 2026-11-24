-- The window's rules, as plain arithmetic: which of its three states it is in, what is remembered,
-- which tabs show, and the sums that guarantee no label is cut. Nothing here calls the game, so the
-- offline tests (Tools\tests) load this file alone and check every rule; Window.lua, WindowList.lua
-- and WindowMenu.lua draw what these functions answer.
--   Compact   one column, 420 x 560 by default (the column as wide as its tab row needs, the
--             height the player's: 400 to 720)
--   Expanded  the column plus a 360 detail column on its right
--   Rolled Up the header and the craft bar only: 420 x 80
-- Sizes are the design's (design\facelift.md 3.1 and principle 6): header 36, tabs 28, craft bar 44,
-- summary line 40, edge padding 14, gap 8, list rows 20.
local _, ns = ...

local State = {}
ns.WinState = State

State.W = 420            -- the column, at least
State.MAX_W = 520        -- and at most, in the longest language (then the tabs take a second row)
State.DETAIL = 360       -- the detail column
State.H = 560
State.MIN_H, State.MAX_H = 400, 720
State.HEADER = 36
State.TABS = 28
State.FOOT = 44          -- the craft bar
State.SUMMARY = 40       -- the picked recipe in one line, above the craft bar
State.PAD = 14
State.GAP = 8
State.ROW = 20
State.VERSION = 2        -- the layout the saved state is for (1: the 1000 x 640 window)

State.TAB_KEYS = { "recipes", "guide", "materials", "queue", "missing" }
-- The tabs Professionally Lost's guide stands in for, for a profession handed to it.
State.HANDED = { guide = true, materials = true }

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ---------------------------------------------------------------------------------------------
-- What is remembered (DaylightRecipesDB.win)
-- ---------------------------------------------------------------------------------------------
-- v        the layout these were saved for
-- spot     { left, top } of the window in the screen's units, from its bottom-left corner
-- rolled   true while rolled up
-- details  { [tab] = true / false }: the detail column open on that tab (nil: the default)
-- tab      the tab last open
-- folded, canMake, skillUps: the recipe list's (unchanged)
-- The height is the "Window Height" setting (Core.lua), so the options slider and a drag agree.

-- The saved state made fit for this layout. A state saved for the old window (or none) gets the
-- compact default once: its place, roll-up, details and tab are dropped, the list's own choices
-- kept. True when that happened (an existing player's first open: the What's New line says why).
function State.Migrate(win)
	if type(win) ~= "table" then return false end
	win.folded = type(win.folded) == "table" and win.folded or {}
	if win.v == State.VERSION then
		if type(win.details) ~= "table" then win.details = {} end
		return false
	end
	local had = win.point ~= nil or next(win.folded) ~= nil or win.canMake ~= nil or win.skillUps ~= nil
	win.point, win.spot, win.rolled, win.tab = nil, nil, nil, nil
	win.details = {}
	win.v = State.VERSION
	return had
end

-- A height the window may have: the player's, within 400 to 720 and the screen (less a margin
-- for the header staying reachable). screenH nil: only the limits.
function State.ClampHeight(h, screenH)
	h = tonumber(h) or State.H
	local most = State.MAX_H
	if type(screenH) == "number" and screenH > 0 then most = min(most, max(State.MIN_H, floor(screenH))) end
	return floor(max(State.MIN_H, min(most, h)) + 0.5)
end

-- Whether the detail column may open at all on this page: the five tabs have one; an alt's
-- recipes, a gathering profession's page and the camping page have nothing to detail.
function State.HasDetails(tab, other)
	if other then return false end
	for _, key in ipairs(State.TAB_KEYS) do
		if key == tab then return true end
	end
	return false
end

-- Whether the detail column is open on this tab: as the player left it there, else `default`
-- ("Open Details by Default").
function State.DetailsOpen(win, tab, other, default)
	if not State.HasDetails(tab, other) then return false end
	local saved = type(win) == "table" and type(win.details) == "table" and win.details[tab]
	if saved == true then return true end
	if saved == false then return false end
	return default == true
end

function State.SetDetails(win, tab, open)
	if type(win) ~= "table" or not tab then return end
	win.details = type(win.details) == "table" and win.details or {}
	win.details[tab] = open and true or false
end

function State.SetRolled(win, rolled)
	if type(win) ~= "table" then return end
	win.rolled = rolled and true or nil
end

-- "rolled", "expanded" or "compact". Rolled up wins: the details are remembered under it and are
-- back when it unrolls. rolled: whether it is rolled up now (nil: as saved). The window passes
-- false while there is nothing to roll up to (no craft bar: someone's linked recipes, no
-- profession open) or a tour is showing it: the saved choice is kept and is back afterwards.
function State.Mode(win, tab, other, default, rolled)
	if rolled == nil then rolled = type(win) == "table" and win.rolled == true end
	if rolled then return "rolled" end
	if State.DetailsOpen(win, tab, other, default) then return "expanded" end
	return "compact"
end

-- The window's size in a state. col: the column's width (TabLayout's), h: the player's height,
-- foot: the craft bar's height now (44; taller when its buttons take two rows or an enchant's
-- item row shows).
function State.Size(mode, col, h, foot)
	col = col or State.W
	if mode == "rolled" then return col, State.HEADER + (foot or State.FOOT) end
	if mode == "expanded" then return col + State.DETAIL, h or State.H end
	return col, h or State.H
end

-- A top-left corner that keeps the header on screen: { left, top } from the screen's bottom-left.
function State.ClampSpot(left, top, w, screenW, screenH)
	left = max(0, min(left, max(0, screenW - min(w, screenW))))
	top = max(State.HEADER, min(top, screenH))
	return floor(left + 0.5), floor(top + 0.5)
end

-- ---------------------------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------------------------

-- The tabs that show, in order. handed: Professionally Lost has this profession's Leveling Guide
-- (ns.ProfLost.Handed("guide", line)), so Leveling Guide and Materials are left out.
function State.Tabs(handed)
	local out = {}
	for _, key in ipairs(State.TAB_KEYS) do
		if not (handed and State.HANDED[key]) then out[#out + 1] = key end
	end
	return out
end

-- The tab to show when `tab` was asked for: itself while it shows, else Recipes.
function State.TabFor(tab, handed)
	for _, key in ipairs(State.Tabs(handed)) do
		if key == tab then return key end
	end
	return "recipes"
end

State.TAB_PAD, State.TAB_MIN_PAD, State.TAB_GAP, State.TAB_EDGE = 9, 4, 4, 8

-- The tab row for these text widths (in order), and the column width it asks for.
-- Returns { col, rows, pad, tabs = { { x, row, w }, ... } } with x from the column's left edge.
--   1. The design's padding (9 a side, 4 between, 8 at the edges) in a 420 column when that fits.
--   2. Else the column grows with the row, to 520 at most.
--   3. Else the padding shrinks, to 4 a side at least.
--   4. Else the tabs take a second row (the design's fallback past 520), at the full padding.
-- A label is never cut: a tab is always its text's width plus padding, and a single tab wider
-- than 520 widens the column past it rather than lose a letter.
-- limits.minTab: no tab narrower than that (Blizzard Style: its tab art's two end caps, as
-- PanelTemplates_TabResize's minWidth, WindowBlizzard.lua's Blz.TabMin).
function State.TabLayout(widths, limits)
	local lo = limits and limits.min or State.W
	local hi = limits and limits.max or State.MAX_W
	local least = limits and tonumber(limits.minTab) or 0
	local gap, edge = State.TAB_GAP, State.TAB_EDGE
	local n = #widths
	local function tabW(i, pad) return max(ceil(widths[i]) + 2 * pad, least) end
	local function need(pad)
		local sum = max(0, n - 1) * gap + 2 * edge
		for i = 1, n do sum = sum + tabW(i, pad) end
		return sum
	end
	local out = { rows = 1, pad = State.TAB_PAD, tabs = {} }
	local function place(pad, breakAt)
		local x, row = edge, 1
		local widest = 0
		for i = 1, n do
			local w = tabW(i, pad)
			if breakAt and i == breakAt then x, row = edge, 2 end
			out.tabs[i] = { x = x, row = row, w = w }
			x = x + w + gap
			widest = max(widest, x - gap + edge)
		end
		return widest
	end
	if need(State.TAB_PAD) <= hi then
		out.col = max(lo, place(State.TAB_PAD))
		return out
	end
	for pad = State.TAB_PAD - 1, State.TAB_MIN_PAD, -1 do
		if need(pad) <= hi then
			out.pad = pad
			out.col = max(lo, place(pad))
			return out
		end
	end
	-- Two rows: break where the first row is as full as it can be within the limit.
	local pad = State.TAB_PAD
	local x, breakAt = edge, n + 1
	for i = 1, n do
		local w = tabW(i, pad)
		if i > 1 and x + w + edge > hi then
			breakAt = i
			break
		end
		x = x + w + gap
	end
	out.rows = breakAt <= n and 2 or 1
	out.col = max(lo, place(pad, breakAt <= n and breakAt or nil))
	return out
end

-- The column's width: what the tab row asks (TabLayout's col, worked out with the queue's tab at
-- its reserved longest), and what the craft bar's one row asks with its words at their reserved
-- longest (CraftBarNeed), up to 520. So a language whose bar words are longer than its tabs
-- (German: "Warteschlange") gets a column its bar fits in one row, and the width is the same
-- whatever is picked or queued. Past 520 the bar keeps its two-row fallback.
function State.Column(tabCol, barNeed)
	local col = max(State.W, tabCol or State.W)
	if type(barNeed) == "number" then col = max(col, min(State.MAX_W, ceil(barNeed))) end
	return col
end

-- Whether every tab of a layout lies inside its column (what the tests assert).
function State.TabsFit(layout)
	for _, t in ipairs(layout.tabs) do
		if t.x < 0 or t.x + t.w > layout.col then return false end
	end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- The craft bar and the header
-- ---------------------------------------------------------------------------------------------

-- The craft bar's buttons, right to left: Create, Max, the count (+, box, -), Queue. Each is as
-- wide as its words (never narrower than the design's), so in a long language they may not fit one
-- row of the column: then the count and Queue go on a row of their own above. True: two rows.
-- w: { make, max, plus, count, minus, queue }.
function State.CraftBarNeed(w)
	return State.PAD + w.make + 8 + w.max + 8 + w.plus + 4 + w.count + 4 + w.minus + 8 + w.queue + State.PAD
end

function State.CraftBarTwoRows(w, col)
	return State.CraftBarNeed(w) > (col or State.W)
end

-- The two rows' widths when the bar takes two (bottom: Create and Max; above: the count and
-- Queue), for the tests: each must fit the column too.
function State.CraftBarRowWidths(w)
	return State.PAD + w.make + 8 + w.max + State.PAD,
		State.PAD + w.plus + 4 + w.count + 4 + w.minus + 8 + w.queue + State.PAD
end

-- The least each button is (the design's widths at 420): Queue 76, the count 46 with 26 each side,
-- Max 56, Create 96; Stop 96.
State.LEAST = { make = 96, max = 56, queue = 76, stop = 96, plus = 26, minus = 26, count = 46 }

-- The header's name in the largest of the type scale's sizes that fits its room (18, 15, 13):
-- returns "title", "head" or "body". widths: the name's width at each. At 13 a name fits the room
-- the header has (246 at 420 with its four buttons: about 35 letters), and the name is set to wrap
-- rather than be cut if a longer one ever came.
function State.NameSize(widths, room)
	if (widths.title or 0) <= room then return "title" end
	if (widths.head or 0) <= room then return "head" end
	return "body"
end

-- The header's name and the note after it (the skill; for someone's linked recipes "<name>'s
-- recipes", the only mark that they are not yours). widths: the name's width at each size; room:
-- HeaderRoom; noteW: the note's width (0: none); must: the note may not be dropped.
-- Returns size, nameWidth, showNote, noteWidth (nil: its own; a number: it wraps in that width).
--   An ordinary note (the skill) drops when the name leaves no room: the 2 px line under the header
--   still shows it.
--   A note that must show makes the name step down the type scale first, then wrap in what the
--   note leaves (60 at least), then wraps itself: neither is ever cut and the note never dropped.
State.NAME_LEAST = 60
function State.HeaderFit(widths, room, noteW, must)
	noteW = noteW or 0
	if not must or noteW <= 0 then
		local size = State.NameSize(widths, room)
		local nameW = min(ceil(widths[size] or 0) + 2, room)
		return size, nameW, noteW > 0 and nameW + 10 + noteW <= room, nil
	end
	local size = State.NameSize(widths, room - 10 - noteW)
	local nameW = min(ceil(widths[size] or 0) + 2, max(State.NAME_LEAST, room - 10 - noteW))
	local left = room - 10 - nameW
	return size, nameW, true, noteW > left and max(40, left) or nil
end

-- A scrolled list's thumb: its size and how far down its track it sits, or nil when everything
-- fits (view: the height on show; total: the height of all of it; at: how far it is scrolled).
function State.Thumb(view, total, at)
	if not (view and total) or view <= 0 or total <= view then return nil end
	local size = min(view, max(24, view * view / total))
	local most = total - view
	return size, (view - size) * max(0, min(most, at or 0)) / most
end

-- The room the header has for the name and, after it, the skill: the column less the icon (10 +
-- 20 + 8), the menu's arrow (6 + 8), and the buttons on the right (each 20 with a 6 gap, 10 at
-- the edge, 8 before them).
function State.HeaderRoom(col, buttons)
	return col - (10 + 20 + 8) - (6 + 8) - (10 + buttons * 26 + 8)
end

-- The title bar's profession chips: which of them show, and how many go behind the "+N" chip.
-- widths: each chip's width in the bar's order; open: the index of the open profession's chip (or
-- nil); room: the width there is; gap: between two chips; plus(n): the width of a "+n" chip.
-- As many as fit from the front, whole (a chip is never cut or shrunk). The open one always
-- shows: when it would be among those left out it takes the last place on show. Returns the
-- indexes on show, in the order they are drawn, and how many are left out.
function State.ChipFit(widths, open, room, gap, plus)
	local n = #widths
	if open and (open < 1 or open > n) then open = nil end
	for k = n, 0, -1 do
		local list = {}
		local forward = open ~= nil and open > k and k >= 1
		for i = 1, forward and k - 1 or k do list[#list + 1] = i end
		if forward then list[#list + 1] = open end
		local w = 0
		for i, index in ipairs(list) do w = w + widths[index] + (i > 1 and gap or 0) end
		local left = n - #list
		if left > 0 then w = w + (#list > 0 and gap or 0) + plus(left) end
		-- (The open one alone is the least there can be: shown even when the bar is narrower.)
		if w <= room or k <= (open and 1 or 0) then return list, left end
	end
	return {}, n
end

-- The professions menu's width: its longest line plus its icon and margins, at least the design's
-- 210 and at most the column less a 2 px margin each side (it opens inside the window).
function State.MenuWidth(textWidth, col)
	local want = ceil(textWidth) + 44 + 14
	return max(210, min(want, (col or State.W) - 4))
end

-- ---------------------------------------------------------------------------------------------
-- The secure Stop
-- ---------------------------------------------------------------------------------------------

-- Whether two rectangles (left, bottom, width, height in the same units) are the same spot, to
-- half a unit: the Stop the window draws against the secure Stop that takes the click.
function State.SameRect(a, b)
	if not (a and b) then return false end
	for i = 1, 4 do
		if type(a[i]) ~= "number" or type(b[i]) ~= "number" or math.abs(a[i] - b[i]) > 0.5 then return false end
	end
	return true
end

-- WHAT THE ROLLED-UP WINDOW'S BAR IS FOR. Rolled up there is no list and no tab to say it, so the
-- bar says it itself and acts on that, by the same rules the open window has, in this order:
--   "run"    something is being made: its recipe, how far, Stop (the bar's own rule on every tab);
--   "queue"  the crafting queue has an entry for the open profession: the first of them, as the
--            Queue tab's Craft Next takes it (Queue.NextHere): made min(its count, what you can
--            make now) at a press; with none makeable the button is off and the bar says you are
--            short of materials (the Queue tab: "You're short of materials for the next one").
--            Nothing is skipped: the open window doesn't either; the order is the player's, and a
--            press on the bar's line opens the Queue tab, where entries are moved;
--   "pick"   else the picked recipe, as the Recipes tab's bar: Queue, the count, Max, Create
--            (Create off when you can make none of it, or the game has it disabled);
--   "none"   else nothing (the window is then not rolled up at all: WindowList's CanRoll).
-- run: true while a run is under way (or a fight keeps its Stop out); nextUp: { count, can } for
-- the queue's next entry of the open profession, or nil; pick: { can, blocked } for the picked
-- recipe, or nil. Returns { kind, make (how many a press makes: "queue"), off (the main button),
-- short (short of materials for the queue's next) }.
function State.RolledBar(run, nextUp, pick)
	if run then return { kind = "run", off = false, short = false } end
	if type(nextUp) == "table" then
		local n = math.max(0, math.min(tonumber(nextUp.count) or 0, tonumber(nextUp.can) or 0))
		local blocked = nextUp.blocked == true
		return { kind = "queue", make = n, off = n < 1 or blocked, short = n < 1 }
	end
	if type(pick) == "table" then
		return { kind = "pick", off = pick.blocked == true or (tonumber(pick.can) or 0) < 1, short = false }
	end
	return { kind = "none", off = true, short = false }
end

-- What to do with the secure Stop for a window change. It can be moved, sized, shown and hidden
-- only out of a fight (Craft.lua). Returns:
--   "place"  out of a fight and a Stop is wanted: put it over the window's Stop
--   "hide"   out of a fight and none is wanted
--   "keep"   in a fight with the secure Stop where the window draws its Stop: nothing to do
--   "face"   in a fight with the secure Stop out and somewhere else (the window moved, rolled up,
--            closed, or the craft ended): it shows its own face where it is, and the window draws
--            none, so what is seen is what a click does
--   "none"   in a fight with no secure Stop out: none can be brought (the window says so)
function State.StopAction(inFight, secureShown, wanted, same)
	if not inFight then return wanted and "place" or "hide" end
	if not secureShown then return "none" end
	if wanted and same then return "keep" end
	return "face"
end
