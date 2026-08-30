-- The smoke sequence: load the addon, drive its whole lifecycle and every slash
-- command, and assert that nothing throws and the basic wiring is in place.
-- Returns { ok = bool, checks = { {name, ok, detail}, ... } }.

local Stub = _G.WowStub
local Harness = _G.Harness
local SCENARIO = _G.SCENARIO or "cold"

local checks = {}
local function record(name, ok, detail)
    checks[#checks + 1] = { name = name, ok = ok and true or false, detail = detail }
    return ok
end

-- Run fn; a thrown error is a failed check, not a crash of the runner.
local function step(name, fn)
    local ok, err = pcall(fn)
    record(name, ok, ok and nil or tostring(err))
end

local function check(name, cond, detail)
    record(name, cond, cond and nil or (detail or "expected truthy"))
end

local addon = Harness.addon

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
step("load all addon files in TOC order", function()
    Harness.load()
end)
check("files were loaded", Harness.loaded and #Harness.loaded > 0, "TOC produced no files")

-- Apply the warm scenario's Overrides seed now that addon.MountOverrides exists.
if SCENARIO == "warm" and Stub.data.overrides and addon.MountOverrides then
    for field, entries in pairs(Stub.data.overrides) do
        addon.MountOverrides[field] = addon.MountOverrides[field] or {}
        for id, value in pairs(entries) do
            addon.MountOverrides[field][id] = value
        end
    end
end

for _, key in ipairs({
    "SafeApiCall", "Print", "IsMountApiReady", "GetCurrentLocationName",
    "InitializeAddon", "MountModel", "Obtainability", "ListView", "Map",
    "MountData", "MountOverrides", "MountInfo", "BindMount",
    "InitializeWindow", "ToggleWindow", "RefreshWindow", "PrintZoneList",
    "IsWindowShown", "ResetWindow", "defaults",
    "SetupConfig", "OpenConfig", "SetupMinimapButton", "ApplyMinimapButton",
}) do
    check("addon." .. key .. " is defined", addon[key] ~= nil)
end

check("/mtlz slash handler registered",
    type(_G.SlashCmdList) == "table" and type(_G.SlashCmdList.MTLZ) == "function")
check("SLASH_MTLZ1 set", _G.SLASH_MTLZ1 == "/mtlz")

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
step("login lifecycle (ADDON_LOADED / PLAYER_LOGIN / PLAYER_ENTERING_WORLD)", function()
    Harness.login()
end)

check("saved variables loaded (addon.db)", type(addon.db) == "table")
check("defaults merged (showMapIcons == true, groupBy == 'source')",
    addon.db and addon.db.showMapIcons == true and addon.db.groupBy == "source")
check("defaults merged (reopenWindow == true, hidden == {})",
    addon.db and addon.db.reopenWindow == true and type(addon.db.hidden) == "table")
check("global saved var table created",
    type(_G.MountTrackerLocalZonesDB) == "table")

step("run post-login timers (warm cache / retry loop)", function()
    Harness.runTimers()
end)

step("zone-change burst", function()
    Harness.changeZone(SCENARIO == "warm" and "Stormwind City" or "Duskwood")
end)
step("run debounced zone-refresh timers", function()
    Harness.runTimers()
end)

step("collect a mount + usability change bursts", function()
    Harness.collectMount(SCENARIO == "warm" and 11 or 99999)
    Harness.usabilityChanged()
    Harness.runTimers()
end)

-- ---------------------------------------------------------------------------
-- Mount row / map-pin interactions
-- ---------------------------------------------------------------------------
step("bind a scratch row and fire every click branch", function()
    local button = _G.CreateFrame("Button")
    button.mountID = SCENARIO == "warm" and 18 or 1
    button.spellID = 12345
    addon.BindMount(button)
    Stub.fireScript(button, "OnEnter")
    Stub.fireScript(button, "OnLeave")
    Stub.fireScript(button, "OnClick", "LeftButton")
    Stub.fireScript(button, "OnClick", "RightButton")
    _G.IsModifiedClick = function() return true end
    Stub.fireScript(button, "OnClick", "LeftButton")
    _G.IsModifiedClick = function() return false end
end)

step("hide then restore a mount", function()
    local victim = SCENARIO == "warm" and 18 or 42
    addon.SetMountHidden(victim, true)
    Harness.runTimers()
    check("mount recorded as hidden", addon.db.hidden[victim] == true)
    addon.SetMountHidden(victim, false)
    Harness.runTimers()
    check("mount restored", addon.db.hidden[victim] == nil)
end)

-- ---------------------------------------------------------------------------
-- Map / minimap pins (Map.lua)
-- ---------------------------------------------------------------------------
check("addon.Map exposes Refresh / Rebuild / Invalidate",
    type(addon.Map.Refresh) == "function"
        and type(addon.Map.Rebuild) == "function"
        and type(addon.Map.Invalidate) == "function")

step("Map.Rebuild + Map.Refresh do not throw", function()
    addon.Map.Rebuild()
    addon.Map.Refresh()
end)

if SCENARIO == "warm" then
    step("warm: a curated point places a world + minimap pin", function()
        addon.Map.Rebuild()
        check("world pin placed for the positioned mount", Stub.data.worldPins > 0,
            "AddWorldMapIconMap was never called")
        check("minimap pin placed for the positioned mount", Stub.data.minimapPins > 0,
            "AddMinimapIconMap was never called")
    end)

    step("warm: turning both icon sets off places nothing", function()
        addon.db.showMapIcons = false
        addon.db.showMinimapIcons = false
        addon.Map.Rebuild()
        check("no world pins with showMapIcons off", Stub.data.worldPins == 0, Stub.data.worldPins)
        check("no minimap pins with showMinimapIcons off", Stub.data.minimapPins == 0, Stub.data.minimapPins)
        addon.db.showMapIcons = true
        addon.db.showMinimapIcons = true
        addon.Map.Rebuild()
    end)
end

-- ---------------------------------------------------------------------------
-- Obtainability engine
-- ---------------------------------------------------------------------------
if SCENARIO == "warm" then
    step("obtainability states compute for the seeded mounts", function()
        local vendor = addon.Obtainability.Evaluate(11, { isCollected = false, source = "vendor" })
        local rep = addon.Obtainability.Evaluate(18, { isCollected = false, source = "vendor" })
        local collected = addon.Obtainability.Evaluate(9, { isCollected = true, source = "vendor" })
        check("affordable vendor mount -> 'available'", vendor.state == "available", vendor.state)
        check("short-on-renown mount -> 'rep_gated'", rep.state == "rep_gated", rep.state)
        check("collected mount -> 'collected'", collected.state == "collected", collected.state)
    end)
end

-- The shipped Overrides.lua seed (real mount ids), independent of the scenario.
step("obtainability reads the Overrides seed", function()
    -- 168 Fiery Warhorse: lockout = "weekly", no lockout quest -> farmable.
    local farm = addon.Obtainability.Evaluate(168, { isCollected = false, source = "instance" })
    check("weekly-lockout mount -> 'farmable'", farm.state == "farmable", farm.state)

    -- 236 Winged Steed of the Ebon Blade: gold vendor, ~1000g. Rich player -> available.
    local before = Stub.data.money
    Stub.data.money = 5000 * 10000 * 100
    local buy = addon.Obtainability.Evaluate(236, { isCollected = false, source = "vendor" })
    Stub.data.money = before
    check("affordable Overrides vendor mount -> 'available'", buy.state == "available", buy.state)
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
for _, cmd in ipairs({
    "", "show", "toggle", "", "list", "config", "map", "debug", "debug",
    "reset", "totally-unknown-subcommand",
}) do
    step(("slash: /mtlz %q"):format(cmd), function()
        Harness.slash(cmd)
        Harness.runTimers()
    end)
end

check("a slash command produced chat output",
    #Harness.getPrints() > 0, "nothing was printed by any command")

-- ---------------------------------------------------------------------------
-- Options panel + minimap button (Config.lua / MinimapButton.lua)
-- ---------------------------------------------------------------------------
check("/mtlz config opened the options panel", Stub.data.openedCategory ~= nil,
    "Settings.OpenToCategory was never called")

step("toggle list settings through the panel, refresh", function()
    local s = Stub.data.settings
    if s.groupBy then s.groupBy.set("expansion") end
    if s.showCollected then s.showCollected.set(true) end
    addon.RefreshWindow()
    Harness.runTimers()
    if s.groupBy then s.groupBy.set("source") end
    if s.showCollected then s.showCollected.set(false) end
    addon.RefreshWindow()
end)

step("Filter by source: unchecking 'Show Vendor' hides vendor mounts", function()
    local binding = Stub.data.settings.show_vendor
    check("the 'Show Vendor' checkbox is bound", binding ~= nil)
    if binding then
        check("it reads as checked by default", binding.get() == true)
        binding.set(false)
        check("db.hiddenSources.vendor is now set", addon.db.hiddenSources.vendor == true)
        binding.set(true)
        check("db.hiddenSources.vendor cleared again", addon.db.hiddenSources.vendor == nil)
    end
    addon.RefreshWindow()
    Harness.runTimers()
end)

step("minimap button toggle (ApplyMinimapButton both ways)", function()
    addon.db.showMinimapButton = false
    addon.ApplyMinimapButton()
    addon.db.showMinimapButton = true
    addon.ApplyMinimapButton()
end)

if SCENARIO == "warm" then
    local named = false
    for _, line in ipairs(Harness.getPrints()) do
        if tostring(line):find("Pinto", 1, true) then named = true end
    end
    check("warm: /mtlz list named a seeded uncollected zone mount", named,
        "/mtlz list never named 'Pinto' -- deep model path not exercised")
end

-- ---------------------------------------------------------------------------
-- Global mounts option (showGlobal)
-- ---------------------------------------------------------------------------
step("enable showGlobal, invalidate cache, re-list + open window", function()
    addon.db.showGlobal = true
    if addon.MountModel then addon.MountModel.InvalidateCache() end
    Harness.clearPrints()
    Harness.slash("list")
    Harness.slash("show")
    Harness.runTimers()
end)

if SCENARIO == "warm" then
    local sawDivider, sawGlobalMount = false, false
    for _, line in ipairs(Harness.getPrints()) do
        line = tostring(line)
        if line:find("Global", 1, true) then sawDivider = true end
        if line:find("Dreadsteed", 1, true) then sawGlobalMount = true end
    end
    check("warm: /mtlz list printed the Global divider", sawDivider,
        "'-- Global --' never appeared with showGlobal on")
    check("warm: /mtlz list named a seeded global mount", sawGlobalMount,
        "the seeded global mount (8) was not listed")
end

step("groupBy = expansion, re-list", function()
    addon.db.groupBy = "expansion"
    if addon.MountModel then addon.MountModel.InvalidateCache() end
    Harness.slash("list")
    Harness.runTimers()
    addon.db.groupBy = "source"
    if addon.MountModel then addon.MountModel.InvalidateCache() end
end)

step("disable showGlobal again", function()
    addon.db.showGlobal = false
    if addon.MountModel then addon.MountModel.InvalidateCache() end
    Harness.slash("list")
    Harness.slash("") -- toggle the window back closed
    Harness.runTimers()
end)

-- ---------------------------------------------------------------------------
-- Window open + zone change while shown
-- ---------------------------------------------------------------------------
step("open window, change zone while shown, refresh", function()
    Harness.slash("show")
    Harness.runTimers()
    Harness.changeZone(SCENARIO == "warm" and "Stormwind City" or "Westfall")
    Harness.runTimers()
    Harness.slash("list")
end)

step("close window", function()
    Harness.slash("") -- /mtlz with the window shown toggles it closed
    Harness.runTimers()
end)

step("logout (records window-open state for next login)", function()
    Harness.fireEvent("PLAYER_LOGOUT")
end)
check("logout recorded window state", type(addon.db.windowOpen) == "boolean")

-- ---------------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------------
local ok = true
for _, c in ipairs(checks) do
    if not c.ok then ok = false end
end

return { ok = ok, checks = checks, scenario = SCENARIO }
