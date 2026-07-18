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
	# Jokaisella hahmolla oma vaihe, ettei koko joukkue pompi yhtä aikaa.
	var phase := float(hero.profile.index) * 0.9
	var bob := absf(sin(_time * 9.0 + phase)) * 4.0 * moving + sin(_time * 2.2 + phase) * 1.5
	if hero.hero_id == "luma":
		bob += 5.0 + sin(_time * 3.0) * 2.5

	_draw_ground_ring()
	_draw_shadow(bob)
	_draw_feet(moving, phase, c1, c2)

	# Vartalo piirretään bobin, kevyen tähtäyskallistuksen ja squashin kanssa.
	var lean: Vector2 = hero.aim * 2.5 * (0.5 + moving * 0.5)
	draw_set_transform(Vector2(0.0, -14.0 - bob) + lean,
		sin(_time * 10.0 + phase) * 0.05 * moving, _draw_scale)
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
		"boulder":
			_paint_boulder(c1, c2)
		"volt":
			_paint_volt(c1, c2)
		"shade":
			_paint_shade(c1, c2)
		"tide":
			_paint_tide(c1, c2)
		"scout":
			_paint_scout(c1, c2)
		"maestro":
			_paint_maestro(c1, c2)
		_:
			_paint_generic(c1, c2)

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 26.0, Color(1, 1, 1, _flash * 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_status(bob)


# --- Yhteiset osat ---

func _draw_ground_ring() -> void:
	# Joukkue näkyy ensin: selkeä sinioranssi rengas ja hehku jokaisella.
	# Oma pelaajaväri on numerolaatassa renkaan alla.
	var is_human: bool = hero.profile.is_human()
	var team_color := Palette.team(hero.team)

	draw_circle(Vector2(0, 8), hero.radius + 16.0,
		Palette.with_alpha(team_color, 0.16 if is_human else 0.10))
	draw_arc(Vector2(0, 8), hero.radius + 7.0, 0.0, TAU, 40,
		Palette.with_alpha(Color.BLACK, 0.3), 8.0 if is_human else 5.5)
	draw_arc(Vector2(0, 8), hero.radius + 7.0, 0.0, TAU, 40,
		Palette.with_alpha(team_color, 0.95 if is_human else 0.55),
		5.0 if is_human else 3.0)

	if is_human:
		# Pelaajan oma tunnusväri ja numero laattana renkaan alla.
		var chip := Vector2(0, hero.radius + 16.0)
		draw_circle(chip, 13.0, Palette.with_alpha(Color.BLACK, 0.4))
		draw_circle(chip, 11.0, hero.profile.color())
		UiKit.draw_text(self, chip + Vector2(0, 1), str(hero.profile.index + 1), 15,
			Palette.TEXT_DARK, true)
		# Pienet cooldown-pallurat: kyky 1, kyky 2, väistö.
		var slots := ["a1", "a2", "dodge"]
		for i in range(slots.size()):
			var pip := Vector2(-16.0 + i * 16.0, hero.radius + 34.0)
			var max_cd: float = maxf(hero.cd_max[slots[i]], 0.001)
			var progress: float = clampf(1.0 - hero.cd[slots[i]] / max_cd, 0.0, 1.0)
			draw_circle(pip, 5.5, Color(0, 0, 0, 0.5))
			if progress >= 1.0:
				draw_circle(pip, 4.5, Palette.glow(hero.hero_color(), 1.2))
			elif progress > 0.02:
				draw_arc(pip, 4.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 16,
					Palette.with_alpha(hero.hero_color(), 0.8), 2.5)

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

	if hero.mark_timer > 0.0:
		# Scoutin merkki: pulssaava kultatimantti pään yläpuolella.
		var mark_center := top + Vector2(0, -16.0)
		var mark_pulse := 1.0 + 0.2 * sin(_time * 8.0)
		var mark := PackedVector2Array([
			mark_center + Vector2(0, -7) * mark_pulse, mark_center + Vector2(6, 0) * mark_pulse,
			mark_center + Vector2(0, 7) * mark_pulse, mark_center + Vector2(-6, 0) * mark_pulse])
		draw_colored_polygon(mark, Palette.glow(Palette.GOLD, 1.7))

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
	draw_circle(center, r + 3.0, Palette.darker(c2, 0.5))      # ääriviiva
	draw_circle(center, r, c1)                                 # runko
	# Alareunan sävytys antaa pyöreyttä
	draw_circle(center + Vector2(0, r * 0.35), r * 0.72, Palette.with_alpha(c2, 0.35))
	# Kiiltävä yläkorostus -> "kiiltävä lelu" -tunnelma
	draw_circle(center + Vector2(-r * 0.32, -r * 0.4), r * 0.36,
		Palette.with_alpha(Color.WHITE, 0.22))
	draw_circle(center + Vector2(-r * 0.34, -r * 0.44), r * 0.18,
		Palette.with_alpha(Color.WHITE, 0.28))


func _eyes(center: Vector2, spread := 7.0, size := 4.0) -> void:
	var look: Vector2 = hero.aim * 2.5
	var perp: Vector2 = hero.aim.orthogonal().normalized() * spread
	for side in [-1.0, 1.0]:
		var p: Vector2 = center + perp * side + look
		draw_circle(p, size + 1.0, Palette.with_alpha(Color(0.08, 0.1, 0.16), 0.5))
		draw_circle(p, size, Color.WHITE)
		draw_circle(p + hero.aim * 1.5, size * 0.55, Color(0.1, 0.12, 0.2))
		# Pieni kiilto silmään
		draw_circle(p + Vector2(-size * 0.3, -size * 0.4), size * 0.22, Color.WHITE)


## Lyhyt käsivarsi: tumma ääriviiva + värillinen raaja.
func _limb(from: Vector2, to: Vector2, color: Color, w := 5.0) -> void:
	draw_line(from, to, Palette.darker(color, 0.45), w + 2.0)
	draw_line(from, to, color, w)


## Piirtää käden pitämään asetta: olkapää rungon reunalta kämmeneen.
## Näin ase ei enää leiju irrallaan vaan hahmo pitelee sitä.
func _hold(hand: Vector2, color: Color, body_r: float, w := 5.0) -> void:
	if hand.length() < 1.0:
		return
	var shoulder: Vector2 = hand.normalized() * (body_r - 5.0)
	_limb(shoulder, hand, color, w)
	draw_circle(hand, w * 0.9 + 1.5, Palette.darker(color, 0.45))
	draw_circle(hand, w * 0.9, color)


## Pienet jalat, joiden yli vartalo pomppii (maadoitus + hyppyvaikutelma).
func _draw_feet(moving: float, phase: float, c1: Color, c2: Color) -> void:
	var step := sin(_time * 9.0 + phase) * moving
	for side in [-1.0, 1.0]:
		var lift: float = maxf(0.0, step * side) * 5.0
		var foot := Vector2(side * 8.0, 7.0 - lift)
		draw_circle(foot, 5.0, Palette.darker(c2, 0.5))
		draw_circle(foot + Vector2(0, -1.5), 3.4, Palette.darker(c1, 0.8))


# --- Sankarikohtaiset ulkoasut ---

func _paint_generic(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))


func _paint_bastion(c1: Color, c2: Color) -> void:
	var a: float = hero.aim.angle()
	var guarding: bool = hero.guard_timer > 0.0

	# Piikkinuija takakädessä (heiluu iskiessä)
	var mace_dir: Vector2 = hero.aim.rotated(2.4 - _attack_anim * 2.4)
	var hand: Vector2 = mace_dir * 24.0
	var head: Vector2 = hand + mace_dir * 15.0
	_limb(mace_dir * 12.0, hand, c1, 5.0)
	draw_line(hand, head, Palette.darker(c2, 0.6), 6.0)
	for i in range(6):
		var spike: Vector2 = Vector2.RIGHT.rotated(TAU * i / 6.0 + _time * 0.6) * 12.0
		draw_line(head, head + spike, Palette.darker(c2, 0.7), 4.0)
	draw_circle(head, 10.0, Palette.darker(c2, 0.5))
	draw_circle(head, 7.5, c2)
	draw_circle(head + Vector2(-2, -2), 3.0, Palette.with_alpha(Color.WHITE, 0.5))

	# Hartiapanssarit rungon takana
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(21.0 * side, -2), 12.0, Palette.darker(c2, 0.5))
		draw_circle(Vector2(21.0 * side, -3), 8.5, Palette.darker(c1, 0.85))

	# Järeä runko
	_body_base(Vector2.ZERO, 25.0, c1, c2)
	# Rintapanssarin V-saumat
	draw_line(Vector2(-9, 3), Vector2(0, 13), Palette.darker(c2, 0.7), 3.0)
	draw_line(Vector2(9, 3), Vector2(0, 13), Palette.darker(c2, 0.7), 3.0)

	# Kypärän visiiri (litistetty ellipsi)
	var visor := PackedVector2Array()
	for i in range(20):
		var ang := TAU * i / 20.0
		visor.append(Vector2(0, -7) + Vector2(cos(ang) * 15.0, sin(ang) * 7.0))
	draw_colored_polygon(visor, Palette.darker(c2, 0.7))
	_eyes(Vector2(0, -7), 8.0, 3.5)

	# Kilpikäsi ja kilpilevy tähtäyksen suunnassa
	_hold(hero.aim * 15.0, c1, 25.0, 6.0)
	var boost := 1.15 if guarding else 1.0
	var perp: Vector2 = hero.aim.orthogonal().normalized()
	var sc: Vector2 = hero.aim * 21.0
	var w := 16.0 * boost
	var plate := PackedVector2Array([
		sc - hero.aim * 7.0 + perp * w,
		sc + hero.aim * 5.0 + perp * w * 0.85,
		sc + hero.aim * 12.0,
		sc + hero.aim * 5.0 - perp * w * 0.85,
		sc - hero.aim * 7.0 - perp * w,
	])
	draw_colored_polygon(plate, Palette.glow(c1, 1.2) if guarding else Palette.darker(c2, 0.5))
	draw_polyline(plate + PackedVector2Array([plate[0]]),
		c1 if guarding else Palette.darker(c2, 0.7), 3.0)
	# Kilven pystyharja ja keskikohouma
	draw_line(sc - hero.aim * 4.0, sc + hero.aim * 8.0, Palette.darker(c2, 0.7), 2.5)
	draw_circle(sc, 5.0, c2)
	draw_circle(sc + Vector2(-1, -1), 2.5, Palette.with_alpha(Color.WHITE, 0.6))
	if guarding:
		draw_arc(sc, 22.0 * boost, a - 1.2, a + 1.2, 22, Palette.glow(Palette.SHIELD, 1.5), 3.5)


func _paint_ember(c1: Color, c2: Color) -> void:
	# Lämmin hehkuaura
	var aura := 0.9 + 0.1 * sin(_time * 6.0)
	draw_circle(Vector2.ZERO, 30.0 * aura, Palette.with_alpha(Color("ff8a4a"), 0.10))

	# Kohoavat kipinät (passiivi näkyväksi)
	for i in range(4):
		var t := fmod(_time * 0.7 + i * 0.27, 1.0)
		var ex := sin((_time + i) * 3.0) * 6.0 + (i - 1.5) * 6.0
		var ey := -12.0 - t * 34.0
		draw_circle(Vector2(ex, ey), (1.0 - t) * 3.2,
			Palette.with_alpha(Palette.glow(Color("ffb347"), 1.4), (1.0 - t) * 0.7))

	# Liekkitukka: viisi kielekettä, jotka lepattavat
	for i in range(5):
		var fx := -10.0 + 5.0 * i
		var h := 13.0 + sin(_time * 8.0 + i * 1.3) * 5.0
		var lean := sin(_time * 3.0 + i) * 3.0
		var flame := PackedVector2Array([
			Vector2(fx - 4, -13), Vector2(fx + lean, -14 - h), Vector2(fx + 4, -13)])
		draw_colored_polygon(flame, Palette.glow(Color("ffcf6b"), 1.6) if i % 2 == 0 else c1)

	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))

	# Käsivarsi ja tulilyhty
	var side: Vector2 = hero.aim.rotated(-0.9)
	var grip: Vector2 = side * 16.0
	_hold(grip, c1, 18.0)
	# Lyhdyn varsi + koukku
	var lantern: Vector2 = grip + Vector2(0, 6.0)
	draw_line(grip, lantern, Palette.darker(c2, 0.6), 3.0)
	# Lyhdyn häkki
	draw_rect(Rect2(lantern + Vector2(-8, -2), Vector2(16, 18)), Palette.darker(c2, 0.6))
	draw_rect(Rect2(lantern + Vector2(-6, 0), Vector2(12, 14)), Color("1a0f08"))
	# Lyhdyn liekki
	var pulse := 0.8 + 0.2 * sin(_time * 11.0)
	var flame_center := lantern + Vector2(0, 8)
	draw_circle(flame_center, 9.0 * pulse, Palette.with_alpha(Color("ffd76d"), 0.4))
	var lantern_flame := PackedVector2Array([
		flame_center + Vector2(-4, 5), flame_center + Vector2(0, -8 * pulse),
		flame_center + Vector2(4, 5)])
	draw_colored_polygon(lantern_flame, Palette.glow(Color("ffb347"), 2.2))
	draw_circle(flame_center + Vector2(0, 2), 3.0 * pulse, Palette.glow(Color("fff0c0"), 1.8))
	# Häkin ristikot ja kahva
	draw_line(lantern + Vector2(-8, 6), lantern + Vector2(8, 6), Palette.darker(c2, 0.7), 1.5)
	draw_arc(lantern + Vector2(0, -2), 5.0, PI, TAU, 8, Palette.darker(c2, 0.6), 2.0)


func _paint_luma(c1: Color, c2: Color) -> void:
	# Pehmeä hehkuaura
	var aura := 0.9 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, 30.0 * aura, Palette.with_alpha(Color("ffe9a8"), 0.14))

	# Leijuvat valopallot kiertävät (tuki-identiteetti)
	for i in range(3):
		var ang := _time * 1.2 + TAU * i / 3.0
		var orb := Vector2(cos(ang), sin(ang) * 0.55) * 30.0 + Vector2(0, -8)
		var osize := 3.5 + sin(_time * 5.0 + i) * 1.0
		draw_circle(orb, osize * 1.8, Palette.with_alpha(Palette.GOLD, 0.2))
		draw_circle(orb, osize, Palette.glow(Palette.GOLD, 1.5))

	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4), 6.5)

	# Sädekehä pään yllä
	draw_arc(Vector2(0, -24), 11.0, 0.0, TAU, 24, Palette.glow(Palette.GOLD, 1.8), 3.0)
	draw_arc(Vector2(0, -24), 11.0, _time * 2.0, _time * 2.0 + PI, 16,
		Palette.glow(Color.WHITE, 1.4), 1.5)

	# Käsivarsi ja valosauva
	var side: Vector2 = hero.aim.rotated(0.9)
	var grip: Vector2 = side * 15.0
	var tip: Vector2 = side * 24.0 + hero.aim * 8.0
	_hold(grip, c1, 17.0)
	draw_line(grip, tip, Color("e8d9b0"), 4.0)
	# Tähtikärki hehkulla
	draw_circle(tip, 12.0, Palette.with_alpha(Palette.GOLD, 0.25))
	var star := PackedVector2Array()
	for i in range(8):
		var r := 10.0 if i % 2 == 0 else 4.0
		star.append(tip + Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 2.0) * r)
	draw_colored_polygon(star, Palette.glow(Palette.GOLD, 2.0))
	draw_circle(tip, 3.0, Palette.glow(Color.WHITE, 1.6))


func _paint_blink(c1: Color, c2: Color) -> void:
	# Jälkikuvavana (haamumainen liike)
	if _trail.size() > 3:
		var pts := PackedVector2Array()
		for i in range(mini(_trail.size(), 8)):
			pts.append(to_local(_trail[i]) + Vector2(0, -18))
		draw_polyline(pts, Palette.with_alpha(Palette.glow(c1, 1.3), 0.3), 6.0)
		draw_polyline(pts, Palette.with_alpha(c2, 0.6), 3.0)

	_body_base(Vector2.ZERO, 15.0, c1, c2)
	# Huppu
	draw_arc(Vector2(0, -8), 15.0, PI - 0.3, TAU + 0.3, 20, c2, 7.0)
	# Naamionauha
	draw_rect(Rect2(Vector2(-12, -9), Vector2(24, 7)), Palette.darker(c2, 0.65))
	# Hehkuvat kapeat silmät
	var perp: Vector2 = hero.aim.orthogonal().normalized() * 6.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -6) + perp * side + hero.aim * 3.0
		draw_line(eye - perp * 0.35, eye + perp * 0.35, Palette.glow(Color("d9c8ff"), 2.2), 2.5)

	# Kaksi hehkuvaa energiaterää
	for side in [-1.0, 1.0]:
		var base: Vector2 = hero.aim.rotated(0.7 * side) * 16.0
		var swing: float = _attack_anim * 1.7 * side
		var blade_dir: Vector2 = hero.aim.rotated(0.25 * side - swing)
		var tip: Vector2 = base + blade_dir * 24.0
		draw_line(base, tip, Palette.with_alpha(Palette.glow(Color("d9c8ff"), 1.6), 0.5), 7.0)
		draw_line(base, tip, Palette.glow(Color("ece2ff"), 2.4), 3.0)
		draw_circle(base, 3.5, c2)


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


func _paint_boulder(c1: Color, c2: Color) -> void:
	# Kivinyrkit heiluvat tähtäyksen mukana
	for side in [-1.0, 1.0]:
		var fist: Vector2 = hero.aim.rotated(0.85 * side) * 26.0
		if side > 0.0:
			fist = hero.aim.rotated(0.85 * side - _attack_anim * 1.4) * (26.0 + _attack_anim * 16.0)
		draw_circle(fist, 13.0, Palette.darker(c2, 0.6))
		draw_circle(fist, 10.5, c2)
		draw_circle(fist + Vector2(-2, -3), 3.5, Palette.with_alpha(c1, 0.7))
	_body_base(Vector2.ZERO, 26.0, c1, c2)
	# Halkeamat
	draw_line(Vector2(-8, -12), Vector2(-2, -4), Palette.darker(c2, 0.7), 2.5)
	draw_line(Vector2(6, 4), Vector2(13, 10), Palette.darker(c2, 0.7), 2.5)
	# Sammalta päälaella
	draw_arc(Vector2(0, -20), 12.0, PI + 0.5, TAU - 0.5, 12, Color("6b8f4e"), 6.0)
	_eyes(Vector2(0, -6), 8.0, 3.5)


func _paint_volt(c1: Color, c2: Color) -> void:
	# Salamaharja
	var crest := PackedVector2Array([
		Vector2(-4, -14), Vector2(4, -24), Vector2(-1, -24), Vector2(7, -36),
		Vector2(2, -25), Vector2(9, -25)])
	draw_polyline(crest, Palette.glow(c1, 1.9), 3.0)
	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4))
	# Kelat selässä rätisevät
	for side in [-1.0, 1.0]:
		var coil := Vector2(15.0 * side, 2.0)
		draw_circle(coil, 7.0, Palette.darker(c2, 0.8))
		draw_arc(coil, 7.0, 0.0, TAU, 12, c1, 2.0)
		draw_arc(coil, 4.0, _time * 8.0 * side, _time * 8.0 * side + PI, 8,
			Palette.glow(Color.WHITE, 1.4), 1.5)
	# Pieni kipinä satunnaisesti sivulla
	if fmod(_time, 0.6) < 0.12:
		var spark_dir := Vector2.RIGHT.rotated(_time * 31.0)
		draw_line(spark_dir * 18.0, spark_dir * 26.0, Palette.glow(c1, 2.2), 2.0)


func _paint_shade(c1: Color, c2: Color) -> void:
	# Savuvana
	for i in range(3):
		var puff := Vector2(-hero.aim.x * (14.0 + i * 8.0), 6.0 + sin(_time * 3.0 + i) * 3.0)
		draw_circle(puff, 6.0 - i * 1.5, Palette.with_alpha(c2, 0.25 - i * 0.06))
	_body_base(Vector2.ZERO, 16.0, c1, c2)
	# Huppu
	draw_arc(Vector2(0, -8), 14.0, PI - 0.3, TAU + 0.3, 20, c2, 8.0)
	# Kapeat hehkuvat silmät
	var perp: Vector2 = hero.aim.orthogonal().normalized() * 6.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -8) + perp * side + hero.aim * 3.0
		draw_line(eye - perp * 0.35, eye + perp * 0.35, Palette.glow(Color("d9c8ff"), 2.0), 2.5)
	# Kiekko kädessä
	var hand: Vector2 = hero.aim.rotated(-0.8 + _attack_anim * 1.2) * 18.0
	draw_arc(hand, 8.0, _time * 6.0, _time * 6.0 + TAU * 0.8, 12, Palette.glow(c1, 1.4), 2.5)


func _paint_tide(c1: Color, c2: Color) -> void:
	# Aaltoharja
	for i in range(3):
		var wave_x := -10.0 + i * 10.0
		draw_arc(Vector2(wave_x, -16), 6.0, PI, TAU, 10, Palette.glow(c1, 1.3), 3.0)
	_body_base(Vector2.ZERO, 20.0, c1, c2)
	_eyes(Vector2(0, -5), 7.0)
	# Vesikeihäs: pitkä varsi + kolmiokärki
	var reach := 30.0 + _attack_anim * 26.0
	var tip: Vector2 = hero.aim * (16.0 + reach)
	var tail: Vector2 = -hero.aim * 14.0 + hero.aim.orthogonal() * 6.0
	_hold(hero.aim * 12.0, c1, 20.0)
	draw_line(tail, tip, Color("bfeaf7"), 4.0)
	var head_perp: Vector2 = hero.aim.orthogonal() * 6.0
	var spear_head := PackedVector2Array([
		tip + hero.aim * 12.0, tip + head_perp, tip - head_perp])
	draw_colored_polygon(spear_head, Palette.glow(c1, 1.5))
	# Pisara keihään kärjestä
	if _attack_anim > 0.5:
		draw_circle(tip + hero.aim * 14.0, 3.0, Palette.with_alpha(c1, 0.8))


func _paint_scout(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 17.0, c1, c2)
	# Suojalasit
	var perp: Vector2 = hero.aim.orthogonal().normalized() * 7.0
	for side in [-1.0, 1.0]:
		var lens: Vector2 = Vector2(0, -6) + perp * side + hero.aim * 3.0
		draw_circle(lens, 5.5, Palette.darker(c2, 0.6))
		draw_circle(lens, 4.0, Palette.glow(Color("ffd76d"), 1.3))
	draw_line(Vector2(0, -6) - perp + hero.aim * 3.0, Vector2(0, -6) + perp + hero.aim * 3.0,
		Palette.darker(c2, 0.6), 2.0)
	# Vaahtopallokivääri kaksin käsin
	var barrel_start: Vector2 = hero.aim.rotated(0.5) * 12.0
	var barrel_end: Vector2 = hero.aim * (26.0 + _attack_anim * 4.0)
	_hold(barrel_start, c1, 17.0, 4.0)
	_hold(hero.aim * 18.0, c1, 17.0, 4.0)
	draw_line(barrel_start, barrel_end, c2, 5.0)
	draw_circle(barrel_end, 5.0, Palette.darker(c2, 0.7))
	draw_circle(barrel_end, 3.0, Color("f2f5ff"))


func _paint_maestro(c1: Color, c2: Color) -> void:
	# Ääniaallot sivuilta musiikin tahtiin
	for i in range(2):
		var wave_r := 20.0 + fmod(_time * 30.0 + i * 14.0, 28.0)
		var wave_alpha: float = 0.5 * (1.0 - (wave_r - 20.0) / 28.0)
		draw_arc(hero.aim * 20.0, wave_r, hero.aim.angle() - 0.7, hero.aim.angle() + 0.7, 12,
			Palette.with_alpha(c1, wave_alpha), 2.5)
	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))
	# Kuulokkeet
	draw_arc(Vector2(0, -12), 14.0, PI + 0.3, TAU - 0.3, 16, c2, 4.0)
	var head_perp: Vector2 = hero.aim.orthogonal().normalized() * 13.0
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(0, -8) + head_perp * side, 5.0, c2)
	# Ääniaaltoheitin: torvi tähtäyssuuntaan
	var horn_base: Vector2 = hero.aim.rotated(0.7) * 14.0
	var horn_tip: Vector2 = hero.aim * 24.0
	_hold(horn_base, c1, 18.0)
	draw_line(horn_base, horn_tip, Palette.darker(c2, 0.8), 5.0)
	var horn_perp: Vector2 = hero.aim.orthogonal() * 7.0
	var horn := PackedVector2Array([
		horn_tip + hero.aim * 8.0 + horn_perp, horn_tip + hero.aim * 8.0 - horn_perp,
		horn_tip - horn_perp * 0.4, horn_tip + horn_perp * 0.4])
	draw_colored_polygon(horn, c1)


func _paint_quill(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 17.0, c1, c2)
	# Huppu
	draw_arc(Vector2(0, -6), 15.0, PI + 0.4, TAU - 0.4, 20, c2, 7.0)
	_eyes(Vector2(0, -4), 6.5)
	# Jousi tähtäyksen suunnassa
	var a: float = hero.aim.angle()
	var bow_pos: Vector2 = hero.aim * 22.0
	_hold(hero.aim * 15.0, c1, 17.0)
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
