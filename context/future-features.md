# Future Features - Nice to Have

Deferred ideas. Do not implement ahead of the current blocker in `immediate-next-steps.md`.

- **Instance-entrance positions** for dungeon/raid drop mounts (`JournalInstanceEntrance` →
  coords), so instance mounts get a map pin instead of being position-less. The sibling repo
  left the equivalent (dungeon-entrance achievement pins) unbuilt.
- **More `groupBy` modes** — by mount type (ground / flying / aquatic / dynamic), by
  collected-vs-not, by drop-rate tier.
- **Drop-rate / source hints in the tooltip** — "~1% from Silithus rares", curated in
  `Overrides.lua`.
- **Account-wide vs per-character view** — mount collection is account-wide; a toggle to
  also flag mounts unusable by the current character (class/faction/riding-skill gated).
- **"Nearby" mode** — when standing near a known rare-spawn point, surface that mount
  prominently (needs curated coords + a proximity check, like the sibling's minimap pins).
- **Pet / toy siblings** — the same zone-local treatment for battle pets and toys. Separate
  addons or optional modules; out of scope for v1.
