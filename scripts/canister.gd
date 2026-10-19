class_name Canister
extends Node2D
## THE canister state machine — defined once, here, and nowhere
## else. Every state change a canister ever makes goes through one
## of this script's transition functions:
##
##   IN_SLOT  -- sitting in its depot berth (home, but stealable)
##   LOOSE    -- free in the arena; momentum applies only here
##   DRAGGING -- latched by a pirate (hauled toward an edge) or by
##               the Dreadnought's grab arm (hauled up to the boss)
##   TOWED    -- latched by the player, trailing the ship home
##   GONE     -- carried off the arena; the run's clock ticking down
##
## Slotting is a glide, not a teleport: a LOOSE canister inside the
## snap radius of its own free berth, or a TOWED canister deposited
## in the depot ring, eases into the berth on an ease-out cubic and
## only becomes IN_SLOT when the glide lands.

enum State { IN_SLOT, LOOSE, DRAGGING, TOWED, GONE }

var state: State = State.IN_SLOT
var velocity: Vector2 = Vector2.ZERO
var slot_index: int = 0
var slot_pos: Vector2 = Vector2.ZERO
var holder: Node2D = null # pirate or boss (DRAGGING), player (TOWED)
var tow_start_pos: Vector2 = Vector2.ZERO # latched here; pays the recovery scale

var _slotting: bool = false
var _glide_from: Vector2 = Vector2.ZERO
var _glide_t: float = 0.0
var _glide_dur: float = 0.0
var _spin: float = 0.0


func setup(p_slot_index: int, p_slot_pos: Vector2) -> void:
	slot_index = p_slot_index
	slot_pos = p_slot_pos
	global_position = p_slot_pos
	state = State.IN_SLOT
	velocity = Vector2.ZERO
	holder = null
	_slotting = false
	visible = true
	_spin = randf() * TAU


func is_slotting() -> bool:
	return _slotting


## Pirates may target a canister that is home or loose — never one
## already held, gone, or mid-glide into its berth.
func is_available_target() -> bool:
	return (state == State.IN_SLOT or state == State.LOOSE) and not _slotting


# --- Transitions (the only doors between states) ----------------------

func set_loose(p_velocity: Vector2) -> void:
	state = State.LOOSE
	velocity = p_velocity
	holder = null
	_slotting = false


func begin_drag(by: Node2D) -> bool:
	if not is_available_target():
		return false
	state = State.DRAGGING
	holder = by
	velocity = Vector2.ZERO
	return true


func release_from_drag(momentum: Vector2) -> void:
	if state == State.DRAGGING:
		set_loose(momentum)


func begin_tow(by: Node2D) -> bool:
	if state != State.LOOSE or _slotting:
		return false
	state = State.TOWED
	holder = by
	tow_start_pos = global_position
	velocity = Vector2.ZERO
	return true


func release_tow(momentum: Vector2) -> void:
	if state == State.TOWED:
		set_loose(momentum)


## Start the glide into the home berth (deposit or snap). The state
## becomes IN_SLOT only when the glide lands.
func begin_slot_glide() -> void:
	if state == State.GONE or _slotting:
		return
	_slotting = true
	holder = null
	velocity = Vector2.ZERO
	_glide_from = global_position
	_glide_t = 0.0
	var dist: float = global_position.distance_to(slot_pos)
	_glide_dur = clampf(dist / Tuning.SLOT_GLIDE_SPEED,
		Tuning.SLOT_GLIDE_MIN, Tuning.SLOT_GLIDE_MAX)


func mark_gone() -> void:
	state = State.GONE
	holder = null
	_slotting = false
	velocity = Vector2.ZERO
	visible = false


# --- Per-frame step (called by Main) -----------------------------------

func step(delta: float) -> void:
	if state == State.GONE:
		return
	if _slotting:
		_glide_t += delta
		var frac: float = clampf(_glide_t / maxf(_glide_dur, 0.01), 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - frac, 3.0) # ease-out cubic
		global_position = _glide_from.lerp(slot_pos, eased)
		if frac >= 1.0:
			_slotting = false
			state = State.IN_SLOT
			global_position = slot_pos
			velocity = Vector2.ZERO
		queue_redraw()
		return
	if state == State.LOOSE:
		_spin += delta * 1.5
		global_position += velocity * delta
		velocity *= clampf(1.0 - Tuning.LOOSE_FRICTION * delta, 0.0, 1.0)
		_bounce_off_walls()
		if global_position.distance_to(slot_pos) <= Tuning.SLOT_SNAP_RADIUS:
			begin_slot_glide()
		queue_redraw()


func _bounce_off_walls() -> void:
	var r: float = Tuning.CANISTER_RADIUS
	var pos: Vector2 = global_position
	if pos.x < Tuning.ARENA_LEFT + r:
		pos.x = Tuning.ARENA_LEFT + r
		velocity.x = absf(velocity.x) * Tuning.LOOSE_BOUNCE
	elif pos.x > Tuning.ARENA_RIGHT - r:
		pos.x = Tuning.ARENA_RIGHT - r
		velocity.x = -absf(velocity.x) * Tuning.LOOSE_BOUNCE
	if pos.y < Tuning.ARENA_TOP + r:
		pos.y = Tuning.ARENA_TOP + r
		velocity.y = absf(velocity.y) * Tuning.LOOSE_BOUNCE
	elif pos.y > Tuning.ARENA_BOTTOM - r:
		pos.y = Tuning.ARENA_BOTTOM - r
		velocity.y = -absf(velocity.y) * Tuning.LOOSE_BOUNCE
	global_position = pos


func _draw() -> void:
	if state == State.GONE:
		return
	var col: Color = Tuning.COLOR_CANISTER
	if state == State.IN_SLOT:
		col = col.lerp(Color.WHITE, 0.25)
	elif _slotting:
		col = col.lerp(Color.WHITE, 0.45)
	draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
	# Capsule: fat line with round end circles, bright core stripe.
	draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), col, 17.0, true)
	draw_circle(Vector2(-9.0, 0.0), 8.5, col)
	draw_circle(Vector2(9.0, 0.0), 8.5, col)
	var core: Color = col.lerp(Color.WHITE, 0.65)
	draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), core, 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
