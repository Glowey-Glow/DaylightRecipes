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
local L, Plural = ns.L, ns.Plural
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
local gather            -- the game's skill line of a gathering profession of yours while its page is shown
                        -- (CAMP: the camping page, every profession's camping items)
local CAMP = "camp"

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

-- The window's scale: the "Window size" setting, made smaller when the window wouldn't fit on the
-- screen at it (a large setting with a large UI scale), so no part of it is ever off screen.
local function Scale()
	local s = ns.Get("winScale") or 1
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	if sw and sw > 0 and sh and sh > 0 then s = math.min(s, sw / W, sh / H) end
	return s
end

function Window.Width() return W * Scale() end
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
	if not id then return L["Other"] end
	local name = catNames[id]
	if name then return name end
	local info = TS("GetCategoryInfo", id)
	name = type(info) == "table" and info.name or L["Other"]
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
			local keep = filterText == "" or ns.Fold(info.name):find(filterText, 1, true) ~= nil
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
	if cd >= 3600 then return L["Ready in %d h %d min"]:format(math.floor(cd / 3600), math.floor(cd % 3600 / 60)) end
	return L["Ready in %d min"]:format(math.max(1, math.floor(cd / 60)))
end

local function DetailPage(d)
	local spell = S.recipe
	if not spell then
		d:Line(#entries == 0 and L["No recipe matches."] or L["Pick a recipe."], "body", "OFF")
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
		d:Line(L["Makes %s at a time."]:format(lo == hi and tostring(lo) or (lo .. "-" .. hi)), "small", "TEXT")
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
		if #words > 0 then d:Line(L["Needs %s"]:format(table.concat(words, ", ")), "small", "TEXT") end
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
		d:Heading(L["Also known by"])
		d:Line(table.concat(who, ", "), "small", "TEXT")
	end
end

-- The bar's buttons fitted to their words (longer in some languages), never narrower than their
-- usual widths. When Queue, the count and Create All don't fit in one row beside Create, the count
-- and Queue go on a row of their own above (true: two rows).
local LEAST = { make = 96, all = 120, queue = 76, stop = 110 }
local LIFT = 32           -- how far above the bottom row the second row sits
local function FitButtons(cb)
	for key, least in pairs(LEAST) do cb[key].FitWidth(least) end
	local w = cb:GetWidth()
	if not w or w <= 0 then w = W - SIDE - LIST - 1 end
	local need = PAD + cb.make:GetWidth() + 8 + cb.all:GetWidth() + 12 + cb.plus:GetWidth() + 4
		+ countBox:GetWidth() + 4 + cb.minus:GetWidth() + 8 + cb.queue:GetWidth() + PAD
	local two = need > w
	cb.plus:ClearAllPoints()
	if two then
		cb.plus:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2 + LIFT)
	else
		cb.plus:SetPoint("RIGHT", cb.all, "LEFT", -12, 0)
	end
	return two
end

local function PaintCraftBar()
	if not craftBar then return end
	local spell = S.recipe
	local making = Craft.Making()
	local cb = craftBar
	-- (A Stop that can't be put away in a fight stays drawn where it is, so what you see is what
	-- a click does.)
	local held = InCombatLockdown() and Craft.StopShown()
	if not held and (S.mode ~= "win" or Linked() or not spell or tab ~= "recipes" or alt or gather) then
		cb:Hide()
		Craft.PlaceStop(nil)
		return
	end
	cb:Show()
	local info = TS("GetRecipeInfo", spell)
	local enchant = type(info) == "table" and info.isEnchantingRecipe == true
	local verb = type(info) == "table" and info.alternateVerb
	if type(verb) ~= "string" or verb == "" then verb = enchant and L["Enchant"] or L["Create"] end
	local can = Craft.Count(spell)
	local blocked = type(info) == "table" and info.disabled == true
	-- An enchant: its item row above the buttons (the item it goes on, Auto-replace).
	local ench = cb.ench
	local base = enchant and BAR + ENCH or BAR
	cb:SetHeight(base)
	if enchant then
		local t = Craft.EnchantTarget(spell)
		ench:Show()
		ench.icon:SetTexture(t and t.icon or EMPTY_SLOT)
		ench.icon:SetDesaturated(t == nil)
		ench.name:SetText(t and t.name or L["Drag an item here"])
		ench.name:SetTextColor(Color(t and "VALUE" or "LABEL"))
		ench.hint:SetText(t and L["Every enchant here goes on it"] or L["or click to pick one from your bags"])
		ench.hint:SetTextColor(Color("OFF"))
		ench.auto.SetOn(Craft.AutoReplace())
		ench.target = t
	else
		ench:Hide()
		ench.target = nil
	end
	-- An enchant run between two enchants: Next (one enchant a click) and Done in place of the buttons.
	if making and making.paused then
		cb.stop:Hide()
		Craft.PlaceStop(nil)
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.status:SetText(L["%d of %d done"]:format(making.done, making.count))
		cb.status:ClearAllPoints()
		cb.status:SetPoint("RIGHT", cb.all, "LEFT", -12, 0)
		cb.status:SetTextColor(Color("LABEL"))
		cb.status:Show()
		cb.make.text:SetText(L["Next (%d left)"]:format(making.count - making.done))
		cb.make.SetOff(false)
		cb.make:Show()
		cb.all.text:SetText(L["Done"])
		cb.all.SetOff(false)
		cb.all:Show()
		FitButtons(cb)
		return
	end
	if making or held then
		if making then
			cb.status:SetText(L["Making %d of %d"]:format(math.min(making.done + 1, making.count), making.count))
		else
			cb.status:SetText(L["Stopped"])
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
		FitButtons(cb)
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
	cb.all.text:SetText(can > 0 and L["%s All %d"]:format(verb, can) or L["%s All"]:format(verb))
	if FitButtons(cb) then cb:SetHeight(base + LIFT) end
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
		ns.Print(L["Nothing you carry can take this enchant."])
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
		if not Craft.TakeFromCursor(spell) then ns.Print(L["That item can't take this enchant."]) end
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
			GameTooltip:SetText(L["The item to enchant"])
		end
		GameTooltip:AddLine(L["Drag an item here, or click to pick one. Right-click empties it."], Color("LABEL"))
		GameTooltip:Show()
	end)
	slot:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.slot = slot
	-- (The name and hint run up to the Auto-replace label, anchored below once it's made.)
	row.name = Text(row, "body")
	row.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.hint = Text(row, "small")
	row.hint:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.hint:SetJustifyH("LEFT")
	row.hint:SetWordWrap(true)
	row.hint:SetMaxLines(2)

	row.auto = API.Switch(row)
	row.auto:SetPoint("RIGHT", row, "RIGHT", -PAD, -2)
	row.auto:SetScript("OnClick", function()
		Craft.SetAutoReplace(not Craft.AutoReplace())
		PaintCraftBar()
	end)
	row.auto:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Auto-replace"])
		GameTooltip:AddLine(L["Answers the game's \"replace the enchant?\" with yes while a run of yours is putting enchants on this item, so it doesn't stop at every cast."], Color("TEXT"))
		GameTooltip:AddLine(L["Off: the game asks each time."], Color("LABEL"))
		GameTooltip:Show()
	end)
	row.auto:HookScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.autoLabel = Text(row, "small", "RIGHT")
	row.autoLabel:SetPoint("RIGHT", row.auto, "LEFT", -8, 0)
	row.autoLabel:SetText(L["Auto-replace"])
	row.autoLabel:SetTextColor(Color("LABEL"))
	row.name:SetPoint("RIGHT", row.autoLabel, "LEFT", -12, 0)
	row.hint:SetPoint("RIGHT", row.autoLabel, "LEFT", -12, 0)
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

	cb.make = API.Button(cb, L["Create"], 26)
	-- (Create in DaylightUI's main-action look, as on its own profession window: 1.8 on.)
	if type(API.MainButton) == "function" then pcall(API.MainButton, cb.make, true) end
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
	cb.all = API.Button(cb, L["%s All"]:format(L["Create"]), 26)
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

	cb.queue = API.Button(cb, L["Queue"], 26)
	cb.queue:SetWidth(76)
	cb.queue:SetPoint("RIGHT", cb.minus, "LEFT", -8, 0)
	cb.queue:SetScript("OnClick", function()
		local spell = S.recipe
		if not spell or not ns.Queue then return end
		ns.Queue.Add(spell, CountWanted())
	end)

	cb.ench = BuildEnchantRow(cb)

	cb.stop = API.Button(cb, L["Stop"], 26)
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
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				if self.onRight then self.onRight(self) end
				return
			end
			if self.onClick then self.onClick() end
		end)
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
	-- (A heading wraps onto more lines rather than being cut off, its row as tall as it.)
	r.name:ClearAllPoints()
	r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -2)
	r.name:SetWidth(SIDE - 24)
	r.name:SetWordWrap(true)
	r.name:SetText(text)
	r.name:SetTextColor(Color("LABEL"))
	local h = math.max(18, math.ceil(r.name:GetStringHeight()) + 4)
	r:SetHeight(h)
	sideY = sideY + h + 2
end

-- o: icon, name, nameColor {r,g,b}, sub, value (0-1 for the bar), picked, onClick, tip
local function SideEntry(o)
	local r = SideRow()
	local h = 42
	r:SetHeight(h)
	r:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -sideY)
	r:SetPoint("RIGHT", side, "RIGHT", 0, 0)
	r.onClick, r.tip, r.onRight = o.onClick, o.tip, o.onRight
	local x = 12
	if o.icon then
		r.icon:SetTexture(o.icon)
		r.icon:Show()
		x = 44
	else
		r.icon:Hide()
	end
	r.name:ClearAllPoints()
	r.name:SetWidth(0)
	r.name:SetWordWrap(false)
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

-- Your professions now: { name, icon, skill, max, line, game, crafts }, those with recipes first.
-- line: the data's skill line (the game's own when the data doesn't cover it); game: the game's
-- line, the one OpenTradeSkill takes; crafts: the data has recipes for it. The rest (Herbalism,
-- Skinning, Fishing) have no trade skill window: a click on one shows its own page (GatherPage).
local function MyProfessions()
	local out = {}
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
	local list = { GetProfessions() }
	for i = 1, 7 do
		local index = list[i]
		if index then
			local ok, name, icon, skill, max, _, spellOffset, line = pcall(GetProfessionInfo, index)
			if ok and name then
				local data = ns.DataLine(line, name)
				out[#out + 1] = { name = name, icon = icon, skill = skill or 0, max = max or 0, line = data or line,
					game = line, crafts = data ~= nil, offset = spellOffset, index = index, primary = i <= 2 }
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

local CAMP_ICON = 279981     -- the Basic Campfire Kit's icon, for the camping page

-- ---------------------------------------------------------------------------------------------
-- Unlearning a primary profession
-- ---------------------------------------------------------------------------------------------
-- As the game's professions book does it (its Unlearn button: StaticPopup "UNLEARN_SKILL", whose
-- yes calls AbandonSkill(skillLine)), from a right-click on the profession on the left, behind our
-- "Are you sure?" box. Only the two primary professions: the book offers none for Cooking, First
-- Aid and Fishing. Once the game drops it, what we kept of it goes too (Forgotten).

local unlearning        -- the game's skill line just unlearned, until the game says it's gone

local function Abandon() return (C_SkillInfo and C_SkillInfo.AbandonSkill) or _G.AbandonSkill end

-- The profession is gone from your list: its saved skill, recipes, Leveling Guide, queue entries
-- and reminders are forgotten, and the window shows another page.
local function Forgotten(p)
	if ns.Store then ns.Store.ForgetProfession(p.line) end
	if ns.Queue then ns.Queue.ForgetLine(p.line) end
	if ns.Tips and ns.Tips.ForgetLine then ns.Tips.ForgetLine(p.line) end
	if gather == p.game then gather = nil end
	if S.line == p.line then
		S.recipe = nil
		if ns.Where then ns.Where.ForgetKnown() end
	end
	if DaylightRecipesDB and DaylightRecipesDB.lastLine == p.line then DaylightRecipesDB.lastLine = nil end
	if ns.Shop then ns.Shop.Refresh() end
	ns.Changed()
end

function Window.Unlearn(p)
	local abandon = Abandon()
	if not p or type(abandon) ~= "function" then return end
	local owner = win and win:IsShown() and win or nil
	ns.Shop.Confirm(owner, L["Unlearn %s? Your skill in it and every %s recipe you know are lost. Learning it again starts over at skill 1."]:format(p.name, p.name),
		nil, function()
			-- (Its trade skill open: closed first, as the game's book is when it unlearns.)
			if ns.state.mode == "win" and ns.state.line == p.line and ns.Take then ns.Take.Close() end
			unlearning = p
			local ok = pcall(abandon, p.game)
			if not ok then unlearning = nil end
		end, { title = L["Unlearn %s"]:format(p.name), yes = L["Unlearn"], warn = true })
end

local function UnlearnMenu(owner, p)
	API.Menu(owner, { "unlearn" }, { unlearn = L["Unlearn"] }, nil, function(key)
		if key == "unlearn" then Window.Unlearn(p) end
	end, nil, { atCursor = true })
end

-- The game took it off your professions: forgotten here too, and the window stays up on what's
-- left (it closes with a trade skill otherwise).
local unlearnEvents = CreateFrame("Frame")
unlearnEvents:RegisterEvent("SKILL_LINES_CHANGED")
unlearnEvents:SetScript("OnEvent", function()
	local p = unlearning
	if not p then return end
	for _, q in ipairs(MyProfessions()) do
		if q.game == p.game then return end
	end
	unlearning = nil
	Forgotten(p)
	C_Timer.After(0.1, function()
		if win and not win:IsShown() then win:Show() end
		Window.Render()
	end)
end)

local function PaintSide()
	if not side then return end
	for i = 1, #sideRows do sideRows[i]:Hide() end
	sideUsed, sideY = 0, 8 - sideScroll
	SideHeading(L["Professions"])
	local mine = MyProfessions()
	if #mine == 0 then
		SideHeading(L["You have no profession yet."])
	end
	for _, p in ipairs(mine) do
		local picked
		if gather then
			picked = not alt and gather == p.game
		else
			picked = not alt and S.mode == "win" and not Linked() and p.line == S.line
		end
		-- (One with recipes opens its trade skill; a gathering one shows its own page.)
		SideEntry({ icon = p.icon, name = p.name,
			sub = p.max > 0 and ("%d / %d"):format(p.skill, p.max) or "",
			value = p.max > 0 and p.skill / p.max or nil, picked = picked,
			onClick = function()
				if p.crafts then Window.OpenProfession(p.line, p.game) else Window.ShowGather(p.game) end
			end,
			-- (A primary profession can be unlearned, as in the game's professions book: right-click.)
			tip = p.primary and function(tip)
				tip:SetText(p.name)
				tip:AddLine(L["Right-click: unlearn"], Color("LABEL"))
			end or nil,
			onRight = p.primary and function(owner) UnlearnMenu(owner, p) end or nil })
	end
	-- Every profession's camping items (Camp.lua).
	if ns.Camp and ns.Camping and #ns.Camping > 0 then
		SideEntry({ icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(CAMP_ICON) or nil,
			name = L["Camping"], sub = L["All professions"],
			picked = not alt and gather == CAMP, onClick = function() Window.ShowGather(CAMP) end })
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
		SideHeading(L["Your alts"])
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
		d:Line(L["That character isn't on this realm and faction."], "small", "OFF")
		return
	end
	local p = type(c.prof) == "table" and c.prof[alt.line] or {}
	local known = type(c.known) == "table" and c.known[alt.line] or nil
	if type(known) ~= "table" then
		d:Line(L["Open this profession on %s once to see what they know."]:format(c.name or L["them"]), "small", "OFF")
		return
	end
	local skill = p.skill or 0
	local list = {}
	for spell in pairs(known) do
		local name = ns.SpellName(spell) or Doc.RecipeName(spell)
		if altFilter == "" or ns.Fold(name):find(altFilter, 1, true) then
			list[#list + 1] = { spell = spell, name = name }
		end
	end
	table.sort(list, function(a, b) return ns.NameLess(a.name, b.name) end)
	d:Line(Plural(#list, "%d recipe known", "%d recipes known"):format(#list), "small", "LABEL")
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
-- A gathering profession of yours
-- ---------------------------------------------------------------------------------------------
-- Herbalism, Skinning and Fishing have no trade skill window, and the recipe data has nothing for
-- them: their page shows the skill, the rank and when the next one is trained. A profession the
-- data covers whose trade skill the game wouldn't open (OpenProfession) shows here too, with how
-- to open it.

local SMELTING = 2656

-- Fishing's Expert rank is a book, sold in Booty Bay, and its Artisan rank a quest from Nat Pagle in
-- Dustwallow Marsh (the fishing trainers of the capitals send you), by the cap they lift.
local FISHING = 356
local FISHING_RANKS = {
	[150] = { item = 16083, npc = 2626, skill = 125, level = 20, rank = 225 },
	[225] = { quest = 6607, npc = 12919, skill = 225, level = 35, rank = 300 },
}

-- Where Fishing's next rank comes from, with a click to set a waypoint to who has it.
local function FishingRank(d, r, now)
	local Plan = ns.Plan
	local name = Plan and Plan.RankName(r.rank) or L["the next rank"]
	local text
	if r.item then
		text = L["%s is a book, not a trainer rank: buy %s and read it (skill %d, level %d)."]:format(name,
			Doc.ItemName(r.item, d), r.skill, r.level)
	else
		local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(r.quest)
		if type(title) ~= "string" or title == "" then
			title = ns.PolestarNames and ns.PolestarNames.quest[r.quest] or L["Quest %d"]:format(r.quest)
		end
		text = L["%s comes from a quest, not a trainer: \"%s\" (skill %d, level %d); the fishing trainer in your capital sends you."]:format(
			name, title, r.skill, r.level)
	end
	d:Line(text, now and "body" or "small", now and "WARN" or "TEXT")
	local who, place
	if ns.Where then who, place = ns.Where.Npc(r.npc) end
	if who then
		local located = place and place.mapID
		d:Row({ left = who, leftInk = "TEXT", sub = place and (located and ("%s (%d, %d)"):format(place.zone, place.x + 0.5, place.y + 0.5)
			or place.zone) or nil, subInk = located and "ACCENT" or "OFF",
			tip = located and function(tip)
				tip:SetText(who)
				tip:AddLine(L["Click for a waypoint."], Color("LABEL"))
			end or nil,
			onClick = located and function() ns.Where.Go(who, place) end or nil })
	end
end

local function GatherEntry()
	for _, p in ipairs(MyProfessions()) do
		if p.game == gather then return p end
	end
end

local function GatherPage(d)
	local p = GatherEntry()
	if not p then
		d:Line(L["You don't have that profession any more."], "body", "OFF")
		return
	end
	local Plan = ns.Plan
	local skill, cap = p.skill or 0, p.max or 0
	d:Heading(L["Skill"])
	local rank = cap > 0 and Plan and Plan.RankName(cap)
	if rank then
		d:Line(L["%s: skill %d of %d."]:format(rank, skill, cap), "body", "VALUE")
	elseif cap > 0 then
		d:Line(L["Skill %d of %d."]:format(skill, cap), "body", "VALUE")
	else
		d:Line(L["Skill %d."]:format(skill), "body", "VALUE")
	end
	d:Bar(cap > 0 and skill / cap or 0)
	-- The next rank: trained at the cap, from a trainer of this profession. Fishing's Expert is a book
	-- and its Artisan a quest (FISHING_RANKS).
	local book = p.game == FISHING and FISHING_RANKS[cap]
	if book and cap < 300 then
		FishingRank(d, book, skill >= cap)
		if skill >= cap then d:Line(L["You're capped at %d until you do."]:format(cap), "small", "TEXT") end
	elseif cap > 0 and cap < 300 then
		local nextCap = cap + 75
		local name = Plan and Plan.RankName(nextCap) or L["the next rank"]
		local level = Plan and Plan.RankLevel(nextCap)
		if skill >= cap then
			d:Line(level and L["Train %s at a %s trainer (it asks level %d)."]:format(name, p.name, level)
				or L["Train %s at a %s trainer."]:format(name, p.name), "body", "WARN")
			d:Line(L["You're capped at %d until you do."]:format(cap), "small", "TEXT")
		else
			d:Line(level and L["At %d: train %s (level %d)."]:format(cap, name, level)
				or L["At %d: train %s."]:format(cap, name), "small", "TEXT")
		end
	elseif cap >= 300 and skill >= cap then
		d:Line(L["%s is at its top skill."]:format(p.name), "small", "GOOD")
	end
	if p.crafts then
		d:Heading(L["Recipes"])
		-- (The game wouldn't open it from here: its own spell does.)
		local spell = p.line == 186 and ns.SpellName(SMELTING) or p.name
		d:Line(L["Cast %s from your spellbook to open its recipes here."]:format(spell or p.name), "small", "TEXT")
	elseif ns.Camp and ns.Camp.Has(p.game) then
		-- (Its only recipes are its camping items: no recipe list, Leveling Guide or Missing tab.)
		d:Line(L["%s's skill rises as you gather; its only recipes are its camping items, below."]:format(p.name), "small", "TEXT")
		ns.Camp.Section(d, p.game, Window.Render)
	else
		d:Heading(L["Recipes"])
		d:Line(L["%s has no recipes: its skill rises as you gather, so there's no recipe list, Leveling Guide or missing recipes for it."]:format(p.name),
			"small", "TEXT")
	end
end

-- Every profession's camping items, in place of a profession's page.
local function CampPage(d)
	if ns.Camp then ns.Camp.Page(d, Window.Render) end
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

local headIcon, headName, headBar, headSkill, headNote

local TABS = { { "recipes", L["Recipes"] }, { "guide", L["Leveling Guide"] }, { "materials", L["Materials"] },
	{ "queue", L["Queue"] }, { "missing", L["Missing"] } }

local function PaintTabs()
	for _, b in ipairs(tabButtons) do
		b:SetShown(not alt and not gather)
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
	win:SetScale(Scale())
	ns.SkinWindow(win)
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
	-- (Beside the X: the swap button, back to the game's or DaylightUI's profession window.)
	if ns.Swap then ns.Swap.OnWindow(win, close) end

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
	search = API.Input(body, { search = true, hint = L["Search recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == filterText then return end
			filterText = text
			Debounce(function()
				offset = 0
				Window.Dirty()
			end)
		end })
	search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	search:SetWidth(LIST - PAD * 2)
	filterButtons = { Toggle(body, L["Can make"], "canMake"), Toggle(body, L["Skill-ups"], "skillUps") }
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

	detail = Doc.New(body, { pad = 18, redraw = function() Window.Render() end })
	detail.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", LIST + 1, -4)
	detail.scroll:SetPoint("BOTTOMRIGHT", craftBar, "TOPRIGHT", 0, 0)

	-- The other tabs: one page across, the missing list with its search above it.
	pageSearch = API.Input(body, { search = true, hint = L["Search missing recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == (pageSearch.filter or "") then return end
			pageSearch.filter = text
			Debounce(function()
				if pageDoc then pageDoc:Top() end
				Window.Render()
			end)
		end })
	pageSearch:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	pageSearch:SetWidth(320)
	pageDoc = Doc.New(body, { pad = 24, redraw = function() Window.Render() end })

	altDoc = Doc.New(body, { pad = 24, redraw = function() Window.Render() end })
	altDoc.search = API.Input(body, { search = true, hint = L["Search their recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == altFilter then return end
			altFilter = text
			Debounce(function() Window.Render() end)
		end })
	altDoc.search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -10)
	altDoc.search:SetWidth(320)
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
		headName:SetText(L["%s's %s"]:format((c and c.name) or "?", ns.Tips and ns.Tips.LineName(alt.line) or ""))
		headName:SetTextColor(Color("VALUE"))
		headBar:SetMinMaxValues(0, math.max(1, p.max or 1))
		headBar:SetValue(p.skill or 0)
		headBar:Show()
		headSkill:SetText(("%d / %d"):format(p.skill or 0, p.max or 0))
		headSkill:SetTextColor(Color("LABEL"))
		headNote:SetText(L["As of their last visit"])
		headNote:SetTextColor(Color("OFF"))
		return
	end
	if gather == CAMP then
		local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(CAMP_ICON) or nil
		headIcon:SetTexture(icon)
		headIcon:SetShown(icon ~= nil)
		headName:SetText(L["Camping"])
		headName:SetTextColor(Color("VALUE"))
		headBar:Hide()
		headSkill:SetText("")
		headNote:SetText("")
		return
	end
	if gather then
		local p = GatherEntry()
		headIcon:SetTexture(p and p.icon or nil)
		headIcon:SetShown(p ~= nil and p.icon ~= nil)
		headName:SetText(p and p.name or L["Profession"])
		headName:SetTextColor(Color("VALUE"))
		if p and p.max > 0 then
			headBar:SetMinMaxValues(0, p.max)
			headBar:SetValue(p.skill)
			headBar:Show()
			headSkill:SetText(("%d / %d"):format(p.skill, p.max))
			headSkill:SetTextColor(Color("LABEL"))
		else
			headBar:Hide()
			headSkill:SetText("")
		end
		headNote:SetText("")
		return
	end
	local open = S.mode == "win"
	local icon = open and S.line and TS("GetTradeSkillTexture", S.line) or nil
	if not icon and open then
		for _, p in ipairs(MyProfessions()) do if p.line == S.line then icon = p.icon end end
	end
	headIcon:SetTexture(icon)
	headIcon:SetShown(icon ~= nil)
	headName:SetText(open and (S.name or L["Profession"]) or "Daylight Recipes")
	headName:SetTextColor(Color("VALUE"))
	if open and (S.max or 0) > 0 then
		headBar:SetMinMaxValues(0, S.max)
		headBar:SetValue(S.skill or 0)
		headBar:Show()
		headSkill:SetText(("%d / %d"):format(S.skill or 0, S.max))
		headSkill:SetTextColor(Color("LABEL"))
	else
		headBar:Hide()
		headSkill:SetText(open and "" or L["Pick a profession on the left."])
		headSkill:SetTextColor(Color("OFF"))
	end
	if open and Linked() then
		local _, who = TS("IsTradeSkillLinked")
		headNote:SetText(type(who) == "string" and L["%s's recipes"]:format(who) or L["Someone else's recipes"])
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
		d:Line(L["Something went wrong drawing this page."], "small", "BAD")
	end
	d:Finish()
end

local function NoSession(d)
	d:Line(L["Open a profession from the list on the left (or cast it from your spellbook)."], "body", "OFF")
end

function Window.Render()
	if not Window.Shown() then return end
	PaintHead()
	PaintSide()
	PaintTabs()
	local other = alt ~= nil or gather ~= nil     -- an alt's profession or a gathering one: no tabs
	local recipes = not other and tab == "recipes"
	local open = S.mode == "win"
	search:SetShown(recipes)
	for _, b in ipairs(filterButtons) do
		b:SetShown(recipes)
		b.Paint()
	end
	listFrame:SetShown(recipes)
	body.listEdge:SetShown(recipes)
	detail.scroll:SetShown(recipes)
	pageSearch:SetShown(not other and tab == "missing")
	pageDoc.scroll:SetShown(not other and not recipes)
	altDoc.scroll:SetShown(other)
	altDoc.search:SetShown(alt ~= nil)
	if other then
		-- (A gathering profession's page has no search above it.)
		altDoc.scroll:ClearAllPoints()
		altDoc.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, alt and -46 or -4)
		altDoc.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
		Draw(altDoc, alt and AltPage or (gather == CAMP and CampPage) or GatherPage)
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
	if tab == key and not alt and not gather then return end
	tab = key
	alt, gather = nil, nil
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
	return Window.Shown() and not alt and not gather and tab ~= "missing"
end

function Window.ShowingMissing()
	return Window.Shown() and not alt and not gather and tab == "missing"
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
	alt, gather = nil, nil
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

-- Opens one of your professions (a click: the game asks for one to open a trade skill). line: the
-- data's skill line; game: the game's own for it, the one the game opens (the same, mostly).
function Window.OpenProfession(line, game)
	if not line then return end
	game = game or line
	if S.mode == "win" and S.line == line and not Linked() then
		if alt or gather then
			alt, gather = nil, nil
			Window.Render()
		end
		return
	end
	alt, gather = nil, nil
	local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, game)
	if not ok or opened == false then
		-- (Its page says how to open it instead, with its skill and rank.)
		ns.Print(L["The game didn't open that profession."])
		Window.ShowGather(game)
	end
end

function Window.ShowAlt(guid, line)
	alt, gather = { guid = guid, line = line }, nil
	if altDoc then altDoc:Top() end
	Window.Render()
end

-- A gathering profession of yours (by the game's skill line): its page, in place of the tabs.
function Window.ShowGather(game)
	if not game then return end
	alt, gather = nil, game
	if not win then Build() end
	if altDoc then altDoc:Top() end
	if not win:IsShown() then win:Show() end
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
	local game = last
	for _, p in ipairs(MyProfessions()) do
		-- (The game's own line for the one last open, else your first with recipes.)
		if (last and p.line == last) or (not last and p.crafts) then
			game = p.game
			break
		end
	end
	if game then
		local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, game)
		if ok and opened ~= false then return end
	end
	-- No profession to open: the window shows your professions and alts anyway.
	if not win then Build() end
	win:Show()
end

function Window.Restyle()
	if Window.Shown() then Window.Render() end
end

function Window.Rescale()
	if not win then return end
	local old, new = win:GetScale(), Scale()
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

-- The screen got smaller or larger (the UI scale, the game's window): the window fits it again.
local screen = CreateFrame("Frame")
screen:RegisterEvent("UI_SCALE_CHANGED")
screen:RegisterEvent("DISPLAY_SIZE_CHANGED")
screen:SetScript("OnEvent", function()
	-- (A frame later: UIParent takes its new size after the event.)
	C_Timer.After(0, Window.Rescale)
end)
