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

# The ONE active powerup (M5): its id, seconds left, and the full
# duration it was picked up with (the HUD chip's timer fraction).
# A pickup replaces the running powerup with a fresh timer;
# death clears it and respawning never restores it.
var powerup_id: String = ""
var powerup_t: float = 0.0
var _powerup_dur: float = 0.0


func _ready() -> void:
	z_index = 5


func speed_now() -> float:
	return velocity.length()


# --- Powerup state (M5) -------------------------------------------------

func activate_powerup(p_type_id: String) -> void:
	powerup_id = p_type_id
	_powerup_dur = PowerupDefs.duration_of(p_type_id)
	powerup_t = _powerup_dur


func clear_powerup() -> void:
	powerup_id = ""
	powerup_t = 0.0
	_powerup_dur = 0.0


func has_powerup(p_type_id: String) -> bool:
	return powerup_id == p_type_id


## Remaining fraction of the active powerup's timer, 0..1 (the
## HUD chip bar). 0 when nothing is active.
func powerup_fraction() -> float:
	if _powerup_dur <= 0.0:
		return 0.0
	return clampf(powerup_t / _powerup_dur, 0.0, 1.0)


## The fire interval the gun actually runs at (rapid halves it).
func effective_fire_interval() -> float:
	if powerup_id == "rapid":
		return Tuning.PLAYER_FIRE_INTERVAL * Tuning.POWERUP_RAPID_FIRE_SCALE
	return Tuning.PLAYER_FIRE_INTERVAL


## The top speed the drive targets (overthrust raises it).
func move_speed_cap() -> float:
	if powerup_id == "overthrust":
		return Tuning.PLAYER_SPEED * Tuning.POWERUP_OVERTHRUST_SPEED_SCALE
	return Tuning.PLAYER_SPEED


## Shield check, called by Main.kill_player BEFORE any death
## cost lands: if the shield is up it eats the hit instead — the
## shield ends and the ship gets a short invincibility window so
## the same overlap cannot re-kill on the next frame. Returns
## true when the hit was absorbed (the player survives untouched).
func try_consume_shield() -> bool:
	if powerup_id != "shield":
		return false
	clear_powerup()
	invincible_t = maxf(invincible_t,
		Tuning.POWERUP_SHIELD_INVINCIBLE_TIME)
	return true


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
	clear_powerup()


func die() -> void:
	alive = false
	visible = false
	velocity = Vector2.ZERO
	clear_powerup() # death costs the active powerup (design doc)
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
	if powerup_t > 0.0:
		powerup_t = maxf(powerup_t - delta, 0.0)
		if powerup_t <= 0.0:
			clear_powerup() # timed out (shield included, if unused)

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
	var target_vel: Vector2 = move * move_speed_cap()
	velocity = velocity.move_toward(target_vel, Tuning.PLAYER_ACCEL * delta)
	global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, Tuning.PLAYER_RADIUS)

	if firing and fire_cd <= 0.0:
		fire_cd = effective_fire_interval()
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
	# The shield, drawn unrotated around the ship while it is up:
	# a breathing ring in the shield's own blue.
	if powerup_id == "shield":
		var pulse: float = 0.6 + 0.3 * sin(
			float(Time.get_ticks_msec()) * 0.006)
		draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 40,
			Color(Tuning.COLOR_POWERUP_SHIELD, pulse), 2.0, true)
