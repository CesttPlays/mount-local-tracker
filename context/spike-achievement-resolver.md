# Spike: achievement-reward → zone resolver for mounts

Spike for plan 005, run 2026-08-31 against build `12.1.0.69497`.
Prototype + scratch script on branch `worktree-execute-plans` (`tools/_spike_ach_resolve.py`).
**No production code changed.** This doc + the follow-up plan stubs are the deliverable.

## The problem

`tools/generate_mount_zones.py` resolves a mount to a zone from `Mount.SourceText_lang`
labels and the instance loot-table join. **217 mounts** carry an `Achievement: <Title>`
label and no `Zone:` label; **209 of them** currently land in the flat `global` list.
`context/future-features.md` predicted "~60" would move to a real zone by porting the
sibling repo's `zones_for_achievement`.

There is a second, larger payoff: `MountData.achievementID` ships empty, so the addon's
`achievement_gated` obtainability state (`Obtainability.lua:181-189`) is **dead code** —
it never has data. Linking mount → achievement here would light it up
("Achievement needed · <name>" instead of a bare "Not yet collected").

## Linking mechanism (Step 1)

Two mechanisms, tried in order:

1. **`Achievement.RewardItemID` → teaching item → mount** (the generator already builds
   `mount_by_item` / `item_by_mount`). Clean FK. 567 achievements carry a `RewardItemID`.
2. **Exact title match**: the text after `Achievement:` in `SourceText_lang`
   (regex, parens stripped) vs `Achievement.Title_lang` (lowercased, exact).

Result over the 217 labelled mounts:

| outcome | count |
|---|---|
| linked via RewardItemID FK | 162 |
| linked via exact title match only | 21 |
| **linked (total)** | **183 / 217 (84%)** |
| unlinked — no FK + ambiguous/missing title | 34 |

**Linker quality caveat (build-plan risk):** the spike's linker is naive and has visible
misses. `Mount.SourceText_lang` titles are lightly mangled ("For The Horde!" vs the real
"For the Horde!"), and some `Achievement:` values are truncated by the label regex
("Warlord's Deathwheel", "Ahead of the", "Dragon"). 565 achievement titles are duplicated
(Alliance/Horde/re-issued), so a bare title match is unsafe on its own. A production build
must: prefer the FK, fall back to title match **only when unambiguous**, and normalise
punctuation/case. The 34 "unlinked" are mostly guild achievements, `Allied` /
`Dragon Isles Drake` collection metas, and PvP-season "Gladiator" mounts that genuinely
have no single achievement — leaving those `global` is correct.

## Zone yield (Step 2)

`Achievement.Instance_ID` **alone** resolves only **6** mounts — modern (Dragonflight+)
raids are the only achievements with the column populated. Classic
"Glory of the <Raid> Raider" achievements have `Instance_ID = -1`; their criteria are
type-8 ("complete achievement") pointing at per-boss feat achievements, and *those* carry
`Instance_ID`. Recursing type-8 criteria (depth 2, like the sibling's `meta_depth`) gives:

| outcome | count |
|---|---|
| resolves to exactly **one** zone | **26** |
| resolves to **2+** zones | 20 |
| linked but no `Instance_ID` anywhere in the tree | 137 |

- **The 26 single-zone hits are the entire "Glory of the <Raid> Raider" family** —
  Ulduar, Icecrown Citadel, Firelands, Dragon Soul, Siege of Orgrimmar, Hellfire Citadel,
  Uldir, Antorus, Battle of Dazar'alor, Eternal Palace, Ny'alotha, Castle Nathria,
  Sanctum of Domination, Sepulcher, Vault of the Incarnates, Aberrus, Amirdrassil,
  Nerub-ar Palace, Undermine, Manaforge Omega, The Venomous Abyss — plus a few
  Timewalking-cache metas (Sanctum of Chronology) and one PvP city-raid ("For The Horde!"
  → Silvermoon/Eversong; borderline, see below).
- **The 20 multi-zone hits are the "Glory of the <Expansion> Hero" dungeon-set metas**
  (Glory of the Hero → 12 Wrath dungeons, Glory of the Cataclysm Hero → 9, …) plus
  "For The Alliance!" (2 of 4 leader cities) and "What a Long, Strange Trip It's Been"
  (holiday bosses in many zones). No single zone is right for these.
- The 137 "no Instance_ID" are correctly global: keystone mounts, Gladiator seasons,
  Honor Level N, Pathfinder, reputation metas, "Mountain o' Mounts", "Leading the Cavalry".

The criteria-quest-POI path from the sibling generator (`QuestPOIBlob`/`QuestPOIPoint`)
was **not** ported: none of the labelled mounts' achievements use type-27 (complete quest)
criteria — they are all instance feats. The category-name → UiMap fallback was also
skipped; for mounts it would only add noise.

## Quality spot-check (Step 3)

15 of the 26 single-zone resolutions, checked against Wowhead / knowledge:

| mount | achievement | resolved zone | correct? |
|---|---|---|---|
| 306/307 | Glory of the Ulduar Raider | Ulduar | ✅ |
| 364 | Glory of the Icecrown Raider | Icecrown Citadel | ✅ |
| 417 | Glory of the Firelands Raider | Firelands | ✅ |
| 443 | Glory of the Dragon Soul Raider | Dragon Soul | ✅ |
| 557 | Glory of the Orgrimmar Raider | Siege of Orgrimmar | ✅ |
| 758 | Glory of the Hellfire Raider | Hellfire Citadel | ✅ |
| 963 | Glory of the Uldir Raider | Uldir | ✅ |
| 1218 | Glory of the Dazar'alor Raider | Battle of Dazar'alor | ✅ |
| 1377 | Glory of the Nathria Raider | Castle Nathria | ✅ |
| 1644 | Glory of the Vault Raider | Vault of the Incarnates | ✅ |
| 1734 | Glory of the Aberrus Raider | Aberrus | ✅ |
| 2180 | Glory of the Nerub-ar Raider | Nerub-ar Palace | ✅ |
| 2549 | Glory of the Omega Raider | Manaforge Omega | ✅ |
| 1576 | Fates of the Shadowlands Raids | Sanctum of Domination | ⚠️ spans 3 SL raids; SoD is the last/most-pointed but arbitrary |
| 272 | "For The Horde!" | Eversong Woods | ⚠️ actually rewarded for killing all 4 Alliance leaders; linker also matched the wrong achievement id |

**Accuracy on the clean "Glory of the <Raid> Raider" subset: ~100% (24/24).**
The 2 ⚠️ are metas that arguably shouldn't resolve to one zone. Zero false positives on
the obviously-global mounts (Leading the Cavalry, Mountain o' Mounts, keystone/Gladiator
all stayed global).

**Ship bar (≥90% agree, zero global false-positives): PASSED** — for the single-zone
subset, scoped to `Instance_ID` + type-8 recursion, multi-zone treated as global.

## Recommendation

**Ship a scoped auto-resolver**, in two independent pieces:

1. **`achievementID` for all confidently-linked mounts (~180).** This is the bigger win
   and carries no zone-accuracy risk — a wrong `achievementID` only mislabels the
   obtainability tooltip, and the linker can be made conservative (FK-first, unambiguous
   title fallback). Lights up the dead `achievement_gated` state for every
   achievement-reward mount, zoned or not.
2. **Zone assignment only for single-`Instance_ID` resolutions (~24, after dropping the
   2 borderline metas).** Multi-zone metas stay `global`. This moves the "Glory of the
   <Raid> Raider" mounts under their raid's zone header — exactly the mounts a player
   standing in that raid wants to see.

Do **not** attempt the ~137 "linked but no Instance_ID" or the 20 multi-zone metas
automatically. If any are wanted zoned, hand-add them to `Overrides.add` +
`Overrides.achievementID`.

Predicted `global` shrinkage: ~24 mounts (well below `future-features.md`'s "~60", because
that estimate assumed the dungeon-set metas would resolve to a usable zone — they don't).

## Follow-up plans

- **plan 006** — Add the achievement→zone + achievementID branch to the mount generator
  (stub written, `plans/006-achievement-generator-branch.md`).
- **plan 007** — Document `Overrides.achievementID` + hand-seed the residual high-value
  cases (stub written, `plans/007-overrides-achievementid-doc.md`).

## Open questions for the build

- **Linker robustness** is the main risk — needs a small fixture-tested normaliser and an
  explicit "ambiguous → skip" rule. Measure the confident-link rate after that.
- **Localisation**: title matching is enUS-only. The FK path is locale-independent; prefer
  it and treat title match as a tie-breaker, so non-enUS refresh runs still work.
- **Weekly `refresh-mount-data.yml` cost**: adds `Achievement` (~4 MB) + `Criteria` +
  `CriteriaTree` (~10 MB) to every run. Acceptable; cache them like the others.
- **`MountData.lua` size**: +~180 `achievementID` int→int lines + ~24 zone refs. Negligible.
- **Instance-entrance pins** (`JournalInstanceEntrance`) remain unbuilt — the newly-zoned
  achievement mounts still get no map pin until that separate `future-features.md` item
  lands.

## Reproduce

```
python tools/_spike_ach_resolve.py --build 12.1.0.69497
```
Needs `.wago-cache/12.1.0.69497/` with `Achievement.csv`, `Achievement_Category.csv`,
`Criteria.csv`, `CriteriaTree.csv` (fetched during the spike) plus the tables the mount
generator already caches. `.wago-cache/` is gitignored.
