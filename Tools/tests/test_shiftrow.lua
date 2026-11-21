-- A list row's Shift action (the strips' Remove), played on the plugin's real Doc.lua: the row's
-- own OnEnter, OnLeave, OnEvent and OnClick scripts, as the game runs them. While Shift is held
-- with the mouse on the row its right text reads "Remove" and its tooltip gains the line; both
-- follow Shift going down and up while the mouse stays (MODIFIER_STATE_CHANGED); and a Shift-click
-- runs the Shift action and never the row's own press (the purchase), with either mouse button,
-- nor a chat link.
-- luacheck: globals GAME NS ADDON_ROOT GameTooltip IsShiftKeyDown IsModifiedClick wipe
-- luacheck: read globals T Fire NewObj
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

local shift = false
function IsShiftKeyDown() return shift end
-- (The game's chat-link click is a Shift-click by default.)
function IsModifiedClick(name) return name == "CHATLINK" and shift end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local tipLines, tipShown = {}, false
GameTooltip = NewObj("GameTooltip", "GameTooltip")
local tipOwner
rawset(GameTooltip, "SetOwner", function(_, owner)
	tipOwner = owner
	tipLines = {}
end)
rawset(GameTooltip, "IsOwned", function(_, owner) return tipOwner == owner and tipShown end)
rawset(GameTooltip, "AddLine", function(_, text) tipLines[#tipLines + 1] = text end)
rawset(GameTooltip, "Show", function() tipShown = true end)
rawset(GameTooltip, "Hide", function() tipShown = false end)

-- The real Doc.lua, on a namespace of its own (the strips' tests keep their stand-in doc).
local links = 0
local ns = {
	ok = true, L = NS.L, Plural = NS.Plural, API = NS.API, Calc = NS.Calc,
	Pad = { Into = function() end },
	InsertLink = function() links = links + 1 end,
}
local src = assert(io.open(ROOT .. "/Doc.lua", "r"))
local chunk = assert(loadstring(src:read("*a"), "@Doc.lua"))
src:close()
chunk("DaylightRecipes", ns)
local Doc = ns.Doc

local d = Doc.New(NewObj("Frame"), { pad = 10, width = 320 })
local bought, removed = 0, 0
local function draw()
	d:Begin()
	local plain = d:Row({ left = "Item 1 x 3", right = "Buy 3", onClick = function() bought = bought + 1 end })
	local r = d:Row({ left = "Item 2320 x 30", right = "Buy 30", rightInk = "VALUE",
		tip = function(tip) tip:AddLine("the item") end,
		onClick = function() bought = bought + 1 end,
		shift = { text = "Remove", tip = "Shift-click to remove this from the list.", run = function() removed = removed + 1 end } })
	return r, plain
end
local r = draw()
local plain
local function enter(row) row.scripts.OnEnter(row) end
local function leave(row) row.scripts.OnLeave(row) end
local function click(row, button) row.scripts.OnClick(row, button or "LeftButton") end
local function tipHas(text)
	for _, l in ipairs(tipLines) do
		if l == text then return true end
	end
	return false
end
local LINE = "Shift-click to remove this from the list."

-- ---- the mouse on the row, Shift up -------------------------------------------------------------
enter(r)
T.eq(r.right:GetText(), "Buy 30", "without Shift the row reads as ever")
T.ok(tipShown and tipHas("the item") and not tipHas(LINE), "and its tooltip has no Shift line")
click(r)
T.eq(bought, 1, "a plain click is the row's own press")
T.eq(removed, 0, "and removes nothing")

-- ---- Shift goes down while the mouse is on the row ----------------------------------------------
shift = true
Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.eq(r.right:GetText(), "Remove", "Shift down over the row: its right text reads Remove at once")
T.ok(tipHas("the item") and tipHas(LINE), "and the tooltip gains the line")
click(r)
T.eq(removed, 1, "a Shift-click removes")
T.eq(bought, 1, "and never buys")
T.eq(links, 0, "nor puts a link in the chat")
click(r, "RightButton")
T.eq(removed, 1, "a Shift-right-click does nothing")
T.eq(bought, 1, "least of all buy")
r.scripts.OnDoubleClick(r, "LeftButton")
T.eq(bought, 1, "nor does the second click of a fast pair")

-- ---- Shift goes up again ------------------------------------------------------------------------
shift = false
Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
T.eq(r.right:GetText(), "Buy 30", "Shift up: the row's own text is back")
T.ok(tipHas("the item") and not tipHas(LINE), "and the tooltip's line is gone")

-- ---- the mouse comes onto the row with Shift already held ---------------------------------------
leave(r)
T.ok(not tipShown, "the tooltip goes with the mouse")
shift = true
T.eq(r.right:GetText(), "Buy 30", "Shift held away from the row changes nothing on it")
Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.eq(r.right:GetText(), "Buy 30", "nor does the event while the mouse is elsewhere")
enter(r)
T.eq(r.right:GetText(), "Remove", "entered with Shift held: Remove")
leave(r)
T.eq(r.right:GetText(), "Buy 30", "left with Shift held: its own text again")

-- ---- drawn again under the mouse with Shift held (a refresh of the list) -------------------------
enter(r)
r, plain = draw()
-- (The game hides and shows the pooled row under the mouse: it leaves and enters.)
enter(r)
T.eq(r.right:GetText(), "Remove", "drawn again under the mouse: still Remove")
click(r)
T.eq(removed, 2, "and a Shift-click still removes")
T.eq(bought, 1, "not buys")

-- ---- a row with no Shift action is not touched ---------------------------------------------------
leave(r)
enter(plain)
T.eq(plain.right:GetText(), "Buy 3", "a row without the action keeps its text under Shift")
click(plain)
T.eq(bought, 2, "and a Shift-click on it is its own press, as before")
T.eq(removed, 2, "removing nothing")
shift = false
leave(plain)

-- ---- a hover hint (the Auction House strip's "Left Click to Search") -----------------------------
local searched = 0
d:Begin()
local h = d:Row({ left = "Item 2589 x 7", right = "AH 210c", rightInk = "GOOD",
	hover = { text = "Left Click to Search", ink = "ACCENT" },
	shift = { text = "Remove", tip = LINE, run = function() removed = removed + 1 end },
	onClick = function() searched = searched + 1 end })
local bare = d:Row({ left = "Item 2589 x 7", right = "AH 210c" })
T.eq(h.right:GetText(), "AH 210c", "away from the mouse the row reads its own text")
T.ok(h.left:GetWidth() < bare.left:GetWidth(), "room is kept for the hint beside the left text")
-- (The stand-in font is 6 units a character: the hint is 120 wide, 8 clear of the left text.)
T.ok(h.left:GetWidth() + 8 + 6 * #"Left Click to Search" <= bare.left:GetWidth() + 8 + 6 * #"AH 210c",
	"enough for all of it: the hint never runs into the item's name")
enter(h)
T.eq(h.right:GetText(), "Left Click to Search", "the mouse on the row: the hint")
click(h)
T.eq(searched, 1, "a click there is the row's own press")
shift = true
Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
T.eq(h.right:GetText(), "Remove", "Shift down on it: Remove wins")
shift = false
Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
T.eq(h.right:GetText(), "Left Click to Search", "Shift up, the mouse still on it: the hint again")
leave(h)
T.eq(h.right:GetText(), "AH 210c", "the mouse gone: its own text is back")
shift = true
enter(h)
T.eq(h.right:GetText(), "Remove", "entered with Shift held: Remove")
click(h)
T.eq(searched, 1, "and a Shift-click does not search")
shift = false
leave(h)
T.eq(h.right:GetText(), "AH 210c", "left: its own text")

return T.done()
