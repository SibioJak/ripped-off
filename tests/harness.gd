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


## Run-length helper: the longest run of one value in a dealt
## sequence (the anti-clump checks read it).
func _max_run(seq: Array[String]) -> int:
	var best: int = 0
	var cur: int = 0
	var prev: String = ""
	for card: String in seq:
		if card == prev:
			cur += 1
		else:
			prev = card
			cur = 1
		best = maxi(best, cur)
	return best


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


## Drag-governor helper: the lane count the pirate gate reads —
## canisters DRAGGING whose holder is a Pirate.
func _drag_count_h() -> int:
	var n: int = 0
	for c: Canister in game.canisters:
		if c.state == Canister.State.DRAGGING and c.holder is Pirate:
			n += 1
	return n


## Contested-tow helper: fresh run, canister 0 set loose at `at`
## (every staging point used below sits far outside its berth's
## snap radius), the player parked on it, invincible, until the
## tow latches. Returns the towed canister, or null.
func _stage_tow(at: Vector2) -> Canister:
	game.start_run()
	game.director.active = false
	game.clear_field()
	var can: Canister = game.canisters[0]
	can.set_loose(Vector2.ZERO)
	can.global_position = at
	game.player.global_position = at + Vector2(20.0, 0.0)
	game.player.invincible_t = 1000000000.0
	for i: int in range(60):
		await _frames(1)
		if game.player.towed == can:
			break
	return can if game.player.towed == can else null


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

	# (15) REWORKED (restructure): the wave-2 quota mix died with
	# the waves. What survives: the early-run composition. At
	# t=60 the composition has exactly two unlocked classes —
	# grabber and gunner — and 600 seed-pinned deals through the
	# director's own sampler deal both, and nothing else.
	game.start_run()
	game.director.active = false
	game.clear_field()
	seed(20261018)
	var saw15: Dictionary = {}
	for i15: int in range(600):
		var dealt15: String = game.director.pick_next_type(60.0, {})
		saw15[dealt15] = true
	_check("early composition deals grabber and gunner only, gunner present",
		saw15.has("grabber") and saw15.has("gunner")
			and saw15.size() == 2)

	# (16) The gunner's shot follows its charge telegraph; nothing
	# fires during the entry telegraph or mid-charge.
	# M7 staging note: a FRESH run starts this check. Check (15)
	# leaves sampled deals behind with a thief having existed —
	# and a lone gunner parked here for seconds could
	# legitimately convert mid-check (dead air / backstop) and
	# stop firing. The fresh run resets the per-run conversion
	# state; the assertions below are untouched.
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

	# (20) REWORKED (restructure): no quota drains any more. What
	# survives: rank makes the director hungrier. Two standalone
	# directors at the same elapsed (t=480, the plateau) run the
	# same simulated window — the high-rank one deals measurably
	# more — and the alive gate is a hard cap: at the cap, no
	# deal happens however long the director runs.
	var d_low: SpawnDirector = SpawnDirector.new()
	var d_high: SpawnDirector = SpawnDirector.new()
	d_low.spawn_requested.connect(_record_spawn)
	d_high.spawn_requested.connect(_record_spawn)
	d_low.start_run()
	_dealt_types.clear()
	for i20a: int in range(480):
		d_low.step(0.25, 0, Vector2.ZERO, 0.0, {}, 480.0)
	var dealt_low20: int = _dealt_types.size()
	d_high.start_run()
	_dealt_types.clear()
	for i20b: int in range(480):
		d_high.step(0.25, 0, Vector2.ZERO, 1.0, {}, 480.0)
	var dealt_high20: int = _dealt_types.size()
	_check("high rank deals measurably more spawns in the same window",
		dealt_high20 > dealt_low20 + 20)
	_dealt_types.clear()
	var cap480: int = Tuning.alive_cap_at(480.0) \
		+ Tuning.rank_alive_bonus(0.0)
	for i20c: int in range(240):
		d_low.step(0.25, cap480, Vector2.ZERO, 0.0, {}, 480.0)
	_check("the alive cap is a hard gate on dealing",
		_dealt_types.is_empty())
	d_low.queue_free()
	d_high.queue_free()

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

	# (141) M9 soundtrack re-voice freeze: the re-render changed
	# voices only — every music stem keeps its M3 name, beat count
	# and exact sample count, and the shared grid constants hold.
	var expected_music: Dictionary = {
		"kick": [16, 315936], "hats": [16, 315936],
		"perc": [10, 197460], "drive": [16, 315936],
		"bass_a": [16, 315936], "bass_b": [16, 315936],
		"bass_c": [16, 315936], "arp_a": [12, 236952],
		"arp_b": [12, 236952], "arp_c": [12, 236952],
		"pad": [32, 631872], "title": [16, 315936],
	}
	var structure_ok: bool = int(manifest.get("bpm", 0)) == 134 \
		and int(manifest.get("samples_per_beat", 0)) == 19746 \
		and music_entries.size() == expected_music.size()
	if structure_ok:
		var ekeys: Array = expected_music.keys()
		for key2: Variant in ekeys:
			var kname: String = String(key2)
			if not music_entries.has(kname):
				structure_ok = false
				break
			var mentry: Dictionary = music_entries[kname] as Dictionary
			var espec: Array = expected_music[key2] as Array
			if int(mentry["beats"]) != int(espec[0]) \
					or int(mentry["samples"]) != int(espec[1]):
				structure_ok = false
				break
	_check("manifest structure frozen at M3 values (bpm 134, spb 19746, stem beats/samples)",
		structure_ok)

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
	# REWORKED (restructure): no deck, no waves. What survives is
	# the hunter's place in the mix: nothing before the 75s
	# unlock, a minority share once unlocked — sampled through
	# the director's own pick at staged run times, seed pinned.
	var dd: SpawnDirector = SpawnDirector.new()
	seed(777001)
	var early_hunters: int = 0
	for i101a: int in range(400):
		if dd.pick_next_type(60.0, {}) == "hunter":
			early_hunters += 1
	var deal_counts: Dictionary = {}
	for i101b: int in range(600):
		var dealt101: String = dd.pick_next_type(100.0, {})
		deal_counts[dealt101] = int(deal_counts.get(dealt101, 0)) + 1
	dd.queue_free()
	_check("director deals zero hunters before the 75s unlock; at t=100 hunters are dealt as a minority (%s)"
		% str(deal_counts),
		early_hunters == 0
			and int(deal_counts.get("hunter", 0)) > 0
			and int(deal_counts.get("hunter", 0))
				< int(deal_counts.get("grabber", 0)))

	# (102) REWORKED (restructure): the hunter alive cap as a
	# class gate in the endless stream. Drive a director at
	# t=100 (hunters unlocked, cap 2): dealt non-hunters count
	# as instantly dead, hunters accumulate — they reach exactly
	# the cap, no more are dealt, and the other classes keep
	# flowing past the full cap.
	var dcap: SpawnDirector = SpawnDirector.new()
	dcap.spawn_requested.connect(_record_spawn)
	_dealt_types.clear()
	seed(424243)
	dcap.start_run()
	var alive_h102: int = 0
	var max_h102: int = 0
	var dealt_h102: int = 0
	var dealt_other102: int = 0
	var read102: int = 0
	var steps102: int = 0
	while steps102 < 20000:
		dcap.step(1.0 / 60.0, alive_h102, Vector2(640.0, 700.0),
			0.25, {"hunter": alive_h102}, 100.0)
		steps102 += 1
		while read102 < _dealt_types.size():
			if _dealt_types[read102] == "hunter":
				alive_h102 += 1
				dealt_h102 += 1
			else:
				dealt_other102 += 1
			read102 += 1
		max_h102 = maxi(max_h102, alive_h102)
		if dealt_h102 >= Tuning.hunter_alive_cap_at(100.0) \
				and dealt_other102 > 100:
			break
	dcap.queue_free()
	_check("hunter alive cap is a hard gate at t=100: field peaks at %d alive, %d dealt, %d other deals flow past the full cap"
		% [max_h102, dealt_h102, dealt_other102],
		max_h102 == Tuning.hunter_alive_cap_at(100.0)
			and dealt_h102 == Tuning.hunter_alive_cap_at(100.0)
			and dealt_other102 > 100)

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
	# M8 staging note: the seed is pinned across the spawn. The
	# first-shot geometry this check samples depends on the
	# hunter's spawn draws (first-shot delay, strafe side), which
	# read the global RNG stream — so the no-lead margin used to
	# ride on however much stream earlier checks happened to
	# consume (it read 0.185-0.187 through M7, then 0.085 once
	# M8's deck build changed the draw count, with the lead error
	# itself still 0.000). The pin makes the sampled geometry
	# the intended one every run; the assertions are untouched.
	seed(777)
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

	# (106) REWORKED (restructure): the retune lives in the
	# continuous curves now — read through the Tuning helpers
	# and the director's own step gate at staged run times.
	var dq: SpawnDirector = SpawnDirector.new()
	dq.spawn_requested.connect(_record_spawn)
	dq.start_run()
	# Alive gate: at the cap nothing spawns, one below it a
	# spawn lands. t=0 rank 0: cap 5. t=480 rank 1: 12 + 3 = 15.
	# (The below-cap probes step 2.0s: a dealt interval can run
	# to ~1.19s at t=0 with flow and jitter at their maxima,
	# and one step deals at most once regardless of its size.)
	_dealt_types.clear()
	dq.step(1.0, Tuning.alive_cap_at(0.0), Vector2.ZERO, 0.0, {}, 0.0)
	var gated_t0: bool = _dealt_types.is_empty()
	dq.step(2.0, Tuning.alive_cap_at(0.0) - 1, Vector2.ZERO, 0.0, {}, 0.0)
	var spawned_t0: bool = _dealt_types.size() == 1
	var cap_end106: int = Tuning.alive_cap_at(480.0) \
		+ Tuning.rank_alive_bonus(1.0)
	_dealt_types.clear()
	dq.step(1.0, cap_end106, Vector2.ZERO, 1.0, {}, 480.0)
	var gated_t480: bool = _dealt_types.is_empty()
	dq.step(2.0, cap_end106 - 1, Vector2.ZERO, 1.0, {}, 480.0)
	var spawned_t480: bool = _dealt_types.size() == 1
	dq.queue_free()
	_check("retune: alive caps gate the director (t=0 rank 0 cap %d; t=480 rank 1 cap %d)"
		% [Tuning.alive_cap_at(0.0), cap_end106],
		gated_t0 and spawned_t0 and gated_t480 and spawned_t480)
	_check("retune: spawn interval base 1.05s at t=0 tightening to 0.48s at t=480 and held; rank scales it x0.55 at rank 1",
		absf(Tuning.spawn_interval_at(0.0) - 1.05) < 0.001
			and absf(Tuning.spawn_interval_at(480.0) - 0.48) < 0.001
			and absf(Tuning.spawn_interval_at(9999.0) - 0.48) < 0.001
			and absf(Tuning.rank_spawn_interval(
				Tuning.spawn_interval_at(0.0), 1.0)
				- 1.05 * Tuning.SPAWN_INTERVAL_MIN_FRAC) < 0.001)
	_check("retune: rank start 0.25; run-time floors 0.20 / 0.375 / 0.55 at t=0 / 300 / 600, held after",
		Tuning.RANK_START == 0.25
			and absf(Tuning.rank_floor_at(0.0) - 0.20) < 0.001
			and absf(Tuning.rank_floor_at(300.0) - 0.375) < 0.001
			and absf(Tuning.rank_floor_at(600.0) - 0.55) < 0.001
			and absf(Tuning.rank_floor_at(9999.0) - 0.55) < 0.001)
	_check("retune: composition plateaus at t=400 — gunner 0.28, hunter 0.14, darter 0.10, sniper 0.10, grabber 0.38",
		absf(float(Tuning.composition_at(400.0).get("gunner", 0.0)) - 0.28) < 0.001
			and absf(float(Tuning.composition_at(400.0).get("hunter", 0.0)) - 0.14) < 0.001
			and absf(float(Tuning.composition_at(400.0).get("darter", 0.0)) - 0.10) < 0.001
			and absf(float(Tuning.composition_at(400.0).get("sniper", 0.0)) - 0.10) < 0.001
			and absf(float(Tuning.composition_at(400.0).get("grabber", 0.0)) - 0.38) < 0.001)

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

	# (108) REWORKED (restructure): a hand-dealt field containing
	# hunters clears once every pirate is dead and the run simply
	# continues (no wave to advance, no soft-lock), and a lone
	# hunter never enters LEAVE on its
	# own — killing it is its only exit, exactly the gunner's end
	# path (check 37). Shooters have no LEAVE path, so the exit
	# watchdog has nothing to cover for either class.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.spawn_pirate("hunter", Vector2(200.0, 200.0))
	game.spawn_pirate("hunter", Vector2(1080.0, 200.0))
	game.spawn_pirate("grabber", Vector2(640.0, 120.0))
	game.player.global_position = Vector2(640.0, 700.0)
	game.player.invincible_t = 1000000000.0
	var field108: Array[Pirate] = game.pirates.duplicate()
	for p: Pirate in field108:
		game.kill_pirate(p, false)
	await _frames(10)
	_check("a field containing hunters clears once every pirate is killed; the run continues",
		game.state == Main.GameState.RUNNING and game.pirates.is_empty())
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
	# thief. Staging controls the trigger state precisely (a
	# thief having existed this run or not; the no-steal clock
	# aged directly where a check says so); kills go through
	# Main's real paths; the reshape's timeline, colour and role
	# flip are read off the pirate itself.

	# (126) Dead-air trigger: a thief worked this run, then only
	# a gunner remains. After the dead-air window the gunner
	# starts reshaping — and it is the only one.
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
	await _frames(10) # a working thief exists; the run flag sets
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

	# (128) Timeline integrity: a reshaping pirate parked beside a
	# slotted canister fires ZERO shots and cannot latch; halfway
	# through it is still a shooter, mid-cross-fade; at the end
	# it is a thief wearing the grabber colour EXACTLY, and the
	# stage signals arrived 1, 2, 3 in order.
	game.start_run()
	game.director.active = false
	game.clear_field()
	# TEST-ONLY LEVER (disclosed): the no-steal clock is aged to
	# its backstop — the quota-spent trigger that used to arm
	# this staging died with the waves; the backstop is the
	# surviving always-armed trigger (check 134's precedent).
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
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
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
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
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	game.multiplier = 2.0
	game.mult_grace_t = 99.0 # pin the multiplier (checks 98/119 precedent)
	# A hunter bystander keeps the field non-empty through the
	# post-kill wait, so the no-thief scan below is a real scan
	# and not a trivial pass over an empty field. A hunter never
	# converts and is never a thief, so it changes nothing else
	# the check measures.
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
	# both the dead-air window and the no-steal backstop (every
	# surviving trigger armed), produces nothing.
	game.start_run()
	game.director.active = false
	game.clear_field()
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
	# run's thief killed, the OLDEST gunner converts; while the
	# convert works as a thief the second gunner stays a shooter.
	game.start_run()
	game.director.active = false
	game.clear_field() # dead air is the trigger here
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var a132: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 60.0))
	await _frames(70) # A is operational, and strictly the oldest
	var b132: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(-300.0, -60.0))
	var t132: Pirate = game.spawn_pirate("grabber",
		Tuning.slot_position(5) + Vector2(-150.0, 0.0))
	await _frames(10) # the thief registers; the run flag sets
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

	# (133) REWORKED (restructure): the mop-up, endless edition.
	# The last grabber is killed and one gunner remains: it
	# converts (dead air — the run's thief worked and is gone),
	# steals a canister and exits with it — and the run simply
	# CONTINUES: no wave advances, the canister count drops by
	# the stolen one, and the state stays RUNNING. No soft-lock.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
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
	var cans133: int = game.canisters_remaining()
	var resolved133: bool = false
	for i: int in range(1800):
		await _frames(1)
		if game.canisters_remaining() == cans133 - 1 \
				and not is_instance_valid(g133) \
				and game.state == Main.GameState.RUNNING:
			resolved133 = true
			break
	_check("mop-up, endless: the last gunner converts, steals, exits; the run continues with one canister gone (no soft-lock)",
		killed133 and resolved133)

	# (134) Backstop: a thief is alive and SEEKING (a working
	# thief — dead air cannot accumulate), yet a gunner converts
	# when the no-steal clock runs out: the thief out failing to
	# latch is exactly what the backstop exists for. TEST-ONLY
	# LEVER (disclosed): the clock is aged directly — the
	# trigger, the gate and the conversion itself all run the
	# real code.
	game.start_run()
	game.director.active = false
	game.clear_field()
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
	_check("backstop: with a live SEEK thief on the field, aging the no-steal clock to %.0fs converts the gunner anyway"
		% Tuning.CONVERT_NO_STEAL_BACKSTOP,
		control134 and fired134 and is_instance_valid(t134)
			and t134.current_role() == "thief")

	# --- M8: spawn flow (continuous dealing) + enemy-bullet pulse --------

	# (136) REWORKED (restructure): the max-run guarantee is now
	# the director's anti-clump rule — across 4000 seed-pinned
	# deals at the t=400 plateau (every class unlocked, several
	# with real alternative shares), no class ever deals more
	# than DIRECTOR_MAX_RUN times consecutively.
	var d136: SpawnDirector = SpawnDirector.new()
	seed(41003)
	var seq136: Array[String] = []
	for k136: int in range(4000):
		seq136.append(d136.pick_next_type(400.0, {}))
	d136.queue_free()
	var worst136: int = _max_run(seq136)
	_check("anti-clump: 4000 deals at the plateau never run one class past %d in a row (worst %d)"
		% [Tuning.DIRECTOR_MAX_RUN, worst136],
		worst136 <= Tuning.DIRECTOR_MAX_RUN)

	# (137) REWORKED (restructure): class-cap dealing. With the
	# hunter count fed in AT the cap (2 at t=100), no hunter is
	# dealt in 600 samples — its share redistributes to the
	# grabber for those deals; with the count below the cap,
	# hunters deal again.
	var d137: SpawnDirector = SpawnDirector.new()
	seed(51003)
	var capped137: Dictionary = {"hunter": Tuning.hunter_alive_cap_at(100.0)}
	var hunters_capped137: int = 0
	var grabbers_capped137: int = 0
	for k137a: int in range(600):
		var dealt137a: String = d137.pick_next_type(100.0, capped137)
		if dealt137a == "hunter":
			hunters_capped137 += 1
		elif dealt137a == "grabber":
			grabbers_capped137 += 1
	var hunters_open137: int = 0
	for k137b: int in range(600):
		if d137.pick_next_type(100.0, {}) == "hunter":
			hunters_open137 += 1
	d137.queue_free()
	_check("class-cap dealing: hunters at cap deal zero hunters in 600 samples (grabbers %d take the share); uncapped, hunters deal (%d)"
		% [grabbers_capped137, hunters_open137],
		hunters_capped137 == 0 and grabbers_capped137 > 400
			and hunters_open137 > 0)

	# (138) Flow pacing: the factor itself (specced value on an
	# empty field, 1.0 at the cap, monotonic between), plus the
	# director's dealt interval — brisk on an empty field, full
	# near the cap. INTEGRATION FORM (disclosed): the harness
	# reads the director's _spawn_t right after a forced deal
	# (the M7 direct-access precedent) and bounds it by
	# rank interval x flow factor x the jitter range [0.8, 1.25].
	var frac_ok138: bool = absf(Tuning.spawn_flow_frac(0, 9)
			- Tuning.SPAWN_FLOW_MIN_FRAC) < 0.001 \
		and absf(Tuning.spawn_flow_frac(9, 9) - 1.0) < 0.001
	var mono138: bool = true
	var prev138: float = Tuning.spawn_flow_frac(0, 9)
	for a138: int in range(1, 10):
		var f138: float = Tuning.spawn_flow_frac(a138, 9)
		if f138 < prev138:
			mono138 = false
		prev138 = f138
	var d138a: SpawnDirector = SpawnDirector.new()
	d138a.start_run() # t=480: alive cap 12 at rank 0
	d138a.step(5.0, 0, Tuning.depot_center(), 0.0, {}, 480.0)
	var empty_t138: float = d138a._spawn_t
	var d138b: SpawnDirector = SpawnDirector.new()
	d138b.start_run()
	d138b.step(5.0, 11, Tuning.depot_center(), 0.0, {}, 480.0)
	var full_t138: float = d138b._spawn_t
	d138a.queue_free()
	d138b.queue_free()
	var base138: float = Tuning.rank_spawn_interval(
		Tuning.spawn_interval_at(480.0), 0.0)
	var empty_ok138: bool = empty_t138 \
			>= base138 * Tuning.SPAWN_FLOW_MIN_FRAC * 0.8 - 0.001 \
		and empty_t138 \
			<= base138 * Tuning.SPAWN_FLOW_MIN_FRAC * 1.25 + 0.001
	var full_frac138: float = Tuning.spawn_flow_frac(11, 12)
	var full_ok138: bool = full_t138 >= base138 * full_frac138 * 0.8 - 0.001 \
		and full_t138 <= base138 * full_frac138 * 1.25 + 0.001
	_check("flow pacing: factor %.2f (empty) -> 1.0 (full) and monotonic; dealt intervals %.3fs empty / %.3fs at 11-of-12 alive"
		% [Tuning.SPAWN_FLOW_MIN_FRAC, empty_t138, full_t138],
		frac_ok138 and mono138 and empty_ok138 and full_ok138
			and full_t138 > empty_t138)

	# (139) Spawn separation: 30 consecutive picks with the
	# player parked at the depot centre — every consecutive pair
	# at least SPAWN_MIN_SEPARATION apart.
	var d139: SpawnDirector = SpawnDirector.new()
	d139.start_run()
	var prev139: Vector2 = d139.pick_spawn_point(Tuning.depot_center())
	var min_pair139: float = INF
	for i139: int in range(29):
		var p139: Vector2 = d139.pick_spawn_point(Tuning.depot_center())
		min_pair139 = minf(min_pair139, p139.distance_to(prev139))
		prev139 = p139
	d139.queue_free()
	_check("spawn separation: 30 consecutive picks at a centred player stay >= %.0fpx apart (min pair %.1fpx)"
		% [Tuning.SPAWN_MIN_SEPARATION, min_pair139],
		min_pair139 >= Tuning.SPAWN_MIN_SEPARATION)

	# (140) Enemy-bullet pulse: the shared clock swings the full
	# range across one breath; two instances sampled in the same
	# instant agree; a tinted bullet's drawn core stays strictly
	# between its tint and white and its green channel visibly
	# climbs toward white at the peak; the pulse constants are
	# as specced. Bounds asserted, never phase-exact values.
	var b140a: EnemyBullet = EnemyBullet.new()
	var b140b: EnemyBullet = EnemyBullet.new()
	var b140t: EnemyBullet = EnemyBullet.new()
	b140t.setup_tinted(Vector2.ZERO, Vector2.RIGHT,
		Color(1.0, 0.2, 0.9), Color(0.3, 0.02, 0.35))
	var same_p140: float = absf(b140a.pulse_value() - b140b.pulse_value())
	var same_c140: Color = b140a.draw_core_color() - b140b.draw_core_color()
	var p_min140: float = 1.0
	var p_max140: float = 0.0
	var tint_g_max140: float = 0.2
	var r_min140: float = Tuning.ENEMY_BULLET_RADIUS * 2.0
	var r_max140: float = 0.0
	var t140: float = 0.0
	while t140 < 0.55: # one full breath at 2.4Hz is ~0.417s
		var pv140: float = b140a.pulse_value()
		p_min140 = minf(p_min140, pv140)
		p_max140 = maxf(p_max140, pv140)
		tint_g_max140 = maxf(tint_g_max140, b140t.draw_core_color().g)
		var rr140: float = b140a.draw_core_radius()
		r_min140 = minf(r_min140, rr140)
		r_max140 = maxf(r_max140, rr140)
		await get_tree().create_timer(0.02).timeout
		t140 += 0.02
	var tint140: Color = b140t.draw_core_color()
	var tint_bounds140: bool = tint140.r >= 1.0 - 0.001 \
		and tint140.r <= 1.0 \
		and tint140.g >= 0.2 - 0.001 and tint140.g <= 1.0 \
		and tint140.b >= 0.9 - 0.001 and tint140.b <= 1.0
	b140a.queue_free()
	b140b.queue_free()
	b140t.queue_free()
	_check("enemy-bullet pulse: swing %.2f..%.2f, instances in sync (dp %.4f), core radius %.2f..%.2f, tinted core climbs toward white (g peak %.2f) within tint..white bounds"
		% [p_min140, p_max140, same_p140, r_min140, r_max140,
			tint_g_max140],
		Tuning.ENEMY_BULLET_PULSE_HZ == 2.4
			and Tuning.ENEMY_BULLET_PULSE_DEPTH == 0.30
			and Tuning.ENEMY_BULLET_PULSE_RADIUS_FRAC == 0.18
			and p_max140 - p_min140 > 0.8
			and same_p140 < 0.02
			and absf(same_c140.r) < 0.01 and absf(same_c140.g) < 0.01
			and absf(same_c140.b) < 0.01
			and r_min140 >= Tuning.ENEMY_BULLET_RADIUS
				* (1.0 - Tuning.ENEMY_BULLET_PULSE_RADIUS_FRAC) - 0.01
			and r_max140 <= Tuning.ENEMY_BULLET_RADIUS
				* (1.0 + Tuning.ENEMY_BULLET_PULSE_RADIUS_FRAC) + 0.01
			and r_max140 - r_min140 > 0.9
			and tint_bounds140 and tint_g_max140 > 0.3)

	# (153) Hunter velocity continuity (micro-fix): the hunter's
	# steering is rebuilt from the player's current position every
	# step, and it used to ASSIGN its velocity outright — every
	# player jink was an instant full-speed direction snap (the
	# jitter reported in play). Now the velocity eases toward the
	# desired vector at HUNTER_STEER_ACCEL. The pirate is driven
	# directly (not through Main) with a scripted zigzag player
	# context: the per-frame velocity change must never exceed
	# the accel bound, however hard the "player" jinks, in either
	# steering branch. The band it settles into once the player
	# parks is measured alongside, like-for-like with (104).
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(80.0, 80.0)
	game.player.invincible_t = 1000000000.0
	var hunt153: Pirate = Pirate.new()
	game.add_child(hunt153)
	hunt153.setup("hunter", Vector2(640.0, 400.0))
	hunt153.player_alive = true
	var no_cans153: Array[Canister] = []
	var delta153: float = 1.0 / 60.0
	var anchor153: Vector2 = Vector2(790.0, 400.0) # orbit range, east
	for i: int in range(60): # burn off the entry telegraph, parked
		hunt153.player_pos = anchor153
		hunt153.player_vel = Vector2.ZERO
		hunt153.step(delta153, no_cans153)
	var zig153: Array[Vector2] = [
		Vector2(1.0, 0.35), Vector2(-0.8, 0.6),
		Vector2(0.3, -1.0), Vector2(-0.6, -0.75)]
	var zig_i153: int = 0
	var prev_v153: Vector2 = hunt153.velocity
	var max_dv153: float = 0.0
	var max_ang153: float = 0.0
	for i: int in range(600): # 10s of hard zigzag at 330 px/s
		if i % 15 == 0:
			zig_i153 = (zig_i153 + 1) % zig153.size()
		var zig_vel153: Vector2 = zig153[zig_i153].normalized() * 330.0
		anchor153 = Tuning.clamp_inside(
			anchor153 + zig_vel153 * delta153, 60.0)
		hunt153.player_pos = anchor153
		hunt153.player_vel = zig_vel153
		hunt153.step(delta153, no_cans153)
		max_dv153 = maxf(max_dv153,
			(hunt153.velocity - prev_v153).length())
		if prev_v153.length() > 1.0 and hunt153.velocity.length() > 1.0:
			max_ang153 = maxf(max_ang153,
				absf(prev_v153.angle_to(hunt153.velocity)))
		prev_v153 = hunt153.velocity
	var min_set153: float = INF
	var max_set153: float = 0.0
	for i: int in range(240): # settle against the parked player
		hunt153.player_pos = anchor153
		hunt153.player_vel = Vector2.ZERO
		hunt153.step(delta153, no_cans153)
		if i >= 120:
			var d153: float = hunt153.global_position.distance_to(anchor153)
			min_set153 = minf(min_set153, d153)
			max_set153 = maxf(max_set153, d153)
	hunt153.queue_free()
	_check("hunter velocity continuity: max |dv| %.2f px/s per frame against the %.2f accel bound under a jinking player, max direction change %.3f rad, settled orbit band %.0f-%.0f"
		% [max_dv153, Tuning.HUNTER_STEER_ACCEL * delta153,
			max_ang153, min_set153, max_set153],
		max_dv153 <= Tuning.HUNTER_STEER_ACCEL * delta153 + 0.05
			and min_set153 >= 110.0 and max_set153 <= 190.0)

	# (154) Drag governor — the cap and the wait, steal lane:
	# three grabbers, three loose canisters by the top edge. Two
	# latch; the third must hold at its canister WITHOUT latching
	# while both lanes are taken (staying in SEEK, near the latch
	# ring), and the pirate-held DRAGGING count must never exceed
	# MAX_CONCURRENT_DRAGS on any frame. When the first steal
	# completes (canister GONE), the waiting thief latches within
	# a bounded number of frames.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 120.0)
	game.player.invincible_t = 1000000000.0
	var cans154: Array[Canister] = []
	var crew154: Array[Pirate] = []
	for i: int in range(3):
		var cx154: float = 300.0 + 340.0 * float(i)
		var can154: Canister = game.canisters[i]
		can154.set_loose(Vector2.ZERO)
		can154.global_position = Vector2(cx154, 205.0)
		cans154.append(can154)
		crew154.append(game.spawn_pirate("grabber", Vector2(cx154, 255.0)))
	var max_drag154: int = 0
	var both_full154: bool = false
	var waiter154: Pirate = null
	var waiter_target154: Canister = null
	var wait_dist_max154: float = 0.0
	var early_drag154: bool = false
	var left_seek154: bool = false
	var gone_frame154: int = -1
	var latch_frame154: int = -1
	var frame154: int = 0
	for i: int in range(1500):
		await _frames(1)
		frame154 += 1
		max_drag154 = maxi(max_drag154, _drag_count_h())
		if not both_full154 and _drag_count_h() == Tuning.MAX_CONCURRENT_DRAGS:
			both_full154 = true
			for p154: Pirate in crew154:
				if p154.phase == Pirate.Phase.SEEK:
					waiter154 = p154
					waiter_target154 = p154.target
		if both_full154 and waiter154 != null and latch_frame154 < 0:
			if waiter154.phase != Pirate.Phase.SEEK \
					and waiter154.phase != Pirate.Phase.DRAG:
				left_seek154 = true
			if waiter_target154 != null \
					and waiter_target154.state == Canister.State.DRAGGING \
					and gone_frame154 < 0:
				early_drag154 = true
			if waiter154.phase == Pirate.Phase.DRAG:
				latch_frame154 = frame154
			elif waiter154.target != null:
				wait_dist_max154 = maxf(wait_dist_max154,
					waiter154.global_position.distance_to(
						waiter154.target.global_position))
		if gone_frame154 < 0:
			for c154: Canister in cans154:
				if c154.state == Canister.State.GONE:
					gone_frame154 = frame154
		if latch_frame154 > 0:
			break
	var latch_latency154: int = -1
	if gone_frame154 > 0 and latch_frame154 > 0:
		latch_latency154 = latch_frame154 - gone_frame154
	_check("drag governor cap: max concurrent pirate drags %d (cap %d), third thief held in SEEK at <= %.0f px from its canister, target never dragged early %s, latched %d frames after the first steal freed a lane"
		% [max_drag154, Tuning.MAX_CONCURRENT_DRAGS, wait_dist_max154,
			str(not early_drag154), latch_latency154],
		max_drag154 == Tuning.MAX_CONCURRENT_DRAGS and both_full154
			and waiter154 != null and not left_seek154
			and not early_drag154
			and wait_dist_max154 <= 40.0
			and latch_latency154 >= 0 and latch_latency154 <= 15)

	# (155) Drag governor — a kill frees a lane: the same three-
	# thief staging in mid-arena, where the drags are far too
	# long to complete inside the setup. One dragging pirate is
	# killed through Main's real kill path; its canister drops
	# loose, and the waiting thief latches its own target within
	# a bounded number of frames, the cap never exceeded.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(120.0, 120.0)
	game.player.invincible_t = 1000000000.0
	var crew155: Array[Pirate] = []
	for i: int in range(3):
		var cx155: float = 300.0 + 340.0 * float(i)
		var can155: Canister = game.canisters[i]
		can155.set_loose(Vector2.ZERO)
		can155.global_position = Vector2(cx155, 400.0)
		crew155.append(game.spawn_pirate("grabber", Vector2(cx155, 450.0)))
	var waiter155: Pirate = null
	var dragger155: Pirate = null
	for i: int in range(600):
		await _frames(1)
		if _drag_count_h() == Tuning.MAX_CONCURRENT_DRAGS:
			for p155: Pirate in crew155:
				if p155.phase == Pirate.Phase.SEEK:
					waiter155 = p155
				elif p155.phase == Pirate.Phase.DRAG and dragger155 == null:
					dragger155 = p155
			if waiter155 != null and dragger155 != null:
				break
	var dropped155: Canister = null
	var drop_state155: int = -1
	if dragger155 != null:
		dropped155 = dragger155.held
		game.kill_pirate(dragger155, false)
		drop_state155 = dropped155.state
	var latch_latency155: int = -1
	var max_drag155: int = 0
	for i: int in range(300):
		await _frames(1)
		max_drag155 = maxi(max_drag155, _drag_count_h())
		if waiter155 != null and is_instance_valid(waiter155) \
				and waiter155.phase == Pirate.Phase.DRAG:
			latch_latency155 = i + 1
			break
	_check("drag governor kill: dropped canister released loose %s, waiting thief latched %d frames after the kill, max concurrent pirate drags %d"
		% [str(drop_state155 == Canister.State.LOOSE), latch_latency155,
			max_drag155],
		waiter155 != null and dropped155 != null
			and drop_state155 == Canister.State.LOOSE
			and latch_latency155 > 0 and latch_latency155 <= 15
			and max_drag155 <= Tuning.MAX_CONCURRENT_DRAGS)

	# (157) Contested tow — a thief targets and latches the
	# canister the player is towing: the canister stays TOWED
	# (the wrestle is a link, not a hold), the pirate enters
	# WRESTLE registered on the canister, and the latch is
	# announced by the CONTESTED! popup at the canister.
	var can157: Canister = await _stage_tow(Vector2(300.0, 200.0))
	var w157: Pirate = game.spawn_pirate("grabber",
		can157.global_position + Vector2(10.0, 46.0))
	var latched157: bool = false
	var popup157: bool = false
	for i: int in range(400):
		await _frames(1)
		if can157.wrestle_count() == 1:
			latched157 = true
			for pop157: Dictionary in game._popups:
				if String(pop157["text"]) == "CONTESTED!":
					popup157 = true
			break
	_check("contested tow latch: thief latched the towed canister %s, CONTESTED! popup shown %s, pirate in WRESTLE %s, canister still TOWED and still the player's tow %s"
		% [str(latched157), str(popup157),
			str(w157.phase == Pirate.Phase.WRESTLE
				and w157.wrestling == can157),
			str(can157.state == Canister.State.TOWED
				and game.player.towed == can157)],
		can157 != null and latched157 and popup157
			and w157.phase == Pirate.Phase.WRESTLE
			and w157.wrestling == can157
			and can157.state == Canister.State.TOWED
			and game.player.towed == can157)

	# (158) Contested tow — the strain, and muscling it home.
	# Baseline: the identical parked tow with no wrestler, its
	# canister settled on the trail point. Contested: the same
	# staging plus a latched wrestler; after settling, the
	# canister must sit displaced TOWARD the wrestler's exit
	# off the baseline point — the visible strain — while still
	# TOWED. Then the player teleports to the depot ring and
	# the canister must still slot, wrestlers detached.
	var can158a: Canister = await _stage_tow(Vector2(300.0, 200.0))
	await _frames(150)
	var base158: Vector2 = can158a.global_position
	var can158: Canister = await _stage_tow(Vector2(300.0, 200.0))
	var w158: Pirate = game.spawn_pirate("grabber",
		can158.global_position + Vector2(10.0, 46.0))
	var latched158: bool = false
	for i: int in range(400):
		await _frames(1)
		if can158.wrestle_count() == 1:
			latched158 = true
			break
	await _frames(240) # settle into the strained equilibrium
	var axis158: Vector2 = (w158.exit_point - base158).normalized()
	var strain158: float = (can158.global_position - base158).dot(axis158)
	_check("contested tow strain: wrestler latched %s, canister displaced %.1f px toward the wrestler's exit off the uncontested trail point (baseline %s, strained %s), still TOWED %s"
		% [str(latched158), strain158, str(base158),
			str(can158.global_position),
			str(can158.state == Canister.State.TOWED
				and game.player.towed == can158)],
		latched158 and strain158 >= 8.0 and strain158 <= 60.0
			and can158.state == Canister.State.TOWED
			and game.player.towed == can158)
	game.player.global_position = Tuning.depot_center() + Vector2(30.0, 0.0)
	var home158: bool = false
	for i: int in range(400):
		await _frames(1)
		if can158.state == Canister.State.IN_SLOT:
			home158 = true
			break
	_check("contested tow muscled home: player slotted the contested canister %s, wrestler list empty %s, wrestler detached back to SEEK %s"
		% [str(home158), str(can158.wrestle_count() == 0),
			str(w158.phase != Pirate.Phase.WRESTLE)],
		home158 and can158.wrestle_count() == 0
			and w158.phase != Pirate.Phase.WRESTLE)

	# (159) Contested tow — the second latch rips it free: with
	# one wrestler hanging on, a second thief's latch detaches
	# the player's tow and hands the canister to the FIRST
	# wrestler as an ordinary DRAG; the second pirate keeps
	# nothing and stays in SEEK.
	var can159: Canister = await _stage_tow(Vector2(300.0, 200.0))
	var w159a: Pirate = game.spawn_pirate("grabber",
		can159.global_position + Vector2(10.0, 46.0))
	var latched159: bool = false
	for i: int in range(400):
		await _frames(1)
		if can159.wrestle_count() == 1:
			latched159 = true
			break
	var w159b: Pirate = game.spawn_pirate("grabber",
		can159.global_position + Vector2(-46.0, -10.0))
	var ripped159: bool = false
	for i: int in range(400):
		await _frames(1)
		if can159.state == Canister.State.DRAGGING:
			ripped159 = true
			break
	_check("contested tow rip: second latch ripped the tow %s, canister DRAGGING under the first wrestler %s (held, in DRAG, lanes clear %s), player tow detached %s, second pirate empty-handed in SEEK %s"
		% [str(ripped159),
			str(can159.holder == w159a and w159a.held == can159
				and w159a.phase == Pirate.Phase.DRAG),
			str(can159.wrestle_count() == 0),
			str(game.player.towed == null),
			str(w159b.held == null
				and w159b.phase == Pirate.Phase.SEEK)],
		latched159 and ripped159 and can159.holder == w159a
			and w159a.held == can159
			and w159a.phase == Pirate.Phase.DRAG
			and can159.wrestle_count() == 0
			and game.player.towed == null
			and w159b.held == null
			and w159b.phase == Pirate.Phase.SEEK)

	# (160) Contested tow — death while contested, end to end:
	# the last canister is towed and wrestled; the player dies
	# through Main's real kill path and the canister does NOT
	# drop loose — it passes to the wrestler's DRAG, hauls out,
	# and the run ends. The old exploit (hold the last canister
	# forever) is closed.
	var can160: Canister = await _stage_tow(Vector2(640.0, 210.0))
	for i: int in range(1, 8):
		game.canisters[i].mark_gone()
	var w160: Pirate = game.spawn_pirate("grabber",
		can160.global_position + Vector2(10.0, 46.0))
	var latched160: bool = false
	for i: int in range(400):
		await _frames(1)
		if can160.wrestle_count() == 1:
			latched160 = true
			break
	game.player.invincible_t = 0.0
	game.kill_player()
	var handed160: bool = can160.state == Canister.State.DRAGGING \
		and can160.holder == w160 and w160.held == can160 \
		and w160.phase == Pirate.Phase.DRAG
	var gone160: bool = false
	for i: int in range(1200):
		await _frames(1)
		if can160.state == Canister.State.GONE:
			gone160 = true
			break
	_check("contested tow death: wrestler latched %s, death handed the canister straight to the wrestler's DRAG (never LOOSE) %s, steal completed at the edge %s, run over %s"
		% [str(latched160), str(handed160), str(gone160),
			str(game.state == Main.GameState.GAMEOVER)],
		latched160 and handed160 and gone160
			and game.state == Main.GameState.GAMEOVER)

	# (161) Contested tow x governor — two pirate drags in
	# flight fill both lanes, so a thief staged on the towed
	# canister is REFUSED the wrestle latch: it reaches the
	# latch ring and waits in SEEK while the lanes stay full
	# for the whole window.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.invincible_t = 1000000000.0
	var tow161: Canister = game.canisters[7]
	tow161.set_loose(Vector2.ZERO)
	tow161.global_position = Vector2(1000.0, 200.0)
	game.player.global_position = Vector2(1020.0, 200.0)
	var can161a: Canister = game.canisters[1]
	can161a.set_loose(Vector2.ZERO)
	can161a.global_position = Vector2(640.0, 500.0)
	game.spawn_pirate("grabber", Vector2(640.0, 552.0))
	var can161b: Canister = game.canisters[2]
	can161b.set_loose(Vector2.ZERO)
	can161b.global_position = Vector2(380.0, 300.0)
	game.spawn_pirate("grabber", Vector2(380.0, 352.0))
	var staged161: bool = false
	for i: int in range(300):
		await _frames(1)
		if _drag_count_h() == Tuning.MAX_CONCURRENT_DRAGS \
				and game.player.towed == tow161:
			staged161 = true
			break
	var t161: Pirate = game.spawn_pirate("grabber",
		tow161.global_position + Vector2(-40.0, 30.0))
	var refused161: bool = true
	var min_ring161: float = INF
	for i: int in range(110):
		await _frames(1)
		min_ring161 = minf(min_ring161,
			t161.global_position.distance_to(tow161.global_position))
		if tow161.wrestle_count() > 0 \
				or t161.phase == Pirate.Phase.WRESTLE:
			refused161 = false
			break
	_check("governor refuses wrestle: lanes staged full %s, thief reached the latch ring (min %.0f px) and was refused for the whole window %s, towed canister unwrestled and still TOWED %s, both drags still in flight %s"
		% [str(staged161), min_ring161, str(refused161),
			str(tow161.wrestle_count() == 0
				and tow161.state == Canister.State.TOWED),
			str(_drag_count_h() == Tuning.MAX_CONCURRENT_DRAGS)],
		staged161 and refused161 and min_ring161 <= 30.0
			and tow161.wrestle_count() == 0
			and tow161.state == Canister.State.TOWED
			and _drag_count_h() == Tuning.MAX_CONCURRENT_DRAGS)

	# (162) Contested tow x governor — one drag plus one
	# wrestler is also a full house: a second thief at the
	# contested canister can neither wrestle nor RIP it (the
	# rip is a latch too, and no lane is free).
	var can162: Canister = await _stage_tow(Vector2(300.0, 200.0))
	var can162d: Canister = game.canisters[1]
	can162d.set_loose(Vector2.ZERO)
	can162d.global_position = Vector2(640.0, 500.0)
	game.spawn_pirate("grabber", Vector2(640.0, 552.0))
	var w162: Pirate = game.spawn_pirate("grabber",
		can162.global_position + Vector2(10.0, 46.0))
	var staged162: bool = false
	for i: int in range(400):
		await _frames(1)
		if can162.wrestle_count() == 1 \
				and _drag_count_h() == 1:
			staged162 = true
			break
	var t162: Pirate = game.spawn_pirate("grabber",
		can162.global_position + Vector2(-46.0, -10.0))
	var held162: bool = true
	var min_ring162: float = INF
	for i: int in range(110):
		await _frames(1)
		min_ring162 = minf(min_ring162,
			t162.global_position.distance_to(can162.global_position))
		if can162.state != Canister.State.TOWED \
				or can162.wrestle_count() != 1 \
				or _drag_count_h() != 1 \
				or t162.phase == Pirate.Phase.WRESTLE \
				or t162.phase == Pirate.Phase.DRAG:
			held162 = false
			break
	_check("governor refuses the rip: drag + wrestler staged %s, second thief reached the ring (min %.0f px) but the house stayed exactly full all window %s (canister TOWED, 1 wrestler, 1 drag)"
		% [str(staged162), min_ring162, str(held162)],
		staged162 and held162 and min_ring162 <= 30.0
			and can162.state == Canister.State.TOWED
			and can162.wrestle_count() == 1
			and _drag_count_h() == 1)

	# (163) Contested tow — killing the wrestler frees the tow:
	# the wrestler dies through the real bullet path, its link
	# clears, and the canister sails on TOWED, uncontested.
	var can163: Canister = await _stage_tow(Vector2(300.0, 200.0))
	var w163: Pirate = game.spawn_pirate("grabber",
		can163.global_position + Vector2(10.0, 46.0))
	var latched163: bool = false
	for i: int in range(400):
		await _frames(1)
		if can163.wrestle_count() == 1:
			latched163 = true
			break
	var killed163: bool = false
	for i: int in range(60):
		if not is_instance_valid(w163):
			killed163 = true
			break
		if i % 4 == 0:
			game.spawn_bullet(
				w163.global_position + Vector2(-30.0, 0.0), Vector2.RIGHT)
		await _frames(1)
	if is_instance_valid(w163):
		await _frames(2)
		killed163 = not is_instance_valid(w163)
	_check("killing the wrestler frees the tow: wrestler latched %s then shot dead %s, canister still TOWED by the player %s, wrestler list empty %s"
		% [str(latched163), str(killed163),
			str(can163.state == Canister.State.TOWED
				and game.player.towed == can163),
			str(can163.wrestle_count() == 0)],
		latched163 and killed163
			and can163.state == Canister.State.TOWED
			and game.player.towed == can163
			and can163.wrestle_count() == 0)

	# --- Restructure: continuous director, darter, sniper ---------

	# (164) Composition curve: at t=10 only the grabber holds a
	# share; at t=100 gunner and hunter are in and darter/sniper
	# are still locked; at t=400 all five hold shares, the
	# grabber sits exactly on its 0.38 floor, and shares sum to 1.
	var comp10: Dictionary = Tuning.composition_at(10.0)
	var comp100: Dictionary = Tuning.composition_at(100.0)
	var comp400: Dictionary = Tuning.composition_at(400.0)
	var sum400: float = 0.0
	for cv164: Variant in comp400.values():
		sum400 += float(cv164)
	_check("composition: t=10 grabber only; t=100 gunner+hunter in, darter+sniper locked; t=400 all five, grabber on its 0.38 floor, shares sum to 1",
		absf(float(comp10.get("grabber", 0.0)) - 1.0) < 0.001
			and float(comp10.get("gunner", 0.0)) == 0.0
			and float(comp100.get("gunner", 0.0)) > 0.0
			and float(comp100.get("hunter", 0.0)) > 0.0
			and float(comp100.get("darter", 0.0)) == 0.0
			and float(comp100.get("sniper", 0.0)) == 0.0
			and float(comp400.get("darter", 0.0)) > 0.0
			and float(comp400.get("sniper", 0.0)) > 0.0
			and absf(float(comp400.get("grabber", 0.0)) - 0.38) < 0.001
			and absf(sum400 - 1.0) < 0.001)

	# (165) Unlock boundaries, seed-pinned: just below an unlock
	# the locked class cannot deal — at t=29.9 every deal is a
	# grabber; at t=179.9 no sniper appears in 600 deals.
	var d165: SpawnDirector = SpawnDirector.new()
	seed(61001)
	var non_grabber165: int = 0
	for i165a: int in range(300):
		if d165.pick_next_type(29.9, {}) != "grabber":
			non_grabber165 += 1
	var snipers165: int = 0
	for i165b: int in range(600):
		if d165.pick_next_type(179.9, {}) == "sniper":
			snipers165 += 1
	d165.queue_free()
	_check("unlock boundaries: 300 deals at t=29.9 are all grabber; 600 deals at t=179.9 deal no sniper",
		non_grabber165 == 0 and snipers165 == 0)

	# (166) Endless soak, phase A: a standalone director runs
	# 600 simulated seconds (delta 0.25) against a scripted
	# killer (dealt pirates die 4-9s later, fed back as the
	# alive count). Dealing never stops — every 30s window is
	# non-empty — and the alive count never beats the cap curve.
	var d166: SpawnDirector = SpawnDirector.new()
	d166.spawn_requested.connect(_record_spawn)
	seed(91001)
	d166.start_run()
	var deaths166: Array[float] = []
	var windows166: Array[int] = []
	for w166: int in range(20):
		windows166.append(0)
	var alive_max166: int = 0
	var read166: int = 0
	_dealt_types.clear()
	var sim166: float = 0.0
	for step166: int in range(2400):
		sim166 += 0.25
		var alive166: int = 0
		for dt166: float in deaths166:
			if dt166 > sim166:
				alive166 += 1
		d166.step(0.25, alive166, Vector2(640.0, 400.0), 0.4, {}, sim166)
		while read166 < _dealt_types.size():
			read166 += 1
			deaths166.append(sim166 + randf_range(4.0, 9.0))
			windows166[mini(int(sim166 / 30.0), 19)] += 1
		alive166 = 0
		for dt166b: float in deaths166:
			if dt166b > sim166:
				alive166 += 1
		alive_max166 = maxi(alive_max166, alive166)
		if step166 % 200 == 199:
			var keep166: Array[float] = []
			for dt166c: float in deaths166:
				if dt166c > sim166:
					keep166.append(dt166c)
			deaths166 = keep166
	var total166: int = _dealt_types.size()
	var quiet166: int = 0
	for w166b: int in range(20):
		if windows166[w166b] == 0:
			quiet166 += 1
	d166.queue_free()
	_check("endless soak A: 600 simulated seconds deal %d spawns, every 30s window non-empty, alive peaks at %d under the cap curve"
		% [total166, alive_max166],
		quiet166 == 0 and total166 > 400
			and alive_max166 <= Tuning.alive_cap_at(600.0)
				+ Tuning.rank_alive_bonus(0.4))

	# (166) Phase B: the real scene under a live director,
	# stepped synchronously for 60 simulated seconds with a
	# killer clearing the field every 30 steps: dealing
	# continues, the field never beats the live cap, and the run
	# is still RUNNING at the end.
	game.start_run() # director live for this one
	game.player.invincible_t = 1000000000.0
	game.player.global_position = Vector2(120.0, 680.0)
	var kills_b166: int = 0
	var over_b166: bool = false
	for stepb166: int in range(3600):
		game._physics_process(1.0 / 60.0)
		var cap_b166: int = Tuning.alive_cap_at(game.run_time) \
			+ Tuning.rank_alive_bonus(game.rank)
		if game.pirates.size() > cap_b166:
			over_b166 = true
		if stepb166 % 30 == 29:
			var field_b166: Array[Pirate] = game.pirates.duplicate()
			for pb166: Pirate in field_b166:
				game.kill_pirate(pb166, false)
				kills_b166 += 1
	_check("endless soak B: 60 stepped seconds under a live director — %d kills fed back, field never over the live cap, run still RUNNING at t=%.1f"
		% [kills_b166, game.run_time],
		kills_b166 + game.pirates.size() > 30 and not over_b166
			and game.state == Main.GameState.RUNNING
			and game.run_time > 59.0)

	# (166) Phase C: a real steal completes under the live
	# director, and once the remaining canisters are gone the
	# run ends at GAMEOVER — the canister clock is the run's
	# only ending.
	game.start_run() # director live
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var can166: Canister = game.canisters[0]
	can166.set_loose(Vector2.ZERO)
	can166.global_position = Vector2(640.0, 210.0)
	game.spawn_pirate("grabber", Vector2(640.0, 252.0))
	var stole_c166: bool = false
	for stepc166: int in range(3600):
		game._physics_process(1.0 / 60.0)
		if can166.state == Canister.State.GONE:
			stole_c166 = true
			break
	for c166b: Canister in game.canisters:
		if c166b.state != Canister.State.GONE:
			c166b.mark_gone()
	var over_c166: bool = false
	for stepc2_166: int in range(120):
		game._physics_process(1.0 / 60.0)
		if game.state == Main.GameState.GAMEOVER:
			over_c166 = true
			break
	_check("endless soak C: a real steal completes under the live director; with the rest gone the run ends at GAMEOVER",
		stole_c166 and over_c166)

	# (167) Darter cycle: approach closes on the parked player;
	# the windup runs ~0.45s wearing the charge glow; the lunge
	# leaves at lunge speed along the player's bearing AT WINDUP
	# END and flies it straight even after the player teleports
	# away; recovery ends slow; then a second approach begins.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(900.0, 400.0)
	game.player.invincible_t = 1000000000.0
	var dart167: Pirate = game.spawn_pirate("darter", Vector2(300.0, 400.0))
	var dist0_167: float = dart167.global_position.distance_to(
		Vector2(900.0, 400.0))
	var min_app167: float = dist0_167
	var windup_frames167: int = 0
	var windup_charge167: bool = false
	var lunge_dir167: Vector2 = Vector2.ZERO
	var lunge_speed167: float = 0.0
	var lunge_bearing_err167: float = -1.0
	var lunge_max_dev167: float = 0.0
	var teleported167: bool = false
	var recover_end_speed167: float = -1.0
	var cycle_done167: bool = false
	var prev_state167: int = -1
	for i167: int in range(900):
		await _frames(1)
		if not is_instance_valid(dart167):
			break
		var st167: int = int(dart167._dart_state)
		var vel167: Vector2 = dart167.velocity
		if st167 == int(Pirate.Dart.APPROACH):
			if prev_state167 == int(Pirate.Dart.RECOVER):
				cycle_done167 = true
				break
			min_app167 = minf(min_app167, dart167.global_position.distance_to(
				game.player.global_position))
		elif st167 == int(Pirate.Dart.WINDUP):
			windup_frames167 += 1
			if dart167.charge_frac() >= 0.0:
				windup_charge167 = true
		elif st167 == int(Pirate.Dart.LUNGE):
			if prev_state167 == int(Pirate.Dart.WINDUP):
				lunge_dir167 = vel167.normalized()
				lunge_speed167 = vel167.length()
				lunge_bearing_err167 = absf(lunge_dir167.angle_to(
					(game.player.global_position
						- dart167.global_position).normalized()))
				game.player.global_position = Vector2(900.0, 650.0)
				teleported167 = true
			elif lunge_dir167 != Vector2.ZERO and vel167.length() > 1.0:
				lunge_max_dev167 = maxf(lunge_max_dev167,
					absf(vel167.normalized().angle_to(lunge_dir167)))
		elif st167 == int(Pirate.Dart.RECOVER):
			recover_end_speed167 = vel167.length()
		prev_state167 = st167
	_check("darter cycle: approach closes to %.0fpx, windup %d frames wearing the charge glow, lunge %.0f px/s on the windup-end bearing (err %.3f rad), flies straight after the player teleports (dev %.3f), recover ends at %.0f px/s, second approach begins"
		% [min_app167, windup_frames167, lunge_speed167,
			lunge_bearing_err167, lunge_max_dev167, recover_end_speed167],
		min_app167 < dist0_167 - 100.0
			and windup_frames167 >= 22 and windup_frames167 <= 33
			and windup_charge167
			and absf(lunge_speed167 - Tuning.DARTER_LUNGE_SPEED) < 1.0
			and lunge_bearing_err167 >= 0.0 and lunge_bearing_err167 < 0.06
			and teleported167 and lunge_max_dev167 < 0.02
			and recover_end_speed167 >= 0.0
				and recover_end_speed167 <= Tuning.DARTER_RECOVER_MAX_SPEED + 1.0
			and cycle_done167)

	# (168) A darter beside a loose canister for 5s never
	# latches, drags or holds it (the hunter's check 103 staging
	# exactly): its cycle only ever points at the player.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(1150.0, 120.0)
	game.player.invincible_t = 1000000000.0
	var can168: Canister = game.canisters[0]
	can168.set_loose(Vector2.ZERO)
	can168.global_position = Vector2(300.0, 620.0)
	var dart168: Pirate = game.spawn_pirate("darter", Vector2(330.0, 620.0))
	var stole168: bool = false
	for i168: int in range(300):
		await _frames(1)
		if not is_instance_valid(dart168):
			stole168 = true
			break
		if dart168.phase == Pirate.Phase.DRAG or dart168.held != null \
				or can168.holder != null \
				or can168.state != Canister.State.LOOSE:
			stole168 = true
			break
	_check("darter beside a loose canister never latches, drags or holds it (5s watch)",
		not stole168 and is_instance_valid(dart168)
			and can168.state == Canister.State.LOOSE
			and can168.holder == null)

	# (169) Sniper band: it settles into the 420-520px band
	# around a parked player; staged at 300px in open field it
	# retreats until the band is restored.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.invincible_t = 1000000000.0
	var snip169: Pirate = game.spawn_pirate("sniper", Vector2(150.0, 400.0))
	var settled169: bool = false
	var settle_d169: float = 0.0
	for i169a: int in range(900):
		await _frames(1)
		if not is_instance_valid(snip169):
			break
		if snip169.phase == Pirate.Phase.HOLD:
			settle_d169 = snip169.global_position.distance_to(
				game.player.global_position)
			if settle_d169 >= Tuning.SNIPER_BAND_MIN \
					and settle_d169 <= Tuning.SNIPER_BAND_MAX:
				settled169 = true
				break
	# Re-stage both in open field at 300px: the retreat reads
	# identically and no arena wall can mask it.
	snip169.global_position = Vector2(400.0, 400.0)
	game.player.global_position = Vector2(700.0, 400.0)
	var restored169: bool = false
	var restore_frames169: int = -1
	for i169b: int in range(600):
		await _frames(1)
		if not is_instance_valid(snip169):
			break
		if snip169.global_position.distance_to(
				game.player.global_position) >= Tuning.SNIPER_BAND_MIN:
			restored169 = true
			restore_frames169 = i169b + 1
			break
	_check("sniper settles in its band (%.0fpx) and retreats to restore it when closed on (restored in %d frames)"
		% [settle_d169, restore_frames169],
		settled169 and restored169)

	# (170) Sniper charge discipline: the first shot comes only
	# after a full charge (0.8s from charge start), and no shot
	# is fired while the player is dead. (An off-screen sniper
	# cannot persist to a fire moment — every pirate step clamps
	# inside the arena before its fire block runs — so the
	# gunner's discipline is asserted on the reachable gates:
	# telegraph, charge duration, player down.)
	game.start_run()
	game.director.active = false
	game.clear_field()
	game.player.global_position = Vector2(640.0, 400.0)
	game.player.invincible_t = 1000000000.0
	var snip170: Pirate = game.spawn_pirate("sniper", Vector2(170.0, 400.0))
	_conv_shots = 0
	snip170.fired.connect(_count_conv_shot)
	var charge_start170: int = -1
	var first_shot170: int = -1
	var telegraph_shots170: int = 0
	for i170a: int in range(900):
		await _frames(1)
		if not is_instance_valid(snip170):
			break
		if snip170.phase == Pirate.Phase.TELEGRAPH and _conv_shots > 0:
			telegraph_shots170 = _conv_shots
		if charge_start170 < 0 and snip170.charge_frac() >= 0.0:
			charge_start170 = i170a
		if _conv_shots > 0:
			first_shot170 = i170a
			break
	var charge_span170: int = -1
	if charge_start170 >= 0 and first_shot170 >= 0:
		charge_span170 = first_shot170 - charge_start170
	# Player down: the cycle halts outright.
	game.player.invincible_t = 0.0
	game.kill_player()
	game.player.respawn_t = 100000.0 # stay down for the watch
	_conv_shots = 0
	for i170b: int in range(300):
		await _frames(1)
	_check("sniper charge discipline: no telegraph fire, first shot %d frames after the charge starts (0.8s = 48), zero fire across a 5s player-down watch (%d)"
		% [charge_span170, _conv_shots],
		telegraph_shots170 == 0 and charge_span170 >= 46
			and _conv_shots == 0)

	# (171) The sniper never converts: staged beside a gunner
	# with the no-steal clock aged to its backstop (checks
	# 128/134's lever), the GUNNER converts — and the sniper's
	# role stays "sniper" throughout, never entering CONVERT.
	game.start_run()
	game.director.active = false
	game.clear_field()
	game._convert_no_progress_t = Tuning.CONVERT_NO_STEAL_BACKSTOP
	game.player.global_position = Vector2(120.0, 680.0)
	game.player.invincible_t = 1000000000.0
	var snip171: Pirate = game.spawn_pirate("sniper", Vector2(1100.0, 150.0))
	var gun171: Pirate = game.spawn_pirate("gunner",
		Tuning.depot_center() + Vector2(300.0, 0.0))
	var gun_converted171: bool = false
	var sniper_held171: bool = true
	for i171: int in range(400):
		await _frames(1)
		if is_instance_valid(snip171) and (
				snip171.current_role() != "sniper"
				or snip171.is_converting()):
			sniper_held171 = false
		if is_instance_valid(gun171) and gun171.is_converting():
			gun_converted171 = true
		if gun_converted171 and i171 >= 150:
			break
	_check("sniper never converts: the gunner converts on the aged clock while the sniper's role stays sniper",
		gun_converted171 and sniper_held171
			and is_instance_valid(snip171)
			and snip171.current_role() == "sniper")

	# (172) Run timer + HUD shape: the run clock advances with
	# stepped physics, the HUD mirrors it (and formats m:ss),
	# and the HUD's property list carries run_time — and no
	# wave or boss fields at all.
	game.start_run()
	game.director.active = false
	var t0_172: float = game.run_time
	for step172: int in range(120):
		game._physics_process(1.0 / 60.0)
	var advanced172: float = game.run_time - t0_172
	game._sync_hud()
	var props172: Array[String] = []
	for pv172: Dictionary in game.hud.get_property_list():
		props172.append(String(pv172["name"]))
	_check("run timer: clock advances %.2fs over 120 stepped frames, HUD mirrors it and formats 65s as %s; HUD has run_time and no wave/boss fields"
		% [advanced172, game.hud.format_time(65.0)],
		advanced172 > 1.9 and advanced172 < 2.1
			and absf(game.hud.run_time - game.run_time) < 0.001
			and game.hud.format_time(65.0) == "1:05"
			and props172.has("run_time")
			and not props172.has("wave")
			and not props172.has("boss_bar_active"))

	print("HARNESS: %d/%d checks passed" % [_passed, _passed + _failed])
	get_tree().quit(0 if _failed == 0 else 1)
