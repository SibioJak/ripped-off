class_name Pirate
extends Node2D
## A pirate, behaviour driven entirely by its EnemyDefs data entry.
## Phases: TELEGRAPH (visible warning at the entry point, cannot
## move) -> SEEK -> DRAG -> LEAVE. What SEEK means depends on the
## def's role: a "thief" hunts the nearest stealable canister and
## DRAGs it to an exit; a "shooter" flies to a standoff point and
## HOLDs, strafing in its range band and firing aimed shots, each
## one announced by a visible muzzle charge-up. 1 HP: Main
## resolves bullet and ram kills; this script never dies on its
## own.

signal fired(from: Vector2, dir: Vector2)

enum Phase { TELEGRAPH, SEEK, DRAG, LEAVE, HOLD }

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
	_fire_t = _fire_interval * randf_range(0.75, 1.1) # first shot is not instant
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	var c: Variant = def.get("color", Color(1.0, 0.38, 0.3, 1.0))
	if typeof(c) == TYPE_COLOR:
		draw_color = c as Color
	global_position = spawn_pos
	_facing = (Tuning.depot_center() - spawn_pos).normalized()
	_telegraph_t = Tuning.TELEGRAPH_TIME
	phase = Phase.TELEGRAPH


## 0..1 charge-up progress while the muzzle glow winds up, else -1.
func charge_frac() -> float:
	if not _charging:
		return -1.0
	return clampf(1.0 - _charge_t / Tuning.GUNNER_CHARGE_TIME, 0.0, 1.0)


## The point a shot leaves from: the nose of the ship.
func muzzle_pos() -> Vector2:
	return global_position + _facing * (radius + 5.0)


func score_value() -> int:
	return int(def.get("score", 100))


func shard_count() -> int:
	return int(def.get("shards", 4))


func step(delta: float, canisters: Array[Canister]) -> void:
	_flash_t += delta
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
		Phase.SEEK:
			if _role == "shooter":
				_step_shooter_seek(delta)
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
			_charge_t = Tuning.GUNNER_CHARGE_TIME


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
