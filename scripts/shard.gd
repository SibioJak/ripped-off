class_name Shard
extends Node2D
## A salvage shard: burst out of a kill, drifts, blinks as it
## nears expiry, and flies to the player inside the magnet radius.
## Collection (and its score/multiplier effect) is Main's job.

var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0

var _age: float = 0.0


func _ready() -> void:
	z_index = 3


func setup(from: Vector2, burst_dir: Vector2, burst_speed: float) -> void:
	global_position = from
	velocity = burst_dir * burst_speed
	life = Tuning.SHARD_LIFE
	_age = 0.0


func step(delta: float, player_pos: Vector2, player_alive: bool) -> void:
	_age += delta
	life -= delta
	if player_alive:
		var to: Vector2 = player_pos - global_position
		var dist: float = to.length()
		if dist > 0.5 and dist <= Tuning.SHARD_MAGNET_RADIUS:
			velocity = to.normalized() * Tuning.SHARD_MAGNET_SPEED
		else:
			velocity = velocity.limit_length(
				Tuning.SHARD_BURST_SPEED * Tuning.SHARD_DRIFT_KEEP)
	else:
		velocity = velocity.limit_length(
			Tuning.SHARD_BURST_SPEED * Tuning.SHARD_DRIFT_KEEP)
	global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, 6.0)
	queue_redraw()


func expired() -> bool:
	return life <= 0.0


func _draw() -> void:
	if life < Tuning.SHARD_BLINK_TIME and int(_age * 10.0) % 2 == 0:
		return # blink off while expiring
	var s: float = 6.0
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -s), Vector2(s, 0.0), Vector2(0.0, s),
		Vector2(-s, 0.0), Vector2(0.0, -s)])
	draw_polyline(pts, Tuning.COLOR_SHARD, 2.0, true)
	draw_circle(Vector2.ZERO, 1.6, Tuning.COLOR_SHARD.lerp(Color.WHITE, 0.6))
