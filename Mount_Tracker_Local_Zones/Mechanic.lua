local addonName, addon = ...

-- ============================================================================
-- Mechanic dev-hub integration (optional, dev-only)
--
-- Loads last so it can wrap addon.DebugPrint. Does nothing unless the !Mechanic
-- addon is installed. When it is:
--   * every DebugPrint line is captured to a ring buffer that Mechanic reads via
--     getDebugBuffer (surfaced by `mech addon.output`), regardless of the
--     /mtlz debug toggle
--   * with /mtlz debug OFF, those lines are also pushed to Mechanic's Console
--     tab. With it ON they print for real, and Mechanic's own global print hook
--     already mirrors them into the Console -- so we skip our push to avoid
--     logging the same line twice.
--   * the addon appears in Mechanic's Lib Registry with its version
--
-- Plain addon.Print (user-facing chat) is deliberately NOT wrapped: it reaches
-- the chat frame, and Mechanic's print hook already mirrors it into the Console.
--
-- Chat output and the headless smoke tests are unaffected. This file is stripped
-- from packaged (CurseForge/WoWInterface) builds via #@do-not-package@ in the TOC.
-- ============================================================================

-- `true` = silent lookup: returns nil (no error) when MechanicLib, which ships
-- inside !Mechanic, is absent.
local MechanicLib = _G.LibStub and _G.LibStub("MechanicLib-1.0", true)

-- Ring buffer of recent debug lines. Entry shape: { message, time, category }.
local LOG_MAX = 500
local logBuffer = {}
addon.logBuffer = logBuffer

local function now()
	return (_G.GetTime and _G.GetTime()) or 0
end

-- Append to the ring buffer, collapsing identical consecutive lines (zone
-- events fire in bursts of 3-4). Returns true when the line was actually added.
local lastLine, lastAt
local function Record(message)
	local t = now()
	if message == lastLine and (t - (lastAt or 0)) < 0.1 then
		return false
	end
	lastLine, lastAt = message, t

	logBuffer[#logBuffer + 1] = { message = message, time = t, category = "[Debug]" }
	if #logBuffer > LOG_MAX then
		table.remove(logBuffer, 1)
	end
	return true
end

local originalDebugPrint = addon.DebugPrint
addon.DebugPrint = function(message)
	message = tostring(message)
	-- Only push to Mechanic's Console when the original won't print the line
	-- itself (see header): otherwise Mechanic's print hook double-logs it.
	if Record(message) and MechanicLib and not (addon.db and addon.db.debug) then
		MechanicLib:Log(addonName, message, "[Debug]")
	end
	return originalDebugPrint(message)
end

if not MechanicLib then
	return
end

local version = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata(addonName, "Version"))
	or "dev"

MechanicLib:Register(addonName, {
	version = version,
	getDebugBuffer = function()
		return logBuffer
	end,
	clearDebugBuffer = function()
		wipe(logBuffer)
	end,
})

addon.DebugPrint("Mechanic integration active (v" .. version .. ")")
