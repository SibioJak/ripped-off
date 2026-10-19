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
const PLAYER_RADIUS: float = 13.0
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

# --- Waves ----------------------------------------------------------------------
const WAVE_BASE_QUOTA: int = 4 # wave quota = BASE + PER_WAVE * wave
const WAVE_QUOTA_PER_WAVE: int = 2
const WAVE_MAX_ALIVE_BASE: int = 3 # alive cap = BASE + wave - 1, capped
const WAVE_MAX_ALIVE_CAP: int = 6
const SPAWN_INTERVAL: float = 1.1
const WAVE_BANNER_TIME: float = 1.5

# --- Rank (the intensity engine) -------------------------------------------------
## Rank lives 0..1 and is explicit: score-fed play raises it, rank
## raises the pressure back. It NEVER falls below a floor that rises
## slowly with the wave, so the game eases off after a disaster but
## never goes soft. All scaling goes through the helpers below.
const RANK_START: float = 0.15 # a fresh run begins at low menace
const RANK_FLOOR_BASE: float = 0.15 # floor at wave 1
const RANK_FLOOR_PER_WAVE: float = 0.02 # floor growth per wave
const RANK_FLOOR_CAP: float = 0.5 # the floor never rises past this
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
const GUNNER_SHARE_MIN: float = 0.25 # gunner share of the quota from wave 2
const GUNNER_SHARE_PER_WAVE: float = 0.03 # share grows with the wave
const GUNNER_SHARE_CAP: float = 0.55

# --- Enemy bullets ------------------------------------------------------------------
const ENEMY_BULLET_SPEED: float = 340.0
const ENEMY_BULLET_RADIUS: float = 4.0
const ENEMY_BULLET_LIFE: float = 4.0

# --- Buzz (grazing) -------------------------------------------------------------------
const BUZZ_RADIUS: float = 46.0 # a near-miss inside this ring pays out
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


## The rank floor for a wave: rank may bleed down after a death or
## a steal, but never below this — "never below menace".
static func rank_floor_for_wave(w: int) -> float:
	return minf(
		RANK_FLOOR_BASE + RANK_FLOOR_PER_WAVE * float(maxi(w - 1, 0)),
		RANK_FLOOR_CAP)


## Enemy move-speed scale at a given rank (0.9 at rank 0, 1.25 at 1).
static func rank_speed_mult(rank: float) -> float:
	return ENEMY_SPEED_MIN + ENEMY_SPEED_RANK_SPAN * clampf(rank, 0.0, 1.0)


## Spawn interval at a given rank: shorter (more pressure) as rank rises.
static func rank_spawn_interval(base: float, rank: float) -> float:
	return base * lerpf(1.0, SPAWN_INTERVAL_MIN_FRAC, clampf(rank, 0.0, 1.0))


## Extra concurrent pirates the director allows at a given rank.
static func rank_alive_bonus(rank: float) -> int:
	return int(round(float(ALIVE_CAP_RANK_BONUS) * clampf(rank, 0.0, 1.0)))


## Gunner fire-interval scale at a given rank (fires faster as rank rises).
static func rank_fire_mult(rank: float) -> float:
	return lerpf(1.0, GUNNER_FIRE_MIN_FRAC, clampf(rank, 0.0, 1.0))


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
