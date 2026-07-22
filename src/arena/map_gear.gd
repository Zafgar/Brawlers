class_name MapGear
extends MapBase
## Geargarden — värikäs mekaaninen puutarha ja pelin TASAPAINOINEN PERUSAREENA.
## Symmetrinen rakenne opettaa perusteet:
##  - Reliikki keskellä, tasan yhtä kaukana molemmista spawneista
##  - Neljä keskusratasta kehystävät tavoitteen (juoksusuoja kantajalle,
##    neljä lähestymissuuntaa)
##  - Pensasaidat ovat oikeaa suojaa: spawn-suojaa ja ylä/ala-kaistojen
##    kiertoreittejä ilman umpikujia
##  - Kuljetinhihnat luovat kiertoliikettä muttei pakota kantajaa pois
## Lämmin ja eloisa, ei synkkä.

const FLOOR_BASE := Color("233a55")
const FLOOR_LIGHT := Color("35597d")
const FLOOR_SEAM := Color("5784b0")
const BRASS := Color("caa15a")
const BRASS_DARK := Color("7a5b28")
const HEDGE := Color("3f7a45")
const HEDGE_DARK := Color("245029")

var _flowers: Array = []
var _bg_gears: Array = []
var _hedges: Array = []


func _setup() -> void:
	map_size = Vector2(2400, 1350)
	# Kuljetinhihnat luovat kiertoliikettä mutta eivät riistä hallintaa (100 < liikenopeus 285-360).
	belt_push = 100.0
	belts = [
		{"rect": Rect2(Vector2(-520, -620), Vector2(1040, 120)), "dir": Vector2.RIGHT},
		{"rect": Rect2(Vector2(-520, 500), Vector2(1040, 120)), "dir": Vector2.LEFT},
	]
	# Neljä keskusratasta kehystävät reliikkiä (hieman avoimempi keskus: r80).
	pillars = [
		{"pos": Vector2(-620, -260), "radius": 80.0},
		{"pos": Vector2(620, -260), "radius": 80.0},
		{"pos": Vector2(-620, 260), "radius": 80.0},
		{"pos": Vector2(620, 260), "radius": 80.0},
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260717
	for i in range(30):
		_flowers.append({
			"pos": Vector2(
				rng.randf_range(-map_size.x / 2.0 + 120.0, map_size.x / 2.0 - 120.0),
				rng.randf_range(-map_size.y / 2.0 + 120.0, map_size.y / 2.0 - 120.0)),
			"size": rng.randf_range(5.0, 10.0),
			"hue": rng.randf(),
			"petals": rng.randi_range(5, 7),
		})
	_bg_gears = [
		{"pos": Vector2(-880, -480), "r": 150.0, "speed": 0.2, "teeth": 10},
		{"pos": Vector2(900, 470), "r": 180.0, "speed": -0.15, "teeth": 12},
		{"pos": Vector2(840, -500), "r": 110.0, "speed": 0.3, "teeth": 8},
		{"pos": Vector2(-860, 500), "r": 120.0, "speed": -0.25, "teeth": 9},
		{"pos": Vector2(0, 0), "r": 260.0, "speed": 0.06, "teeth": 16},
	]
	# Pensasaidat ovat oikeaa suojaa (törmäys + piirto): ylä/ala-kaistojen
	# kiertoreitit ja spawn-suoja, symmetrisesti ja spawnien ulkopuolella.
	_hedges = [
		Rect2(Vector2(-980, -660), Vector2(360, 70)),
		Rect2(Vector2(620, -660), Vector2(360, 70)),
		Rect2(Vector2(-980, 590), Vector2(360, 70)),
		Rect2(Vector2(620, 590), Vector2(360, 70)),
		Rect2(Vector2(-1150, -180), Vector2(70, 360)),
		Rect2(Vector2(1080, -180), Vector2(70, 360)),
	]
	rect_walls = _hedges


# --- Piirto ---

func _draw() -> void:
	var half := map_size / 2.0

	# Pohja reunan yli (ettei laidoille jää tyhjää)
	draw_rect(Rect2(-half - Vector2(500, 500), map_size + Vector2(1000, 1000)), Palette.BG_DARK)

	_draw_floor(half)

	# Taustarattaat (himmeät, syvyyttä)
	for gear in _bg_gears:
		_draw_gear(gear.pos, gear.r, _time * gear.speed, gear.teeth,
			Palette.with_alpha(FLOOR_LIGHT, 0.5),
			Palette.with_alpha(Palette.BG_DARK, 0.5),
			Palette.with_alpha(BRASS, 0.2))

	_draw_team_bases(half)
	_draw_hedges()
	_draw_flowers()
	_draw_belts()
	_draw_pillars()
	_draw_center_pad()

	_draw_motes(34, Color("ffe9a8"), 18.0, 4242)
	_draw_vignette()
	_draw_walls_frame(Color("6f9ad6"))


func _draw_floor(half: Vector2) -> void:
	draw_rect(Rect2(-half, map_size), FLOOR_BASE)
	# Suuri lämmin valokeila keskelle -> ei synkkä
	for i in range(6):
		var r := 720.0 - i * 110.0
		var a := 0.06 + i * 0.03
		draw_circle(Vector2.ZERO, r, Palette.with_alpha(FLOOR_LIGHT, a))
	# Lattialaatat saumoineen
	var tile := 200.0
	var cols := int(map_size.x / tile)
	var rows := int(map_size.y / tile)
	for gx in range(cols + 1):
		for gy in range(rows + 1):
			var p := Vector2(-half.x + gx * tile, -half.y + gy * tile)
			if (gx + gy) % 2 == 0:
				draw_rect(Rect2(p, Vector2(tile, tile)), Palette.with_alpha(FLOOR_LIGHT, 0.10))
	for gx in range(cols + 1):
		var x := -half.x + gx * tile
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), Palette.with_alpha(FLOOR_SEAM, 0.10), 1.5)
	for gy in range(rows + 1):
		var y := -half.y + gy * tile
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), Palette.with_alpha(FLOOR_SEAM, 0.10), 1.5)


func _draw_team_bases(half: Vector2) -> void:
	for team in [0, 1]:
		var cx := -half.x + 210.0 if team == 0 else half.x - 210.0
		var color := Palette.team(team)
		var center := Vector2(cx, 0)
		# Valaistu tukikohtalattia
		draw_circle(center, 250.0, Palette.with_alpha(color, 0.10))
		draw_circle(center, 200.0, Palette.with_alpha(color, 0.08))
		draw_arc(center, 240.0, 0.0, TAU, 48, Palette.with_alpha(color, 0.4), 4.0)
		# Nuolikuvio joukkueen väristä osoittaa keskelle
		var dir := 1.0 if team == 0 else -1.0
		for i in range(3):
			var ax := cx + dir * (90.0 + i * 40.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(ax, -26), Vector2(ax + dir * 26.0, 0), Vector2(ax, 26)]),
				Palette.with_alpha(color, 0.22))


func _draw_hedges() -> void:
	for rect in _hedges:
		# Varjo
		draw_rect(Rect2(rect.position + Vector2(4, 6), rect.size), Palette.with_alpha(Color.BLACK, 0.25))
		# Pensas
		_rounded_rect(rect, HEDGE_DARK, 14.0)
		_rounded_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 10)), HEDGE, 12.0)
		# Nukkapinta pikkupalloilla
		var rng := RandomNumberGenerator.new()
		rng.seed = int(rect.position.x * 13.0 + rect.position.y)
		var hrect: Rect2 = rect
		var count := int(hrect.size.x * hrect.size.y / 1400.0)
		for i in range(count):
			var p: Vector2 = hrect.position + Vector2(
				rng.randf_range(6, hrect.size.x - 6), rng.randf_range(4, hrect.size.y - 8))
			draw_circle(p, rng.randf_range(4, 7), Palette.with_alpha(Color("54924f"), 0.6))


func _draw_flowers() -> void:
	for flower in _flowers:
		var base := Color.from_hsv(fmod(0.05 + flower.hue * 0.9, 1.0), 0.65, 0.95)
		var sway := sin(_time * 1.5 + flower.hue * TAU) * 2.0
		var pos: Vector2 = flower.pos + Vector2(sway, 0)
		draw_circle(pos, flower.size * 2.4, Palette.with_alpha(base, 0.08))
		var petals: int = int(flower.petals)
		var fsize: float = flower.size
		for p in range(petals):
			var ang: float = TAU * p / float(petals) + _time * 0.2
			var petal: Vector2 = pos + Vector2(cos(ang), sin(ang)) * fsize * 0.9
			draw_circle(petal, fsize * 0.6, base)
		draw_circle(pos, flower.size * 0.55, Color("ffe08a"))


func _draw_belts() -> void:
	for belt in belts:
		var rect: Rect2 = belt.rect
		# Metallinen alusta
		_rounded_rect(rect, Color("2a3346"), 10.0)
		_rounded_rect(Rect2(rect.position + Vector2(0, 4), Vector2(rect.size.x, rect.size.y - 12)),
			Color("39435c"), 8.0)
		draw_rect(rect, Palette.with_alpha(BRASS, 0.45), false, 3.0)
		# Liikkuvat chevron-nuolet
		var dir: Vector2 = belt.dir
		var scroll := fmod(_time * 90.0, 90.0)
		var count := int(rect.size.x / 90.0)
		var cy := rect.position.y + rect.size.y / 2.0
		for i in range(count + 1):
			var base_x: float = rect.position.x + fmod(scroll + i * 90.0, rect.size.x + 90.0) - 45.0
			if base_x < rect.position.x + 10.0 or base_x > rect.end.x - 30.0:
				continue
			var tip := Vector2(base_x + (26.0 if dir.x > 0.0 else 6.0), cy)
			var tail := Vector2(base_x + (6.0 if dir.x > 0.0 else 26.0), cy)
			draw_line(Vector2(tail.x, cy - 20.0), tip, Palette.with_alpha(BRASS, 0.85), 5.0)
			draw_line(Vector2(tail.x, cy + 20.0), tip, Palette.with_alpha(BRASS, 0.85), 5.0)
		# Reunatelojen niitit
		for rivet_x in range(int(rect.position.x) + 20, int(rect.end.x), 60):
			draw_circle(Vector2(rivet_x, rect.position.y + 8.0), 3.0, Palette.with_alpha(BRASS, 0.5))
			draw_circle(Vector2(rivet_x, rect.end.y - 8.0), 3.0, Palette.with_alpha(BRASS, 0.5))


func _draw_pillars() -> void:
	for i in range(pillars.size()):
		var pillar = pillars[i]
		var spin: float = _time * (0.4 if i % 2 == 0 else -0.4)
		# Varjo
		draw_circle(pillar.pos + Vector2(0, 10), pillar.radius, Palette.with_alpha(Color.BLACK, 0.25))
		# Messinkiratas kiillolla
		_draw_gear(pillar.pos, pillar.radius, spin, 9, BRASS, BRASS_DARK,
			Palette.glow(Color("ffe6b0"), 1.2))
		draw_circle(pillar.pos, pillar.radius * 0.35, Color("5b4420"))
		draw_circle(pillar.pos, pillar.radius * 0.16, BRASS)
		# Kolme pulttia napaan
		for b in range(3):
			var ang := spin * 0.5 + TAU * b / 3.0
			draw_circle(pillar.pos + Vector2(cos(ang), sin(ang)) * pillar.radius * 0.24, 4.0,
				Color("3a2c12"))


func _draw_center_pad() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	# Kuusikulmainen kohdealusta
	var hex := PackedVector2Array()
	for i in range(6):
		hex.append(Vector2.RIGHT.rotated(TAU * i / 6.0 + PI / 6.0) * 140.0)
	draw_colored_polygon(hex, Palette.with_alpha(Palette.GOLD, 0.08))
	draw_polyline(hex + PackedVector2Array([hex[0]]),
		Palette.with_alpha(Palette.GOLD, 0.35 + pulse * 0.2), 3.0)
	draw_arc(Vector2.ZERO, 120.0, 0.0, TAU, 64, Palette.with_alpha(Palette.GOLD, 0.30), 3.0)
	# Kiertävät merkit
	for i in range(6):
		var ang := _time * 0.4 + TAU * i / 6.0
		draw_circle(Vector2(cos(ang), sin(ang)) * 110.0, 4.0,
			Palette.with_alpha(Palette.GOLD, 0.4))


func _rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	var r: float = minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	draw_rect(Rect2(rect.position + Vector2(r, 0), rect.size - Vector2(r * 2.0, 0)), color)
	draw_rect(Rect2(rect.position + Vector2(0, r), rect.size - Vector2(0, r * 2.0)), color)
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, color)
	draw_circle(rect.position + Vector2(r, rect.size.y - r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, rect.size.y - r), r, color)
