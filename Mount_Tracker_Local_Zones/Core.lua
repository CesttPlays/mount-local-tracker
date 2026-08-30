local addonName, addon = ...

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
-- Mount helpers (shared by the tracker window and the map pins)
-- ============================================================================

-- Blizzard icon textures carry a built-in border; crop it.
local function TrimIcon(texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

addon.TrimIcon = TrimIcon

-- C_MountJournal.GetMountInfoByID returns, in order:
--   name, spellID, icon, isActive, isUsable, sourceType, isFavorite,
--   isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID
local function MountInfo(mountID)
	if not (C_MountJournal and type(C_MountJournal.GetMountInfoByID) == "function") then
		return
	end
	return SafeApiCallMulti(C_MountJournal.GetMountInfoByID, mountID)
end

addon.MountInfo = MountInfo

-- The mount's name, or a bland fallback. Used for menu titles / waypoints.
local function MountName(mountID)
	local name = MountInfo(mountID)
	if type(name) == "string" and name ~= "" then
		return name
	end
	return "Mount " .. tostring(mountID)
end

-- Open Blizzard's Mount Journal to a specific mount.
local function OpenMount(mountID)
	if InCombatLockdown() then
		Print("Can't open the Mount Journal during combat.")
		return
	end

	if type(ToggleCollectionsJournal) == "function" then
		ToggleCollectionsJournal(1) -- 1 = Mounts tab
	end
	if type(MountJournal_SelectByMountID) == "function" then
		MountJournal_SelectByMountID(mountID)
	end
end

addon.OpenMount = OpenMount

-- Append the obtainability block (rep progress, vendor cost, lockout status,
-- drop-chance / tip) to GameTooltip. No-op until Obtainability.lua lands.
local function AddObtainabilityLines(mountID)
	if addon.Obtainability and type(addon.Obtainability.AddTooltipLines) == "function" then
		addon.Obtainability.AddTooltipLines(GameTooltip, mountID)
	end
end

-- Add or remove a mount from the "never show" list, then refresh every surface
-- that reads it. The zone list is cached by zone/map, which hiding does not
-- change, so the cache has to be invalidated explicitly.
local function SetMountHidden(mountID, hidden)
	if not (addon.db and addon.db.hidden) then
		return
	end
	addon.db.hidden[mountID] = hidden and true or nil
	if addon.MountModel then
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
	if addon.Map then
		addon.Map.Rebuild()
	end
end

addon.SetMountHidden = SetMountHidden

-- Drop a native map pin (the shift-click-the-map waypoint) at a MountData point
-- { uiMapID, x*10000, y*10000 } and super-track it so the on-screen arrow shows.
local function PlaceUserWaypoint(point)
	local uiMapID, x, y = point[1], point[2] / 10000, point[3] / 10000
	if
		type(C_Map) == "table"
		and type(C_Map.CanSetUserWaypointOnMap) == "function"
		and SafeApiCall(C_Map.CanSetUserWaypointOnMap, uiMapID)
		and type(UiMapPoint) == "table"
		and type(UiMapPoint.CreateFromCoordinates) == "function"
	then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x, y))
		if type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	else
		Print("Can't place a map pin for that mount here.")
	end
end

-- Hand a MountData point to TomTom as a "crazy arrow" waypoint. Caller checks
-- that TomTom is loaded before offering this.
local function SetTomTomWaypoint(point, mountID)
	if type(TomTom) ~= "table" or type(TomTom.AddWaypoint) ~= "function" then
		return
	end
	TomTom:AddWaypoint(point[1], point[2] / 10000, point[3] / 10000, {
		title = MountName(mountID),
		from = "Mount Tracker",
		crazy = true,
	})
end

-- Right-click context menu for a mount row / map pin. Location actions only
-- appear when we have coordinates for that mount.
local function ShowMountMenu(frame)
	local mountID = frame.mountID
	if
		not mountID
		or type(MenuUtil) ~= "table"
		or type(MenuUtil.CreateContextMenu) ~= "function"
	then
		return
	end

	local point = (addon.MountOverrides and addon.MountOverrides.points and addon.MountOverrides.points[mountID])
		or (addon.MountData and addon.MountData.points and addon.MountData.points[mountID])
	local isCollected = select(11, MountInfo(mountID))

	MenuUtil.CreateContextMenu(frame, function(_, rootDescription)
		rootDescription:CreateTitle(MountName(mountID))
		if point then
			rootDescription:CreateButton("Place map pin", function()
				PlaceUserWaypoint(point)
			end)
			if
				type(C_AddOns) == "table"
				and type(C_AddOns.IsAddOnLoaded) == "function"
				and C_AddOns.IsAddOnLoaded("TomTom")
			then
				rootDescription:CreateButton("Set TomTom waypoint", function()
					SetTomTomWaypoint(point, mountID)
				end)
			end
		end
		if
			isCollected
			and C_MountJournal
			and type(C_MountJournal.SummonByID) == "function"
		then
			rootDescription:CreateButton("Summon", function()
				C_MountJournal.SummonByID(mountID)
			end)
		end
		rootDescription:CreateButton("Hide this mount", function()
			SetMountHidden(mountID, true)
		end)
	end)
end

-- Give a Button the standard mount behaviour: hover tooltip, left-click to open
-- the Mount Journal to the mount, shift-left-click to link its spell in chat,
-- and a right-click context menu. The frame supplies the ids live via
-- self.mountID / self.spellID, so a pooled frame is re-bound by reassigning
-- those fields.
local function BindMount(frame)
	frame:SetScript("OnEnter", function(self)
		if not self.mountID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local shown = false
		if self.spellID and type(GameTooltip.SetMountBySpellID) == "function" then
			shown = pcall(GameTooltip.SetMountBySpellID, GameTooltip, self.spellID)
		end
		if not shown then
			GameTooltip:AddLine(MountName(self.mountID))
		end
		AddObtainabilityLines(self.mountID)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	if type(frame.RegisterForClicks) == "function" then
		frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end
	frame:SetScript("OnClick", function(self, button)
		if not self.mountID then
			return
		end
		if button == "RightButton" then
			ShowMountMenu(self)
			return
		end
		if type(IsModifiedClick) == "function" and IsModifiedClick("CHATLINK") then
			local link
			if self.spellID and C_Spell and type(C_Spell.GetSpellLink) == "function" then
				link = SafeApiCall(C_Spell.GetSpellLink, self.spellID)
			end
			if link then
				if not (type(ChatEdit_InsertLink) == "function" and ChatEdit_InsertLink(link)) then
					if type(ChatFrame_OpenChat) == "function" then
						ChatFrame_OpenChat(link)
					end
				end
			end
			return
		end
		OpenMount(self.mountID)
	end)
end

addon.BindMount = BindMount

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
		or "Unknown"
	return state.lastZone
end

-- Reads the cache filled by UpdateCurrentLocation (always called before anything
-- asks for the location), so no live API fallback is needed here.
local function GetCurrentLocationName()
	return state.lastZone or "Unknown"
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

-- NEW_MOUNT_ADDED / MOUNT_JOURNAL_USABILITY_CHANGED change mount *state*, never
-- zone membership. Coalesce a burst into one cheap state-only refresh.
local RequestStateRefresh = Debounced(0.5, function()
	if addon.MountModel then
		addon.MountModel.RefreshCachedStates()
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
		Print("Window and section state reset.")
	elseif msg == "list" then
		if addon.PrintZoneList then
			addon.PrintZoneList()
		end
	elseif msg == "config" then
		if addon.OpenConfig then
			addon.OpenConfig()
		else
			Print("Options are not available yet.")
		end
	elseif msg == "debug" then
		addon.db.debug = not addon.db.debug
		Print("Debug output " .. (addon.db.debug and "enabled" or "disabled") .. ".")
	elseif msg == "map" then
		if addon.Map then
			addon.Map.Rebuild() -- pin count prints only when /mtlz debug is on
		end
	elseif msg == "" or msg == "show" or msg == "toggle" then
		if addon.ToggleWindow then
			addon.ToggleWindow()
		end
	else
		Print("Commands: /mtlz [show | list | config | map | debug | reset]")
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
		RequestStateRefresh()
		if event == "NEW_MOUNT_ADDED" then
			RequestMapRefresh()
		end
		return
	end

	-- Zone changes: coalesced full refresh. If mount data is still settling,
	-- InitializeAddon schedules its own retry.
	RequestRefresh()
end)
