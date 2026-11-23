# Testing Buff-o-Matic

## Automated tests (run offline)
`python tests/run_tests.py` (needs `pip install lupa`) runs both suites under an embedded **Lua 5.1**, the same Lua version WoW uses.

| # | Scenario | Covered by |
|---|---|---|
| 1-4 | best missing / 2nd best / 3rd best / all supplied | run.lua 01-04 |
| 5-8 | 9:59 refresh, 10:00 not, 4:59 warns, 5:00 doesn't | run.lua 05-08 |
| 9 | short-duration policy, no loop, no instant warning, grace | run.lua 09 |
| 10-11 | other's expiring buff untouched; healthy fallback not refreshed | run.lua 10-11 |
| 12-13 | tank threat-reduction guard; unknown role + overrides | run.lua 12-13 |
| 14-17 | failed cast no advance; unreachable skipped; GUID vs slot; propagation delay | run.lua 14-17 + smoke 5-7 |
| 18-19 | normal/Greater equivalence; Greater protected-assignment safety | run.lua 18-19 + smoke 10 |
| 20 | no protected changes in combat | run.lua 20 + smoke 4 (the mock errors on any in-combat SetAttribute) |
| 21 | unknown caster / remaining time conservative | run.lua 21 + smoke 8 |
| 22 | fair cycling | run.lua 22 + smoke 1 |

**What these prove:** the addon's own logic and Lua run correctly. **What they don't prove:** that the real Forever client behaves like the mock. Real API return shapes, secret-value behaviour, secure-template click handling and the TGA icon can only be confirmed in game.

## Manual in-game checklist
Turn on `/bfm debug on` during testing and use `/bfm diag` to dump state.

**Setup and loading**
- [ ] The AddOns list shows Buff-o-Matic with its icon and is **not** marked "out of date".
- [ ] On a paladin the window appears. On another class you get a chat message and no window.
- [ ] `/bfm diag` shows interface 16001, `Forever=true`, and the blessings you know (with Symbol of Kings count).

**Solo**
- [ ] With no buffs, the button shows *Kings → you* (or your first known blessing). One click casts it.
- [ ] Clicking again right away does nothing (Party buffed). There's no second cast and no error.
- [ ] `/bfm self off` leaves you out of the rotation and shows "Party buffed".

**Party, single paladin** (a two-person party is enough)
- [ ] Clicks go through members in order, one cast per click, then "Party buffed".
- [ ] The text next to the button always matches who actually receives the cast.
- [ ] Out-of-range or dead member: skipped, others still get buffed, and the row shows the reason.
- [ ] Out of mana: no cast, the cursor doesn't advance, and the next click retries.
- [ ] Rearrange party slots (or someone leaves and rejoins) right before clicking: the cast still goes to the person named.
- [ ] Wrong-class buffs: the mage gets no Might, the rogue and warrior get no Wisdom.

**Two paladins** (the most important test)
- [ ] The other paladin gives Kings to X. Your button offers X a *different* blessing, and the tooltip says "Kings already supplied by …".
- [ ] Wait until their Kings drops below 10:00 (or have them recast at low rank). You don't take over Kings, and your healthy blessing on X isn't refreshed.
- [ ] With `/bfm others on`, their expiring blessings are listed.
- [ ] `/bfm assign X might` keeps your Might on X no matter what the other paladin does.

**Timers and alerts** (shorten them with `/bfm refresh 59` and `/bfm warn 58`, or just wait)
- [ ] The shortest timer counts only your intended blessings.
- [ ] Crossing the warning threshold plays one sound and shows **Rebuff soon**. No repeat until you rebuff and it crosses again.
- [ ] A missing blessing appears as **Missing blessing**, separate from the timer.

**Combat**
- [ ] Entering combat greys the button with "Smart cycling available out of combat". Clicking does nothing.
- [ ] No "AddOn action blocked" or taint errors in combat, including when a party member joins or leaves mid-fight.
- [ ] After combat the button re-arms within about 1 second.
- [ ] `/bfm buttons on`: clicking a member row casts their blessing, including in combat.

**Greater mode** (level 52+ with Symbol of Kings)
- [ ] `/bfm greater on` with two DPS warriors who both need Might: the button shows Greater Might for all warriors.
- [ ] If one of them is pinned to Kings or has Might from another paladin, you get single-target blessings instead.

**Key binding, options, minimap (1.1.0)**
- [ ] Bind a key under Keybindings > AddOns > Buff-o-Matic. One press casts once. Holding the key does not repeat-cast.
- [ ] The key does nothing in combat, with no "action blocked" error.
- [ ] Options > AddOns > Buff-o-Matic opens the panel, and so does `/bfm options`. Toggling a checkbox takes effect immediately.
- [ ] Minimap button: left-click toggles the window, right-click opens options, and dragging moves it around the minimap. `/bfm minimap off` hides it.
- [ ] Addon compartment (the minimap addon list): Buff-o-Matic appears and its clicks behave like the minimap button.

**Ready check**
- [ ] Leave someone unbuffed, then start a ready check. You hear a sound, a chat line names them, and the window border flashes.
- [ ] With everyone buffed and nothing near expiry, a ready check stays quiet.

**PallyPower (needs a second paladin running PallyPower)**
- [ ] They assign themselves Kings for Warriors in PallyPower. `/bfm pp` lists it, and your button gives warriors something else. The tooltip says "Kings is <name>'s job (PallyPower)".
- [ ] If you already had Kings on a warrior before they assigned it, you keep it (no swap) until it's due.
- [ ] The raid leader assigns *you* Might on Warriors in PallyPower. Your button now gives warriors Might, with the reason "Your PallyPower assignment".
- [ ] `/bfm pallypower off` ignores their plans.

Please report anything that fails with the output of `/bfm diag`.
