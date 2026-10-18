class_name Player
extends Node2D
## The player ship: DIRECT twin-stick. Velocity is driven toward
## the input vector at a high acceleration, so the ship goes where
## the stick points and stops when the stick stops. There is
## deliberately NO zero-g drift or inertia model — a design
## decision from the Ripped-Off design document, not an omission.
##
## Aim: mouse position, right stick, or the arrow keys (keyboard
## twin-stick fallback — holding an arrow aims AND fires that way).
## Ram: Main resolves contact; this script just reports speed.

signal fired(from: Vector2, dir: Vector2)

var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var alive: bool = true
var invincible_t: float = 0.0
var respawn_t: float = 0.0
var fire_cd: float = 0.0
var towed: Canister = null


func _ready() -> void:
	z_index = 5


func speed_now() -> float:
	return velocity.length()


func is_invincible() -> bool:
	return invincible_t > 0.0


func reset_for_run(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	velocity = Vector2.ZERO
	facing = Vector2.UP
	alive = true
	visible = true
	invincible_t = 0.0
	respawn_t = 0.0
	fire_cd = 0.0
	towed = null


func die() -> void:
	alive = false
	visible = false
	velocity = Vector2.ZERO
	if towed != null:
		var c: Canister = towed
		towed = null
		c.release_tow(Vector2.ZERO)


func respawn(spawn_pos: Vector2) -> void:
	global_position = spawn_pos
	velocity = Vector2.ZERO
	alive = true
	visible = true
	invincible_t = Tuning.PLAYER_INVINCIBLE_TIME
	fire_cd = 0.0


func step(delta: float, allow_input: bool) -> void:
	if not alive:
		respawn_t = maxf(respawn_t - delta, 0.0)
		return
	invincible_t = maxf(invincible_t - delta, 0.0)
	fire_cd = maxf(fire_cd - delta, 0.0)

	var move: Vector2 = Vector2.ZERO
	var aim: Vector2 = Vector2.ZERO
	var firing: bool = false
	if allow_input:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var stick_aim: Vector2 = Input.get_vector(
			"aim_left", "aim_right", "aim_up", "aim_down")
		if stick_aim.length() > 0.25:
			aim = stick_aim.normalized()
			firing = true # twin-stick: pointing the aim stick fires
		else:
			var mouse: Vector2 = get_global_mouse_position()
			if mouse.distance_squared_to(global_position) > 9.0:
				aim = (mouse - global_position).normalized()
		firing = firing or Input.is_action_pressed("fire")

	if aim != Vector2.ZERO:
		facing = aim
	elif move != Vector2.ZERO:
		facing = move.normalized()

	# Direct drive: accelerate hard toward the stick's velocity.
	var target_vel: Vector2 = move * Tuning.PLAYER_SPEED
	velocity = velocity.move_toward(target_vel, Tuning.PLAYER_ACCEL * delta)
	global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, Tuning.PLAYER_RADIUS)

	if firing and fire_cd <= 0.0:
		fire_cd = Tuning.PLAYER_FIRE_INTERVAL
		fired.emit(global_position + facing * (Tuning.PLAYER_RADIUS + 5.0), facing)

	# Invincibility blink.
	if invincible_t > 0.0:
		visible = int(invincible_t * 14.0) % 2 == 0
	else:
		visible = true
	queue_redraw()


func _draw() -> void:
	if not alive:
		return
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2.ONE)
	var col: Color = Tuning.COLOR_PLAYER
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(18.0, 0.0), Vector2(-12.0, 10.0),
		Vector2(-7.0, 0.0), Vector2(-12.0, -10.0), Vector2(18.0, 0.0)])
	draw_polyline(pts, col, 2.0, true)
	var core: Color = col.lerp(Color.WHITE, 0.6)
	draw_line(Vector2(10.0, 0.0), Vector2(-5.0, 0.0), core, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
