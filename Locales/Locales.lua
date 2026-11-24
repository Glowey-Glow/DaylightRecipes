-- Glowey's Recipes' own text in the player's language.
-- The English text is the key and the fallback: L["Recipes"] gives "Recipes" when the
-- language has no line for it, so a missing line never breaks anything.
-- Each language has a file next to this one that returns at once unless the game runs in that
-- language, then fills L["English"] = "Translation". Keys are whole sentences with
-- string.format holes, never sentences glued from pieces, since word order differs.
-- Saved data, setting keys, dropdown value keys, slash words and macro names stay English.

local ADDON, ns = ...

-- The language of the addon's own text, ns.LOCALE: Daylight UI's own pick while it runs (its Home >
-- Language, since 2.2.5), else the Language picked on the General page of Glowey's Plugins window
-- (Host.lua), else the game's. One of the seven there are files for; enGB reads enUS, esMX esES.
-- The game's own words (GAME below) stay in the game's language.
local CLIENT = GetLocale and GetLocale() or "enUS"
local FOLD = { enGB = "enUS", esMX = "esES" }
local HAVE = { enUS = true, deDE = true, esES = true, frFR = true, ruRU = true, koKR = true, zhCN = true }
local function Picked()
	local D = rawget(_G, "DaylightUI")
	if type(D) == "table" and type(D.API) == "table" and D.API.major == 1 then
		-- (Its pick is on from its own ADDON_LOADED, which comes before any addon loading after it:
		-- DaylightUI/Locales/Locales.lua:16-20, Core.lua:984-992. Its saved pick, should it not be.)
		local pick = D.LOCALE
		local db = rawget(_G, "DaylightUIDB")
		local saved = type(db) == "table" and db.language
		if type(saved) == "string" and saved ~= "auto" and pick == D.CLIENT_LOCALE then pick = saved end
		return pick
	end
	-- (Kept in every Glowey addon's <Addon>Settings, the newest counting. Ours can be read this early
	-- because the .toc loads the saved variables first: LoadSavedVariablesFirst.)
	local best, at
	local own = rawget(_G, ADDON .. "Settings")
	if type(own) == "table" and type(own.general) == "table" then best, at = own.general.language, own.generalAt or 0 end
	local host = rawget(_G, "GloweyHost")
	local S = type(host) == "table" and host.state
	if type(S) == "table" and type(S.general) == "table" and (S.generalAt or -1) >= (at or -1) then best = S.general.language end
	return best
end
local pick = Picked()
pick = type(pick) == "string" and (FOLD[pick] or pick) or nil
ns.LOCALE = (pick and HAVE[pick]) and pick or (FOLD[CLIENT] or CLIENT)

-- Keys whose English is word for word one of the game's global strings (same case, punctuation
-- and holes), in the same sense: on a non-English client the game's own translation stands in
-- for ours, which stays as the fallback when the client lacks the global. English clients keep
-- ours. Left out on purpose: same words in another sense (Missing, Recommended, Remove, Queued,
-- Recipe, Poisons, Clear, Guide), "Recipes" (also the plugin's short name on DaylightUI's rail),
-- and "Skill-ups" and "Auction House", whose game words are too long for where they sit.
-- (The game's words don't stand in for ours on an English game, nor for ours picked in another
-- language than the game's.)
local ENGLISH = CLIENT:sub(1, 2) == "en" or ns.LOCALE ~= (FOLD[CLIENT] or CLIENT)
local GAME = {
	["%d%%"] = "PERCENTAGE_STRING",
	["Apprentice"] = "APPRENTICE",
	["Artisan"] = "ARTISAN",
	["Cooking"] = "PROFESSIONS_COOKING",
	["Create"] = "CREATE_PROFESSION",
	["Disenchant"] = "ROLL_DISENCHANT",
	["Done"] = "DONE",
	["Drop"] = "BATTLE_PET_SOURCE_1",
	["Enchant"] = "ENSCRIBE",
	["Expert"] = "EXPERT",
	["First Aid"] = "PROFESSIONS_FIRST_AID",
	["Journeyman"] = "JOURNEYMAN",
	["Later"] = "CHARACTER_UPGRADE_POPUP_LATER",
	["Level %d"] = "UNIT_LEVEL_TEMPLATE",
	["No"] = "NO",
	["Other"] = "OTHER",
	["Profession"] = "GUILD_ROSTER_DROPDOWN_PROFESSION",
	["Professions"] = "TRADE_SKILLS",
	["Quest"] = "BATTLE_PET_SOURCE_2",
	["Search"] = "SEARCH",
	["Total"] = "TOTAL",
	["Vendor"] = "BATTLE_PET_SOURCE_3",
	["Yes"] = "YES",
}

-- The game's text for a key in GAME, on a non-English client that has it; else nil.
local function Game(key)
	local global = not ENGLISH and GAME[key]
	local v = global and _G[global]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- A language file's line for a key in GAME is kept only where the game has no text for it.
ns.L = setmetatable({}, {
	__index = function(_, key) return Game(key) or key end,
	__newindex = function(t, key, value) rawset(t, key, Game(key) or value) end,
})

-- How each language picks a plural form:
--   "one": a single form (Korean, Chinese);
--   "ru":  1 / 2-4 / 5+ with 11-14 always the many form (Russian);
--   "fr":  one for 0 and 1 (French);
--   otherwise one for exactly 1.
local RULE = { koKR = "one", zhCN = "one", zhTW = "one", ruRU = "ru", frFR = "fr" }

-- ns.Plural(n, one, many[, few]): the English key of the right form for n, translated.
-- one and many are whole English sentences ("%d recipe you don't know" /
-- "%d recipes you don't know"); few is Russian's 2-4 form, which defaults to many and is found
-- in ruRU.lua under the key "<many>|few" when a language needs it.
local L = ns.L
function ns.Plural(n, one, many, few)
	local rule = RULE[ns.LOCALE]
	n = math.abs(tonumber(n) or 0)
	if rule == "one" then return L[many] end
	if rule == "ru" then
		local m10, m100 = n % 10, n % 100
		if m10 == 1 and m100 ~= 11 then return L[one] end
		if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
			local key = few or (many .. "|few")
			local text = rawget(L, key)
			if text then return text end
			return L[many]
		end
		return L[many]
	end
	if rule == "fr" then
		if n < 2 then return L[one] end
		return L[many]
	end
	if n == 1 then return L[one] end
	return L[many]
end
