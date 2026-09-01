local _, addon = ...
local L = addon.L

-- Collapsible grouped list for the tracker window, built on the Blizzard
-- ScrollBox (WowScrollBoxList + MinimalScrollBar). The list is a flat sequence
-- of "header", "row" and "separator" elements held in a DataProvider; collapsing
-- a group or toggling a filter just rebuilds the provider.
--
-- Owner wiring:
--   ListView.Init(scrollBox, scrollBar)  once, from the window
--   ListView.Layout(groups) -> number of headers shown  (0 => nothing visible)
--   ListView.Clear()  empty the list (used while a status message is shown)

local ListView = {}
addon.ListView = ListView

local HEADER_HEIGHT = 22
local ROW_HEIGHT = 18
local ROW_INDENT = 22
local SEPARATOR_HEIGHT = 24
local CONTENT_PADDING = 6

local HEADER_TEMPLATE = "MountTrackerLocalGroupHeaderTemplate"
local ROW_TEMPLATE = "MountTrackerLocalMountRowTemplate"
local SEPARATOR_TEMPLATE = "MountTrackerLocalSeparatorTemplate"

local PLUS_TEXTURE = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS_TEXTURE = "Interface\\Buttons\\UI-MinusButton-Up"

-- Global (class / racial / PvP / shop) groups start collapsed. Their collapsed
-- state already lives under a "g:"-prefixed key from MountModel, so it never
-- clashes with the same group shown as a real zone section.
local GLOBAL_SEPARATOR_LABEL = L["Global"]

local DIM_ALPHA = 0.5 -- mounts your class/faction can't use, when they're shown

local scrollBox

-- ============================================================================
-- Element frames
--
-- The ScrollBox pools frames by template and reuses them, so each Init function
-- runs on both fresh and recycled frames: build the child regions once (guarded
-- by frame.built), then refill them from the element's data every call.
-- ============================================================================

local function BuildHeader(header)
	header.toggle = header:CreateTexture(nil, "ARTWORK")
	header.toggle:SetSize(16, 16)
	header.toggle:SetPoint("LEFT", header, "LEFT", 2, 0)

	header.icon = header:CreateTexture(nil, "ARTWORK")
	header.icon:SetSize(16, 16)
	header.icon:SetPoint("LEFT", header.toggle, "RIGHT", 4, 0)
	addon.TrimIcon(header.icon)

	header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header.label:SetPoint("LEFT", header.icon, "RIGHT", 6, 0)
	header.label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
	header.label:SetJustifyH("LEFT")
	header.label:SetWordWrap(false)

	header:SetScript("OnClick", function(self)
		local collapsed = addon.db.collapsed
		local key = self.collapseKey
		if self.defaultCollapsed then
			-- default-collapsed section: absent key = collapsed, `false` = the
			-- user opened it. (Can't use the and/or idiom -- it can't yield nil.)
			if collapsed[key] == false then
				collapsed[key] = nil
			else
				collapsed[key] = false
			end
		else
			collapsed[key] = (not collapsed[key]) or nil
		end
		addon.RefreshWindow()
	end)
end

local function InitHeader(header, elementData)
	if not header.built then
		BuildHeader(header)
		header.built = true
	end

	local group = elementData.group
	header.collapseKey = elementData.collapseKey
	header.defaultCollapsed = elementData.defaultCollapsed
	header.toggle:SetTexture(elementData.collapsed and PLUS_TEXTURE or MINUS_TEXTURE)

	if group.icon then
		header.icon:SetTexture(group.icon)
		header.icon:Show()
	else
		header.icon:Hide()
	end

	local text = string.format("%s  |cff9d9d9d%d/%d|r", group.label, group.collected, group.total)
	if (group.available or 0) > 0 then
		text = text .. "  " .. ("|cff66cc66\194\183 %s|r"):format(L["%d available"]:format(group.available))
	end
	header.label:SetText(text)
end

local function BuildRow(row)
	addon.BindMount(row) -- hover tooltip + click-to-open, reads row.mountID / row.spellID

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row, "LEFT", ROW_INDENT, 0)
	addon.TrimIcon(row.icon)

	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.status:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.status:SetJustifyH("RIGHT")

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
end

local function InitRow(row, elementData)
	if not row.built then
		BuildRow(row)
		row.built = true
	end

	local entry = elementData.entry
	local r, g, b = addon.Obtainability.Color(entry.state)
	local alpha = (not entry.isUsable and addon.db.showUnusable) and DIM_ALPHA or 1

	row.mountID = entry.id
	row.spellID = entry.spellID

	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:SetAlpha(alpha)
		row.icon:Show()
	else
		row.icon:Hide()
	end

	row.label:SetText(entry.name)
	row.label:SetTextColor(r, g, b)
	row.label:SetAlpha(alpha)

	row.status:SetText(entry.detail or (entry.state == "collected" and L["collected"]) or "")
	row.status:SetTextColor(r, g, b)
	row.status:SetAlpha(alpha)
end

-- A centered caption with a hairline running out to each side.
local function BuildSeparator(sep)
	sep.label = sep:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	sep.label:SetPoint("CENTER", sep, "CENTER", 0, 0)

	sep.lineLeft = sep:CreateTexture(nil, "ARTWORK")
	sep.lineLeft:SetColorTexture(1, 1, 1, 0.10)
	sep.lineLeft:SetHeight(1)
	sep.lineLeft:SetPoint("LEFT", sep, "LEFT", 4, 0)
	sep.lineLeft:SetPoint("RIGHT", sep.label, "LEFT", -8, 0)

	sep.lineRight = sep:CreateTexture(nil, "ARTWORK")
	sep.lineRight:SetColorTexture(1, 1, 1, 0.10)
	sep.lineRight:SetHeight(1)
	sep.lineRight:SetPoint("LEFT", sep.label, "RIGHT", 8, 0)
	sep.lineRight:SetPoint("RIGHT", sep, "RIGHT", -4, 0)
end

local function InitSeparator(sep, elementData)
	if not sep.built then
		BuildSeparator(sep)
		sep.built = true
	end
	sep.label:SetText(elementData.label or "")
end

-- ============================================================================
-- Setup
-- ============================================================================

function ListView.Init(box, bar)
	scrollBox = box

	-- top/bottom/left/right/spacing -- pad the list away from the frame edges.
	local view = CreateScrollBoxListLinearView(CONTENT_PADDING, CONTENT_PADDING, 0, 0, 0)
	view:SetElementExtentCalculator(function(_, elementData)
		if elementData.kind == "header" then
			return HEADER_HEIGHT
		elseif elementData.kind == "separator" then
			return SEPARATOR_HEIGHT
		end
		return ROW_HEIGHT
	end)
	view:SetElementFactory(function(factory, elementData)
		if elementData.kind == "header" then
			factory(HEADER_TEMPLATE, InitHeader)
		elseif elementData.kind == "separator" then
			factory(SEPARATOR_TEMPLATE, InitSeparator)
		else
			factory(ROW_TEMPLATE, InitRow)
		end
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
end

-- ============================================================================
-- Population
-- ============================================================================

-- A group is worth showing unless every mount in it is collected and collected
-- rows are hidden.
local function GroupHasVisibleRows(group, showCollected)
	return showCollected or group.collected < group.total
end

-- Collapse key + collapsed state + default for a group. Zone groups default to
-- open and store `true` when collapsed; global groups default to collapsed and
-- store `false` when the user opens them.
local function CollapseStateFor(collapsed, group)
	if group.isGlobal then
		return group.key, collapsed[group.key] ~= false, true
	end
	return group.key, collapsed[group.key] and true or false, false
end

function ListView.Clear()
	if scrollBox then
		scrollBox:Flush()
	end
end

-- Rebuild the flat element list from every visible group. Returns the number of
-- headers shown (0 => nothing to draw, caller shows a status message instead).
function ListView.Layout(groups)
	local provider = CreateDataProvider()
	local usedHeaders = 0
	local collapsed = addon.db.collapsed
	local showCollected = addon.db.showCollected
	local sawGlobal = false

	for _, group in ipairs(groups) do
		if GroupHasVisibleRows(group, showCollected) then
			if group.isGlobal and not sawGlobal then
				sawGlobal = true
				provider:Insert({ kind = "separator", label = GLOBAL_SEPARATOR_LABEL })
			end

			local key, isCollapsed, defaultCollapsed = CollapseStateFor(collapsed, group)

			usedHeaders = usedHeaders + 1
			provider:Insert({
				kind = "header",
				group = group,
				collapsed = isCollapsed,
				collapseKey = key,
				defaultCollapsed = defaultCollapsed,
			})

			if not isCollapsed then
				for _, entry in ipairs(group.rows) do
					if showCollected or not entry.isCollected then
						provider:Insert({ kind = "row", entry = entry })
					end
				end
			end
		end
	end

	scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
	return usedHeaders
end
