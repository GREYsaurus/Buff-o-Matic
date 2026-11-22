<p align="center"><img src="art/banner_1280x400.png" alt="Buff-o-Matic" width="100%"></p>

# Buff-o-Matic

A paladin blessing manager for **WoW Forever** (interface 16001). Click one **Smart Bless** button and it buffs the next party member who needs one of *your* blessings. Each time it picks the best blessing that another paladin isn't already providing.

- **One physical click = at most one cast.** Nothing is ever cast automatically.
- **Fair rotation** through the party, tracked by GUID so it survives slot reordering, joins and leaves.
- **Never duplicates or overwrites another paladin's blessing**, including when theirs is expiring.
- **Stable assignments:** your healthy blessing isn't swapped out just because someone else's buffs changed.
- Role-safe defaults with per-player, per-class and per-role overrides.
- Timers, a **Rebuff soon** warning with an optional sound, a separate **Missing blessing** state, and an optional view of other paladins' expiring blessings.
- Optional, safety-checked **Greater Blessing** mode.

> Research notes and every source are in [RESEARCH.md](RESEARCH.md).

## Installation
1. Copy the `BuffOMatic` folder into
   `World of Warcraft\_forever_\Interface\AddOns\`.
   The result should be `...\AddOns\BuffOMatic\BuffOMatic.toc`.
2. Restart the game, or `/reload`. Enable **Buff-o-Matic** in the AddOns list on the character screen.
3. Log in on a paladin. The window appears near the center of the screen; drag it wherever you like.

## Usage
- **Left-click the big button.** It casts the blessing shown next to it on the player shown. The window always shows exactly what the button will do.
- Hover the button or any member row to see why that blessing was chosen, and why higher-priority ones were skipped (for example, "Kings already supplied by Oren").
- **Status line:**
  - **Missing blessing: N**: members who still need one of your blessings.
  - **Shortest**: the shortest remaining timer among *your* intended blessings. It turns into **Rebuff soon** below 5:00.
  - **N uncertain**: members whose buffs can't be read. They are never auto-buffed.
- When everyone is covered, the button says **"Party buffed — nothing to cast."**

### Combat
WoW Forever hides aura data from addons during combat ("secret values"), and secure buttons can't be reconfigured in combat. So:
- **Smart cycling works out of combat only.** In combat the button does nothing and says *"Smart cycling available out of combat."* It re-arms automatically when combat ends.
- Optional `/bfm buttons on` makes each member row a manual secure button. Clicking a row casts that member's assigned blessing, including in combat. These buttons are bound to party slots at the moment combat starts; if the party changes mid-fight, the rows are flagged stale until combat ends.

### Rebuff timing
| Remaining | Behaviour (defaults) |
|---|---|
| missing | eligible immediately |
| < 10:00 | eligible to refresh (9:59 yes, **10:00 no**) |
| < 5:00 | **Rebuff soon** warning (4:59 yes, **5:00 no**) |

Forever blessings last 60 minutes, so these rules apply literally. If a blessing's full duration is ever 10 minutes or less, a **short-duration policy** takes over to prevent a rebuff loop: refresh below 20% of the full duration, warn below 10%. The window then shows the effective thresholds. A 30-second grace period after each successful cast blocks immediate re-refreshes.

## Default priorities (editable)
These are judgment calls, not objective truth. Kings is the safe pick when a role is unknown. Wisdom is automatically dropped for classes without mana, and Might is never given to pure casters.

| Class | Tank | Healer | Damage | Unknown role |
|---|---|---|---|---|
| Warrior | Kings > Might | – | Might > Kings | Kings > Might |
| Rogue | – | – | Might > Kings | Might > Kings |
| Hunter | – | – | Kings > Wisdom > Might | Kings > Wisdom > Might |
| Mage / Warlock | – | – | Kings > Wisdom | Kings > Wisdom |
| Priest | – | Wisdom > Kings | Kings > Wisdom | Kings > Wisdom |
| Druid | Kings > Might | Wisdom > Kings | Kings > Might > Wisdom | Kings > Wisdom > Might |
| Paladin | Kings > Wisdom > Might | Wisdom > Kings | Might > Kings > Wisdom | Kings > Wisdom > Might |
| Shaman | – | Wisdom > Kings | Kings > Might > Wisdom | Kings > Wisdom > Might |

Roles come from the group role (`UnitGroupRolesAssigned`). When no role is set, the "unknown" column applies. Correct it with `/bfm role`. Forever has no threat-reducing blessing (Salvation was removed), but the engine is built to never auto-cast one on a tank if one is ever added.

## Slash commands (`/bfm` or `/buffomatic`)
| Command | Effect |
|---|---|
| `/bfm` | help |
| `/bfm show`, `hide`, `lock`, `unlock`, `scale 1.2` | window |
| `/bfm self on\|off` | include yourself in the rotation (default on) |
| `/bfm assign <name> <kings\|might\|wisdom\|auto>` | pin a blessing to a player (stable, manual coordination) |
| `/bfm role <name> <tank\|healer\|dps\|auto>` | correct a player's role |
| `/bfm prio <name> kings,might` / `auto` | per-player priority list |
| `/bfm classprio WARRIOR DAMAGER kings,might` / `default` | per-class/role priority |
| `/bfm exclude <name> on\|off` | leave someone out entirely |
| `/bfm greater on\|off` | Greater Blessing mode (default off) |
| `/bfm sticky on\|off` | keep your healthy existing blessing (default on) |
| `/bfm refresh <min>`, `warn <min>`, `grace <sec>`, `shortpct 0.2`, `shortwarnpct 0.1` | timing |
| `/bfm sound`, `chat`, `others`, `members`, `buttons` `on\|off` | alerts and display |
| `/bfm raid on\|off` | rotate through the whole raid (default: your subgroup) |
| `/bfm table` | print the effective priority tables |
| `/bfm reset` / `/bfm resetall confirm` | reset position and rotation / everything |
| `/bfm debug on\|off`, `/bfm diag` | debugging and a full state dump |

## Greater Blessings (optional)
Off by default, because a Greater Blessing hits **every member of that class** in the group. It is only used when all of these hold:
- you know the Greater spell, have a Symbol of Kings, and have the mana for it
- every same-class member wants the **same** blessing (mixed roles mean no Greater)
- none of them has that blessing from another paladin
- none of them is pinned to a different blessing or excluded
- at least two of them need it

Otherwise you get the normal single-target blessing.

## Limitations
- **No in-combat smart cycling.** The client hides the data it would need and locks the button.
- It doesn't speak PallyPower's assignment protocol. It reacts to actual buffs and leaves other paladins' blessings alone. Use `/bfm assign` to coordinate.
- Raid support works but is secondary: by default only your subgroup rotates, though Greater-Blessing safety checks always look at the whole raid.
- Unverified Forever details are listed in RESEARCH.md: lower-rank spell IDs, Greater/normal overwrite rules, and aura secrecy inside instances.

## Development
```
pip install lupa
python tests/run_tests.py
```
- `tests/run.lua`: 25 tests of the pure decision engine, thresholds, scheduler, cast state machine, Greater safety and combat guard. They cover all 22 scenarios from the spec.
- `tests/smoke.lua`: loads every addon file in TOC order against a mocked WoW API and simulates a full session (65 checks).
- `tools/make_logo.py` regenerates the logo, icon and banner (needs Pillow).
- Manual in-game checklist: [TESTING.md](TESTING.md).

## License
MIT. See [LICENSE](LICENSE).
