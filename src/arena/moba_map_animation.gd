class_name MobaMapAnimation
extends Node2D
## Vain Eternal Dividen liikkuvat yksityiskohdat. Staattinen kartta säilyttää
## täyden piirtojälkensä välimuistissa, joten split screen monistaa vain tämän
## pienen animoidun komentolistan eikä koko 7200x4400-kartan rakennustyötä.

var map: MapMoba = null
var _time := 0.0
var _brush_zones: Array = []
var _motes: Array = []


func _ready() -> void:
	z_index = 1
	_brush_zones = map.brush_zones() if map != null else []
	_build_motes(55, 8.0, 55128)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	_draw_river_glints()
	_draw_fountain_energy()
	_draw_objective_energy()
	_draw_deep_crossings()
	_draw_brush_shimmer()
	_draw_motes(Color("8de59a"))


func _draw_river_glints() -> void:
	for i in range(-5, 6):
		var y := float(i) * 205.0 + sin(_time * 0.7 + float(i)) * 14.0
		draw_line(Vector2(-82, y), Vector2(82, y + 24), Color("6bc6d444"), 3.0)


func _draw_fountain_energy() -> void:
	for team in range(2):
		var col: Color = Palette.team(team)
		var fp: Vector2 = map.fountain_spot(team)
		draw_arc(fp, 151.0, -_time * 0.18, -_time * 0.18 + TAU * 0.82, 54,
			Palette.with_alpha(Palette.glow(col, 1.5), 0.72), 8.0)


func _draw_objective_energy() -> void:
	for index in range(2):
		var pos: Vector2 = map.boss_spot() if index == 0 else map.dragon_spot()
		var col: Color = MapMoba.BARON_COL if index == 0 else MapMoba.DRAGON_COL
		draw_arc(pos, 212.0, -_time * 0.18, -_time * 0.18 + TAU * 0.75, 52,
			Palette.with_alpha(Palette.glow(col, 1.35), 0.38), 4.0)


func _draw_deep_crossings() -> void:
	for sx in [-1.0, 1.0]:
		var pos := Vector2(sx * 1990.0, 0.0)
		draw_arc(pos, 61.0, _time * 0.18, _time * 0.18 + TAU * 0.82,
			32, Color("a25ad099"), 6.0)


func _draw_brush_shimmer() -> void:
	# Lehtien täydet muodot ovat staattisessa kartassa. Kaksi liikkuvaa kiiltoa
	# per puska säilyttää tuulen ja elävyyden murto-osalla piirroista.
	for index in range(_brush_zones.size()):
		var rect: Rect2 = _brush_zones[index]
		var phase := _time * 1.2 + float(index) * 1.71
		for row in range(2):
			var x := rect.position.x + fposmod(
				(_time * (22.0 + row * 7.0)) + index * 37.0 + row * rect.size.x * 0.43,
				rect.size.x)
			var y := rect.get_center().y + (float(row) - 0.5) * 40.0 + sin(phase + row) * 7.0
			draw_circle(Vector2(x, y), 8.0 + row * 2.0,
				Color(0.43, 0.88, 0.48, 0.16 + 0.07 * sin(phase)))


func _build_motes(count: int, rise_speed: float, seed_val: int) -> void:
	if map == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var half: Vector2 = map.size() / 2.0
	for _i in range(count):
		_motes.append({
			"x": rng.randf_range(-half.x, half.x),
			"y": rng.randf_range(-half.y, half.y),
			"speed": rng.randf_range(0.5, 1.5) * rise_speed,
			"drift": rng.randf_range(-14.0, 14.0),
			"radius": rng.randf_range(1.5, 4.0),
			"tint": rng.randf(),
		})


func _draw_motes(base_color: Color) -> void:
	var half: Vector2 = map.size() / 2.0
	for mote in _motes:
		var tint: float = mote.tint
		var y: float = fmod(float(mote.y) - _time * float(mote.speed), map.size().y)
		if y < -half.y:
			y += map.size().y
		var x: float = float(mote.x) + sin(_time * 0.4 + tint * TAU) * float(mote.drift)
		var alpha: float = 0.10 + 0.12 * (0.5 + 0.5 * sin(_time * 1.5 + tint * TAU))
		draw_circle(Vector2(x, y), float(mote.radius), Palette.with_alpha(base_color, alpha))
