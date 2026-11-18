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
local Pad = ns.Pad     -- the window on a controller (Guide.lua)

local W, H = 1000, 640
local SIDE = 210          -- the professions on the left
local LIST = 330          -- the recipe list
local HEAD = 96           -- the profession's name, skill bar and tabs
local BAR = 52            -- Create / Create All under the recipe
local ROW = 20            -- a line of the recipe list
local PAD = 14

local win, side, sideList, track, cool, content, body
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

-- On a controller the list scrolls under the cursor: the D-pad past its first or last row moves it
-- a row (the cursor stays on that row), and the right stick scrolls it (listPad: a stand-in scroll
-- frame, Guide.lua's Pad.Scroller).
local listPad
local stickMoving = false   -- the stick moved it: its stand-in keeps the stick's own position
local PaintList

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
		Pad.Into(self, listPad)
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
			if link then ns.InsertLink(link) end
			return
		end
		Window.Select(e.spell)
	end)
	-- The D-pad past the list's edge: a row further, the cursor (and its tooltip) staying put.
	local function Step(by)
		local n = by > 0 and VisibleRows() or 1
		if r.index ~= n then return false end
		local was = offset
		offset = offset + by
		PaintList()
		if offset == was then return false end
		if GameTooltip:IsOwned(r) then r:GetScript("OnEnter")(r) end
		return true
	end
	Pad.Edge(r, "DOWN", function() return Step(1) end)
	Pad.Edge(r, "UP", function() return Step(-1) end)
	return r
end

PaintList = function()
	if not listFrame then return end
	if listDirty then BuildList() end
	ClampOffset()
	local shown = VisibleRows()
	listRows = listRows or {}
	local best = ns.Tips and ns.Tips.Best and ns.Get("marks") and ns.Tips.Best() or nil
	-- The Leveling Guide's current recipe, lit wherever its row is (rows are reused as it scrolls).
	local guide = Doc.GlowStyle() and ns.Plan and ns.Plan.CurrentSpell() or nil
	local ar, ag, ab = API.Accent()
	for i = 1, shown + 1 do
		local r = listRows[i]
		if not r then
			r = MakeListRow()
			r.index = i
			listRows[i] = r
		end
		local e = entries[offset + i]
		r.entry = e
		Doc.Glow(r, e ~= nil and i <= shown and not e.cat and e.spell == guide)
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
	if listPad and not stickMoving then listPad.Sync() end
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

local ENCH = ns.EnchantRow.HEIGHT   -- an enchant's item row, above the buttons (EnchantRow.lua)
local countBox

local function Linked() return S.linked == true end

-- A link into the open chat box, through the game's own call (ChatFrameUtil.InsertLink; the old
-- ChatEdit_InsertLink only lives in the game's deprecated-API addon). True when it went in.
function ns.InsertLink(link)
	if not link then return false end
	local U = _G.ChatFrameUtil
	if U and type(U.InsertLink) == "function" then return U.InsertLink(link) and true or false end
	if type(_G.ChatEdit_InsertLink) == "function" then return _G.ChatEdit_InsertLink(link) and true or false end
	return false
end

-- Your open profession's link (C_TradeSkillUI.GetTradeSkillListLink, as the game's own link
-- button) into the open chat box. Only for your own profession: not a linked one, not an alt's.
function Window.LinkOpen()
	if S.mode ~= "win" or Linked() or alt or gather then return false end
	local ok, link = pcall(C_TradeSkillUI.GetTradeSkillListLink)
	if not ok or not link then return false end
	return ns.InsertLink(link)
end

-- Shift-click on a profession in the list: linked at once when it's the open one, else opened and
-- linked as soon as it's open (the game only links the open trade skill).
function Window.LinkProfession(line, game)
	if S.mode == "win" and S.line == line and not Linked() and not alt and not gather then
		Window.LinkOpen()
		return
	end
	Window.OpenProfession(line, game)
	local tries = 0
	local function wait()
		tries = tries + 1
		if S.mode == "win" and S.line == line and not Linked() then
			Window.LinkOpen()
		elseif tries < 20 then
			C_Timer.After(0.1, wait)
		end
	end
	C_Timer.After(0.1, wait)
end

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
		d:Heading(L["Also Known By"])
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
		ench:Show()
		ench:Update(spell)
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
		cb.make.text:SetText(L["Next (%d Left)"]:format(making.count - making.done))
		if ns.Guide then ns.Guide.Offer("enchant") end
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

	-- (An enchant's item row: EnchantRow.lua, shared with the docked pane.)
	cb.ench = ns.EnchantRow.New(cb, { pad = PAD, onChange = PaintCraftBar })
	cb.ench:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
	cb.ench:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)

	cb.stop = API.Button(cb, L["Stop"], 26)
	cb.stop:SetWidth(110)
	cb.stop:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	-- (The secure Stop laid over it takes the click: Craft.PlaceStop. A controller's A on it stops
	-- through DaylightUI's own secure button: the window's padKeys, Build.)
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
local PaintTrack           -- the tracking strip under the professions (below)
local PaintCooldowns       -- the craft cooldowns box above it (below)
local PlaceFoot            -- stacks the two under the professions list
local sideUsed = 0
local sideY = 0
local sideScroll = 0     -- how far the side list is scrolled
local sideTall = 0       -- how tall it is in all
local sidePad            -- its stand-in scroll frame for a controller's right stick (Build)
local PaintSide

-- A controller's cursor on a row scrolled out of the list's sight: the list scrolls to it (the
-- mouse can't reach those rows, so this is the controller's only way there).
local function SideIntoView(r)
	if not Pad.On() then return end
	local top, bottom = r:GetTop(), r:GetBottom()
	local listTop, listBottom = sideList:GetTop(), sideList:GetBottom()
	if not (top and bottom and listTop and listBottom) then return end
	local by = 0
	if bottom < listBottom then by = listBottom - bottom + 4 elseif top > listTop then by = listTop - top - 4 end
	if by == 0 then return end
	local most = math.max(0, sideTall - sideList:GetHeight() + 8)
	local to = math.max(0, math.min(most, sideScroll + by))
	if to ~= sideScroll then
		sideScroll = to
		PaintSide()
	end
end

local function SideRow()
	sideUsed = sideUsed + 1
	local r = sideRows[sideUsed]
	if not r then
		r = CreateFrame("Button", nil, sideList)
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
			Pad.Into(self, sidePad)
			SideIntoView(self)
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
		-- A controller's Y: what a right-click does (a primary profession's Unlearn).
		r.padMore = function(self) return self.onRight end
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
	r:SetPoint("TOPLEFT", sideList, "TOPLEFT", 0, -sideY)
	r:SetPoint("RIGHT", sideList, "RIGHT", 0, 0)
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
	r:SetPoint("TOPLEFT", sideList, "TOPLEFT", 0, -sideY)
	r:SetPoint("RIGHT", sideList, "RIGHT", 0, 0)
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

-- ---------------------------------------------------------------------------------------------
-- Tracking: the professions' minimap tracking, at the foot of the professions
-- ---------------------------------------------------------------------------------------------
-- The tracking spells of your professions (Find Minerals, Find Herbs, Find Fish), as the game's
-- minimap tracking menu lists them (C_Minimap.GetTrackingInfo: only the ones you know). Click one
-- to turn it on or off (C_Minimap.SetTracking, as that menu does). The one on has an accent ring
-- and DaylightUI's glow, in the style the player picked for its main buttons.

local TRACK_SPELLS = { [2580] = true, [2383] = true, [43308] = true }
local TILE, TILE_GAP = 32, 8
local trackTiles = {}

-- Their names in the game's language, so one Forever lists under another spell ID still counts.
local trackNames
local function TrackName(name)
	if not trackNames then
		trackNames = {}
		for spell in pairs(TRACK_SPELLS) do
			local n = ns.SpellName(spell)
			if type(n) == "string" and n ~= "" then trackNames[n] = true end
		end
		if not next(trackNames) then
			trackNames = nil     -- (the spell names weren't in yet: asked again next time)
			return false
		end
	end
	return type(name) == "string" and trackNames[name] == true
end

local function TrackingList()
	local out = {}
	local M = C_Minimap
	if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo and M.SetTracking) then return out end
	local ok, n = pcall(M.GetNumTrackingTypes)
	if not ok or type(n) ~= "number" then return out end
	for i = 1, n do
		local got, info = pcall(M.GetTrackingInfo, i)
		if got and type(info) == "table" and ((info.spellID and TRACK_SPELLS[info.spellID]) or TrackName(info.name)) then
			out[#out + 1] = { index = i, name = info.name, icon = info.texture, on = info.active == true,
				spell = info.spellID }
		end
	end
	return out
end

-- The glow style for a tile that's on: the player's main-button style, none when that's None or
-- this DaylightUI has no GlowAround (the ring still shows it's on).
local function TrackGlowStyle()
	if type(API.GlowAround) ~= "function" then return false end
	local ok, style = pcall(API.GetSetting, "general", "buttonGlow")
	if not ok or style == "none" then return false end
	return type(style) == "string" and style or "circle"
end

local function TrackTile(i)
	local b = trackTiles[i]
	if b then return b end
	b = CreateFrame("Button", nil, track)
	b:SetSize(TILE, TILE)
	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetPoint("TOPLEFT", -2, 2)
	b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.wash = Wash(b, "OVERLAY", 0.12)
	b.wash:SetAllPoints()
	b.wash:Hide()
	b:SetScript("OnEnter", function(self)
		self.wash:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not (self.spell and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell)) then
			GameTooltip:SetText(self.name or "")
		end
		GameTooltip:AddLine(self.on and L["Click: turn off"] or L["Click: turn on"], Color("LABEL"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function(self)
		if not self.index then return end
		pcall(C_Minimap.SetTracking, self.index, not self.on)
	end)
	trackTiles[i] = b
	return b
end

PaintTrack = function()
	if not track then return end
	local list = TrackingList()
	for i = #list + 1, #trackTiles do
		local b = trackTiles[i]
		b:Hide()
		if b.glow then API.GlowAround(b, false); b.glow = nil end
	end
	if #list == 0 then
		track:Hide()
		PlaceFoot()
		return
	end
	if not track.title then
		track.title = Text(track, "body")
		track.title:SetJustifyH("LEFT")
		track.title:SetPoint("TOPLEFT", track, "TOPLEFT", 14, -10)
		track.line = track:CreateTexture(nil, "ARTWORK")
		track.line:SetHeight(1)
		track.line:SetPoint("TOPLEFT", track, "TOPLEFT", 12, 0)
		track.line:SetPoint("TOPRIGHT", track, "TOPRIGHT", -12, 0)
		track.line:SetColorTexture(1, 1, 1, 0.06)
	end
	track.title:SetText(L["Tracking"])
	track.title:SetTextColor(Color("LABEL"))
	-- (Tiles in rows across the strip, as many as fit.)
	local across = math.max(1, math.floor((SIDE - 28 + TILE_GAP) / (TILE + TILE_GAP)))
	local top = 10 + math.ceil(track.title:GetStringHeight()) + 10
	local ar, ag, ab = API.Accent()
	local style = TrackGlowStyle()
	for i, t in ipairs(list) do
		local b = TrackTile(i)
		local col, row = (i - 1) % across, math.floor((i - 1) / across)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", track, "TOPLEFT", 14 + col * (TILE + TILE_GAP), -(top + row * (TILE + TILE_GAP)))
		b.index, b.name, b.spell, b.on = t.index, t.name, t.spell, t.on
		b.icon:SetTexture(t.icon)
		b.icon:SetDesaturated(not t.on)
		b.icon:SetAlpha(t.on and 1 or 0.6)
		if t.on then b.ring:SetColorTexture(ar, ag, ab, 1) else b.ring:SetColorTexture(1, 1, 1, 0.08) end
		-- (Started again only when it changes, so a repaint doesn't start its light over.)
		local want = t.on and style or false
		if (b.glow or false) ~= want then
			if b.glow then API.GlowAround(b, false) end
			if want then API.GlowAround(b, true, { style = want, inset = -2 }) end
			b.glow = want or nil
		end
		b:Show()
	end
	local rows = math.ceil(#list / across)
	track:SetHeight(top + rows * TILE + (rows - 1) * TILE_GAP + 14)
	track:Show()
	PlaceFoot()
end

-- ---------------------------------------------------------------------------------------------
-- Craft cooldowns: above the tracking strip
-- ---------------------------------------------------------------------------------------------
-- Your recipes that can only be made once in a while (Cooldowns.lua), one tile each: the item
-- gray with the time left on it while it's cooling down, in full color with a green ring once it's
-- ready. Hover for which recipes and when; click to open the recipe. While a tile is cooling down
-- and the box shows, it's drawn again every half minute (nothing runs while it's hidden).

local coolTiles = {}
local coolTicker
local COOL_TICK = 30

local function StopCoolTicker()
	if coolTicker then
		coolTicker:Cancel()
		coolTicker = nil
	end
end

local function CoolTile(index)
	local b = coolTiles[index]
	if b then return b end
	b = CreateFrame("Button", nil, cool)
	b:SetSize(TILE, TILE)
	b.ring = b:CreateTexture(nil, "BACKGROUND")
	b.ring:SetPoint("TOPLEFT", -2, 2)
	b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.time = Text(b, "tiny")
	b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
	b.wash = Wash(b, "OVERLAY", 0.12)
	b.wash:SetAllPoints()
	b.wash:Hide()
	b:SetScript("OnEnter", function(self)
		self.wash:Show()
		local t = self.tile
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for i, name in ipairs(t.names) do GameTooltip:AddLine(name, Color(i == 1 and "VALUE" or "TEXT")) end
		if t.readyAt == 0 then
			GameTooltip:AddLine(L["Ready to craft"], Color("GOOD"))
		else
			GameTooltip:AddLine(L["Ready in %s"]:format(ns.Cooldowns.Left(t.readyAt)), Color("WARN"))
		end
		GameTooltip:AddLine(L["Click: show the recipe"], Color("LABEL"))
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.wash:Hide()
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function(self)
		local t = self.tile
		if t and t.line and t.spells[1] then Window.OpenRecipe(t.line, t.spells[1]) end
	end)
	coolTiles[index] = b
	return b
end

PaintCooldowns = function()
	if not cool then return end
	local list = ns.Cooldowns and ns.Cooldowns.List() or {}
	for i = #list + 1, #coolTiles do coolTiles[i]:Hide() end
	if #list == 0 then
		StopCoolTicker()
		cool:Hide()
		PlaceFoot()
		return
	end
	if not cool.title then
		cool.title = Text(cool, "body")
		cool.title:SetJustifyH("LEFT")
		cool.title:SetPoint("TOPLEFT", cool, "TOPLEFT", 14, -10)
		cool.line = cool:CreateTexture(nil, "ARTWORK")
		cool.line:SetHeight(1)
		cool.line:SetPoint("TOPLEFT", cool, "TOPLEFT", 12, 0)
		cool.line:SetPoint("TOPRIGHT", cool, "TOPRIGHT", -12, 0)
		cool.line:SetColorTexture(1, 1, 1, 0.06)
	end
	cool.title:SetText(L["Cooldowns"])
	cool.title:SetTextColor(Color("LABEL"))
	local across = math.max(1, math.floor((SIDE - 28 + TILE_GAP) / (TILE + TILE_GAP)))
	local top = 10 + math.ceil(cool.title:GetStringHeight()) + 10
	local gr, gg, gb = Color("GOOD")
	local cooling = false
	for i, t in ipairs(list) do
		local b = CoolTile(i)
		local col, row = (i - 1) % across, math.floor((i - 1) / across)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", cool, "TOPLEFT", 14 + col * (TILE + TILE_GAP), -(top + row * (TILE + TILE_GAP)))
		b.tile = t
		b.icon:SetTexture(t.icon or 134400)
		local ready = t.readyAt == 0
		b.icon:SetDesaturated(not ready)
		b.icon:SetAlpha(ready and 1 or 0.55)
		if ready then
			b.ring:SetColorTexture(gr, gg, gb, 1)
			b.time:SetText("")
		else
			cooling = true
			b.ring:SetColorTexture(1, 1, 1, 0.08)
			-- (One unit on the tile, so it fits its width; the tooltip has the whole time.)
			b.time:SetText(ns.Cooldowns.Short(t.readyAt))
			b.time:SetTextColor(Color("VALUE"))
		end
		b:Show()
	end
	local rows = math.ceil(#list / across)
	cool:SetHeight(top + rows * TILE + (rows - 1) * TILE_GAP + 14)
	cool:Show()
	PlaceFoot()
	-- The countdown: only while something is cooling down and the box is on screen.
	if not cooling then
		StopCoolTicker()
	elseif not coolTicker then
		coolTicker = C_Timer.NewTicker(COOL_TICK, function()
			if Window.PaintCooldowns and cool and cool:IsVisible() then Window.PaintCooldowns() else StopCoolTicker() end
		end)
	end
end

-- The foot of the professions list, bottom up: tracking, then cooldowns, then the list above them.
PlaceFoot = function()
	local below, point = side, "BOTTOM"
	if track and track:IsShown() then
		track:ClearAllPoints()
		track:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
		track:SetPoint("RIGHT", side, "RIGHT", 0, 0)
		below, point = track, "TOP"
	end
	if cool and cool:IsShown() then
		cool:ClearAllPoints()
		cool:SetPoint("BOTTOMLEFT", below, point == "TOP" and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
		cool:SetPoint("RIGHT", side, "RIGHT", 0, 0)
		below, point = cool, "TOP"
	end
	sideList:SetPoint("BOTTOM", below, point, 0, 0)
end

-- Tracking turned on or off (here or from the minimap), or a tracking spell learned: the strip,
-- and the professions above it (a strip that comes or goes changes how much of them fits).
local trackEvents = CreateFrame("Frame")
trackEvents:RegisterEvent("MINIMAP_UPDATE_TRACKING")
trackEvents:RegisterEvent("SPELLS_CHANGED")
trackEvents:SetScript("OnEvent", function()
	if not Window.Shown() then return end
	PaintTrack()
	PaintSide()
end)

-- The cooldowns read again (Cooldowns.lua) or their countdown ticked: the box, and the professions
-- above it.
function Window.PaintCooldowns()
	if not Window.Shown() then return end
	PaintCooldowns()
	PaintSide()
end

PaintSide = function()
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
				if p.crafts and IsModifiedClick("CHATLINK") then
					Window.LinkProfession(p.line, p.game)
				elseif p.crafts then
					Window.OpenProfession(p.line, p.game)
				else
					Window.ShowGather(p.game)
				end
			end,
			-- (Shift-click links one with recipes to chat; a primary profession can be unlearned,
			-- as in the game's professions book: right-click.)
			tip = (p.crafts or p.primary) and function(tip)
				tip:SetText(p.name)
				if p.crafts then tip:AddLine(L["Shift-click: link to chat"], Color("LABEL")) end
				if p.primary then tip:AddLine(L["Right-click: unlearn"], Color("LABEL")) end
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
		SideHeading(L["Your Alts"])
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
	local most = math.max(0, sideTall - sideList:GetHeight() + 8)
	if sideScroll > most then
		sideScroll = most
		PaintSide()
		return
	end
	if sidePad and not stickMoving then sidePad.Sync() end
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

-- The window on a controller. Its own function: Build alone would reach more than the 60 outside
-- locals Lua 5.1 lets one function use, and the file would not load at all.
local function BuildPad(iconHit)
	-- A controller (Guide.lua's Pad): the game's cursor moves over the window's rows and buttons
	-- while it's shown, A presses, B closes it, LB / RB step through the tabs, Y does what a
	-- right-click does, the right stick scrolls the list the cursor is in. The recipe list and the
	-- professions are drawn from an offset, so the stick scrolls them through stand-ins.
	Pad.Skip(iconHit)   -- (shift-click only)
	listPad = Pad.Scroller({
		range = function() return math.max(0, #entries - VisibleRows()) * ROW end,
		at = function() return offset * ROW end,
		set = function(v)
			local n = math.floor(v / ROW + 0.5)
			if n == offset then return end
			offset = n
			stickMoving = true
			PaintList()
			stickMoving = false
		end })
	sidePad = Pad.Scroller({
		range = function() return math.max(0, sideTall - sideList:GetHeight() + 8) end,
		at = function() return sideScroll end,
		set = function(v)
			v = math.floor(v + 0.5)
			if v == sideScroll then return end
			sideScroll = v
			stickMoving = true
			PaintSide()
			stickMoving = false
		end })
	win.padTabs = function()
		local list, at = {}, nil
		for _, b in ipairs(tabButtons) do
			if b:IsShown() then
				list[#list + 1] = b
				if b.key == tab then at = #list end
			end
		end
		return list, at
	end
	-- The cursor starts on the picked recipe (else the list's first row, else your first profession).
	win.padFirst = function()
		if listFrame:IsVisible() and listRows then
			for _, r in ipairs(listRows) do
				if r:IsShown() and r.entry and r.entry.spell and r.entry.spell == S.recipe then return r end
			end
			if listRows[1] and listRows[1]:IsShown() then return listRows[1] end
		end
		for _, r in ipairs(sideRows) do
			if r:IsShown() and r.onClick then return r end
		end
		return nil
	end
	-- A on Stop: the secure Stop's own action, through DaylightUI's secure key (the Stop drawn here
	-- only shows it).
	win.padKeys = { { key = "A", label = L["Stop"],
		secure = function(at)
			if craftBar and at == craftBar.stop and craftBar.stop:IsVisible() then
				return { type = "macro", macrotext = "/stopcasting" }
			end
			return nil
		end } }
	Pad.Follow(win, function() win:Hide() end)
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
		StopCoolTicker()
		Craft.PlaceStop(nil)
		if ns.Take and ns.Take.OursNow() then ns.Take.Close() end
	end)
	win:SetScript("OnShow", function()
		ns.Changed()
		-- (A tour is showing the window: above DaylightUI's options, where Retake Tour is clicked,
		-- and on its Recipes tab. Window.ShowForTour)
		if Window.tourRaised then Window.TourRaise() end
		-- (The first time, on this account: the window's tour. RecipesGuide.lua)
		if ns.Guide then ns.Guide.Offer("window") end
	end)

	local close = API.Close(win, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -10, -10)
	-- (Beside the X: the swap button, back to the game's or DaylightUI's profession window.)
	if ns.Swap then win.swapButton = ns.Swap.OnWindow(win, close) end

	-- Left: the professions.
	side = CreateFrame("Frame", nil, win)
	side:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDE)
	side:SetClipsChildren(true)
	side:EnableMouseWheel(true)
	side:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, sideTall - sideList:GetHeight() + 8)
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
	-- (The professions scroll in sideList; under it, the tracking strip (PaintTrack) when you
	-- know a profession's tracking.)
	sideList = CreateFrame("Frame", nil, side)
	sideList:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)
	sideList:SetPoint("RIGHT", side, "RIGHT", 0, 0)
	sideList:SetPoint("BOTTOM", side, "BOTTOM", 0, 0)
	sideList:SetClipsChildren(true)
	track = CreateFrame("Frame", nil, side)
	track:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 0, 0)
	track:SetPoint("RIGHT", side, "RIGHT", 0, 0)
	track:Hide()
	cool = CreateFrame("Frame", nil, side)
	cool:Hide()

	content = CreateFrame("Frame", nil, win)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
	content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)

	-- The profession's head: icon, name, skill bar.
	headIcon = content:CreateTexture(nil, "ARTWORK")
	headIcon:SetSize(34, 34)
	headIcon:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, -14)
	headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Shift-click the icon: your open profession linked to chat, as the game's link button does.
	local iconHit = CreateFrame("Button", nil, content)
	iconHit:SetAllPoints(headIcon)
	iconHit:SetScript("OnClick", function()
		if IsModifiedClick("CHATLINK") then Window.LinkOpen() end
	end)
	iconHit:SetScript("OnEnter", function(self)
		if not headIcon:IsShown() or S.mode ~= "win" or Linked() or alt or gather then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(S.name or L["Profession"])
		GameTooltip:AddLine(L["Shift-click: link to chat"], Color("LABEL"))
		GameTooltip:Show()
	end)
	iconHit:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
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
	filterButtons = { Toggle(body, L["Can Make"], "canMake"), Toggle(body, L["Skill-ups"], "skillUps") }
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

	BuildPad(iconHit)

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

local Render
local stuckTo      -- the page the right stick was last put on

function Window.Render()
	if not Window.Shown() then return end
	Render()
	-- A controller: the game finds the window's buttons again (they come and go with the page),
	-- and the stick goes to the new page's list (a row the cursor enters takes it after).
	if Pad.On() then
		local page = (alt or gather) and "other" or tab
		if page ~= stuckTo then
			stuckTo = page
			Pad.Stick(win, page == "recipes" and listPad or page == "other" and altDoc.scroll or pageDoc.scroll)
		end
		Pad.Settle()
	end
end

Render = function()
	PaintHead()
	PaintTrack()
	PaintCooldowns()
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
	-- (A tab's own short tour, the first time it opens: RecipesGuide.lua.)
	if ns.Guide then ns.Guide.Offer("tab-" .. key) end
end

-- What the tours light (RecipesGuide.lua): the window, the professions list, the tabs, the recipe
-- list, the craft bar, the page under the tabs and the swap button beside the X.
function Window.TourParts()
	local byKey = {}
	for _, b in ipairs(tabButtons) do if b.key then byKey[b.key] = b end end
	return { win = win, side = side, tabs = tabButtons, tabOf = byKey, list = listFrame, craft = craftBar, body = body,
		swap = win and win.swapButton, tab = tab }
end

-- Opens the window for a tour (on the open profession, else the last one, else your professions).
-- Until the tour ends (Window.TourDone) the window sits above DaylightUI's options (Retake Tour is
-- clicked there) on its Recipes tab, whenever it shows: opening a profession shows it a moment
-- later, once the game says the trade skill is open.
function Window.ShowForTour()
	Window.tourRaised = true
	if Window.Shown() then Window.TourRaise() else Window.Toggle(true) end
end

function Window.TourRaise()
	if not win then return end
	win:SetFrameStrata("FULLSCREEN")
	if tab ~= "recipes" or alt or gather then
		tab, alt, gather = "recipes", nil, nil
		Window.Render()
	end
end

function Window.TourDone()
	Window.tourRaised = nil
	if win then win:SetFrameStrata("MEDIUM") end
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

-- Opens one of your recipes (a cooldown tile's click): its profession first when another is
-- open, then the recipe on the Recipes tab, as a pick from the Leveling Guide does.
function Window.OpenRecipe(line, spell)
	if not (line and type(spell) == "number") then return end
	local function Pick()
		Window.SetTab("recipes")
		Window.Select(spell)
	end
	if S.mode == "win" and S.line == line and not Linked() then
		Pick()
		return
	end
	local game
	for _, p in ipairs(MyProfessions()) do
		if p.line == line and p.crafts then game = p.game end
	end
	if not game then return end
	Window.OpenProfession(line, game)
	-- (Picked once the game says it's open: it opens a moment after the click.)
	local tries = 0
	local function wait()
		tries = tries + 1
		if S.mode == "win" and S.line == line and not Linked() then
			Pick()
		elseif tries < 20 then
			C_Timer.After(0.1, wait)
		end
	end
	C_Timer.After(0.1, wait)
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
-- noGame: the window alone, without asking the game to open a profession (a tour that starts by
-- itself: the game opens a trade skill only from a click, and blocks it from a timer).
function Window.Toggle(noGame)
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
	if game and not noGame then
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
