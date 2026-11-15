-- Making things from Daylight Recipes' window: Create, Create All, enchanting onto an item, and
-- following the casts until they're done or stopped.
-- The game's own Create buttons are plain buttons calling C_TradeSkillUI.CraftRecipe (and
-- CraftEnchant with the item picked beforehand), so ours do the same. Stopping a cast is the one
-- protected thing (SpellStopCasting): Stop is a secure /stopcasting button of the game's own
-- template, laid over the window's Stop button while something is being made. It's a child of
-- UIParent placed at the same spot on screen, never anchored to the window, so the window stays an
-- ordinary frame you can move and close in a fight.
-- Enchanting for skill: the item an enchant goes on is kept (the last few, per character), so one
-- cheap item can take enchant after enchant; a run of several casts on it is one call, as the game's
-- own Create does for a stack; and, with "Auto-replace" on, the game's "replace the enchant?" question
-- is answered yes during a run of ours on that item (the question comes on every cast after the
-- first, and would stop the run).
local _, ns = ...
if not ns.ok then return end

local Craft = {}
ns.Craft = Craft

local making      -- { spell, count, done } while casts are under way

local function TS(name, ...)
	local fn = C_TradeSkillUI and C_TradeSkillUI[name]
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end
Craft.TS = TS

local function Changed()
	if ns.Window then ns.Window.CraftChanged() end
end

function Craft.Making() return making end

-- How many you can make now from your bags.
function Craft.Count(spell)
	local n = TS("GetCraftableCount", spell)
	return type(n) == "number" and n or 0
end

-- Items an enchant can go on: { { guid, location, name, icon, link }, ... }.
function Craft.Targets(spell)
	local out = {}
	local guids = TS("GetEnchantItems", spell)
	if type(guids) ~= "table" or not C_Item or not C_Item.GetItemLocation then return out end
	for _, guid in ipairs(guids) do
		local ok, loc = pcall(C_Item.GetItemLocation, guid)
		if ok and loc then
			local name = C_Item.GetItemName and C_Item.GetItemName(loc)
			out[#out + 1] = { guid = guid, location = loc, name = name or "?",
				icon = C_Item.GetItemIcon and C_Item.GetItemIcon(loc),
				link = C_Item.GetItemLink and C_Item.GetItemLink(loc) }
		end
	end
	table.sort(out, function(a, b) return ns.NameLess(a.name, b.name) end)
	return out
end

-- ---------------------------------------------------------------------------------------------
-- The items enchants go on
-- ---------------------------------------------------------------------------------------------

local KEEP = 6      -- items remembered (an enchant takes the first of them it can go on)

local function Recent()
	local c = ns.Store and ns.Store.Char()
	if not c then return {} end
	c.enchantTargets = type(c.enchantTargets) == "table" and c.enchantTargets or {}
	return c.enchantTargets
end

-- Whether a recipe is an enchant cast on an item.
function Craft.IsEnchant(spell)
	local info = TS("GetRecipeInfo", spell)
	return type(info) == "table" and info.isEnchantingRecipe == true
end

-- The item this enchant goes on: the most recent kept one it can go on, or nil.
function Craft.EnchantTarget(spell)
	local list = Craft.Targets(spell)
	local byGuid = {}
	for _, t in ipairs(list) do byGuid[t.guid] = t end
	for _, guid in ipairs(Recent()) do
		if byGuid[guid] then return byGuid[guid] end
	end
end

-- Keeps an item as the one enchants go on (first of the kept ones).
function Craft.KeepTarget(guid)
	if type(guid) ~= "string" then return end
	local kept = Recent()
	for i = #kept, 1, -1 do
		if kept[i] == guid then table.remove(kept, i) end
	end
	table.insert(kept, 1, guid)
	for i = #kept, KEEP + 1, -1 do kept[i] = nil end
	Changed()
end

-- No item for this enchant any more (the slot emptied): it goes back to asking.
function Craft.DropTarget(spell)
	local kept = Recent()
	for _, t in ipairs(Craft.Targets(spell)) do
		for i = #kept, 1, -1 do
			if kept[i] == t.guid then table.remove(kept, i) end
		end
	end
	Changed()
end

-- The item on the cursor, kept for this enchant when it can take it: true when it was. The item
-- goes back where it came from either way.
function Craft.TakeFromCursor(spell)
	local cursor = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
	if not cursor or not (cursor.IsValid and cursor:IsValid()) then return false end
	local ok, guid = pcall(C_Item.GetItemGUID, cursor)
	ClearCursor()
	if not ok or type(guid) ~= "string" then return false end
	for _, t in ipairs(Craft.Targets(spell)) do
		if t.guid == guid then
			Craft.KeepTarget(guid)
			return true
		end
	end
	return false
end

function Craft.AutoReplace()
	local db = DaylightRecipesDB
	return not (type(db) == "table" and db.autoReplace == false)
end

function Craft.SetAutoReplace(on)
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	DaylightRecipesDB.autoReplace = on and true or false
	Changed()
end

-- Makes `count` of a recipe, or puts an enchant on an item `count` times (`target`, a
-- { location, guid } from Craft.Targets; for an enchant without one, the kept item it fits).
-- The game's call first, before anything of ours changes (a craft started after the pressed
-- button changed can be refused).
-- A run of enchants on a kept item goes one enchant a click. Every enchant after the first replaces
-- the last, and the game takes the answer to its "replace the enchant?" question only inside a
-- click (from anywhere else: ADDON_ACTION_BLOCKED, seen in game): so after each enchant lands the run
-- waits on "Next", and each click casts one, the question answered right there.
local WAIT = 1.5     -- s for a cast to begin after it's asked for

-- Asks for the next enchant of a run on its item: one at a time (the game's own repeat of an
-- enchant breaks at its replace question and fails the next cast, which would end the run).
local function Step(run)
	if making ~= run then return end
	run.started, run.paused = false, nil
	run.stepAt = GetTime()
	-- (The run is ours before the call: the replace question can come up inside it.)
	local ok = pcall(C_TradeSkillUI.CraftEnchant, run.spell, 1, nil, run.location)
	if not ok then
		making = nil
		Changed()
		return
	end
	Changed()
	C_Timer.After(WAIT, function()
		if making == run and not run.started then
			run.paused = true
			Changed()
		end
	end)
end

function Craft.Make(spell, count, target)
	if making or type(spell) ~= "number" then return false end
	count = math.max(1, math.floor(tonumber(count) or 1))
	local fn = C_TradeSkillUI
	if not fn then return false end
	if not target and Craft.IsEnchant(spell) then target = Craft.EnchantTarget(spell) end
	if target and target.location then
		making = { spell = spell, count = count, done = 0, target = target.guid, location = target.location }
		Step(making)
		return making ~= nil
	end
	local ok
	if Craft.IsEnchant(spell) then
		-- (No item kept: the game asks for a click on one, once.)
		count = 1
		ok = pcall(fn.CraftRecipe, spell, 1)
	else
		ok = pcall(fn.CraftRecipe, spell, count)
	end
	if not ok then return false end
	local run = { spell = spell, count = count, done = 0 }
	making = run
	Changed()
	-- The game may take the call and cast nothing (and say nothing): no cast begun shortly means
	-- nothing is being made.
	C_Timer.After(WAIT, function()
		if making == run and not run.started then
			making = nil
			Changed()
		end
	end)
	return true
end

-- A paused enchant run, on with the next cast (a click).
function Craft.Continue()
	if making and making.paused then Step(making) end
end

-- A paused run given up.
function Craft.Cancel()
	if making then
		making = nil
		Changed()
	end
end

local function Stopped()
	if not making then return end
	making = nil
	Changed()
end

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("REPLACE_TRADESKILL_ENCHANT")
events:RegisterEvent("REPLACE_ENCHANT")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "REPLACE_TRADESKILL_ENCHANT" or event == "REPLACE_ENCHANT" then
		-- Only for a run of ours on a kept item, with the toggle on: anything else is the player's call.
		if not making then return end
		-- (The question waits for the player: the run isn't given up while it's up.)
		making.started = true
		if not (making.target and Craft.AutoReplace()) then return end
		local yes = event == "REPLACE_TRADESKILL_ENCHANT" and "ReplaceTradeskillEnchant" or "ReplaceEnchant"
		if C_Item and type(C_Item[yes]) == "function" then pcall(C_Item[yes]) end
		local function hide() if StaticPopup_Hide then StaticPopup_Hide(event) end end
		hide()
		C_Timer.After(0, hide)   -- (the game's own handler may show it after ours)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		-- (A Stop left where it was through a fight: put where it belongs now, or away.)
		if ns.Window then ns.Window.CraftChanged(true) end
		return
	end
	-- (Any cast of a queued recipe takes one off the queue, however it was started.)
	if event == "UNIT_SPELLCAST_SUCCEEDED" and ns.Queue and type(spellID) == "number" then ns.Queue.Made(spellID) end
	if not making then return end
	if event == "UNIT_SPELLCAST_START" then
		if spellID == making.spell then making.started = true end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if spellID ~= making.spell then return end
		local run = making
		run.started = true
		run.done = run.done + 1
		if run.done >= run.count then
			Stopped()
			return
		end
		Changed()
		-- An enchant run: the next one, unless the game is casting it already.
		if run.location then
			-- (The next one is a click on Next: see above.)
			run.paused = true
			Changed()
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		if spellID ~= making.spell then return end
		-- An enchant run's next cast refused at once (the game still busy with the last): asked
		-- again shortly, twice at most. Anything later (moving, Stop) ends the run.
		local run = making
		-- (Refused at once, the game still busy with the last cast: the run waits on Next.)
		if run.location and run.stepAt and GetTime() - run.stepAt < 0.4 then
			run.paused = true
			Changed()
			return
		end
		Stopped()
	elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" and making.location then
		-- (The game's repeat ended: an enchant run of ours goes on by itself, above.)
		return
	else
		Stopped()
	end
end)

-- ---------------------------------------------------------------------------------------------
-- Stop
-- ---------------------------------------------------------------------------------------------

local stop
local function StopButton()
	if stop or InCombatLockdown() then return stop end
	stop = CreateFrame("Button", "DaylightRecipesStop", UIParent, "SecureActionButtonTemplate")
	stop:SetAttribute("type", "macro")
	stop:SetAttribute("macrotext", "/stopcasting")
	stop:RegisterForClicks("AnyUp", "AnyDown")
	stop:Hide()
	return stop
end

-- Whether the secure Stop is out (it can't be put away in a fight).
function Craft.StopShown() return stop ~= nil and stop:IsShown() end

-- The secure Stop over `visual` (the window's own Stop button, which shows the look and hover),
-- or put away (visual nil). Out of combat only; in a fight it stays as it is.
function Craft.PlaceStop(visual)
	if InCombatLockdown() then return end
	local b = StopButton()
	if not b then return end
	if not visual or not visual:IsVisible() then
		b:Hide()
		return
	end
	local scale = visual:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom = visual:GetLeft(), visual:GetBottom()
	if not left or not bottom then b:Hide() return end
	b:ClearAllPoints()
	b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
	b:SetSize(visual:GetWidth() * scale, visual:GetHeight() * scale)
	-- (Above the window whatever its level: clicking the window raises it.)
	b:SetFrameStrata("DIALOG")
	if not b.hovered then
		b.hovered = true
		b:HookScript("OnEnter", function() if b.visual and b.visual.Hover then b.visual.Hover(true) end end)
		b:HookScript("OnLeave", function() if b.visual and b.visual.Hover then b.visual.Hover(false) end end)
	end
	b.visual = visual
	b:Show()
end
