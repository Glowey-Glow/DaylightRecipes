-- The Auction House strip's host: DaylightMogul's window, Daylight UI 2.0's own Auction House
-- window (the frame "DaylightUIAuctionHouse", with the game's frame parked unseen under it), or
-- the game's. Which one is chosen, the swap between the two while the Auction House stays open,
-- the strip following a window that is dragged or scaled, where the strip and its list sit for the
-- room there is, what a press on a row does on each, and that Daylight UI 1.9 (no such frame) and
-- the game's own window behave as before. (Carried over from 2.5.3 on main.)
-- luacheck: globals GAME PRINTS ERRORS DaylightUI DaylightRecipesDB NS AuctionHouseFrame AuctionatorAHTabsContainer GloweyGearWindow DaylightUIAuctionHouse DaylightMogulMain Auctionator UIParent C_AddOns
-- luacheck: read globals T Fire NewObj ALL
local ns = NS
local Shop = ns.Shop

local VERSION = "2.0"
C_AddOns.GetAddOnMetadata = function(addon, field)
	if addon == "DaylightUI" and field == "Version" then return VERSION end
end

-- The game's window, with its search box.
AuctionHouseFrame = NewObj("Frame", "AuctionHouseFrame")
AuctionHouseFrame.w, AuctionHouseFrame.h = 800, 538
AuctionHouseFrame.SearchBar = { SearchBox = NewObj("EditBox") }
AuctionHouseFrame.shown = false
local focused = 0
rawset(AuctionHouseFrame.SearchBar.SearchBox, "SetFocus", function() focused = focused + 1 end)

-- Daylight UI 2.0's module, as much as a search touches.
local submitted, tabs = {}, {}
local page = { Submit = function(text) submitted[#submitted + 1] = text return true end }
local window = { frame = { tab = "sell" }, ShowTab = function(tab)
	tabs[#tabs + 1] = tab
end }
local function Module() return { ns = { BuyPage = page, Window = window } } end
local module = Module()
DaylightUI = { GetModule = function(_, name) return name == "AuctionHouse" and module or nil end }

-- Daylight UI's window up: the game's frame stays shown, parked at alpha 0 under it.
local function DaylightUp()
	if not DaylightUIAuctionHouse then
		NewObj("Frame", "DaylightUIAuctionHouse")
		DaylightUIAuctionHouse.w, DaylightUIAuctionHouse.h = 960, 620
	end
	DaylightUIAuctionHouse.shown = true
	DaylightUIAuctionHouse.left, DaylightUIAuctionHouse.bottom = 16, 464
	AuctionHouseFrame.shown = true
	rawset(AuctionHouseFrame, "GetEffectiveAlpha", function() return 0 end)
end
local function GameUp()
	if DaylightUIAuctionHouse then DaylightUIAuctionHouse.shown = false end
	AuctionHouseFrame.shown = true
	rawset(AuctionHouseFrame, "GetEffectiveAlpha", function() return 1 end)
end
local function strip() return _G.DaylightRecipesAHStrip end
-- A frame of the game: every strip's OnUpdate, as the client runs it.
local function Frame()
	local s = strip()
	if s and s:IsShown() and s.scripts.OnUpdate then s.scripts.OnUpdate(s) end
end
local function fresh()
	if GAME.ahOpen then
		GAME.ahOpen = false
		Fire("AUCTION_HOUSE_CLOSED")
	end
	T.run(5)
	GAME.plans = { [197] = { need = { [2320] = 5, [2604] = 3 } } }
	GAME.queue, GAME.bags = {}, {}
	DaylightRecipesDB = { shop = { auction = true } }
	PRINTS, submitted, tabs = {}, {}, {}
	focused = 0
	VERSION = "2.0"
	module = Module()
	window.frame.tab = "sell"
	Auctionator = nil
	UIParent.w, UIParent.h = 1920, 1080
end
local function Open()
	GAME.ahOpen = true
	Fire("AUCTION_HOUSE_SHOW")
	T.run(2)
end
local function said(text)
	for _, line in ipairs(PRINTS) do
		if line:find(text, 1, true) then return true end
	end
	return false
end
Auctionator = nil
local function WithAuctionator()
	Auctionator = { API = { v1 = { CreateShoppingList = function() end, ConvertToSearchString = function() return "x" end } } }
end

T.case("Daylight UI 1.9 and the game's own window: as before", function()
	fresh()
	VERSION = "1.9.6"
	GameUp()                                   -- (no DaylightUIAuctionHouse global at all yet)
	T.eq(rawget(_G, "DaylightUIAuctionHouse"), nil, "Daylight UI 1.9 has no Auction House window")
	WithAuctionator()
	Open()
	local s = strip()
	T.ok(s and s:IsShown(), "the strip is up at the game's window")
	T.eq(s.host, AuctionHouseFrame, "docked to it")
	T.eq(s.fit, false, "under the window, not beside it")
	local at = s.points[1]
	T.ok(#s.points == 1 and at[1] == "TOPRIGHT" and at[2] == AuctionHouseFrame and at[3] == "BOTTOMRIGHT" and at[4] == 0,
		"flush under its bottom right corner, their right edges one line")
	T.ok(s.compact == true and s.w > 0 and s.w < 800 / 2, "a compact strip: as wide as its row needs (" .. s.w .. "), all of it right of the window's middle")
	T.ok(s.main:IsShown() and s.main.text:GetText() == "Auctionator List", "with Auctionator's list button")
	T.ok(s.list:IsShown() and #s.doc.rows == 2, "its list has the two items")
	s.doc.rows[1].onClick()
	T.eq(AuctionHouseFrame.SearchBar.SearchBox:GetText(), "Item 2320", "a press on a row puts the name in the game's search box")
	T.eq(focused, 1, "and the cursor in it")
	T.eq(#submitted, 0, "nothing of Daylight UI's is called")
end)

T.case("Daylight UI 2.0's Auction House window is the host while it is the one on screen", function()
	fresh()
	DaylightUp()
	WithAuctionator()
	Open()
	local s = strip()
	T.ok(s and s:IsShown(), "the strip is up")
	T.eq(s.host, DaylightUIAuctionHouse, "docked to Daylight UI's window, not the game's parked frame")
	T.eq(s.fit, false, "under it, where there is room")
	local at = s.points[1]
	T.ok(#s.points == 1 and at[1] == "TOPRIGHT" and at[2] == DaylightUIAuctionHouse and at[3] == "BOTTOMRIGHT" and at[4] == 0,
		"flush under its bottom right corner, their right edges one line")
	T.ok(s.compact == true and s.w > 0 and s.w < 960 / 2, "a compact strip: as wide as its row needs (" .. s.w .. "), all of it right of the window's middle")
	local hung = s.list.points[1]
	T.ok(hung[1] == "TOPRIGHT" and hung[2] == s and hung[3] == "BOTTOMRIGHT", "its list hangs from the strip's right end: the same corner")
	T.ok(not s.main:IsShown(), "no Auctionator List button: Auctionator's tab is on the parked window")
	T.eq(s.rows, 1, "one row")
	-- A press on a row: the Buy tab, then the search, through Daylight UI's own functions.
	s.doc.rows[1].onClick()
	T.eq(tabs[1], "buy", "it was on Sell: the Buy tab first")
	T.eq(submitted[1], "Item 2320", "then the search for that item")
	T.eq(AuctionHouseFrame.SearchBar.SearchBox:GetText() ~= "Item 2320" or focused == 0, true, "the game's parked search box is left alone")
	window.frame.tab = "buy"
	s.doc.rows[2].onClick()
	T.eq(#tabs, 1, "already on Buy: no tab change")
	T.eq(submitted[2], "Item 2604", "the second row's search")
	T.eq(#PRINTS, 0, "and nothing said in chat")
end)

T.case("the search is gated and guarded: a version or a shape that is not as read says so in chat", function()
	fresh()
	DaylightUp()
	Open()
	local s = strip()
	VERSION = "1.9.6"
	s.doc.rows[1].onClick()
	T.eq(#submitted, 0, "before 2.0 its internals are not called")
	T.ok(said("Couldn't start the search. Type Item 2320"), "the player is told what to type")
	VERSION = "2.0"
	for _, broken in ipairs({
		function() module = nil end,
		function() module = { ns = "moved" } end,
		function() module = { ns = { BuyPage = {} } } end,
		function() module = { ns = { BuyPage = { Submit = function() error("changed in 2.1") end } } } end,
		function() DaylightUI.GetModule = nil end,
	}) do
		PRINTS, submitted = {}, {}
		broken()
		s.doc.rows[1].onClick()
		T.eq(#submitted, 0, "a changed shape: nothing runs")
		T.ok(said("Couldn't start the search."), "and the press is not silent")
	end
	DaylightUI.GetModule = function(_, name) return name == "AuctionHouse" and module or nil end
	-- Without its tab function the search still runs.
	module = { ns = { BuyPage = page } }
	PRINTS, submitted = {}, {}
	s.doc.rows[1].onClick()
	T.eq(submitted[1], "Item 2320", "no ShowTab to call: the search is still started")
	T.noErrors("guarded calls")
end)

T.case("the two windows swap while the Auction House stays open", function()
	fresh()
	DaylightUp()
	Open()
	local s = strip()
	T.eq(s.host, DaylightUIAuctionHouse, "on Daylight UI's window")
	-- The swap icon on its header: the game's window comes up in its place. No game event.
	GameUp()
	Frame()
	T.ok(not s:IsShown(), "the strip goes with the window it hung on")
	T.run(2)
	T.ok(s:IsShown(), "and comes back")
	T.eq(s.host, AuctionHouseFrame, "on the game's window")
	T.ok(s.compact == true and s.points[1][1] == "TOPRIGHT" and s.points[1][2] == AuctionHouseFrame, "at that window's bottom right corner")
	s.doc.rows[1].onClick()
	T.eq(AuctionHouseFrame.SearchBar.SearchBox:GetText(), "Item 2320", "a press now fills the game's search box")
	T.eq(#submitted, 0, "not Daylight UI's")
	-- And back.
	T.run(2)
	DaylightUp()
	Frame()
	T.run(2)
	T.ok(s:IsShown() and s.host == DaylightUIAuctionHouse, "swapped back: on Daylight UI's window again")
	-- Closed for good: nothing looks for a host.
	GAME.ahOpen = false
	DaylightUIAuctionHouse.shown, AuctionHouseFrame.shown = false, false
	Fire("AUCTION_HOUSE_CLOSED")
	T.run(5)
	T.ok(not s:IsShown(), "the Auction House closed: no strip")
end)

T.case("room: where the strip and its list sit at Daylight UI's window", function()
	-- The sums.
	T.eq(Shop.StripPlace(26, 400, 900), "below", "room under the window: under it")
	T.eq(Shop.StripPlace(26, 32, 389), "below", "the default spot on a 768-high space (32 free, 26 needed past the shared border): under it")
	T.eq(Shop.StripPlace(26, 10, 389), "side", "scaled up or dragged down, with room on the right: against the right edge")
	T.eq(Shop.StripPlace(26, 10, 48), "below", "no room on the right either: under it all the same (held on screen by its clamp)")
	T.eq(Shop.StripPlace(26, nil, nil), "below", "the room not known yet: under it")
	fresh()
	DaylightUp()
	Open()
	local s = strip()
	T.eq(s.listAt, "below", "plenty of room (the owner's 1200-high space): the list is under the strip")
	-- A 768-high, 16:9 space: the window's foot is 32 up, and 389 are free on its right.
	UIParent.w, UIParent.h = 1365, 768
	DaylightUIAuctionHouse.bottom = 32
	s.bottom = 6
	Fire("PLAYER_MONEY")
	T.run(1)
	T.eq(s.fit, false, "32 under the window: the strip still fits flush under it")
	T.eq(s.listAt, "right", "its list does not: beside the window, on the right")
	local at = s.list.points[1]
	T.ok(at[1] == "BOTTOMLEFT" and at[2] == DaylightUIAuctionHouse and at[3] == "BOTTOMRIGHT", "against the window's right edge")
	T.eq(at[5], 0, "its foot level with the window's")
	-- A 4:3 space, 1024 wide: 48 on the right, 16 on the left.
	UIParent.w = 1024
	Fire("PLAYER_MONEY")
	T.run(1)
	T.eq(s.listAt, "up", "no room on the window's right either: the list opens upward, over its lower RIGHT corner (never on its left)")
	at = s.list.points[1]
	T.ok(at[1] == "BOTTOMRIGHT" and at[2] == s and at[3] == "TOPRIGHT", "from the strip's top, at its right end")
	s.listButton:Click()
	T.ok(not s.list:IsShown(), "List again puts it away: the window is whole")
	s.listButton:Click()
	-- The window scaled up on the 16:9 space: nothing under it, 389 beside it.
	UIParent.w = 1365
	DaylightUIAuctionHouse.bottom = 4
	Fire("PLAYER_MONEY")
	T.run(1)
	T.eq(s.fit, true, "no room under the window: the strip stands against its right edge, at its foot")
	at = s.points[1]
	T.ok(at[1] == "BOTTOMLEFT" and at[2] == DaylightUIAuctionHouse and at[3] == "BOTTOMRIGHT", "flush against that edge")
	s.bottom = nil
end)

T.case("the strip follows Daylight UI's window when it is dragged or scaled", function()
	fresh()
	DaylightUp()
	Open()
	local s = strip()
	Frame()
	T.eq(s.fit, false, "under the window")
	-- Dragged down to the screen's foot: once it has been still a moment, docked again.
	DaylightUIAuctionHouse.bottom = 3
	Frame()
	T.eq(s.fit, false, "while it moves nothing is redone")
	T.run(0.2)
	Frame()
	T.eq(s.fit, false, "nor right after")
	T.run(0.2)
	Frame()
	T.eq(s.fit, true, "still for a moment: docked again, now beside the window (no room under it)")
	-- Scaled.
	rawset(DaylightUIAuctionHouse, "GetEffectiveScale", function() return 1.3 end)
	DaylightUIAuctionHouse.bottom = 464
	Frame()
	T.run(0.4)
	Frame()
	T.eq(s.fit, false, "scaled and moved back up: under it again")
	rawset(DaylightUIAuctionHouse, "GetEffectiveScale", nil)
	-- The game's window is not followed this way (it has no such moves): nothing is redone there.
	GameUp()
	Frame()
	T.run(2)
	T.eq(s.host, AuctionHouseFrame, "on the game's window")
	T.eq(s.follow, false, "which is not watched for moves")
end)

-- The game's tab row (Buy, Sell, Auctions, and Auctionator's beside them) hangs under the
-- window's foot: the strip never lies over it. (The stand-in's frames stand where their left and
-- bottom say, the strip at 100 from the left like the window.)
T.case("the game's tab row under the corner: the strip moves clear of it", function()
	local function Tab(left, w)
		local t = NewObj("Button")
		t.left, t.bottom, t.w, t.h, t.shown = left, 372, w, 32, true
		return t
	end
	local ok, err = pcall(function()
		fresh()
		GameUp()
		WithAuctionator()
		AuctionHouseFrame.Tabs = { Tab(100, 300) }
		Open()
		local s = strip()
		T.ok(s and s:IsShown(), "the strip is up")
		local at = s.points[1]
		T.eq(s.fit, true, "the game's tabs reach under it: beside the window's right edge instead")
		T.ok(at[1] == "BOTTOMLEFT" and at[2] == AuctionHouseFrame and at[3] == "BOTTOMRIGHT", "at its foot")
		-- No room on the right: under the tab row.
		UIParent.w = 900
		Shop.Auction()
		at = s.points[1]
		T.ok(s.compact == true and at[1] == "TOPRIGHT" and at[3] == "BOTTOMRIGHT" and at[5] <= -28,
			"no room beside it: at the corner, under the tabs (" .. tostring(at[5]) .. ")")
		UIParent.w = 1920
		-- Tabs that stop short of it: the corner, as ever.
		AuctionHouseFrame.Tabs = { Tab(0, 60) }
		Shop.Auction()
		at = s.points[1]
		T.ok(s.compact == true and at[1] == "TOPRIGHT" and at[5] == 0, "tabs clear of it: flush at the corner")
		-- Auctionator's tabs, made after the strip showed: seen within half a second.
		_G.AuctionatorAHTabsContainer = { Tabs = { Tab(60, 400) } }
		T.run(1)
		Frame()
		T.eq(s.fit, true, "Auctionator's tabs, come later: beside the window")
		-- Glowey's Gear's window docked against the same right edge: the strip hangs under it.
		local gear = NewObj("Frame", "GloweyGearWindow")
		gear.left, gear.bottom, gear.w, gear.h, gear.shown = 900, 500, 340, 520, true
		T.run(1)
		Frame()
		at = s.points[1]
		T.ok(s.fit == true and at[1] == "TOPLEFT" and at[2] == gear and at[3] == "BOTTOMLEFT",
			"Gear's window docked beside: flush under it, left edges one line")
		-- No room under Gear's window: under the tab row instead.
		gear.bottom = 10
		Shop.Auction()
		at = s.points[1]
		T.ok(s.compact == true and at[1] == "TOPRIGHT" and at[2] == AuctionHouseFrame and at[5] <= -28,
			"no room under Gear's window: at the corner, under the tabs")
		-- Gear's window put away: beside the window again, noticed within half a second.
		gear.shown = false
		T.run(1)
		Frame()
		at = s.points[1]
		T.ok(s.fit == true and at[1] == "BOTTOMLEFT" and at[2] == AuctionHouseFrame, "Gear's window gone: beside the window's right edge again")
		-- Docked somewhere else (not on the right edge): no matter.
		gear.shown, gear.left, gear.bottom = true, 1300, 500
		Shop.Auction()
		T.ok(s.points[1][2] == AuctionHouseFrame, "a Gear window that isn't on that edge changes nothing")
		gear.shown = false
		-- A hidden tab is no tab.
		_G.AuctionatorAHTabsContainer.Tabs[1].shown = false
		Shop.Auction()
		T.eq(s.compact, true, "a hidden tab: the corner again")
	end)
	AuctionHouseFrame.Tabs = nil
	_G.AuctionatorAHTabsContainer = nil
	UIParent.w = 1920
	if not ok then error(err, 0) end
end)

T.case("DaylightMogul's window comes first", function()
	fresh()
	DaylightUp()
	DaylightMogulMain = NewObj("Frame", "DaylightMogulMain")
	DaylightMogulMain.w, DaylightMogulMain.h = 900, 600
	local ok, err = pcall(function()
		Open()
		local s = strip()
		T.eq(s.host, DaylightMogulMain, "with DaylightMogul its window is the host")
		T.ok(s.compact == true and s.points[1][1] == "TOPRIGHT" and s.points[1][2] == DaylightMogulMain and s.points[1][3] == "BOTTOMRIGHT",
			"at its bottom right corner, as on every Auction House window")
	end)
	DaylightMogulMain.shown = false
	if not ok then error(err, 0) end
end)

fresh()
if DaylightUIAuctionHouse then DaylightUIAuctionHouse.shown = false end
AuctionHouseFrame.shown = false
return T.done()
