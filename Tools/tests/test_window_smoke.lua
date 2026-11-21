-- The window itself, run end to end on stand-ins: the real Doc.lua, Pages.lua, Craft.lua,
-- Queue.lua, EnchantRow.lua, ProfLost.lua, WindowState.lua, WindowList.lua, WindowMenu.lua and
-- Window.lua, loaded in the .toc's order over a mock game. It proves the code runs through every
-- state and page (and the docked pane, Pane.lua) without a Lua error and that its own rules hold; it does not prove how the game
-- draws it (design/in-game-check.md, "Window").
-- What the mock enforces, so a pass means more than "it loads":
--   * THE SECURE STOP IS STRICT. A frame made from SecureActionButtonTemplate raises on SetPoint,
--     ClearAllPoints, SetSize, SetWidth, SetHeight, SetParent, SetFrameStrata, SetFrameLevel, Show,
--     Hide and SetShown while the fight flag is up, and on any parent or anchor that isn't UIParent
--     at any time. So "moved only out of a fight, never tied to the window" is checked on every call.
--   * NOTHING WRITES THE PANEL LAYOUT. SetUIPanelAttribute raises.
--   * No label is cut: every tab and every craft-bar button is at least as wide as its words.
--   * NO WIDGET METHOD ON A GUESS. A method that isn't on the list checked against the client's API
--     documentation raises (VERIFIED, below).
-- Self-contained (its own mock, not mocks.lua's): runs in Tools/tests/run.py and alone.
-- luacheck: no global

local ROOT
for _, root in ipairs({ rawget(_G, "ADDON_ROOT") or ".", ".", "../.." }) do
	local f = io.open(root .. "/WindowState.lua", "r")
	if f then
		f:close()
		ROOT = root
		break
	end
end
assert(ROOT, "run from the plugin's folder")

local checks = 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then error("FAILED: " .. tostring(what), 2) end
end
local function eq(got, want, what)
	checks = checks + 1
	if got ~= want then error(("FAILED: %s (got %s, wanted %s)"):format(tostring(what), tostring(got), tostring(want)), 2) end
end

-- ---- the game ----------------------------------------------------------------------------------
local FIGHT = false
local NOW = 100
local ERRORS = {}
local timers, updaters = {}, {}
local MENU             -- the last API.Menu opened: { keys, values, onPick, catcher, box }
local TRUNC            -- a test's rule for which texts are cut (IMPL.IsTruncated)
local DROPDOWN         -- Daylight UI's shared dropdown, as it builds it (ns.API.Menu below)

geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
function InCombatLockdown() return FIGHT end
function GetTime() return NOW end
function time() return 1700000000 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function IsModifiedClick() return false end
function IsShiftKeyDown() return false end
function CursorHasItem() return false end
function ClearCursor() end
function GetCursorPosition() return 300, 900 end
function issecretvalue() return false end
function SetUIPanelAttribute() error("the game's panel layout was written to", 2) end
function StaticPopup_Show() end
function StaticPopup_Hide() end
StaticPopupDialogs = {}
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
C_Timer = {
	After = function(_, fn) timers[#timers + 1] = fn end,
	NewTicker = function() return { Cancel = function() end } end,
}
local function Flush()
	for _ = 1, 20 do
		if #timers == 0 then break end
		local list = timers
		timers = {}
		for _, fn in ipairs(list) do fn() end
	end
end

local PROTECTED = { SetPoint = true, ClearAllPoints = true, SetSize = true, SetWidth = true, SetHeight = true,
	SetParent = true, SetFrameStrata = true, SetFrameLevel = true, Show = true, Hide = true, SetShown = true,
	SetAllPoints = true, StartMoving = true, Raise = true }
-- Every widget method the window calls on this run, each one checked by hand against the client's
-- own API documentation (wow-ui-source, branch "forever": Blizzard_APIDocumentationGenerated/
-- Simple*APIDocumentation.lua). A method not on this list raises: a new call is looked up there
-- first, then added here. (The tooltip's methods are the ones 2.5.2 already used.)
local VERIFIED = {}
for name in ([[
ClearAllPoints Click CreateTexture EnableMouse EnableMouseWheel GetBottom GetEffectiveScale
GetFrameLevel GetFrameStrata GetHeight GetLeft GetParent GetRect GetScale GetScript
GetStringHeight GetStringWidth GetText GetTop GetUnboundedStringWidth GetVerticalScroll
GetVerticalScrollRange GetWidth Hide HookScript IsMouseOver IsShown IsTruncated IsVisible
RegisterEvent RegisterForClicks RegisterForDrag RegisterUnitEvent SetAllPoints SetAlpha
SetAttribute SetClampedToScreen SetClipsChildren SetColorTexture SetDesaturated SetFrameLevel
SetFrameStrata SetHeight SetIgnoreParentAlpha SetJustifyH SetMinMaxValues SetMovable SetParent
SetPoint SetScale SetScript SetScrollChild SetShown SetSize SetTexCoord SetText SetTextColor
SetTexture SetToplevel SetUserPlaced SetValue SetVerticalScroll SetWidth SetWordWrap Show
StartMoving StopMovingOrSizing UnregisterEvent
]]):gmatch("%S+") do VERIFIED[name] = true end
local IMPL = {}
local MT = {}
MT.__index = function(t, k)
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	if not VERIFIED[k] and rawget(t, "kind") ~= "GameTooltip" then
		error("widget method not verified against the client's API documentation: " .. k, 2)
	end
	local impl = IMPL[k]
	local guard = PROTECTED[k]
	local fn = function(self, ...)
		if guard and rawget(self, "secure") and FIGHT then
			error("protected call " .. k .. " on the secure Stop in a fight", 2)
		end
		if impl then return impl(self, ...) end
	end
	rawset(t, k, fn)
	return fn
end
local ALL = {}
-- A frame starts one level over its parent and in its parent's strata; a strata set on it holds
-- for its children too, and a level set on it moves them with it (the client's rules: a child
-- frame's level is its parent's + 1, and SetFrameLevel carries the children along).
local function NewObj(kind, name, parent, template)
	local o = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, w = 0, h = 0,
		level = parent and (parent.level + 1) or 1, enabled = true, attrs = {} }, MT)
	if template == "SecureActionButtonTemplate" then
		o.secure = true
		if parent ~= rawget(_G, "UIParent") then error("the secure Stop must be UIParent's child") end
	end
	if name then _G[name] = o end
	ALL[#ALL + 1] = o
	return o
end
local function strip(text)
	return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
function IMPL.GetObjectType(self) return self.kind end
function IMPL.IsObjectType(self, kind) return self.kind == kind end
function IMPL.GetParent(self) return self.parent end
function IMPL.SetParent(self, p)
	if rawget(self, "secure") and p ~= UIParent then error("the secure Stop given a parent that isn't UIParent") end
	rawset(self, "parent", p)
end
function IMPL.Show(self)
	local was = self.shown
	rawset(self, "shown", true)
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function IMPL.Hide(self)
	local was = self.shown
	rawset(self, "shown", false)
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function IMPL.SetShown(self, on) if on then self:Show() else self:Hide() end end
function IMPL.IsShown(self) return self.shown end
function IMPL.IsVisible(self)
	local o = self
	while o do
		if not o.shown then return false end
		o = o.parent
	end
	return true
end
function IMPL.IsMouseOver() return false end
function IMPL.GetScale() return 1 end
function IMPL.GetEffectiveScale() return 1 end
-- Where a thing is: the secure Stop where its one anchor to the screen put it; anything else where
-- its window is (the test moves the window by setting its left and bottom).
function IMPL.GetLeft(self)
	if rawget(self, "secure") then return self.px end
	local o = self
	while o do
		if rawget(o, "left") then return o.left end
		o = o.parent
	end
	return 0
end
function IMPL.GetBottom(self)
	if rawget(self, "secure") then return self.py end
	local o = self
	while o do
		if rawget(o, "bottom") then return o.bottom end
		o = o.parent
	end
	return 0
end
function IMPL.GetTop(self) return IMPL.GetBottom(self) + self.h end
function IMPL.GetRight(self) return IMPL.GetLeft(self) + self.w end
function IMPL.GetRect(self) return IMPL.GetLeft(self), IMPL.GetBottom(self), self.w, self.h end
function IMPL.ClearAllPoints(self) rawset(self, "points", {}) end
function IMPL.SetPoint(self, point, rel, relPoint, x, y)
	local points = rawget(self, "points") or {}
	rawset(self, "points", points)
	points[#points + 1] = { point, rel, relPoint, x, y }
	if rawget(self, "secure") then
		if rel ~= UIParent then error("the secure Stop anchored to something that isn't UIParent") end
		rawset(self, "px", x)
		rawset(self, "py", y)
	end
	if rel == rawget(_G, "DaylightRecipesStop") and rel ~= nil and self ~= rel.face then
		error("something other than its own face is anchored to the secure Stop")
	end
end
function IMPL.SetAllPoints(self, rel)
	if rawget(self, "secure") then error("the secure Stop given all points of another frame") end
	if rel then
		rawset(self, "w", rel.w)
		rawset(self, "h", rel.h)
	end
end
function IMPL.SetSize(self, w, h) rawset(self, "w", w) rawset(self, "h", h) end
function IMPL.SetWidth(self, w) rawset(self, "w", w) end
function IMPL.SetHeight(self, h) rawset(self, "h", h) end
-- (A frame given no width of its own is laid out by its anchors, which this mock doesn't work
-- out: it is as wide as what holds it, as the window's pages are as wide as its column.)
function IMPL.GetWidth(self)
	if self.w == 0 and self.parent and self.parent ~= UIParent and (self.kind == "Frame" or self.kind == "ScrollFrame") then
		return self.parent:GetWidth()
	end
	return self.w
end
function IMPL.GetHeight(self) return self.h end
function IMPL.GetSize(self) return self.w, self.h end
function IMPL.GetFrameLevel(self) return self.level end
function IMPL.SetFrameLevel(self, l)
	local by = l - self.level
	rawset(self, "level", l)
	if by == 0 then return end
	for _, o in ipairs(ALL) do
		local up = o.parent
		while up do
			if up == self then
				rawset(o, "level", o.level + by)
				break
			end
			up = up.parent
		end
	end
end
function IMPL.GetFrameStrata(self)
	local o = self
	while o do
		if rawget(o, "strata") then return o.strata end
		o = o.parent
	end
	return "MEDIUM"
end
function IMPL.SetFrameStrata(self, s) rawset(self, "strata", s) end
function IMPL.SetClipsChildren(self, on) rawset(self, "clips", on and true or false) end
function IMPL.SetScript(self, name, fn)
	self.scripts[name] = fn
	if name == "OnUpdate" then updaters[self] = fn end
end
function IMPL.GetScript(self, name) return self.scripts[name] end
function IMPL.HookScript(self, name, fn)
	local old = self.scripts[name]
	self.scripts[name] = old and function(...) old(...) fn(...) end or fn
end
function IMPL.SetAttribute(self, k, v) self.attrs[k] = v end
function IMPL.GetAttribute(self, k) return self.attrs[k] end
function IMPL.SetEnabled(self, on) rawset(self, "enabled", on and true or false) end
function IMPL.IsEnabled(self) return self.enabled end
function IMPL.Click(self)
	if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
end
function IMPL.SetText(self, text) rawset(self, "textValue", text) end
function IMPL.GetText(self) return self.textValue end
-- Six units a letter; a string with a width wraps to as many lines as it needs.
function IMPL.GetUnboundedStringWidth(self) return 6 * #strip(self.textValue) end
function IMPL.GetStringWidth(self)
	local w = 6 * #strip(self.textValue)
	if self.w and self.w > 0 then return math.min(w, self.w) end
	return w
end
function IMPL.GetStringHeight(self)
	local w = 6 * #strip(self.textValue)
	if self.w and self.w > 0 and w > self.w then return 14 * math.ceil(w / self.w) end
	return 14
end
-- (A text is cut when the test says so: TRUNC(fontString), for a name in a wide font.)
function IMPL.IsTruncated(self) return TRUNC ~= nil and TRUNC(self) or false end
function IMPL.GetFont() return "font", 12, "" end
function IMPL.CreateTexture(self) return NewObj("Texture", nil, self) end
function IMPL.CreateFontString(self) return NewObj("FontString", nil, self) end
function IMPL.GetVerticalScrollRange() return 0 end
function IMPL.GetVerticalScroll() return 0 end
function IMPL.SetScrollChild(self, child) rawset(self, "child", child) end
function IMPL.NumLines() return 0 end
function IMPL.IsOwned() return false end
function IMPL.GetChildren() return end
local EVENTS = {}
function IMPL.RegisterEvent(self, e) EVENTS[e] = EVENTS[e] or {} EVENTS[e][self] = true end
function IMPL.RegisterUnitEvent(self, e) EVENTS[e] = EVENTS[e] or {} EVENTS[e][self] = true end
local function Fire(event, ...)
	local list = {}
	for frame in pairs(EVENTS[event] or {}) do list[#list + 1] = frame end
	for _, frame in ipairs(list) do
		local fn = frame.scripts.OnEvent
		if fn then fn(frame, event, ...) end
	end
end
function IMPL.GetNumPoints() return 0 end

UIParent = NewObj("Frame", "UIParent")
UIParent.w, UIParent.h = 1920, 1080
GameTooltip = NewObj("GameTooltip", "GameTooltip")
function CreateFrame(kind, name, parent, template) return NewObj(kind, name, parent, template) end
local function Tick(dt)
	NOW = NOW + (dt or 0.05)
	local list = {}
	for frame, fn in pairs(updaters) do list[#list + 1] = { frame, fn } end
	for _, e in ipairs(list) do
		local frame, fn = e[1], e[2]
		if frame.scripts.OnUpdate == fn and frame:IsVisible() then fn(frame, dt or 0.05) end
	end
end

-- ---- the trade skill ---------------------------------------------------------------------------
local RECIPES = {
	{ id = 3839, name = "Bolt of Silk Cloth", cat = 1, rd = 3, can = 12 },
	{ id = 8762, name = "Silk Headband", cat = 2, rd = 0, can = 4 },
	{ id = 8772, name = "Crimson Silk Belt", cat = 3, rd = 1, can = 0 },
	{ id = 13503, name = "Enchant Weapon - Lesser Striking With a Very Long Name Indeed", cat = 3, rd = 2, can = 2, enchant = true },
}
local byID = {}
for _, r in ipairs(RECIPES) do byID[r.id] = r end
local CRAFTED = {}
C_TradeSkillUI = {
	GetAllRecipeIDs = function()
		local out = {}
		for _, r in ipairs(RECIPES) do out[#out + 1] = r.id end
		return out
	end,
	GetRecipeInfo = function(id)
		local r = byID[id]
		if not r then return nil end
		return { name = r.name, learned = true, categoryID = r.cat, relativeDifficulty = r.rd, icon = 1, numSkillUps = 1,
			isEnchantingRecipe = r.enchant == true }
	end,
	GetCategoryInfo = function(id) return { name = "Category " .. id } end,
	GetCraftableCount = function(id) return byID[id] and byID[id].can or 0 end,
	GetRecipeOutputItemData = function(id) return { itemID = id + 1, icon = 2 } end,
	GetRecipeSchematic = function() return { quantityMin = 1, quantityMax = 1 } end,
	GetRecipeRequirements = function() return {} end,
	GetRecipeCooldown = function() return nil end,
	GetRecipeLink = function(id) return "link:" .. id end,
	GetTradeSkillTexture = function() return 3 end,
	GetTradeSkillListLink = function() return "tradeskill" end,
	IsTradeSkillLinked = function() return false end,
	OpenTradeSkill = function() return true end,
	GetEnchantItems = function() return {} end,
	CraftRecipe = function(id, n) CRAFTED[#CRAFTED + 1] = { id, n } end,
	CraftEnchant = function() end,
}
C_Item = { GetItemIconByID = function() return 4 end }
C_SkillInfo = { AbandonSkill = function() end }
C_Minimap = {
	GetNumTrackingTypes = function() return 1 end,
	GetTrackingInfo = function() return { name = "Find Minerals", texture = 5, active = true, spellID = 2580 } end,
	SetTracking = function() end,
}
function GetProfessions() return 1, 2, nil, 3 end
function GetProfessionInfo(i)
	if i == 1 then return "Tailoring", 6, 187, 225, 0, 0, 197 end
	if i == 2 then return "Herbalism", 7, 96, 150, 0, 0, 182 end
	return "Fishing", 8, 120, 150, 0, 0, 356
end
function UnitCastingInfo() return "x", "x", 1, NOW * 1000, (NOW + 3) * 1000 end

-- ---- the plugin's other parts, stood in for ----------------------------------------------------
local ns = { ok = true }
local SETTINGS = { useAH = true, marks = true, guideGlow = true, paneWidth = 300 }
ns.L = setmetatable({}, { __index = function(_, key) return key end })
ns.Plural = function(n, one, many) return n == 1 and one or many end
ns.state = { mode = nil, line = 197, name = "Tailoring", skill = 187, max = 225, linked = false, recipe = nil }
ns.LINES = { [197] = true, [171] = true }
ns.Get = function(key) return SETTINGS[key] end
ns.Print = function() end
ns.SkinWindow = function() end
ns.ShellOf = function(frame) return rawget(frame, "shell") end
ns.ReskinWindows = function() end
ns.Fold = function(text) return type(text) == "string" and text:lower() or "" end
ns.NameLess = function(a, b) return a < b end
ns.SpellName = function(spell) return byID[spell] and byID[spell].name or ("Spell " .. spell) end
ns.ItemNameOf = function(itemID) return "Item " .. itemID end
ns.DataLine = function(line) return ns.LINES[line] and line or nil end
ns.ReadProfession = function() return true end
ns.Ask = function(name, ...) return C_TradeSkillUI[name] and C_TradeSkillUI[name](...) end
ns.me = { On = function() end, AttachCraftPane = function() return NewObj("Frame", nil, UIParent) end }
ns.Changed = function()
	if ns.Window then ns.Window.Render() end
end
local function Button(parent, text)
	local b = NewObj("Button", nil, parent)
	b.text = NewObj("FontString", nil, b)
	b.text:SetText(text or "")
	b.h = 24
	function b.FitWidth(min) b.w = math.max(min or 64, 6 * #strip(b.text.textValue) + 24) end
	function b.SetOff(on)
		b.off = on and true or nil
	end
	function b.SetActive(on) b.active = on end
	function b.Hover() end
	b.FitWidth(64)
	return b
end
ns.API = {
	Accent = function() return 1, 0.8, 0.2 end,
	Colors = function() return setmetatable({}, { __index = function() return { 1, 1, 1 } end }) end,
	Font = function() return "font" end,
	Text = function(parent) return NewObj("FontString", nil, parent) end,
	Button = Button,
	MainButton = function() end,
	Close = function(parent, onClick)
		local b = NewObj("Button", nil, parent)
		b.scripts.OnClick = onClick
		b.w, b.h = 20, 20
		return b
	end,
	Switch = function(parent)
		local s = NewObj("Button", nil, parent)
		s.w = 36
		function s.SetOn(on) s.on = on end
		return s
	end,
	Input = function(parent, opts)
		local e = NewObj("EditBox", nil, parent)
		e.h = 24
		e.isSearch = opts and opts.search or nil
		return e
	end,
	Bar = function(parent) return NewObj("StatusBar", nil, parent) end,
	-- Daylight UI's dropdown, as it builds it (DaylightUI/Options/Widgets.lua:2656-2666): one
	-- catcher over the screen, UIParent's child in FULLSCREEN_DIALOG, its list 5 levels over it.
	Menu = function(_, keys, values, _, onPick)
		if not DROPDOWN then
			local catcher = NewObj("Button", nil, UIParent)
			catcher:SetFrameStrata("FULLSCREEN_DIALOG")
			local box = NewObj("Frame", nil, catcher)
			box:SetFrameLevel(catcher:GetFrameLevel() + 5)
			DROPDOWN = { catcher = catcher, box = box }
		end
		DROPDOWN.catcher:Show()
		MENU = { keys = keys, values = values, onPick = onPick, catcher = DROPDOWN.catcher, box = DROPDOWN.box }
	end,
	Skin = function(frame, opts)
		rawset(frame, "skin", opts or {})
		if not rawget(frame, "shell") then
			local s = NewObj("Frame", nil, frame)
			s.level = math.max(0, frame.level - 1)
			rawset(frame, "shell", s)
		end
	end,
	Fade = function() end,
	Speed = { FAST = 0.12, NORMAL = 0.2, SLOW = 0.4 },
	GlowAround = function() return true end,
	GetSetting = function() return "circle" end,
	ClassColor = function() return 1, 1, 1 end,
}
local padSkipped = {}
ns.Pad = {
	On = function() return true end,
	Follow = function(frame, close) frame.padClose = close end,
	Popup = function(frame, close) frame.padClose = close end,
	Settle = function() end, Front = function() end, KeepOff = function() end, Remember = function() end,
	Skip = function(frame) padSkipped[frame] = true end,
	Edge = function() end,
	Scroller = function() return { Sync = function() end } end,
	Stick = function() end, Into = function() end,
}
ns.Calc = {
	version = 1,
	Chance = function() return 0.62, 0.62, "ok" end,
	Thresholds = function() return { 160, 170, 175, 180 } end,
	Step = function() return 1 end,
	SkillUps = function() return 1 end,
	Talents = function() return 0, 0, {} end,
	Materials = function() return { { 4306, 3 }, { 2321, 2 } } end,
	Cost = function() return { rows = { { itemID = 4306, count = 3, kind = "ah", unit = 1400, total = 4200 },
		{ itemID = 2321, count = 2, kind = "vendor", unit = 90, total = 180, who = "Vendor" } }, total = 4380, complete = true } end,
	Worth = function(spell) return { itemID = spell + 1, count = 1, routes = { { label = "Auction House", text = "Auction House", value = 6100, profit = 1720 } } } end,
	Money = function(copper) return math.floor(copper) .. "c" end,
	ItemInfo = function(itemID) return "Item " .. itemID, nil, 1, 9 end,
	HasAH = function() return true end,
	Vendor = function() return nil end,
	AH = function() return 100 end,
}
local MISSING = {
	{ spell = 8791, name = "Crimson Silk Vest", required = 185, reachable = true, summary = "Trainer",
		groups = { { title = "Trainers", kind = "trainer", more = 0, lines = { { name = "Tepa", place = { zone = "Thunder Bluff", mapID = 1, x = 44, y = 45 } } } } } },
	{ spell = 8793, name = "Pattern: Shadoweave Mask", required = 245, reachable = false, summary = "Vendor", unknown = true, groups = {} },
}
ns.Where = {
	Missing = function() return MISSING end,
	Rep = function() return nil end,
	StandingName = function() return "Honored" end,
	Npc = function() return nil end,
	Go = function() end,
	ForgetKnown = function() end,
	KnownSet = function() return {} end,
}
local CHAR = { queue = {}, prof = {}, known = {} }
ns.Store = {
	version = 1,
	Char = function() return CHAR end,
	Count = function() return { bags = 5, bank = 2, mail = 0, mine = 7, alts = { { name = "Mira", count = 12 } }, altTotal = 12 } end,
	Alts = function() return { ["Player-1"] = { name = "Mira", class = "MAGE", prof = { [171] = { skill = 140, max = 150 } },
		known = { [171] = { [3839] = true, [8762] = true } } } } end,
	WhoKnows = function() return { "Mira" } end,
	ForgetProfession = function() end,
}
local PLAN = { target = 225, route = { crafts = 58, total = 214000, complete = true, steps = {
	{ kind = "craft", spell = 8762, from = 185, to = 200, count = 12, cost = 52600, complete = true, alts = { { spell = 8772, perPoint = 900 } } },
	{ kind = "rank", at = 225, cap = 300, name = "Artisan", level = 35 },
	{ kind = "craft", spell = 8772, from = 200, to = 205, count = 6, cost = 31200, complete = true, learn = 5000, source = "vendor" },
	{ kind = "gap", at = 205, to = 215 },
} }, shopping = { rows = { { itemID = 4306, need = 96, short = 0, buy = 0, have = { mine = 110, bags = 110, bank = 0, mail = 0, altTotal = 0, alts = {} } },
	{ itemID = 2321, need = 24, short = 24, buy = 24, cost = 2160, vendor = "Tailoring Supplies",
		have = { mine = 0, bags = 0, bank = 0, mail = 0, altTotal = 12, alts = { { name = "Mira", count = 12 } } } } },
	buyTotal = 2160, complete = true } }
local OWN_STEP = 8762
ns.Plan = {
	GOALS = { "cost", "vendor", "disenchant", "auction" },
	GOAL_WORDS = { cost = "Cheapest", vendor = "Vendor", disenchant = "Disenchant", auction = "Auction House" },
	GOAL_LONG = { cost = "cheapest materials", vendor = "after vendoring", disenchant = "after disenchanting", auction = "after selling" },
	Get = function() return PLAN end,
	Targets = function() return { 225, 300 } end,
	Goal = function() return "cost" end,
	SetGoal = function(g) PLAN.goalPicked = g end,
	SetTarget = function(v) PLAN.target = v end,
	CraftNext = function() return { { spell = 8772, chance = 0.4, perPoint = 800, can = 2 } } end,
	RankName = function() return "Expert" end,
	RankLevel = function() return 20 end,
	Forget = function() end,
	-- (As the real one, Plan.lua: for a profession handed to Professionally Lost its step is the
	-- one lit, when that row is on and the recipe is one of ours; else nothing is.)
	CurrentSpell = function()
		local P = ns.ProfLost
		if P and P.Handed and P.Handed("guide", ns.state.line) then
			local theirs = P.Handed("step", ns.state.line) and P.NextStepSpell(ns.state.line) or nil
			return theirs and byID[theirs] and theirs or nil
		end
		return OWN_STEP
	end,
}
ns.Tips = { Best = function() return 8762 end, LineName = function(line) return line == 171 and "Alchemy" or "Tailoring" end }
ns.Cooldowns = {
	List = function() return { { spells = { 3839 }, names = { "Mooncloth" }, icon = 1, readyAt = 0, line = 197 },
		{ spells = { 8762 }, names = { "Transmute" }, icon = 1, readyAt = time() + 4000, line = 171 } } end,
	Left = function() return "1h 6m" end,
	Short = function() return "2h" end,
}
ns.Camping = { 1 }
ns.Camp = { Has = function() return true end, Section = function(d) d:Line("camping items", "small") end,
	Page = function(d) d:Line("camping page", "small") end }
local TAKE = { ours = true, closed = 0 }
ns.Take = { OursNow = function() return TAKE.ours end, Close = function() TAKE.closed = TAKE.closed + 1 end }
ns.Swap = { OnWindow = function(win)
	local b = NewObj("Button", nil, win)
	b.w, b.h = 20, 20
	return b
end }
ns.Guide = { Offer = function() end }
ns.Shop = { Refresh = function() end, Confirm = function(_, _, _, yes) ns.Shop.asked = yes end }
ns.Prices = { Mogul = function() return true end }
C_AddOns = { IsAddOnLoaded = function(name) return rawget(_G, "ProfLost") ~= nil and name == "ProfessionallyLost" end }
DaylightUI = { Set = function(_, _, path, value) SETTINGS[path] = value end }

-- ---- the plugin's own files, in the .toc's order -----------------------------------------------
local function Load(file)
	local chunk = assert(loadfile(ROOT .. "/" .. file))
	chunk("DaylightRecipes", ns)
end
Load("ProfLost.lua")
Load("Queue.lua")
Load("Doc.lua")
Load("Pages.lua")
Load("Craft.lua")
Load("EnchantRow.lua")
Load("Pane.lua")
Load("WindowState.lua")
Load("WindowList.lua")
Load("WindowMenu.lua")
Load("Window.lua")

local Window, Craft, State, W, Menu = ns.Window, ns.Craft, ns.WinState, ns.Win, ns.WinMenu
local S = ns.state

-- No label cut: each tab and each craft-bar button that shows is as wide as its words (and a bit).
local function NoLabelCut(what)
	local parts = Window.TourParts()
	local right = 0
	for _, b in ipairs(parts.tabs) do
		ok(b.w >= 6 * #strip(b.text.textValue) + 2 * State.TAB_MIN_PAD, what .. ": tab '" .. tostring(b.text.textValue) .. "' holds its label")
		right = math.max(right, b.w)
	end
	local cb = W.craftBar
	if cb and cb:IsVisible() then
		for _, key in ipairs({ "make", "max", "queue", "stop" }) do
			local b = cb[key]
			if b:IsShown() then
				ok(b.w >= 6 * #strip(b.text.textValue) + 12, what .. ": button '" .. tostring(b.text.textValue) .. "' holds its label")
			end
		end
	end
	ok(W.col >= State.W, what .. ": the column is at least 420")
end
local function SizeIs(w, h, what)
	local win = W.win
	ok(win.w == w and win.h == h, ("%s: the window is %s x %s (wanted %s x %s)"):format(what, tostring(win.w), tostring(win.h), w, h))
end

-- The mouse over everything that shows, and off again: every hover, tooltip and wheel script runs.
local function Hover(what)
	local n = 0
	local list = {}
	for _, o in ipairs(ALL) do list[#list + 1] = o end
	for _, o in ipairs(list) do
		if o ~= GameTooltip and o:IsVisible() then
			local enter, leave, wheel = o.scripts.OnEnter, o.scripts.OnLeave, o.scripts.OnMouseWheel
			if enter then enter(o) n = n + 1 end
			if leave then leave(o) end
			if wheel then wheel(o, -1) wheel(o, 1) end
		end
	end
	Flush()
	ok(n > 0, what .. ": something to hover")
end
-- A row of a page (a doc's) by its left text.
local function DocRow(text)
	for _, o in ipairs(ALL) do
		if o.kind == "Button" and rawget(o, "left") and o:IsVisible() and strip(o.left.textValue) == text then return o end
	end
end

-- ---- a profession opens: compact, the first recipe picked ----------------------------------------
Window.SessionStarted()
Flush()
local win = W.win
win.left, win.bottom = 16, 404
ok(Window.Shown(), "opening a profession opens the window by itself")
eq(Window.Mode(), "compact", "a first open is compact")
SizeIs(420, 560, "compact")
eq(S.recipe, 3839, "the first recipe is picked")
ok(W.list:IsVisible() and W.summary:IsVisible() and W.craftBar:IsVisible(), "list, summary line and craft bar show")
ok(not W.side:IsVisible(), "the detail column is shut")
eq(W.craftBar.max.text.textValue, "Max 12", "Create All is Max, with how many")
NoLabelCut("compact")
eq(DaylightRecipesDB.win.v, State.VERSION, "the saved state is this layout's")
Hover("compact")

-- Max puts all you can make in the count; Create makes that many.
W.craftBar.max:Click()
eq(W.craftBar.count.textValue, "12", "Max fills the count")
Window.Select(8762)
Flush()
eq(S.recipe, 8762, "a recipe picked from a list row")
ok(strip(W.summary.name.textValue) == "Silk Headband", "the summary line names it")
ok(tostring(W.summary.sub.textValue):find("Materials: 4380c", 1, true) and tostring(W.summary.sub.textValue):find("Sells for 6100c", 1, true),
	"and says what it costs and sells for")

-- ---- details: slide out, remembered per tab ------------------------------------------------------
Window.ToggleDetails()
for _ = 1, 10 do Tick(0.05) end
Flush()
eq(Window.Mode(), "expanded", "Details opens the detail column")
SizeIs(780, 560, "expanded")
ok(W.side:IsVisible(), "the detail column shows")
eq(DaylightRecipesDB.win.details.recipes, true, "remembered for the Recipes tab")
NoLabelCut("expanded")
Hover("expanded")
ok(DocRow("Chance of a Point"), "the detail column has the recipe's skill-up chance")
Window.SetTab("guide")
Flush()
eq(Window.Mode(), "compact", "the Leveling Guide tab has its own answer: shut")
SizeIs(420, 560, "the guide, compact")
Hover("the guide")
-- Goal and Cheapest Route are two pickers (they were two rows of buttons): a press opens a menu.
local pickers = {}
for _, o in ipairs(ALL) do
	if rawget(o, "label") and rawget(o, "button") and rawget(o, "chevron") and o:IsVisible() then pickers[#pickers + 1] = o end
end
eq(#pickers, 2, "two pickers on the guide")
eq(strip(pickers[1].label.textValue), "Goal", "Goal")
eq(strip(pickers[2].label.textValue), "Cheapest Route", "Cheapest Route")
ok(pickers[1].points[1][5] == pickers[2].points[1][5], "on one line at 420")
MENU = nil
pickers[2].button:Click()
ok(MENU and table.concat(MENU.keys, " ") == "cost vendor disenchant auction", "the route's four goals in its menu")
MENU.onPick("vendor")
eq(PLAN.goalPicked, "vendor", "a pick sets the goal")
pickers[1].button:Click()
MENU.onPick("300")
eq(PLAN.target, 300, "a pick sets the target")
PLAN.target = 225
Window.SetTab("materials")
Flush()
Hover("materials")
Window.SetTab("queue")
Flush()
Hover("the queue")
Window.SetTab("missing")
Flush()
Hover("missing")
eq(DaylightRecipesDB.win.tab, "missing", "the last tab is remembered")
-- Missing, compact: a pick opens its sources under its row, as before.
local vest = DocRow("Crimson Silk Vest")
ok(vest and vest.onClick, "a missing recipe's row")
vest.onClick("LeftButton", vest)
Flush()
ok(DocRow("Tepa"), "compact: its sources open under it")
DocRow("Crimson Silk Vest").onClick("LeftButton")
Flush()
ok(not DocRow("Tepa"), "and close again")
-- Missing with the details open: a pick shows its sources there, and the list stays whole.
Window.SetDetails(true)
for _ = 1, 10 do Tick(0.05) end
Flush()
eq(Window.Mode(), "expanded", "details on Missing")
DocRow("Crimson Silk Vest").onClick("LeftButton")
Flush()
local tepa = DocRow("Tepa")
ok(tepa and tepa.parent.parent.parent == W.side, "expanded: its sources show in the detail column")
Hover("missing, expanded")
Window.SetTab("recipes")
Flush()
eq(Window.Mode(), "expanded", "back on Recipes the details are as they were left")
-- B on a controller closes one level at a time.
win.padClose()
for _ = 1, 10 do Tick(0.05) end
Flush()
ok(Window.Shown() and Window.Mode() == "compact", "B closes the details first")
eq(DaylightRecipesDB.win.details.recipes, false, "and that is remembered")

-- ---- the professions menu --------------------------------------------------------------------------
W.nameButton:Click()
ok(Menu.Shown(), "the profession's name opens the menu")
ok(W.menu.w >= 210 and W.menu.w <= W.col - 4, "the menu is 210 at least and inside the column")
ok(W.menu.h <= win.h - State.HEADER, "and inside the window's height")
Hover("the menu")
ok(Menu.Shown(), "hovering changes nothing")
W.menu.padClose()
ok(not Menu.Shown() and Window.Shown(), "B closes the menu, not the window")
Window.ShowAlt("Player-1", 171)
Flush()
ok(Window.Shown() and #Window.TourParts().tabs == 0, "an alt's recipes: no tabs")
eq(Window.Mode(), "compact", "and no detail column")
Hover("an alt's recipes")
Window.ShowGather(182)
Flush()
Hover("a gathering profession")
Window.ShowGather(W.CAMP)
Flush()
Hover("camping")
Window.OpenProfession(197, 197)
Flush()
eq(#Window.TourParts().tabs, 5, "back on your profession: five tabs")
-- The "more" menu on a profession: Link to Chat and Unlearn, neither only in a tooltip. It opens
-- from the row's three-dot button, a right-click, or a controller's Y (the row's padMore).
W.nameButton:Click()
MENU = nil
local row
for _, o in ipairs(ALL) do
	if rawget(o, "more") and rawget(o, "onRight") and o:IsVisible() and strip(o.name.textValue) == "Tailoring" then row = o end
end
ok(row and row.more:IsShown(), "your profession's row has a More button")
ok(padSkipped[row.more], "which is not a second controller stop")
ok(type(row.padMore(row)) == "function", "a controller's Y opens the same menu")
row.more:Click()
ok(MENU and table.concat(MENU.keys, " ") == "link unlearn", "More offers Link to Chat and Unlearn")
eq(MENU.values.link, "Link to Chat", "by name")
MENU.onPick("unlearn")
ok(type(ns.Shop.asked) == "function", "Unlearn asks first")
ok(not Menu.Shown(), "and the menu closes")

-- ---- the hand-off to Professionally Lost ----------------------------------------------------------
local opened = {}
ProfLost = { Guides = { [197] = { name = "Tailoring" } },
	Window = { Pick = function(id) opened[#opened + 1] = "pick " .. id end, Open = function() opened[#opened + 1] = "open" end } }
ProfLostCharDB = { nextStep = { [197] = { spell = 8772 } } }
Window.Render()
eq(#Window.TourParts().tabs, 5, "loaded but nothing handed off: five tabs")
eq(ns.WinList.StepSpell(), 8762, "and our own step is the one marked")
SETTINGS.plGuide = true
Window.SetTab("guide")
Flush()
local tabs = Window.TourParts().tabs
eq(#tabs, 3, "the guide handed off: Leveling Guide and Materials are gone")
eq(Window.TourParts().tab, "recipes", "and the window is on Recipes")
ok(tabs[1].key == "recipes" and tabs[2].key == "queue" and tabs[3].key == "missing", "Recipes, Queue, Missing stay")
NoLabelCut("handed off")
eq(ns.WinList.StepSpell(), nil, "nothing of ours is lit, and its step isn't until that row is on")
SETTINGS.plStep = true
eq(ns.WinList.StepSpell(), 8772, "Light Up Its Step: the recipe its guide is on is marked")
ns.ProfLost.OpenGuide(197)
eq(table.concat(opened, ", "), "pick 197, open", "Open Professionally Lost points its guide at this profession")
SETTINGS.plGuide = false
Window.Render()
eq(#Window.TourParts().tabs, 5, "put back: the tabs return at once")
eq(Window.TourParts().tab, "guide", "on the tab that was asked for")
eq(ns.WinList.StepSpell(), 8762, "and our own step is marked again")
ProfLost, ProfLostCharDB = nil, nil
SETTINGS.plStep = nil
Window.SetTab("recipes")
Flush()

-- ---- making, rolled up, and the secure Stop --------------------------------------------------------
Window.Select(8762)
W.craftBar.count:SetText("3")
W.craftBar.make:Click()
eq(CRAFTED[#CRAFTED][1], 8762, "Create makes the picked recipe")
eq(CRAFTED[#CRAFTED][2], 3, "as many as the count says")
-- (The game says the cast began: the run is under way, and its start and end are noted.)
Fire("UNIT_SPELLCAST_START", "player", "cast-1", 8762)
Flush()
ok(Craft.Making() ~= nil, "a run is under way")
local stop = DaylightRecipesStop
local cb = W.craftBar
ok(stop and stop:IsShown() and cb.stop:IsShown(), "Stop shows, and the secure Stop is out")
eq(stop.attrs.macrotext, "/stopcasting", "it is the game's own /stopcasting")
ok(stop.parent == UIParent, "a child of UIParent")
ok(State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect()), "exactly over the window's Stop")
ok(padSkipped[stop.face], "its face is never a controller stop")
ok(not stop.face:IsShown(), "and stays hidden while the window draws the Stop")
-- The window moves out of a fight: the secure Stop follows on the next frame.
win.left, win.bottom = 500, 300
Tick()
ok(State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect()), "moved out of a fight: the secure Stop follows")
-- Rolled up while making: progress, the queue's count and Stop.
ns.Queue.Add(8772, 2)
Window.SetRolled(true)
Flush()
eq(Window.Mode(), "rolled", "rolled up")
SizeIs(420, 80, "rolled up")
ok(cb:IsVisible() and cb.stop:IsShown() and cb.status:IsShown(), "rolled up: the status and Stop")
eq(cb.queued.text.textValue, "Queue (1)", "and the queue's count")
ok(cb.prog:IsShown(), "and our own progress line")
NOW = NOW + 1.5
local p = Craft.Progress()
ok(p > 0.1 and p < 0.34, "the line is the casts done plus how far this one is: " .. tostring(p))
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8762)
eq(Craft.Making().done, 1, "a cast done")
ok(math.abs(Craft.Progress() - 1 / 3) < 0.001, "one of three done: a third")
ok(not W.list:IsVisible() and not Window.TourParts().tabs[1], "nothing else")
Tick()
ok(State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect()), "rolled up: the secure Stop is over the Stop")
ok(win.padFirst() == cb.stop, "a controller starts on Stop")
Hover("rolled up")
local a = win.padKeys[1].secure(cb.stop)
ok(a and a.macrotext == "/stopcasting", "A on Stop is the secure Stop's action")
eq(win.padKeys[3].label(), "Unroll", "Y unrolls")

-- A fight starts. The window is moved, unrolled, expanded and closed: the secure Stop is never
-- touched (the strict mock would raise), and a Stop that takes a click is always one you can see.
FIGHT = true
local was = Craft.StopRect()
win.left, win.bottom = 900, 600
Tick()
ok(State.SameRect(was, Craft.StopRect()), "in a fight the secure Stop stays where it was")
ok(stop:IsShown() and stop.face:IsShown(), "and shows its own face there")
ok(not cb.stop:IsShown(), "the window draws no Stop that a click would not reach")
Window.SetRolled(false)
Window.SetDetails(true)
for _ = 1, 10 do Tick(0.05) end
Window.SetTab("queue")
Flush()
ok(stop.face:IsShown() and not cb.stop:IsShown(), "through unrolling, details and a tab change: the same")
win:Hide()
ok(stop:IsShown() and stop.face:IsShown(), "the window closed in a fight: the Stop keeps its face")
eq(TAKE.closed, 1, "closing the window ends the trade skill")
win:Show()
Flush()
-- The fight ends: it goes where it belongs.
FIGHT = false
Window.CraftChanged(true)
ok(cb.stop:IsShown() and not stop.face:IsShown(), "after the fight the window's Stop is back")
ok(State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect()), "with the secure Stop over it")
-- The run ends in a fight: the secure Stop can't be put away, so it stays honest, then goes.
FIGHT = true
Craft.Cancel()
ok(Craft.Making() == nil and stop:IsShown(), "a run that ends in a fight leaves the secure Stop out")
ok((cb.stop:IsShown() and State.SameRect(Craft.RectOf(cb.stop), Craft.StopRect())) or stop.face:IsShown(),
	"drawn where it is, by the window or by its own face")
FIGHT = false
Window.CraftChanged(true)
ok(not stop:IsShown(), "and it is put away once the fight is over")
ok(cb.make:IsShown() or not cb:IsVisible(), "the bar is back to Create (or away on this tab)")
-- A craft begun in a fight: no secure Stop can be brought; the bar's Stop is drawn off.
Window.SetTab("recipes")
Flush()
FIGHT = true
cb.make:Click()
Fire("UNIT_SPELLCAST_START", "player", "cast-2", S.recipe)
Flush()
ok(Craft.Making() ~= nil and not stop:IsShown(), "a craft begun in a fight: no secure Stop")
ok(cb.stop:IsShown() and cb.stop.off, "the bar's Stop is drawn off, as a click on it would do nothing")
ok(win.padKeys[1].secure(cb.stop) == nil, "and A is not offered on it")
FIGHT = false
Window.CraftChanged(true)
ok(stop:IsShown() and not cb.stop.off, "the fight over: Stop works")
Craft.Cancel()

-- ---- an enchant: its item row in the bar, the name never cut ---------------------------------------
Window.Select(13503)
Flush()
ok(cb.ench:IsShown(), "an enchant shows its item row")
ok(cb.h >= State.FOOT + 46, "and the bar is as tall as both")
eq(cb.make.text.textValue, "Enchant", "its button is Enchant")
NoLabelCut("an enchant")

-- ---- the height: the setting, a drag, the limits -----------------------------------------------------
Window.SetDetails(false)
for _ = 1, 10 do Tick(0.05) end
Window.SetHeight(650)
eq(SETTINGS.winHeight, 650, "a drag of the edge writes the Window Height setting")
eq(win.h, 650, "and the window is that tall")
Window.SetHeight(5000)
eq(win.h, 720, "720 at most")
Window.ResetPlace()
eq(win.h, 560, "a right-click on the header: the default height")
eq(DaylightRecipesDB.win.spot, nil, "and the default place")
-- The bottom edge dragged: the height at the start plus the mouse's travel, saved on release.
local grip = win.grip
ok(grip:IsShown() and padSkipped[grip], "the grip shows, and is not a controller stop")
local cursorY = 900
GetCursorPosition = function() return 300, cursorY end
grip.scripts.OnMouseDown(grip, "LeftButton")
cursorY = 860
Tick()
eq(win.h, 600, "dragged 40 down: 40 taller, live")
cursorY = -5000
Tick()
eq(win.h, 720, "never past 720")
cursorY = 880
Tick()
grip.scripts.OnMouseUp(grip, "LeftButton")
eq(SETTINGS.winHeight, 580, "the height is saved on release")
eq(win.h, 580, "and kept")
Window.SetHeight(560)
-- Dragged by its header (the mouse is at the header's height here), its place remembered.
win.left, win.bottom = 16, 404
cursorY = win.bottom + win.h - 10
win.scripts.OnDragStart(win)
ok(win.dragging, "a drag on the header moves it")
win.left, win.bottom = 240, 300
win.scripts.OnDragStop(win)
local spot = DaylightRecipesDB.win.spot
ok(spot and spot[1] == 240 and spot[2] == 300 + win.h, "its top-left corner is remembered")
cursorY = win.bottom + 100
win.scripts.OnDragStart(win)
ok(not win.dragging, "a drag on the page does not")

-- ---- a tour unrolls it; closing and opening keeps the state ------------------------------------------
Window.SetRolled(true)
Window.ShowForTour()
ok(Window.Mode() ~= "rolled", "a tour shows the window unrolled")
Window.TourDone()
Window.SetRolled(true)
win:Hide()
Window.SessionStarted()
Flush()
eq(Window.Mode(), "rolled", "opening a profession opens it in the state it was left: rolled up")
Window.SetRolled(false)
Window.SetDetails(true)
for _ = 1, 10 do Tick(0.05) end
win:Hide()
Window.SessionStarted()
Flush()
eq(Window.Mode(), "expanded", "or expanded")
SizeIs(780, 560, "reopened expanded")

-- ==================================================================================================
-- What the audit of the face lift found (design/audit-facelift.md): each one as it broke
-- ==================================================================================================
Window.SetRolled(false)
Window.SetTab("recipes")
Window.SetDetails(false)
for _ = 1, 10 do Tick(0.05) end
Flush()
local cb2 = W.craftBar

-- The frames of the recipe list that are on show, and how far down the lowest one reaches.
local function ListRows()
	local n, lowest = 0, 0
	for _, o in ipairs(ALL) do
		if o.kind == "Button" and o.parent == W.list and o:IsShown() then
			n = n + 1
			lowest = math.max(lowest, -(o.points[1][5]) + o.h)
		end
	end
	return n, lowest
end
local function ListRow(spell)
	for _, o in ipairs(ALL) do
		if o.kind == "Button" and o.parent == W.list and o:IsShown() and rawget(o, "entry") and o.entry.spell == spell then return o end
	end
end
local function Resize(h)
	W.list.h = h
	W.list.scripts.OnSizeChanged(W.list)
end

-- Each finding is a case of its own: one that fails does not stop the rest, so a run against the
-- files as they were names every one of them.
-- after: puts back what the case changed, whether it passed or not, so the next one starts clean.
local FAILED = {}
local function Case(name, fn, after)
	local good, err = pcall(fn)
	if good and #ERRORS > 0 then good, err = false, "an error reached the error handler: " .. ERRORS[1] end
	ERRORS = {}
	if after then
		local tidy, why = pcall(after)
		if not tidy and good then good, err = false, "its clean-up: " .. tostring(why) end
		ERRORS = {}
	end
	if not good then FAILED[#FAILED + 1] = name .. " [" .. tostring(err) .. "]" end
end

-- ---- M6: the list gets shorter, and no row is left below its foot ---------------------------------
Case("M6: the list gets shorter, and no row is left below its foot", function()
	for i = 1, 40 do
		local r = { id = 20000 + i, name = "Recipe " .. i, cat = 1, rd = 1, can = 0 }
		RECIPES[#RECIPES + 1] = r
		byID[r.id] = r
	end
	Window.Dirty()
	Flush()
	Resize(400)
	local n, lowest = ListRows()
	eq(n, 20, "a list 400 tall shows 20 rows")
	ok(lowest <= 400, "all of them inside it")
	-- The window's edge dragged up, a taller summary line, a second row of the craft bar, an
	-- enchant's item row: the list is 100 tall now.
	Resize(100)
	n, lowest = ListRows()
	eq(n, 5, "100 tall: five rows, none left over from the taller list")
	ok(lowest <= 100, "and none below its foot, over the summary line and the craft bar: " .. lowest)
	Resize(60)
	n, lowest = ListRows()
	ok(n == 3 and lowest <= 60, "shorter still: three")
	Resize(400)
	eq((ListRows()), 20, "taller again: its rows are back")
end, function()
	while RECIPES[#RECIPES].id > 20000 do
		local r = table.remove(RECIPES)
		byID[r.id] = nil
	end
	Window.Dirty()
	Flush()
	Resize(200)
end)
eq(#RECIPES, 4, "the profession's own four recipes again")

-- ---- L15: a name too long even a size down takes the count's room ----------------------------------
Case("L15: a name too long even a size down takes the count's room", function()
	TRUNC = function(fs) return #strip(fs.textValue) > 40 end
	Resize(200)
	local long = ListRow(13503)
	ok(long, "the enchant with the very long name is in the list")
	ok(long.nameSmall:IsShown() and not long.name:IsShown(), "a name too long at 13 is drawn at 12")
	ok(not long.right:IsShown(), "still too long: the count gives its room to the name")
	local at = long.nameSmall.points[#long.nameSmall.points]
	ok(at[1] == "RIGHT" and at[2] == long, "and the name runs to the row's own edge")
	local short = ListRow(3839)
	ok(short.name:IsShown() and short.right:IsShown() and short.right.textValue == "[12]", "a name that fits keeps its size and its count")
	TRUNC = nil
	Resize(200)
	ok(ListRow(13503).right:IsShown(), "in a font it fits in, the count is back")
end, function()
	TRUNC = nil
	Resize(200)
end)

-- ---- M9 and L18: the column is as wide as the craft bar's one row needs, and stays that wide ----------
Case("M9 and L18: the column is as wide as the craft bar's one row needs, and stays that wide", function()
	local L = ns.L
	Window.Select(8762)
	Flush()
	eq(W.col, 420, "English: the 420 column")
	eq(cb2.h, State.FOOT, "and the craft bar on one row")
	-- German's words (Locales/deDE.lua): the bar's own are longer than the tabs'.
	rawset(L, "Queue", "Warteschlange")
	rawset(L, "Max %d", "Max. %d")
	rawset(L, "Max", "Max.")
	rawset(L, "Create", "Herstellen")
	Window.Render()
	Flush()
	ok(W.col > 420 and W.col <= State.MAX_W, "German: the column grows for the bar, within 520: " .. W.col)
	eq(cb2.h, State.FOOT, "so the bar is one row (it was two, 76 tall, in a 420 column)")
	eq(cb2.queue.text.textValue, "Warteschlange", "with Queue in its own word, uncut")
	ok(cb2.queue.w >= 6 * #"Warteschlange" + 12, "and room for it")
	SizeIs(W.col, 560, "German, compact")
	NoLabelCut("German")
	local german = W.col
	Window.Select(3839)
	Flush()
	eq(W.col, german, "another recipe (Max. 12 for Max. 4): the same column")
	Window.Select(8772)
	Flush()
	eq(W.col, german, "one you can make none of (Max.): the same column")
	Window.SetRolled(true)
	Flush()
	SizeIs(german, State.HEADER + State.FOOT, "rolled up in German: one row too")
	Window.SetRolled(false)
	-- The queue's tab: the column does not move as the queue fills.
	rawset(L, "Queue (%d)", "Warteschlange (%d)")
	Window.Render()
	Flush()
	local one = W.col
	for i = 1, 11 do ns.Queue.Add(3839, i) end
	ns.Queue.Add(8762, 1)
	ns.Queue.Add(13503, 1)
	Window.Render()
	Flush()
	ok(ns.Queue.Count() >= 3, "more in the queue")
	local tabs2 = Window.TourParts().tabs
	local label
	for _, b in ipairs(tabs2) do if b.key == "queue" then label = b.text.textValue end end
	ok(label and label:find("Warteschlange (", 1, true), "the queue's tab counts them: " .. tostring(label))
	eq(W.col, one, "and the column is as wide as with one queued")
	NoLabelCut("a long queue label")
	-- An alt's page has no tabs: the column keeps its width.
	Window.ShowAlt("Player-1", 171)
	Flush()
	eq(W.col, one, "an alt's page: the same column, nothing snaps to 420 and back")
end, function()
	W.alt, W.gather = nil, nil
	Window.SetRolled(false)
	for _, key in ipairs({ "Queue", "Max %d", "Max", "Create", "Queue (%d)" }) do rawset(ns.L, key, nil) end
	Window.Render()
	Flush()
end)
eq(W.col, 420, "English again: 420")
eq(cb2.h, State.FOOT, "and one row")

-- ---- M7: the "more" menu opens wholly over the professions menu ------------------------------------
Case("M7: the \"more\" menu opens wholly over the professions menu", function()
	local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
	-- `top` is drawn over `under`, and takes a press before it: by strata first, then by level.
	local function Over(top, under)
		local st, su = STRATA[top:GetFrameStrata()], STRATA[under:GetFrameStrata()]
		if st ~= su then return st > su end
		return top:GetFrameLevel() > under:GetFrameLevel()
	end
	local function Inside(o, root)
		while o do
			if o == root then return true end
			o = o.parent
		end
		return false
	end
	local function Check(what)
		W.nameButton:Click()
		ok(Menu.Shown(), what .. ": the professions menu is open")
		local ours = W.menu.parent
		local more
		for _, o in ipairs(ALL) do
			if rawget(o, "more") and rawget(o, "onRight") and o:IsVisible() and strip(o.name.textValue) == "Tailoring" then more = o end
		end
		MENU = nil
		more.more:Click()
		ok(MENU and MENU.catcher and MENU.catcher:IsShown(), what .. ": More opened Daylight UI's dropdown")
		local n = 0
		for _, o in ipairs(ALL) do
			if (o.kind == "Frame" or o.kind == "Button") and Inside(o, ours) and o:IsVisible() then
				n = n + 1
				ok(Over(MENU.catcher, o), what .. ": every frame of our menu is under the dropdown's catcher (a press beside the box reaches the catcher, not a profession)")
				ok(Over(MENU.box, o), what .. ": and under its box (nothing of the menu shows through it)")
			end
		end
		ok(n > 5, what .. ": the menu's frames were looked at: " .. n)
		ok(Over(ours, win) and Over(W.menu, win), what .. ": and the menu is over the window")
		MENU.catcher:Hide()
		Menu.Close()
	end
	Check("the window in its own layer")
	-- A tour holds the window in FULLSCREEN: the menu still opens over it.
	Window.ShowForTour()
	W.nameButton:Click()
	ok(Over(W.menu.parent, win), "in a tour the menu is over the raised window")
end, function()
	if MENU and MENU.catcher then MENU.catcher:Hide() end
	Menu.Close()
	Window.TourDone()
end)

-- ---- L16: more rows than fit in the menu, and something says so -------------------------------------
Case("L16: more rows than fit in the menu, and something says so", function()
	W.nameButton:Click()
	ok(W.menuThumb ~= nil and W.menuList ~= nil, "the menu has a thumb for its list")
	W.menuList.h = 60
	Menu.Paint()
	ok(W.menuThumb:IsShown(), "a list taller than its room shows a thumb")
	ok(W.menuThumb.h >= 24 and W.menuThumb.h <= 60, "as tall as the share of it on show, 24 at least: " .. W.menuThumb.h)
	eq(W.menuThumb.points[1][5], 0, "at the top while nothing is scrolled")
	W.menu.scripts.OnMouseWheel(W.menu, -1)
	ok(W.menuThumb.points[1][5] < 0, "the wheel scrolls the rows and the thumb moves down")
	W.menuList.h = 5000
	Menu.Paint()
	ok(not W.menuThumb:IsShown(), "everything fits: no thumb")
end, function()
	if W.menuList then W.menuList.h = 0 end
	Menu.Close()
end)

-- ---- L12: with the menu open, the window's own keys do nothing underneath ----------------------------
Case("L12: with the menu open, the window's own keys do nothing underneath", function()
	Window.Select(8762)
	Flush()
	local keyX, keyY = win.padKeys[2], win.padKeys[3]
	ok(keyX.key == "X" and keyY.key == "Y", "the window's X and Y")
	ok(keyX.when() == true and keyY.when(nil) == true, "menu shut: X is Create, Y is Details")
	local list = win.padTabs()
	eq(#list, 5, "and LB / RB step five tabs")
	W.nameButton:Click()
	ok(keyX.when() == false, "menu open: X does not press Create under it")
	ok(keyY.when(nil) == false, "nor Y open the details")
	local made = #CRAFTED
	keyX.run()
	eq(#CRAFTED, made, "X run all the same crafts nothing")
	eq(#(win.padTabs()), 0, "and LB / RB have no tab to step to")
	Menu.Close()
	ok(keyX.when() == true and #(win.padTabs()) == 5, "menu shut: they are back")
end, function() Menu.Close() end)

-- ---- L13: someone's linked recipes always say whose they are ----------------------------------------
local notLinked = C_TradeSkillUI.IsTradeSkillLinked
local function Own()
	S.linked = false
	C_TradeSkillUI.IsTradeSkillLinked = notLinked
	Window.Render()
	Flush()
end
Case("L13: someone's linked recipes always say whose they are", function()
	local function Note()
		for _, o in ipairs(ALL) do
			if o.kind == "FontString" and type(o.textValue) == "string" and o.textValue:find("'s recipes", 1, true) then return o end
		end
	end
	S.linked = true
	C_TradeSkillUI.IsTradeSkillLinked = function() return true, "Bob" end
	Window.Render()
	Flush()
	local note = Note()
	ok(note and note:IsShown() and note.textValue == "Bob's recipes", "a short name: the owner's note after the profession's")
	C_TradeSkillUI.IsTradeSkillLinked = function() return true, "Bartholomeusz of the Very Long Name" end
	Window.Render()
	Flush()
	note = Note()
	ok(note:IsShown(), "a long name: the note is still there (it was dropped, and nothing said the recipes were not yours)")
	local room = State.HeaderRoom(W.col, 4)
	local name
	for _, o in ipairs(ALL) do
		if o.kind == "FontString" and o.parent == W.nameButton and o:IsShown() and o.textValue == "Tailoring" then name = o end
	end
	ok(name, "the profession's name shows too")
	local noteW = note.w > 0 and note.w or 6 * #note.textValue
	ok(name.w + 10 + noteW <= room, "and the two fit the header's room: " .. name.w .. " + " .. noteW .. " in " .. room)
	ok(note.w > 0 and note:GetStringHeight() > 14, "the note wraps rather than be cut")
	ok(not cb2:IsVisible(), "someone's recipes: no craft bar")
end, Own)

-- ---- L14: rolled up with nothing to craft is not an empty bar ----------------------------------------
Case("L14: rolled up with nothing to craft is not an empty bar", function()
	Window.SetRolled(true)
	Flush()
	eq(Window.Mode(), "rolled", "your own profession, rolled up")
	S.linked = true
	C_TradeSkillUI.IsTradeSkillLinked = function() return true, "Bob" end
	Window.Render()
	Flush()
	ok(Window.Mode() ~= "rolled", "left rolled up, someone's recipes open: shown unrolled (there is no craft bar to roll up to)")
	ok(W.list:IsVisible(), "their recipes show")
	ok(not Window.TourParts().roll:IsShown(), "and there is no Roll Up button to press")
	ok(Window.TourParts().details:IsShown(), "Details is still there")
	eq(DaylightRecipesDB.win.rolled, true, "the choice is kept")
	Own()
	eq(Window.Mode(), "rolled", "your own profession again: rolled up, as it was left")
	ok(Window.TourParts().roll:IsShown(), "with its button")
	local mode = S.mode
	S.mode = nil
	Window.Render()
	Flush()
	ok(Window.Mode() ~= "rolled", "no profession open: unrolled too")
	S.mode = mode
end, function()
	S.mode = "win"
	Own()
	Window.SetRolled(false)
	Flush()
end)

-- ---- L17: a tour changes nothing that is remembered --------------------------------------------------
Case("L17: a tour changes nothing that is remembered", function()
	Window.SetTab("queue")
	Window.SetRolled(true)
	Flush()
	eq(Window.Mode(), "rolled", "rolled up on the Queue tab")
	Window.ShowForTour()
	ok(Window.Mode() ~= "rolled", "a tour shows the window unrolled")
	eq(Window.TourParts().tab, "recipes", "on its Recipes tab")
	eq(DaylightRecipesDB.win.rolled, true, "without touching the rolled-up choice")
	Window.SetTab("missing")          -- (as a step of the tour does)
	Flush()
	Window.TourDone()
	Flush()
	eq(Window.Mode(), "rolled", "the tour over: rolled up again")
	eq(DaylightRecipesDB.win.tab, "queue", "and the tab remembered is the one the player left")
	Window.SetRolled(false)
	Flush()
	eq(Window.TourParts().tab, "queue", "unrolled: on that tab")
end, function()
	Window.TourDone()
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

-- ---- L19: the height lives in the Window Height setting alone -----------------------------------------
Case("L19: the height lives in the Window Height setting alone", function()
	Window.SetHeight(600)
	eq(SETTINGS.winHeight, 600, "a drag writes the setting")
	eq(DaylightRecipesDB.win.h, nil, "and no second copy in the window's saved state")
end, function() Window.SetHeight(560) end)

-- ---- L11: cast times that may be secret are tested for that before anything else looks at them -------
Case("L11: cast times that may be secret are tested for that before anything else looks at them", function()
	local f = assert(io.open(ROOT .. "/Craft.lua", "r"))
	local src = f:read("*a")
	f:close()
	local note = src:match("function Craft%.NoteCast%(run%)(.-)\nend\n")
	ok(note, "Craft.NoteCast is there")
	local secretAt = note:find("secret(from)", 1, true)
	ok(secretAt, "it asks issecretvalue of the cast's start")
	for _, early in ipairs({ "from == nil", "to == nil", "from ~= nil", "to ~= nil" }) do
		ok(not note:find(early, 1, true), "nothing compares them with nil (" .. early .. ")")
	end
	ok(secretAt < note:find("type(from)", 1, true), "the secret test comes before their type is asked")
	ok(secretAt < note:find("to <= from", 1, true), "and before they are compared")
	local rect = src:match("function Craft%.StopRect%(%)(.-)\nend\n")
	ok(rect and not rect:find("left == nil", 1, true), "Craft.StopRect compares nothing with nil either")
	ok(rect:find("secret(left)", 1, true) < rect:find("type(left)", 1, true), "secret first there too")
	-- And with secret numbers the run simply has no cast times: the line moves a cast at a time.
	local wasInfo, wasSecret = UnitCastingInfo, issecretvalue
	local SECRET = {}
	UnitCastingInfo = function() return "x", "x", 1, SECRET, SECRET end
	local run = { castStart = 1, castEnd = 2 }
	Craft.NoteCast(run)
	ok(run.castStart == nil and run.castEnd == nil, "values that are not plain numbers are not kept")
	UnitCastingInfo, issecretvalue = wasInfo, wasSecret
end, function() UnitCastingInfo = function() return "x", "x", 1, NOW * 1000, (NOW + 3) * 1000 end end)

-- ---- L21: a picker's choice wider than the page wraps inside its button --------------------------------
Case("L21: a picker's choice wider than the page wraps inside its button", function()
	local holder = NewObj("Frame", nil, UIParent)
	holder.w = 200
	local d = ns.Doc.New(holder, { pad = 14, width = 200 })
	local words = "Whatever Sells for the Most at the Auction House Today"
	d:Begin()
	d:Pickers({ { label = "Cheapest Route", keys = { "a" }, values = { a = words }, current = "a" } })
	d:Finish()
	local picker
	for _, o in ipairs(ALL) do
		if rawget(o, "label") and rawget(o, "button") and rawget(o, "chevron") and o.button.text.textValue == words then picker = o end
	end
	ok(picker, "the picker")
	ok(picker.button.w <= 200 - 28, "its button is as wide as the page at most: " .. picker.button.w)
	local text = picker.button.text
	ok(text.w > 0 and text.w <= picker.button.w - 37, "its words have the button's room, less the arrow's")
	ok(text:GetStringHeight() > 14, "and wrap in it")
	ok(picker.button.h >= text:GetStringHeight() + 10, "the button is as tall as they need: " .. picker.button.h)
	ok(picker.h >= picker.button.h + 16, "and the picker as tall as its label and button")
	d:Begin()
	d:Pickers({ { label = "Goal", keys = { "a" }, values = { a = "300" }, current = "a" } })
	d:Finish()
	ok(picker.button.h == 24 and picker.button.text.w == 0, "a short choice in the same picker: the ordinary button again")
end)

-- (The cases' verdict comes at the very end, after the docked pane's own.)

-- ---- the docked pane: its fold tab at the top corner, flush on a host we place ---------------------
do
	local Pane = ns.Pane
	win:Hide()
	local function FoldTab()
		for _, o in ipairs(ALL) do
			if o.kind == "Button" and rawget(o, "bars") and o.w == 14 and o.h == 34 then return o end
		end
	end
	local function Tabs()
		local out = {}
		for _, o in ipairs(ALL) do
			if rawget(o, "tabs") and rawget(o, "pl") then
				for _, b in ipairs(o.tabs) do if b:IsShown() then out[#out + 1] = b.key end end
				return out, o
			end
		end
		return out
	end
	S.mode = "dui"
	S.recipe = 8762
	Pane.Render()
	local tab = FoldTab()
	ok(tab and tab:IsShown(), "the pane has its fold tab")
	local host = tab.parent
	local at = tab.points[1]
	ok(at[1] == "TOPLEFT" and at[2] == host and at[3] == "TOPRIGHT" and at[4] == -3 and at[5] == -14,
		"open: at the pane's top corner, on its outer edge, 14 down (never mid-edge)")
	Pane.SetFolded(true)
	for _ = 1, 10 do Tick(0.05) end
	at = tab.points[1]
	ok(at[1] == "TOPLEFT" and at[2] == host and at[3] == "TOPLEFT" and at[5] == -14,
		"folded: at the same top corner, on the window's edge")
	eq(at[4], -6 - 3, "across Daylight UI's own 6 px gap, tucked 3 under the edge")
	Pane.SetFolded(false)
	for _ = 1, 10 do Tick(0.05) end
	local keys, root = Tabs()
	eq(table.concat(keys, " "), "recipe plan missing", "the pane's three tabs")
	ok(not root.pl:IsShown(), "no Professionally Lost button while nothing is handed off")
	ProfLost = { Guides = { [197] = {} }, Window = { Pick = function() end, Open = function() end } }
	SETTINGS.plGuide = true
	Pane.Render()
	eq(table.concat((Tabs()), " "), "recipe missing", "the guide handed off: the pane's Guide tab is gone")
	ok(root.pl:IsShown() and root.pl.w >= 6 * #"Open Professionally Lost", "and Open Professionally Lost is offered, uncut")
	SETTINGS.plGuide = false
	Pane.Render()
	eq(table.concat((Tabs()), " "), "recipe plan missing", "put back: the Guide tab returns")
	ProfLost = nil
	-- On DaylightMogul's window the pane is ours to place: flush, no gap.
	local mogul = NewObj("Frame", "DaylightMogulCraft", UIParent)
	Pane.AttachMogul(mogul)
	local pane = DaylightRecipesPane
	ok(pane and pane.points[1][2] == mogul and pane.points[1][3] == "TOPRIGHT" and pane.points[1][4] == 0,
		"on DaylightMogul's window the pane is flush against its right edge")
	S.mode = "mogul"
	Pane.Render()
	Pane.SetFolded(true)
	for _ = 1, 10 do Tick(0.05) end
	tab = FoldTab()
	at = tab.points[1]
	ok(at[2] == pane and at[3] == "TOPLEFT" and at[4] == -3 and at[5] == -14, "its fold tab at the top corner, on that same edge")
	Pane.SetFolded(false)
	for _ = 1, 10 do Tick(0.05) end
	-- A host in Daylight UI's bordered shell: the two share one border line (the border's thickness
	-- from the player's setting, 8 screen pixels on a 1080-high screen here).
	DaylightUI.Style = { GetShell = function(frame) return frame == mogul and { opts = {} } or nil end }
	ns.API.GetSetting = function(scope, path) return scope == "general" and path == "borderPx" and 8 or "circle" end
	GetPhysicalScreenSize = function() return 1920, 1080 end
	Pane.Render()
	local seam = 8 * 768 / 1080
	ok(math.abs(pane.points[1][4] + seam) < 0.001 and pane.points[1][3] == "TOPRIGHT",
		"a host in Daylight UI's shell: the pane tucks in by exactly its border")
	-- A shell with a border of its own (Style.BorderPx, as Daylight UI's own docking asks): that one.
	Case("L20: the pane's seam is the host's own border where its shell has one", function()
		DaylightUI.Style.BorderPx = function(frame) return frame == mogul and 4 or 8 end
		Pane.Render()
		ok(math.abs(pane.points[1][4] + 4 * 768 / 1080) < 0.001, "a host whose shell has its own border: tucked in by that, not the general setting")
		DaylightUI.Style.BorderPx = function() error("changed in a later version") end
		Pane.Render()
		ok(math.abs(pane.points[1][4] + seam) < 0.001, "a BorderPx that raises: the general setting, no error")
	end, function() DaylightUI.Style.BorderPx = nil end)
	DaylightUI.Style = { GetShell = function() return { opts = { noBorder = true } } end }
	Pane.Render()
	eq(pane.points[1][4], 0, "a host with no border: flush, no overlap")
	DaylightUI.Style = nil
	-- An enchant in the pane: its item row as tall as its words need.
	S.recipe = 13503
	Pane.Render()
	ok(Pane.EnchantPart() ~= nil, "an enchant picked: the pane's enchant section shows")
end

-- ---- rolled up: the bar always says what it acts on ---------------------------------------------
-- (From the game: "I currently have an item I can make in the Queue but I don't see it in the roll
-- mode": a bar with Queue, the count, Max and a dim Create, and no word on which recipe.)
-- (The pane's cases above left the pane's mode: the window again, on your own profession.)
S.mode, S.linked = "win", false
Window.SessionStarted()
Flush()
Case("rolled up: the picked recipe is named, and kept across rolling up and unrolling", function()
	ns.Queue.Clear()
	Window.SetTab("recipes")
	Window.Select(8772)                 -- Crimson Silk Belt: none can be made
	Flush()
	Window.SetRolled(true)
	Flush()
	local bar = W.craftBar
	eq(Window.Mode(), "rolled", "rolled up")
	eq(S.recipe, 8772, "the pick is kept by rolling up")
	ok(bar.what:IsShown(), "the bar says what it acts on")
	eq(bar.what.text.textValue, "Crimson Silk Belt", "the picked recipe's name")
	ok(bar.make:IsShown() and bar.make.off, "Create is off: none of it can be made (why it was dim)")
	eq(bar.make.text.textValue, "Create", "and reads Create")
	ok(bar.queue:IsShown() and bar.count:IsShown() and bar.max:IsShown(), "with the Recipes tab's controls")
	ok(win.h > State.HEADER + State.FOOT, "the window is a line taller for the name, not cut for it")
	ok(win.h <= State.HEADER + State.FOOT + 30, "one line")
	Window.Select(8762)                 -- Silk Headband: four can be made
	Flush()
	eq(bar.what.text.textValue, "Silk Headband", "another pick: its name")
	ok(not bar.make.off, "Create is on for one that can be made")
	Window.SetRolled(false)
	Flush()
	eq(S.recipe, 8762, "the pick is kept by unrolling")
	ok(not bar.what:IsShown(), "unrolled, the list shows the pick: no line of the bar's own")
	SizeIs(W.col, DaylightRecipesDB.win.h or 560, "unrolled: its own size again")
	-- A press on the name unrolls onto the Recipes tab.
	Window.SetTab("queue")
	Window.SetRolled(true)
	Flush()
	bar.what:Click()
	Flush()
	ok(Window.Mode() ~= "rolled", "a press on the name unrolls")
	eq(Window.TourParts().tab, "recipes", "onto the Recipes tab")
end, function()
	ns.Queue.Clear()
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

Case("rolled up: something queued that can be made is the bar's, with one button that makes it", function()
	ns.Queue.Clear()
	Window.SetTab("recipes")
	Window.Select(8772)                 -- the pick: none can be made
	ns.Queue.Add(8762, 3)               -- queued: Silk Headband x 3 (four can be made)
	ns.Queue.Add(3839, 2)
	Window.SetRolled(true)
	Flush()
	local bar = W.craftBar
	ok(bar.what:IsShown(), "the bar says what it acts on")
	eq(bar.what.text.textValue, "Queue: Silk Headband x 3 · and 1 more", "the queue's next, how many, and what waits behind it")
	eq(bar.make.text.textValue, "Craft Next", "one button: Craft Next")
	ok(bar.make:IsShown() and not bar.make.off, "which is on, though the picked recipe can't be made")
	ok(not bar.queue:IsShown() and not bar.count:IsShown() and not bar.max:IsShown() and not bar.plus:IsShown(),
		"the pick's controls give way")
	ok(not bar.queued:IsShown(), "and the bare count of the queue: the line says it")
	SizeIs(W.col, State.HEADER + State.FOOT, "still one row: the name sits beside the button")
	eq(S.recipe, 8772, "the pick is not changed by it")
	eq(win.padKeys[2].label(), "Craft Next", "a controller's X reads Craft Next")
	local n = #CRAFTED
	bar.make:Click()
	eq(#CRAFTED, n + 1, "a press makes")
	eq(CRAFTED[#CRAFTED][1], 8762, "the queue's next, not the pick")
	eq(CRAFTED[#CRAFTED][2], 3, "as many as are queued of it")
	-- More queued than can be made: what can be made.
	ns.Queue.Clear()
	ns.Queue.Add(8762, 9)
	Window.Render()
	Flush()
	eq(bar.what.text.textValue, "Queue: Silk Headband x 9", "nine queued, nothing behind")
	bar.make:Click()
	eq(CRAFTED[#CRAFTED][2], 4, "four can be made: four are, as the Queue tab's Craft Next does")
	-- A press on the line unrolls onto the Queue tab.
	bar.what:Click()
	Flush()
	ok(Window.Mode() ~= "rolled", "a press on the line unrolls")
	eq(Window.TourParts().tab, "queue", "onto the Queue tab")
end, function()
	ns.Queue.Clear()
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

Case("rolled up: the queue's next short of materials says so; a later one is not made in its place", function()
	ns.Queue.Clear()
	Window.SetTab("recipes")
	Window.Select(8762)
	ns.Queue.Add(8772, 2)               -- next: Crimson Silk Belt, none can be made
	ns.Queue.Add(8762, 1)               -- behind it: one that can
	Window.SetRolled(true)
	Flush()
	local bar = W.craftBar
	ok(bar.what.text.textValue:find("Queue: Crimson Silk Belt x 2 · and 1 more", 1, true), "the queue's next is named, in its order")
	ok(bar.what.text.textValue:find("Short of Materials", 1, true), "and the bar says you are short of materials for it")
	ok(bar.make:IsShown() and bar.make.off, "Craft Next is off")
	local n = #CRAFTED
	bar.make.scripts.OnClick(bar.make)
	eq(#CRAFTED, n, "a press on it makes nothing: the entry behind is not made in its place")
	ok(win.padKeys[2].when() == false, "a controller's X is not offered for a button that is off")
	-- With nothing picked at all, the queue alone gives the window something to roll up to.
	S.recipe = nil
	ns.Queue.Clear()
	ns.Queue.Add(8762, 1)
	Window.Render()
	Flush()
	eq(Window.Mode(), "rolled", "nothing picked, something queued: still rolled up")
	eq(bar.what.text.textValue, "Queue: Silk Headband x 1", "on the queue's next")
end, function()
	ns.Queue.Clear()
	S.recipe = 8762
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

Case("rolled up: during a run the status names the recipe, and Stop is where it was", function()
	ns.Queue.Clear()
	Window.SetTab("recipes")
	Window.Select(8762)
	ns.Queue.Add(8762, 2)
	Window.SetRolled(true)
	Flush()
	local bar = W.craftBar
	bar.make:Click()
	Fire("UNIT_SPELLCAST_START", "player", "cast-9", 8762)
	Flush()
	ok(Craft.Making() ~= nil, "a run is under way")
	ok(bar.stop:IsShown() and bar.status:IsShown(), "Stop and the status")
	ok(bar.status.textValue:find("Silk Headband", 1, true) and bar.status.textValue:find("Making 1 of 2", 1, true),
		"the status names what is being made: " .. tostring(bar.status.textValue))
	ok(not bar.what:IsShown() and not bar.make:IsShown(), "no Craft Next under a run")
	Tick()
	ok(State.SameRect(Craft.RectOf(bar.stop), Craft.StopRect()), "the secure Stop is over the Stop")
	ok(win.padFirst() == bar.stop, "a controller starts on Stop")
	Craft.Cancel()
	Flush()
end, function()
	if Craft.Making() then Craft.Cancel() end
	ns.Queue.Clear()
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

Case("rolled up: a long name wraps, and the window grows for it rather than cut it", function()
	ns.Queue.Clear()
	Window.SetTab("recipes")
	Window.Select(13503)                -- "Enchant Weapon - Lesser Striking With a Very Long Name Indeed"
	Window.SetRolled(true)
	Flush()
	local bar = W.craftBar
	ok(bar.what:IsShown() and bar.what.text.textValue:find("Very Long Name Indeed", 1, true), "the whole name")
	ok(bar.what.text.w <= W.col - 2 * State.PAD + 1, "no wider than the column")
	ok(bar.what.h >= bar.what.text:GetStringHeight(), "as tall as its lines")
	ok(win.h >= State.HEADER + State.FOOT + bar.what.text:GetStringHeight(), "and the window is taller by them")
	-- Queued: beside the button, wrapped in the room left of it.
	ns.Queue.Add(13503, 2)
	Window.Render()
	Flush()
	ok(bar.what.text.textValue:find("Queue: Enchant Weapon", 1, true), "queued: named on the bar")
	ok(bar.what.text.w <= W.col - 2 * State.PAD - bar.make.w - 12 + 1, "in the room beside the button")
	ok(bar.what.text.w + bar.make.w < W.col, "the two do not meet")
end, function()
	ns.Queue.Clear()
	S.recipe = 8762
	Window.SetRolled(false)
	Window.SetTab("recipes")
	Flush()
end)

-- ---- 3.0.1: a profession's row opens it by its spell -------------------------------------------------
-- Cooking and First Aid did not open from the menu: it asked the game by skill line. A row now
-- carries the profession's spell and a secure button over it casts that, as the game's tabs do.
local realProfessions, realProfessionInfo = GetProfessions, GetProfessionInfo
local realOpen = C_TradeSkillUI.OpenTradeSkill
Case("3.0.1: a profession's row opens it by its spell", function()
	local asked = {}
	C_TradeSkillUI.OpenTradeSkill = function(line) asked[#asked + 1] = line return true end
	-- (As this client lists them: two primaries, then First Aid, Fishing, Cooking.)
	GetProfessions = function() return 1, 2, 4, 3, 5 end
	GetProfessionInfo = function(i)
		if i == 4 then return "First Aid", 9, 79, 150, 0, 60, 129 end
		if i == 5 then return "Cooking", 10, 153, 225, 0, 40, 185 end
		local name, icon, skill, max, n, _, line = realProfessionInfo(i)
		return name, icon, skill, max, n, i * 10, line
	end
	ns.LINES[185], ns.LINES[129] = true, true
	Enum = { SpellBookSpellBank = { Player = 0 } }
	C_SpellBook = { GetSpellBookItemInfo = function(slot, bank)
		if bank ~= 0 then error("the player's spell bank") end
		return { spellID = 5000 + slot }
	end }
	-- (Herbalism's and Fishing's spells show no crafting window.)
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function(spell) return spell ~= 5021 and spell ~= 5031 end
	local function RowOf(name)
		local found
		for _, o in ipairs(ALL) do
			if rawget(o, "more") and o:IsVisible() and strip(o.name.textValue) == name then found = o end
		end
		return found
	end
	W.nameButton:Click()
	ok(Menu.Shown(), "the menu is open")
	local cooking, aid, tailoring, herbs = RowOf("Cooking"), RowOf("First Aid"), RowOf("Tailoring"), RowOf("Herbalism")
	ok(cooking and aid and tailoring and herbs, "Cooking and First Aid are listed with the others")
	eq(cooking.cast, 5041, "Cooking's row carries its spell: the first in its part of the spellbook")
	eq(aid.cast, 5061, "and First Aid's row its own")
	eq(tailoring.cast, nil, "the profession open now has none: casting it again would close it")
	eq(herbs.cast, nil, "a gathering profession has none")
	-- The mouse on Cooking's row: the secure button comes over it, set to that spell.
	cooking.left, cooking.bottom, cooking.w, cooking.h = 300, 500, 206, 34
	cooking.more.left, cooking.more.bottom = 480, 507
	W.menuList.left, W.menuList.bottom, W.menuList.h = 300, 200, 400
	cooking.scripts.OnEnter(cooking)
	local cast = _G.DaylightRecipesMenuCast
	ok(cast and cast:IsShown(), "a secure button is over the row")
	ok(rawget(cast, "secure") and cast.parent == UIParent, "the game's own kind, on the screen alone")
	eq(cast.attrs.type1, "spell", "a left click casts a spell")
	eq(cast.attrs.spell, 5041, "Cooking's")
	eq(cast.px, 300, "at the row's left")
	eq(cast.py, 500, "and bottom")
	eq(cast.h, 34, "as tall as the row")
	eq(cast.w, 178, "and as wide as the row left of its More button")
	ok(cast.level > cooking.level, "over the row")
	eq(cast:GetFrameStrata(), W.menu.parent:GetFrameStrata(), "in the menu's own layer")
	-- The click: the game casts (its own handler), then ours closes the menu. Nothing is asked by line.
	cast.scripts.PreClick(cast, "LeftButton")
	cast.scripts.PostClick(cast, "LeftButton")
	ok(not Menu.Shown(), "the click closes the menu")
	ok(not cast:IsShown(), "and puts the button away")
	eq(#asked, 0, "the game was not asked by skill line")
	-- A row scrolled half out of the list: only the part on show takes the click.
	W.nameButton:Click()
	cooking = RowOf("Cooking")
	cooking.left, cooking.bottom, cooking.w, cooking.h = 300, 190, 206, 34
	cooking.scripts.OnEnter(cooking)
	eq(cast.py, 200, "a row half under the list's foot: the button stops at the foot")
	eq(cast.h, 24, "and covers what shows")
	-- A right-click on it: the row's More menu, and the button out of its way.
	MENU = nil
	cast.scripts.PreClick(cast, "RightButton")
	cast.scripts.PostClick(cast, "RightButton")
	ok(MENU and table.concat(MENU.keys, " ") == "link", "a right-click opens Cooking's More menu")
	ok(not cast:IsShown(), "with the button put away")
	if MENU and MENU.catcher then MENU.catcher:Hide() end
	-- The mouse leaves it: away. A row with no spell: none.
	cooking.scripts.OnEnter(cooking)
	ok(cast:IsShown(), "back on the row: back")
	cast.scripts.OnLeave(cast)
	ok(not cast:IsShown(), "the mouse leaves it: away")
	cooking.scripts.OnEnter(cooking)
	tailoring = RowOf("Tailoring")
	tailoring.scripts.OnEnter(tailoring)
	ok(not cast:IsShown(), "on the open profession's row there is none")
	-- A controller's A on the row: the same spell through Daylight UI's secure key.
	local keyA = win.padKeys[1]
	eq(keyA.key, "A", "the window's A")
	local attrs = keyA.secure(cooking)
	ok(attrs and attrs.type == "spell" and attrs.spell == 5041, "A on Cooking's row casts its spell")
	eq(keyA.secure(tailoring), nil, "A on the open profession's row is the row's own press")
	eq(keyA.label(), nil, "and the hint is Daylight UI's own Select")
	-- The game opens the profession: the menu closes by itself (a controller's A has no click of ours).
	Fire("TRADE_SKILL_SHOW")
	ok(not Menu.Shown(), "the profession opening closes the menu")
	eq(keyA.label(), "Stop", "menu shut: A is Stop's again")
	-- A fight starts with the button out: it is put away at once, and never touched in the fight.
	W.nameButton:Click()
	cooking = RowOf("Cooking")
	cooking.left, cooking.bottom, cooking.w, cooking.h = 300, 500, 206, 34
	cooking.scripts.OnEnter(cooking)
	ok(cast:IsShown(), "out again")
	Fire("PLAYER_REGEN_DISABLED")
	ok(not cast:IsShown(), "a fight starts: put away")
	FIGHT = true
	cooking.scripts.OnEnter(cooking)          -- (the strict stand-in raises on any protected call now)
	ok(not cast:IsShown(), "in a fight it stays away")
	eq(Menu.PadCast(cooking), nil, "and A has no spell")
	cooking:Click()
	eq(asked[#asked], 185, "in a fight the row's own click asks the game by line, as before")
	ok(not Menu.Shown(), "and closes the menu")
	FIGHT = false
end, function()
	FIGHT = false
	if MENU and MENU.catcher then MENU.catcher:Hide() end
	Menu.Close()
	GetProfessions, GetProfessionInfo = realProfessions, realProfessionInfo
	C_TradeSkillUI.OpenTradeSkill = realOpen
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = nil
	C_SpellBook, Enum = nil, nil
	ns.LINES[185], ns.LINES[129] = nil, nil
	W.menuList.left, W.menuList.bottom, W.menuList.h = nil, nil, 0
	Window.OpenProfession(197, 197)
	Flush()
end)

-- ---- 3.0.1: the menu carries everything the old sidebar did ------------------------------------------
-- Your professions, Camping, your alts, and at its foot the Cooldowns and Tracking tiles: all of
-- them, from the window as it stands and from a rolled-up one (it unrolls first, and the menu has
-- the unrolled window's room).
Case("3.0.1: the menu carries everything the old sidebar did", function()
	local function Look(what)
		ok(Menu.Shown(), what .. ": the menu is open")
		local names, titles, tiles = {}, {}, 0
		for _, o in ipairs(ALL) do
			if rawget(o, "more") and rawget(o, "name") and o:IsVisible() then names[strip(o.name.textValue)] = o end
			local inMenu, up = false, o.parent
			while up do
				if up == W.menu then inMenu = true end
				up = up.parent
			end
			if rawget(o, "title") and o.kind == "Frame" and o:IsVisible() and inMenu then
				titles[strip(o.title.textValue)] = o
			end
			if rawget(o, "ring") and o.kind == "Button" and o:IsVisible() and inMenu then
				tiles = tiles + 1
			end
		end
		ok(names["Professions"] and names["Tailoring"] and names["Herbalism"] and names["Fishing"], what .. ": your professions")
		ok(names["Camping"], what .. ": Camping")
		ok(names["Camping"].onClick ~= nil, what .. ": which opens its page")
		ok(names["Your Alts"] and names["Mira"], what .. ": your alts")
		ok(titles["Cooldowns"], what .. ": the Cooldowns tiles")
		ok(titles["Tracking"], what .. ": the Tracking tiles")
		eq(tiles, 3, what .. ": two cooldown tiles and one tracking tile")
		local foot = titles["Cooldowns"].h + titles["Tracking"].h
		ok(foot > 0 and W.menu.h >= foot + 34 * 5, what .. ": the menu has room for its rows over the foot: " .. W.menu.h)
		ok(W.menu.h <= win.h - State.HEADER, what .. ": inside the window")
		-- Camping's row opens the camping page.
		names["Camping"]:Click()
		ok(not Menu.Shown() and W.gather == W.CAMP, what .. ": a press on Camping shows the camping page")
		Window.OpenProfession(197, 197)
		Flush()
	end
	W.nameButton:Click()
	Look("the window open")
	Window.SetTab("recipes")
	Window.SetRolled(true)
	Flush()
	eq(Window.Mode(), "rolled", "rolled up")
	W.nameButton:Click()
	ok(Window.Mode() ~= "rolled", "the menu unrolls the window")
	Look("from a rolled-up window")
end, function()
	Menu.Close()
	Window.SetRolled(false)
	Window.OpenProfession(197, 197)
	Flush()
end)

-- ---- 3.0.2: the professions menu is a solid box --------------------------------------------------------
-- In the game 3.0.1's menu was see-through: the window's tabs and page could be read through it.
-- Its background is Daylight UI's shell, a child frame one level under the menu. So: the menu asks
-- for a background of 1 (never the window opacity), it does not clip its own children (the shell
-- is one of them, and lies under it), a frame inside it does the clipping, and the shell is put
-- under the menu in the menu's own layer every time it opens, wherever it was left.
Case("3.0.2: the professions menu is a solid box", function()
	local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
	local function Over(top, under)
		local st, su = STRATA[top:GetFrameStrata()], STRATA[under:GetFrameStrata()]
		if st ~= su then return st > su end
		return top:GetFrameLevel() > under:GetFrameLevel()
	end
	local function Within(o, root)
		o = o.parent
		while o do
			if o == root then return true end
			o = o.parent
		end
		return false
	end
	local function Look(what)
		ok(Menu.Shown(), what .. ": the menu is open")
		local m = W.menu
		local shell = rawget(m, "shell")
		ok(shell ~= nil, what .. ": the menu wears Daylight UI's shell")
		eq(m.skin.bgAlpha, 1, what .. ": its background is asked fully solid")
		ok(m.skin.window == nil and m.skin.look == nil, what .. ": not as a window, whose background follows the window opacity")
		ok(not rawget(m, "clips"), what .. ": the menu does not clip its children: its background is one of them")
		eq(shell:GetFrameStrata(), m:GetFrameStrata(), what .. ": the background is in the menu's layer")
		eq(shell:GetFrameLevel(), m:GetFrameLevel() - 1, what .. ": one level under the menu")
		ok(Over(shell, win), what .. ": and over the window, with everything on it")
		local n, clipped = 0, 0
		for _, o in ipairs(ALL) do
			if o ~= shell and (o.kind == "Frame" or o.kind == "Button") and Within(o, m) and o:IsVisible() then
				n = n + 1
				ok(Over(o, shell), what .. ": every frame of the menu is over its background")
				ok(Over(o, win), what .. ": and over the window")
				-- (What the menu holds is clipped by the frame inside it, not by the menu.)
				local up, inClip = o.parent, false
				while up and up ~= m do
					if rawget(up, "clips") then inClip = true end
					up = up.parent
				end
				if inClip then clipped = clipped + 1 end
			end
		end
		ok(n > 8, what .. ": the menu's frames were looked at: " .. n)
		ok(clipped >= n - 1, what .. ": its rows and tiles are still kept inside it, by a frame of its own")
	end
	-- Whatever the opacity settings say.
	SETTINGS.duiOpacity, SETTINGS.opacity = false, 0.1
	W.nameButton:Click()
	Look("window opacity at its lowest")
	Menu.Restyle()
	Look("dressed again (a theme or opacity change)")
	Menu.Close()
	-- The shell left somewhere else (the game did not carry the menu's layer or level on to it):
	-- opening the menu puts it back.
	local shell = rawget(W.menu, "shell")
	shell:SetFrameStrata("MEDIUM")
	shell:SetFrameLevel(0)
	W.nameButton:Click()
	Look("after its background was left in the window's layer")
	-- The secure button over a row: over the row, in the menu's layer, never over its More button,
	-- and under Daylight UI's dropdown (the More menu) in every case.
	local realInfo = GetProfessionInfo
	GetProfessions = function() return 1, 2, nil, 3, 5 end
	GetProfessionInfo = function(i)
		if i == 5 then return "Cooking", 10, 153, 225, 0, 40, 185 end
		return realInfo(i)
	end
	ns.LINES[185] = true
	Enum = { SpellBookSpellBank = { Player = 0 } }
	C_SpellBook = { GetSpellBookItemInfo = function(slot) return { spellID = 5000 + slot } end }
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function() return true end
	Menu.Paint()
	local row
	for _, o in ipairs(ALL) do
		if rawget(o, "more") and o:IsVisible() and strip(o.name.textValue) == "Cooking" then row = o end
	end
	ok(row and row.cast == 5041, "Cooking's row, with its spell")
	row.left, row.bottom, row.w, row.h = 300, 500, 206, 34
	row.more.left, row.more.bottom, row.more.w = 480, 507, 20
	W.menuList.left, W.menuList.bottom, W.menuList.h = 300, 200, 400
	row.scripts.OnEnter(row)
	local cast = _G.DaylightRecipesMenuCast
	ok(cast and cast:IsShown(), "the secure button is out")
	ok(Over(cast, row), "over the row it covers")
	ok(Over(cast, rawget(W.menu, "shell")) and Over(cast, win), "over the menu's background and the window")
	ok(cast.px + cast.w <= row.more.left, "it ends left of the row's More button: that keeps its own clicks")
	local drawn = 0
	for _, o in ipairs(ALL) do
		if o.parent == cast then drawn = drawn + 1 end
	end
	eq(drawn, 0, "it draws nothing: the row's name, bar and highlight show as they are")
	ok(row.wash:IsShown(), "and the row is still lit under the mouse")
	MENU = nil
	row.more:Click()
	ok(MENU and MENU.catcher and MENU.catcher:IsShown(), "More opens Daylight UI's dropdown")
	ok(not cast:IsShown(), "the secure button is put away as it opens")
	ok(STRATA[cast:GetFrameStrata()] < STRATA[MENU.catcher:GetFrameStrata()], "and its layer is under that dropdown's in any case")
	ok(Over(MENU.catcher, W.menu) and Over(MENU.box, W.menu), "the More menu lies over the professions menu")
	ok(Over(MENU.box, rawget(W.menu, "shell")), "and over its background")
	MENU.catcher:Hide()
	Menu.Close()
	-- In a tour the window is one layer up, and the menu with its background over it.
	Window.ShowForTour()
	W.nameButton:Click()
	Look("in a tour")
end, function()
	SETTINGS.duiOpacity, SETTINGS.opacity = nil, nil
	if MENU and MENU.catcher then MENU.catcher:Hide() end
	Menu.Close()
	Window.TourDone()
	GetProfessions, GetProfessionInfo = realProfessions, realProfessionInfo
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = nil
	C_SpellBook, Enum = nil, nil
	ns.LINES[185] = nil
	W.menuList.left, W.menuList.bottom, W.menuList.h = nil, nil, 0
	Window.OpenProfession(197, 197)
	Flush()
end)

if #FAILED > 0 then error(#FAILED .. " case(s) failed: " .. table.concat(FAILED, " || ")) end
if #ERRORS > 0 then error("an error reached the error handler: " .. ERRORS[1]) end
return ("ok, %d checks"):format(checks)
