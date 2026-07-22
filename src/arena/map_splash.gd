class_name MapSplash
extends MapBase
## Splashport — leikkisä satama-areena ja LIIKKUVUUDEN AREENA.
## Identiteetti: keskilaituri + kaksi vesikaistaa erilaisin liikkumiskeinoin.
##  - Selkeä keskilaituri (maa) yhdistää spawnit; reliikki keskellä
##  - Ylä- ja alakaista ovat matalaa vettä joka HIDASTAA -> flankki on
##    hitaampi mutta yllättävämpi reitti
##  - LAUTAT ajelehtivat vesikaistoilla ja kuljettavat kyydissä olevia
##  - HYPPYALUSTAT vesiflankeilla sinkoavat takaisin laiturille (nopea paluu)
## Vaikutukset eivät ratkaise otteluita sattumalta — ne luovat vaihtoehtoja.

const PIER_HALF := 155.0
const WATER_MULT := 0.72
const PAD_COOLDOWN := 1.0

const WATER_DEEP := Color("123f5f")
const WATER := Color("1f6f9e")
const WATER_LIGHT := Color("4fb3dd")
const DOCK := Color("7a5330")
const DOCK_DARK := Color("4a3019")
const DOCK_LIGHT := Color("9a6d43")
const PAD_COLOR := Color("4ce0a6")

var _rafts: Array = []          # {y, cx, amp, omega, phase, width, height}
var _pads: Array = []           # {pos, dir, power, radius}
var _buoys: Array = []
var _pad_cd := {}               # hero instance_id -> jäljellä oleva cooldown


func _setup() -> void:
	map_size = Vector2(2400, 1350)
	var half := map_size / 2.0

	# Spawnit keskilaiturin päihin (maalle).
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var y := -105.0 + i * 70.0
		blue.append(Vector2(-half.x + 150.0, y))
		orange.append(Vector2(half.x - 150.0, y))
	spawn_slots = [blue, orange]

	# Suoja-arkut laiturilla (180° symmetriset).
	for c in [Vector2(-450, -45), Vector2(-450, 45)]:
		for center in [c, -c]:
			rect_walls.append(Rect2(center - Vector2(46, 46), Vector2(92, 92)))

	# Lautat ajelehtivat vesikaistoilla (vastavaiheessa).
	_rafts = [
		{"y": -430.0, "cx": 0.0, "amp": 620.0, "omega": 0.46, "phase": 0.0,
			"width": 240.0, "height": 140.0},
		{"y": 430.0, "cx": 0.0, "amp": 620.0, "omega": 0.46, "phase": PI,
			"width": 240.0, "height": 140.0},
	]

	# Hyppyalustat vesiflankeilla -> sinko takaisin laiturille.
	_pads = [
		{"pos": Vector2(-300, -450), "dir": Vector2(0, 1), "power": 1250.0, "radius": 44.0},
		{"pos": Vector2(300, -450), "dir": Vector2(0, 1), "power": 1250.0, "radius": 44.0},
		{"pos": Vector2(-300, 450), "dir": Vector2(0, -1), "power": 1250.0, "radius": 44.0},
		{"pos": Vector2(300, 450), "dir": Vector2(0, -1), "power": 1250.0, "radius": 44.0},
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 550880
	for i in range(8):
		var side := -1.0 if i % 2 == 0 else 1.0
		_buoys.append({
			"pos": Vector2(rng.randf_range(-half.x + 160.0, half.x - 160.0),
				side * rng.randf_range(300.0, half.y - 120.0)),
			"phase": rng.randf() * TAU})


# --- Pelilogiikan rajapinta ---

func terrain_mult(pos: Vector2) -> float:
	if absf(pos.y) < PIER_HALF:
		return 1.0
	if _on_raft(pos):
		return 1.0
	return WATER_MULT


func conveyor_push(pos: Vector2) -> Vector2:
	for raft in _rafts:
		var rx: float = raft.cx + raft.amp * sin(_time * raft.omega + raft.phase)
		var rect := Rect2(rx - raft.width / 2.0, raft.y - raft.height / 2.0,
			raft.width, raft.height)
		if rect.has_point(pos):
			var vx: float = raft.amp * raft.omega * cos(_time * raft.omega + raft.phase)
			return Vector2(vx, 0.0)
	return Vector2.ZERO


func _on_raft(pos: Vector2) -> bool:
	for raft in _rafts:
		var rx: float = raft.cx + raft.amp * sin(_time * raft.omega + raft.phase)
		var rect := Rect2(rx - raft.width / 2.0, raft.y - raft.height / 2.0,
			raft.width, raft.height)
		if rect.has_point(pos):
			return true
	return false


## Hyppyalustat: sinkoavat päälle astuvat hahmot alustan suuntaan.
func _physics_process(_delta: float) -> void:
	var arena = get_parent()
	if arena == null:
		return
	var heroes = arena.get("heroes")
	if heroes == null:
		return
	for id in _pad_cd.keys():
		_pad_cd[id] = maxf(_pad_cd[id] - _delta, 0.0)
	for hero in heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		var id: int = hero.get_instance_id()
		if _pad_cd.get(id, 0.0) > 0.0:
			continue
		for pad in _pads:
			if hero.global_position.distance_to(pad.pos) < pad.radius + hero.radius * 0.5:
				hero.dash(pad.dir, pad.power, 0.38, false)
				_pad_cd[id] = PAD_COOLDOWN
				AudioMgr.play("dash", 0.15, 3.0)
				Fx.ring(arena, pad.pos, Palette.glow(PAD_COLOR, 1.5), 60.0, 0.4)
				Fx.burst(arena, pad.pos, Palette.with_alpha(WATER_LIGHT, 0.7), 10, 200.0, 0.4, 5.0)
				break


# --- Piirto ---

func _draw() -> void:
	var half := map_size / 2.0
	draw_rect(Rect2(-half - Vector2(500, 500), map_size + Vector2(1000, 1000)), Color("0a1826"))

	_draw_water(half)
	_draw_pier(half)
	_draw_team_bases(half)
	_draw_crates()
	_draw_rafts()
	_draw_pads()
	_draw_buoys()

	_draw_vignette()
	_draw_walls_frame(Color("4fb3dd"))


func _draw_water(half: Vector2) -> void:
	# Vesikaistat ylhäällä ja alhaalla laiturin ulkopuolella.
	for band_top in [-half.y, PIER_HALF]:
		var rect := Rect2(-half.x, band_top, map_size.x, half.y - PIER_HALF)
		draw_rect(rect, WATER_DEEP)
		draw_rect(Rect2(rect.position + Vector2(0, 10), Vector2(rect.size.x, rect.size.y - 20)),
			Palette.with_alpha(WATER, 0.85))
		# Aaltoraidat vierivät
		for i in range(6):
			var wy: float = rect.position.y + 30.0 + i * (rect.size.y / 6.0)
			var pts := PackedVector2Array()
			for sx in range(0, 49):
				var x := -half.x + sx * (map_size.x / 48.0)
				var yy := wy + sin(x * 0.012 + _time * 1.5 + i * 0.9) * 6.0
				pts.append(Vector2(x, yy))
			draw_polyline(pts, Palette.with_alpha(WATER_LIGHT, 0.18), 2.0)
		# Kimalluksia
		for i in range(10):
			var gx: float = -half.x + fmod(i * 231.0 + _time * 20.0, map_size.x)
			var gy: float = rect.position.y + fmod(i * 97.0, rect.size.y)
			draw_circle(Vector2(gx, gy), 2.0, Palette.with_alpha(Color.WHITE, 0.25))


func _draw_pier(half: Vector2) -> void:
	var rect := Rect2(-half.x, -PIER_HALF, map_size.x, PIER_HALF * 2.0)
	draw_rect(rect, DOCK_DARK)
	draw_rect(Rect2(rect.position + Vector2(0, 6), Vector2(rect.size.x, rect.size.y - 12)), DOCK)
	# Lankut (pystysaumat)
	var plank := 90.0
	var count := int(map_size.x / plank)
	for i in range(count + 1):
		var x := -half.x + i * plank
		draw_line(Vector2(x, -PIER_HALF + 6.0), Vector2(x, PIER_HALF - 6.0),
			Palette.with_alpha(DOCK_DARK, 0.7), 2.0)
		draw_line(Vector2(x + 3.0, -PIER_HALF + 6.0), Vector2(x + 3.0, PIER_HALF - 6.0),
			Palette.with_alpha(DOCK_LIGHT, 0.2), 1.0)
	# Reunapalkit ja hehku vedenrajaan
	for edge in [-PIER_HALF, PIER_HALF]:
		draw_line(Vector2(-half.x, edge), Vector2(half.x, edge), DOCK_LIGHT, 4.0)
		draw_line(Vector2(-half.x, edge + sign(edge) * 3.0),
			Vector2(half.x, edge + sign(edge) * 3.0), Palette.with_alpha(WATER_LIGHT, 0.4), 2.0)
	# Kiinnityspollarit reunoille
	for i in range(-4, 5):
		for edge2 in [-PIER_HALF + 14.0, PIER_HALF - 14.0]:
			draw_circle(Vector2(i * 250.0, edge2), 8.0, DOCK_DARK)
			draw_circle(Vector2(i * 250.0, edge2), 5.0, DOCK_LIGHT)


func _draw_team_bases(half: Vector2) -> void:
	for team in [0, 1]:
		var cx := -half.x + 170.0 if team == 0 else half.x - 170.0
		var color := Palette.team(team)
		var center := Vector2(cx, 0)
		draw_circle(center, 210.0, Palette.with_alpha(color, 0.12))
		if team == 1:
			draw_arc(center, 200.0, -PI * 0.6, PI * 0.6, 24, Palette.with_alpha(color, 0.4), 4.0)
		else:
			draw_arc(center, 200.0, PI * 0.4, PI * 1.6, 24, Palette.with_alpha(color, 0.4), 4.0)


func _draw_crates() -> void:
	for wall_rect in rect_walls:
		var r: Rect2 = wall_rect
		draw_rect(Rect2(r.position + Vector2(3, 5), r.size), Palette.with_alpha(Color.BLACK, 0.3))
		draw_rect(r, DOCK_DARK)
		draw_rect(Rect2(r.position + Vector2(4, 4), r.size - Vector2(8, 8)), DOCK)
		# Ristikkolauta
		draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Palette.with_alpha(DOCK_DARK, 0.8), 3.0)
		draw_line(Vector2(r.end.x - 6, r.position.y + 6), Vector2(r.position.x + 6, r.end.y - 6),
			Palette.with_alpha(DOCK_DARK, 0.8), 3.0)
		draw_rect(r, DOCK_LIGHT, false, 2.0)


func _draw_rafts() -> void:
	for raft in _rafts:
		var rx: float = raft.cx + raft.amp * sin(_time * raft.omega + raft.phase)
		var center := Vector2(rx, raft.y)
		var w: float = raft.width
		var h: float = raft.height
		var bob := sin(_time * 2.0 + raft.phase) * 3.0
		center.y += bob
		# Varjo vedessä
		draw_rect(Rect2(center + Vector2(-w / 2.0 + 6, -h / 2.0 + 10), Vector2(w, h)),
			Palette.with_alpha(Color.BLACK, 0.25))
		# Lauttarunko
		draw_rect(Rect2(center - Vector2(w / 2.0, h / 2.0), Vector2(w, h)), DOCK_DARK)
		draw_rect(Rect2(center - Vector2(w / 2.0 - 5, h / 2.0 - 5), Vector2(w - 10, h - 10)), DOCK)
		# Lankut
		for i in range(1, 5):
			var lx := center.x - w / 2.0 + i * (w / 5.0)
			draw_line(Vector2(lx, center.y - h / 2.0 + 6), Vector2(lx, center.y + h / 2.0 - 6),
				Palette.with_alpha(DOCK_DARK, 0.7), 2.0)
		# Tynnyri keskelle
		draw_circle(center, 22.0, Color("8a5a2c"))
		draw_arc(center, 22.0, 0.0, TAU, 16, DOCK_DARK, 3.0)
		draw_line(center + Vector2(-22, -6), center + Vector2(22, -6), DOCK_DARK, 2.0)
		draw_line(center + Vector2(-22, 6), center + Vector2(22, 6), DOCK_DARK, 2.0)
		# Kulkusuuntanuoli
		var vx: float = raft.amp * raft.omega * cos(_time * raft.omega + raft.phase)
		if absf(vx) > 20.0:
			var dir := signf(vx)
			var tip := center + Vector2(dir * (w / 2.0 + 14.0), 0)
			draw_line(center + Vector2(dir * (w / 2.0 - 4.0), 0), tip,
				Palette.with_alpha(WATER_LIGHT, 0.7), 3.0)
			draw_line(tip, tip + Vector2(-dir * 8.0, -6.0), Palette.with_alpha(WATER_LIGHT, 0.7), 3.0)
			draw_line(tip, tip + Vector2(-dir * 8.0, 6.0), Palette.with_alpha(WATER_LIGHT, 0.7), 3.0)


func _draw_pads() -> void:
	for pad in _pads:
		var center: Vector2 = pad.pos
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		# Alusta-laituri
		draw_circle(center + Vector2(0, 6), pad.radius + 6.0, Palette.with_alpha(Color.BLACK, 0.25))
		draw_circle(center, pad.radius + 4.0, DOCK_DARK)
		draw_circle(center, pad.radius, DOCK)
		# Hehkuva jousi
		draw_circle(center, pad.radius * 0.62, Palette.with_alpha(PAD_COLOR, 0.3 + pulse * 0.3))
		draw_arc(center, pad.radius * 0.62, 0.0, TAU, 20, Palette.glow(PAD_COLOR, 1.5), 3.0)
		# Suuntanuoli
		var d: Vector2 = pad.dir
		var pr: float = pad.radius
		var tip: Vector2 = center + d * (pr * 0.5 + pulse * 6.0)
		var perp := d.orthogonal() * 8.0
		draw_colored_polygon(PackedVector2Array([tip + d * 10.0, tip + perp, tip - perp]),
			Palette.glow(PAD_COLOR, 1.7))


func _draw_buoys() -> void:
	for buoy in _buoys:
		var pos: Vector2 = buoy.pos
		var bob := sin(_time * 2.5 + buoy.phase) * 4.0
		var p := pos + Vector2(0, bob)
		draw_circle(p + Vector2(0, 8), 9.0, Palette.with_alpha(Color.BLACK, 0.2))
		draw_circle(p, 9.0, Color("e8534f"))
		draw_arc(p, 9.0, 0.0, TAU, 12, Color("f2f5ff"), 2.0)
		draw_circle(p + Vector2(0, -12), 3.0, Color("f2f5ff"))
