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

## M5 helper state: counts the Player's fired emissions (the
## rapid-fire cadence and spread fan-out checks read it).
var _fired_count: int = 0


func _count_fired(_from: Vector2, _dir: Vector2) -> void:
	_fired_count += 1


## M6 helper state: the pirate whose fired emissions the lead
## check inspects (its step context is the exact input the shot
## was computed from), and the types a driven director deals
## (the mix and alive-cap checks read them).
var _watch_pirate: Pirate = null
var _lead_shots: Array[Dictionary] = []
var _dealt_types: Array[String] = []


func _record_lead(from: Vector2, dir: Vector2) -> void:
	if _watch_pirate == null:
		return
	_lead_shots.append({
		"from": from, "dir": dir,
		"ppos": _watch_pirate.player_pos,
		"pvel": _watch_pirate.player_vel})


func _record_spawn(type_name: String, _pos: Vector2) -> void:
	_dealt_types.append(type_name)


## M7 helper state: a staged pirate's fired count and conversion
## stage emissions (the timeline-integrity check reads them).
var _conv_shots: int = 0
var _conv_stages: Array[int] = []


func _count_conv_shot(_from: Vector2, _dir: Vector2) -> void:
	_conv_shots += 1


func _record_conv_stage(stage: int) -> void:
	_conv_stages.append(stage)


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


## M4 helper: wait for the given boss to finish its descent and
## reach ACTIVE. Returns the boss (or null if it never spawned).
func _await_boss_active(b: Boss) -> Boss:
	if b == null:
		return null
	for i: int in range(500):
		await _frames(1)
		if b.phase == Boss.Phase.ACTIVE:
			break
	return b


## M4 helper: start a fresh run and drive it into the wave-5 boss
## wave through Main's real wave flow; the player parks far away,
## invincible, so the boss's systems run undisturbed.
func _start_boss_wave() -> Boss:
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.wave = 4
	game._start_next_wave() # -> wave 5: a boss wave
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var b: Boss = null
	for i: int in range(300):
		await _frames(1)
		if game.bosses.size() > 0:
			b = game.bosses[0]
			break
	return await _await_boss_active(b)


## M4 helper: clear enemy bullets and shards WITHOUT touching the
## boss (game.clear_field() would free it — it is a start_run lever).
func _clear_hostiles() -> void:
	for eb: EnemyBullet in game.enemy_bullets:
		eb.queue_free()
	game.enemy_bullets.clear()
	for s: Shard in game.shards:
		s.queue_free()
	game.shards.clear()


## M4 helper: land `hits` real player bullets on the boss's hull
## (aimed at the hull-circle zone, clear of every part circle).
func _shoot_hull(b: Boss, hits: int) -> void:
	for i: int in range(hits):
		var hp: Vector2 = b.global_position + Vector2(0.0, 10.0)
		game.spawn_bullet(hp + Vector2(-50.0, 0.0), Vector2.RIGHT)
		await _frames(2)


## M4 helper: land real player bullets on one boss part until it
## breaks (bounded). Returns true if the part broke.
func _shoot_part_until_broken(b: Boss, part_id: String) -> bool:
	for i: int in range(80):
		if b.is_part_broken(part_id):
			return true
		var pp: Vector2 = b.part_world(part_id)
		game.spawn_bullet(pp + Vector2(-40.0, 0.0), Vector2.RIGHT)
		await _frames(2)
	return b.is_part_broken(part_id)


## Proximity helper: land exactly one real player bullet on one
## boss part. The shot approaches from the part's OUTER side:
## fired from the left, the right turret sits behind a hull
## circle and the bullet legitimately hits hull first (the
## until-broken helper can grind through that; a one-shot
## damage measurement cannot).
func _shoot_part_once(b: Boss, part_id: String) -> void:
	var pp: Vector2 = b.part_world(part_id)
	var dir: Vector2 = Vector2.RIGHT
	if pp.x > b.global_position.x:
		dir = Vector2.LEFT
	game.spawn_bullet(pp - dir * 40.0, dir)
	await _frames(3)


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	game = packed.instantiate() as Main
	add_child(game)
	game.player.fired.connect(_count_fired)
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
	# Park the ship clear of the latch (setup only — the
	# assertions below are unchanged): the pirate's latch stop
	# sits 29px from where check (4) left the ship, outside the
	# OLD 26px contact sum but inside the danmaku split's new
	# 30px body sum, so an unparked ship now dies during this
	# wait and cannot collect.
	game.player.global_position = Vector2(120.0, 120.0)
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
		game.director.start_wave(2) # quota 12 (M6 retune), gunners enter the mix
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
	# M7 staging note: a FRESH run starts this check. Check (15)
	# left the director's quota drained to zero with a thief
	# having existed — precisely a live conversion trigger state
	# (quota-spent + dead air), and a lone gunner parked here for
	# seconds would now legitimately convert mid-check and stop
	# firing. The fresh run resets the per-wave conversion state
	# (and the quota); the assertions below are untouched.
	game.start_run()
	game.director.active = false
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

	# --- Furniture fix: stage centering, banner, aim integrity ----

	# (57) The stage-offset helper (pure math): no offset at the
	# design size, half the surplus per axis beyond it, clamped
	# to zero on a smaller canvas.
	_check("stage offset is zero at the 1280x800 design size",
		Tuning.stage_offset_for(Vector2(1280.0, 800.0)) == Vector2.ZERO)
	_check("stage offset centers a wider canvas (1422x800 -> 71, 0)",
		Tuning.stage_offset_for(Vector2(1422.0, 800.0))
			== Vector2(71.0, 0.0))
	_check("stage offset centers a taller canvas (1280x1024 -> 0, 112)",
		Tuning.stage_offset_for(Vector2(1280.0, 1024.0))
			== Vector2(0.0, 112.0))
	_check("stage offset splits a wider-and-taller surplus per axis",
		Tuning.stage_offset_for(Vector2(1600.0, 1000.0))
			== Vector2(160.0, 100.0))
	_check("stage offset clamps a smaller canvas to zero",
		Tuning.stage_offset_for(Vector2(1000.0, 700.0)) == Vector2.ZERO)

	# (58) The wave banner's first baseline is the stage's
	# vertical center (it drew at 0.32 x VIEW_H before the fix).
	_check("wave banner draws at the stage's vertical center",
		game.hud.center_line_y() == Tuning.VIEW_H * 0.5)

	# (59) Mouse aim resolves in global (world) space, so the
	# stage offset cannot skew it. Headless pins the cursor at
	# world (0,0) — a known point, which is all the geometry
	# needs: the same design-space ship position must produce
	# DIFFERENT facings with and without the offset, each equal
	# to the global-space expectation. A raw-viewport/local-space
	# aim would give the same facing in both cases and fail.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.position = Vector2.ZERO
	game.player.global_position = Vector2(200.0, 150.0)
	game.player.facing = Vector2.RIGHT
	await _frames(6)
	var aim_flat: Vector2 = game.player.facing
	var expect_flat: Vector2 = (
		Vector2.ZERO - Vector2(200.0, 150.0)).normalized()
	_check("aim matches global-space geometry with no stage offset",
		aim_flat.angle_to(expect_flat) < 0.02)
	game.position = Vector2(71.0, 112.0)
	game.player.global_position = Vector2(71.0, 112.0) \
		+ Vector2(200.0, 150.0)
	game.player.facing = Vector2.RIGHT
	await _frames(6)
	var aim_off: Vector2 = game.player.facing
	var expect_off: Vector2 = (Vector2.ZERO
		- (Vector2(71.0, 112.0) + Vector2(200.0, 150.0))).normalized()
	_check("aim matches global-space geometry under a stage offset",
		aim_off.angle_to(expect_off) < 0.02)
	_check("the stage offset measurably changes the aim solution",
		aim_flat.angle_to(aim_off) > 0.05)
	game.position = Vector2.ZERO

	# (60) Centered text is measured, not alignment-boxed: the
	# origin from Hud.centered_origin plus half the real
	# font-measured width lands on the stage center (640) for
	# every screen that draws through _text_center (wave banner,
	# PAUSED, title, game over). Regression: draw_string's
	# CENTER box started at the caller's x and extended VIEW_W,
	# centering text on the stage's right edge instead — only
	# "WA" of WAVE 17 reached the screen, at the right border.
	var center_font: Font = ThemeDB.fallback_font
	var center_cases: Array = [
		["WAVE 17", 40],
		["RIPPED-OFF", 84],
		["Fire ............ Hold Left Mouse  /  Space  /  Right Trigger  /  A Button", 21],
	]
	for case_v: Variant in center_cases:
		var case_arr: Array = case_v as Array
		var case_text: String = case_arr[0] as String
		var case_size: int = case_arr[1] as int
		var origin: Vector2 = game.hud.centered_origin(
			case_text, case_size, Tuning.VIEW_W * 0.5, 0.0)
		var measured: float = center_font.get_string_size(case_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, case_size).x
		_check("centered text centers on the stage middle: '%s'"
			% case_text,
			absf(origin.x + measured * 0.5 - Tuning.VIEW_W * 0.5) <= 1.0)

	# --- M4: the Dreadnought (first boss, every 5th wave) ---------

	# (69) Wave 5 is a boss wave: the director's pirate quota is
	# replaced by the single boss, which enters and reaches its
	# station; no pirates spawn.
	var boss: Boss = await _start_boss_wave()
	await _frames(120)
	_check("wave 5 is a boss wave: Dreadnought reaches station, no pirate quota",
		boss != null and boss.phase == Boss.Phase.ACTIVE
			and game.boss_wave and game.director.quota_exhausted()
			and game.pirates.is_empty())

	# (70) A turret takes damage through the real bullet path,
	# breaks at its HP, and stops firing — while the other turret
	# keeps the cadence alone.
	var turret_broke: bool = await _shoot_part_until_broken(
		boss, Boss.PART_TURRET_L)
	var sl0: int = boss.shots_left
	var sr0: int = boss.shots_right
	await _frames(300)
	_check("turret breaks at its HP and stops firing; the other keeps firing",
		turret_broke and boss.shots_left == sl0
			and boss.shots_right > sr0)

	# (71) Hull hits pay tick points through the multiplier and
	# route the hit_tick confirm (sfx play counter). Turret fire
	# is parked so no buzz can disturb the exact score delta.
	boss.park_turrets() # no in-progress shot may buzz the delta
	_clear_hostiles()
	game.multiplier = 1.0
	game.mult_grace_t = 99.0
	var tick_score0: int = game.score
	var tick_plays0: int = int(game.sfx.play_count.get("hit_tick", 0))
	for i: int in range(3):
		var hp1: Vector2 = boss.global_position + Vector2(0.0, 10.0)
		game.spawn_bullet(hp1 + Vector2(-50.0, 0.0), Vector2.RIGHT)
		await _frames(8) # > the 50 ms hit_tick throttle
	_check("hull hits pay tick points and route hit_tick",
		game.score - tick_score0 == 3 * Tuning.BOSS_TICK_POINTS
			and int(game.sfx.play_count.get("hit_tick", 0)) - tick_plays0 == 3)

	# (72) Grab arm: the telegraph precedes the latch; a slotted
	# canister leaves IN_SLOT under arm drag; breaking the arm
	# mid-drag drops it LOOSE; a completed drag on a fresh boss
	# consumes a canister (GONE, count drops, wave does not end).
	game.bosses.erase(boss)
	boss.queue_free()
	var boss2: Boss = await _await_boss_active(game.spawn_boss(5))
	var arm_target: Canister = null
	for i: int in range(700):
		await _frames(1)
		for c: Canister in game.canisters:
			if c.state == Canister.State.DRAGGING and c.holder == boss2:
				arm_target = c
				break
		if arm_target != null:
			break
	var arm_broke: bool = await _shoot_part_until_broken(
		boss2, Boss.PART_ARM)
	_check("arm telegraph precedes latch; slotted canister drags; arm break drops it LOOSE",
		arm_target != null and boss2.arm_telegraphed_once
			and arm_broke and arm_target.state == Canister.State.LOOSE)
	game.bosses.erase(boss2)
	boss2.queue_free()
	var boss3: Boss = await _await_boss_active(game.spawn_boss(5))
	var cans_before: int = game.canisters_remaining()
	var eaten: Canister = null
	for i: int in range(700):
		await _frames(1)
		for c: Canister in game.canisters:
			if c.state == Canister.State.DRAGGING and c.holder == boss3:
				eaten = c
				break
		if eaten != null:
			break
	var consumed: bool = false
	if eaten != null:
		for i: int in range(400):
			await _frames(1)
			if eaten.state == Canister.State.GONE:
				consumed = true
				break
	_check("a completed arm drag consumes the canister (GONE, count drops)",
		consumed and game.canisters_remaining() == cans_before - 1
			and game.wave == 5 and game.boss_wave)

	# (73) Radial bursts fire once at each hull threshold (66%,
	# then 33%) — a ring of bullets at the crossing, and no
	# repeat while the hull stays below the line.
	var eb_base: int = game.enemy_bullets.size()
	var guard1: int = 0
	while boss3.hull_hp > 79 and guard1 < 200:
		guard1 += 1
		await _shoot_hull(boss3, 1)
	for i: int in range(120):
		await _frames(1)
		if boss3.radial_count >= 1:
			break
	var ring_jump: bool = game.enemy_bullets.size() >= eb_base + 8
	var guard2: int = 0
	while boss3.hull_hp > 39 and guard2 < 200:
		guard2 += 1
		await _shoot_hull(boss3, 1)
	for i: int in range(120):
		await _frames(1)
		if boss3.radial_count >= 2:
			break
	await _shoot_hull(boss3, 10)
	await _frames(90)
	_check("radial bursts fire once at the 66% and 33% hull thresholds",
		ring_jump and boss3.radial_count == 2)

	# (74) Boss death: the staged sequence completes, the payout
	# lands, the shard fountain spawns, and the wave advances —
	# even with a player death in the middle of the spectacle.
	var death_score0: int = game.score
	for i: int in range(200):
		await _frames(1)
		if boss3.phase == Boss.Phase.DYING:
			break
		if i % 2 == 0:
			await _shoot_hull(boss3, 1)
	var saw_dying: bool = boss3.phase == Boss.Phase.DYING
	game.player.invincible_t = 0.0
	game.kill_player() # death DURING the death sequence
	var player_died_mid_death: bool = not game.player.alive
	for i: int in range(300):
		await _frames(1)
		if game.wave == 6:
			break
	_check("boss death completes: payout lands, fountain spawns, wave advances",
		saw_dying and player_died_mid_death and game.wave == 6
			and game.bosses.is_empty() and not game.boss_wave
			and game.score - death_score0
				>= Tuning.boss_score_value(1)
			and game.shards.size() >= 12)

	# (75) Tier scaling: a wave-10 boss has strictly more hull
	# than a wave-5 boss.
	var t5: Boss = game.spawn_boss(5)
	var t10: Boss = game.spawn_boss(10)
	_check("tier scaling: wave-10 hull strictly exceeds wave-5",
		t10.max_hull_hp > t5.max_hull_hp
			and t5.max_hull_hp == Tuning.BOSS_HULL_HP)
	game.bosses.erase(t5)
	t5.queue_free()
	game.bosses.erase(t10)
	t10.queue_free()

	# (76) Player contact with the boss kills the player and does
	# not damage the boss (no ram-kill on a capital).
	var boss4: Boss = await _start_boss_wave()
	boss4.park_turrets() # isolate contact from turret fire
	_clear_hostiles()
	var hull_full: int = boss4.hull_hp
	game.player.invincible_t = 0.0
	game.player.global_position = boss4.global_position
	var contact_died: bool = false
	for i: int in range(15):
		await _frames(1)
		if not game.player.alive:
			contact_died = true
			break
	_check("player contact with the boss kills the player, boss undamaged",
		contact_died and boss4.hull_hp == hull_full)

	# (77) Turret independence (M4 pressure fix): each turret runs
	# its own cycle (2.2s cooldown + 0.4s charge at tier 1), so in
	# a 6s window from ACTIVE both turrets fire and the pair lands
	# at least 4 shots through the real fired-signal path. (The
	# old shared alternating cadence at 2.8s managed ~2 shots in
	# the same window, total, from one turret at a time.)
	var boss5: Boss = await _start_boss_wave()
	var first_l: int = -1
	var first_r: int = -1
	var window_frames: int = 360 # 6.0s of ACTIVE fight time
	for i: int in range(window_frames):
		await _frames(1)
		if first_l < 0 and boss5.shots_left > 0:
			first_l = i
		if first_r < 0 and boss5.shots_right > 0:
			first_r = i
	_check("both turrets fire in a 6s window (left %d, right %d)"
		% [boss5.shots_left, boss5.shots_right],
		boss5.shots_left >= 1 and boss5.shots_right >= 1)
	_check("independent turrets yield >= 4 shots in 6s (got %d)"
		% (boss5.shots_left + boss5.shots_right),
		boss5.shots_left + boss5.shots_right >= 4)

	# (78) The stagger: the right turret's first cycle starts
	# half an interval behind the left's, so the two first shots
	# land at clearly different times — never a synchronized
	# volley. 30 frames = 0.5s at the 60 fps physics step.
	_check("first shots are staggered by >= 0.5s (left frame %d, right frame %d)"
		% [first_l, first_r],
		first_l >= 0 and first_r >= 0
			and absf(float(first_l - first_r)) >= 30.0)
	print("BOSS FIRE: left first shot frame %d, right frame %d; window totals L%d R%d"
		% [first_l, first_r, boss5.shots_left, boss5.shots_right])

	# --- Dreadnought proximity bonus ------------------------------
	# Close-range hits (player within 300px of the boss's centre
	# at impact) deal 2 damage and pay the boosted 20-point tick;
	# far hits keep the original 1 damage / 5 points. All hits go
	# through Main's real bullet path with the multiplier pinned
	# at exactly 1.0, so score deltas are exact.
	var boss6: Boss = await _start_boss_wave()
	boss6.park_turrets() # no enemy bullet may buzz the exact deltas
	_clear_hostiles()
	game.multiplier = 1.0
	game.mult_grace_t = 99.0

	# (81) FAR hull hit: exactly 1 HP and exactly the base tick.
	game.player.global_position = boss6.global_position + Vector2(500.0, 0.0)
	var far_hull0: int = boss6.hull_hp
	var far_score0: int = game.score
	await _shoot_hull(boss6, 1)
	_check("far boss hull hit deals 1 damage and pays 5 tick points (hp %d -> %d, score +%d)"
		% [far_hull0, boss6.hull_hp, game.score - far_score0],
		boss6.hull_hp == far_hull0 - 1
			and game.score - far_score0 == Tuning.BOSS_TICK_POINTS)

	# (82) CLOSE hull hit: exactly 2 HP and exactly the boosted tick.
	game.player.global_position = boss6.global_position + Vector2(250.0, 0.0)
	var close_hull0: int = boss6.hull_hp
	var close_score0: int = game.score
	await _shoot_hull(boss6, 1)
	_check("close boss hull hit deals 2 damage and pays 20 tick points (hp %d -> %d, score +%d)"
		% [close_hull0, boss6.hull_hp, game.score - close_score0],
		boss6.hull_hp == close_hull0 - Tuning.BOSS_PROXIMITY_DAMAGE
			and game.score - close_score0
				== Tuning.BOSS_PROXIMITY_TICK_POINTS)

	# (83) Part hits follow the same rule: 1 HP far, 2 HP close.
	var prox_part: String = Boss.PART_TURRET_R
	game.player.global_position = boss6.global_position + Vector2(500.0, 0.0)
	var far_part0: int = boss6.part_hp(prox_part)
	await _shoot_part_once(boss6, prox_part)
	var far_part_delta: int = far_part0 - boss6.part_hp(prox_part)
	game.player.global_position = boss6.global_position + Vector2(250.0, 0.0)
	var close_part0: int = boss6.part_hp(prox_part)
	await _shoot_part_once(boss6, prox_part)
	var close_part_delta: int = close_part0 - boss6.part_hp(prox_part)
	_check("boss part hits deal 1 damage far and 2 close (far -%d, close -%d)"
		% [far_part_delta, close_part_delta],
		far_part_delta == 1
			and close_part_delta == Tuning.BOSS_PROXIMITY_DAMAGE)

	# (84) The boundary itself: exactly the radius counts as close.
	_check("proximity boundary: 300.0 counts as close, 301.0 does not",
		Tuning.boss_proximity_active(Vector2(300.0, 0.0), Vector2.ZERO)
			and not Tuning.boss_proximity_active(
				Vector2(301.0, 0.0), Vector2.ZERO))

	# (85) The HUD indicator follows the boss's proximity state:
	# live inside the band, dark outside it.
	game.player.global_position = boss6.global_position + Vector2(250.0, 0.0)
	await _frames(2)
	game._sync_hud()
	var indicator_close: bool = boss6.proximity_active \
		and game.hud.boss_bar_close_bonus
	game.player.global_position = boss6.global_position + Vector2(500.0, 0.0)
	await _frames(2)
	game._sync_hud()
	var indicator_far: bool = not boss6.proximity_active \
		and not game.hud.boss_bar_close_bonus
	_check("close-bonus HUD indicator is live inside the band and dark outside",
		indicator_close and indicator_far)

	# (86) A close 2-damage hit crossing the 66% threshold queues
	# exactly one radial burst (the ring counter moves by one).
	var boss7: Boss = await _start_boss_wave()
	boss7.park_turrets()
	_clear_hostiles()
	boss7.hull_hp = 80 # one close hit crosses 79.2 (66% of 120)
	game.player.global_position = boss7.global_position + Vector2(250.0, 0.0)
	var radial_before: int = boss7.radial_count
	await _shoot_hull(boss7, 1)
	for i: int in range(150):
		await _frames(1)
		if boss7.radial_count > radial_before:
			break
	_check("close 2-damage threshold crossing queues exactly one radial (hp %d, rings %d -> %d)"
		% [boss7.hull_hp, radial_before, boss7.radial_count],
		boss7.hull_hp == 80 - Tuning.BOSS_PROXIMITY_DAMAGE
			and boss7.radial_count == radial_before + 1)

	# --- Pass-through weak points --------------------------------
	# A part hit also wounds the hull by the same amount: the
	# part resolves first (a breaking hit always lands its break
	# payout), then the hull takes the identical amount through
	# damage_hull. Tick points stay paid ONCE per connecting
	# bullet at the proximity rate — no second payment for the
	# pass-through. Same discipline as 81-86: real bullet path,
	# multiplier pinned at 1.0, turrets parked, field cleared.
	var boss8: Boss = await _start_boss_wave()
	boss8.park_turrets()
	_clear_hostiles()
	game.multiplier = 1.0
	game.mult_grace_t = 99.0

	# (87) FAR part hit: part -1, hull -1, one base tick (+5).
	game.player.global_position = boss8.global_position + Vector2(500.0, 0.0)
	var pt_part0: int = boss8.part_hp(Boss.PART_TURRET_L)
	var pt_hull0: int = boss8.hull_hp
	var pt_score0: int = game.score
	await _shoot_part_once(boss8, Boss.PART_TURRET_L)
	_check("far part hit passes through: part -1, hull -1, one 5-point tick (part %d -> %d, hull %d -> %d, score +%d)"
		% [pt_part0, boss8.part_hp(Boss.PART_TURRET_L), pt_hull0,
			boss8.hull_hp, game.score - pt_score0],
		boss8.part_hp(Boss.PART_TURRET_L) == pt_part0 - 1
			and boss8.hull_hp == pt_hull0 - 1
			and game.score - pt_score0 == Tuning.BOSS_TICK_POINTS)

	# (88) CLOSE part hit: part -2, hull -2, one boosted tick (+20).
	game.player.global_position = boss8.global_position + Vector2(250.0, 0.0)
	var pc_part0: int = boss8.part_hp(Boss.PART_TURRET_L)
	var pc_hull0: int = boss8.hull_hp
	var pc_score0: int = game.score
	await _shoot_part_once(boss8, Boss.PART_TURRET_L)
	_check("close part hit passes through: part -2, hull -2, one 20-point tick (part %d -> %d, hull %d -> %d, score +%d)"
		% [pc_part0, boss8.part_hp(Boss.PART_TURRET_L), pc_hull0,
			boss8.hull_hp, game.score - pc_score0],
		boss8.part_hp(Boss.PART_TURRET_L)
				== pc_part0 - Tuning.BOSS_PROXIMITY_DAMAGE
			and boss8.hull_hp == pc_hull0 - Tuning.BOSS_PROXIMITY_DAMAGE
			and game.score - pc_score0
				== Tuning.BOSS_PROXIMITY_TICK_POINTS)

	# (89) A part hit whose pass-through crosses the 66% hull
	# line queues exactly one radial burst, as a hull hit would.
	var boss9: Boss = await _start_boss_wave()
	boss9.park_turrets()
	_clear_hostiles()
	boss9.hull_hp = 80 # just above the 66% line (79.2 of 120)
	game.player.global_position = boss9.global_position + Vector2(500.0, 0.0)
	var th_part0: int = boss9.part_hp(Boss.PART_TURRET_L)
	var th_radial0: int = boss9.radial_count
	await _shoot_part_once(boss9, Boss.PART_TURRET_L)
	for i: int in range(150):
		await _frames(1)
		if boss9.radial_count > th_radial0:
			break
	await _frames(45) # settle: a phantom second ring would show
	_check("part hit crossing the 66%% hull line queues exactly one radial (hull %d, part %d -> %d, rings %d -> %d)"
		% [boss9.hull_hp, th_part0, boss9.part_hp(Boss.PART_TURRET_L),
			th_radial0, boss9.radial_count],
		boss9.hull_hp == 79
			and boss9.part_hp(Boss.PART_TURRET_L) == th_part0 - 1
			and boss9.radial_count == th_radial0 + 1)

	# (90) Lethal pass-through with a simultaneous break — on
	# the grab arm WHILE it is mid-pull on a canister. One close
	# hit breaks the arm (break payout lands: 20 tick + 300
	# break bonus at mult 1.0 = 320, nothing else pays in the
	# window) and the pass-through kills the hull: the held
	# canister drops LOOSE via the break/death path, and the
	# staged death completes — wave advances, no soft-lock.
	var boss10: Boss = await _start_boss_wave()
	boss10.park_turrets()
	_clear_hostiles()
	game.multiplier = 1.0
	game.mult_grace_t = 99.0
	var held: Canister = null
	for i: int in range(700):
		await _frames(1)
		for c: Canister in game.canisters:
			if c.state == Canister.State.DRAGGING and c.holder == boss10:
				held = c
				break
		if held != null:
			break
	# Direct writes (the check-86/89 precedent): the arm is one
	# close hit from breaking, the hull one close pass-through
	# from death.
	var arm_pd: Dictionary = boss10._parts[Boss.PART_ARM] as Dictionary
	arm_pd["hp"] = Tuning.BOSS_PROXIMITY_DAMAGE
	boss10._parts[Boss.PART_ARM] = arm_pd
	boss10.hull_hp = Tuning.BOSS_PROXIMITY_DAMAGE
	game.player.global_position = boss10.global_position + Vector2(250.0, 0.0)
	var kill_score0: int = game.score
	await _shoot_part_once(boss10, Boss.PART_ARM)
	var kill_delta: int = game.score - kill_score0
	var arm_broke90: bool = boss10.is_part_broken(Boss.PART_ARM)
	var boss_dying90: bool = boss10.phase == Boss.Phase.DYING
	var held_loose90: bool = held != null \
		and held.state == Canister.State.LOOSE
	for i: int in range(300):
		await _frames(1)
		if game.wave == 6:
			break
	_check("lethal close arm hit: break pays, pass-through kills, held canister drops LOOSE, death completes (score +%d = 20 tick + 300 break)"
		% kill_delta,
		held != null and arm_broke90 and boss_dying90 and held_loose90
			and kill_delta == Tuning.BOSS_PROXIMITY_TICK_POINTS
				+ Tuning.BOSS_PART_SCORE
			and game.wave == 6 and game.bosses.is_empty()
			and not game.boss_wave)

	# --- M5: temp powerups ---------------------------------------
	# Drops roll on Main's dedicated drop RNG (pinned where a
	# check needs determinism). Kills drive the real kill_pirate
	# path; collections fly the ship onto the pickup through the
	# real physics loop; effects are measured on the real Player.

	# (91) Random drops: pirate kills drop a pickup at the kill
	# position; the one-on-field cap blocks further random drops
	# until it is collected; after collection, drops roll again.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.reseed_drop_rng(424242)
	game.player.global_position = Vector2(1100.0, 650.0)
	var drop_pos: Vector2 = Vector2(200.0, 200.0)
	var drop_seen: bool = false
	var drop_at: Vector2 = Vector2.ZERO
	var drop_type91: String = ""
	for i: int in range(300):
		var kp: Pirate = game.spawn_pirate("grabber", drop_pos)
		game.kill_pirate(kp, true)
		if game.pickups.size() > 0:
			drop_seen = true
			drop_at = game.pickups[0].global_position
			drop_type91 = game.pickups[0].type_id
			break
	var cap_held91: bool = false
	if drop_seen:
		for i: int in range(60):
			var kp2: Pirate = game.spawn_pirate("grabber", drop_pos)
			game.kill_pirate(kp2, true)
		cap_held91 = game.pickups.size() == 1
		game.player.global_position = game.pickups[0].global_position
		for i: int in range(30):
			await _frames(1)
			if game.pickups.is_empty():
				break
	var collected91: bool = game.pickups.is_empty() \
		and game.player.powerup_id == drop_type91
	var drop_again91: bool = false
	if collected91:
		for i: int in range(300):
			var kp3: Pirate = game.spawn_pirate("grabber", drop_pos)
			game.kill_pirate(kp3, true)
			if game.pickups.size() > 0:
				drop_again91 = true
				break
	_check("pirate kills drop a pickup at the kill point (type %s); the cap holds until collection; drops roll again after"
		% drop_type91,
		drop_seen and drop_at.distance_to(drop_pos) < 1.0
			and PowerupDefs.has_def(drop_type91)
			and cap_held91 and collected91 and drop_again91)

	# (92) Boss death completion ALWAYS drops a powerup at the
	# boss's position — the guarantee is exempt from the cap.
	var boss11: Boss = await _start_boss_wave()
	boss11.park_turrets()
	_clear_hostiles()
	game.spawn_powerup_drop(Vector2(200.0, 620.0), "rapid")
	var cap_before92: int = game.pickups.size()
	boss11.hull_hp = 1
	var boss_pos92: Vector2 = boss11.global_position
	await _shoot_hull(boss11, 1)
	var drops_after92: int = cap_before92
	var drop_near_boss92: bool = false
	for i: int in range(300):
		await _frames(1)
		if game.bosses.is_empty():
			drops_after92 = game.pickups.size()
			for pk: Powerup in game.pickups:
				if pk.global_position.distance_to(boss_pos92) < 60.0:
					drop_near_boss92 = true
			break
	_check("boss death drops a guaranteed powerup even with the field cap satisfied (pickups %d -> %d)"
		% [cap_before92, drops_after92],
		cap_before92 == 1 and drops_after92 == cap_before92 + 1
			and drop_near_boss92)

	# (93) Collection activates the rolled type on the player;
	# the HUD chip shows it, named, with a full timer fraction.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.spawn_powerup_drop(Vector2(400.0, 300.0), "overthrust")
	game.player.global_position = Vector2(400.0, 300.0)
	for i: int in range(30):
		await _frames(1)
		if game.player.powerup_id == "overthrust":
			break
	game._sync_hud()
	_check("pickup collects on overlap: OVERTHRUST active, HUD chip named with a full timer (frac %.2f)"
		% game.hud.powerup_frac,
		game.player.powerup_id == "overthrust"
			and game.pickups.is_empty()
			and game.hud.powerup_id == "overthrust"
			and game.hud.powerup_name == "OVERTHRUST"
			and game.hud.powerup_frac >= 0.95)

	# (94) A second pickup REPLACES the active powerup with a
	# fresh full timer (same run, straight after check 93).
	game.spawn_powerup_drop(game.player.global_position, "shield")
	for i: int in range(30):
		await _frames(1)
		if game.player.powerup_id == "shield":
			break
	_check("collecting SHIELD replaces OVERTHRUST with a fresh full timer (frac %.2f)"
		% game.player.powerup_fraction(),
		game.player.powerup_id == "shield"
			and game.player.powerup_fraction() >= 0.95
			and game.pickups.is_empty())

	# (95) Rapid: the effective interval halves, the fired-signal
	# cadence over a fixed window roughly doubles, and expiry
	# restores the base interval.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(300.0, 400.0)
	var base_interval95: float = game.player.effective_fire_interval()
	_fired_count = 0
	Input.action_press("aim_right")
	await _frames(75) # 1.25s of held twin-stick fire
	Input.action_release("aim_right")
	var base_shots95: int = _fired_count
	_fired_count = 0
	game.player.activate_powerup("rapid")
	var rapid_interval95: float = game.player.effective_fire_interval()
	Input.action_press("aim_right")
	await _frames(75)
	Input.action_release("aim_right")
	var rapid_shots95: int = _fired_count
	game.player.powerup_t = 0.05 # run the timer out
	await _frames(12)
	_check("rapid fire: interval %.3f -> %.3f, cadence %d -> %d shots in 1.25s, expiry restores %.3f"
		% [base_interval95, rapid_interval95, base_shots95,
			rapid_shots95, game.player.effective_fire_interval()],
		base_interval95 == Tuning.PLAYER_FIRE_INTERVAL
			and rapid_interval95 == Tuning.PLAYER_FIRE_INTERVAL \
				* Tuning.POWERUP_RAPID_FIRE_SCALE
			and rapid_shots95 >= base_shots95 + 6
			and game.player.powerup_id == ""
			and game.player.effective_fire_interval()
				== Tuning.PLAYER_FIRE_INTERVAL)
	print("RAPID: base %d shots, rapid %d shots in 75 frames"
		% [base_shots95, rapid_shots95])

	# (96) Spread: ONE fired signal produces exactly 3 Main
	# bullets, at -angle / 0 / +angle from facing.
	game.clear_field()
	_fired_count = 0
	game.player.activate_powerup("spread")
	game.player.fire_cd = 0.0
	Input.action_press("aim_right")
	await _frames(3)
	Input.action_release("aim_right")
	var angles96: Array[float] = []
	for b: Bullet in game.bullets:
		angles96.append(b.velocity.normalized().angle())
	angles96.sort()
	_check("spread fans one fired signal into exactly 3 bullets at -0.15 / 0 / +0.15 rad (fired %d, bullets %d)"
		% [_fired_count, game.bullets.size()],
		_fired_count == 1 and game.bullets.size() == 3
			and absf(angles96[0] + Tuning.POWERUP_SPREAD_ANGLE) < 0.01
			and absf(angles96[1]) < 0.01
			and absf(angles96[2] - Tuning.POWERUP_SPREAD_ANGLE) < 0.01)

	# (97) Overthrust: the speed cap measures 350 x 1.35 = 472.5
	# in real movement; expiry returns the ship to the 350 cap.
	game.player.clear_powerup()
	game.player.activate_powerup("overthrust")
	game.player.global_position = Vector2(200.0, 400.0)
	game.player.velocity = Vector2.ZERO
	var cap97: float = game.player.move_speed_cap()
	Input.action_press("move_right")
	await _frames(60) # 1s: accel 3200 reaches the cap in ~0.15s
	var speed97: float = game.player.speed_now()
	game.player.powerup_t = 0.05 # run the timer out
	await _frames(30) # the drive settles onto the base cap
	var speed_after97: float = game.player.speed_now()
	Input.action_release("move_right")
	_check("overthrust: cap %.1f, measured speed %.1f, settles to %.1f after expiry"
		% [cap97, speed97, speed_after97],
		absf(cap97 - Tuning.PLAYER_SPEED
				* Tuning.POWERUP_OVERTHRUST_SPEED_SCALE) < 0.01
			and absf(speed97 - 472.5) < 2.0
			and game.player.move_speed_cap() == Tuning.PLAYER_SPEED
			and speed_after97 <= Tuning.PLAYER_SPEED + 2.0)

	# (98) Shield absorb, through BOTH kill paths. The lethal
	# bullets are pre-flagged buzzed so the graze payout cannot
	# blur the "no death costs landed" assertions (multiplier
	# and rank pinned at known values, grace held open).
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(300.0, 300.0)
	game.player.invincible_t = 0.0
	game.multiplier = 3.0
	game.mult_grace_t = 99.0
	game.rank = 0.5
	game.player.activate_powerup("shield")
	var eb1: EnemyBullet = game.spawn_enemy_bullet(
		game.player.global_position + Vector2(-30.0, 0.0), Vector2.RIGHT)
	eb1.buzzed = true
	for i: int in range(40):
		await _frames(1)
		if game.player.powerup_id == "":
			break
	var absorbed98: bool = game.player.alive \
		and game.player.powerup_id == "" \
		and game.player.is_invincible() \
		and absf(game.multiplier - 3.0) < 0.001 \
		and absf(game.rank - 0.5) < 0.001
	await _frames(75) # the 1s post-absorb grace runs out for real
	var eb2: EnemyBullet = game.spawn_enemy_bullet(
		game.player.global_position + Vector2(-30.0, 0.0), Vector2.RIGHT)
	eb2.buzzed = true
	for i: int in range(40):
		await _frames(1)
		if not game.player.alive:
			break
	var died98: bool = not game.player.alive \
		and absf(game.multiplier - 1.5) < 0.001
	for i: int in range(200):
		await _frames(1)
		if game.player.alive:
			break
	game.player.invincible_t = 0.0
	game.multiplier = 3.0
	game.mult_grace_t = 99.0
	game.rank = 0.5
	game.player.activate_powerup("shield")
	var toucher98: Pirate = game.spawn_pirate("grabber",
		game.player.global_position + Vector2(8.0, 0.0))
	for i: int in range(240):
		await _frames(1)
		if game.player.powerup_id == "":
			break
	var contact98: bool = game.player.alive \
		and game.player.powerup_id == "" \
		and absf(game.multiplier - 3.0) < 0.001 \
		and absf(game.rank - 0.5) < 0.001
	_check("shield absorbs a lethal bullet and a contact hit with no death costs; the unshielded bullet kills (toucher valid: %s)"
		% str(is_instance_valid(toucher98)),
		absorbed98 and died98 and contact98)

	# (99) Death clears the active powerup; respawn restores none.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.activate_powerup("rapid")
	game.player.invincible_t = 0.0
	game.kill_player()
	var cleared99: bool = not game.player.alive \
		and game.player.powerup_id == ""
	for i: int in range(200):
		await _frames(1)
		if game.player.alive:
			break
	_check("death clears the active powerup and respawn restores none",
		cleared99 and game.player.alive
			and game.player.powerup_id == "")

	# (100) An uncollected pickup despawns at its lifetime, and
	# the drop-type sequence reproduces under a pinned seed.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.spawn_powerup_drop(Vector2(200.0, 200.0), "rapid")
	game.player.global_position = Vector2(1100.0, 650.0)
	for i: int in range(620):
		await _frames(1)
		if game.pickups.is_empty():
			break
	var despawned100: bool = game.pickups.is_empty()
	game.reseed_drop_rng(20261020)
	var seq_a: Array[String] = [game.roll_powerup_type(),
		game.roll_powerup_type(), game.roll_powerup_type()]
	game.reseed_drop_rng(20261020)
	var seq_b: Array[String] = [game.roll_powerup_type(),
		game.roll_powerup_type(), game.roll_powerup_type()]
	_check("uncollected pickup despawns after %.0fs; pinned seed reproduces the type sequence %s"
		% [Tuning.POWERUP_LIFETIME, str(seq_a)],
		despawned100 and seq_a == seq_b)

	# --- M6: the hunter class + GW-hard early pressure -----------
	# The direct-challenge class: it hunts the player, never the
	# canisters, and leads its shots. The retune numbers are read
	# through the Tuning constants and the director's own helpers
	# at the waves the spec names.

	# (101) The def exists as specced, and the director's dealing
	# path keeps waves 1-2 hunter-free while wave 3 deals hunters
	# as a minority share.
	var hdef: Dictionary = EnemyDefs.get_def("hunter")
	_check("hunter def: role hunter, speed 215, score 175, shards 5, radius 13, fire 2.6",
		String(hdef.get("role", "")) == "hunter"
			and float(hdef.get("speed", 0.0)) == 215.0
			and int(hdef.get("score", 0)) == 175
			and int(hdef.get("shards", 0)) == 5
			and float(hdef.get("radius", 0.0)) == 13.0
			and float(hdef.get("fire_interval", 0.0)) == 2.6)
	var dd: SpawnDirector = SpawnDirector.new()
	seed(777001)
	var early_hunters: int = 0
	var early_waves: Array[int] = [1, 2]
	for w: int in early_waves:
		dd.start_wave(w)
		for i: int in range(200):
			if dd.pick_type(0) == "hunter":
				early_hunters += 1
	dd.start_wave(3)
	var deal_counts: Dictionary = {"hunter": 0, "gunner": 0, "grabber": 0}
	for i: int in range(400):
		var dealt_t: String = dd.pick_type(0)
		deal_counts[dealt_t] = int(deal_counts.get(dealt_t, 0)) + 1
	dd.queue_free()
	_check("director deals zero hunters on waves 1-2; wave 3 deals hunters as a minority (%s)"
		% str(deal_counts),
		early_hunters == 0
			and int(deal_counts.get("hunter", 0)) > 0
			and int(deal_counts.get("hunter", 0))
				< int(deal_counts.get("grabber", 0))
			and int(deal_counts.get("hunter", 0)) < 100)

	# (102) The alive cap is a hard gate: drive a wave-3 director
	# stepping manually, non-hunters "dying" the instant they are
	# dealt (so total alive == hunters alive). Hunters accumulate
	# to the cap and the dealing then produces no more of them,
	# however many spawn slots the quota still holds.
	var dcap: SpawnDirector = SpawnDirector.new()
	dcap.spawn_requested.connect(_record_spawn)
	_dealt_types.clear()
	seed(424243)
	dcap.start_wave(3)
	var alive_h102: int = 0
	var max_h102: int = 0
	var dealt_h102: int = 0
	var read102: int = 0
	var steps102: int = 0
	while not dcap.quota_exhausted() and steps102 < 20000:
		dcap.step(1.0 / 60.0, alive_h102, Vector2(640.0, 700.0),
			0.25, alive_h102)
		steps102 += 1
		while read102 < _dealt_types.size():
			if _dealt_types[read102] == "hunter":
				alive_h102 += 1
				dealt_h102 += 1
			read102 += 1
		max_h102 = maxi(max_h102, alive_h102)
	var drained102: bool = dcap.quota_exhausted()
	dcap.queue_free()
	_check("hunter alive cap is a hard gate: driven wave-3 field peaks at %d alive, %d dealt of a %d quota"
		% [max_h102, dealt_h102,
			Tuning.WAVE_BASE_QUOTA + Tuning.WAVE_QUOTA_PER_WAVE * 3],
		drained102 and max_h102 == Tuning.HUNTER_ALIVE_CAP
			and dealt_h102 == Tuning.HUNTER_ALIVE_CAP)

	# (103) A hunter parked beside a loose canister for 5s never
	# latches, drags or holds it: the canister's state and holder
	# never change, and the hunter never enters DRAG.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(1150.0, 120.0)
	game.player.invincible_t = 1000000000.0
	var can103: Canister = game.canisters[0]
	can103.set_loose(Vector2.ZERO)
	can103.global_position = Vector2(300.0, 620.0)
	var hunt103: Pirate = game.spawn_pirate("hunter", Vector2(330.0, 620.0))
	var stole103: bool = false
	for i: int in range(300):
		await _frames(1)
		if not is_instance_valid(hunt103):
			stole103 = true
			break
		if hunt103.phase == Pirate.Phase.DRAG or hunt103.held != null \
				or can103.holder != null \
				or can103.state != Canister.State.LOOSE:
			stole103 = true
			break
	_check("hunter beside a loose canister never latches, drags or holds it (5s watch)",
		not stole103 and is_instance_valid(hunt103)
			and can103.state == Canister.State.LOOSE
			and can103.holder == null)

	# (104) Pursuit: a hunter spawned across the arena from a
	# stationary player closes into the orbit band and holds it —
	# it neither parks on the player nor drifts away.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(300.0, 400.0)
	game.player.invincible_t = 1000000000.0
	var hunt104: Pirate = game.spawn_pirate("hunter", Vector2(1120.0, 130.0))
	var end_dist104: float = -1.0
	var min_late104: float = INF
	var max_late104: float = 0.0
	for i: int in range(600):
		await _frames(1)
		if not is_instance_valid(hunt104):
			break
		if i >= 480:
			var d104: float = hunt104.global_position.distance_to(
				game.player.global_position)
			min_late104 = minf(min_late104, d104)
			max_late104 = maxf(max_late104, d104)
			end_dist104 = d104
	_check("hunter closes across the arena and holds the orbit band (end %.0f, late range %.0f-%.0f)"
		% [end_dist104, min_late104, max_late104],
		end_dist104 >= 110.0 and end_dist104 <= 190.0
			and min_late104 > 60.0 and max_late104 < 230.0)

	# (105) Lead fire: the shot is computed from the player's
	# position AND velocity, recorded off the shooter's own step
	# context at the instant of the fired signal. Nothing fires
	# in the entry telegraph, a charge always precedes the shot,
	# and nothing fires while the player is dead.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.rank = 0.0
	game.player.global_position = Vector2(640.0, 620.0)
	game.player.invincible_t = 1000000000.0
	var hunt105: Pirate = game.spawn_pirate("hunter", Vector2(640.0, 180.0))
	_watch_pirate = hunt105
	_lead_shots.clear()
	hunt105.fired.connect(_record_lead)
	for i: int in range(48): # the 0.8s entry telegraph
		await _frames(1)
	var telegraph_shots105: int = _lead_shots.size()
	Input.action_press("move_right") # steady velocity (350, 0) once at cap
	var saw_charge105: bool = false
	for i: int in range(900):
		await _frames(1)
		if is_instance_valid(hunt105) and hunt105.charge_frac() >= 0.0:
			saw_charge105 = true
		if _lead_shots.size() > 0:
			break
	Input.action_release("move_right")
	var lead_ok105: bool = false
	var lead_err105: float = 0.0
	var nolead_gap105: float = 0.0
	var shot_vel105: float = 0.0
	if _lead_shots.size() > 0:
		var s105: Dictionary = _lead_shots[0] as Dictionary
		var from105: Vector2 = s105["from"] as Vector2
		var dir105: Vector2 = s105["dir"] as Vector2
		var ppos105: Vector2 = s105["ppos"] as Vector2
		var pvel105: Vector2 = s105["pvel"] as Vector2
		shot_vel105 = pvel105.length()
		var tof105: float = from105.distance_to(ppos105) \
			/ Tuning.ENEMY_BULLET_SPEED
		var lead_dir105: Vector2 = (ppos105
			+ pvel105 * tof105 * Tuning.HUNTER_LEAD_FACTOR
			- from105).normalized()
		var nolead_dir105: Vector2 = (ppos105 - from105).normalized()
		lead_err105 = absf(dir105.angle_to(lead_dir105))
		nolead_gap105 = absf(dir105.angle_to(nolead_dir105))
		lead_ok105 = lead_err105 < 0.05 and nolead_gap105 > 0.1
	_check("lead fire: %d shots in the telegraph, a charge precedes the shot, moving shot matches the lead point (err %.3f rad, no-lead gap %.3f, player speed %.0f)"
		% [telegraph_shots105, lead_err105, nolead_gap105, shot_vel105],
		telegraph_shots105 == 0 and saw_charge105
			and _lead_shots.size() > 0 and shot_vel105 > 300.0
			and lead_ok105)
	# Stationary player: the lead point IS the ship — the shot
	# aims at the player itself.
	var mark105: int = _lead_shots.size()
	game.player.global_position = Vector2(350.0, 300.0)
	for i: int in range(600):
		await _frames(1)
		if _lead_shots.size() > mark105:
			break
	var still_ok105: bool = false
	var still_err105: float = 0.0
	var still_vel105: float = -1.0
	if _lead_shots.size() > mark105:
		var s105b: Dictionary = _lead_shots[mark105] as Dictionary
		var from105b: Vector2 = s105b["from"] as Vector2
		var dir105b: Vector2 = s105b["dir"] as Vector2
		var ppos105b: Vector2 = s105b["ppos"] as Vector2
		var pvel105b: Vector2 = s105b["pvel"] as Vector2
		still_vel105 = pvel105b.length()
		still_err105 = absf(dir105b.angle_to(
			(ppos105b - from105b).normalized()))
		still_ok105 = still_vel105 < 20.0 and still_err105 < 0.05
	_check("stationary player: the hunter's shot aims at the ship itself (err %.3f rad, player speed %.0f)"
		% [still_err105, still_vel105], still_ok105)
	# Dead player: the fire cycle halts outright.
	game.player.invincible_t = 0.0
	game.kill_player()
	game.player.respawn_t = 100000.0 # stay down for the watch
	var dead_mark105: int = _lead_shots.size()
	for i: int in range(300):
		await _frames(1)
	_check("no hunter fire while the player is dead (%d shots across a 5s watch)"
		% (_lead_shots.size() - dead_mark105),
		_lead_shots.size() == dead_mark105 and not game.player.alive)
	_watch_pirate = null

	# (106) The retune, read through the Tuning constants and
	# the director's own gates at waves 1, 5 and 10.
	var dq: SpawnDirector = SpawnDirector.new()
	dq.spawn_requested.connect(_record_spawn)
	dq.start_wave(1)
	var quota1: int = dq.quota_left
	dq.start_wave(5)
	var quota5: int = dq.quota_left
	dq.start_wave(10)
	var quota10: int = dq.quota_left
	_check("retune: wave quotas are 9 / 21 / 36 at waves 1 / 5 / 10 (got %d / %d / %d)"
		% [quota1, quota5, quota10],
		quota1 == 9 and quota5 == 21 and quota10 == 36)
	# Alive cap through the step gate: at the cap nothing spawns,
	# one below it a spawn lands. Wave 1 rank 0: cap 4. Wave 10
	# rank 1: min(4 + 9 + 3, 9 + 3) = 12.
	dq.start_wave(1)
	_dealt_types.clear()
	dq.step(1.0, 4, Vector2.ZERO, 0.0, 0)
	var gated_w1: bool = _dealt_types.is_empty()
	dq.step(1.0, 3, Vector2.ZERO, 0.0, 0)
	var spawned_w1: bool = _dealt_types.size() == 1
	dq.start_wave(10)
	_dealt_types.clear()
	dq.step(1.0, 12, Vector2.ZERO, 1.0, 0)
	var gated_w10: bool = _dealt_types.is_empty()
	dq.step(1.0, 11, Vector2.ZERO, 1.0, 0)
	var spawned_w10: bool = _dealt_types.size() == 1
	_check("retune: alive caps gate the director (wave 1 rank 0 cap 4; wave 10 rank 1 cap 12)",
		gated_w1 and spawned_w1 and gated_w10 and spawned_w10)
	_check("retune: spawn interval is 0.85 at rank 0 and x0.55 at rank 1",
		Tuning.SPAWN_INTERVAL == 0.85
			and absf(Tuning.rank_spawn_interval(
				Tuning.SPAWN_INTERVAL, 0.0) - 0.85) < 0.001
			and absf(Tuning.rank_spawn_interval(
				Tuning.SPAWN_INTERVAL, 1.0)
				- 0.85 * Tuning.SPAWN_INTERVAL_MIN_FRAC) < 0.001)
	_check("retune: rank start 0.25; floors 0.15 / 0.29 / 0.465 at waves 1 / 5 / 10, capped 0.6",
		Tuning.RANK_START == 0.25
			and absf(Tuning.rank_floor_for_wave(1) - 0.15) < 0.001
			and absf(Tuning.rank_floor_for_wave(5) - 0.29) < 0.001
			and absf(Tuning.rank_floor_for_wave(10) - 0.465) < 0.001
			and absf(Tuning.rank_floor_for_wave(100) - 0.6) < 0.001)
	dq.start_wave(2)
	var gs2: float = dq.gunner_share()
	dq.start_wave(5)
	var gs5: float = dq.gunner_share()
	dq.start_wave(10)
	var gs10: float = dq.gunner_share()
	var hs10: float = dq.hunter_share()
	var hc10: int = dq.hunter_alive_cap()
	dq.start_wave(3)
	var hs3: float = dq.hunter_share()
	var hc3: int = dq.hunter_alive_cap()
	dq.start_wave(7)
	var hc7: int = dq.hunter_alive_cap()
	dq.queue_free()
	_check("retune: gunner share 0.25 / 0.40 / 0.60 at waves 2 / 5 / 10; hunter share 0.12 (w3), 0.19 (w10); hunter caps 2 (w3), 3 (w7+)",
		absf(gs2 - 0.25) < 0.001 and absf(gs5 - 0.40) < 0.001
			and absf(gs10 - 0.60) < 0.001
			and absf(hs3 - 0.12) < 0.001 and absf(hs10 - 0.19) < 0.001
			and hc3 == 2 and hc7 == 3 and hc10 == 3)

	# (107) Hunter kill flow, through Main's standard paths: a
	# bullet kill pays 175 x multiplier and bursts 5 shards; a
	# ram kill at/above the ram threshold resolves the same way
	# and the player flies on.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.multiplier = 1.0
	game.mult_grace_t = 99.0
	game.player.global_position = Vector2(1100.0, 650.0)
	game.player.invincible_t = 1000000000.0
	var hunt107: Pirate = game.spawn_pirate("hunter", Vector2(400.0, 300.0))
	for i: int in range(120):
		await _frames(1)
		if not is_instance_valid(hunt107) \
				or hunt107.phase != Pirate.Phase.TELEGRAPH:
			break
	var score107: int = game.score
	if is_instance_valid(hunt107):
		game.spawn_bullet(hunt107.global_position, Vector2.RIGHT)
	for i: int in range(30):
		await _frames(1)
		if not is_instance_valid(hunt107):
			break
	_check("hunter bullet kill pays 175 and bursts 5 shards (score +%d, shards %d)"
		% [game.score - score107, game.shards.size()],
		not is_instance_valid(hunt107)
			and game.score - score107 == 175
			and game.shards.size() == 5)
	var hunt107b: Pirate = game.spawn_pirate("hunter", Vector2(700.0, 300.0))
	for i: int in range(120):
		await _frames(1)
		if not is_instance_valid(hunt107b) \
				or hunt107b.phase != Pirate.Phase.TELEGRAPH:
			break
	game.player.invincible_t = 0.0 # contact must be able to resolve
	var rammed107: bool = false
	for i: int in range(90):
		if not is_instance_valid(hunt107b):
			rammed107 = true
			break
		game.player.global_position = hunt107b.global_position \
			+ Vector2(-22.0, 0.0)
		game.player.velocity = Vector2(320.0, 0.0)
		await _frames(1)
		if not is_instance_valid(hunt107b):
			rammed107 = true
			break
	_check("hunter rammed at speed dies through the standard contact path; the player flies on",
		rammed107 and game.player.alive)

	# (108) Wave flow with hunters: a hand-dealt field containing
	# hunters clears and advances once every pirate is dead (no
	# soft-lock), and a lone hunter never enters LEAVE on its
	# own — killing it is its only exit, exactly the gunner's end
	# path (check 37). Shooters have no LEAVE path, so the exit
	# watchdog has nothing to cover for either class.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.start_wave(3) # composition flavour; Main's wave is its own
	game.director.active = false
	game.director.quota_left = 0
	game.spawn_pirate("hunter", Vector2(200.0, 200.0))
	game.spawn_pirate("hunter", Vector2(1080.0, 200.0))
	game.spawn_pirate("grabber", Vector2(640.0, 120.0))
	game.player.global_position = Vector2(640.0, 700.0)
	game.player.invincible_t = 1000000000.0
	var field108: Array[Pirate] = game.pirates.duplicate()
	for p: Pirate in field108:
		game.kill_pirate(p, false)
	await _frames(10)
	_check("a wave containing hunters clears and advances once every pirate is killed (wave %d)"
		% game.wave,
		game.wave == 2 and game.pirates.is_empty())
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(640.0, 700.0)
	game.player.invincible_t = 1000000000.0
	var hunt108: Pirate = game.spawn_pirate("hunter", Vector2(640.0, 150.0))
	var left108: bool = false
	for i: int in range(360):
		await _frames(1)
		if not is_instance_valid(hunt108) \
				or hunt108.phase == Pirate.Phase.LEAVE:
			left108 = true
			break
	_check("a lone hunter never enters LEAVE on its own — it holds its hunt until killed",
		not left108 and is_instance_valid(hunt108)
			and hunt108.phase != Pirate.Phase.LEAVE)

	# --- Danmaku split: body, hotspot, buzz geometry -------------
	# The hull grew (body 13 -> 17: contact, clamp, muzzle) while
	# enemy bullets judge a 5px hotspot, so the kill distance fell
	# 17 -> 9. The bullet graze ring tightened 46 -> 30; the
	# drag-pass window is contact-relative now (contact + 16,
	# outer edge 46 for a standard pirate — where it always was).
	var bullet_step: float = Tuning.ENEMY_BULLET_SPEED / 60.0

	# (118) The hotspot kill ring: a bullet passing 12px abeam —
	# inside the OLD 17px kill distance, outside the new 9px —
	# cannot kill; it grazes and pays buzz. A bullet arriving at
	# 8px kills through the real bullet path.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.invincible_t = 0.0
	game.player.clear_powerup()
	game.multiplier = 1.0
	var score118: int = game.score
	var eb118a: EnemyBullet = game.spawn_enemy_bullet(
		Vector2(652.0, 400.0), Vector2.DOWN)
	await _frames(10)
	var graze118: bool = game.player.alive and eb118a.buzzed \
		and game.score > score118
	game.spawn_enemy_bullet(
		game.player.global_position + Vector2(8.0 + bullet_step, 0.0),
		Vector2.LEFT)
	for i: int in range(10):
		await _frames(1)
		if not game.player.alive:
			break
	_check("hotspot ring: a 12px pass grazes (buzz paid, ship alive); an 8px arrival kills (graze %s, alive %s)"
		% [str(graze118), str(game.player.alive)],
		graze118 and not game.player.alive)

	# (119) The graze boundary: a bullet whose first step ends
	# just inside the 30px ring pays buzz exactly once; one
	# ending just outside pays nothing at all. (Spawns sit one
	# step short of the measured arrival — the ring is sampled
	# after each step, so arrival distance is what counts.)
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.invincible_t = 99.0 # the boundary pays or not; nobody dies
	game.multiplier = 1.0
	game.mult_grace_t = 99.0
	var score119: int = game.score
	var eb119a: EnemyBullet = game.spawn_enemy_bullet(
		game.player.global_position + Vector2(29.9 - bullet_step, 0.0),
		Vector2.RIGHT)
	for i: int in range(10):
		await _frames(1)
		if eb119a.buzzed:
			break
	var paid119: bool = eb119a.buzzed \
		and game.score == score119 + Tuning.BUZZ_POINTS
	game.enemy_bullets.erase(eb119a)
	eb119a.queue_free()
	var score119b: int = game.score
	var mult119b: float = game.multiplier
	var eb119b: EnemyBullet = game.spawn_enemy_bullet(
		game.player.global_position + Vector2(30.1 - bullet_step, 0.0),
		Vector2.RIGHT)
	await _frames(10)
	_check("graze boundary: a 29.9px arrival pays %d once; a 30.1px arrival pays nothing (paid %s, outside buzzed %s)"
		% [Tuning.BUZZ_POINTS, str(paid119), str(eb119b.buzzed)],
		paid119 and not eb119b.buzzed
			and game.score == score119b
			and absf(game.multiplier - mult119b) < 0.001)

	# (120) Contact judges the BODY (17 + pirate 13 = 30). The
	# pirate is re-pinned each frame at the test distance and
	# steps straight along the pin axis toward its one available
	# target — away from the ship in the far case, toward it in
	# the near case — so the sampled distance stays on its own
	# side of the line: held at 32 nothing ever resolves; held
	# at 29 the contact lands and the parked ship dies.
	game.start_run()
	game.director.active = false
	game.clear_field()
	for c: Canister in game.canisters:
		c.state = Canister.State.TOWED # unavailable as targets...
	var loose120: Canister = game.canisters[0]
	loose120.state = Canister.State.LOOSE # ...but one, far right
	loose120.global_position = Vector2(900.0, 400.0)
	game.player.global_position = Vector2(400.0, 400.0)
	game.player.invincible_t = 0.0
	var far120: Pirate = game.spawn_pirate("grabber",
		Vector2(432.0, 400.0))
	for i: int in range(150):
		if is_instance_valid(far120):
			far120.global_position = game.player.global_position \
				+ Vector2(32.0, 0.0)
		await _frames(1)
	_check("contact body: a pirate held 32px off never touches the ship (alive %s)"
		% str(game.player.alive),
		game.player.alive and is_instance_valid(far120))
	game.start_run()
	game.director.active = false
	game.clear_field()
	for c: Canister in game.canisters:
		c.state = Canister.State.TOWED
	var loose120b: Canister = game.canisters[0]
	loose120b.state = Canister.State.LOOSE # the one target, far left
	loose120b.global_position = Vector2(300.0, 400.0)
	game.player.global_position = Vector2(400.0, 400.0)
	game.player.invincible_t = 0.0
	var near120: Pirate = game.spawn_pirate("grabber",
		Vector2(429.0, 400.0))
	var died120: bool = false
	for i: int in range(150):
		if is_instance_valid(near120):
			near120.global_position = game.player.global_position \
				+ Vector2(29.0, 0.0)
		await _frames(1)
		if not game.player.alive:
			died120 = true
			break
	_check("contact body: a pirate held 29px off resolves contact and the parked ship dies",
		died120)

	# (121) The drag-pass window, contact-relative: (30, 46] for
	# a standard pirate. Riding 38px abeam of a pirate mid-drag
	# pays the pass buzz; riding at 50px pays nothing.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.invincible_t = 1000000000.0 # geometry must not kill
	var slot121: Vector2 = Tuning.slot_position(0)
	var dragger121: Pirate = game.spawn_pirate("grabber",
		slot121 + Vector2(120.0, 0.0))
	for i: int in range(300):
		await _frames(1)
		if dragger121.held != null:
			break
	game.multiplier = 1.0
	game.mult_grace_t = 99.0
	var score121: int = game.score
	for i: int in range(120):
		game.player.global_position = dragger121.global_position \
			+ Vector2(38.0, 0.0)
		await _frames(1)
		if dragger121.buzzed_this_drag:
			break
	_check("drag-pass window: riding 38px abeam of a dragging pirate pays the pass buzz (score +%d)"
		% (game.score - score121),
		dragger121.buzzed_this_drag and game.score > score121)
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.invincible_t = 1000000000.0
	var dragger121b: Pirate = game.spawn_pirate("grabber",
		slot121 + Vector2(120.0, 0.0))
	for i: int in range(300):
		await _frames(1)
		if dragger121b.held != null:
			break
	var saw_drag121b: bool = dragger121b.phase == Pirate.Phase.DRAG
	for i: int in range(90):
		game.player.global_position = dragger121b.global_position \
			+ Vector2(50.0, 0.0)
		await _frames(1)
	_check("drag-pass window: riding 50px abeam pays nothing (was dragging %s, buzzed %s)"
		% [str(saw_drag121b), str(dragger121b.buzzed_this_drag)],
		saw_drag121b and not dragger121b.buzzed_this_drag)

	# (122) Boss bullets judge the hotspot too: they fly the
	# same EnemyBullet path (tinted), so a 12px pass off the
	# ship grazes and an 8px arrival kills.
	var boss122: Boss = await _start_boss_wave()
	boss122.park_turrets()
	_clear_hostiles()
	game.player.global_position = Vector2(640.0, 320.0)
	game.player.invincible_t = 0.0
	game.player.clear_powerup()
	var eb122a: EnemyBullet = game.spawn_enemy_bullet_tinted(
		Vector2(652.0, 320.0), Vector2.DOWN,
		Tuning.COLOR_BOSS_BULLET_CORE, Tuning.COLOR_BOSS_BULLET_RIM)
	await _frames(10)
	var graze122: bool = game.player.alive and eb122a.buzzed
	game.spawn_enemy_bullet_tinted(
		game.player.global_position + Vector2(8.0 + bullet_step, 0.0),
		Vector2.LEFT,
		Tuning.COLOR_BOSS_BULLET_CORE, Tuning.COLOR_BOSS_BULLET_RIM)
	for i: int in range(10):
		await _frames(1)
		if not game.player.alive:
			break
	_check("boss bullets judge the hotspot: a 12px pass grazes, an 8px arrival kills (graze %s, alive %s)"
		% [str(graze122), str(game.player.alive)],
		graze122 and not game.player.alive)

	# (123) The constants gate: the split's numbers and the
	# kill distance they produce.
	_check("danmaku constants: body 17, hotspot 5, graze ring 30, pass margin 16, kill distance 9",
		Tuning.PLAYER_RADIUS == 17.0
			and Tuning.PLAYER_HOTSPOT_RADIUS == 5.0
			and Tuning.BUZZ_RADIUS == 30.0
			and Tuning.BUZZ_PASS_MARGIN == 16.0
			and Tuning.ENEMY_BULLET_RADIUS
				+ Tuning.PLAYER_HOTSPOT_RADIUS == 9.0)

	# --- M7: conversion, with the transformer reshape --------------
	# A gunner whose getters are gone rebuilds itself into a
	# thief. Staging controls the trigger state precisely (quota
	# live vs spent, a thief having existed or not); kills go
	# through Main's real paths; the reshape's timeline, colour
	# and role flip are read off the pirate itself.

	# (126) Dead-air trigger: a thief worked this wave, then only
	# a gunner remains (quota NOT exhausted). After the dead-air
	# window the gunner starts reshaping — and it is the only one.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var g126: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	await _frames(70) # the gunner is at its post (HOLD)
	var t126: Pirate = game.spawn_pirate("grabber",
		Tuning.slot_position(2) + Vector2(150.0, 0.0))
	await _frames(10) # a working thief exists; the wave flag sets
	game.kill_pirate(t126, false)
	var frames126: int = -1
	for i: int in range(280):
		await _frames(1)
		if g126.is_converting():
			frames126 = i + 1
			break
	var converting126: int = 0
	for p: Pirate in game.pirates:
		if p.is_converting():
			converting126 += 1
	_check("dead-air trigger: conversion starts %d frames after the last thief died (window 130-190, dead air 150); exactly one pirate converts"
		% frames126,
		frames126 >= 130 and frames126 <= 190 and converting126 == 1)

	# (127) Quota-spent trigger: no thief has EVER existed this
	# wave, but the quota is spent and a gunner holds the field —
	# it converts promptly (the quota delay plus its entry
	# telegraph), which neither dead air (no thief ever) nor the
	# 8s backstop can explain.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0 # the quota is spent from the outset
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var g127: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(-300.0, 0.0))
	var start127: int = -1
	for i: int in range(200):
		await _frames(1)
		if g127.is_converting():
			start127 = i + 1
			break
	_check("quota-spent trigger: a getter-free wave converts its gunner promptly (frame %d, window 41-160) with no thief ever on the field"
		% start127,
		start127 >= 41 and start127 <= 160
			and not game._wave_had_thief)

	# (128) Timeline integrity: a reshaping pirate parked beside a
	# slotted canister fires ZERO shots and cannot latch; halfway
	# through it is still a shooter, mid-cross-fade; at the end
	# it is a thief wearing the grabber colour EXACTLY, and the
	# stage signals arrived 1, 2, 3 in order.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var can128: Canister = game.canisters[0]
	var g128: Pirate = game.spawn_pirate("gunner",
		can128.global_position + Vector2(45.0, 0.0))
	_conv_shots = 0
	_conv_stages.clear()
	g128.fired.connect(_count_conv_shot)
	g128.convert_stage.connect(_record_conv_stage)
	for i: int in range(200):
		await _frames(1)
		if g128.is_converting():
			break
	var started128: bool = g128.is_converting()
	var shots_at_start128: int = _conv_shots
	var latched128: bool = false
	var role_mid128: String = ""
	var color_mid128: Color = Color.BLACK
	var frames128: int = 0
	while g128.is_converting() and frames128 < 200:
		await _frames(1)
		frames128 += 1
		if g128.held != null or can128.state == Canister.State.DRAGGING:
			latched128 = true
		if frames128 == 27: # ~halfway through the 0.9s reshape
			role_mid128 = g128.current_role()
			color_mid128 = g128.draw_color
	var gunner_def128: Dictionary = EnemyDefs.get_def("gunner")
	var gunner_col128: Color = gunner_def128["color"] as Color
	var grabber_def128: Dictionary = EnemyDefs.get_def("grabber")
	var grabber_col128: Color = grabber_def128["color"] as Color
	_check("conversion timeline: no shots, no latch mid-reshape; shooter at halfway, mid-fade; thief in exact grabber coral at the end; stages 1-2-3 in order (stages %s)"
		% str(_conv_stages),
		started128 and not latched128
			and _conv_shots == shots_at_start128
			and role_mid128 == "shooter"
			and color_mid128 != gunner_col128
			and color_mid128 != grabber_col128
			and g128.current_role() == "thief"
			and g128.draw_color == grabber_col128
			and _conv_stages.size() == 3
			and _conv_stages[0] == 1 and _conv_stages[1] == 2
			and _conv_stages[2] == 3)

	# (129) A convert completes a steal (the Rip-Off 2 orbit-
	# stall guard): from a mid-field conversion it must latch a
	# canister and reach DRAG inside a bounded time, then haul
	# it out and leave by the normal path.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var g129: Pirate = game.spawn_pirate("gunner", Vector2(1100.0, 150.0))
	for i: int in range(200):
		await _frames(1)
		if g129.is_converting():
			break
	for i: int in range(200):
		await _frames(1)
		if not g129.is_converting():
			break
	var converted129: bool = g129.current_role() == "thief"
	var drag_frames129: int = -1
	var held129: Canister = null
	for i: int in range(480): # 8s bound from conversion completion
		await _frames(1)
		if not is_instance_valid(g129):
			break
		if g129.phase == Pirate.Phase.DRAG:
			drag_frames129 = i + 1
			held129 = g129.held
			break
	var exited129: bool = false
	if held129 != null:
		for i: int in range(900):
			await _frames(1)
			if not is_instance_valid(g129) or not game.pirates.has(g129):
				exited129 = held129.state == Canister.State.GONE
				break
	_check("convert completes a steal: DRAG reached %d frames after the reshape (bound 480), canister hauled out GONE and the convert leaves"
		% drag_frames129,
		converted129 and drag_frames129 > 0 and exited129)

	# (130) Death mid-conversion: a bullet kills the reshaping
	# gunner — it pays as a GUNNER (150 x multiplier), bursts its
	# 4 gunner shards, and never flips posthumously.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	game.multiplier = 2.0
	game.mult_grace_t = 99.0 # pin the multiplier (checks 98/119 precedent)
	# A hunter bystander keeps the field non-empty through the
	# post-kill wait: with the quota spent, an emptied field
	# would legitimately advance the wave and deal fresh pirates
	# (grabbers among them) into the post assertions. A hunter
	# never converts and is never a thief, so it changes nothing
	# else the check measures.
	game.spawn_pirate("hunter", Vector2(200.0, 150.0))
	var g130: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	for i: int in range(200):
		await _frames(1)
		if g130.is_converting():
			break
	await _frames(15) # ~0.25s in: mid-reshape
	var mid130: bool = g130.is_converting()
	var score130: int = game.score
	var shards130: int = game.shards.size()
	game.spawn_bullet(g130.global_position + Vector2(-30.0, 0.0),
		Vector2.RIGHT)
	for i: int in range(30):
		await _frames(1)
		if not is_instance_valid(g130):
			break
	var paid130: int = game.score - score130
	var burst130: int = game.shards.size() - shards130
	await _frames(150) # well past what completion would have been
	var any_converting130: bool = false
	var any_thief130: bool = false
	for p: Pirate in game.pirates:
		if p.is_converting():
			any_converting130 = true
		if p.current_role() == "thief":
			any_thief130 = true
	_check("death mid-conversion pays the gunner (score +%d = 150 x 2.0, shards +%d = 4) and nothing ever flips"
		% [paid130, burst130],
		mid130 and not is_instance_valid(g130)
			and paid130 == 300 and burst130 == 4
			and not any_converting130 and not any_thief130)

	# (131) Hunters NEVER convert: a hunter-only field held past
	# both the dead-air window and the no-steal backstop, with
	# the quota spent (every trigger armed), produces nothing.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0
	game.player.global_position = Vector2(640.0, 700.0)
	game.player.invincible_t = 1000000000.0
	var h131: Pirate = game.spawn_pirate("hunter", Vector2(640.0, 150.0))
	var saw_convert131: bool = false
	for i: int in range(660): # 11s: past dead air (2.5s) and backstop (8s)
		await _frames(1)
		if not is_instance_valid(h131) or h131.is_converting():
			saw_convert131 = true
			break
	_check("hunters never convert: 11s alone with every trigger armed, still hunting (convert seen %s)"
		% str(saw_convert131),
		not saw_convert131 and is_instance_valid(h131)
			and h131.current_role() == "hunter")

	# (132) One at a time, oldest first: with two gunners and the
	# wave's thief killed, the OLDEST gunner converts; while the
	# convert works as a thief the second gunner stays a shooter.
	game.start_run()
	game.director.active = false
	game.clear_field() # quota stays live: dead air is the trigger here
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var a132: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 60.0))
	await _frames(70) # A is operational, and strictly the oldest
	var b132: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(-300.0, -60.0))
	var t132: Pirate = game.spawn_pirate("grabber",
		Tuning.slot_position(5) + Vector2(-150.0, 0.0))
	await _frames(10) # the thief registers; the wave flag sets
	game.kill_pirate(t132, false)
	var a_started132: bool = false
	var b_started_early132: bool = false
	for i: int in range(280):
		await _frames(1)
		if b132.is_converting():
			b_started_early132 = true
		if a132.is_converting():
			a_started132 = true
			break
	var watched132: int = 0
	var b_converted132: bool = false
	for i: int in range(420):
		await _frames(1)
		if not is_instance_valid(a132) or not game.pirates.has(a132):
			break
		if a132.current_role() == "thief" and (
				a132.phase == Pirate.Phase.SEEK
				or a132.phase == Pirate.Phase.DRAG):
			watched132 += 1
			if b132.is_converting() or b132.current_role() != "shooter":
				b_converted132 = true
				break
	_check("one at a time: the oldest gunner converts first; the second stays a shooter across %d frames of the convert working as a thief"
		% watched132,
		a_started132 and not b_started_early132
			and not b_converted132 and watched132 >= 120)

	# (133) Mop-up ending: quota spent, the last grabber killed,
	# one gunner left. It converts, steals a canister, exits —
	# and the wave ADVANCES. No soft-lock.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.director.quota_left = 0
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var t133: Pirate = game.spawn_pirate("grabber",
		Tuning.slot_position(3) + Vector2(130.0, 0.0))
	var g133: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	await _frames(70) # both operational; the grabber is en route or dragging
	var killed133: bool = false
	for i: int in range(60):
		if not is_instance_valid(t133):
			killed133 = true
			break
		game.spawn_bullet(t133.global_position + Vector2(-30.0, 0.0),
			Vector2.RIGHT)
		await _frames(1)
	killed133 = killed133 or not is_instance_valid(t133)
	var wave133: int = game.wave
	var advanced133: bool = false
	for i: int in range(1800):
		await _frames(1)
		if game.wave > wave133:
			advanced133 = true
			break
	_check("mop-up ending: the last gunner converts, steals, exits and wave %d advances to %d (no soft-lock)"
		% [wave133, game.wave],
		killed133 and advanced133 and game.wave == wave133 + 1)

	# (134) Backstop: a thief is alive and SEEKING (a working
	# thief — dead air cannot accumulate, and the quota is live,
	# so the quota trigger is inert too), yet a gunner converts
	# when the no-steal clock runs out: the thief out failing to
	# latch is exactly what the backstop exists for. TEST-ONLY
	# LEVER (disclosed): the clock is aged directly, the same
	# direct-write precedent as boss.hull_hp — the trigger, the
	# gate and the conversion itself all run the real code.
	game.start_run()
	game.director.active = false
	game.clear_field() # quota live (9): the quota trigger stays inert
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var t134: Pirate = game.spawn_pirate("grabber", Vector2(150.0, 150.0))
	var g134: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	await _frames(70) # both operational; the grabber is mid-SEEK, far from any slot
	var control134: bool = not g134.is_converting() \
		and t134.phase == Pirate.Phase.SEEK
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
	var fired134: bool = false
	for i: int in range(30):
		await _frames(1)
		if g134.is_converting():
			fired134 = true
			break
	_check("backstop: with a live SEEK thief and a live quota, aging the no-steal clock to %.0fs converts the gunner anyway"
		% Tuning.CONVERT_NO_STEAL_BACKSTOP,
		control134 and fired134 and is_instance_valid(t134)
			and t134.current_role() == "thief")

	print("HARNESS: %d/%d checks passed" % [_passed, _passed + _failed])
	get_tree().quit(0 if _failed == 0 else 1)
