class_name Hud
extends Node2D
## All text and screen furniture: the in-run HUD bar, the wave
## banner, the title screen (with the FULL controls list — every
## control the game accepts, house rule), the game-over screen and
## the pause note. Main pushes plain values in each frame; this
## script only draws, so it never reaches into game state.

var score: int = 0
var multiplier: float = 1.0
var grace_frac: float = 0.0 # 1 = decay grace full, 0 = decaying
var rank: float = 0.0 # 0..1, the intensity engine, shown and named
var rank_floor: float = 0.0 # the wave's menace floor, ticked on the bar
var wave: int = 0
var canisters_left: int = 8
var best_score: int = 0
var best_wave: int = 0
var mode: int = 0 # mirrors Main.GameState: 0 title, 1 running, 2 game over
var paused: bool = false
var banner_text: String = ""
var banner_frac: float = 0.0 # 1 at banner start, fades to 0
var boss_bar_active: bool = false # boss waves: hull bar at top center
var boss_bar_label: String = ""
var boss_bar_frac: float = 1.0 # hull fraction remaining, 0..1
var boss_bar_close_bonus: bool = false # player inside the proximity band
var powerup_id: String = "" # active powerup ("" = none): HUD chip
var powerup_name: String = ""
var powerup_color: Color = Color.WHITE
var powerup_frac: float = 0.0 # remaining timer fraction, 0..1

const MODE_TITLE: int = 0
const MODE_RUNNING: int = 1
const MODE_GAMEOVER: int = 2

var _font: Font = null


func _ready() -> void:
	z_index = 40
	_font = ThemeDB.fallback_font


func _draw() -> void:
	if _font == null:
		return
	if mode == MODE_RUNNING:
		_draw_run_hud()
		if paused:
			_draw_center_lines(["PAUSED"], 44, Tuning.COLOR_TEXT)
		elif banner_frac > 0.0 and banner_text != "":
			var col: Color = Color(Tuning.COLOR_TEXT,
				clampf(banner_frac * 1.6, 0.0, 1.0))
			_draw_center_lines([banner_text], 40, col)
	elif mode == MODE_TITLE:
		_draw_title()
	elif mode == MODE_GAMEOVER:
		_draw_run_hud()
		_draw_gameover()


func _draw_run_hud() -> void:
	_text(Vector2(52.0, 32.0), "SCORE %06d" % score, 22, Tuning.COLOR_TEXT)
	# Multiplier with its decay bar underneath.
	var mx: float = 330.0
	_text(Vector2(mx, 32.0), "x%.2f" % multiplier, 22,
		Tuning.COLOR_SHARD.lerp(Color.WHITE, 0.25))
	var bar_w: float = 110.0
	draw_rect(Rect2(mx, 40.0, bar_w, 4.0), Color(Tuning.COLOR_TEXT_DIM, 0.35))
	var fill: float = bar_w * clampf(
		(multiplier - 1.0) / maxf(Tuning.MULT_CAP - 1.0, 0.01), 0.0, 1.0)
	draw_rect(Rect2(mx, 40.0, fill, 4.0), Tuning.COLOR_SHARD)
	draw_rect(Rect2(mx, 47.0, bar_w * grace_frac, 3.0),
		Color(Tuning.COLOR_DEPOT, 0.8))
	# RANK: labelled, visible, with the wave floor ticked so the
	# player can watch pressure build and see where it cannot fall.
	var rx: float = 560.0
	_text(Vector2(rx, 32.0), "RANK", 22, Tuning.COLOR_TEXT)
	var rank_w: float = 150.0
	draw_rect(Rect2(rx + 62.0, 20.0, rank_w, 8.0),
		Color(Tuning.COLOR_TEXT_DIM, 0.35))
	draw_rect(Rect2(rx + 62.0, 20.0, rank_w * clampf(rank, 0.0, 1.0), 8.0),
		Tuning.COLOR_STEAL_FLASH.lerp(Tuning.COLOR_SHARD, 1.0 - rank))
	var floor_x: float = rx + 62.0 + rank_w * clampf(rank_floor, 0.0, 1.0)
	draw_rect(Rect2(floor_x - 1.0, 17.0, 2.0, 14.0), Tuning.COLOR_TEXT)
	# Powerup chip (M5): the shared glyph, the name, and a
	# remaining-time bar — between the RANK bar and the wave
	# readout, clear of the boss bar's centred label.
	if powerup_id != "":
		var chip_x: float = 800.0
		PowerupDefs.draw_glyph(self, powerup_id,
			Vector2(chip_x + 10.0, 25.0), 0.85)
		_text(Vector2(chip_x + 26.0, 32.0), powerup_name, 18,
			powerup_color)
		draw_rect(Rect2(chip_x + 26.0, 38.0, 96.0, 4.0),
			Color(Tuning.COLOR_TEXT_DIM, 0.35))
		draw_rect(Rect2(chip_x + 26.0, 38.0,
			96.0 * clampf(powerup_frac, 0.0, 1.0), 4.0), powerup_color)
	_text(Vector2(1030.0, 32.0), "WAVE %d" % wave, 22, Tuning.COLOR_TEXT)
	# Canister pips.
	for i: int in range(Tuning.SLOT_COUNT):
		var px: float = 1130.0 + float(i) * 13.0
		var col: Color = Tuning.COLOR_CANISTER if i < canisters_left \
			else Color(Tuning.COLOR_TEXT_DIM, 0.3)
		draw_circle(Vector2(px, 25.0), 4.5, col)
	# Boss hull bar (boss waves only): the Dreadnought's name and
	# hull fraction, top center — below the HUD strip, clear of
	# the boss's station band. The label centers through the
	# measured _text_center path, never an alignment box.
	if boss_bar_active:
		var bcx: float = Tuning.VIEW_W * 0.5
		var label: String = boss_bar_label
		if boss_bar_close_bonus:
			label += " — CLOSE BONUS"
		_text_center(Vector2(bcx, 66.0), label, 18,
			Tuning.COLOR_BOSS.lerp(Color.WHITE, 0.3))
		var bw: float = 320.0
		var bx: float = bcx - bw * 0.5
		draw_rect(Rect2(bx, 72.0, bw, 7.0),
			Color(Tuning.COLOR_TEXT_DIM, 0.35))
		draw_rect(Rect2(bx, 72.0,
			bw * clampf(boss_bar_frac, 0.0, 1.0), 7.0),
			Tuning.COLOR_BOSS)


func _draw_title() -> void:
	var cx: float = Tuning.VIEW_W * 0.5
	_text_center(Vector2(cx, 190.0), "RIPPED-OFF", 84, Tuning.COLOR_DEPOT)
	_text_center(Vector2(cx, 246.0),
		"Defend the canisters. Feed the multiplier.", 24, Tuning.COLOR_TEXT)
	if best_score > 0:
		_text_center(Vector2(cx, 300.0),
			"BEST  %06d   —   WAVE %d" % [best_score, best_wave], 22,
			Tuning.COLOR_SHARD)
	var lines: Array[String] = [
		"CONTROLS",
		"Move ............ W A S D  /  Left Stick",
		"Aim ............. Mouse  /  Right Stick",
		"Fire ............ Hold Left Mouse  /  Space  /  Right Trigger  /  A Button",
		"Twin-stick ...... Arrow Keys aim and fire",
		"Pause ........... Esc  /  P  /  Start Button",
		"",
		"Ram a pirate at speed to kill it. Tow loose canisters home.",
		"The run ends when all 8 canisters are gone.",
		"",
		"Fire to play",
	]
	var y: float = 356.0
	for line: String in lines:
		var col: Color = Tuning.COLOR_TEXT
		if line == "CONTROLS":
			col = Tuning.COLOR_DEPOT
		elif line == "Fire to play":
			col = Tuning.COLOR_SHARD
		_text_center(Vector2(cx, y), line, 21, col)
		y += 30.0
	# Powerup legend (M5): the four glyphs with their names, drawn
	# with the SAME PowerupDefs implementation the field pickups
	# and the HUD chip use — learn the symbols here, read them
	# at speed in the run.
	_text_center(Vector2(cx, y + 6.0), "POWERUPS — KILLS DROP THEM",
		16, Tuning.COLOR_TEXT_DIM)
	var ids: Array[String] = PowerupDefs.type_ids()
	var cell_w: float = 170.0
	var first_cx: float = cx - cell_w * float(ids.size() - 1) * 0.5
	for i: int in range(ids.size()):
		var cell_cx: float = first_cx + cell_w * float(i)
		PowerupDefs.draw_glyph(self, ids[i],
			Vector2(cell_cx, y + 34.0), 0.9)
		_text_center(Vector2(cell_cx, y + 62.0),
			PowerupDefs.name_of(ids[i]), 15, PowerupDefs.color_of(ids[i]))


func _draw_gameover() -> void:
	var cx: float = Tuning.VIEW_W * 0.5
	draw_rect(Rect2(0.0, 0.0, Tuning.VIEW_W, Tuning.VIEW_H),
		Color(0.0, 0.0, 0.0, 0.55))
	_text_center(Vector2(cx, 300.0), "ALL CANISTERS GONE", 52,
		Tuning.COLOR_STEAL_FLASH)
	_text_center(Vector2(cx, 366.0), "SCORE  %06d" % score, 30,
		Tuning.COLOR_TEXT)
	_text_center(Vector2(cx, 406.0), "WAVE REACHED  %d" % wave, 24,
		Tuning.COLOR_TEXT)
	_text_center(Vector2(cx, 446.0), "BEST  %06d" % best_score, 24,
		Tuning.COLOR_SHARD)
	_text_center(Vector2(cx, 516.0), "Fire to play again", 22,
		Tuning.COLOR_TEXT_DIM)


## The first baseline of the centered screen lines (the wave
## banner, the PAUSED note): the stage's vertical center. The
## banner used to draw at 0.32 x VIEW_H, up toward the top of
## the stage, where on a real window it read as almost off
## screen; the between-wave beat belongs in the middle.
func center_line_y() -> float:
	return Tuning.VIEW_H * 0.5


func _draw_center_lines(lines: Array[String], size: int, col: Color) -> void:
	var y: float = center_line_y()
	for line: String in lines:
		_text_center(Vector2(Tuning.VIEW_W * 0.5, y), line, size, col)
		y += float(size) + 10.0


func _text(pos: Vector2, content: String, size: int, col: Color) -> void:
	draw_string(_font, pos, content, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		size, col)


## The draw origin (baseline start) that centers `content` on
## the horizontal point `center_x`, measured with the real
## font. The previous _text_center passed HORIZONTAL_ALIGNMENT_
## CENTER with width = VIEW_W at pos.x = VIEW_W * 0.5 — but
## draw_string's alignment box STARTS at the position and
## extends `width`, so the box was [640, 1920] and "centered"
## text was centered on 1280, the stage's right edge: only its
## left sliver showed ("WA" of WAVE 17, "RIPPE" of the title).
## Measuring and placing explicitly is exact for any string.
func centered_origin(content: String, size: int, center_x: float,
		y: float) -> Vector2:
	var text_w: float = 0.0
	if _font != null:
		text_w = _font.get_string_size(content,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	return Vector2(center_x - text_w * 0.5, y)


func _text_center(pos: Vector2, content: String, size: int, col: Color) -> void:
	draw_string(_font, centered_origin(content, size, pos.x, pos.y),
		content, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)
