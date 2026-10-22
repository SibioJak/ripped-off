class_name SpawnDirector
extends Node
## The continuous director (the restructure: no waves, no
## bosses). Nothing enters the arena except through here, and
## every entry is announced by the pirate's own telegraph at its
## spawn point. Spawn points sit on the arena walls, never
## within the fairness exclusion radius of the player, and never
## bunched against the previous spawn.
##
## There is no quota and no deck: while a run is live the
## director deals forever, sampling the class composition for
## the elapsed run time (Tuning.composition_at) on every deal.
## Escalation is time's job — the composition unlocks and grows,
## the base interval tightens and the alive cap rises on the
## Tuning curves — while Rank (pushed in by Main each step)
## breathes on top: it tightens the interval further and lifts
## the cap, and the flow factor still refills a thin field
## briskly without ever bursting.
##
## Three dealing disciplines:
##  - the anti-clump rule (survived from the deck era): no
##    class deals more than DIRECTOR_MAX_RUN times
##    consecutively while another unlocked class holds a share
##    of at least 0.10;
##  - proportional redistribution (the rebalance): a class that
##    cannot deal — at its alive cap (hunter by time, darter,
##    sniper), or the grabber during a tow window — has its
##    share spread across the other unlocked, uncapped
##    NON-GRABBER classes in proportion to their shares. The
##    grabber's own weight is always exactly its curve share;
##    it takes redistributed share only when literally every
##    other door is shut (all other classes locked or capped),
##    the one remaining fallback;
##  - the tow window (the rebalance): while the player tows a
##    canister, the grabber is held out of the deal entirely
##    (redistributed as above) and the spawn interval stretches
##    by Tuning.TOW_WINDOW_INTERVAL_SCALE. Pirates already out
##    are untouched — only deals are gated. The window ends the
##    instant the tow does; nothing is banked and nothing
##    bursts to catch up.

signal spawn_requested(type_name: String, pos: Vector2)

var active: bool = false

var _spawn_t: float = 0.0
var _last_dealt: String = ""
var _deal_run: int = 0
var _last_spawn_point: Vector2 = Vector2.ZERO
var _has_last_spawn_point: bool = false

const CLASSES: Array[String] = ["grabber", "gunner", "hunter", "darter", "sniper"]


func start_run() -> void:
	active = true
	_spawn_t = 0.7 # first entry comes a beat after the run starts
	_last_dealt = ""
	_deal_run = 0
	_has_last_spawn_point = false # a run's first spawn answers only to the player exclusion


func stop() -> void:
	active = false


## The alive gate for one class at a run time: the hunter cap
## steps up late (Tuning), the darter and sniper caps are flat,
## and the grabber and gunner are never capped.
func class_alive_cap(type_name: String, elapsed: float) -> int:
	match type_name:
		"hunter":
			return Tuning.hunter_alive_cap_at(elapsed)
		"darter":
			return Tuning.DARTER_ALIVE_CAP
		"sniper":
			return Tuning.SNIPER_ALIVE_CAP
	return 1 << 30


func step(delta: float, alive_count: int, player_pos: Vector2,
		rank: float = 0.0, class_alive: Dictionary = {},
		elapsed: float = 0.0, towing: bool = false) -> void:
	if not active:
		return
	var max_alive: int = Tuning.alive_cap_at(elapsed) \
		+ Tuning.rank_alive_bonus(rank)
	if alive_count >= max_alive:
		return
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		var dealt: String = pick_next_type(elapsed, class_alive, towing)
		_spawn_t = Tuning.rank_spawn_interval(
				Tuning.spawn_interval_at(elapsed), rank) \
			* Tuning.spawn_flow_frac(alive_count, max_alive) \
			* randf_range(0.8, 1.25)
		if towing:
			_spawn_t *= Tuning.TOW_WINDOW_INTERVAL_SCALE
		spawn_requested.emit(dealt, pick_spawn_point(player_pos))


## Sample the next class to deal at a run time. The weights
## come from _deal_weights (composition, caps, tow window).
## The anti-clump rule then applies: if the sampled class
## would extend the standing run past DIRECTOR_MAX_RUN while
## another unlocked class holds a share of at least 0.10, the
## deal is resampled once with the running class excluded.
func pick_next_type(elapsed: float, class_alive: Dictionary,
		towing: bool = false) -> String:
	var comp: Dictionary = Tuning.composition_at(elapsed)
	var weights: Dictionary = _deal_weights(comp, elapsed,
		class_alive, towing)
	var pick: String = _weighted_pick(weights)
	if pick == _last_dealt and _deal_run >= Tuning.DIRECTOR_MAX_RUN \
			and _another_class_has_share(comp, pick):
		var trimmed: Dictionary = weights.duplicate()
		trimmed[pick] = 0.0
		var retry: String = _weighted_pick(trimmed)
		if retry != "":
			pick = retry
	if pick == _last_dealt:
		_deal_run += 1
	else:
		_last_dealt = pick
		_deal_run = 1
	return pick


## Build the deal weights for one sample. A class is EXCLUDED
## when it cannot deal on this sample: at its alive cap, or the
## grabber while the tow window is up. The excluded shares pool
## and spread across the eligible NON-GRABBER classes in
## proportion to their composition shares — the grabber's
## weight is always exactly its curve share, never a magnet
## for other classes' scraps. (The rebalance: the old rule
## handed every capped share to the grabber, a quiet thief
## amplifier.) Edge: if every non-grabber class is locked or
## capped, no recipient exists and the grabber takes the pool
## whole — the only remaining door, tow window or not.
func _deal_weights(comp: Dictionary, elapsed: float,
		class_alive: Dictionary, towing: bool) -> Dictionary:
	var excluded: Dictionary = {}
	var pool: float = 0.0
	for c: String in CLASSES:
		var w: float = float(comp.get(c, 0.0))
		var out: bool = towing and c == "grabber"
		if not out and w > 0.0 and int(class_alive.get(c, 0)) \
				>= class_alive_cap(c, elapsed):
			out = true
		if out:
			excluded[c] = true
			pool += w
	var recipients: float = 0.0
	for c2: String in CLASSES:
		if c2 != "grabber" and not excluded.has(c2):
			recipients += float(comp.get(c2, 0.0))
	var weights: Dictionary = {}
	for c3: String in CLASSES:
		if excluded.has(c3):
			weights[c3] = 0.0
		elif c3 == "grabber":
			weights[c3] = float(comp.get(c3, 0.0))
			if recipients <= 0.0:
				# Every other door is shut: the grabber takes
				# the pool — the only remaining door.
				weights[c3] = float(weights.get(c3, 0.0)) + pool
		elif recipients > 0.0:
			var base: float = float(comp.get(c3, 0.0))
			weights[c3] = base + pool * (base / recipients)
		else:
			weights[c3] = float(comp.get(c3, 0.0))
	var total: float = 0.0
	for c4: String in CLASSES:
		total += float(weights.get(c4, 0.0))
	if total <= 0.0:
		# Unreachable with the shipped curves (the gunner is
		# never capped and always holds a share, so a recipient
		# always exists) — but a deal must never come up empty:
		# the grabber takes it, the only remaining door.
		weights["grabber"] = 1.0
	return weights


## Does any unlocked class other than `except_class` hold a
## composition share of at least 0.10? (The anti-clump rule's
## condition: clumps only matter when a real alternative mix
## exists.)
func _another_class_has_share(comp: Dictionary, except_class: String) -> bool:
	for c: String in CLASSES:
		if c != except_class and float(comp.get(c, 0.0)) >= 0.10:
			return true
	return false


## Weighted sample over a {class: weight} dictionary. Returns ""
## only when every weight is zero (unreachable in play:
## _deal_weights guarantees a positive total).
func _weighted_pick(weights: Dictionary) -> String:
	var total: float = 0.0
	for c: String in CLASSES:
		total += float(weights.get(c, 0.0))
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var acc: float = 0.0
	for c2: String in CLASSES:
		acc += float(weights.get(c2, 0.0))
		if roll < acc:
			return c2
	return "grabber"


## A point just inside a random arena wall, kept out of the
## player's exclusion radius AND at least SPAWN_MIN_SEPARATION
## from the previous spawn point, so entries walk the walls
## instead of bunching on one edge. Whichever point is returned
## becomes the separation reference for the next call. Fairness
## outranks separation: when no random candidate satisfies both,
## fixed anchors answer (the exclusion-passing anchor farthest
## from the last point), and if every anchor fails the exclusion
## too, the best-of-tries (farthest from the player) stands.
func pick_spawn_point(player_pos: Vector2) -> Vector2:
	var best: Vector2 = Tuning.depot_center()
	var best_d: float = -1.0
	for i: int in range(40):
		var cand: Vector2 = _random_wall_point()
		var d: float = cand.distance_to(player_pos)
		if d >= Tuning.SPAWN_EXCLUSION_RADIUS and _is_separated(cand):
			_last_spawn_point = cand
			_has_last_spawn_point = true
			return cand
		if d > best_d:
			best_d = d
			best = cand
	# Deterministic anchor fallback: the four arena corners and
	# the four edge midpoints, inset by the same margins the
	# random candidates use.
	var anchor_best: Vector2 = Vector2.ZERO
	var anchor_sep: float = -1.0
	var anchor_found: bool = false
	var anchors: Array[Vector2] = _spawn_anchors()
	for a: Vector2 in anchors:
		if a.distance_to(player_pos) < Tuning.SPAWN_EXCLUSION_RADIUS:
			continue
		var sep: float = INF if not _has_last_spawn_point \
			else a.distance_to(_last_spawn_point)
		if not anchor_found or sep > anchor_sep:
			anchor_found = true
			anchor_sep = sep
			anchor_best = a
	if anchor_found:
		_last_spawn_point = anchor_best
		_has_last_spawn_point = true
		return anchor_best
	_last_spawn_point = best
	_has_last_spawn_point = true
	return best


## One random candidate: a point just inside a random arena wall.
func _random_wall_point() -> Vector2:
	var edge: int = randi_range(0, 3)
	match edge:
		0: # top
			return Vector2(
				randf_range(Tuning.ARENA_LEFT + 30.0, Tuning.ARENA_RIGHT - 30.0),
				Tuning.ARENA_TOP + 14.0)
		1: # bottom
			return Vector2(
				randf_range(Tuning.ARENA_LEFT + 30.0, Tuning.ARENA_RIGHT - 30.0),
				Tuning.ARENA_BOTTOM - 14.0)
		2: # left
			return Vector2(Tuning.ARENA_LEFT + 14.0,
				randf_range(Tuning.ARENA_TOP + 30.0, Tuning.ARENA_BOTTOM - 30.0))
		3: # right
			return Vector2(Tuning.ARENA_RIGHT - 14.0,
				randf_range(Tuning.ARENA_TOP + 30.0, Tuning.ARENA_BOTTOM - 30.0))
	return Tuning.depot_center()


## The eight separation anchors: arena corners and edge
## midpoints, inset by the same 14/30px margins the random
## candidates use.
func _spawn_anchors() -> Array[Vector2]:
	var x0: float = Tuning.ARENA_LEFT + 30.0
	var x1: float = Tuning.ARENA_RIGHT - 30.0
	var y0: float = Tuning.ARENA_TOP + 14.0
	var y1: float = Tuning.ARENA_BOTTOM - 14.0
	var cx: float = (Tuning.ARENA_LEFT + Tuning.ARENA_RIGHT) * 0.5
	var cy: float = (Tuning.ARENA_TOP + Tuning.ARENA_BOTTOM) * 0.5
	var anchors: Array[Vector2] = [
		Vector2(x0, y0), Vector2(x1, y0),
		Vector2(x0, y1), Vector2(x1, y1),
		Vector2(cx, y0), Vector2(cx, y1),
		Vector2(Tuning.ARENA_LEFT + 14.0, cy),
		Vector2(Tuning.ARENA_RIGHT - 14.0, cy)]
	return anchors


## Separation gate: the first point of a run is constrained only
## by the player exclusion, exactly as before M8; every later
## point must clear SPAWN_MIN_SEPARATION from the previous one.
func _is_separated(cand: Vector2) -> bool:
	if not _has_last_spawn_point:
		return true
	return cand.distance_to(_last_spawn_point) \
		>= Tuning.SPAWN_MIN_SEPARATION
