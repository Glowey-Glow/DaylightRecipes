-- Glowey's Recipes: standing together with Professionally Lost (another author's addon, All Rights
-- Reserved). Every call into it and every read of its saved data in this plugin goes through this
-- one file. Nothing of Professionally Lost's is ever written, switched or edited from here: each
-- hand-off quiets something of our own, or reads something of its, so "Put Everything Back" is
-- exact by construction. A name of its that is gone in a later version makes a function here
-- answer false / nil, so a button hides or Recipes does the job itself; nothing errors.
--
-- What other files use (the interface; the window's files code against these names):
--   ns.ProfLost.Loaded()             -> bool    Professionally Lost is loaded and its handle is there.
--   ns.ProfLost.Handed(key, line)    -> bool    key: "guide", "buy", "trainer", "tooltip", "prices",
--                                               "step". line: a profession's skill line, or nil for
--                                               "any profession". True when that job is handed off
--                                               (and, for a line, Professionally Lost has a guide for
--                                               it). "buy", "trainer" and "step" follow "guide": they
--                                               are false while the Leveling Guide is not handed off.
--                                               "prices" has no profession; a line given is ignored.
--   ns.ProfLost.Covers(line)         -> bool    It has a crafting guide for that profession.
--   ns.ProfLost.Due()                -> bool    its first-load window is still to come at this login
--   ns.ProfLost.PlanQuiet(line)      -> bool    Nothing of ours reads that profession's own plan any
--                                               more (guide, buy list and trainer piece all handed
--                                               off): it is not worked out again, only kept.
--   ns.ProfLost.RestPlan(line)       -> bool    PlanQuiet(line), and the plan saved for that profession
--                                               marked as resting (plan.rested): it is not kept up
--                                               while it rests, so nothing may count from it until
--                                               it is worked out again (Shop.lua, Tips.lua skip it).
--   ns.ProfLost.NextStepSpell(line)  -> spellID or nil   The recipe its guide is on. A plain guarded
--                                               read: ask Handed("step", line) before lighting it.
--   ns.ProfLost.OpenGuide(line)      -> bool    Its guide window, on that profession when it covers it.
--   ns.ProfLost.OpenGathering()      -> bool    Its gathering panel.
--   ns.ProfLost.OpenSettings()       -> bool    Its options page.
--   ns.ProfLost.CanOpenGuide() / CanOpenGathering() / CanOpenSettings() -> bool   Whether to show the
--                                               button at all (the function behind it is there).
--   ns.ProfLost.Price(itemID)        -> copper, age (seconds) or nil   Its own scanned price. A plain
--                                               guarded read; Prices.lua decides whether to use it.
--   ns.ProfLost.HasPrices()          -> bool    Its scan has stored a price for this realm and faction.
--   ns.ProfLost.VendorButtonShown()  -> bool    Its "Buy for guide" button is on show at the vendor
--                                               (Shop.lua stands its strip beside it on the game's
--                                               vendor window).
--   ns.ProfLost.OnChange(fn)         fn(what) runs when a hand-off changed: what is "settings" (a
--                                               switch), "step" (its guide moved on) or "prices" (its
--                                               scan stored prices).
--
-- Source read for every name used (Professionally Lost 1.2.0; "PL:" is its folder):
--   the handle          PL:Core/Init.lua:5-6     "Public handle for other addons": ProfLost = CP
--   its guides          PL:Data/Guides/*.lua     CP.Guides[<skill line>] = { name, steps = {...} }
--                                                 (171, 164, 185, 333, 202, 129, 165, 197)
--   its signals         PL:Core/Init.lua:93-122  CP:On(event, fn) / CP:Emit; handlers get (event, ...)
--                       PL:Engine/Gather.lua:1051 CP:Emit("ProfLost_NEEDS") after nextStep is saved
--   its next step       PL:Engine/Gather.lua:1044-1045  CP.charDB.nextStep[key] = { spell = ..., ... }
--                       PL:Core/Init.lua:326-328  ProfLostCharDB is that same table
--   its window          PL:UI/Window.lua:133-140 Window.Pick(id); :357-365 Window.Open()
--                       PL:UI/Launcher.lua:217-219 ProfLost_Open(_, button): a toggle (the .toc's
--                                                 AddonCompartmentFunc), used only as the fallback;
--                                                 :129-136 with Shift held it toggles the gathering
--                                                 panel instead (never pressed with Shift held)
--                       PL:UI/Panel.lua:19, 27    the frame ProfLost_Panel
--   its gathering panel PL:UI/GatherPanel.lua:767-779  GatherPanel.Open()
--   its settings        PL:UI/Panel.lua:590-597  Panel:OpenSettings() (a method)
--   its scanned prices  PL:Pricing/Scan.lua:113-118  Scan.Price(itemID) -> price, time seen
--                       PL:Pricing/Scan.lua:121-124  Scan.HasData()
--                       PL:Pricing/Scan.lua:244   Scan.OnChange(fn): "runs whenever the scan starts, steps,
--                                                 stops, or the auction house opens or closes"
--                       PL:Pricing/Scan.lua:220   Scan.Running(); :127-130 Scan.LastTime() (when this
--                                                 realm and faction last finished a scan, or nil)
--   its vendor button   PL:UI/Buying.lua:16-17    CP.Buying; :525-526 Buying.vendor = { button = ... };
--                       PL:UI/Buying.lua:520, 613  under the game's MerchantFrame: TOPLEFT to its
--                                                 BOTTOMLEFT, +4, -4 (made the first time it shows)
--   its tooltip switch  PL:UI/ItemTooltip.lua:65  its item block shows only with itemTooltip on;
--                       PL:UI/Plugin.lua:15       its Daylight UI module is named "ProfLost"

local ADDON, ns = ...

local PL = {}
ns.ProfLost = PL

local FOLDER = "ProfessionallyLost"     -- its addon folder (its .toc's name)
local HANDLE = "ProfLost"               -- its global handle, and its Daylight UI module's name

-- Our six switches, by the job's key. All false until the player answers the first-load dialog.
local SETTING = { guide = "plGuide", buy = "plShop", trainer = "plTrainer", tooltip = "plTips",
	prices = "plPrices", step = "plStep" }
PL.SETTING = SETTING
PL.ORDER = { "guide", "buy", "trainer", "tooltip", "prices", "step" }
-- These three mean nothing without the guide handed off (the dialog dims them).
local FOLLOWS_GUIDE = { buy = true, trainer = true, step = true }
PL.FOLLOWS_GUIDE = FOLLOWS_GUIDE
-- "prices" is the one job that is not a profession's.
local NO_LINE = { prices = true }

-- ---------------------------------------------------------------------------------------------
-- Guarded reads
-- ---------------------------------------------------------------------------------------------

local function Handle()
	local h = rawget(_G, HANDLE)
	return type(h) == "table" and h or nil
end

-- A table inside its handle (ProfLost.Window, ProfLost.Scan ...), or nil.
local function Part(name)
	local h = Handle()
	if not h then return nil end
	local ok, part = pcall(function() return h[name] end)
	return ok and type(part) == "table" and part or nil
end

-- A function inside one of its tables, or nil.
local function Func(part, name)
	local t = Part(part)
	if not t then return nil end
	local ok, fn = pcall(function() return t[name] end)
	return ok and type(fn) == "function" and fn or nil
end

local loaded = false
function PL.Loaded()
	if loaded then return Handle() ~= nil end
	-- (C_AddOns.IsAddOnLoaded: Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua; Core.lua
	-- reads Mastercraft the same way.)
	local is = type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded
	if type(is) ~= "function" then return false end
	local ok, yes = pcall(is, FOLDER)
	if ok and yes and Handle() then
		loaded = true
		return true
	end
	return false
end

function PL.Covers(line)
	if type(line) ~= "number" or not PL.Loaded() then return false end
	local guides = Part("Guides")
	if not guides then return false end
	local ok, guide = pcall(function() return guides[line] end)
	return ok and guide ~= nil and guide ~= false
end

local function CoversAny()
	local guides = Part("Guides")
	if not guides then return false end
	local ok, any = pcall(next, guides)
	return ok and any ~= nil
end

local function On(setting)
	return ns.Get and ns.Get(setting) == true or false
end

-- Its own item tooltip block is on (its switch "itemTooltip", read the sanctioned way:
-- API.GetSetting is read-only, DaylightUI/API.md "Read settings"). Unknown counts as on, its default.
local function ItsTooltipOn()
	local API = ns.API
	if not API or type(API.GetSetting) ~= "function" then return true end
	local ok, value = pcall(API.GetSetting, HANDLE, "itemTooltip")
	if ok and value == false then return false end
	return true
end

function PL.Handed(key, line)
	local setting = SETTING[key]
	if not setting or not PL.Loaded() then return false end
	if not On(setting) then return false end
	if NO_LINE[key] then return true end
	if FOLLOWS_GUIDE[key] and not On(SETTING.guide) then return false end
	if key == "tooltip" and not ItsTooltipOn() then return false end
	if line == nil then return CoversAny() end
	return PL.Covers(line)
end

function PL.PlanQuiet(line)
	if type(line) ~= "number" then return false end
	return PL.Handed("guide", line) and PL.Handed("buy", line) and PL.Handed("trainer", line)
end

-- Core.lua asks this in place of working a plan out: true while the plan rests, and then the one
-- saved for the profession (Store.Char().plans[line], written by Plan.Get) carries rested = true.
-- A plan worked out again is a new table without the mark (Plan.Get), so the mark means exactly
-- "not kept up since": after a partial put-back nothing counts from a plan made for a skill you
-- have since passed.
function PL.RestPlan(line)
	if not PL.PlanQuiet(line) then return false end
	local c = ns.Store and ns.Store.Char and ns.Store.Char()
	local plan = type(c) == "table" and type(c.plans) == "table" and c.plans[line]
	if type(plan) == "table" then plan.rested = true end
	return true
end

function PL.NextStepSpell(line)
	if type(line) ~= "number" or not PL.Loaded() then return nil end
	local db = rawget(_G, "ProfLostCharDB")
	if type(db) ~= "table" then return nil end
	local steps = rawget(db, "nextStep")
	if type(steps) ~= "table" then return nil end
	local step = rawget(steps, line)
	if type(step) ~= "table" then return nil end
	local spell = rawget(step, "spell")
	if type(spell) ~= "number" or spell <= 0 or spell ~= math.floor(spell) then return nil end
	return spell
end

local function Now()
	-- (Its scan stamps with GetServerTime() where the client has it, else time(): PL:Pricing/Scan.lua:100.)
	local server = rawget(_G, "GetServerTime")
	if type(server) == "function" then
		local ok, t = pcall(server)
		if ok and type(t) == "number" then return t end
	end
	return time()
end

function PL.Price(itemID)
	if type(itemID) ~= "number" or not PL.Loaded() then return nil end
	local price = Func("Scan", "Price")
	if not price then return nil end
	local ok, copper, seen = pcall(price, itemID)
	if not ok or type(copper) ~= "number" or copper <= 0 or copper ~= copper then return nil end
	if type(seen) ~= "number" then return nil end
	local age = Now() - seen
	if age < 0 then age = 0 end
	return math.floor(copper), age
end

function PL.HasPrices()
	if not PL.Loaded() then return false end
	local has = Func("Scan", "HasData")
	if not has then return false end
	local ok, yes = pcall(has)
	return ok and yes == true
end

-- Its button at a vendor is on show. Not readable in a later version of its: loaded counts as
-- "it's there", so our strip keeps clear of the corner it would hang in.
function PL.VendorButtonShown()
	if not PL.Loaded() then return false end
	local buying = Part("Buying")
	if not buying then return true end
	local ok, shown = pcall(function()
		local vendor = buying.vendor
		if type(vendor) ~= "table" then return true end
		local button = vendor.button
		-- (Not made yet: it makes its button the first time it has something to show.)
		if button == nil then return false end
		if type(button) ~= "table" then return true end
		return button:IsVisible() and true or false
	end)
	if ok then return shown end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Its windows, opened on the player's click
-- ---------------------------------------------------------------------------------------------

local function PanelShown()
	local panel = rawget(_G, "ProfLost_Panel")
	if type(panel) ~= "table" or type(panel.IsShown) ~= "function" then return false end
	local ok, shown = pcall(panel.IsShown, panel)
	return ok and shown and true or false
end

function PL.CanOpenGuide()
	if not PL.Loaded() then return false end
	return Func("Window", "Open") ~= nil or type(rawget(_G, "ProfLost_Open")) == "function"
end

function PL.OpenGuide(line)
	if not PL.Loaded() then return false end
	local open = Func("Window", "Open")
	if open then
		-- Pointed at the profession first, as a pick in its own dropdown would (it saves that pick).
		local pick = Func("Window", "Pick")
		if pick and PL.Covers(line) then pcall(pick, line) end
		return (pcall(open))
	end
	-- Its launcher's own function is a toggle: only pressed while its window is shut. With Shift
	-- held it shows or hides its gathering panel instead of the guide (PL:UI/Launcher.lua:129-136),
	-- which is not what was asked for: then nothing is pressed, and the answer is false.
	local toggle = rawget(_G, "ProfLost_Open")
	if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then return false end
	if type(toggle) == "function" and not PanelShown() then
		return (pcall(toggle, FOLDER, "LeftButton"))
	end
	return false
end

function PL.CanOpenGathering()
	return PL.Loaded() and Func("GatherPanel", "Open") ~= nil
end

function PL.OpenGathering()
	if not PL.Loaded() then return false end
	local open = Func("GatherPanel", "Open")
	if not open then return false end
	return (pcall(open))
end

function PL.CanOpenSettings()
	return PL.Loaded() and Func("Panel", "OpenSettings") ~= nil
end

function PL.OpenSettings()
	if not PL.Loaded() then return false end
	local open = Func("Panel", "OpenSettings")
	if not open then return false end
	return (pcall(open, Part("Panel")))
end

-- ---------------------------------------------------------------------------------------------
-- Changes
-- ---------------------------------------------------------------------------------------------

local listeners = {}

function PL.OnChange(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function Fire(what)
	for i = 1, #listeners do
		local ok, err = pcall(listeners[i], what)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

-- One of our six switches changed (Core.lua's SettingChanged), or all of them at once.
function PL.Changed()
	if ns.Calc and ns.Calc.Forget then ns.Calc.Forget() end
	-- A plan that rested while everything of its profession was handed off (RestPlan) is stale. For
	-- the profession open now it is worked out again here, before the strips are drawn from it (a
	-- fresh plan carries no mark); for the others it stays left out until they are opened
	-- (Core.lua's ReadProfession works a resting plan out as soon as it may).
	local S = ns.state
	if type(S) == "table" and S.line and S.mode and not S.linked and ns.Plan and ns.Plan.Get
		and not PL.PlanQuiet(S.line) then
		pcall(ns.Plan.Get)
	end
	Fire("settings")
	if ns.Shop then ns.Shop.Refresh() end
	if ns.Changed then ns.Changed() end
end

-- Its signals reach us through its own hub. Its dispatch does not guard a handler, so ours never
-- lets an error out; and both are gathered to one call a moment later (its scan tells of every step).
local pending = {}
local function Soon(what)
	if pending[what] then return end
	pending[what] = true
	C_Timer.After(what == "prices" and 2 or 0.2, function()
		pending[what] = nil
		if what == "prices" then
			if not PL.Handed("prices") then return end
			if ns.Calc and ns.Calc.Forget then ns.Calc.Forget() end
		elseif not PL.Handed("step") then
			return
		end
		Fire(what)
		if ns.Shown and ns.Shown() and ns.Changed then ns.Changed() end
	end)
end

-- Its scan's listener runs on every step of a scan and whenever the Auction House opens or closes
-- (PL:Pricing/Scan.lua:243-246, 290-602), far more often than its prices change for us. Ours are
-- thrown away and the window drawn again only when a scan of its has ended (Scan.Running() gone
-- from true to false: a stopped search keeps what it priced, :276-290) or its "last finished scan"
-- stamp moved (Scan.LastTime(), :127-130). With neither readable (a later version of its), every
-- call counts, as before: gathered to one a moment later (Soon).
local scan = { running = false, stamp = nil }
local function ScanMoved()
	local running, last = Func("Scan", "Running"), Func("Scan", "LastTime")
	if not running and not last then return true end
	local isRunning, stamp
	if running then
		local ok, yes = pcall(running)
		if ok then isRunning = yes == true end
	end
	if last then
		local ok, t = pcall(last)
		if ok and type(t) == "number" then stamp = t end
	end
	local moved = (scan.running and isRunning == false) or stamp ~= scan.stamp
	scan.running, scan.stamp = isRunning == true, stamp
	return moved
end

-- Asked at login (Professionally Lost loads after us). Each of the two is taken up once, when its
-- function is there.
local hearing = {}
function PL.Listen()
	if not PL.Loaded() then return end
	local h = Handle()
	if not hearing.step then
		local ok, on = pcall(function() return h.On end)
		if ok and type(on) == "function" then
			hearing.step = pcall(on, h, "ProfLost_NEEDS", function() pcall(Soon, "step") end)
		end
	end
	if not hearing.prices then
		local changed = Func("Scan", "OnChange")
		if changed then
			-- (Where its stamp stands now, so the first call after login is not taken for a scan.)
			pcall(ScanMoved)
			hearing.prices = pcall(changed, function()
				local ok, moved = pcall(ScanMoved)
				if not ok or moved then pcall(Soon, "prices") end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The switches: defaults, put back
-- ---------------------------------------------------------------------------------------------

-- What the first-load dialog starts each row at: on = Professionally Lost does it. With a
-- controller in use the first three start off, since Professionally Lost has no gamepad code.
function PL.Suggested(pad)
	local out = {}
	for _, key in ipairs(PL.ORDER) do out[key] = true end
	if pad then out.guide, out.buy, out.trainer = false, false, false end
	return out
end

local function Set(setting, value)
	local DUI = rawget(_G, "DaylightUI")
	if type(DUI) ~= "table" or type(DUI.Set) ~= "function" then return false end
	-- (DaylightUI:Set(scope, path, value): DaylightUI/Core.lua:841; saved in the player's profile and
	-- told to us through SettingChanged, as RecipesGuide.lua and Swap.lua already set "window".)
	return (pcall(DUI.Set, DUI, ADDON, setting, value))
end

-- picks: { guide = bool, ... }. Sets all six, then tells everyone once.
function PL.Apply(picks)
	PL.applying = true
	for _, key in ipairs(PL.ORDER) do Set(SETTING[key], picks[key] == true) end
	PL.applying = false
	PL.Changed()
end

function PL.PutBack()
	PL.Apply({})
end

-- ---------------------------------------------------------------------------------------------
-- The first-load window: "Professionally Lost Is Installed"
-- ---------------------------------------------------------------------------------------------
-- Shown once, the first login where Professionally Lost is loaded and the rows have not been
-- answered (DaylightRecipesDB.proflost.asked); a new player gets it after the welcome is answered.
-- Nothing is switched before Apply. Ask Me Later (and the X, Escape, B) closes it until the next
-- login. The pattern is Addon Skins' choice window (one row a job with a switch, Apply in the left
-- corner as the main action, Ask Me Later in the right), written anew here from Daylight UI's
-- widgets (API.Skin, API.Text, API.Switch, API.Button, API.Close: DaylightUI/API.md "Look like
-- Daylight UI"; a switch is sw.SetOn(bool) and reads sw.on: Options/Widgets.lua:2353-2354).
-- On a controller (Guide.lua's Pad): the cursor starts on Apply, every switch is a stop, A flips
-- it, B is Ask Me Later.
if not ns.ok then return end

local API, L = ns.API, ns.L

local ROWS = {
	{ key = "guide", label = L["Leveling Guide"],
	  desc = L["Professionally Lost guides your leveling, and Glowey's Recipes hides its Leveling Guide and Materials tabs for the professions it covers."] },
	{ key = "buy", label = L["Buy Lists"],
	  desc = L["Professionally Lost's Buy for Guide button covers your guide at vendors, and Glowey's Recipes lists only what your crafting queue needs."] },
	{ key = "trainer", label = L["Trainer Panel"],
	  desc = L["Professionally Lost's guide names the recipes to train, and Glowey's Recipes' trainer strip shows only your next rank."] },
	{ key = "tooltip", label = L["Guide Line in Item Tooltips"],
	  desc = L["Professionally Lost's tooltip says what your guides need, and Glowey's Recipes drops its own guide line."] },
	{ key = "prices", label = L["Scanned Prices"],
	  desc = L["Glowey's Recipes also uses the auction prices Professionally Lost scanned, so one scan serves both."] },
	{ key = "step", label = L["Light Up Its Step"],
	  desc = L["Glowey's Recipes lights the recipe Professionally Lost's guide is on in your recipe list."] },
}
PL.ROWS = ROWS

local function Record()
	DaylightRecipesDB = type(DaylightRecipesDB) == "table" and DaylightRecipesDB or {}
	local db = DaylightRecipesDB
	db.proflost = type(db.proflost) == "table" and db.proflost or {}
	return db.proflost
end

-- "Asked" is kept per account (DaylightRecipesDB), the six switches in Daylight UI's profile with
-- the plugin's other settings (DaylightUI:Set, below). A character on another profile is therefore
-- not asked again and starts with all six off, as before the window was answered: the options
-- group and the window's own sentence ("You can change this any time in Plugins > Recipes") are
-- the way there. Daylight UI's API names no call for which profile is in use (API.md: settings
-- are read and set by scope and path only), so "asked" is not kept per profile on a guess.
function PL.Asked() return Record().asked == true end

local W, EDGE = 560, 18
local dialog

local function Ink(fs, role)
	local c = API.Colors()[role]
	if type(c) == "table" then fs:SetTextColor(c[1], c[2], c[3]) end
end

-- The rows that mean nothing while the guide is not handed off are dimmed and take no press.
local function Dim()
	local guide = dialog.rows.guide.switch.on == true
	for _, def in ipairs(ROWS) do
		local row = dialog.rows[def.key]
		local off = FOLLOWS_GUIDE[def.key] and not guide
		row:SetAlpha(off and 0.4 or 1)
		row.switch:SetEnabled(not off)
		row:EnableMouse(not off)
	end
end

local function Build()
	local f = CreateFrame("Frame", "DaylightRecipesProfLost", UIParent)
	f:SetWidth(W)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	-- (A box that asks a question: solid, whatever the window opacity.)
	ns.SkinWindow(f, { solid = true })
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightRecipesProfLost") end

	f.title = API.Text(f, "title", "LEFT")
	f.title:SetPoint("TOPLEFT", EDGE, -EDGE)
	f.title:SetPoint("RIGHT", f, "RIGHT", -44, 0)
	f.title:SetText(L["Professionally Lost Is Installed"])
	Ink(f.title, "VALUE")
	f.lead = API.Text(f, "body", "LEFT")
	f.lead:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.lead:SetWidth(W - EDGE * 2)
	f.lead:SetWordWrap(true)
	f.lead:SetText(L["Both addons guide your profession leveling, so pick which one does each job: on means Professionally Lost does it. You can change this any time in Plugins > Recipes."])
	Ink(f.lead, "TEXT")
	local close = API.Close(f, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)

	f.rows = {}
	for _, def in ipairs(ROWS) do
		local row = CreateFrame("Frame", nil, f)
		row:EnableMouse(true)
		row.name = API.Text(row, "body", "LEFT")
		row.name:SetPoint("TOPLEFT", 4, -6)
		row.name:SetText(def.label)
		Ink(row.name, "VALUE")
		row.switch = API.Switch(row)
		row.switch:SetPoint("RIGHT", -4, 0)
		row.what = API.Text(row, "small", "LEFT")
		row.what:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
		-- (The sentence wraps beside the switch: never cut, the row grows with it.)
		row.what:SetWidth(W - EDGE * 2 - 4 - 70)
		row.what:SetWordWrap(true)
		row.what:SetText(def.desc)
		Ink(row.what, "TEXT")
		row.switch:SetScript("OnClick", function(self)
			self.SetOn(not self.on)
			Dim()
		end)
		-- The whole row flips it.
		row:SetScript("OnMouseUp", function(self, button)
			if button == "LeftButton" and self.switch:IsEnabled() then self.switch:Click() end
		end)
		f.rows[def.key] = row
	end

	f.foot = API.Text(f, "small", "LEFT")
	f.foot:SetWidth(W - EDGE * 2 - 8)
	f.foot:SetWordWrap(true)
	Ink(f.foot, "LABEL")

	-- Apply is the window's main action, as Daylight UI lays out its own: in the left corner with
	-- its main-button look (API.MainButton, 1.8), Ask Me Later in the right corner.
	f.apply = API.Button(f, L["Apply"], 26)
	f.apply.FitWidth(150)
	f.apply:SetPoint("BOTTOMLEFT", EDGE, EDGE)
	if type(API.MainButton) == "function" then pcall(API.MainButton, f.apply, true) end
	f.apply:SetScript("OnClick", function()
		local picks = {}
		for _, def in ipairs(ROWS) do picks[def.key] = f.rows[def.key].switch.on == true end
		-- (A row that is dimmed is off: it has no meaning without the guide.)
		if not picks.guide then
			for key in pairs(FOLLOWS_GUIDE) do picks[key] = false end
		end
		Record().asked = true
		f:Hide()
		PL.Apply(picks)
	end)
	f.later = API.Button(f, L["Ask Me Later"], 26)
	f.later.FitWidth(150)
	f.later:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
	f.later:SetScript("OnClick", function() f:Hide() end)

	f.padFirst = function() return f.apply end
	if ns.Pad then ns.Pad.Follow(f, function() f:Hide() end) end
	-- While it is up, the other Daylight plugins' welcomes and tours wait, as they do for each
	-- other's (Guide.lua's shared mark: Guide.Hold).
	f:HookScript("OnShow", function() if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("proflost", true) end end)
	f:HookScript("OnHide", function() if ns.Guide and ns.Guide.Hold then ns.Guide.Hold("proflost", false) end end)
	dialog = f
end

-- Opens the window on what it suggests (everything to Professionally Lost, except the first three
-- while a controller is in use), or on the switches as they stand when some are already on.
function PL.ShowDialog()
	if not PL.Loaded() or InCombatLockdown() then return false end
	if not dialog then Build() end
	local f = dialog
	local pad = ns.Pad ~= nil and ns.Pad.On() == true
	local picks = PL.Suggested(pad)
	-- (Switches already set, in the options before this window was answered, are kept as they are.)
	local any = false
	for _, key in ipairs(PL.ORDER) do
		if ns.Get(SETTING[key]) == true then any = true end
	end
	if any then
		for _, key in ipairs(PL.ORDER) do picks[key] = ns.Get(SETTING[key]) == true end
	end
	local notes = { L["Your profession window stays Glowey's Recipes' own; Professionally Lost's guide window stands beside it."] }
	if pad then
		notes[#notes + 1] = L["Professionally Lost has no controller support yet, so the first three stay with Glowey's Recipes unless you switch them on."]
	end
	f.foot:SetText(table.concat(notes, "\n"))
	local y = EDGE + math.ceil(f.title:GetStringHeight() or 20) + 8 + math.ceil(f.lead:GetStringHeight() or 30) + 12
	for _, def in ipairs(ROWS) do
		local row = f.rows[def.key]
		row.switch.SetOn(picks[def.key] == true)
		local h = 6 + math.ceil(row.name:GetStringHeight() or 14) + 3 + math.ceil(row.what:GetStringHeight() or 12) + 8
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -y)
		row:SetPoint("RIGHT", f, "RIGHT", -EDGE, 0)
		row:SetHeight(h)
		y = y + h
	end
	f.foot:ClearAllPoints()
	f.foot:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + 4, -(y + 8))
	y = y + 8 + math.ceil(f.foot:GetStringHeight() or 14)
	f:SetHeight(y + 16 + 26 + EDGE)
	ns.SkinWindow(f, { solid = true })
	Dim()
	f:Show()
	return true
end

-- At login, never over anything else of ours or Daylight UI's: out of a fight, and only once
-- Guide.lua has had its turn (Guide.Busy): the welcome (a first launch) answered, the What's New
-- note (an update) shown AND closed, no tour running, Daylight UI's own setup guide, welcome or tour
-- and the other Daylight plugins' guides away. So a player updating with Professionally Lost
-- installed sees What's New first, and this window only after closing it; never both at once.
-- Looked at every 2 seconds for 5 minutes; not answered, it is asked again at the next login.
local WAIT, TRIES = 2, 150
-- Whether that window is still to come at this login (looked for, not shown yet, not given up):
-- another question of ours (Pane.lua's, about Daylight UI's profit) waits for it rather than take
-- its place in the order.
local due = false
function PL.Due() return due end
ns.me.On("Login", function()
	PL.Listen()
	if not PL.Loaded() or PL.Asked() then return end
	local tries = 0
	due = true
	local function ask()
		tries = tries + 1
		local G = ns.Guide
		local busy = InCombatLockdown() or (G ~= nil and G.Busy ~= nil and G.Busy())
		if busy then
			if tries < TRIES then C_Timer.After(WAIT, ask) else due = false end
			return
		end
		due = false
		PL.ShowDialog()
	end
	C_Timer.After(8, ask)
end)
