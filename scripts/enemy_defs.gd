class_name EnemyDefs
extends RefCounted
## Enemy definitions AS DATA. One dictionary per type: movement,
## scoring and look. Pirate behaviour reads its numbers from here,
## so a new class is a new dictionary entry, not new code.
## M1 ships exactly one type: the grabber.

const DEFS: Dictionary = {
	"grabber": {
		"speed": 125.0, # approach speed while hunting a canister
		"drag_speed": 92.0, # escape speed while dragging one
		"score": 100, # base kill points (before multiplier)
		"shards": 4, # salvage shards burst on death
		"radius": 13.0,
		"color": Color(1.0, 0.38, 0.3, 1.0), # coral red
		"role": "thief",
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
