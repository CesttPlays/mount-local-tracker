-- luacheck config for this WoW addon
-- Run:  luacheck .

std = "lua51"
max_line_length = false
codes = true

-- Vendored libraries: not our code, don't lint.
-- tests/: the headless harness deliberately monkey-patches the global
-- environment to fake the WoW client; addon lint rules are just noise there.
-- It is exercised on every run, so a typo in it fails loudly anyway.
exclude_files = { "Mount_Tracker_Local_Zones/Libs/", "tests/", ".claude/" }

-- The addon receives (addonName, addon) as vararg; TOC-loaded files share the table.
files["**/*.lua"] = {
    -- Globals the addon intentionally defines for the WoW client to pick up.
    globals = {
        "SLASH_MTLZ1",
        "SlashCmdList",
        "MountTrackerWindow",
        "MountTrackerLocalZonesDB",
    },
}

-- WoW client APIs and constants used by the addon. Read-only: linting flags
-- assignment to these, which usually means a typo or an accidental global.
read_globals = {
    -- Core
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "C_Timer", "wipe", "bit", "Settings",
    "GetTime", "C_AddOns",
    -- Zone / location / map
    "GetRealZoneText", "GetZoneText", "GetSubZoneText", "C_Map", "UnitFactionGroup",
    -- Mount journal
    "C_MountJournal", "ToggleCollectionsJournal", "MountJournal_SelectByMountID",
    -- Spells / tooltip / combat
    "C_Spell", "GameTooltip", "InCombatLockdown",
    -- Obtainability inputs (rep / renown / currency / gold / lockout / achievement)
    "C_Reputation", "C_MajorFactions", "C_CurrencyInfo", "C_QuestLog", "GetMoney",
    "GetAchievementInfo",
    -- Mount row / map-pin interactions (chat link, context menu, waypoints)
    "IsModifiedClick", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
    "MenuUtil", "C_SuperTrack", "UiMapPoint", "TomTom",
    -- Map pins (HereBeDragons)
    "LibStub", "HBD_PINS_WORLDMAP_SHOW_PARENT",
    -- ScrollBox list (Blizzard, Dragonflight+)
    "CreateScrollBoxListLinearView", "ScrollUtil", "CreateDataProvider", "ScrollBoxConstants",
    -- Settings panel (Blizzard)
    "CreateSettingsListSectionHeaderInitializer",
}
