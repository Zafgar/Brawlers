class_name MapBase
extends Node2D
## Kaikkien areenojen yhteinen pohja: reunaseinät, törmäysesteet, spawn-pisteet
## ja liikkumisapurit. Aliluokka määrittää koon, esteet ja ulkoasun.
##
## Aliluokan sopimus:
##   _setup()  — täytä map_size, pillars ja belts ENNEN seinien rakennusta
##   _draw()   — piirrä areena (kutsu halutessasi _draw_walls_frame apuriin)

const WALL_THICKNESS := 80.0

var map_size := Vector2(2400, 1350)
var pillars: Array = []      # [{pos: Vector2, radius: float}] pyöreät esteet
var rect_walls: Array = []   # [Rect2] suorakaide-esteet (kartan sisäseinät)
var belts: Array = []        # [{rect: Rect2, dir: Vector2}] kuljetinhihnat
var belt_push := 120.0
var spawn_slots: Array = []  # [team0: [Vector2...], team1: [Vector2...]] valinnainen

var _time := 0.0


func _ready() -> void:
	z_index = -10
	_setup()
	_build_walls()


## Aliluokka ylikirjoittaa: asettaa map_size, pillars, belts.
func _setup() -> void:
	pass


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _build_walls() -> void:
	var half := map_size / 2.0
	var t := WALL_THICKNESS
	var wall_rects := [
		Rect2(Vector2(-half.x - t, -half.y - t), Vector2(map_size.x + t * 2.0, t)),
		Rect2(Vector2(-half.x - t, half.y), Vector2(map_size.x + t * 2.0, t)),
		Rect2(Vector2(-half.x - t, -half.y), Vector2(t, map_size.y)),
		Rect2(Vector2(half.x, -half.y), Vector2(t, map_size.y)),
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
	for wall_rect in rect_walls:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = wall_rect.size
		shape.shape = rect_shape
		shape.position = wall_rect.position + wall_rect.size / 2.0
		body.add_child(shape)
		add_child(body)


# --- Pelilogiikan rajapinta (yhteinen kaikille areenoille) ---

func size() -> Vector2:
	return map_size


func spawn_point(team: int, index: int) -> Vector2:
	# Kartta voi määrittää omat spawn-pisteensä; muuten oletus (reunat).
	if spawn_slots.size() == 2 and not spawn_slots[team].is_empty():
		var arr: Array = spawn_slots[team]
		return arr[index % arr.size()]
	var x := -map_size.x / 2.0 + 170.0 if team == 0 else map_size.x / 2.0 - 170.0
	var slot := index % 4
	var y := -240.0 + slot * 160.0
	return Vector2(x, y)


func relic_home() -> Vector2:
	return Vector2.ZERO


func conveyor_push(pos: Vector2) -> Vector2:
	for belt in belts:
		if belt.rect.has_point(pos):
			return belt.dir * belt_push
	return Vector2.ZERO


func clamp_to_field(pos: Vector2, margin := 40.0) -> Vector2:
	var half := map_size / 2.0
	var p := Vector2(
		clampf(pos.x, -half.x + margin, half.x - margin),
		clampf(pos.y, -half.y + margin, half.y - margin))
	for pillar in pillars:
		var diff: Vector2 = p - pillar.pos
		if diff.length() < pillar.radius + margin:
			p = pillar.pos + diff.normalized() * (pillar.radius + margin)
	for wall_rect in rect_walls:
		var grown: Rect2 = wall_rect.grow(margin)
		if grown.has_point(p):
			# Työnnä lähimmän reunan yli.
			var left := p.x - grown.position.x
			var right := grown.end.x - p.x
			var top := p.y - grown.position.y
			var bottom := grown.end.y - p.y
			var m: float = min(min(left, right), min(top, bottom))
			if m == left:
				p.x = grown.position.x
			elif m == right:
				p.x = grown.end.x
			elif m == top:
				p.y = grown.position.y
			else:
				p.y = grown.end.y
	return p


func random_point(margin := 140.0) -> Vector2:
	return clamp_to_field(Vector2(
		randf_range(-map_size.x / 2.0, map_size.x / 2.0),
		randf_range(-map_size.y / 2.0, map_size.y / 2.0)), margin)


# --- Jaetut piirtoapurit ---

## Hammasratas (tähtimonikulmio + napa).
func _draw_gear(pos: Vector2, r: float, angle: float, teeth: int,
		main: Color, dark: Color, highlight := Color(0, 0, 0, 0)) -> void:
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
	if highlight.a > 0.0:
		# Pyörivä kiilto napaan
		var shine := pos + Vector2(cos(angle * 1.5), sin(angle * 1.5)) * r * 0.3
		draw_circle(shine, r * 0.12, highlight)


## Reunaseinät: paksu tumma runko ja hehkuva sisäreuna.
func _draw_walls_frame(inner_color: Color, wall_color := Color("0b1122")) -> void:
	var half := map_size / 2.0
	var t := WALL_THICKNESS
	draw_rect(Rect2(Vector2(-half.x - t, -half.y - t), Vector2(map_size.x + t * 2.0, t)), wall_color)
	draw_rect(Rect2(Vector2(-half.x - t, half.y), Vector2(map_size.x + t * 2.0, t)), wall_color)
	draw_rect(Rect2(Vector2(-half.x - t, -half.y), Vector2(t, map_size.y)), wall_color)
	draw_rect(Rect2(Vector2(half.x, -half.y), Vector2(t, map_size.y)), wall_color)
	draw_rect(Rect2(-half, map_size), Palette.with_alpha(inner_color, 0.6), false, 4.0)
	draw_rect(Rect2(-half + Vector2(6, 6), map_size - Vector2(12, 12)),
		Palette.with_alpha(inner_color, 0.2), false, 2.0)


## Reunojen tummennus (vignette): näyttää vähemmän litteältä.
func _draw_vignette() -> void:
	var half := map_size / 2.0
	var band := 220.0
	var edge := Palette.with_alpha(Color(0.02, 0.03, 0.07), 0.55)
	var clear := Color(0.02, 0.03, 0.07, 0.0)
	_v_grad(Rect2(-half.x, -half.y, map_size.x, band), edge, clear, true)
	_v_grad(Rect2(-half.x, half.y - band, map_size.x, band), clear, edge, true)
	_v_grad(Rect2(-half.x, -half.y, band, map_size.y), edge, clear, false)
	_v_grad(Rect2(half.x - band, -half.y, band, map_size.y), clear, edge, false)


## Yksinkertainen lineaarinen liukuväri suorakaiteeseen (pysty tai vaaka).
func _v_grad(rect: Rect2, from: Color, to: Color, vertical: bool) -> void:
	var steps := 10
	for i in range(steps):
		var t0 := float(i) / steps
		var col := from.lerp(to, t0)
		if vertical:
			var y := rect.position.y + rect.size.y * t0
			draw_rect(Rect2(rect.position.x, y, rect.size.x, rect.size.y / steps + 1.0), col)
		else:
			var x := rect.position.x + rect.size.x * t0
			draw_rect(Rect2(x, rect.position.y, rect.size.x / steps + 1.0, rect.size.y), col)


## Ajelehtivat hiukkaset (siitepöly/tuhka/kiiltohiput). Deterministinen.
func _draw_motes(count: int, base_color: Color, rise_speed := 20.0, seed_val := 12345) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var half := map_size / 2.0
	for i in range(count):
		var bx := rng.randf_range(-half.x, half.x)
		var by := rng.randf_range(-half.y, half.y)
		var speed := rng.randf_range(0.5, 1.5) * rise_speed
		var drift := rng.randf_range(-14.0, 14.0)
		var mote_r := rng.randf_range(1.5, 4.0)
		var tint := rng.randf()
		var y: float = fmod(by - _time * speed, map_size.y)
		if y < -half.y:
			y += map_size.y
		var x := bx + sin(_time * 0.4 + tint * TAU) * drift
		var alpha: float = 0.10 + 0.12 * (0.5 + 0.5 * sin(_time * 1.5 + tint * TAU))
		draw_circle(Vector2(x, y), mote_r, Palette.with_alpha(base_color, alpha))
