# Ripped-Off

A from-scratch Rip-Off homage for 2026: defend the 8 canisters in the
central depot against pirates who latch them and drag them off the
arena. Shoot them, ram them, tow the loose canisters home, and feed
the salvage multiplier — the run ends when all 8 canisters are gone,
and the high score is the goal.

Design document: `~/workspace/ripped-off/design.md` (kept outside the
repo). This build is **Milestone 2 — pressure & variety**, on top of
the M1 playable core. Later design systems (bosses, bombs, gravity
wells, powerups, co-op, your-music reactivity, global leaderboard)
are deliberately not in yet.

## What's in M1

- Direct twin-stick movement (no zero-g drift — a design decision),
  mouse/gamepad aim, hold to fire, ram kills at speed
- One pirate class, the **grabber**, defined as data
  (`scripts/enemy_defs.gd`): telegraphs at a wall, hunts the nearest
  canister, latches it, drags it to an exit
- The canister state machine, defined once in `scripts/canister.gd`:
  IN_SLOT / LOOSE / DRAGGING / TOWED / GONE, with momentum in LOOSE and
  glide-in slotting
- Tow-and-deposit recovery paying a distance-scaled bonus (100–600)
- Salvage shards from kills; collecting them builds a multiplier
  (cap x10) that decays without collection and halves on death
- Wave flow run by `scripts/spawn_director.gd` (quotas, pacing,
  telegraphed spawns, fairness exclusion near the player)
- Procedural light effects (`scripts/light_fx.gd`) — light, never
  screen shake
- Local best score + wave saved to `user://rippedoff_save.json`
- All gameplay constants in `scripts/tuning.gd`

## What's new in M2

- **Rank, the intensity engine**: a visible RANK bar on the HUD
  (with the wave's menace floor ticked). Kills, shard collection,
  buzz and recoveries raise rank; player death and stolen canisters
  bleed it — never below a floor that rises with the wave. Rank
  tightens spawn pacing, lifts the concurrent-alive cap, speeds
  enemies up, and shortens gunner fire intervals
- **The gunner**, a second pirate class added as data: flies to a
  standoff band around the depot, strafes, and fires aimed shots —
  every shot announced by a growing muzzle charge-up. Enemy bullets
  (`scripts/enemy_bullet.gd`) draw bright-core/dark-rim above
  everything else. From wave 2 the director mixes gunners into the
  quota, the share growing with the wave
- **Buzz (grazing)**: an enemy bullet passing within 46px without
  hitting, or a close pass on a pirate mid-drag, pays 25 points
  through the multiplier, a +0.1 multiplier nudge and a little rank
  — once per bullet, once per drag. Floating popups show buzz and
  recovery payouts in the world
- **Death protocol**: dying converts every live enemy bullet into
  a salvage shard where it flies, on top of the M1 costs
  (multiplier halved, rank bled)

## Controls

| Action | Keys / buttons |
| --- | --- |
| Move | W A S D / Left Stick |
| Aim | Mouse / Right Stick |
| Fire | Hold Left Mouse / Space / Right Trigger / A Button |
| Twin-stick fallback | Arrow Keys aim and fire |
| Pause | Esc / P / Start Button |

## Run it

Open the project in Godot 4.7 and press F5. Title screen shows the
controls and your best score; fire starts a run.

## Verify it (headless harness)

```
~/workspace/tools/godot/Godot_v4.7-stable_linux.x86_64 --headless --path . --import
~/workspace/tools/godot/Godot_v4.7-stable_linux.x86_64 --headless --path . res://tests/harness.tscn
```

The harness drives the real game scene and asserts the core loop:
boot/title, 8 slotted canisters, pirate latch + drag, bullet kill
frees the canister LOOSE, tow + deposit pays the recovery bonus,
shard collection raises the multiplier, multiplier decay, game over
at 0 canisters, and death halving the multiplier with an invincible
respawn — plus M2: gunners in the wave-2 mix, charge-telegraphed
fire, buzz paid exactly once, death converting bullets to shards,
rank rising on play and falling on death, and the director getting
measurably hungrier at high rank. It prints PASS/FAIL per check
and a total.
