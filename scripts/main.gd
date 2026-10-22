class_name Main
extends Node2D
## Ripped-Off, milestone 1: a THIN orchestrator. It owns the run
## state machine (TITLE / RUNNING / GAMEOVER), the score state (the
## one place score and multiplier live), collision resolution and
## the local high-score save. Everything with its own behaviour —
## canisters, pirates, the director, the light — lives in its own
## script and is only stepped and refereed from here.

enum GameState { TITLE, RUNNING, GAMEOVER }

const SAVE_PATH: String = "user://rippedoff_save.json"
const SAVE_BEST_SCORE: String = "best_score"
const SAVE_BEST_TIME: String = "best_time"

var state: GameState = GameState.TITLE
var paused: bool = false

# Score state — exactly one home: here. Rank lives here too, with
# the score it feeds on: gains for kills, shards, buzz and
# recoveries; bleeds on death and on canisters lost; floored by
# run time. The run clock lives here too: seconds since the run
# started, the director's escalation input.
var score: int = 0
var multiplier: float = 1.0
var mult_grace_t: float = 0.0
var rank: float = Tuning.RANK_START
var run_time: float = 0.0
var best_score: int = 0
var best_time: float = 0.0

var player: Player = null
var canisters: Array[Canister] = []
var pirates: Array[Pirate] = []
var bullets: Array[Bullet] = []
var enemy_bullets: Array[EnemyBullet] = []
var shards: Array[Shard] = []
var pickups: Array[Powerup] = []
var director: SpawnDirector = null
var fx: LightFx = null
var hud: Hud = null
var music: MusicDirector = null
var sfx: SfxDirector = null

var _run_count: int = 0 # seeds the music variant rotation per run

# Conversion watcher state (M7) — see _step_conversion. All of it
# is per-run: reset on every run start, so no trigger state
# leaks across a run boundary.
var _convert_cooldown_t: float = 0.0 # ticks down from a conversion start
var _convert_dead_air_t: float = 0.0 # no working thief, after one existed
var _convert_no_progress_t: float = 0.0 # nobody dragging anything
var _run_had_thief: bool = false # a getter has worked this run

var _debris: Array[Dictionary] = [] # shrapnel lines {pos, vel, t, dur, color}
var _popups: Array[Dictionary] = [] # floating text {pos, t, dur, text, color}
var _font: Font = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Powerup drops roll on their OWN generator, seeded per run (the
# music director's pattern): runs deal different drop sequences,
# and the harness can pin the seed for a deterministic one.
var _drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()


# --- Setup ---------------------------------------------------------------

func _ready() -> void:
	_apply_stage_offset()
	get_tree().root.size_changed.connect(_on_window_size_changed)
	_rng.randomize()
	_font = ThemeDB.fallback_font
	AudioBuses.ensure()
	_load_best()
	fx = LightFx.new()
	add_child(fx)
	director = SpawnDirector.new()
	add_child(director)
	director.spawn_requested.connect(_on_spawn_requested)
	player = Player.new()
	add_child(player)
	player.fired.connect(_on_player_fired)
	player.reset_for_run(_player_spawn_pos())
	player.invincible_t = 0.0
	_make_canisters()
	hud = Hud.new()
	add_child(hud)
	music = MusicDirector.new()
	add_child(music) # boots in TITLE mode: the title loop is live
	sfx = SfxDirector.new()
	add_child(sfx)
	_sync_hud()
	queue_redraw()


## Center the whole 1280x800 stage in the real visible canvas.
## Stretch aspect "expand" grows the canvas on any window whose
## aspect differs from the design view; without this offset the
## stage hugs the top-left and every screen rides high on the
## physical window. This is a pure
## presentation translation of the root node: every gameplay
## coordinate is stage-local and untouched, and mouse aim reads
## get_global_mouse_position(), which already accounts for it.
func _apply_stage_offset() -> void:
	position = Tuning.stage_offset_for(get_viewport_rect().size)


func _on_window_size_changed() -> void:
	_apply_stage_offset()


func _make_canisters() -> void:
	for c: Canister in canisters:
		c.queue_free()
	canisters.clear()
	for i: int in range(Tuning.SLOT_COUNT):
		var c: Canister = Canister.new()
		add_child(c)
		move_child(c, 1) # canisters draw under ships, over the floor
		c.setup(i, Tuning.slot_position(i))
		canisters.append(c)


func _player_spawn_pos() -> Vector2:
	return Tuning.depot_center() + Vector2(0.0, 195.0)


# --- Run flow --------------------------------------------------------------

func start_run() -> void:
	clear_field()
	_make_canisters()
	player.reset_for_run(_player_spawn_pos())
	score = 0
	multiplier = 1.0
	mult_grace_t = 0.0
	rank = Tuning.RANK_START
	run_time = 0.0
	_reset_conversion_state()
	paused = false
	state = GameState.RUNNING
	fx.clear()
	_run_count += 1
	music.begin_run(20261018 + _run_count * 7919)
	_drop_rng.seed = 20261018 + _run_count * 104729
	sfx.play("ui_start", player.global_position)
	director.start_run()
	_sync_hud()
	queue_redraw()


func _game_over() -> void:
	state = GameState.GAMEOVER
	director.stop()
	music.set_mode_title() # run layers fade out; title loop returns
	sfx.play("game_over", Tuning.depot_center())
	fx.burst(Tuning.depot_center(), Tuning.COLOR_DEPOT, LightFx.Size.MEDIUM)
	fx.edge_flash(Tuning.COLOR_STEAL_FLASH)
	if score > best_score:
		best_score = score
		best_time = run_time
		_save_best()
	_sync_hud()


## Every conversion trigger clock starts clean each run: the
## cooldown is ready, no dead air or stall has accumulated, and
## no getter has worked yet — conversion replaces a run's lost
## getters, it never pre-empts its first one.
func _reset_conversion_state() -> void:
	_convert_cooldown_t = 0.0
	_convert_dead_air_t = 0.0
	_convert_no_progress_t = 0.0
	_run_had_thief = false


## Free every pirate, bullet and shard (used by start_run; also a
## clean lever for the test harness).
func clear_field() -> void:
	for p: Pirate in pirates:
		p.queue_free()
	pirates.clear()
	for b: Bullet in bullets:
		b.queue_free()
	bullets.clear()
	for eb: EnemyBullet in enemy_bullets:
		eb.queue_free()
	enemy_bullets.clear()
	for s: Shard in shards:
		s.queue_free()
	shards.clear()
	for pk: Powerup in pickups:
		pk.queue_free()
	pickups.clear()
	_debris.clear()
	_popups.clear()


# --- Spawning (director / player signals) -----------------------------------

func _on_spawn_requested(type_name: String, pos: Vector2) -> void:
	spawn_pirate(type_name, pos)


func spawn_pirate(type_name: String, pos: Vector2) -> Pirate:
	var p: Pirate = Pirate.new()
	add_child(p)
	p.setup(type_name, pos)
	p.fired.connect(_on_pirate_fired)
	p.convert_stage.connect(_on_pirate_convert_stage.bind(p))
	p.wrestle_started.connect(_on_pirate_wrestle_started.bind(p))
	pirates.append(p)
	return p


func _on_pirate_fired(from: Vector2, dir: Vector2) -> void:
	spawn_enemy_bullet(from, dir)


## The canister-loss path: a pirate carried it out — gone, the
## stolen sound, a steal burst at the canister, the arena edge
## flash, and the steal rank bleed.
func _steal_canister(c: Canister) -> void:
	var edge_pos: Vector2 = Tuning.clamp_inside(c.global_position, 2.0)
	c.mark_gone()
	sfx.play("canister_stolen", edge_pos)
	_add_rank(-Tuning.RANK_BLEED_STEAL) # a loss lets the game ease off
	fx.edge_flash(Tuning.COLOR_STEAL_FLASH)
	fx.burst(edge_pos, Tuning.COLOR_STEAL_FLASH, LightFx.Size.SPARK)


func spawn_enemy_bullet(from: Vector2, dir: Vector2) -> EnemyBullet:
	var eb: EnemyBullet = EnemyBullet.new()
	add_child(eb)
	eb.setup(from, dir)
	enemy_bullets.append(eb)
	return eb


func _on_player_fired(from: Vector2, dir: Vector2) -> void:
	if player.has_powerup("spread"):
		# Spread: the one fired signal fans out into 3 bullets —
		# centre and facing rotated by the Tuning angle each way.
		spawn_bullet(from, dir.rotated(-Tuning.POWERUP_SPREAD_ANGLE))
		spawn_bullet(from, dir)
		spawn_bullet(from, dir.rotated(Tuning.POWERUP_SPREAD_ANGLE))
	else:
		spawn_bullet(from, dir)
	sfx.play("shot", from) # throttled inside the sfx director


func spawn_bullet(from: Vector2, dir: Vector2) -> Bullet:
	var b: Bullet = Bullet.new()
	add_child(b)
	b.setup(from, dir)
	bullets.append(b)
	return b


func _spawn_shards(at: Vector2, count: int) -> void:
	for i: int in range(count):
		var s: Shard = Shard.new()
		add_child(s)
		var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
		s.setup(at, dir, Tuning.SHARD_BURST_SPEED * _rng.randf_range(0.6, 1.25))
		shards.append(s)


func _spawn_debris(at: Vector2, color: Color, count: int) -> void:
	for i: int in range(count):
		var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
		_debris.append({
			"pos": at, "vel": dir * _rng.randf_range(90.0, 320.0),
			"t": 0.0, "dur": _rng.randf_range(0.3, 0.6), "color": color})


# --- Score state ---------------------------------------------------------------

## The only door into the score. Returns what was actually paid.
func add_score(base_points: int) -> int:
	var gained: int = int(round(float(base_points) * multiplier))
	score += gained
	return gained


func collect_shard() -> void:
	add_score(Tuning.SHARD_BASE_POINTS)
	multiplier = minf(multiplier + Tuning.MULT_PER_SHARD, Tuning.MULT_CAP)
	mult_grace_t = Tuning.MULT_GRACE
	_add_rank(Tuning.RANK_GAIN_SHARD)
	sfx.play_collect(player.global_position)


## Rank moves only through here: clamped to 0..1, and the run-time
## floor is re-applied every frame in _step_score.
func _add_rank(amount: float) -> void:
	rank = clampf(rank + amount, 0.0, 1.0)


## A buzz payout (bullet graze or close drag pass): small points
## through the multiplier, a multiplier nudge, a little rank, a
## light tick on the ship and a floating "BUZZ" marker.
func _award_buzz(at_pos: Vector2) -> void:
	var gained: int = add_score(Tuning.BUZZ_POINTS)
	multiplier = minf(multiplier + Tuning.BUZZ_MULT_NUDGE, Tuning.MULT_CAP)
	_add_rank(Tuning.RANK_GAIN_BUZZ)
	sfx.play("buzz", at_pos)
	fx.burst(player.global_position, Tuning.COLOR_SHARD, LightFx.Size.SPARK)
	spawn_popup(at_pos, "BUZZ +%d" % gained, Tuning.COLOR_SHARD)


## Floating world-space score text (buzz, recovery bonuses).
func spawn_popup(pos: Vector2, text: String, color: Color) -> void:
	_popups.append({"pos": pos, "t": 0.0, "dur": Tuning.POPUP_TIME,
		"text": text, "color": color})


func _step_popups(delta: float) -> void:
	for i: int in range(_popups.size() - 1, -1, -1):
		var pop: Dictionary = _popups[i]
		var t: float = float(pop["t"]) + delta
		if t >= float(pop["dur"]):
			_popups.remove_at(i)
		else:
			pop["t"] = t
			var pos: Vector2 = pop["pos"] as Vector2
			pop["pos"] = pos + Vector2(0.0, -Tuning.POPUP_RISE_SPEED * delta)
			_popups[i] = pop


func recovery_base_points(tow_start: Vector2) -> int:
	var dist: float = tow_start.distance_to(Tuning.depot_center())
	var frac: float = clampf(
		(dist - Tuning.RECOVERY_DIST_NEAR)
			/ (Tuning.RECOVERY_DIST_FAR - Tuning.RECOVERY_DIST_NEAR),
		0.0, 1.0)
	return int(round(lerpf(
		float(Tuning.RECOVERY_MIN), float(Tuning.RECOVERY_MAX), frac)))


func _step_score(delta: float) -> void:
	if mult_grace_t > 0.0:
		mult_grace_t = maxf(mult_grace_t - delta, 0.0)
	elif multiplier > 1.0:
		multiplier = maxf(1.0, multiplier - Tuning.MULT_DECAY_RATE * delta)
	# The rank floor: bleeding stops at the run's menace level.
	rank = maxf(rank, Tuning.rank_floor_at(run_time))


# --- Kills and death -------------------------------------------------------------

func kill_pirate(p: Pirate, award: bool) -> void:
	if not pirates.has(p):
		return
	pirates.erase(p)
	if p.wrestling != null:
		p.detach_wrestle() # a dead wrestler lets go; the tow sails on
	if p.held != null and is_instance_valid(p.held):
		p.held.release_from_drag(p.velocity)
	_spawn_shards(p.global_position, p.shard_count())
	_spawn_debris(p.global_position, p.draw_color, 7)
	fx.burst(p.global_position, p.draw_color, LightFx.Size.SMALL)
	sfx.play("death_" + p.type_name, p.global_position) # per-class pop
	if award:
		add_score(p.score_value())
		_add_rank(Tuning.RANK_GAIN_KILL)
	_maybe_roll_powerup_drop(p.global_position)
	p.queue_free()


func kill_player() -> void:
	if not player.alive or player.is_invincible():
		return
	# SHIELD: an active shield eats the hit BEFORE any death cost
	# lands — no multiplier slash, no rank bleed, no bullet-cancel,
	# no tow drop. Both kill paths (enemy bullet, contact) run
	# through here, so both are covered by this one hook.
	if player.try_consume_shield():
		fx.burst(player.global_position, Tuning.COLOR_POWERUP_SHIELD,
			LightFx.Size.SMALL)
		sfx.play("tow_latch", player.global_position)
		return
	fx.burst(player.global_position, Tuning.COLOR_PLAYER,
		LightFx.Size.PLAYER_DEATH)
	sfx.play("player_death", player.global_position)
	fx.edge_flash(Tuning.COLOR_STEAL_FLASH)
	_spawn_debris(player.global_position, Tuning.COLOR_PLAYER, 10)
	_cancel_enemy_bullets() # death protocol: hostile fire becomes salvage
	# CONTESTED TOW: death while a wrestler hangs on the tow hands
	# the canister to that wrestler BEFORE the tow drops — it
	# passes straight to a pirate DRAG and out, never LOOSE, so
	# holding the last canister can no longer pause the clock.
	# (Uncontested, die() drops the tow LOOSE exactly as before.)
	if player.towed != null and is_instance_valid(player.towed) \
			and player.towed.state == Canister.State.TOWED \
			and player.towed.wrestle_count() > 0:
		var first_w: Node2D = player.towed.wrestlers[0]
		if first_w is Pirate and is_instance_valid(first_w):
			(first_w as Pirate).take_over_wrestle()
	player.die() # drops any tow; the canister goes LOOSE
	multiplier = maxf(1.0, multiplier * Tuning.MULT_DEATH_FACTOR)
	_add_rank(-Tuning.RANK_BLEED_DEATH)
	player.respawn_t = Tuning.PLAYER_RESPAWN_TIME


# --- Powerup drops (M5) ---------------------------------------------------------

## Pin the drop sequence (the harness's determinism lever; live
## runs reseed per run in start_run).
func reseed_drop_rng(p_seed: int) -> void:
	_drop_rng.seed = p_seed


## Uniform roll over the four powerup types, from the drop RNG.
func roll_powerup_type() -> String:
	var ids: Array[String] = PowerupDefs.type_ids()
	return ids[_drop_rng.randi_range(0, ids.size() - 1)]


## Put a drop on the field at `at`, drifting slowly off the point.
func spawn_powerup_drop(at: Vector2, type_id: String) -> Powerup:
	var pk: Powerup = Powerup.new()
	add_child(pk)
	var drift: Vector2 = Vector2.from_angle(_drop_rng.randf() * TAU) \
		* _drop_rng.randf_range(Tuning.POWERUP_DRIFT_MIN,
			Tuning.POWERUP_DRIFT_MAX)
	pk.setup(at, type_id, drift)
	pickups.append(pk)
	return pk


## The random drop on a pirate kill: 12%, and ONLY while no
## uncollected pickup sits on the field — one at a time, so a
## drop is an event, not litter.
func _maybe_roll_powerup_drop(at: Vector2) -> void:
	if not pickups.is_empty():
		return
	if _drop_rng.randf() < Tuning.POWERUP_DROP_CHANCE:
		spawn_powerup_drop(at, roll_powerup_type())


## Collection: the pickup REPLACES whatever powerup is running
## (fresh full timer, in the Player's own state), announced by a
## popup naming it, a light burst in its colour, and the pickup
## note — recovery_small lifted a pitch-step so it reads as
## "module gained", not as a small canister deposit.
func collect_powerup(pk: Powerup) -> void:
	var at: Vector2 = pk.global_position
	var type_id: String = pk.type_id
	player.activate_powerup(type_id)
	var col: Color = PowerupDefs.color_of(type_id)
	spawn_popup(at, PowerupDefs.name_of(type_id), col)
	fx.burst(at, col, LightFx.Size.SPARK)
	sfx.play("recovery_small", at, 1.3)


## A wrestle latch lands on the player's tow (contested tow):
## one announcement at the canister, in the pirate's own colour,
## through the ordinary popup path.
func _on_pirate_wrestle_started(c: Canister, p: Pirate) -> void:
	spawn_popup(c.global_position, "CONTESTED!", p.draw_color)


## Reshape beats (M7): a spark burst at the pirate on every
## stage, and the mechanical clunk when the claw locks in at
## completion — the same one-shot the tow latch uses.
func _on_pirate_convert_stage(stage: int, p: Pirate) -> void:
	if not is_instance_valid(p):
		return
	fx.burst(p.global_position, p.draw_color, LightFx.Size.SPARK)
	if stage == 3:
		sfx.play("tow_latch", p.global_position)


## The conversion watcher (M7). Conversion replaces lost getters:
## a "working thief" is any pirate whose CURRENT role is thief in
## TELEGRAPH, SEEK, DRAG or WRESTLE — a natural grabber, or a
## convert that finished its reshape. While one works, no
## conversion starts.
## Two triggers, either sufficient, both gated by the cooldown
## and by nobody already reshaping (one at a time):
##   (a) dead air: a getter worked this run, none works now,
##       sustained for CONVERT_DEAD_AIR_TIME;
##   (b) the backstop: nothing has been dragged for
##       CONVERT_NO_STEAL_BACKSTOP — fires even while a thief is
##       out SEEKING and failing to latch; that failure is its
##       whole purpose.
## (The quota-spent trigger died with the wave structure in the
## restructure: there is no quota to spend. Dead air is now the
## primary trigger, and it is per-RUN — conversion may only
## replace lost getters after at least one natural thief has
## been dealt since the run started.)
## The convert is the longest-alive eligible gunner (current role
## "shooter" in SEEK or HOLD — SEEK is its entry flight, HOLD is
## its working post; both are its operational states). Hunters,
## darters and snipers are never eligible: their jobs are the
## player, and they do not change.
func _step_conversion(delta: float) -> void:
	_convert_cooldown_t = maxf(_convert_cooldown_t - delta, 0.0)
	var working_thief: bool = false
	var any_converting: bool = false
	var any_in_drag: bool = false
	for p: Pirate in pirates:
		if p.phase == Pirate.Phase.DRAG or p.phase == Pirate.Phase.WRESTLE:
			any_in_drag = true
		if p.is_converting():
			any_converting = true
		if p.current_role() == "thief" and (
				p.phase == Pirate.Phase.TELEGRAPH
				or p.phase == Pirate.Phase.SEEK
				or p.phase == Pirate.Phase.DRAG
				or p.phase == Pirate.Phase.WRESTLE):
			working_thief = true
	if working_thief:
		_run_had_thief = true
	# (a) Dead air: only counts while a field exists to convert.
	if not pirates.is_empty() and not working_thief and _run_had_thief:
		_convert_dead_air_t += delta
	else:
		_convert_dead_air_t = 0.0
	# (b) Steal progress is a canister DRAGGING, a pirate in
	# DRAG, or a wrestler on the player's tow (a steal in
	# progress against the tow itself); anything else lets the
	# backstop clock run.
	if _any_dragging() or any_in_drag:
		_convert_no_progress_t = 0.0
	else:
		_convert_no_progress_t += delta

	if _convert_cooldown_t > 0.0 or any_converting:
		return
	var triggered: bool = false
	if _convert_dead_air_t >= Tuning.CONVERT_DEAD_AIR_TIME:
		triggered = true
	if _convert_no_progress_t >= Tuning.CONVERT_NO_STEAL_BACKSTOP:
		triggered = true
	if not triggered:
		return
	var oldest: Pirate = null
	for p: Pirate in pirates:
		if p.current_role() == "shooter" and (
				p.phase == Pirate.Phase.SEEK
				or p.phase == Pirate.Phase.HOLD):
			if oldest == null or p.alive_time() > oldest.alive_time():
				oldest = p
	if oldest != null:
		oldest.begin_conversion()
		_convert_cooldown_t = Tuning.CONVERT_COOLDOWN


## Every live enemy bullet converts into a salvage shard where it
## flies. Death costs the multiplier, never the whole field state.
func _cancel_enemy_bullets() -> void:
	var now: Array[EnemyBullet] = enemy_bullets.duplicate()
	enemy_bullets.clear()
	for eb: EnemyBullet in now:
		_spawn_shards(eb.global_position, 1)
		eb.queue_free()


# --- Queries ------------------------------------------------------------------------

func canisters_remaining() -> int:
	var n: int = 0
	for c: Canister in canisters:
		if c.state != Canister.State.GONE:
			n += 1
	return n


func _any_dragging() -> bool:
	for c: Canister in canisters:
		if c.state == Canister.State.DRAGGING:
			return true
	return false


# --- Main loops ------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == GameState.RUNNING:
		paused = not paused
		_sync_hud()
		return
	if event.is_action_pressed("fire"):
		if state == GameState.TITLE or state == GameState.GAMEOVER:
			start_run()


func _process(delta: float) -> void:
	if not paused:
		fx.advance(delta)
		_step_debris(delta)
		_step_popups(delta)
	if state == GameState.RUNNING and music != null:
		music.set_rank(rank) # the soundtrack hears the pressure
	_sync_hud()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state != GameState.RUNNING or paused:
		return
	run_time += delta
	_step_score(delta)

	# Player, including the respawn beat.
	player.step(delta, true)
	if not player.alive and player.respawn_t <= 0.0:
		player.respawn(_safe_respawn_pos())

	# Spawning. The director gates its deals on how many of each
	# class are alive right now (the class alive caps), the run
	# clock drives its escalation, and Rank breathes on top.
	var class_alive: Dictionary = {}
	for hp: Pirate in pirates:
		class_alive[hp.type_name] = int(class_alive.get(hp.type_name, 0)) + 1
	director.step(delta, pirates.size(), player.global_position, rank,
		class_alive, run_time)

	# Pirates, then the canisters they drag or trail. Each pirate
	# gets its per-frame context first: where the player is, whether
	# it is up, and the rank scaling for its speed and fire rate.
	var pirates_now: Array[Pirate] = pirates.duplicate()
	for p: Pirate in pirates_now:
		p.player_pos = player.global_position
		p.player_vel = player.velocity
		p.player_alive = player.alive
		p.speed_scale = Tuning.rank_speed_mult(rank)
		p.fire_interval_scale = Tuning.rank_fire_mult(rank)
		p.step(delta, canisters)
	_resolve_steals_and_leavers()
	_step_conversion(delta)

	# Towed canister trails the ship before canister physics runs.
	if player.towed != null and is_instance_valid(player.towed) \
			and player.towed.state == Canister.State.TOWED:
		var c: Canister = player.towed
		var trail: Vector2 = player.global_position \
			- player.facing * Tuning.TOW_TRAIL_DIST
		var blend: float = clampf(Tuning.TOW_FOLLOW_RATE * delta, 0.0, 1.0)
		c.global_position = c.global_position.lerp(trail, blend)
		# CONTESTED TOW: every wrestler hauls on the canister
		# toward its own exit at its drag strength (scaled) —
		# a constant bias against the tow's exponential follow,
		# so the pair strains off the clean trail line while the
		# player keeps control. This step is the canister's only
		# position writer while TOWED; the wrestlers just hang on.
		for wv: Node2D in c.wrestlers:
			if wv is Pirate and is_instance_valid(wv):
				var w: Pirate = wv as Pirate
				var pull: Vector2 = w.exit_point - c.global_position
				if pull.length() > 1.0:
					c.global_position += pull.normalized() \
						* w.drag_speed() * Tuning.WRESTLE_PULL_SCALE * delta
	for c: Canister in canisters:
		c.step(delta)

	# Bullets fly and hit.
	var bullets_now: Array[Bullet] = bullets.duplicate()
	for b: Bullet in bullets_now:
		b.step(delta)
		if b.expired():
			bullets.erase(b)
			b.queue_free()
			continue
		var hit: Pirate = _bullet_hit(b)
		if hit != null:
			bullets.erase(b)
			b.queue_free()
			kill_pirate(hit, true)

	_step_enemy_bullets(delta)

	_resolve_player_contact()
	_resolve_buzz_passes()
	_resolve_tow_and_deposit()

	# Shards drift, magnet and get collected.
	var shards_now: Array[Shard] = shards.duplicate()
	for s: Shard in shards_now:
		s.step(delta, player.global_position, player.alive)
		if s.expired():
			shards.erase(s)
			s.queue_free()
		elif player.alive and s.global_position.distance_to(
				player.global_position) <= Tuning.SHARD_COLLECT_RADIUS:
			shards.erase(s)
			s.queue_free()
			collect_shard()

	# Powerup drops drift and expire; flying over one collects it.
	var pickups_now: Array[Powerup] = pickups.duplicate()
	for pk: Powerup in pickups_now:
		pk.step(delta)
		if pk.expired():
			pickups.erase(pk)
			pk.queue_free()
		elif player.alive and pk.global_position.distance_to(
				player.global_position) <= Tuning.POWERUP_PICKUP_RADIUS:
			pickups.erase(pk)
			collect_powerup(pk)
			pk.queue_free()

	# The run's only ending: the last canister is gone.
	if canisters_remaining() <= 0:
		_game_over()
	queue_redraw()


## Enemy bullets fly, hit (a hit is a death, via the M1 flow) and
## graze. The hit test judges the ship's HOTSPOT, not its hull
## (the danmaku split): a bullet only kills inside
## ENEMY_BULLET_RADIUS + PLAYER_HOTSPOT_RADIUS of the centre.
## A graze inside BUZZ_RADIUS that does not hit pays buzz —
## once per bullet, however long it stays in the ring.
func _step_enemy_bullets(delta: float) -> void:
	var now: Array[EnemyBullet] = enemy_bullets.duplicate()
	for eb: EnemyBullet in now:
		if not is_instance_valid(eb):
			continue # a death this frame may have cancelled the rest
		eb.step(delta)
		if eb.expired():
			enemy_bullets.erase(eb)
			eb.queue_free()
			continue
		if not player.alive:
			continue
		var d: float = eb.global_position.distance_to(player.global_position)
		if not player.is_invincible() \
				and d <= Tuning.ENEMY_BULLET_RADIUS \
					+ Tuning.PLAYER_HOTSPOT_RADIUS:
			enemy_bullets.erase(eb)
			eb.queue_free()
			kill_player() # converts every other live bullet to shards
		elif not eb.buzzed and d <= Tuning.BUZZ_RADIUS:
			eb.buzzed = true
			_award_buzz(eb.global_position)


## The other buzz: a close pass on a pirate mid-drag, without
## contact. The window is relative to the contact range (body +
## pirate radius): closer than contact + BUZZ_PASS_MARGIN but
## not touching. Once per pirate per drag — the flag resets on
## latch.
func _resolve_buzz_passes() -> void:
	if not player.alive:
		return
	var now: Array[Pirate] = pirates.duplicate()
	for p: Pirate in now:
		if p.phase != Pirate.Phase.DRAG or p.held == null \
				or p.buzzed_this_drag:
			continue
		var d: float = p.global_position.distance_to(player.global_position)
		var contact_sum: float = Tuning.PLAYER_RADIUS + p.radius
		if d > contact_sum and d <= contact_sum + Tuning.BUZZ_PASS_MARGIN:
			p.buzzed_this_drag = true
			_award_buzz(p.global_position)


func _bullet_hit(b: Bullet) -> Pirate:
	for p: Pirate in pirates:
		if p.phase == Pirate.Phase.TELEGRAPH:
			continue # not in the arena yet; cannot be shot mid-telegraph
		if b.global_position.distance_to(p.global_position) \
				<= p.radius + Tuning.BULLET_RADIUS:
			return p
	return null


func _resolve_player_contact() -> void:
	if not player.alive or player.is_invincible():
		return
	var contact: Array[Pirate] = pirates.duplicate()
	for p: Pirate in contact:
		if p.phase == Pirate.Phase.TELEGRAPH:
			continue
		if p.global_position.distance_to(player.global_position) \
				<= p.radius + Tuning.PLAYER_RADIUS:
			if player.speed_now() >= Tuning.RAM_SPEED_THRESHOLD:
				kill_pirate(p, true) # ram: pirate dies, player flies on
			else:
				kill_player()
				return
	if not player.alive:
		return


func _resolve_tow_and_deposit() -> void:
	if not player.alive:
		return
	if player.towed == null:
		for c: Canister in canisters:
			if c.state == Canister.State.LOOSE and not c.is_slotting() \
					and c.global_position.distance_to(player.global_position) \
						<= Tuning.TOW_LATCH_DIST:
				if c.begin_tow(player):
					player.towed = c
					sfx.play("tow_latch", c.global_position)
				break
	elif is_instance_valid(player.towed):
		var c: Canister = player.towed
		if c.state != Canister.State.TOWED:
			player.towed = null
		elif c.global_position.distance_to(Tuning.depot_center()) \
				<= Tuning.DEPOT_RADIUS:
			# Deposit: any wrestlers let go (the canister is home;
			# they retarget through plain SEEK), the distance-
			# scaled bonus pays, and it glides into its berth.
			var wrestlers_now: Array[Node2D] = c.wrestlers.duplicate()
			for wv2: Node2D in wrestlers_now:
				if wv2 is Pirate and is_instance_valid(wv2):
					(wv2 as Pirate).detach_wrestle()
			var base_pts: int = recovery_base_points(c.tow_start_pos)
			var paid: int = add_score(base_pts)
			sfx.play_recovery(c.global_position, base_pts)
			_add_rank(Tuning.RANK_GAIN_RECOVERY)
			spawn_popup(c.global_position, "+%d" % paid,
				Tuning.COLOR_CANISTER)
			fx.burst(c.global_position, Tuning.COLOR_CANISTER,
				LightFx.Size.SPARK)
			c.begin_slot_glide()
			player.towed = null


func _resolve_steals_and_leavers() -> void:
	var grown: Rect2 = Tuning.arena_rect().grow(Tuning.EXIT_MARGIN)
	var now: Array[Pirate] = pirates.duplicate()
	for p: Pirate in now:
		if p.held != null and is_instance_valid(p.held) \
				and p.held.state == Canister.State.DRAGGING \
				and not grown.has_point(p.held.global_position):
			var stolen: Canister = p.held
			p.held = null
			p.phase = Pirate.Phase.LEAVE
			p.exit_point = Tuning.nearest_exit_point(p.global_position)
			_steal_canister(stolen)
		if p.phase == Pirate.Phase.LEAVE:
			var past_boundary: bool = not grown.grow(50.0).has_point(
				p.global_position)
			# Exit watchdog: whatever went wrong out there, a leaver
			# older than the Tuning limit is freed on the spot — no
			# pirate may ever park and hold a run hostage.
			var timed_out: bool = p.exit_age >= Tuning.EXIT_WATCHDOG_TIME
			if past_boundary or timed_out:
				if timed_out and not past_boundary:
					fx.burst(Tuning.clamp_inside(p.global_position, 2.0),
						p.draw_color, LightFx.Size.SPARK)
				pirates.erase(p)
				p.queue_free()


func _safe_respawn_pos() -> Vector2:
	var candidates: Array[Vector2] = [
		_player_spawn_pos(),
		Tuning.depot_center() + Vector2(-260.0, 195.0),
		Tuning.depot_center() + Vector2(260.0, 195.0),
		Tuning.depot_center() + Vector2(0.0, -195.0)]
	var best: Vector2 = candidates[0]
	var best_d: float = -1.0
	for cand: Vector2 in candidates:
		var nearest: float = INF
		for p: Pirate in pirates:
			nearest = minf(nearest, cand.distance_to(p.global_position))
		if nearest > best_d:
			best_d = nearest
			best = cand
	return best


# --- Debris (shrapnel lines) ----------------------------------------------------------

func _step_debris(delta: float) -> void:
	for i: int in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		var t: float = float(d["t"]) + delta
		if t >= float(d["dur"]):
			_debris.remove_at(i)
		else:
			d["t"] = t
			var pos: Vector2 = d["pos"] as Vector2
			var vel: Vector2 = d["vel"] as Vector2
			d["pos"] = pos + vel * delta
			_debris[i] = d


# --- Save / load ------------------------------------------------------------------------

func _load_best() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		var data: Dictionary = parsed as Dictionary
		best_score = int(data.get(SAVE_BEST_SCORE, 0))
		best_time = float(data.get(SAVE_BEST_TIME, 0.0))


func _save_best() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		SAVE_BEST_SCORE: best_score, SAVE_BEST_TIME: best_time}))


# --- HUD sync and arena drawing ------------------------------------------------------------

func _sync_hud() -> void:
	if hud == null:
		return
	hud.score = score
	hud.multiplier = multiplier
	hud.grace_frac = clampf(mult_grace_t / Tuning.MULT_GRACE, 0.0, 1.0)
	hud.rank = rank
	hud.rank_floor = Tuning.rank_floor_at(run_time)
	hud.run_time = run_time
	hud.canisters_left = canisters_remaining()
	hud.best_score = best_score
	hud.best_time = best_time
	hud.mode = int(state)
	hud.paused = paused
	# Powerup chip: the active powerup's id, name, colour and
	# remaining-timer fraction, fed from the Player's state.
	hud.powerup_id = player.powerup_id
	if player.powerup_id != "":
		hud.powerup_name = PowerupDefs.name_of(player.powerup_id)
		hud.powerup_color = PowerupDefs.color_of(player.powerup_id)
		hud.powerup_frac = player.powerup_fraction()
	else:
		hud.powerup_frac = 0.0
	hud.queue_redraw()


func _draw() -> void:
	# Arena border.
	var r: Rect2 = Tuning.arena_rect()
	var border: PackedVector2Array = PackedVector2Array([
		r.position, r.position + Vector2(r.size.x, 0.0),
		r.position + r.size, r.position + Vector2(0.0, r.size.y),
		r.position])
	draw_polyline(border, Tuning.COLOR_ARENA, 2.0, true)
	# Depot ring and slot cradles.
	var center: Vector2 = Tuning.depot_center()
	draw_arc(center, Tuning.DEPOT_RADIUS, 0.0, TAU, 72,
		Color(Tuning.COLOR_DEPOT, 0.35), 1.5, true)
	for i: int in range(Tuning.SLOT_COUNT):
		var slot_pos: Vector2 = Tuning.slot_position(i)
		var filled: bool = false
		for c: Canister in canisters:
			if c.slot_index == i and c.state == Canister.State.IN_SLOT:
				filled = true
				break
		var col: Color = Tuning.COLOR_CRADLE_LIT if filled \
			else Tuning.COLOR_CRADLE_DIM
		draw_arc(slot_pos, 16.0, 0.0, TAU, 24, col, 2.0, true)
	# Tethers for held canisters.
	for c: Canister in canisters:
		if (c.state == Canister.State.DRAGGING
				or c.state == Canister.State.TOWED) \
				and c.holder != null and is_instance_valid(c.holder):
			draw_line(c.holder.global_position, c.global_position,
				Color(Tuning.COLOR_CANISTER, 0.55), 1.5, true)
		# Wrestler tethers (contested tow): the same line, from
		# each pirate hanging on a towed canister to the canister.
		for wv3: Node2D in c.wrestlers:
			if is_instance_valid(wv3):
				draw_line(wv3.global_position, c.global_position,
					Color(Tuning.COLOR_CANISTER, 0.55), 1.5, true)
	# Shrapnel.
	for d: Dictionary in _debris:
		var frac: float = float(d["t"]) / float(d["dur"])
		var col: Color = Color(d["color"] as Color, 1.0 - frac)
		var pos: Vector2 = d["pos"] as Vector2
		var vel: Vector2 = d["vel"] as Vector2
		draw_line(pos, pos + vel.normalized() * 9.0, col, 2.0, true)
	# Floating score popups (buzz, recovery bonuses).
	if _font != null:
		for pop: Dictionary in _popups:
			var frac: float = float(pop["t"]) / float(pop["dur"])
			var base_col: Color = pop["color"] as Color
			var col: Color = Color(base_col, 1.0 - frac)
			var pos: Vector2 = pop["pos"] as Vector2
			draw_string(_font, pos - Vector2(60.0, 0.0),
				String(pop["text"]), HORIZONTAL_ALIGNMENT_CENTER,
				120.0, 15, col)
