# Buff-o-Matic research notes

**Target client:** WoW Forever (Blizzard, launched Nov 2026). Patch 1.60.1, builds 70790 to 71037, `## Interface: 16001`.
**Research date:** 2026-11-22. Forever is new and was hotfixed heavily before launch, so re-check anything marked *unverified* after major patches.

Legend: **Verified** means at least two independent sources agree, or the fact comes from Blizzard or client data. **Single-source** means one credible source. **Judgment** means a design choice, not a game fact.

---

## 1. Client and API

| Fact | Status | Source |
|---|---|---|
| Forever runs the modern (12.x / Midnight) engine, not the 1.15 Classic API | Verified | Atraeau/WoW-Addons `vendor/forever-compat-patches.md`; warcraft.wiki.gg TOC format page |
| `## Interface: 16001` (patch 1.60.1) | Verified | PallyPower `PallyPower_Camelot.toc`; Atraeau `wow-dev.config.json`; **the user's own installed Forever addons** (Bartender4, Auctionator, Baganator, BigWigs and DBM all list 16001 in a base `.toc`) |
| `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (value 18) | Single-source (Questie docs, RealUI notes) | github.com/Questie/Questie `docs/forever-development.md` |
| `C_UnitAuras.GetAuraDataByIndex`, `C_Spell.*`, `C_SpellBook.IsSpellKnown`, `IsPlayerSpell`, `UnitGroupRolesAssigned`, `C_Item.GetItemCount` exist | Verified | Atraeau generated `api.json` (client APIDocumentation dump, build 70790); Gethe/wow-ui-source `forever` branch |
| Legacy globals `UnitAura`, `UnitBuff`, `GetSpellInfo`, `GetItemCount` are **absent** | Verified | Atraeau `api.json`; PallyPower `Compat.lua` shims them |
| **Secret Values** are active. In combat, encounters and some instances, aura data, unit identity, GUIDs and spellcast IDs may be opaque. Comparing or doing arithmetic on them errors for addon code. `issecretvalue()` exists. | Verified | warcraft.wiki.gg/wiki/Secret_Values; Atraeau notes; PallyPower `Compat.lua` / `FOREVER_PORT.md` |
| Exactly which aura fields are secret out of combat inside instances | **Unverified** | No source documents this per field. Buff-o-Matic guards every field. |
| `SecureActionButtonTemplate` reads `useOnKeyDown` and falls back to the `ActionButtonUseKeyDown` CVar, which defaults to on | Verified (client source) | wow-ui-source `forever` branch, `SecureTemplates.lua` |
| Protected attributes cannot be changed in combat. A frame parenting secure buttons can't be moved or hidden in combat | Long-standing WoW rule | warcraft.wiki.gg "Secure Execution and Tainting" |

**Consequences for the design:**
- Smart cycling runs **only out of combat**. In combat, aura data may be secret, so a "who needs what" decision is impossible, and attributes are locked anyway. A secure state driver clears the main button when combat starts.
- Every value from a restricted API goes through `issecretvalue` before any comparison (`Compat.lua`, `Auras.lua`).
- The base `BuffOMatic.toc` has Interface 16001. No `_Camelot.toc`: one porter reported SavedVariables not loading with that suffix during beta, and your installed addons all use a base TOC.

## 2. Blessing mechanics on Forever

| Fact | Status | Sources |
|---|---|---|
| Long blessings are **Might, Wisdom and Kings** only, each with a Greater version | Verified | Blizzard pre-launch dev notes, via warcrafttavern.com/forever/news/wow-forever-pre-launch-class-changes-bug-fixes/; foreverchanges.pro/spellbook/paladin; zockify.com/forever/paladin/ |
| **Removed:** Blessing of Light, Sanctuary, Salvation, and beta-only "Salvation", "Mass Salvation" and "Revoke" | Verified | Same dev notes; kami-labs.fr Oct 30 hotfix summary; Wowhead Forever returns 404 for 1038, 25895 and 19977; PallyPower CHANGELOG v11.05 |
| Single **and** Greater blessings last **60 minutes** (Classic: 5 and 15 min) | Verified | foreverchanges.pro/class/paladin; Wowhead Forever spell pages; PallyPower `PallyPowerValues.lua` (`60*60` for both) |
| Kings is trained at level 20 and is no longer a talent. Greater Kings at 60 | Verified | foreverchanges, conquestcapped, zockify, Blizzard deep-dive (worldofwarcraft.blizzard.com/news/24302099) |
| Might: 7 ranks, max +133 AP. Greater Might: 2 ranks (52+) | Verified (Wowhead Forever 25291 / 25916) | One foreverchanges tooltip says 112 AP; its changelog and Wowhead say 133 |
| Wisdom: 6 ranks, max 40 mp5. Improved Wisdom is now baseline. Greater Wisdom: 2 ranks (54+) | Verified | Wowhead Forever 25290 / 25918; Blizzard deep dive |
| Improved Blessing of Might/Wisdom talents removed | Verified | foreverchanges; Blizzard deep dive |
| Greater blessings consume **Symbol of Kings** (21177) and hit **every member of the target's class** in the party/raid | Verified (spell data) / long-standing mechanic | Wowhead Forever 25898 / 25916 / 25918; warcrafttavern paladin guide |
| **One blessing per paladin per target.** Blessings from different paladins stack | Verified | Spell tooltip text quoted by foreverchanges, warcrafttavern and loreforever |
| Same family from two paladins can't coexist (stronger or newer overwrites). Greater and normal of one family replace each other | **Unverified on Forever** (Classic behaviour) | No Forever source covers this. Buff-o-Matic treats normal and Greater as one family and never casts over another paladin's family, which is safe either way. |
| Spell IDs are the Classic IDs | Verified for max ranks (Wowhead Forever serves 20217, 25898, 25291, 25916, 25290, 25918). **Lower ranks unverified** | PallyPower's Forever port also uses the Classic IDs |
| Tactical blessings: Protection (1022/5599/10278, 10 s), Freedom (1044, 10 s), Sacrifice (6940/20729, 30 s) | Verified | foreverchanges spellbook. **Never** used as maintenance buffs |
| Holy's Oath of Light (1328548, 5 min, single target) is a talent, not a blessing | Single-source (PallyPower source) | Not handled |
| Campfire buffs (Fish Bowl ≈ Kings, Lodestone ≈ Might) don't stack with the paladin buff | Fan guides only, no spell IDs | Hook provided (`Blessings.EQUIVALENT_EFFECTS`), left empty on purpose |
| Battle Shout vs Might stacking | Stack in Classic. **Unverified on Forever** | Not treated as exclusive |

### The duration edge case
You asked for "refresh when under 10:00" and "warn when under 5:00". Every Forever blessing lasts 60 minutes, so the literal rule is safe and is what Buff-o-Matic uses.

The short-duration policy still exists as a guard against a future hotfix (Classic had 5-minute single blessings, which would refresh instantly under a literal 10-minute rule). If a blessing's full duration is 10 minutes or less:
- refresh below `min(10:00, 20% of full)`
- warn below `min(5:00, 10% of full)`

A 30-second grace period after each successful cast also blocks immediate re-refreshes. The UI shows the effective thresholds whenever the policy applies. All values are configurable (`/bfm shortpct`, `/bfm shortwarnpct`, `/bfm grace`).

## 3. Reference implementation: PallyPower (Forever port)

AznamirWoW/PallyPower at commit 7510a3bd (2026-11-22). Its Forever port (by Pallyblaze and Laxativum) was merged into the main repo. What I learned from it:
- Detects Forever with `toc >= 16000 and < 17000` or an unknown project ID.
- Reads auras with `C_UnitAuras.GetAuraDataByIndex` inside `pcall`, guards every value with `issecretvalue`, caches expiry per GUID, and counts down in combat.
- Its secure buttons use `type=spell` plus `unit` and `spell` attributes, and every attribute write is guarded by `InCombatLockdown`.
- Default class templates still list Salvation. On Forever they are filtered out by `IsSpellKnown`, so Buff-o-Matic built its own Forever-specific table rather than copying them.

Buff-o-Matic does **not** speak the PallyPower sync protocol, so it can't see other paladins' *assignments*, only their actual buffs. That's what the stability logic below is for.

## 4. Design decisions (judgment)

- **Sticky ownership:** if your blessing on someone is healthy and still useful, it stays even when a higher-priority family frees up (for example, another paladin's Kings expires). Re-evaluation happens only when your blessing is missing or due for refresh. This stops oscillation, and an expiring blessing from another paladin is never treated as permission to take over.
- **Unknown caster** (secret `sourceUnit`) or **unreadable auras:** the member is marked *uncertain* and never auto-buffed. **Unknown remaining time** on your own blessing counts as healthy-but-unknown, neither missing nor infinite.
- **`sourceUnit == nil`** with `isFromPlayerOrPlayerPet ~= true` is treated as another paladin outside your group. Your own blessings always resolve to `"player"`.
- **Failures:** a click that never produces `UNIT_SPELLCAST_SENT` within 1 second, or a cast that reports FAILED or INTERRUPTED, counts as a failure. Two failures in a row put that member on a 10-second backoff. The cursor advances only on `UNIT_SPELLCAST_SUCCEEDED` matched by castGUID.
- **Priorities:** see `BuffOMatic/Data/Priorities.lua` and the README. They are explicitly opinions.

## Sources
- Blizzard Forever class deep dive: https://worldofwarcraft.blizzard.com/news/24302099
- Pre-launch dev notes (as reproduced): https://www.warcrafttavern.com/forever/news/wow-forever-pre-launch-class-changes-bug-fixes/
- https://foreverchanges.pro/class/paladin and https://foreverchanges.pro/spellbook/paladin
- https://foreverdiff.com/spells/salvation-1038/ (beta Salvation, later removed)
- https://theforeverera.com/en/spells/paladin/greater-blessing-of-salvation/
- https://www.zockify.com/forever/paladin/
- https://conquestcapped.com/guides/wow-forever/wow-forever-paladin-overview/
- https://kami-labs.fr/en/wow-forever/patch-notes-wow-forever-30-octobre-gagnants-perdants/
- Wowhead Forever spells: https://www.wowhead.com/forever/spell=20217 (also 25898, 25291, 25916, 25290, 25918)
- https://loreforeverwow.com/guides/wow-forever-paladin-auras-blessings-and-seals-guide (beta-era; its Light and Salvation info is outdated)
- https://warcraft.wiki.gg/wiki/TOC_format, https://warcraft.wiki.gg/wiki/Secret_Values
- https://github.com/Atraeau/WoW-Addons (Forever API dump), https://github.com/Gethe/wow-ui-source (branch `forever`)
- https://github.com/AznamirWoW/PallyPower (Forever port)
- https://github.com/Questie/Questie/blob/master/docs/forever-development.md
