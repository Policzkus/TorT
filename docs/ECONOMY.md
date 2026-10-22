# ECONOMY — tuning notes

Run the simulator from the project root: `lune run tests/economy_sim [hours] [-v]` (`-v` lists every purchase).
It models an average player on the real config (PROMPT §3.14): grades 10% MISS / 40% GOOD / 35% GREAT / 15% PERFECT,
knock + mini-game ≈ 2.7 s, walking between doors at the Sneakers speed, stash trips to the nearest of the three
drop-offs per street, greedy shopping (gate first, otherwise the cheapest upgrade that costs ≤ 45% of the next gate),
and rebirth as soon as the Candy Box is full. It's seeded, so runs are comparable.

## Pass #0 (Phase 1, 2026-10-22)

Only Phase 1 systems exist: doors (Timing Bar), bucket tiers, Charm, Sneakers, gates. No streak, house types,
rare candy, familiars, potions or playtime gifts yet, so later phases add income on top of this.

| Milestone | Target | Sim |
|---|---|---|
| first candy / first stash | 0:15 / 1:00 | 0:16 / 0:30 ✅ |
| first upgrade | ≤ 2:00 | 0:35 ✅ |
| Maple Lane | 5–7 min | 6:06 ✅ |
| Pumpkin Hollow | 20–25 min | 27:43 (≈ on target once the Phase 2 streak adds ~+20%) |
| first Rebirth | 45–60 min | 1:23 ❌ (retune in Phase 4 with rare candy, familiars, house types) |
| Rebirth 3 / Mansion Hill | ~3 h | 4:33 / 5:36 ❌ (Phase 4) |
| purchase gaps, first hour | ≤ ~3 min | longest 8:35 ❌ (the save-up for Pumpkin Hollow; Phase 4 adds tracks and cases, Phase 5 adds playtime gifts) |

Time split: knocking 38% · walking 48% · waiting for cooldowns 6% · stashing 5% · shopping 3%.

### Changes made to hit the early targets

- **Candy per door roughly doubled** vs PROMPT §3.3 (N1 3–7, N2 10–20, N3 30–60, N4 120–240, N5 500–1000, N6 2000–4000).
  The first sim had Maple Lane at 30 min.
- **Maple Lane 250 → 150.** Players buy upgrades on the way (a purchase about every minute early on), which is the point.
- **Door cooldown 4 min → 90 s.** With 16 houses, a 2–4 min cooldown left players idle for 20%+ of the time.
- **Three drop-offs per street** (entrance, a road island in the middle, the end) instead of one. Walking was 60% of all time.
- **Charm cost growth 1.75 → 1.45 and Sneakers 1.9 → 1.85**, so every price stays ≤ 50% of that life's Candy Box
  (enforced by a test in `tests/formulas.spec.luau`).

### To look at in Phase 4 (economy pass #1)

- First rebirth is ~1.4× too slow and late lives ~1.5× too slow: adding streak, house types, rare-candy jackpots and familiars
  should cover most of it. Then re-tune N3+ candy and the Candy Box sizes.
- The first-hour purchase gap (saving 2,500 for Pumpkin Hollow) needs more cheap sinks in that window: Luck/Stealth
  tracks, basic costumes, consumables.
