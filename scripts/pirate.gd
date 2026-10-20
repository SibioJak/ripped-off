class_name Pirate
extends Node2D
## A pirate, behaviour driven entirely by its EnemyDefs data entry.
## Phases: TELEGRAPH (visible warning at the entry point, cannot
## move) -> SEEK -> DRAG -> LEAVE. What SEEK means depends on the
## def's role: a "thief" hunts the nearest stealable canister and
## DRAGs it to an exit; a "shooter" flies to a standoff point and
## HOLDs, strafing in its range band and firing aimed shots, each
## one announced by a visible muzzle charge-up; a "hunter" (M6)
## never looks at a canister at all — it pursues the player,
## strafes around them at orbit range and fires lead shots, and
## like the shooter it holds its hunt until killed. A shooter can
## also enter CONVERT (M7): when no getter is working, Main orders
## it to reshape — plates fold, a latch claw unfolds, the colour
## cross-fades to the grabber's coral — and it comes out of the
## reshape a thief in the same gunner hull. 1 HP: Main resolves
## bullet and ram kills; this script never dies on its own.

signal fired(from: Vector2, dir: Vector2)
signal convert_stage(stage: int)

enum Phase { TELEGRAPH, SEEK, DRAG, LEAVE, HOLD, CONVERT }

var phase: Phase = Phase.TELEGRAPH
var type_name: String = "grabber"
var def: Dictionary = {}
var draw_color: Color = Color(1.0, 0.38, 0.3, 1.0)
var radius: float = 13.0
var velocity: Vector2 = Vector2.ZERO
var target: Canister = null
var held: Canister = null
var exit_point: Vector2 = Vector2.ZERO

## Context Main pushes in every frame before stepping.
var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.ZERO # the hunter leads its shots by this
var player_alive: bool = false
var speed_scale: float = 1.0 # rank scaling, from Tuning via Main
var fire_interval_scale: float = 1.0 # rank scaling, from Tuning via Main

## Buzz bookkeeping: Main sets this after paying a drag-pass buzz;
## it resets when this pirate latches a fresh canister.
var buzzed_this_drag: bool = false

## Seconds spent continuously in LEAVE. Main's exit watchdog reads
## this: a leaver older than Tuning.EXIT_WATCHDOG_TIME is force-
## freed, so no pirate can block wave progression indefinitely.
var exit_age: float = 0.0

var _speed: float = 120.0
var _drag_speed: float = 90.0
var _telegraph_t: float = 0.0
var _facing: Vector2 = Vector2.LEFT
var _flash_t: float = 0.0

# Shooter-only state (read from the def; inert for thieves).
var _role: String = "thief"
var _fire_interval: float = 2.2
var _standoff_min: float = 260.0
var _standoff_max: float = 340.0
var _strafe_speed: float = 55.0
var _anchor: Vector2 = Vector2.ZERO
var _anchor_set: bool = false
var _strafe_dir: float = 1.0
var _fire_t: float = 0.0
var _charging: bool = false
var _charge_t: float = 0.0
var _charge_time: float = Tuning.GUNNER_CHARGE_TIME # per role, set in setup

# Conversion state (M7). The clock runs only in Phase.CONVERT;
# _convert_from_color is the gunner's colour at the start of the
# reshape and _grabber_color (cached in setup from the grabber
# def) is where the cross-fade lands — at completion draw_color
# IS the grabber colour, exactly. _alive_t is this pirate's age
# in stepped seconds: Main's oldest-first conversion pick reads
# it. Stage signals fire once each, in order: 1 and 2 at the
# third boundaries, 3 at completion.
var _alive_t: float = 0.0
var _convert_t: float = 0.0
var _convert_stage_emitted: int = 0
var _convert_from_color: Color = Color(0.66, 0.42, 1.0, 1.0)
var _grabber_color: Color = Color(1.0, 0.38, 0.3, 1.0)


func _ready() -> void:
	z_index = 5


func setup(p_type: String, spawn_pos: Vector2) -> void:
	type_name = p_type
	def = EnemyDefs.get_def(p_type)
	_speed = float(def.get("speed", 120.0))
	_drag_speed = float(def.get("drag_speed", 90.0))
	radius = float(def.get("radius", 13.0))
	_role = String(def.get("role", "thief"))
	_fire_interval = float(def.get("fire_interval", 2.2))
	_standoff_min = float(def.get("standoff_min", 260.0))
	_standoff_max = float(def.get("standoff_max", 340.0))
	_strafe_speed = float(def.get("strafe_speed", 55.0))
	_charge_time = Tuning.HUNTER_CHARGE_TIME if _role == "hunter" \
		else Tuning.GUNNER_CHARGE_TIME
	_fire_t = _fire_interval * randf_range(0.75, 1.1) # first shot is not instant
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	var c: Variant = def.get("color", Color(1.0, 0.38, 0.3, 1.0))
	if typeof(c) == TYPE_COLOR:
		draw_color = c as Color
	# The conversion cross-fade's destination: the grabber def's
	# colour, cached once (a convert must end up EXACTLY coral).
	var grabber_def: Dictionary = EnemyDefs.get_def("grabber")
	var gc: Variant = grabber_def.get("color", Color(1.0, 0.38, 0.3, 1.0))
	if typeof(gc) == TYPE_COLOR:
		_grabber_color = gc as Color
	global_position = spawn_pos
	_facing = (Tuning.depot_center() - spawn_pos).normalized()
	_telegraph_t = Tuning.TELEGRAPH_TIME
	phase = Phase.TELEGRAPH


## 0..1 charge-up progress while the muzzle glow winds up, else -1.
func charge_frac() -> float:
	if not _charging:
		return -1.0
	return clampf(1.0 - _charge_t / _charge_time, 0.0, 1.0)


## The point a shot leaves from: the nose of the ship.
func muzzle_pos() -> Vector2:
	return global_position + _facing * (radius + 5.0)


func score_value() -> int:
	return int(def.get("score", 100))


func shard_count() -> int:
	return int(def.get("shards", 4))


## The role the pirate is CURRENTLY working — the def's role
## until a conversion completes, "thief" from that moment on.
## Main's conversion watcher and the draw marks read this, never
## the def, so a converted gunner counts as the getter it became.
func current_role() -> String:
	return _role


func is_converting() -> bool:
	return phase == Phase.CONVERT


## Stepped seconds since spawn (Main's oldest-first pick).
func alive_time() -> float:
	return _alive_t


## Begin the reshape (M7). Only a working shooter can convert —
## from its SEEK entry flight or its HOLD post — and only once:
## the phase gate makes a second order a no-op. Any muzzle charge
## in progress is cancelled outright, so no shot can ever leave a
## reshaping ship, and the gun goes silent from this frame.
func begin_conversion() -> void:
	if _role != "shooter":
		return
	if phase != Phase.SEEK and phase != Phase.HOLD:
		return
	phase = Phase.CONVERT
	_convert_t = 0.0
	_convert_stage_emitted = 0
	_convert_from_color = draw_color
	_charging = false
	_charge_t = 0.0
	velocity = Vector2.ZERO
	queue_redraw()


func step(delta: float, canisters: Array[Canister]) -> void:
	_flash_t += delta
	_alive_t += delta
	if phase == Phase.LEAVE:
		exit_age += delta
	else:
		exit_age = 0.0
	match phase:
		Phase.TELEGRAPH:
			velocity = Vector2.ZERO
			_charging = false
			_telegraph_t -= delta
			if _telegraph_t <= 0.0:
				phase = Phase.SEEK
		Phase.CONVERT:
			_step_convert(delta)
		Phase.SEEK:
			if _role == "shooter":
				_step_shooter_seek(delta)
			elif _role == "hunter":
				_step_hunter(delta)
			else:
				_step_thief_seek(delta, canisters)
		Phase.DRAG:
			if held == null or held.state != Canister.State.DRAGGING:
				held = null
				phase = Phase.SEEK
			else:
				_steer_toward(exit_point, _drag_speed, delta)
				# The canister trails just behind the pirate's nose.
				held.global_position = global_position - _facing * 24.0
		Phase.HOLD:
			_step_shooter_hold(delta)
		Phase.LEAVE:
			_steer_toward(exit_point, _speed, delta)
	queue_redraw()


func _step_thief_seek(delta: float, canisters: Array[Canister]) -> void:
	if not _target_valid():
		target = _find_target(canisters)
	if target == null:
		_enter_leave()
	else:
		_steer_toward(target.global_position, _speed, delta)
		if global_position.distance_to(target.global_position) \
				<= Tuning.PIRATE_LATCH_DIST:
			if target.begin_drag(self):
				held = target
				target = null
				buzzed_this_drag = false # a fresh drag can be buzzed again
				phase = Phase.DRAG
				exit_point = Tuning.nearest_exit_point(global_position)


## The reshape (M7): the ship holds its position and rebuilds
## itself over CONVERT_TIME. It cannot fire (the charge was
## cancelled at the order), cannot latch, cannot move — the
## transformation IS the telegraph, and it stays fully killable
## throughout: a pirate shot mid-reshape dies a gunner. The
## colour cross-fades to the grabber's coral as the staging runs;
## at completion the role flips and the plain thief SEEK takes
## over in this same hull (its gunner score and shards stay —
## type_name never changes).
func _step_convert(delta: float) -> void:
	velocity = Vector2.ZERO
	_convert_t += delta
	var frac: float = clampf(_convert_t / Tuning.CONVERT_TIME, 0.0, 1.0)
	draw_color = _convert_from_color.lerp(_grabber_color, frac)
	if _convert_stage_emitted < 1 and frac >= 1.0 / 3.0:
		_convert_stage_emitted = 1
		convert_stage.emit(1)
	if _convert_stage_emitted < 2 and frac >= 2.0 / 3.0:
		_convert_stage_emitted = 2
		convert_stage.emit(2)
	if frac >= 1.0:
		_role = "thief"
		phase = Phase.SEEK
		draw_color = _grabber_color
		convert_stage.emit(3)


## Shooter entry: fly to a standoff point in the def's range band
## (measured from the depot centre), then hold there.
func _step_shooter_seek(delta: float) -> void:
	if not _anchor_set:
		_anchor_set = true
		var mid: float = (_standoff_min + _standoff_max) * 0.5
		var outward: Vector2 = global_position - Tuning.depot_center()
		if outward.length() < 1.0:
			outward = Vector2.RIGHT
		_anchor = Tuning.clamp_inside(
			Tuning.depot_center() + outward.normalized() * mid, radius + 18.0)
	_steer_toward(_anchor, _speed, delta)
	if global_position.distance_to(_anchor) <= 14.0:
		phase = Phase.HOLD


## Shooter at its post: strafe slowly around the depot, stay inside
## the range band, face the player, and run the fire cycle. Every
## shot is announced: the muzzle charges for GUNNER_CHARGE_TIME
## before the bullet exists. No firing from any other phase, and
## never while off-screen or while the player is down.
func _step_shooter_hold(delta: float) -> void:
	var center: Vector2 = Tuning.depot_center()
	var rel: Vector2 = global_position - center
	var dist: float = rel.length()
	var radial: Vector2 = rel.normalized() if dist > 0.5 else Vector2.RIGHT
	var tangent: Vector2 = radial.rotated(PI * 0.5) * _strafe_dir
	var mid: float = (_standoff_min + _standoff_max) * 0.5
	var radial_fix: float = clampf((mid - dist) * 2.0,
		-_strafe_speed, _strafe_speed)
	velocity = (tangent * _strafe_speed + radial * radial_fix) * speed_scale
	global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, radius)
	if player_alive:
		_facing = (player_pos - global_position).normalized()

	if _charging:
		_charge_t -= delta
		if _charge_t <= 0.0:
			_charging = false
			_fire_t = _fire_interval * fire_interval_scale \
				* randf_range(0.9, 1.1)
			if player_alive and Tuning.arena_rect().has_point(global_position):
				var dir: Vector2 = (player_pos - muzzle_pos()).normalized()
				if dir != Vector2.ZERO:
					fired.emit(muzzle_pos(), dir)
	elif player_alive:
		_fire_t -= delta
		if _fire_t <= 0.0:
			_charging = true
			_charge_t = _charge_time


## Hunter: the direct-challenge class. It never targets, latches
## or drags a canister — its target is the player, always. It
## closes at full speed until it reaches HUNTER_ORBIT_RANGE, then
## strafes tangentially around the player (orbit direction rolled
## once per spawn, in setup) while a radial correction holds the
## band. Its fire cycle mirrors the gunner's exactly — charge
## first, nothing from any other phase, nothing while the player
## is down, nothing from off-screen — but the shot itself is LED:
## aimed at player_pos + player_vel x time-of-flight x
## HUNTER_LEAD_FACTOR, so a steady strafe is punished and a
## direction change beats it. Like the gunner, it has no exit of
## its own: it holds its hunt until killed.
func _step_hunter(delta: float) -> void:
	var to_player: Vector2 = player_pos - global_position
	var dist: float = to_player.length()
	if player_alive and dist > 0.5:
		_facing = to_player / dist
	if dist > Tuning.HUNTER_ORBIT_RANGE:
		_steer_toward(player_pos, _speed, delta)
	else:
		var radial: Vector2 = Vector2.RIGHT # outward, away from the player
		if dist > 0.5:
			radial = -to_player / dist
		var tangent: Vector2 = radial.rotated(PI * 0.5) * _strafe_dir
		var radial_fix: float = clampf(
			(Tuning.HUNTER_ORBIT_RANGE - dist) * 2.0, -_speed, _speed)
		var desired: Vector2 = tangent * _speed + radial * radial_fix
		if desired.length() > _speed:
			desired = desired.normalized() * _speed
		velocity = desired * speed_scale
		global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, radius)

	if _charging:
		_charge_t -= delta
		if _charge_t <= 0.0:
			_charging = false
			_fire_t = _fire_interval * fire_interval_scale \
				* randf_range(0.9, 1.1)
			if player_alive and Tuning.arena_rect().has_point(global_position):
				var from: Vector2 = muzzle_pos()
				var tof: float = from.distance_to(player_pos) \
					/ Tuning.ENEMY_BULLET_SPEED
				var lead_point: Vector2 = player_pos \
					+ player_vel * tof * Tuning.HUNTER_LEAD_FACTOR
				var dir: Vector2 = (lead_point - from).normalized()
				if dir != Vector2.ZERO:
					fired.emit(from, dir)
	elif player_alive:
		_fire_t -= delta
		if _fire_t <= 0.0:
			_charging = true
			_charge_t = _charge_time


func _target_valid() -> bool:
	return target != null and is_instance_valid(target) \
		and target.is_available_target()


func _find_target(canisters: Array[Canister]) -> Canister:
	var best: Canister = null
	var best_d: float = INF
	for c: Canister in canisters:
		if c.is_available_target():
			var d: float = global_position.distance_squared_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
	return best


func _enter_leave() -> void:
	phase = Phase.LEAVE
	exit_point = Tuning.nearest_exit_point(global_position)


func _steer_toward(point: Vector2, speed: float, delta: float) -> void:
	var to: Vector2 = point - global_position
	if to.length() > 1.0:
		_facing = to.normalized()
	velocity = _facing * speed * speed_scale
	global_position += velocity * delta


func _draw() -> void:
	if phase == Phase.TELEGRAPH:
		# Flashing entry warning: ring + cross in the pirate's colour.
		var a: float = 0.35 + 0.6 * absf(sin(_flash_t * 10.0))
		var col: Color = Color(draw_color, a)
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, col, 2.0, true)
		draw_line(Vector2(-11.0, -11.0), Vector2(11.0, 11.0), col, 2.0, true)
		draw_line(Vector2(-11.0, 11.0), Vector2(11.0, -11.0), col, 2.0, true)
		return
	if phase == Phase.CONVERT:
		_draw_convert()
		return
	draw_set_transform(Vector2.ZERO, _facing.angle(), Vector2.ONE)
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(16.0, 0.0), Vector2(-6.0, 11.0), Vector2(-12.0, 5.0),
		Vector2(-12.0, -5.0), Vector2(-6.0, -11.0), Vector2(16.0, 0.0)])
	draw_polyline(pts, draw_color, 2.0, true)
	var eye: Color = draw_color.lerp(Color.WHITE, 0.7)
	draw_circle(Vector2(4.0, 0.0), 2.5, eye)
	if _role == "shooter":
		# Broadside cheek plates mark the gunner silhouette apart.
		draw_line(Vector2(-2.0, -13.0), Vector2(8.0, -9.0), draw_color, 2.0, true)
		draw_line(Vector2(-2.0, 13.0), Vector2(8.0, 9.0), draw_color, 2.0, true)
	if _role == "hunter":
		# Swept rear fins mark the hunter silhouette apart.
		draw_line(Vector2(-10.0, -6.0), Vector2(-19.0, -13.0), draw_color, 2.0, true)
		draw_line(Vector2(-10.0, 6.0), Vector2(-19.0, 13.0), draw_color, 2.0, true)
	if _role == "thief":
		# The latch claw, open at the nose: the getter's standing
		# mark — natural grabbers and completed converts alike.
		_draw_claw(1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Charge-up telegraph: a muzzle glow that grows and whitens as
	# the shot nears — nothing fires without this warning.
	var frac: float = charge_frac()
	if frac >= 0.0:
		var glow_pos: Vector2 = _facing * (radius + 5.0)
		var glow_col: Color = draw_color.lerp(Color.WHITE, frac * 0.85)
		draw_circle(glow_pos, lerpf(2.0, 4.5, frac),
			Color(draw_color, 0.35 + 0.4 * frac))
		draw_circle(glow_pos, lerpf(1.0, 2.6, frac), glow_col)


func _ease_out(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)


## The latch claw at the nose: two mandible lines from fixed
## roots either side of the nose, their tips travelling from the
## folded pose (tucked back along the nose flanks) to the open
## pose (forward pincers) as open_f runs 0 -> 1. Drawn in the
## ship's local (facing) space, like every other mark.
func _draw_claw(open_f: float) -> void:
	var root_a: Vector2 = Vector2(15.0, -3.0)
	var root_b: Vector2 = Vector2(15.0, 3.0)
	var tip_a: Vector2 = Vector2(8.0, -5.5).lerp(
		Vector2(24.0, -9.0), open_f)
	var tip_b: Vector2 = Vector2(8.0, 5.5).lerp(
		Vector2(24.0, 9.0), open_f)
	draw_line(root_a, tip_a, draw_color, 2.0, true)
	draw_line(root_b, tip_b, draw_color, 2.0, true)


## The reshape, drawn (M7): a dedicated staging path, not the
## role branches — the gunner's marks fold away while the
## thief's claw unfolds, the hull breathes through a scale
## pulse, and the colour (already cross-fading in _step_convert)
## lands on coral. Beat 1 (frac 0 -> 0.34): the cheek plates
## lerp from their drawn positions to tucked positions flush
## against the hull's aft edges. Beat 2 (frac 0.33 -> 0.67):
## the claw unfolds at the nose, ease-out. Beat 3: the claw
## stands open and the last of the colour lands — at completion
## the plain thief draw takes over with the claw already out,
## so the silhouette never pops.
func _draw_convert() -> void:
	var frac: float = clampf(_convert_t / Tuning.CONVERT_TIME, 0.0, 1.0)
	var fold_f: float = _ease_out(clampf(frac / 0.34, 0.0, 1.0))
	var claw_f: float = _ease_out(clampf((frac - 0.33) / 0.34, 0.0, 1.0))
	var pulse: float = 1.0 + 0.15 * sin(PI * frac)
	draw_set_transform(Vector2.ZERO, _facing.angle(),
		Vector2.ONE * pulse)
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(16.0, 0.0), Vector2(-6.0, 11.0), Vector2(-12.0, 5.0),
		Vector2(-12.0, -5.0), Vector2(-6.0, -11.0), Vector2(16.0, 0.0)])
	draw_polyline(pts, draw_color, 2.0, true)
	var eye: Color = draw_color.lerp(Color.WHITE, 0.7)
	draw_circle(Vector2(4.0, 0.0), 2.5, eye)
	# Beat 1: cheek plates fold flat against the hull.
	var plate_a0: Vector2 = Vector2(-2.0, -13.0).lerp(
		Vector2(3.0, -5.5), fold_f)
	var plate_a1: Vector2 = Vector2(8.0, -9.0).lerp(
		Vector2(-6.0, -10.5), fold_f)
	var plate_b0: Vector2 = Vector2(-2.0, 13.0).lerp(
		Vector2(3.0, 5.5), fold_f)
	var plate_b1: Vector2 = Vector2(8.0, 9.0).lerp(
		Vector2(-6.0, 10.5), fold_f)
	draw_line(plate_a0, plate_a1, draw_color, 2.0, true)
	draw_line(plate_b0, plate_b1, draw_color, 2.0, true)
	# Beat 2: the claw unfolds at the nose.
	_draw_claw(claw_f)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
