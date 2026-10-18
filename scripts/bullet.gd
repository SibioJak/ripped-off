class_name Bullet
extends Node2D
## A straight player bullet. Main owns collision; this script only
## flies and ages.

var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0


func _ready() -> void:
	z_index = 6


func setup(from: Vector2, dir: Vector2) -> void:
	global_position = from
	velocity = dir.normalized() * Tuning.BULLET_SPEED
	life = Tuning.BULLET_LIFE


func step(delta: float) -> void:
	global_position += velocity * delta
	life -= delta
	queue_redraw()


func expired() -> bool:
	if life <= 0.0:
		return true
	var r: Rect2 = Tuning.arena_rect().grow(24.0)
	return not r.has_point(global_position)


func _draw() -> void:
	var dir: Vector2 = velocity.normalized()
	draw_line(-dir * 7.0, dir * 7.0, Tuning.COLOR_BULLET, 3.0, true)
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
