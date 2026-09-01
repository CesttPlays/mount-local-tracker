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
--   achievementID[mountID] = achievementID      -- mount is a reward for finishing that
--                            achievement; drives the "Achievement needed" obtainability line
--   dropChance   [mountID] = "~1%"              -- curated display string
--   lockout      [mountID] = "daily" | "weekly"
--   lockoutQuest [mountID] = questID            -- hidden quest that flags "done this reset"
--   vendor       [mountID] = { npc = , uiMapID = , x = , y = , cost = , currencyID = }
--                            (cost in copper when currencyID is nil, i.e. gold)
--   repFaction   [mountID] = { factionID = , standing = }  -- standing = renown level
--                            for a major faction, or the raw reputation value otherwise
--   note         [mountID] = "short tip"
--
-- mountID == C_MountJournal id == DB2 Mount.ID. uiMapID comes from
-- C_Map.GetBestMapForUnit("player"); /mtlz debug prints the current zone id.
--
-- Coordinates below are approximate spawn / patrol centroids from community data
-- (wowhead) -- close enough for a map marker, not a GPS fix. Drop rates are the
-- commonly cited figures.

addon.MountOverrides = {
	-- The generator missed a home zone for these three.
	add = {
		[542] = { 634 }, -- Spires of Arak: Solar Spirehawk (Rukhmar)
		[539] = { 682 }, -- Shadowmoon Valley (Draenor): Voidtalon of the Dark Star
		[379] = { 473 }, -- Kun-Lai Summit: Heavenly Onyx Cloud Serpent (Sha of Anger)
	},

	remove = {},

	-- Open-world rare drops: retype to a rare drop and give them a map pin.
	source = {
		[265] = "drop", -- Time-Lost Proto-Drake
		[393] = "drop", -- Phosphorescent Stone Drake (Aeonaxx)
		[802] = "drop", -- Long-Forgotten Hippogryph
		[420] = "drop", -- Subdued Seahorse (Poseidus)
		[634] = "drop", -- Solar Spirehawk
		[682] = "drop", -- Voidtalon of the Dark Star
	},
	subcat = {
		[265] = "rare",
		[393] = "rare",
		[802] = "rare",
		[420] = "rare",
		[634] = "rare",
		[682] = "rare",
		[473] = "rare",
	},

	-- Map pins for the well-known rares.
	points = {
		[265] = { 120, 6100, 4300 }, -- Time-Lost Proto-Drake -- Storm Peaks patrol (NW)
		[393] = { 207, 4900, 5500 }, -- Aeonaxx -- Deepholm, near the Temple of Earth
		[802] = { 630, 4400, 4200 }, -- Long-Forgotten Hippogryph -- Azsuna (crystals roam)
		[420] = { 205, 5000, 5000 }, -- Poseidus -- Shimmering Expanse (roams all of Vashj'ir)
		[634] = { 542, 3600, 3200 }, -- Solar Spirehawk -- Rukhmar, above Sethekk Hollow
		[682] = { 539, 2300, 3900 }, -- Voidtalon -- Shadowmoon Valley portal spawns
		[473] = { 379, 4000, 6200 }, -- Heavenly Onyx Cloud Serpent -- Sha of Anger roams Kun-Lai
	},

	faction = {},
	expansion = {},

	-- Achievement-reward links the generator's auto-resolver (plan 006) can't
	-- make confidently. [mountID] = achievementID; feeds the "Achievement needed"
	-- obtainability line for uncollected mounts.
	--
	-- Empty by design: the generator links every mount with a clean RewardItemID
	-- FK or an unambiguous title match (~183 on build 12.1.0.69497). The mounts
	-- it leaves unlinked are collection metas ("Mountacular", "A Horde of
	-- Hoofbeats"), Allied-race unlocks and PvP feats -- each has an Alliance/Horde
	-- title pair or sits in a global category, so there is no single achievement
	-- to gate on and they correctly stay in the Global bucket. Add an entry here
	-- only for a specific mount you want the tooltip to call out.
	achievementID = {},

	dropChance = {
		[265] = "guaranteed off the rare",
		[393] = "guaranteed off Aeonaxx",
		[802] = "5 hidden crystals",
		[420] = "guaranteed off Poseidus",
		[634] = "~4% from Rukhmar",
		[682] = "guaranteed off the Voidtalon",
		[473] = "~2% from Sha of Anger",
		-- instance farms
		[185] = "~1%",  -- Raven Lord
		[213] = "~4%",  -- Swift White Hawkstrider
		[168] = "~1%",  -- Fiery Warhorse
		[442] = "~1%",  -- Blazing Drake
		[444] = "~1%",  -- Life-Binder's Handmaiden
		[445] = "Cache of the Aspects",  -- Experiment 12-B
		[411] = "~1%",  -- Swift Zulian Panther
		[410] = "~1%",  -- Armored Razzashi Raptor
		[363] = "~1%",  -- Invincible
		[183] = "~2%",  -- Ashes of Al'ar
		[247] = "~4%",  -- Blue Drake
		[264] = "~1%",  -- Blue Proto-Drake
		[349] = "~1%",  -- Onyxian Drake
		[395] = "~1%",  -- Drake of the North Wind
		[396] = "~1%",  -- Drake of the South Wind
		[397] = "~1%",  -- Vitreous Stone Drake
		[286] = "~1%",  -- Grand Black War Mammoth
	},

	-- Reset-locked farms. No lockoutQuest ids (not confidently known), so the
	-- engine shows "farmable - weekly/daily" but never "done this reset".
	lockout = {
		[185] = "daily",   -- Raven Lord (heroic Sethekk Halls)
		[213] = "daily",   -- Swift White Hawkstrider (heroic Magisters' Terrace)
		[168] = "weekly",  -- Fiery Warhorse (Karazhan)
		[442] = "weekly",  -- Blazing Drake (Dragon Soul)
		[444] = "weekly",  -- Life-Binder's Handmaiden (Dragon Soul)
		[445] = "weekly",  -- Experiment 12-B (Dragon Soul)
		[411] = "daily",   -- Swift Zulian Panther (Zul'Gurub)
		[410] = "daily",   -- Armored Razzashi Raptor (Zul'Gurub)
		[363] = "weekly",  -- Invincible (Icecrown Citadel 25H)
		[183] = "weekly",  -- Ashes of Al'ar (Tempest Keep)
		[247] = "weekly",  -- Blue Drake (Eye of Eternity)
		[264] = "daily",   -- Blue Proto-Drake (heroic Utgarde Pinnacle)
		[349] = "weekly",  -- Onyxian Drake (Onyxia's Lair)
		[395] = "daily",   -- Drake of the North Wind (heroic Vortex Pinnacle)
		[396] = "weekly",  -- Drake of the South Wind (Throne of the Four Winds)
		[397] = "daily",   -- Vitreous Stone Drake (heroic Stonecore)
		[286] = "weekly",  -- Grand Black War Mammoth (Vault of Archavon)
		[473] = "weekly",  -- Heavenly Onyx Cloud Serpent (Sha of Anger world boss)
	},
	lockoutQuest = {},

	-- Gold / reputation vendor mounts.
	vendor = {
		-- Mei Francis, Dalaran (Northrend). Flat gold, no reputation.
		[280] = { npc = "Mei Francis", uiMapID = 125, x = 5900, y = 4700, cost = 200000000 },
		[277] = { npc = "Mei Francis", uiMapID = 125, x = 5900, y = 4700, cost = 20000000 }, -- Armored Blue Wind Rider
		-- Dread Commander Thalanor, Eastern Plaguelands. Death Knight vendor.
		[236] = { npc = "Dread Commander Thalanor", uiMapID = 23, x = 2000, y = 5900, cost = 10000000 }, -- Winged Steed of the Ebon Blade
		-- Blacksmith Abasi, Uldum. Requires Ramkahen - Exalted.
		[398] = { npc = "Blacksmith Abasi", uiMapID = 249, x = 5600, y = 3400, cost = 1000000 }, -- Brown Riding Camel
		[399] = { npc = "Blacksmith Abasi", uiMapID = 249, x = 5600, y = 3400, cost = 1000000 }, -- Tan Riding Camel
		-- Lillehoff, Storm Peaks. Requires The Sons of Hodir - Exalted.
		[288] = { npc = "Lillehoff", uiMapID = 120, x = 6600, y = 5200, cost = 100000000 }, -- Grand Ice Mammoth
		-- Granpap Whiskers, Dragonscale Basecamp. Requires Dragonscale Expedition Renown 25.
		[1615] = { npc = "Granpap Whiskers", uiMapID = 2022, x = 5100, y = 8600, cost = 0 }, -- Tamed Skitterfly
	},

	repFaction = {
		[398] = { factionID = 1173, standing = 42000 },  -- Ramkahen -- Exalted
		[399] = { factionID = 1173, standing = 42000 },  -- Ramkahen -- Exalted
		[288] = { factionID = 1119, standing = 42000 },  -- The Sons of Hodir -- Exalted
		[1615] = { factionID = 2507, standing = 25 },    -- Dragonscale Expedition -- Renown 25
		[1653] = { factionID = 2511, standing = 30 },    -- Iskaara Tuskarr -- Renown 30 (Brown War Ottuk)
	},

	note = {
		[265] = "Shares its spawn point and timer with the grey drake Vyragosa -- most sightings are her.",
		[393] = "Aeonaxx is a cloaked flyer on a long patrol; tag it and ride the fight down.",
		[802] = "Collect five Crystallized Memories hidden around Azsuna; one becomes available per day.",
		[420] = "Poseidus roams the whole of Vashj'ir underwater on a multi-hour timer.",
		[682] = "Spawns from a temporary Dark Portal at fixed spots -- server-wide competition for the click.",
		[185] = "Was a druid-only summon; now a normal boss in Heroic Sethekk Halls.",
		[1653] = "Bought with Tuskarr crafting mats once you hit Renown 30.",
	},
}
