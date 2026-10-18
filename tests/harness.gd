extends Node
## Headless verification harness for Ripped-Off M1.
## Run:  Godot --headless --path . res://tests/harness.tscn
## Drives the REAL game scene through its real code paths
## (director disabled so spawns are deterministic; kills go
## through Main's bullet collision and kill functions, the same
## paths live play uses) and prints PASS/FAIL per check.

var game: Main = null
var _passed: int = 0
var _failed: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label)


func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Main
	add_child(game)
	await _frames(3)

	# (1) Boot reaches TITLE; starting a run places 8 IN_SLOT canisters.
	_check("boot reaches TITLE", game.state == Main.GameState.TITLE)
	game.start_run()
	game.director.active = false # deterministic spawns from here on
	await _frames(2)
	var in_slot: int = 0
	for c: Canister in game.canisters:
		if c.state == Canister.State.IN_SLOT:
			in_slot += 1
	_check("run starts with 8 IN_SLOT canisters",
		game.canisters.size() == 8 and in_slot == 8)

	# (2) A spawned pirate latches a canister and drags it.
	var slot0: Vector2 = Tuning.slot_position(0)
	var pirate: Pirate = game.spawn_pirate("grabber", slot0 + Vector2(120.0, 0.0))
	var latched: bool = false
	for i: int in range(300):
		await _frames(1)
		if pirate.held != null:
			latched = true
			break
	_check("pirate latches a canister (DRAGGING)",
		latched and pirate.held.state == Canister.State.DRAGGING)
	var dragged: Canister = pirate.held
	var drag_from: Vector2 = dragged.global_position
	# Drag well clear of the berth: a canister dropped inside the
	# 56px snap radius glides home on its own (by design) and would
	# leave nothing loose to tow in check (4).
	await _frames(150)
	_check("dragging pirate hauls the canister across the arena",
		dragged.global_position.distance_to(drag_from) > 25.0)

	# (3) Killing the pirate mid-drag (real bullet path) frees it LOOSE.
	game.spawn_bullet(pirate.global_position + Vector2(-30.0, 0.0), Vector2.RIGHT)
	for i: int in range(20):
		await _frames(1)
		if not is_instance_valid(pirate):
			break
	_check("bullet kill removes the pirate and leaves the canister LOOSE",
		not is_instance_valid(pirate)
			and dragged.state == Canister.State.LOOSE)

	# (4) Tow it home: latch TOWED, deposit pays 100-600 x multiplier.
	game.clear_field() # remove stray shards so the score delta is pure bonus
	var score_before: int = game.score
	game.player.global_position = dragged.global_position + Vector2(20.0, 0.0)
	var towed: bool = false
	for i: int in range(30):
		await _frames(1)
		if game.player.towed == dragged:
			towed = true
			break
	_check("player tow latches the loose canister (TOWED)",
		towed and dragged.state == Canister.State.TOWED)
	game.player.global_position = Tuning.depot_center() + Vector2(55.0, 0.0)
	var home: bool = false
	for i: int in range(150):
		await _frames(1)
		if dragged.state == Canister.State.IN_SLOT:
			home = true
			break
	var bonus: int = game.score - score_before
	_check("deposit returns the canister IN_SLOT", home)
	_check("recovery bonus pays within 100-600 x multiplier",
		bonus >= 100 and bonus <= 600)

	# (5) A kill bursts salvage shards; collecting one raises the multiplier.
	var slot2: Vector2 = Tuning.slot_position(2)
	var pirate2: Pirate = game.spawn_pirate("grabber", slot2 + Vector2(120.0, 0.0))
	for i: int in range(300):
		await _frames(1)
		if pirate2.held != null:
			break
	game.spawn_bullet(pirate2.global_position + Vector2(-30.0, 0.0), Vector2.RIGHT)
	for i: int in range(20):
		await _frames(1)
		if not is_instance_valid(pirate2):
			break
	_check("kill bursts salvage shards", game.shards.size() >= 1)
	var mult_before: float = game.multiplier
	if game.shards.size() > 0:
		game.player.global_position = game.shards[0].global_position
	for i: int in range(45):
		await _frames(1)
		if game.multiplier > mult_before:
			break
	_check("collecting a shard raises the multiplier",
		game.multiplier > mult_before)

	# (6) The multiplier decays when no shards are collected.
	game.clear_field()
	game.multiplier = 5.0
	game.mult_grace_t = 0.0
	game.player.global_position = Vector2(120.0, 120.0)
	await _frames(150)
	_check("multiplier decays without shard collection",
		game.multiplier < 4.2 and game.multiplier >= 1.0)

	# (7) All canisters GONE ends the run.
	for c: Canister in game.canisters:
		if c.state != Canister.State.GONE:
			c.mark_gone()
	await _frames(5)
	_check("all canisters GONE triggers GAMEOVER",
		game.state == Main.GameState.GAMEOVER)

	# (8) Player death halves the multiplier; respawn is invincible.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.multiplier = 4.0
	game.player.invincible_t = 0.0
	game.kill_player()
	_check("player death halves the multiplier",
		not game.player.alive and absf(game.multiplier - 2.0) < 0.01)
	await _frames(110)
	_check("respawn returns the ship with invincibility active",
		game.player.alive and game.player.is_invincible())

	print("HARNESS: %d/%d checks passed" % [_passed, _passed + _failed])
	get_tree().quit(0 if _failed == 0 else 1)
