-- Camping: every profession's camping items (Forever's camp features), from Polestar's data
-- (Data/Polestar.lua, ns.Camping). Each is made at skill 20, 140 or 300 (Cooking's campfires
-- at 1, 90 and 200) and placed beside a campfire, where it gives everyone at the camp a buff for an
-- hour; all camping features share one cooldown. The first is taught by the profession's trainer
-- (or free from the quest "Camping 101"), the others by a blueprint.
-- ForeverRecipes' tables have the crafting professions' ones (they show in the recipe window and the
-- Missing tab); Herbalism, Skinning and Fishing have no recipe data at all, so their page in the
-- window (a gathering profession's) lists theirs here, and the "Camping" page every profession's.
local _, ns = ...
if not ns.ok then return end
local L = ns.L

local Doc, Where = ns.Doc, ns.Where
local ItemTip, ItemName = Doc.ItemTip, Doc.ItemName

local Camp = {}
ns.Camp = Camp

local GATHERING = { [182] = true, [393] = true, [356] = true }

-- The camping items of a skill line: { { spell, line, skill, item, teach } }, by skill. Made once.
local byLine
local function Items(line)
	if not byLine then
		byLine = {}
		local mine = ns.Faction()
		for _, c in ipairs(ns.Camping or {}) do
			-- (Tailoring's Faction Banner comes in one for each faction.)
			local meta = ns.RecipeMeta and ns.RecipeMeta[c[1]]
			local variant = meta and meta.variantFaction
			if not variant or variant == mine then
				local list = byLine[c[2]] or {}
				byLine[c[2]] = list
				list[#list + 1] = { spell = c[1], line = c[2], skill = c[3], item = c[4], teach = c[5] or nil }
			end
		end
	end
	return byLine[line] or {}
end
Camp.Items = Items

function Camp.Has(line) return #Items(line) > 0 end

-- What a camping item takes: { item, count, ... }. ForeverRecipes' recipe, else Polestar's guides
-- (tier one of the gathering professions'), else the game's own recipe (kept once read).
local schematics = {}
local function Reagents(spell)
	local data = ns.Recipes and ns.Recipes[spell]
	if data and type(data[3]) == "table" and #data[3] > 0 then return data[3] end
	if ns.CampReagents and ns.CampReagents[spell] then return ns.CampReagents[spell] end
	if schematics[spell] then return schematics[spell] end
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
	local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, spell, false)
	local slots = ok and type(sch) == "table" and sch.reagentSlotSchematics
	if type(slots) ~= "table" then return nil end
	local out = {}
	for _, slot in ipairs(slots) do
		local r = type(slot.reagents) == "table" and slot.reagents[1]
		if r and r.itemID and (slot.quantityRequired or 0) > 0 then
			out[#out + 1] = r.itemID
			out[#out + 1] = slot.quantityRequired
		end
	end
	if #out == 0 then return nil end
	schematics[spell] = out
	return out
end

-- What a camping item does, in the game's words (its "Use:" spell), or nil.
local function Effect(item)
	if not (C_Item and C_Item.GetItemSpell and C_Spell and C_Spell.GetSpellDescription) then return nil end
	local ok, _, spellID = pcall(C_Item.GetItemSpell, item)
	if not ok or not spellID then return nil end
	local got, text = pcall(C_Spell.GetSpellDescription, spellID)
	if got and type(text) == "string" and text ~= "" then return text end
	return nil
end

-- Your profession of a skill line: { name, skill, max, line, game, offset } or nil.
local function Mine(line)
	local W = ns.Window
	for _, p in ipairs(W and W.MyProfessions() or {}) do
		if p.game == line or p.line == line then return p end
	end
end

-- Whether the game opens a recipe window for this profession of yours (Forever's professions book
-- asks the same of each profession's spell before it offers one).
function Camp.CanOpen(p)
	if not (p and p.offset and C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank) then return false end
	if not (C_TradeSkillUI and C_TradeSkillUI.CanTradeSkillShowCraftingUI) then return false end
	local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, p.offset + 1, Enum.SpellBookSpellBank.Player)
	local spell = ok and type(info) == "table" and info.spellID
	if not spell then return false end
	local got, can = pcall(C_TradeSkillUI.CanTradeSkillShowCraftingUI, spell)
	return got and can == true
end

-- How to learn one: its trainer (tier one) or its blueprint, with where those are.
local function HowToLearn(d, c, p)
	local prof = ns.Tips and ns.Tips.LineName(c.line) or L["Profession"]
	if not c.teach then
		d:Line(L["Taught by a %s trainer from skill %d, or free from the quest \"Camping 101: %s\"."]:format(prof, c.skill, prof),
			"small", "TEXT", 12)
		local trainers = (ns.Trainers and ns.Trainers[c.spell]) or (ns.CampTrainers and ns.CampTrainers[c.line])
		local g = trainers and Where.NpcGroup("trainer", L["Trainer"], trainers, function(rec)
			return type(rec) == "table" and type(rec[2]) == "number" and ns.Calc.Money(rec[2]) or nil
		end)
		if g then ns.Pages.SourceGroups(d, { g }, 12) end
		return
	end
	local name, icon = ItemName(c.teach, d)
	d:Row({ indent = 12, icon = icon, left = name, right = L["Skill %d"]:format(c.skill),
		rightInk = (p and (p.skill or 0) >= c.skill) and "GOOD" or "OFF", tip = ItemTip(c.teach) })
	local groups = (ns.Recipes and ns.Recipes[c.spell]) and Where.Sources(c.spell) or Where.ItemSources(c.teach)
	if #groups == 0 then
		d:Line(L["Where this blueprint comes from isn't known yet."], "small", "OFF", 12)
	else
		ns.Pages.SourceGroups(d, groups, 12)
	end
end

-- How to make one you know.
local function HowToMake(d, c, p)
	local prof = ns.Tips and ns.Tips.LineName(c.line) or L["Profession"]
	if not p then return end
	if not GATHERING[c.line] then
		d:Line(L["Made in the %s recipe window, with its other recipes."]:format(prof), "small", "TEXT", 12)
		d:Buttons({ { text = L["Open %s"]:format(prof), onClick = function()
			if ns.Window then ns.Window.OpenProfession(p.line, p.game) end
		end } }, 12)
	elseif Camp.CanOpen(p) then
		d:Line(L["Made in the %s recipe window."]:format(prof), "small", "TEXT", 12)
		d:Buttons({ { text = L["Open %s"]:format(prof), onClick = function()
			pcall(C_TradeSkillUI.OpenTradeSkill, p.game)
		end } }, 12)
	else
		local spell = ns.SpellName(c.spell) or L["it"]
		d:Line(L["The game has no recipe window for %s: cast %s from your spellbook, with its materials in your bags."]:format(prof, spell),
			"small", "TEXT", 12)
	end
end

-- One camping item: a row (what it makes and does, known or the skill it needs); a click opens
-- what it takes, how to learn it and how to make it.
local function ItemRow(d, c, p, redraw)
	local st = d.state
	st.camp = st.camp or {}
	local c0 = ns.Store and ns.Store.Char()
	local saved = c0 and type(c0.known) == "table" and c0.known[c.line]
	local known = p and (Where.SpellKnown(c.spell) or (type(saved) == "table" and saved[c.spell] == true))
	local skill = p and p.skill or 0
	local name, icon = ItemName(c.item, d)
	local right, ink
	if known then
		right, ink = L["Known"], "GOOD"
	else
		right, ink = L["Skill %d"]:format(c.skill), (p and skill >= c.skill) and "GOOD" or "OFF"
	end
	d:Row({ icon = icon, left = name, leftInk = "VALUE", right = right, rightInk = ink,
		sub = Effect(c.item) or (c.teach and L["From a blueprint"] or L["From a trainer"]), subInk = "TEXT",
		tip = ItemTip(c.item), marked = st.camp[c.spell] == true,
		onClick = function()
			st.camp[c.spell] = not st.camp[c.spell] or nil
			redraw()
		end })
	if not st.camp[c.spell] then return end
	local mats = Reagents(c.spell)
	d:Line(L["Materials"], "small", "LABEL", 12)
	if mats then
		for i = 1, #mats, 2 do ns.Pages.MaterialRow(d, mats[i], mats[i + 1], 12) end
	else
		d:Line(L["The game shows what it takes once you know it."], "small", "OFF", 12)
	end
	if not known then
		d:Line(L["How to learn it"], "small", "LABEL", 12)
		HowToLearn(d, c, p)
	end
	if p then
		d:Line(L["How to make it"], "small", "LABEL", 12)
		if known then HowToMake(d, c, p) else d:Line(L["Learn it first."], "small", "OFF", 12) end
	end
	d:Gap(6)
end

local NOTE = L["Placed beside a campfire, a camping item gives everyone at the camp its buff for an hour. All camping features share one hour's cooldown."]

-- A profession's camping items, under a heading (a gathering profession's page).
function Camp.Section(d, line, redraw)
	local list = Items(line)
	if #list == 0 then return end
	d:Heading(L["Camping"])
	d:Line(NOTE, "small", "TEXT")
	d:Gap(2)
	local p = Mine(line)
	for _, c in ipairs(list) do ItemRow(d, c, p, redraw) end
end

-- Every profession's camping items: yours first, then the rest.
function Camp.Page(d, redraw)
	d:Line(NOTE, "small", "TEXT")
	local lines, seen = {}, {}
	for _, p in ipairs(ns.Window and ns.Window.MyProfessions() or {}) do
		local line = (#Items(p.game) > 0 and p.game) or p.line
		if #Items(line) > 0 and not seen[line] then
			seen[line] = true
			lines[#lines + 1] = line
		end
	end
	local others = {}
	for _, c in ipairs(ns.Camping or {}) do
		if not seen[c[2]] then
			seen[c[2]] = true
			others[#others + 1] = c[2]
		end
	end
	local function Name(line) return ns.Tips and ns.Tips.LineName(line) or tostring(line) end
	table.sort(others, function(a, b) return ns.NameLess(Name(a), Name(b)) end)
	for _, line in ipairs(lines) do
		local p = Mine(line)
		d:Heading(p and L["%s (skill %d)"]:format(Name(line), p.skill or 0) or Name(line))
		for _, c in ipairs(Items(line)) do ItemRow(d, c, p, redraw) end
	end
	if #others > 0 then
		d:Heading(L["Other professions"])
		for _, line in ipairs(others) do
			d:Line(Name(line), "small", "LABEL")
			for _, c in ipairs(Items(line)) do ItemRow(d, c, nil, redraw) end
		end
	end
end
