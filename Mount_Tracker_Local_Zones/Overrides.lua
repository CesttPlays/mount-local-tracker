local _, addon = ...

-- Hand-maintained corrections to the generated MountData.lua, merged at runtime.
-- The generator never touches this file, so edits here survive regeneration.
--
--   add          [uiMapID] = { mountID, ... }   -- extra mounts for a zone ([0] = global bucket)
--   remove       [uiMapID] = { mountID, ... }   -- drop a wrong association ([0] = suppress from global)
--   source       [mountID] = "vendor" | "drop" | ...
--   subcat       [mountID] = "rare" | "raid" | ...
--   points       [mountID] = { uiMapID, x*10000, y*10000 }
--   faction      [mountID] = 0 (Horde) | 1 (Alliance)
--   expansion    [mountID] = expansionID
--   dropChance   [mountID] = "~1%"              -- curated display string
--   lockout      [mountID] = "daily" | "weekly"
--   lockoutQuest [mountID] = questID            -- hidden quest that flags "done this reset"
--   vendor       [mountID] = { npcID, uiMapID, x, y, cost, currencyID }
--   repFaction   [mountID] = { factionID, standing }
--   note         [mountID] = "short tip"
--
-- uiMapID comes from C_Map.GetBestMapForUnit("player"); /mtlz debug prints the
-- current zone's id in chat.

addon.MountOverrides = {
	add = {
		-- [1970] = { 1416 },  -- Thaldraszus: Highland Drake
	},
	remove = {
		-- [0] = { 123 },      -- never treat mount 123 as a global
	},
	source = {},
	subcat = {},
	points = {},
	faction = {},
	expansion = {},
	dropChance = {},
	lockout = {},
	lockoutQuest = {},
	vendor = {},
	repFaction = {},
	note = {},
}
