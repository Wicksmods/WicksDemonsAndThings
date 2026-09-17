# Wick's Demons and Things - Changelog

## 1.0.0 - 2026-09-17 (Forever)

### Rebuilt as a loadout kit on WickCore

Forever inherits Midnight's addon rules, so the cooldown and proc tracker is
gone: those values are secret in combat. The soul bar, pet bar and shard
counter carry over on WickCore's dialect shim, and the kit gains the talent
layer, a pre-pull checklist and a racials row.

- Requires WickCore. Interface 16001.
- Settings move into a WickCore profile.
- Cooldown tracker removed. Cooldown display on the bars passes secret values
  straight to the widget and never compares them.
- Aura reads route through WickCore's guard and return nothing while blocked.
- Shard counter falls back to the soul shard resource when the bag count is zero.
- Talents: export, import, save, apply, through Blizzard's own parser.
- Pre-pull checklist and racials in the kit panel (/wdt kit).
- Minimap launcher and a page under Options, Wick's Mods.

## 0.1.1 (TBC)

Previous TBC Anniversary builds lived in the deployed AddOns folder only.
