class_name SfxDirector
extends Node2D
## One-shot sound effects, all synthesized by tools/render_audio.py.
##
## Doctrine (from the design doc): crisp and never fatiguing;
## PER-CLASS death pops (the audio twin of per-class ammo colours);
## pitch variance of +/-4% on one-shots only, applied here at play
## time — music players are never pitch-touched; positional panning
## by event location (AudioStreamPlayer2D with attenuation off, so a
## sound pans across the arena but never vanishes at the edges);
## collection audio scales with the haul.
##
## A small round-robin pool keeps simultaneous sounds bounded. The
## shot gets its own discipline (Chris's M3 ear verdict: a firing
## sound "basically becomes part of the soundtrack — it's just
## prevalent"): it throttles harder (100 ms minimum interval, max 2
## concurrent), plays ~-7 dB under the other one-shots, and varies
## pitch by only +/-2%, so autofire reads as texture in the mix
## instead of a stack of zaps on top of it.
##
## Note: "hit_tick" is rendered and loaded, deliberately unwired —
## every current target dies in one hit, so there is no sustained-
## fire confirm to tick yet. It is the reserved hook for the first
## armoured target.

const POOL_SIZE: int = 24
const SHOT_MIN_INTERVAL_MS: int = 100
const SHOT_MAX_CONCURRENT: int = 2
const SHOT_VOLUME_DB: float = -7.0 # shot sits IN the mix, not on top
const SHOT_PITCH_SPREAD: float = 0.02 # narrower than the usual +/-4%
const COLLECT_RESET_MS: int = 800 # combo ladder resets after this quiet
const COLLECT_STEP_SEMITONES: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
const RECOVERY_MID_MIN: int = 250 # deposit base points -> mid sound
const RECOVERY_LARGE_MIN: int = 425 # deposit base points -> large sound

const STREAM_PATHS: Dictionary = {
	"shot": "res://audio/sfx/shot.wav",
	"death_grabber": "res://audio/sfx/death_grabber.wav",
	"death_gunner": "res://audio/sfx/death_gunner.wav",
	"hit_tick": "res://audio/sfx/hit_tick.wav",
	"shard_collect": "res://audio/sfx/shard_collect.wav",
	"recovery_small": "res://audio/sfx/recovery_small.wav",
	"recovery_mid": "res://audio/sfx/recovery_mid.wav",
	"recovery_large": "res://audio/sfx/recovery_large.wav",
	"buzz": "res://audio/sfx/buzz.wav",
	"tow_latch": "res://audio/sfx/tow_latch.wav",
	"canister_stolen": "res://audio/sfx/canister_stolen.wav",
	"player_death": "res://audio/sfx/player_death.wav",
	"wave_start": "res://audio/sfx/wave_start.wav",
	"game_over": "res://audio/sfx/game_over.wav",
	"ui_start": "res://audio/sfx/ui_start.wav",
}

var _pool: Array[AudioStreamPlayer2D] = []
var _streams: Dictionary = {} # name -> AudioStream
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next: int = 0
var _last_shot_ms: int = -100000
var _collect_step: int = 0
var _collect_last_ms: int = -100000


func _ready() -> void:
	AudioBuses.ensure()
	_rng.randomize()
	var names: Array = STREAM_PATHS.keys()
	for sound_name: Variant in names:
		var path: String = String(STREAM_PATHS[sound_name])
		_streams[String(sound_name)] = load(path) as AudioStream
	for i: int in range(POOL_SIZE):
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.bus = AudioBuses.SFX_BUS
		p.attenuation = 0.0 # pan by position, never fade with distance
		p.max_distance = 4000.0
		add_child(p)
		_pool.append(p)


## Play a one-shot at a world position. Returns the pool player used
## (null when throttled or unknown) — the harness inspects it.
func play(sound_name: String, pos: Vector2, base_pitch: float = 1.0,
		volume_db: float = 0.0) -> AudioStreamPlayer2D:
	if not _streams.has(sound_name):
		return null
	var vol: float = volume_db
	var spread: float = 0.04
	if sound_name == "shot":
		var now: int = Time.get_ticks_msec()
		if now - _last_shot_ms < SHOT_MIN_INTERVAL_MS:
			return null
		if _count_playing("shot") >= SHOT_MAX_CONCURRENT:
			return null
		_last_shot_ms = now
		vol += SHOT_VOLUME_DB
		spread = SHOT_PITCH_SPREAD
	var p: AudioStreamPlayer2D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound_name] as AudioStream
	p.global_position = pos
	p.pitch_scale = base_pitch * _rng.randf_range(1.0 - spread, 1.0 + spread)
	p.volume_db = vol
	p.play()
	return p


## Shard pickup: rapid successive collections climb a pitch ladder
## (and gain a little volume), so a haul SOUNDS like a haul. The
## ladder resets after COLLECT_RESET_MS of quiet.
func play_collect(pos: Vector2) -> AudioStreamPlayer2D:
	var now: int = Time.get_ticks_msec()
	if now - _collect_last_ms > COLLECT_RESET_MS:
		_collect_step = 0
	else:
		_collect_step = mini(_collect_step + 1,
			COLLECT_STEP_SEMITONES.size() - 1)
	_collect_last_ms = now
	var semis: int = COLLECT_STEP_SEMITONES[_collect_step]
	var base_pitch: float = pow(2.0, float(semis) / 12.0)
	var vol: float = minf(float(_collect_step) * 0.4, 3.0)
	return play("shard_collect", pos, base_pitch, vol)


## Canister deposit: the completion sound is sized by the haul —
## small single note-thud, mid two-note, large three-note figure.
func play_recovery(pos: Vector2, base_points: int) -> AudioStreamPlayer2D:
	var sound_name: String = "recovery_small"
	if base_points >= RECOVERY_LARGE_MIN:
		sound_name = "recovery_large"
	elif base_points >= RECOVERY_MID_MIN:
		sound_name = "recovery_mid"
	return play(sound_name, pos)


func pool() -> Array[AudioStreamPlayer2D]:
	return _pool


func _count_playing(sound_name: String) -> int:
	var target: AudioStream = _streams[sound_name] as AudioStream
	var n: int = 0
	for p: AudioStreamPlayer2D in _pool:
		if p.playing and p.stream == target:
			n += 1
	return n
