class_name MapMoba
extends MapBase
## 4v4-kartan pitkän aikavälin pohja: top + bottom, niiden välissä kaksiosainen
## viidakko sekä erilliset Baron- ja Dragon-pitit. Sininen aloittaa vasemmalta,
## oranssi oikealta. Kaikki taktiset reitit annetaan samasta rajapinnasta myös
## minioneille, boteille ja minimapille.

const FLOOR := Color("183d27")
const FLOOR_ALT := Color("235333")
const CANOPY := Color("081b12")
const LANE := Color("5b4d34")
const LANE_EDGE := Color("8b7550")
const RIVER := Color("1f6c82")
const WALL := Color("244332")
const WALL_EDGE := Color("68a16e")
const GOLD := Color("e7c34b")
const CLAW := Color("dc7136")
const BARON_COL := Color("bd60e5")
const DRAGON_COL := Color("49d7c5")

const TOP := "top"
const BOTTOM := "bottom"

var _nexus := [Vector2(-3000, 0), Vector2(3000, 0)]
var _baron := Vector2(0, -650)
var _dragon := Vector2(0, 650)
var _sanctuary := [Rect2(-3570, -470, 400, 940), Rect2(3170, -470, 400, 940)]
var _shop := [Vector2(-3390, 275), Vector2(3390, 275)]
var _fountain := [Vector2(-3400, 0), Vector2(3400, 0)]

# Järjestys on aina outer -> inner -> base. Torni on 140 px linjan
# keskiviivan jungle-puolella, joten minionit eivät törmää sen runkoon.
var _towers := {
	0: {
		TOP: [Vector2(-1050, -1510), Vector2(-2050, -1540), Vector2(-2880, -1220)],
		BOTTOM: [Vector2(-1050, 1510), Vector2(-2050, 1540), Vector2(-2880, 1220)],
	},
	1: {
		TOP: [Vector2(1050, -1510), Vector2(2050, -1540), Vector2(2880, -1220)],
		BOTTOM: [Vector2(1050, 1510), Vector2(2050, 1540), Vector2(2880, 1220)],
	},
}

var _red_camps := [Vector2(-2220, -720), Vector2(2220, 720)]
var _blue_camps := [Vector2(-2220, 720), Vector2(2220, -720)]
var _small_camps := [
	Vector2(-1510, -720), Vector2(-1510, 720), Vector2(-2300, 0),
	Vector2(1510, -720), Vector2(1510, 720), Vector2(2300, 0),
]
# Linjojen ulkoreunan kiistellyt alcovet: eivat kuulu kummankaan junglerin
# turvalliseen viiden campin looppiin, vaan lanerit joutuvat poistumaan aallolta.
var _lane_wildlife := [Vector2(0, -2020), Vector2(0, 2020)]
var _patches: Array = []
var _trees: Array = []
var _brushes: Array = []        # Rect2-alueet: tuleva fog/vision + nykyinen AI-näkö
var _corner_massifs: Array = [] # kulmien kalliomassiivien portaat (myös rect_walls-osia)


func _setup() -> void:
	map_size = Vector2(7200, 4400)
	# Kartan satoja staattisia polkuja, puita, seiniä ja merkkejä ei rakenneta
	# uudelleen 60 kertaa sekunnissa jokaiselle split-viewportille. Liikkuvat
	# yksityiskohdat elävät erillisessä pienessä overlay-kerroksessa.
	animate_full_canvas = false
	# Kaikki heräävät oikeassa basessa. Roolit ohjaavat botit topiin,
	# jungleen ja bottom-duoksi; kuoleman jälkeen palataan silti baseen.
	spawn_slots = [
		[Vector2(-3420, -205), Vector2(-3310, -70), Vector2(-3310, 70), Vector2(-3420, 205)],
		[Vector2(3420, -205), Vector2(3310, -70), Vector2(3310, 70), Vector2(3420, 205)],
	]
	_setup_barriers()
	_setup_cover()
	_setup_brushes()
	_setup_decor()
	var animation := MobaMapAnimation.new()
	animation.map = self
	add_child(animation)


func _setup_barriers() -> void:
	# Linjojen ja viidakon väliset harjanteet. Aukot ovat lane-gankkien
	# kiertopisteitä; molempien puolien geometria on täysin peilattu.
	var segments: Array = [
		# Base-alueilla harjanne korvataan tiimikohtaisilla energiaporteilla.
		-2200.0, -1160.0, -880.0, -160.0,
		160.0, 880.0, 1160.0, 2200.0,
	]
	for y in [-1250.0, 1250.0]:
		for i in range(0, segments.size(), 2):
			var a: float = segments[i]
			var b: float = segments[i + 1]
			rect_walls.append(Rect2(a, y - 34.0, b - a, 68.0))

	# Objective-pittien kaaret tehdään suorista lohkareista. Pitit ovat auki
	# vasemmalta ja oikealta, mutta niiden pohjois/eteläreittejä voi kontrolloida.
	for center_y in [-650.0, 650.0]:
		rect_walls.append(Rect2(-360, center_y - 300, 720, 55))
		rect_walls.append(Rect2(-360, center_y + 245, 720, 55))
	# Combat-basen jungle-seinässä on kaksi oman tiimin oikoreittiä. Top/bottom-
	# lane kiertää seinän päistä täysin avoimesti: base-torni suojaa, ei portti.
	for x in [-2570.0, 2500.0]:
		rect_walls.append(Rect2(x, -1100, 70, 330))
		rect_walls.append(Rect2(x, -530, 70, 1060))
		rect_walls.append(Rect2(x, 770, 70, 330))

	# Pitka keskiselanne erottaa top- ja bottom-junglen. Kaksi ylitysta per puoli
	# (river 700 ja deep jungle 1990) tekee rotaatioreitista tietoisen valinnan.
	rect_walls.append(Rect2(-1850, -45, 950, 90))
	rect_walls.append(Rect2(900, -45, 950, 90))
	# Jokainen quadrantti saa sisemman camp-taskun ja base-campin alcoven.
	# Seinien valiset aukot osuvat tarkoituksella jungle_paths()-risteyksiin.
	var quadrant_walls := [
		Rect2(1120, 340, 690, 82), Rect2(1260, 970, 550, 82),
		Rect2(1770, 340, 82, 200), Rect2(1770, 830, 82, 222),
		Rect2(2130, 340, 340, 82), Rect2(2130, 990, 250, 82),
		Rect2(2090, 340, 82, 210), Rect2(2090, 830, 82, 242),
	]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for wall in quadrant_walls:
				rect_walls.append(_mirror_quadrant_rect(wall, sx, sy))
	# Top- ja bottom-linjan ulkoreunan bounty-alcovet. Kartan reunaseina sulkee
	# taskun takaa; sivuseinat jattavat yhden luettavan sisaan-/uloskaynnin.
	rect_walls.append(Rect2(-210, -2180, 50, 230))
	rect_walls.append(Rect2(160, -2180, 50, 230))
	rect_walls.append(Rect2(-210, 1950, 50, 230))
	rect_walls.append(Rect2(160, 1950, 50, 230))

	# Kulmien kalliomassiivit: porrastettu diagonaali sulkee neljän kulman
	# kuolleet kiilat linjan kaarta myötäillen. Portaiden ja linjan väliin jää
	# pieni tasku, johon _setup_brushes lisää juke-puskan. Portaat ovat myös
	# collision-seiniä; _draw_corner_forest pukee ne metsäksi.
	var corner_steps := [
		Rect2(2600, 2070, 1000, 130), Rect2(2720, 1955, 880, 130),
		Rect2(2860, 1840, 740, 130), Rect2(3020, 1725, 580, 130),
		Rect2(3200, 1610, 400, 130), Rect2(3360, 1505, 240, 120),
		Rect2(3450, 1250, 150, 255),
	]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for step in corner_steps:
				var placed := _mirror_quadrant_rect(step, sx, sy)
				_corner_massifs.append(placed)
				rect_walls.append(placed)


func _mirror_quadrant_rect(rect: Rect2, sx: float, sy: float) -> Rect2:
	var x := rect.position.x if sx > 0.0 else -rect.end.x
	var y := rect.position.y if sy > 0.0 else -rect.end.y
	return Rect2(x, y, rect.size.x, rect.size.y)

func _setup_cover() -> void:
	# Pienet, symmetriset maastoesteet luovat gank-kulmia tukkimatta reittejä.
	var seeds := [
		Vector2(420, -1030), Vector2(830, -480),
		Vector2(1180, 150),
	]
	for p in seeds:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				pillars.append({"pos": Vector2(p.x * sx, p.y * sy), "radius": 56.0})
	# Linjakohtaiset suojakivet ovat sivussa minionien keskireitiltä.
	for x in [-2550.0, -1650.0, -520.0, 520.0, 1650.0, 2550.0]:
		pillars.append({"pos": Vector2(x, -1910), "radius": 48.0})
		pillars.append({"pos": Vector2(x, 1910), "radius": 48.0})


func _setup_brushes() -> void:
	# Jokaisella linjalla on viisi luettavaa gank-porttia. Puska on jungle-puolella,
	# joten linjapelaaja näkee sisään vain tulemalla lähelle tai ward-järjestelmällä
	# myöhemmin. Rect2 on samalla AI:n näkyvyysalueen täsmällinen lähde.
	for x in [-2350.0, -1020.0, 0.0, 1020.0, 2350.0]:
		_brushes.append(Rect2(x - 125.0, -1210.0, 250.0, 150.0))
		_brushes.append(Rect2(x - 125.0, 1060.0, 250.0, 150.0))
	# Syvän junglen väijypaikat leirien ja objective-reittien välissä.
	# Puskat vartioivat oikeita valintoja: river-lahestymista, sisemman campin
	# suuaukkoa ja syvan junglen choke-pistetta. Kaikki ovat peilattuja.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for base in [Vector2(560, 650), Vector2(1110, 650), Vector2(1960, 650)]:
				var p := Vector2(base.x * sx, base.y * sy)
				_brushes.append(Rect2(p - Vector2(135, 85), Vector2(270, 170)))
		# Deep crossingin keskuspensas mahdollistaa top/bottom-rotaation vaijytyksen.
		var cross := Vector2(1990 * sx, 0)
		_brushes.append(Rect2(cross - Vector2(120, 90), Vector2(240, 180)))
	# Alcoven kaksi sivupuskaa piilottavat odottajan, mutta keskelle jaa 50 px
	# nakyva kulkuaukko ohjaimella luettavaa sisaanmenoa varten.
	_brushes.append(Rect2(-145, -1950, 120, 145))
	_brushes.append(Rect2(25, -1950, 120, 145))
	_brushes.append(Rect2(-145, 1805, 120, 145))
	_brushes.append(Rect2(25, 1805, 120, 145))
	# Linjan ULKOREUNAN puskat: kaksi per linja reunakaistalla (juket, syvät
	# gankit tornin ohi). Jungle-puolen viisi puskaa saavat vastaparin.
	for x in [-1700.0, 1700.0]:
		_brushes.append(Rect2(x - 135.0, -2160.0, 270.0, 150.0))
		_brushes.append(Rect2(x - 135.0, 2010.0, 270.0, 150.0))
	# Kulmataskujen juke-puskat: massiiviportaiden ja linjan väliin jäävä
	# suojaisa tasku jokaisessa kulmassa (avoin linjan suuntaan).
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_brushes.append(_mirror_quadrant_rect(Rect2(2700, 1590, 260, 170), sx, sy))


func _setup_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2044084
	for i in range(125):
		var p := Vector2(rng.randf_range(-3480, 3480), rng.randf_range(-1180, 1180))
		if absf(p.x) > 2450.0:
			continue
		if p.distance_to(_baron) < 370 or p.distance_to(_dragon) < 370:
			continue
		_patches.append({"pos": p, "r": rng.randf_range(55, 175)})
	for i in range(90):
		var p := Vector2(rng.randf_range(-3500, 3500), rng.randf_range(-2150, 2150))
		if absf(p.x) > 2450.0:
			continue
		if absf(absf(p.y) - 1650.0) < 330.0:
			continue
		_trees.append({"pos": p, "r": rng.randf_range(9, 22)})


# --- Yhteinen taktinen rajapinta ---

func lane_ids() -> Array:
	return [TOP, BOTTOM]


func lane_path(lane_id: String = BOTTOM) -> Array:
	# Pitka S-kaari tekee linjoista luonnollisia ja antaa base-tornin ohi
	# juoksemiselle selkean, avoimen sisaantulon. Fyysista lane-porttia ei ole.
	var top_path: Array = [
		Vector2(-3000, -110), Vector2(-2960, -560), Vector2(-2860, -1030),
		Vector2(-2650, -1420), Vector2(-2250, -1650), Vector2(-1700, -1740),
		Vector2(-1100, -1680), Vector2(-550, -1585), Vector2(0, -1540),
		Vector2(550, -1585), Vector2(1100, -1680), Vector2(1700, -1740),
		Vector2(2250, -1650), Vector2(2650, -1420), Vector2(2860, -1030),
		Vector2(2960, -560), Vector2(3000, -110),
	]
	if lane_id == TOP:
		return top_path
	var bottom_path: Array = []
	for point in top_path:
		bottom_path.append(Vector2(point.x, -point.y))
	return bottom_path


func lane_paths() -> Dictionary:
	return {TOP: lane_path(TOP), BOTTOM: lane_path(BOTTOM)}


func lane_center(lane_id: String) -> Vector2:
	return Vector2(0, -1650 if lane_id == TOP else 1650)


func nearest_lane(pos: Vector2) -> String:
	return TOP if pos.y < 0.0 else BOTTOM


## Geometrinen etäisyys kaarevaan linjaan. Tätä käytetään telemetriassa ja
## AI:ssa, jotta basesta kaartava lane ei näytä virheellisesti jungle-ajalta.
func distance_to_lane(pos: Vector2, lane_id: String) -> float:
	var path: Array = lane_path(lane_id)
	if path.size() < 2:
		return INF
	var best_sq := INF
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		best_sq = minf(best_sq, pos.distance_squared_to(a + ab * t))
	return sqrt(best_sq)


## Lähin oikea aukko junglen ja linjan välisessä pitkässä harjanteessa.
## Paluubotit tähtäävät aukon lane-puolelle, eivät seinän läpi lähimpään
## geometriseen pisteeseen.
func nearest_lane_entry(pos: Vector2, lane_id: String) -> Vector2:
	var y := -1395.0 if lane_id == TOP else 1395.0
	var best := Vector2(0.0, y)
	var best_sq := INF
	for x in [-2350.0, -1020.0, 0.0, 1020.0, 2350.0]:
		var candidate := Vector2(x, y)
		var d_sq := pos.distance_squared_to(candidate)
		if d_sq < best_sq:
			best_sq = d_sq
			best = candidate
	return best


func assigned_role(slot: int) -> String:
	match slot % 4:
		0:
			return TOP
		1:
			return "jungle"
		_:
			return BOTTOM


func role_anchor(team: int, role: String) -> Vector2:
	var sx: float = -1.0 if team == 0 else 1.0
	match role:
		TOP:
			return Vector2(sx * 1550.0, -1650)
		"jungle":
			return Vector2(sx * 1990.0, -140)
		_:
			return Vector2(sx * 1550.0, 1650)


func jungle_anchor(team: int) -> Vector2:
	return role_anchor(team, "jungle")


func jungle_paths() -> Array:
	var paths: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			# Base door -> outer alcove -> inner camp pocket -> objective approach.
			paths.append([Vector2(sx * 2700, sy * 650), Vector2(sx * 2460, sy * 650),
				Vector2(sx * 2220, sy * 720), Vector2(sx * 1960, sy * 650),
				Vector2(sx * 1510, sy * 720), Vector2(sx * 1110, sy * 650),
				Vector2(sx * 560, sy * 650), Vector2(sx * 430, sy * 650)])
		# Vain nama kaksi kaytavaa ylittavat keskiselanteen kullakin puolella.
		paths.append([Vector2(sx * 1990, -650), Vector2(sx * 1990, -140),
			Vector2(sx * 1990, 140), Vector2(sx * 1990, 650)])
		paths.append([Vector2(sx * 700, -650), Vector2(sx * 700, -140),
			Vector2(sx * 700, 140), Vector2(sx * 700, 650)])
	return paths


func jungle_patrol(team: int, step: int) -> Vector2:
	# Oma puolisko -> joki -> toinen oma leiri. Bottijungleri kiertää tätä, jos
	# kaikki leirit ovat kuolleina eikä näkyvää gankkia ole.
	var sx: float = -1.0 if team == 0 else 1.0
	var route := [Vector2(sx * 2450, -650), Vector2(sx * 2220, -720),
		Vector2(sx * 1960, -650), Vector2(sx * 1510, -720),
		Vector2(sx * 1110, -650), Vector2(sx * 700, -140),
		Vector2(sx * 700, 140), Vector2(sx * 1110, 650),
		Vector2(sx * 1510, 720), Vector2(sx * 1960, 650),
		Vector2(sx * 2220, 720), Vector2(sx * 2450, 650),
		Vector2(sx * 2700, 650), Vector2(sx * 2700, -650)]
	return route[step % route.size()]


func jungle_choke_points() -> Array:
	var result: Array = []
	for sx in [-1.0, 1.0]:
		result.append(Vector2(sx * 700, 0))
		result.append(Vector2(sx * 1990, 0))
		for sy in [-1.0, 1.0]:
			result.append(Vector2(sx * 1110, sy * 650))
			result.append(Vector2(sx * 1960, sy * 650))
	return result


func gank_point(team: int, lane_id: String, deep := false) -> Vector2:
	var sx: float = -1.0 if team == 0 else 1.0
	var x: float = sx * (1020.0 if deep else 2350.0)
	var y: float = -1130.0 if lane_id == TOP else 1130.0
	return Vector2(x, y)


func sanctuary_rect(team: int) -> Rect2:
	return _sanctuary[team]


func fountain_spot(team: int) -> Vector2:
	return _fountain[team]


func shop_spot(team: int) -> Vector2:
	return _shop[team]


func jungle_door_ids() -> Array:
	return ["upper", "lower"]


func jungle_door_rect(team: int, door_id: String) -> Rect2:
	# Aukko vastaa collision-seinan aukkoa. Oma tiimi kulkee molempiin suuntiin,
	# vastustaja ohjataan takaisin junglen puolelle.
	var x: float = -2590.0 if team == 0 else 2440.0
	var y: float = -770.0 if door_id == "upper" else 530.0
	return Rect2(x, y, 150.0, 240.0)


func is_in_own_sanctuary(pos: Vector2, team: int) -> bool:
	return team in [0, 1] and (_sanctuary[team] as Rect2).has_point(pos)


func is_in_enemy_sanctuary(pos: Vector2, team: int) -> bool:
	return team in [0, 1] and (_sanctuary[1 - team] as Rect2).has_point(pos)


func enforce_base_boundaries(pos: Vector2, moving_team: int, radius: float,
		velocity := Vector2.ZERO) -> Vector2:
	if not moving_team in [0, 1]:
		return pos
	var out := pos
	var enemy_team := 1 - moving_team
	var safe := (_sanctuary[enemy_team] as Rect2).grow(radius)
	if safe.has_point(out):
		# Fountain on pysyvästi viholliselta suljettu mutta oma joukkue kulkee ulos.
		out.x = safe.end.x + 1.0 if enemy_team == 0 else safe.position.x - 1.0
	for door_id in jungle_door_ids():
		var door := jungle_door_rect(enemy_team, door_id).grow(radius)
		if not door.has_point(out):
			continue
		# Työnnä hyökkääjä takaisin linjan ulkopuolelle. Portin oman tiimin minionit
		# ja sankarit kulkevat vapaasti ulospäin.
		var toward_base: bool = velocity.x < 0.0 if enemy_team == 0 else velocity.x > 0.0
		if absf(velocity.x) < 0.1:
			var middle := door.get_center().x
			toward_base = out.x < middle if enemy_team == 0 else out.x > middle
		if enemy_team == 0:
			out.x = door.end.x + 1.0 if toward_base else door.position.x - 1.0
		else:
			out.x = door.position.x - 1.0 if toward_base else door.end.x + 1.0
	return out


func brush_zones() -> Array:
	return _brushes.duplicate()


func brush_index(pos: Vector2) -> int:
	for i in range(_brushes.size()):
		if (_brushes[i] as Rect2).has_point(pos):
			return i
	return -1


func is_in_brush(pos: Vector2) -> bool:
	return brush_index(pos) >= 0


func same_brush(a: Vector2, b: Vector2) -> bool:
	var ai := brush_index(a)
	return ai >= 0 and ai == brush_index(b)


func is_dark_jungle(pos: Vector2) -> bool:
	return absf(pos.y) < 1230.0 and absf(pos.x) > 180.0


func damage_camps() -> Array:
	return _red_camps.duplicate()


func points_camps() -> Array:
	return _blue_camps.duplicate()


func points_camp() -> Vector2:
	return _blue_camps[0]


func red_camps() -> Array:
	return _red_camps.duplicate()


func blue_camps() -> Array:
	return _blue_camps.duplicate()


func small_camps() -> Array:
	return _small_camps.duplicate()


func lane_wildlife_spots() -> Array:
	return _lane_wildlife.duplicate()


func lane_alcove_paths() -> Array:
	return [
		[Vector2(0, -1540), Vector2(0, -1810), Vector2(0, -2020)],
		[Vector2(0, 1540), Vector2(0, 1810), Vector2(0, 2020)],
	]


func boss_spot() -> Vector2:
	return _baron


func dragon_spot() -> Vector2:
	return _dragon


func nexus_spot(team: int) -> Vector2:
	return _nexus[team]


func tower_spots(team: int, lane_id: String = BOTTOM) -> Array:
	return _towers[team][lane_id].duplicate()


func camp_markers() -> Array:
	var result: Array = []
	for p in _red_camps:
		result.append({"pos": p, "kind": "red"})
	for p in _blue_camps:
		result.append({"pos": p, "kind": "blue"})
	for p in _small_camps:
		result.append({"pos": p, "kind": "small"})
	for p in _lane_wildlife:
		result.append({"pos": p, "kind": "lane"})
	result.append({"pos": _baron, "kind": "baron"})
	result.append({"pos": _dragon, "kind": "dragon"})
	return result


func terrain_mult(pos: Vector2) -> float:
	# Keskijoki on pieni rotaatioboosti eikä rankaise taistelua hidastuksella.
	return 1.06 if absf(pos.x) < 135.0 and absf(pos.y) < 1210.0 else 1.0


# --- Ulkoasu ---

func _draw() -> void:
	var half := map_size / 2.0
	draw_rect(Rect2(-half - Vector2(500, 500), map_size + Vector2(1000, 1000)), CANOPY)
	draw_rect(Rect2(-half, map_size), FLOOR)
	# Joukkuepuolten hillitty värikieli.
	draw_rect(Rect2(-half.x, -half.y, half.x, map_size.y), Palette.with_alpha(Palette.team(0), 0.075))
	draw_rect(Rect2(0, -half.y, half.x, map_size.y), Palette.with_alpha(Palette.team(1), 0.075))
	_draw_base_grounds()
	for patch in _patches:
		draw_circle(patch.pos, patch.r, Palette.with_alpha(FLOOR_ALT, 0.42))
	_draw_jungle_routes()
	_draw_jungle_landmarks()
	_draw_lane_alcoves()
	_draw_river()
	_draw_lane(TOP)
	_draw_lane(BOTTOM)
	_draw_objective_pit(_baron, BARON_COL, "BARON")
	_draw_objective_pit(_dragon, DRAGON_COL, "DRAGON")
	_draw_structures()
	for p in _red_camps:
		_draw_camp(p, Color("df4938"), "R")
	for p in _blue_camps:
		_draw_camp(p, Color("4e8ee8"), "B")
	for p in _small_camps:
		_draw_camp(p, Color("79b45e"), "C")
	for p in _lane_wildlife:
		_draw_camp(p, GOLD, "S")
	_draw_inner_walls()
	_draw_jungle_doors()
	_draw_brushes()
	_draw_forest()
	_draw_corner_forest()
	_draw_route_marks()
	_draw_walls_frame(Color("5f9364"), Color("07130d"))
	_draw_vignette()


func _draw_base_grounds() -> void:
	for team in range(2):
		var col: Color = Palette.team(team)
		var points := PackedVector2Array([
			Vector2(-3600, -1250), Vector2(-2600, -1250), Vector2(-2440, -1080),
			Vector2(-2440, 1080), Vector2(-2600, 1250), Vector2(-3600, 1250),
		])
		if team == 1:
			points = PackedVector2Array([
				Vector2(3600, -1250), Vector2(2600, -1250), Vector2(2440, -1080),
				Vector2(2440, 1080), Vector2(2600, 1250), Vector2(3600, 1250),
			])
		var safe := _sanctuary[team] as Rect2
		var floor_col := Color("102d39") if team == 0 else Color("3a2618")
		var edge_col := Color("58d8e9") if team == 0 else Color("e89b45")
		draw_colored_polygon(points, Palette.with_alpha(floor_col, 0.93))
		var closed := PackedVector2Array(Array(points) + [points[0]])
		draw_polyline(closed, Palette.with_alpha(edge_col, 0.68), 9.0, true)
		draw_rect(safe, Palette.with_alpha(Color("071923") if team == 0 else Color("25140d"), 0.95))
		draw_rect(safe, Palette.with_alpha(edge_col, 0.72), false, 8.0)
		if team == 0:
			_draw_blue_base_pattern()
		else:
			_draw_orange_base_pattern()
		# Respawn-fountain: pysyvä turva ja resurssipalautus.
		var fp: Vector2 = _fountain[team]
		draw_circle(fp, 178.0, Palette.with_alpha(Color("07121a"), 0.94))
		draw_circle(fp, 142.0, Palette.with_alpha(col, 0.18))
		draw_arc(fp, 151.0, 0.0, TAU, 54,
			Palette.with_alpha(Palette.glow(col, 1.25), 0.22), 4.0)
		UiKit.draw_text(self, fp + Vector2(0, -6), "RESPAWN", 22,
			Palette.with_alpha(Palette.glow(col, 1.4), 0.72), true, 3)
		# Tuleva shop-piste. Ei ostologiikkaa vielä, mutta paikka ja API ovat valmiit.
		var sp: Vector2 = _shop[team]
		draw_circle(sp, 72.0, Color("111713dd"))
		draw_arc(sp, 64.0, 0, TAU, 28, Palette.with_alpha(GOLD, 0.78), 5.0)
		draw_rect(Rect2(sp - Vector2(30, 20), Vector2(60, 42)), Color("6b4e25"))
		draw_colored_polygon(PackedVector2Array([sp + Vector2(-38, -20),
			sp + Vector2(0, -48), sp + Vector2(38, -20)]), Color("d5aa49"))
		UiKit.draw_text(self, sp + Vector2(0, 48), "SHOP", 16,
			Palette.with_alpha(GOLD, 0.86), true, 2)


func _draw_blue_base_pattern() -> void:
	# Cold crystal citadel: straight energy channels and diamond runes.
	var line := Color("65e8f488")
	for y in [-890.0, -445.0, 445.0, 890.0]:
		draw_line(Vector2(-3545, y), Vector2(-2690, y * 0.76), line, 5.0)
		draw_line(Vector2(-2690, y * 0.76), Vector2(-3000, 0), Color("65e8f444"), 3.0)
	for p in [Vector2(-3210, -720), Vector2(-2780, -430), Vector2(-2780, 430),
			Vector2(-3210, 720)]:
		var rune := PackedVector2Array([p + Vector2(0, -32), p + Vector2(24, 0),
			p + Vector2(0, 32), p + Vector2(-24, 0)])
		draw_colored_polygon(rune, Color("4ddce644"))
		draw_polyline(PackedVector2Array(Array(rune) + [rune[0]]), line, 3.0, true)
	draw_arc(Vector2(-3000, 0), 286.0, -1.2, 1.2, 28, Color("6df5ff66"), 8.0)
	draw_arc(Vector2(-3000, 0), 286.0, PI - 1.2, PI + 1.2, 28, Color("6df5ff66"), 8.0)


func _draw_orange_base_pattern() -> void:
	# Bronze sun fortress: round rings, radial plates and lava seams.
	var line := Color("ffc06488")
	for radius in [255.0, 360.0, 510.0]:
		draw_arc(Vector2(3000, 0), radius, -1.05, 1.05, 32, line, 5.0)
		draw_arc(Vector2(3000, 0), radius, PI - 1.05, PI + 1.05, 32, Color("e86b3655"), 4.0)
	for i in range(10):
		var angle := TAU * float(i) / 10.0
		var inner := Vector2(3000, 0) + Vector2(cos(angle), sin(angle)) * 200.0
		var outer := Vector2(3000, 0) + Vector2(cos(angle), sin(angle)) * 520.0
		draw_line(inner, outer, Color("ff9d4255"), 5.0)
	for p in [Vector2(3220, -740), Vector2(2740, -700), Vector2(2740, 700),
			Vector2(3220, 740)]:
		draw_circle(p, 34.0, Color("9d492c66"))
		draw_arc(p, 29.0, 0, TAU, 16, line, 4.0)


func _draw_jungle_routes() -> void:
	for raw_path in jungle_paths():
		var path := PackedVector2Array(raw_path)
		draw_polyline(path, Color("081a1088"), 220.0, true)
		draw_polyline(path, Color("315a35aa"), 154.0, true)
		draw_polyline(path, Color("76915d55"), 5.0, true)
		for p in path:
			draw_circle(p, 72.0, Color("315a3566"))


func _draw_jungle_landmarks() -> void:
	for sx in [-1.0, 1.0]:
		# River crossing on avoin ja helposti luettava: nopea mutta nakyva rotaatio.
		var river_gate := Vector2(sx * 700, 0)
		draw_circle(river_gate, 64.0, Color("132d2b99"))
		draw_arc(river_gate, 57.0, 0, TAU, 28, Color("78cbd0aa"), 5.0)
		for y in [-30.0, 0.0, 30.0]:
			draw_line(river_gate + Vector2(-42, y), river_gate + Vector2(42, y),
				Color("8fc8ad88"), 4.0)
		# Deep crossing on pimeampi shrine ja puskan peittama vaijytysreitti.
		var shadow_gate := Vector2(sx * 1990, 0)
		draw_circle(shadow_gate, 70.0, Color("100d18cc"))
		draw_arc(shadow_gate, 61.0, 0.0, TAU, 32, Color("a25ad044"), 3.0)
		for i in range(4):
			var angle := PI * 0.25 + TAU * float(i) / 4.0
			var rune := shadow_gate + Vector2(cos(angle), sin(angle)) * 42.0
			draw_circle(rune, 7.0, Color("cf84e2bb"))


func _draw_lane_alcoves() -> void:
	for raw_path in lane_alcove_paths():
		var path := PackedVector2Array(raw_path)
		draw_polyline(path, Color("17160f"), 300.0, true)
		draw_polyline(path, LANE_EDGE, 250.0, true)
		draw_polyline(path, Color("493e2d"), 205.0, true)
		var center: Vector2 = path[path.size() - 1]
		draw_circle(center, 142.0, Color("10150fdd"))
		draw_circle(center, 116.0, Color("35452e"))
		draw_arc(center, 123.0, 0, TAU, 36, Color("d7bd6277"), 6.0)
		for i in range(6):
			var angle := TAU * float(i) / 6.0 + PI / 6.0
			var stone := center + Vector2(cos(angle), sin(angle)) * 94.0
			draw_circle(stone, 10.0, Color("8d805599"))
		UiKit.draw_text(self, center + Vector2(0, 58), "SIDE CAMP", 15,
			Palette.with_alpha(GOLD, 0.82), true, 2)


func _draw_lane(lane_id: String) -> void:
	var path := PackedVector2Array(lane_path(lane_id))
	draw_polyline(path, Color("17160f"), 550.0, true)
	draw_polyline(path, LANE_EDGE, 500.0, true)
	draw_polyline(path, LANE, 430.0, true)
	draw_polyline(path, Palette.with_alpha(Color("d9c58a"), 0.18), 5.0, true)
	for p in path:
		draw_circle(p, 212.0, LANE)
	# Katkoviiva auttaa lukemaan reitin nopeasti zoomattunakin.
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var direction := a.direction_to(b)
		var length := a.distance_to(b)
		var cursor := 70.0
		while cursor < length:
			var mark := a + direction * cursor
			draw_line(mark - direction * 38.0, mark + direction * 38.0,
				Color("9e8b5d80"), 4.0)
			cursor += 220.0


func _draw_river() -> void:
	draw_rect(Rect2(-135, -1220, 270, 2440), Color("0b2631"))
	draw_rect(Rect2(-105, -1220, 210, 2440), RIVER)


func _draw_objective_pit(pos: Vector2, col: Color, label: String) -> void:
	draw_circle(pos, 280.0, Color("07120f"))
	draw_circle(pos, 245.0, Palette.with_alpha(col, 0.12))
	draw_arc(pos, 260.0, 0, TAU, 64, Palette.with_alpha(col, 0.58), 8.0)
	draw_arc(pos, 212.0, 0.0, TAU, 52,
		Palette.with_alpha(Palette.glow(col, 1.2), 0.12), 2.0)
	UiKit.draw_text(self, pos + Vector2(0, 16), label, 29,
		Palette.with_alpha(Palette.glow(col, 1.3), 0.7), true, 3)


func _draw_structures() -> void:
	for team in range(2):
		_platform(_nexus[team], 160, Palette.team(team), true)
		for lane_id in lane_ids():
			var spots: Array = _towers[team][lane_id]
			for i in range(spots.size()):
				_platform(spots[i], 94 if i == 2 else 78, Palette.team(team), i == 2)


func _platform(pos: Vector2, r: float, col: Color, major: bool) -> void:
	draw_circle(pos, r + 15, Color("090d0b99"))
	draw_circle(pos, r, Color("263329"))
	draw_arc(pos, r - 5, 0, TAU, 40, Palette.with_alpha(col, 0.65), 6.0 if major else 4.0)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + PI / 8.0
		draw_circle(pos + Vector2(cos(a), sin(a)) * (r - 14), 5.0, Palette.with_alpha(col, 0.5))


func _draw_camp(pos: Vector2, col: Color, mark: String) -> void:
	draw_circle(pos, 86, Color("07100cbb"))
	draw_arc(pos, 75, 0, TAU, 30, Palette.with_alpha(col, 0.58), 4.0)
	if mark == "R":
		for s in [-1.0, 1.0]:
			draw_line(pos + Vector2(s * 20, -22), pos + Vector2(s * 7, 24), col, 7.0)
	elif mark == "B":
		var gem := PackedVector2Array([pos + Vector2(0, -27), pos + Vector2(22, 8),
			pos + Vector2(0, 27), pos + Vector2(-22, 8)])
		draw_colored_polygon(gem, Palette.with_alpha(col, 0.78))
	else:
		UiKit.draw_text(self, pos + Vector2(0, 2), mark, 25,
			Palette.with_alpha(Palette.glow(col, 1.25), 0.9), true, 3)


func _draw_inner_walls() -> void:
	for wall in rect_walls:
		draw_rect(wall.grow(11), Color("06110bcc"))
		draw_rect(wall, Color("1d3a2a"))
		draw_rect(wall.grow(-5), WALL)
		draw_line(wall.position + Vector2(4, 3),
			Vector2(wall.end.x - 4, wall.position.y + 3), WALL_EDGE, 4.0)
		# Pitkat harjanteet nayttavat kasvaneilta kallio-/pensasmuureilta eivatka
		# debug-suorakulmioilta. Solmut pysyvat collision-pinnan sisalla.
		var horizontal: bool = wall.size.x >= wall.size.y
		var length: float = wall.size.x if horizontal else wall.size.y
		if length > 150.0:
			var count: int = maxi(1, int(length / 105.0))
			for i in range(count + 1):
				var t: float = float(i) / float(count)
				var p: Vector2 = Vector2(
					lerpf(wall.position.x + 14.0, wall.end.x - 14.0, t) if horizontal else wall.get_center().x,
					wall.get_center().y if horizontal else lerpf(wall.position.y + 14.0, wall.end.y - 14.0, t))
				var r: float = 12.0 + 3.0 * sin(float(i) * 1.7 + wall.position.x * 0.01)
				draw_circle(p + Vector2(3, 4), r + 3.0, Color("07160dcc"))
				draw_circle(p, r, Color("31553a"))
				draw_circle(p + Vector2(-4, -4), r * 0.46, Color("60916699"))
	for pillar in pillars:
		var p: Vector2 = pillar.pos
		var r: float = pillar.radius
		draw_circle(p + Vector2(5, 8), r + 6, Color("050b0888"))
		draw_circle(p, r, Color("24362a"))
		draw_circle(p + Vector2(-r * 0.22, -r * 0.25), r * 0.55, Color("3c5740"))


func _draw_jungle_doors() -> void:
	for team in range(2):
		var col: Color = Palette.team(team)
		var direction := 1.0 if team == 0 else -1.0
		for door_id in jungle_door_ids():
			var door := jungle_door_rect(team, door_id)
			var center := door.get_center()
			draw_rect(door, Palette.with_alpha(col, 0.09))
			# Kaksi pilaria rajaa aukon, mutta keskella ei ole fyysista porttia.
			draw_circle(Vector2(center.x, door.position.y + 15.0), 20.0, Color("18251d"))
			draw_circle(Vector2(center.x, door.end.y - 15.0), 20.0, Color("18251d"))
			draw_arc(Vector2(center.x, door.position.y + 15.0), 16.0, 0, TAU, 18,
				Palette.with_alpha(col, 0.72), 4.0)
			draw_arc(Vector2(center.x, door.end.y - 15.0), 16.0, 0, TAU, 18,
				Palette.with_alpha(col, 0.72), 4.0)
			var from := center - Vector2(direction * 46.0, 0)
			var tip := center + Vector2(direction * 50.0, 0)
			draw_line(from, tip, Palette.with_alpha(Palette.glow(col, 1.45), 0.78), 7.0)
			var arrow := PackedVector2Array([tip,
				tip + Vector2(-direction * 28.0, -22.0),
				tip + Vector2(-direction * 28.0, 22.0)])
			draw_colored_polygon(arrow, Palette.with_alpha(Palette.glow(col, 1.45), 0.78))


func _draw_brushes() -> void:
	for rect in _brushes:
		var r := rect as Rect2
		var center := r.get_center()
		# Soikea tumma aluskasvillisuus ilman näkyvää Rect2-debuglaatikkoa.
		draw_set_transform(center, 0.0, Vector2(r.size.x / r.size.y, 0.62))
		draw_circle(Vector2.ZERO, r.size.y * 0.52, Color("07150d82"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var cols := 8
		for row in range(2):
			for i in range(cols):
				var t: float = float(i) / float(cols - 1)
				var x: float = lerpf(r.position.x + 20.0, r.end.x - 20.0, t)
				var seed: float = float(i + row * cols)
				# Varsinainen lehtimassa on staattinen; overlay lisää liikkuvan
				# valon ja tuulen ilman koko kartan uudelleenpiirtoa.
				var sway: float = sin(seed * 1.7) * 4.0
				var y: float = center.y + (float(row) - 0.5) * 42.0 \
					+ sin(seed * 2.3) * 10.0
				var leaf_r: float = 20.0 + fmod(seed * 7.0, 10.0)
				draw_circle(Vector2(x + sway, y), leaf_r + 6.0, Color("0b27169a"))
				draw_circle(Vector2(x + sway, y), leaf_r, Color("1c5b2eaa"))
				draw_circle(Vector2(x + sway - 7.0, y - 8.0), leaf_r * 0.48,
					Color("54a45db5"))


func _draw_forest() -> void:
	for tree in _trees:
		var p: Vector2 = tree.pos
		var r: float = tree.r
		draw_circle(p + Vector2(3, 5), r + 3, Color("04100988"))
		draw_circle(p, r, Color("245a32aa"))
		draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.45, Color("4b9558aa"))


## Kulmamassiivien metsä: portaikon kivet saavat päälleen tiheän latvuston,
## syvyysvarjon kulmaa kohti, hehkuvaa sammalta ja sienirykelmiä. Deterministinen
## siemen -> sama kaunis kulma joka käynnistyksellä, ei uudelleenlaskentaa.
func _draw_corner_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771224
	# Syvyysvarjo: latvusto tummenee kulmaa kohti (kolme pehmeää kerrosta).
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(3600.0 * sx, 2200.0 * sy)
			for i in range(3):
				var r := 620.0 - i * 170.0
				draw_circle(corner, r, Color(0.02, 0.08, 0.05, 0.16 + 0.07 * i))
	# Latvusto: puita massiiviportaiden päälle (kasvatettu reunus -> puut
	# valuvat hieman kiven yli, mikä rikkoo suorat linjat luonnollisesti).
	for step in _corner_massifs:
		var zone := (step as Rect2).grow(26.0)
		var count := int(zone.size.x / 68.0)
		for i in range(count):
			var p := Vector2(rng.randf_range(zone.position.x, zone.end.x),
				rng.randf_range(zone.position.y, zone.end.y))
			var r := rng.randf_range(16.0, 34.0)
			draw_circle(p + Vector2(4, 6), r + 4.0, Color("04100988"))
			draw_circle(p, r, Color(0.13, 0.34, 0.19, 0.92))
			draw_circle(p + Vector2(-r * 0.28, -r * 0.3), r * 0.5, Color("4b9558aa"))
			if rng.randf() < 0.3:
				draw_circle(p + Vector2(r * 0.2, -r * 0.15), r * 0.24, Color("6fc17b66"))
	# Hehkuva sammal + tulikärpäset portaiden reunoille: pieni elävä valo
	# muuten pimeään kulmaan (staattinen; overlay-animaatio ei koske karttaa).
	for step in _corner_massifs:
		var rect := step as Rect2
		for i in range(3):
			var edge := Vector2(rng.randf_range(rect.position.x + 20.0, rect.end.x - 20.0),
				rect.position.y + (0.0 if rng.randf() < 0.5 else rect.size.y))
			draw_circle(edge, rng.randf_range(10.0, 18.0), Color(0.35, 0.78, 0.5, 0.13))
			draw_circle(edge, 3.2, Color(0.62, 0.95, 0.66, 0.5))
		if rng.randf() < 0.45:
			var fly := Vector2(rng.randf_range(rect.position.x, rect.end.x),
				rng.randf_range(rect.position.y, rect.end.y))
			draw_circle(fly, 7.0, Color(1.0, 0.91, 0.55, 0.14))
			draw_circle(fly, 2.4, Color(1.0, 0.93, 0.66, 0.66))
	# Sienirykelmät kulmataskujen (juke-puskien) kupeeseen: pehmeä maamerkki
	# joka auttaa lukemaan taskun sijainnin kaukaakin.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var base := Vector2(3050.0 * sx, 1810.0 * sy)
			for i in range(4):
				var p := base + Vector2(rng.randf_range(-46.0, 46.0), rng.randf_range(-30.0, 30.0))
				var r := rng.randf_range(7.0, 13.0)
				draw_circle(p + Vector2(0, r * 0.4), r * 0.5, Color("d8cfae99"))
				draw_circle(p, r, Color("c2564acc"))
				draw_circle(p + Vector2(-r * 0.3, -r * 0.25), r * 0.3, Color("f2e6d799"))


func _draw_route_marks() -> void:
	# Gank-portit on merkitty kivillä, jotta pelaaja lukee jungle-sisäänkäynnit.
	for x in [-2350.0, -1000.0, 0.0, 1000.0, 2350.0]:
		for y in [-1250.0, 1250.0]:
			draw_circle(Vector2(x, y), 16, Color("8fd49b55"))
			draw_arc(Vector2(x, y), 28, 0, TAU, 18, Color("b6efbd88"), 3.0)
	# Jungle-risteysten kompassikivet kertovat pelaajalle, missa pitkien seinien
	# ylitykset ja camp-taskujen suuaukot ovat jo ennen fog/ward-jarjestelmaa.
	for p in jungle_choke_points():
		draw_circle(p, 13.0, Color("0a1a10cc"))
		draw_arc(p, 20.0, 0, TAU, 16, Color("75c98788"), 3.0)
		var diamond := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0),
			p + Vector2(0, 8), p + Vector2(-8, 0)])
		draw_colored_polygon(diamond, Color("9edb8faa"))
