-- The crafting queue: recipes to make and how many, kept per character (any of its professions).
-- Added from the Recipes tab and from the Leveling Guide's steps; "Craft next" in the Queue tab
-- makes the first one of the open profession. Every cast of a queued recipe takes one off it,
-- however it was started. What the queue needs is on the strips at vendors and the Auction House.
-- Its count is on the window's Queue tab ("Queue (3)") and, rolled up, on its craft bar.
local _, ns = ...
if not ns.ok then return end

local Queue = {}
ns.Queue = Queue

local function List()
	local c = ns.Store and ns.Store.Char()
	if not c then return nil end
	c.queue = type(c.queue) == "table" and c.queue or {}
	return c.queue
end

local function Changed()
	if ns.Changed then ns.Changed() end
	if ns.Shop then ns.Shop.Refresh() end
end

-- { { spell, count, line }, ... } in the order they're made.
function Queue.List() return List() or {} end

function Queue.Count()
	local q = List()
	return q and #q or 0
end

-- Adds `count` of a recipe (to its entry when it's queued already).
function Queue.Add(spell, count)
	local q = List()
	if not q or type(spell) ~= "number" then return end
	count = math.max(1, math.floor(tonumber(count) or 1))
	for _, e in ipairs(q) do
		if e.spell == spell then
			e.count = e.count + count
			Changed()
			return
		end
	end
	local data = ns.Recipes and ns.Recipes[spell]
	q[#q + 1] = { spell = spell, count = count, line = data and data[1] or ns.state.line }
	Changed()
end

function Queue.Remove(i)
	local q = List()
	if q and q[i] then
		table.remove(q, i)
		Changed()
	end
end

-- Moves an entry up (-1) or down (1).
function Queue.Move(i, by)
	local q = List()
	local j = i + by
	if not q or not q[i] or not q[j] then return end
	q[i], q[j] = q[j], q[i]
	Changed()
end

-- A profession unlearned: its recipes leave the queue.
function Queue.ForgetLine(line)
	local q = List()
	if not q or not line then return end
	local gone = false
	for i = #q, 1, -1 do
		if q[i].line == line then
			table.remove(q, i)
			gone = true
		end
	end
	if gone then Changed() end
end

function Queue.Clear()
	local q = List()
	if q and #q > 0 then
		wipe(q)
		Changed()
	end
end

-- One of a queued recipe made: one off its entry, gone at none.
function Queue.Made(spell)
	local q = List()
	if not q then return end
	for i, e in ipairs(q) do
		if e.spell == spell then
			e.count = e.count - 1
			if e.count <= 0 then table.remove(q, i) end
			Changed()
			return
		end
	end
end

-- The first entry of the open profession (your own): the entry and its place, or nil.
function Queue.NextHere()
	local S = ns.state
	if not S.line or S.linked then return nil end
	for i, e in ipairs(Queue.List()) do
		if e.line == S.line then return e, i end
	end
end

-- What the queue's own crafts make (itemID -> count, at the least a craft makes): a bolt queued
-- before the shirt that uses it covers the shirt's bolts, so they aren't to buy as well (Profit's
-- plan queues what it makes on the way first).
local function Made()
	local made = {}
	for _, e in ipairs(Queue.List()) do
		local itemID, each
		if ns.Calc.Output then itemID, each = ns.Calc.Output(e.spell) end
		if itemID then
			local lo = math.floor(each or 1)
			made[itemID] = (made[itemID] or 0) + math.max(1, lo) * e.count
		end
	end
	return made
end

-- What the queue takes, profession by profession: line -> { itemID -> count } (the profession of
-- each queued recipe; for the strips' profession tags, Shop.lua). Together they are Queue.Needs().
-- What the queue makes itself is taken off (Made), from the first lines that need it.
function Queue.NeedsByLine()
	local out = {}
	for _, e in ipairs(Queue.List()) do
		local data = ns.Recipes and ns.Recipes[e.spell]
		local line = data and data[1] or e.line
		if line then
			out[line] = out[line] or {}
			for _, m in ipairs(ns.Calc.Materials(e.spell)) do
				out[line][m[1]] = (out[line][m[1]] or 0) + m[2] * e.count
			end
		end
	end
	local made = Made()
	for _, items in pairs(out) do
		for itemID, n in pairs(items) do
			local have = made[itemID]
			if have and have > 0 then
				local take = math.min(have, n)
				made[itemID] = have - take
				items[itemID] = n - take > 0 and n - take or nil
			end
		end
	end
	return out
end

-- What the whole queue takes: itemID -> count (less what it makes itself).
function Queue.Needs()
	local out = {}
	for _, e in ipairs(Queue.List()) do
		for _, m in ipairs(ns.Calc.Materials(e.spell)) do
			out[m[1]] = (out[m[1]] or 0) + m[2] * e.count
		end
	end
	for itemID, n in pairs(Made()) do
		local need = out[itemID]
		if need then out[itemID] = need - n > 0 and need - n or nil end
	end
	return out
end
