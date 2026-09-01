local addonName, addon = ...

-- Localization layer. Every user-facing string resolves through addon.L (an
-- AceLocale-3.0 table); missing translations fall back to the English key.
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
addon.L = L

-- ============================================================================
-- Saved variables
-- ============================================================================

-- Only serializable, user-facing state lives here. Runtime/transient values
-- (readiness flags, resolved zone, pending timers) are module locals below.
local defaults = {
	version = 1,
	windowStyle = "stylized", -- "stylized" | "classic" (see Window.lua)
	groupBy = "source", -- "source" | "expansion" (see MountModel.lua)
	showCollected = false, -- include already-collected mounts in the list
	showObtainableOnly = false, -- only list mounts you could get right now
	showUnusable = true, -- true = dim mounts your class/faction can't use, false = hide them
	showGlobal = false, -- also list mounts with no home zone (class / racial / PvP / store)
	hiddenSources = {}, -- [sourceType] = true -- catalog-style "hide this whole source" filter
	showMapIcons = true,
	showMinimapIcons = true,
	showVendorIcons = true, -- also pin vendor-purchase mounts at their vendor's location
	showMinimapButton = true,
	debug = false,
	collapsed = {}, -- [groupKey] = true
	hidden = {}, -- [mountID] = true -- mounts the user never wants to see
	reopenWindow = true, -- reopen the tracker on login if it was open at logout
	windowOpen = false, -- persisted "was the window shown at logout" state
	window = nil, -- { point, relPoint, x, y, w, h } -- nil until the user moves/resizes
	minimapButton = nil, -- LibDBIcon position/hide state
}

local function ApplyDefaults(db, defs)
	for key, value in pairs(defs) do
		if type(value) == "table" then
			if type(db[key]) ~= "table" then
				db[key] = {}
			end
			ApplyDefaults(db[key], value)
		elseif db[key] == nil then
			db[key] = value
		end
	end
end

local function LoadSavedVariables()
	MountTrackerLocalZonesDB = MountTrackerLocalZonesDB or {}
	ApplyDefaults(MountTrackerLocalZonesDB, defaults)
	addon.db = MountTrackerLocalZonesDB
end

-- Single source of truth for per-setting defaults (the options panel reads these
-- so its "reset to default" matches what a fresh install gets).
addon.defaults = defaults

-- ============================================================================
-- Transient state
-- ============================================================================

local state = {
	lastZone = nil,
	retryScheduled = false,
}

-- ============================================================================
-- API helpers
-- ============================================================================

-- Call a WoW API defensively: bail if it is not a function or errors, and
-- return only its first result.
local function SafeApiCall(func, ...)
	if type(func) ~= "function" then
		return nil
	end

	local ok, result = pcall(func, ...)
	if not ok then
		return nil
	end

	return result
end

-- Forward a pcall's results only when it succeeded, preserving exact arity
-- (embedded nils and all -- no table pack/unpack round-trip).
local function ForwardIfOk(ok, ...)
	if ok then
		return ...
	end
end

-- Like SafeApiCall but preserves every return value.
local function SafeApiCallMulti(func, ...)
	if type(func) ~= "function" then
		return
	end

	return ForwardIfOk(pcall(func, ...))
end

addon.SafeApiCall = SafeApiCall
addon.SafeApiCallMulti = SafeApiCallMulti

-- ============================================================================
-- Output
-- ============================================================================

local function Print(message)
	print("|cff00ccff" .. addonName .. "|r: " .. tostring(message))
end

-- Only prints when the user has enabled /mtlz debug.
local function DebugPrint(message)
	if addon.db and addon.db.debug then
		Print(message)
	end
end

addon.Print = Print
addon.DebugPrint = DebugPrint

-- ============================================================================
-- Timing
-- ============================================================================

-- Wrap `fn` so that a burst of calls collapses into one deferred run. WoW fires
-- zone/mount events in bursts of 3-4; this keeps the work to once.
local function Debounced(delay, fn)
	local pending = false
	return function()
		if pending then
			return
		end
		pending = true
		C_Timer.After(delay, function()
			pending = false
			fn()
		end)
	end
end

-- ============================================================================
-- Curated data
-- ============================================================================

-- Overrides.lua wins over the generated MountData for the same [field][id].
-- Both tables load after Core, so the lookups resolve lazily at call time.
local function Curated(field, id)
	local ov = addon.MountOverrides and addon.MountOverrides[field]
	if ov and ov[id] ~= nil then
		return ov[id]
	end
	local md = addon.MountData and addon.MountData[field]
	return md and md[id]
end

addon.Curated = Curated

-- ============================================================================
-- Mount helpers (shared by the tracker window and the map pins)
-- ============================================================================

-- Blizzard icon textures carry a built-in border; crop it.
local function TrimIcon(texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

addon.TrimIcon = TrimIcon

-- ============================================================================
-- Mount API readiness
-- ============================================================================

local ScheduleMountRetry -- forward declaration

-- A non-empty GetMountIDs list means the Mount Journal data is loaded.
local function IsMountApiReady()
	if not (C_MountJournal and type(C_MountJournal.GetMountIDs) == "function") then
		return false
	end
	local ids = SafeApiCall(C_MountJournal.GetMountIDs)
	return type(ids) == "table" and #ids > 0
end

addon.IsMountApiReady = IsMountApiReady

function ScheduleMountRetry()
	if state.retryScheduled then
		return
	end

	state.retryScheduled = true
	C_Timer.After(2, function()
		state.retryScheduled = false
		addon.InitializeAddon()
	end)
end

addon.ScheduleMountRetry = ScheduleMountRetry

-- ============================================================================
-- Location
-- ============================================================================

local function NormalizeLocationValue(value)
	if value == nil or value == "" then
		return nil
	end
	return value
end

local function UpdateCurrentLocation()
	state.lastZone = NormalizeLocationValue(SafeApiCall(GetRealZoneText))
		or NormalizeLocationValue(SafeApiCall(GetZoneText))
		or L["Unknown"]
	return state.lastZone
end

-- Reads the cache filled by UpdateCurrentLocation (always called before anything
-- asks for the location), so no live API fallback is needed here.
local function GetCurrentLocationName()
	return state.lastZone or L["Unknown"]
end

addon.GetCurrentLocationName = GetCurrentLocationName

local function GetCurrentMapID()
	if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
		return SafeApiCall(C_Map.GetBestMapForUnit, "player")
	end
end

addon.GetCurrentMapID = GetCurrentMapID

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function InitializeAddon()
	UpdateCurrentLocation()

	if addon.db and addon.db.debug then
		DebugPrint(("Zone: %s (uiMapID %s)"):format(GetCurrentLocationName(), tostring(GetCurrentMapID())))
	end

	if addon.RefreshWindow then
		addon.RefreshWindow()
	end

	if addon.Map then
		addon.Map.Refresh()
	end

	if not IsMountApiReady() then
		ScheduleMountRetry()
	end
end

addon.InitializeAddon = InitializeAddon

-- Zone-change events arrive in bursts of 3-4 (plus PLAYER_ENTERING_WORLD).
-- Coalesce them into a single refresh so the per-zone scan runs at most once.
-- The location cache is updated eagerly (before the debounce) so anything that
-- reads the zone name in the meantime sees the current value.
local RunRefresh = Debounced(0.3, InitializeAddon)
local function RequestRefresh()
	UpdateCurrentLocation()
	RunRefresh()
end

-- MOUNT_JOURNAL_USABILITY_CHANGED changes mount *state* only, never which mounts
-- exist. Coalesce a burst into one cheap in-place refresh (no full re-derive).
local RequestStateRefresh = Debounced(0.5, function()
	if addon.MountModel then
		addon.MountModel.RefreshCachedStates()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end)

-- NEW_MOUNT_ADDED changes list *membership* (a mount became collected, and with
-- "Show collected" off its row must leave). An in-place refresh can't drop rows,
-- so take the full-rebuild path -- same as a zone change -- behind its own
-- debounce.
local RequestMembershipRefresh = Debounced(0.5, function()
	if addon.MountModel then
		addon.MountModel.RefreshAccountCounts()
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end)

-- Collecting a mount can change which zones still have work; the full per-zone
-- recount is heavier, so keep it on NEW_MOUNT_ADDED only.
local RequestMapRefresh = Debounced(1, function()
	if addon.Map then
		addon.Map.Rebuild()
	end
end)

-- ============================================================================
-- Slash command
-- ============================================================================

local function ClearSlashInput()
	local chatFrame = DEFAULT_CHAT_FRAME
	if chatFrame and chatFrame.editBox then
		chatFrame.editBox:SetText("")
		chatFrame.editBox:ClearFocus()
	end
end

local function HandleSlashCommand(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")

	if msg == "reset" then
		wipe(addon.db.collapsed)
		addon.db.window = nil
		UpdateCurrentLocation()
		if addon.ResetWindow then
			addon.ResetWindow()
		end
		Print(L["Window and section state reset."])
	elseif msg == "list" then
		if addon.PrintZoneList then
			addon.PrintZoneList()
		end
	elseif msg == "config" then
		if addon.OpenConfig then
			addon.OpenConfig()
		else
			Print(L["Options are not available yet."])
		end
	elseif msg == "debug" then
		addon.db.debug = not addon.db.debug
		Print(addon.db.debug and L["Debug output enabled."] or L["Debug output disabled."])
	elseif msg == "map" then
		if addon.Map then
			addon.Map.Rebuild() -- pin count prints only when /mtlz debug is on
		end
	elseif msg == "" or msg == "show" or msg == "toggle" then
		if addon.ToggleWindow then
			addon.ToggleWindow()
		end
	else
		Print(L["Commands: /mtlz [show | list | config | map | debug | reset]"])
	end

	ClearSlashInput()
end

SLASH_MTLZ1 = "/mtlz"
SlashCmdList["MTLZ"] = HandleSlashCommand

-- ============================================================================
-- Events
-- ============================================================================

local zoneEvents = {
	ZONE_CHANGED = true,
	ZONE_CHANGED_INDOORS = true,
	ZONE_CHANGED_NEW_AREA = true,
}

local mountEvents = {
	NEW_MOUNT_ADDED = true,
	MOUNT_JOURNAL_USABILITY_CHANGED = true,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
for eventName in pairs(zoneEvents) do
	frame:RegisterEvent(eventName)
end
for eventName in pairs(mountEvents) do
	frame:RegisterEvent(eventName)
end

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			LoadSavedVariables()
		end
		return
	end

	if event == "PLAYER_LOGIN" then
		if addon.InitializeWindow then
			addon.InitializeWindow()
		end
		if addon.SetupConfig then
			addon.SetupConfig()
		end
		if addon.SetupMinimapButton then
			addon.SetupMinimapButton()
		end
		InitializeAddon()
		-- Convenience: bring the tracker back if it was open when the player last
		-- logged out. The window is built hidden, so a toggle just shows it.
		if
			addon.db.reopenWindow
			and addon.db.windowOpen
			and addon.ToggleWindow
			and not (addon.IsWindowShown and addon.IsWindowShown())
		then
			addon.ToggleWindow()
		end
		-- Build the model cache while things are quiet, so the first window open
		-- doesn't pay for it, then place the world-map pins.
		C_Timer.After(5, function()
			if addon.MountModel then
				addon.MountModel.Warm()
			end
			if addon.Map then
				addon.Map.Refresh()
			end
		end)
		return
	end

	if event == "PLAYER_LOGOUT" then
		-- Fires on both logout and /reload, before saved variables are written.
		if addon.db and addon.IsWindowShown then
			addon.db.windowOpen = addon.IsWindowShown()
		end
		return
	end

	if mountEvents[event] then
		if event == "NEW_MOUNT_ADDED" then
			RequestMembershipRefresh()
			RequestMapRefresh()
		else
			RequestStateRefresh()
		end
		return
	end

	-- Zone changes: coalesced full refresh. If mount data is still settling,
	-- InitializeAddon schedules its own retry.
	RequestRefresh()
end)
