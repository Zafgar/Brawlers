class_name MapJungle
extends MapBase
## Suuri viidakkokartta jaettua ruutua ja viidakko-pelimuotoa varten.
## Joukkueet aloittavat vastakkaisilta laidoilta. Kentällä on kolme leiriä:
## kaksi sivuvahinkoleiriä (molemmin puolin), yksi keskeinen pistereiri, ja
## keskustan pomomonttu johon pomo ilmestyy ajastimella.
##
## Leiripaikat luetaan areenasta (damage_camps/points_camp/boss_spot).

const FLOOR := Color("15321f")
const FLOOR_ALT := Color("1a3b25")
const CANOPY := Color("0d2417")
const LEAF := Color("3f8f4e")
const PATH := Color("2a2418")

var _boss := Vector2(0, -140)
var _points := Vector2(0, 560)
var _dmg_left := Vector2(-1120, 140)
var _dmg_right := Vector2(1120, 140)


func _setup() -> void:
	map_size = Vector2(3400, 1900)
	# Suuri staattinen pohja (laikut, polut, leirit, esteet, kehykset) piirretään
	# vain kerran; ainoat liikkuvat osat (leirien hehkukaaret ja hiukkaset)
	# elävät pienessä overlay-kerroksessa — sama malli kuin Eternal Dividella.
	# Ilman jakoa koko ~200 komennon kartta rakennettiin uudelleen joka framella
	# jokaiseen split-viewporttiin.
	animate_full_canvas = false
	var animation := JungleMapAnimation.new()
	animation.map = self
	add_child(animation)
	var half := map_size / 2.0

	# Aloituspaikat: sininen vasemmalla, oranssi oikealla (neljä paikkaa kumpikin).
	var bx := half.x - 220.0
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var y := -330.0 + i * 220.0
		blue.append(Vector2(-bx, y))
		orange.append(Vector2(bx, y))
	spawn_slots = [blue, orange]

	# Puita/kiviä suojaksi — pidä leirit ja keskilinjat vapaina.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260719
	var blocked: Array = [_boss, _points, _dmg_left, _dmg_right,
		Vector2(-bx, 0), Vector2(bx, 0)]
	var tries := 0
	while pillars.size() < 12 and tries < 200:
		tries += 1
		var p := Vector2(rng.randf_range(-half.x + 260.0, half.x - 260.0),
			rng.randf_range(-half.y + 240.0, half.y - 240.0))
		var ok := true
		for b in blocked:
			if p.distance_to(b) < 360.0:
				ok = false
				break
		for existing in pillars:
			if p.distance_to(existing.pos) < 320.0:
				ok = false
				break
		if ok:
			pillars.append({"pos": p, "radius": rng.randf_range(46.0, 74.0)})


# --- Leiripaikat (areena kysyy näitä) ---

func damage_camps() -> Array:
	return [_dmg_left, _dmg_right]


func points_camp() -> Vector2:
	return _points


func boss_spot() -> Vector2:
	return _boss


func _draw() -> void:
	var half := map_size / 2.0

	# Reunojen ulkopuoli tumma latvusto
	draw_rect(Rect2(-half - Vector2(600, 600), map_size + Vector2(1200, 1200)), CANOPY)
	# Lattia
	draw_rect(Rect2(-half, map_size), FLOOR)

	# Orgaaninen laikutus (vaaleammat aukot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71723
	for i in range(60):
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var rr := rng.randf_range(60.0, 190.0)
		draw_circle(p, rr, Palette.with_alpha(FLOOR_ALT, 0.5))

	# Kulkupolut leirien välillä (himmeät)
	_path(Vector2(-half.x + 220.0, 0), _dmg_left)
	_path(Vector2(half.x - 220.0, 0), _dmg_right)
	_path(_dmg_left, _boss)
	_path(_dmg_right, _boss)
	_path(_boss, _points)

	# Leirimerkit
	_camp_marker(_dmg_left, Color("e08a3c"), "V")
	_camp_marker(_dmg_right, Color("e08a3c"), "V")
	_camp_marker(_points, Color("e0c23c"), "P")
	_boss_pit(_boss)

	# Latvuston lehtiläikät (koristeena esteiden päällä)
	for pillar in pillars:
		draw_circle(pillar.pos + Vector2(0, 6), pillar.radius + 6.0, Color(0.03, 0.09, 0.05, 0.6))
		draw_circle(pillar.pos, pillar.radius, Palette.darker(LEAF, 0.4))
		draw_circle(pillar.pos + Vector2(-pillar.radius * 0.3, -pillar.radius * 0.3),
			pillar.radius * 0.5, Palette.with_alpha(LEAF, 0.55))
		draw_circle(pillar.pos + Vector2(pillar.radius * 0.25, pillar.radius * 0.2),
			pillar.radius * 0.45, Palette.with_alpha(Palette.darker(LEAF, 0.2), 0.5))

	_draw_walls_frame(LEAF, CANOPY)
	_draw_vignette()
	# Hiukkaset (motes) piirtää JungleMapAnimation-overlay — pohja pysyy
	# staattisena eikä sitä piirretä uudelleen joka framella.


## Himmeä polku kahden pisteen välille.
func _path(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, Palette.with_alpha(PATH, 0.5), 62.0)
	draw_line(a, b, Palette.with_alpha(FLOOR_ALT, 0.6), 44.0)


## Leirin maamerkki: hehkuva rengas ja tunnuskirjain. Kiertävän hehkukaaren
## piirtää JungleMapAnimation-overlay (ainoa animoitu osa).
func _camp_marker(pos: Vector2, color: Color, letter: String) -> void:
	draw_circle(pos, 118.0, Palette.with_alpha(color, 0.08))
	draw_arc(pos, 108.0, 0.0, TAU, 40, Palette.with_alpha(color, 0.5), 3.0)
	UiKit.draw_text(self, pos + Vector2(0, -140.0), letter, 26,
		Palette.with_alpha(color, 0.8), true)


## Keskustan pomomonttu.
func _boss_pit(pos: Vector2) -> void:
	draw_circle(pos, 200.0, Palette.with_alpha(Color("2a1030"), 0.55))
	draw_arc(pos, 190.0, 0.0, TAU, 52, Palette.with_alpha(Color("b64ad6"), 0.55), 4.0)
	# Täysi ympyräkaari: kierto oli näkymätön (alku- ja loppukulma kattavat aina
	# koko kehän), joten kaari voi olla staattinen ilman visuaalista muutosta.
	draw_arc(pos, 165.0, 0.0, TAU, 52,
		Palette.with_alpha(Palette.glow(Color("b64ad6"), 1.2), 0.35), 2.0)
	# Kuusikulmainen areenakuvio
	var hexa := PackedVector2Array()
	for i in range(6):
		var a: float = TAU * i / 6.0 + PI / 6.0
		hexa.append(pos + Vector2(cos(a), sin(a)) * 150.0)
	hexa.append(hexa[0])
	draw_polyline(hexa, Palette.with_alpha(Color("d98adf"), 0.4), 2.0)


## Viidakkokartan liikkuvat yksityiskohdat (leirien hehkukaaret ja hiukkaset)
## omana kevyenä kerroksenaan. Staattinen karttapohja säilyy välimuistissa —
## vain tämä pieni komentolista piirretään uudelleen joka framella.
class JungleMapAnimation:
	extends Node2D

	var map: MapJungle = null
	var _time := 0.0
	var _motes: Array = []
	var _sweeps: Array = []   # [{pos, color}] leirien kaaret (ei kyselyä per frame)

	func _ready() -> void:
		z_index = 1
		if map == null:
			return
		for camp in map.damage_camps():
			_sweeps.append({"pos": camp, "color": Color("e08a3c")})
		_sweeps.append({"pos": map.points_camp(), "color": Color("e0c23c")})
		# Samat hiukkasparametrit kuin aiemmassa MapBase._draw_motes-kutsussa
		# (70 kpl, nousu 14.0, siemen 4242) -> identtinen ulkoasu.
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var half: Vector2 = map.size() / 2.0
		for _i in range(70):
			_motes.append({
				"x": rng.randf_range(-half.x, half.x),
				"y": rng.randf_range(-half.y, half.y),
				"speed": rng.randf_range(0.5, 1.5) * 14.0,
				"drift": rng.randf_range(-14.0, 14.0),
				"radius": rng.randf_range(1.5, 4.0),
				"tint": rng.randf(),
			})

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		if map == null:
			return
		# Leirien kiertävät hehkukaaret (staattinen rengas on karttapohjassa).
		for entry in _sweeps:
			_sweep(entry.pos, entry.color)
		_draw_motes(Color("bfe6a0"))

	func _sweep(pos: Vector2, color: Color) -> void:
		draw_arc(pos, 92.0, _time * 0.5, _time * 0.5 + TAU * 0.7, 30,
			Palette.with_alpha(Palette.glow(color, 1.3), 0.5), 2.0)

	func _draw_motes(base_color: Color) -> void:
		var half: Vector2 = map.size() / 2.0
		for mote in _motes:
			var tint: float = mote.tint
			var y: float = fmod(float(mote.y) - _time * float(mote.speed), map.size().y)
			if y < -half.y:
				y += map.size().y
			var x: float = float(mote.x) + sin(_time * 0.4 + tint * TAU) * float(mote.drift)
			var alpha: float = 0.10 + 0.12 * (0.5 + 0.5 * sin(_time * 1.5 + tint * TAU))
			draw_circle(Vector2(x, y), float(mote.radius),
				Palette.with_alpha(base_color, alpha))