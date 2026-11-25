-- Glowey's Recipes: Auction House prices from another addon, when the player picks one. Seven
-- price addons for this client are known here; each is read through its own small reader below,
-- every call guarded (pcall, type checks), so a name gone in a later version of that addon makes
-- the reader answer nil and Recipes falls back to the prices it would use without it (its own,
-- Daylight UI's, Professionally Lost's or DaylightMogul's: Calc.lua). Nothing of theirs is ever
-- written or switched from here, except AHDB's documented "another addon is using the Auction
-- House" flag (S.Busy below).
--
-- What other files use:
--   ns.Sources.Choice()       -> "own" | "mogul" | a reader's id   what prices are in use
--   ns.Sources.External()     -> reader or nil    the picked addon, when it is one of the seven
--                                                  and loaded
--   ns.Sources.Get(itemID)    -> copper, age (seconds, or nil when that addon keeps none) or nil
--   ns.Sources.ScanHandedOff()-> bool   the picked addon scans the Auction House itself, so our
--                                       own full scan isn't offered (Prices.CanScan)
--   ns.Sources.Busy(key, on)  tells AHDB that one of our scans is using the Auction House
--   ns.Sources.Due()          -> bool   the "which prices" window is still to come at this login
--   ns.Sources.ShowDialog()   the window that asks which prices to use
--   ns.Sources.CHOICES / KINDS  for the options page (Core.lua)
--
-- Source read for every name used (downloaded 2026-11-24 from CurseForge, read only; Auctionator
-- from the installed copy):
--   Auctionator 353      Source/API/v1/GetAuctionPrice.lua:1-16 GetAuctionPriceByItemID(callerID,
--                        itemID) -> copper or nil (the lowest buyout of its last scan that had the
--                        item, Source/Database/Mixin.lua:82-88); GetAuctionAge.lua:1-3
--                        GetAuctionAgeByItemID -> whole days or nil; Source/API/Internal.lua:9-13
--                        callerID must be a non-empty string; database made at PLAYER_LOGIN.
--   TradeSkillMaster 4.15.9  App/API.lua:279-284 TSM_API.GetCustomPriceValue(priceString,
--                        itemString) -> copper or nil, err (a dot call; :554-558 errors on a colon
--                        call); :535-544 itemString "i:<id>"; LibTSMApp/Source/Config/
--                        AuctionDBConfig.lua:30-54 the DB* sources; their data only comes from the
--                        TSM desktop app (LibTSMService/Source/AppHelper/AppHelper.lua:108), loaded
--                        at login; no per-item age.
--   AuctionMaster 11.8.4 src/api/API.lua:24-46 AuctionMaster.API.GetLowestPrice / GetMarketPrice
--                        (item) -> copper or nil, GetDataAge(item) -> seconds or nil; :60-73
--                        AddDataChangeListener(fn), told once a scan or search, next frame.
--   AHDB 2.8.3           folder AuctionDB, global AuctionDB (AuctionDB.lua:16); no public API:
--                        History.lua:319-324 ADB:LastPrice(itemID, house) -> { ts (server time),
--                        min, median, qty } of the last scan that saw it, else of its last day;
--                        :329-346 ADB:Typical(itemID, house, days) -> median of daily lows, median
--                        of daily medians, days; AuctionDB.lua:178 ADB:PlayerHouse(); the house's
--                        realm is set at PLAYER_LOGIN (:124). Scan.lua:291-296 and Live.lua:267
--                        AuctionDB.ahBusy: set by other addons while they use the Auction House.
--   Auctioneer 4.0.9     folder Auc-Advanced; CoreAPI.lua:125 AucAdvanced.API.GetMarketValue(
--                        itemLink, serverKey, confidence) -> copper, seen, modules or nil; it can
--                        error (:222, :242); a number goes through GetItemInfo (nil until cached),
--                        so "item:<id>" is passed; its server key exists only after the first
--                        PLAYER_ENTERING_WORLD (CoreMain.lua:677-722): nil before.
--   ForeverForge Auction 2.8.14  folder ForeverForge_Auction (needs the ForeverForge core: every
--                        file returns without it, Market.lua:41); no public API: Market.lua:376-379
--                        ForeverForgeAuction.Market.KeyFor(itemID, link) -> key; :381-397
--                        Market:Get(key) -> { low, rate (the average of the cheapest ~15%), qty,
--                        t (time()) }; :434-458 Market:Usual(key, minDays) -> 14-day usual price.
--   Oribos Exchange 1.4  OribosExchange.lua:1-38, :209-216 OEMarketInfo(item, reuse) -> table
--                        { market (4-day median on this house), region, days (since last seen,
--                        251 = over 250), age (seconds since its data was compiled) } or nil;
--                        OEMarketInfo(0) -> data loaded; data loads at the first
--                        PLAYER_ENTERING_WORLD (:460-484). Ships its data: never scans.

-- Loaded before Core.lua (its options page is built from S.CHOICES / S.KINDS as that file loads),
-- so nothing here touches Core's names until the player is logged in.

local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Sources = S

local CALLER = "Glowey's Recipes"     -- Auctionator's callerID: the name of the addon asking
local DAY = 86400

local function Now() return _G.GetServerTime and _G.GetServerTime() or time() end

-- A function inside a global table, or nil.
local function Fn(t, name)
	return type(t) == "table" and type(t[name]) == "function" and t[name] or nil
end

local function Copper(v)
	return type(v) == "number" and v > 0 and v or nil
end

-- ---------------------------------------------------------------------------------------------
-- The readers. kinds: the price kinds the player can pick (Core.lua's options), the first is the
-- default. scans: the addon reads the Auction House itself (our own full scan stands down for it).
-- ---------------------------------------------------------------------------------------------

local oeTable = {}

local READERS = {
	{ id = "auctionator", folder = "Auctionator", name = "Auctionator", scans = true,
	  desc = L["The lowest buyout from Auctionator's last scan that saw the item."],
	  ready = function()
		local A = _G.Auctionator
		return Fn(type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil, "GetAuctionPriceByItemID") ~= nil
	  end,
	  get = function(itemID)
		local api = _G.Auctionator.API.v1
		local ok, copper = pcall(api.GetAuctionPriceByItemID, CALLER, itemID)
		copper = ok and Copper(copper) or nil
		if not copper then return nil end
		local age
		local getAge = Fn(api, "GetAuctionAgeByItemID")
		if getAge then
			local got, days = pcall(getAge, CALLER, itemID)
			if got and type(days) == "number" then age = days * DAY end
		end
		return copper, age
	  end },

	{ id = "tsm", folder = "TradeSkillMaster", name = "TradeSkillMaster", scans = false,
	  desc = L["TSM's prices come from the TSM desktop app: without it they are empty and Glowey's Recipes uses its own."],
	  kinds = { { "DBMarket", L["Market Value"] }, { "DBMinBuyout", L["Lowest Buyout"] },
		{ "DBRecent", L["Recent Value"] }, { "DBRegionMarketAvg", L["Region Market Average"] } },
	  ready = function() return Fn(_G.TSM_API, "GetCustomPriceValue") ~= nil end,
	  get = function(itemID, kind)
		local ok, copper = pcall(_G.TSM_API.GetCustomPriceValue, kind, "i:" .. itemID)
		return ok and Copper(copper) or nil, nil
	  end },

	{ id = "auctionmaster", folder = "AuctionMaster", name = "AuctionMaster", scans = true,
	  desc = L["AuctionMaster's market price, built from many scans, or the lowest buyout of its latest scan."],
	  kinds = { { "market", L["Market Value"] }, { "lowest", L["Lowest Buyout"] } },
	  ready = function()
		local M = _G.AuctionMaster
		return Fn(type(M) == "table" and M.API or nil, "GetLowestPrice") ~= nil
	  end,
	  get = function(itemID, kind)
		local api = _G.AuctionMaster.API
		local fn = kind == "lowest" and api.GetLowestPrice or Fn(api, "GetMarketPrice") or api.GetLowestPrice
		local ok, copper = pcall(fn, itemID)
		copper = ok and Copper(copper) or nil
		if not copper then return nil end
		local age
		local getAge = Fn(api, "GetDataAge")
		if getAge then
			local got, secs = pcall(getAge, itemID)
			if got and type(secs) == "number" then age = secs end
		end
		return copper, age
	  end },

	{ id = "ahdb", folder = "AuctionDB", name = "Auction House DataBase", scans = true,
	  desc = L["AHDB's prices from its own scans, for your faction's Auction House."],
	  kinds = { { "median", L["Median of Its Last Scan"] }, { "lowest", L["Lowest Buyout"] },
		{ "typical", L["30-Day Typical Price"] } },
	  ready = function()
		local A = _G.AuctionDB
		return Fn(A, "LastPrice") ~= nil and Fn(A, "PlayerHouse") ~= nil
	  end,
	  get = function(itemID, kind)
		local A = _G.AuctionDB
		local okH, house = pcall(A.PlayerHouse, A)
		if not okH or type(house) ~= "string" then return nil end
		local ok, p = pcall(A.LastPrice, A, itemID, house)
		if not ok or type(p) ~= "table" then return nil end
		local age = type(p[1]) == "number" and math.max(0, Now() - p[1]) or nil
		if kind == "typical" and Fn(A, "Typical") then
			local got, _, median = pcall(A.Typical, A, itemID, house)
			if got and Copper(median) then return median, age end
		end
		local copper = kind == "lowest" and Copper(p[2]) or Copper(p[3]) or Copper(p[2])
		if not copper then return nil end
		return copper, age
	  end },

	{ id = "auctioneer", folder = "Auc-Advanced", name = "Auctioneer", scans = true,
	  desc = L["Auctioneer's market value, blended from its price statistics."],
	  ready = function()
		local A = _G.AucAdvanced
		return Fn(type(A) == "table" and A.API or nil, "GetMarketValue") ~= nil
	  end,
	  get = function(itemID)
		local ok, copper = pcall(_G.AucAdvanced.API.GetMarketValue, "item:" .. itemID)
		return ok and Copper(copper) or nil, nil
	  end },

	{ id = "ffauction", folder = "ForeverForge_Auction", name = "ForeverForge Auction", scans = true,
	  desc = L["ForeverForge Auction's going rate (the average of the cheapest listings), lowest buyout or usual price."],
	  kinds = { { "rate", L["Going Rate"] }, { "low", L["Lowest Buyout"] }, { "usual", L["Usual Price"] } },
	  ready = function()
		local A = _G.ForeverForgeAuction
		local M = type(A) == "table" and A.Market or nil
		return Fn(M, "KeyFor") ~= nil and Fn(M, "Get") ~= nil
	  end,
	  get = function(itemID, kind)
		local M = _G.ForeverForgeAuction.Market
		local okK, key = pcall(M.KeyFor, itemID)
		if not okK or key == nil then return nil end
		local ok, e = pcall(M.Get, M, key)
		if not ok or type(e) ~= "table" then return nil end
		local age = type(e.t) == "number" and math.max(0, time() - e.t) or nil
		if kind == "usual" and Fn(M, "Usual") then
			local got, usual = pcall(M.Usual, M, key, 2)
			if got and Copper(usual) then return usual, age end
		end
		local copper = kind == "low" and Copper(e.low) or Copper(e.rate) or Copper(e.low)
		if not copper then return nil end
		return copper, age
	  end },

	{ id = "oribos", folder = "OribosExchange", name = "Oribos Exchange", scans = false,
	  desc = L["Oribos Exchange's prices ship with the addon (no scanning): the 4-day median on your Auction House, or across the region."],
	  kinds = { { "market", L["This Auction House"] }, { "region", L["Region Median"] } },
	  ready = function()
		if type(_G.OEMarketInfo) ~= "function" then return false end
		local ok, loaded = pcall(_G.OEMarketInfo, 0)
		return ok and loaded == true
	  end,
	  get = function(itemID, kind)
		local ok, o = pcall(_G.OEMarketInfo, itemID, oeTable)
		if not ok or type(o) ~= "table" then return nil end
		local copper = Copper(o[kind == "region" and "region" or "market"])
		if not copper then return nil end
		-- (How old: since its data was compiled, plus the days the item had then not been seen.
		-- 252 means a vendor sells it without limit: no age to add.)
		local age = type(o.age) == "number" and o.age or nil
		local days = tonumber(o.days)
		if age and days and days <= 251 then age = age + math.min(days, 250) * DAY end
		return copper, age
	  end },
}
S.READERS = READERS

local byId = {}
for _, r in ipairs(READERS) do byId[r.id] = r end

-- Installed and switched on for this character (the game's own list, so it can be read before
-- those addons load: the options page is built from it as the file loads).
local function Installed(folder)
	local A = C_AddOns
	if type(A) ~= "table" or type(A.DoesAddOnExist) ~= "function" or type(A.GetAddOnEnableState) ~= "function" then
		return false
	end
	local okE, exists = pcall(A.DoesAddOnExist, folder)
	if not okE or not exists then return false end
	local okN, who = pcall(UnitName, "player")
	local okS, state = pcall(A.GetAddOnEnableState, folder, okN and who or nil)
	if not okS or type(state) ~= "number" then
		okS, state = pcall(A.GetAddOnEnableState, folder)
	end
	return okS and type(state) == "number" and state > 0 or false
end

local function Loaded(folder)
	return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(folder) and true or false
end

-- The readers of the addons installed now, in READERS' order.
local installed = {}
for _, r in ipairs(READERS) do
	if Installed(r.folder) then installed[#installed + 1] = r end
end
S.INSTALLED = installed

local function MogulLoaded()
	local M = _G.DaylightMogul
	return type(M) == "table" and type(M.API) == "table" and type(M.API.Price) == "function"
end

-- The options page's choices (Core.lua): "auto" (as before any of this: DaylightMogul's when it's
-- loaded, else our own), our own, DaylightMogul's when it's installed, and each installed addon.
S.CHOICES = { auto = L["Automatic"], own = L["Glowey's Recipes' Own"] }
S.ORDER = { "auto", "own" }
if Installed("DaylightMogul") then
	S.CHOICES.mogul = "Daylight Mogul"
	S.ORDER[#S.ORDER + 1] = "mogul"
end
for _, r in ipairs(installed) do
	S.CHOICES[r.id] = r.name
	S.ORDER[#S.ORDER + 1] = r.id
end

-- Per reader with kinds: its options row's values and order, and its setting's key.
S.KINDS = {}
for _, r in ipairs(installed) do
	if r.kinds then
		local values, order = {}, {}
		for _, k in ipairs(r.kinds) do
			values[k[1]] = k[2]
			order[#order + 1] = k[1]
		end
		S.KINDS[#S.KINDS + 1] = { id = r.id, name = r.name, key = "ahKind_" .. r.id, values = values, order = order,
			default = r.kinds[1][1] }
	end
end

function S.Kind(r)
	if not r.kinds then return nil end
	local k = ns.Get("ahKind_" .. r.id)
	for _, kind in ipairs(r.kinds) do
		if kind[1] == k then return k end
	end
	return r.kinds[1][1]
end

-- What prices are in use. A pick whose addon is not loaded now falls back to "auto".
function S.Choice(get)
	local c = (get or ns.Get)("ahSource") or "auto"
	if c == "mogul" and not MogulLoaded() then c = "auto" end
	if c == "own" and MogulLoaded() then c = "auto" end
	local r = byId[c]
	if r and not (Loaded(r.folder) and r.ready()) then c = "auto" end
	if c == "auto" then return MogulLoaded() and "mogul" or "own" end
	return c
end

function S.External()
	if not ns.Get("useAH") then return nil end
	return byId[S.Choice()]
end

function S.Get(itemID)
	local r = S.External()
	if not r or type(itemID) ~= "number" then return nil end
	local ok, copper, age = pcall(r.get, itemID, S.Kind(r))
	if not ok or not Copper(copper) then return nil end
	return copper, type(age) == "number" and age or nil
end

function S.ScanHandedOff()
	local r = S.External()
	return r ~= nil and r.scans == true
end

function S.Name()
	local r = S.External()
	return r and r.name or nil
end

-- ---------------------------------------------------------------------------------------------
-- AHDB's flag: it holds its own browse pass while another addon uses the Auction House (the
-- client keeps only the newest pending request, so one of the two would go unanswered). Set
-- while one of our scans or price checks runs, and cleared only when we were the ones to set it.
-- ---------------------------------------------------------------------------------------------

local busy, weSet = {}, false
function S.Busy(key, on)
	busy[key] = on and true or nil
	local A = _G.AuctionDB
	if type(A) ~= "table" or type(A.LastPrice) ~= "function" then return end
	if next(busy) ~= nil then
		if not A.ahBusy then
			A.ahBusy = true
			weSet = true
		end
	elseif weSet then
		weSet = false
		if A.ahBusy == true then A.ahBusy = nil end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Prices change: theirs after their scans (AuctionMaster says so; the others are read again when
-- the Auction House closes) and when the pick changes (Core.lua's settings hook forgets Calc).
-- ---------------------------------------------------------------------------------------------

local function Changed()
	if not S.External() then return end
	if ns.Prices and ns.Prices.Changed then ns.Prices.Changed() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		pcall(self.RegisterEvent, self, "AUCTION_HOUSE_CLOSED")
		-- (Oribos Exchange and Auctioneer are ready only from the first PLAYER_ENTERING_WORLD.)
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		local M = _G.AuctionMaster
		local add = Fn(type(M) == "table" and M.API or nil, "AddDataChangeListener")
		if add then pcall(add, Changed) end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then self:UnregisterEvent("PLAYER_ENTERING_WORLD") end
	Changed()
end)

-- ---------------------------------------------------------------------------------------------
-- The window: which prices to use, asked when a price addon is installed that it hasn't asked
-- about before (kept per account in DaylightRecipesDB.priceAsk: folder -> true).
-- ---------------------------------------------------------------------------------------------

local function Record()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	db.priceAsk = type(db.priceAsk) == "table" and db.priceAsk or {}
	return db.priceAsk
end

-- The readers loaded and ready now.
local function Ready()
	local list = {}
	for _, r in ipairs(installed) do
		if Loaded(r.folder) and r.ready() then list[#list + 1] = r end
	end
	return list
end

local function Unasked()
	local rec = Record()
	for _, r in ipairs(Ready()) do
		if not rec[r.folder] then return true end
	end
	return false
end

local API                 -- Daylight UI's or Host.lua's (ns.API, set by Core.lua), when the window is made
local W, EDGE = 560, 18
local dialog

local function Ink(fs, role) ns.Host.Ink(fs, role) end

local function Pick(id)
	dialog.pick = id
	for _, row in ipairs(dialog.rows) do
		if row:IsShown() then row.switch.SetOn(row.id == id) end
	end
end

local function Row(f)
	local row = CreateFrame("Frame", nil, f)
	row:EnableMouse(true)
	row.name = API.Text(row, "body", "LEFT")
	row.name:SetPoint("TOPLEFT", 4, -6)
	Ink(row.name, "VALUE")
	row.switch = API.Switch(row)
	row.switch:SetPoint("RIGHT", -4, 0)
	row.what = API.Text(row, "small", "LEFT")
	row.what:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.what:SetWidth(W - EDGE * 2 - 4 - 70)
	row.what:SetWordWrap(true)
	Ink(row.what, "TEXT")
	-- (One pick: a switch turned on turns the others off; the one on stays on.)
	row.switch:SetScript("OnClick", function() Pick(row.id) end)
	row:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then Pick(self.id) end
	end)
	return row
end

local function Build()
	API = ns.API
	local f = CreateFrame("Frame", "DaylightRecipesPriceSource", UIParent)
	f:SetWidth(W)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	ns.SkinWindow(f, { solid = true })
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightRecipesPriceSource") end

	f.title = API.Text(f, "title", "LEFT")
	f.title:SetPoint("TOPLEFT", EDGE, -EDGE)
	f.title:SetPoint("RIGHT", f, "RIGHT", -44, 0)
	f.title:SetText(L["Which Auction House Prices?"])
	Ink(f.title, "VALUE")
	f.lead = API.Text(f, "body", "LEFT")
	f.lead:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.lead:SetWidth(W - EDGE * 2)
	f.lead:SetWordWrap(true)
	f.lead:SetText(L["You have an Auction House addon installed. Pick whose prices Glowey's Recipes uses for materials, sales and disenchants. You can change this any time in Plugins > Recipes > Prices."])
	Ink(f.lead, "TEXT")
	local close = API.Close(f, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)

	f.rows = {}
	f.foot = API.Text(f, "small", "LEFT")
	f.foot:SetWidth(W - EDGE * 2 - 8)
	f.foot:SetWordWrap(true)
	f.foot:SetText(L["An item the picked addon has no price for is priced as before, from your own browsing and scans."])
	Ink(f.foot, "LABEL")

	f.apply = API.Button(f, L["Apply"], 26)
	f.apply.FitWidth(150)
	f.apply:SetPoint("BOTTOMLEFT", EDGE, EDGE)
	if type(API.MainButton) == "function" then pcall(API.MainButton, f.apply, true) end
	f.apply:SetScript("OnClick", function()
		local rec = Record()
		for _, r in ipairs(Ready()) do rec[r.folder] = true end
		f:Hide()
		-- (DaylightUI:Set, or Host.lua's stand-in without it: saved in the player's profile and
		-- told to Core.lua's settings hook, which forgets every worked-out price.)
		local DUI = ns.DUI or _G.DaylightUI
		if dialog.pick and type(DUI) == "table" and type(DUI.Set) == "function" then
			pcall(DUI.Set, DUI, ADDON, "ahSource", dialog.pick)
		end
	end)
	f.later = API.Button(f, L["Ask Me Later"], 26)
	f.later.FitWidth(150)
	f.later:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	f.later:SetScript("OnClick", function() f:Hide() end)

	f.padFirst = function() return f.apply end
	if ns.Pad then ns.Pad.Follow(f, function() f:Hide() end) end
	f:HookScript("OnShow", function() if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("prices", true) end end)
	f:HookScript("OnHide", function() if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("prices", false) end end)
	dialog = f
end

function S.ShowDialog()
	local ready = Ready()
	if #ready == 0 or InCombatLockdown() then return false end
	if not dialog then Build() end
	local f = dialog
	-- Ours (or DaylightMogul's, which stands in for ours while it's loaded) first, then each addon.
	local choices = {}
	if MogulLoaded() then
		choices[1] = { id = "mogul", name = "Daylight Mogul", desc = L["DaylightMogul's prices, as before."] }
	else
		choices[1] = { id = "own", name = L["Glowey's Recipes' Own"],
			desc = L["What you browse and scan at the Auction House yourself, and Daylight UI's prices when it has them."] }
	end
	for _, r in ipairs(ready) do choices[#choices + 1] = { id = r.id, name = r.name, desc = r.desc } end
	local y = EDGE + math.ceil(f.title:GetStringHeight() or 20) + 8 + math.ceil(f.lead:GetStringHeight() or 30) + 12
	for i, c in ipairs(choices) do
		local row = f.rows[i] or Row(f)
		f.rows[i] = row
		row.id = c.id
		row.name:SetText(c.name)
		row.what:SetText(c.desc)
		local h = 6 + math.ceil(row.name:GetStringHeight() or 14) + 3 + math.ceil(row.what:GetStringHeight() or 12) + 8
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -y)
		row:SetPoint("RIGHT", f, "RIGHT", -EDGE, 0)
		row:SetHeight(h)
		row:Show()
		y = y + h
	end
	for i = #choices + 1, #f.rows do f.rows[i]:Hide() end
	f.foot:ClearAllPoints()
	f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 4, -(y + 8))
	y = y + 8 + math.ceil(f.foot:GetStringHeight() or 14)
	f:SetHeight(y + 16 + 26 + EDGE)
	ns.SkinWindow(f, { solid = true })
	-- (On what is in use now.)
	Pick(S.Choice())
	f:Show()
	return true
end

-- At login, after everything else of ours that asks (the welcome or What's New, Professionally
-- Lost's window): the same waiting as ProfLost.lua's. Looked at every 2 seconds for 5 minutes;
-- not answered, asked again at the next login.
local WAIT, TRIES = 2, 150
local due = false
function S.Due() return due end

local function Busy()
	if InCombatLockdown() then return true end
	local G = ns.Guide
	if G and G.Busy and G.Busy() then return true end
	if ns.ProfLost and ns.ProfLost.Due and ns.ProfLost.Due() then return true end
	return false
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	-- (Core.lua ran: ns.ok. Ready() needs the addons' own login work done: a few seconds on.)
	if not ns.ok then return end
	local tries = 0
	due = #installed > 0
	if not due then return end
	local function ask()
		tries = tries + 1
		if Busy() then
			if tries < TRIES then C_Timer.After(WAIT, ask) else due = false end
			return
		end
		due = false
		if Unasked() then S.ShowDialog() end
	end
	C_Timer.After(10, ask)
end)
