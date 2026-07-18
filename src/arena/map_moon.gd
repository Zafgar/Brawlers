class_name MapMoon
extends MapBase
## Moonstone Ruins — taianomaiset rauniot. Symmetrinen rakenne, hohtavat
## kristallit, riimuympyrät ja ajoittain avautuvat portit sivukäytävillä.
## Kristallit reagoivat lähellä oleviin hahmoihin kirkastumalla.

const FLOOR_BASE := Color("1b1a38")
const FLOOR_LIGHT := Color("332f66")
const STONE := Color("3b3663")
const STONE_DARK := Color("221f42")
const CRYSTAL_A := Color("6fe6ff")
const CRYSTAL_B := Color("c77bff")
const MOONLIGHT := Color("cdd6ff")
const RUNE := Color("9a86ff")

const GATE_PERIOD := 8.0
const GATE_OPEN_FROM := 5.0     # portti auki kun sykli > tämä

var _crystals: Array = []       # {pos, color, size}
var _rubble: Array = []
var _gates: Array = []          # {body, rect, open}


func _setup() -> void:
	map_size = Vector2(2400, 1350)
	# Neljä suurta kristallipylvästä symmetrisesti + kaksi keskellä.
	pillars = [
		{"pos": Vector2(-620, -260), "radius": 82.0},
		{"pos": Vector2(620, -260), "radius": 82.0},
		{"pos": Vector2(-620, 260), "radius": 82.0},
		{"pos": Vector2(620, 260), "radius": 82.0},
		{"pos": Vector2(0, -430), "radius": 66.0},
		{"pos": Vector2(0, 430), "radius": 66.0},
	]

	# Ajoittain avautuvat portit sivujen pylväiden (±620, ±260) väliseen
	# aukkoon: kiinni ollessaan estävät sivujen oikoreitin.
	for side in [-1.0, 1.0]:
		var rect := Rect2(Vector2(side * 620.0 - 22.0, -110.0), Vector2(44, 220))
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = rect.get_center()
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = rect.size
		shape.shape = rect_shape
		body.add_child(shape)
		add_child(body)
		_gates.append({"body": body, "rect": rect, "open": false})

	# Kristallit pylväiden päällä ja siroteltuina.
	for pillar in pillars:
		_crystals.append({
			"pos": pillar.pos, "color": CRYSTAL_A if pillar.pos.x < 0 else CRYSTAL_B,
			"size": pillar.radius * 0.5})
	var rng := RandomNumberGenerator.new()
	rng.seed = 990077
	for i in range(10):
		var p := Vector2(rng.randf_range(-1000, 1000), rng.randf_range(-560, 560))
		if p.length() < 200.0:
			continue
		_crystals.append({"pos": p, "color": CRYSTAL_A if rng.randf() < 0.5 else CRYSTAL_B,
			"size": rng.randf_range(14.0, 26.0)})
	# Kiviraunioita koristeeksi
	for i in range(16):
		_rubble.append({
			"pos": Vector2(rng.randf_range(-map_size.x / 2.0 + 100, map_size.x / 2.0 - 100),
				rng.randf_range(-map_size.y / 2.0 + 100, map_size.y / 2.0 - 100)),
			"size": rng.randf_range(10.0, 28.0),
			"rot": rng.randf() * TAU})


func _process(delta: float) -> void:
	_time += delta
	# Porttien avautumissykli
	var cycle := fmod(_time, GATE_PERIOD)
	var should_open := cycle > GATE_OPEN_FROM
	for gate in _gates:
		if gate.open != should_open:
			gate.open = should_open
			gate.body.collision_layer = 0 if should_open else 1
	queue_redraw()


# --- Piirto ---

func _draw() -> void:
	var half := map_size / 2.0
	draw_rect(Rect2(-half - Vector2(500, 500), map_size + Vector2(1000, 1000)), Color("0a0918"))

	_draw_floor(half)
	_draw_runes()
	_draw_team_bases(half)
	_draw_rubble()
	_draw_pillars()
	_draw_crystals()
	_draw_gates()
	_draw_center_pad()

	_draw_motes(30, CRYSTAL_A, 14.0, 7788)
	_draw_vignette()
	_draw_walls_frame(Color("7d6fd6"))


func _draw_floor(half: Vector2) -> void:
	draw_rect(Rect2(-half, map_size), FLOOR_BASE)
	# Kuunvalo keskelle -> kirkas ja taianomainen, ei synkkä
	for i in range(7):
		var r := 780.0 - i * 105.0
		draw_circle(Vector2.ZERO, r, Palette.with_alpha(MOONLIGHT, 0.035 + i * 0.012))
	# Kivilaatat
	var tile := 190.0
	var cols := int(map_size.x / tile)
	var rows := int(map_size.y / tile)
	for gx in range(cols + 1):
		for gy in range(rows + 1):
			var p := Vector2(-half.x + gx * tile, -half.y + gy * tile)
			if (gx + gy) % 2 == 0:
				draw_rect(Rect2(p, Vector2(tile, tile)), Palette.with_alpha(FLOOR_LIGHT, 0.14))
	for gx in range(cols + 1):
		var x := -half.x + gx * tile
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), Palette.with_alpha(RUNE, 0.06), 1.5)
	for gy in range(rows + 1):
		var y := -half.y + gy * tile
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), Palette.with_alpha(RUNE, 0.06), 1.5)


func _draw_runes() -> void:
	# Kolme sisäkkäistä hitaasti pyörivää riimuympyrää keskelle
	for ring in range(3):
		var r := 150.0 + ring * 90.0
		var spin: float = _time * (0.12 if ring % 2 == 0 else -0.12)
		var seg := 8 + ring * 4
		for i in range(seg):
			var a0 := spin + TAU * i / seg
			var a1 := a0 + TAU / seg * 0.6
			draw_arc(Vector2.ZERO, r, a0, a1, 8, Palette.with_alpha(RUNE, 0.18), 2.0)
		# Riimumerkit kehälle
		for i in range(seg / 2):
			var ang := spin * 1.5 + TAU * i / (seg / 2)
			var p := Vector2(cos(ang), sin(ang)) * r
			draw_circle(p, 3.0, Palette.with_alpha(RUNE, 0.3))


func _draw_team_bases(half: Vector2) -> void:
	for team in [0, 1]:
		var cx := -half.x + 210.0 if team == 0 else half.x - 210.0
		var color := Palette.team(team)
		var center := Vector2(cx, 0)
		draw_circle(center, 250.0, Palette.with_alpha(color, 0.10))
		draw_arc(center, 240.0, 0.0, TAU, 48, Palette.with_alpha(color, 0.4), 4.0)
		# Portin muotoinen kaari tukikohdan takana (aukeaa kohti keskustaa)
		if team == 1:
			draw_arc(center, 150.0, PI * 0.5, PI * 1.5, 24, Palette.with_alpha(color, 0.35), 6.0)
		else:
			draw_arc(center, 150.0, -PI * 0.5, PI * 0.5, 24, Palette.with_alpha(color, 0.35), 6.0)


func _draw_rubble() -> void:
	for chunk in _rubble:
		var pos: Vector2 = chunk.pos
		draw_circle(pos + Vector2(0, 5), chunk.size, Palette.with_alpha(Color.BLACK, 0.2))
		var poly := PackedVector2Array()
		var crot: float = chunk.rot
		var csize: float = chunk.size
		for i in range(5):
			var ang: float = crot + TAU * i / 5.0
			var rr: float = csize * (0.7 + 0.3 * sin(i * 2.3))
			poly.append(pos + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(poly, STONE)
		draw_polyline(poly + PackedVector2Array([poly[0]]), STONE_DARK, 2.0)


func _draw_pillars() -> void:
	for pillar in pillars:
		var pos: Vector2 = pillar.pos
		var r: float = pillar.radius
		draw_circle(pos + Vector2(0, 10), r, Palette.with_alpha(Color.BLACK, 0.28))
		# Kivinen jalusta
		var base := PackedVector2Array()
		for i in range(6):
			base.append(pos + Vector2.RIGHT.rotated(TAU * i / 6.0 + PI / 6.0) * r)
		draw_colored_polygon(base, STONE)
		draw_polyline(base + PackedVector2Array([base[0]]), STONE_DARK, 3.0)
		draw_circle(pos, r * 0.6, Palette.darker(STONE, 0.8))


func _draw_crystals() -> void:
	for crystal in _crystals:
		var pos: Vector2 = crystal.pos
		var size: float = crystal.size
		var color: Color = crystal.color
		# Reagoi lähellä oleviin hahmoihin: kirkastuu
		var energy := 0.4 + 0.25 * sin(_time * 2.5 + pos.x * 0.01)
		energy += _proximity_glow(pos)
		energy = clampf(energy, 0.0, 1.4)
		# Hehkukupla
		draw_circle(pos, size * 1.8, Palette.with_alpha(color, 0.12 * energy))
		draw_circle(pos, size * 1.2, Palette.with_alpha(color, 0.15 * energy))
		# Kristallisärmä (timantti)
		var gem := PackedVector2Array([
			pos + Vector2(0, -size), pos + Vector2(size * 0.6, -size * 0.2),
			pos + Vector2(0, size), pos + Vector2(-size * 0.6, -size * 0.2)])
		draw_colored_polygon(gem, Palette.glow(color, 1.0 + energy * 0.6))
		# Sisäsärmät
		draw_line(pos + Vector2(0, -size), pos + Vector2(0, size),
			Palette.with_alpha(Color.WHITE, 0.5 * energy), 1.5)
		draw_line(pos + Vector2(-size * 0.6, -size * 0.2), pos + Vector2(size * 0.6, -size * 0.2),
			Palette.with_alpha(Color.WHITE, 0.35 * energy), 1.0)


## Kuinka paljon lähellä olevat hahmot kirkastavat kristallia (0..0.6).
func _proximity_glow(pos: Vector2) -> float:
	var arena = get_parent()
	if arena == null:
		return 0.0
	var heroes = arena.get("heroes")
	if heroes == null:
		return 0.0
	var boost := 0.0
	for hero in heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		var d: float = hero.global_position.distance_to(pos)
		if d < 180.0:
			boost = maxf(boost, (1.0 - d / 180.0) * 0.6)
	return boost


func _draw_gates() -> void:
	for gate in _gates:
		var rect: Rect2 = gate.rect
		if gate.open:
			# Auki: himmeät riimupylväät, käytävä vapaa
			var pulse := 0.4 + 0.3 * sin(_time * 4.0)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 8)),
				Palette.with_alpha(RUNE, 0.4 * pulse))
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 8), Vector2(rect.size.x, 8)),
				Palette.with_alpha(RUNE, 0.4 * pulse))
			# Portaalikimallus
			for i in range(3):
				var y := rect.position.y + rect.size.y * (0.2 + i * 0.3)
				draw_circle(Vector2(rect.get_center().x, y), 3.0,
					Palette.with_alpha(CRYSTAL_B, 0.5 * pulse))
		else:
			# Kiinni: kiinteä energiaportti estää kulun
			var shimmer := 0.7 + 0.3 * sin(_time * 6.0)
			draw_rect(rect, Palette.with_alpha(RUNE, 0.25))
			for i in range(5):
				var t := i / 4.0
				var y := rect.position.y + rect.size.y * t
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y),
					Palette.with_alpha(Palette.glow(CRYSTAL_B, 1.3), 0.6 * shimmer), 2.0)
			draw_rect(rect, Palette.with_alpha(Palette.glow(CRYSTAL_B, 1.2), shimmer), false, 3.0)


func _draw_center_pad() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 2.0)
	# Kuunkivialusta reliikille
	draw_circle(Vector2.ZERO, 130.0, Palette.with_alpha(MOONLIGHT, 0.06))
	var ring := PackedVector2Array()
	for i in range(8):
		ring.append(Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 0.2) * 128.0)
	draw_polyline(ring + PackedVector2Array([ring[0]]),
		Palette.with_alpha(CRYSTAL_A, 0.4 + pulse * 0.2), 3.0)
	draw_arc(Vector2.ZERO, 110.0, 0.0, TAU, 48, Palette.with_alpha(MOONLIGHT, 0.3), 2.0)
