class_name SpawnDirector
extends Node
## Owns the waves: quotas, pacing, spawn points. Nothing enters
## the arena except through here, and every entry is announced by
## the pirate's own telegraph at its spawn point. Spawn points sit
## on the arena walls, never within the fairness exclusion radius
## of the player. Rank (pushed in by Main each step) tightens the
## pacing and lifts the alive cap; from wave 2 the quota mixes
## gunners in alongside grabbers, the share growing with the wave;
## from wave 3 hunters join the spawn rolls, their share gated by
## a hard cap on hunters alive at once (Main reports the count).

signal spawn_requested(type_name: String, pos: Vector2)

var wave: int = 0
var quota_left: int = 0
var active: bool = false

var _spawn_t: float = 0.0


func start_wave(p_wave: int) -> void:
	wave = p_wave
	quota_left = Tuning.WAVE_BASE_QUOTA + Tuning.WAVE_QUOTA_PER_WAVE * p_wave
	active = true
	_spawn_t = 0.7 # first entry comes a beat after the banner


func stop() -> void:
	active = false
	quota_left = 0


func quota_exhausted() -> bool:
	return quota_left <= 0


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
		_spawn_t = Tuning.rank_spawn_interval(Tuning.SPAWN_INTERVAL, rank) \
			* randf_range(0.8, 1.25)
		quota_left -= 1
		spawn_requested.emit(pick_type(hunters_alive),
			pick_spawn_point(player_pos))


## The gunner share of a wave's quota: none on wave 1, then the
## Tuning base share growing per wave up to its cap.
func gunner_share() -> float:
	if wave < 2:
		return 0.0
	return clampf(
		Tuning.GUNNER_SHARE_MIN
			+ Tuning.GUNNER_SHARE_PER_WAVE * float(wave - 2),
		0.0, Tuning.GUNNER_SHARE_CAP)


## The hunter share of a wave's spawn rolls: none before wave 3,
## then the Tuning base share growing per wave up to its cap.
func hunter_share() -> float:
	if wave < 3:
		return 0.0
	return clampf(
		Tuning.HUNTER_SHARE_BASE
			+ Tuning.HUNTER_SHARE_PER_WAVE * float(wave - 3),
		0.0, Tuning.HUNTER_SHARE_CAP)


## Concurrent hunters allowed on the field: a hard gate on the
## share roll, so the direct-challenge class pressures in ones
## and twos (threes late) instead of swarming.
func hunter_alive_cap() -> int:
	if wave < Tuning.HUNTER_ALIVE_CAP_LATE_WAVE:
		return Tuning.HUNTER_ALIVE_CAP
	return Tuning.HUNTER_ALIVE_CAP_LATE


func pick_type(hunters_alive: int = 0) -> String:
	# The hunter roll comes first and is short-circuited before
	# wave 3, so early-wave rolls consume exactly the randoms
	# they always did. At/over the alive cap the roll is skipped
	# entirely — the cap is a hard gate, not a reroll.
	if wave >= 3 and hunters_alive < hunter_alive_cap() \
			and randf() < hunter_share():
		return "hunter"
	if randf() < gunner_share():
		return "gunner"
	return "grabber"


## A point just inside a random arena wall, kept out of the
## player's exclusion radius (best of several tries).
func pick_spawn_point(player_pos: Vector2) -> Vector2:
	var best: Vector2 = Tuning.depot_center()
	var best_d: float = -1.0
	for i: int in range(12):
		var edge: int = randi_range(0, 3)
		var cand: Vector2 = Vector2.ZERO
		match edge:
			0: # top
				cand = Vector2(
					randf_range(Tuning.ARENA_LEFT + 30.0, Tuning.ARENA_RIGHT - 30.0),
					Tuning.ARENA_TOP + 14.0)
			1: # bottom
				cand = Vector2(
					randf_range(Tuning.ARENA_LEFT + 30.0, Tuning.ARENA_RIGHT - 30.0),
					Tuning.ARENA_BOTTOM - 14.0)
			2: # left
				cand = Vector2(Tuning.ARENA_LEFT + 14.0,
					randf_range(Tuning.ARENA_TOP + 30.0, Tuning.ARENA_BOTTOM - 30.0))
			3: # right
				cand = Vector2(Tuning.ARENA_RIGHT - 14.0,
					randf_range(Tuning.ARENA_TOP + 30.0, Tuning.ARENA_BOTTOM - 30.0))
		var d: float = cand.distance_to(player_pos)
		if d >= Tuning.SPAWN_EXCLUSION_RADIUS:
			return cand
		if d > best_d:
			best_d = d
			best = cand
	return best
