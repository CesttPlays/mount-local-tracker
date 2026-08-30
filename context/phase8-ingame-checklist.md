# Phase 8 — in-game validation checklist

Nothing in phases 1-7 has run in the live client. The headless suite proves "no
Lua threw and the wiring is connected"; it does NOT prove the WoW APIs behave as
assumed, that frames lay out, or that the curated data is right.

**Deploy:** copy the whole `Mount_Tracker_Local_Zones/` folder to
`E:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\Mount_Tracker_Local_Zones\`,
then `/reload`. Re-run `.\run-tests.ps1` after every fix.

When it all passes: update `context/`, merge `phase-buildout` -> `main`, then
manual-dispatch `release.yml` with `version = 0.1.0`.

---

## A. Load & core (anywhere)

- [ ] No Lua error on login or `/reload`. Addon shows in the AddOns list.
- [ ] `/mtlz help` (or any unknown arg) prints
      `Commands: /mtlz [show | list | config | map | debug | reset]`.
- [ ] `/mtlz debug` toggles; with it **on**, a zone change prints
      `Zone: <name> (uiMapID <n>)` and `/mtlz map` prints `Map: N mount pins across M zones`.
- [ ] `/mtlz` opens the tracker window; `/mtlz` again closes it.
- [ ] `/mtlz reset` prints `Window and section state reset.` and recentres the window.
- [ ] Log out with the window open -> log back in -> it reopens (`reopenWindow` default).

## B. The list (visit >= 3 different zones + a city + a zone with a dungeon)

- [ ] The window lists **uncollected** mounts for the current zone, grouped by source
      ("Dungeon & Raid", "Rare Drop", "Vendor", "Quest", "Zone Drop", "World Event",
      "Profession"). Groups collapse/expand and remember state.
- [ ] Header summary line reads `Zone — C / T collected · N available`, and a few seconds
      after login gains ` · a / b account`. **`GetMountInfoByID` tuple order** — if the list
      is empty, all-grey, or the counts are nonsense, that index assumption is wrong
      (Core.MountInfo / MountModel).
- [ ] Row colours: green = available now, yellow = farmable, light = plain drop,
      reddish = gated (rep/achievement), grey = reset-locked / collected. Unusable mounts
      (wrong class/faction) are dimmed, not missing (with "Dim unusable mounts" on).
- [ ] Obtainability detail text is sane: a vendor mount you can afford says "available",
      a gold cost renders as e.g. `5,000g`, a weekly farm says `farmable · weekly`.
- [ ] Hover a row -> Blizzard's mount tooltip **plus** an appended obtainability block
      ("Available now" / "Farmable now" / "Reputation needed" + detail). No taint warning.
      Confirms `GameTooltip:SetMountBySpellID`.
- [ ] Left-click a row -> Mount Journal opens to that mount. Shift-click -> spell link in
      chat. Right-click -> menu (Place map pin / Set TomTom waypoint if TomTom loaded /
      Summon if collected / Hide this mount).
- [ ] `/mtlz list` dumps the same list to chat, with a `-- Global --` divider when
      "Show global mounts" is on.
- [ ] Change zone -> list follows within ~0.3s. Stand in a city -> its vendor mounts show.
- [ ] Collect a mount (or use a known-collected one) -> its row drops out on the next
      `NEW_MOUNT_ADDED` (or shows greyed with "Show collected mounts" on).

## C. Options (`/mtlz config`)

- [ ] `/mtlz config` opens straight to the "Mount Tracker: Local Zones" panel.
- [ ] **Window** — style dropdown (Stylized/Classic) shows a /reload hint; `reopenWindow`.
- [ ] **Mount list** — `groupBy` dropdown switches the list between source and expansion
      grouping **live, no /reload**. `showCollected` / `showObtainableOnly` / `showUnusable` /
      `showGlobal` each update the window immediately.
- [ ] **Filter by source** — the checkboxes read "Show <source>". Unchecking "Show Vendor"
      hides the Vendor group; re-checking restores it; the state survives `/reload`.
      **Risk: the metatable-proxy binding** — if a box won't reflect or persist, the Settings
      API is using `rawget`/`rawset` on the bound table (Config.lua needs a plain synced
      table instead).
- [ ] **Map & minimap** — `showMinimapButton` hides/shows the button live; the two icon
      toggles clear/replace their pin set.
- [ ] **Hidden mounts** subcategory — right-click-hide a mount, open this page, it's listed
      (bucketed by source); "Restore" and "Restore all" work; empty-state text shows when
      nothing is hidden.
- [ ] Settings API 11.0.2 signature — if the panel is blank or errors, check
      `Settings.RegisterAddOnSetting(category, uniqueVar, key, tbl, "boolean"|"string", name, default)`
      and `Settings.CreateDropdown(category, setting, optionsGetter, tooltip)`.

## D. Minimap button

- [ ] Button appears on the minimap edge (mount icon). Left-click toggles the tracker;
      right-click opens the options.

## E. Map & minimap pins — the seeded rares (phase 6)

`MountData.points` is empty, so the only pins come from `Overrides.points`. Fly to each and
check the pin is roughly where the rare actually is (coords are eyeballed — fix in
`Overrides.lua` if off):

- [ ] **The Storm Peaks** — Time-Lost Proto-Drake pin (NW patrol area).
- [ ] **Deepholm** — Aeonaxx / Phosphorescent Stone Drake pin (near the Temple of Earth).
- [ ] **Azsuna** — Long-Forgotten Hippogryph pin.
- [ ] **Shimmering Expanse (Vashj'ir)** — Poseidus / Subdued Seahorse pin.
- [ ] **Spires of Arak** — Solar Spirehawk pin (near Rukhmar).
- [ ] Pin colour matches the row colour; a gated pin is visibly dimmed.
- [ ] Right-click a pin -> same menu as a row. Hover -> mount tooltip + obtainability.
- [ ] Collect one of these (or fake it) -> its pin disappears on the next `NEW_MOUNT_ADDED`.
- [ ] **HBD-Pins arg order** — if pins land in the wrong spot or not at all, re-check
      `AddWorldMapIconMap` / `AddMinimapIconMap` signatures against the vendored lib.

## F. Obtainability data spot-checks (phase 6 low-confidence)

- [ ] A **classic-rep vendor mount** (Brown/Tan Riding Camel — Ramkahen, Uldum): if you're
      Exalted it should read "available"; if not, "Reputation needed". Confirms the raw
      `currentStanding` vs `42000` encoding in `Overrides.repFaction` + `C_Reputation`.
- [ ] A **renown mount** (Tamed Skitterfly — Dragonscale Expedition Renown 25): reads
      "available" past renown 25, else the renown target. Confirms
      `C_MajorFactions.GetMajorFactionData().renownLevel`.
- [ ] A **gold vendor mount** (Traveler's Tundra Mammoth / Armored Blue Wind Rider —
      Mei Francis, Dalaran): cost renders and "available" flips on whether you can afford it
      (`GetMoney`). Dalaran is `uiMapID 125` — check the vendor pin/zone attribution.
- [ ] A **weekly instance mount** (Fiery Warhorse — Karazhan; Reins of the Raven Lord —
      Sethekk Halls): reads `farmable · weekly` / `farmable · daily`. It can never read
      "done this reset" yet (no `lockoutQuest` ids) — that's expected.

## G. Regression net

- [ ] After all fixes: `.\run-tests.ps1` -> luacheck 0/0, smoke cold+warm PASS,
      63 python tests OK.
