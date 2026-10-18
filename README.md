# Ripped-Off

A from-scratch Rip-Off homage for 2026: defend the 8 canisters in the
central depot against pirates who latch them and drag them off the
arena. Shoot them, ram them, tow the loose canisters home, and feed
the salvage multiplier — the run ends when all 8 canisters are gone,
and the high score is the goal.

Design document: `~/workspace/ripped-off/design.md` (kept outside the
repo). This build is **Milestone 1 — the playable core**. Later design
systems (bosses, dynamic rank, bombs, gravity wells, powerups, co-op,
your-music reactivity, global leaderboard) are deliberately not in yet.

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
respawn. It prints PASS/FAIL per check and a total.
