class_name HeroVisual
extends Node2D
## Sankarin ulkoasu piirretään kokonaan koodilla: paksut ääriviivat, selkeä
## siluetti, pehmeä varjo, tunnusrengas ja pienet animaatiot (hengitys,
## kävelyheilunta, squash & stretch, osumavälähdys).

var hero: Hero = null
var aux := 0.0                    # sankarikohtainen lisäparametri (esim. Quillin lataus)

var _time := 0.0
var _flash := 0.0
var _attack_anim := 0.0
var _draw_scale := Vector2.ONE
var _trail: Array = []            # Blinkin huivia yms. varten


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_attack_anim = maxf(_attack_anim - delta * 4.0, 0.0)
	if hero != null:
		_trail.push_front(hero.global_position)
		if _trail.size() > 10:
			_trail.pop_back()
	queue_redraw()


func flash() -> void:
	_flash = 1.0


func attack_swing() -> void:
	_attack_anim = 1.0
	squash(1.15, 0.88)


func squash(x: float, y: float) -> void:
	_draw_scale = Vector2(x, y)
	var tween := create_tween()
	tween.tween_property(self, "_draw_scale", Vector2.ONE, 0.28)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if hero == null or not hero.alive:
		return

	var def := HeroDef.get_def(hero.hero_id)
	var c1: Color = def["color"]
	var c2: Color = def["color_b"]
	var moving: float = clampf(hero.velocity.length() / 300.0, 0.0, 1.0)
	var bob := absf(sin(_time * 9.0)) * 4.0 * moving + sin(_time * 2.2) * 1.5
	if hero.hero_id == "luma":
		bob += 5.0 + sin(_time * 3.0) * 2.5

	_draw_ground_ring()
	_draw_shadow(bob)

	# Vartalo piirretään bobin ja squashin kanssa.
	draw_set_transform(Vector2(0.0, -14.0 - bob), sin(_time * 10.0) * 0.05 * moving, _draw_scale)
	match hero.hero_id:
		"bastion":
			_paint_bastion(c1, c2)
		"ember":
			_paint_ember(c1, c2)
		"luma":
			_paint_luma(c1, c2)
		"blink":
			_paint_blink(c1, c2)
		"bramble":
			_paint_bramble(c1, c2)
		"quill":
			_paint_quill(c1, c2)
		_:
			_paint_generic(c1, c2)

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 26.0, Color(1, 1, 1, _flash * 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_status(bob)


# --- Yhteiset osat ---

func _draw_ground_ring() -> void:
	var is_human: bool = hero.profile.is_human()
	var ring_color: Color = hero.profile.color() if is_human else Palette.with_alpha(Palette.team(hero.team), 0.4)
	var width := 4.0 if is_human else 2.5
	draw_arc(Vector2(0, 8), hero.radius + 7.0, 0.0, TAU, 40, Palette.with_alpha(Color.BLACK, 0.25), width + 3.0)
	draw_arc(Vector2(0, 8), hero.radius + 7.0, 0.0, TAU, 40, ring_color, width)
	if is_human:
		UiKit.draw_text(self, Vector2(0, 34), str(hero.profile.index + 1), 15, ring_color, true, 3)
	if hero.ult_charge >= 100.0:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(Vector2(0, 8), hero.radius + 12.0, 0.0, TAU, 40,
			Palette.with_alpha(Palette.GOLD, 0.35 + pulse * 0.4), 2.5)


func _draw_shadow(bob: float) -> void:
	var shrink: float = clampf(1.0 - bob * 0.02, 0.6, 1.0)
	draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.42) * shrink)
	draw_circle(Vector2.ZERO, hero.radius + 2.0, Color(0.02, 0.03, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_status(bob: float) -> void:
	var top := Vector2(0, -52.0 - bob)
	# Pieni kestopalkki pään yläpuolella
	var w := 46.0
	var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
	draw_rect(Rect2(top + Vector2(-w / 2.0 - 1.0, -1.0), Vector2(w + 2.0, 7.0)), Color(0, 0, 0, 0.45))
	var hp_color: Color = Palette.GOOD if frac > 0.35 else Palette.BAD
	draw_rect(Rect2(top + Vector2(-w / 2.0, 0.0), Vector2(w * frac, 5.0)), hp_color)
	if hero.shield_hp > 0.0:
		var sfrac: float = clampf(hero.shield_hp / hero.max_hp, 0.0, 1.0)
		draw_rect(Rect2(top + Vector2(-w / 2.0, -4.0), Vector2(w * sfrac, 3.0)), Palette.SHIELD)
		# Kilpikupla
		draw_arc(Vector2(0, -14), hero.radius + 10.0, 0.0, TAU, 36,
			Palette.with_alpha(Palette.SHIELD, 0.5 + 0.2 * sin(_time * 8.0)), 3.0)

	if hero.guard_timer > 0.0:
		# Suuntatorjunnan kaari tähtäyksen suuntaan
		var a := hero.aim.angle()
		var half := deg_to_rad(hero.guard_arc_deg)
		draw_arc(Vector2(0, -14), hero.radius + 13.0, a - half, a + half, 24,
			Palette.glow(Palette.SHIELD, 1.4), 5.0)

	if hero.root_timer > 0.0:
		for i in range(3):
			var ang := _time * 2.0 + TAU * i / 3.0
			var p := Vector2(cos(ang), sin(ang) * 0.4) * (hero.radius + 4.0) + Vector2(0, 6)
			draw_line(p, p + Vector2(0, -12), Color("2f7a33"), 3.0)
	if hero.stun_timer > 0.0:
		for i in range(3):
			var ang := _time * 5.0 + TAU * i / 3.0
			var p := Vector2(cos(ang), sin(ang) * 0.5) * 18.0 + Vector2(0, -46.0 - bob)
			draw_circle(p, 3.0, Palette.GOLD)


func _body_base(center: Vector2, r: float, c1: Color, c2: Color) -> void:
	draw_circle(center, r + 3.0, Palette.darker(c2, 0.5))
	draw_circle(center, r, c1)
	# Kevyt sävytys alareunaan
	draw_circle(center + Vector2(0, r * 0.35), r * 0.72, Palette.with_alpha(c2, 0.35))


func _eyes(center: Vector2, spread := 7.0, size := 4.0) -> void:
	var look: Vector2 = hero.aim * 2.5
	var perp: Vector2 = hero.aim.orthogonal().normalized() * spread
	for side in [-1.0, 1.0]:
		var p: Vector2 = center + perp * side + look
		draw_circle(p, size, Color.WHITE)
		draw_circle(p + hero.aim * 1.5, size * 0.55, Color(0.1, 0.12, 0.2))


# --- Sankarikohtaiset ulkoasut ---

func _paint_generic(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))


func _paint_bastion(c1: Color, c2: Color) -> void:
	var a: float = hero.aim.angle()
	# Nuija takakädessä
	var mace_dir: Vector2 = hero.aim.rotated(2.4 - _attack_anim * 2.2)
	var hand: Vector2 = mace_dir * 24.0
	draw_line(Vector2.ZERO, hand + mace_dir * 12.0, Palette.darker(c2, 0.6), 5.0)
	draw_circle(hand + mace_dir * 16.0, 9.0, c2)
	for i in range(6):
		var spike: Vector2 = Vector2.RIGHT.rotated(TAU * i / 6.0) * 12.0
		draw_line(hand + mace_dir * 16.0, hand + mace_dir * 16.0 + spike, c2, 3.0)
	# Leveä runko
	_body_base(Vector2.ZERO, 24.0, c1, c2)
	# Visiiri (litistetty ellipsi polygonina, ettei transformia tarvitse vaihtaa)
	var visor := PackedVector2Array()
	for i in range(20):
		var ang := TAU * i / 20.0
		visor.append(Vector2(0, -6) + Vector2(cos(ang) * 15.0, sin(ang) * 7.0))
	draw_colored_polygon(visor, Palette.darker(c2, 0.7))
	_eyes(Vector2(0, -6), 8.0, 3.5)
	# Kilpi etukädessä (kaari tähtäyksen suunnassa)
	var guard_boost := 1.0 + (0.35 if hero.guard_timer > 0.0 else 0.0)
	draw_arc(hero.aim * 20.0, 18.0 * guard_boost, a - 1.15, a + 1.15, 18, Palette.darker(c2, 0.55), 10.0)
	draw_arc(hero.aim * 20.0, 18.0 * guard_boost, a - 1.05, a + 1.05, 18,
		Palette.glow(c1, 1.25) if hero.guard_timer > 0.0 else c1, 6.0)


func _paint_ember(c1: Color, c2: Color) -> void:
	# Liekkihiukset
	for i in range(3):
		var fx := -8.0 + 8.0 * i
		var h := 14.0 + sin(_time * 7.0 + i * 1.7) * 4.0
		var flame := PackedVector2Array([
			Vector2(fx - 5, -14), Vector2(fx, -14 - h), Vector2(fx + 5, -14)])
		draw_colored_polygon(flame, Palette.glow(Color("ffb347"), 1.6) if i == 1 else c1)
	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))
	# Tulilyhty-sauva
	var side: Vector2 = hero.aim.rotated(-0.9)
	var tip: Vector2 = side * 26.0 + hero.aim * 6.0
	draw_line(side * 8.0, tip, Palette.darker(c2, 0.6), 4.0)
	var pulse := 0.8 + 0.2 * sin(_time * 9.0)
	draw_circle(tip, 8.0 * pulse, Palette.with_alpha(Color("ffd76d"), 0.5))
	draw_circle(tip, 5.0 * pulse, Palette.glow(Color("ffb347"), 2.2))


func _paint_luma(c1: Color, c2: Color) -> void:
	# Hehkuva aura
	draw_circle(Vector2.ZERO, 24.0, Palette.with_alpha(Color("ffe9a8"), 0.15))
	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4), 6.5)
	# Sädekehä
	draw_arc(Vector2(0, -24), 10.0, 0.0, TAU, 24, Palette.glow(Palette.GOLD, 1.8), 3.0)
	# Valosauva ja tähtikärki
	var side: Vector2 = hero.aim.rotated(0.9)
	var tip: Vector2 = side * 24.0 + hero.aim * 8.0
	draw_line(side * 7.0, tip, Color("e8d9b0"), 4.0)
	var star := PackedVector2Array()
	for i in range(8):
		var r := 9.0 if i % 2 == 0 else 3.8
		star.append(tip + Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 2.0) * r)
	draw_colored_polygon(star, Palette.glow(Palette.GOLD, 2.0))


func _paint_blink(c1: Color, c2: Color) -> void:
	# Huivi liikejäljestä
	if _trail.size() > 3:
		var pts := PackedVector2Array()
		for i in range(mini(_trail.size(), 8)):
			pts.append(to_local(_trail[i]) + Vector2(0, -18))
		draw_polyline(pts, Palette.with_alpha(c2, 0.7), 5.0)
	_body_base(Vector2.ZERO, 15.0, c1, c2)
	# Naamio
	draw_rect(Rect2(Vector2(-12, -10), Vector2(24, 8)), Palette.darker(c2, 0.65))
	_eyes(Vector2(0, -6), 6.0, 3.2)
	# Kaksi valomiekkaa
	for side in [-1.0, 1.0]:
		var base: Vector2 = hero.aim.rotated(0.7 * side) * 16.0
		var swing: float = _attack_anim * 1.6 * side
		var blade_dir: Vector2 = hero.aim.rotated(0.25 * side - swing)
		draw_line(base, base + blade_dir * 22.0, Palette.glow(Color("d9c8ff"), 2.4), 3.5)
		draw_circle(base, 3.0, c2)


func _paint_bramble(c1: Color, c2: Color) -> void:
	# Piikkikruunu
	for i in range(3):
		var fx := -10.0 + 10.0 * i
		var thorn := PackedVector2Array([
			Vector2(fx - 4, -16), Vector2(fx, -26), Vector2(fx + 4, -16)])
		draw_colored_polygon(thorn, c2)
	_body_base(Vector2.ZERO, 21.0, c1, c2)
	# Lehtiolkapäät
	for side in [-1.0, 1.0]:
		var leaf := PackedVector2Array([
			Vector2(14 * side, -8), Vector2(26 * side, -16), Vector2(20 * side, -2)])
		draw_colored_polygon(leaf, Palette.darker(c1, 0.8))
	_eyes(Vector2(0, -5), 7.5)
	# Köynnösruoska aaltoilee tähtäyksen suuntaan
	var pts := PackedVector2Array()
	var reach := 30.0 + _attack_anim * 34.0
	for i in range(9):
		var t := i / 8.0
		var wave: Vector2 = hero.aim.orthogonal() * sin(t * 6.0 + _time * 5.0) * 5.0 * t
		pts.append(hero.aim * (10.0 + reach * t) + wave)
	draw_polyline(pts, Palette.darker(c1, 0.75), 4.0)
	draw_circle(pts[pts.size() - 1], 4.0, c2)


func _paint_quill(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 17.0, c1, c2)
	# Huppu
	draw_arc(Vector2(0, -6), 15.0, PI + 0.4, TAU - 0.4, 20, c2, 7.0)
	_eyes(Vector2(0, -4), 6.5)
	# Jousi tähtäyksen suunnassa
	var a: float = hero.aim.angle()
	var bow_pos: Vector2 = hero.aim * 22.0
	draw_arc(bow_pos, 14.0, a - 1.25, a + 1.25, 16, Color("8a6a3f"), 4.0)
	var top: Vector2 = bow_pos + Vector2.RIGHT.rotated(a - 1.25) * 14.0
	var bottom: Vector2 = bow_pos + Vector2.RIGHT.rotated(a + 1.25) * 14.0
	var pull: Vector2 = bow_pos - hero.aim * (4.0 + aux * 10.0)
	draw_line(top, pull, Color("e8e2d0"), 2.0)
	draw_line(bottom, pull, Color("e8e2d0"), 2.0)
	if aux > 0.05:
		# Ladattu nuoli hehkuu
		var glow_color: Color = Palette.glow(c1, 1.0 + aux * 1.5)
		draw_line(pull, bow_pos + hero.aim * 16.0, glow_color, 3.0)
		if aux >= 1.0:
			draw_circle(bow_pos + hero.aim * 16.0, 5.0 + sin(_time * 12.0) * 1.5,
				Palette.glow(Palette.GOLD, 2.0))
