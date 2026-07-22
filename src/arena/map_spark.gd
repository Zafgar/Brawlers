class_name MapSpark
extends MapBase
## Sparkring — tiivis neon-areena ja KAAOKSEN AREENA.
## Identiteetti: pieni koko + kimmoketolpat = jatkuvaa lähitaistelua.
##  - Selvästi muita pienempi -> kamera lähellä, taistelu tauotonta
##  - Reliikki keskellä, ympärillä neljä KIMMOKETOLPPAA (bumperia)
##  - Bumperiin hipaisu tai tönäisy singahduttaa pois -> pinball-kaaos
##  - Tönäisykyvyt (Boulder, Bastion, Maestro...) korostuvat: vihollisen
##    voi lingota bumperiin
## Nopeatempoinen, ihanteellinen 1v1- ja 2v2-otteluihin.

const FLOOR := Color("11162e")
const GRID := Color("2b4080")
const NEON := Color("3fe0ff")
const NEON2 := Color("ff5ecb")
const BUMP_POWER := 720.0
const BUMP_CD := 0.35

var _bumpers: Array = []        # {pos, radius, hit_t}
var _bump_cd := {}              # hero id -> jäljellä oleva cooldown


func _setup() -> void:
	map_size = Vector2(1700, 1050)
	var half := map_size / 2.0

	# Kompaktit spawnit laidoille.
	var blue: Array = []
	var orange: Array = []
	for i in range(4):
		var y := -90.0 + i * 60.0
		blue.append(Vector2(-half.x + 130.0, y))
		orange.append(Vector2(half.x - 130.0, y))
	spawn_slots = [blue, orange]

	# Neljä kimmoketolppaa timanttina reliikin ympärille.
	_bumpers = [
		{"pos": Vector2(0, -270), "radius": 52.0, "hit_t": -1.0},
		{"pos": Vector2(0, 270), "radius": 52.0, "hit_t": -1.0},
		{"pos": Vector2(-360, 0), "radius": 52.0, "hit_t": -1.0},
		{"pos": Vector2(360, 0), "radius": 52.0, "hit_t": -1.0},
	]
	for b in _bumpers:
		pillars.append({"pos": b.pos, "radius": b.radius})


# --- Kimmokelogiikka ---

func _physics_process(delta: float) -> void:
	var arena = get_parent()
	if arena == null:
		return
	var heroes = arena.get("heroes")
	if heroes == null:
		return
	for id in _bump_cd.keys():
		_bump_cd[id] = maxf(_bump_cd[id] - delta, 0.0)
	for hero in heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		var id: int = hero.get_instance_id()
		if _bump_cd.get(id, 0.0) > 0.0:
			continue
		for b in _bumpers:
			var diff: Vector2 = hero.global_position - b.pos
			var d := diff.length()
			if d > 1.0 and d < b.radius + hero.radius + 12.0:
				hero.dash(diff.normalized(), BUMP_POWER, 0.18, false)
				_bump_cd[id] = BUMP_CD
				b.hit_t = _time
				AudioMgr.play("bump", 0.2)
				Fx.ring(arena, b.pos, Palette.glow(NEON2, 1.6), b.radius + 34.0, 0.35)
				break


# --- Piirto ---

func _draw() -> void:
	var half := map_size / 2.0
	draw_rect(Rect2(-half - Vector2(400, 400), map_size + Vector2(800, 800)), Color("070a1a"))
	draw_rect(Rect2(-half, map_size), FLOOR)

	# Keskustan hehku
	draw_circle(Vector2.ZERO, 420.0, Palette.with_alpha(Color("18224a"), 0.6))
	draw_circle(Vector2.ZERO, 240.0, Palette.with_alpha(Color("1e2a58"), 0.6))

	# Neon-ruudukko
	var step := 130.0
	var cols := int(map_size.x / step)
	var rows := int(map_size.y / step)
	for i in range(cols + 1):
		var x := -half.x + i * step
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), Palette.with_alpha(GRID, 0.35), 1.5)
	for j in range(rows + 1):
		var y := -half.y + j * step
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), Palette.with_alpha(GRID, 0.35), 1.5)

	_draw_team_bases(half)
	_draw_center_pad()
	_draw_bumpers()
	_draw_motes(24, NEON, 22.0, 3131)

	_draw_vignette()
	# Neon-reunus
	draw_rect(Rect2(-half, map_size), Palette.glow(NEON, 1.3), false, 4.0)
	draw_rect(Rect2(-half + Vector2(7, 7), map_size - Vector2(14, 14)),
		Palette.with_alpha(NEON2, 0.4), false, 2.0)
	_draw_walls_frame(NEON)


func _draw_team_bases(half: Vector2) -> void:
	for team in [0, 1]:
		var cx := -half.x + 150.0 if team == 0 else half.x - 150.0
		var color := Palette.team(team)
		draw_circle(Vector2(cx, 0), 170.0, Palette.with_alpha(color, 0.12))
		draw_arc(Vector2(cx, 0), 160.0, 0.0, TAU, 40, Palette.with_alpha(color, 0.45), 3.0)


func _draw_center_pad() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(Vector2.ZERO, 120.0, Palette.with_alpha(NEON, 0.06))
	draw_arc(Vector2.ZERO, 108.0, 0.0, TAU, 48, Palette.with_alpha(NEON, 0.35 + pulse * 0.2), 3.0)
	for i in range(4):
		var ang := _time * 0.8 + TAU * i / 4.0
		draw_circle(Vector2(cos(ang), sin(ang)) * 96.0, 4.0, Palette.glow(NEON, 1.4))


func _draw_bumpers() -> void:
	for b in _bumpers:
		var pos: Vector2 = b.pos
		var r: float = b.radius
		var hit_t: float = b.hit_t
		var flash: float = clampf(0.3 - (_time - hit_t), 0.0, 0.3) / 0.3
		var pulse := 0.6 + 0.4 * sin(_time * 6.0 + pos.x)

		# Varjo
		draw_circle(pos + Vector2(0, 8), r, Palette.with_alpha(Color.BLACK, 0.3))
		# Iskuvälähdys
		if flash > 0.0:
			draw_circle(pos, r + 20.0 * flash, Palette.with_alpha(NEON2, 0.3 * flash))
		# Tolppa
		draw_circle(pos, r, Palette.darker(NEON2, 0.5))
		draw_circle(pos, r - 6.0, Color("2a1740"))
		draw_arc(pos, r - 3.0, 0.0, TAU, 32, Palette.glow(NEON2, 1.3 + flash), 4.0)
		# Keskusydin sykkii
		draw_circle(pos, (r - 20.0) * (0.8 + pulse * 0.2 + flash * 0.4),
			Palette.with_alpha(Palette.glow(NEON2, 1.4), 0.5 + flash * 0.5))
		draw_circle(pos, 6.0, Palette.glow(Color.WHITE, 1.4))
		# Kimmokenuolet ulospäin
		for i in range(4):
			var ang := TAU * i / 4.0 + PI / 4.0
			var d := Vector2(cos(ang), sin(ang))
			var tip := pos + d * (r + 4.0 + flash * 6.0)
			draw_line(pos + d * (r - 4.0), tip, Palette.with_alpha(NEON2, 0.6 + flash * 0.4), 2.5)
