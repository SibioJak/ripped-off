class_name EnemyBullet
extends Node2D
## A straight enemy bullet, fired by shooter-class pirates. Main
## owns collision (player hit, buzz near-miss); this script only
## flies and ages. Drawn bright-core/dark-rim and layered ABOVE
## player bullets and ships, so hostile fire always wins the
## value read (the readability doctrine from the design doc).
##
## Every hostile bullet also BREATHES (M8): the core's brightness
## and radius pulse off one shared clock, in sync across all
## enemy fire — pirates' shots and the Dreadnought's tinted
## shells alike — while player bullets stay dead steady. Motion
## is the differentiator: hostile fire shimmers, yours does not.

var velocity: Vector2 = Vector2.ZERO
var life: float = 0.0
var buzzed: bool = false # a bullet can pay out buzz exactly once
var core_color: Color = Tuning.COLOR_ENEMY_BULLET_CORE
var rim_color: Color = Tuning.COLOR_ENEMY_BULLET_RIM


func _ready() -> void:
	z_index = 7 # player bullets sit at 6, ships at 5


func setup(from: Vector2, dir: Vector2) -> void:
	global_position = from
	velocity = dir.normalized() * Tuning.ENEMY_BULLET_SPEED
	life = Tuning.ENEMY_BULLET_LIFE
	buzzed = false


## Per-shot colours (M4: the Dreadnought fires a hot-magenta
## variant). Same bullet, same rules — buzz, death-cancel, life.
## The pulse rides on top of the stored tint via draw_core_color.
func setup_tinted(from: Vector2, dir: Vector2, core: Color, rim: Color) -> void:
	setup(from, dir)
	core_color = core
	rim_color = rim


## The shared pulse value in [0, 1]: one clock for every hostile
## bullet, so the whole field breathes together. 0 is the settled
## trough, 1 the swollen peak.
static func pulse_value() -> float:
	var t: float = Time.get_ticks_msec() / 1000.0
	return 0.5 - 0.5 * cos(TAU * t * Tuning.ENEMY_BULLET_PULSE_HZ)


## The core radius this frame: ENEMY_BULLET_RADIUS swinging by
## +/- ENEMY_BULLET_PULSE_RADIUS_FRAC across the breath.
func draw_core_radius() -> float:
	return Tuning.ENEMY_BULLET_RADIUS \
		* (1.0 + Tuning.ENEMY_BULLET_PULSE_RADIUS_FRAC \
			* (2.0 * pulse_value() - 1.0))


## The core colour this frame: the bullet's own colour (tint
## included) lerped toward white by the pulse depth at peak.
func draw_core_color() -> Color:
	return core_color.lerp(Color.WHITE,
		Tuning.ENEMY_BULLET_PULSE_DEPTH * pulse_value())


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
	# The rim holds its colour steady; the CORE breathes — radius
	# and brightness pulsing in sync with every other hostile
	# bullet on the field (the helpers above; no math duplicated
	# here). The white centre dot scales with the core.
	var cr: float = draw_core_radius()
	draw_circle(Vector2.ZERO, cr + 2.0, rim_color)
	draw_circle(Vector2.ZERO, cr, draw_core_color())
	draw_circle(Vector2.ZERO,
		1.6 * cr / Tuning.ENEMY_BULLET_RADIUS, Color.WHITE)
