class_name AudioBuses
extends RefCounted
## The audio bus layout, created in code at startup so it lives in
## source (no default_bus_layout.tres to drift). Master -> Music
## and Master -> SFX. Music sits at -6 dB under master by default;
## SFX at unity. Runtime never puts effects on the Music bus —
## Chris's rule: music tracks are never DJ-effected; the soundtrack's
## layering is arrangement by fades only, done in MusicDirector.

const MUSIC_BUS: String = "Music"
const SFX_BUS: String = "SFX"
const MUSIC_BUS_DB: float = -6.0


static func ensure() -> void:
	_ensure_bus(MUSIC_BUS, MUSIC_BUS_DB)
	_ensure_bus(SFX_BUS, 0.0)


static func _ensure_bus(bus_name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return # already there: idempotent, never stomp twice
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, volume_db)
