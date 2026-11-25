-- A strip and its list on the screen: that everything they write is drawn OVER their backgrounds
-- and over the window they hang on (the first report from the game: "the text looks like it's
-- being written behind the frame"), and that the list's head (the pair of lists, the profession
-- tags, Check Prices) stays small and never squeezes the rows (the same report: one row and a
-- half of eleven showing). Played on the plugin's real Doc.lua, so rows, chips and scroll frames are
-- frames with levels, with backgrounds made the way DaylightUI's shell makes them (a child frame
-- one level under its window when the window is dressed, its corner caps ten above:
-- DaylightUI/Style.lua:1019-1021, 1085-1087), and with the game carrying a frame's new level on to
-- its children both ways (GAME.levelsFollow), since nothing may hang on which it does.
-- The geometry is the report's: a 2160-line screen at Daylight UI's 0.64 (a UI space of 2133 x
-- 1200), Daylight UI's Auction House window (960 x 620) above the strip, eleven items of three
-- professions.
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightRecipesDB NS ADDON_ROOT AuctionHouseFrame DaylightUIAuctionHouse UIParent
-- luacheck: globals GameTooltip IsShiftKeyDown IsModifiedClick wipe C_AuctionHouse C_AddOns
-- luacheck: read globals T Fire NewObj
local ns = NS
local Shop = ns.Shop

local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/Doc.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "Doc.lua not found")

function IsShiftKeyDown() return false end
function IsModifiedClick() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
GameTooltip = NewObj("GameTooltip", "GameTooltip")

-- ---- backgrounds as DaylightUI makes them ---------------------------------------------------------
local function Shell(frame)
	if rawget(frame, "shell") then return end
	local s = NewObj("Frame", nil, frame)
	s.level = math.max(0, frame.level - 1)
	s.isShell = true
	s.over = NewObj("Frame", nil, s)
	s.over.level = frame.level + 10
	s.over.isShell = true
	rawset(frame, "shell", s)
end
ns.SkinWindow = function(frame, extra)
	rawset(frame, "skinExtra", extra or false)
	Shell(frame)
end
local plainButton = ns.API.Button
ns.API.Button = function(...)
	local b = plainButton(...)
	Shell(b)
	return b
end
local function Daylight()
	DaylightUI = { Style = { GetShell = function(f) return rawget(f, "shell") end },
		GetModule = function() return nil end }
end
Daylight()
C_AddOns.GetAddOnMetadata = function(addon, field)
	if addon == "DaylightUI" and field == "Version" then return "2.1.3" end
end

-- ---- the real Doc.lua for the strips' lists ---------------------------------------------------------
local ns2 = { ok = true, L = ns.L, Plural = ns.Plural, API = ns.API, Calc = ns.Calc, Pad = { Into = function() end },
	InsertLink = function() end }
local src = assert(io.open(ROOT .. "/Doc.lua", "r"))
assert(loadstring(src:read("*a"), "@Doc.lua"))("DaylightRecipes", ns2)
src:close()
-- (Shop.lua holds the Doc table it loaded with: the real functions go into that one. Item names
-- and "how long ago" stay the stand-in's: they need the game.)
for k, v in pairs(ns2.Doc) do
	if k ~= "ItemName" and k ~= "Ago" and k ~= "Color" and k ~= "Hex" then ns.Doc[k] = v end
end

-- ---- the screen of the report ------------------------------------------------------------------
UIParent.w, UIParent.h = 2133, 1200
AuctionHouseFrame = NewObj("Frame", "AuctionHouseFrame")
AuctionHouseFrame.w, AuctionHouseFrame.h = 800, 538
AuctionHouseFrame.shown = false
NewObj("Frame", "DaylightUIAuctionHouse")
DaylightUIAuctionHouse.w, DaylightUIAuctionHouse.h = 960, 620
DaylightUIAuctionHouse.shown = false
GAME.npc = NewObj("Frame", "FakeNpcWindow")
GAME.npc.w, GAME.npc.h = 520, 540

local COOKING, FIRST_AID, LEATHER = 185, 129, 165
local NAMES = { [COOKING] = "Cooking", [FIRST_AID] = "First Aid", [LEATHER] = "Leatherworking" }
ns.Tips.LineName = function(line) return NAMES[line] or ("Prof " .. tostring(line)) end

local ahOpen = false
local function closeAH()
	if not ahOpen then return end
	ahOpen = false
	DaylightUIAuctionHouse.shown = false
	Fire("AUCTION_HOUSE_CLOSED")
end
-- Daylight UI's Auction House window with its foot `bottom` above the screen's, at level `level`.
local function openAH(bottom, level, left, width)
	closeAH()
	T.run(5)
	DaylightUIAuctionHouse.shown = true
	DaylightUIAuctionHouse.left, DaylightUIAuctionHouse.bottom = left or 16, bottom
	DaylightUIAuctionHouse.w = width or 960
	DaylightUIAuctionHouse.level = level or 2
	DaylightUIAuctionHouse.strata = "MEDIUM"
	ahOpen = true
	Fire("AUCTION_HOUSE_SHOW")
	T.run(2)
	-- (The stand-in frames don't work their place out from their anchors: the strip's foot is
	-- said here, 32 under the window's, and the strip drawn again for it.)
	local s = _G.DaylightRecipesAHStrip
	if s then
		s.left, s.bottom = left or 16, bottom - 32
		Fire("BAG_UPDATE_DELAYED")
		T.run(1)
	end
	return s
end
-- Eleven items of three professions, none with a price (all the Auction House's to list).
local function eleven()
	GAME.plans = {
		[COOKING] = { need = { [1001] = 48, [1002] = 20, [1003] = 12, [1004] = 5 } },
		[FIRST_AID] = { need = { [2001] = 30, [2002] = 14, [2003] = 9 } },
		[LEATHER] = { need = { [3001] = 40, [3002] = 16, [3003] = 8, [3004] = 2 } },
	}
	GAME.queue, GAME.bags, GAME.removed, GAME.vendorPrice = {}, {}, {}, {}
	DaylightRecipesDB = { shop = { vendor = true, auction = true } }
end

-- ---- what must hold of the layers ---------------------------------------------------------------
local function frames(f, out)
	out = out or {}
	for _, kid in ipairs(rawget(f, "kids") or {}) do
		out[#out + 1] = kid
		frames(kid, out)
	end
	return out
end
-- Every frame on a window that is not a background: its contents.
local function contents(win, skip)
	local out = {}
	for _, f in ipairs(frames(win)) do
		local own, p = true, f
		while p and p ~= win do
			if rawget(p, "isShell") or p == skip then own = false end
			p = p.parent
		end
		if own then out[#out + 1] = f end
	end
	return out
end
local function sound(s, what, host)
	local list = s.list
	T.eq(s.strata, "HIGH", what .. ": the strip is a layer over its MEDIUM host's")
	for _, f in ipairs(frames(s)) do
		T.eq(f.strata, s.strata, what .. ": every frame of it is in that layer")
	end
	T.ok(not (s.strata == host.strata and s.level <= host.level), what .. ": never behind its host")
	-- Each window (the strip, the list) and each button: its background under it, its contents
	-- over the background, the background's caps over the contents.
	local function window(win, name, skip)
		local shell = rawget(win, "shell")
		T.ok(shell ~= nil, what .. ": " .. name .. " has one background")
		T.ok(shell.level < win.level, ("%s: %s is over its background (%d over %d)"):format(what, name, win.level, shell.level))
		local top = win.level
		for _, f in ipairs(contents(win, skip)) do
			T.ok(f.level > shell.level, ("%s: a frame on %s (level %d) is over its background (%d)"):format(what, name, f.level, shell.level))
			T.ok(f.level >= win.level, what .. ": and not under " .. name .. " itself")
			if f.level > top then top = f.level end
		end
		T.ok(shell.over.level > top, what .. ": " .. name .. "'s corner caps are over its contents")
		return top
	end
	local stripTop = window(s, "the strip", list)
	local listTop = window(list, "the list")
	T.ok(list.level > stripTop, what .. ": the list is over the strip and all that is on it")
	T.ok(rawget(list, "shell").level > stripTop, what .. ": its background too (it never hides behind the strip's)")
	for _, f in ipairs(frames(s)) do
		local shell = rawget(f, "shell")
		if shell and f ~= s and f ~= list then
			T.ok(shell.level < f.level, what .. ": a button is over its own background")
			T.ok(shell.level >= rawget(f.parent == list and list or s, "shell").level, what .. ": whose background is not under its window's")
		end
	end
	-- Rows are frames of the list's rows doc, chips of its head: there, and over the list.
	T.ok(#contents(list) >= 6, what .. ": the list's rows and chips are frames (" .. #contents(list) .. ")")
	return listTop
end

for _, follow in ipairs({ false, true }) do
	local how = follow and "levels carried on to children" or "levels not carried on"
	T.case("layers: everything written is over its background (" .. how .. ")", function()
		GAME.levelsFollow = follow
		eleven()
		local s = openAH(464, 2)
		T.ok(s and s:IsShown() and s.list:IsShown(), "the strip and its list are up")
		sound(s, "first shown", DaylightUIAuctionHouse)
		-- The window is clicked: the game raises a toplevel window's level.
		DaylightUIAuctionHouse.level = 500
		s.Check(s)
		sound(s, "the host raised to level 500", DaylightUIAuctionHouse)
		DaylightUIAuctionHouse.level = 0
		s.Check(s)
		sound(s, "the host at level 0", DaylightUIAuctionHouse)
		-- The list drawn again (a refresh; another list; a tag): rows and chips made anew.
		s.head.buttons = nil
		Fire("BAG_UPDATE_DELAYED")
		T.run(1)
		sound(s, "drawn again", DaylightUIAuctionHouse)
		GAME.plans[COOKING].need[1005], GAME.plans[COOKING].need[1006] = 3, 4
		Fire("BAG_UPDATE_DELAYED")
		T.run(1)
		sound(s, "two rows more", DaylightUIAuctionHouse)
		-- Shut and opened again.
		s.listButton:Click()
		s.listButton:Click()
		sound(s, "the list shut and opened", DaylightUIAuctionHouse)
		-- A host that is itself a dialog: the strip keeps that layer, well over the host.
		DaylightUIAuctionHouse.strata, DaylightUIAuctionHouse.level = "DIALOG", 30
		s.Check(s)
		T.eq(s.strata, "DIALOG", "a DIALOG host: the strip in its layer")
		T.ok(s.level > 30 + 20, "well over it")
		T.ok(rawget(s, "shell").level > 30, "its background over the host too")
		DaylightUIAuctionHouse.strata, DaylightUIAuctionHouse.level = "MEDIUM", 2
		closeAH()
		-- The vendor's strip, the same.
		GAME.vendorPrice = { [1001] = 5, [1002] = 5, [2001] = 5, [3001] = 5, [3002] = 5, [3003] = 5 }
		T.vendor({ { id = 1001, price = 5, stack = 1, max = 20 }, { id = 1002, price = 5, stack = 1, max = 20 },
			{ id = 2001, price = 5, stack = 1, max = 20 }, { id = 3001, price = 5, stack = 1, max = 20 },
			{ id = 3002, price = 5, stack = 1, max = 20 }, { id = 3003, price = 5, stack = 1, max = 20 } })
		T.run(1)
		sound(_G.DaylightRecipesBuyStrip, "the vendor's strip", GAME.npc)
		T.leave()
		GAME.levelsFollow = nil
	end)
end

-- ---- the head, and the rows it must leave -----------------------------------------------------------
-- The head's lines, from the chips' and the Check line's places in it.
local function headOf(s)
	local tops, right = {}, 0
	for _, f in ipairs(contents(s.head.scroll)) do
		local p = f.points and f.points[1]
		if f:IsShown() and p and p[1] == "TOPLEFT" and type(p[5]) == "number" and f.w > 0 and f.h > 0 then
			tops[-p[5]] = true
			right = math.max(right, (p[4] or 0) + f.w)
		end
	end
	local n = 0
	for _ in pairs(tops) do n = n + 1 end
	return n, right
end
-- How many whole rows the list shows: the rows' feet (the doc's marks) inside its rows area.
local function rowsVisible(s)
	local n = 0
	for _, y in ipairs(s.doc.marks) do
		if y <= s.list.h - s.listHead then n = n + 1 end
	end
	return n
end
-- Whether the rows area ends at a row's foot (or holds everything, foot and all).
local function wholeRows(s)
	local area = s.list.h - s.listHead
	if area >= s.doc.y then return true end
	for _, y in ipairs(s.doc.marks) do
		if y == area then return true end
	end
	return false
end

T.case("the report's screen: a head of two lines that never scrolls, and all eleven rows without a scroll bar", function()
	eleven()
	-- Check Prices can run (as at the owner's): it is the strip's button, not a line of the head.
	C_AuctionHouse = C_AuctionHouse or {}
	Fire("PLAYER_LOGIN")
	local s = openAH(464, 2)
	T.eq(s.rows, 1, "the strip is one row")
	T.eq(s.main.text:GetText(), "Check Prices", "with Check Prices beside List")
	local lines, right = headOf(s)
	T.eq(lines, 2, "the head is two lines: the pair, the tags")
	T.ok(s.listHead <= 60, ("and at most 60 tall (%d): it was 126 of the list's 170"):format(s.listHead))
	T.ok(right <= 320 - 6, "nothing in it runs past the list's edge (" .. right .. ")")
	for _, f in ipairs(contents(s.head.scroll)) do
		T.ok(not (f.right and f.right.GetText and f.right:GetText() == "Check Prices"), "no Check Prices line in the head")
	end
	-- The head is a plain area: as tall as what is in it, nothing of it out of sight, no thumb, no wheel.
	T.eq(s.head.still, true, "the head is an area that never scrolls")
	T.eq(s.head.scroll.h, s.listHead, "as tall as its lines")
	T.eq(s.head.child.h, s.listHead, "and what is drawn in it is exactly that tall: nothing to scroll to")
	T.ok(not s.head.thumb:IsShown(), "it has no scroll bar")
	T.eq(s.head.scroll.enabledWheel, false, "and takes no wheel")
	-- The rows: all eleven, under the head, without a scroll bar.
	T.eq(s.listAt, "below", "432 under the strip: the list hangs under it")
	T.eq(#s.doc.marks, 11, "(eleven rows)")
	T.eq(rowsVisible(s), 11, "all eleven rows show: six is the least a list is given, not the most")
	T.eq(s.list.h, s.listHead + s.doc.y, "the list is as tall as its head and all its rows")
	T.ok(not s.doc.thumb:IsShown(), "so the rows have no scroll bar either")
	T.ok(464 - 32 - s.list.h >= 0, "all of it on the screen")
	local at = s.doc.scroll.points[1]
	T.ok(at[1] == "TOPLEFT" and at[2] == s.list and at[5] == -s.listHead, "the rows start under the head")
	T.ok(s.head.scroll ~= s.doc.scroll, "one area scrolls, the rows': the head is not part of it")
	closeAH()
end)

T.case("more rows than fit: the rows scroll, the list ends on a whole row, the head stays", function()
	eleven()
	local s = openAH(464, 2)
	local head = s.listHead
	-- Room under the strip for the head and 200 more: six rows and more, not all eleven.
	DaylightUIAuctionHouse.bottom, s.bottom = head + 200 + 4 + 32, head + 200 + 4
	Fire("BAG_UPDATE_DELAYED")
	T.run(1)
	T.eq(s.listAt, "below", "the head and six rows fit under the strip: under it")
	local area = s.list.h - s.listHead
	T.ok(area <= 200, "no taller than the room (" .. area .. ")")
	T.ok(wholeRows(s), "the rows area ends at a row's foot: no row is cut through")
	T.ok(rowsVisible(s) >= 6 and rowsVisible(s) < 11, "six rows or more show, not all (" .. rowsVisible(s) .. ")")
	T.ok(s.doc.y > area, "the rest is reached by scrolling the rows")
	T.eq(s.head.scroll.h, s.listHead, "the head is as it was")
	T.eq(s.head.child.h, s.listHead, "with nothing of it to scroll")
	closeAH()
	-- Thirty rows and all the room in the world: sixteen at most, on a whole row.
	eleven()
	for i = 1, 19 do GAME.plans[COOKING].need[5000 + i] = i end
	s = openAH(1100, 2)
	T.eq(s.listAt, "below", "plenty of room")
	T.ok(wholeRows(s), "ends at a row's foot")
	T.ok(rowsVisible(s) >= 14 and rowsVisible(s) <= 16, "sixteen rows at the most (" .. rowsVisible(s) .. " of 30): a list is never a wall")
	closeAH()
end)

T.case("the window near the screen's foot: the list opens beside it, whole, never squeezed", function()
	eleven()
	local s = openAH(60, 2)
	T.eq(s.listAt, "right", "24 under the strip: beside the window, on its right")
	local at = s.list.points[1]
	T.ok(at[1] == "BOTTOMLEFT" and at[2] == DaylightUIAuctionHouse and at[3] == "BOTTOMRIGHT", "against the window's right edge")
	T.eq(at[5], 0, "its foot level with the window's")
	T.ok(rowsVisible(s) >= 6, "six rows or more show (" .. rowsVisible(s) .. ")")
	T.ok(60 + s.list.h <= 1200, "its top on the screen")
	-- Dragged up again: under the strip. (The strip follows a window that moves.)
	DaylightUIAuctionHouse.bottom, s.bottom = 464, 432
	s.Check(s)
	GAME.now = GAME.now + 1
	s.Check(s)
	T.run(1)
	T.eq(s.listAt, "below", "the window dragged up: the list is under the strip again")
	closeAH()
	-- A window as wide as the screen, near its foot: over the window's lower RIGHT corner.
	s = openAH(60, 2, 0, 2133)
	T.eq(s.listAt, "up", "no room under it or beside it: upward from the strip")
	at = s.list.points[1]
	T.ok(at[1] == "BOTTOMRIGHT" and at[2] == s and at[3] == "TOPRIGHT", "from the strip's top, at its right end")
	T.ok(s.list.level > s.level and s.list.strata == "HIGH", "over the strip and over the window it covers")
	T.ok(rowsVisible(s) >= 6, "six rows or more show (" .. rowsVisible(s) .. ")")
	closeAH()
	DaylightUIAuctionHouse.w = 960
end)

-- ---- the right corner -----------------------------------------------------------------------------
-- A frame's left and right edges from where it is hung (the stand-in frames don't work their place
-- out themselves): by its TOPRIGHT, BOTTOMRIGHT or BOTTOMLEFT on another frame's edge.
local function span(f, host, hostLeft)
	local hostRight = hostLeft + host.w
	local function edges(frame)
		if frame == host then return hostLeft, hostRight end
		local p = frame.points[1]
		local l, r = edges(p[2])
		local x = p[4] or 0
		if p[1] == "TOPRIGHT" or p[1] == "BOTTOMRIGHT" then
			local right = ((p[3] == "BOTTOMRIGHT" or p[3] == "TOPRIGHT") and r or l) + x
			return right - frame.w, right
		end
		local left = ((p[3] == "BOTTOMRIGHT" or p[3] == "TOPRIGHT") and r or l) + x
		return left, left + frame.w
	end
	return edges(f)
end

T.case("the right corner: under the window nothing of the strip or its list is left of the window's middle", function()
	-- The report's screen: the chat at the bottom left, under and left of Daylight UI's window.
	eleven()
	local s = openAH(464, 2)
	local host, hostLeft = DaylightUIAuctionHouse, 16
	local middle = hostLeft + host.w / 2
	T.eq(s.compact, true, "a compact strip")
	T.eq(s.rows, 1, "of one row: its count, cost, List and button fit it")
	local at = s.points[1]
	T.ok(#s.points == 1 and at[1] == "TOPRIGHT" and at[2] == host and at[3] == "BOTTOMRIGHT" and at[4] == 0 and at[5] == 0,
		"flush under the window's bottom right corner: their right edges one line, no gap")
	local l, r = span(s, host, hostLeft)
	T.eq(r, hostLeft + host.w, "the strip ends on the window's right edge")
	T.ok(l >= middle, ("and starts right of the window's middle (%d, the middle is %d)"):format(l, middle))
	T.eq(s.listAt, "below", "its list is under it")
	at = s.list.points[1]
	T.ok(at[1] == "TOPRIGHT" and at[2] == s and at[3] == "BOTTOMRIGHT" and at[4] == 0, "hung from the strip's right end")
	l, r = span(s.list, host, hostLeft)
	T.eq(r, hostLeft + host.w, "the list ends on the window's right edge too")
	T.ok(l >= middle, ("and starts right of the window's middle (%d)"):format(l))
	T.ok(l >= 496, "so nothing of either is over the left half, where the chat is")
	-- The words of the strip are all there: none dropped for being compact, but the note, which goes first.
	T.ok(s.lead:IsShown() and s.listButton:IsShown(), "the count and List show")
	T.ok(s.w >= 14 + s.lead:GetStringWidth() + 16 + s.listButton.w + 8, "the strip is as wide as they need")
	-- The game's window (800 wide) and DaylightMogul's: the same corner.
	closeAH()
	DaylightUIAuctionHouse.shown = false
	AuctionHouseFrame.shown = true
	ahOpen = true
	Fire("AUCTION_HOUSE_SHOW")
	T.run(2)
	s = _G.DaylightRecipesAHStrip
	T.eq(s.host, AuctionHouseFrame, "the game's own window")
	at = s.points[1]
	T.ok(s.compact and at[1] == "TOPRIGHT" and at[2] == AuctionHouseFrame and at[3] == "BOTTOMRIGHT", "the same corner there")
	l = span(s, AuctionHouseFrame, 100)
	T.ok(l >= 100 + 400, "right of its middle")
	l = span(s.list, AuctionHouseFrame, 100)
	T.ok(l >= 100 + 400, "the list too")
	-- With Professionally Lost loaded its Scan Prices button hangs under that corner of the game's
	-- window: the strip stands against the window's right edge instead, as at its vendor button.
	ns.ProfLost.Loaded = function() return true end
	Fire("BAG_UPDATE_DELAYED")
	T.run(1)
	T.eq(s.fit, true, "Professionally Lost on the game's window: beside the right edge, not on its button")
	at = s.points[1]
	T.ok(at[1] == "BOTTOMLEFT" and at[2] == AuctionHouseFrame and at[3] == "BOTTOMRIGHT", "flush against that edge, at the window's foot")
	l = span(s, AuctionHouseFrame, 100)
	T.ok(l >= 100 + 800, "wholly right of the window")
	ns.ProfLost.Loaded = function() return false end
	AuctionHouseFrame.shown = false
	ahOpen = true
	closeAH()
end)

T.case("the right corner: a strip too long for a compact one is as wide as the window, nothing cut", function()
	eleven()
	-- (A window only 300 wide: the row does not fit a strip narrower than it.)
	local s = openAH(464, 2, 16, 300)
	T.ok(s.w <= 300, "never wider than the window (" .. s.w .. ")")
	T.ok(s.lead:IsShown() and s.listButton:IsShown(), "the count and List still show")
	T.ok(s.rows >= 1 and s.h >= 32, "on as many rows as they need")
	closeAH()
	DaylightUIAuctionHouse.w = 960
end)

T.case("long tag names (German): the tags wrap whole, the rows keep their six", function()
	eleven()
	NAMES = { [COOKING] = "Kochkunst", [FIRST_AID] = "Erste Hilfe", [LEATHER] = "Lederverarbeitung" }
	local s = openAH(464, 2)
	local lines, right = headOf(s)
	T.ok(right <= 320 - 6, "no tag runs past the list's edge (" .. right .. ")")
	T.ok(lines <= 4, "a tag that does not fit takes a line more, no more than that (" .. lines .. ")")
	T.ok(rowsVisible(s) >= 6, "and the rows still show six or more (" .. rowsVisible(s) .. ")")
	T.eq(s.list.h, s.listHead + s.doc.y, "the head's extra line is the list's, not the rows': all eleven still show")
	T.eq(s.head.child.h, s.listHead, "and the taller head still has nothing to scroll")
	NAMES = { [COOKING] = "Cooking", [FIRST_AID] = "First Aid", [LEATHER] = "Leatherworking" }
	closeAH()
	-- One profession: no tags; the head is the pair alone.
	eleven()
	GAME.plans[FIRST_AID], GAME.plans[LEATHER] = nil, nil
	s = openAH(464, 2)
	lines = headOf(s)
	T.ok(lines <= 2, "one profession: the head is the pair (and Check Prices where it can run): " .. lines)
	closeAH()
end)

-- 3.0.2: what opens over something is a solid box. The list is dressed solid (ns.SkinWindow's
-- extra.solid: a background of 1 whatever the opacity settings, test_solid.lua); the strip's bar
-- is not, and follows the window opacity.
T.case("3.0.2: the strip's list is dressed solid, its bar follows the window opacity", function()
	eleven()
	local s = openAH(464, 2)
	T.ok(s and s:IsShown() and s.list:IsShown(), "the strip and its list are up")
	local extra = rawget(s.list, "skinExtra")
	T.ok(type(extra) == "table" and extra.solid == true, "the list asks for a solid background")
	T.eq(rawget(s, "skinExtra"), false, "the strip's bar asks for nothing of its own: the window opacity")
	sound(s, "the solid list", DaylightUIAuctionHouse)
end)

T.case("a list without a head (the trainer's) has none", function()
	local mode, h = Shop.ListPlace(60, 400, 1000, 16, 700, 0)
	T.ok(mode == "below" and h == 60, "three rows and no head: as tall as its rows")
	mode, h = Shop.ListPlace(60, 400, 1000, 16, 700)
	T.ok(mode == "below" and h == 60, "the head not said: none")
end)

return T.done()
