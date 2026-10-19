# Ripped-Off

A from-scratch Rip-Off homage for 2026: defend the 8 canisters in the
central depot against pirates who latch them and drag them off the
arena. Shoot them, ram them, tow the loose canisters home, and feed
the salvage multiplier — the run ends when all 8 canisters are gone,
and the high score is the goal.

Design document: `~/workspace/ripped-off/design.md` (kept outside the
repo). This build is **Milestone 3 — sound**, on top of the M1
playable core and M2 pressure & variety. Later design systems
(bosses, bombs, gravity wells, powerups, co-op, your-music
reactivity, global leaderboard) are deliberately not in yet.

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

## What's new in M3

- **Every sound is synthesized in-repo**: `tools/render_audio.py`
  (numpy) renders all music stems and SFX offline; re-running it
  reproduces every asset. Exact sample counts live in
  `audio/manifest.json`. Music ships as OGG (libvorbis q5), SFX as
  WAV, everything at 44100 Hz
- **Trance soundtrack, layered by rank** (`scripts/music_director.gd`):
  stems loop on one shared 134 BPM sample grid at differing lengths
  — drums/bass 16 beats, arp 12, perc figure 10, pad 32 — so layers
  phase against each other (polyrhythm) without ever drifting.
  Syncopated off-beat bass; Kick B foundation (120→40 Hz sweep,
  58% of its energy below 80 Hz, measured). Kick + bass are always
  in during a run; pad joins at rank 0.25, hats + perc at 0.45, arp
  at 0.60, clap drive at 0.80 — crossfaded by volume only, never
  effects. Bass and arp each carry a 3-variant pattern bank that a
  seeded rotation recombines every two drum loops. A separate
  minimal loop plays on the title / game-over screens
- **SFX set** (`scripts/sfx.gd`): a pooled set of positional
  one-shots — fatigueless shot tick (throttled, max 4 concurrent),
  per-class death pops (grabber thud vs gunner crack), shard pickup
  with a pitch ladder that climbs during a combo and scales with
  the haul, three sizes of deposit completion sound, buzz tick,
  tow latch, canister-stolen warning, player death, wave start,
  game over, UI start. One-shots get ±4% pitch variance; music
  pitch is never touched. (`hit_tick.wav` is rendered and loaded,
  deliberately unwired until the first armoured target exists)
- Audio buses (Master → Music at −6 dB, SFX at unity) are created
  in code at startup (`scripts/audio_buses.gd`)

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
measurably hungrier at high rank — plus M3: audio assets present
with loop lengths matching the render manifest, the music
director's title/run state machine and rank layer targets, variant
rotation, and SFX pool routing with pitch rules. It prints
PASS/FAIL per check and a total.
