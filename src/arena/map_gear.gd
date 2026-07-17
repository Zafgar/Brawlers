class_name MapGear
extends Node2D
## Geargarden — värikäs mekaaninen puutarha. Koko kenttä piirretään koodilla:
## tausta, pyörivät hammasrattaat, kuljetinhihnat, esteet ja reunat.
## Tarjoaa myös spawn-pisteet, reliikin paikan ja liikuteltavuusapurit.

const SIZE := Vector2(2400, 1350)
const WALL_THICKNESS := 80.0
const BELT_PUSH := 120.0

# Kuljetinhihnat: {rect, dir}
var belts := [
	{"rect": Rect2(Vector2(-520, -620), Vector2(1040, 120)), "dir": Vector2.RIGHT},
	{"rect": Rect2(Vector2(-520, 500), Vector2(1040, 120)), "dir": Vector2.LEFT},
]

# Pyöreät este-pilarit (hammasrattaita): {pos, radius}
var pillars := [
	{"pos": Vector2(-620, -260), "radius": 86.0},
	{"pos": Vector2(620, -260), "radius": 86.0},
	{"pos": Vector2(-620, 260), "radius": 86.0},
	{"pos": Vector2(620, 260), "radius": 86.0},
]

var _time := 0.0
var _flowers: Array = []
var _bg_gears: Array = []


func _ready() -> void:
	z_index = -10
	_build_walls()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260717
	for i in range(26):
		_flowers.append({
			"pos": Vector2(
				rng.randf_range(-SIZE.x / 2.0 + 120.0, SIZE.x / 2.0 - 120.0),
				rng.randf_range(-SIZE.y / 2.0 + 120.0, SIZE.y / 2.0 - 120.0)),
			"size": rng.randf_range(4.0, 9.0),
			"hue": rng.randf(),
		})
	_bg_gears = [
		{"pos": Vector2(-880, -480), "r": 150.0, "speed": 0.2, "teeth": 10},
		{"pos": Vector2(900, 470), "r": 180.0, "speed": -0.15, "teeth": 12},
		{"pos": Vector2(840, -500), "r": 110.0, "speed": 0.3, "teeth": 8},
		{"pos": Vector2(-860, 500), "r": 120.0, "speed": -0.25, "teeth": 9},
		{"pos": Vector2(0, 0), "r": 260.0, "speed": 0.06, "teeth": 16},
	]


func _build_walls() -> void:
	var half := SIZE / 2.0
	var t := WALL_THICKNESS
	var wall_rects := [
		Rect2(Vector2(-half.x - t, -half.y - t), Vector2(SIZE.x + t * 2.0, t)),
		Rect2(Vector2(-half.x - t, half.y), Vector2(SIZE.x + t * 2.0, t)),
		Rect2(Vector2(-half.x - t, -half.y), Vector2(t, SIZE.y)),
		Rect2(Vector2(half.x, -half.y), Vector2(t, SIZE.y)),
	]
	for r in wall_rects:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = r.size
		shape.shape = rect_shape
		shape.position = r.position + r.size / 2.0
		body.add_child(shape)
		add_child(body)
	for pillar in pillars:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pillar.pos
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = pillar.radius
		shape.shape = circle
		body.add_child(shape)
		add_child(body)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# --- Pelilogiikan rajapinta ---

func spawn_point(team: int, index: int) -> Vector2:
	var x := -SIZE.x / 2.0 + 170.0 if team == 0 else SIZE.x / 2.0 - 170.0
	var slot := index % 4
	var y := -240.0 + slot * 160.0
	return Vector2(x, y)


func relic_home() -> Vector2:
	return Vector2.ZERO


func conveyor_push(pos: Vector2) -> Vector2:
	for belt in belts:
		if belt.rect.has_point(pos):
			return belt.dir * BELT_PUSH
	return Vector2.ZERO


func clamp_to_field(pos: Vector2, margin := 40.0) -> Vector2:
	var half := SIZE / 2.0
	var p := Vector2(
		clampf(pos.x, -half.x + margin, half.x - margin),
		clampf(pos.y, -half.y + margin, half.y - margin))
	# Ei pilarien sisään
	for pillar in pillars:
		var diff: Vector2 = p - pillar.pos
		if diff.length() < pillar.radius + margin:
			p = pillar.pos + diff.normalized() * (pillar.radius + margin)
	return p


func random_point(margin := 140.0) -> Vector2:
	return clamp_to_field(Vector2(
		randf_range(-SIZE.x / 2.0, SIZE.x / 2.0),
		randf_range(-SIZE.y / 2.0, SIZE.y / 2.0)), margin)


# --- Piirto ---

func _draw() -> void:
	var half := SIZE / 2.0

	# Pohja: tumma gradientti keskeltä vaaleampi
	draw_rect(Rect2(-half - Vector2(400, 400), SIZE + Vector2(800, 800)), Palette.BG_DARK)
	draw_rect(Rect2(-half, SIZE), Palette.BG_MID)
	draw_circle(Vector2.ZERO, 560.0, Palette.with_alpha(Palette.BG_LIGHT, 0.5))
	draw_circle(Vector2.ZERO, 360.0, Palette.with_alpha(Palette.BG_LIGHT, 0.55))

	# Hienovarainen pisteruudukko
	for gx in range(-5, 6):
		for gy in range(-3, 4):
			draw_circle(Vector2(gx * 220.0, gy * 220.0), 3.0, Color(1, 1, 1, 0.05))

	# Taustarattaat (isot, himmeät, pyörivät)
	for gear in _bg_gears:
		_draw_gear(gear.pos, gear.r, _time * gear.speed, gear.teeth,
			Palette.with_alpha(Palette.BG_LIGHT, 0.35),
			Palette.with_alpha(Palette.BG_DARK, 0.4))

	# Puutarhaläikät ja kukat
	for flower in _flowers:
		var c := Color.from_hsv(0.25 + flower.hue * 0.15, 0.5, 0.75, 0.5)
		draw_circle(flower.pos, flower.size * 2.6, Palette.with_alpha(c, 0.10))
		draw_circle(flower.pos, flower.size, c)
		draw_circle(flower.pos, flower.size * 0.4, Color(1.0, 0.95, 0.7, 0.9))

	# Kuljetinhihnat animoiduilla nuoliraidoilla
	for belt in belts:
		var rect: Rect2 = belt.rect
		draw_rect(rect, Color(0.09, 0.11, 0.2, 0.9))
		draw_rect(rect, Color(0.35, 0.42, 0.6, 0.5), false, 3.0)
		var dir: Vector2 = belt.dir
		var scroll := fmod(_time * 90.0, 90.0)
		var count := int(rect.size.x / 90.0)
		for i in range(count + 1):
			var base_x: float = rect.position.x + fmod(scroll + i * 90.0, rect.size.x + 90.0) - 45.0
			if base_x < rect.position.x or base_x > rect.end.x - 30.0:
				continue
			var cy := rect.position.y + rect.size.y / 2.0
			var tip := Vector2(base_x + (24.0 if dir.x > 0.0 else 6.0), cy)
			var tail := Vector2(base_x + (6.0 if dir.x > 0.0 else 24.0), cy)
			draw_line(Vector2(tail.x, cy - 18.0), tip, Color(0.5, 0.62, 0.9, 0.5), 4.0)
			draw_line(Vector2(tail.x, cy + 18.0), tip, Color(0.5, 0.62, 0.9, 0.5), 4.0)

	# Estepilarit kirkkaina hammasrattaina
	for i in range(pillars.size()):
		var pillar = pillars[i]
		var spin: float = _time * (0.4 if i % 2 == 0 else -0.4)
		_draw_gear(pillar.pos, pillar.radius, spin, 9,
			Color("3d5a80"), Color("2b3f5c"))
		draw_circle(pillar.pos, pillar.radius * 0.35, Color("22334f"))
		draw_circle(pillar.pos, pillar.radius * 0.18, Color("4a6da0"))

	# Keskusaukio reliikille
	draw_arc(Vector2.ZERO, 130.0, 0.0, TAU, 64, Palette.with_alpha(Palette.GOLD, 0.30), 4.0)
	draw_arc(Vector2.ZERO, 118.0, 0.0, TAU, 64, Palette.with_alpha(Palette.GOLD, 0.15), 2.0)

	# Reunaseinät: paksu tumma reunus ja hehkuva sisäreuna
	var t := WALL_THICKNESS
	draw_rect(Rect2(Vector2(-half.x - t, -half.y - t), Vector2(SIZE.x + t * 2.0, t)), Color("0b1122"))
	draw_rect(Rect2(Vector2(-half.x - t, half.y), Vector2(SIZE.x + t * 2.0, t)), Color("0b1122"))
	draw_rect(Rect2(Vector2(-half.x - t, -half.y), Vector2(t, SIZE.y)), Color("0b1122"))
	draw_rect(Rect2(Vector2(half.x, -half.y), Vector2(t, SIZE.y)), Color("0b1122"))
	draw_rect(Rect2(-half, SIZE), Palette.with_alpha(Color("5a7ec9"), 0.55), false, 4.0)

	# Joukkueiden kotipesien hehkut
	draw_circle(Vector2(-half.x + 150.0, 0), 190.0, Palette.with_alpha(Palette.TEAM_BLUE, 0.07))
	draw_circle(Vector2(half.x - 150.0, 0), 190.0, Palette.with_alpha(Palette.TEAM_ORANGE, 0.07))


func _draw_gear(pos: Vector2, r: float, angle: float, teeth: int,
		main: Color, dark: Color) -> void:
	var pts := PackedVector2Array()
	var steps := teeth * 4
	for i in range(steps):
		var a: float = angle + TAU * i / steps
		var phase := i % 4
		var rr: float = r if phase < 2 else r * 0.82
		pts.append(pos + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, main)
	draw_circle(pos, r * 0.55, dark)
	draw_circle(pos, r * 0.2, main)
