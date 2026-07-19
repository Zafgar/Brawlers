class_name MapMoba
extends MapBase
## Suuri MOBA-kartta: yläpuoli on viidakko (leirit + pomo), alapuoli on LINJA
## jota pitkin minionit marssivat. Kummallakin puolella on tukikohta (nexus) ja
## kaksi tornia linjalla. Voitto = tuhoa vihollisen nexus (tornit ensin).
##
## Sininen (joukkue 0) vasemmalla, oranssi (joukkue 1) oikealla.

const FLOOR := Color("15321f")
const FLOOR_ALT := Color("1a3b25")
const CANOPY := Color("0d2417")
const LEAF := Color("3f8f4e")
const LANE := Color("3a3324")
const LANE_EDGE := Color("54492f")
const RIVER := Color("1e4a5c")

# Viidakko (yläpuoli)
var _boss := Vector2(0, -800)
var _points := Vector2(0, -340)
var _dmg_left := Vector2(-1150, -560)
var _dmg_right := Vector2(1150, -560)

# Linja (alapuoli): tornit ja nexukset
var _nexus_blue := Vector2(-2000, 780)
var _nexus_orange := Vector2(2000, 780)
var _tower_blue := [Vector2(-760, 660), Vector2(-1480, 720)]    # [ulompi (keskelle), sisempi (basea suojaava)]
var _tower_orange := [Vector2(760, 660), Vector2(1480, 720)]


func _setup() -> void:
	map_size = Vector2(4400, 2600)
	var half := map_size / 2.0

	# Aloituspaikat tukikohtien luo.
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var oy := -60.0 + i * 90.0
		blue.append(Vector2(-2000.0 + 90.0, 820.0 + oy))
		orange.append(Vector2(2000.0 - 90.0, 820.0 + oy))
	spawn_slots = [blue, orange]

	# Puita/kiviä suojaksi viidakkoon; linja pidetään avoimena.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720
	var blocked: Array = [_boss, _points, _dmg_left, _dmg_right,
		_nexus_blue, _nexus_orange]
	for t in _tower_blue:
		blocked.append(t)
	for t in _tower_orange:
		blocked.append(t)
	var tries := 0
	while pillars.size() < 14 and tries < 260:
		tries += 1
		var p := Vector2(rng.randf_range(-half.x + 300.0, half.x - 300.0),
			rng.randf_range(-half.y + 260.0, -120.0))   # vain yläpuoli (viidakko)
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
			pillars.append({"pos": p, "radius": rng.randf_range(46.0, 76.0)})


# --- Paikat (areena kysyy näitä) ---

func damage_camps() -> Array:
	return [_dmg_left, _dmg_right]


func points_camp() -> Vector2:
	return _points


func boss_spot() -> Vector2:
	return _boss


func nexus_spot(team: int) -> Vector2:
	return _nexus_blue if team == 0 else _nexus_orange


## Tornipaikat: [ulompi (keskelle päin), sisempi (nexusta suojaava)].
func tower_spots(team: int) -> Array:
	return _tower_blue if team == 0 else _tower_orange


## Minionien reittipisteet sinisestä oranssiin. Oranssi kulkee käänteisesti.
func lane_path() -> Array:
	return [
		Vector2(-2000, 900), Vector2(-1480, 760), Vector2(-760, 700),
		Vector2(0, 680), Vector2(760, 700), Vector2(1480, 760), Vector2(2000, 900)]


func _draw() -> void:
	var half := map_size / 2.0

	draw_rect(Rect2(-half - Vector2(600, 600), map_size + Vector2(1200, 1200)), CANOPY)
	draw_rect(Rect2(-half, map_size), FLOOR)

	# Viidakon laikutus (yläpuoli).
	var rng := RandomNumberGenerator.new()
	rng.seed = 81724
	for i in range(70):
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, 120.0))
		draw_circle(p, rng.randf_range(60.0, 200.0), Palette.with_alpha(FLOOR_ALT, 0.5))

	# Jokivyö erottaa viidakon ja linjan (n. y=200).
	_draw_river(half)

	# LINJA alapuolelle: leveä päällystetty kaista tukikohtien välillä.
	_draw_lane()

	# Nexus-alustat ja tornipohjat (rakennukset itse piirtyvät entiteetteinä).
	_platform(_nexus_blue, 150.0, Palette.team(0))
	_platform(_nexus_orange, 150.0, Palette.team(1))
	for t in _tower_blue:
		_platform(t, 78.0, Palette.team(0))
	for t in _tower_orange:
		_platform(t, 78.0, Palette.team(1))

	# Viidakon leirimerkit ja pomomonttu (yläpuoli).
	_camp_marker(_dmg_left, Color("e08a3c"))
	_camp_marker(_dmg_right, Color("e08a3c"))
	_camp_marker(_points, Color("e0c23c"))
	_boss_pit(_boss)

	# Latvuston lehtiläikät esteiden päällä.
	for pillar in pillars:
		draw_circle(pillar.pos + Vector2(0, 6), pillar.radius + 6.0, Color(0.03, 0.09, 0.05, 0.6))
		draw_circle(pillar.pos, pillar.radius, Palette.darker(LEAF, 0.4))
		draw_circle(pillar.pos + Vector2(-pillar.radius * 0.3, -pillar.radius * 0.3),
			pillar.radius * 0.5, Palette.with_alpha(LEAF, 0.55))

	_draw_walls_frame(LEAF, CANOPY)
	_draw_vignette()
	_draw_motes(80, Color("bfe6a0"), 14.0, 4343)


func _draw_river(half: Vector2) -> void:
	var y := 210.0
	var band := 90.0
	draw_rect(Rect2(-half.x, y - band * 0.5, map_size.x, band), Palette.with_alpha(RIVER, 0.5))
	for i in range(3):
		var yy := y - band * 0.5 + band * (float(i) + 0.5) / 3.0
		draw_line(Vector2(-half.x, yy), Vector2(half.x, yy),
			Palette.with_alpha(Palette.glow(RIVER, 1.3), 0.3), 2.0)


func _draw_lane() -> void:
	var pts := lane_path()
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], LANE_EDGE, 150.0)
		draw_line(pts[i], pts[i + 1], LANE, 128.0)
	# Keskiviivan katkoviiva.
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var segs := 6
		for s in range(segs):
			if s % 2 == 0:
				var p0: Vector2 = a.lerp(b, float(s) / segs)
				var p1: Vector2 = a.lerp(b, float(s + 1) / segs)
				draw_line(p0, p1, Palette.with_alpha(LANE_EDGE, 0.6), 3.0)


## Rakennuksen alusta (tornit/nexus piirtyvät päälle entiteetteinä).
func _platform(pos: Vector2, r: float, team_col: Color) -> void:
	draw_circle(pos, r, Palette.with_alpha(Color("22201a"), 0.9))
	draw_arc(pos, r, 0.0, TAU, 40, Palette.with_alpha(team_col, 0.5), 4.0)
	draw_circle(pos, r * 0.7, Palette.with_alpha(team_col, 0.08))


func _camp_marker(pos: Vector2, color: Color) -> void:
	draw_circle(pos, 116.0, Palette.with_alpha(color, 0.08))
	draw_arc(pos, 106.0, 0.0, TAU, 40, Palette.with_alpha(color, 0.5), 3.0)
	draw_arc(pos, 90.0, _time * 0.5, _time * 0.5 + TAU * 0.7, 30,
		Palette.with_alpha(Palette.glow(color, 1.3), 0.5), 2.0)


func _boss_pit(pos: Vector2) -> void:
	draw_circle(pos, 200.0, Palette.with_alpha(Color("2a1030"), 0.55))
	draw_arc(pos, 190.0, 0.0, TAU, 52, Palette.with_alpha(Color("b64ad6"), 0.55), 4.0)
	draw_arc(pos, 165.0, -_time * 0.4, -_time * 0.4 + TAU, 52,
		Palette.with_alpha(Palette.glow(Color("b64ad6"), 1.2), 0.35), 2.0)
