local addonName, addon = ...
local L = addon.L

-- Minimap launcher button (LibDataBroker + LibDBIcon).

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local dataObject
if LDB then
	dataObject = LDB:NewDataObject(addonName, {
		type = "launcher",
		text = L["Mount Tracker"],
		icon = "Interface\\ICONS\\Ability_Mount_RidingHorse",
		OnClick = function(_, button)
			if button == "RightButton" then
				if addon.OpenConfig then
					addon.OpenConfig()
				end
			elseif addon.ToggleWindow then
				addon.ToggleWindow()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(L["Mount Tracker: Local Zones"])
			tooltip:AddLine(L["Left-click to toggle the tracker"], 1, 1, 1)
			tooltip:AddLine(L["Right-click for options"], 1, 1, 1)
		end,
	})
end

function addon.SetupMinimapButton()
	if not (LDBIcon and dataObject) then
		return
	end

	addon.db.minimapButton = addon.db.minimapButton or {}
	addon.db.minimapButton.hide = not addon.db.showMinimapButton

	if not LDBIcon:IsRegistered(addonName) then
		LDBIcon:Register(addonName, dataObject, addon.db.minimapButton)
	end
end

-- Called from the options panel when the "Show minimap button" checkbox changes.
function addon.ApplyMinimapButton()
	if not (LDBIcon and LDBIcon:IsRegistered(addonName)) then
		return
	end
	if addon.db.showMinimapButton then
		LDBIcon:Show(addonName)
	else
		LDBIcon:Hide(addonName)
	end
end
