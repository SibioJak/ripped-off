class_name MusicDirector
extends Node
## The trance soundtrack as layered loops, arranged live by rank.
##
## Every stem is an OGG loop rendered by tools/render_audio.py on one
## shared beat grid (134 BPM) at differing lengths — 16 / 12 / 10 /
## 32 beats — so the layers phase against each other (polyrhythm)
## while never drifting apart. All players start together at boot
## and run continuously; a layer is "in" purely by its volume, so
## phasing can never be lost by a late start.
##
## Rank layering (the core hook): kick + bass are always in during a
## run; pad joins at rank 0.25, hats + perc figure at 0.45, the arp
## at 0.60, clap drive at 0.80. Crossfades are volume only (~1.5 s),
## never effects — the music itself is never processed at runtime.
##
## Complex pattern work: bass and arp each have a 3-variant bank
## (A/B/C, same lengths and roots, different patterns). At every
## second drum-loop boundary the director advances a seeded rotation
## that swaps which variant is audible, so the pattern bank keeps
## recombining instead of sitting static.

enum Mode { TITLE, RUN }

const SILENT_DB: float = -60.0
const FADE_TAU: float = 0.5 # exponential fade constant; ~95% in 1.5 s
const ROTATE_EVERY_WRAPS: int = 2 # variant rotation per N drum loops

const MUSIC_DIR: String = "res://audio/music/"

# Layer table: name -> threshold (rank at which it joins a run),
# gain (its volume_db when in), files (1 = fixed, 3 = variant bank).
const LAYER_DEFS: Dictionary = {
	"title": {"threshold": -1.0, "gain": -3.0, "files": ["music_title.ogg"]},
	"kick": {"threshold": 0.0, "gain": 0.0, "files": ["music_kick.ogg"]},
	"bass": {"threshold": 0.0, "gain": -2.0,
		"files": ["music_bass_a.ogg", "music_bass_b.ogg", "music_bass_c.ogg"]},
	"pad": {"threshold": 0.25, "gain": -8.0, "files": ["music_pad.ogg"]},
	"hats": {"threshold": 0.45, "gain": -5.0, "files": ["music_hats.ogg"]},
	"perc": {"threshold": 0.45, "gain": -7.0, "files": ["music_perc.ogg"]},
	"arp": {"threshold": 0.60, "gain": -6.0,
		"files": ["music_arp_a.ogg", "music_arp_b.ogg", "music_arp_c.ogg"]},
	"drive": {"threshold": 0.80, "gain": -4.0, "files": ["music_drive.ogg"]},
}
const VARIANT_LAYERS: Array[String] = ["bass", "arp"]

var mode: Mode = Mode.TITLE
var rank: float = 0.0

var _layers: Dictionary = {} # name -> Array[AudioStreamPlayer]
var _active_variant: Dictionary = {"bass": 0, "arp": 0}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wrap_count: int = 0
var _last_kick_pos: float = 0.0


func _ready() -> void:
	AudioBuses.ensure()
	_rng.seed = 20261018
	var names: Array = LAYER_DEFS.keys()
	for layer_name: Variant in names:
		var name_str: String = String(layer_name)
		var def: Dictionary = LAYER_DEFS[layer_name] as Dictionary
		var files: Array = def["files"] as Array
		var players: Array[AudioStreamPlayer] = []
		for file_name: Variant in files:
			players.append(_make_player(MUSIC_DIR + String(file_name)))
		_layers[name_str] = players
	_snap_volumes() # boot state (TITLE) applies instantly, no fade-in


func _make_player(path: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	var stream: AudioStream = load(path) as AudioStream
	var ogg: AudioStreamOggVorbis = stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = true # seamless stem loops, set on the resource
	p.stream = stream
	p.bus = AudioBuses.MUSIC_BUS
	p.volume_db = SILENT_DB
	p.pitch_scale = 1.0 # never touched again: no DJ effects on music
	add_child(p)
	p.play()
	return p


# --- State from Main -------------------------------------------------

func set_mode_title() -> void:
	mode = Mode.TITLE


func set_mode_run() -> void:
	mode = Mode.RUN


## A run starts: title loop yields, stems take over from rank, and
## the variant rotation reseeds deterministically for this run.
func begin_run(run_seed: int) -> void:
	mode = Mode.RUN
	_rng.seed = run_seed
	_wrap_count = 0
	_active_variant["bass"] = 0
	_active_variant["arp"] = 0


func set_rank(value: float) -> void:
	rank = clampf(value, 0.0, 1.0)


# --- Targets (the director's whole decision, readable by tests) ------

## What this layer's audible player should sit at right now.
func layer_target_db(layer_name: String) -> float:
	if layer_name == "title":
		return _layer_gain("title") if mode == Mode.TITLE else SILENT_DB
	if mode != Mode.RUN or not _layers.has(layer_name):
		return SILENT_DB
	var def: Dictionary = LAYER_DEFS[layer_name] as Dictionary
	var threshold: float = float(def["threshold"])
	return _layer_gain(layer_name) if rank >= threshold else SILENT_DB


## Per-player target: for a variant bank, only the active variant
## may be audible; the others ride silent but stay phase-locked.
func variant_target_db(layer_name: String, variant_idx: int) -> float:
	if variant_idx != active_variant(layer_name):
		return SILENT_DB
	return layer_target_db(layer_name)


func active_variant(layer_name: String) -> int:
	return int(_active_variant.get(layer_name, 0))


func _layer_gain(layer_name: String) -> float:
	var def: Dictionary = LAYER_DEFS[layer_name] as Dictionary
	return float(def["gain"])


func all_players() -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	var names: Array = _layers.keys()
	for layer_name: Variant in names:
		var players: Array = _layers[layer_name] as Array
		for p: Variant in players:
			out.append(p as AudioStreamPlayer)
	return out


# --- Rotation ----------------------------------------------------------

## Advance the pattern bank: each variant layer moves to a different
## variant (seeded; never stays put). Called on drum-loop boundaries
## in game, and directly by the test harness.
func advance_rotation() -> void:
	for layer_name: String in VARIANT_LAYERS:
		var players: Array = _layers[layer_name] as Array
		if players.size() < 2:
			continue
		var current: int = active_variant(layer_name)
		var next: int = _rng.randi_range(0, players.size() - 2)
		if next >= current:
			next += 1 # skip the current one: rotation always moves
		_active_variant[layer_name] = next


# --- Per-frame --------------------------------------------------------

func _process(delta: float) -> void:
	var fade: float = 1.0 - exp(-delta / FADE_TAU)
	var names: Array = _layers.keys()
	for layer_name: Variant in names:
		var name_str: String = String(layer_name)
		var players: Array = _layers[name_str] as Array
		for idx: int in range(players.size()):
			var p: AudioStreamPlayer = players[idx] as AudioStreamPlayer
			var target: float = variant_target_db(name_str, idx)
			p.volume_db = lerpf(p.volume_db, target, fade)
	_track_loop_boundary()


## The kick stem is the drum grid: when its playback position wraps,
## a drum loop has completed. (Under the headless dummy audio driver
## the position never advances; rotation then simply never fires,
## and the harness drives advance_rotation() directly.)
func _track_loop_boundary() -> void:
	if mode != Mode.RUN:
		return
	var kick_players: Array = _layers["kick"] as Array
	var kick: AudioStreamPlayer = kick_players[0] as AudioStreamPlayer
	var pos: float = kick.get_playback_position()
	if pos < _last_kick_pos - 0.1:
		_wrap_count += 1
		if _wrap_count % ROTATE_EVERY_WRAPS == 0:
			advance_rotation()
	_last_kick_pos = pos


func _snap_volumes() -> void:
	var names: Array = _layers.keys()
	for layer_name: Variant in names:
		var name_str: String = String(layer_name)
		var players: Array = _layers[name_str] as Array
		for idx: int in range(players.size()):
			var p: AudioStreamPlayer = players[idx] as AudioStreamPlayer
			p.volume_db = variant_target_db(name_str, idx)
