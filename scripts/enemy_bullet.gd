class_name EnemyBullet
extends Node2D
## A straight enemy bullet, fired by shooter-class pirates. Main
## owns collision (player hit, buzz near-miss); this script only
## flies and ages. Drawn bright-core/dark-rim and layered ABOVE
## player bullets and ships, so hostile fire always wins the
## value read (the readability doctrine from the design doc).

var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0
var buzzed: bool = false # a bullet can pay out buzz exactly once


func _ready() -> void:
	z_index = 7 # player bullets sit at 6, ships at 5


func setup(from: Vector2, dir: Vector2) -> void:
	global_position = from
	velocity = dir.normalized() * Tuning.ENEMY_BULLET_SPEED
	life = Tuning.ENEMY_BULLET_LIFE
	buzzed = false


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
	# Dark rim first, bright core on top: reads at any brightness.
	draw_circle(Vector2.ZERO, Tuning.ENEMY_BULLET_RADIUS + 2.0,
		Tuning.COLOR_ENEMY_BULLET_RIM)
	draw_circle(Vector2.ZERO, Tuning.ENEMY_BULLET_RADIUS,
		Tuning.COLOR_ENEMY_BULLET_CORE)
	draw_circle(Vector2.ZERO, 1.6, Color.WHITE)
