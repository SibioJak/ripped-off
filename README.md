# Ripped-Off

A from-scratch Rip-Off homage for 2026: defend the 8 canisters in the
central depot against pirates who latch them and drag them off the
arena. Shoot them, ram them, tow the loose canisters home, and feed
the salvage multiplier — the run ends when all 8 canisters are gone,
and the high score is the goal.

Design document: `~/workspace/ripped-off/design.md` (kept outside the
repo).

## The restructure (2026-10-22)

Boss battles and waves are **removed entirely** (Chris's ruling:
boss battles were never enjoyed in any game; waves out for
unceasing Geometry Wars-style action). There is no quota, no wave
counter, no boss. A run starts when it starts and ends only at
0 canisters. Escalation is the run clock's job, run by the
continuous spawn director (`scripts/spawn_director.gd`):

- **Composition is a function of elapsed run time**
  (`Tuning.composition_at`): grabbers only until 30s; gunners unlock
  at 30s and grow to a 0.28 share by 180s; hunters at 75s → 0.14;
  darters at 120s → 0.10; snipers at 180s → 0.10; the grabber takes
  the remainder, never below 0.38. Shares plateau after 300s.
- **Spawn interval** tightens from 1.05s at t=0 to 0.48s at t=480;
  **alive cap** rises 5 → 12 over the same span; the **rank floor**
  rises 0.20 → 0.55 by t=600. Rank scaling and flow pacing (a thin
  field refills faster) multiply on top.
- Dealing samples the composition per spawn with an anti-clump rule
  (no class more than 3 in a row while an alternative holds a real
  share) and per-class alive caps (hunter 2, then 3 after t=240;
  darter 3; sniper 2) whose shares redistribute to the grabber.
  Spawn points keep the player exclusion radius, the minimum
  separation between consecutive spawns, and the anchor fallback.
- The HUD shows a **run timer** (m:ss) beside the score; the save
  keeps best score + best run time.

Two new enemy classes landed with the restructure:

- **Darter** (`enemy_defs.gd` + pirate role): the fastest ship in
  the game, no gun, never touches canisters. Approach at 240 until
  within 300px, a 0.45s windup wearing the standard charge glow,
  a 540-speed lunge locked to the player's position at windup end
  (~340px, 0.7s cap), 0.8s of slow recovery, repeat. Green.
- **Sniper**: a long-range shooter that never touches canisters and
  never converts. It seeks a post 420–520px from the *player*,
  holds it with a slow strafe, retreats at full speed when the
  player closes inside 380px, and fires one aimed shot (no lead)
  per slow cycle behind a 0.8s charge tell. Pale ice blue.

## The game as built

- Direct twin-stick movement (no zero-g drift — a design decision),
  mouse/gamepad aim, hold to fire, ram kills at speed
- Five pirate classes defined as data (`scripts/enemy_defs.gd`),
  one state machine (`scripts/pirate.gd`): the **grabber** thief
  (telegraphs at a wall, hunts a canister, latches, drags it out;
  can also wrestle the player's tow — contested tow — and a second
  latch rips the tow free), the **gunner** shooter (standoff band
  around the depot, strafes, charge-telegraphed aimed shots), the
  **hunter** (pursues the player, orbits, fires shots that lead the
  player's motion), the **darter** and the **sniper** (above)
- **Conversion**: a gunner whose getters are gone rebuilds itself
  into a thief — triggers are dead air (2.5s with no working thief
  after one has worked this run) and the 8s no-steal backstop;
  longest-alive gunner, one at a time, 20s cooldown
- **Drag governor**: at most 2 canisters may be under pirate drag
  (or wrestled) at once, so a swarm can never snatch the depot in
  one moment
- The canister state machine, defined once in `scripts/canister.gd`:
  IN_SLOT / LOOSE / DRAGGING / TOWED / GONE, with momentum in LOOSE
  and glide-in slotting
- Tow-and-deposit recovery paying a distance-scaled bonus (100–600)
- Salvage shards from kills; collecting them builds a multiplier
  (cap x10) that decays without collection and halves on death
- **Rank, the intensity engine**: a visible RANK bar on the HUD with
  the run-time menace floor ticked. Kills, shard collection, buzz
  and recoveries raise rank; player death and stolen canisters bleed
  it — never below the floor. Rank tightens spawn pacing, lifts the
  alive cap, speeds enemies up, and shortens shooter fire intervals
- **Buzz (grazing)**: an enemy bullet passing close without hitting,
  or a close pass on a pirate mid-drag, pays points through the
  multiplier, a multiplier nudge and a little rank — once per
  bullet, once per drag
- **Death protocol**: dying converts every live enemy bullet into a
  salvage shard where it flies, on top of the multiplier and rank
  costs; respawn is invincible for a beat
- **Danmaku split**: the player hull is 17px for contact/clamping,
  but enemy bullets judge a 5px hotspot at its center — threading
  dense fire is a real skill, and grazes pay buzz
- **Powerups**: pirate kills drop a pickup 12% of the time (one on
  the field at a time): Rapid Fire, Spread, Overthrust, Shield —
  one active at a time, timed, fly-over collect
- Procedural light effects (`scripts/light_fx.gd`) — light, never
  screen shake
- Local best score + best run time saved to
  `user://rippedoff_save.json`
- All gameplay constants in `scripts/tuning.gd`

## Sound

- **Every sound is synthesized in-repo**: `tools/render_audio.py`
  (numpy) renders all music stems and SFX offline; re-running it
  reproduces every asset. Exact sample counts live in
  `audio/manifest.json`. Music ships as OGG (libvorbis q5), SFX as
  WAV, everything at 44100 Hz
- **Soundtrack, layered by rank** (`scripts/music_director.gd`):
  stems loop on one shared 134 BPM sample grid at differing lengths
  — drums/bass 16 beats, arp 12, perc figure 10, pad 32 — so layers
  phase against each other (polyrhythm) without ever drifting.
  Re-voiced in M9 toward high-tech minimal (the Brejcha direction):
  a rolling low bassline as the constant engine, dry pinpoint
  percussion, melodic content low-mid and dark, almost no high end.
  Kick B foundation (120→40 Hz sweep). Layers join as rank climbs —
  crossfaded by volume only, never effects. Bass and arp each carry
  a 3-variant pattern bank that a seeded rotation recombines every
  two drum loops. A separate minimal loop plays on the title /
  game-over screens
- **SFX set** (`scripts/sfx.gd`): a pooled set of positional
  one-shots — fatigueless shot tick (throttled, max 4 concurrent),
  per-class death pops, shard pickup with a pitch ladder that
  climbs during a combo and scales with the haul, three sizes of
  deposit completion sound, buzz tick, tow latch, canister-stolen
  warning, player death, game over, UI start. One-shots get ±4%
  pitch variance; music pitch is never touched
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

The harness drives the real game scene through its real code paths
and prints PASS/FAIL per check plus a total. It covers the core
loop (boot/title, 8 slotted canisters, latch + drag, bullet kill
frees the canister LOOSE, tow + deposit, shards/multiplier, decay,
game over at 0 canisters, death costs + invincible respawn), rank
and the continuous director (composition curve and unlock
boundaries, anti-clump, class alive caps, flow pacing, spawn
separation, a 600-second endless soak, rank hunger), the audio
manifest and music/SFX directors, the exit stall + watchdog,
conversion (dead air, backstop, timeline, one-at-a-time, hunters
and snipers never convert), the drag governor and contested tow,
the danmaku hotspot geometry, and the darter and sniper classes
(cycle timing and lunge lock; band hold and retreat; charge
discipline). Boss and wave checks were removed with the systems
they tested in the 2026-10-22 restructure.
