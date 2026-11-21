-- Making things from Glowey's Recipes' window: Create (as many as the count says), enchanting onto an item, and
-- following the casts until they're done or stopped. The docked pane's enchant section (Pane.lua)
-- enchants through the same calls.
-- The game's own Create buttons are plain buttons calling C_TradeSkillUI.CraftRecipe (and
-- CraftEnchant with the item picked beforehand), so ours do the same. Stopping a cast is the one
-- protected thing (SpellStopCasting): Stop is a secure /stopcasting button of the game's own
-- template, laid over the window's Stop button while something is being made. It's a child of
-- UIParent placed at the same spot on screen, never anchored to the window, so the window stays an
-- ordinary frame you can move, resize, roll up and close in a fight (the rules, with their source,
-- are at "Stop" below).
-- Enchanting for skill: the item an enchant goes on is kept (the last few, per character), so one
-- cheap item can take enchant after enchant; a run of several casts on it is one call, as the game's
-- own Create does for a stack; and, with "Auto-replace" on, the game's "replace the enchant?" question
-- is answered yes during a run of ours on that item (the question comes on every cast after the
-- first, and would stop the run).
local _, ns = ...
if not ns.ok then return end

local Craft = {}
ns.Craft = Craft

local making      -- { spell, count, done, castStart, castEnd } while casts are under way

local function TS(name, ...)
	local fn = C_TradeSkillUI and C_TradeSkillUI[name]
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then return a, b, c, d end
end
Craft.TS = TS

local function Changed()
	if ns.Window then ns.Window.CraftChanged() end
	-- (The docked pane's enchant section makes things here too: Pane.lua.)
	if ns.Pane then ns.Pane.CraftChanged() end
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
		if spellID == making.spell then
			making.started = true
			Craft.NoteCast(making)
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if spellID ~= making.spell then return end
		local run = making
		run.started = true
		run.done = run.done + 1
		run.castStart, run.castEnd = nil, nil
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
-- Progress
-- ---------------------------------------------------------------------------------------------
-- How far a run is, for the window's own 2 px progress line (no cast-bar art): the casts done plus
-- how far the one under way is. The cast's start and end come from UnitCastingInfo("player") as it
-- starts (returns name, displayName, textureID, startTimeMs, endTimeMs: Blizzard_APIDocumentation
-- Generated/UnitDocumentation.lua:828-851). That call is SecretWhenUnitSpellCastRestricted (:830):
-- under the client's restrictions its numbers are secret and can't be compared or used in sums, so
-- they are kept only when issecretvalue says they are plain; else the line moves a cast at a time.
-- issecretvalue is asked BEFORE anything else looks at them, a comparison with nil included: the
-- game's own code tests a value that may be secret before it compares it (Blizzard_DamageMeter/
-- DamageMeterEntry.lua:54: issecretvalue(texture) or ... or texture ~= self.iconTexture; Blizzard_
-- SharedXMLBase/Pools.lua:274).

local secret = type(issecretvalue) == "function" and issecretvalue or nil

function Craft.NoteCast(run)
	run.castStart, run.castEnd = nil, nil
	if type(UnitCastingInfo) ~= "function" then return end
	local ok, _, _, _, from, to = pcall(UnitCastingInfo, "player")
	if not ok then return end
	if secret and (secret(from) or secret(to)) then return end
	if type(from) ~= "number" or type(to) ~= "number" or to <= from then return end
	run.castStart, run.castEnd = from / 1000, to / 1000
end

-- 0 to 1 for the run under way, nil when nothing is being made.
function Craft.Progress()
	local run = making
	if not run or (run.count or 0) < 1 then return nil end
	local part = 0
	if run.castStart and run.castEnd and not run.paused then
		part = math.max(0, math.min(1, (GetTime() - run.castStart) / (run.castEnd - run.castStart)))
	end
	return math.max(0, math.min(1, (run.done + part) / run.count))
end

-- ---------------------------------------------------------------------------------------------
-- Stop
-- ---------------------------------------------------------------------------------------------
-- What the game's source settles about this button (the client's own UI source, wow-ui-source
-- branch "forever", version 1.60.1):
--   - SecureActionButtonTemplate inherits SecureFrameTemplate and runs SecureActionButton_OnClick
--     (Blizzard_FrameXML/SecureTemplates.xml:4-10); its "macro" action with a "macrotext" attribute
--     runs C_Macro.RunMacroText(text, button) (Blizzard_FrameXML/SecureTemplates.lua:449-463).
--   - On a protected frame SetPoint, ClearAllPoints, SetSize, SetParent, SetFrameStrata,
--     SetFrameLevel, Raise and StartMoving are protected functions (IsProtectedFunction = true:
--     Blizzard_APIDocumentationGenerated/SimpleScriptRegionResizingAPIDocumentation.lua:22-24,
--     135-139, 163-165, SimpleScriptRegionAPIDocumentation.lua:653-657, SimpleFrameAPIDocumentation
--     .lua:1000-1002, 1281-1297, 1548-1551): in a fight they are refused. Show and Hide carry no
--     such flag in that documentation (:357, :751); they are treated as protected here all the same
--     (the careful reading). So the secure Stop is moved, sized, shown and hidden out of a fight
--     only: PlaceStop returns at once in one.
--   - A region can be protected without being so explicitly (IsProtected returns isProtected,
--     isProtectedExplicitly: SimpleScriptRegionAPIDocumentation.lua:540-553), and a region can have
--     its anchoring restricted (IsAnchoringRestricted, :400-412; the restricted environment refuses
--     GetRect and GetPoint of such a frame: Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua:
--     136-143, 375-380). The Lua source names those two states but not what causes them: that a
--     protected frame's parent and anchor targets are the ones that get them is the engine's rule,
--     not in the Lua source. So nothing of ours is ever the secure Stop's parent or anchor target:
--     it is a child of UIParent, anchored to UIParent only, at coordinates read from the window's
--     own Stop. The window is never touched by it and stays free in every state.
--   - Its face (below) is a plain child of it: a child depends on its parent, not the other way,
--     and showing or hiding a plain frame is not protected. DaylightUI gives plugins the same thing
--     on its secure unit frames (API.Attach: "a plain child, so drawing on it is fine",
--     DaylightUI/API.md, "The game's rules still apply").
-- What only the game can show is listed in design/in-game-check.md under "Window".


local stop
local function StopButton()
	if stop or InCombatLockdown() then return stop end
	stop = CreateFrame("Button", "DaylightRecipesStop", UIParent, "SecureActionButtonTemplate")
	stop:SetAttribute("type", "macro")
	stop:SetAttribute("macrotext", "/stopcasting")
	stop:RegisterForClicks("AnyUp", "AnyDown")
	stop:Hide()
	-- Its own face: Daylight UI's button look, a plain child filling it, shown only while the window's
	-- Stop is not under it (Craft.StopFace). It takes no clicks (the secure button under it does) and
	-- a controller's cursor never stops on it.
	local face = ns.API.Button(stop, ns.L["Stop"], 24)
	face:SetAllPoints(stop)
	face:EnableMouse(false)
	face:Hide()
	if ns.Pad then ns.Pad.Skip(face) end
	stop.face = face
	return stop
end

-- Whether the secure Stop is out (it can't be put away in a fight).
function Craft.StopShown() return stop ~= nil and stop:IsShown() end

-- Where the secure Stop is: { left, bottom, width, height } in the screen's units, or nil while
-- it's away. (Reading a frame's rectangle is not protected.)
-- (GetRect may return nothing, and secret numbers for a region whose anchoring is secret:
-- SimpleScriptRegionAPIDocumentation.lua:193-196. Ours is anchored to the screen alone; checked
-- all the same, since a secret number can't be compared.)
function Craft.StopRect()
	if not (stop and stop:IsShown()) then return nil end
	local left, bottom, w, h = stop:GetRect()
	-- (Secret first, then plain numbers: NoteCast, above.)
	if secret and (secret(left) or secret(bottom) or secret(w) or secret(h)) then return nil end
	if type(left) ~= "number" or type(bottom) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
	return { left, bottom, w, h }
end

-- Where `visual` is, in the same units (what PlaceStop would give the secure Stop).
function Craft.RectOf(visual)
	if not visual or not visual:IsVisible() then return nil end
	local scale = visual:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, bottom = visual:GetLeft(), visual:GetBottom()
	if not left or not bottom then return nil end
	return { left * scale, bottom * scale, visual:GetWidth() * scale, visual:GetHeight() * scale }
end

-- The secure Stop's own face on or off: on while it is out and the window draws no Stop under it
-- (a fight kept it where it was while the window moved, changed state or closed), so a Stop that
-- takes a click is always one you can see.
function Craft.StopFace(on)
	if not (stop and stop.face) then return end
	local face = stop.face
	if on and stop:IsShown() then
		face.text:SetText(ns.L["Stop"])
		face:Show()
	else
		face:Hide()
	end
end

-- The secure Stop over `visual` (the window's own Stop button, which shows the look and hover),
-- or put away (visual nil). Out of combat only; in a fight it stays as it is.
function Craft.PlaceStop(visual)
	if InCombatLockdown() then return end
	local b = StopButton()
	if not b then return end
	if b.face then b.face:Hide() end
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
