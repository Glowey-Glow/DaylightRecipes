-- Glowey's Recipes' public API, for plugins of its own (Glowey's Recipes: Profit): the global
-- DaylightRecipes.API. Read-only on everything of ours but the crafting queue, and a plugin's own
-- tab in the profession window. Nothing here runs until a plugin calls it.
--   major                     1 (a change that breaks a call raises it)
--   Price(itemID)             the Auction House price in use (the picked addon's, DaylightMogul's,
--                             Daylight UI's or our own), copper or nil
--   PriceAge(itemID)          how long ago that price was seen, seconds, or nil (not known)
--   Listed(itemID)            how many were listed when it was seen, or nil (not known)
--   Stale(itemID)             whether that price is over a day old
--   HasPrices()               whether Auction House prices are in use at all
--   Unit(itemID)              the cheaper of the Auction House and a vendor: copper, "ah" | "vendor"
--   Vendor(itemID)            the cheapest vendor's price for one, or nil
--   BuyCost(itemID, n, skip)  n bought the cheapest way (the Auction House's listings when fresh,
--                             after the `skip` cheapest), copper or nil, and whether that's exact
--   Materials(spell)          { { itemID, count }, ... } (a copy)
--   Output(spell)             itemID, count made (nil for an enchant)
--   ItemInfo(itemID)          name, link, quality, icon, vendor sell price, bind type
--   Recipes()                 the recipe data, spell -> { line, thresholds, materials, output,
--                             recipe item } (ours: read it, never write to it)
--   Cooldown(spell)           whether a recipe is on a cooldown (Transmutes, Mooncloth...)
--   Known()                   spell -> true: the recipes this character knows (read only), and the
--                             ones every character has (Automatic)
--   LearnAt(spell)            the skill it's learned at, or nil
--   TrainerCost(spell)        the cheapest of its trainers you can reach, copper, or nil
--   Faction()                 "A" or "H"
--   VariantFaction(spell)     the faction a recipe is for, when it has a variant per faction
--   Automatic(spell)          whether every character has it
--   Profession()              the open profession: { line, name, skill, max, linked }, or nil
--   HouseKey()                this character's Auction House, as a text key (one per set of rules)
--   Version()                 a number that changes whenever prices or a setting changed (what's
--                             worked out from them is out of date)
--   Queue(spell, count)       adds crafts to the crafting queue
--   RegisterTab(key, label, draw)   a tab of the plugin's own after ours (false: the key is taken);
--                             draw(d, ctx) draws its page
--                             on our doc (Doc.lua's d:Line, d:Heading, d:Row, d:Buttons,
--                             d:Pickers, d:Gap, d.state); ctx.pick(spell) shows a recipe,
--                             ctx.redraw() draws the page again
--   SetTab(key)               shows a tab
--   Redraw()                  draws what's open again (on the next frame)
--   OnPrices(fn)              fn() after prices change (once things are quiet), never in a burst
--   Money(copper), ItemName(itemID, d), RecipeName(spell), Color(ink), PricesNote(d), Print(msg),
--   L, Plural(n, one, many)   our look's and words' helpers, so a plugin's page reads as ours
local _, ns = ...
if not ns.ok then return end

local API = { major = 1 }

local function Calc() return ns.Calc end

function API.Price(itemID) return Calc().AH(itemID) end
function API.PriceAge(itemID) return Calc().AHAge(itemID) end
function API.Listed(itemID) return ns.Prices and ns.Prices.Quantity and ns.Prices.Quantity(itemID) or nil end
function API.Stale(itemID) return (Calc().Stale(itemID)) end
function API.HasPrices() return Calc().HasAH() end
function API.Unit(itemID)
	local u, kind = Calc().Unit(itemID)
	return u, kind
end
function API.Vendor(itemID) return (Calc().Vendor(itemID)) end
function API.BuyCost(itemID, n, skip) return Calc().BuyCost(itemID, n, skip) end
function API.Materials(spell)
	local out = {}
	for i, m in ipairs(Calc().Materials(spell)) do out[i] = { m[1], m[2] } end
	return out
end
function API.Output(spell) return Calc().Output(spell) end
function API.ItemInfo(itemID) return Calc().ItemInfo(itemID) end
function API.Recipes() return ns.Recipes or {} end

local COOLDOWN = { "^Transmute", "Mooncloth$" }
function API.Cooldown(spell)
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	if meta and meta.cooldown then return true end
	local name = ns.RecipeNames and ns.RecipeNames[spell]
	if type(name) == "string" then
		for _, p in ipairs(COOLDOWN) do
			if string.find(name, p) then return true end
		end
	end
	return false
end

function API.Known() return ns.Where.KnownSet() end
function API.Automatic(spell) return ns.AutomaticRecipes and ns.AutomaticRecipes[spell] and true or false end
function API.LearnAt(spell) return ns.Where.Required(spell) end
function API.TrainerCost(spell)
	local list = ns.Trainers and ns.Trainers[spell]
	if type(list) ~= "table" then return nil end
	local best
	for _, rec in ipairs(list) do
		if type(rec) == "table" and ns.Where.Npc(rec[1]) then
			local copper = type(rec[2]) == "number" and rec[2] or 0
			if not best or copper < best then best = copper end
		end
	end
	return best
end
function API.Faction() return ns.Faction() end
-- (Meta for a recipe the faction picks between: its variantFaction.)
function API.VariantFaction(spell)
	local meta = ns.RecipeMeta and ns.RecipeMeta[spell]
	return meta and meta.variantFaction or nil
end
function API.Profession()
	local S = ns.state
	if not S or not S.line then return nil end
	return { line = S.line, name = S.name, skill = S.skill, max = S.max, linked = S.linked and true or false }
end
function API.Version() return Calc().version end
-- The key of this character's Auction House (its price book's: Store.RealmKey).
function API.HouseKey() return ns.Store.RealmKey() end

function API.Queue(spell, count) if ns.Queue then ns.Queue.Add(spell, count) end end

-- A plugin's tab: kept in ns.ExtraTabs, its key after ours (WindowState.lua's AddTab).
function API.RegisterTab(key, label, draw)
	if type(key) ~= "string" or type(draw) ~= "function" then return false end
	ns.ExtraTabs = ns.ExtraTabs or {}
	-- (A key taken, ours or another plugin's, is refused: one page a tab.)
	if ns.ExtraTabs[key] or (ns.Window and ns.Window.TabWord and ns.Window.TabWord(key)) then return false end
	ns.ExtraTabs[key] = { label = tostring(label or key), draw = draw }
	if ns.WinState then ns.WinState.AddTab(key) end
	if ns.Window and ns.Window.Shown() then ns.Changed() end
	return true
end
function API.SetTab(key) if ns.Window and ns.Window.SetTab then ns.Window.SetTab(key) end end
function API.Redraw() if ns.Changed then ns.Changed() end end

local heard = {}
function API.OnPrices(fn) if type(fn) == "function" then heard[#heard + 1] = fn end end
-- (Prices.lua's Touched, once prices changed.)
function ns.PricesHeard()
	for _, fn in ipairs(heard) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

function API.Money(copper) return Calc().Money(copper) end
function API.ItemName(itemID, d) return ns.Doc.ItemName(itemID, d) end
function API.RecipeName(spell) return ns.Doc.RecipeName(spell) end
function API.Color(ink) return ns.Doc.Color(ink) end
function API.PricesNote(d) if ns.Pages and ns.Pages.Prices then ns.Pages.Prices(d) end end
function API.Print(msg) ns.Print(msg) end
API.L = ns.L
function API.Plural(n, one, many) return ns.Plural(n, one, many) end

_G.DaylightRecipes = _G.DaylightRecipes or {}
_G.DaylightRecipes.API = API
