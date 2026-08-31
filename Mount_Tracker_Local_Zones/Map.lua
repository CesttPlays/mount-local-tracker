local _, addon = ...

-- One icon per uncollected mount that has a known map position (Overrides.points
-- or the generated MountData.points), on both the world map and the minimap.
-- Uses HereBeDragons-Pins so it never taints the map.
--
-- Mounts with no position (most vendor / instance / reputation mounts) are not
-- pinned -- they still show in the tracker window. MountData.points ships empty;
-- the curated rare-drop coordinates live in Overrides.points (phase 6).

local Map = {}
addon.Map = Map

local HBDPins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)

local FALLBACK_ICON = "Interface\\ICONS\\Ability_Mount_RidingHorse"
local SHOW_ON_PARENT = HBD_PINS_WORLDMAP_SHOW_PARENT or 1

-- Colour comes from addon.Obtainability (single source of truth, shared with the
-- ListView rows). Alpha for dimmed states is a map-rendering choice, kept here.
local ALPHA_GATED = 0.55

-- ============================================================================
-- What to pin: uncollected positioned mounts, grouped by their pin map
-- ============================================================================

-- pins : { [uiMapID] = { { id, spellID, x, y, state, icon }, ... } }  (x/y 0-1)
local pins
local registered = false

function Map.Invalidate()
	pins = nil
	registered = false
end

-- Only mounts with a curated position can ever produce a pin: a `points` entry,
-- or (when db.showVendorIcons) a `vendor` entry that carries coordinates. BuildRow
-- still does the real filtering (row.include / collected / point); this just spares
-- it ~1800 calls for mounts that could never be pinned anyway. Keep the id sources
-- here in sync with BuildRow's row.point logic (MountModel.lua).
local function PositionedCandidates()
	local ids, seen = {}, {}
	local function add(tbl)
		if type(tbl) ~= "table" then
			return
		end
		for mountID in pairs(tbl) do
			if not seen[mountID] then
				seen[mountID] = true
				ids[#ids + 1] = mountID
			end
		end
	end

	local md = addon.MountData or {}
	local ov = addon.MountOverrides or {}
	add(md.points)
	add(ov.points)
	if addon.db and addon.db.showVendorIcons then
		add(md.vendor)
		add(ov.vendor)
	end
	return ids
end

local function Compute()
	pins = {}

	local MountModel = addon.MountModel
	if not (MountModel and MountModel.BuildRow) then
		return
	end

	local seen = {}
	local function consider(mountID)
		if seen[mountID] then
			return
		end
		seen[mountID] = true

		local row = MountModel.BuildRow(mountID)
		-- row.include folds in hidden / hiddenSources / unusable / faction /
		-- obtainable-only / show-collected -- Map respects all of them now.
		if not row or not row.include or row.isCollected or not row.point then
			return
		end

		local uiMapID = row.point[1]
		pins[uiMapID] = pins[uiMapID] or {}
		table.insert(pins[uiMapID], {
			id = mountID,
			spellID = row.spellID,
			x = row.point[2] / 10000,
			y = row.point[3] / 10000,
			state = row.state,
			icon = row.icon,
		})
	end

	for _, mountID in ipairs(PositionedCandidates()) do
		consider(mountID)
	end
end

-- ============================================================================
-- Pin pools (separate frames for world map and minimap -- HBD reparents them)
-- ============================================================================

local worldPool, minimapPool = {}, {}

local function ConfigurePin(pin)
	pin:SetSize(13, 13)
	pin.texture = pin:CreateTexture(nil, "OVERLAY")
	pin.texture:SetAllPoints()
	addon.TrimIcon(pin.texture)
	addon.BindMount(pin) -- hover tooltip + click, reads pin.mountID / pin.spellID
	return pin
end

local function Acquire(pool, index)
	local pin = pool[index]
	if not pin then
		pin = ConfigurePin(CreateFrame("Button", nil, UIParent))
		pool[index] = pin
	end
	return pin
end

local function DressPin(pin, entry)
	pin.mountID = entry.id
	pin.spellID = entry.spellID
	pin.texture:SetTexture(entry.icon or FALLBACK_ICON)

	local r, g, b = addon.Obtainability.Color(entry.state)
	local dim = addon.Obtainability.IsDimmed(entry.state)
	pin.texture:SetVertexColor(r, g, b)
	pin.texture:SetAlpha(dim and ALPHA_GATED or 1)
end

-- ============================================================================
-- Refresh
-- ============================================================================

-- Drop the current pin set and place it again from scratch. Use after anything
-- that changes *which* mounts should be pinned (a collected mount, an options
-- toggle); plain Refresh only redraws when it isn't already current.
function Map.Rebuild()
	Map.Invalidate()
	Map.Refresh()
end

function Map.Refresh()
	if not HBDPins then
		addon.DebugPrint("Map: HereBeDragons-Pins not loaded")
		return
	end
	if registered and pins then
		return -- already up to date
	end

	HBDPins:RemoveAllWorldMapIcons(addon)
	HBDPins:RemoveAllMinimapIcons(addon)
	for _, pin in ipairs(worldPool) do
		pin:Hide()
	end
	for _, pin in ipairs(minimapPool) do
		pin:Hide()
	end

	local wantWorld = addon.db and addon.db.showMapIcons
	local wantMinimap = addon.db and addon.db.showMinimapIcons
	if not (wantWorld or wantMinimap) then
		-- Nothing wanted: mark current so later refreshes are a no-op until an
		-- Invalidate (an options toggle goes through Map.Rebuild, which does).
		pins = pins or {}
		registered = true
		return
	end
	if not (addon.IsMountApiReady and addon.IsMountApiReady()) then
		return -- try again from the readiness retry / a zone change
	end

	if not pins then
		Compute()
	end

	local placed, zoneCount = 0, 0
	for uiMapID, entries in pairs(pins) do
		zoneCount = zoneCount + 1
		for _, entry in ipairs(entries) do
			placed = placed + 1

			if wantWorld then
				local worldPin = Acquire(worldPool, placed)
				DressPin(worldPin, entry)
				if not HBDPins:AddWorldMapIconMap(addon, worldPin, uiMapID, entry.x, entry.y, SHOW_ON_PARENT) then
					worldPin:Hide()
				end
			end

			if wantMinimap then
				local minimapPin = Acquire(minimapPool, placed)
				DressPin(minimapPin, entry)
				HBDPins:AddMinimapIconMap(addon, minimapPin, uiMapID, entry.x, entry.y, false, false)
			end
		end
	end

	registered = true
	addon.DebugPrint(string.format("Map: %d mount pins across %d zones", placed, zoneCount))
end
