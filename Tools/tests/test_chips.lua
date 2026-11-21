-- The title bar's profession chips (3.0.2): the rule for which of them show (WindowState.ChipFit,
-- pure arithmetic) and the abbreviations every language file carries for them.
-- luacheck: globals ADDON_ROOT NS
-- luacheck: read globals T
local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/WindowState.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "WindowState.lua not found")
local ns = {}
assert(loadfile(ROOT .. "/WindowState.lua"))("DaylightRecipes", ns)
local State = ns.WinState

local GAP = 4
local function plus(n) return 14 + 6 * #("+" .. n) end
local function total(widths, list, left)
	local w = 0
	for i, index in ipairs(list) do w = w + widths[index] + (i > 1 and GAP or 0) end
	if left > 0 then w = w + (#list > 0 and GAP or 0) + plus(left) end
	return w
end
local function same(list, want) return table.concat(list, ",") == table.concat(want, ",") end

T.case("they all fit: all of them, in order, no +N", function()
	local widths = { 100, 26, 26, 38, 38, 38 }
	local list, left = State.ChipFit(widths, 1, 300, GAP, plus)
	T.ok(same(list, { 1, 2, 3, 4, 5, 6 }) and left == 0, "six chips in 300")
	list, left = State.ChipFit(widths, nil, 300, GAP, plus)
	T.ok(same(list, { 1, 2, 3, 4, 5, 6 }) and left == 0, "none open: the same")
	list, left = State.ChipFit({}, nil, 300, GAP, plus)
	T.ok(#list == 0 and left == 0, "no profession: no chip, no +N")
end)

T.case("too many: the last ones go behind +N, whole chips only, never wider than the room", function()
	-- Ten professions (a client with more of them), the first open.
	local widths = { 104, 38, 44, 38, 44, 32, 44, 38, 38, 44 }
	for room = 140, 520, 7 do
		local list, left = State.ChipFit(widths, 1, room, GAP, plus)
		T.eq(#list + left, 10, "every profession is shown or counted at " .. room)
		T.ok(total(widths, list, left) <= room, "what shows fits in " .. room)
		for i = 2, #list do T.ok(list[i] > list[i - 1], "in the bar's order at " .. room) end
		-- (One more would not have fitted.)
		if left > 0 then
			local more = {}
			for i = 1, #list + 1 do more[i] = i end
			T.ok(total(widths, more, left - 1) > room, "as many as fit at " .. room)
		end
	end
	local _, left = State.ChipFit(widths, 1, 330, GAP, plus)
	T.ok(left > 0 and left < 10, "at the window's real room some are behind +N: " .. left)
end)

T.case("the open one is never behind +N: it comes forward", function()
	local widths = { 38, 38, 44, 38, 44, 32, 44, 38, 38, 110 }
	for open = 1, 10 do
		for room = 60, 520, 11 do
			local list, left = State.ChipFit(widths, open, room, GAP, plus)
			local found = false
			for _, index in ipairs(list) do if index == open then found = true end end
			T.ok(found, ("chip %d open in %d: on show"):format(open, room))
			T.eq(#list + left, 10, "and all are accounted for")
			-- (Brought forward, it takes the last place on show; the others keep their order.)
			for i = 2, #list - 1 do T.ok(list[i] > list[i - 1], "the others in order") end
			if #list > 1 or left == 0 then T.ok(total(widths, list, left) <= room or #list == 1, "what shows fits") end
		end
	end
	-- German, "Lederverarbeitung" open with its skill, as the tenth of ten.
	local list, left = State.ChipFit(widths, 10, 330, GAP, plus)
	T.eq(list[#list], 10, "the open one last on show")
	T.ok(left > 0, "with the rest behind +N")
	-- A bar narrower than the open chip alone: it still shows, whole.
	list, left = State.ChipFit(widths, 10, 40, GAP, plus)
	T.ok(same(list, { 10 }) and left == 9, "the open one alone is the least there can be")
end)

-- ---- the abbreviations ---------------------------------------------------------------------------
local KEYS = { "Alch", "BS", "Ench", "Eng", "Herb", "LW", "Mine", "Skin", "Tail", "Cook", "FA", "Fish", "Pois", "Camp" }
local function letters(s)
	local n = 0
	for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
	return n
end
T.case("English: the mockup's set, one for every profession the plugin knows and Camping", function()
	local f = assert(io.open(ROOT .. "/WindowChips.lua", "rb"))
	local src = f:read("*a")
	f:close()
	for _, line in ipairs({ 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356, 40 }) do
		T.ok(src:find("%[" .. line .. "%] = L%[\"%a+\"%]"), "skill line " .. line .. " has an abbreviation")
	end
	for _, key in ipairs(KEYS) do
		T.ok(src:find('L["' .. key .. '"]', 1, true), key .. " is used")
		T.ok(letters(key) >= 2 and letters(key) <= 5, key .. ": two to five letters")
	end
	local core = assert(io.open(ROOT .. "/Core.lua", "rb"))
	local lines = core:read("*a"):match("ns%.LINES = (%b{})")
	core:close()
	for line in lines:gmatch("%[(%d+)%]") do
		T.ok(src:find("%[" .. line .. "%] = L%["), "ns.LINES " .. line .. " has an abbreviation")
	end
end)
for _, loc in ipairs({ "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN" }) do
	T.case(loc .. ": its own abbreviations, two to five letters, no two alike", function()
		local f = assert(io.open(ROOT .. "/Locales/" .. loc .. ".lua", "rb"))
		local src = f:read("*a")
		f:close()
		local seen = {}
		for _, key in ipairs(KEYS) do
			local v = src:match('\nL%["' .. key .. '"%] = "([^"\r\n]*)"')
			T.ok(v ~= nil and v ~= "", key .. " is translated")
			-- (One sign can be a whole word in Korean and Chinese: "독", poison.)
			local least = (loc == "koKR" or loc == "zhCN") and 1 or 2
			T.ok(letters(v) >= least and letters(v) <= 5, key .. " = " .. v .. ": short enough for a chip")
			T.ok(not seen[v], key .. " = " .. v .. ": not the same as " .. tostring(seen[v]))
			seen[v] = key
		end
		T.ok(src:find("Title bar abbreviations", 1, true), "with a note on which are in players' use")
	end)
end

return T.done()
