-- Help outside the pane:
--   * Item tooltips (DaylightUI 1.7 and later): which professions use a material and in how many
--     recipes, what your guides need of it (this character's only), and for a recipe
--     item who on your account already knows it. Read from tables made once, so a tooltip filling
--     several times a second costs a few lookups.
--   * Trainer reminders: a chat line when a skill-up lets you learn new recipes at a trainer, and
--     when a profession reaches its cap and needs the next rank.
--   * The recipe "Craft next" picks gets a small mark in DaylightUI's profession list.
--   * Mastercraft's own recipe item lines handed over while ours show (below).
local ADDON, ns = ...
if not ns.ok then return end
local L, Plural = ns.L, ns.Plural
local DUI = ns.DUI or _G.DaylightUI   -- (ns.DUI: Host.lua; the global only in the offline tests)

local API, me = ns.API, ns.me
local Tips = {}
ns.Tips = Tips

local NAMES = { [164] = L["Blacksmithing"], [165] = L["Leatherworking"], [171] = L["Alchemy"], [185] = L["Cooking"],
	[186] = L["Mining"], [197] = L["Tailoring"], [202] = L["Engineering"], [333] = L["Enchanting"], [129] = L["First Aid"],
	[40] = L["Poisons"], [182] = L["Herbalism"], [393] = L["Skinning"], [356] = L["Fishing"] }

-- A profession's name in the client's language: the name of its own spell (the one learning it
-- gives you; every rank shares the name), else the game's name for the skill line, else the English
-- one above. Kept once found: it never changes in a session.
local LINE_SPELL = { [164] = 2018, [165] = 2108, [171] = 2259, [185] = 2550, [186] = 2575, [197] = 3908,
	[202] = 4036, [333] = 7411, [129] = 3273, [40] = 2842, [182] = 2366, [393] = 8613, [356] = 7620 }
local lineNames = {}
local function Usable(name) return type(name) == "string" and name ~= "" and name or nil end
local function LineName(line)
	if not line then return nil end
	local name = lineNames[line]
	if name then return name end
	local spell = LINE_SPELL[line]
	if spell and C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, spell)
		name = ok and Usable(n) or nil
	end
	name = name or Usable(ns.Ask("GetTradeSkillDisplayName", line))
	if not name then
		local info = ns.Ask("GetProfessionInfoBySkillLineID", line)
		name = type(info) == "table" and Usable(info.professionName) or nil
	end
	if name then
		lineNames[line] = name
		return name
	end
	return NAMES[line]
end
function Tips.LineName(line) return LineName(line) or L["Profession"] end

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

-- The recipe (spell) a recipe item teaches, or nil.
function Tips.Teaches(itemID)
	Index()
	return teaches[itemID]
end

-- The professions this character has learned (skill line -> true), from the game, kept until its
-- skills change. The tooltip only speaks of these: a profession you don't have is no news to you.
-- (Poisons are a rogue's class skill, not in the professions list.)
local learned
local function Learned()
	if learned then return learned end
	learned = {}
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			local index = list[i]
			if index then
				local ok, _, _, _, _, _, _, line = pcall(GetProfessionInfo, index)
				if ok and type(line) == "number" then learned[line] = true end
			end
		end
	end
	local _, class = UnitClass("player")
	if class == "ROGUE" then learned[40] = true end
	return learned
end

local usedText = {}      -- itemID -> its "Used in" text (false: none), made once per set of professions
local function UsedText(itemID)
	local cached = usedText[itemID]
	if cached ~= nil then return cached or nil end
	local t = usedBy[itemID]
	if not t then
		usedText[itemID] = false
		return nil
	end
	local parts = {}
	local have = Learned()
	for line, n in pairs(t) do
		if have[line] then parts[#parts + 1] = { LineName(line) or "?", n } end
	end
	if #parts == 0 then
		usedText[itemID] = false
		return nil
	end
	table.sort(parts, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(3, #parts) do out[i] = L["%s %d"]:format(parts[i][1], parts[i][2]) end
	if #parts > 3 then out[#out + 1] = "..." end
	local text = table.concat(out, ", ")
	usedText[itemID] = text
	return text
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

-- Up to three names, then how many more: a tooltip line stays one short line.
local function Short(names)
	if #names <= 3 then return table.concat(names, ", ") end
	return table.concat(names, ", ", 1, 3) .. " " .. L["+%d more"]:format(#names - 3)
end

-- Text in DaylightUI's dim ink.
local function Dim(text)
	local c = API.Colors and API.Colors()
	local off = type(c) == "table" and c.OFF
	if type(off) ~= "table" then return text end
	return ("|cff%02x%02x%02x%s|r"):format(off[1] * 255, off[2] * 255, off[3] * 255, text)
end

local function ItemLines(lines, data)
	if not ns.Get("tooltips") then return end
	local itemID = type(data) == "table" and data.itemID
	if type(itemID) ~= "number" then return end
	Index()
	local spell = teaches[itemID]
	local recipe = spell and ns.Recipes and ns.Recipes[spell]
	-- A recipe item: who on the account knows it, and who of this realm and faction (the ones it can
	-- be mailed to) has its profession and could learn it, with the skill each still needs. Shown
	-- when this character or one of those has the profession.
	local learn = spell and recipe and ns.Learn and ns.Learn.For(itemID)
	if spell and recipe and (learn or Learned()[recipe[1]]) then
		local who = ns.Store.WhoKnows(spell, true)
		lines.Line(L["Known By"], #who > 0 and Short(who) or L["No one on your account"])
		local can = {}
		for _, e in ipairs(learn and learn.list or {}) do
			if not e.knows then
				local name = ns.Learn.ClassName(e)
				if e.short > 0 then name = name .. " " .. Dim(L["(needs %d)"]:format(learn.need)) end
				can[#can + 1] = name
			end
		end
		if #can > 0 then lines.Line(L["Can Learn"], Short(can)) end
	end
	local used = UsedText(itemID)
	if used then lines.Line(L["Used In"], used) end
	-- Guides: this character's own, for the professions it has learned (alts' guides aren't shown).
	-- Not for a profession whose guide line is handed to Professionally Lost (its own tooltip block
	-- says what its guide needs), or whose plan of ours is no longer kept up (ProfLost.lua), or was
	-- not kept up and has not been worked out since (plan.rested: ProfLost.RestPlan).
	local mine = ns.Store.Char()
	if type(mine) == "table" and type(mine.plans) == "table" then
		local have = Learned()
		local P = ns.ProfLost
		for line, plan in pairs(mine.plans) do
			local n = type(plan) == "table" and plan.need and plan.need[itemID]
			local theirs = P ~= nil and (P.Handed("tooltip", line) or P.PlanQuiet(line))
			if n and n > 0 and have[line] and not theirs and not plan.rested then
				lines.Line(L["Your %s Guide"]:format(LineName(line) or ""), L["%d (to %d)"]:format(n, plan.target or 0))
			end
		end
	end
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
				out[#out + 1] = ns.SpellName(spell) or L["Recipe %d"]:format(spell)
			end
		end
	end
	table.sort(out, ns.NameLess)
	return out
end

local told = {}       -- "line:skill" -> true, said this session
-- Called by Core when your skill in the open profession went up.
function Tips.SkillUp(line, from, skill, max)
	if not ns.Get("reminders") or not line then return end
	local key = line .. ":" .. skill
	if told[key] then return end
	told[key] = true
	local name = LineName(line) or L["Your profession"]
	if max and max > 0 and skill >= max and max < 300 then
		local nextCap = max + 75
		local rank = ns.Plan and ns.Plan.RankName(nextCap) or L["the next rank"]
		ns.Print(L["%s is at its cap (%d): train %s at a %s trainer."]:format(name, max, rank, name))
		return
	end
	local new = NewAt(line, from, skill)
	if #new > 0 then
		local list = table.concat(new, ", ", 1, math.min(3, #new))
		if #new > 3 then list = list .. L["... (%d in all)"]:format(#new) end
		ns.Print(Plural(#new, "New %s recipe at a trainer: %s.", "New %s recipes at a trainer: %s."):format(name, list))
	end
end

-- A profession unlearned: learned again, its reminders are said again from skill 1.
function Tips.ForgetLine(line)
	local prefix = tostring(line) .. ":"
	for key in pairs(told) do
		if key:sub(1, #prefix) == prefix then told[key] = nil end
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

-- Whether what a recipe makes would be a gear upgrade for this character, by Glowey's Gear when
-- it is installed (its GloweyGearAPI.Upgrade: a global of its own, nothing of it is read or
-- copied): true and its words ("+12% over your Chest"), or false. The recipe list's arrow.
-- Gear keeps its answer for an item, so asking for every row each repaint costs a lookup.
function Tips.GearUp(spell)
	if not ns.Get("marks") then return false end
	local api = rawget(_G, "GloweyGearAPI")
	if type(api) ~= "table" or type(api.Upgrade) ~= "function" then return false end
	local data = ns.Recipes and ns.Recipes[spell]
	local made = data and data[4]
	local id = type(made) == "table" and made[1]
	if type(id) ~= "number" then return false end
	local ok, up, text = pcall(api.Upgrade, "item:" .. id)
	if not ok or up ~= true then return false end
	return true, type(text) == "string" and text or nil
end

-- Gear's answers changed (gear put on, a level, item data arriving): fn runs. False without Gear.
function Tips.GearWatch(fn)
	local api = rawget(_G, "GloweyGearAPI")
	if type(api) ~= "table" or type(api.Watch) ~= "function" then return false end
	return (pcall(api.Watch, fn))
end

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
-- Mastercraft's recipe item lines
-- ---------------------------------------------------------------------------------------------
-- Mastercraft (its own addon, read only through its saved settings) lists, on a recipe item, each of
-- your characters with that profession and whether they know it or can learn it ("What a pattern
-- teaches": MastercraftDB.settings.tipTeaches). With our tooltips on, that's said twice, so by
-- default ours stand and Mastercraft's is switched off (setting "mastercraftTips"). What it was is
-- kept (DaylightRecipesDB.mastercraftTeachesWas) and put back when ours are off or this choice is.
-- Asked once, the first time both are on. Mastercraft reads its settings live, so this takes effect
-- at once.

local function MastercraftSettings()
	local db = _G.MastercraftDB
	return type(db) == "table" and type(db.settings) == "table" and db.settings or nil
end

function Tips.ApplyMastercraft()
	local ms = MastercraftSettings()
	if not ms then return end
	local db = ns.Store.DB()
	if ns.Get("tooltips") and ns.Get("mastercraftTips") ~= false then
		if db.mastercraftTeachesWas == nil then db.mastercraftTeachesWas = ms.tipTeaches ~= false end
		ms.tipTeaches = false
	elseif db.mastercraftTeachesWas ~= nil then
		ms.tipTeaches = db.mastercraftTeachesWas
		db.mastercraftTeachesWas = nil
	end
end

local function AskMastercraft()
	local ms = MastercraftSettings()
	local db = ns.Store.DB()
	if not ms or db.mastercraftTipsAsked or not ns.Get("tooltips") then return end
	-- (Only when it would have been said twice: Mastercraft's lines were on.)
	if ms.tipTeaches == false and db.mastercraftTeachesWas ~= true then return end
	db.mastercraftTipsAsked = true
	-- (A first launch: the welcome says it instead. Guide.lua)
	if ns.Guide and ns.Guide.Welcoming and ns.Guide.Welcoming() then return end
	StaticPopupDialogs.DAYLIGHTRECIPES_MASTERCRAFT_TIPS = {
		text = L["Mastercraft also lists your characters on recipe items. Show only Glowey's Recipes' lines?\n\nMastercraft's come back if you pick Keep Both, or later in Glowey's Recipes' options."],
		button1 = L["Only Recipes'"],
		button2 = L["Keep Both"],
		OnAccept = function() pcall(DUI.Set, DUI, ADDON, "mastercraftTips", true) end,
		OnCancel = function(_, _, reason)
			if reason == "clicked" then pcall(DUI.Set, DUI, ADDON, "mastercraftTips", false) end
		end,
		timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
	}
	StaticPopup_Show("DAYLIGHTRECIPES_MASTERCRAFT_TIPS")
end

-- ---------------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------------

-- A profession learned or dropped: the set and the texts made from it are read again.
local skills = CreateFrame("Frame")
skills:RegisterEvent("SKILL_LINES_CHANGED")
skills:SetScript("OnEvent", function()
	learned = nil
	wipe(usedText)
end)

me.On("Login", function()
	if type(me.AddTooltipLines) == "function" then pcall(me.AddTooltipLines, "item", ItemLines) end
	-- (With DaylightUI's tooltips off, or another addon drawing them: the same lines, written
	-- into the game's own tooltip. TipFallback.lua)
	if ns.TipFallback then ns.TipFallback(ItemLines) end
	if type(me.Paint) == "function" then pcall(me.Paint, "craftrow", Mark) end
	Tips.ApplyMastercraft()
	C_Timer.After(4, AskMastercraft)
end)
