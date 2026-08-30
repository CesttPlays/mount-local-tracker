-- Loads the addon the way the WoW client would -- files in TOC order, each
-- called with the (addonName, addonTable) vararg and a shared _G -- then exposes
-- helpers to drive its event / timer / slash surface.

local Stub = _G.WowStub or error("stub.lua must run before harness.lua")

local ADDON_NAME = "Mount_Tracker_Local_Zones"
local ADDON_DIR = _G.ADDON_DIR or error("ADDON_DIR not set")

local Harness = { addon = {}, addonName = ADDON_NAME }

-- Read the file list out of the .toc so the load order is never a second copy
-- that can drift. Skip metadata (##), comments (#) and the vendored Libs (the
-- stub fakes LibStub instead of loading the real libraries).
local function tocFiles()
    local path = ADDON_DIR .. "/" .. ADDON_NAME .. ".toc"
    local fh = assert(io.open(path, "r"), "cannot open TOC: " .. path)
    local files = {}
    for line in fh:lines() do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local rel = line:gsub("\\", "/")
            -- Lua only: .xml templates are consumed by the client, not loadfile'd,
            -- and the stub fakes LibStub instead of loading the vendored Libs.
            if rel:match("%.lua$") and not rel:match("^Libs/") then
                files[#files + 1] = rel
            end
        end
    end
    fh:close()
    return files
end

function Harness.load()
    for _, rel in ipairs(tocFiles()) do
        local full = ADDON_DIR .. "/" .. rel
        local chunk, err = loadfile(full)
        if not chunk then
            error("load error in " .. rel .. ": " .. tostring(err), 0)
        end
        local ok, runErr = pcall(chunk, ADDON_NAME, Harness.addon)
        if not ok then
            error("runtime error loading " .. rel .. ": " .. tostring(runErr), 0)
        end
        Harness.loaded = Harness.loaded or {}
        Harness.loaded[#Harness.loaded + 1] = rel
    end
    return Harness
end

-- Lifecycle: the event sequence the client fires on a fresh login.
function Harness.login()
    Stub.fireEvent("ADDON_LOADED", ADDON_NAME)
    Stub.fireEvent("PLAYER_LOGIN")
    Stub.fireEvent("PLAYER_ENTERING_WORLD", true, false)
end

function Harness.changeZone(zone, subZone)
    if zone ~= nil then Stub.data.zone = zone end
    if subZone ~= nil then Stub.data.subZone = subZone end
    Stub.fireEvent("ZONE_CHANGED_NEW_AREA")
    Stub.fireEvent("ZONE_CHANGED")
    Stub.fireEvent("ZONE_CHANGED_INDOORS")
end

function Harness.collectMount(mountID)
    if mountID and Stub.data.mountInfo[mountID] then
        Stub.data.mountInfo[mountID].isCollected = true
    end
    Stub.fireEvent("NEW_MOUNT_ADDED", mountID)
end

function Harness.usabilityChanged()
    Stub.fireEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
end

function Harness.slash(msg)
    local fn = _G.SlashCmdList and _G.SlashCmdList.MTLZ
    if not fn then error("no /mtlz handler registered") end
    fn(msg or "")
end

Harness.fireEvent = Stub.fireEvent
Harness.runTimers = Stub.runTimers
Harness.getPrints = Stub.getPrints
Harness.clearPrints = Stub.clearPrints

_G.Harness = Harness
return Harness
