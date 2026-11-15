-- Daylight Recipes' own text in the player's language.
-- The English text is the key and the fallback: L["Recipes"] gives "Recipes" when the
-- language has no line for it, so a missing line never breaks anything.
-- Each language has a file next to this one that returns at once unless the game runs in that
-- language, then fills L["English"] = "Translation". Keys are whole sentences with
-- string.format holes, never sentences glued from pieces, since word order differs.
-- Saved data, setting keys, dropdown value keys, slash words and macro names stay English.

local _, ns = ...

ns.LOCALE = GetLocale and GetLocale() or "enUS"
if ns.LOCALE == "enGB" then ns.LOCALE = "enUS" end
if ns.LOCALE == "esMX" then ns.LOCALE = "esES" end

ns.L = setmetatable({}, { __index = function(_, key) return key end })

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
