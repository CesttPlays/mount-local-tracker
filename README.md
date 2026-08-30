# Mount Tracker: Local Zones

Shows the mounts you can still collect **in the zone you're standing in** — and
whether you can actually get them right now.

> **Status:** early development. The skeleton (saved variables, slash commands,
> event wiring) is in place; the zone data, tracker window, obtainability engine
> and map pins are being built phase by phase. Not yet released.

## What it does

- **Per-zone mount list.** A movable, resizable window listing the uncollected
  mounts tied to your current zone — dungeon and raid drops for instances there,
  rare-mob drops, vendor mounts, quest rewards, zone drops and world-event
  mounts. It follows you as you change zones.
- **Obtainability-aware.** Every row says where you stand: *available now* for a
  vendor mount you can afford, *Revered — 2,400 → Exalted* for a reputation mount,
  *weekly — done this reset* for a farm you've already run, *~0.4%* for a rare
  drop. Inspired by [MissingMounts](https://www.missingmounts.com/).
- **Group by source or expansion.** A setting switches the list between grouping
  by source type (Dungeon & Raid, Rare Drop, Vendor, Quest, …) and by expansion.
- **Collapsible groups** with an icon and a collected/total count.
- **Global mounts (optional).** Turn this on to also see mounts with no home zone
  (class, racial, PvP, store, promotion) under a "Global" divider.
- **Hover for details.** The full Blizzard mount tooltip plus the obtainability
  breakdown.
- **Click to open.** Click a row to jump to that mount in the Mount Journal.
  Shift-click to link it in chat. Right-click for a menu: place a map pin, send it
  to TomTom (when installed), summon it (if collected), or hide it.
- **Hide what you'll never chase.** Hidden mounts drop out of the list and off the
  map; restore them from the options.
- **World map & minimap icons** for uncollected mounts with a known location.
- **Minimap button** — left-click toggles the tracker, right-click opens options.

## Commands

| Command | Action |
| --- | --- |
| `/mtlz` | Toggle the tracker window |
| `/mtlz list` | Print the current zone's mounts to chat |
| `/mtlz config` | Open the options |
| `/mtlz map` | Rebuild the map pins |
| `/mtlz debug` | Toggle debug chat output |
| `/mtlz reset` | Reset the window position and expand all groups |

## How the zone data is built

No WoW API maps a mount to the zone you collect it in, so the association is
datamined offline from the game's DB2 tables by `tools/generate_mount_zones.py`
and shipped as `MountData.lua`, refreshed each patch. Anything the generator
can't resolve is hand-curated in `Overrides.lua` (merged at runtime) or listed as
a global mount. Expect coverage to be partial and improving.

## Related

Sibling project: **[Achievement Tracker: Local
Zones](https://github.com/CesttPlays/achivement-local-tracker)** — the same idea
for achievements, built first. This addon mirrors its architecture, headless
tests, CI and release pipeline.

## License

MIT — see [LICENSE](LICENSE).
