class_name PowerupDefs
extends RefCounted
## Powerup definitions AS DATA (the enemy_defs.gd pattern), plus
## the ONE glyph-drawing implementation. The same glyph, in the
## same colour, is drawn by the field pickup (powerup.gd), the
## HUD chip and the title-screen legend — all three call
## draw_glyph() here, so the symbol a player learns in the field
## is the symbol on the HUD and in the legend, never a copy.

const IDS: Array[String] = ["rapid", "spread", "overthrust", "shield"]

const DEFS: Dictionary = {
	"rapid": {
		"name": "RAPID FIRE",
		"duration": Tuning.POWERUP_RAPID_DURATION,
		"color": Tuning.COLOR_POWERUP_RAPID,
	},
	"spread": {
		"name": "SPREAD",
		"duration": Tuning.POWERUP_SPREAD_DURATION,
		"color": Tuning.COLOR_POWERUP_SPREAD,
	},
	"overthrust": {
		"name": "OVERTHRUST",
		"duration": Tuning.POWERUP_OVERTHRUST_DURATION,
		"color": Tuning.COLOR_POWERUP_OVERTHRUST,
	},
	"shield": {
		"name": "SHIELD",
		"duration": Tuning.POWERUP_SHIELD_DURATION,
		"color": Tuning.COLOR_POWERUP_SHIELD,
	},
}


static func get_def(type_id: String) -> Dictionary:
	var raw: Variant = DEFS.get(type_id, {})
	if typeof(raw) == TYPE_DICTIONARY:
		return (raw as Dictionary).duplicate()
	return {}


static func has_def(type_id: String) -> bool:
	return DEFS.has(type_id)


static func type_ids() -> Array[String]:
	return IDS.duplicate()


static func name_of(type_id: String) -> String:
	return String(get_def(type_id).get("name", ""))


static func duration_of(type_id: String) -> float:
	return float(get_def(type_id).get("duration", 0.0))


static func color_of(type_id: String) -> Color:
	var c: Variant = get_def(type_id).get("color", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		return c as Color
	return Color.WHITE


## Draw `type_id`'s glyph centred on `center`, scaled by `scl`
## (glyphs are drawn on a ~20px unit box). Called from _draw()
## contexts only — `on` is the CanvasItem doing the drawing.
static func draw_glyph(on: CanvasItem, type_id: String,
		center: Vector2, scl: float) -> void:
	var col: Color = color_of(type_id)
	match type_id:
		"rapid":
			# Lightning bolt: a closed zig-zag outline.
			var bolt: PackedVector2Array = PackedVector2Array([
				center + Vector2(3.0, -10.0) * scl,
				center + Vector2(-4.5, 1.5) * scl,
				center + Vector2(-0.5, 1.5) * scl,
				center + Vector2(-3.0, 10.0) * scl,
				center + Vector2(4.5, -1.5) * scl,
				center + Vector2(0.5, -1.5) * scl,
				center + Vector2(3.0, -10.0) * scl])
			on.draw_polyline(bolt, col, 2.0, true)
		"spread":
			# Triple fan: three rays out of one hub (the glyph
			# fans wider than the real +/-0.15 rad — a symbol,
			# not a scale drawing).
			var hub: Vector2 = center + Vector2(0.0, 7.0) * scl
			for a: float in [-0.55, 0.0, 0.55]:
				var tip: Vector2 = hub \
					+ Vector2(sin(a), -cos(a)) * 15.0 * scl
				on.draw_line(hub, tip, col, 2.0, true)
				on.draw_circle(tip, 1.6 * scl, col)
			on.draw_circle(hub, 2.0 * scl, col)
		"overthrust":
			# Double chevron pointing up: boost, stacked.
			for dy: float in [-3.5, 3.5]:
				var chev: PackedVector2Array = PackedVector2Array([
					center + Vector2(-6.5, dy + 3.5) * scl,
					center + Vector2(0.0, dy - 3.5) * scl,
					center + Vector2(6.5, dy + 3.5) * scl])
				on.draw_polyline(chev, col, 2.0, true)
		"shield":
			# Hexagon with a core dot: a shell around the ship.
			var hex: PackedVector2Array = PackedVector2Array()
			for i: int in range(7):
				var a: float = TAU * float(i % 6) / 6.0 - PI * 0.5
				hex.append(center + Vector2.from_angle(a) * 9.0 * scl)
			on.draw_polyline(hex, col, 2.0, true)
			on.draw_circle(center, 2.0 * scl, col)
