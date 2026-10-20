class_name EnemyDefs
extends RefCounted
## Enemy definitions AS DATA. One dictionary per type: movement,
## scoring and look. Pirate behaviour reads its numbers from here,
## so a new class is a new dictionary entry, not new code.
## M1 shipped the grabber; M2 adds the gunner through this system;
## M6 adds the hunter, the direct-challenge class.

const DEFS: Dictionary = {
	"grabber": {
		"speed": 140.0, # approach speed while hunting a canister
		"drag_speed": 92.0, # escape speed while dragging one
		"score": 100, # base kill points (before multiplier)
		"shards": 4, # salvage shards burst on death
		"radius": 13.0,
		"color": Color(1.0, 0.38, 0.3, 1.0), # coral red
		"role": "thief",
	},
	"gunner": {
		"speed": 165.0, # entry speed while flying to its standoff point
		"score": 150, # base kill points (before multiplier)
		"shards": 4, # salvage shards burst on death
		"radius": 13.0,
		"color": Color(0.66, 0.42, 1.0, 1.0), # violet
		"role": "shooter",
		"fire_interval": 2.2, # seconds between shots at rank 0 (rank scales it)
		"standoff_min": 260.0, # preferred range band from the depot centre
		"standoff_max": 340.0,
		"strafe_speed": 55.0, # tangential drift while holding the band
	},
	"hunter": {
		"speed": 215.0, # pursuit speed: closes on the player, then orbits
		"score": 175, # base kill points (before multiplier)
		"shards": 5, # salvage shards burst on death
		"radius": 13.0,
		"color": Color(1.0, 0.62, 0.15, 1.0), # hunter orange (the Rip-Off 2 hunter)
		"role": "hunter",
		"fire_interval": 2.6, # seconds between shots at rank 0 (rank scales it)
	},
}


static func get_def(type_name: String) -> Dictionary:
	var raw: Variant = DEFS.get(type_name, {})
	if typeof(raw) == TYPE_DICTIONARY:
		return (raw as Dictionary).duplicate()
	return {}


static func has_def(type_name: String) -> bool:
	return DEFS.has(type_name)


static func type_names() -> Array[String]:
	var out: Array[String] = []
	var keys: Array = DEFS.keys()
	for k: Variant in keys:
		out.append(String(k))
	return out
