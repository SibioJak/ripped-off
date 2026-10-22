class_name Tuning
extends RefCounted
## Every gameplay constant for Ripped-Off lives in this one file.
## No magic numbers in gameplay scripts: if a value is tuned, it is
## tuned here. Distances are in pixels, times in seconds, speeds in
## pixels per second, on the 1280x800 design view.

# --- Arena / depot -------------------------------------------------
const VIEW_W: float = 1280.0
const VIEW_H: float = 800.0
const ARENA_LEFT: float = 40.0
const ARENA_TOP: float = 40.0
const ARENA_RIGHT: float = 1240.0
const ARENA_BOTTOM: float = 760.0
const DEPOT_RADIUS: float = 118.0 # tow a canister inside this ring to deposit
const SLOT_COUNT: int = 8
const SLOT_RING_RADIUS: float = 62.0 # slots sit on a ring around the center
const EXIT_MARGIN: float = 30.0 # a dragged canister this far past the wall is gone
const EXIT_TARGET_DEPTH: float = 110.0 # exit points sit this far past the wall — BEYOND
	# the leaver despawn boundary (EXIT_MARGIN + 50), so a pirate steering
	# at full speed crosses the boundary and is freed before it can park
const EXIT_WATCHDOG_TIME: float = 6.0 # a pirate in LEAVE longer than this is force-freed

# --- Canisters ------------------------------------------------------
const CANISTER_RADIUS: float = 11.0
const SLOT_SNAP_RADIUS: float = 56.0 # loose canister this close to its berth glides in
const SLOT_GLIDE_MIN: float = 0.25
const SLOT_GLIDE_MAX: float = 0.6
const SLOT_GLIDE_SPEED: float = 420.0 # glide duration = distance / this, clamped
const LOOSE_FRICTION: float = 1.4 # exponential damping rate while LOOSE
const LOOSE_BOUNCE: float = 0.55 # velocity kept when a loose canister hits a wall
const TOW_LATCH_DIST: float = 32.0 # player center to canister center latches a tow
const TOW_TRAIL_DIST: float = 36.0 # towed canister trails this far behind the ship
const TOW_FOLLOW_RATE: float = 14.0 # exponential follow rate for the tow trail

# --- Recovery scoring ------------------------------------------------
const RECOVERY_MIN: int = 100
const RECOVERY_MAX: int = 600
const RECOVERY_DIST_NEAR: float = 80.0 # tow-start distance mapping to RECOVERY_MIN
const RECOVERY_DIST_FAR: float = 560.0 # tow-start distance mapping to RECOVERY_MAX

# --- Player -----------------------------------------------------------
const PLAYER_SPEED: float = 350.0
const PLAYER_ACCEL: float = 3200.0 # high on purpose: direct twin-stick, no drift
const PLAYER_RADIUS: float = 17.0 # BODY radius: ship contact, the arena
# clamp margin and the muzzle offset all judge the full hull.
# Enemy bullets do NOT — they judge the hotspot below (danmaku
# split: a bigger ship you can still thread through dense fire).
const PLAYER_HOTSPOT_RADIUS: float = 5.0 # the ship's vulnerable core:
# the ONLY radius enemy bullets test against (kill distance =
# ENEMY_BULLET_RADIUS + this), drawn on the hull at this size.
const PLAYER_FIRE_INTERVAL: float = 0.15
const PLAYER_RESPAWN_TIME: float = 1.2
const PLAYER_INVINCIBLE_TIME: float = 2.0
const RAM_SPEED_THRESHOLD: float = 235.0 # at/above this speed, contact rams kill

# --- Bullets ------------------------------------------------------------
const BULLET_SPEED: float = 760.0
const BULLET_LIFE: float = 1.1
const BULLET_RADIUS: float = 4.0

# --- Pirates --------------------------------------------------------------
const TELEGRAPH_TIME: float = 0.8 # visible warning before a pirate can move
const PIRATE_LATCH_DIST: float = 22.0
const MAX_CONCURRENT_DRAGS: int = 2 # drag governor: at most this many
	# canisters may be DRAGGING under pirate control at once, so a
	# swarm can never snatch the whole depot in one moment.
	# CONTESTED TOW shares these lanes: a pirate wrestling a
	# player-towed canister holds one lane exactly as a drag does,
	# and a latch of either kind needs the shared load under cap.

# --- Contested tow -----------------------------------------------------
const WRESTLE_TETHER_DIST: float = 30.0 # a wrestler hangs on within
	# this distance of the canister it is wrestling
const WRESTLE_PULL_SCALE: float = 2.5 # the wrestle's bias on the tow:
	# the wrestler's drag speed x this, applied toward its exit
	# against the tow's follow rate — the pair strains visibly
	# (equilibrium ~16px off the clean trail) but the player
	# keeps control and can still muscle the canister home
const SPAWN_EXCLUSION_RADIUS: float = 260.0 # no spawn point this close to the player

# --- Salvage shards ---------------------------------------------------------
const SHARD_BASE_POINTS: int = 10
const SHARD_LIFE: float = 6.0
const SHARD_BLINK_TIME: float = 1.5 # shards blink for this long before expiring
const SHARD_MAGNET_RADIUS: float = 120.0
const SHARD_MAGNET_SPEED: float = 300.0
const SHARD_COLLECT_RADIUS: float = 20.0
const SHARD_BURST_SPEED: float = 130.0
const SHARD_DRIFT_KEEP: float = 0.35 # fraction of burst velocity kept while drifting

# --- Multiplier ---------------------------------------------------------------
const MULT_CAP: float = 10.0
const MULT_PER_SHARD: float = 0.25
const MULT_GRACE: float = 2.5 # seconds after a collection before decay resumes
const MULT_DECAY_RATE: float = 0.45 # multiplier points per second, floor is x1
const MULT_DEATH_FACTOR: float = 0.5 # death halves the multiplier

# --- Continuous director (the restructure: no waves, no bosses) --------------
## The run has no wave structure: the director deals pirates
## forever, and the class composition, spawn interval and alive
## cap are functions of ELAPSED RUN TIME. Classes unlock on a
## schedule and grow to a plateau share; the grabber takes the
## remainder and never falls below its floor, so the canister
## clock is threatened from the first second to the last.
## The rebalance (play verdict: the stream was a relentless red
## conveyor with no room to retrieve) deals gunners from the
## first second — pressure on the PLAYER, not the clock — and
## lets the grabber share ease down as the mix fills in.
const COMP_GUNNER_START_SHARE: float = 0.40 # gunner share at t=0...
const COMP_GUNNER_SHARE: float = 0.30 # ...easing to this plateau...
const COMP_GUNNER_RAMP_END: float = 180.0 # ...by 180s
const COMP_HUNTER_UNLOCK: float = 75.0
const COMP_HUNTER_RAMP_END: float = 210.0
const COMP_HUNTER_SHARE: float = 0.14
const COMP_DARTER_UNLOCK: float = 120.0
const COMP_DARTER_RAMP_END: float = 240.0
const COMP_DARTER_SHARE: float = 0.10
const COMP_SNIPER_UNLOCK: float = 180.0
const COMP_SNIPER_RAMP_END: float = 300.0
const COMP_SNIPER_SHARE: float = 0.10
const COMP_GRABBER_MIN: float = 0.30 # the thief share never falls below this
const DIRECTOR_SPAWN_START: float = 1.35 # spawn interval at t=0 (pre-rank/flow)
const DIRECTOR_SPAWN_END: float = 0.55 # ...tightening to this by the ramp end
const DIRECTOR_SPAWN_RAMP: float = 480.0
const DIRECTOR_CAP_START: int = 4 # alive cap at t=0 (pre-rank bonus)
const DIRECTOR_CAP_END: int = 12 # ...rising to this by the ramp end
const DIRECTOR_CAP_RAMP: float = 480.0
## Anti-clump (the dealt deck's run guard, kept in sampled form):
## no class deals more than this many times consecutively while
## another unlocked class holds a real share.
const DIRECTOR_MAX_RUN: int = 3
## A new spawn point must sit at least this far from the previous
## one (the player exclusion still outranks it), so entries walk
## around the walls instead of stacking on one edge.
const SPAWN_MIN_SEPARATION: float = 220.0
## Refill pacing: the spawn interval is multiplied by a flow
## factor between this (empty field) and 1.0 (field at its alive
## cap), so a wiped field refills briskly but still one ship at a
## time — flow, never burst.
const SPAWN_FLOW_MIN_FRAC: float = 0.45
## The tow window (the rebalance): while the player is towing a
## canister home, the director deals NO new grabbers — the field
## already out keeps hunting, but the conveyor stops adding
## clock-threats until the tow ends — and its spawn interval is
## stretched by this factor. The retrieve is the game's natural
## breath, earned by doing it; the window ends the instant the
## tow does, with no catch-up burst and no banked deals.
const TOW_WINDOW_INTERVAL_SCALE: float = 1.5

# --- Rank (the intensity engine) -------------------------------------------------
## Rank lives 0..1 and is explicit: score-fed play raises it, rank
## raises the pressure back. It NEVER falls below a floor that rises
## slowly with elapsed run time, so the game eases off after a
## disaster but never goes soft. All scaling goes through the
## helpers below.
const RANK_START: float = 0.25 # a fresh run begins at real menace (M6)
const RANK_FLOOR_START: float = 0.20 # floor at t=0
const RANK_FLOOR_END: float = 0.55 # floor at the ramp end, held after
const RANK_FLOOR_RAMP: float = 600.0
const RANK_GAIN_KILL: float = 0.02
const RANK_GAIN_SHARD: float = 0.004
const RANK_GAIN_BUZZ: float = 0.01
const RANK_GAIN_RECOVERY: float = 0.03
const RANK_BLEED_DEATH: float = 0.15 # player death bleeds this much
const RANK_BLEED_STEAL: float = 0.08 # a canister carried off bleeds this
const SPAWN_INTERVAL_MIN_FRAC: float = 0.55 # spawn interval x this at rank 1
const ALIVE_CAP_RANK_BONUS: int = 3 # extra concurrent pirates at rank 1
const ENEMY_SPEED_MIN: float = 0.9 # enemy speed scale at rank 0
const ENEMY_SPEED_RANK_SPAN: float = 0.35 # ... up to 0.9 + 0.35 at rank 1
const GUNNER_FIRE_MIN_FRAC: float = 0.6 # gunner fire interval x this at rank 1

# --- Gunners (first shooter class; numbers live in enemy_defs.gd) ------------------
const GUNNER_CHARGE_TIME: float = 0.4 # muzzle glow wind-up before every shot

# --- Hunters (M6: the direct-challenge class; numbers live in enemy_defs.gd) --------
## The hunter never looks at a canister: it closes on the player,
## strafes around them at orbit range and fires lead shots. Its
## job is to keep the player moving — a parked or steadily
## strafing ship is exactly what its aim punishes.
const HUNTER_CHARGE_TIME: float = 0.35 # muzzle glow wind-up before every shot
const HUNTER_ORBIT_RANGE: float = 150.0 # pursuit closes to this band, then strafes
const HUNTER_LEAD_FACTOR: float = 0.75 # shots lead the player's velocity by
	# this fraction of the full time-of-flight lead: a steady strafe
	# gets punished, a direction change beats the shot
const HUNTER_STEER_ACCEL: float = 1400.0 # the hunter's velocity eases
	# toward its desired vector at this rate (px/s^2) instead of
	# snapping to it outright: its steering is rebuilt from the
	# player's current position every step, so a direct assignment
	# turned every player jink into an instant direction snap
const HUNTER_ALIVE_CAP: int = 2 # concurrent hunters on the field, early run
const HUNTER_ALIVE_CAP_LATE: int = 3 # ... from HUNTER_ALIVE_CAP_LATE_TIME
const HUNTER_ALIVE_CAP_LATE_TIME: float = 240.0

# --- Conversion (M7: the shooter becomes a thief) -----------------------------------
## When no getter is working, a gunner stops shooting and RESHAPES
## — transformer-style, plates folding, claw unfolding, colour
## cross-fading to the grabber's coral — then dives for a canister
## as a thief. The reshape is the fairness telegraph: a getter is
## always manufactured in plain sight before one exists. Main owns
## the triggers; the pirate owns the timeline.
const CONVERT_TIME: float = 0.9 # the full reshape, staged in thirds
const CONVERT_DEAD_AIR_TIME: float = 2.5 # no working thief (after one
	# has existed this run) for this long -> the oldest gunner converts
const CONVERT_NO_STEAL_BACKSTOP: float = 8.0 # no canister dragged for
	# this long -> a gunner converts even if a thief is out failing
const CONVERT_COOLDOWN: float = 4.0 # minimum seconds between conversion starts

# --- Enemy bullets ------------------------------------------------------------------
const ENEMY_BULLET_SPEED: float = 340.0
const ENEMY_BULLET_RADIUS: float = 4.0
const ENEMY_BULLET_LIFE: float = 4.0
## The hostile-fire pulse (M8): every enemy bullet breathes in
## sync off one shared clock — core brightness and radius swell
## and settle together — so hostile fire separates from steady
## player bullets, shards and bursts at a glance. Player bullets
## never pulse; that stillness is the other half of the read.
const ENEMY_BULLET_PULSE_HZ: float = 2.4 # full breaths per second
const ENEMY_BULLET_PULSE_DEPTH: float = 0.30 # core colour lerp toward white at peak
const ENEMY_BULLET_PULSE_RADIUS_FRAC: float = 0.18 # core radius swings +/- this fraction

# --- Powerups (M5: temp drops; ONE active at a time) ------------------------------
## Kills drop a pickup; flying over it replaces whatever powerup
## is running with a fresh full timer. Death clears it. The set
## is data in powerup_defs.gd; every number lives here.
const POWERUP_DROP_CHANCE: float = 0.12 # per pirate kill, field clear
const POWERUP_LIFETIME: float = 9.0 # seconds a drop sits before despawning
const POWERUP_BLINK_TIME: float = 2.0 # blink-out warning over the final stretch
const POWERUP_PICKUP_RADIUS: float = 26.0 # player centre to pickup centre
const POWERUP_DRIFT_MIN: float = 15.0 # drop drift speed off the kill point
const POWERUP_DRIFT_MAX: float = 45.0
const POWERUP_RAPID_DURATION: float = 10.0
const POWERUP_SPREAD_DURATION: float = 10.0
const POWERUP_OVERTHRUST_DURATION: float = 8.0
const POWERUP_SHIELD_DURATION: float = 8.0
const POWERUP_RAPID_FIRE_SCALE: float = 0.5 # fire interval x this (rapid)
const POWERUP_SPREAD_ANGLE: float = 0.15 # rad: outer bullets off facing (spread)
const POWERUP_OVERTHRUST_SPEED_SCALE: float = 1.35 # top speed x this
const POWERUP_SHIELD_INVINCIBLE_TIME: float = 1.0 # grace after a shield eats a hit
const COLOR_POWERUP_RAPID: Color = Color(1.0, 0.55, 0.1, 1.0) # orange bolt
const COLOR_POWERUP_SPREAD: Color = Color(0.2, 0.95, 1.0, 1.0) # cyan fan
const COLOR_POWERUP_OVERTHRUST: Color = Color(0.35, 1.0, 0.4, 1.0) # green arrow
const COLOR_POWERUP_SHIELD: Color = Color(0.35, 0.6, 1.0, 1.0) # blue hex

# --- Buzz (grazing) -------------------------------------------------------------------
const BUZZ_RADIUS: float = 30.0 # bullet graze: a near-miss inside this
# ring (centre distance) pays out — tightened around the bigger
# hull in the danmaku split, so buzz pays for a genuine shave.
const BUZZ_PASS_MARGIN: float = 16.0 # drag-pass buzz window: a pirate
# mid-drag pays when it passes within contact range + this margin
# without touching. For a standard pirate the window is
# (17 + 13, 17 + 13 + 16] = (30, 46] — the outer edge sits exactly
# where the old shared buzz ring put it; only the inner edge
# moved out with the bigger hull.
const BUZZ_POINTS: int = 25
const BUZZ_MULT_NUDGE: float = 0.1

# --- Floating popups ---------------------------------------------------------------------
const POPUP_TIME: float = 0.9
const POPUP_RISE_SPEED: float = 42.0

# --- Colours (vector palette) -----------------------------------------------------
const COLOR_ARENA: Color = Color(0.16, 0.45, 0.55, 1.0)
const COLOR_DEPOT: Color = Color(0.22, 0.95, 0.83, 1.0)
const COLOR_CRADLE_DIM: Color = Color(0.15, 0.4, 0.36, 1.0)
const COLOR_CRADLE_LIT: Color = Color(0.35, 1.0, 0.85, 1.0)
const COLOR_CANISTER: Color = Color(0.5, 1.0, 0.8, 1.0)
const COLOR_PLAYER: Color = Color(0.35, 0.95, 1.0, 1.0)
const COLOR_BULLET: Color = Color(0.75, 1.0, 1.0, 1.0)
const COLOR_ENEMY_BULLET_CORE: Color = Color(1.0, 0.8, 1.0, 1.0) # near-white magenta
const COLOR_ENEMY_BULLET_RIM: Color = Color(0.16, 0.02, 0.22, 1.0) # dark violet rim
const COLOR_SHARD: Color = Color(1.0, 0.85, 0.3, 1.0)
const COLOR_STEAL_FLASH: Color = Color(1.0, 0.25, 0.2, 1.0)
const COLOR_TEXT: Color = Color(0.85, 0.97, 1.0, 1.0)
const COLOR_TEXT_DIM: Color = Color(0.45, 0.62, 0.7, 1.0)


static func arena_rect() -> Rect2:
	return Rect2(ARENA_LEFT, ARENA_TOP,
		ARENA_RIGHT - ARENA_LEFT, ARENA_BOTTOM - ARENA_TOP)


static func depot_center() -> Vector2:
	return Vector2(VIEW_W * 0.5, VIEW_H * 0.5)


## Where the 1280x800 stage sits inside the real visible canvas:
## centered — half the surplus on each axis — and never negative
## (on a smaller canvas the stage stays pinned top-left, as
## before). Pure math on plain values, so the harness asserts it
## directly. Main applies the result as its own position; at
## exactly 1280x800 it is (0,0) and behaviour is today's.
static func stage_offset_for(visible: Vector2) -> Vector2:
	return Vector2(
		maxf((visible.x - VIEW_W) * 0.5, 0.0),
		maxf((visible.y - VIEW_H) * 0.5, 0.0))


static func slot_position(index: int) -> Vector2:
	var ang: float = TAU * float(index) / float(SLOT_COUNT) - PI * 0.5
	return depot_center() + Vector2.from_angle(ang) * SLOT_RING_RADIUS


## The rank floor at a run time: rank may bleed down after a
## death or a steal, but never below this — "never below menace".
static func rank_floor_at(t: float) -> float:
	return lerpf(RANK_FLOOR_START, RANK_FLOOR_END,
		clampf(t / RANK_FLOOR_RAMP, 0.0, 1.0))


## One class's composition share ramp: 0 before its unlock,
## growing linearly to its plateau at the ramp end, held after.
static func _share_ramp(t: float, unlock: float, ramp_end: float,
		plateau: float) -> float:
	return plateau * clampf((t - unlock) / (ramp_end - unlock), 0.0, 1.0)


## The gunner's share: it deals from the first second at
## COMP_GUNNER_START_SHARE and eases DOWN to its plateau by
## COMP_GUNNER_RAMP_END (the rebalance: gunner pressure is heavy
## early, when it teaches the player to move, and makes room as
## the specialist classes unlock).
static func _gunner_share_at(t: float) -> float:
	return lerpf(COMP_GUNNER_START_SHARE, COMP_GUNNER_SHARE,
		clampf(t / COMP_GUNNER_RAMP_END, 0.0, 1.0))


## The class composition at a run time: shares for every class,
## summing to 1. The grabber takes whatever the unlocked classes
## leave, and the others are scaled down proportionally if they
## would ever push the grabber below COMP_GRABBER_MIN (with the
## shipped plateaus they total 0.64, so the floor is a guard,
## not a participant).
static func composition_at(t: float) -> Dictionary:
	var gunner: float = _gunner_share_at(t)
	var hunter: float = _share_ramp(t, COMP_HUNTER_UNLOCK,
		COMP_HUNTER_RAMP_END, COMP_HUNTER_SHARE)
	var darter: float = _share_ramp(t, COMP_DARTER_UNLOCK,
		COMP_DARTER_RAMP_END, COMP_DARTER_SHARE)
	var sniper: float = _share_ramp(t, COMP_SNIPER_UNLOCK,
		COMP_SNIPER_RAMP_END, COMP_SNIPER_SHARE)
	var others: float = gunner + hunter + darter + sniper
	if others > 1.0 - COMP_GRABBER_MIN:
		var scale: float = (1.0 - COMP_GRABBER_MIN) / others
		gunner *= scale
		hunter *= scale
		darter *= scale
		sniper *= scale
		others = 1.0 - COMP_GRABBER_MIN
	return {
		"grabber": 1.0 - others,
		"gunner": gunner,
		"hunter": hunter,
		"darter": darter,
		"sniper": sniper}


## The director's base spawn interval at a run time (rank and
## flow scaling multiply on top of this in the director).
static func spawn_interval_at(t: float) -> float:
	return lerpf(DIRECTOR_SPAWN_START, DIRECTOR_SPAWN_END,
		clampf(t / DIRECTOR_SPAWN_RAMP, 0.0, 1.0))


## The director's base alive cap at a run time (the rank bonus
## adds on top in the director).
static func alive_cap_at(t: float) -> int:
	return int(round(lerpf(float(DIRECTOR_CAP_START),
		float(DIRECTOR_CAP_END),
		clampf(t / DIRECTOR_CAP_RAMP, 0.0, 1.0))))


## Concurrent hunters allowed on the field at a run time: a hard
## gate on dealing, so the direct-challenge class pressures in
## ones and twos (threes late) instead of swarming.
static func hunter_alive_cap_at(t: float) -> int:
	if t < HUNTER_ALIVE_CAP_LATE_TIME:
		return HUNTER_ALIVE_CAP
	return HUNTER_ALIVE_CAP_LATE


## Enemy move-speed scale at a given rank (0.9 at rank 0, 1.25 at 1).
static func rank_speed_mult(rank: float) -> float:
	return ENEMY_SPEED_MIN + ENEMY_SPEED_RANK_SPAN * clampf(rank, 0.0, 1.0)


## Spawn interval at a given rank: shorter (more pressure) as rank rises.
static func rank_spawn_interval(base: float, rank: float) -> float:
	return base * lerpf(1.0, SPAWN_INTERVAL_MIN_FRAC, clampf(rank, 0.0, 1.0))


## Refill flow factor: SPAWN_FLOW_MIN_FRAC on an empty field,
## easing to 1.0 as the field fills to its alive cap. Multiplies
## the spawn interval so the director deals briskly into a lull
## and at full pace into a crowd (M8).
static func spawn_flow_frac(alive_count: int, max_alive: int) -> float:
	return lerpf(SPAWN_FLOW_MIN_FRAC, 1.0,
		clampf(float(alive_count) / float(maxi(max_alive, 1)), 0.0, 1.0))


## Extra concurrent pirates the director allows at a given rank.
static func rank_alive_bonus(rank: float) -> int:
	return int(round(float(ALIVE_CAP_RANK_BONUS) * clampf(rank, 0.0, 1.0)))


## Gunner fire-interval scale at a given rank (fires faster as rank rises).
static func rank_fire_mult(rank: float) -> float:
	return lerpf(1.0, GUNNER_FIRE_MIN_FRAC, clampf(rank, 0.0, 1.0))


# --- Darters (the restructure: the lunging class) -------------------
## The fastest ship in the game and the only one with no gun: it
## hunts the PLAYER through a four-beat cycle — approach, a
## visible windup, a locked-line lunge, a slow vulnerable
## recovery. Numbers live here; the def carries speed/score.
const DARTER_TRIGGER_RANGE: float = 300.0 # approach ends, windup begins
const DARTER_WINDUP_TIME: float = 0.45 # decelerate + charge tell
const DARTER_LUNGE_SPEED: float = 540.0
const DARTER_LUNGE_DIST: float = 340.0 # lunge ends after this travel...
const DARTER_LUNGE_MAX_TIME: float = 0.7 # ...or this long, whichever first
const DARTER_RECOVER_TIME: float = 0.8 # slow drift after the lunge
const DARTER_RECOVER_MAX_SPEED: float = 60.0 # drift cap while recovering
const DARTER_ALIVE_CAP: int = 3 # concurrent darters, a hard dealing gate

# --- Snipers (the restructure: the long-range class) ----------------
## A shooter that parks FAR out — its band is measured from the
## PLAYER, not the depot — with a long, bright charge tell on a
## slow cycle, and a retreat when the player closes on it. It
## never converts: conversion stays the gunner's road to thief.
const SNIPER_CHARGE_TIME: float = 0.8 # the long tell before every shot
const SNIPER_BAND_MIN: float = 420.0 # post band from the player...
const SNIPER_BAND_MAX: float = 520.0
const SNIPER_RETREAT_DIST: float = 380.0 # player closer than this: back off
const SNIPER_ALIVE_CAP: int = 2 # concurrent snipers, a hard dealing gate


static func clamp_inside(pos: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(pos.x, ARENA_LEFT + radius, ARENA_RIGHT - radius),
		clampf(pos.y, ARENA_TOP + radius, ARENA_BOTTOM - radius))


## A point well outside the nearest arena wall from `pos` — where a
## dragging pirate escapes and where an empty pirate leaves. It
## must sit beyond Main's leaver despawn boundary: steering has no
## arrival slowdown, so a point inside the boundary is a parking
## spot the pirate jitters around forever (the M3 exit stall).
static func nearest_exit_point(pos: Vector2) -> Vector2:
	var d_left: float = pos.x - ARENA_LEFT
	var d_right: float = ARENA_RIGHT - pos.x
	var d_top: float = pos.y - ARENA_TOP
	var d_bottom: float = ARENA_BOTTOM - pos.y
	var best: float = minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if best == d_left:
		return Vector2(ARENA_LEFT - EXIT_TARGET_DEPTH, pos.y)
	if best == d_right:
		return Vector2(ARENA_RIGHT + EXIT_TARGET_DEPTH, pos.y)
	if best == d_top:
		return Vector2(pos.x, ARENA_TOP - EXIT_TARGET_DEPTH)
	return Vector2(pos.x, ARENA_BOTTOM + EXIT_TARGET_DEPTH)
