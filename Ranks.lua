-- How each profession's ranks are learned on this game version, looked up (2026-11-20), not
-- inferred: the Leveling Guide's rank steps and its "you can already learn it" notice read it
-- through Where.RankInfo. The recipe data has no such list.
--
--   ns.Ranks[skill line][the rank's cap: 150 Journeyman, 225 Expert, 300 Artisan] = {
--     how    "trainer" (left out) | "book" | "quest"
--     at     the skill it can be learned from (50, 125, 200: before your cap, not at it)
--     level  the character level it asks for (none for Cooking, First Aid, Mining)
--     cost   copper, where the source says (a trainer's price, a book's)
--     who    who teaches it or sells the book: NPC ids of the data's tables (their places and
--            factions come from there). Left out: any trainer of the profession (Journeyman
--            Cooking and First Aid), found from the recipe data.
--     item   the book
--     quests { { id, name (English; the game's own is shown when it has it), side "A" | "H" | nil,
--              who = { NPC id }, bring = { { itemID, count }, ... } } }
--   }
--
-- Sources, and what each is good for:
--   * ForeverDB.app's profession pages (the ladder: skill, level, price, trainer / book / quest),
--     its spell pages' Trainers tables (who teaches a rank spell: marked "db" below), and its
--     item, NPC and quest pages (the books, their vendors, the quests).
--   * Where ForeverDB lists no trainer for a rank spell (every Artisan rank, most Expert ones,
--     most Alliance trainers), the lists are those the Forever trainer guides at
--     wow-professions.com and warcrafttavern.com agree on (marked "guides"): each NPC checked by
--     id and name against ForeverDB's NPC page and this plugin's NPC tables, but its rank is the
--     guides' word, not a database's. A trainer of a higher rank also teaches the lower ones
--     (ForeverDB shows it for Josef Gregorian, Bengus Deepforge, Hgarth, Doctor Herbert Halsey).
--   * Left out: trainers named by one guide only or whose NPC id could not be found (the new
--     Dalaran and Shen'dralas trainers, Bena Winterhoof), and the Apprentice-only trainers.
-- Facts only; no text or code from those sites or from any addon.
local _, ns = ...
if not ns.ok then return end

local function join(...)
	local out, seen = {}, {}
	for _, list in ipairs({ ... }) do
		for _, id in ipairs(list) do
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- (Each rank's own trainers; a rank's `who` is its own and every higher rank's.)
local ALCH = {
	j = { 3347, 4611, 2837,                               -- db: Yelmak, Doctor Herbert Halsey, Jaxin Chong
		4609, 2391, 5499, 5177, 11042, 3964, 4900 },        -- guides
	e = { 4611, 4160 },                                   -- db: Halsey; guides: Ainethil
	a = { 1386, 7948 },                                   -- guides: Rogvar, Kylanna Windwhisper
}
local SMITH = {
	j = { 1383, 4596, 3478, 276067, 10276, 4258, 3136, 252479,   -- db
		2998, 5511 },                                              -- guides
	e = { 4258, 3355 },                                   -- db: Bengus Deepforge; guides: Saru Steelfury
	a = { 2836 },                                         -- guides: Brikk Keencraft
}
local ENCH = {
	j = { 3345, 11074,                                    -- db: Godan, Hgarth
		3011, 4616, 1317, 5157, 4213, 7949 },               -- guides
	e = { 11074, 11072 },                                 -- db: Hgarth; guides: Kitta Firewind
	a = { 11073 },                                        -- guides: Annora (inside Uldaman)
}
local TAILOR = {
	j = { 3363, 3004, 11049, 5153, 252380, 251991,        -- db
		3704, 4159, 5567, 2627 },                           -- guides
	e = { 4576, 1346 },                                   -- db: Josef Gregorian; guides: Georgio Bolero
	a = { 2399, 11052 },                                  -- guides: Daryl Stack, Timothy Worthington
}
local ENGI = {
	j = { 3412,                                           -- db: Nogg
		11031, 11029, 5518, 1676 },                         -- guides
	e = { 11017, 5174 },                                  -- guides: Roxxik, Springspindle Fizzlegear
	a = { 8736 },                                         -- guides: Buzzek Bracketswing
}
local LEATHER = {
	j = { 252376,                                         -- db: Emerii Tallgust
		3365, 11084, 4588, 1385, 3703, 11081, 5127, 5564, 3967 },   -- guides
	e = { 3007, 4212 },                                   -- guides: Una, Telonis
	a = { 11098, 11097 },                                 -- guides: Hahrana Ironhide, Drakk Stonehand
}
-- (Every mining trainer but the starting zones' Junior ones teaches all three ranks: db for the
-- first ten, the guides for the last three.)
local MINERS = { 3175, 3357, 3001, 3555, 1681, 1701, 3137, 8128, 252388, 257022, 4254, 5513, 6297 }

local function trained(t, costs)
	return {
		[150] = { at = 50, level = 10, cost = costs[1], who = join(t.j, t.e, t.a) },
		[225] = { at = 125, level = 20, cost = costs[2], who = join(t.e, t.a) },
		[300] = { at = 200, level = 35, cost = costs[3], who = t.a },
	}
end

ns.Ranks = {
	[171] = trained(ALCH, { 500, 5000 }),
	[164] = trained(SMITH, { 450, 4500 }),
	[333] = trained(ENCH, { 500, 5000 }),
	[197] = trained(TAILOR, { 450, 5000 }),
	[202] = trained(ENGI, { 500 }),
	[165] = trained(LEATHER, { 500 }),
	[186] = {
		[150] = { at = 50, cost = 500, who = MINERS },
		[225] = { at = 125, cost = 5000, who = MINERS },
		[300] = { at = 200, cost = 50000, who = MINERS },
	},
	-- Cooking: Expert from the Expert Cookbook (two vendors, one a faction), Artisan from Dirge
	-- Quikcleave's quest in Gadgetzan.
	[185] = {
		[150] = { at = 50, cost = 500 },
		[225] = { how = "book", at = 125, cost = 10000, item = 16072, who = { 3955, 12033 } },
		[300] = { how = "quest", at = 200, level = 35, quests = {
			{ id = 6610, name = "Clamlette Surprise", who = { 8125 }, bring = { { 12207, 12 }, { 7974, 10 }, { 8932, 20 } } },
		} },
	},
	-- First Aid: Expert from "Expert First Aid - Under Wraps" (two vendors, one a faction), Artisan
	-- from the Triage quest of your faction's doctor.
	[129] = {
		[150] = { at = 50, cost = 500 },
		[225] = { how = "book", at = 125, cost = 10000, item = 16084, who = { 2805, 13476 } },
		[300] = { how = "quest", at = 200, level = 35, quests = {
			{ id = 6624, name = "Triage", side = "A", who = { 12939 } },
			{ id = 6622, name = "Triage", side = "H", who = { 12920 } },
		} },
	},
}
