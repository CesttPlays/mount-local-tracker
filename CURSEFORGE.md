<!--
CurseForge project page copy for "Mount Tracker: Local Zones".
Paste the body below into the project Description. Use the one-line Summary
as the project Summary (it is a separate field on CurseForge).
Checked against CurseForge moderation policies:
https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies
- English throughout.
- Functional description, not a generic pitch.
- No external download links.
- Repo / bug-report links kept small and at the bottom.
- No copyrighted or datamined imagery embedded here (screenshots go in the Images tab).
-->

# Summary

Shows the mounts you can still collect in the zone you're standing in — and whether you can actually get them right now.

---

# Mount Tracker: Local Zones

You ride into a zone and you don't remember which mounts drop there, or which
vendor sells one you could already afford. This addon answers that. It puts a
small window on your screen listing the uncollected mounts tied to your current
zone — dungeon and raid drops for the instances there, rare-mob drops, vendor
mounts, quest rewards, zone drops and world-event mounts.

It follows you. Change zones and the list changes with it. Collect a mount and
its row updates. No setup, no import, no account login.

## What it does

- **Per-zone mount list.** A movable, resizable window listing the uncollected
  mounts for your current zone.
- **Obtainability-aware.** Each row tells you where you stand: *available now*
  for a vendor mount you can afford, a reputation / renown target for a
  quartermaster mount, *farmable — weekly* for an instance you haven't run this
  reset, a drop-chance hint for an open-world rare.
- **Group by source or by expansion.** A setting switches the list between the
  two — Dungeon & Raid, Rare Drop, Vendor, Quest, Zone Drop, World Event,
  Profession — or newest expansion first.
- **Collapsible groups** with an icon and a collected / total count.
- **Global mounts (optional).** Turn this on to also list mounts with no single
  home zone — class, racial, PvP, trading-card, promotion and shop mounts — under
  a "Global" divider below the zone list. Those sections start collapsed.
- **Hover for details.** Blizzard's full mount tooltip, plus the obtainability
  breakdown.
- **Click to open.** Click a row to jump straight to that mount in the Mount
  Journal.
- **Shift-click to link.** Drop the mount's spell link into chat.
- **Right-click for actions.** On a row or a map icon: place a map pin at the
  mount's location, send it to TomTom as a waypoint (when TomTom is installed),
  summon it (if you have it), or hide it.
- **Hide what you'll never chase.** Hidden mounts leave the list and the map.
  Bring them back from Options → Hidden mounts.
- **World map icons.** Every uncollected mount with a known location gets an icon
  on the world map, so you can see which zones still have something for you — and
  where in a zone to look.
- **Minimap icons.** The same markers show on the minimap as you travel near
  them.
- **Minimap button.** Left-click toggles the window, right-click opens the
  options.

## Commands

| Command | Action |
| --- | --- |
| `/mtlz` | Toggle the tracker window |
| `/mtlz list` | Print the current zone's mounts to chat |
| `/mtlz config` | Open the options |
| `/mtlz map` | Rebuild the map and minimap pins |
| `/mtlz reset` | Reset the window position and expand all groups |

## Options

Open with `/mtlz config`, or through Game Menu → Options → AddOns.

**Window**
- **Window style** — *Classic* (Blizzard dialog frame and scrollbar) or
  *Stylized* (flat dark panel with minimal controls). Reload your UI after
  changing it.
- **Reopen on login** — bring the window back at login if it was open when you
  logged out.

**Mount list**
- **Group by** — by source type or by expansion.
- **Show collected mounts** — include mounts you already have, greyed out.
- **Only obtainable now** — hide mounts that are gated behind reputation, an
  achievement or a reset you've already used.
- **Dim unusable mounts** — keep mounts your class or faction can't ride in the
  list, greyed, instead of hiding them.
- **Show global mounts** — also list mounts with no home zone, under a "Global"
  divider.

**Filter by source** — a checkbox per source type (Dungeon & Raid, Rare Drop,
Vendor, Quest, Zone Drop, World Event, Profession) to drop that whole category
from the list.

**Map & minimap**
- **Show minimap button**
- **Show world map icons**
- **Show minimap icons**

**Hidden mounts** — a sub-page listing everything you've hidden, with a
**Restore** button on each and a **Restore all**.

## Compatibility

- Built for current retail World of Warcraft.
- **TomTom** — optional. When it's installed, the right-click menu can send a
  mount's location to TomTom as a waypoint. The addon works fine without it.
- Mount collection is account-wide; the addon's settings are saved per character.

## How the zone data is built

There is no WoW API that maps a collectable mount to the zone you get it in, so
the association is datamined from the game's own data files, refreshed each
patch, and shipped with the addon. Anything that can't be resolved automatically
is hand-curated or listed as a global mount. Coverage is partial and improving —
if a mount is missing from a zone, or in the wrong one, please say so (see
below).

## Credits

Bundles the following open libraries: LibStub, CallbackHandler-1.0,
LibDataBroker-1.1, LibDBIcon-1.0, and HereBeDragons-2.0. Thanks to their authors.

## Source and bug reports

Found a bug, or a mount in the wrong zone? A few ways to reach me:

- The **comments on this CurseForge page**, or the CurseForge addon forum.
- **@Cestt_Plays** on X / socials.

A screenshot and the zone / mount name helps a lot.
