-- Daylight Recipes' profession window: in place of the game's (and DaylightUI's) while it's the one
-- chosen (Take.lua holds the game's out of sight; it keeps running the trade skill).
--   Left:  your professions (click one to open it) and, below, your alts' on this realm.
--   Top:   the open profession, its skill bar, and four tabs:
--     Recipes:   the recipe list (search, "Can make", "Skill-ups", categories that fold) and the
--                picked recipe: what it makes and needs, its skill-up chance, costs, value, and the
--                Create / Create All buttons (or the item an enchant goes on).
--     Plan:      Auction House prices, the cheapest recipes for a point now, the route to a target.
--     Materials: what the route needs, what you and your alts hold, what's left to buy.
--     Missing:   the recipes you don't know yet, and where to get them.
--   An alt's profession shows what that character knows (from the last time they opened it).
-- Its pages are drawn on docs (Doc.lua) from Pages.lua; the recipe list is its own: a fixed set of
-- rows over the list, filled as it scrolls, so a profession of hundreds of recipes costs a screen.
local _, ns = ...
if not ns.ok then return end

local API = ns.API
local Doc, Pages, Calc, Craft = ns.Doc, ns.Pages, ns.Calc, ns.Craft
local S = ns.state
local Color, Hex, Text, DiffColor = Doc.Color, Doc.Hex, Doc.Text, Doc.DiffColor

local Window = {}
ns.Window = Window

local W, H = 1000, 640
local SIDE = 210          -- the professions on the left
local LIST = 330          -- the recipe list
local HEAD = 96           -- the profession's name, skill bar and tabs
local BAR = 52            -- Create / Create All under the recipe
local ROW = 20            -- a line of the recipe list
local PAD = 14

local win, side, content, body
local tabButtons = {}
local tab = "recipes"
local listFrame, listRows, listThumb, search, filterButtons
local detail, craftBar, pageDoc, pageSearch
local altDoc
local alt               -- { guid, line } while an alt's profession is shown

local function DB()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	db.win = type(db.win) == "table" and db.win or {}
	db.win.folded = type(db.win.folded) == "table" and db.win.folded or {}
	return db.win
end

local function TS(name, ...)
	return Craft.TS(name, ...)
end

function Window.Width() return W * (ns.Get("winScale") or 1) end
function Window.Shown() return win ~= nil and win:IsShown() end

-- ---------------------------------------------------------------------------------------------
-- Small pieces
-- ---------------------------------------------------------------------------------------------

local function Wash(parent, layer, a)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(1, 1, 1, a or 0.05)
	return t
end

-- A word you click to turn on and off (the list's filters): label ink, accent with a line when on.
local function Toggle(parent, label, key)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(20)
	b.text = Text(b, "small")
	b.text:SetPoint("CENTER", 0, 1)
	b.text:SetText(label)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetHeight(1)
	b.line:SetPoint("BOTTOMLEFT", 4, 0)
	b.line:SetPoint("BOTTOMRIGHT", -4, 0)
	b.key = key
	function b.Paint()
		local on = DB()[key] == true
		if on then
			b.text:SetTextColor(API.Accent())
			b.line:SetColorTexture(API.Accent())
			b.line:Show()
		else
			b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
			b.line:Hide()
		end
		b:SetWidth(math.ceil(b.text:GetStringWidth()) + 14)
	end
	b:SetScript("OnEnter", b.Paint)
	b:SetScript("OnLeave", b.Paint)
	b:SetScript("OnClick", function()
		DB()[key] = not DB()[key] or nil
		b.Paint()
		Window.Dirty()
	end)
	return b
end

-- ---------------------------------------------------------------------------------------------
-- The recipe list
-- ---------------------------------------------------------------------------------------------

local entries = {}       -- what the list shows: { cat = id, name } or { spell, name, step, count }
local listDirty = true
local offset = 0         -- the first entry shown
local filterText = ""
local catNames = {}

local function CategoryName(id)
	if not id then return "Other" end
	local name = catNames[id]
	if name then return name end
	local info = TS("GetCategoryInfo", id)
	name = type(info) == "table" and info.name or "Other"
	catNames[id] = name
	return name
end

local function AllRecipeIDs()
	local ids = TS("GetAllRecipeIDs")
	if type(ids) ~= "table" or #ids == 0 then ids = TS("GetFilteredRecipeIDs") end
	return type(ids) == "table" and ids or {}
end

-- The list worked out again: the open profession's learned recipes, searched and filtered, under
-- their categories (in the game's order), folded ones without their recipes.
local function BuildList()
	listDirty = false
	wipe(entries)
	if not S.mode or S.mode ~= "win" then return end
	local db = DB()
	local canOnly, upOnly = db.canMake == true, db.skillUps == true
	local byCat, order = {}, {}
	local first
	for _, id in ipairs(AllRecipeIDs()) do
		local info = TS("GetRecipeInfo", id)
		if type(info) == "table" and info.learned and not info.isDummyRecipe and info.name then
			local keep = filterText == "" or info.name:lower():find(filterText, 1, true) ~= nil
			local count = keep and Craft.Count(id) or 0
			local rd = type(info.relativeDifficulty) == "number" and info.relativeDifficulty or 3
			if keep and canOnly and count <= 0 then keep = false end
			if keep and upOnly and (rd >= 3 or info.canSkillUp == false) then keep = false end
			if keep then
				local cat = info.categoryID or 0
				local list = byCat[cat]
				if not list then
					list = {}
					byCat[cat] = list
					order[#order + 1] = cat
				end
				list[#list + 1] = { spell = id, name = info.name, step = rd + 1, count = count,
					ups = info.numSkillUps }
				first = first or id
			end
		end
	end
	local folded = db.folded
	for _, cat in ipairs(order) do
		local list = byCat[cat]
		local key = tostring(cat)
		-- (A search shows every match, folded or not.)
		local fold = folded[key] and filterText == ""
		entries[#entries + 1] = { cat = key, name = CategoryName(cat ~= 0 and cat or nil), fold = fold, n = #list }
		if not fold then
			for _, e in ipairs(list) do entries[#entries + 1] = e end
		end
	end
	-- Nothing picked yet (a profession just opened): its first recipe, as the game does.
	if not S.recipe and first then
		S.recipe = first
		Window.RecipeChanged()
	end
end

local function VisibleRows()
	local h = listFrame and listFrame:GetHeight() or 0
	return math.max(1, math.floor(h / ROW))
end

local function ClampOffset()
	local maxOff = math.max(0, #entries - VisibleRows())
	if offset > maxOff then offset = maxOff end
	if offset < 0 then offset = 0 end
end

local function PaintThumb()
	local n, shown = #entries, VisibleRows()
	if n <= shown then listThumb:Hide() return end
	local h = listFrame:GetHeight()
	local size = math.max(24, h * shown / n)
	listThumb:SetHeight(size)
	listThumb:ClearAllPoints()
	listThumb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -((h - size) * offset / (n - shown)))
	listThumb:SetColorTexture(API.Accent())
	listThumb:SetAlpha(0.5)
	listThumb:Show()
end

local function MakeListRow()
	local r = CreateFrame("Button", nil, listFrame)
	r:SetHeight(ROW)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.ground = r:CreateTexture(nil, "BACKGROUND")
	r.ground:SetAllPoints()
	r.ground:Hide()
	r.wash = Wash(r, "BORDER", 0.05)
	r.wash:SetAllPoints()
	r.wash:Hide()
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(3, 12)
	r.mark:SetPoint("LEFT", r, "LEFT", 2, 0)
	r.sign = Text(r, "body")
	r.sign:SetPoint("LEFT", r, "LEFT", 8, 0)
	r.sign:SetWidth(12)
	r.name = Text(r, "body")
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.right = Text(r, "small", "RIGHT")
	r.right:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r:SetScript("OnEnter", function(self)
		self.wash:Show()
		local e = self.entry
		if e and e.spell then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local ok = pcall(GameTooltip.SetRecipeResultItem, GameTooltip, e.spell)
			if not ok or GameTooltip:NumLines() == 0 then GameTooltip:SetSpellByID(e.spell) end
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	r:SetScript("OnClick", function(self)
		local e = self.entry
		if not e then return end
		if e.cat then
			local folded = DB().folded
			folded[e.cat] = not folded[e.cat] or nil
			Window.Dirty()
			return
		end
		if IsModifiedClick("CHATLINK") then
			local link = TS("GetRecipeLink", e.spell)
			if link then ChatEdit_InsertLink(link) end
			return
		end
		Window.Select(e.spell)
	end)
	return r
end

local function PaintList()
	if not listFrame then return end
	if listDirty then BuildList() end
	ClampOffset()
	local shown = VisibleRows()
	listRows = listRows or {}
	local best = ns.Tips and ns.Tips.Best and ns.Get("marks") and ns.Tips.Best() or nil
	local ar, ag, ab = API.Accent()
	for i = 1, shown + 1 do
		local r = listRows[i]
		if not r then
			r = MakeListRow()
			listRows[i] = r
		end
		local e = entries[offset + i]
		r.entry = e
		if not e or i > shown then
			r:Hide()
		else
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * ROW)
			r:SetPoint("RIGHT", listFrame, "RIGHT", -6, 0)
			r.name:ClearAllPoints()
			if e.cat then
				r.sign:SetText(e.fold and "+" or "-")
				r.sign:SetTextColor(Color("LABEL"))
				r.sign:Show()
				r.name:SetPoint("LEFT", r.sign, "RIGHT", 2, 0)
				r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
				r.name:SetText(e.name)
				r.name:SetTextColor(Color("LABEL"))
				r.right:SetText(e.fold and tostring(e.n) or "")
				r.right:SetTextColor(Color("OFF"))
				r.ground:SetColorTexture(1, 1, 1, 0.03)
				r.ground:Show()
				r.mark:Hide()
			else
				r.sign:Hide()
				r.name:SetPoint("LEFT", r, "LEFT", 22, 0)
				r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
				r.name:SetText(e.name)
				r.name:SetTextColor(DiffColor(math.min(4, math.max(1, e.step))))
				local right = e.count > 0 and ("[" .. e.count .. "]") or ""
				r.right:SetText(right)
				r.right:SetTextColor(Color("VALUE"))
				if e.spell == S.recipe then
					r.ground:SetColorTexture(ar, ag, ab, 0.16)
					r.ground:Show()
				else
					r.ground:Hide()
				end
				if e.spell == best then
					r.mark:SetColorTexture(ar, ag, ab, 1)
					r.mark:Show()
				else
					r.mark:Hide()
				end
			end
			r:Show()
		end
	end
	PaintThumb()
end

-- Scrolls the list so a recipe shows (after a pick from the Leveling Guide or the queue).
local function ShowInList(spell)
	if listDirty then BuildList() end
	for i, e in ipairs(entries) do
		if e.spell == spell then
			local shown = VisibleRows()
			if i <= offset or i > offset + shown then offset = i - math.floor(shown / 2) end
			ClampOffset()
			return
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The picked recipe and making it
-- ---------------------------------------------------------------------------------------------

local ENCH = 46            -- an enchant's item row, above the buttons
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local countBox

local function Linked() return S.linked == true end

local function Cooldown(spell)
	local cd = TS("GetRecipeCooldown", spell)
	if type(cd) ~= "number" or cd <= 0 then return nil end
	if cd >= 3600 then return ("Ready in %d h %d min"):format(math.floor(cd / 3600), math.floor(cd % 3600 / 60)) end
	return ("Ready in %d min"):format(math.max(1, math.floor(cd / 60)))
end

local function DetailPage(d)
	local spell = S.recipe
	if not spell then
		d:Line(#entries == 0 and "No recipe matches." or "Pick a recipe.", "body", "OFF")
		return
	end
	local info = TS("GetRecipeInfo", spell)
	local out = TS("GetRecipeOutputItemData", spell)
	local itemID = type(out) == "table" and out.itemID or nil
	local name = type(info) == "table" and info.name or Doc.RecipeName(spell)
	local icon = (type(out) == "table" and out.icon) or (type(info) == "table" and info.icon) or nil
	d:Row({ icon = icon, left = name, leftInk = "VALUE",
		tip = itemID and Doc.ItemTip(itemID) or Doc.SpellTip(spell),
		link = (type(out) == "table" and out.hyperlink) or TS("GetRecipeLink", spell) })
	local schematic = TS("GetRecipeSchematic", spell, false)
	if type(schematic) == "table" and schematic.quantityMax and schematic.quantityMax > 1 then
		local lo, hi = schematic.quantityMin or 1, schematic.quantityMax
		d:Line(("Makes %s at a time."):format(lo == hi and tostring(lo) or (lo .. "-" .. hi)), "small", "TEXT")
	end
	local reqs = TS("GetRecipeRequirements", spell)
	if type(reqs) == "table" and #reqs > 0 then
		local words = {}
		for _, r in ipairs(reqs) do
			if type(r) == "table" and r.name then
				local cr, cg, cb = Color(r.met and "GOOD" or "BAD")
				words[#words + 1] = Hex(cr, cg, cb) .. r.name .. "|r"
			end
		end
		if #words > 0 then d:Line("Needs " .. table.concat(words, ", "), "small", "TEXT") end
	end
	local cd = Cooldown(spell)
	if cd then d:Line(cd, "small", "WARN") end
	if type(info) == "table" and info.disabled and info.disabledReason then
		d:Line(info.disabledReason, "small", "BAD")
	end
	local chance = Pages.Skill(d, spell)
	Pages.Cost(d, spell, chance, { have = true })
	Pages.Worth(d, spell)
	local who = ns.Store and ns.Store.WhoKnows(spell)
	if type(who) == "table" and #who > 0 then
		d:Heading("Also known by")
		d:Line(table.concat(who, ", "), "small", "TEXT")
	end
end

local function PaintCraftBar()
	if not craftBar then return end
	local spell = S.recipe
	local making = Craft.Making()
	local cb = craftBar
	-- (A Stop that can't be put away in a fight stays drawn where it is, so what you see is what
	-- a click does.)
	local held = InCombatLockdown() and Craft.StopShown()
	if not held and (S.mode ~= "win" or Linked() or not spell or tab ~= "recipes" or alt) then
		cb:Hide()
		Craft.PlaceStop(nil)
		return
	end
	cb:Show()
	local info = TS("GetRecipeInfo", spell)
	local enchant = type(info) == "table" and info.isEnchantingRecipe == true
	local verb = type(info) == "table" and info.alternateVerb
	if type(verb) ~= "string" or verb == "" then verb = enchant and "Enchant" or "Create" end
	local can = Craft.Count(spell)
	local blocked = type(info) == "table" and info.disabled == true
	-- An enchant: its item row above the buttons (the item it goes on, Auto-replace).
	local ench = cb.ench
	if enchant then
		local t = Craft.EnchantTarget(spell)
		ench:Show()
		cb:SetHeight(BAR + ENCH)
		ench.icon:SetTexture(t and t.icon or EMPTY_SLOT)
		ench.icon:SetDesaturated(t == nil)
		ench.name:SetText(t and t.name or "Drag an item here")
		ench.name:SetTextColor(Color(t and "VALUE" or "LABEL"))
		ench.hint:SetText(t and "Every enchant here goes on it" or "or click to pick one from your bags")
		ench.hint:SetTextColor(Color("OFF"))
		ench.auto.SetOn(Craft.AutoReplace())
		ench.target = t
	else
		ench:Hide()
		ench.target = nil
		cb:SetHeight(BAR)
	end
	-- An enchant run between two enchants: Next (one enchant a click) and Done in place of the buttons.
	if making and making.paused then
		cb.stop:Hide()
		Craft.PlaceStop(nil)
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.status:SetText(("%d of %d done"):format(making.done, making.count))
		cb.status:ClearAllPoints()
		cb.status:SetPoint("RIGHT", cb.all, "LEFT", -12, 0)
		cb.status:SetTextColor(Color("LABEL"))
		cb.status:Show()
		cb.make.text:SetText(("Next (%d left)"):format(making.count - making.done))
		cb.make.SetOff(false)
		cb.make:Show()
		cb.all.text:SetText("Done")
		cb.all.SetOff(false)
		cb.all:Show()
		return
	end
	if making or held then
		if making then
			cb.status:SetText(("Making %d of %d"):format(math.min(making.done + 1, making.count), making.count))
		else
			cb.status:SetText("Stopped")
		end
		cb.status:SetTextColor(API.Accent())
		cb.status:Show()
		cb.status:ClearAllPoints()
		cb.status:SetPoint("RIGHT", cb.stop, "LEFT", -12, 0)
		cb.make:Hide()
		cb.all:Hide()
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.stop:Show()
		Craft.PlaceStop(cb.stop)
		return
	end
	cb.status:Hide()
	cb.stop:Hide()
	Craft.PlaceStop(nil)
	cb.make.text:SetText(verb)
	cb.make:Show()
	cb.queue:Show()
	countBox:Show()
	cb.minus:Show()
	cb.plus:Show()
	cb.all:Show()
	cb.all.text:SetText(verb .. " All" .. (can > 0 and (" " .. can) or ""))
	-- (An enchant with no item yet: the game would ask for a click on one, once; with one kept,
	-- as many as asked go on it.)
	local noItem = enchant and not ench.target
	cb.make.SetOff(blocked or can < 1)
	cb.all.SetOff(blocked or can < 1 or noItem)
end

local function CountWanted()
	local n = tonumber(countBox and countBox:GetText() or "") or 1
	return math.max(1, math.floor(n))
end

local function PickTarget(owner)
	local spell = S.recipe
	if not spell then return end
	local list = Craft.Targets(spell)
	if #list == 0 then
		ns.Print("Nothing you carry can take this enchant.")
		return
	end
	local keys, values, byKey = {}, {}, {}
	for i, t in ipairs(list) do
		local key = tostring(i)
		keys[#keys + 1] = key
		values[key] = t.name
		byKey[key] = t
	end
	API.Menu(owner, keys, values, nil, function(key)
		local t = byKey[key]
		if t then Craft.KeepTarget(t.guid) end
		PaintCraftBar()
	end, 240)
end

-- The enchant's item row: a slot the item goes in (dragged there, or picked from a menu of what
-- you carry that it can go on; right-click empties it), its name, and the Auto-replace switch
-- (the game's "replace the enchant?" answered yes during a run on this item).

local function BuildEnchantRow(cb)
	local row = CreateFrame("Frame", nil, cb)
	row:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
	row:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	row:SetHeight(ENCH)
	row:Hide()
	local slot = CreateFrame("Button", nil, row)
	slot:SetSize(34, 34)
	slot:SetPoint("LEFT", row, "LEFT", PAD, -2)
	API.Skin(slot, { noBevel = true })
	slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.icon = slot:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 3, -3)
	row.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local function Take()
		local spell = S.recipe
		if not spell then return end
		if not Craft.TakeFromCursor(spell) then ns.Print("That item can't take this enchant.") end
		PaintCraftBar()
	end
	slot:SetScript("OnReceiveDrag", Take)
	slot:SetScript("OnClick", function(self, button)
		if CursorHasItem() then
			Take()
		elseif button == "RightButton" then
			if S.recipe then Craft.DropTarget(S.recipe) end
			PaintCraftBar()
		else
			PickTarget(self)
		end
	end)
	slot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local t = row.target
		if t and t.link then
			GameTooltip:SetHyperlink(t.link)
			GameTooltip:AddLine(" ")
		else
			GameTooltip:SetText("The item to enchant")
		end
		GameTooltip:AddLine("Drag an item here, or click to pick one. Right-click empties it.", Color("LABEL"))
		GameTooltip:Show()
	end)
	slot:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.slot = slot
	row.name = Text(row, "body")
	row.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.name:SetWidth(200)
	row.hint = Text(row, "small")
	row.hint:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.hint:SetJustifyH("LEFT")
	row.hint:SetWidth(220)
	row.hint:SetWordWrap(false)

	row.auto = API.Switch(row)
	row.auto:SetPoint("RIGHT", row, "RIGHT", -PAD, -2)
	row.auto:SetScript("OnClick", function()
		Craft.SetAutoReplace(not Craft.AutoReplace())
		PaintCraftBar()
	end)
	row.auto:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Auto-replace")
		GameTooltip:AddLine("Answers the game's \"replace the enchant?\" with yes while a run of yours is putting enchants on this item, so it doesn't stop at every cast.", Color("TEXT"))
		GameTooltip:AddLine("Off: the game asks each time.", Color("LABEL"))
		GameTooltip:Show()
	end)
	row.auto:HookScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.autoLabel = Text(row, "small", "RIGHT")
	row.autoLabel:SetPoint("RIGHT", row.auto, "LEFT", -8, 0)
	row.autoLabel:SetText("Auto-replace")
	row.autoLabel:SetTextColor(Color("LABEL"))
	return row
end

local function BuildCraftBar(parent)
	local cb = CreateFrame("Frame", nil, parent)
	cb:SetHeight(BAR)
	local line = cb:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", 0, 0)
	line:SetColorTexture(1, 1, 1, 0.06)

	cb.make = API.Button(cb, "Create", 26)
	cb.make:SetWidth(96)
	-- (The buttons sit on the bar's bottom row: an enchant's item row goes above them.)
	cb.make:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	cb.make:SetScript("OnClick", function()
		local run = Craft.Making()
		if run and run.paused then
			Craft.Continue()
			return
		end
		local spell = S.recipe
		if not spell then return end
		-- (An enchant goes on its kept item, as many times as asked: Craft.Make finds it.)
		Craft.Make(spell, CountWanted())
	end)
	cb.all = API.Button(cb, "Create All", 26)
	cb.all:SetWidth(120)
	cb.all:SetPoint("RIGHT", cb.make, "LEFT", -8, 0)
	cb.all:SetScript("OnClick", function()
		local run = Craft.Making()
		if run and run.paused then
			Craft.Cancel()
			return
		end
		local spell = S.recipe
		local n = spell and Craft.Count(spell) or 0
		if n > 0 then Craft.Make(spell, n) end
	end)

	cb.plus = API.Button(cb, "+", 26)
	cb.plus:SetWidth(26)
	cb.plus:SetPoint("RIGHT", cb.all, "LEFT", -12, 0)
	countBox = API.Input(cb, { numeric = true })
	countBox:SetSize(46, 26)
	countBox:SetPoint("RIGHT", cb.plus, "LEFT", -4, 0)
	countBox:SetText("1")
	countBox:SetJustifyH("CENTER")
	cb.minus = API.Button(cb, "-", 26)
	cb.minus:SetWidth(26)
	cb.minus:SetPoint("RIGHT", countBox, "LEFT", -4, 0)
	local function Step(by)
		local n = math.max(1, CountWanted() + by)
		countBox:SetText(tostring(n))
	end
	cb.plus:SetScript("OnClick", function() Step(IsShiftKeyDown() and 10 or 1) end)
	cb.minus:SetScript("OnClick", function() Step(IsShiftKeyDown() and -10 or -1) end)

	cb.queue = API.Button(cb, "Queue", 26)
	cb.queue:SetWidth(76)
	cb.queue:SetPoint("RIGHT", cb.minus, "LEFT", -8, 0)
	cb.queue:SetScript("OnClick", function()
		local spell = S.recipe
		if not spell or not ns.Queue then return end
		ns.Queue.Add(spell, CountWanted())
	end)

	cb.ench = BuildEnchantRow(cb)

	cb.stop = API.Button(cb, "Stop", 26)
	cb.stop:SetWidth(110)
	cb.stop:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	-- (The secure Stop laid over it takes the click: Craft.PlaceStop.)
	cb.stop:EnableMouse(false)
	cb.stop:Hide()
	cb.status = Text(cb, "body", "RIGHT")
	cb.status:SetPoint("RIGHT", cb.stop, "LEFT", -12, 0)
	cb.status:Hide()
	return cb
end

-- ---------------------------------------------------------------------------------------------
-- The professions on the left
-- ---------------------------------------------------------------------------------------------

local sideRows = {}
local sideUsed = 0
local sideY = 0
local sideScroll = 0     -- how far the side list is scrolled
local sideTall = 0       -- how tall it is in all

local function SideRow()
	sideUsed = sideUsed + 1
	local r = sideRows[sideUsed]
	if not r then
		r = CreateFrame("Button", nil, side)
		r.ground = r:CreateTexture(nil, "BACKGROUND")
		r.ground:SetAllPoints()
		r.edge = r:CreateTexture(nil, "ARTWORK")
		r.edge:SetWidth(2)
		r.edge:SetPoint("TOPLEFT")
		r.edge:SetPoint("BOTTOMLEFT")
		r.wash = Wash(r, "BORDER", 0.05)
		r.wash:SetAllPoints()
		r.wash:Hide()
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(24, 24)
		r.icon:SetPoint("LEFT", r, "LEFT", 12, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = Text(r, "body")
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		r.sub = Text(r, "small")
		r.sub:SetJustifyH("LEFT")
		r.sub:SetWordWrap(false)
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetHeight(2)
		r.barBack = r:CreateTexture(nil, "BORDER")
		r.barBack:SetHeight(2)
		r:SetScript("OnEnter", function(self)
			if self.onClick then self.wash:Show() end
			if self.tip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				pcall(self.tip, GameTooltip)
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function(self)
			self.wash:Hide()
			if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
		end)
		r:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
		sideRows[sideUsed] = r
	end
	r:ClearAllPoints()
	r:Show()
	return r
end

local function SideHeading(text)
	sideY = sideY + 10
	local r = SideRow()
	r:SetHeight(18)
	r:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -sideY)
	r:SetPoint("RIGHT", side, "RIGHT", 0, 0)
	r.icon:Hide()
	r.bar:Hide()
	r.barBack:Hide()
	r.sub:Hide()
	r.ground:Hide()
	r.edge:Hide()
	r.onClick, r.tip = nil, nil
	r.name:ClearAllPoints()
	r.name:SetPoint("LEFT", r, "LEFT", 14, 0)
	r.name:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r.name:SetText(text)
	r.name:SetTextColor(Color("LABEL"))
	sideY = sideY + 20
end

-- o: icon, name, nameColor {r,g,b}, sub, value (0-1 for the bar), picked, onClick, tip
local function SideEntry(o)
	local r = SideRow()
	local h = 42
	r:SetHeight(h)
	r:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -sideY)
	r:SetPoint("RIGHT", side, "RIGHT", 0, 0)
	r.onClick, r.tip = o.onClick, o.tip
	local x = 12
	if o.icon then
		r.icon:SetTexture(o.icon)
		r.icon:Show()
		x = 44
	else
		r.icon:Hide()
	end
	r.name:ClearAllPoints()
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", x, -7)
	r.name:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r.name:SetText(o.name)
	if o.nameColor then r.name:SetTextColor(o.nameColor[1], o.nameColor[2], o.nameColor[3])
	else r.name:SetTextColor(Color(o.off and "OFF" or "VALUE")) end
	r.sub:ClearAllPoints()
	r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	r.sub:SetText(o.sub or "")
	r.sub:SetTextColor(Color("LABEL"))
	r.sub:Show()
	local ar, ag, ab = API.Accent()
	if o.value then
		r.barBack:ClearAllPoints()
		r.barBack:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 5)
		r.barBack:SetPoint("RIGHT", r, "RIGHT", -12, 0)
		r.barBack:SetColorTexture(1, 1, 1, 0.08)
		r.barBack:Show()
		local full = (r:GetWidth() > 0 and r:GetWidth() or SIDE) - x - 12
		r.bar:ClearAllPoints()
		r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 5)
		r.bar:SetWidth(math.max(1, full * math.min(1, o.value)))
		r.bar:SetColorTexture(ar, ag, ab, 0.8)
		r.bar:Show()
	else
		r.bar:Hide()
		r.barBack:Hide()
	end
	if o.picked then
		r.ground:SetColorTexture(ar, ag, ab, 0.12)
		r.ground:Show()
		r.edge:SetColorTexture(ar, ag, ab, 1)
		r.edge:Show()
	else
		r.ground:Hide()
		r.edge:Hide()
	end
	sideY = sideY + h + 2
end

-- Your professions now: { name, icon, skill, max, line }, those with recipes first.
local function MyProfessions()
	local out = {}
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
	local list = { GetProfessions() }
	for i = 1, 6 do
		local index = list[i]
		if index then
			local ok, name, icon, skill, max, _, _, line = pcall(GetProfessionInfo, index)
			if ok and name then
				out[#out + 1] = { name = name, icon = icon, skill = skill or 0, max = max or 0, line = line,
					crafts = line ~= nil and ns.LINES[line] == true }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.crafts ~= b.crafts then return a.crafts end
		return a.name < b.name
	end)
	return out
end
Window.MyProfessions = MyProfessions

local function PaintSide()
	if not side then return end
	for i = 1, #sideRows do sideRows[i]:Hide() end
	sideUsed, sideY = 0, 8 - sideScroll
	SideHeading("Professions")
	local mine = MyProfessions()
	if #mine == 0 then
		SideHeading("You have no profession yet.")
	end
	for _, p in ipairs(mine) do
		local picked = not alt and S.mode == "win" and not Linked() and p.line == S.line
		SideEntry({ icon = p.icon, name = p.name, off = not p.crafts,
			sub = p.max > 0 and ("%d / %d"):format(p.skill, p.max) or "",
			value = p.max > 0 and p.skill / p.max or nil, picked = picked,
			onClick = p.crafts and function() Window.OpenProfession(p.line) end or nil })
	end
	-- Your alts' professions on this realm, from the last time each opened them.
	local alts = {}
	for guid, c in pairs(ns.Store and ns.Store.Alts() or {}) do
		if type(c.prof) == "table" then
			for line, p in pairs(c.prof) do
				if type(p) == "table" and ns.LINES[line] then
					alts[#alts + 1] = { guid = guid, c = c, line = line, skill = p.skill or 0, max = p.max or 0 }
				end
			end
		end
	end
	if #alts > 0 then
		table.sort(alts, function(a, b)
			if (a.c.name or "") ~= (b.c.name or "") then return (a.c.name or "") < (b.c.name or "") end
			return a.line < b.line
		end)
		SideHeading("Your alts")
		for _, a in ipairs(alts) do
			local color
			if a.c.class and API.ClassColor then
				local ok, r, g, b = pcall(API.ClassColor, a.c.class)
				if ok and r then color = { r, g, b } end
			end
			SideEntry({ name = a.c.name or "?", nameColor = color,
				sub = ("%s %d"):format(ns.Tips and ns.Tips.LineName(a.line) or "", a.skill),
				value = a.max > 0 and a.skill / a.max or nil,
				picked = alt and alt.guid == a.guid and alt.line == a.line,
				onClick = function() Window.ShowAlt(a.guid, a.line) end })
		end
	end
	sideTall = sideY + sideScroll
	-- (Fewer rows than before, scrolled past the end: back to the end.)
	local most = math.max(0, sideTall - side:GetHeight() + 8)
	if sideScroll > most then
		sideScroll = most
		PaintSide()
	end
end

-- ---------------------------------------------------------------------------------------------
-- An alt's profession
-- ---------------------------------------------------------------------------------------------

local altFilter = ""

local function AltPage(d)
	local c = ns.Store and ns.Store.Alts()[alt.guid]
	if type(c) ~= "table" then
		d:Line("That character isn't on this realm and faction.", "small", "OFF")
		return
	end
	local p = type(c.prof) == "table" and c.prof[alt.line] or {}
	local known = type(c.known) == "table" and c.known[alt.line] or nil
	if type(known) ~= "table" then
		d:Line(("Open this profession on %s once to see what they know."):format(c.name or "them"), "small", "OFF")
		return
	end
	local skill = p.skill or 0
	local list = {}
	for spell in pairs(known) do
		local name = (ns.RecipeNames and ns.RecipeNames[spell]) or Doc.RecipeName(spell)
		if altFilter == "" or name:lower():find(altFilter, 1, true) then
			list[#list + 1] = { spell = spell, name = name }
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	d:Line(("%d recipe%s known"):format(#list, #list == 1 and "" or "s"), "small", "LABEL")
	d:Gap(2)
	for _, e in ipairs(list) do
		local t = Calc.Thresholds(e.spell)
		local step = 4
		if t then for i = 1, 3 do if skill < t[i + 1] then step = i break end end end
		local row = d:Row({ left = e.name, tip = Doc.SpellTip(e.spell) })
		row.left:SetTextColor(DiffColor(step))
	end
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

local headIcon, headName, headBar, headSkill, headNote

local TABS = { { "recipes", "Recipes" }, { "guide", "Leveling Guide" }, { "materials", "Materials" },
	{ "queue", "Queue" }, { "missing", "Missing" } }

local function PaintTabs()
	for _, b in ipairs(tabButtons) do
		b:SetShown(not alt)
		local on = b.key == tab
		if on then
			b.text:SetTextColor(Color("VALUE"))
			b.line:SetColorTexture(API.Accent())
			b.line:Show()
		else
			b.text:SetTextColor(Color(b:IsMouseOver() and "VALUE" or "LABEL"))
			b.line:Hide()
		end
		b:SetWidth(math.ceil(b.text:GetStringWidth()) + 20)
	end
end

local function SavePlace()
	local point, _, rel, x, y = win:GetPoint(1)
	DB().point = { point, rel, x, y }
end

local function Place()
	win:ClearAllPoints()
	local p = DB().point
	if type(p) == "table" and p[1] then
		win:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
end

local searchSerial = 0
local function Debounce(fn)
	searchSerial = searchSerial + 1
	local serial = searchSerial
	C_Timer.After(0.15, function()
		if serial == searchSerial then fn() end
	end)
end

local function Build()
	win = CreateFrame("Frame", "DaylightRecipesWindow", UIParent)
	win:SetSize(W, H)
	win:SetFrameStrata("MEDIUM")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function(self) self:StartMoving() end)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePlace()
		PaintCraftBar()
	end)
	win:Hide()
	win:SetScale(ns.Get("winScale") or 1)
	API.Skin(win, { window = true })
	Place()
	-- Esc closes it like any window (and ends the trade skill with it).
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightRecipesWindow") end
	win:SetScript("OnHide", function()
		Craft.PlaceStop(nil)
		if ns.Take and ns.Take.OursNow() then ns.Take.Close() end
	end)
	win:SetScript("OnShow", function() ns.Changed() end)

	local close = API.Close(win, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -10)

	-- Left: the professions.
	side = CreateFrame("Frame", nil, win)
	side:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE)
	side:SetClipsChildren(true)
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, sideTall - self:GetHeight() + 8)
		local to = math.max(0, math.min(most, sideScroll - delta * 44))
		if to ~= sideScroll then
			sideScroll = to
			PaintSide()
		end
	end)
	local ground = side:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0, 0, 0, 0.18)
	local divide = side:CreateTexture(nil, "ARTWORK")
	divide:SetWidth(1)
	divide:SetPoint("TOPRIGHT")
	divide:SetPoint("BOTTOMRIGHT")
	divide:SetColorTexture(1, 1, 1, 0.06)

	content = CreateFrame("Frame", nil, win)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

	-- The profession's head: icon, name, skill bar.
	headIcon = content:CreateTexture(nil, "ARTWORK")
	headIcon:SetSize(34, 34)
	headIcon:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, -14)
	headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	headName = Text(content, "title")
	headName:SetPoint("TOPLEFT", headIcon, "TOPRIGHT", 12, 0)
	headBar = API.Bar(content)
	headBar:SetSize(240, 8)
	headBar:SetPoint("BOTTOMLEFT", headIcon, "BOTTOMRIGHT", 12, 2)
	headSkill = Text(content, "small")
	headSkill:SetPoint("LEFT", headBar, "RIGHT", 10, 0)
	headNote = Text(content, "small", "RIGHT")
	headNote:SetPoint("TOPRIGHT", content, "TOPRIGHT", -48, -20)

	for i, spec in ipairs(TABS) do
		local b = CreateFrame("Button", nil, content)
		b.key = spec[1]
		b:SetHeight(26)
		b.text = Text(b, "body")
		b.text:SetPoint("CENTER", 0, 1)
		b.text:SetText(spec[2])
		b.line = b:CreateTexture(nil, "ARTWORK")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 6, 0)
		b.line:SetPoint("BOTTOMRIGHT", -6, 0)
		b:SetScript("OnClick", function() Window.SetTab(b.key) end)
		b:SetScript("OnEnter", PaintTabs)
		b:SetScript("OnLeave", PaintTabs)
		if i == 1 then
			b:SetPoint("TOPLEFT", content, "TOPLEFT", PAD - 6, -(HEAD - 30))
		else
			b:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 4, 0)
		end
		tabButtons[i] = b
	end
	local under = content:CreateTexture(nil, "ARTWORK")
	under:SetHeight(1)
	under:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -HEAD)
	under:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -HEAD)
	under:SetColorTexture(1, 1, 1, 0.06)

	body = CreateFrame("Frame", nil, content)
	body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -HEAD - 1)
	body:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

	-- Recipes: search, filters, list on the left; the recipe on the right; making it under it.
	search = API.Input(body, { search = true, hint = "Search recipes",
		onChange = function(text)
			text = (text or ""):lower()
			if text == filterText then return end
			filterText = text
			Debounce(function()
				offset = 0
				Window.Dirty()
			end)
		end })
	search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	search:SetWidth(LIST - PAD * 2)
	filterButtons = { Toggle(body, "Can make", "canMake"), Toggle(body, "Skill-ups", "skillUps") }
	filterButtons[1]:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -6)
	filterButtons[2]:SetPoint("LEFT", filterButtons[1], "RIGHT", 4, 0)

	listFrame = CreateFrame("Frame", nil, body)
	listFrame:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -70)
	listFrame:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 8)
	listFrame:SetWidth(LIST - 12)
	listFrame:EnableMouseWheel(true)
	listFrame:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		PaintList()
	end)
	listFrame:SetScript("OnSizeChanged", function() PaintList() end)
	listThumb = listFrame:CreateTexture(nil, "OVERLAY")
	listThumb:SetWidth(3)
	listThumb:Hide()

	local listEdge = body:CreateTexture(nil, "ARTWORK")
	listEdge:SetWidth(1)
	listEdge:SetPoint("TOPLEFT", body, "TOPLEFT", LIST, 0)
	listEdge:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", LIST, 0)
	listEdge:SetColorTexture(1, 1, 1, 0.06)
	body.listEdge = listEdge

	craftBar = BuildCraftBar(body)
	craftBar:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", LIST + 1, 0)
	craftBar:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	detail = Doc.New(body, { pad = 18 })
	detail.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", LIST + 1, -4)
	detail.scroll:SetPoint("BOTTOMRIGHT", craftBar, "TOPRIGHT", 0, 0)

	-- The other tabs: one page across, the missing list with its search above it.
	pageSearch = API.Input(body, { search = true, hint = "Search missing recipes",
		onChange = function(text)
			text = (text or ""):lower()
			if text == (pageSearch.filter or "") then return end
			pageSearch.filter = text
			Debounce(function()
				if pageDoc then pageDoc:Top() end
				Window.Render()
			end)
		end })
	pageSearch:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	pageSearch:SetWidth(320)
	pageDoc = Doc.New(body, { pad = 24 })

	altDoc = Doc.New(body, { pad = 24 })
	altDoc.search = API.Input(body, { search = true, hint = "Search their recipes",
		onChange = function(text)
			text = (text or ""):lower()
			if text == altFilter then return end
			altFilter = text
			Debounce(function() Window.Render() end)
		end })
	altDoc.search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	altDoc.search:SetWidth(320)
	altDoc.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -46)
	altDoc.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

local pageCtx = {
	make = true,
	redraw = function() Window.Render() end,
	pick = function(spell)
		Window.SetTab("recipes")
		Window.Select(spell)
	end,
}

local function PaintHead()
	if alt then
		local c = ns.Store and ns.Store.Alts()[alt.guid]
		local p = c and type(c.prof) == "table" and c.prof[alt.line] or {}
		headIcon:Hide()
		headName:SetText(((c and c.name) or "?") .. "'s " .. (ns.Tips and ns.Tips.LineName(alt.line) or ""))
		headName:SetTextColor(Color("VALUE"))
		headBar:SetMinMaxValues(0, math.max(1, p.max or 1))
		headBar:SetValue(p.skill or 0)
		headBar:Show()
		headSkill:SetText(("%d / %d"):format(p.skill or 0, p.max or 0))
		headSkill:SetTextColor(Color("LABEL"))
		headNote:SetText("As of their last visit")
		headNote:SetTextColor(Color("OFF"))
		return
	end
	local open = S.mode == "win"
	local icon = open and S.line and TS("GetTradeSkillTexture", S.line) or nil
	if not icon and open then
		for _, p in ipairs(MyProfessions()) do if p.line == S.line then icon = p.icon end end
	end
	headIcon:SetTexture(icon)
	headIcon:SetShown(icon ~= nil)
	headName:SetText(open and (S.name or "Profession") or "Daylight Recipes")
	headName:SetTextColor(Color("VALUE"))
	if open and (S.max or 0) > 0 then
		headBar:SetMinMaxValues(0, S.max)
		headBar:SetValue(S.skill or 0)
		headBar:Show()
		headSkill:SetText(("%d / %d"):format(S.skill or 0, S.max))
		headSkill:SetTextColor(Color("LABEL"))
	else
		headBar:Hide()
		headSkill:SetText(open and "" or "Pick a profession on the left.")
		headSkill:SetTextColor(Color("OFF"))
	end
	if open and Linked() then
		local _, who = TS("IsTradeSkillLinked")
		headNote:SetText(type(who) == "string" and (who .. "'s recipes") or "Someone else's recipes")
		headNote:SetTextColor(Color("WARN"))
	else
		headNote:SetText("")
	end
end

local function Draw(d, fn, ...)
	d:Begin()
	local ok, err = pcall(fn, d, ...)
	if not ok then
		geterrorhandler()(err)
		d:Line("Something went wrong drawing this page.", "small", "BAD")
	end
	d:Finish()
end

local function NoSession(d)
	d:Line("Open a profession from the list on the left (or cast it from your spellbook).", "body", "OFF")
end

function Window.Render()
	if not Window.Shown() then return end
	PaintHead()
	PaintSide()
	PaintTabs()
	local recipes = not alt and tab == "recipes"
	local open = S.mode == "win"
	search:SetShown(recipes)
	for _, b in ipairs(filterButtons) do
		b:SetShown(recipes)
		b.Paint()
	end
	listFrame:SetShown(recipes)
	body.listEdge:SetShown(recipes)
	detail.scroll:SetShown(recipes)
	pageSearch:SetShown(not alt and tab == "missing")
	pageDoc.scroll:SetShown(not alt and not recipes)
	altDoc.scroll:SetShown(alt ~= nil)
	altDoc.search:SetShown(alt ~= nil)
	if alt then
		Draw(altDoc, AltPage)
		PaintCraftBar()
		return
	end
	if recipes then
		PaintList()
		Draw(detail, open and DetailPage or NoSession)
		PaintCraftBar()
		return
	end
	PaintCraftBar()
	local scroll = pageDoc.scroll
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, tab == "missing" and -46 or -4)
	scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
	if not open then
		Draw(pageDoc, NoSession)
	elseif tab == "guide" then
		Draw(pageDoc, Pages.Guide, pageCtx)
	elseif tab == "queue" then
		Draw(pageDoc, Pages.Queue, pageCtx)
	elseif tab == "materials" then
		Draw(pageDoc, Pages.Materials)
	else
		pageCtx.filter = pageSearch.filter or ""
		Draw(pageDoc, Pages.Missing, pageCtx)
	end
end

-- ---------------------------------------------------------------------------------------------
-- What the rest of the plugin calls
-- ---------------------------------------------------------------------------------------------

function Window.Dirty()
	listDirty = true
	ns.Changed()
end

function Window.SetTab(key)
	if tab == key and not alt then return end
	tab = key
	alt = nil
	if pageDoc then pageDoc:Top() end
	Window.Render()
end

function Window.Select(spell)
	if type(spell) ~= "number" then return end
	if S.recipe ~= spell then
		S.recipe = spell
		Window.RecipeChanged()
	end
	ShowInList(spell)
	ns.Changed()
end

-- Another recipe picked: the enchant target was for the last one.
function Window.RecipeChanged()
	if detail then detail:Top() end
end

-- What the page now drawn is waiting on (an item's data).
function Window.Waiting(itemID)
	if not Window.Shown() then return false end
	return (detail and detail:Waiting(itemID)) or (pageDoc and pageDoc:Waiting(itemID)) or false
end

-- Whether a page showing prices, your materials or the plan is up.
function Window.ShowingPlan()
	return Window.Shown() and not alt and tab ~= "missing"
end

function Window.ShowingMissing()
	return Window.Shown() and not alt and tab == "missing"
end

function Window.CraftChanged(afterFight)
	if not Window.Shown() then
		Craft.PlaceStop(nil)
		return
	end
	PaintCraftBar()
	-- (A finished craft changes the counts in the list.)
	if not afterFight and not Craft.Making() then Window.Dirty() end
end

local closing = 0       -- counts closings: one put off a frame is dropped if a session started

-- A trade skill opened that belongs in our window (Take.lua).
function Window.SessionStarted()
	if not win then Build() end
	closing = closing + 1
	alt = nil
	S.mode = "win"
	if ns.Where then ns.Where.ForgetKnown() end
	ns.ReadProfession()
	-- (The one /recipes opens next time, away from a crafting station.)
	if S.line and not Linked() then DaylightRecipesDB.lastLine = S.line end
	listDirty = true
	offset = 0
	if not win:IsShown() then
		win:SetAlpha(0)
		win:Show()
		API.Fade(win, 1, "FAST")
	end
	ns.Changed()
end

-- The trade skill closed (or moved to the game's window): our window closes with it.
-- (A frame later: another profession picked on the left closes the trade skill and opens the next
-- one at once, and the window stays up through it.)
function Window.SessionEnded()
	if S.mode == "win" then S.mode = nil end
	if not (win and win:IsShown()) then return end
	closing = closing + 1
	local serial = closing
	C_Timer.After(0, function()
		if serial ~= closing or S.mode == "win" then return end
		if win:IsShown() then win:Hide() end
	end)
end

-- The list's counts follow your bags (the game updates the trade skill on every bag change), and
-- a recipe learned joins it.
local listEvents = CreateFrame("Frame")
listEvents:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
listEvents:RegisterEvent("NEW_RECIPE_LEARNED")
listEvents:SetScript("OnEvent", function()
	if S.mode == "win" and Window.Shown() then Window.Dirty() end
end)

-- Opens one of your professions (a click: the game asks for one to open a trade skill).
function Window.OpenProfession(line)
	if not line then return end
	if S.mode == "win" and S.line == line and not Linked() then
		if alt then
			alt = nil
			Window.Render()
		end
		return
	end
	alt = nil
	local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, line)
	if not ok or opened == false then ns.Print("The game didn't open that profession.") end
end

function Window.ShowAlt(guid, line)
	alt = { guid = guid, line = line }
	if altDoc then altDoc:Top() end
	Window.Render()
end

-- /recipes: the window, on the profession open now, or the one you had open last.
function Window.Toggle()
	if Window.Shown() then
		win:Hide()
		return
	end
	if ns.Take and ns.Take.OursNow() then
		if not win then Build() end
		win:Show()
		return
	end
	local last = DaylightRecipesDB and DaylightRecipesDB.lastLine
	if not last then
		for _, p in ipairs(MyProfessions()) do
			if p.crafts then last = p.line break end
		end
	end
	if last then
		local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, last)
		if ok and opened ~= false then return end
	end
	-- No profession to open: the window shows your professions and alts anyway.
	if not win then Build() end
	win:Show()
end

function Window.Restyle()
	if win then API.Skin(win, { window = true }) end
	if Window.Shown() then Window.Render() end
end

function Window.Rescale()
	if not win then return end
	local old, new = win:GetScale(), ns.Get("winScale") or 1
	local left, top = win:GetLeft(), win:GetTop()
	win:SetScale(new)
	if left and top then
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / new, top * old / new)
		SavePlace()
	end
	if ns.Take then ns.Take.Rewidth() end
	PaintCraftBar()
end
