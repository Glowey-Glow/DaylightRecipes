-- What Glowey's Recipes keeps between sessions, for every character on the account: professions and
-- their skill, the recipes each knows, and what each holds (bags, bank, mail, and what was bought
-- at the Auction House since the mailbox was last read), plus the bank tabs
-- the whole account shares and what vendors you've visited sell. Everything is read when the game
-- says it changed (a bag change settled, the bank or mailbox open, a merchant open), a moment
-- later and once, never on a timer. Nothing needs another addon.
local _, ns = ...
if not ns.ok then return end

local Store = {}
ns.Store = Store

-- Bumped after every read of bags, bank, mail or a merchant: the plan keys its shopping list on it.
Store.version = 0

-- 2: prices and vendors kept by rules key (db.books), the old "Realm-Faction" tables (db.prices,
-- db.vendors) left as they were. An older version of the plugin reading this file sets the number
-- back to 1 and goes on with the old tables, which are all still there for it.
local DB_VERSION = 2

-- ---------------------------------------------------------------------------------------------
-- Which server: the rules key
-- ---------------------------------------------------------------------------------------------
-- Forever has no realms to trade on: each set of rules (PvE, PvP, RP, RPvP, Hardcore) is one
-- server in a region, its many numbered realms ("CAMWOW US1 Realm 5 PvE", "CAMWOW US2 Realm 2
-- PvP") sharing one Auction House that both factions use (Daylight UI's own Auction House keys its
-- prices the same way, DaylightUI_AuctionHouse\Ruleset.lua:1-7, and its alt lists take every realm
-- of a ruleset as one, DaylightUI\Alts.lua:26-41). And since 2026-11-20 the game gives no realm
-- name at all here (GetRealmName() is ""), so a realm can't be the key any more.
-- The rules key is "<Region>-<Rules>", "US-PvP": the region from GetCurrentRegion()
-- (LocaleDocumentation.lua:40), the rules from the game's own rules for this character
-- (C_GameRules.IsGameRuleActive, GameRulesDocumentation.lua:225-238, of Enum.GameRule's
-- HardcoreRuleset, PvPRuleset and RPRuleset), asked only where the game runs without trading
-- realms (RegionalUniqueNamesEnabled(), UnitDocumentation.lua:536-543). The same facts, read the
-- same way, as Daylight UI's ns.Ruleset.Key(), so the two agree wherever both answer; nothing of
-- Daylight UI is needed for it. Where the game can't say (rules not known yet early in a login),
-- the key this character was last saved with stands in, then the rules word in its saved realm
-- name. A client that still has trading realms gets "<Region>-<Realm Name>", as Daylight UI's.
--
-- Prices are kept per rules key (one Auction House for both factions); the vendors you've seen
-- per rules key and faction (who sells to you, and for how much, hangs on your side); alts are
-- the account's other characters of the same rules key and faction.

local REGIONS = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

-- The region's two letters, nil when the game doesn't say.
function Store.Region()
	local get = _G.GetCurrentRegion
	local n = type(get) == "function" and get() or nil
	return REGIONS[n]
end

-- The rules word in a realm's name: "CAMWOW US1 Realm 5 PvE" gives "PvE". nil with none.
local function RulesWord(realm)
	if type(realm) ~= "string" or realm == "" then return nil end
	local s = " " .. realm:lower():gsub("[^%a]+", " ") .. " "
	if s:find(" hardcore ", 1, true) then return "Hardcore" end
	if s:find(" rppvp ", 1, true) or s:find(" rpvp ", 1, true) or s:find(" rp pvp ", 1, true) then return "RPvP" end
	if s:find(" pvp ", 1, true) then return "PvP" end
	if s:find(" pve ", 1, true) then return "PvE" end
	if s:find(" rp ", 1, true) then return "RP" end
	return nil
end
Store.RulesWord = RulesWord

-- Whether the game runs without trading realms here (then the rules are the server).
local function NoRealms()
	local enabled = _G.RegionalUniqueNamesEnabled
	return type(enabled) == "function" and enabled() == true
end

-- The rules the game says this character plays under, nil when it can't.
local function GameRules()
	if not NoRealms() then return nil end
	local rules = Enum and Enum.GameRule
	local G = _G.C_GameRules
	if not (type(G) == "table" and type(G.IsGameRuleActive) == "function" and type(rules) == "table") then return nil end
	if rules.PvPRuleset == nil or rules.RPRuleset == nil then return nil end
	local function on(rule)
		if rule == nil then return false end
		local ok, active = pcall(G.IsGameRuleActive, rule)
		return ok and active == true
	end
	if on(rules.HardcoreRuleset) then return "Hardcore" end
	local pvp, rp = on(rules.PvPRuleset), on(rules.RPRuleset)
	if pvp and rp then return "RPvP" end
	if pvp then return "PvP" end
	if rp then return "RP" end
	return "PvE"
end

-- The rules key of a saved character, from what's saved alone: the key it was last seen with,
-- else the rules word of its realm name (in this region: an account's characters are one
-- region's), else, on a client with trading realms, its realm. nil when nothing says.
local function RulesOf(c, region)
	if type(c) ~= "table" then return nil end
	if type(c.rules) == "string" and c.rules ~= "" then return c.rules end
	region = region or Store.Region()
	if not region then return nil end
	local word = RulesWord(c.realm)
	if word then return region .. "-" .. word end
	return nil
end
Store.RulesOf = RulesOf


-- On 2026-11-20 the game stopped giving realm names on this client (GetRealmName() is "";
-- Daylight UI 2.1.2 DB.lua:226-238), so the prices and vendors kept under "Realm-Faction"
-- (Store.RealmKey) went on under "-H" and "-A" and the ones seen before looked gone. RealmKey now
-- falls back on the realm a character was first saved under (Store.Realm), which brings the old
-- ones back; this brings what was seen meanwhile along. A "-Faction" book is copied into a realm's
-- when the characters of that faction seen since its oldest entry (their bags, bank or mail read
-- no earlier) are all of one realm, so it is known whose it is: an entry the realm's book lacks,
-- or has an older price or a dearer vendor of, is taken. Once per book, at the first load after the update, before this
-- session reads anything. With more than one realm to choose from, or a character that has no
-- realm saved (its own book is "-Faction"), nothing is copied. Nothing is deleted: the "-Faction"
-- book stays as it is.
local function AdoptBare(db)
	if type(db.prices) ~= "table" or type(db.vendors) ~= "table" or type(db.chars) ~= "table" then return end
	local done = type(db.bareAdopted) == "table" and db.bareAdopted or {}
	for _, faction in ipairs({ "H", "A" }) do
		local bare = "-" .. faction
		local book, shop = db.prices[bare], db.vendors[bare]
		local items = type(book) == "table" and type(book.items) == "table" and book.items or nil
		if type(shop) ~= "table" then shop = nil end
		local oldest
		for _, row in pairs(items or {}) do
			local t = type(row) == "table" and tonumber(row.t)
			if t and (not oldest or t < oldest) then oldest = t end
		end
		for _, row in pairs(shop or {}) do
			local t = type(row) == "table" and tonumber(row.at)
			if t and (not oldest or t < oldest) then oldest = t end
		end
		if oldest and not done[bare] then
			local realm, several = nil, false
			for _, c in pairs(db.chars) do
				if type(c) == "table" and c.faction == faction then
					local seen = math.max(tonumber(c.bagsAt) or 0, tonumber(c.bankAt) or 0, tonumber(c.mailAt) or 0)
					local r = type(c.realm) == "string" and c.realm or ""
					if r == "" then
						several = true
					elseif seen >= oldest then
						if realm and realm ~= r then several = true end
						realm = r
					end
				end
			end
			if realm and not several then
				local key = realm .. bare
				if items then
					local into = type(db.prices[key]) == "table" and db.prices[key] or { items = {} }
					db.prices[key] = into
					if type(into.items) ~= "table" then into.items = {} end
					for itemID, row in pairs(items) do
						local have = into.items[itemID]
						if type(row) == "table" and (type(have) ~= "table" or (tonumber(have.t) or 0) < (tonumber(row.t) or 0)) then
							local copy = {}
							for k, v in pairs(row) do copy[k] = v end
							into.items[itemID] = copy
						end
					end
					if tonumber(book.scanned) and (tonumber(into.scanned) or 0) < book.scanned then into.scanned = book.scanned end
				end
				if shop then
					local into = type(db.vendors[key]) == "table" and db.vendors[key] or {}
					db.vendors[key] = into
					for itemID, row in pairs(shop) do
						local have = into[itemID]
						-- (The cheaper vendor stays, as when one is read.)
						if type(row) == "table" and (type(have) ~= "table" or (tonumber(row.unit) or math.huge) <= (tonumber(have.unit) or math.huge)) then
							local copy = {}
							for k, v in pairs(row) do copy[k] = v end
							into[itemID] = copy
						end
					end
				end
			end
			done[bare] = time()
			db.bareAdopted = done
		end
	end
end

local adoptedIn       -- the saved table AdoptBare has gone through this session

-- The books move from "Realm-Faction" (db.prices, db.vendors) to the rules key (db.books.prices
-- [rules], db.books.vendors[rules-Faction]). Each old book goes to the rules key its characters
-- belong to, decided by what's saved: for "Realm-F", the rules word in the realm's name and the
-- rules keys of the characters saved on that realm; for a bare "-F" (written since the game
-- stopped naming realms), the rules keys of that faction's characters seen since its oldest
-- entry (bags, bank or mail read no earlier). One answer, and all of it agreeing: the book is
-- merged in, a newer price winning and a cheaper vendor staying. No answer, or two: it stays
-- where it is and is still read by the characters it was written by (OldKey). Nothing is deleted
-- or changed in the old tables: db.migrated[old key] = { to, at } says where a book went.
-- Run when db.version isn't this one (the first load, and again after an older version of the
-- plugin, which sets it back and goes on writing the old tables: what it wrote is merged then).
-- Merging twice changes nothing.
local function MergePrices(into, from)
	if type(into.items) ~= "table" then into.items = {} end
	for itemID, row in pairs(type(from.items) == "table" and from.items or {}) do
		local have = into.items[itemID]
		if type(row) == "table" and (type(have) ~= "table" or (tonumber(have.t) or 0) < (tonumber(row.t) or 0)) then
			local copy = {}
			for k, v in pairs(row) do copy[k] = v end
			into.items[itemID] = copy
		end
	end
	if tonumber(from.scanned) and (tonumber(into.scanned) or 0) < from.scanned then into.scanned = from.scanned end
end

local function MergeVendors(into, from)
	for itemID, row in pairs(from) do
		local have = into[itemID]
		-- (The cheaper vendor stays, as when one is read; of two as cheap, the later sighting.)
		if type(row) == "table" then
			local mine, theirs = type(have) == "table" and tonumber(have.unit) or math.huge, tonumber(row.unit) or math.huge
			if theirs < mine or (theirs == mine and (tonumber(row.at) or 0) > (type(have) == "table" and tonumber(have.at) or 0)) then
				local copy = {}
				for k, v in pairs(row) do copy[k] = v end
				into[itemID] = copy
			end
		end
	end
end

-- Where an old book belongs: its rules key, or nil when what's saved doesn't say, or says two.
local function Belongs(db, realm, faction, region)
	local found, several = nil, false
	local function say(key)
		if not key then return end
		if found and found ~= key then several = true end
		found = key
	end
	if realm ~= "" then
		local word = RulesWord(realm)
		say(word and (region .. "-" .. word) or nil)
		for _, c in pairs(db.chars) do
			if type(c) == "table" and c.realm == realm then say(RulesOf(c, region)) end
		end
	else
		local oldest
		local book, shop = db.prices[realm .. "-" .. faction], db.vendors[realm .. "-" .. faction]
		for _, row in pairs(type(book) == "table" and type(book.items) == "table" and book.items or {}) do
			local t = type(row) == "table" and tonumber(row.t)
			if t and (not oldest or t < oldest) then oldest = t end
		end
		for _, row in pairs(type(shop) == "table" and shop or {}) do
			local t = type(row) == "table" and tonumber(row.at)
			if t and (not oldest or t < oldest) then oldest = t end
		end
		if not oldest then return nil end
		for _, c in pairs(db.chars) do
			if type(c) == "table" and c.faction == faction then
				local seen = math.max(tonumber(c.bagsAt) or 0, tonumber(c.bankAt) or 0, tonumber(c.mailAt) or 0)
				if seen >= oldest then
					local key = RulesOf(c, region)
					-- (Someone seen since whose rules nothing says: it may be theirs.)
					if not key then several = true end
					say(key)
				end
			end
		end
	end
	if several then return nil end
	return found
end

-- True when it ran (the region known), so the version can be set.
local function Migrate(db)
	local region = Store.Region()
	if not region then return false end
	db.books = type(db.books) == "table" and db.books or {}
	local books = db.books
	books.prices = type(books.prices) == "table" and books.prices or {}
	books.vendors = type(books.vendors) == "table" and books.vendors or {}
	db.migrated = type(db.migrated) == "table" and db.migrated or {}
	local olds = {}
	for key in pairs(db.prices) do olds[key] = true end
	for key in pairs(db.vendors) do olds[key] = true end
	for old in pairs(olds) do
		local realm, faction = tostring(old):match("^(.*)%-([HA])$")
		local to = realm and Belongs(db, realm, faction, region) or nil
		-- (A book that went somewhere once goes there again: what was decided stands.)
		local was = type(db.migrated[old]) == "table" and db.migrated[old].to or nil
		if was then to = was end
		if to then
			local book, shop = db.prices[old], db.vendors[old]
			if type(book) == "table" then
				local into = type(books.prices[to]) == "table" and books.prices[to] or { items = {} }
				books.prices[to] = into
				MergePrices(into, book)
			end
			if type(shop) == "table" then
				local key = to .. "-" .. faction
				local into = type(books.vendors[key]) == "table" and books.vendors[key] or {}
				books.vendors[key] = into
				MergeVendors(into, shop)
			end
			db.migrated[old] = { to = to, at = was and db.migrated[old].at or time() }
		end
	end
	return true
end

local function DB()
	local db = _G.DaylightRecipesDB
	if type(db) ~= "table" then
		db = {}
		_G.DaylightRecipesDB = db
	end
	if db.version ~= DB_VERSION then
		db.chars = type(db.chars) == "table" and db.chars or {}
		db.account = type(db.account) == "table" and db.account or {}
		db.vendors = type(db.vendors) == "table" and db.vendors or {}
		db.prices = type(db.prices) == "table" and db.prices or {}
		db.books = type(db.books) == "table" and db.books or {}
		db.books.prices = type(db.books.prices) == "table" and db.books.prices or {}
		db.books.vendors = type(db.books.vendors) == "table" and db.books.vendors or {}
		db.migrated = type(db.migrated) == "table" and db.migrated or {}
		if adoptedIn ~= db then
			adoptedIn = db
			AdoptBare(db)
		end
		-- (With the region not known yet, the old books are gone through at the next ask.)
		if Migrate(db) then db.version = DB_VERSION end
	end
	return db
end
Store.DB = DB

local me              -- this character's GUID
local function Me()
	if not me then me = UnitGUID("player") end
	return me
end

-- This character's record (made the first time it's asked for).
function Store.Char()
	local guid = Me()
	if not guid then return nil end
	local chars = DB().chars
	local c = chars[guid]
	if not c then
		c = { prof = {}, known = {}, bags = {}, bank = {}, mail = {} }
		chars[guid] = c
	end
	-- (The realm it was first seen on. The game may give none, "": then the one saved stays.)
	local realm = GetRealmName and GetRealmName()
	if type(realm) ~= "string" or realm == "" then realm = nil end
	if realm and (c.realm == nil or c.realm == "") then c.realm = realm end
	if not c.named then
		c.name = UnitName("player")
		c.realm = realm or c.realm
		c.faction = ns.Faction()
		c.class = select(2, UnitClass("player"))
		c.named = true
	end
	-- (The rules key it plays under, whenever the game says: what its alts and books go by.)
	local rules = Store.LiveRules()
	if rules then c.rules = rules end
	return c
end

-- The rules key as the game gives it right now ("US-PvP"; "US-Realm Name" on a client with
-- trading realms), nil while it can't say.
function Store.LiveRules()
	local region = Store.Region()
	if not region then return nil end
	local kind = GameRules()
	if kind then return region .. "-" .. kind end
	if NoRealms() then return nil end
	local realm = GetRealmName and GetRealmName()
	if type(realm) == "string" and realm ~= "" then return region .. "-" .. realm end
	return nil
end

-- This character's rules key: the game's, else the one it was last saved with, else the rules
-- word of its saved realm. nil when none of those says (a character never seen, the game's rules
-- not in yet): then the old "Realm-Faction" books are used meanwhile (Store.RealmKey).
local keptRules       -- the game's answer, kept from login on (asked again when the rules change)
function Store.RulesKey()
	local live = keptRules or Store.LiveRules()
	if live then return live end
	local guid = Me()
	local c = guid and DB().chars[guid]
	return RulesOf(c)
end

-- This character's realm: the game's name for it, else (since 2026-11-20 the game gives none on
-- this client: GetRealmName() is "") the one the character was first saved under, else "".
function Store.Realm()
	local realm = GetRealmName and GetRealmName()
	if type(realm) == "string" and realm ~= "" then return realm end
	local guid = Me()
	local c = guid and DB().chars[guid]
	realm = type(c) == "table" and c.realm
	return type(realm) == "string" and realm or ""
end

-- The old key of this character's books, "Realm-Faction" ("-H" with no realm known).
local function OldKey()
	return Store.Realm() .. "-" .. ns.Faction()
end

-- The key of this character's Auction House: its rules key (one house for both factions), or,
-- while that isn't known, the old "Realm-Faction". What's kept for a session by Auction House
-- (Prices' price steps) goes by it. (The name is from when a realm and faction shared one.)
function Store.RealmKey()
	return Store.RulesKey() or OldKey()
end

-- This character's price book ({ items = { [itemID] = { p, t, q } }, scanned }), made when there
-- is none: the rules key's, or the old "Realm-Faction" one while the rules aren't known.
function Store.PriceBook()
	local db = DB()
	local rules = Store.RulesKey()
	local shelf, key = db.prices, OldKey()
	if rules and type(db.books) == "table" then shelf, key = db.books.prices, rules end
	local book = shelf[key]
	if type(book) ~= "table" then
		book = { items = {} }
		shelf[key] = book
	end
	if type(book.items) ~= "table" then book.items = {} end
	return book
end

-- The old "Realm-Faction" price book this character wrote and nobody could place (it wasn't
-- merged into a rules key's): read beside the rules key's own. nil when there is none, or when
-- the old book is the one in use anyway.
function Store.OldPriceBook()
	local db = DB()
	if not Store.RulesKey() then return nil end
	local key = OldKey()
	if type(db.migrated) == "table" and db.migrated[key] then return nil end
	local book = db.prices[key]
	return type(book) == "table" and type(book.items) == "table" and book or nil
end

-- The same two for the vendors seen ({ [itemID] = { unit, who, map, x, y, at } }): kept by rules
-- key and faction.
local function VendorBook(make)
	local db = DB()
	local rules = Store.RulesKey()
	local shelf, key = db.vendors, OldKey()
	if rules and type(db.books) == "table" then shelf, key = db.books.vendors, rules .. "-" .. ns.Faction() end
	local book = shelf[key]
	if type(book) ~= "table" and make then
		book = {}
		shelf[key] = book
	end
	return type(book) == "table" and book or nil
end

local function OldVendorBook()
	local db = DB()
	if not Store.RulesKey() then return nil end
	local key = OldKey()
	if type(db.migrated) == "table" and db.migrated[key] then return nil end
	local book = db.vendors[key]
	return type(book) == "table" and book or nil
end

-- ---------------------------------------------------------------------------------------------
-- Professions and known recipes (from Core and Where as they read them)
-- ---------------------------------------------------------------------------------------------

function Store.SaveProfession(line, skill, max)
	if not line then return end
	local c = Store.Char()
	if not c then return end
	c.prof[line] = { skill = skill or 0, max = max or 0 }
end

-- A profession this character unlearned: its skill, known recipes and Leveling Guide are forgotten
-- (its alts' view, the buy lists and the trainer's list read them).
function Store.ForgetProfession(line)
	local c = Store.Char()
	if not c or not line then return end
	if type(c.prof) == "table" then c.prof[line] = nil end
	if type(c.known) == "table" then c.known[line] = nil end
	if type(c.plans) == "table" then c.plans[line] = nil end
	Store.version = Store.version + 1
end

-- set: spell -> true, every recipe of `line` this character knows.
function Store.SaveKnown(line, set)
	if not line or type(set) ~= "table" then return end
	local c = Store.Char()
	if not c then return end
	-- (Only this profession's: a list read just as the window switched profession can hold the
	-- other one's.)
	local copy = {}
	for spell in pairs(set) do
		local data = ns.Recipes and ns.Recipes[spell]
		if data and data[1] == line then copy[spell] = true end
	end
	c.known[line] = copy
	Store.version = Store.version + 1
end

-- The account's other characters you can mail: the same rules key (every numbered realm of a
-- set of rules is one server) and faction. guid -> record. While this character's rules key
-- isn't known: the ones saved on its realm, as before; a character whose rules nothing says is
-- nobody's alt.
local alts, altsAt, altsKey
function Store.Alts()
	local rules = Store.RulesKey()
	if alts and altsAt == Store.version and altsKey == rules then return alts end
	local out = {}
	local guid = Me()
	local realm, faction = Store.Realm(), ns.Faction()
	local region = Store.Region()
	for g, c in pairs(DB().chars) do
		if g ~= guid and type(c) == "table" and c.faction == faction then
			if rules then
				if RulesOf(c, region) == rules then out[g] = c end
			elseif realm ~= "" and c.realm == realm then
				out[g] = c
			end
		end
	end
	alts, altsAt, altsKey = out, Store.version, rules
	return out
end

-- The characters on the account who know a recipe: { name, ... } (this one included), each in its
-- class color when `colored`.
function Store.WhoKnows(spell, colored)
	local data = ns.Recipes and ns.Recipes[spell]
	local line = data and data[1]
	if not line then return {} end
	local out = {}
	for _, c in pairs(DB().chars) do
		local set = type(c) == "table" and c.known and c.known[line]
		if set and set[spell] and c.name then out[#out + 1] = c end
	end
	table.sort(out, function(a, b) return ns.NameLess(a.name, b.name) end)
	for i, c in ipairs(out) do
		out[i] = colored and ns.Learn and ns.Learn.ClassName(c) or c.name
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- What's held: bags, bank, mail
-- ---------------------------------------------------------------------------------------------

local function ReadBag(bag, into)
	local get = C_Container and C_Container.GetContainerNumSlots
	local info = C_Container and C_Container.GetContainerItemInfo
	if not get or not info then return end
	local slots = get(bag) or 0
	for slot = 1, slots do
		local item = info(bag, slot)
		-- (Bound items count too: a soulbound reagent is still yours to use.)
		if item and item.itemID then
			into[item.itemID] = (into[item.itemID] or 0) + (item.stackCount or 1)
		end
	end
end

-- Whether two counts tables hold the same (a craft that used nothing the plan counts changes none).
local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Each read says whether anything changed: only then is the plan's list worked out again.
local function ReadBags()
	local c = Store.Char()
	if not c then return false end
	local bags = {}
	local last = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or NUM_BAG_SLOTS or 4
	for bag = 0, math.max(NUM_BAG_SLOTS or 4, last) do ReadBag(bag, bags) end
	c.bagsAt = time()
	if Same(c.bags, bags) then return false end
	c.bags = bags
	return true
end

local bankOpen = false

-- The bank: Forever's tabs (this character's, and the account's shared ones), or the old bank and
-- its bag slots on a client without tabs.
-- A bank tab that does not report its slots yet (just after the bank opens): not read yet.
local function TabsReady(tabs)
	local get = C_Container and C_Container.GetContainerNumSlots
	for _, bag in ipairs(tabs) do
		if not get or (get(bag) or 0) == 0 then return false end
	end
	return true
end

local bankTries = 0
local ReadBank
function ReadBank()
	if not bankOpen then return false end
	local c = Store.Char()
	if not c then return false end
	local mine, shared = {}, nil
	local fetch = C_Bank and C_Bank.FetchPurchasedBankTabIDs
	local types = Enum and Enum.BankType
	if fetch and types then
		local canView = C_Bank.CanViewBank
		local tabs, acct
		if not canView or canView(types.Character) then
			local ok, list = pcall(fetch, types.Character)
			if ok and type(list) == "table" then tabs = list end
		end
		if not canView or canView(types.Account) then
			local ok, list = pcall(fetch, types.Account)
			if ok and type(list) == "table" then acct = list end
		end
		-- Its tabs not filled in yet: asked again shortly (a few times), never saved empty.
		if (tabs and not TabsReady(tabs)) or (acct and not TabsReady(acct)) then
			if bankTries < 5 then
				bankTries = bankTries + 1
				C_Timer.After(0.5, function()
					if bankOpen and ReadBank() then
						Store.version = Store.version + 1
						if ns.ShowingPlan() then ns.Changed() end
					end
				end)
			end
			return false
		end
		bankTries = 0
		for _, bag in ipairs(tabs or {}) do ReadBag(bag, mine) end
		if acct and #acct > 0 then
			shared = {}
			for _, bag in ipairs(acct) do ReadBag(bag, shared) end
		end
	else
		ReadBag(BANK_CONTAINER or -1, mine)
		local first = (NUM_BAG_SLOTS or 4) + 1
		for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do ReadBag(bag, mine) end
	end
	c.bankAt = time()
	local changed = not Same(c.bank, mine)
	c.bank = mine
	-- The account's tabs are shared by every character, whatever the realm.
	if shared then
		local db = DB()
		if not Same(db.account.bank, shared) then changed = true end
		db.account.bank = shared
	end
	return changed
end

-- BOUGHT AT THE AUCTION HOUSE, NOT SEEN IN THE MAILBOX YET. What is bought there comes by mail
-- (the buyer's letter is an invoice of its own in the game's mail window: Blizzard_MailFrame/
-- MailFrame.lua:789-803, GetInboxInvoiceInfo's "buyer"; Daylight UI's mail ledger books such
-- letters as won auctions, DaylightUI/Mail/Ledger.lua:371-377; Professionally Lost and Polestar
-- count purchases apart for the same reason), and the mailbox is only read while it is open. So
-- every purchase is counted here the moment the game reports it: c.won[itemID] = { n, at }, kept
-- with the character (it is still in the mail after a relog), and Store.Count adds it to the
-- mail's number. It ends when the mailbox is next read with its whole inbox listed: that reading
-- holds those letters, so from then on they are counted there and nowhere else (never twice).
-- One the mailbox never shows (taken on another machine, say) is dropped after WON_DAYS, the life
-- of an auction's letter.
local WON_DAYS = 30

local function Won(c)
	if type(c.won) ~= "table" then return nil end
	local now = time()
	for itemID, w in pairs(c.won) do
		if type(w) ~= "table" or (w.n or 0) <= 0 or now - (w.at or 0) > WON_DAYS * 86400 then c.won[itemID] = nil end
	end
	return c.won
end

-- How many of an item were bought at the Auction House since the mailbox was last read.
function Store.Won(itemID)
	local c = Store.Char()
	local won = c and Won(c)
	local w = won and won[itemID]
	return w and w.n or 0
end

-- `count` of an item bought at the Auction House just now.
function Store.NoteWon(itemID, count)
	if type(itemID) ~= "number" or type(count) ~= "number" or count <= 0 then return end
	local c = Store.Char()
	if not c then return end
	c.won = type(c.won) == "table" and c.won or {}
	local w = c.won[itemID]
	c.won[itemID] = { n = (type(w) == "table" and w.n or 0) + count, at = time() }
	-- (And gone from the item's price steps: what's left for sale starts at the next price.
	-- Prices.lua; as 2.7.0's Shop.NoteAuction.)
	if ns.Prices and ns.Prices.Took then ns.Prices.Took(itemID, count) end
	Store.version = Store.version + 1
	if ns.Changed and ns.ShowingPlan and ns.ShowingPlan() then ns.Changed() end
	if ns.Shop then ns.Shop.Refresh() end
end

-- The purchases, as the game reports them (Blizzard_APIDocumentationGenerated/
-- AuctionHouseDocumentation.lua): COMMODITY_PURCHASED(itemID, quantity) :1386-1394 for stackable
-- goods, ITEM_PURCHASED(itemID) :1443-1450 for single items. Daylight UI's own Auction House
-- found that COMMODITY_PURCHASED "didn't always come" (DaylightUI_AuctionHouse/Buy.lua:194) and
-- counts what it confirmed when COMMODITY_PURCHASE_SUCCEEDED (:1380, no payload) answers. The same
-- here, for any window: what was last confirmed (C_AuctionHouse.ConfirmCommoditiesPurchase(itemID,
-- quantity) :83-91, heard through hooksecurefunc, which leaves the game's own call as it was) is
-- counted when SUCCEEDED comes, unless COMMODITY_PURCHASED already counted that item; and a
-- COMMODITY_PURCHASED that comes after such a count is that same purchase and is not counted again.
local confirmed            -- { itemID, qty, at, seen (PURCHASED came), counted (SUCCEEDED counted it) }
local function CommodityConfirmed(itemID, quantity)
	if type(itemID) == "number" and type(quantity) == "number" and quantity > 0 then
		confirmed = { itemID = itemID, qty = quantity, at = GetTime() }
	end
end
-- Whether a purchase on the Auction House is being confirmed right now (asked of the game and not
-- answered yet): Prices' check of prices sends nothing meanwhile.
function Store.Confirming()
	local p = confirmed
	return p ~= nil and not p.counted and not p.seen and GetTime() - p.at < 60
end

local function CommodityPurchased(itemID, quantity)
	local p = confirmed
	if p and p.itemID == itemID and GetTime() - p.at < 30 then
		if p.counted then
			confirmed = nil
			return
		end
		p.seen = true
	end
	Store.NoteWon(itemID, quantity)
end
local function CommoditySucceeded()
	local p = confirmed
	if not p or GetTime() - p.at >= 30 then
		confirmed = nil
		return
	end
	if p.seen then
		confirmed = nil
	elseif not p.counted then
		p.counted = true
		Store.NoteWon(p.itemID, p.qty)
	end
end

-- The mailbox: every item waiting, except cash-on-delivery ones (not yours until you pay).
local inboxListed = false     -- MAIL_INBOX_UPDATE came since the mailbox opened: its list is in
local function ReadMail()
	local c = Store.Char()
	if not c or not GetInboxNumItems or not GetInboxItem then return false end
	local mail = {}
	local n, total = GetInboxNumItems()
	n = n or 0
	for i = 1, n do
		local cod = GetInboxHeaderInfo and select(6, GetInboxHeaderInfo(i))
		if not cod or cod == 0 then
			for j = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
				local _, itemID, _, count = GetInboxItem(i, j)
				if itemID then mail[itemID] = (mail[itemID] or 0) + (count or 1) end
			end
		end
	end
	c.mailAt = time()
	-- (What was bought at the Auction House is in this reading now: counted here from now on. Not
	-- while the inbox is not all listed: GetInboxNumItems' second number, the letters there are
	-- in all, MailFrame.lua:317.)
	local settled = false
	if inboxListed and (type(total) ~= "number" or total <= n) and type(c.won) == "table" and next(c.won) then
		c.won = nil
		settled = true
	end
	if Same(c.mail, mail) then return settled end
	c.mail = mail
	return true
end

-- How many of an item you have: here (bags), bank (this character's and the account's), mail, and
-- each alt on this realm and faction ({ { name, count } }, most first). Totals.
function Store.Count(itemID)
	local c = Store.Char()
	-- (altHeld: the alts' bags and bank only, without their mail: what DaylightUI's bag tooltip counts.)
	local out = { bags = 0, bank = 0, mail = 0, alts = {}, altTotal = 0, altHeld = 0 }
	if not c then return out end
	out.bags = (c.bags and c.bags[itemID]) or 0
	out.bank = (c.bank and c.bank[itemID]) or 0
	local shared = DB().account.bank
	out.bank = out.bank + ((shared and shared[itemID]) or 0)
	-- (won: bought at the Auction House and not seen in the mailbox yet. It is in the mail.)
	local won = Won(c)
	out.won = won and won[itemID] and won[itemID].n or 0
	out.mail = ((c.mail and c.mail[itemID]) or 0) + out.won
	for _, alt in pairs(Store.Alts()) do
		local held = ((alt.bags and alt.bags[itemID]) or 0) + ((alt.bank and alt.bank[itemID]) or 0)
		local n = held + ((alt.mail and alt.mail[itemID]) or 0)
		if n > 0 then
			out.alts[#out.alts + 1] = { name = alt.name or "?", count = n }
			out.altTotal = out.altTotal + n
			out.altHeld = out.altHeld + held
		end
	end
	table.sort(out.alts, function(a, b) return a.count > b.count end)
	out.mine = out.bags + out.bank + out.mail
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Vendors you've visited: what they sell that recipes use, and for how much (your discounts in).
-- ---------------------------------------------------------------------------------------------

local reagents        -- itemID -> true: every item a recipe in the data uses
local function Reagents()
	if reagents then return reagents end
	reagents = {}
	for _, data in pairs(ns.Recipes or {}) do
		local mats = data[3]
		for i = 1, #(mats or {}), 2 do reagents[mats[i]] = true end
	end
	return reagents
end
Store.Reagents = Reagents

local function ReadMerchant()
	if not GetMerchantNumItems or not GetMerchantItemID then return false end
	local n = GetMerchantNumItems() or 0
	if n == 0 then return false end
	local changed = false
	local want = Reagents()
	local byRealm = VendorBook(true)
	local who = UnitName("npc")
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local x, y
	if map and C_Map.GetPlayerMapPosition then
		local pos = C_Map.GetPlayerMapPosition(map, "player")
		if pos then x, y = pos:GetXY() end
	end
	for i = 1, n do
		local itemID = GetMerchantItemID(i)
		if itemID and want[itemID] then
			local price, stack, extended
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local info = C_MerchantFrame.GetItemInfo(i)
				if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
			elseif GetMerchantItemInfo then
				local _, _, p, s, _, _, _, ext = GetMerchantItemInfo(i)
				price, stack, extended = p, s, ext
			end
			if price and price > 0 and not extended then
				local unit = price / math.max(1, stack or 1)
				local old = byRealm[itemID]
				if not old or unit <= old.unit or old.who == who then
					if not old or old.unit ~= unit then changed = true end
					byRealm[itemID] = { unit = unit, who = who, map = map, x = x and x * 100, y = y and y * 100, at = time() }
				end
			end
		end
	end
	-- (Vendor prices are kept by the price math: thrown away so the new ones count.)
	if changed and ns.Calc then ns.Calc.Forget() end
	return changed
end

-- The cheapest vendor you've seen selling an item: unit price, who, place ({ mapID, x, y }).
function Store.SeenVendor(itemID)
	local book, old = VendorBook(), OldVendorBook()
	local v = book and book[itemID]
	-- (An old book nobody could place: its vendor when it's the cheaper one.)
	local w = old and old[itemID]
	if type(w) == "table" and (type(v) ~= "table" or (tonumber(w.unit) or math.huge) < (tonumber(v.unit) or math.huge)) then v = w end
	if type(v) ~= "table" then return nil end
	return v.unit, v.who, v.map and { mapID = v.map, x = v.x, y = v.y } or nil
end

-- ---------------------------------------------------------------------------------------------
-- Events: each read once, a moment after the last change
-- ---------------------------------------------------------------------------------------------

local pending = {}
local function Soon(what, fn, delay)
	if pending[what] then return end
	pending[what] = true
	C_Timer.After(delay or 0.5, function()
		pending[what] = nil
		local ok, changed = pcall(fn)
		if not ok then
			geterrorhandler()(changed)
			return
		end
		-- Only what changed, and only the page that shows it (the Leveling Guide's list).
		if not changed then return end
		Store.version = Store.version + 1
		if ns.Changed and ns.ShowingPlan() then ns.Changed() end
		-- (The buy lists at a vendor or the Auction House count from this read, window or not.)
		if ns.Shop then ns.Shop.Refresh() end
	end)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GAME_RULES_CHANGED", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MERCHANT_SHOW",
	"COMMODITY_PURCHASED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "ITEM_PURCHASED" }) do
	pcall(f.RegisterEvent, f, e)
end
if type(hooksecurefunc) == "function" and type(C_AuctionHouse) == "table"
	and type(C_AuctionHouse.ConfirmCommoditiesPurchase) == "function" then
	pcall(hooksecurefunc, C_AuctionHouse, "ConfirmCommoditiesPurchase", CommodityConfirmed)
end
f:SetScript("OnEvent", function(_, event, a, b)
	if event == "COMMODITY_PURCHASED" then
		CommodityPurchased(a, b)
		return
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		CommoditySucceeded()
		return
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		confirmed = nil
		return
	elseif event == "ITEM_PURCHASED" then
		Store.NoteWon(a, 1)
		return
	end
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "GAME_RULES_CHANGED" then
		-- (The game's rules for this character can come in after login: its key is saved when
		-- they do, and what hangs on it worked out again.)
		local was = keptRules
		keptRules = Store.LiveRules()
		Store.Char()
		if keptRules ~= was then
			Store.version = Store.version + 1
			if ns.Calc then ns.Calc.Forget() end
		end
		if event == "PLAYER_LOGIN" then Soon("bags", ReadBags, 2) end
	elseif event == "BAG_UPDATE_DELAYED" then
		Soon("bags", ReadBags)
		if bankOpen then Soon("bank", ReadBank) end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		Soon("bank", ReadBank, 0.2)
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	elseif event == "PLAYERBANKSLOTS_CHANGED" then
		if bankOpen then Soon("bank", ReadBank) end
	elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
		inboxListed = event == "MAIL_INBOX_UPDATE"
		Soon("mail", ReadMail)
	elseif event == "MERCHANT_SHOW" then
		-- (Forever can show the merchant's window a moment after the event.)
		Soon("merchant", ReadMerchant, 0.3)
	end
end)
