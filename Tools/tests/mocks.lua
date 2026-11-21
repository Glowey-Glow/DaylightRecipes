-- Offline mocks for Glowey's Recipes' tests (Tools/tests/run.py loads this, then the plugin's own
-- Locales/Locales.lua, ProfLost.lua, Prices.lua and Shop.lua, unchanged, then one test file).
-- Only the pure logic of the shop strips and the Professionally Lost hand-off is under test; the
-- rest of the plugin (Core, Store, Calc, Queue, Doc, the window) is stood in for by small tables a
-- test fills in. Nothing here is the game: what only the game can show is in design/in-game-check.md.
--
-- What the mocks enforce, so a pass proves more than "it loads":
--   * THE VENDOR IS STRICT. BuyMerchantItem raises when the vendor is closed, the slot is empty,
--     the quantity is over the slot's cap or not a whole number of its lots, the vendor has too
--     few left, the gold doesn't reach, or the bags are full. Every purchase is recorded in
--     GAME.bought; tests then check that nothing over the need was bought.
--   * PROFESSIONALLY LOST IS READ-ONLY. T.snapshot() / T.untouched() compare its whole handle and
--     saved variables before and after: any write by our code fails the test.
--   * Every error that reaches geterrorhandler() is collected in ERRORS; T.done() fails on one.
--   * Time is the test's: C_Timer.After queues, T.run(seconds) plays the queue forward.
--   * VENDORS COME AND GO. T.vendor(shelf) opens one (each has a number), T.leave() closes it,
--     T.walk(shelf) closes it and opens another in the same moment, as a right-click on the
--     vendor beside the first does. Every purchase is recorded with the vendor it was made at.
--   * BAGS ARE LATE. With GAME.deliver set, what is bought reaches the bags that many seconds
--     later (then the snapshot's version rises and BAG_UPDATE_DELAYED fires, as Store.lua's read
--     does); T.bagEvent() is any other bag event: the snapshot read again, nothing arrived.
--   * NEVER OVER THE NEED. With GAME.limit[itemID] set, BuyMerchantItem raises on the purchase
--     that takes the total bought of that item over it.
--   * THE TRAINER IS STRICT TOO. BuyTrainerService raises when the trainer is closed, the place
--     is empty, the service is not available, was learned already, or the gold doesn't reach;
--     every lesson is recorded with the trainer it was learned at (GAME.learned).
--   * Frames remember their anchors (frame.points), so a test can see where one was put.

-- (This file is the test world: it defines the game's globals and replaces print and time.)
-- luacheck: ignore 111 112 113 121 122 131
ERRORS, PRINTS = {}, {}
geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
print = function(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	PRINTS[#PRINTS + 1] = table.concat(t, " ")
end

-- ---- the game's state ------------------------------------------------------------------------
GAME = {
	now = 1000,            -- GetTime()
	clock = 1700000000,    -- time() and GetServerTime()
	money = 0,
	merchant = false,      -- the vendor window is open
	shelf = {},            -- [index] = { id, price (a lot's), stack (items a lot), left (lots; -1 none), max, extended, purchasable }
	freeSlots = 16,        -- in bag 0; the other bags have none
	stackSize = {},        -- itemID -> how many fit a slot (nil: the game doesn't know the item)
	bags = {},             -- itemID -> count held (what Store.Count reads as bags)
	bought = {},           -- { index, quantity, itemID, count, cost } in order
	addons = {},           -- name -> loaded
	settings = { useAH = true },   -- our own settings (ns.Get); Auction House prices on, as by default
	dui = {},              -- Daylight UI's settings other than ours: ["scope.path"] = value
	pad = false,           -- a controller is in use
	plans = {},            -- this character's saved plans: line -> { need = { [itemID] = n }, learn = {} }
	queue = {},            -- the crafting queue's needs: itemID -> n
	queueBy = nil,         -- the same, profession by profession: line -> { itemID -> n } (nil: all of
	                       -- GAME.queue under one profession, line 0)
	removed = {},          -- this character's removed items (Shop.Remove): kind -> { itemID -> need }
	vendorPrice = {},      -- itemID -> what one costs at the cheapest vendor known (Calc.Vendor); the
	                       -- Auction House's price is Prices.lua's own (GAME.db.prices)
	reagents = nil,        -- itemID -> true: the items recipes use (Store.Reagents: Prices.lua keeps
	                       -- prices and price steps only for these). nil: none
	version = 1,           -- Store.version (the bag snapshot's)
	vendorID = 0,          -- the vendor open now (T.vendor / T.walk count them)
	deliver = nil,         -- seconds until a purchase is in the bags (nil: it never gets there)
	limit = {},            -- itemID -> the most that may ever be bought of it (the need)
	total = {},            -- itemID -> how many were bought in all
	trainer = false,       -- the trainer window is open
	trainerID = 0,         -- the trainer open now
	services = {},         -- [index] = { name, kind ("available" | "unavailable" | "used" | "header"), cost, req, spell, step }
	learned = {},          -- { name, spell, trainer, cost } in order
	known = {},            -- spell -> true (IsPlayerSpell)
	trainLag = 0,          -- seconds until a learned service leaves the trainer's list
}

function GetTime() return GAME.now end
function time() return GAME.clock end
function GetServerTime() return GAME.clock end
function GetMoney() return GAME.money end
function InCombatLockdown() return false end
function GetLocale() return "enUS" end
NUM_BAG_SLOTS = 4
MERCHANT_HIGH_PRICE_COST = 1500000

C_AddOns = { IsAddOnLoaded = function(name) return GAME.addons[name] == true, GAME.addons[name] == true end }

local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = GAME.now + (delay or 0), fn = fn } end }

-- ---- the vendor ------------------------------------------------------------------------------
function GetMerchantNumItems() return GAME.merchant and #GAME.shelf or 0 end
function GetMerchantItemID(i)
	local s = GAME.merchant and GAME.shelf[i]
	return s and s.id or nil
end
function GetMerchantItemMaxStack(i)
	local s = GAME.shelf[i]
	return s and (s.max or s.stack or 1) or 1
end
C_MerchantFrame = { GetItemInfo = function(i)
	local s = GAME.merchant and GAME.shelf[i]
	if not s then return nil end
	return { name = "Item " .. s.id, price = s.price, stackCount = s.stack or 1, numAvailable = s.left or -1,
		isPurchasable = s.purchasable ~= false, hasExtendedCost = s.extended == true }
end }
C_Container = { GetContainerNumFreeSlots = function(bag)
	if bag == 0 then return GAME.freeSlots, 0 end
	return 0, 0
end }
C_Item = { GetItemMaxStackSizeByID = function(itemID) return GAME.stackSize[itemID] end }

function BuyMerchantItem(index, quantity)
	if not GAME.merchant then error("BuyMerchantItem: the vendor is closed", 2) end
	local s = GAME.shelf[index]
	if not s then error("BuyMerchantItem: no item at slot " .. tostring(index), 2) end
	if s.extended then error("BuyMerchantItem: slot " .. index .. " costs tokens", 2) end
	local lot = s.stack or 1
	local count = quantity or lot
	if type(count) ~= "number" or count <= 0 or count ~= math.floor(count) then error("BuyMerchantItem: bad quantity " .. tostring(quantity), 2) end
	if count % lot ~= 0 then error("BuyMerchantItem: " .. count .. " is not a whole number of lots of " .. lot, 2) end
	if count > math.max(lot, s.max or lot) then error("BuyMerchantItem: " .. count .. " is over the slot's cap", 2) end
	local lots = count / lot
	if (s.left or -1) >= 0 and lots > s.left then error("BuyMerchantItem: the vendor has only " .. s.left .. " left", 2) end
	local cost = lots * s.price
	if cost > GAME.money then error("BuyMerchantItem: " .. cost .. " copper asked, " .. GAME.money .. " held", 2) end
	local per = GAME.stackSize[s.id]
	if per then
		local slots = math.ceil(count / per)
		if slots > GAME.freeSlots then error("BuyMerchantItem: the bags are full", 2) end
		GAME.freeSlots = GAME.freeSlots - slots
	end
	local total = (GAME.total[s.id] or 0) + count
	if GAME.limit[s.id] and total > GAME.limit[s.id] then
		error(("BuyMerchantItem: %d of item %d bought, %d needed"):format(total, s.id, GAME.limit[s.id]), 2)
	end
	GAME.total[s.id] = total
	GAME.money = GAME.money - cost
	if (s.left or -1) >= 0 then s.left = s.left - lots end
	GAME.bought[#GAME.bought + 1] = { index = index, quantity = quantity, itemID = s.id, count = count, cost = cost,
		vendor = GAME.vendorID, at = GAME.now }
	if GAME.deliver then
		local id = s.id
		C_Timer.After(GAME.deliver, function()
			GAME.bags[id] = (GAME.bags[id] or 0) + count
			T.bagEvent()
		end)
	end
end

-- ---- the trainer -------------------------------------------------------------------------------
function IsTradeskillTrainer() return GAME.trainer end
function GetNumTrainerServices() return GAME.trainer and #GAME.services or 0 end
function GetTrainerServiceInfo(i)
	local s = GAME.trainer and GAME.services[i]
	if not s then return nil end
	return s.name, s.kind, "icon"
end
function GetTrainerServiceCost(i)
	local s = GAME.services[i]
	return s and s.cost or 0
end
function GetTrainerServiceSkillReq(i)
	local s = GAME.services[i]
	return "Skill", s and s.req or nil
end
function GetTrainerServiceStepIndex()
	for i, s in ipairs(GAME.trainer and GAME.services or {}) do
		if s.step then return i end
	end
	return nil
end
function IsPlayerSpell(spell) return GAME.known[spell] == true end
function BuyTrainerService(i)
	if not GAME.trainer then error("BuyTrainerService: the trainer is closed", 2) end
	local s = GAME.services[i]
	if not s then error("BuyTrainerService: no service at " .. tostring(i), 2) end
	if s.kind ~= "available" then error("BuyTrainerService: " .. s.name .. " is " .. tostring(s.kind), 2) end
	if s.sent then error("BuyTrainerService: " .. s.name .. " was learned already", 2) end
	if (s.cost or 0) > GAME.money then error("BuyTrainerService: " .. s.name .. " costs more than you hold", 2) end
	s.sent = true
	GAME.money = GAME.money - (s.cost or 0)
	GAME.learned[#GAME.learned + 1] = { name = s.name, spell = s.spell, trainer = GAME.trainerID, cost = s.cost or 0 }
	local function land()
		s.kind = "used"
		if s.spell then GAME.known[s.spell] = true end
		if GAME.trainer then Fire("TRAINER_UPDATE") end
	end
	if (GAME.trainLag or 0) > 0 then C_Timer.After(GAME.trainLag, land) else land() end
end

-- ---- widgets: every method exists and does little; scripts and shown state are kept ---------
local IMPL = {}
local MT = {}
MT.__index = function(t, k)
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	local impl = IMPL[k]
	local fn = function(self, ...)
		if impl then return impl(self, ...) end
	end
	rawset(t, k, fn)
	return fn
end

ALL = {}       -- every frame and region made, in order (a test finds an unnamed one in it)
function NewObj(kind, name, parent)
	-- (A frame starts one level over its parent, in its parent's layer, as the game makes it; a
	-- frame's child frames are kept, for GetChildren: regions are not frames.)
	local o = setmetatable({ kind = kind, gname = name, parent = parent, scripts = {}, shown = true, w = 0, h = 0,
		level = parent and (rawget(parent, "level") or 0) + 1 or 1, strata = parent and rawget(parent, "strata") or "MEDIUM",
		enabled = true, points = {}, kids = {} }, MT)
	if parent and rawget(parent, "kids") and kind ~= "Texture" and kind ~= "FontString" and kind ~= "AnimationGroup"
		and kind ~= "Animation" then
		parent.kids[#parent.kids + 1] = o
	end
	if name then _G[name] = o end
	ALL[#ALL + 1] = o
	return o
end

function IMPL.GetObjectType(self) return self.kind end
function IMPL.GetParent(self) return self.parent end
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
function IMPL.GetEffectiveAlpha() return 1 end
function IMPL.GetEffectiveScale() return 1 end
function IMPL.GetScale() return 1 end
-- (Where a frame is: 100 from the left, 400 up, unless a test puts it elsewhere: frame.left,
-- frame.bottom.)
function IMPL.GetLeft(self) return rawget(self, "left") or 100 end
function IMPL.GetBottom(self) return rawget(self, "bottom") or 400 end
function IMPL.GetRight(self) return (rawget(self, "left") or 100) + self.w end
function IMPL.GetTop(self) return (rawget(self, "bottom") or 400) + self.h end
function IMPL.ClearAllPoints(self) rawset(self, "points", {}) end
function IMPL.SetPoint(self, point, rel, relPoint, x, y)
	local points = rawget(self, "points") or {}
	rawset(self, "points", points)
	points[#points + 1] = { point, rel, relPoint, x, y }
end
function IMPL.SetSize(self, w, h) rawset(self, "w", w) rawset(self, "h", h) end
function IMPL.SetWidth(self, w) rawset(self, "w", w) end
function IMPL.SetHeight(self, h) rawset(self, "h", h) end
function IMPL.GetWidth(self) return self.w end
function IMPL.GetHeight(self) return self.h end
function IMPL.GetFrameLevel(self) return self.level end
-- (How the game carries a frame's new level on to its child frames is not something the plugin
-- may lean on: GAME.levelsFollow plays it both ways. true: every frame on it moves by as much,
-- never under 0; false or nil: they stay where they were.)
function IMPL.SetFrameLevel(self, l)
	local by = l - (rawget(self, "level") or 0)
	rawset(self, "level", l)
	if GAME.levelsFollow and by ~= 0 then
		local function carry(f)
			for _, kid in ipairs(rawget(f, "kids") or {}) do
				rawset(kid, "level", math.max(0, (rawget(kid, "level") or 0) + by))
				carry(kid)
			end
		end
		carry(self)
	end
end
function IMPL.GetFrameStrata(self) return self.strata end
function IMPL.SetFrameStrata(self, s)
	rawset(self, "strata", s)
	for _, kid in ipairs(rawget(self, "kids") or {}) do kid:SetFrameStrata(s) end
end
function IMPL.EnableMouseWheel(self, on) rawset(self, "enabledWheel", on and true or false) end
function IMPL.GetVerticalScrollRange() return 0 end
function IMPL.GetVerticalScroll() return 0 end
function IMPL.GetChildren(self) return unpack(rawget(self, "kids") or {}) end
function IMPL.SetScript(self, name, fn) self.scripts[name] = fn end
function IMPL.GetScript(self, name) return self.scripts[name] end
function IMPL.HookScript(self, name, fn)
	local old = self.scripts[name]
	self.scripts[name] = old and function(...) old(...) fn(...) end or fn
end
function IMPL.SetEnabled(self, on) rawset(self, "enabled", on and true or false) end
function IMPL.IsEnabled(self) return self.enabled end
function IMPL.Click(self)
	if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
end
function IMPL.SetText(self, text) rawset(self, "textValue", text) end
function IMPL.GetText(self) return self.textValue end
-- (Six units a character: enough for the strip's layout arithmetic to have something to add up.)
function IMPL.GetStringWidth(self) return 6 * #(tostring(self.textValue or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
function IMPL.GetStringHeight() return 14 end
function IMPL.CreateTexture(self) return NewObj("Texture", nil, self) end
function IMPL.CreateAnimationGroup(self) return NewObj("AnimationGroup", nil, self) end
function IMPL.CreateAnimation(self) return NewObj("Animation", nil, self) end
function IMPL.CreateFontString(self) return NewObj("FontString", nil, self) end
function IMPL.RegisterEvent(self, e) EVENTS[e] = EVENTS[e] or {} EVENTS[e][self] = true end

EVENTS = {}
UIParent = NewObj("Frame", "UIParent")
UIParent.w, UIParent.h = 1920, 1080
UISpecialFrames = {}
function CreateFrame(kind, name, parent) return NewObj(kind, name, parent) end

function Fire(event, ...)
	for frame in pairs(EVENTS[event] or {}) do
		local fn = frame.scripts.OnEvent
		if fn then fn(frame, event, ...) end
	end
end

-- ---- what stands in for the rest of the plugin (filled into NS before its files load) -------
local function Button(parent, text)
	local b = NewObj("Button", nil, parent)
	b.text = NewObj("FontString", nil, b)
	b.text:SetText(text or "")
	function b.FitWidth(min) b.w = math.max(min or 90, b.text:GetStringWidth() + 32) end
	function b.SetOff(on)
		b.off = on and true or nil
		b.enabled = not on
	end
	function b.SetActive(on) b.active = on end
	return b
end

-- A doc that keeps what was drawn: d.rows[i] = the table D:Row was given; d.lines the D:Line texts;
-- d.buttons the first D:Buttons line ({ text, onClick, active }: the two lists' pair) and d.tags
-- the second (the profession tags). A strip's list has two docs: its head (strip.head: the pair,
-- the tags, the Check Prices line) and its rows (strip.doc).
local function NewDoc(parent)
	local d = { rows = {}, lines = {}, buttons = {}, waiting = {}, y = 0, scroll = NewObj("ScrollFrame", nil, parent) }
	function d:Begin() self.rows, self.lines, self.buttons, self.tags, self.marks, self.y = {}, {}, {}, {}, {}, 8 end
	-- (The first line of buttons is the two lists' pair, the second the profession tags.)
	function d:Buttons(list, _, opts)
		if #self.buttons == 0 then self.buttons = list else self.tags = list end
		self.chips = opts
		self.y = self.y + (opts and (opts.height + opts.gap) or 30)
	end
	function d:Top() self.topped = (self.topped or 0) + 1 end
	function d:Row(o)
		self.rows[#self.rows + 1] = o
		self.y = self.y + 22
		self.marks[#self.marks + 1] = self.y
	end
	function d:Line(text) self.lines[#self.lines + 1] = text end
	function d:Finish()
		if not self.still then self.y = self.y + 8 end
	end
	function d.Waiting() return false end
	return d
end

function Bootstrap(ns)
	ns.ok = true
	ns.Get = function(key) return GAME.settings[key] end
	ns.Print = function(msg) PRINTS[#PRINTS + 1] = msg end
	ns.Changed = function() GAME.redraws = (GAME.redraws or 0) + 1 end
	ns.Shown = function() return false end
	ns.ShowingPlan = function() return false end
	ns.SkinWindow = function(frame, extra) rawset(frame, "skinExtra", extra or false) end
	ns.ItemNameOf = function(itemID) return "Item " .. itemID end
	ns.SpellName = function(spell) return "Spell " .. spell end
	ns.state = {}
	ns.API = {
		GetSetting = function(scope, path) return GAME.dui[scope .. "." .. path] end,
		IsModuleEnabled = function() return false end,
		Accent = function() return 1, 0.8, 0.2 end,
		Colors = function() return setmetatable({}, { __index = function() return { 1, 1, 1 } end }) end,
		Button = Button,
		Skin = function() end,
		Text = function(parent) return NewObj("FontString", nil, parent) end,
		Switch = function(parent)
			local s = NewObj("Button", nil, parent)
			function s.SetOn(on) s.on = on end
			return s
		end,
		Close = function(parent) return NewObj("Button", nil, parent) end,
		GetFrame = function(name) return name == "npc" and GAME.npc or nil end,
	}
	ns.me = { On = function(event, fn) GAME.on = GAME.on or {} GAME.on[event] = fn end }
	ns.Doc = {
		Color = function() return 1, 1, 1 end,
		Hex = function() return "|cffffffff" end,
		Text = function(parent) return NewObj("FontString", nil, parent) end,
		ItemName = function(itemID) return "Item " .. itemID, "icon" end,
		Ago = function(stamp) return ("%d s ago"):format(GAME.clock - stamp) end,
		New = function(parent, opts)
			local d = NewDoc(parent)
			d.still = opts and opts.still == true or nil
			return d
		end,
	}
	-- What stands in for Calc.lua's reading of the game, kept apart so it can be laid over the
	-- real Calc.lua once that has loaded (AfterLoad, below): its price math (Unit, Steps, AHCost,
	-- Split, BuyCost) is the plugin's own in every test; only where a price comes from is ours.
	local calc = {
		Money = function(copper) return tostring(math.floor(copper + 0.5)) .. "c" end,
		ItemInfo = function(itemID) return "Item " .. itemID end,
		Vendor = function(itemID)
			local unit = GAME.vendorPrice[itemID]
			if unit then return unit, "Vendor Bob" end
		end,
		AH = function(itemID) return ns.Prices and ns.Prices.Get(itemID) or nil end,
		HasAH = function() return ns.Prices ~= nil and ns.Prices.Has() end,
	}
	GAME.calc = calc
	ns.Calc = { version = 1, Forget = function() ns.Calc.version = ns.Calc.version + 1 end }
	for k, v in pairs(calc) do ns.Calc[k] = v end
	local db = { prices = {} }
	GAME.db = db
	ns.Store = {
		version = GAME.version,
		DB = function() return db end,
		RealmKey = function() return "Realm-A" end,
		Char = function() return { plans = GAME.plans, prof = GAME.prof or {}, known = {}, removed = GAME.removed } end,
		Count = function(itemID)
			local n = GAME.bags[itemID] or 0
			local alts = GAME.alts and GAME.alts[itemID] or 0
			return { bags = n, bank = 0, mail = 0, mine = n, alts = alts > 0 and { { name = "Mira", count = alts } } or {},
				altTotal = alts, altHeld = alts }
		end,
		Reagents = function() return GAME.reagents or {} end,
	}
	ns.Queue = {
		Needs = function() return GAME.queue end,
		NeedsByLine = function() return GAME.queueBy or { [0] = GAME.queue } end,
	}
	ns.Tips = { LineName = function(line) return "Prof " .. tostring(line) end }
	ns.Pages = {
		AltAlert = function(have)
			if (have.altTotal or 0) <= 0 then return nil end
			return ("[%s Has %d]"):format(have.alts[1].name, have.alts[1].count)
		end,
		HaveText = function() return nil end,
	}
	ns.Pad = {
		On = function() return GAME.pad end,
		Follow = function() end, Back = function() end,
		Settle = function() GAME.settled = (GAME.settled or 0) + 1 end,
	}
	ns.Guide = { Offer = function(id) GAME.offered = id end }
end

-- ---- Professionally Lost, as much of it as we read (its 1.2.0 shapes) ------------------------
-- InstallProfLost{ guides = { 197, 171 }, step = { [197] = 3852 }, prices = { [2589] = { 120, t } },
-- tooltip = false } loads a stand-in under its real names.
function InstallProfLost(o)
	o = o or {}
	GAME.addons.ProfessionallyLost = true
	local CP = { name = "ProfessionallyLost", calls = {} }
	CP.Guides = {}
	for _, line in ipairs(o.guides or { 171, 164, 185, 333, 202, 129, 165, 197 }) do CP.Guides[line] = { name = "Guide " .. line, steps = {} } end
	local handlers = {}
	function CP.On(_, event, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end
	function CP.Emit(_, event, ...)
		for _, fn in ipairs(handlers[event] or {}) do fn(event, ...) end
	end
	CP.Window = {
		Pick = function(id) CP.calls[#CP.calls + 1] = "Pick " .. tostring(id) end,
		Open = function() CP.calls[#CP.calls + 1] = "Open" end,
	}
	CP.GatherPanel = { Open = function() CP.calls[#CP.calls + 1] = "Gather" end }
	CP.Panel = { OpenSettings = function(self)
		if self ~= CP.Panel then error("OpenSettings is a method") end
		CP.calls[#CP.calls + 1] = "Settings"
	end }
	local listeners = {}
	CP.Scan = {
		Price = function(itemID)
			local e = (o.prices or {})[itemID]
			if type(e) ~= "table" then return nil end
			return e[1], e[2]
		end,
		HasData = function() return next(o.prices or {}) ~= nil end,
		OnChange = function(fn) listeners[#listeners + 1] = fn end,
		notify = function() for _, fn in ipairs(listeners) do fn() end end,
	}
	-- o.scan: its scan can be asked whether it is running and when it last finished (its 1.2.0:
	-- Scan.Running, Scan.LastTime), from GAME.scan = { running, last }.
	if o.scan then
		GAME.scan = { running = false, last = nil }
		CP.Scan.Running = function() return GAME.scan.running end
		CP.Scan.LastTime = function() return GAME.scan.last end
	end
	ProfLost = CP
	ProfLostCharDB = { nextStep = {} }
	for line, spell in pairs(o.step or {}) do ProfLostCharDB.nextStep[line] = { spell = spell, from = 1, to = 2 } end
	ProfLostDB = { itemTooltip = o.tooltip ~= false }
	GAME.dui["ProfLost.itemTooltip"] = o.tooltip ~= false
	return CP
end

-- ---- the tests' helpers ----------------------------------------------------------------------
T = { n = 0 }
function T.ok(cond, what)
	T.n = T.n + 1
	if not cond then error("FAILED: " .. tostring(what), 2) end
end
function T.eq(got, want, what)
	T.n = T.n + 1
	if got ~= want then error(("FAILED: %s (got %s, wanted %s)"):format(tostring(what), tostring(got), tostring(want)), 2) end
end
function T.noErrors(what)
	T.n = T.n + 1
	if #ERRORS > 0 then error("FAILED: " .. tostring(what) .. ": " .. ERRORS[1], 2) end
end
-- A bag event that brings nothing of what was bought (loot, a stack moved, the mail): the bag
-- snapshot is read again, so its version rises, and the strips are told as Store.lua tells them.
function T.bagEvent()
	NS.Store.version = NS.Store.version + 1
	Fire("BAG_UPDATE_DELAYED")
end
-- A vendor opens (another one each time), with this shelf.
function T.vendor(shelf)
	GAME.vendorID = GAME.vendorID + 1
	GAME.merchant = true
	GAME.shelf = shelf
	Fire("MERCHANT_SHOW")
end
function T.leave()
	GAME.merchant = false
	Fire("MERCHANT_CLOSED")
end
-- From one vendor straight to the next: closed and shown in the same moment.
function T.walk(shelf)
	T.leave()
	T.vendor(shelf)
end
-- The same for a trainer, with these services.
function T.trainer(services)
	GAME.trainerID = GAME.trainerID + 1
	GAME.trainer = true
	GAME.services = services
	Fire("TRAINER_SHOW")
end
function T.leaveTrainer()
	GAME.trainer = false
	Fire("TRAINER_CLOSED")
end
-- How many of an item were bought, at which vendors: count, { [vendorID] = count }.
function T.boughtOf(itemID)
	local n, where = 0, {}
	for _, b in ipairs(GAME.bought) do
		if b.itemID == itemID then
			n = n + b.count
			where[b.vendor] = (where[b.vendor] or 0) + b.count
		end
	end
	return n, where
end
-- Cases: each runs by itself and a failed one does not stop the rest, so one run against an older
-- file shows every case it fails. T.done() fails the test when any did.
T.failed = {}
function T.case(name, fn)
	local ok, err = pcall(fn)
	if ok and #ERRORS > 0 then ok, err = false, "an error reached the error handler: " .. ERRORS[1] end
	ERRORS = {}
	if not ok then T.failed[#T.failed + 1] = name .. " [" .. tostring(err) .. "]" end
end
-- Plays the timers forward by `seconds`, in order.
function T.run(seconds)
	local stop = GAME.now + (seconds or 0)
	while true do
		local best
		for i, t in ipairs(timers) do
			if t.at <= stop and (not best or t.at < timers[best].at) then best = i end
		end
		if not best then break end
		local t = table.remove(timers, best)
		if t.at > GAME.now then GAME.now = t.at end
		t.fn()
	end
	GAME.now = stop
end
local function dump(v, seen, out, key)
	if type(v) ~= "table" then
		out[#out + 1] = key .. "=" .. type(v) .. ":" .. (type(v) == "function" and "fn" or tostring(v))
		return
	end
	if seen[v] then return end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = tostring(k) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local child = v[k]
		if child == nil then child = v[tonumber(k)] end
		if k ~= "calls" then dump(child, seen, out, key .. "." .. k) end
	end
end
local function picture()
	local out = {}
	for _, name in ipairs({ "ProfLost", "ProfLostCharDB", "ProfLostDB" }) do
		dump(rawget(_G, name), {}, out, name)
	end
	return table.concat(out, "\n")
end
function T.snapshot() T.before = picture() end
function T.untouched(what)
	T.n = T.n + 1
	if picture() ~= T.before then error("FAILED: Professionally Lost's tables were written to (" .. tostring(what) .. ")", 2) end
end
function T.done()
	if #T.failed > 0 then error(#T.failed .. " case(s) failed: " .. table.concat(T.failed, " || "), 2) end
	if #ERRORS > 0 then error("errors reached the error handler: " .. ERRORS[1], 2) end
	return ("ok, %d checks"):format(T.n)
end

-- Run by run.py once the plugin's files have loaded: the real Calc.lua's sources of prices are
-- the tests' (a vendor's from GAME.vendorPrice, the Auction House's straight from Prices.lua,
-- money as plain copper), its math its own.
function AfterLoad(ns)
	for k, v in pairs(GAME.calc) do ns.Calc[k] = v end
end
