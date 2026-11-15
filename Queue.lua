-- The crafting queue: recipes to make and how many, kept per character (any of its professions).
-- Added from the Recipes tab and from the Leveling Guide's steps; "Craft next" in the Queue tab
-- makes the first one of the open profession. Every cast of a queued recipe takes one off it,
-- however it was started. What the queue needs is on the buy list at vendors and the Auction House.
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

-- What the whole queue takes: itemID -> count.
function Queue.Needs()
	local out = {}
	for _, e in ipairs(Queue.List()) do
		for _, m in ipairs(ns.Calc.Materials(e.spell)) do
			out[m[1]] = (out[m[1]] or 0) + m[2] * e.count
		end
	end
	return out
end
