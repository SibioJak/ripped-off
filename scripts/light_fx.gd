class_name LightFx
extends Node2D
## Light, not shake: there is no screen shake anywhere in this
## game. Events answer with PROCEDURAL light — every burst rolls
## its recipe once at spawn (radius, peak alpha, decay shape,
## wobbly rings that are never perfect circles, optional radial
## streaks, optional delayed echo) from ranges keyed to its size
## class, so no two kills look alike while the scale still reads:
## recipe bases are spaced so rolled ranges can never invert the
## class ordering. Purely visual: nothing here moves the camera
## or any entity, ever.

enum Size { SPARK, SMALL, MEDIUM, PLAYER_DEATH }

## [base_radius, alpha_min, alpha_max, duration,
##  ring_min, ring_max, streak_chance, echo_chance]
const RECIPES: Dictionary = {
	0: [55.0, 0.25, 0.40, 0.30, 0, 1, 0.20, 0.0], # SPARK: deposits, breaks
	1: [88.0, 0.30, 0.45, 0.42, 0, 2, 0.35, 0.0], # SMALL: pirate kill
	2: [116.0, 0.40, 0.55, 0.52, 1, 2, 0.55, 0.25], # MEDIUM: depot blast
	3: [170.0, 0.55, 0.70, 0.70, 1, 2, 0.60, 0.30], # PLAYER_DEATH
}

const SHAPE_SNAP: int = 0 # fast attack, fast out
const SHAPE_BLOOM: int = 1 # slow swell, then fade
const SHAPE_LINGER: int = 2 # fast attack, long tail

var bursts: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var pending: Array[Dictionary] = []


func _ready() -> void:
	z_index = 26
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func clear() -> void:
	bursts.clear()
	rings.clear()
	edges.clear()
	pending.clear()
	queue_redraw()


func burst(at: Vector2, color: Color, size_class: int) -> void:
	_spawn_burst(at, color, size_class, 1.0, 1.0, true)


## A flash inset from the arena edges (a steal, a player death):
## peak alpha at most 0.35, sometimes with a second beat.
func edge_flash(color: Color) -> void:
	edges.append({"color": color,
		"alpha": randf_range(0.22, 0.35),
		"t": 0.0, "dur": randf_range(0.6, 0.85),
		"depth": randf_range(0.7, 1.4),
		"beat2": randf() < 0.35})
	queue_redraw()


func _spawn_burst(at: Vector2, color: Color, size_class: int,
		radius_scale: float, alpha_scale: float, allow_echo: bool) -> void:
	var r: Array = RECIPES[size_class] as Array
	var col: Color = Color.from_hsv(
		wrapf(color.h + randf_range(-0.04, 0.04), 0.0, 1.0),
		clampf(color.s * randf_range(0.92, 1.05), 0.0, 1.0),
		clampf(color.v * randf_range(0.9, 1.1), 0.0, 1.0),
		color.a)
	var radius: float = float(r[0]) * randf_range(0.75, 1.3) * radius_scale
	var alpha: float = randf_range(float(r[1]), float(r[2])) * alpha_scale
	var dur: float = float(r[3]) * randf_range(0.85, 1.2)
	var shape: int = randi_range(0, 2)
	var peak: float = 0.16
	var ea: float = 1.1
	var eb: float = 1.4
	match shape:
		SHAPE_SNAP:
			peak = randf_range(0.10, 0.16)
			ea = randf_range(0.9, 1.2)
			eb = randf_range(1.9, 2.6)
		SHAPE_BLOOM:
			peak = randf_range(0.38, 0.52)
			ea = randf_range(1.4, 1.9)
			eb = randf_range(1.0, 1.4)
		SHAPE_LINGER:
			peak = randf_range(0.15, 0.22)
			ea = randf_range(1.0, 1.4)
			eb = randf_range(0.5, 0.75)
	var streaks: Array[Dictionary] = []
	if randf() < float(r[6]):
		var n: int = randi_range(4, 10)
		for i: int in range(n):
			streaks.append({
				"ang": randf() * TAU,
				"len": randf_range(0.55, 1.1),
				"alpha": randf_range(0.18, 0.42),
				"width": randf_range(1.0, 2.0)})
	var ring_count: int = randi_range(int(r[4]), int(r[5]))
	bursts.append({
		"pos": at, "color": col, "radius": radius, "alpha": alpha,
		"t": 0.0, "dur": dur, "shape": shape, "peak": peak,
		"ea": ea, "eb": eb, "grow0": randf_range(0.4, 0.55),
		"core_frac": randf_range(0.25, 0.5),
		"streaks": streaks, "ring_count": ring_count,
		"cls": size_class})
	for i: int in range(ring_count):
		_spawn_ring(at, col, radius, dur)
	if allow_echo and randf() < float(r[7]):
		pending.append({
			"t": randf_range(0.08, 0.2),
			"pos": at + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 20.0),
			"color": color, "cls": size_class,
			"scale": randf_range(0.55, 0.75)})
	queue_redraw()


func _spawn_ring(at: Vector2, col: Color, base_radius: float, base_dur: float) -> void:
	rings.append({
		"pos": at, "color": col,
		"max_radius": base_radius * randf_range(1.0, 1.25),
		"t": 0.0, "dur": base_dur * randf_range(0.9, 1.5),
		"width": randf_range(1.0, 2.5),
		"alpha": randf_range(0.22, 0.5),
		"wob": _roll_wobble(randf_range(0.06, 0.14))})


## A closed loop of smooth radial offsets: three sine harmonics at
## random phases summing to at most `mag`, so the ring bulges and
## pinches as one continuous wobbly band — never a perfect circle.
func _roll_wobble(mag: float) -> PackedFloat32Array:
	var n: int = 28
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var a1: float = mag * randf_range(0.35, 0.55)
	var a2: float = mag * randf_range(0.15, 0.3)
	var a3: float = mag * randf_range(0.05, 0.15)
	var p1: float = randf() * TAU
	var p2: float = randf() * TAU
	var p3: float = randf() * TAU
	var k1: int = randi_range(2, 3)
	var k2: int = randi_range(3, 5)
	var k3: int = randi_range(5, 8)
	for i: int in range(n):
		var th: float = TAU * float(i) / float(n)
		out[i] = 1.0 + a1 * sin(float(k1) * th + p1) \
			+ a2 * sin(float(k2) * th + p2) \
			+ a3 * sin(float(k3) * th + p3)
	return out


func advance(delta: float) -> void:
	if bursts.is_empty() and rings.is_empty() and edges.is_empty() \
			and pending.is_empty():
		return
	for i: int in range(pending.size() - 1, -1, -1):
		var p: Dictionary = pending[i]
		var t: float = float(p["t"]) - delta
		if t <= 0.0:
			pending.remove_at(i)
			var epos: Vector2 = p["pos"] as Vector2
			var ecol: Color = p["color"] as Color
			_spawn_burst(epos, ecol, int(p["cls"]), float(p["scale"]), 0.8, false)
		else:
			p["t"] = t
			pending[i] = p
	_step(bursts, delta)
	_step(rings, delta)
	_step(edges, delta)
	queue_redraw()


func _step(list: Array[Dictionary], delta: float) -> void:
	for i: int in range(list.size() - 1, -1, -1):
		var d: Dictionary = list[i]
		var t: float = float(d["t"]) + delta
		if t >= float(d["dur"]):
			list.remove_at(i)
		else:
			d["t"] = t
			list[i] = d


func _envelope(d: Dictionary, frac: float) -> float:
	var peak: float = float(d["peak"])
	if frac < peak:
		return pow(frac / maxf(peak, 0.001), float(d["ea"]))
	return pow(1.0 - (frac - peak) / maxf(1.0 - peak, 0.001), float(d["eb"]))


func _draw() -> void:
	for d: Dictionary in bursts:
		var frac: float = clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var env: float = _envelope(d, frac)
		if env <= 0.003:
			continue
		var at: Vector2 = d["pos"] as Vector2
		var col: Color = d["color"] as Color
		var a: float = float(d["alpha"]) * env
		var gspan: float = 0.62
		if int(d["shape"]) == SHAPE_BLOOM:
			gspan = 0.88
		var gf: float = clampf(frac / gspan, 0.0, 1.0)
		gf = gf * gf * (3.0 - 2.0 * gf) # smoothstep
		var r: float = float(d["radius"]) * lerpf(float(d["grow0"]), 1.0, gf)
		# Layered discs under additive blending read as a radial gradient.
		draw_circle(at, r, Color(col, a * 0.18))
		draw_circle(at, r * 0.7, Color(col, a * 0.32))
		draw_circle(at, r * 0.48, Color(col, a * 0.5))
		var cf: float = float(d["core_frac"])
		draw_circle(at, r * cf, Color(col, a * 0.85))
		var core: Color = col.lerp(Color.WHITE, 0.78)
		draw_circle(at, r * cf * 0.55, Color(core, a))
		var streaks: Array = d["streaks"] as Array
		for sv: Variant in streaks:
			var st: Dictionary = sv as Dictionary
			var sa: float = float(st["alpha"]) * env * (1.0 - frac * 0.5)
			if sa <= 0.003:
				continue
			var dir: Vector2 = Vector2.from_angle(float(st["ang"]))
			var scol: Color = col.lerp(Color.WHITE, 0.45)
			draw_line(at + dir * r * 0.18, at + dir * r * float(st["len"]),
				Color(scol, sa), float(st["width"]), true)
	for d: Dictionary in rings:
		var frac: float = clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var ease: float = 1.0 - (1.0 - frac) * (1.0 - frac)
		var r: float = float(d["max_radius"]) * ease
		if r < 1.0:
			continue
		var at: Vector2 = d["pos"] as Vector2
		var col: Color = d["color"] as Color
		var a: float = float(d["alpha"]) * minf(frac * 5.0, 1.0) * pow(1.0 - frac, 1.1)
		if a <= 0.003:
			continue
		var wob: PackedFloat32Array = d["wob"] as PackedFloat32Array
		var n: int = wob.size()
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(n + 1)
		for i: int in range(n + 1):
			var j: int = i % n
			var th: float = TAU * float(j) / float(n)
			pts[i] = at + Vector2(cos(th), sin(th)) * r * wob[j]
		draw_polyline(pts, Color(col, a), float(d["width"]), true)
	for d: Dictionary in edges:
		var frac: float = clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var env: float = 1.0 - frac
		if bool(d["beat2"]):
			env = maxf(env, 0.8 * exp(-pow((frac - 0.5) * 5.0, 2.0)))
		var a: float = float(d["alpha"]) * env
		if a <= 0.003:
			continue
		var col: Color = d["color"] as Color
		var depth: float = float(d["depth"])
		_edge_outline(4.0, Color(col, a * 0.75))
		_edge_outline(4.0 + 11.0 * depth, Color(col, a * 0.4))
		_edge_outline(4.0 + 24.0 * depth, Color(col, a * 0.18))


func _edge_outline(inset: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(Tuning.ARENA_LEFT + inset, Tuning.ARENA_TOP + inset),
		Vector2(Tuning.ARENA_RIGHT - inset, Tuning.ARENA_TOP + inset),
		Vector2(Tuning.ARENA_RIGHT - inset, Tuning.ARENA_BOTTOM - inset),
		Vector2(Tuning.ARENA_LEFT + inset, Tuning.ARENA_BOTTOM - inset),
		Vector2(Tuning.ARENA_LEFT + inset, Tuning.ARENA_TOP + inset)])
	draw_polyline(pts, col, 3.0, true)
