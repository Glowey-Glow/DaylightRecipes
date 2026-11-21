-- The rules key (Store.lua): prices, vendors and alts kept by the server's rules ("US-PvP") now
-- that the game gives no realm names; the old "Realm-Faction" books carried over, never deleted.
-- Store.lua and Prices.lua themselves, loaded a second time over this test's own saved table and
-- game facts (the other tests run on mocks.lua's stand-in for Store).
-- luacheck: ignore 111 112 113 121 122 131
local T = rawget(_G, "T")
local ROOT = rawget(_G, "ADDON_ROOT") or "."

-- ---- the game facts the key is made of ----------------------------------------------------------
local W = { region = 1, noRealms = true, rules = {}, realm = "", guid = "Player-6800-0000AAAA", name = "Moo", faction = "Horde" }
GetCurrentRegion = function() return W.region end
RegionalUniqueNamesEnabled = function() return W.noRealms end
C_GameRules = { IsGameRuleActive = function(rule) return W.rules[rule] == true end }
GetRealmName = function() return W.realm end
UnitGUID = function() return W.guid end
UnitName = function() return W.name end
UnitClass = function() return "Mage", "MAGE" end
UnitFactionGroup = function() return W.faction end
local function SetRules(kind)
	Enum = Enum or {}
	W.rules = {}
	if kind == nil then
		Enum.GameRule = {}
		return
	end
	Enum.GameRule = { HardcoreRuleset = 1, PvPRuleset = 2, RPRuleset = 3 }
	if kind == "PvP" or kind == "RPvP" then W.rules[2] = true end
	if kind == "RP" or kind == "RPvP" then W.rules[3] = true end
	if kind == "Hardcore" then W.rules[1] = true end
end

local frames = {}
local realCreateFrame = CreateFrame
local Store, Prices
-- A session: the two files loaded over DaylightRecipesDB as it stands, then PLAYER_LOGIN.
local function Boot()
	local ns = { ok = true, L = setmetatable({}, { __index = function(_, k) return k end }), Recipes = {}, state = {} }
	ns.Faction = function() return W.faction == "Horde" and "H" or "A" end
	ns.Get = function(key) if key == "useAH" then return true end end
	ns.ShowingPlan = function() return false end
	ns.Print = function() end
	frames = {}
	CreateFrame = function(...)
		local f = realCreateFrame(...)
		frames[#frames + 1] = f
		return f
	end
	assert(loadfile(ROOT .. "/Store.lua"))("DaylightRecipes", ns)
	assert(loadfile(ROOT .. "/Prices.lua"))("DaylightRecipes", ns)
	CreateFrame = realCreateFrame
	Store, Prices = ns.Store, ns.Prices
	for _, f in ipairs(frames) do
		local on = f.GetScript and f:GetScript("OnEvent")
		if on then on(f, "PLAYER_LOGIN") end
	end
	return ns
end
local function Fire(event)
	for _, f in ipairs(frames) do
		local on = f.GetScript and f:GetScript("OnEvent")
		if on then on(f, event) end
	end
end

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end
local function dump(v)
	if type(v) ~= "table" then return tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. dump(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end
local function names(set)
	local t = {}
	for _, c in pairs(set) do t[#t + 1] = c.name end
	table.sort(t)
	return table.concat(t, ",")
end

local now = time()
-- A profile in the shape the split left: books by realm and faction, and a bare "-H" written since
-- the game stopped naming realms.
local function Profile()
	local function char(name, realm, faction, seen)
		return { name = name, realm = realm, faction = faction, named = true, bagsAt = seen, prof = {}, known = {}, bags = {}, bank = {}, mail = {} }
	end
	return { version = 1, account = {},
		chars = {
			["Player-6800-0000AAAA"] = char("Moo", "CAMWOW US2 Realm 2 PvP", "H", now - 10),
			["Player-6922-0000BBBB"] = char("Goose", "CAMWOW US1 Realm 4 PvP", "H", now - 9000),
			["Player-6923-0000CCCC"] = char("Doctor", "CAMWOW US1 Realm 5 PvE", "H", now - 9000),
			["Player-6923-0000DDDD"] = char("Jorkt", "CAMWOW US1 Realm 5 PvE", "A", now - 9000),
		},
		prices = {
			["CAMWOW US2 Realm 2 PvP-H"] = { scanned = now - 5000, items = { [1] = { p = 99, t = now - 5000 }, [2] = { p = 20, t = now - 5000 } } },
			["-H"] = { items = { [1] = { p = 10, t = now - 100 }, [3] = { p = 30, t = now - 100 } } },
			["CAMWOW US1 Realm 5 PvE-H"] = { items = { [4] = { p = 40, t = now - 6000 } } },
			["CAMWOW US1 Realm 5 PvE-A"] = { items = { [5] = { p = 50, t = now - 7000 } } },
		},
		vendors = {
			["CAMWOW US2 Realm 2 PvP-H"] = { [7] = { unit = 4, who = "A", at = now - 5000 }, [8] = { unit = 8, who = "A", at = now - 5000 } },
			["-H"] = { [7] = { unit = 3, who = "B", at = now - 100 }, [8] = { unit = 9, who = "B", at = now - 100 } },
			["CAMWOW US1 Realm 5 PvE-H"] = { [7] = { unit = 1, who = "C", at = now - 6000 } },
			["CAMWOW US1 Realm 5 PvE-A"] = { [9] = { unit = 2, who = "D", at = now - 7000 } },
		} }
end

-- ---- the owner's shape, as the PvP Horde character -----------------------------------------------
SetRules("PvP")
DaylightRecipesDB = Profile()
local db = DaylightRecipesDB
local old = { prices = dump(db.prices), vendors = dump(db.vendors) }
Boot()
T.eq(db.version, 2, "the saved table is at version 2")
T.eq(Store.RulesKey(), "US-PvP", "the rules key, from the game's rules")
T.eq(db.chars[W.guid].rules, "US-PvP", "saved on the character")
T.eq(Store.RealmKey(), "US-PvP", "the old name answers with it (session tables go by it)")
local b = db.books
T.eq(count(b.prices["US-PvP"].items), 3, "US-PvP: the realm's book and the bare one together")
T.eq(b.prices["US-PvP"].items[1].p, 10, "the newer price wins")
T.eq(b.prices["US-PvP"].items[2].p, 20, "one only the realm's book had")
T.eq(b.prices["US-PvP"].items[3].p, 30, "one only the bare book had")
T.eq(b.prices["US-PvP"].scanned, now - 5000, "the scan time comes along")
T.eq(count(b.prices["US-PvE"].items), 2, "US-PvE: both factions' prices in one book (one Auction House)")
T.eq(b.prices["US-PvP"].items[4], nil, "none of PvE's prices in PvP's book")
T.eq(b.vendors["US-PvP-H"][7].unit, 3, "the cheaper vendor stays")
T.eq(b.vendors["US-PvP-H"][8].unit, 8, "and here the realm book's was the cheaper")
T.eq(b.vendors["US-PvE-H"][7].unit, 1, "PvE's vendors by faction: Horde")
T.eq(b.vendors["US-PvE-A"][9].unit, 2, "and Alliance")
T.eq(b.vendors["US-PvP-A"], nil, "no book made for a faction nobody played there")
T.eq(db.migrated["-H"].to, "US-PvP", "the bare book: marked with where it went")
T.eq(db.migrated["CAMWOW US1 Realm 5 PvE-A"].to, "US-PvE", "a realm's book too")
T.eq(count(db.migrated), 4, "all four placed")
T.eq(dump(db.prices["-H"]), dump(Profile().prices["-H"]), "the bare book itself is untouched")
T.eq(dump(db.prices["CAMWOW US1 Realm 5 PvE-H"]), dump(Profile().prices["CAMWOW US1 Realm 5 PvE-H"]), "so are the others")
T.ok(old.vendors ~= nil and count(db.vendors) == 4 and count(db.prices) == 4, "no old book deleted")
T.eq(Prices.Get(1), 10, "Prices.Get reads the rules book")
T.eq(Prices.Get(4), nil, "and nothing of another rule set's")
T.eq((Store.SeenVendor(7)), 3, "Store.SeenVendor reads the rules book of this faction")
T.eq(Store.OldPriceBook(), nil, "no old book read beside it")
T.eq(names(Store.Alts()), "Goose", "alts: same rules and faction, any numbered realm; not the PvE ones")
local snap = dump(db)
db.version = 1
Boot()
T.eq(dump(db), snap, "the migration again: nothing changes")
Boot()
T.eq(dump(db), snap, "a later session: nothing changes")
Store.PriceBook().items[77] = { p = 5, t = now }
T.ok(b.prices["US-PvP"].items[77] ~= nil and db.prices["-H"].items[77] == nil, "a new price goes to the rules book, not to an old one")

-- ---- brand-new characters with no realm anywhere --------------------------------------------------
for _, case in ipairs({ { "PvE", "Doctor" }, { "PvP", "Goose,Moo" }, { "Hardcore", "" } }) do
	SetRules(case[1])
	DaylightRecipesDB = Profile()
	db = DaylightRecipesDB
	W.guid, W.name, W.realm = "Player-7001-0000EEEE", "Newbie", ""
	Boot()
	local key = "US-" .. case[1]
	T.eq(Store.RulesKey(), key, "a new " .. case[1] .. " character: " .. key)
	T.eq(db.chars[W.guid].rules, key, "saved with it")
	Store.PriceBook().items[88] = { p = 1, t = now }
	local only = true
	for k, book in pairs(db.books.prices) do
		if (book.items[88] ~= nil) ~= (k == key) then only = false end
	end
	for _, book in pairs(db.prices) do
		if book.items[88] then only = false end
	end
	T.ok(only, "its price is in " .. key .. "'s book and nowhere else")
	T.eq(names(Store.Alts()), case[2], "its alts are that rule set's Horde characters")
end
-- Two of them on two rule sets, one after the other on one saved table.
SetRules("PvE")
DaylightRecipesDB = Profile()
W.guid, W.name = "Player-7001-0000EEEE", "NewPvE"
Boot()
Store.PriceBook().items[88] = { p = 1, t = now }
SetRules("PvP")
W.guid, W.name = "Player-7002-0000FFFF", "NewPvP"
Boot()
T.eq(Prices.Get(88), nil, "two new characters on two rule sets don't share prices")
T.ok(not names(Store.Alts()):find("NewPvE", 1, true), "and aren't each other's alts")

-- ---- the game's rules not in yet -------------------------------------------------------------------
SetRules(nil)
DaylightRecipesDB = nil
W.guid, W.name, W.realm = "Player-7003-00001111", "Early", ""
Boot()
db = DaylightRecipesDB
T.eq(Store.RulesKey(), nil, "no rules, no realm, nothing saved: no key")
T.eq(Store.RealmKey(), "-H", "the old key meanwhile")
T.eq(next(Store.Alts()), nil, "nobody's alt")
T.eq(Prices.Get(1), nil, "no error reading a price")
SetRules("PvE")
Fire("PLAYER_ENTERING_WORLD")
T.eq(Store.RulesKey(), "US-PvE", "the rules arrive: the key from then on")
T.eq(db.chars[W.guid].rules, "US-PvE", "and it is saved")
SetRules(nil)
Boot()
T.eq(Store.RulesKey(), "US-PvE", "next login before the rules are in: the saved key")

-- ---- books that can't be placed ---------------------------------------------------------------------
SetRules("PvE")
DaylightRecipesDB = Profile()
db = DaylightRecipesDB
db.chars["Player-6923-0000CCCC"].bagsAt = now - 50          -- (a PvE Horde character seen since, too)
db.prices["Oddname-H"] = { items = { [6] = { p = 60, t = now - 100 } } }
W.guid, W.name, W.realm = "Player-7004-00002222", "Bare", ""
db.chars[W.guid] = { name = "Bare", realm = "", faction = "H", named = true, prof = {}, known = {}, bags = {}, bank = {}, mail = {} }
Boot()
T.eq(db.migrated["-H"], nil, "a bare book two rule sets could have written: left where it is")
T.eq(db.migrated["Oddname-H"], nil, "a realm with no rules word and no characters: left where it is")
T.eq(db.books.prices["US-PvE"].items[3], nil, "and nothing of it copied")
T.eq(Store.OldPriceBook(), db.prices["-H"], "the character it belongs to still reads it")
T.eq(Prices.Get(3), 30, "its price")
T.eq((Store.SeenVendor(8)), 9, "and its vendor")
Store.PriceBook().items[3] = { p = 7, t = now }
T.eq(Prices.Get(3), 7, "until its own book has a later one")
W.guid, W.name = "Player-6923-0000CCCC", "Doctor"
Boot()
T.eq(Store.OldPriceBook(), nil, "a character with a realm of its own doesn't read the bare book")

-- ---- the region not known ----------------------------------------------------------------------------
SetRules("PvP")
DaylightRecipesDB = Profile()
db = DaylightRecipesDB
W.region = 99
W.guid, W.name = "Player-6800-0000AAAA", "Moo"
Boot()
T.eq(db.version, 1, "no region: nothing migrated yet")
T.eq(Store.RealmKey(), "CAMWOW US2 Realm 2 PvP-H", "the old key in use")
T.eq(Prices.Get(2), 20, "and the old book read")
W.region = 3
Boot()
T.eq(db.version, 2, "the region known: migrated")
T.eq(Store.RulesKey(), "EU-PvP", "under its own letters")

-- ---- the key's words ----------------------------------------------------------------------------------
W.region = 1
for _, kind in ipairs({ "PvE", "PvP", "RP", "RPvP", "Hardcore" }) do
	SetRules(kind)
	T.eq(Store.LiveRules(), "US-" .. kind, "the game's rules say " .. kind)
end
W.noRealms, W.realm = false, "Stormrage"
T.eq(Store.LiveRules(), "US-Stormrage", "a client with trading realms: region and realm")
W.noRealms, W.realm = true, ""
T.eq(Store.RulesWord("CAMWOW US1 Realm 5 PvE"), "PvE", "a realm name's word: PvE")
T.eq(Store.RulesWord("CAMWOW US1 Realm 3 RP PvP"), "RPvP", "RP PvP")
T.eq(Store.RulesWord("CAMWOW EU1 Realm 1 Hardcore"), "Hardcore", "Hardcore")
T.eq(Store.RulesWord("Warpve Sharp"), nil, "a word inside another is not one")
T.eq(Store.RulesWord(""), nil, "none")

DaylightRecipesDB = nil
return T.done()
