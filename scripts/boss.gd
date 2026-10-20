class_name Boss
extends Node2D
## The DREADNOUGHT — Ripped-Off's first boss, on every 5th wave
## (design doc, "Enemies and bosses"). A big vector capital that
## stations in the arena's top band and never leaves it: a tier-
## scaled hull, two breakable turrets firing telegraphed aimed
## shots, a breakable grab arm that steals canisters, radial ring
## bursts at 66% and 33% hull, and a staged spectacle death.
## Numbers live in Tuning's boss section (the data discipline);
## this script is behaviour only. Main referees collisions, owns
## the score and routes effects — the boss reports via signals.
## There is no invulnerable phase anywhere: it is damageable from
## the first frame of its descent.

signal fired(from: Vector2, dir: Vector2, core: Color, rim: Color)
signal detonated(pos: Vector2, size_class: int, color: Color, sound: String)
signal spark(pos: Vector2)
signal canister_consumed(c: Canister)
signal part_broken(part_id: String, at: Vector2)
signal death_completed(boss: Boss)

enum Phase { ENTRY, ACTIVE, DYING }
enum ArmState { IDLE, TELEGRAPH, PULL }

const PART_TURRET_L: String = "turret_left"
const PART_TURRET_R: String = "turret_right"
const PART_ARM: String = "arm"

# Hit circles in boss-local space, [offset, radius]. Bullets test
# parts first, then the hull body (see hit_circles); player
# contact uses the same circles — a capital cannot be rammed.
const HULL_CIRCLES: Array = [
	[Vector2(-48.0, 10.0), 46.0],
	[Vector2(48.0, 10.0), 46.0],
	[Vector2(0.0, -38.0), 42.0],
]
const PART_DEFS: Dictionary = {
	"turret_left": {"offset": Vector2(-74.0, 34.0), "radius": 18.0},
	"turret_right": {"offset": Vector2(74.0, 34.0), "radius": 18.0},
	"arm": {"offset": Vector2(0.0, 62.0), "radius": 20.0},
}

var phase: Phase = Phase.ENTRY
var tier: int = 1
var max_hull_hp: int = 1
var hull_hp: int = 1
var proximity_active: bool = false # player inside the bonus band

# Test-visible counters (the harness reads these).
var shots_left: int = 0
var shots_right: int = 0
var radial_count: int = 0
var arm_telegraphed_once: bool = false

var _parts: Dictionary = {} # id -> {hp, broken, flash}
var _entry_t: float = 0.0
var _entry_from: Vector2 = Vector2.ZERO
var _entry_to: Vector2 = Vector2.ZERO
var _strafe_t: float = 0.0
var _hull_flash: float = 0.0
# Per-turret fire cycles (M4 pressure fix: the turrets used to
# share one timer and alternate, which starved the fight's first
# phase). Each turret counts its own cooldown down, charges, and
# fires on its own clock — a broken or charging turret never
# slows its twin.
var _fire_t: Dictionary = {} # part id -> seconds until it charges
var _charge_t: Dictionary = {} # part id -> charge seconds left (< 0: idle)
var _turret_aim: Dictionary = {} # part id -> Vector2
var _radial1_done: bool = false
var _radial2_done: bool = false
var _radial_pending: int = 0
var _radial_charging: bool = false
var _radial_t: float = 0.0
var _arm_state: int = ArmState.IDLE
var _arm_t: float = 0.0
var _arm_target: Canister = null
var _arm_cool: float = 2.0
var _pull_speed: float = 0.0
var _dying_t: float = 0.0
var _death_events: Array[Dictionary] = []
var _death_idx: int = 0
var _death_sent: bool = false
var _chunks: Array[Dictionary] = [] # torn-off part debris, drawn in DYING
var _spark_t: float = 0.0
var _proximity_pulse_t: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 5


func setup(p_wave: int) -> void:
	tier = Tuning.boss_tier(p_wave)
	max_hull_hp = Tuning.boss_hull_hp(tier)
	hull_hp = max_hull_hp
	_rng.randomize()
	var ids: Array = PART_DEFS.keys()
	for pid_v: Variant in ids:
		var pid: String = String(pid_v)
		_parts[pid] = {"hp": Tuning.BOSS_PART_HP,
			"broken": false, "flash": 0.0}
		_turret_aim[pid] = Vector2.DOWN
	_entry_from = Vector2(Tuning.VIEW_W * 0.5, Tuning.ARENA_TOP - 130.0)
	_entry_to = Vector2(Tuning.VIEW_W * 0.5, Tuning.BOSS_STATION_Y)
	global_position = _entry_from
	phase = Phase.ENTRY
	_entry_t = 0.0
	# First shots are not instant, and the right turret starts
	# half an interval behind the left so the pair never settles
	# into synchronized volleys.
	var interval: float = Tuning.boss_turret_interval(tier)
	_fire_t[PART_TURRET_L] = interval * 0.75
	_fire_t[PART_TURRET_R] = interval * 0.75 + interval * 0.5
	_charge_t[PART_TURRET_L] = -1.0
	_charge_t[PART_TURRET_R] = -1.0
	queue_redraw()


# --- Queries -------------------------------------------------------------

func part_world(part_id: String) -> Vector2:
	var pd: Dictionary = PART_DEFS[part_id] as Dictionary
	return global_position + (pd["offset"] as Vector2)


func part_radius(part_id: String) -> float:
	var pd: Dictionary = PART_DEFS[part_id] as Dictionary
	return float(pd["radius"])


func is_part_broken(part_id: String) -> bool:
	var pd: Dictionary = _parts[part_id] as Dictionary
	return bool(pd["broken"])


func part_hp(part_id: String) -> int:
	var pd: Dictionary = _parts[part_id] as Dictionary
	return int(pd["hp"])


func hull_frac() -> float:
	return clampf(float(hull_hp) / float(maxi(max_hull_hp, 1)), 0.0, 1.0)


## Every damageable circle in world space as [center, radius, id]:
## unbroken parts first (bullets test parts before the hull), then
## the hull body under the id "hull". Main uses this for both
## bullet hits and player contact.
func hit_circles() -> Array:
	var out: Array = []
	var ids: Array = PART_DEFS.keys()
	for pid_v: Variant in ids:
		var pid: String = String(pid_v)
		if not is_part_broken(pid):
			out.append([part_world(pid), part_radius(pid), pid])
	for circ_v: Variant in HULL_CIRCLES:
		var circ: Array = circ_v as Array
		out.append([global_position + (circ[0] as Vector2),
			float(circ[1]), "hull"])
	return out


func _arm_mouth() -> Vector2:
	return global_position + Vector2(0.0, 78.0)


# --- Damage (called by Main when a bullet connects) -----------------------

func damage_hull(amount: int = 1) -> void:
	if phase == Phase.DYING:
		return
	hull_hp = maxi(hull_hp - maxi(amount, 0), 0)
	_hull_flash = 0.12
	var frac: float = hull_frac()
	if not _radial1_done and frac <= 0.66:
		_radial1_done = true
		_radial_pending += 1
	elif not _radial2_done and frac <= 0.33:
		_radial2_done = true
		_radial_pending += 1
	if hull_hp <= 0:
		_begin_dying()
	queue_redraw()


func damage_part(part_id: String, amount: int = 1) -> void:
	if phase == Phase.DYING or is_part_broken(part_id):
		return
	var pd: Dictionary = _parts[part_id] as Dictionary
	var hp: int = maxi(int(pd["hp"]) - maxi(amount, 0), 0)
	pd["hp"] = hp
	pd["flash"] = 0.15
	_parts[part_id] = pd
	if hp <= 0:
		_break_part(part_id)
	queue_redraw()


func _break_part(part_id: String) -> void:
	var pd: Dictionary = _parts[part_id] as Dictionary
	pd["broken"] = true
	pd["flash"] = 0.0
	_parts[part_id] = pd
	if _charge_t.has(part_id):
		_charge_t[part_id] = -1.0 # a dead turret never completes its charge
	if part_id == PART_ARM:
		_drop_arm_hold() # mid-drag: the canister drops LOOSE
		_arm_cool = Tuning.BOSS_GRAB_COOLDOWN
	part_broken.emit(part_id, part_world(part_id))


## Release whatever the grab arm is holding, LOOSE with a small
## momentum — the counter-play reward, and the death protocol.
func _drop_arm_hold() -> void:
	if _arm_target != null and is_instance_valid(_arm_target) \
			and _arm_target.state == Canister.State.DRAGGING \
			and _arm_target.holder == self:
		_arm_target.release_from_drag(Vector2(50.0, 70.0))
	_arm_target = null
	if _arm_state == ArmState.PULL:
		_arm_state = ArmState.IDLE


# --- Per-frame step (called by Main) ---------------------------------------

func step(delta: float, canisters: Array[Canister], player_pos: Vector2,
		player_alive: bool) -> void:
	proximity_active = Tuning.boss_proximity_active(
		player_pos, global_position)
	if proximity_active:
		_proximity_pulse_t += delta
	_hull_flash = maxf(_hull_flash - delta, 0.0)
	var ids: Array = _parts.keys()
	for pid_v: Variant in ids:
		var pid: String = String(pid_v)
		var pd: Dictionary = _parts[pid] as Dictionary
		if float(pd["flash"]) > 0.0:
			pd["flash"] = maxf(float(pd["flash"]) - delta, 0.0)
			_parts[pid] = pd
	match phase:
		Phase.ENTRY:
			_entry_t += delta
			var frac: float = clampf(
				_entry_t / Tuning.BOSS_ENTRY_TIME, 0.0, 1.0)
			var eased: float = frac * frac * (3.0 - 2.0 * frac)
			global_position = _entry_from.lerp(_entry_to, eased)
			if frac >= 1.0:
				phase = Phase.ACTIVE
				_strafe_t = 0.0
		Phase.ACTIVE:
			_step_active(delta, canisters, player_pos, player_alive)
		Phase.DYING:
			_step_dying(delta)
	# Broken parts spark occasionally; Main routes the light.
	if phase != Phase.DYING:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = _rng.randf_range(0.5, 1.1)
			var broken: Array[String] = []
			for pid_v2: Variant in ids:
				var pid2: String = String(pid_v2)
				if is_part_broken(pid2):
					broken.append(pid2)
			if not broken.is_empty():
				var pick: String = broken[
					_rng.randi_range(0, broken.size() - 1)]
				spark.emit(part_world(pick))
	queue_redraw()


func _step_active(delta: float, canisters: Array[Canister],
		player_pos: Vector2, player_alive: bool) -> void:
	# Station-keeping: slow strafe + slight bob in the top band.
	# While the arm is reeling a canister in, the capital holds
	# station — the pull is the tell, and the canister's travel
	# time stays the Tuning value instead of chasing a moving mouth.
	if _arm_state != ArmState.PULL:
		_strafe_t += delta
	var sx: float = Tuning.VIEW_W * 0.5 \
		+ sin(_strafe_t * Tuning.BOSS_STRAFE_RATE) * Tuning.BOSS_STRAFE_AMP
	var sy: float = Tuning.BOSS_STATION_Y \
		+ sin(_strafe_t * Tuning.BOSS_BOB_RATE) * Tuning.BOSS_BOB_AMP
	global_position = Vector2(
		clampf(sx, Tuning.ARENA_LEFT + 150.0, Tuning.ARENA_RIGHT - 150.0),
		clampf(sy, Tuning.ARENA_TOP + 90.0, Tuning.ARENA_BOTTOM - 90.0))
	_step_turrets(delta, player_pos, player_alive)
	_step_radial(delta)
	_step_arm(delta, canisters)


# --- Turrets -----------------------------------------------------------------

func _step_turrets(delta: float, player_pos: Vector2, player_alive: bool) -> void:
	var ids: Array[String] = [PART_TURRET_L, PART_TURRET_R]
	for pid: String in ids:
		if player_alive:
			var to: Vector2 = player_pos - part_world(pid)
			if to.length() > 1.0:
				_turret_aim[pid] = to.normalized()
	for pid2: String in ids:
		_step_one_turret(pid2, delta, player_alive)


## One turret's independent cycle: cooldown (boss_turret_interval)
## -> charge (GUNNER_CHARGE_TIME telegraph glow) -> fire ->
## cooldown. A charge already winding up runs to completion even
## if the player drops (the shot itself is suppressed in
## _fire_charged); a cooldown only ticks while the player is up —
## gunner discipline, applied per turret: no new charges at a
## downed ship. A broken turret's cycle simply stops; the survivor
## keeps its own rate unchanged.
func _step_one_turret(pid: String, delta: float, player_alive: bool) -> void:
	if is_part_broken(pid):
		return
	if float(_charge_t[pid]) >= 0.0:
		_charge_t[pid] = float(_charge_t[pid]) - delta
		if float(_charge_t[pid]) <= 0.0:
			_charge_t[pid] = -1.0
			_fire_charged(pid, player_alive)
			_fire_t[pid] = Tuning.boss_turret_interval(tier)
		return
	if not player_alive:
		return
	_fire_t[pid] = float(_fire_t[pid]) - delta
	if float(_fire_t[pid]) <= 0.0:
		_charge_t[pid] = Tuning.GUNNER_CHARGE_TIME


## Test lever (the harness parks turret fire to isolate score and
## contact measurements): long cooldowns on both turrets and any
## in-progress charge cancelled — neither turret can fire.
func park_turrets() -> void:
	_fire_t[PART_TURRET_L] = 999.0
	_fire_t[PART_TURRET_R] = 999.0
	_charge_t[PART_TURRET_L] = -1.0
	_charge_t[PART_TURRET_R] = -1.0


func _fire_charged(part_id: String, player_alive: bool) -> void:
	if is_part_broken(part_id) or not player_alive:
		return
	var from: Vector2 = part_world(part_id)
	var base: Vector2 = _turret_aim[part_id] as Vector2
	if part_id == PART_TURRET_L:
		shots_left += 1
	else:
		shots_right += 1
	if tier >= 2:
		for k: int in [-1, 0, 1]:
			fired.emit(from, base.rotated(0.18 * float(k)),
				Tuning.COLOR_BOSS_BULLET_CORE,
				Tuning.COLOR_BOSS_BULLET_RIM)
	else:
		fired.emit(from, base,
			Tuning.COLOR_BOSS_BULLET_CORE, Tuning.COLOR_BOSS_BULLET_RIM)


func charge_frac(part_id: String) -> float:
	if not _charge_t.has(part_id):
		return -1.0
	var left: float = float(_charge_t[part_id])
	if left < 0.0:
		return -1.0
	return clampf(1.0 - left / Tuning.GUNNER_CHARGE_TIME, 0.0, 1.0)


# --- Radial bursts -------------------------------------------------------------

func _step_radial(delta: float) -> void:
	if _radial_pending > 0 and not _radial_charging:
		_radial_charging = true
		_radial_t = Tuning.BOSS_RADIAL_CHARGE_TIME
	if _radial_charging:
		_radial_t -= delta
		if _radial_t <= 0.0:
			_radial_charging = false
			_radial_pending = maxi(_radial_pending - 1, 0)
			radial_count += 1
			var n: int = Tuning.boss_radial_count(tier)
			for i: int in range(n):
				var dir: Vector2 = Vector2.from_angle(
					TAU * float(i) / float(n))
				fired.emit(global_position, dir,
					Tuning.COLOR_BOSS_BULLET_CORE,
					Tuning.COLOR_BOSS_BULLET_RIM)


# --- Grab arm ---------------------------------------------------------------------

func _step_arm(delta: float, canisters: Array[Canister]) -> void:
	if is_part_broken(PART_ARM):
		return # a broken arm never grabs again this fight
	match _arm_state:
		ArmState.IDLE:
			_arm_cool -= delta
			if _arm_cool <= 0.0:
				_select_arm_target(canisters)
		ArmState.TELEGRAPH:
			if not _arm_target_valid():
				_arm_target = null
				_arm_state = ArmState.IDLE
				_arm_cool = 1.0
			else:
				_arm_t -= delta
				if _arm_t <= 0.0:
					if _arm_target.begin_drag(self):
						_arm_state = ArmState.PULL
						var d: float = _arm_mouth().distance_to(
							_arm_target.global_position)
						_pull_speed = d / Tuning.BOSS_GRAB_PULL_TIME
					else:
						_arm_target = null
						_arm_state = ArmState.IDLE
						_arm_cool = 1.0
		ArmState.PULL:
			if _arm_target == null or not is_instance_valid(_arm_target) \
					or _arm_target.state != Canister.State.DRAGGING \
					or _arm_target.holder != self:
				_arm_target = null
				_arm_state = ArmState.IDLE
				_arm_cool = Tuning.BOSS_GRAB_COOLDOWN
			else:
				var to: Vector2 = _arm_mouth() - _arm_target.global_position
				var step_d: float = _pull_speed * delta
				if to.length() <= maxf(step_d, Tuning.BOSS_CONSUME_DIST):
					var c: Canister = _arm_target
					_arm_target = null
					_arm_state = ArmState.IDLE
					_arm_cool = Tuning.BOSS_GRAB_COOLDOWN
					canister_consumed.emit(c)
				else:
					_arm_target.global_position += to.normalized() * step_d


## Target choice: the nearest IN_SLOT canister (the arm threatens
## the rack first); if none is slotted, the nearest LOOSE one; if
## nothing is stealable, idle and retry. is_available_target()
## already excludes TOWED and GONE canisters — the arm never takes
## a canister out of the player's tow.
func _select_arm_target(canisters: Array[Canister]) -> void:
	var mouth: Vector2 = _arm_mouth()
	var best: Canister = null
	var best_d: float = INF
	for c: Canister in canisters:
		if c.state == Canister.State.IN_SLOT and c.is_available_target():
			var d: float = mouth.distance_squared_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		for c: Canister in canisters:
			if c.state == Canister.State.LOOSE and c.is_available_target():
				var d2: float = mouth.distance_squared_to(c.global_position)
				if d2 < best_d:
					best_d = d2
					best = c
	if best == null:
		_arm_cool = 1.0
		return
	_arm_target = best
	_arm_state = ArmState.TELEGRAPH
	_arm_t = Tuning.BOSS_GRAB_TELEGRAPH_TIME
	arm_telegraphed_once = true


func _arm_target_valid() -> bool:
	return _arm_target != null and is_instance_valid(_arm_target) \
		and _arm_target.is_available_target()


# --- Death: the spectacle ---------------------------------------------------------

func _begin_dying() -> void:
	phase = Phase.DYING
	_dying_t = 0.0
	_death_idx = 0
	_charge_t[PART_TURRET_L] = -1.0
	_charge_t[PART_TURRET_R] = -1.0
	_radial_charging = false
	_radial_pending = 0
	_drop_arm_hold()
	_arm_state = ArmState.IDLE
	# Parts tear off as debris chunks for the rest of the sequence.
	var ids: Array[String] = [PART_TURRET_L, PART_TURRET_R, PART_ARM]
	for pid: String in ids:
		_spawn_chunk(part_world(pid), _rng.randf_range(13.0, 20.0))
	_spawn_chunk(global_position + Vector2(-30.0, -10.0),
		_rng.randf_range(16.0, 24.0))
	_spawn_chunk(global_position + Vector2(34.0, 6.0),
		_rng.randf_range(16.0, 24.0))
	# The detonation walk: parts pop small, hull points medium,
	# then the core goes capital with two more capital bursts —
	# the light system's wobbled rings at their largest scale.
	_death_events = [
		{"t": 0.10, "pos": part_world(PART_TURRET_L),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.30, "pos": part_world(PART_TURRET_R),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.50, "pos": part_world(PART_ARM),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.70, "pos": global_position + Vector2(-40.0, 0.0),
			"cls": LightFx.Size.MEDIUM, "sound": "death_grabber"},
		{"t": 0.90, "pos": global_position + Vector2(40.0, 0.0),
			"cls": LightFx.Size.MEDIUM, "sound": "death_grabber"},
		{"t": 1.10, "pos": global_position,
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
		{"t": 1.22, "pos": global_position + Vector2(-24.0, 10.0),
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
		{"t": 1.34, "pos": global_position + Vector2(24.0, -6.0),
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
	]


func _spawn_chunk(at: Vector2, size: float) -> void:
	var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
	_chunks.append({
		"pos": at, "vel": dir * _rng.randf_range(110.0, 260.0),
		"rot": _rng.randf() * TAU, "rotvel": _rng.randf_range(-6.0, 6.0),
		"size": size, "t": 0.0, "dur": Tuning.BOSS_DEATH_TIME})


func _step_dying(delta: float) -> void:
	_dying_t += delta
	while _death_idx < _death_events.size() \
			and _dying_t >= float(_death_events[_death_idx]["t"]):
		var ev: Dictionary = _death_events[_death_idx]
		_death_idx += 1
		detonated.emit(ev["pos"] as Vector2, int(ev["cls"]),
			Tuning.COLOR_BOSS, String(ev["sound"]))
	for i: int in range(_chunks.size() - 1, -1, -1):
		var ch: Dictionary = _chunks[i]
		ch["t"] = float(ch["t"]) + delta
		var pos: Vector2 = ch["pos"] as Vector2
		var vel: Vector2 = ch["vel"] as Vector2
		ch["pos"] = pos + vel * delta
		ch["rot"] = float(ch["rot"]) + float(ch["rotvel"]) * delta
		_chunks[i] = ch
	if _dying_t >= Tuning.BOSS_DEATH_TIME and not _death_sent:
		_death_sent = true
		death_completed.emit(self)


# --- Drawing ---------------------------------------------------------------------

func _hull_pts() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-95.0, -18.0), Vector2(-58.0, -62.0),
		Vector2(58.0, -62.0), Vector2(95.0, -18.0),
		Vector2(95.0, 28.0), Vector2(58.0, 54.0),
		Vector2(-58.0, 54.0), Vector2(-95.0, 28.0),
		Vector2(-95.0, -18.0)])


func _draw() -> void:
	if phase == Phase.DYING:
		_draw_dying()
		return
	var base: Color = Tuning.COLOR_BOSS
	var dim: Color = base.darkened(0.45)
	_draw_proximity_ring(base)
	draw_polyline(_hull_pts(), base, 2.5, true)
	# Inner deck echo + structure lines.
	var inner: PackedVector2Array = PackedVector2Array([
		Vector2(-70.0, -14.0), Vector2(-40.0, -44.0),
		Vector2(40.0, -44.0), Vector2(70.0, -14.0),
		Vector2(70.0, 20.0), Vector2(40.0, 40.0),
		Vector2(-40.0, 40.0), Vector2(-70.0, 20.0),
		Vector2(-70.0, -14.0)])
	draw_polyline(inner, dim, 1.5, true)
	draw_line(Vector2(-58.0, -62.0), Vector2(-40.0, 40.0), dim, 1.5, true)
	draw_line(Vector2(58.0, -62.0), Vector2(40.0, 40.0), dim, 1.5, true)
	# Core.
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, base, 2.0, true)
	draw_circle(Vector2.ZERO, 4.0, base.lerp(Color.WHITE, 0.5))
	# Hull hit-flash: the whole body answers a hull hit, briefly.
	if _hull_flash > 0.0:
		var fa: float = clampf(_hull_flash / 0.12, 0.0, 1.0)
		draw_polyline(_hull_pts(), Color(Color.WHITE, fa * 0.8), 3.0, true)
	# Radial charge: the core swells and whitens before a ring.
	if _radial_charging:
		var rf: float = clampf(
			1.0 - _radial_t / Tuning.BOSS_RADIAL_CHARGE_TIME, 0.0, 1.0)
		var glow_col: Color = base.lerp(Color.WHITE, rf * 0.85)
		draw_circle(Vector2.ZERO, lerpf(6.0, 20.0, rf),
			Color(base, 0.3 + 0.4 * rf))
		draw_circle(Vector2.ZERO, lerpf(3.0, 11.0, rf), glow_col)
	_draw_part(PART_TURRET_L)
	_draw_part(PART_TURRET_R)
	_draw_part(PART_ARM)
	_draw_arm_telegraph()


## The proximity bonus band, drawn under the hull as broken arc
## segments (this game's linework does not do perfect circles).
## Faint while the player is outside; inside, it brightens and
## pulses — the standing, spatial half of the bonus feedback.
## The ring is drawn in boss-local space, so it may run past the
## arena's top wall and clip there, exactly as a range band should.
func _draw_proximity_ring(base: Color) -> void:
	var alpha: float = 0.10
	var width: float = 1.5
	if proximity_active:
		alpha = 0.34 + 0.12 * sin(_proximity_pulse_t * 6.0)
		width = 2.5
	var col: Color = Color(base, alpha)
	var segments: int = 28
	var gap: float = 0.055 # radians of air at each segment joint
	for i: int in range(segments):
		var a0: float = TAU * float(i) / float(segments) + gap
		var a1: float = TAU * float(i + 1) / float(segments) - gap
		draw_arc(Vector2.ZERO, Tuning.BOSS_PROXIMITY_RADIUS,
			a0, a1, 10, col, width, true)


func _draw_part(part_id: String) -> void:
	var pd: Dictionary = PART_DEFS[part_id] as Dictionary
	var off: Vector2 = pd["offset"] as Vector2
	var r: float = float(pd["radius"])
	var broken: bool = is_part_broken(part_id)
	var state: Dictionary = _parts[part_id] as Dictionary
	var flash: float = float(state["flash"])
	var col: Color = Color(0.25, 0.22, 0.28, 1.0) if broken \
		else Tuning.COLOR_BOSS
	if part_id == PART_ARM:
		# Keel claw on the underside, reaching toward the canisters.
		draw_polyline(PackedVector2Array([
			off + Vector2(-12.0, -14.0), off + Vector2(-6.0, 8.0),
			off + Vector2(-14.0, 18.0)]), col, 2.5, true)
		draw_polyline(PackedVector2Array([
			off + Vector2(12.0, -14.0), off + Vector2(6.0, 8.0),
			off + Vector2(14.0, 18.0)]), col, 2.5, true)
		draw_arc(off, r * 0.55, 0.0, TAU, 20, col, 2.0, true)
	else:
		# Turret cheek + barrel aimed at the player.
		draw_arc(off, r, 0.0, TAU, 24, col, 2.0, true)
		if not broken:
			var aim: Vector2 = _turret_aim[part_id] as Vector2
			draw_line(off, off + aim * (r + 9.0), col, 3.0, true)
	if broken:
		# Break marks: two jagged ticks across the dead part.
		draw_line(off + Vector2(-r * 0.6, -r * 0.3),
			off + Vector2(r * 0.2, r * 0.4), col, 1.5, true)
		draw_line(off + Vector2(r * 0.1, -r * 0.5),
			off + Vector2(r * 0.6, r * 0.3), col, 1.5, true)
	if flash > 0.0 and not broken:
		var fa: float = clampf(flash / 0.15, 0.0, 1.0)
		draw_arc(off, r + 1.5, 0.0, TAU, 24,
			Color(Color.WHITE, fa), 2.5, true)
	# Charge telegraph on the firing turret only: a muzzle glow
	# that grows and whitens — nothing fires unwarned.
	var cf: float = charge_frac(part_id)
	if cf >= 0.0 and not broken:
		var aim2: Vector2 = _turret_aim[part_id] as Vector2
		var muzzle: Vector2 = off + aim2 * (r + 9.0)
		var glow_col2: Color = Tuning.COLOR_BOSS.lerp(
			Color.WHITE, cf * 0.85)
		draw_circle(muzzle, lerpf(2.0, 5.0, cf),
			Color(Tuning.COLOR_BOSS, 0.35 + 0.4 * cf))
		draw_circle(muzzle, lerpf(1.0, 3.0, cf), glow_col2)


func _draw_arm_telegraph() -> void:
	if _arm_state != ArmState.TELEGRAPH or not _arm_target_valid():
		return
	# Pulsing targeting line from the arm mouth to the chosen
	# canister, with a reticle around it: the player's warning.
	var pulse: float = 0.45 + 0.45 * absf(sin(_arm_t * 12.0))
	var col: Color = Color(Tuning.COLOR_STEAL_FLASH, pulse)
	var from: Vector2 = Vector2(0.0, 78.0) # local arm mouth
	var to: Vector2 = to_local(_arm_target.global_position)
	draw_line(from, to, col, 1.5, true)
	draw_arc(to, Tuning.CANISTER_RADIUS + 7.0, 0.0, TAU, 24, col, 1.5, true)


func _draw_dying() -> void:
	var base: Color = Tuning.COLOR_BOSS
	var fade: float = clampf(
		1.0 - _dying_t / Tuning.BOSS_DEATH_TIME, 0.0, 1.0)
	# The hull silhouette holds, dimming, while the detonations
	# walk it; then Main frees the boss and it is gone.
	draw_polyline(_hull_pts(), Color(base, 0.35 + 0.65 * fade), 2.5, true)
	# Torn-off chunks: part-shaped vector shards flying out,
	# rotating, fading with the sequence.
	for ch: Dictionary in _chunks:
		var cpos: Vector2 = ch["pos"] as Vector2
		var local: Vector2 = cpos - global_position
		var sz: float = float(ch["size"])
		var rot: float = float(ch["rot"])
		var cfade: float = clampf(
			1.0 - float(ch["t"]) / float(ch["dur"]), 0.0, 1.0)
		var corners: Array[Vector2] = [
			Vector2(-sz, -sz * 0.6), Vector2(sz, -sz * 0.4),
			Vector2(sz * 0.5, sz), Vector2(-sz * 0.7, sz * 0.8)]
		var pts: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in corners:
			pts.append(local + corner.rotated(rot))
		pts.append(local + corners[0].rotated(rot))
		draw_polyline(pts, Color(base, cfade), 2.0, true)
