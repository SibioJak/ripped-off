class_name Powerup
extends Node2D
## A powerup drop on the field: drifts slowly off the kill point,
## lives Tuning.POWERUP_LIFETIME seconds, and blinks over the
## final POWERUP_BLINK_TIME before despawning (the shard cadence).
## It does NOT home — flying to it is the cost. Collection (and
## activation on the player) is Main's job; the glyph and colour
## come from PowerupDefs, the same drawing the HUD and the title
## legend use.

var type_id: String = ""
var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0

var _age: float = 0.0


func _ready() -> void:
	z_index = 3


func setup(from: Vector2, p_type_id: String, drift_vel: Vector2) -> void:
	global_position = from
	type_id = p_type_id
	velocity = drift_vel
	life = Tuning.POWERUP_LIFETIME
	_age = 0.0


func step(delta: float) -> void:
	_age += delta
	life -= delta
	global_position += velocity * delta
	global_position = Tuning.clamp_inside(global_position, 14.0)
	queue_redraw()


func expired() -> bool:
	return life <= 0.0


func _draw() -> void:
	if life < Tuning.POWERUP_BLINK_TIME and int(_age * 10.0) % 2 == 0:
		return # blink off while expiring (the shard pattern)
	var col: Color = PowerupDefs.color_of(type_id)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32,
		Color(col, 0.55), 1.5, true)
	PowerupDefs.draw_glyph(self, type_id, Vector2.ZERO, 1.0)
