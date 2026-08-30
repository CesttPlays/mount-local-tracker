# Phase 6 — Overrides.lua seed

Seeded `Mount_Tracker_Local_Zones/Overrides.lua` on 2026-08-30 (build 12.1.0.69497).
All mountIDs and zone uiMapIDs were grepped out of `.wago-cache/12.1.0.69497/`
(`Mount.csv` by exact `Name_lang`, `UiMap.csv` for zones). ~30 distinct mounts.

## What went in

| table | count | mounts |
| --- | --- | --- |
| `add` | 3 | Solar Spirehawk→Spires of Arak (542), Voidtalon→Shadowmoon Valley Draenor (539), Heavenly Onyx Cloud Serpent→Kun-Lai (379) — the generator left these zoneless |
| `points` | 7 | Time-Lost Proto-Drake, Aeonaxx (Phosphorescent Stone Drake), Long-Forgotten Hippogryph, Poseidus (Subdued Seahorse), Solar Spirehawk, Voidtalon, Heavenly Onyx Cloud Serpent |
| `source`/`subcat` | 6 / 7 | the rares above retyped `drop`/`rare` |
| `dropChance` | 24 | the 7 rares + 17 instance farms |
| `lockout` | 18 | Raven Lord, Swift White Hawkstrider, Fiery Warhorse, 3× Dragon Soul, Swift Zulian Panther, Armored Razzashi Raptor, Invincible, Ashes of Al'ar, Blue Drake, Blue Proto-Drake, Onyxian Drake, N/S Wind drakes, Vitreous Stone Drake, Grand Black War Mammoth, Heavenly Onyx Cloud Serpent |
| `vendor` | 7 | Traveler's Tundra Mammoth, Armored Blue Wind Rider, Winged Steed of the Ebon Blade, Brown/Tan Riding Camel, Grand Ice Mammoth, Tamed Skitterfly |
| `repFaction` | 5 | Brown/Tan Camel (Ramkahen), Grand Ice Mammoth (Sons of Hodir), Tamed Skitterfly (Dragonscale Expedition r25), Brown War Ottuk (Iskaara Tuskarr r30) |
| `note` | 7 | Time-Lost/Vyragosa, Aeonaxx, LFH crystals, Poseidus, Voidtalon, Raven Lord, Ottuk |

## Low-confidence — spot-check in-game (phase 8)

- **All 7 `points` coords** are eyeballed spawn/patrol centroids, not surveyed. Good
  enough for "there's a marker in roughly the right zone", not for pathing to it.
  Poseidus/LFH especially — those targets roam a whole zone.
- **`repFaction` factionIDs**: Ramkahen 1173, Sons of Hodir 1119, Dragonscale
  Expedition 2507, Iskaara Tuskarr 2511. Classic-rep "Exalted" is encoded as the raw
  value `42000`; `Obtainability.ReputationProgress` compares that against
  `C_Reputation.GetFactionDataByID(...).currentStanding` — verify that field is a
  cumulative value on this build, not a within-tier delta.
- **`vendor` costs**: Traveler's Tundra Mammoth `20000g` and Armored Blue Wind Rider
  `2000g` are from the mount's own `SourceText`. Grand Ice Mammoth `10000g` is the
  commonly cited figure. NPC map coords (Mei Francis in Dalaran etc.) are rough.
- **Dalaran (Northrend) uiMapID 125** is `UiMap.Type 4` in this build (not the usual
  city `Type 6`); if the runtime `GetBestMapForUnit` returns a different Dalaran id
  the vendor NPC coord pin won't line up. Not fatal — vendor coords are display-only.
- **`lockout` daily/weekly** split is by dungeon/raid convention; no `lockoutQuest`
  ids were seeded (not confidently known), so the engine shows "farmable · weekly"
  but never "done this reset". That's the acceptable fallback per the plan.

## Not seeded (left for later curation)

Drake of the West Wind (faction-specific Tol Barad quartermaster — needs the
0/1 faction split done properly), Golden King (rotating "world vendor", no fixed
zone), the Argent Tournament / Wintergrasp currency mounts, profession mounts,
Grand Expedition Yak.
