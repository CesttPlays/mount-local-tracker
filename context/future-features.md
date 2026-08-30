# Future Features - Nice to Have

Deferred ideas. Do not implement ahead of the current blocker in `immediate-next-steps.md`.

## Data / generator

- **Achievement-reward mount -> zone resolver.** Mounts with an `Achievement:` source and no
  `Zone:` currently land in `global` (~60 of them). Port the sibling repo's achievement ->
  zone resolver (`generate_zone_achievements.py`: criteria-quest POI + `Achievement.Instance_ID`
  + category-name fallback) and emit `achievementID[mountID]` + the zone.
- **Instance-entrance positions** for dungeon/raid drop mounts (`JournalInstanceEntrance` ->
  coords) so instance mounts get a real map pin instead of no position. The sibling left the
  equivalent (dungeon-entrance achievement pins) unbuilt. `Overrides.points` covers a few by
  hand for now.
- **`lockoutQuest` ids** — the hidden quests that flag a daily/weekly mount farm as done this
  reset, so `Obtainability` can show "done this reset" instead of a bare "farmable · weekly".
  Datamine or hand-collect them into `Overrides.lockoutQuest`.
- **Vendor cost / rep-requirement from DB2** — if `NpcVendor` / faction-requirement tables
  turn out to be in the wago export set for retail, fill `vendor` / `repFaction` from the
  generator instead of curating each one in `Overrides.lua`.
- **Variant-map dedup** — collapse the per-expansion/phase UI-map copies of one real zone so
  the `zones` table (and the "293 zones" count) reflects real zones. Needs a runtime
  live-map -> canonical-id resolution, or a canonical-id table in `MountData.lua`.

## Runtime / UI

- **More `groupBy` modes** — by mount type (ground / flying / aquatic / dynamic), by
  drop-rate tier, by collected-vs-not.
- **Drop-rate / source hints in the tooltip** — beyond the curated `Overrides.dropChance`
  string, e.g. "1-in-4 vendor rotation" or a live "you're 3 renown away" line.
- **Full non-zone catalog browse** — `/mtlz all` with the catalog-style filters, so the
  addon can double as a MissingMounts-style browser. Deliberately deferred to protect the
  zone-local identity.
- **Account-wide vs per-character view** — mount collection is account-wide; a clearer
  toggle for "also flag mounts this character can't ride" beyond the current `showUnusable`.
- **"Nearby" mode** — when standing near a known rare-spawn point, surface that mount
  prominently (proximity check on curated coords).
- **Pet / toy siblings** — the same zone-local treatment for battle pets and toys. Separate
  addons or optional modules; out of scope for v1.
