class_name MenuBackdrop
extends Control
## Valikoiden yhteinen MOBA-tausta: kaksi kaartuvaa linjaa, niiden välinen
## jungle, objective-pitit, tornit ja hitaasti etenevät minion-aallot.

var team_glow := false

var _time := 0.0
var _foliage: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 715517
	for i in range(105):
		var p := Vector2(rng.randf_range(100.0, 1820.0), rng.randf_range(120.0, 960.0))
		if absf(absf(p.y - 540.0) - 345.0) < 72.0:
			continue
		_foliage.append({
			"pos": p, "r": rng.randf_range(5.0, 18.0),
			"phase": rng.randf_range(0.0, TAU), "bright": rng.randf(),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# Syvä vihreänsininen kenttä, ei enää vanhan areenan hammasrattatausta.
	draw_rect(Rect2(0, 0, 1920, 1080), Color("07140f"))
	draw_circle(Vector2(960, 540), 920.0, Color(0.035, 0.16, 0.10, 0.82))
	draw_circle(Vector2(960, 540), 620.0, Color(0.05, 0.22, 0.14, 0.42))
	draw_circle(Vector2(160, 540), 470.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.055))
	draw_circle(Vector2(1760, 540), 470.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.055))
	if team_glow:
		draw_circle(Vector2(170, 540), 390.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.07))
		draw_circle(Vector2(1750, 540), 390.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.07))

	_draw_tactical_grid()
	_draw_river()
	_draw_jungle()
	var top := _lane_points(true)
	var bottom := _lane_points(false)
	_draw_lane(top)
	_draw_lane(bottom)
	_draw_bases_and_towers(top, bottom)
	_draw_objective(Vector2(960, 385), Color("bd60e5"), "B")
	_draw_objective(Vector2(960, 695), Color("49d7c5"), "D")
	_draw_minion_waves(top)
	_draw_minion_waves(bottom)


func _draw_tactical_grid() -> void:
	for x in range(120, 1920, 120):
		draw_line(Vector2(x, 70), Vector2(x, 1010), Color(0.18, 0.45, 0.31, 0.035), 1.0)
	for y in range(90, 1080, 90):
		draw_line(Vector2(70, y), Vector2(1850, y), Color(0.18, 0.45, 0.31, 0.03), 1.0)
	draw_rect(Rect2(72, 62, 1776, 956), Color(0.25, 0.66, 0.43, 0.09), false, 2.0)


func _draw_river() -> void:
	draw_rect(Rect2(923, 102, 74, 876), Color(0.08, 0.33, 0.40, 0.34))
	draw_rect(Rect2(943, 102, 34, 876), Color(0.14, 0.48, 0.56, 0.22))
	for i in range(11):
		var y := 125.0 + i * 82.0
		var drift := sin(_time * 0.55 + i) * 12.0
		draw_line(Vector2(938 + drift, y), Vector2(982 + drift, y),
			Color(0.40, 0.86, 0.90, 0.12), 2.0)


func _draw_jungle() -> void:
	for plant in _foliage:
		var p: Vector2 = plant.pos
		var r: float = plant.r
		var pulse := 0.72 + 0.12 * sin(_time * 0.42 + plant.phase)
		var col := Color(0.12, 0.38, 0.21, 0.12 + plant.bright * 0.08)
		draw_circle(p, r * 1.65, Color(col.r, col.g, col.b, col.a * 0.30))
		draw_circle(p, r * pulse, col)
	# Pitkät jungle-harjanteet tekevät taustasta taktisen kartan näköisen.
	var wall_col := Color(0.25, 0.54, 0.32, 0.18)
	for seg in [
		[Vector2(290, 420), Vector2(720, 420)], [Vector2(1200, 420), Vector2(1630, 420)],
		[Vector2(290, 660), Vector2(720, 660)], [Vector2(1200, 660), Vector2(1630, 660)],
		[Vector2(520, 500), Vector2(820, 500)], [Vector2(1100, 580), Vector2(1400, 580)],
	]:
		draw_line(seg[0], seg[1], Color(0.02, 0.09, 0.05, 0.55), 18.0, true)
		draw_line(seg[0], seg[1], wall_col, 3.0, true)


func _lane_points(top: bool) -> PackedVector2Array:
	var pts := PackedVector2Array([
		Vector2(145, 540), Vector2(175, 400), Vector2(280, 270),
		Vector2(470, 190), Vector2(700, 178), Vector2(960, 205),
		Vector2(1220, 178), Vector2(1450, 190), Vector2(1640, 270),
		Vector2(1745, 400), Vector2(1775, 540),
	])
	if top:
		return pts
	var mirrored := PackedVector2Array()
	for p in pts:
		mirrored.append(Vector2(p.x, 1080.0 - p.y))
	return mirrored


func _draw_lane(points: PackedVector2Array) -> void:
	draw_polyline(points, Color(0.025, 0.045, 0.03, 0.72), 54.0, true)
	draw_polyline(points, Color(0.33, 0.28, 0.18, 0.42), 38.0, true)
	draw_polyline(points, Color(0.58, 0.48, 0.28, 0.18), 4.0, true)


func _draw_bases_and_towers(top: PackedVector2Array, bottom: PackedVector2Array) -> void:
	_draw_base(Vector2(135, 540), Palette.TEAM_BLUE)
	_draw_base(Vector2(1785, 540), Palette.TEAM_ORANGE)
	for lane in [top, bottom]:
		for idx in [2, 3, 4]:
			_draw_tower(lane[idx], Palette.TEAM_BLUE)
		for idx in [6, 7, 8]:
			_draw_tower(lane[idx], Palette.TEAM_ORANGE)


func _draw_base(pos: Vector2, col: Color) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 1.2 + pos.x * 0.01)
	draw_circle(pos, 62.0 + pulse * 5.0, Palette.with_alpha(col, 0.035))
	draw_circle(pos, 35.0, Color(0.015, 0.035, 0.025, 0.9))
	draw_arc(pos, 31.0, _time * 0.22, _time * 0.22 + TAU * 0.82, 24,
		Palette.with_alpha(Palette.glow(col, 1.35), 0.42), 4.0)
	var diamond := PackedVector2Array([
		pos + Vector2(0, -20), pos + Vector2(17, 0),
		pos + Vector2(0, 20), pos + Vector2(-17, 0),
	])
	draw_colored_polygon(diamond, Palette.with_alpha(col, 0.72))


func _draw_tower(pos: Vector2, col: Color) -> void:
	draw_circle(pos, 15.0, Color(0.015, 0.03, 0.02, 0.86))
	draw_circle(pos, 9.0, Palette.with_alpha(col, 0.78))
	draw_arc(pos, 17.0, 0.0, TAU, 16, Palette.with_alpha(col, 0.22), 2.0)


func _draw_objective(pos: Vector2, col: Color, letter: String) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 1.5 + pos.y)
	draw_circle(pos, 52.0 + pulse * 4.0, Palette.with_alpha(col, 0.035))
	draw_circle(pos, 35.0, Color(0.015, 0.04, 0.03, 0.88))
	draw_arc(pos, 34.0, -_time * 0.2, -_time * 0.2 + TAU * 0.76, 26,
		Palette.with_alpha(col, 0.48), 3.0)
	UiKit.draw_text(self, pos + Vector2(0, 1), letter, 17, Palette.with_alpha(col, 0.76), true)


func _draw_minion_waves(path: PackedVector2Array) -> void:
	for team in range(2):
		var col := Palette.TEAM_BLUE if team == 0 else Palette.TEAM_ORANGE
		for wave in range(3):
			var phase := fmod(_time * 0.025 + wave / 3.0 + team * 0.5, 1.0)
			if team == 1:
				phase = 1.0 - phase
			var p := _sample_path(path, phase)
			draw_circle(p, 8.0, Palette.with_alpha(col, 0.04))
			draw_circle(p, 3.2, Palette.with_alpha(Palette.glow(col, 1.25), 0.45))


func _sample_path(path: PackedVector2Array, t: float) -> Vector2:
	if path.size() < 2:
		return Vector2.ZERO
	var scaled := clampf(t, 0.0, 0.9999) * float(path.size() - 1)
	var idx := mini(int(scaled), path.size() - 2)
	return path[idx].lerp(path[idx + 1], scaled - float(idx))
