local _, addon = ...

-- Turns "the zone you're standing in" into a grouped list of the mounts you can
-- still collect there. Zone membership comes from the datamined MountData plus
-- hand-tuned Overrides; per-mount obtainability comes from Obtainability.lua.

local MountModel = {}
addon.MountModel = MountModel

local SafeApiCall = addon.SafeApiCall
local Obtainability = addon.Obtainability

local Curated = addon.Curated -- Overrides wins over generated MountData; see Core.lua

local EMPTY = {} -- shared read-only sentinel for "no list"

-- Loop guard for the map parent-chain walk. Real WoW map trees are a handful of
-- levels deep; this is purely a runaway-cycle stop.
local MAX_TREE_DEPTH = 15

-- The "obtainable right now" states, for the showObtainableOnly filter and the
-- zone "available" count.
local OBTAINABLE = { available = true, farmable = true, drop = true }

-- ============================================================================
-- Source-type groups (groupBy == "source")
-- ============================================================================

-- display order + label. A mount whose source is missing / unknown falls to "other".
local SOURCE_ORDER = { "instance", "drop", "rare", "vendor", "quest", "zonedrop", "worldevent", "profession", "achievement", "other" }
local SOURCE_LABEL = {
	instance = "Dungeon & Raid",
	drop = "Rare Drop",
	rare = "Rare Drop",
	vendor = "Vendor",
	quest = "Quest",
	zonedrop = "Zone Drop",
	worldevent = "World Event",
	profession = "Profession",
	achievement = "Achievement",
	other = "Other",
}
local SOURCE_RANK = {}
for index, key in ipairs(SOURCE_ORDER) do
	SOURCE_RANK[key] = index
end

-- ============================================================================
-- Expansion groups (groupBy == "expansion")
-- ============================================================================

-- Enum.ExpansionType-ish ids seen in ItemSparse. Negatives / 0 are classic-era.
local EXPANSION_LABEL = {
	[0] = "Classic",
	[1] = "The Burning Crusade",
	[2] = "Wrath of the Lich King",
	[3] = "Cataclysm",
	[4] = "Mists of Pandaria",
	[5] = "Warlords of Draenor",
	[6] = "Legion",
	[7] = "Battle for Azeroth",
	[8] = "Shadowlands",
	[9] = "Dragonflight",
	[10] = "The War Within",
	[11] = "Midnight",
}

local function ExpansionLabel(id)
	local n = tonumber(id)
	if not n then
		return "Other"
	end
	if n < 0 then
		n = 0
	end
	return EXPANSION_LABEL[n] or "Other"
end

-- ============================================================================
-- Zone resolution
-- ============================================================================

local function GetCurrentMapID()
	if type(C_Map) ~= "table" then
		return nil
	end
	return SafeApiCall(C_Map.GetBestMapForUnit, "player")
end

-- Every uiMapID from the player's map up through its parents, closest first.
local function GetMapChain(mapID)
	local chain = {}
	if not mapID or type(C_Map) ~= "table" then
		return mapID and { mapID } or chain
	end
	local current, guard = mapID, 0
	while current and guard < MAX_TREE_DEPTH do
		chain[#chain + 1] = current
		local info = SafeApiCall(C_Map.GetMapInfo, current)
		if type(info) ~= "table" or not info.parentMapID or info.parentMapID == 0 then
			break
		end
		current = info.parentMapID
		guard = guard + 1
	end
	return chain
end

-- ============================================================================
-- Candidate sets (generated MountData + Overrides)
-- ============================================================================

-- Merge MountData.zones + Overrides.add for a set of uiMapIDs, applying
-- Overrides.remove. mapIDs = nil means "every zone" (the map-pin pass).
-- Returns: ids (array, deduped, insertion order) and removed (set).
local function CandidateSet(mapIDs)
	local zones = (addon.MountData and addon.MountData.zones) or EMPTY
	local overrides = addon.MountOverrides or EMPTY
	local add = overrides.add or EMPTY
	local remove = overrides.remove or EMPTY

	if not mapIDs then
		local union = {}
		for id in pairs(zones) do
			union[id] = true
		end
		for id in pairs(add) do
			union[id] = true
		end
		mapIDs = {}
		for id in pairs(union) do
			mapIDs[#mapIDs + 1] = id
		end
	end

	local removed = {}
	for _, mapID in ipairs(mapIDs) do
		for _, id in ipairs(remove[mapID] or EMPTY) do
			removed[id] = true
		end
	end

	local ids, seen = {}, {}
	local function collect(list)
		for _, id in ipairs(list or EMPTY) do
			if not removed[id] and not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	for _, mapID in ipairs(mapIDs) do
		collect(zones[mapID])
		collect(add[mapID])
	end

	return ids, removed
end

MountModel.CandidateSet = CandidateSet

-- The seeded "global" ids: mounts with no home zone (class / racial / PvP / TCG /
-- shop). uiMapID 0 is not a real map, so Overrides.remove[0] doubles as the
-- "suppress this global" key.
local function GlobalCandidateSet()
	local list = (addon.MountData and addon.MountData.global) or EMPTY
	local overrides = addon.MountOverrides or EMPTY
	local removed = {}
	for _, id in ipairs((overrides.remove and overrides.remove[0]) or EMPTY) do
		removed[id] = true
	end

	local ids, seen = {}, {}
	for _, id in ipairs(list) do
		if not removed[id] and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	return ids
end

MountModel.GlobalCandidateSet = GlobalCandidateSet

-- ============================================================================
-- Per-mount rows
-- ============================================================================

local function PlayerFactionIndex()
	local faction = SafeApiCall(UnitFactionGroup, "player")
	if faction == "Alliance" then
		return 1
	elseif faction == "Horde" then
		return 0
	end
	return nil
end

local function PointFor(mountID)
	local point = Curated("points", mountID)
	return type(point) == "table" and point or nil
end

-- { id, name, spellID, icon, isUsable, isCollected, source, subcat, expansion,
--   state, detail, sortRank, point } or nil when the mount is filtered out.
local function BuildRow(mountID)
	local name, spellID, icon, _, isUsable, _, _, _, _, _, isCollected =
		addon.MountInfo(mountID)

	if type(name) ~= "string" or name == "" then
		return nil -- not a real / not-yet-loaded mount id
	end

	local db = addon.db or EMPTY

	if isCollected and not db.showCollected then
		return nil
	end
	if db.hidden and db.hidden[mountID] then
		return nil
	end

	local source = Curated("source", mountID) or "other"
	if db.hiddenSources and db.hiddenSources[source] then
		return nil
	end

	-- Faction-specific mounts: hide the other faction's version.
	local requiredFaction = Curated("faction", mountID)
	if requiredFaction ~= nil then
		local playerFaction = PlayerFactionIndex()
		if playerFaction ~= nil and playerFaction ~= requiredFaction then
			return nil
		end
	end

	if isUsable == false and not db.showUnusable then
		return nil
	end

	local row = {
		id = mountID,
		name = name,
		spellID = spellID,
		icon = icon,
		isUsable = isUsable ~= false,
		isCollected = isCollected and true or false,
		source = source,
		subcat = Curated("subcat", mountID),
		expansion = Curated("expansion", mountID),
		point = PointFor(mountID),
	}

	-- Vendor-purchase mounts have no spawn point of their own. When the user opts
	-- in (db.showVendorIcons), fall back to the vendor's location so Map.lua pins
	-- them at the merchant. The right-click "... (vendor)" waypoint actions work
	-- regardless of this toggle (see Core.VendorLocation).
	if not row.point and db.showVendorIcons and addon.VendorLocation then
		row.point = addon.VendorLocation(mountID)
	end

	local verdict = Obtainability and Obtainability.Evaluate(mountID, row)
		or { state = isCollected and "collected" or "drop", sortRank = 99 }
	row.state = verdict.state
	row.detail = verdict.detail
	row.sortRank = verdict.sortRank

	if db.showObtainableOnly and not (row.isCollected or OBTAINABLE[row.state]) then
		return nil
	end

	return row
end

MountModel.BuildRow = BuildRow

-- ============================================================================
-- Grouping
-- ============================================================================

local function FinishGroup(group)
	table.sort(group.rows, function(a, b)
		if (a.sortRank or 99) ~= (b.sortRank or 99) then
			return (a.sortRank or 99) < (b.sortRank or 99)
		end
		return a.name < b.name
	end)

	group.icon = group.rows[1] and group.rows[1].icon or nil
	group.total = #group.rows
	group.collected = 0
	group.available = 0
	for _, row in ipairs(group.rows) do
		if row.isCollected then
			group.collected = group.collected + 1
		end
		if row.state == "available" then
			group.available = group.available + 1
		end
	end
end

-- ids -> array of { key, label, icon, rows, total, collected, available, isGlobal }.
local function GroupRows(ids, groupBy, isGlobal)
	local groups, byKey = {}, {}

	for _, mountID in ipairs(ids) do
		local row = BuildRow(mountID)
		if row then
			local key, label, rank
			if groupBy == "expansion" then
				-- Clamp classic-era / unknown ids to one "Classic" bucket so a
				-- stray -3 does not spawn a second Classic group.
				local exp = tonumber(row.expansion)
				exp = (exp and exp >= 0) and exp or (exp and 0) or nil
				key = "e:" .. tostring(exp or "x")
				label = row.expansion ~= nil and ExpansionLabel(exp) or "Other"
				rank = exp and -exp or 99 -- newest first, unknown last
			else
				key = "s:" .. row.source
				label = SOURCE_LABEL[row.source] or "Other"
				rank = SOURCE_RANK[row.source] or SOURCE_RANK.other
			end
			if isGlobal then
				key = "g:" .. key
			end

			local group = byKey[key]
			if not group then
				group = { key = key, label = label, rank = rank, rows = {}, isGlobal = isGlobal or nil }
				byKey[key] = group
				groups[#groups + 1] = group
			end
			group.rows[#group.rows + 1] = row
		end
	end

	for _, group in ipairs(groups) do
		FinishGroup(group)
	end

	table.sort(groups, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.label < b.label
	end)

	return groups
end

MountModel.GroupRows = GroupRows

-- ============================================================================
-- Account-wide counts (cheap, cached)
-- ============================================================================

local accountCache = { total = nil, collected = nil }

local function RefreshAccountCounts()
	if not (C_MountJournal and type(C_MountJournal.GetMountIDs) == "function") then
		accountCache.total, accountCache.collected = nil, nil
		return
	end
	local all = SafeApiCall(C_MountJournal.GetMountIDs)
	if type(all) ~= "table" then
		return
	end
	local total, collected = 0, 0
	for _, mountID in ipairs(all) do
		total = total + 1
		if select(11, addon.MountInfo(mountID)) then
			collected = collected + 1
		end
	end
	accountCache.total, accountCache.collected = total, collected
end

-- ============================================================================
-- Public: the grouped zone list
-- ============================================================================

local cache = {}

function MountModel.InvalidateCache()
	cache.key = nil
end

function MountModel.StatusFor(groups)
	if not addon.IsMountApiReady() then
		return "Loading mounts..."
	end
	if #groups == 0 then
		return "No collectable mounts tracked for this zone."
	end
	return nil
end

local function hiddenSourcesHash()
	local db = addon.db
	if not (db and db.hiddenSources) then
		return ""
	end
	local keys = {}
	for key, value in pairs(db.hiddenSources) do
		if value then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- Count total / collected / available across a flat candidate id list, for the
-- window summary line. Collected mounts are counted even when the list filters
-- them out.
local function ZoneTally(ids)
	local total, collected, available = 0, 0, 0
	for _, mountID in ipairs(ids) do
		local name, _, _, _, _, _, _, _, _, _, isCollected = addon.MountInfo(mountID)
		if type(name) == "string" and name ~= "" then
			total = total + 1
			if isCollected then
				collected = collected + 1
			else
				local verdict = Obtainability
					and Obtainability.Evaluate(mountID, { isCollected = false, source = Curated("source", mountID) })
				if verdict and verdict.state == "available" then
					available = available + 1
				end
			end
		end
	end
	return total, collected, available
end

-- Returns: groups, zoneName, mapID.
function MountModel.GetZoneMounts()
	local zoneName = addon.GetCurrentLocationName()
	local mapID = GetCurrentMapID()

	local db = addon.db or EMPTY
	local groupBy = db.groupBy or "source"
	local key = table.concat({
		tostring(mapID),
		groupBy,
		tostring(db.showCollected),
		tostring(db.showObtainableOnly),
		tostring(db.showGlobal),
		tostring(db.showUnusable),
		hiddenSourcesHash(),
	}, "|")

	if cache.key == key then
		return cache.groups, cache.zoneName, cache.mapID
	end

	local ids = CandidateSet(GetMapChain(mapID))
	local groups = GroupRows(ids, groupBy, false)

	local zoneTotal, zoneCollected, zoneAvailable = ZoneTally(ids)

	if db.showGlobal then
		local shown = {}
		for _, id in ipairs(ids) do
			shown[id] = true
		end
		local globalIDs = {}
		for _, id in ipairs(GlobalCandidateSet()) do
			if not shown[id] then
				globalIDs[#globalIDs + 1] = id
			end
		end
		for _, group in ipairs(GroupRows(globalIDs, groupBy, true)) do
			groups[#groups + 1] = group
		end
	end

	cache.key = key
	cache.groups = groups
	cache.zoneName = zoneName
	cache.mapID = mapID
	cache.summary = {
		zoneTotal = zoneTotal,
		zoneCollected = zoneCollected,
		zoneAvailable = zoneAvailable,
	}

	addon.DebugPrint(string.format(
		"%s = uiMapID %s | %d zone mounts, %d/%d collected in %d groups%s",
		zoneName or "?",
		tostring(mapID),
		zoneTotal,
		zoneCollected,
		zoneTotal,
		#groups,
		db.showGlobal and " (+global)" or ""
	))

	return groups, zoneName, mapID
end

-- Re-evaluate obtainability for the mounts already in the cached list, without a
-- full re-derivation. Backs NEW_MOUNT_ADDED / MOUNT_JOURNAL_USABILITY_CHANGED.
function MountModel.RefreshCachedStates()
	RefreshAccountCounts()

	if not cache.groups then
		return
	end
	for _, group in ipairs(cache.groups) do
		for _, row in ipairs(group.rows) do
			local fresh = BuildRow(row.id)
			if fresh then
				row.state = fresh.state
				row.detail = fresh.detail
				row.sortRank = fresh.sortRank
				row.isUsable = fresh.isUsable
				row.isCollected = fresh.isCollected
			end
		end
		FinishGroup(group)
	end
end

-- { zoneCollected, zoneTotal, zoneAvailable, accountCollected, accountTotal }
function MountModel.Summary()
	local summary = cache.summary or {}
	return {
		zoneCollected = summary.zoneCollected or 0,
		zoneTotal = summary.zoneTotal or 0,
		zoneAvailable = summary.zoneAvailable or 0,
		accountCollected = accountCache.collected,
		accountTotal = accountCache.total,
	}
end

-- Prime the account count during a quiet moment (a few seconds after login).
function MountModel.Warm()
	RefreshAccountCounts()
end

return MountModel
