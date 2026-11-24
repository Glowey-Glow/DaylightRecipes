-- The item an enchant goes on, as a row: a slot the item goes in (dragged there, or picked from a
-- menu of what you carry that it can go on; right-click, or a controller's Y, empties it), its name,
-- and the Auto-replace switch (the game's "replace the enchant?" answered yes during a run on this
-- item). Used by Glowey's Recipes' window (its craft bar, Window.lua) and by the docked pane
-- (Pane.lua); what it keeps and makes is Craft.lua's.
--   EnchantRow.New(parent, opts)   a new row, hidden, not placed. opts: pad (the side margin),
--                                  stacked (Auto-replace on a line of its own under the item, for
--                                  a narrow pane), onChange() (the item or Auto-replace changed:
--                                  draw again)
--   row:Update(spell, width)       filled for this enchant; returns its item (or nil). width: how
--                                  wide the row is (the window's column, the pane): the item's name
--                                  and the hint wrap inside it rather than being cut, and the row
--                                  is as tall as they need (row:GetHeight(); 46 for a line each)
--   row.target                     the item shown, row.spell the enchant
local _, ns = ...
if not ns.ok then return end

local API, Craft = ns.API, ns.Craft
local L = ns.L
local Color, Text = ns.Doc.Color, ns.Doc.Text

local EnchantRow = {}
ns.EnchantRow = EnchantRow

EnchantRow.HEIGHT = 46          -- the item line
EnchantRow.AUTO = 28            -- Auto-replace's own line, stacked
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local function PickTarget(row, owner)
	local spell = row.spell
	if not spell then return end
	local list = Craft.Targets(spell)
	if #list == 0 then
		ns.Print(L["Nothing you carry can take this enchant."])
		return
	end
	local keys, values, byKey = {}, {}, {}
	for i, t in ipairs(list) do
		local key = tostring(i)
		keys[#keys + 1] = key
		values[key] = t.name
		byKey[key] = t
	end
	API.Menu(owner, keys, values, nil, function(key)
		local t = byKey[key]
		if t then Craft.KeepTarget(t.guid) end
		row.onChange()
	end, 240)
end

-- The name and the hint as wide as the row leaves them (beside the Auto-replace label, or to the
-- row's edge when that is stacked under them), and the row as tall as they wrap to.
local function Fit(row, width)
	if not width or width <= 0 then width = row:GetWidth() end
	if not width or width <= 0 then return end
	local room = width - row.pad - 34 - 10 - row.pad
	if not row.stacked then
		room = room - 12 - math.ceil(row.autoLabel:GetStringWidth()) - 8 - row.auto:GetWidth()
	end
	room = math.max(60, room)
	row.name:SetWidth(room)
	row.hint:SetWidth(room)
	local h = math.max(EnchantRow.HEIGHT, 6 + math.ceil(row.name:GetStringHeight()) + 3 + math.ceil(row.hint:GetStringHeight()) + 6)
	row:SetHeight(h + (row.stacked and EnchantRow.AUTO or 0))
end

local function Update(row, spell, width)
	row.spell = spell
	local t = spell and Craft.EnchantTarget(spell) or nil
	row.icon:SetTexture(t and t.icon or EMPTY_SLOT)
	row.icon:SetDesaturated(t == nil)
	row.name:SetText(t and t.name or L["Drag an item here"])
	row.name:SetTextColor(Color(t and "VALUE" or "LABEL"))
	row.hint:SetText(t and L["Every enchant here goes on it"] or L["or click to pick one from your bags"])
	row.hint:SetTextColor(Color("OFF"))
	row.auto.SetOn(Craft.AutoReplace())
	row.target = t
	Fit(row, width)
	return t
end

function EnchantRow.New(parent, opts)
	opts = opts or {}
	local pad = opts.pad or 14
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(EnchantRow.HEIGHT + (opts.stacked and EnchantRow.AUTO or 0))
	row:Hide()
	row.onChange = opts.onChange or function() end
	row.Update = Update
	row.pad, row.stacked = pad, opts.stacked == true

	local slot = CreateFrame("Button", nil, row)
	slot:SetSize(34, 34)
	slot:SetPoint("LEFT", row, "TOPLEFT", pad, -EnchantRow.HEIGHT / 2 - 2)
	-- (Host.Skin: dressed again after a look change.)
	ns.Host.Skin(slot, { noBevel = true })
	slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.icon = slot:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("TOPLEFT", 3, -3)
	row.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local function Take()
		local spell = row.spell
		if not spell then return end
		if not Craft.TakeFromCursor(spell) then ns.Print(L["That item can't take this enchant."]) end
		row.onChange()
	end
	slot:SetScript("OnReceiveDrag", Take)
	slot:SetScript("OnClick", function(self, button)
		if CursorHasItem() then
			Take()
		elseif button == "RightButton" then
			if row.spell then Craft.DropTarget(row.spell) end
			row.onChange()
		else
			PickTarget(row, self)
		end
	end)
	-- A controller's Y: the right-click (empties the slot).
	slot.padMore = function()
		if not (row.target and row.spell) then return nil end
		return function()
			Craft.DropTarget(row.spell)
			row.onChange()
		end
	end
	slot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		local t = row.target
		if t and t.link then
			GameTooltip:SetHyperlink(t.link)
			GameTooltip:AddLine(" ")
		else
			GameTooltip:SetText(L["The item to enchant"])
		end
		GameTooltip:AddLine(L["Drag an item here, or click to pick one. Right-click empties it."], Color("LABEL"))
		GameTooltip:Show()
	end)
	slot:SetScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.slot = slot
	-- (The name and hint run up to the Auto-replace label, or to the row's edge when it's stacked:
	-- Fit gives them that width, and they wrap inside it.)
	row.name = Text(row, "body")
	row.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(true)
	row.name:SetWidth(150)
	row.hint = Text(row, "small")
	row.hint:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.hint:SetJustifyH("LEFT")
	row.hint:SetWordWrap(true)
	row.hint:SetWidth(150)

	row.auto = API.Switch(row)
	if opts.stacked then
		row.auto:SetPoint("RIGHT", row, "BOTTOMRIGHT", -pad, EnchantRow.AUTO / 2)
	else
		row.auto:SetPoint("RIGHT", row, "TOPRIGHT", -pad, -EnchantRow.HEIGHT / 2 - 2)
	end
	row.auto:SetScript("OnClick", function()
		Craft.SetAutoReplace(not Craft.AutoReplace())
		row.onChange()
	end)
	row.auto:HookScript("OnEnter", function(self)
		ns.Host.TipLines(self, function(t)
			t.Line(L["Auto-replace"], "TITLE")
			t.Line(L["Answers the game's \"replace the enchant?\" with yes while a run of yours is putting enchants on this item, so it doesn't stop at every cast."], "TEXT", true)
			t.Line(L["Off: the game asks each time."], "LABEL", true)
		end, "ANCHOR_TOP")
	end)
	row.auto:HookScript("OnLeave", function(self)
		if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
	row.autoLabel = Text(row, "small", "RIGHT")
	row.autoLabel:SetPoint("RIGHT", row.auto, "LEFT", -8, 0)
	row.autoLabel:SetText(L["Auto-replace"])
	row.autoLabel:SetTextColor(Color("LABEL"))
	return row
end
