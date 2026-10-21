class_name Broadside
extends Boss
## The BROADSIDE — Ripped-Off's second capital (M10), on even
## boss numbers (waves 10, 20, ...), alternating with the
## Dreadnought. A long flank gunship that ORBITS the depot and
## fires broadsides from whichever battery faces the arena
## centre: strip the presented battery and it comes about to
## present the other; strip both and a bow gun is all it has
## left. It NEVER touches the canisters — a pure duel, the
## deliberate contrast with the Dreadnought's theft fight.
## It satisfies the Boss contract Main routes through (setup,
## step, the six signals, damage_hull/damage_part, hull_frac,
## hit_circles, part_world), so bullets, the proximity bonus,
## pass-through damage, the HUD bar and the death completion
## all work unchanged. Numbers live in Tuning's Broadside
## section; this script is behaviour only.

const POD_PORT_1: String = "pod_port_1"
const POD_PORT_2: String = "pod_port_2"
const POD_PORT_3: String = "pod_port_3"
const POD_STARBOARD_1: String = "pod_starboard_1"
const POD_STARBOARD_2: String = "pod_starboard_2"
const POD_STARBOARD_3: String = "pod_starboard_3"
const ENGINE_1: String = "engine_1"
const ENGINE_2: String = "engine_2"

# Hit circles in boss-local space, [offset, radius] — a long
# hull (~166 x 52) read as three overlapping circles, the Boss
# precedent. Local +X is the nose; the node rotates nose-tangent
# to the orbit, so these ride the heading via to_world().
const BS_HULL_CIRCLES: Array = [
	[Vector2(-50.0, 0.0), 30.0],
	[Vector2(0.0, 0.0), 34.0],
	[Vector2(50.0, 0.0), 30.0],
]

# Test-visible state (the harness reads these, as it reads the
# Dreadnought's shot counters).
var orbit_angle: float = -PI * 0.5 # current angle on the orbit circle
var orbit_dir: int = 1 # +1: angle grows (CCW); -1: it shrinks (CW)
var angular_speed_now: float = 0.0 # signed rad/s applied this frame
var desperate: bool = false # the one-time 50%-hull escalation
var volleys_fired: int = 0
var bow_shots_fired: int = 0
var cookoffs_fired: int = 0
var last_volley_origins: Array[Vector2] = []
var last_volley_dirs: Array[Vector2] = []

var _defs: Dictionary = {} # part id -> {offset, radius, hp, side?}
var _centre: Vector2 = Vector2.ZERO
# (_entry_t/_entry_from/_entry_to are inherited from Boss and
# reused for the orbit entry glide.)
var _volley_t: float = 0.0
var _charging: bool = false
var _bow_t: float = 0.0
var _bow_started: bool = false
var _bow_charging: bool = false
var _bow_charge_t: float = 0.0
var _volley_charge_t: float = 0.0 # (Boss's _charge_t is a Dictionary)
var _bow_aim_local: Vector2 = Vector2.RIGHT
var _reversing: bool = false
var _reverse_t: float = 0.0
var _heading_from: float = 0.0
var _yaw_delta: float = 0.0
var _cookoff_t: Dictionary = {} # side -> seconds until the fan fires
var _cookoff_done: Dictionary = {} # side -> true once scheduled
var _sizzle_t: float = 0.0
var _orbit_parked: bool = false # test lever: hold the orbit still


# --- Identity (Boss hooks Main routes through) ---------------------

func theme_color() -> Color:
	return Tuning.COLOR_BROADSIDE


func display_name() -> String:
	return Tuning.BROADSIDE_NAME


func kill_score_value() -> int:
	return Tuning.broadside_score_value(tier)


func part_def(part_id: String) -> Dictionary:
	if _defs.is_empty():
		_defs = _build_part_defs()
	return _defs[part_id] as Dictionary


func part_ids() -> Array:
	if _defs.is_empty():
		_defs = _build_part_defs()
	return _defs.keys()


func hull_circle_defs() -> Array:
	return BS_HULL_CIRCLES


## The Broadside flies nose-tangent, so local offsets rotate
## with the node (the Dreadnought never rotates; its to_world
## is a plain translation).
func to_world(local: Vector2) -> Vector2:
	return global_position + local.rotated(rotation)


## Part geometry as data: six battery pods (three per flank,
## "side" is the local-Y sign of the flank) and two rear engines.
## HP comes from Tuning so the fight retunes from one place.
func _build_part_defs() -> Dictionary:
	var pod_hp: int = Tuning.BROADSIDE_POD_HP
	var eng_hp: int = Tuning.BROADSIDE_ENGINE_HP
	return {
		POD_PORT_1: {"offset": Vector2(-48.0, -31.0),
			"radius": 13.0, "hp": pod_hp, "side": -1},
		POD_PORT_2: {"offset": Vector2(0.0, -31.0),
			"radius": 13.0, "hp": pod_hp, "side": -1},
		POD_PORT_3: {"offset": Vector2(48.0, -31.0),
			"radius": 13.0, "hp": pod_hp, "side": -1},
		POD_STARBOARD_1: {"offset": Vector2(-48.0, 31.0),
			"radius": 13.0, "hp": pod_hp, "side": 1},
		POD_STARBOARD_2: {"offset": Vector2(0.0, 31.0),
			"radius": 13.0, "hp": pod_hp, "side": 1},
		POD_STARBOARD_3: {"offset": Vector2(48.0, 31.0),
			"radius": 13.0, "hp": pod_hp, "side": 1},
		ENGINE_1: {"offset": Vector2(-80.0, -17.0),
			"radius": 14.0, "hp": eng_hp},
		ENGINE_2: {"offset": Vector2(-80.0, 17.0),
			"radius": 14.0, "hp": eng_hp},
	}


func setup(p_wave: int) -> void:
	tier = Tuning.boss_tier(p_wave)
	max_hull_hp = Tuning.broadside_hull_hp(tier)
	hull_hp = max_hull_hp
	_rng.randomize()
	_defs = _build_part_defs()
	for pid_v: Variant in _defs.keys():
		var pid: String = String(pid_v)
		var pd: Dictionary = _defs[pid] as Dictionary
		_parts[pid] = {"hp": int(pd["hp"]), "broken": false,
			"flash": 0.0}
	_centre = Tuning.depot_center()
	orbit_angle = -PI * 0.5 # joins the circle at its top
	orbit_dir = 1 if _rng.randf() < 0.5 else -1
	_entry_to = _orbit_point()
	_entry_from = _entry_to \
		+ Vector2.from_angle(orbit_angle) * 320.0
	global_position = _entry_from
	rotation = (_entry_to - _entry_from).angle()
	phase = Phase.ENTRY
	_entry_t = 0.0
	_volley_t = Tuning.broadside_volley_interval(tier)
	queue_redraw()


# --- Queries ---------------------------------------------------------

func _orbit_point() -> Vector2:
	return _centre + Vector2.from_angle(orbit_angle) \
		* Tuning.BROADSIDE_ORBIT_RADIUS


## Heading when flying the circle: the velocity direction at
## the current angle for the current orbit direction.
func _tangent_angle() -> float:
	var tangent: Vector2 = Vector2(-sin(orbit_angle),
		cos(orbit_angle)) * float(orbit_dir)
	return tangent.angle()


## The presented flank is the one facing the orbit centre. In
## local space that is the +Y flank while the angle grows
## (orbit_dir +1) and the -Y flank while it shrinks — the
## heading is always tangent, so the inward side flips with
## the direction of travel.
func presented_side_sign() -> int:
	return orbit_dir


func _pod_ids(side: int) -> Array[String]:
	var out: Array[String] = []
	for pid_v: Variant in _defs.keys():
		var pid: String = String(pid_v)
		var pd: Dictionary = _defs[pid] as Dictionary
		if pd.has("side") and int(pd["side"]) == side:
			out.append(pid)
	return out


func _battery_live_count(side: int) -> int:
	var n: int = 0
	for pid: String in _pod_ids(side):
		if not is_part_broken(pid):
			n += 1
	return n


func _dead_engines() -> int:
	var n: int = 0
	if is_part_broken(ENGINE_1):
		n += 1
	if is_part_broken(ENGINE_2):
		n += 1
	return n


## Signed orbit rate: base by tier, x0.72 per dead engine
## (the ship visibly wallows), x1.15 once desperate.
func _omega() -> float:
	var mag: float = Tuning.broadside_orbit_speed(tier)
	mag *= pow(Tuning.BROADSIDE_ENGINE_SLOW, float(_dead_engines()))
	if desperate:
		mag *= Tuning.BROADSIDE_DESPERATION_SPEED
	return mag * float(orbit_dir)


## The effective volley cycle: tier base, x1.15 per dead
## engine (a wallowing ship reloads slower), x0.8 once
## desperate — desperation is the only acceleration.
func current_volley_interval() -> float:
	var v: float = Tuning.broadside_volley_interval(tier)
	for i: int in range(_dead_engines()):
		v *= Tuning.BROADSIDE_VOLLEY_ENGINE_STEP
	if desperate:
		v *= Tuning.BROADSIDE_DESPERATION_VOLLEY
	return v


## Test levers (the park_turrets precedent): freeze fire and /
## or the orbit so score, geometry and contact checks can stage
## exact states on a moving boss.
func park_volleys() -> void:
	_volley_t = 999.0
	_charging = false
	_bow_t = 999.0
	_bow_charging = false


func park_orbit() -> void:
	_orbit_parked = true


# --- Damage ------------------------------------------------------------

func damage_hull(amount: int = 1) -> void:
	if phase == Phase.DYING:
		return
	hull_hp = maxi(hull_hp - maxi(amount, 0), 0)
	_hull_flash = 0.12
	# Desperation: ONE escalation at half hull, permanent.
	# No radial bursts — those are the Dreadnought's signature.
	if not desperate \
			and hull_frac() <= Tuning.BROADSIDE_DESPERATION_FRAC:
		desperate = true
	if hull_hp <= 0:
		_begin_dying()
	queue_redraw()


## Part breaks run through Boss.damage_part (its bookkeeping and
## the part_broken emit are inherited via super here); the
## Broadside adds its own consequences: a charge whose battery
## just emptied dies with it, and a battery's LAST pod schedules
## that flank's one-time cook-off fan.
func _break_part(part_id: String) -> void:
	super._break_part(part_id)
	var pd: Dictionary = part_def(part_id)
	if not pd.has("side"):
		return # an engine: the slowdown reads the break live
	var side: int = int(pd["side"])
	if _charging and side == presented_side_sign() \
			and _battery_live_count(side) == 0:
		_charging = false # the volley dies with its battery
	if _battery_live_count(side) == 0 \
			and not bool(_cookoff_done.get(side, false)):
		_cookoff_done[side] = true
		_cookoff_t[side] = Tuning.BROADSIDE_COOKOFF_DELAY


# --- Per-frame step ------------------------------------------------------

func step(delta: float, _canisters: Array[Canister],
		player_pos: Vector2, player_alive: bool) -> void:
	_common_pre_step(delta, player_pos)
	match phase:
		Phase.ENTRY:
			_entry_t += delta
			var frac: float = clampf(
				_entry_t / Tuning.BOSS_ENTRY_TIME, 0.0, 1.0)
			var eased: float = frac * frac * (3.0 - 2.0 * frac)
			global_position = _entry_from.lerp(_entry_to, eased)
			# Bank from the entry heading into the tangent so
			# the handover to the orbit has no snap.
			var entry_ang: float = (_entry_to - _entry_from).angle()
			rotation = lerp_angle(entry_ang, _tangent_angle(), eased)
			if frac >= 1.0:
				phase = Phase.ACTIVE
				_volley_t = current_volley_interval() \
					- Tuning.BROADSIDE_VOLLEY_CHARGE_TIME
		Phase.ACTIVE:
			_step_active(delta, _canisters, player_pos, player_alive)
		Phase.DYING:
			_step_dying(delta)
	_common_sparks(delta)
	queue_redraw()


func _step_active(delta: float, _canisters: Array[Canister],
		player_pos: Vector2, player_alive: bool) -> void:
	_step_cookoffs(delta)
	# Bow aim tracks the player even between shots (the draw
	# reads it); stored in local space for the rotated hull.
	var to_player: Vector2 = player_pos - global_position
	if to_player.length() > 1.0:
		_bow_aim_local = to_player.normalized().rotated(-rotation)
	if _orbit_parked:
		angular_speed_now = 0.0
	elif _reversing:
		# Coming about: angular velocity eases through zero
		# while the hull yaws 180 degrees; at the end of the
		# turn the orbit direction (and with it the presented
		# flank) has flipped. It does not fire during the turn.
		_reverse_t += delta
		var f: float = clampf(_reverse_t
			/ Tuning.BROADSIDE_REVERSE_TIME, 0.0, 1.0)
		var eased: float = f * f * (3.0 - 2.0 * f)
		var decel: float = _omega() * (1.0 - eased)
		orbit_angle += decel * delta
		angular_speed_now = decel
		rotation = _heading_from + _yaw_delta * eased
		global_position = _orbit_point()
		if f >= 1.0:
			_reversing = false
			orbit_dir = -orbit_dir
			rotation = _tangent_angle()
			_volley_t = current_volley_interval() \
				- Tuning.BROADSIDE_VOLLEY_CHARGE_TIME
	else:
		var om: float = _omega()
		orbit_angle += om * delta
		angular_speed_now = om
		rotation = _tangent_angle()
		global_position = _orbit_point()
	if _reversing:
		return
	# A stripped presented battery (with the other still live)
	# starts the turn to present the live side.
	var ps: int = presented_side_sign()
	if not _orbit_parked and _battery_live_count(ps) == 0 \
			and _battery_live_count(-ps) > 0:
		_begin_reversal()
		return
	if _battery_live_count(1) == 0 and _battery_live_count(-1) == 0:
		_step_bow(delta, player_pos, player_alive)
	else:
		_step_volley(delta, player_pos, player_alive)


func _begin_reversal() -> void:
	_reversing = true
	_reverse_t = 0.0
	_heading_from = rotation
	# Yaw away from the centre (the sign that swings the nose
	# outward for the current direction of travel).
	_yaw_delta = -PI * float(orbit_dir)
	_charging = false
	_bow_charging = false


# --- Volley ----------------------------------------------------------------

## The volley cycle, gunner discipline like the Dreadnought's
## turrets: the cooldown ticks only while the player is up; a
## charge already winding up runs to completion, but its
## volley is suppressed if the player is down at the release.
func _step_volley(delta: float, player_pos: Vector2,
		player_alive: bool) -> void:
	if _charging:
		_volley_charge_t -= delta
		if _volley_charge_t <= 0.0:
			_charging = false
			_volley_t = current_volley_interval() \
				- Tuning.BROADSIDE_VOLLEY_CHARGE_TIME
			if player_alive:
				_fire_volley(player_pos)
		return
	if not player_alive:
		return
	_volley_t -= delta
	if _volley_t <= 0.0:
		_charging = true
		_volley_charge_t = Tuning.BROADSIDE_VOLLEY_CHARGE_TIME


## Every LIVE pod of the presented flank fires one bullet at
## the same instant — a dead pod leaves a gap in the rank.
## Direction: the flank's inward normal, bent toward the
## player's bearing and capped at +/- BROADSIDE_AIM_CAP.
func _fire_volley(player_pos: Vector2) -> void:
	var side: int = presented_side_sign()
	var inward: Vector2 = (_centre - global_position).normalized()
	var diff: float = 0.0
	var to_player: Vector2 = player_pos - global_position
	if to_player.length() > 1.0:
		diff = clampf(inward.angle_to(to_player.normalized()),
			-Tuning.BROADSIDE_AIM_CAP, Tuning.BROADSIDE_AIM_CAP)
	var dir: Vector2 = inward.rotated(diff)
	last_volley_origins.clear()
	last_volley_dirs.clear()
	for pid: String in _pod_ids(side):
		if is_part_broken(pid):
			continue
		var from: Vector2 = part_world(pid)
		fired.emit(from, dir, Tuning.COLOR_BROADSIDE_BULLET_CORE,
			Tuning.COLOR_BROADSIDE_BULLET_RIM)
		last_volley_origins.append(from)
		last_volley_dirs.append(dir)
	volleys_fired += 1


## Test/draw helper: the charge fraction of a volley winding
## up, or -1 when no charge is live.
func volley_charge_frac() -> float:
	if not _charging:
		return -1.0
	return clampf(1.0 - _volley_charge_t
		/ Tuning.BROADSIDE_VOLLEY_CHARGE_TIME, 0.0, 1.0)


# --- Cook-off ----------------------------------------------------------------

## Pending cook-offs tick in ACTIVE: the dead flank sizzles
## (spark signals at its middle pod) for COOKOFF_DELAY, then
## fires its one fan. Once per battery, scheduled in
## _break_part at the moment its last pod went.
func _step_cookoffs(delta: float) -> void:
	if _cookoff_t.is_empty():
		return
	var sides: Array = _cookoff_t.keys()
	for side_v: Variant in sides:
		var side: int = int(side_v)
		var left: float = float(_cookoff_t[side]) - delta
		if left <= 0.0:
			_cookoff_t.erase(side)
			_fire_cookoff(side)
		else:
			_cookoff_t[side] = left
			_sizzle_t -= delta
			if _sizzle_t <= 0.0:
				_sizzle_t = 0.07
				spark.emit(part_world(_pod_ids(side)[1]))


func _fire_cookoff(side: int) -> void:
	var origin: Vector2 = part_world(_pod_ids(side)[1])
	# The fan follows the dead battery's own flank normal —
	# the direction its guns faced. For the presented battery
	# that IS the inward direction (its volley direction);
	# for an outer battery stripped first it sprays outward.
	var normal: Vector2 = Vector2(0.0, float(side)).rotated(rotation)
	var n: int = Tuning.BROADSIDE_COOKOFF_COUNT
	for i: int in range(n):
		var f: float = lerpf(-Tuning.BROADSIDE_COOKOFF_SPREAD,
			Tuning.BROADSIDE_COOKOFF_SPREAD,
			float(i) / float(maxi(n - 1, 1)))
		fired.emit(origin, normal.rotated(f),
			Tuning.COLOR_BROADSIDE_BULLET_CORE,
			Tuning.COLOR_BROADSIDE_BULLET_RIM)
	cookoffs_fired += 1


# --- Bow gun -------------------------------------------------------------------

## Both batteries gone: a single aimed nose gun on the bow
## cycle (cooldown, charge, one shot). It never reverts to
## volleys and never reverses — the ship is a hulk with a gun.
func _step_bow(delta: float, player_pos: Vector2,
		player_alive: bool) -> void:
	if not _bow_started:
		_bow_started = true
		_bow_t = 0.8 # a beat before the first charge
	if _bow_charging:
		_bow_charge_t -= delta
		if _bow_charge_t <= 0.0:
			_bow_charging = false
			_bow_t = Tuning.BROADSIDE_BOW_INTERVAL \
				- Tuning.BROADSIDE_BOW_CHARGE_TIME
			if player_alive:
				var nose: Vector2 = to_world(Vector2(82.0, 0.0))
				var dir: Vector2 = (player_pos - nose)
				if dir.length() > 1.0:
					fired.emit(nose, dir.normalized(),
						Tuning.COLOR_BROADSIDE_BULLET_CORE,
						Tuning.COLOR_BROADSIDE_BULLET_RIM)
					bow_shots_fired += 1
		return
	if not player_alive:
		return
	_bow_t -= delta
	if _bow_t <= 0.0:
		_bow_charging = true
		_bow_charge_t = Tuning.BROADSIDE_BOW_CHARGE_TIME


func bow_charge_frac() -> float:
	if not _bow_charging:
		return -1.0
	return clampf(1.0 - _bow_charge_t
		/ Tuning.BROADSIDE_BOW_CHARGE_TIME, 0.0, 1.0)


# --- Death -----------------------------------------------------------------------

func _begin_dying() -> void:
	phase = Phase.DYING
	_dying_t = 0.0
	_death_idx = 0
	_charging = false
	_bow_charging = false
	_reversing = false
	_cookoff_t.clear()
	# Parts tear off as debris chunks, the Boss pattern: pods
	# and engines at their stations, then hull chunks.
	for pid_v: Variant in part_ids():
		var pid: String = String(pid_v)
		_spawn_chunk(part_world(pid), _rng.randf_range(11.0, 17.0))
	_spawn_chunk(to_world(Vector2(-30.0, -8.0)),
		_rng.randf_range(16.0, 24.0))
	_spawn_chunk(to_world(Vector2(34.0, 6.0)),
		_rng.randf_range(16.0, 24.0))
	# The detonation walk, the Boss pattern retimed to this
	# hull: hardware pops small, hull points medium, core goes
	# capital with two more capital bursts.
	_death_events = [
		{"t": 0.10, "pos": part_world(POD_PORT_2),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.24, "pos": part_world(POD_STARBOARD_2),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.38, "pos": part_world(ENGINE_1),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.52, "pos": part_world(ENGINE_2),
			"cls": LightFx.Size.SMALL, "sound": "death_gunner"},
		{"t": 0.70, "pos": to_world(Vector2(-40.0, 0.0)),
			"cls": LightFx.Size.MEDIUM, "sound": "death_grabber"},
		{"t": 0.90, "pos": to_world(Vector2(40.0, 0.0)),
			"cls": LightFx.Size.MEDIUM, "sound": "death_grabber"},
		{"t": 1.10, "pos": global_position,
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
		{"t": 1.22, "pos": to_world(Vector2(-24.0, 10.0)),
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
		{"t": 1.34, "pos": to_world(Vector2(24.0, -6.0)),
			"cls": LightFx.Size.CAPITAL, "sound": "death_grabber"},
	]


# --- Drawing ---------------------------------------------------------------------

func _hull_pts_bs() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-80.0, -16.0), Vector2(-46.0, -26.0),
		Vector2(40.0, -26.0), Vector2(72.0, -14.0),
		Vector2(86.0, 0.0), Vector2(72.0, 14.0),
		Vector2(40.0, 26.0), Vector2(-46.0, 26.0),
		Vector2(-80.0, 16.0), Vector2(-80.0, -16.0)])


func _draw() -> void:
	if phase == Phase.DYING:
		_draw_dying_bs()
		return
	var base: Color = Tuning.COLOR_BROADSIDE
	var dim: Color = base.darkened(0.45)
	_draw_proximity_ring(base)
	draw_polyline(_hull_pts_bs(), base, 2.5, true)
	# Deck structure: a spine and two frame lines.
	draw_line(Vector2(-68.0, 0.0), Vector2(66.0, 0.0), dim, 1.5, true)
	draw_line(Vector2(-46.0, -26.0), Vector2(-30.0, 20.0), dim, 1.5, true)
	draw_line(Vector2(40.0, -26.0), Vector2(52.0, 20.0), dim, 1.5, true)
	# Core.
	draw_arc(Vector2(6.0, 0.0), 11.0, 0.0, TAU, 24, base, 2.0, true)
	draw_circle(Vector2(6.0, 0.0), 3.0, base.lerp(Color.WHITE, 0.5))
	if _hull_flash > 0.0:
		var fa: float = clampf(_hull_flash / 0.12, 0.0, 1.0)
		draw_polyline(_hull_pts_bs(), Color(Color.WHITE, fa * 0.8),
			3.0, true)
	_draw_engines(base)
	_draw_pods(base)
	_draw_bow(base)


func _draw_engines(base: Color) -> void:
	var ids: Array[String] = [ENGINE_1, ENGINE_2]
	for pid: String in ids:
		var pd: Dictionary = part_def(pid)
		var off: Vector2 = pd["offset"] as Vector2
		var r: float = float(pd["radius"])
		var broken: bool = is_part_broken(pid)
		if broken:
			var dark: Color = Color(0.25, 0.22, 0.28, 1.0)
			draw_arc(off, r, 0.0, TAU, 20, dark, 2.0, true)
			draw_line(off + Vector2(-r * 0.6, -r * 0.3),
				off + Vector2(r * 0.2, r * 0.4), dark, 1.5, true)
			draw_line(off + Vector2(r * 0.1, -r * 0.5),
				off + Vector2(r * 0.6, r * 0.3), dark, 1.5, true)
		else:
			# Live engine: an amber exhaust glow that dies with
			# the engine — thrust you can read at a glance.
			draw_arc(off, r, 0.0, TAU, 20, base, 2.0, true)
			var flicker: float = 5.5 + 1.5 * sin(
				Time.get_ticks_msec() / 90.0 + off.y)
			draw_circle(off, flicker + 2.5,
				Color(Tuning.COLOR_BROADSIDE_BULLET_CORE, 0.35))
			draw_circle(off, flicker,
				Tuning.COLOR_BROADSIDE_BULLET_CORE)
		_draw_part_flash(pid, off, r)


func _draw_pods(base: Color) -> void:
	for pid_v: Variant in part_ids():
		var pid: String = String(pid_v)
		var pd: Dictionary = part_def(pid)
		if not pd.has("side"):
			continue
		var off: Vector2 = pd["offset"] as Vector2
		var r: float = float(pd["radius"])
		var broken: bool = is_part_broken(pid)
		var col: Color = Color(0.25, 0.22, 0.28, 1.0) if broken \
			else base
		draw_arc(off, r, 0.0, TAU, 20, col, 2.0, true)
		# A short barrel tick pointing off the flank.
		var out_dir: Vector2 = Vector2(0.0, float(int(pd["side"])))
		draw_line(off, off + out_dir * (r + 6.0), col, 2.5, true)
		if broken:
			draw_line(off + Vector2(-r * 0.6, -r * 0.3),
				off + Vector2(r * 0.2, r * 0.4), col, 1.5, true)
			draw_line(off + Vector2(r * 0.1, -r * 0.5),
				off + Vector2(r * 0.6, r * 0.3), col, 1.5, true)
		_draw_part_flash(pid, off, r)
		# Charge telegraph: the presented flank's live pods
		# swell and whiten together before the volley.
		var cf: float = volley_charge_frac()
		if cf >= 0.0 and not broken \
				and int(pd["side"]) == presented_side_sign():
			var glow_col: Color = base.lerp(Color.WHITE, cf * 0.85)
			draw_circle(off, lerpf(2.0, 6.0, cf),
				Color(base, 0.35 + 0.4 * cf))
			draw_circle(off, lerpf(1.0, 3.5, cf), glow_col)


func _draw_bow(base: Color) -> void:
	var nose: Vector2 = Vector2(78.0, 0.0)
	draw_arc(nose, 8.0, 0.0, TAU, 16, base, 2.0, true)
	draw_line(nose, nose + _bow_aim_local * 15.0, base, 2.5, true)
	var bf: float = bow_charge_frac()
	if bf >= 0.0:
		var muzzle: Vector2 = nose + _bow_aim_local * 15.0
		var glow_col: Color = base.lerp(Color.WHITE, bf * 0.85)
		draw_circle(muzzle, lerpf(2.0, 5.0, bf),
			Color(base, 0.35 + 0.4 * bf))
		draw_circle(muzzle, lerpf(1.0, 3.0, bf), glow_col)


## A broken or hit part flashes white briefly (the Boss
## _draw_part pattern, shared by pods and engines here).
func _draw_part_flash(part_id: String, off: Vector2, r: float) -> void:
	if is_part_broken(part_id):
		return
	var state: Dictionary = _parts[part_id] as Dictionary
	var flash: float = float(state["flash"])
	if flash > 0.0:
		var fa: float = clampf(flash / 0.15, 0.0, 1.0)
		draw_arc(off, r + 1.5, 0.0, TAU, 20,
			Color(Color.WHITE, fa), 2.5, true)


func _draw_dying_bs() -> void:
	var base: Color = Tuning.COLOR_BROADSIDE
	var fade: float = clampf(
		1.0 - _dying_t / Tuning.BOSS_DEATH_TIME, 0.0, 1.0)
	draw_polyline(_hull_pts_bs(), Color(base, 0.35 + 0.65 * fade),
		2.5, true)
	# Torn-off chunks, counter-rotated into this hull's local
	# space (the Dreadnought never rotates; this one does).
	for ch: Dictionary in _chunks:
		var cpos: Vector2 = ch["pos"] as Vector2
		var local: Vector2 = (cpos - global_position).rotated(-rotation)
		var sz: float = float(ch["size"])
		var rot: float = float(ch["rot"])
		var cfade: float = clampf(
			1.0 - float(ch["t"]) / float(ch["dur"]), 0.0, 1.0)
		var corners: Array[Vector2] = [
			Vector2(-sz, -sz * 0.6), Vector2(sz, -sz * 0.4),
			Vector2(sz * 0.5, sz), Vector2(-sz * 0.7, sz * 0.8)]
		var pts: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in corners:
			pts.append(local + corner.rotated(rot))
		pts.append(local + corners[0].rotated(rot))
		draw_polyline(pts, Color(base, cfade), 2.0, true)
