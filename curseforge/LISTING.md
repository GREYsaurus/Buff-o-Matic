# CurseForge listing: Buff-o-Matic

## Fields
- **Name:** Buff-o-Matic
- **Summary** (short, shown in search results):
  One click, next player, best blessing nobody else gave. A smart paladin blessing button for WoW Forever.
- **Primary category:** Buffs & Debuffs
- **Additional categories:** Class: Paladin; Combat
- **License:** MIT License
- **Source:** https://github.com/GREYsaurus/Buff-o-Matic
- **Issues:** https://github.com/GREYsaurus/Buff-o-Matic/issues
- **Logo / avatar:** art/logo_400.png
- **Banner / description image:** art/banner_1280x400.png
- **File:** dist/BuffOMatic-1.0.0.zip, game version WoW Forever 1.60.1, release type Release

## Description

![Buff-o-Matic](https://raw.githubusercontent.com/GREYsaurus/Buff-o-Matic/main/art/banner_1280x400.png)

**Stop juggling blessings.** Buff-o-Matic gives paladins one **Smart Bless** button. Each click casts the right blessing on the next party member who needs one, and it never steps on another paladin's blessing.

Built specifically for **WoW Forever** (60-minute blessings; Might, Wisdom and Kings; the modern addon API).

### How it works
- **One click = one cast.** It never casts automatically.
- **Fair rotation:** each click moves to the next player who needs a blessing from you. Healthy buffs are skipped.
- **No duplicates:** if another paladin already gave someone Kings, you give them something else. Hover a row and it tells you who supplied what.
- **Never overwrites other paladins**, even when their blessing is about to expire.
- **Stable assignments:** your healthy blessing isn't swapped out just because another paladin's buffs changed.
- **Smart defaults:**
  - Kings when a role is unknown
  - Might for physical damage dealers
  - Wisdom for healers
  - no Wisdom for classes without mana
  - no Might for pure casters

### At a glance
- Shows the next target and blessing, plus *why* it was chosen
- **Missing blessing** count and **shortest timer** for your blessings
- **Rebuff soon** warning below 5:00, with an optional sound (it plays once, not on repeat)
- Optional list of other paladins' expiring blessings
- Tooltips on every party member: role, priority, your blessing, others' blessings

### Key binding, options and minimap button
- Bind **Smart Bless** to a key (Keybindings > AddOns): one press, one cast.
- A full **options panel** (Options > AddOns > Buff-o-Matic, or `/bfm options`).
- A **minimap button** and **addon compartment** entry.
- **Ready-check reminder:** a sound, a chat line and a flashing window when someone still needs your blessing.

### Works with PallyPower
If the other paladins use **PallyPower**, Buff-o-Matic reads their assignments, read-only:
- whatever they are assigned to give, you leave to them
- whatever PallyPower assigns *you* becomes your default

Buffs actually on players always come first, so you never overwrite anyone.

### Roles and overrides
Roles come from the party role icons (Group Finder or Set Role). Solo, your own talent spec is used. **Right-click any member** to set their role, pin a blessing, or exclude them.
Slash commands: `/bfm` (or `/buffomatic`). Examples:
- `/bfm role me tank`
- `/bfm assign Brann kings`
- `/bfm classprio WARRIOR DAMAGER kings,might`
- `/bfm diag`

### Rebuff timing
- Missing: cast immediately
- Under 10:00 left: eligible to refresh
- Under 5:00 left: "Rebuff soon" warning

All thresholds are configurable.

### Greater Blessings (optional)
Turn on with `/bfm greater on`. Greater Blessings are used only when it's safe for **everyone** of that class:
- they all want the same blessing
- none of them has it from another paladin
- none of them is pinned to something else
- you have a Symbol of Kings

Otherwise it falls back to single-target blessings.

### Combat
WoW Forever hides buff information from addons in combat. Smart cycling therefore works **out of combat** and re-arms the moment combat ends. In combat the button safely does nothing: no "action blocked" errors. Optional per-member buttons (`/bfm buttons on`) let you cast a member's assigned blessing manually in combat.

### Notes
- Paladins only. Party first; raids are supported (your subgroup by default, `/bfm raid on` for everyone).
- PallyPower support is read-only: Buff-o-Matic follows PallyPower plans but doesn't publish its own.
- Open source (MIT): https://github.com/GREYsaurus/Buff-o-Matic. Bug reports are welcome; please include the output of `/bfm diag`.
