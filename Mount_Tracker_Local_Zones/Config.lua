local _, addon = ...

-- Options panel built on the retail Settings API (the old InterfaceOptions_*
-- system was deprecated in 10.0). Settings are bound directly to the saved
-- variables table, so no separate persistence is needed.

local categoryID

-- The "Filter by source" section iterates addon.MountModel.SOURCE_ORDER (the one
-- canonical source-type list) so its checkboxes always match the tracker list's
-- group headers. Labels come from addon.MountModel.SourceLabel.

-- Settings whose value is folded into the MountModel cache key (see
-- MountModel.CACHE_KEYS). Changing any of them changes the tracker list content.
local CACHE_AFFECTING = {}
for _, key in ipairs((addon.MountModel and addon.MountModel.CACHE_KEYS) or {}) do
	CACHE_AFFECTING[key] = true
end

local function InvalidateAndRefresh()
	if addon.MountModel then
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end

-- React only to what each setting actually affects.
local function OnSettingChanged(key)
	if key == "showMinimapButton" then
		if addon.ApplyMinimapButton then
			addon.ApplyMinimapButton()
		end
		return
	end

	if key == "windowStyle" then
		if addon.NotifyWindowStyleChanged then
			addon.NotifyWindowStyleChanged()
		end
		return
	end

	-- Map-only toggles: they change world/minimap icon rendering, nothing in the
	-- tracker list.
	if key == "showMapIcons" or key == "showMinimapIcons" then
		if addon.Map then
			addon.Map.Rebuild()
		end
		return
	end

	-- showVendorIcons feeds row.point for vendor mounts (part of the model cache
	-- key now) *and* drives the map pins, so it needs both a rebuild and a
	-- cache invalidation. It falls through to the CACHE_AFFECTING check below.
	if key == "showVendorIcons" and addon.Map then
		addon.Map.Rebuild()
	end

	-- groupBy / showCollected / showObtainableOnly / showUnusable / showGlobal /
	-- showVendorIcons or a hiddenSources toggle: the list content changes, so
	-- drop the model cache and refresh the window.
	if key == "hiddenSources" or CACHE_AFFECTING[key] then
		InvalidateAndRefresh()
	end
end

-- ============================================================================
-- Control helpers
-- ============================================================================

local function AddCheckbox(category, key, name, tooltip)
	-- 11.0.2 signature: (category, variable, variableKey, variableTbl, type, name, default)
	-- The default comes from addon.defaults so it always matches a fresh install.
	local setting =
		Settings.RegisterAddOnSetting(category, "MTLZ_" .. key, key, addon.db, "boolean", name, addon.defaults[key])
	Settings.CreateCheckbox(category, setting, tooltip)
	setting:SetValueChangedCallback(function()
		OnSettingChanged(key)
	end)
end

-- A text dropdown bound straight to a string saved variable. `options` is a list
-- of { value, label } pairs. Skips itself on clients without the dropdown
-- Settings API rather than erroring.
local function AddDropdown(category, key, name, tooltip, options)
	if type(Settings.CreateDropdown) ~= "function" or type(Settings.CreateControlTextContainer) ~= "function" then
		return
	end

	local setting =
		Settings.RegisterAddOnSetting(category, "MTLZ_" .. key, key, addon.db, "string", name, addon.defaults[key])

	Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		for _, option in ipairs(options) do
			container:Add(option[1], option[2])
		end
		return container:GetData()
	end, tooltip)

	setting:SetValueChangedCallback(function()
		OnSettingChanged(key)
	end)
end

-- A gold section header inside the same panel. Grouping only -- if the client
-- lacks the helper the settings just render ungrouped.
local function AddSection(layout, title)
	if layout
		and type(layout.AddInitializer) == "function"
		and type(CreateSettingsListSectionHeaderInitializer) == "function"
	then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
	end
end

-- ============================================================================
-- "Filter by source" section
--
-- Each checkbox reads "Show <label>" but the saved state is the *hidden* flag
-- (db.hiddenSources[type] is true only when the box is unchecked). A metatable
-- proxy inverts the value so the Settings API can bind to it like any boolean.
-- ============================================================================

local sourceFilterProxy = setmetatable({}, {
	__index = function(_, proxyKey)
		local sourceType = proxyKey:match("^show_(.+)$")
		if not sourceType then
			return nil
		end
		local hidden = addon.db.hiddenSources
		return not (hidden and hidden[sourceType])
	end,
	__newindex = function(_, proxyKey, value)
		local sourceType = proxyKey:match("^show_(.+)$")
		if not sourceType then
			return
		end
		addon.db.hiddenSources = addon.db.hiddenSources or {}
		addon.db.hiddenSources[sourceType] = (not value) or nil
	end,
})

local function AddSourceFilters(category, layout)
	AddSection(layout, "Filter by source")
	for _, sourceType in ipairs(addon.MountModel.SOURCE_ORDER) do
		local label = addon.MountModel.SourceLabel(sourceType)
		local proxyKey = "show_" .. sourceType
		local setting = Settings.RegisterAddOnSetting(
			category, "MTLZ_" .. proxyKey, proxyKey, sourceFilterProxy, "boolean", "Show " .. label, true
		)
		Settings.CreateCheckbox(category, setting, ("Show %s mounts in the tracker list."):format(label:lower()))
		setting:SetValueChangedCallback(function()
			OnSettingChanged("hiddenSources")
		end)
	end
end

-- ============================================================================
-- "Hidden mounts" sub-panel
--
-- A canvas subcategory listing everything the user has hidden (right-click a
-- mount -> Hide this mount) with a per-row Restore button and a Restore all.
-- The list is rebuilt every time the panel is shown. Mounts are bucketed by
-- their source type so no Mount Journal enumeration is needed.
-- ============================================================================

local HIDDEN_ROW_TEMPLATE = "MountTrackerLocalHiddenRowTemplate"
local HIDDEN_HEADER_TEMPLATE = "MountTrackerLocalHiddenHeaderTemplate"
local HIDDEN_ROW_HEIGHT = 26
local HIDDEN_HEADER_HEIGHT = 24
local FALLBACK_ICON = "Interface\\ICONS\\Ability_Mount_RidingHorse"

local function SourceBucketLabel(mountID)
	local source = addon.Curated("source", mountID)
	return addon.MountModel.SourceLabel(source or "other")
end

local function BuildHiddenHeader(header)
	header.restore = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
	header.restore:SetSize(130, 20)
	header.restore:SetPoint("RIGHT", header, "RIGHT", -2, 0)
	header.restore:SetText("Restore section")

	header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header.label:SetPoint("LEFT", header, "LEFT", 4, 0)
	header.label:SetPoint("RIGHT", header.restore, "LEFT", -8, 0)
	header.label:SetJustifyH("LEFT")
	header.label:SetWordWrap(false)
end

local function InitHiddenHeader(header, elementData)
	if not header.built then
		BuildHiddenHeader(header)
		header.built = true
	end

	header.label:SetText(string.format("%s  |cff9d9d9d%d|r", elementData.name, #elementData.ids))
	header.restore:SetScript("OnClick", function()
		for _, id in ipairs(elementData.ids) do
			addon.SetMountHidden(id, false)
		end
		if elementData.rebuild then
			elementData.rebuild()
		end
	end)
end

local function BuildHiddenRow(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
	addon.TrimIcon(row.icon)

	row.restore = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.restore:SetSize(90, 22)
	row.restore:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.restore:SetText("Restore")

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", row.restore, "LEFT", -8, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
end

local function InitHiddenRow(row, elementData)
	if not row.built then
		BuildHiddenRow(row)
		row.built = true
	end

	row.icon:SetTexture(elementData.icon or FALLBACK_ICON)
	row.label:SetText(elementData.name)
	row.restore:SetScript("OnClick", function()
		addon.SetMountHidden(elementData.id, false)
		if elementData.rebuild then
			elementData.rebuild()
		end
	end)
end

local function AddHiddenMountsPanel(parentCategory)
	if
		type(Settings.RegisterCanvasLayoutSubcategory) ~= "function"
		or type(CreateScrollBoxListLinearView) ~= "function"
	then
		return -- older client without the canvas / ScrollBox API; skip silently
	end

	local panel = CreateFrame("Frame")
	panel:SetSize(680, 500)
	-- The settings canvas calls these if present; this panel writes changes
	-- immediately (via addon.SetMountHidden), so they are no-ops.
	panel.OnCommit = function() end
	panel.OnDefault = function() end
	panel.OnRefresh = function() end

	local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -14)
	intro:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -14)
	intro:SetJustifyH("LEFT")
	intro:SetText(
		"Mounts you have hidden (right-click a mount -> Hide this mount). Hidden mounts "
			.. "stay out of the tracker list and off the map."
	)

	local restoreAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	restoreAll:SetSize(120, 24)
	restoreAll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -46)
	restoreAll:SetText("Restore all")

	local empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -84)
	empty:SetText("No hidden mounts.")

	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -80)
	scrollBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 10)

	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

	-- Same ScrollBox wiring as the tracker list (see ListView.Init).
	local view = CreateScrollBoxListLinearView(0, 0, 0, 0, 2)
	view:SetElementExtentCalculator(function(_, elementData)
		return elementData.isHeader and HIDDEN_HEADER_HEIGHT or HIDDEN_ROW_HEIGHT
	end)
	view:SetElementFactory(function(factory, elementData)
		if elementData.isHeader then
			factory(HIDDEN_HEADER_TEMPLATE, InitHiddenHeader)
		else
			factory(HIDDEN_ROW_TEMPLATE, InitHiddenRow)
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local function Rebuild()
		local provider = CreateDataProvider()
		local count = 0
		local hidden = addon.db and addon.db.hidden
		if hidden then
			-- Bucket the hidden ids by source type, then sort buckets and rows
			-- alphabetically so a long list stays scannable.
			local buckets, order = {}, {}
			for id in pairs(hidden) do
				local name, _, icon = addon.MountInfo(id)
				local bucketName = SourceBucketLabel(id)
				local bucket = buckets[bucketName]
				if not bucket then
					bucket = { name = bucketName, ids = {}, entries = {} }
					buckets[bucketName] = bucket
					order[#order + 1] = bucket
				end
				bucket.ids[#bucket.ids + 1] = id
				bucket.entries[#bucket.entries + 1] = {
					id = id,
					name = (type(name) == "string" and name ~= "" and name) or ("Mount " .. id),
					icon = icon,
					rebuild = Rebuild,
				}
				count = count + 1
			end

			table.sort(order, function(a, b)
				return a.name < b.name
			end)
			for _, bucket in ipairs(order) do
				table.sort(bucket.entries, function(a, b)
					return a.name < b.name
				end)
				provider:Insert({ isHeader = true, name = bucket.name, ids = bucket.ids, rebuild = Rebuild })
				for _, entry in ipairs(bucket.entries) do
					provider:Insert(entry)
				end
			end
		end
		scrollBox:SetDataProvider(provider, ScrollBoxConstants.DiscardScrollPosition)
		empty:SetShown(count == 0)
	end

	restoreAll:SetScript("OnClick", function()
		local hidden = addon.db and addon.db.hidden
		if hidden then
			for id in pairs(hidden) do
				addon.SetMountHidden(id, false)
			end
		end
		Rebuild()
	end)

	panel:SetScript("OnShow", Rebuild)

	Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Hidden mounts")
end

-- ============================================================================
-- Setup
-- ============================================================================

function addon.SetupConfig()
	if categoryID then
		return
	end
	if type(Settings) ~= "table" or type(Settings.RegisterAddOnSetting) ~= "function" then
		return
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory("Mount Tracker: Local Zones")

	AddSection(layout, "Window")
	AddDropdown(
		category,
		"windowStyle",
		"Window style",
		"Classic uses the Blizzard dialog frame and scrollbar. Stylized uses a flat dark panel "
			.. "with minimal controls. Reload your UI (/reload) after changing this.",
		{ { "stylized", "Stylized" }, { "classic", "Classic" } }
	)
	AddCheckbox(
		category,
		"reopenWindow",
		"Reopen on login",
		"Reopen the tracker window when you log in if it was open when you logged out."
	)

	AddSection(layout, "Mount list")
	AddDropdown(
		category,
		"groupBy",
		"Group by",
		"How the tracked mounts are grouped in the list.",
		{ { "source", "By source type" }, { "expansion", "By expansion" } }
	)
	AddCheckbox(
		category,
		"showCollected",
		"Show collected mounts",
		"Include mounts you already own. They appear greyed out in the list."
	)
	AddCheckbox(
		category,
		"showObtainableOnly",
		"Only show obtainable mounts",
		"Hide mounts you can't get right now (reputation locked, weekly farm already done, "
			.. "achievement incomplete)."
	)
	AddCheckbox(
		category,
		"showUnusable",
		"Show unusable mounts",
		"Include mounts your class or faction can't use. They appear dimmed. Turn off to hide them."
	)
	AddCheckbox(
		category,
		"showGlobal",
		"Show global mounts",
		"Also list mounts with no home zone (class, racial, PvP, store, promotion), under a "
			.. "\"Global\" divider. Their sections start collapsed."
	)

	AddSourceFilters(category, layout)

	AddSection(layout, "Map & minimap")
	AddCheckbox(
		category,
		"showMinimapButton",
		"Show minimap button",
		"A button on the minimap that toggles the tracker (right-click for options)."
	)
	AddCheckbox(
		category,
		"showMapIcons",
		"Show world map icons",
		"An icon on the world map for each uncollected mount that has a known location."
	)
	AddCheckbox(
		category,
		"showMinimapIcons",
		"Show minimap icons",
		"An icon on the minimap for each nearby uncollected mount that has a known location."
	)
	AddCheckbox(
		category,
		"showVendorIcons",
		"Show vendor icons",
		"Also mark the vendor on the map for mounts you can buy."
	)

	Settings.RegisterAddOnCategory(category)
	categoryID = category:GetID()

	AddHiddenMountsPanel(category)
end

function addon.OpenConfig()
	if categoryID and type(Settings.OpenToCategory) == "function" then
		Settings.OpenToCategory(categoryID)
	else
		addon.Print("Options panel is unavailable.")
	end
end
