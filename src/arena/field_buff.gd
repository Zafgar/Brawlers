class_name FieldBuff
extends Node2D
## Kenttäbuffi (blue/red). Ilmestyy kentälle tasaisin väliajoin ja on
## HENKILÖKOHTAINEN omalle tiimille. Buffin saa vain MURSKAAMALLA sen:
## seiso päällä hetki (ei riitä että kävelee ohi). Vihollinen ei voi ottaa
## sitä itselleen mutta voi murskata sen tuhotakseen (menetetään). KO myös
## rikkoo kantajan buffin.
##
## Blue = resurssin (mana/energia) nopea palautuminen + raivo kertyy kovempaa.
##        Sankarit ilman resurssia eivät hyödy siitä.
## Red  = +25 % aiheutettu vahinko ja elämän palautuminen. Kaikki hyötyvät.

const BREAK_RADIUS := 58.0
const BREAK_TIME := 1.3           # kuinka kauan murskaaminen kestää
const LIFETIME := 28.0            # kauanko orb odottaa kentällä ennen katoamista
const DURATION := 22.0            # buffin kesto kantajalla

var arena = null
var type := "blue"                # "blue" tai "red"
var owner_team := 0

var _time := 0.0
var _age := 0.0
var _progress := 0.0              # 0..1 murskausedistymä
var _breaking_enemy := false      # murskaako vihollinen (tuhoaa) vai oma (nappaa)
var _claimer: Hero = null


func setup(p_arena, p_type: String, p_team: int, pos: Vector2) -> void:
	arena = p_arena
	type = p_type
	owner_team = p_team
	global_position = pos
	z_index = 20


func _physics_process(delta: float) -> void:
	_time += delta
	_age += delta
	queue_redraw()
	if _age >= LIFETIME:
		queue_free()
		return
	if arena == null or arena.state != arena.State.PLAY:
		return

	# Ketkä ovat murskausetäisyydellä?
	var owner_here: Hero = null
	var enemy_here: Hero = null
	for hero in arena.heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		if hero.global_position.distance_to(global_position) > BREAK_RADIUS + hero.radius:
			continue
		if hero.team == owner_team:
			if owner_here == null:
				owner_here = hero
		elif enemy_here == null:
			enemy_here = hero

	# Oma nappaa, vihollinen tuhoaa; molemmat läsnä (tai ei ketään) -> ei etene.
	if owner_here != null and enemy_here == null:
		_breaking_enemy = false
		_claimer = owner_here
		_progress += delta / BREAK_TIME
	elif enemy_here != null and owner_here == null:
		_breaking_enemy = true
		_claimer = null
		_progress += delta / BREAK_TIME
	else:
		_progress = maxf(_progress - delta / BREAK_TIME, 0.0)

	if _progress >= 1.0:
		_finish()


func _finish() -> void:
	if _breaking_enemy:
		# Vihollinen tuhosi buffin (denied) — kukaan ei saa sitä.
		AudioMgr.play("ui_back", 0.1, -2.0)
		Fx.burst(arena, global_position, Palette.with_alpha(_col(), 0.7), 16, 240.0, 0.5, 6.0)
	elif _claimer != null and is_instance_valid(_claimer) and _claimer.alive:
		_claimer.apply_field_buff(type, DURATION)
		AudioMgr.play("pickup", 0.1, 3.0)
		Fx.ring(arena, global_position, Palette.glow(_col(), 1.6), 90.0, 0.5, 5.0)
		Fx.burst(arena, global_position, Palette.with_alpha(_col(), 0.8), 14, 200.0, 0.5, 6.0)
	queue_free()


func _col() -> Color:
	return Color("4a8cff") if type == "blue" else Color("ff5a4a")


func _draw() -> void:
	var col := _col()
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	# Varjo maahan
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 16.0, Color(0.02, 0.03, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Tiimivärikehä (kenen buffi tämä on)
	var team_col: Color = Palette.team(owner_team)
	draw_arc(Vector2.ZERO, BREAK_RADIUS, 0.0, TAU, 40, Palette.with_alpha(team_col, 0.28), 2.0)
	# Hehku
	draw_circle(Vector2.ZERO, 22.0 + pulse * 3.0, Palette.with_alpha(col, 0.18))
	# Kristalli
	var r := 15.0
	var gem := PackedVector2Array([
		Vector2(0, -r), Vector2(r * 0.8, 0), Vector2(0, r), Vector2(-r * 0.8, 0)])
	draw_colored_polygon(gem, Palette.glow(col, 1.4))
	var inner := PackedVector2Array([
		Vector2(0, -r * 0.5), Vector2(r * 0.4, 0), Vector2(0, r * 0.5), Vector2(-r * 0.4, 0)])
	draw_colored_polygon(inner, Palette.glow(Color.WHITE, 1.3))
	# Kirjain B/R
	UiKit.draw_text(self, Vector2(0, -32.0), "B" if type == "blue" else "R", 16,
		Palette.glow(col, 1.5), true, 3)
	# Murskausrengas
	if _progress > 0.01:
		var ring_col: Color = Palette.BAD if _breaking_enemy else Palette.glow(col, 1.4)
		draw_arc(Vector2.ZERO, 28.0, -PI / 2.0, -PI / 2.0 + TAU * _progress, 32, ring_col, 4.0)
