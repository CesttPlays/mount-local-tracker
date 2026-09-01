local _, addon = ...
local L = addon.L

-- ============================================================================
-- Mount actions (shared by the tracker window and the map pins)
-- ============================================================================
--
-- The mount-interaction layer: journal lookups, opening the Mount Journal,
-- placing waypoints, the right-click context menu, and binding a frame to a
-- mount. Moved verbatim out of Core.lua; everything it needs is already on
-- `addon` (Curated, SafeApiCall*, Print, Obtainability, MountModel, Map,
-- RefreshWindow).

local SafeApiCall = addon.SafeApiCall
local SafeApiCallMulti = addon.SafeApiCallMulti
local Print = addon.Print

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
	return L["Mount %d"]:format(mountID)
end

-- Open Blizzard's Mount Journal to a specific mount.
local function OpenMount(mountID)
	if InCombatLockdown() then
		Print(L["Can't open the Mount Journal during combat."])
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
		Print(L["Can't place a map pin for that mount here."])
	end
end

-- Hand a MountData point to TomTom as a "crazy arrow" waypoint. Caller checks
-- that TomTom is loaded before offering this. `title` overrides the default
-- (the mount name) -- the vendor actions pass "<mount> - <npc>".
local function SetTomTomWaypoint(point, mountID, title)
	if type(TomTom) ~= "table" or type(TomTom.AddWaypoint) ~= "function" then
		return
	end
	TomTom:AddWaypoint(point[1], point[2] / 10000, point[3] / 10000, {
		title = title or MountName(mountID),
		from = L["Mount Tracker"],
		crazy = true,
	})
end

-- The curated vendor entry's map location as a { uiMapID, x, y } triple (x/y on
-- the same 0-10000 scale as MountData.points) plus the NPC name, when the entry
-- carries coordinates. Vendor-purchase mounts have no spawn point of their own,
-- so this is what the "... (vendor)" waypoint actions and the opt-in vendor map
-- pins aim at. Returns nil when there is no vendor entry or it has no position.
local function VendorLocation(mountID)
	local vendor = addon.Curated("vendor", mountID)
	if type(vendor) ~= "table" then
		return nil
	end
	local uiMapID, x, y = vendor.uiMapID, vendor.x, vendor.y
	if type(uiMapID) == "number" and type(x) == "number" and type(y) == "number" then
		return { uiMapID, x, y }, vendor.npc
	end
	return nil
end

addon.VendorLocation = VendorLocation

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

	local point = addon.Curated("points", mountID)
	local vendorPoint, vendorNPC = VendorLocation(mountID)
	local isCollected = select(11, MountInfo(mountID))

	local hasTomTom = type(C_AddOns) == "table"
		and type(C_AddOns.IsAddOnLoaded) == "function"
		and C_AddOns.IsAddOnLoaded("TomTom")

	MenuUtil.CreateContextMenu(frame, function(_, rootDescription)
		rootDescription:CreateTitle(MountName(mountID))

		-- A datamined spawn point wins; otherwise fall back to the vendor's
		-- location so vendor-purchase mounts still get a waypoint.
		if point then
			rootDescription:CreateButton(L["Place map pin"], function()
				PlaceUserWaypoint(point)
			end)
			if hasTomTom then
				rootDescription:CreateButton(L["Set TomTom waypoint"], function()
					SetTomTomWaypoint(point, mountID)
				end)
			end
		elseif vendorPoint then
			rootDescription:CreateButton(L["Place map pin (vendor)"], function()
				PlaceUserWaypoint(vendorPoint)
			end)
			if hasTomTom then
				rootDescription:CreateButton(L["Set TomTom waypoint (vendor)"], function()
					local title = vendorNPC
						and ("%s \194\183 %s"):format(MountName(mountID), vendorNPC)
						or MountName(mountID)
					SetTomTomWaypoint(vendorPoint, mountID, title)
				end)
			end
		end
		if
			isCollected
			and C_MountJournal
			and type(C_MountJournal.SummonByID) == "function"
		then
			rootDescription:CreateButton(L["Summon"], function()
				C_MountJournal.SummonByID(mountID)
			end)
		end
		rootDescription:CreateButton(L["Hide this mount"], function()
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
