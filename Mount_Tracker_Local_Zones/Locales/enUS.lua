-- SOURCE OF TRUTH for every translatable string in the addon. Keys are the
-- English text; `= true` tells AceLocale to use the key as the value.
--
-- This file is pushed verbatim to CurseForge Localization by
-- tools/push_locale_phrases.py. Translations come back into the sibling
-- Locales/<code>.lua files via .github/workflows/refresh-locales.yml.
--
-- Adding a string: add the line here AND wrap the call site in L["..."].
-- Keep the section order below stable so translation diffs stay readable.

local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true, true) -- isDefault, silent
if not L then return end

-- Shared / fallbacks
L["Mount Tracker"] = true
L["Mount Tracker: Local Zones"] = true
L["Mount %d"] = true
L["Unknown"] = true
L["Other"] = true
L["Global"] = true
L["collected"] = true

-- Chat / slash (Core.lua)
L["Window and section state reset."] = true
L["Options are not available yet."] = true
L["Debug output enabled."] = true
L["Debug output disabled."] = true
L["Commands: /mtlz [show | list | config | map | debug | reset]"] = true

-- Mount Journal / actions (MountActions.lua)
L["Can't open the Mount Journal during combat."] = true
L["Can't place a map pin for that mount here."] = true
L["Place map pin"] = true
L["Place map pin (vendor)"] = true
L["Set TomTom waypoint"] = true
L["Set TomTom waypoint (vendor)"] = true
L["Summon"] = true
L["Hide this mount"] = true

-- Tracker window (Window.lua)
L["Reload your UI (/reload) to apply the new window style."] = true
L["Mounts: %s"] = true
L["Mounts for %s:"] = true
L["Every mount here is already collected."] = true
L["%s \226\128\148 %d / %d collected"] = true
L["%d available"] = true
L["%d / %d account"] = true

-- Zone model status (MountModel.lua)
L["Loading mounts..."] = true
L["No collectable mounts tracked for this zone."] = true

-- Source-type group labels (MountModel.lua SOURCE_LABEL)
L["Dungeon & Raid"] = true
L["Rare Drop"] = true
L["Vendor"] = true
L["Quest"] = true
L["Zone Drop"] = true
L["World Event"] = true
L["Profession"] = true

-- Expansion group labels (MountModel.lua EXPANSION_LABEL). "Classic" doubles as
-- the window-style label below -- one entry covers both, intentionally.
L["Classic"] = true
L["The Burning Crusade"] = true
L["Wrath of the Lich King"] = true
L["Cataclysm"] = true
L["Mists of Pandaria"] = true
L["Warlords of Draenor"] = true
L["Legion"] = true
L["Battle for Azeroth"] = true
L["Shadowlands"] = true
L["Dragonflight"] = true
L["The War Within"] = true
L["Midnight"] = true

-- Obtainability detail text (Obtainability.lua)
L["Renown %d"] = true
L["%s / need %s"] = true
L["%s / %s reputation"] = true
L["available from a vendor"] = true
L["vendor"] = true
L["currency"] = true
L["%s |cffffffff(%s)|r"] = true
L["achievement reward"] = true
L["%s \194\183 done this reset"] = true

-- Obtainability tooltip headers (Obtainability.lua)
L["Available now"] = true
L["Farmable now"] = true
L["Reputation needed"] = true
L["Achievement needed"] = true
L["Quest needed"] = true
L["Locked this reset"] = true
L["Not yet collected"] = true
L["Dungeon drop"] = true
L["Raid drop"] = true
L["Rare drop"] = true

-- Options: sections
L["Window"] = true
L["Mount list"] = true
L["Filter by source"] = true
L["Map & minimap"] = true

-- Options: window style
L["Window style"] = true
L["Classic uses the Blizzard dialog frame and scrollbar. Stylized uses a flat dark panel with minimal controls. Reload your UI (/reload) after changing this."] = true
L["Stylized"] = true

-- Options: group-by
L["Group by"] = true
L["How the tracked mounts are grouped in the list."] = true
L["By source type"] = true
L["By expansion"] = true

-- Options: checkboxes + tooltips
L["Reopen on login"] = true
L["Reopen the tracker window when you log in if it was open when you logged out."] = true
L["Show collected mounts"] = true
L["Include mounts you already own. They appear greyed out in the list."] = true
L["Only show obtainable mounts"] = true
L["Hide mounts you can't get right now (reputation locked, weekly farm already done, achievement incomplete)."] = true
L["Show unusable mounts"] = true
L["Include mounts your class or faction can't use. They appear dimmed. Turn off to hide them."] = true
L["Show global mounts"] = true
L['Also list mounts with no home zone (class, racial, PvP, store, promotion), under a "Global" divider. Their sections start collapsed.'] = true
L["Show minimap button"] = true
L["A button on the minimap that toggles the tracker (right-click for options)."] = true
L["Show world map icons"] = true
L["An icon on the world map for each uncollected mount that has a known location."] = true
L["Show minimap icons"] = true
L["An icon on the minimap for each nearby uncollected mount that has a known location."] = true
L["Show vendor icons"] = true
L["Also mark the vendor on the map for mounts you can buy."] = true

-- Options: "Filter by source" rows
L["Show %s"] = true
L["Show %s mounts in the tracker list."] = true

-- Options: "Hidden mounts" sub-panel
L["Hidden mounts"] = true
L["Mounts you have hidden (right-click a mount -> Hide this mount). Hidden mounts stay out of the tracker list and off the map."] = true
L["Restore"] = true
L["Restore all"] = true
L["Restore section"] = true
L["No hidden mounts."] = true

-- Options: panel unavailable (Config.lua)
L["Options panel is unavailable."] = true

-- Minimap button tooltip (MinimapButton.lua)
L["Left-click to toggle the tracker"] = true
L["Right-click for options"] = true
