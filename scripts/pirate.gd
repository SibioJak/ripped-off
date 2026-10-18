class_name Pirate
extends Node2D
## A pirate, behaviour driven entirely by its EnemyDefs data entry.
## Phases: TELEGRAPH (visible warning at the entry point, cannot
## move) -> SEEK (steer to the nearest stealable canister) -> DRAG
## (latched; haul the canister to the nearest exit) -> LEAVE (no
## canister to take; fly off and despawn). 1 HP: Main resolves
## bullet and ram kills; this script never dies on its own.

enum Phase { TELEGRAPH, SEEK, DRAG, LEAVE }

var phase: Phase = Phase.TELEGRAPH
var type_name: String = "grabber"
var def: Dictionary = {}
var draw_color: Color = Color(1.0, 0.38, 0.3, 1.0)
var radius: float = 13.0
var velocity: Vector2 = Vector2.ZERO
var target: Canister = null
var held: Canister = null
var exit_point: Vector2 = Vector2.ZERO

var _speed: float = 120.0
var _drag_speed: float = 90.0
var _telegraph_t: float = 0.0
var _facing: Vector2 = Vector2.LEFT
var _flash_t: float = 0.0


func _ready() -> void:
	z_index = 5


func setup(p_type: String, spawn_pos: Vector2) -> void:
	type_name = p_type
	def = EnemyDefs.get_def(p_type)
	_speed = float(def.get("speed", 120.0))
	_drag_speed = float(def.get("drag_speed", 90.0))
	radius = float(def.get("radius", 13.0))
	var c: Variant = def.get("color", Color(1.0, 0.38, 0.3, 1.0))
	if typeof(c) == TYPE_COLOR:
		draw_color = c as Color
	global_position = spawn_pos
	_facing = (Tuning.depot_center() - spawn_pos).normalized()
	_telegraph_t = Tuning.TELEGRAPH_TIME
	phase = Phase.TELEGRAPH


func score_value() -> int:
	return int(def.get("score", 100))


func shard_count() -> int:
	return int(def.get("shards", 4))


func step(delta: float, canisters: Array[Canister]) -> void:
	_flash_t += delta
	match phase:
		Phase.TELEGRAPH:
			velocity = Vector2.ZERO
			_telegraph_t -= delta
			if _telegraph_t <= 0.0:
				phase = Phase.SEEK
		Phase.SEEK:
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
						phase = Phase.DRAG
						exit_point = Tuning.nearest_exit_point(global_position)
		Phase.DRAG:
			if held == null or held.state != Canister.State.DRAGGING:
				held = null
				phase = Phase.SEEK
			else:
				_steer_toward(exit_point, _drag_speed, delta)
				# The canister trails just behind the pirate's nose.
				held.global_position = global_position - _facing * 24.0
		Phase.LEAVE:
			_steer_toward(exit_point, _speed, delta)
	queue_redraw()


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
	velocity = _facing * speed
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
