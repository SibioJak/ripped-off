extends Node
## Headless verification harness for Ripped-Off (M1 + M2).
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


## Exit-stall helper: park a loose canister near one arena edge and
## let a grabber latch it and haul it out that edge. Returns true
## only if the canister goes GONE *and* the pirate is freed, all
## inside the frame budget. (Regression: a leaver used to park on
## its exit point, inside the despawn margin, forever.)
func _drag_out_through(edge: int) -> bool:
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 120.0)
	var loose_pos: Vector2 = Vector2(640.0, 210.0) # 0 = top
	var spawn_pos: Vector2 = Vector2(640.0, 252.0)
	match edge:
		1: # bottom
			loose_pos = Vector2(640.0, 590.0)
			spawn_pos = Vector2(640.0, 548.0)
		2: # left
			loose_pos = Vector2(210.0, 400.0)
			spawn_pos = Vector2(252.0, 400.0)
		3: # right
			loose_pos = Vector2(1070.0, 400.0)
			spawn_pos = Vector2(1028.0, 400.0)
	var can: Canister = game.canisters[0]
	can.set_loose(Vector2.ZERO)
	can.global_position = loose_pos
	var p: Pirate = game.spawn_pirate("grabber", spawn_pos)
	var gone: bool = false
	var freed: bool = false
	for i: int in range(900):
		await _frames(1)
		if can.state == Canister.State.GONE:
			gone = true
		if not is_instance_valid(p) or not game.pirates.has(p):
			freed = true
			break
	return gone and freed


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Main
	add_child(game)
	await _frames(3)
	# Captured for M3 check (29): the music director's boot state.
	var boot_music_title: bool = game.music != null \
		and game.music.mode == MusicDirector.Mode.TITLE

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

	# --- M2: rank, gunners, buzz, death bullet-cancel ----------------

	# (15) From wave 2 the director mixes gunners into the quota.
	game.start_run()
	game.director.active = false
	game.clear_field()
	seed(20261018)
	var saw_gunner: bool = false
	var round_i: int = 0
	while not saw_gunner and round_i < 3:
		round_i += 1
		game.director.start_wave(2) # quota 8, gunners enter the mix
		game.player.global_position = Tuning.depot_center() \
			+ Vector2(0.0, 195.0)
		var seen: int = 0
		while game.director.quota_left > 0 and seen < 40:
			var snapshot: Array[Pirate] = game.pirates.duplicate()
			for p: Pirate in snapshot:
				seen += 1
				if p.type_name == "gunner":
					saw_gunner = true
				game.pirates.erase(p)
				p.queue_free()
			await _frames(1)
	game.director.active = false
	_check("wave-2 quota includes at least one gunner", saw_gunner)

	# (16) The gunner's shot follows its charge telegraph; nothing
	# fires during the entry telegraph or mid-charge.
	game.clear_field()
	var g: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	game.player.global_position = Tuning.depot_center() \
		+ Vector2(0.0, 195.0)
	game.player.invincible_t = 0.0
	var fired_in_entry: bool = false
	var fired_mid_charge: bool = false
	var saw_charge: bool = false
	var bullets_seen: int = 0
	for i: int in range(300):
		await _frames(1)
		if not is_instance_valid(g):
			break
		bullets_seen = maxi(bullets_seen, game.enemy_bullets.size())
		if g.phase == Pirate.Phase.TELEGRAPH \
				and game.enemy_bullets.size() > 0:
			fired_in_entry = true
		if g.charge_frac() >= 0.0:
			saw_charge = true
			if game.enemy_bullets.size() > 0:
				fired_mid_charge = true
	_check("gunner shows a muzzle charge before firing", saw_charge)
	_check("gunner fires nothing during its entry telegraph",
		not fired_in_entry)
	_check("no enemy bullet exists while the charge winds up",
		not fired_mid_charge)
	_check("gunner fires an aimed enemy bullet", bullets_seen >= 1)

	# (17) A bullet grazing the ship pays buzz exactly once.
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.alive = true
	game.player.visible = true
	game.player.invincible_t = 99.0 # the pass can only be a pass
	var gz_mult_before: float = game.multiplier
	var gz_score_before: int = game.score
	# Path passes ~18px from the ship: inside BUZZ_RADIUS, no hit.
	game.spawn_enemy_bullet(Vector2(640.0, 220.0), Vector2(0.1, 1.0))
	var buzzed: bool = false
	var buzz_gain: int = 0
	for i: int in range(200):
		await _frames(1)
		if not buzzed and game.multiplier > gz_mult_before:
			buzzed = true
			buzz_gain = game.score - gz_score_before
	_check("grazing bullet pays buzz (score and multiplier up)",
		buzzed and buzz_gain > 0)
	_check("buzz pays exactly once while the bullet lingers",
		game.score == gz_score_before + buzz_gain
			and game.multiplier
				<= gz_mult_before + Tuning.BUZZ_MULT_NUDGE + 0.001)

	# (18) Death converts every live enemy bullet into shards.
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.alive = true
	game.player.invincible_t = 0.0
	game.spawn_enemy_bullet(Vector2(640.0, 100.0), Vector2.DOWN)
	game.spawn_enemy_bullet(Vector2(200.0, 100.0), Vector2.DOWN)
	game.spawn_enemy_bullet(Vector2(1100.0, 100.0), Vector2.DOWN)
	var bullets_live: int = game.enemy_bullets.size()
	var shards_pre: int = game.shards.size()
	game.kill_player()
	_check("death leaves zero live enemy bullets",
		bullets_live >= 2 and game.enemy_bullets.is_empty())
	_check("cancelled bullets become salvage shards",
		game.shards.size() >= shards_pre + bullets_live)

	# (19) Rank rises on kills and salvage, falls on death.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.rank = Tuning.RANK_START
	game.mult_grace_t = 0.0
	var rank_base: float = game.rank
	var slot3: Vector2 = Tuning.slot_position(3)
	var thief: Pirate = game.spawn_pirate("grabber",
		slot3 + Vector2(120.0, 0.0))
	for i: int in range(300):
		await _frames(1)
		if thief.held != null:
			break
	game.spawn_bullet(thief.global_position + Vector2(-30.0, 0.0),
		Vector2.RIGHT)
	for i: int in range(30):
		await _frames(1)
		if not is_instance_valid(thief):
			break
	if game.shards.size() > 0:
		game.player.global_position = game.shards[0].global_position
	for i: int in range(90):
		await _frames(1)
		if game.rank > rank_base + 0.02:
			break
	var rank_fed: float = game.rank
	_check("rank rises on a kill and shard collection",
		rank_fed > rank_base)
	game.player.invincible_t = 0.0
	game.kill_player()
	await _frames(5)
	_check("rank falls on player death", game.rank < rank_fed)

	# (20) Rank makes the director hungrier: the same quota drains
	# faster, and the concurrent-alive cap is higher.
	var d_low: SpawnDirector = SpawnDirector.new()
	var d_high: SpawnDirector = SpawnDirector.new()
	d_low.start_wave(10)
	d_high.start_wave(10)
	var t_low: float = 0.0
	while d_low.quota_left > 0 and t_low < 120.0:
		d_low.step(1.0 / 60.0, 0, Vector2.ZERO, 0.0)
		t_low += 1.0 / 60.0
	var t_high: float = 0.0
	while d_high.quota_left > 0 and t_high < 120.0:
		d_high.step(1.0 / 60.0, 0, Vector2.ZERO, 1.0)
		t_high += 1.0 / 60.0
	d_low.queue_free()
	d_high.queue_free()
	_check("high rank drains a spawn quota measurably faster",
		t_high + 1.0 < t_low)
	var cap_low: int = mini(
		Tuning.WAVE_MAX_ALIVE_BASE + 10 - 1 + Tuning.rank_alive_bonus(0.0),
		Tuning.WAVE_MAX_ALIVE_CAP + Tuning.rank_alive_bonus(0.0))
	var cap_high: int = mini(
		Tuning.WAVE_MAX_ALIVE_BASE + 10 - 1 + Tuning.rank_alive_bonus(1.0),
		Tuning.WAVE_MAX_ALIVE_CAP + Tuning.rank_alive_bonus(1.0))
	_check("high rank lifts the concurrent-alive cap", cap_high > cap_low)

	# --- M3: audio assets, music director, sfx routing ----------------

	# (28) Every rendered asset exists; music loop lengths match the
	# render manifest's exact sample counts (the engine reports OGG
	# lengths sample-exact for these files; probe deviation was
	# 0.01 samples, tolerance is 4).
	var manifest_file: FileAccess = FileAccess.open(
		"res://audio/manifest.json", FileAccess.READ)
	_check("audio manifest exists", manifest_file != null)
	var manifest: Dictionary = {}
	if manifest_file != null:
		var parsed_m: Variant = JSON.parse_string(manifest_file.get_as_text())
		if typeof(parsed_m) == TYPE_DICTIONARY:
			manifest = parsed_m as Dictionary
	var music_entries: Dictionary = {}
	var sfx_entries: Dictionary = {}
	if manifest.has("music"):
		music_entries = manifest["music"] as Dictionary
	if manifest.has("sfx"):
		sfx_entries = manifest["sfx"] as Dictionary
	_check("manifest lists 12 music loops and 15 sfx",
		music_entries.size() == 12 and sfx_entries.size() == 15)
	var assets_ok: bool = true
	var lengths_ok: bool = true
	var mkeys: Array = music_entries.keys()
	for key: Variant in mkeys:
		var entry: Dictionary = music_entries[key] as Dictionary
		var mpath: String = "res://" + String(entry["file"])
		if not FileAccess.file_exists(mpath):
			assets_ok = false
			continue
		var mstream: AudioStream = load(mpath) as AudioStream
		if mstream == null:
			assets_ok = false
			continue
		var measured: float = mstream.get_length() * 44100.0
		var expected: float = float(int(entry["samples"]))
		if absf(measured - expected) > 4.0:
			lengths_ok = false
	var skeys: Array = sfx_entries.keys()
	for key: Variant in skeys:
		var entry2: Dictionary = sfx_entries[key] as Dictionary
		if not FileAccess.file_exists("res://" + String(entry2["file"])):
			assets_ok = false
	_check("all audio assets exist on disk", assets_ok)
	_check("music loop lengths match beat specs within 4 samples",
		lengths_ok)

	# (29) Music director state machine (headless audio is a dummy
	# driver: these assert the director's decisions, not audible
	# output). Boot: TITLE with the title loop the active layer.
	_check("music director boots in TITLE mode", boot_music_title)
	game.music.set_mode_title()
	_check("TITLE mode targets the title loop on and stems silent",
		game.music.layer_target_db("title") > MusicDirector.SILENT_DB
			and game.music.layer_target_db("kick")
				== MusicDirector.SILENT_DB)
	game.start_run()
	await _frames(2)
	_check("run start targets kick and bass on, title off",
		game.music.layer_target_db("kick") > MusicDirector.SILENT_DB
			and game.music.layer_target_db("bass")
				> MusicDirector.SILENT_DB
			and game.music.layer_target_db("title")
				== MusicDirector.SILENT_DB)
	game.rank = 0.1
	game.music.set_rank(0.1)
	_check("at rank 0.1 the arp layer stays silent",
		game.music.layer_target_db("arp") == MusicDirector.SILENT_DB)
	game.rank = 0.9
	game.music.set_rank(0.9)
	_check("at rank 0.9 the arp and drive layers target on",
		game.music.layer_target_db("arp") > MusicDirector.SILENT_DB
			and game.music.layer_target_db("drive")
				> MusicDirector.SILENT_DB)

	# (30) Variant rotation advances through the bank; only the
	# active variant may target the layer gain.
	var bass_before: int = game.music.active_variant("bass")
	game.music.advance_rotation()
	var bass_after: int = game.music.active_variant("bass")
	_check("rotation advances the bass variant", bass_after != bass_before)
	_check("only the active bass variant targets the layer gain",
		game.music.variant_target_db("bass", bass_after)
				== game.music.layer_target_db("bass")
			and game.music.variant_target_db("bass", bass_before)
				== MusicDirector.SILENT_DB)
	var arp_before: int = game.music.active_variant("arp")
	game.music.advance_rotation()
	_check("rotation advances the arp variant",
		game.music.active_variant("arp") != arp_before)

	# (31) SFX routing: calls land on pool players with streams set;
	# one-shot pitch varies inside +/-4%; the collect combo steps
	# pitch up; music pitch is never touched.
	var shot_player: AudioStreamPlayer2D = game.sfx.play(
		"shot", Vector2(300.0, 300.0))
	_check("shot routes to the sfx pool with a stream",
		shot_player != null and shot_player.stream != null)
	_check("shot pitch_scale lands within 0.96..1.04",
		shot_player != null and shot_player.pitch_scale >= 0.96
			and shot_player.pitch_scale <= 1.04)
	_check("sfx players sit at their event positions",
		shot_player != null
			and shot_player.global_position == Vector2(300.0, 300.0))
	var collect_1: AudioStreamPlayer2D = game.sfx.play_collect(
		Vector2(320.0, 300.0))
	var collect_2: AudioStreamPlayer2D = game.sfx.play_collect(
		Vector2(320.0, 300.0))
	_check("collect combo steps the pitch up between quick pickups",
		collect_1 != null and collect_2 != null
			and collect_2.pitch_scale > collect_1.pitch_scale * 1.02)
	var death_player: AudioStreamPlayer2D = game.sfx.play(
		"player_death", Vector2(640.0, 400.0))
	_check("player death routes to the sfx pool",
		death_player != null and death_player.stream != null)
	var music_pitch_ok: bool = true
	var all_music: Array[AudioStreamPlayer] = game.music.all_players()
	for mp: AudioStreamPlayer in all_music:
		if mp.pitch_scale != 1.0:
			music_pitch_ok = false
	_check("every music player keeps pitch_scale exactly 1.0",
		music_pitch_ok and all_music.size() == 12)

	# --- M3 fix: the exit stall (a leaver parked on its exit point,
	# inside the despawn margin, and held the wave forever) ---------

	# (32-35) A grabber drags a canister out through EACH edge: the
	# canister resolves GONE and the pirate is freed, every time.
	var out_top: bool = await _drag_out_through(0)
	_check("drag-out top: canister GONE and pirate freed", out_top)
	var out_bottom: bool = await _drag_out_through(1)
	_check("drag-out bottom: canister GONE and pirate freed", out_bottom)
	var out_left: bool = await _drag_out_through(2)
	_check("drag-out left: canister GONE and pirate freed", out_left)
	var out_right: bool = await _drag_out_through(3)
	_check("drag-out right: canister GONE and pirate freed", out_right)

	# (36) The no-canister exit: with nothing stealable, a grabber
	# enters LEAVE — and the leave actually completes.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 680.0)
	for c: Canister in game.canisters:
		c.state = Canister.State.TOWED # unavailable as a target
	var leaver: Pirate = game.spawn_pirate("grabber", Vector2(640.0, 100.0))
	var saw_leave: bool = false
	var leaver_freed: bool = false
	for i: int in range(600):
		await _frames(1)
		if is_instance_valid(leaver) and leaver.phase == Pirate.Phase.LEAVE:
			saw_leave = true
		if not is_instance_valid(leaver) or not game.pirates.has(leaver):
			leaver_freed = true
			break
	_check("with no target a grabber enters LEAVE", saw_leave)
	_check("an empty leaver flies out and is freed", leaver_freed)

	# (37) A gunner's end path: it never exits on its own — it holds
	# its post until killed; a bullet kill is what frees it.
	game.start_run()
	game.director.active = false
	game.clear_field()
	var gun: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	game.player.global_position = Tuning.depot_center() \
		+ Vector2(0.0, 195.0)
	var holding: bool = false
	for i: int in range(300):
		await _frames(1)
		if is_instance_valid(gun) and gun.phase == Pirate.Phase.HOLD:
			holding = true
			break
	_check("gunner reaches its HOLD post", holding)
	game.spawn_bullet(gun.global_position + Vector2(-30.0, 0.0),
		Vector2.RIGHT)
	var gun_down: bool = false
	for i: int in range(30):
		await _frames(1)
		if not is_instance_valid(gun):
			gun_down = true
			break
	_check("a HOLD gunner is freed by a bullet kill (its only exit)",
		gun_down)

	# (38) The exit watchdog: a leaver pinned where it can never
	# cross the despawn boundary is left alone while young, then
	# force-freed once it passes the Tuning limit.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 680.0)
	for c: Canister in game.canisters:
		c.state = Canister.State.TOWED
	var stuck: Pirate = game.spawn_pirate("grabber", Vector2(640.0, 100.0))
	var watchdog_frames: int = int(Tuning.EXIT_WATCHDOG_TIME * 60.0)
	var still_at_300: bool = false
	var stuck_freed: bool = false
	for i: int in range(watchdog_frames + 240):
		await _frames(1)
		if not is_instance_valid(stuck) or not game.pirates.has(stuck):
			stuck_freed = true
			break
		stuck.global_position = Vector2(640.0, 60.0) # pinned inside
		if i == 300:
			still_at_300 = game.pirates.has(stuck)
	_check("watchdog does not free a young leaver", still_at_300)
	_check("watchdog force-frees a permanently stuck leaver", stuck_freed)

	# (39) Stall soak: three full waves behind a stand-in player
	# (unkillable; it clears every pirate through Main's real kill
	# path the moment it appears). Wave progression itself is what
	# is on trial — stepped directly so the soak runs fast.
	game.start_run() # director live for this one
	game.player.invincible_t = 1000000000.0
	var soak_frames: int = 0
	while game.wave < 4 and soak_frames < 9000:
		game._physics_process(1.0 / 60.0)
		soak_frames += 1
		var field_now: Array[Pirate] = game.pirates.duplicate()
		for p: Pirate in field_now:
			game.kill_pirate(p, false)
	await _frames(3)
	_check("soak: three full waves advance without a stall",
		game.wave >= 4 and game.state == Main.GameState.RUNNING)
	print("SOAK: reached wave %d in %d stepped frames"
		% [game.wave, soak_frames])

	print("HARNESS: %d/%d checks passed" % [_passed, _passed + _failed])
	get_tree().quit(0 if _failed == 0 else 1)
