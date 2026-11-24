-- The window's recipe side (Window.lua builds the frame and calls these):
--   the recipe list (search, "Can Make", "Skill-ups", categories that fold): a fixed set of rows
--   over the list, filled as it scrolls, so a profession of hundreds of recipes costs a screen;
--   the picked recipe's page (the detail column that slides out);
--   the summary line (the picked recipe's chance, cost and sale value in one line);
--   the craft bar (Queue, the count, Max, Create; Stop and the progress line while making).
-- Also ns.Win: what the window's files share (its frames, the open tab, the alt or gathering page
-- shown). Sizes are WindowState.lua's, the design's (design\facelift.md 3.1).
local _, ns = ...
if not ns.ok then return end

local API = ns.API
local Doc, Pages, Calc, Craft = ns.Doc, ns.Pages, ns.Calc, ns.Craft
local State = ns.WinState
local S = ns.state
local L = ns.L
local Color, Hex, Text, DiffColor = Doc.Color, Doc.Hex, Doc.Text, Doc.DiffColor
local Pad = ns.Pad     -- the window on a controller (Guide.lua)

local W = {}
ns.Win = W
W.tab = "recipes"      -- the open tab
W.alt = nil            -- { guid, line } while an alt's profession is shown
W.gather = nil         -- the game's skill line of a gathering profession of yours while its page
                       -- is shown (W.CAMP: the camping page, every profession's camping items)
W.CAMP = "camp"
W.col = State.W        -- the column's width now (the tab row's: Window.lua)

local List = {}
ns.WinList = List

local ROW = State.ROW
local PAD = State.PAD

-- The window's saved state (DaylightRecipesDB.win), made fit for this layout (WindowState.lua).
function W.DB()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	db.win = type(db.win) == "table" and db.win or {}
	State.Migrate(db.win)
	return db.win
end
local DB = W.DB

local function TS(name, ...)
	return Craft.TS(name, ...)
end

function W.Linked() return S.linked == true end
local Linked = W.Linked

-- Your own profession is open in the window (not someone's linked recipes, not an alt's page, not
-- a gathering page).
function W.Own()
	return S.mode == "win" and not Linked() and not W.alt and not W.gather
end

-- Rolled up now: the player's choice (kept in DB().rolled), while there is a craft bar to roll up
-- to (List.CanRoll) and no tour is showing the window. With nothing to craft (someone's linked
-- recipes, no profession open) a rolled-up window would be a header over an empty bar: it shows
-- unrolled then, and the choice is neither lost nor saved over.
function W.Rolled()
	if DB().rolled ~= true then return false end
	if ns.Window and ns.Window.tourRaised then return false end
	return List.CanRoll()
end

function W.Wash(parent, layer, a)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(1, 1, 1, a or 0.05)
	return t
end
local Wash = W.Wash

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
		-- (Blizzard Style without Daylight UI: a check box, WindowBlizzard.lua.)
		if W.Blz then W.Blz.Toggle(b, on) end
	end
	b:SetScript("OnEnter", b.Paint)
	b:SetScript("OnLeave", b.Paint)
	b:SetScript("OnClick", function()
		DB()[key] = not DB()[key] or nil
		b.Paint()
		ns.Window.Dirty()
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
local listFrame, listRows, listThumb

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

-- seek: a recipe to scroll to once the list is built (the one last picked in this profession).
local seek
local ApplySeek          -- (below ClampOffset: scrolls to the recipe List.Reset was given)

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
	local anyLearned, pickedKnown = false, false
	for _, id in ipairs(AllRecipeIDs()) do
		local info = TS("GetRecipeInfo", id)
		if type(info) == "table" and info.learned and not info.isDummyRecipe and info.name then
			anyLearned = true
			if id == S.recipe then pickedKnown = true end
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
				-- (can: it can still give a point, as the game says; the Blizzard Layout's arrow.)
				list[#list + 1] = { spell = id, name = info.name, step = rd + 1, count = count,
					ups = info.numSkillUps, can = info.canSkillUp ~= false }
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
	-- The recipe brought back from the last time (Core.lua's ns.LastRecipe), checked once the
	-- profession's recipes are in: one no longer known (unlearned, another rank) is let go.
	if S.recipeRestored and anyLearned then
		S.recipeRestored = nil
		if not pickedKnown then S.recipe, seek = nil, nil end
	end
	-- Nothing picked yet (a profession just opened): its first recipe, as the game does.
	if not S.recipe and first then
		S.recipe = first
		ns.Window.RecipeChanged()
	end
	if anyLearned and ApplySeek then ApplySeek() end
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

ApplySeek = function()
	local spell = seek
	seek = nil
	if not spell then return end
	for i, e in ipairs(entries) do
		if e.spell == spell then
			local shown = VisibleRows()
			if i > shown then offset = i - math.floor(shown / 2) end
			ClampOffset()
			return
		end
	end
end

-- On a controller the list scrolls under the cursor: the D-pad past its first or last row moves it
-- a row (the cursor stays on that row), and the right stick scrolls it (listPad: a stand-in scroll
-- frame, Guide.lua's Pad.Scroller).
local listPad
local stickMoving = false   -- the stick moved it: its stand-in keeps the stick's own position
local PaintList

-- The list as the game's scroll bar sees it (WindowBlizzard.lua's Blz.Thumb): in rows' heights,
-- its offset a row at a time.
local scrollCtl = {
	range = function() return math.max(0, #entries - VisibleRows()) * ROW end,
	at = function() return offset * ROW end,
	set = function(v)
		local to = math.floor(v / ROW + 0.5)
		if to == offset then return end
		offset = to
		PaintList()
	end,
	view = function() return VisibleRows() * ROW end,
	step = ROW,
}

local function PaintThumb()
	local n, shown = #entries, VisibleRows()
	if n <= shown then
		listThumb:Hide()
		if W.Blz then W.Blz.Thumb(listThumb, listFrame, scrollCtl) end
		return
	end
	local h = listFrame:GetHeight()
	local size = math.max(24, h * shown / n)
	listThumb:SetHeight(size)
	listThumb:ClearAllPoints()
	listThumb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -((h - size) * offset / (n - shown)))
	listThumb:SetColorTexture(API.Accent())
	listThumb:SetAlpha(0.5)
	listThumb:Show()
	-- (Blizzard Style without Daylight UI: the game's own scroll bar in its place, WindowBlizzard.lua.)
	if W.Blz then W.Blz.Thumb(listThumb, listFrame, scrollCtl) end
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
	-- (The guide's step, ours or Professionally Lost's: a square that stays when the glow is off.)
	r.step = r:CreateTexture(nil, "ARTWORK")
	r.step:SetSize(6, 6)
	r.step:SetPoint("LEFT", r, "LEFT", 11, 0)
	r.step:Hide()
	r.sign = Text(r, "body")
	r.sign:SetPoint("LEFT", r, "LEFT", 8, 0)
	r.sign:SetWidth(12)
	-- The name at the list's size (13), and at the next size down (12) for one too long for the row
	-- at 13: PaintList shows whichever fits (FontString:IsTruncated, Blizzard_APIDocumentation
	-- Generated/SimpleFontStringAPIDocumentation.lua:442).
	r.name = Text(r, "body")
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.nameSmall = Text(r, "small")
	r.nameSmall:SetJustifyH("LEFT")
	r.nameSmall:SetWordWrap(false)
	r.nameSmall:Hide()
	r.right = Text(r, "small", "RIGHT")
	r.right:SetPoint("RIGHT", r, "RIGHT", -10, 0)
	-- (What it makes would be a gear upgrade for you, by Glowey's Gear: the game's own upgrade
	-- arrow, as on a bag slot. Atlas "bags-greenarrow": the game's ContainerFrame.xml:104.)
	r.up = r:CreateTexture(nil, "OVERLAY")
	r.up:SetSize(12, 12)
	if not pcall(r.up.SetAtlas, r.up, "bags-greenarrow") then r.up:SetColorTexture(0.3, 0.9, 0.3, 1) end
	r.up:Hide()
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
			ns.Window.Dirty()
			return
		end
		if IsModifiedClick("CHATLINK") then
			local link = TS("GetRecipeLink", e.spell)
			if link then ns.InsertLink(link) end
			return
		end
		ns.Window.Select(e.spell)
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

-- The recipe the guide is on, for the list's mark and glow: Plan.CurrentSpell, which is our own
-- route's step, or, for a profession whose Leveling Guide is handed to Professionally Lost, the
-- recipe its guide is on while "Light Up Its Step" is on (ns.ProfLost.Handed("step", line) and
-- NextStepSpell(line), asked there), and nothing when that is off. Only your own open profession.
local function StepSpell()
	if not W.Own() then return nil end
	return ns.Plan and ns.Plan.CurrentSpell() or nil
end
List.StepSpell = StepSpell

local gearWatched = false
PaintList = function()
	if not listFrame then return end
	if listDirty then BuildList() end
	ClampOffset()
	local shown = VisibleRows()
	listRows = listRows or {}
	local best = ns.Tips and ns.Tips.Best and ns.Get("marks") and ns.Tips.Best() or nil
	-- (Glowey's Gear's word on what each recipe makes: asked only for your own profession's
	-- list. Its answers change with your gear: the list is painted again when they do.)
	local gearUp = W.Own() and ns.Tips and ns.Tips.GearUp or nil
	if gearUp and not gearWatched then
		gearWatched = true
		ns.Tips.GearWatch(function()
			if listFrame and listFrame:IsVisible() and not listDirty then PaintList() end
		end)
	end
	-- The guide's current recipe, lit wherever its row is (rows are reused as it scrolls).
	local step = StepSpell()
	local glow = Doc.GlowStyle() and step or nil
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
		local lit = e ~= nil and i <= shown and not e.cat and e.spell == glow
		if lit then
			Doc.Glow(r, true, Doc.DiffColor(math.max(1, math.min(4, tonumber(e.step) or 2))))
		else
			Doc.Glow(r, false)
		end
		if not e or i > shown then
			r:Hide()
		else
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * ROW)
			r:SetPoint("RIGHT", listFrame, "RIGHT", -6, 0)
			r.name:ClearAllPoints()
			r.nameSmall:Hide()
			r.name:Show()
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
				r.right:Show()
				r.ground:SetColorTexture(1, 1, 1, 0.03)
				r.ground:Show()
				r.mark:Hide()
				r.step:Hide()
				r.up:Hide()
			else
				r.sign:Hide()
				local right = e.count > 0 and ("[" .. e.count .. "]") or ""
				r.right:SetText(right)
				r.right:SetTextColor(Color("VALUE"))
				local dr, dg, db = DiffColor(math.min(4, math.max(1, e.step)))
				-- The upgrade arrow sits before the count; the name ends at whichever comes first.
				local up = gearUp and gearUp(e.spell) or false
				local edge, gap = r.right, -6
				r.up:ClearAllPoints()
				if up then
					r.up:SetPoint("RIGHT", r.right, "LEFT", right ~= "" and -4 or 0, 0)
					r.up:Show()
					edge, gap = r.up, -4
				else
					r.up:Hide()
				end
				r.name:SetPoint("LEFT", r, "LEFT", 22, 0)
				r.name:SetPoint("RIGHT", edge, "LEFT", gap, 0)
				r.name:SetText(e.name)
				r.name:SetTextColor(dr, dg, db)
				r.right:Show()
				if r.name:IsTruncated() then
					r.name:Hide()
					r.nameSmall:ClearAllPoints()
					r.nameSmall:SetPoint("LEFT", r, "LEFT", 22, 0)
					r.nameSmall:SetPoint("RIGHT", edge, "LEFT", gap, 0)
					r.nameSmall:SetText(e.name)
					r.nameSmall:SetTextColor(dr, dg, db)
					r.nameSmall:Show()
					-- (Still too long at 12, in a wide font: the count gives its room to the name;
					-- how many you can make is on the craft bar's Max for the picked recipe.)
					if r.nameSmall:IsTruncated() then
						r.right:Hide()
						r.nameSmall:ClearAllPoints()
						r.nameSmall:SetPoint("LEFT", r, "LEFT", 22, 0)
						if up then
							r.up:ClearAllPoints()
							r.up:SetPoint("RIGHT", r, "RIGHT", -10, 0)
							r.nameSmall:SetPoint("RIGHT", r.up, "LEFT", -4, 0)
						else
							r.nameSmall:SetPoint("RIGHT", r, "RIGHT", -10, 0)
						end
					end
				end
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
				if e.spell == step then
					r.step:SetColorTexture(ar, ag, ab, 1)
					r.step:Show()
				else
					r.step:Hide()
				end
			end
			r:Show()
		end
		-- (Blizzard Style without Daylight UI: the list's header and row art, WindowBlizzard.lua.)
		if W.Blz then W.Blz.Row(r, (e and i <= shown) and e or nil) end
		-- (Blizzard Layout: the game's skill-up arrow and the count after the name, WindowLayout.lua.)
		if W.Lay then W.Lay.Row(r, (e and i <= shown) and e or nil) end
	end
	-- Rows made for a taller list are put away. The list gets shorter by a drag of the window's
	-- edge, the Window Height setting, a taller summary line, a second row of the craft bar or an
	-- enchant's item row; a row left on show would lie over the summary line and the craft bar
	-- and take their clicks. (Hidden, not clipped: SetClipsChildren on the list would also trim
	-- the guide's light round a row at the list's edge.)
	for i = shown + 2, #listRows do
		local r = listRows[i]
		r.entry = nil
		Doc.Glow(r, false)
		r:Hide()
	end
	PaintThumb()
	if listPad and not stickMoving then listPad.Sync() end
end
List.Paint = function() PaintList() end


function List.Dirty() listDirty = true end

-- A profession just opened: the list from its top.
function List.Reset(spell)
	listDirty = true
	offset = 0
	seek = type(spell) == "number" and spell or nil
end

function List.Count()
	if listDirty then BuildList() end
	return #entries
end

-- Scrolls the list so a recipe shows (after a pick from the Leveling Guide or the queue).
function List.ShowInList(spell)
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

-- The row a controller's cursor starts on: the picked recipe's, else the first.
function List.FirstStop()
	if not (listFrame and listFrame:IsVisible() and listRows) then return nil end
	for _, r in ipairs(listRows) do
		if r:IsShown() and r.entry and r.entry.spell and r.entry.spell == S.recipe then return r end
	end
	if listRows[1] and listRows[1]:IsShown() then return listRows[1] end
	return nil
end

-- The stand-in scroll frame for a controller's right stick (made once, by Window.lua's pad setup).
function List.PadScroller()
	if listPad then return listPad end
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
	return listPad
end

local searchSerial = 0
function W.Debounce(fn)
	searchSerial = searchSerial + 1
	local serial = searchSerial
	C_Timer.After(0.15, function()
		if serial == searchSerial then fn() end
	end)
end

-- The search box, the two filters and the list, in `body` (the column under the tabs). The search
-- and filters are placed here; the list's top too, its bottom by Window.lua (it ends at the summary
-- line or the craft bar).
function List.Build(body)
	local search = API.Input(body, { search = true, hint = L["Search recipes"],
		onChange = function(text)
			text = ns.Fold(text)
			if text == filterText then return end
			filterText = text
			W.Debounce(function()
				offset = 0
				ns.Window.Dirty()
			end)
		end })
	search:SetPoint("TOPLEFT", body, "TOPLEFT", PAD - 2, -8)
	search:SetPoint("RIGHT", body, "RIGHT", -(PAD - 2), 0)
	W.search = search
	W.filters = { Toggle(body, L["Can Make"], "canMake"), Toggle(body, L["Skill-ups"], "skillUps") }
	W.filters[1]:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -4)
	W.filters[2]:SetPoint("LEFT", W.filters[1], "RIGHT", 4, 0)

	listFrame = CreateFrame("Frame", nil, body)
	listFrame:EnableMouseWheel(true)
	listFrame:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		PaintList()
	end)
	listFrame:SetScript("OnSizeChanged", function() PaintList() end)
	listThumb = listFrame:CreateTexture(nil, "OVERLAY")
	listThumb:SetWidth(3)
	listThumb:Hide()
	W.list = listFrame
	return listFrame
end

-- Where the list starts under the body's top: the search (its own height), the filters (20) and
-- the gaps of the grid.
function List.Top()
	local sh = W.search and W.search:GetHeight() or 24
	return 8 + (sh > 0 and sh or 24) + 4 + 20 + 4
end

-- Where a page starts under a search box alone (the Missing tab's, an alt's recipes'): the box
-- and the grid's gaps.
function List.UnderSearch(box)
	local sh = box and box:GetHeight() or 24
	return 8 + (sh > 0 and sh or 24) + 6
end

-- ---------------------------------------------------------------------------------------------
-- The picked recipe's page (the detail column)
-- ---------------------------------------------------------------------------------------------

-- A link into the open chat box, through the game's own call (ChatFrameUtil.InsertLink; the old
-- ChatEdit_InsertLink only lives in the game's deprecated-API addon). True when it went in.
function ns.InsertLink(link)
	if not link then return false end
	local U = _G.ChatFrameUtil
	if U and type(U.InsertLink) == "function" then return U.InsertLink(link) and true or false end
	if type(_G.ChatEdit_InsertLink) == "function" then return _G.ChatEdit_InsertLink(link) and true or false end
	return false
end

local function Cooldown(spell)
	local cd = TS("GetRecipeCooldown", spell)
	if type(cd) ~= "number" or cd <= 0 then return nil end
	if cd >= 3600 then return L["Ready in %d h %d min"]:format(math.floor(cd / 3600), math.floor(cd % 3600 / 60)) end
	return L["Ready in %d min"]:format(math.max(1, math.floor(cd / 60)))
end

function List.DetailPage(d)
	local spell = S.recipe
	-- (On the Leveling Guide: the recipe its current step makes, when the game has it.)
	if W.tab == "guide" then
		local step = StepSpell()
		local info = step and TS("GetRecipeInfo", step)
		if type(info) == "table" and info.name then spell = step end
	end
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
	local who = ns.Store and ns.Store.WhoKnows(spell, false, true)
	if type(who) == "table" and #who > 0 then
		d:Heading(L["Also Known By"])
		d:Line(table.concat(who, ", "), "small", "TEXT")
	end
end

-- ---------------------------------------------------------------------------------------------
-- The summary line
-- ---------------------------------------------------------------------------------------------
-- The picked recipe's headline above the craft bar: its name and chance of a point, then what its
-- materials cost and what it sells for. A press opens the details (or closes them). Its texts wrap
-- rather than being cut, and the line is as tall as they are (40 for one line each).

local summary

function List.BuildSummary(body)
	local b = CreateFrame("Button", nil, body)
	b:SetHeight(State.SUMMARY)
	local line = b:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", 0, 0)
	line:SetColorTexture(1, 1, 1, 0.06)
	b.wash = Wash(b, "BACKGROUND", 0.05)
	b.wash:SetAllPoints()
	b.wash:Hide()
	b.right = Text(b, "body", "RIGHT")
	b.right:SetPoint("TOPRIGHT", b, "TOPRIGHT", -PAD, -5)
	b.right:SetWordWrap(false)
	b.name = Text(b, "body")
	b.name:SetJustifyH("LEFT")
	b.name:SetWordWrap(true)
	b.name:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -5)
	b.sub = Text(b, "small")
	b.sub:SetJustifyH("LEFT")
	b.sub:SetWordWrap(true)
	b:SetScript("OnEnter", function(self) self.wash:Show() end)
	b:SetScript("OnLeave", function(self) self.wash:Hide() end)
	b:SetScript("OnClick", function() ns.Window.ToggleDetails() end)
	summary = b
	W.summary = b
	return b
end

-- Filled for the picked recipe; returns its height (0 while hidden).
function List.PaintSummary(show)
	local b = summary
	if not b then return 0 end
	local spell = S.recipe
	if not show or not spell or S.mode ~= "win" then
		b:Hide()
		return 0
	end
	local width = W.col
	local chance, _, state = Calc.Chance(spell, S.skill or 0, S.max)
	if state ~= "unknown" and not Linked() then
		local step = Calc.Step(spell) or 4
		b.right:SetText(L["%s chance"]:format(Doc.Pct(chance)))
		b.right:SetTextColor(DiffColor(math.min(4, math.max(1, step))))
	else
		b.right:SetText("")
	end
	local rw = math.ceil(b.right:GetStringWidth())
	b.name:SetWidth(math.max(40, width - 2 * PAD - (rw > 0 and rw + 10 or 0)))
	b.name:SetText(Doc.RecipeName(spell))
	b.name:SetTextColor(Color("VALUE"))
	local parts = {}
	local cost = Calc.Cost(spell)
	if type(cost) == "table" and #cost.rows > 0 then
		parts[#parts + 1] = L["Materials: %s"]:format(Calc.Money(cost.total))
	end
	local worth = Calc.Worth(spell)
	local sale = type(worth) == "table" and worth.routes[1] or nil
	if sale and sale.label ~= "Disenchant" then
		parts[#parts + 1] = L["Sells for %s"]:format(Calc.Money(sale.value))
	end
	local nameH = math.ceil(b.name:GetStringHeight())
	b.sub:ClearAllPoints()
	b.sub:SetPoint("TOPLEFT", b, "TOPLEFT", PAD, -(5 + nameH + 2))
	b.sub:SetWidth(math.max(40, width - 2 * PAD))
	b.sub:SetText(table.concat(parts, " · "))
	b.sub:SetTextColor(Color("TEXT"))
	local subH = #parts > 0 and math.ceil(b.sub:GetStringHeight()) or 0
	local h = math.max(State.SUMMARY, 5 + nameH + 2 + subH + 6)
	b:SetHeight(h)
	b:Show()
	return h
end

-- ---------------------------------------------------------------------------------------------
-- The craft bar
-- ---------------------------------------------------------------------------------------------

local BAR = State.FOOT
local LIFT = 32                     -- how far above the bottom row the second row sits
local craftBar, countBox
local PaintCraftBar

-- The bar's buttons fitted to their words (longer in some languages), never narrower than the
-- design's widths. When they don't fit one row of the column, the count and Queue go on a row of
-- their own above (true: two rows). The sum is WindowState's, so the tests check it.
-- The buttons' own places on the bar (as the bar is built). Put back on each fit: the Blizzard
-- Layout lays them out its own way (WindowLayout.lua's FitBar), and a switch back or a run under
-- way finds them here again.
function List.AnchorBar(cb)
	cb.make:ClearAllPoints()
	cb.make:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	cb.max:ClearAllPoints()
	cb.max:SetPoint("RIGHT", cb.make, "LEFT", -8, 0)
	cb.plus:ClearAllPoints()
	cb.plus:SetPoint("RIGHT", cb.max, "LEFT", -8, 0)
	countBox:ClearAllPoints()
	countBox:SetPoint("RIGHT", cb.plus, "LEFT", -4, 0)
	cb.minus:ClearAllPoints()
	cb.minus:SetPoint("RIGHT", countBox, "LEFT", -4, 0)
	cb.queue:ClearAllPoints()
	cb.queue:SetPoint("RIGHT", cb.minus, "LEFT", -8, 0)
end

local function FitButtons(cb)
	List.AnchorBar(cb)
	-- (Blizzard Layout: Create All, the count and Create on the game's places; nil when it isn't
	-- on, or the bar shows a run's buttons.)
	local laid = W.Lay and W.Lay.FitBar(cb, countBox)
	if laid ~= nil then return laid end
	local least = State.LEAST
	cb.make.FitWidth(least.make)
	cb.max.FitWidth(least.max)
	cb.queue.FitWidth(least.queue)
	cb.stop.FitWidth(least.stop)
	local two = State.CraftBarTwoRows({ make = cb.make:GetWidth(), max = cb.max:GetWidth(), plus = cb.plus:GetWidth(),
		count = countBox:GetWidth(), minus = cb.minus:GetWidth(), queue = cb.queue:GetWidth() }, W.col)
	cb.plus:ClearAllPoints()
	if two then
		cb.plus:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2 + LIFT)
	else
		cb.plus:SetPoint("RIGHT", cb.max, "LEFT", -8, 0)
	end
	return two
end

-- The secure Stop kept honest for what the bar draws now (WindowState.StopAction says what to do;
-- Craft.lua says why it can only be moved out of a fight). wanted: the bar's Stop is showing.
local function SyncStop(wanted)
	local cb = craftBar
	if not cb then return end
	local same = wanted and State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect()) or false
	local act = State.StopAction(InCombatLockdown(), Craft.StopShown(), wanted, same)
	cb.stop.SetOff(false)
	if act == "place" then
		Craft.PlaceStop(cb.stop)
	elseif act == "hide" then
		Craft.PlaceStop(nil)
	elseif act == "keep" then
		Craft.StopFace(false)
	elseif act == "face" then
		-- (The secure Stop is somewhere else and can't come here in a fight: it shows its own face
		-- there, and the bar draws no Stop that a click would not reach.)
		cb.stop:Hide()
		Craft.StopFace(true)
	elseif wanted then
		-- (A craft begun in a fight: no secure Stop can be brought. The bar's Stop is drawn off.)
		cb.stop.SetOff(true)
	end
end
List.SyncStop = SyncStop

local function CountWanted()
	local n = tonumber(countBox and countBox:GetText() or "") or 1
	return math.max(1, math.floor(n))
end

-- The crafting queue's next entry for the open profession (your own), as the Queue tab's Craft
-- Next takes it: the entry, or nil.
local function QueueNext()
	if not W.Own() or not ns.Queue or not ns.Queue.NextHere then return nil end
	return (ns.Queue.NextHere())
end

-- The recipe the bar is for: the one being made while a run is under way (on any tab); rolled up,
-- the queue's next for this profession when it has one (WindowState.RolledBar: the rolled-up
-- window says what its bar acts on, the queue before the pick); else the picked one.
local function BarSpell()
	local run = Craft.Making()
	if run then return run.spell end
	if W.Rolled() then
		local q = QueueNext()
		if q then return q.spell, q end
	end
	return S.recipe
end

-- Whether the bar shows: your own profession with a recipe, on the Recipes tab or rolled up
-- (rolled up also with nothing picked but something queued for it); a run under way, on any tab;
-- a secure Stop a fight is keeping out.
local function BarShown(held)
	if held or Craft.Making() then return true end
	if not W.Own() then return false end
	if W.Rolled() then return S.recipe ~= nil or QueueNext() ~= nil end
	return S.recipe ~= nil and W.tab == "recipes"
end

-- Whether there is a craft bar to roll the window up to (BarShown's rule for a rolled-up window):
-- a run under way, a secure Stop a fight keeps out, or your own profession with a recipe picked
-- or one queued.
function List.CanRoll()
	if Craft.Making() or (InCombatLockdown() and Craft.StopShown()) then return true end
	return W.Own() and (S.recipe ~= nil or QueueNext() ~= nil)
end

-- Rolled up, the bar's own line: what it acts on (the queue's next, or the picked recipe). A press
-- unrolls the window onto the tab that has it. text; own: on a line of its own above the buttons
-- (the picked recipe: the buttons take the whole row), else at the row's left beside the one
-- button (the queue's next), `room` wide. Wrapped, never cut: returns how much taller the bar is for it.
local function PaintWhat(cb, text, ink, own, room, top, tab)
	local what = cb.what
	if not text then
		what:Hide()
		return 0
	end
	what.tab = tab
	what.text:SetText(text)
	what.text:SetTextColor(Color(ink))
	what.ink = ink
	local wide = math.max(60, room)
	what.text:SetWidth(wide)
	local high = math.max(16, math.ceil(what.text:GetStringHeight() or 16))
	what:SetSize(wide + 12, high + 4)
	what:ClearAllPoints()
	what:Show()
	if own then
		what:SetPoint("TOPLEFT", cb, "TOPLEFT", PAD - 6, -(top + 6))
		return high + 8
	end
	-- (Beside the button, centered on the buttons' row; a name of three lines or more lifts the bar.)
	local extra = math.max(0, high + 4 - (BAR - 8))
	what:SetPoint("LEFT", cb, "BOTTOMLEFT", PAD - 6, BAR / 2 + extra / 2)
	return extra
end

-- The width the craft bar's one row asks of the column, with its words at their reserved longest:
-- the longer of Create and Enchant, "Max 999", Queue. Window.lua sizes the column from it
-- (WindowState.Column) before the bar is painted, so the bar is one row in every language a
-- column of up to 520 holds it in, and the column does not change with the pick. (It sets the
-- buttons' words to measure them: PaintCraftBar, which Window.lua's Render calls next, sets the
-- ones that show.)
function List.CraftBarNeed()
	local cb = craftBar
	if not cb then return nil end
	local least = State.LEAST
	local function Wide(b, text, min)
		b.text:SetText(text)
		b.FitWidth(min)
		return b:GetWidth()
	end
	local make = math.max(Wide(cb.make, L["Create"], least.make), Wide(cb.make, L["Enchant"], least.make))
	local max = Wide(cb.max, L["Max %d"]:format(999), least.max)
	local queue = Wide(cb.queue, L["Queue"], least.queue)
	return State.CraftBarNeed({ make = make, max = max, plus = cb.plus:GetWidth(), count = countBox:GetWidth(),
		minus = cb.minus:GetWidth(), queue = queue })
end

-- The progress line: 2 px in the accent along the bar's top edge, as wide as the run is far.
local function PaintProgress(cb)
	local p = Craft.Progress()
	if not p then
		cb.prog:Hide()
		cb.progBack:Hide()
		return
	end
	local w = cb:GetWidth()
	if not w or w <= 0 then w = W.col end
	cb.progBack:Show()
	cb.prog:SetColorTexture(API.Accent())
	cb.prog:SetWidth(math.max(1, w * p))
	cb.prog:Show()
end

PaintCraftBar = function()
	if not craftBar then return 0 end
	local cb = craftBar
	local making = Craft.Making()
	-- (A Stop that can't be put away in a fight stays drawn where it is, so what you see is what
	-- a click does.)
	local held = InCombatLockdown() and Craft.StopShown()
	if not BarShown(held) then
		cb:Hide()
		SyncStop(false)
		return 0
	end
	cb:Show()
	local spell, nextUp = BarSpell()
	local rolled = W.Rolled()
	local info = spell and TS("GetRecipeInfo", spell) or nil
	local enchant = type(info) == "table" and info.isEnchantingRecipe == true
	local verb = type(info) == "table" and info.alternateVerb
	if type(verb) ~= "string" or verb == "" then verb = enchant and L["Enchant"] or L["Create"] end
	local can = spell and Craft.Count(spell) or 0
	local blocked = type(info) == "table" and info.disabled == true
	-- An enchant: its item row above the buttons (the item it goes on, Auto-replace).
	local ench = cb.ench
	local base = BAR
	if enchant then
		ench:Show()
		ench:Update(spell, W.col)
		-- (As tall as its item's name and hint wrap to: 46 for a line each. EnchantRow.lua)
		base = BAR + ench:GetHeight()
	else
		ench:Hide()
		ench.target = nil
	end
	cb:SetHeight(base)
	cb.what:Hide()
	-- Rolled up, the queue's count on the left (a press unrolls onto the Queue tab). Not while the
	-- bar is for the queue's next itself: its own line says what waits.
	local queued = rolled and not nextUp and ns.Queue and ns.Queue.Count() or 0
	if queued > 0 then
		cb.queued.text:SetText(L["Queue (%d)"]:format(queued))
		cb.queued:SetWidth(math.ceil(cb.queued.text:GetStringWidth()) + 12)
		cb.queued:Show()
	else
		cb.queued:Hide()
	end
	PaintProgress(cb)
	cb:SetScript("OnUpdate", (making or Craft.StopShown()) and cb.Tick or nil)
	-- An enchant run between two enchants: Next (one enchant a click) and Done in place of the buttons.
	if making and making.paused then
		cb.stop:Hide()
		SyncStop(false)
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.status:SetText(L["%d of %d done"]:format(making.done, making.count))
		cb.status:ClearAllPoints()
		cb.status:SetPoint("RIGHT", cb.max, "LEFT", -12, 0)
		cb.status:SetTextColor(Color("LABEL"))
		cb.status:Show()
		cb.make.text:SetText(L["Next (%d Left)"]:format(making.count - making.done))
		if ns.Guide then ns.Guide.Offer("enchant") end
		cb.make.SetOff(false)
		cb.make:Show()
		cb.max.text:SetText(L["Done"])
		cb.max.SetOff(false)
		cb.max:Show()
		FitButtons(cb)
		List.FitStatus(cb, cb.max)
		return base
	end
	if making or held then
		if making then
			local words = L["Making %d of %d"]:format(math.min(making.done + 1, making.count), making.count)
			-- (Rolled up nothing else names the recipe: the status does.)
			if rolled and making.spell then words = Doc.RecipeName(making.spell) .. " · " .. words end
			cb.status:SetText(words)
		else
			cb.status:SetText(L["Stopped"])
		end
		cb.status:SetTextColor(API.Accent())
		cb.status:Show()
		cb.status:ClearAllPoints()
		cb.status:SetPoint("RIGHT", cb.stop, "LEFT", -12, 0)
		cb.make:Hide()
		cb.max:Hide()
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.stop:Show()
		FitButtons(cb)
		List.FitStatus(cb, cb.stop)
		SyncStop(true)
		return base
	end
	cb.status:Hide()
	cb.stop:Hide()
	SyncStop(false)
	-- Rolled up with something queued for this profession: the bar is the queue's next (the Queue
	-- tab's Craft Next, in less space): what it is and how many wait behind it, and one button.
	if rolled and nextUp then
		local model = State.RolledBar(false, { count = nextUp.count, can = can, blocked = blocked }, nil)
		cb.queue:Hide()
		countBox:Hide()
		cb.minus:Hide()
		cb.plus:Hide()
		cb.max:Hide()
		cb.make.text:SetText(L["Craft Next"])
		cb.make.FitWidth(State.LEAST.make)
		cb.make.SetOff(model.off)
		cb.make:Show()
		local words = L["Queue: %s x %d"]:format(Doc.RecipeName(nextUp.spell), nextUp.count)
		local more = (ns.Queue.Count() or 1) - 1
		if more > 0 then words = words .. " · " .. L["and %d more"]:format(more) end
		if model.short then words = words .. "\n" .. L["Short of Materials"] end
		local room = W.col - PAD - cb.make:GetWidth() - 12 - PAD
		local h = base + PaintWhat(cb, words, model.short and "WARN" or "VALUE", false, room, 0, "queue")
		cb:SetHeight(h)
		return h
	end
	cb.make.text:SetText(verb)
	cb.make:Show()
	cb.queue:Show()
	countBox:Show()
	cb.minus:Show()
	cb.plus:Show()
	cb.max:Show()
	-- "Max" puts all you can make into the count (what Create All did in one press, in two).
	cb.max.text:SetText(can > 0 and L["Max %d"]:format(can) or L["Max"])
	local h = base
	if FitButtons(cb) then
		h = base + LIFT
		cb:SetHeight(h)
	end
	-- (Rolled up: the picked recipe's name on a line of its own over the buttons, which take the
	-- whole row; the bar is that line taller. Never an anonymous bar.)
	if rolled and spell then
		local grown = PaintWhat(cb, Doc.RecipeName(spell), "VALUE", true, W.col - 2 * PAD, 0, "recipes")
		if enchant then
			-- (An enchant's item row goes under the name.)
			ench:ClearAllPoints()
			ench:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, -grown)
			ench:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, -grown)
		end
		h = h + grown
		cb:SetHeight(h)
	elseif enchant then
		ench:ClearAllPoints()
		ench:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
		ench:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)
	end
	-- (An enchant with no item yet: the game would ask for a click on one, once; with one kept,
	-- as many as asked go on it.)
	local noItem = enchant and not ench.target
	cb.make.SetOff(blocked or can < 1)
	cb.max.SetOff(blocked or can < 1 or noItem)
	-- (Rolled up with the queue's count: it gives way when the buttons need the row.)
	if cb.queued:IsShown() then
		local need = State.CraftBarNeed({ make = cb.make:GetWidth(), max = cb.max:GetWidth(), plus = cb.plus:GetWidth(),
			count = countBox:GetWidth(), minus = cb.minus:GetWidth(), queue = cb.queue:GetWidth() })
		if need + cb.queued:GetWidth() + 8 > W.col then cb.queued:Hide() end
	end
	return h
end
List.PaintCraftBar = function() return PaintCraftBar() end

-- The status words ("Making 3 of 12") left of `anchor`, and the queue's count left of them: the
-- count gives way first when the column has no room for both, and the status wraps onto two lines
-- rather than being cut.
function List.FitStatus(cb, anchor)
	local room = W.col - PAD - anchor:GetWidth() - 12 - PAD
	if cb.make:IsShown() and anchor ~= cb.make then room = room - cb.make:GetWidth() - 8 end
	local sw = math.ceil(cb.status:GetUnboundedStringWidth())
	if cb.queued:IsShown() and sw + 12 + cb.queued:GetWidth() > room then cb.queued:Hide() end
	cb.status:SetWidth(math.max(40, math.min(sw + 2, room)))
end

function List.BuildCraftBar(parent)
	local cb = CreateFrame("Frame", nil, parent)
	cb:SetHeight(BAR)
	local line = cb:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", 0, 0)
	line:SetColorTexture(1, 1, 1, 0.06)
	-- The progress line: our own 2 px in the accent (no cast-bar art), over a faint track.
	cb.progBack = cb:CreateTexture(nil, "ARTWORK", nil, 1)
	cb.progBack:SetHeight(2)
	cb.progBack:SetPoint("TOPLEFT", 0, 0)
	cb.progBack:SetPoint("TOPRIGHT", 0, 0)
	cb.progBack:SetColorTexture(1, 1, 1, 0.08)
	cb.progBack:Hide()
	cb.prog = cb:CreateTexture(nil, "ARTWORK", nil, 2)
	cb.prog:SetHeight(2)
	cb.prog:SetPoint("TOPLEFT", 0, 0)
	cb.prog:Hide()
	-- While something is being made (or a fight keeps the secure Stop out): the line follows the
	-- cast, and the secure Stop follows the bar's Stop wherever a move, a resize or a change of
	-- state put it (a fight aside: SyncStop).
	cb.Tick = function(self)
		PaintProgress(self)
		local wanted = self.stop:IsShown()
		if not State.SameRect(Craft.RectOf(self.stop), Craft.StopRect()) then
			if wanted or Craft.StopShown() then SyncStop(wanted) end
		end
	end

	cb.make = API.Button(cb, L["Create"], 24)
	-- (Create in DaylightUI's main-action look, as on its own profession window: 1.8 on.)
	if type(API.MainButton) == "function" then pcall(API.MainButton, cb.make, true) end
	cb.make:SetWidth(State.LEAST.make)
	-- (The buttons sit on the bar's bottom row: an enchant's item row goes above them.)
	cb.make:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	cb.make:SetScript("OnClick", function()
		local run = Craft.Making()
		if run and run.paused then
			Craft.Continue()
			return
		end
		-- (Rolled up with something queued for this profession the bar is the queue's next: made
		-- as the Queue tab's Craft Next makes it, worked out at the press, not from what was drawn.)
		local _, nextUp = BarSpell()
		if nextUp then
			local model = State.RolledBar(false, { count = nextUp.count, can = Craft.Count(nextUp.spell) }, nil)
			if not model.off then Craft.Make(nextUp.spell, model.make) end
			return
		end
		local spell = S.recipe
		if not spell then return end
		-- (An enchant goes on its kept item, as many times as asked: Craft.Make finds it.)
		Craft.Make(spell, CountWanted())
	end)
	cb.max = API.Button(cb, L["Max"], 24)
	cb.max:SetWidth(State.LEAST.max)
	cb.max:SetPoint("RIGHT", cb.make, "LEFT", -8, 0)
	cb.max:SetScript("OnClick", function()
		local run = Craft.Making()
		if run and run.paused then
			Craft.Cancel()
			return
		end
		local spell = S.recipe
		local n = spell and Craft.Count(spell) or 0
		-- (Blizzard Layout: it is Create All, all you can make at once, as the game's; a Shift-click
		-- still puts that many into the count, as Max does.)
		if n > 0 and W.Lay and W.Lay.Active() and not IsShiftKeyDown() then
			Craft.Make(spell, n)
			return
		end
		if n > 0 then countBox:SetText(tostring(n)) end
	end)

	cb.plus = API.Button(cb, "+", 24)
	cb.plus:SetWidth(State.LEAST.plus)
	cb.plus:SetPoint("RIGHT", cb.max, "LEFT", -8, 0)
	countBox = API.Input(cb, { numeric = true })
	countBox:SetSize(State.LEAST.count, 24)
	countBox:SetPoint("RIGHT", cb.plus, "LEFT", -4, 0)
	countBox:SetText("1")
	countBox:SetJustifyH("CENTER")
	cb.count = countBox
	cb.minus = API.Button(cb, "-", 24)
	cb.minus:SetWidth(State.LEAST.minus)
	cb.minus:SetPoint("RIGHT", countBox, "LEFT", -4, 0)
	local function Step(by)
		local n = math.max(1, CountWanted() + by)
		countBox:SetText(tostring(n))
	end
	cb.plus:SetScript("OnClick", function() Step(IsShiftKeyDown() and 10 or 1) end)
	cb.minus:SetScript("OnClick", function() Step(IsShiftKeyDown() and -10 or -1) end)

	cb.queue = API.Button(cb, L["Queue"], 24)
	cb.queue:SetWidth(State.LEAST.queue)
	cb.queue:SetPoint("RIGHT", cb.minus, "LEFT", -8, 0)
	cb.queue:SetScript("OnClick", function()
		local spell = S.recipe
		if not spell or not ns.Queue then return end
		ns.Queue.Add(spell, CountWanted())
	end)

	-- (An enchant's item row: EnchantRow.lua, shared with the docked pane.)
	cb.ench = ns.EnchantRow.New(cb, { pad = PAD, onChange = function() ns.Window.Relayout() end })
	cb.ench:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
	cb.ench:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)

	cb.stop = API.Button(cb, L["Stop"], 24)
	cb.stop:SetWidth(State.LEAST.stop)
	cb.stop:SetPoint("RIGHT", cb, "BOTTOMRIGHT", -PAD, BAR / 2)
	-- (The secure Stop laid over it takes the click: Craft.PlaceStop. A controller's A on it stops
	-- through DaylightUI's own secure button: the window's padKeys.)
	cb.stop:EnableMouse(false)
	cb.stop:Hide()
	cb.status = Text(cb, "body", "RIGHT")
	cb.status:SetPoint("RIGHT", cb.stop, "LEFT", -12, 0)
	cb.status:SetWordWrap(true)
	cb.status:Hide()

	-- Rolled up: the queue's count on the left; a press unrolls the window onto the Queue tab.
	cb.queued = CreateFrame("Button", nil, cb)
	cb.queued:SetHeight(24)
	cb.queued:SetPoint("LEFT", cb, "BOTTOMLEFT", PAD - 6, BAR / 2)
	cb.queued.text = Text(cb.queued, "small")
	cb.queued.text:SetPoint("CENTER", 0, 0)
	cb.queued.text:SetTextColor(Color("LABEL"))
	cb.queued:SetScript("OnEnter", function(self) self.text:SetTextColor(Color("VALUE")) end)
	cb.queued:SetScript("OnLeave", function(self) self.text:SetTextColor(Color("LABEL")) end)
	cb.queued:SetScript("OnClick", function()
		ns.Window.SetRolled(false)
		ns.Window.SetTab("queue")
	end)
	cb.queued:Hide()

	-- Rolled up: what the bar acts on (PaintWhat). A press unrolls the window onto its tab.
	cb.what = CreateFrame("Button", nil, cb)
	cb.what.text = Text(cb.what, "body")
	cb.what.text:SetPoint("LEFT", 6, 0)
	cb.what.text:SetJustifyH("LEFT")
	cb.what.text:SetWordWrap(true)
	cb.what:SetScript("OnEnter", function(self) self.text:SetTextColor(Color("ACCENT")) end)
	cb.what:SetScript("OnLeave", function(self) self.text:SetTextColor(Color(self.ink or "VALUE")) end)
	cb.what:SetScript("OnClick", function(self)
		ns.Window.SetRolled(false)
		if self.tab then ns.Window.SetTab(self.tab) end
	end)
	cb.what:Hide()

	craftBar = cb
	W.craftBar = cb
	return cb
end

function List.CountWanted() return CountWanted() end
