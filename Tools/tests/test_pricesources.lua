-- PriceSources.lua: Auction House prices from another addon. Each of the seven readers against a
-- stand-in for that addon shaped as its own code is (the calls PriceSources.lua's header cites),
-- the pick and its fall-backs, the real Calc.lua using the picked price and falling back per item,
-- our own full scan standing down for an addon that scans, AHDB's busy flag (set and cleared only
-- by us), the options' choices, and the question at login (asked once per newly installed addon,
-- after Professionally Lost's window, never in a fight).
-- luacheck: globals GAME ERRORS DaylightRecipesDB DaylightUI DaylightMogul UnitName C_AddOns
-- luacheck: globals Auctionator TSM_API AuctionMaster AuctionDB AucAdvanced ForeverForgeAuction OEMarketInfo
-- luacheck: globals NS
-- luacheck: read globals T ADDON_ROOT Fire
-- luacheck: ignore 212/self
local ROOT = ADDON_ROOT

local function read(file)
	local f = assert(io.open(ROOT .. "/" .. file, "rb"))
	local src = f:read("*a")
	f:close()
	return src
end

local DAY = 86400
local NOW = GAME.clock

-- The addons installed (folder -> true) and loaded, as the game's C_AddOns tells.
local installed = {}
function UnitName() return "Tester" end
C_AddOns.DoesAddOnExist = function(folder) return installed[folder] == true end
C_AddOns.GetAddOnEnableState = function(folder) return installed[folder] and 2 or 0 end
C_AddOns.IsAddOnLoaded = function(folder) return installed[folder] == true, installed[folder] == true end

-- Stand-ins, each answering for item 2589 (Linen Cloth) only.
local calls = {}
local function Install()
	installed = { Auctionator = true, TradeSkillMaster = true, AuctionMaster = true, AuctionDB = true,
		["Auc-Advanced"] = true, ForeverForge_Auction = true, OribosExchange = true }
	Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID = function(caller, id)
			if type(caller) ~= "string" or caller == "" then error("Invalid callerID. Use the name of your add-on.") end
			calls.auctionator = caller
			return id == 2589 and 110 or nil
		end,
		GetAuctionAgeByItemID = function(_, id) return id == 2589 and 2 or nil end,
	} } }
	TSM_API = {}
	function TSM_API.GetCustomPriceValue(price, item)
		if price == TSM_API then error("colon call") end
		if not item:match("^[ip]:%d+") then error("bad item string") end
		calls.tsm = price .. "|" .. item
		if item ~= "i:2589" then return nil, "no data" end
		return ({ DBMarket = 120, DBMinBuyout = 100, DBRecent = 115, DBRegionMarketAvg = 130 })[price]
	end
	AuctionMaster = { API = {
		GetLowestPrice = function(item) return item == 2589 and 90 or nil end,
		GetMarketPrice = function(item) return item == 2589 and 125 or nil end,
		GetDataAge = function(item) return item == 2589 and 600 or nil end,
		AddDataChangeListener = function(fn) calls.amListener = fn return true end,
	} }
	AuctionDB = {}
	function AuctionDB:PlayerHouse() return "Alliance" end
	function AuctionDB:LastPrice(id, house)
		if house ~= "Alliance" or id ~= 2589 then return nil end
		return { NOW - 3600, 95, 105, 40 }
	end
	function AuctionDB:Typical(id) if id == 2589 then return 97, 108, 12 end end
	AucAdvanced = { API = { GetMarketValue = function(link)
		if type(link) ~= "string" then error("needs a link") end
		if link == "item:2589" then return 140, 30, 3 end
	end } }
	local Market = {}
	function Market.KeyFor(id) return tostring(id) end
	function Market:Get(key) if key == "2589" then return { low = 88, rate = 99, qty = 50, t = NOW - 120 } end end
	function Market:Usual(key) if key == "2589" then return 101, 14 end end
	ForeverForgeAuction = { Market = Market }
	function OEMarketInfo(item, t)
		if item == 0 then return true end
		if item ~= 2589 then return nil end
		t = t or {}
		for k in pairs(t) do t[k] = nil end
		t.market, t.region, t.days, t.age = 150, 160, 1, 7200
		return t
	end
end

-- PriceSources.lua loaded again over NS (as the game loads it: before Core.lua, with what's
-- installed now), and the real Calc.lua again over the mocks' stand-in.
local S
local function Load()
	assert(loadstring(read("PriceSources.lua"), "@PriceSources.lua"))("DaylightRecipes", NS)
	S = NS.Sources
end
local function RealCalc()
	assert(loadstring(read("Calc.lua"), "@Calc.lua"))("DaylightRecipes", NS)
	return NS.Calc
end

local function Pick(id, kind)
	GAME.settings.ahSource = id
	if kind then GAME.settings["ahKind_" .. id] = kind end
	if NS.Calc and NS.Calc.Forget then NS.Calc.Forget() end
end

Install()
Load()

T.case("every installed addon is offered, in order, after Automatic and our own", function()
	T.eq(table.concat(S.ORDER, ","), "auto,own,auctionator,tsm,auctionmaster,ahdb,auctioneer,ffauction,oribos", "choices")
	T.eq(#S.INSTALLED, 7, "seven installed")
	T.eq(S.CHOICES.ahdb, "Auction House DataBase", "AHDB's name")
	T.eq(S.CHOICES.mogul, nil, "no DaylightMogul installed: not offered")
	local keys = {}
	for _, k in ipairs(S.KINDS) do keys[#keys + 1] = k.key .. "=" .. k.default end
	T.eq(table.concat(keys, ","), "ahKind_tsm=DBMarket,ahKind_auctionmaster=market,ahKind_ahdb=median,ahKind_ffauction=rate,ahKind_oribos=market",
		"the kinds rows and their defaults")
end)

T.case("each reader gives copper and an age, the default kind first", function()
	local want = {
		auctionator = { 110, 2 * DAY }, tsm = { 120, nil }, auctionmaster = { 125, 600 }, ahdb = { 105, 3600 },
		auctioneer = { 140, nil }, ffauction = { 99, 120 }, oribos = { 150, 7200 + DAY },
	}
	for id, w in pairs(want) do
		Pick(id)
		T.eq(S.Choice(), id, id .. " picked")
		local copper, age = S.Get(2589)
		T.eq(copper, w[1], id .. " price")
		T.eq(age, w[2], id .. " age")
		T.eq(S.Get(2592), nil, id .. ": an item it doesn't know has no price")
	end
	T.eq(calls.auctionator, "Glowey's Recipes", "Auctionator is told who asks")
end)

T.case("the other kinds", function()
	local want = {
		{ "tsm", "DBMinBuyout", 100 }, { "tsm", "DBRecent", 115 }, { "tsm", "DBRegionMarketAvg", 130 },
		{ "auctionmaster", "lowest", 90 }, { "ahdb", "lowest", 95 }, { "ahdb", "typical", 108 },
		{ "ffauction", "low", 88 }, { "ffauction", "usual", 101 }, { "oribos", "region", 160 },
	}
	for _, w in ipairs(want) do
		Pick(w[1], w[2])
		T.eq((S.Get(2589)), w[3], w[1] .. " " .. w[2])
	end
	Pick("tsm", "NotAKind")
	T.eq((S.Get(2589)), 120, "a kind that isn't one: the default")
	T.eq(calls.tsm, "DBMarket|i:2589", "TSM is asked by a dot call with its item string")
end)

T.case("a reader that errors or changed shape answers nil, never an error", function()
	Pick("auctioneer")
	local was = AucAdvanced.API.GetMarketValue
	AucAdvanced.API.GetMarketValue = function() error("boom") end
	T.eq(S.Get(2589), nil, "it errors")
	AucAdvanced.API.GetMarketValue = was
	Pick("ahdb")
	local last = AuctionDB.LastPrice
	AuctionDB.LastPrice = function() return "not a table" end
	T.eq(S.Get(2589), nil, "a value of another shape")
	AuctionDB.LastPrice = last
	Pick("oribos")
	OEMarketInfo = nil
	T.eq(S.Choice(), "own", "gone after an update: back to our own")
	Install()
end)

T.case("the pick falls back: not loaded, our own while DaylightMogul runs, Automatic", function()
	Pick("auctionmaster")
	installed.AuctionMaster = nil
	T.eq(S.Choice(), "own", "not loaded now: Automatic, which is our own")
	installed.AuctionMaster = true
	T.eq(S.Choice(), "auctionmaster", "loaded again")
	Pick("auto")
	T.eq(S.Choice(), "own", "Automatic without DaylightMogul")
	DaylightMogul = { API = { Price = function() return 77 end } }
	T.eq(S.Choice(), "mogul", "Automatic with DaylightMogul")
	Pick("own")
	T.eq(S.Choice(), "mogul", "our own isn't one while DaylightMogul runs the house")
	Pick("oribos")
	T.eq(S.Choice(), "oribos", "an addon can be picked over DaylightMogul")
	DaylightMogul = nil
	Pick("mogul")
	T.eq(S.Choice(), "own", "DaylightMogul picked, not loaded")
	GAME.settings.useAH = false
	Pick("oribos")
	T.eq(S.External(), nil, "Auction House prices off: no addon's")
	GAME.settings.useAH = true
end)

T.case("Calc uses the picked addon's price, and per item falls back to what it used before", function()
	local Calc = RealCalc()
	NS.Prices.Get = function(id) if id == 2592 then return 33 end end
	Pick("auctionator")
	T.eq(Calc.AH(2589), 110, "the picked price")
	T.eq(Calc.AH(2592), 33, "an item it has none for: our own")
	T.eq(Calc.AHAge(2589), 2 * DAY, "its age")
	T.ok(Calc.HasAH(), "Auction House prices are there")
	Pick("tsm")
	T.eq(Calc.AHAge(2589), nil, "TSM keeps no age: none (never called stale)")
	Pick("own")
	T.eq(Calc.AH(2589), nil, "our own: theirs isn't read")
	T.eq(Calc.AH(2592), 33, "our own")
end)

T.case("our own full scan stands down for an addon that scans, not for one that ships its data", function()
	for _, id in ipairs({ "auctionator", "auctionmaster", "ahdb", "auctioneer", "ffauction" }) do
		Pick(id)
		T.ok(S.ScanHandedOff(), id .. " scans: ours isn't offered")
	end
	for _, id in ipairs({ "tsm", "oribos", "own" }) do
		Pick(id)
		T.ok(not S.ScanHandedOff(), id .. ": ours is still offered")
	end
end)

T.case("AHDB's busy flag: set while ours run, cleared only when we set it", function()
	S.Busy("scan", true)
	T.eq(AuctionDB.ahBusy, true, "set while our scan runs")
	S.Busy("check", true)
	S.Busy("scan", false)
	T.eq(AuctionDB.ahBusy, true, "still set: a price check runs")
	S.Busy("check", false)
	T.eq(AuctionDB.ahBusy, nil, "cleared when both ended")
	AuctionDB.ahBusy = true          -- another addon's
	S.Busy("scan", true)
	S.Busy("scan", false)
	T.eq(AuctionDB.ahBusy, true, "another addon's flag is left as it was")
	AuctionDB.ahBusy = nil
end)

T.case("AuctionMaster's change listener throws our worked-out prices away", function()
	Pick("auctionmaster")
	local touched = 0
	NS.Prices.Changed = function() touched = touched + 1 end
	-- (PLAYER_LOGIN: the listener is added.)
	Fire("PLAYER_LOGIN")
	T.ok(calls.amListener ~= nil, "a listener was added")
	calls.amListener()
	T.ok(touched >= 1, "told")
	-- (Closing the Auction House reads the picked addon's prices again.)
	local was = touched
	Fire("AUCTION_HOUSE_CLOSED")
	T.ok(touched > was, "read again when the Auction House closes")
end)

T.case("the question: asked for addons not asked about, Apply saves the pick for all of them", function()
	DaylightRecipesDB = {}
	local set = {}
	NS.DUI = { Set = function(_, scope, key, value) set[#set + 1] = scope .. "." .. key .. "=" .. tostring(value) end }
	NS.Host = { Ink = function() end }
	Pick("auto")
	T.ok(S.ShowDialog(), "shown")
	local f = _G.DaylightRecipesPriceSource
	T.ok(f and f:IsShown(), "on screen")
	local ids = {}
	for _, row in ipairs(f.rows) do if row:IsShown() then ids[#ids + 1] = row.id end end
	T.eq(table.concat(ids, ","), "own,auctionator,tsm,auctionmaster,ahdb,auctioneer,ffauction,oribos", "its rows")
	T.eq(f.pick, "own", "on what is in use now")
	-- (A row clicked: that one on, every other off.)
	f.rows[3]:GetScript("OnMouseUp")(f.rows[3], "LeftButton")
	T.eq(f.pick, "tsm", "picked TSM")
	local on = 0
	for _, row in ipairs(f.rows) do if row.switch.on then on = on + 1 end end
	T.eq(on, 1, "one switch on")
	f.apply:GetScript("OnClick")(f.apply)
	T.eq(set[1], "DaylightRecipes.ahSource=tsm", "saved")
	T.ok(DaylightRecipesDB.priceAsk.OribosExchange and DaylightRecipesDB.priceAsk.Auctionator, "every addon asked about")
	T.ok(not f:IsShown(), "closed")
end)

T.case("at login: waits for Professionally Lost's window, then asks only about a newly installed addon", function()
	-- (The login was fired above; its question is due 10 s on.)
	local f = _G.DaylightRecipesPriceSource
	f:Hide()
	DaylightRecipesDB.priceAsk.OribosExchange = nil      -- installed since the last answer
	local due = true
	local was = NS.ProfLost.Due
	NS.ProfLost.Due = function() return due end
	T.ok(S.Due(), "still to come at this login")
	T.run(12)
	T.ok(not f:IsShown(), "not while Professionally Lost's window is still to come")
	due = false
	T.run(3)
	T.ok(f:IsShown(), "asked once it has had its turn")
	T.ok(not S.Due(), "no longer to come")
	f.later:GetScript("OnClick")(f.later)
	T.ok(not DaylightRecipesDB.priceAsk.OribosExchange, "Ask Me Later records nothing: asked again next login")
	NS.ProfLost.Due = was
end)

return T.done()
