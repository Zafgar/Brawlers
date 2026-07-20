class_name MapMoba
extends MapBase
## Suuri MOBA-kartta: yläpuoli on viidakko (leirit + pomo), alapuoli on LINJA
## jota pitkin minionit marssivat. Kummallakin puolella on tukikohta (nexus) ja
## kaksi tornia linjalla. Voitto = tuhoa vihollisen nexus (tornit ensin).
##
## LINJA ON KÄYTÄVÄ, ei avoin kenttä: yläreuna on viidakkoseinä (gank-aukoin),
## alareuna on eteläseinä. Näin tornit peittävät käytävän koko leveyden eikä
## alakautta voi enää kävellä ohi torneista suoraan nexukselle. Käytävässä on
## suojaesteitä (kivet) taisteluihin ja gankkeihin.
##
## Sininen (joukkue 0) vasemmalla, oranssi (joukkue 1) oikealla.

const FLOOR := Color("15321f")
const FLOOR_ALT := Color("1a3b25")
const CANOPY := Color("0d2417")
const LEAF := Color("3f8f4e")
const LANE := Color("3a3324")
const LANE_EDGE := Color("54492f")
const RIVER := Color("1e4a5c")
const GOLD := Color("e0c23c")
const CLAW := Color("d9662a")   # puna-oranssi: ei sekoitu joukkue-oranssiin
const BOSS_COL := Color("b64ad6")

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

# Esilasketut koristeet (ei RandomNumberGeneratoria joka ruutu). Laikut on
# sävytetty joukkuepuolen mukaan, jotta sininen/oranssi puoli erottuu.
var _patches: Array = []   # [{pos, r, col}]
var _foliage: Array = []   # [{pos, s}]
var _cliff: Array = []     # [{pos, r}] eteläseinän lohkareet (esilaskettu)


func _setup() -> void:
	map_size = Vector2(4400, 2600)
	var half := map_size / 2.0

	# Aloituspaikat tukikohtien luo. Vedetty SISÄTORNIN kantamalle (x=∓1800,
	# nexuksesta 200 px): torni puolustaa spawnia, joten vihollinen ei voi
	# rauhassa spawn-campata. Pysyvät käytävässä (y<~960), eteläseinän yläpuolella.
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var oy := -84.0 + i * 72.0
		blue.append(Vector2(-2000.0 + 200.0, 820.0 + oy))
		orange.append(Vector2(2000.0 - 200.0, 820.0 + oy))
	spawn_slots = [blue, orange]

	# --- Viidakon suojaesteet: SYMMETRINEN setti (peilattu x=0 yli) reiluuden
	# takaamiseksi. Aiemmin 10 satunnaiskiveä ei ollut peilattu -> toinen puoli
	# saattoi saada paremmat suojat. Nyt kaikki kivet ovat pareittain peilattuja.
	# 1) Deliberaatit suojaparit: pistereirin sivustat + kiertoreitin kapeikot.
	var cover_pairs := [
		{"x": 260.0, "y": -340.0, "r": 56.0},   # pistereirin sivusuoja (sivusta voi kiistää)
		{"x": 640.0, "y": -520.0, "r": 64.0},   # pomo<->linja kiertoreitin kapeikko
	]
	for c in cover_pairs:
		var cr: float = c.r
		pillars.append({"pos": Vector2(-float(c.x), float(c.y)), "radius": cr})
		pillars.append({"pos": Vector2(float(c.x), float(c.y)), "radius": cr})

	# 2) Peilatut satunnaiskivet (tekstuuria, mutta reilusti): arvo vasen puoli,
	# lisaa aina myos peilikuva. Valta camp/objektiivit ja pida 320 px valistys.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720
	var blocked: Array = [_boss, _points, _dmg_left, _dmg_right,
		_nexus_blue, _nexus_orange]
	for t in _tower_blue:
		blocked.append(t)
	for t in _tower_orange:
		blocked.append(t)
	var tries := 0
	while pillars.size() < 12 and tries < 320:
		tries += 1
		var p := Vector2(rng.randf_range(-half.x + 300.0, -180.0),
			rng.randf_range(-half.y + 260.0, -120.0))   # vain vasen viidakko -> peilataan
		var mir := Vector2(-p.x, p.y)
		var ok := true
		for b in blocked:
			if p.distance_to(b) < 360.0 or mir.distance_to(b) < 360.0:
				ok = false
				break
		if ok:
			for existing in pillars:
				if p.distance_to(existing.pos) < 320.0 or mir.distance_to(existing.pos) < 320.0:
					ok = false
					break
		if ok:
			var pr := rng.randf_range(46.0, 76.0)
			pillars.append({"pos": p, "radius": pr})
			pillars.append({"pos": mir, "radius": pr})

	# Suojaesteet LINJALLE (symmetriset kivet tien pohjoispuolelle): antavat
	# suojaa taisteluihin ja gankkeihin tukkimatta tietä, torneja, gank-aukkoja
	# tai nexuksia. y~470-500 on tien (y660-900) yläpuolella.
	for cx in [-920.0, -760.0, -380.0, 380.0, 760.0, 920.0]:
		var cy := 470.0 if absf(cx) > 500.0 else 500.0
		pillars.append({"pos": Vector2(cx, cy), "radius": 50.0})

	# Suojaa myos tien ETELApuolelle (puolustajalle): pienet nyppylat ohueen
	# eteläkaistaan. r<=30 ettei botti tartu eteläseinään.
	for sx in [570.0, 1150.0]:
		var sy := 860.0 if sx < 1000.0 else 880.0
		pillars.append({"pos": Vector2(-sx, sy), "radius": 28.0})
		pillars.append({"pos": Vector2(sx, sy), "radius": 28.0})

	_setup_walls()
	_setup_decor(half)


## Esilaskee viidakkopohjan laikut (joukkuepuolen mukaan sävytetyt) ja
## koristepensaat kerran, jottei _draw luo RNG:tä joka ruutu.
func _setup_decor(half: Vector2) -> void:
	var drng := RandomNumberGenerator.new()
	drng.seed = 81724
	for i in range(70):
		var p := Vector2(drng.randf_range(-half.x, half.x), drng.randf_range(-half.y, 120.0))
		var pr := drng.randf_range(60.0, 200.0)
		var team_col: Color = Palette.team(0) if p.x < 0.0 else Palette.team(1)
		var col: Color = FLOOR_ALT.lerp(team_col, 0.22)
		_patches.append({"pos": p, "r": pr, "col": col})
	drng.seed = 559
	for i in range(26):
		var fp := Vector2(drng.randf_range(-half.x + 220.0, half.x - 220.0),
			drng.randf_range(-half.y + 200.0, 60.0))
		var s := drng.randf_range(14.0, 30.0)
		_foliage.append({"pos": fp, "s": s})
	# Eteläseinän lohkareet (linjan alareunan kalliojono, ei törmäystä).
	drng.seed = 4711
	var cx := -half.x + 120.0
	while cx < half.x - 60.0:
		var cr := drng.randf_range(40.0, 82.0)
		var cy := 1010.0 + drng.randf_range(6.0, 48.0)
		_cliff.append({"pos": Vector2(cx, cy), "r": cr})
		cx += drng.randf_range(150.0, 260.0)


## Sisaseinat (rect_walls): viidakon ja linjan erottava seina gank-aukoin,
## pomo-alkovi ja sivuleirien alkovit. Linja pidetaan taysin auki (minionit
## marssivat sita) eivatka seinat osu torneihin/nexuksiin/spawneihin.
func _setup_walls() -> void:
	var t := 64.0
	var dy := 320.0 - t / 2.0
	# Viidakon ja linjan erottava seina; gank-aukot kohdissa x = -1150 / 0 / +1150.
	# Paadyt kavennettu ~200 px kapeikoiksi (ennen 300+ auki): tukikohtaan pääsee
	# viidakosta yha, mutta ahtaammin -> puolustaja saa pitopisteen eikä spawnia
	# voi flankata leveaa reittia. (Spawnit ovat lisaksi nyt sisatornin kantamalla.)
	rect_walls.append(Rect2(-2000.0, dy, 700.0, t))
	rect_walls.append(Rect2(-1000.0, dy, 850.0, t))
	rect_walls.append(Rect2(150.0, dy, 850.0, t))
	rect_walls.append(Rect2(1300.0, dy, 700.0, t))
	# ETELÄSEINÄ: sulkee linjakäytävän alareunan koko leveydeltä. Tornit (kantama
	# 360, y~660-720) peittävat nyt käytävän (y 352..1010) koko korkeuden, joten
	# alakautta ei voi enää kävellä ohi torneista suoraan nexukselle. Täyttää
	# kiinteänä kartan alareunaan asti (ei kuollutta kuljettavaa tilaa).
	# Korkeus 290 -> alareuna y=1300 = kartan reuna tasan (ei ylitä reunaa, mikä
	# aiemmin sai clamp-työnnön heittämään hahmon kentän ulkopuolelle).
	rect_walls.append(Rect2(-2200.0, 1010.0, 4400.0, 290.0))
	# Pomo-alkovi (0,-800): seinat pohjoiseen ja sivuille, auki etelaan.
	rect_walls.append(Rect2(-440.0, -1090.0, 880.0, 60.0))
	rect_walls.append(Rect2(-440.0, -1030.0, 70.0, 380.0))
	rect_walls.append(Rect2(370.0, -1030.0, 70.0, 380.0))
	# Sivuleirien alkovit (L-seina ulkokulmaan, auki keskelle ja etelaan).
	rect_walls.append(Rect2(-1420.0, -760.0, 340.0, 60.0))
	rect_walls.append(Rect2(-1420.0, -760.0, 60.0, 300.0))
	rect_walls.append(Rect2(1080.0, -760.0, 340.0, 60.0))
	rect_walls.append(Rect2(1360.0, -760.0, 60.0, 300.0))


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
## Reittipisteet linjaa pitkin. HUOM: pisteet on siirretty tornien ETELÄPUOLELLE
## (y 800-900), pois tornien törmäysrunkojen (torni r46 + minion r15 = 61 px)
## sisältä. Aiemmin pisteet olivat ~40 px tornin keskeltä -> minionit jäivät
## jauhamaan tornin runkoa yrittäessään saavuttaa saavuttamatonta pistettä.
func lane_path() -> Array:
	# y ~795-815: tornien eteläpuolella (torni y660/720, >90px selvä) MUTTA myös
	# etelänyppylöiden (±570,860 / ±1150,880 r28) yläpuolella niin ettei linjan
	# VÄLIsegmentti raapaise niitä (tarve 28+15=43px; nyt ~50-67px).
	return [
		Vector2(-2000, 900), Vector2(-1480, 815), Vector2(-760, 810),
		Vector2(0, 795), Vector2(760, 810), Vector2(1480, 815), Vector2(2000, 900)]


func _draw() -> void:
	var half := map_size / 2.0

	draw_rect(Rect2(-half - Vector2(600, 600), map_size + Vector2(1200, 1200)), CANOPY)
	draw_rect(Rect2(-half, map_size), FLOOR)

	# Joukkuepuolten kevyt aluevari (sininen vasen, oranssi oikea).
	_draw_side_tint(half)

	# Viidakon laikutus (yläpuoli), esilaskettu ja joukkuepuolen mukaan sävytetty.
	for patch in _patches:
		draw_circle(patch.pos, patch.r, Palette.with_alpha(patch.col, 0.5))

	# Koristepensaat viidakkoon (ei törmäystä).
	_draw_foliage()

	# Jokivyö erottaa viidakon ja linjan (n. y=210), ylityskivet gank-kohdissa.
	_draw_river(half)

	# LINJA alapuolelle: leveä päällystetty kaista, reunukset ja suuntachevronit.
	_draw_lane()

	# Roihut linjan varrella (tunnelmaa).
	_draw_braziers()

	# Nexus-alustat ja tornipohjat (rakennukset itse piirtyvät entiteetteinä).
	_platform(_nexus_blue, 150.0, Palette.team(0), true)
	_platform(_nexus_orange, 150.0, Palette.team(1), true)
	for t in _tower_blue:
		_platform(t, 78.0, Palette.team(0), false)
	for t in _tower_orange:
		_platform(t, 78.0, Palette.team(1), false)

	# Viidakon leirimerkit (tyyppikohtainen ikoni) ja pomomonttu.
	_camp_marker(_dmg_left, CLAW, "dmg")
	_camp_marker(_dmg_right, CLAW, "dmg")
	_camp_marker(_points, GOLD, "points")
	_boss_pit(_boss)

	# Sisaseinat (kivi + lehtiharja) ja gank-aukkojen hehkumerkit.
	_draw_moba_walls()
	_draw_south_cliff()
	_draw_gank_markers()

	# Latvuston lehtiläikät esteiden päällä.
	for pillar in pillars:
		draw_circle(pillar.pos + Vector2(0, 6), pillar.radius + 6.0, Color(0.03, 0.09, 0.05, 0.6))
		draw_circle(pillar.pos, pillar.radius, Palette.darker(LEAF, 0.4))
		draw_circle(pillar.pos + Vector2(-pillar.radius * 0.3, -pillar.radius * 0.3),
			pillar.radius * 0.5, Palette.with_alpha(LEAF, 0.55))

	_draw_walls_frame(LEAF, CANOPY)
	_draw_vignette()
	_draw_motes(80, Color("bfe6a0"), 14.0, 4343)


## Kevyt joukkueväri kummallekin puolelle + hehku tukikohdista (luettavuus).
func _draw_side_tint(half: Vector2) -> void:
	var bt: Color = Palette.team(0)
	var ot: Color = Palette.team(1)
	draw_rect(Rect2(-half.x, -half.y, half.x, map_size.y), Palette.with_alpha(bt, 0.05))
	draw_rect(Rect2(0.0, -half.y, half.x, map_size.y), Palette.with_alpha(ot, 0.05))
	# Vahvempi hehku tukikohdista -> selkeä "kenen puoli" (laikut kantavat lopun).
	for k in range(4):
		var rr: float = 1250.0 - float(k) * 260.0
		draw_circle(_nexus_blue, rr, Palette.with_alpha(bt, 0.05))
		draw_circle(_nexus_orange, rr, Palette.with_alpha(ot, 0.05))


## Koristepensaat viidakkoon (vain yläpuoli, ei törmäystä), esilaskettu.
func _draw_foliage() -> void:
	for f in _foliage:
		var p: Vector2 = f.pos
		var s: float = f.s
		draw_circle(p + Vector2(0, 5), s + 3.0, Color(0.03, 0.09, 0.05, 0.5))
		draw_circle(p, s, Palette.darker(LEAF, 0.55))
		draw_circle(p + Vector2(-s * 0.3, -s * 0.3), s * 0.5, Palette.with_alpha(LEAF, 0.4))


func _draw_river(half: Vector2) -> void:
	# Joki ulottuu alas seinaan (y~288) asti, jotta viidakon ja linjan raja lukee
	# yhtena esteena. Ylityskivet ovat gank-aukoissa (x = -1150/0/+1150).
	var y := 225.0
	var band := 130.0
	# Tummat rannat.
	draw_rect(Rect2(-half.x, y - band * 0.5 - 10.0, map_size.x, 10.0),
		Palette.with_alpha(Palette.darker(RIVER, 0.5), 0.6))
	draw_rect(Rect2(-half.x, y + band * 0.5, map_size.x, 10.0),
		Palette.with_alpha(Palette.darker(RIVER, 0.5), 0.6))
	# Vesi.
	draw_rect(Rect2(-half.x, y - band * 0.5, map_size.x, band), Palette.with_alpha(RIVER, 0.55))
	# Virtausviivat (animoitu vaakadash).
	for i in range(3):
		var yy: float = y - band * 0.3 + band * 0.3 * float(i)
		var scroll: float = fmod(_time * 60.0 + float(i) * 90.0, 300.0)
		var x: float = -half.x + scroll
		while x < half.x:
			draw_line(Vector2(x, yy), Vector2(x + 90.0, yy),
				Palette.with_alpha(Palette.glow(RIVER, 1.4), 0.22), 2.0)
			x += 300.0
	# Ylityskivet: pystyketju joesta seinan aukon lapi kummassakin gank-kohdassa.
	for gx in [-1150.0, 0.0, 1150.0]:
		for j in range(4):
			var sy: float = 235.0 + float(j) * 30.0
			var sp := Vector2(gx, sy)
			draw_circle(sp, 16.0, Palette.darker(Color("6b5a3a"), 0.2))
			draw_circle(sp + Vector2(-4, -4), 8.0, Palette.with_alpha(Color("8a774f"), 0.75))


func _draw_lane() -> void:
	var pts := lane_path()
	# Leveä tumma reunus + tie kahtena sävynä.
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		draw_line(a, b, Palette.darker(LANE, 0.5), 168.0)
		draw_line(a, b, LANE_EDGE, 150.0)
		draw_line(a, b, LANE, 128.0)
	# Keskiviivan katkoviiva.
	for i in range(pts.size() - 1):
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[i + 1]
		var segs := 6
		for s in range(segs):
			if s % 2 == 0:
				var p0: Vector2 = a2.lerp(b2, float(s) / segs)
				var p1: Vector2 = a2.lerp(b2, float(s + 1) / segs)
				draw_line(p0, p1, Palette.with_alpha(LANE_EDGE, 0.6), 3.0)
	# Suuntachevronit: sininen tyontaa oikealle, oranssi vasemmalle.
	_lane_chevrons(pts)
	# Keskikohdan tunnus (kohtaamispiste).
	var mid := Vector2(0, 680)
	draw_arc(mid, 46.0, 0.0, TAU, 28, Palette.with_alpha(Color("cdbb7a"), 0.4), 3.0)
	draw_arc(mid, 30.0, _time * 0.6, _time * 0.6 + TAU * 0.75, 22,
		Palette.with_alpha(Color("e8d79a"), 0.4), 2.0)


func _lane_chevrons(pts: Array) -> void:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: Vector2 = b - a
		var count: int = maxi(int(seg.length() / 160.0), 1)
		for j in range(count):
			var tt: float = (float(j) + 0.5) / float(count)
			var p: Vector2 = a.lerp(b, tt)
			var right_side: bool = p.x >= 0.0
			var arrow: Vector2 = Vector2.LEFT if right_side else Vector2.RIGHT
			var col: Color = Palette.team(1) if right_side else Palette.team(0)
			_chevron(p, arrow, 24.0, Palette.with_alpha(col, 0.22))


func _chevron(p: Vector2, dir: Vector2, size: float, col: Color) -> void:
	var perp: Vector2 = dir.orthogonal()
	var tip: Vector2 = p + dir * size
	var l: Vector2 = p - dir * size * 0.4 + perp * size
	var r: Vector2 = p - dir * size * 0.4 - perp * size
	draw_line(l, tip, col, 5.0)
	draw_line(r, tip, col, 5.0)


## Roihut linjan varrella tornien kohdilla (tunnelmaa, ei törmäystä).
func _draw_braziers() -> void:
	var spots := [Vector2(-760, 620), Vector2(-1480, 620),
		Vector2(760, 620), Vector2(1480, 620)]
	for sp in spots:
		var p: Vector2 = sp
		var f: float = 0.6 + 0.4 * sin(_time * 8.0 + p.x * 0.05)
		draw_circle(p, 11.0, Color("241a12"))
		draw_circle(p + Vector2(0, -6), 8.0 * f, Palette.with_alpha(Color("ff9a3c"), 0.7))
		draw_circle(p + Vector2(0, -9), 4.0 * f, Palette.with_alpha(Color("ffe08a"), 0.85))


## Rakennuksen alusta (tornit/nexus piirtyvät päälle entiteetteinä).
func _platform(pos: Vector2, r: float, team_col: Color, is_nexus: bool) -> void:
	draw_circle(pos, r * 1.15, Palette.with_alpha(team_col, 0.06))
	draw_circle(pos, r, Palette.with_alpha(Color("22201a"), 0.92))
	draw_circle(pos, r * 0.9, Palette.with_alpha(Palette.darker(team_col, 0.6), 0.16))
	# Riimutikut kehalla.
	var ticks := 16 if is_nexus else 10
	for i in range(ticks):
		var a: float = TAU * float(i) / float(ticks)
		var d := Vector2(cos(a), sin(a))
		draw_line(pos + d * (r * 0.82), pos + d * (r * 0.96),
			Palette.with_alpha(team_col, 0.35), 2.0)
	draw_arc(pos, r, 0.0, TAU, 48, Palette.with_alpha(team_col, 0.6), 4.0)
	draw_arc(pos, r * 0.72, 0.0, TAU, 40, Palette.with_alpha(team_col, 0.28), 2.0)
	if is_nexus:
		draw_arc(pos, r * 0.5, _time * 0.5, _time * 0.5 + TAU * 0.7, 30,
			Palette.with_alpha(Palette.glow(team_col, 1.3), 0.4), 3.0)
	draw_circle(pos, r * 0.12, Palette.with_alpha(team_col, 0.22))


func _camp_marker(pos: Vector2, color: Color, kind: String) -> void:
	draw_circle(pos, 116.0, Palette.with_alpha(color, 0.08))
	draw_arc(pos, 106.0, 0.0, TAU, 40, Palette.with_alpha(color, 0.5), 3.0)
	draw_arc(pos, 90.0, _time * 0.5, _time * 0.5 + TAU * 0.7, 30,
		Palette.with_alpha(Palette.glow(color, 1.3), 0.5), 2.0)
	if kind == "points":
		# Timantti + kolikkorengas (pistereiri).
		var g: Color = Palette.glow(color, 1.2)
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -34), pos + Vector2(24, 0),
			pos + Vector2(0, 34), pos + Vector2(-24, 0)]), Palette.with_alpha(g, 0.5))
		draw_arc(pos, 18.0, 0.0, TAU, 18, Palette.with_alpha(Color("fff2c0"), 0.6), 2.0)
	else:
		# Kynsimerkit (vahinkoleiri).
		for s in [-1.0, 0.0, 1.0]:
			var off := Vector2(s * 26.0, -2.0)
			draw_line(pos + off + Vector2(-11, -22), pos + off + Vector2(6, 24),
				Palette.with_alpha(Palette.glow(color, 1.2), 0.55), 4.0)


func _boss_pit(pos: Vector2) -> void:
	# Tumma vortex.
	draw_circle(pos, 210.0, Palette.with_alpha(Color("2a1030"), 0.6))
	draw_circle(pos, 150.0, Palette.with_alpha(Color("140720"), 0.5))
	# Piikikas riimurengas (hitaasti pyorien).
	var ring := PackedVector2Array()
	var spikes := 16
	for i in range(spikes * 2):
		var a: float = TAU * float(i) / float(spikes * 2) - _time * 0.25
		var rr: float = 200.0 if i % 2 == 0 else 168.0
		ring.append(pos + Vector2(cos(a), sin(a)) * rr)
	if ring.size() > 1:
		draw_polyline(ring, Palette.with_alpha(BOSS_COL, 0.5), 3.0)
		draw_line(ring[ring.size() - 1], ring[0], Palette.with_alpha(BOSS_COL, 0.5), 3.0)
	draw_arc(pos, 130.0, _time * 0.4, _time * 0.4 + TAU * 0.8, 40,
		Palette.with_alpha(Palette.glow(BOSS_COL, 1.3), 0.4), 2.0)
	# Hehkuva silma keskella (syke).
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.0)
	draw_circle(pos, 26.0 + 6.0 * pulse, Palette.with_alpha(Palette.glow(BOSS_COL, 1.5), 0.22 + 0.22 * pulse))


## Piirtaa sisaseinat kivisena harjanteena joukkuevarittomana + lehtiharja.
func _draw_moba_walls() -> void:
	for entry in rect_walls:
		var w: Rect2 = entry
		draw_rect(w, Color("0f1f16"))
		draw_rect(Rect2(w.position + Vector2(4, 4), w.size - Vector2(8, 8)),
			Palette.with_alpha(Color("24402c"), 0.7))
		draw_rect(w, Palette.with_alpha(Palette.glow(LEAF, 1.1), 0.3), false, 2.5)
		# Lehtiharja yläreunaan.
		draw_rect(Rect2(w.position - Vector2(0, 7), Vector2(w.size.x, 12)),
			Palette.with_alpha(CANOPY, 0.85))


## Eteláseinä kalliojonona: reunavalo linjan alalaitaan + esilasketut lohkareet,
## jotta seinä lukee tarkoituksellisena kallioseinänä eikä litteänä palkkina.
func _draw_south_cliff() -> void:
	var half := map_size / 2.0
	var top := 1010.0
	# Kallion reunavalo (linjan eteläraja erottuu selkeästi).
	draw_rect(Rect2(-half.x, top - 3.0, map_size.x, 6.0),
		Palette.with_alpha(Palette.glow(LEAF, 1.1), 0.4))
	draw_rect(Rect2(-half.x, top, map_size.x, half.y - top),
		Palette.with_alpha(Color("0a1410"), 0.5))
	for b in _cliff:
		var p: Vector2 = b.pos
		var r: float = b.r
		draw_circle(p + Vector2(0, 5), r + 4.0, Color(0.02, 0.06, 0.04, 0.6))
		draw_circle(p, r, Palette.darker(Color("2c3d2e"), 0.15))
		draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.5,
			Palette.with_alpha(Color("3d523d"), 0.6))


## Hehkumerkit viidakko/linja-seinan gank-aukkojen kohdalle (nakyva kulkuaukko).
func _draw_gank_markers() -> void:
	var y := 320.0
	var c: Color = Palette.glow(LEAF, 1.2)
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
	for gx in [-1150.0, 0.0, 1150.0]:
		# Kirkkaampi hehkukaari aukon yli (selkeä "kuljetaan tästä").
		draw_arc(Vector2(gx, y + 6.0), 150.0, PI, TAU, 24, Palette.with_alpha(c, 0.4 + 0.15 * pulse), 4.0)
		draw_arc(Vector2(gx, y + 6.0), 132.0, PI, TAU, 22, Palette.with_alpha(c, 0.18), 2.0)
		for s in [-1.0, 1.0]:
			var px: float = gx + s * 150.0
			draw_circle(Vector2(px, y), 16.0, Palette.darker(FLOOR, 0.4))
			draw_circle(Vector2(px, y), 10.0, Palette.with_alpha(c, 0.75))
			draw_circle(Vector2(px, y - 2.0), 4.0, Palette.with_alpha(Color.WHITE, 0.5))
