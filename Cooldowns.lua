-- Craft cooldowns: the recipes you know that can only be made once in a while (Alchemy's
-- transmutes, Tailoring's Mooncloth, Leatherworking's Cured Rugged Hide, and any other the game
-- reports a cooldown on), shown in a box at the foot of the professions list (Window.lua).
--
-- The recipe data carries no cooldowns, so they come from the game:
--  * which recipes have one: the names above, plus any recipe the game ever reports a cooldown for
--    while its profession is open (remembered for the account, so Forever's own ones count too);
--  * how long is left: the game's spell cooldown when it answers, else the profession's own
--    (GetRecipeCooldown, only while that profession is open). Each is saved as the time it's ready,
--    per character, so it carries across logouts.
-- Transmutes that are ready, or ready at the same moment (a shared cooldown), make one tile.
-- Nothing runs on a timer here: the profession opening or changing, and a cooldown recipe cast,
-- read it again; the box's own countdown ticks only while it shows (Window.lua).
-- A value the game hands over as secret is never compared or counted: it's as if it said nothing.

local _, ns = ...
if not ns.ok then return end

local L = ns.L

local Cooldowns = {}
ns.Cooldowns = Cooldowns

Cooldowns.NAMES = { "^Transmute", "^Mooncloth$", "^Cured Rugged Hide$" }
Cooldowns.GCD = 2      -- a spell cooldown this short or shorter is the global cooldown, not the recipe's
local SHARED = 120     -- transmutes ready within two minutes of each other share a tile

local secret = _G.issecretvalue
local function IsSecret(v) return secret ~= nil and secret(v) == true end
local function Plain(v)
	if IsSecret(v) then return nil end
	return v
end

local function TS(name, ...)
	local fn = C_TradeSkillUI and C_TradeSkillUI[name]
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

-- Recipes seen with a cooldown on any character (spell -> true).
local function Seen()
	local db = ns.Store and ns.Store.DB()
	if not db then return {} end
	db.account = type(db.account) == "table" and db.account or {}
	db.account.cooldownRecipes = type(db.account.cooldownRecipes) == "table" and db.account.cooldownRecipes or {}
	return db.account.cooldownRecipes
end

-- This character's saved cooldowns: spell -> { at = time() it's ready (0: ready), line }.
local function Mine()
	local c = ns.Store and ns.Store.Char()
	if not c then return nil end
	c.cooldowns = type(c.cooldowns) == "table" and c.cooldowns or {}
	return c.cooldowns
end

local function Save(mine, spell, at, line)
	local e = mine[spell]
	if type(e) ~= "table" then
		e = {}
		mine[spell] = e
	end
	e.at = at
	e.line = line or e.line
end

local function SavedAt(e)
	if type(e) == "table" then return tonumber(e.at) or 0 end
	return tonumber(e) or 0
end

local nameCache = {}
function Cooldowns.IsCooldownRecipe(spell)
	if type(spell) ~= "number" then return false end
	if Seen()[spell] then return true end
	local v = nameCache[spell]
	if v ~= nil then return v end
	v = false
	local name = ns.RecipeNames and ns.RecipeNames[spell]
	if type(name) == "string" then
		for _, pattern in ipairs(Cooldowns.NAMES) do
			if name:find(pattern) then v = true break end
		end
	end
	nameCache[spell] = v
	return v
end

-- What the game's spell cooldown says: the time() it's ready, or nil when it says nothing useful
-- (no cooldown running, only the global cooldown, or secret).
local function Live(spell)
	local get = C_Spell and C_Spell.GetSpellCooldown
	if type(get) ~= "function" then return nil end
	local ok, info = pcall(get, spell)
	if not ok or type(info) ~= "table" then return nil end
	if info.isActive == false or info.isEnabled == false then return nil end
	local start, duration = Plain(info.startTime), Plain(info.duration)
	if type(start) ~= "number" or type(duration) ~= "number" or start <= 0 or duration <= Cooldowns.GCD then return nil end
	return time() + math.max(0, math.floor(start + duration - GetTime() + 0.5))
end

-- The open profession is yours (not someone's linked recipes) and the game can answer for it.
local open = false     -- a trade skill is open (TRADE_SKILL_SHOW until TRADE_SKILL_CLOSE)
local scanned = {}     -- skill line -> its whole recipe list was read since it opened

local function OwnLine()
	local S = ns.state
	if not (open and S and S.mode and S.line) or S.linked then return nil end
	return S.line
end

-- One recipe's cooldown from the open profession, saved. True when the game answered.
local function ReadRecipe(spell, line, mine, seen, now)
	local ok, cd, _, charges = TS("GetRecipeCooldown", spell)
	if not ok or IsSecret(cd) or IsSecret(charges) then return false end
	-- (Saved under the data's profession when it has the recipe: the list read just as the window
	-- switched profession can still be the other one's.)
	local data = ns.Recipes and ns.Recipes[spell]
	if type(data) == "table" and type(data[1]) == "number" then line = data[1] end
	-- (As the game's own window reads it: a cooldown left and no charge to spend.)
	if type(cd) == "number" and cd > 0 and not (type(charges) == "number" and charges > 0) then
		seen[spell] = true
		Save(mine, spell, now + math.floor(cd + 0.5), line)
	elseif Cooldowns.IsCooldownRecipe(spell) then
		Save(mine, spell, 0, line)
	end
	return true
end

-- Reads the cooldowns of the open profession's recipes and saves when each is ready. The first
-- time after it opens (or learns a recipe) every learned recipe is asked, which is how recipes
-- with a cooldown no name gives away are found; after that only the cooldown ones.
function Cooldowns.Record()
	local line = OwnLine()
	local mine = Mine()
	if not (line and mine) then return end
	local seen, now = Seen(), time()
	if not scanned[line] then
		local ok, ids = TS("GetAllRecipeIDs")
		if ok and type(ids) == "table" and #ids > 0 then
			for _, spell in ipairs(ids) do
				local got, info = TS("GetRecipeInfo", spell)
				if got and type(info) == "table" and info.learned and not info.isDummyRecipe then
					ReadRecipe(spell, line, mine, seen, now)
				end
			end
			scanned[line] = true
		end
		return
	end
	local c = ns.Store.Char()
	local known = c and type(c.known) == "table" and c.known[line]
	if type(known) == "table" then
		for spell in pairs(known) do
			if Cooldowns.IsCooldownRecipe(spell) then ReadRecipe(spell, line, mine, seen, now) end
		end
	end
	for spell, e in pairs(mine) do
		if type(e) == "table" and e.line == line and not (known and known[spell]) then
			ReadRecipe(spell, line, mine, seen, now)
		end
	end
end

-- When a recipe is ready (time(); 0 or past: ready), from the game when it answers, else saved.
function Cooldowns.ReadyAt(spell, line)
	local mine = Mine()
	local live = Live(spell)
	if live then
		if mine then Save(mine, spell, live, line) end
		return live
	end
	return mine and SavedAt(mine[spell]) or 0
end

local function Icon(spell, item)
	local icon = item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
	if not icon and C_Spell and C_Spell.GetSpellTexture then
		local ok, t = pcall(C_Spell.GetSpellTexture, spell)
		if ok then icon = t end
	end
	return icon
end

-- The tiles for this character, ready ones first, then the soonest:
-- { spells = { ... }, names = { ... }, icon, readyAt (0: ready), line }.
-- Its spells and names in the same order (by name); a click opens the first.
function Cooldowns.List()
	local out = {}
	local c = ns.Store and ns.Store.Char()
	if not (c and type(c.known) == "table") then return out end
	local mine = Mine() or {}
	local now = time()
	local rows, have = {}, {}
	local function Add(spell, line)
		if have[spell] or not Cooldowns.IsCooldownRecipe(spell) then return end
		have[spell] = true
		local at = Cooldowns.ReadyAt(spell, line)
		if at <= now then at = 0 end
		local data = ns.Recipes and ns.Recipes[spell]
		local item = type(data) == "table" and type(data[4]) == "table" and data[4][1] or nil
		local english = ns.RecipeNames and ns.RecipeNames[spell]
		rows[#rows + 1] = { spell = spell, line = line, at = at, item = item,
			name = ns.SpellName(spell) or english or tostring(spell),
			transmute = type(english) == "string" and english:find("^Transmute") ~= nil }
	end
	for line, set in pairs(c.known) do
		if type(set) == "table" then
			for spell in pairs(set) do Add(spell, line) end
		end
	end
	-- (A recipe the data doesn't have, found by its cooldown: from what was saved.)
	for spell, e in pairs(mine) do
		if type(e) == "table" and e.line then Add(spell, e.line) end
	end
	table.sort(rows, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return ns.NameLess(a.name, b.name)
	end)
	-- Transmutes ready, or ready within SHARED of each other, share a tile.
	local shared
	for _, r in ipairs(rows) do
		local t
		if r.transmute and shared and ((shared.readyAt == 0 and r.at == 0)
			or (shared.readyAt > 0 and r.at > 0 and r.at - shared.readyAt <= SHARED)) then
			t = shared
		else
			t = { spells = {}, names = {}, readyAt = r.at, line = r.line, icon = Icon(r.spell, r.item) }
			out[#out + 1] = t
			if r.transmute then shared = t end
		end
		t.spells[#t.spells + 1] = r.spell
		t.names[#t.names + 1] = r.name
	end
	return out
end

-- How long until ready: "2d 4h", "5h 12m", "23m" (the tooltip).
function Cooldowns.Left(readyAt)
	local s = math.max(0, readyAt - time())
	local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
	if d > 0 then return L["%dd %dh"]:format(d, h) end
	if h > 0 then return L["%dh %dm"]:format(h, m) end
	return L["%dm"]:format(math.max(1, m))
end

-- The same, one unit only, to fit on a tile: "2d", "5h", "23m" (rounded up, so "1m" until ready).
function Cooldowns.Short(readyAt)
	local s = math.max(0, readyAt - time())
	if s >= 86400 then return L["%dd"]:format(math.ceil(s / 86400)) end
	if s >= 3600 then return L["%dh"]:format(math.ceil(s / 3600)) end
	return L["%dm"]:format(math.max(1, math.ceil(s / 60)))
end

-- ---------------------------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------------------------
-- A profession opened, learned a recipe or its list changed (a craft, a bag change): read its
-- cooldowns a moment later, once. A cooldown recipe you just made: read again once the game has
-- started its cooldown (SPELL_UPDATE_COOLDOWN, listened to only until then). The box repaints if
-- the window shows.
local queued = false
local watching = false   -- a cooldown recipe was just cast: the next cooldown update reads it

local function Soon()
	if queued then return end
	queued = true
	C_Timer.After(0.3, function()
		queued = false
		local ok, err = pcall(Cooldowns.Record)
		if not ok then geterrorhandler()(err) end
		if ns.Window and ns.Window.PaintCooldowns then ns.Window.PaintCooldowns() end
	end)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
	"TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "SPELL_UPDATE_COOLDOWN" }) do
	pcall(f.RegisterEvent, f, e)
end
pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")
f:SetScript("OnEvent", function(_, event, _, _, spell)
	if event == "SPELL_UPDATE_COOLDOWN" then
		if not watching then return end
		watching = false
		Soon()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		spell = Plain(spell)
		if not Cooldowns.IsCooldownRecipe(spell) then return end
		watching = true
		Soon()
	elseif event == "TRADE_SKILL_CLOSE" then
		open = false
		wipe(scanned)
	else
		if event == "TRADE_SKILL_SHOW" then open = true end
		-- (Another profession, or a recipe learned: every recipe is asked again.)
		if event ~= "TRADE_SKILL_LIST_UPDATE" then wipe(scanned) end
		Soon()
	end
end)
