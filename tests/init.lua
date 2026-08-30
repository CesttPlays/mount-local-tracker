-- Entry point for one smoke-test scenario, run in a fresh Lua state by run.py.
-- Expects globals: TEST_DIR, ADDON_DIR, SCENARIO ("cold" | "warm").
-- Sets _G.RESULT = { ok = bool, checks = { {name, ok, detail}, ... }, error = str? }

local TEST_DIR = assert(_G.TEST_DIR, "TEST_DIR not set")
local SCENARIO = _G.SCENARIO or "cold"

local Stub = dofile(TEST_DIR .. "/stub.lua")
_G.WowStub = Stub
Stub.install()

-- The "warm" scenario feeds a tiny fake mount world so the code paths behind the
-- API-readiness gate actually execute. It asserts nothing about the specific
-- results -- only that walking that data never throws and the obtainability
-- states compute. uiMapID 84 (Stormwind City) has entries in the real
-- MountData.zones, so CandidateSet returns a non-empty list for it.
if SCENARIO == "warm" then
    local D = Stub.data
    D.zone = "Stormwind City"
    D.mapID = 84
    D.mapInfo[84] = { name = "Stormwind City", mapID = 84, parentMapID = 0 }
    D.money = 100000 -- 10g, enough for the seeded vendor mount

    -- 9 / 11 / 18 are all in MountData.zones[84]; 8 is in MountData.global.
    D.mountIDs = { 8, 9, 11, 18 }
    D.mountInfo = {
        [8]  = { name = "Warlock's Dreadsteed", spellID = 80,  isUsable = true,  isCollected = false },
        [9]  = { name = "Swift Palomino",       spellID = 90,  isUsable = true,  isCollected = true },
        [11] = { name = "Chestnut Mare",        spellID = 110, isUsable = true,  isCollected = false },
        [18] = { name = "Pinto",                spellID = 180, isUsable = false, isCollected = false },
    }
    D.factions = { [2600] = { renownLevel = 5 } } -- short of the seeded threshold

    -- Applied to addon.MountOverrides after the addon loads (see smoke.lua):
    --   11 -> a vendor mount you can afford  -> state "available"
    --   18 -> a renown mount you're short on -> state "rep_gated"
    D.overrides = {
        -- 11 -> affordable, positioned vendor. 18 -> renown-gated *and* sold by a
        -- positioned vendor, so the vendor map-pin / waypoint fallback has a target.
        vendor = {
            [11] = { npc = "Katie Stokx", uiMapID = 84, x = 5000, y = 5000, cost = 500 },
            [18] = { npc = "Katie Stokx", uiMapID = 84, x = 5200, y = 4800, cost = 500 },
        },
        repFaction = { [18] = { factionID = 2600, standing = 20 } },
        note = { [8] = "Class mount -- learned from a quest chain." },
        -- 8 is an uncollected global mount; a curated point makes Map.Compute
        -- place a world + minimap pin for it.
        points = { [8] = { 84, 5000, 5000 } },
    }
end

local Harness = dofile(TEST_DIR .. "/harness.lua")

local result = dofile(TEST_DIR .. "/smoke.lua")
_G.RESULT = result
return result.ok
