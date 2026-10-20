class_name SpawnDirector
extends Node
## Owns the waves: quotas, pacing, spawn points. Nothing enters
## the arena except through here, and every entry is announced by
## the pirate's own telegraph at its spawn point. Spawn points sit
## on the arena walls, never within the fairness exclusion radius
## of the player, and never bunched against the previous spawn.
## Rank (pushed in by Main each step) tightens the pacing and
## lifts the alive cap; the spawn interval also breathes with the
## field — brisk into a thin field, full pace into a full one —
## so a wiped wave refills as a flow, never a burst or a lull.
##
## The class mix is a DEALT DECK (M8), not per-spawn dice: at
## wave start the director builds the wave's exact class counts
## from the share helpers, dealing them out under a run guard so
## no class appears more than SPAWN_DECK_MAX_RUN times
## consecutively. The mix is guaranteed and spread — no en-masse
## clumps of one class, no droughts of another. A hunter card is
## dealt only while the hunter alive cap (reported by Main) has
## room; dealing scans past a capped hunter to the next legal
## card and the hunter waits in the deck.

signal spawn_requested(type_name: String, pos: Vector2)

var wave: int = 0
var quota_left: int = 0
var active: bool = false

var _spawn_t: float = 0.0
var _deck: Array[String] = []
var _last_spawn_point: Vector2 = Vector2.ZERO
var _has_last_spawn_point: bool = false


func start_wave(p_wave: int) -> void:
	wave = p_wave
	active = true
	_spawn_t = 0.7 # first entry comes a beat after the banner
	_build_deck()
	quota_left = _deck.size()
	_has_last_spawn_point = false # a wave's first spawn answers only to the player exclusion


func stop() -> void:
	active = false
	quota_left = 0
	_deck.clear()


func quota_exhausted() -> bool:
	return quota_left <= 0


## The undealt deck, front first (a copy — tests read it, nobody
## outside the director deals from it).
func deck_snapshot() -> Array[String]:
	return _deck.duplicate()


func step(delta: float, alive_count: int, player_pos: Vector2,
		rank: float = 0.0, hunters_alive: int = 0) -> void:
	if not active or quota_left <= 0:
		return
	var bonus: int = Tuning.rank_alive_bonus(rank)
	var max_alive: int = mini(
		Tuning.WAVE_MAX_ALIVE_BASE + wave - 1 + bonus,
		Tuning.WAVE_MAX_ALIVE_CAP + bonus)
	if alive_count >= max_alive:
		return
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		var dealt: String = _deal_card(hunters_alive)
		if dealt == "":
			# Nothing in the deck is legal right now (an
			# all-hunter remainder at a full cap): retry on a
			# short fuse instead of burning a full interval.
			_spawn_t = 0.15
			return
		_spawn_t = Tuning.rank_spawn_interval(Tuning.SPAWN_INTERVAL, rank) \
			* Tuning.spawn_flow_frac(alive_count, max_alive) \
			* randf_range(0.8, 1.25)
		quota_left = _deck.size()
		spawn_requested.emit(dealt, pick_spawn_point(player_pos))


## Build the wave's deck: exact class counts from the share
## helpers (so the field mix matches the old rolled averages),
## dealt out card by card under a run guard. Each card is drawn
## at random — weighted by how many of its class remain — from
## the classes that keep the deck legal: never extending the
## standing run past SPAWN_DECK_MAX_RUN, and never leaving a
## remainder no legal completion could place (the capacity
## guard in _completion_possible). The bound therefore holds by
## construction, not by after-the-fact repair: a shuffled deck
## whose classes cluster at the tail has legal arrangements
## that no sequence of single-card swaps or relocations can
## reach, so the deck is never shuffled blind in the first
## place. If a composition has no legal arrangement at all (a
## one-class wave), the guard has nothing to protect: the most
## numerous remaining class deals and the run stands — the
## harmless composition tail.
func _build_deck() -> void:
	_deck.clear()
	var quota: int = Tuning.WAVE_BASE_QUOTA \
		+ Tuning.WAVE_QUOTA_PER_WAVE * wave
	var hunter_n: int = roundi(float(quota) * hunter_share())
	var gunner_n: int = roundi(float(quota) * (1.0 - hunter_share()) \
		* gunner_share())
	var rem: Dictionary = {
		"hunter": hunter_n,
		"gunner": gunner_n,
		"grabber": maxi(quota - hunter_n - gunner_n, 0)}
	var classes: Array[String] = ["hunter", "gunner", "grabber"]
	var lead_class: String = ""
	var lead_len: int = 0
	while _deck.size() < quota:
		var options: Array[String] = []
		var weights: Array[int] = []
		for c: String in classes:
			var left: int = int(rem[c])
			if left <= 0:
				continue
			if c == lead_class \
					and lead_len >= Tuning.SPAWN_DECK_MAX_RUN:
				continue
			rem[c] = left - 1
			var new_len: int = lead_len + 1 if c == lead_class else 1
			if _completion_possible(rem, c, new_len):
				options.append(c)
				weights.append(left)
			rem[c] = left
		var pick: String = ""
		if options.is_empty():
			# No legal continuation (infeasible tail): deal the
			# most numerous remaining class and let the run stand.
			var most: int = 0
			for c2: String in classes:
				if int(rem[c2]) > most:
					most = int(rem[c2])
					pick = c2
		else:
			var total_w: int = 0
			for wt: int in weights:
				total_w += wt
			var roll: int = randi_range(1, total_w)
			var acc: int = 0
			for oi: int in range(options.size()):
				acc += weights[oi]
				if roll <= acc:
					pick = options[oi]
					break
		_deck.append(pick)
		rem[pick] = int(rem[pick]) - 1
		if pick == lead_class:
			lead_len += 1
		else:
			lead_class = pick
			lead_len = 1


## Capacity guard for the deck construction: can the remaining
## counts (rem, after a tentative placement) still be arranged
## with no run past SPAWN_DECK_MAX_RUN, given the deck ends in a
## run of lead_len cards of lead_class? A class x fits at most
## SPAWN_DECK_MAX_RUN cards per block and has at most
## (non-x cards + 1) blocks; the lead class's first block is
## shorter, since it may only grow the standing run to the cap:
## (MAX_RUN - lead_len) + MAX_RUN * non-x cards. If every class
## fits its capacity a completion exists — the standard
## bounded-run argument — so the guard never strands the deck.
func _completion_possible(rem: Dictionary, lead_class: String,
		lead_len: int) -> bool:
	var total: int = 0
	var keys: Array = rem.keys()
	for k: Variant in keys:
		total += int(rem[k])
	for k2: Variant in keys:
		var x: String = String(k2)
		var xn: int = int(rem[x])
		if xn <= 0:
			continue
		var others: int = total - xn
		var capacity: int = 0
		if x == lead_class:
			capacity = (Tuning.SPAWN_DECK_MAX_RUN - lead_len) \
				+ Tuning.SPAWN_DECK_MAX_RUN * others
		else:
			capacity = Tuning.SPAWN_DECK_MAX_RUN * (others + 1)
		if xn > capacity:
			return false
	return true


## Deal the first LEGAL card from the front of the deck. Hunter
## cards are legal only while the hunter alive cap has room;
## every other card is always legal. Returns "" when no card is
## legal right now (an all-hunter remainder at a full cap) —
## the card stays in the deck for a later, legal moment.
func _deal_card(hunters_alive: int) -> String:
	for i: int in range(_deck.size()):
		var card: String = _deck[i]
		if card == "hunter" and hunters_alive >= hunter_alive_cap():
			continue
		_deck.remove_at(i)
		return card
	return ""


## The gunner share of a wave's quota: none on wave 1, then the
## Tuning base share growing per wave up to its cap.
func gunner_share() -> float:
	if wave < 2:
		return 0.0
	return clampf(
		Tuning.GUNNER_SHARE_MIN
			+ Tuning.GUNNER_SHARE_PER_WAVE * float(wave - 2),
		0.0, Tuning.GUNNER_SHARE_CAP)


## The hunter share of a wave's deck: none before wave 3, then
## the Tuning base share growing per wave up to its cap.
func hunter_share() -> float:
	if wave < 3:
		return 0.0
	return clampf(
		Tuning.HUNTER_SHARE_BASE
			+ Tuning.HUNTER_SHARE_PER_WAVE * float(wave - 3),
		0.0, Tuning.HUNTER_SHARE_CAP)


## Concurrent hunters allowed on the field: a hard gate on
## dealing, so the direct-challenge class pressures in ones
## and twos (threes late) instead of swarming.
func hunter_alive_cap() -> int:
	if wave < Tuning.HUNTER_ALIVE_CAP_LATE_WAVE:
		return Tuning.HUNTER_ALIVE_CAP
	return Tuning.HUNTER_ALIVE_CAP_LATE


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


## Separation gate: the first point of a wave is constrained only
## by the player exclusion, exactly as before M8; every later
## point must clear SPAWN_MIN_SEPARATION from the previous one.
func _is_separated(cand: Vector2) -> bool:
	if not _has_last_spawn_point:
		return true
	return cand.distance_to(_last_spawn_point) \
		>= Tuning.SPAWN_MIN_SEPARATION
