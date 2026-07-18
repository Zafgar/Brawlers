class_name MapDust
extends MapBase
## Dust Canyon — suuri avoin autiomaa-areena ja LIIKKUVAN VAARAN AREENA.
## Identiteetti: iso avoin tila + pyyhkäisevä hiekkamyrsky.
##  - Selvästi suurin kartta -> pitkät näkölinjat, kaukotaistelu ja kierto
##  - Harvat isot kalliomesat suojana; keskikaista avoin (ampujien valtakunta)
##  - HIEKKAMYRSKY pyyhkii kentän poikki edestakaisin: sisällä hidastaa ja
##    työntää kulkusuuntaan -> pakottaa siirtämään taistelua, ei staattista
##  - Myrsky ei tapa (ei ratkaise ottelua sattumalta), mutta kannattaa väistää
## Vastapari tiiviille Sparkringille.

const FLOOR := Color("2e2518")
const FLOOR_LIGHT := Color("493922")
const ROCK := Color("6e5334")
const ROCK_DARK := Color("3f2f1c")
const ROCK_LIGHT := Color("8f6c43")
const DUST := Color("cbab78")
const ACCENT := Color("e0a24a")

const STORM_AMP := 1050.0
const STORM_W := 0.285          # 2*PI / ~22 s
const STORM_HALF := 220.0
const STORM_SLOW := 0.72
const STORM_PUSH := 110.0

var _rocks: Array = []          # koristekivet {pos, size, rot}
var _cacti: Array = []


func _setup() -> void:
	map_size = Vector2(2800, 1500)
	var half := map_size / 2.0

	# Spawnit laidoille, hieman levitettynä (iso kartta).
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var y := -240.0 + i * 160.0
		blue.append(Vector2(-half.x + 170.0, y))
		orange.append(Vector2(half.x - 170.0, y))
	spawn_slots = [blue, orange]

	# Harvat isot kalliomesat suojana (keskikaista jää avoimeksi).
	pillars = [
		{"pos": Vector2(-760, -440), "radius": 115.0},
		{"pos": Vector2(760, -440), "radius": 115.0},
		{"pos": Vector2(-760, 440), "radius": 115.0},
		{"pos": Vector2(760, 440), "radius": 115.0},
		{"pos": Vector2(0, -600), "radius": 95.0},
		{"pos": Vector2(0, 600), "radius": 95.0},
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 442201
	for i in range(22):
		_rocks.append({
			"pos": Vector2(rng.randf_range(-half.x + 120.0, half.x - 120.0),
				rng.randf_range(-half.y + 120.0, half.y - 120.0)),
			"size": rng.randf_range(10.0, 26.0),
			"rot": rng.randf() * TAU})
	for i in range(7):
		_cacti.append({
			"pos": Vector2(rng.randf_range(-half.x + 200.0, half.x - 200.0),
				rng.randf_range(-half.y + 160.0, half.y - 160.0)),
			"size": rng.randf_range(20.0, 34.0)})


# --- Myrsky vaikuttaa liikkumiseen ---

func _storm_x() -> float:
	return STORM_AMP * sin(_time * STORM_W)


func _storm_dir() -> float:
	return signf(cos(_time * STORM_W))


func terrain_mult(pos: Vector2) -> float:
	if absf(pos.x - _storm_x()) < STORM_HALF:
		return STORM_SLOW
	return 1.0


func conveyor_push(pos: Vector2) -> Vector2:
	if absf(pos.x - _storm_x()) < STORM_HALF:
		return Vector2(_storm_dir() * STORM_PUSH, 0.0)
	return Vector2.ZERO


# --- Piirto ---

func _draw() -> void:
	var half := map_size / 2.0
	draw_rect(Rect2(-half - Vector2(500, 500), map_size + Vector2(1000, 1000)), Color("161009"))

	_draw_floor(half)
	_draw_team_bases(half)
	_draw_cacti()
	_draw_mesas()
	_draw_center_pad()
	_draw_rocks()
	_draw_storm(half)

	_draw_sand_motes(20, DUST, 10.0, 8080)
	_draw_vignette()
	_draw_walls_frame(Color("b98a4e"))


func _draw_floor(half: Vector2) -> void:
	draw_rect(Rect2(-half, map_size), FLOOR)
	# Lämmin valo keskelle
	for i in range(6):
		var r := 820.0 - i * 120.0
		draw_circle(Vector2.ZERO, r, Palette.with_alpha(FLOOR_LIGHT, 0.06))
	# Hiekkajuovat
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in range(40):
		var y := rng.randf_range(-half.y, half.y)
		var x0 := rng.randf_range(-half.x, 0.0)
		var w := rng.randf_range(200.0, 700.0)
		draw_line(Vector2(x0, y), Vector2(x0 + w, y), Palette.with_alpha(FLOOR_LIGHT, 0.25), 2.0)
	# Halkeamat
	for i in range(10):
		var start := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var pts := PackedVector2Array([start])
		var p := start
		for seg in range(4):
			p += Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
			pts.append(p)
		draw_polyline(pts, Palette.with_alpha(ROCK_DARK, 0.4), 2.0)


func _draw_team_bases(half: Vector2) -> void:
	for team in [0, 1]:
		var cx := -half.x + 200.0 if team == 0 else half.x - 200.0
		var color := Palette.team(team)
		draw_circle(Vector2(cx, 0), 230.0, Palette.with_alpha(color, 0.10))
		draw_arc(Vector2(cx, 0), 220.0, 0.0, TAU, 44, Palette.with_alpha(color, 0.4), 4.0)


func _draw_mesas() -> void:
	for pillar in pillars:
		var pos: Vector2 = pillar.pos
		var r: float = pillar.radius
		# Varjo
		draw_circle(pos + Vector2(0, 14), r, Palette.with_alpha(Color.BLACK, 0.3))
		# Kerroksellinen kallio
		draw_circle(pos, r, ROCK_DARK)
		draw_circle(pos, r - 6.0, ROCK)
		draw_circle(pos + Vector2(-r * 0.2, -r * 0.25), r * 0.62, ROCK_LIGHT)
		# Kerrosviivat
		for i in range(3):
			var ry := pos.y - r * 0.4 + i * r * 0.35
			draw_arc(pos, r - 10.0 - i * 6.0, PI * 0.1, PI * 0.9, 16,
				Palette.with_alpha(ROCK_DARK, 0.5), 2.0)
		# Latvan valaistu reuna
		draw_arc(pos, r - 3.0, PI * 1.1, PI * 1.9, 20, Palette.with_alpha(ACCENT, 0.4), 3.0)


func _draw_center_pad() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	draw_circle(Vector2.ZERO, 140.0, Palette.with_alpha(ACCENT, 0.06))
	draw_arc(Vector2.ZERO, 126.0, 0.0, TAU, 48, Palette.with_alpha(ACCENT, 0.3 + pulse * 0.15), 3.0)
	# Kiviympyrä
	for i in range(8):
		var ang := TAU * i / 8.0
		draw_circle(Vector2(cos(ang), sin(ang)) * 118.0, 8.0, ROCK)


func _draw_rocks() -> void:
	for rock in _rocks:
		var pos: Vector2 = rock.pos
		var size: float = rock.size
		var rot: float = rock.rot
		draw_circle(pos + Vector2(0, 4), size, Palette.with_alpha(Color.BLACK, 0.2))
		var poly := PackedVector2Array()
		for i in range(5):
			var ang := rot + TAU * i / 5.0
			var rr := size * (0.7 + 0.3 * sin(i * 2.1))
			poly.append(pos + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(poly, ROCK)
		draw_polyline(poly + PackedVector2Array([poly[0]]), ROCK_DARK, 2.0)


func _draw_cacti() -> void:
	for cactus in _cacti:
		var pos: Vector2 = cactus.pos
		var size: float = cactus.size
		var sway := sin(_time * 1.5 + pos.x * 0.01) * 2.0
		draw_circle(pos + Vector2(0, 6), size * 0.5, Palette.with_alpha(Color.BLACK, 0.2))
		# Runko
		draw_line(pos + Vector2(sway, 6), pos + Vector2(0, -size), Color("3f7a45"), 8.0)
		# Haarat
		draw_line(pos + Vector2(0, -size * 0.5), pos + Vector2(-size * 0.5, -size * 0.6), Color("3f7a45"), 6.0)
		draw_line(pos + Vector2(-size * 0.5, -size * 0.6), pos + Vector2(-size * 0.5, -size * 0.9),
			Color("3f7a45"), 6.0)
		draw_line(pos + Vector2(0, -size * 0.7), pos + Vector2(size * 0.5, -size * 0.8), Color("3f7a45"), 6.0)
		draw_line(pos + Vector2(size * 0.5, -size * 0.8), pos + Vector2(size * 0.5, -size * 1.1),
			Color("3f7a45"), 6.0)


func _draw_storm(half: Vector2) -> void:
	var sx := _storm_x()
	var dir := _storm_dir()
	# Sumea seinämä
	draw_rect(Rect2(sx - STORM_HALF, -half.y, STORM_HALF * 2.0, map_size.y),
		Palette.with_alpha(DUST, 0.10))
	draw_rect(Rect2(sx - STORM_HALF * 0.55, -half.y, STORM_HALF * 1.1, map_size.y),
		Palette.with_alpha(DUST, 0.12))
	# Tuuliviirut vierivät kulkusuuntaan
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in range(46):
		var sy := -half.y + rng.randf_range(0.0, map_size.y)
		var scroll := fmod(_time * 700.0 * dir + i * 120.0, STORM_HALF * 2.0)
		var lx := sx - STORM_HALF + fmod(scroll + STORM_HALF * 2.0, STORM_HALF * 2.0)
		var len := rng.randf_range(30.0, 80.0)
		draw_line(Vector2(lx, sy), Vector2(lx + dir * len, sy),
			Palette.with_alpha(DUST, 0.25), 2.0)
	# Etureuna korostuu (varoitus)
	var edge_x := sx + dir * STORM_HALF
	draw_line(Vector2(edge_x, -half.y), Vector2(edge_x, half.y),
		Palette.with_alpha(Palette.glow(ACCENT, 1.3), 0.4), 3.0)


func _draw_sand_motes(count: int, base_color: Color, rise_speed: float, seed_val: int) -> void:
	# Autiomaassa hiukkaset ajelehtivat vaakasuunnassa (tuuli).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var half := map_size / 2.0
	for i in range(count):
		var by := rng.randf_range(-half.y, half.y)
		var bx := rng.randf_range(-half.x, half.x)
		var speed := rng.randf_range(0.5, 1.5) * rise_speed * 6.0
		var mote_r := rng.randf_range(1.5, 3.5)
		var x: float = fmod(bx + _time * speed, map_size.x)
		if x > half.x:
			x -= map_size.x
		var alpha := 0.08 + 0.08 * sin(_time * 1.2 + i)
		draw_circle(Vector2(x, by + sin(_time + i) * 6.0), mote_r,
			Palette.with_alpha(base_color, alpha))
