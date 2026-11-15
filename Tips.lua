-- Help outside the pane:
--   * Item tooltips (DaylightUI 1.7 and later): which professions use a material and in how many
--     recipes, what your plans need of it (yours, and your alts' on this realm), and for a recipe
--     item who on your account already knows it. Read from tables made once, so a tooltip filling
--     several times a second costs a few lookups.
--   * Trainer reminders: a chat line when a skill-up lets you learn new recipes at a trainer, and
--     when a profession reaches its cap and needs the next rank.
--   * The recipe "Craft next" picks gets a small mark in DaylightUI's profession list.
local _, ns = ...
if not ns.ok then return end

local API, me = ns.API, ns.me
local Tips = {}
ns.Tips = Tips

local NAMES = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [185] = "Cooking",
	[186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [129] = "First Aid",
	[40] = "Poisons" }
function Tips.LineName(line) return NAMES[line] or "Profession" end

-- ---------------------------------------------------------------------------------------------
-- Indexes, made once
-- ---------------------------------------------------------------------------------------------

local usedBy      -- itemID -> { [line] = recipe count }
local teaches     -- recipe item -> spell
local function Index()
	if usedBy then return end
	usedBy, teaches = {}, {}
	for spell, data in pairs(ns.Recipes or {}) do
		local mats, line = data[3], data[1]
		local seen = {}
		for i = 1, #(mats or {}), 2 do
			local item = mats[i]
			if not seen[item] then
				seen[item] = true
				local t = usedBy[item] or {}
				usedBy[item] = t
				t[line] = (t[line] or 0) + 1
			end
		end
		if data[5] then teaches[data[5]] = spell end
	end
end

local usedText = {}      -- itemID -> its "Used in" text (false: none), made once
local function UsedText(itemID)
	local cached = usedText[itemID]
	if cached ~= nil then return cached or nil end
	local t = usedBy[itemID]
	if not t then
		usedText[itemID] = false
		return nil
	end
	local parts = {}
	for line, n in pairs(t) do parts[#parts + 1] = { NAMES[line] or "?", n } end
	table.sort(parts, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(3, #parts) do out[i] = ("%s %d"):format(parts[i][1], parts[i][2]) end
	if #parts > 3 then out[#out + 1] = "..." end
	local text = table.concat(out, ", ")
	usedText[itemID] = text
	return text
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

local function ItemLines(lines, data)
	if not ns.Get("tooltips") then return end
	local itemID = type(data) == "table" and data.itemID
	if type(itemID) ~= "number" then return end
	Index()
	local spell = teaches[itemID]
	if spell then
		local who = ns.Store.WhoKnows(spell)
		lines.Line("Known by", #who > 0 and table.concat(who, ", ") or "No one on your account")
	end
	local used = UsedText(itemID)
	if used then lines.Line("Used in", used) end
	-- Plans: yours first, then your alts' on this realm.
	local mine = ns.Store.Char()
	local function planLines(c, who)
		if type(c) ~= "table" or type(c.plans) ~= "table" then return end
		for line, plan in pairs(c.plans) do
			local n = type(plan) == "table" and plan.need and plan.need[itemID]
			if n and n > 0 then
				local label = (who and (who .. "'s ") or "Your ") .. (NAMES[line] or "") .. " guide"
				lines.Line(label, ("%d (to %d)"):format(n, plan.target or 0))
			end
		end
	end
	planLines(mine, nil)
	for _, alt in pairs(ns.Store.Alts()) do planLines(alt, alt.name) end
end

-- ---------------------------------------------------------------------------------------------
-- Trainer reminders
-- ---------------------------------------------------------------------------------------------

-- The trainer recipes you don't know that opened up between `from` (not counted) and `to`
-- (counted): a craft can give two points, and skill gained with the window shut comes as one jump.
local function NewAt(line, from, to)
	local out = {}
	local known = ns.Where.KnownSet()
	for spell, data in pairs(ns.Recipes or {}) do
		if data[1] == line and not known[spell] and ns.Trainers and ns.Trainers[spell] then
			local req = ns.Where.Required(spell)
			if req and req > from and req <= to then
				out[#out + 1] = ns.RecipeNames and ns.RecipeNames[spell] or ("Recipe " .. spell)
			end
		end
	end
	table.sort(out)
	return out
end

local told = {}       -- "line:skill" -> true, said this session
-- Called by Core when your skill in the open profession went up.
function Tips.SkillUp(line, from, skill, max)
	if not ns.Get("reminders") or not line then return end
	local key = line .. ":" .. skill
	if told[key] then return end
	told[key] = true
	local name = NAMES[line] or "Your profession"
	if max and max > 0 and skill >= max and max < 300 then
		local nextCap = max + 75
		local rank = ns.Plan and ns.Plan.RankName(nextCap) or "the next rank"
		ns.Print(("%s is at its cap (%d): train %s at a %s trainer."):format(name, max, rank, name))
		return
	end
	local new = NewAt(line, from, skill)
	if #new > 0 then
		local list = table.concat(new, ", ", 1, math.min(3, #new))
		if #new > 3 then list = list .. ("... (%d in all)"):format(#new) end
		ns.Print(("New %s recipe%s at a trainer: %s."):format(name, #new == 1 and "" or "s", list))
	end
end

-- ---------------------------------------------------------------------------------------------
-- The mark on "Craft next"'s pick in DaylightUI's recipe list
-- ---------------------------------------------------------------------------------------------

-- (Asked on every line the list fills: worked out only when the profession, skill or prices
-- changed, compared field by field so nothing is made per line.)
local best, bestLine, bestSkill, bestVersion
local function Best()
	local S = ns.state
	if not ns.Plan or not S.line then return nil end
	local skill, version = S.skill or 0, ns.Calc.version
	if bestLine ~= S.line or bestSkill ~= skill or bestVersion ~= version then
		local top = ns.Plan.CraftNext(1)[1]
		best, bestLine, bestSkill, bestVersion = top and top.spell or nil, S.line, skill, version
	end
	return best
end
Tips.Best = Best
Tips.Best = Best

local marks = setmetatable({}, { __mode = "k" })
local function Mark(frame, _, info)
	local holder = API.Attach and API.Attach(frame)
	if not holder then return end
	local m = marks[holder]
	if not m then
		m = holder:CreateTexture(nil, "OVERLAY")
		m:SetSize(4, 12)
		m:SetPoint("LEFT", holder, "LEFT", 1, 0)
		marks[holder] = m
	end
	local on = ns.Get("marks") and type(info) == "table" and info.recipeID and info.recipeID == Best()
	if on then m:SetColorTexture(API.Accent()) end
	m:SetShown(on and true or false)
end

-- ---------------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------------

me.On("Login", function()
	if type(me.AddTooltipLines) == "function" then pcall(me.AddTooltipLines, "item", ItemLines) end
	if type(me.Paint) == "function" then pcall(me.Paint, "craftrow", Mark) end
end)
