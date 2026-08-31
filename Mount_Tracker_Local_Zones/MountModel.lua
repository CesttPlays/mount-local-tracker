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

-- The db fields that change which rows GetZoneMounts produces. The cache key is
-- derived from exactly this list (plus the hiddenSources / hidden hashes), and
-- Config.lua drives cache invalidation off the same list -- so covering a new
-- filter means editing one list, not two hand-kept call sites. Every entry here
-- must be a db field BuildRow / row.include (or the group/global split) reads.
local CACHE_KEYS = {
	"groupBy",
	"showCollected",
	"showObtainableOnly",
	"showGlobal",
	"showUnusable",
	"showVendorIcons",
}
MountModel.CACHE_KEYS = CACHE_KEYS

-- ============================================================================
-- Source-type groups (groupBy == "source")
-- ============================================================================

-- display order + label. A mount whose source is missing / unknown falls to "other".
-- This is the ONE canonical source-type list; Config.lua iterates the exported copy
-- so its filter checkboxes always match the list's group headers.
local SOURCE_ORDER = { "instance", "drop", "vendor", "quest", "zonedrop", "worldevent", "profession", "other" }
MountModel.SOURCE_ORDER = SOURCE_ORDER
local SOURCE_LABEL = {
	instance = "Dungeon & Raid",
	drop = "Rare Drop",
	vendor = "Vendor",
	quest = "Quest",
	zonedrop = "Zone Drop",
	worldevent = "World Event",
	profession = "Profession",
	other = "Other",
}
local SOURCE_RANK = {}
for index, key in ipairs(SOURCE_ORDER) do
	SOURCE_RANK[key] = index
end

-- Label for a source-type string; unknown / nil -> "Other".
function MountModel.SourceLabel(s)
	return SOURCE_LABEL[s] or "Other"
end

-- Grouping bucket for a source-type string (groupBy == "source").
-- Returns key, label, rank. nil / unknown source -> the "other" bucket.
local function SourceBucket(source)
	local s = source or "other"
	return "s:" .. s, SOURCE_LABEL[s] or "Other", SOURCE_RANK[s] or SOURCE_RANK.other
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

-- Grouping bucket for an expansion id (groupBy == "expansion").
-- Returns key, label, rank. Classic-era / negative ids clamp to one "Classic"
-- bucket; non-numeric / nil ids fall to the "Other" bucket, sorted last.
local function ExpansionBucket(raw)
	local n = tonumber(raw)
	if not n then
		return "e:x", "Other", 99
	end
	if n < 0 then
		n = 0
	end
	return "e:" .. n, EXPANSION_LABEL[n] or "Other", -n
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

-- Always returns a row for a real mount id; nil only when the id isn't a real /
-- not-yet-loaded mount. row.include is the boolean "list this row" verdict --
-- callers that only want the listed rows check it, while the zone summary folds
-- over every row so collected / hidden mounts still count toward the zone totals.
-- row = { id, name, spellID, icon, isUsable, isCollected, source, subcat,
--         expansion, state, detail, sortRank, point, include }
local function BuildRow(mountID)
	local name, spellID, icon, _, isUsable, _, _, _, _, _, isCollected =
		addon.MountInfo(mountID)

	if type(name) ~= "string" or name == "" then
		return nil -- not a real / not-yet-loaded mount id
	end

	local db = addon.db or EMPTY
	local source = Curated("source", mountID) or "other"

	-- Faction-specific mounts: the other faction's version is filtered from the
	-- list (but still counted in the zone total).
	local factionOK = true
	local requiredFaction = Curated("faction", mountID)
	if requiredFaction ~= nil then
		local playerFaction = PlayerFactionIndex()
		if playerFaction ~= nil and playerFaction ~= requiredFaction then
			factionOK = false
		end
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

	-- Count everything; list only what passes every active filter.
	row.include = (db.showCollected or not row.isCollected)
		and not (db.hidden and db.hidden[mountID])
		and not (db.hiddenSources and db.hiddenSources[source])
		and (db.showUnusable or row.isUsable)
		and (row.isCollected or not db.showObtainableOnly or OBTAINABLE[row.state])
		and factionOK or false

	return row
end

MountModel.BuildRow = BuildRow

-- Build a row for every id in a candidate list, dropping ids that aren't real
-- mounts. Feeds both GroupRows (which lists the row.include rows) and the zone
-- summary fold (which counts them all).
local function BuildRows(ids)
	local rows = {}
	for _, mountID in ipairs(ids) do
		local row = BuildRow(mountID)
		if row then
			rows[#rows + 1] = row
		end
	end
	return rows
end

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

-- Pre-built rows -> array of
-- { key, label, icon, rows, total, collected, available, isGlobal }.
-- Rows with include == false are skipped here (the zone summary still counts them).
local function GroupRows(rows, groupBy, isGlobal)
	local groups, byKey = {}, {}

	for _, row in ipairs(rows) do
		if row.include then
			local key, label, rank
			if groupBy == "expansion" then
				key, label, rank = ExpansionBucket(row.expansion)
			else
				key, label, rank = SourceBucket(row.source)
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

-- Sorted concat of the hidden mount ids (db.hidden). Same shape as
-- hiddenSourcesHash: folding it into the cache key means hiding / restoring a
-- mount changes the key on its own, no separate InvalidateCache() call needed.
local function hiddenHash()
	local db = addon.db
	if not (db and db.hidden) then
		return ""
	end
	local keys = {}
	for id, value in pairs(db.hidden) do
		if value then
			keys[#keys + 1] = id
		end
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

-- The GetZoneMounts cache key: mapID + every CACHE_KEYS db field + the two
-- hidden-set hashes. Covers exactly what BuildRow / row.include and the
-- group/global split depend on.
local function cacheKey(mapID)
	local db = addon.db or EMPTY
	local parts = { tostring(mapID) }
	for _, k in ipairs(CACHE_KEYS) do
		parts[#parts + 1] = tostring(db[k])
	end
	parts[#parts + 1] = hiddenSourcesHash()
	parts[#parts + 1] = hiddenHash()
	return table.concat(parts, "|")
end

-- Returns: groups, zoneName, mapID.
function MountModel.GetZoneMounts()
	local zoneName = addon.GetCurrentLocationName()
	local mapID = GetCurrentMapID()

	local db = addon.db or EMPTY
	local groupBy = db.groupBy or "source"
	local key = cacheKey(mapID)

	if cache.key == key then
		return cache.groups, cache.zoneName, cache.mapID
	end

	local ids = CandidateSet(GetMapChain(mapID))
	local rows = BuildRows(ids)
	local groups = GroupRows(rows, groupBy, false)

	-- Zone summary: fold over every real row, filters or not. Collected / hidden /
	-- filtered mounts still count toward the zone totals.
	local zoneTotal, zoneCollected, zoneAvailable = 0, 0, 0
	for _, row in ipairs(rows) do
		zoneTotal = zoneTotal + 1
		if row.isCollected then
			zoneCollected = zoneCollected + 1
		elseif row.state == "available" then
			zoneAvailable = zoneAvailable + 1
		end
	end

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
		for _, group in ipairs(GroupRows(BuildRows(globalIDs), groupBy, true)) do
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

-- In-place refresh of obtainability for the rows already in the cached list;
-- never adds or removes rows. Only valid when the candidate set is unchanged
-- (MOUNT_JOURNAL_USABILITY_CHANGED). If a cached row's membership actually
-- changed -- BuildRow now returns nil or a row with include == false -- we can't
-- fix that in place, so drop the cache and let the next GetZoneMounts rebuild
-- rather than leave a stale row on screen.
function MountModel.RefreshCachedStates()
	RefreshAccountCounts()

	if not cache.groups then
		return
	end
	for _, group in ipairs(cache.groups) do
		for _, row in ipairs(group.rows) do
			local fresh = BuildRow(row.id)
			if not fresh or not fresh.include then
				MountModel.InvalidateCache()
				return
			end
			row.state = fresh.state
			row.detail = fresh.detail
			row.sortRank = fresh.sortRank
			row.isUsable = fresh.isUsable
			row.isCollected = fresh.isCollected
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
