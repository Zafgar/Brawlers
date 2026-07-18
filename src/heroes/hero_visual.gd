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
		"prism":
			_paint_prism(c1, c2)
		"rift":
			_paint_rift(c1, c2)
		"titan":
			_paint_titan(c1, c2)
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


func _res_color(t: String) -> Color:
	match t:
		"mana":
			return Color("5b8cff")
		"energy":
			return Color("4ad4ff")
		"rage":
			return Color("ff6b3d")
	return Color.WHITE


func _draw_status(bob: float) -> void:
	var top := Vector2(0, -52.0 - bob)
	# Kenttäbuffin aura sankarin ympärillä
	if hero.blue_buff > 0.0 or hero.red_buff > 0.0:
		var bcol: Color = Color("6aa0ff")
		if hero.blue_buff > 0.0 and hero.red_buff > 0.0:
			bcol = Color("c58aff")
		elif hero.red_buff > 0.0:
			bcol = Color("ff7a6a")
		var ap: float = 0.35 + 0.25 * sin(_time * 5.0)
		draw_arc(Vector2(0, -8), hero.radius + 15.0, 0.0, TAU, 40, Palette.with_alpha(bcol, ap), 3.0)
	# Pieni kestopalkki pään yläpuolella
	var w := 46.0
	var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
	draw_rect(Rect2(top + Vector2(-w / 2.0 - 1.0, -1.0), Vector2(w + 2.0, 7.0)), Color(0, 0, 0, 0.45))
	var hp_color: Color = Palette.GOOD if frac > 0.35 else Palette.BAD
	draw_rect(Rect2(top + Vector2(-w / 2.0, 0.0), Vector2(w * frac, 5.0)), hp_color)
	# Resurssipalkki (mana/energy/rage) HP-palkin alla, jos sankarilla on resurssi.
	if hero.res_type != "":
		var rfrac: float = clampf(hero.res / hero.res_max, 0.0, 1.0)
		draw_rect(Rect2(top + Vector2(-w / 2.0 - 1.0, 6.0), Vector2(w + 2.0, 5.0)), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(top + Vector2(-w / 2.0, 7.0), Vector2(w * rfrac, 3.0)), _res_color(hero.res_type))
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

	# Void-pinot (Riftin) pieninä timantteina HP-palkin yllä
	if hero.void_stacks > 0:
		var vcol := Color("b48aff")
		var n: int = hero.void_stacks
		for i in range(n):
			var px: float = -((n - 1) * 7.0) / 2.0 + i * 7.0
			var pc: Vector2 = top + Vector2(px, -13.0)
			draw_colored_polygon(PackedVector2Array([
				pc + Vector2(0, -3.5), pc + Vector2(3, 0), pc + Vector2(0, 3.5), pc + Vector2(-3, 0)]),
				Palette.glow(vcol, 1.6))

	# Ajanpysäytys: void-jäätymisverho sankarin päälle
	if hero.frozen > 0.0:
		draw_circle(Vector2(0, -8), hero.radius + 5.0, Palette.with_alpha(Color("6a4a9c"), 0.35))
		draw_arc(Vector2(0, -8), hero.radius + 9.0, 0.0, TAU, 26,
			Palette.with_alpha(Palette.glow(Color("b48aff"), 1.4), 0.55), 2.5)

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


func _paint_prism(c1: Color, c2: Color) -> void:
	# Hehkuaura
	var aura := 0.9 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, 28.0 * aura, Palette.with_alpha(c1, 0.12))

	# Kolme kiertävää valopistettä (prisman hajottama spektri)
	for i in range(3):
		var ang := _time * 1.4 + TAU * i / 3.0
		var orb := Vector2(cos(ang), sin(ang) * 0.55) * 28.0 + Vector2(0, -6)
		draw_circle(orb, 3.2, Palette.glow(c1, 1.5))

	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4), 6.5)

	# Kädessä pyörivä prismakristalli, joka hehkuu tähtäyssuuntaan
	var side: Vector2 = hero.aim.rotated(0.8)
	var grip: Vector2 = side * 15.0
	var crystal: Vector2 = side * 24.0 + hero.aim * 6.0
	_hold(grip, c1, 17.0)
	var spin := _time * 2.5
	var tri := PackedVector2Array()
	for i in range(3):
		tri.append(crystal + Vector2.RIGHT.rotated(spin + TAU * i / 3.0) * 9.0)
	draw_colored_polygon(tri, Palette.glow(c1, 1.6))
	draw_polyline(tri + PackedVector2Array([tri[0]]), Palette.glow(Color.WHITE, 1.4), 2.0)
	draw_circle(crystal, 3.0, Palette.glow(Color.WHITE, 1.6))
	draw_circle(crystal + hero.aim * 8.0, 4.0, Palette.with_alpha(Palette.glow(c1, 1.6), 0.7))


func _paint_rift(c1: Color, c2: Color) -> void:
	# Jälkikuvavana
	if _trail.size() > 3:
		var pts := PackedVector2Array()
		for i in range(mini(_trail.size(), 7)):
			pts.append(to_local(_trail[i]) + Vector2(0, -16))
		draw_polyline(pts, Palette.with_alpha(Palette.glow(c1, 1.2), 0.25), 5.0)

	# Tyhjyyshiukkaset kiertävät
	for i in range(4):
		var ang := _time * 2.2 + TAU * i / 4.0
		var wisp := Vector2(cos(ang), sin(ang) * 0.6) * 24.0 + Vector2(0, -6)
		draw_circle(wisp, 2.6, Palette.glow(c1, 1.5))

	_body_base(Vector2.ZERO, 16.0, c1, c2)
	# Huppu (tumma kolmio pään päällä)
	var hood := PackedVector2Array([Vector2(-11, -8), Vector2(0, -24), Vector2(11, -8)])
	draw_colored_polygon(hood, Palette.darker(c2, 0.6))
	_eyes(Vector2(0, -6), 6.0)

	# Tyhjyyden tikari tähtäyssuuntaan
	var a: float = hero.aim.angle() - _attack_anim * 0.8
	var hilt: Vector2 = Vector2.RIGHT.rotated(a) * 16.0
	var tip: Vector2 = Vector2.RIGHT.rotated(a) * 34.0
	_hold(hilt, c1, 16.0)
	draw_line(hilt, tip, Palette.glow(c1, 1.5), 4.0)
	draw_line(hilt, tip, Palette.glow(Color.WHITE, 1.3), 1.5)
	draw_circle(tip, 3.0, Palette.glow(c1, 1.7))


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
	# Ajelehtivat lehdet/itiöt
	for i in range(3):
		var la := _time * 0.8 + TAU * i / 3.0
		var lp := Vector2(cos(la), sin(la) * 0.6) * 32.0 + Vector2(0, -6)
		draw_colored_polygon(PackedVector2Array([
			lp + Vector2(0, -4), lp + Vector2(3, 0), lp + Vector2(0, 4), lp + Vector2(-3, 0)]),
			Palette.with_alpha(Color("7ed957"), 0.5))

	# Piikkikruunu
	for i in range(3):
		var fx := -10.0 + 10.0 * i
		var h := 26.0 + sin(_time * 4.0 + i) * 2.0
		var thorn := PackedVector2Array([
			Vector2(fx - 4, -16), Vector2(fx, -h), Vector2(fx + 4, -16)])
		draw_colored_polygon(thorn, c2)

	# Puumainen runko
	_body_base(Vector2.ZERO, 21.0, c1, c2)
	# Kaarnasaumat
	draw_line(Vector2(-6, -6), Vector2(-3, 10), Palette.darker(c2, 0.7), 2.0)
	draw_line(Vector2(7, -4), Vector2(4, 12), Palette.darker(c2, 0.7), 2.0)

	# Lehtiolkapäät
	for side in [-1.0, 1.0]:
		var leaf := PackedVector2Array([
			Vector2(14 * side, -8), Vector2(27 * side, -17), Vector2(24 * side, -4),
			Vector2(20 * side, -2)])
		draw_colored_polygon(leaf, Palette.darker(c1, 0.8))
		draw_line(Vector2(15 * side, -6), Vector2(25 * side, -14), Palette.darker(c2, 0.7), 1.5)
	_eyes(Vector2(0, -5), 7.5)

	# Käsivarsi ja köynnösruoska (aaltoilee tähtäyksen suuntaan)
	_hold(hero.aim * 12.0, c1, 21.0)
	var pts := PackedVector2Array()
	var reach := 30.0 + _attack_anim * 40.0
	for i in range(10):
		var t := i / 9.0
		var wave: Vector2 = hero.aim.orthogonal() * sin(t * 6.0 + _time * 5.0) * 6.0 * t
		pts.append(hero.aim * (10.0 + reach * t) + wave)
	draw_polyline(pts, Palette.darker(c1, 0.7), 5.0)
	draw_polyline(pts, c1, 2.5)
	# Piikit ruoskan varrella
	for i in range(2, pts.size(), 2):
		var seg: Vector2 = (pts[i] - pts[i - 1]).orthogonal().normalized() * 4.0
		draw_line(pts[i], pts[i] + seg, c2, 2.0)
	draw_circle(pts[pts.size() - 1], 5.0, c2)


func _paint_boulder(c1: Color, c2: Color) -> void:
	# Kivinyrkit heiluvat tähtäyksen mukana
	for side in [-1.0, 1.0]:
		var fist: Vector2 = hero.aim.rotated(0.85 * side) * 26.0
		if side > 0.0:
			fist = hero.aim.rotated(0.85 * side - _attack_anim * 1.5) * (26.0 + _attack_anim * 18.0)
		_limb(fist * 0.55, fist, c1, 6.0)
		draw_circle(fist, 13.0, Palette.darker(c2, 0.6))
		draw_circle(fist, 10.5, c2)
		draw_line(fist + Vector2(-6, -4), fist + Vector2(2, 3), Palette.darker(c2, 0.75), 1.5)
		draw_circle(fist + Vector2(-2, -3), 3.5, Palette.with_alpha(c1, 0.7))

	# Kivinen runko
	_body_base(Vector2.ZERO, 26.0, c1, c2)
	# Kivisärmät
	var facets := PackedVector2Array([
		Vector2(-18, -6), Vector2(-4, -20), Vector2(13, -13),
		Vector2(20, 5), Vector2(6, 18), Vector2(-15, 13)])
	draw_polyline(facets + PackedVector2Array([facets[0]]), Palette.darker(c2, 0.65), 2.0)
	# Halkeamat
	draw_line(Vector2(-9, -13), Vector2(-2, -2), Palette.darker(c2, 0.75), 2.5)
	draw_line(Vector2(-2, -2), Vector2(7, 7), Palette.darker(c2, 0.75), 2.0)
	draw_line(Vector2(7, 7), Vector2(14, 11), Palette.darker(c2, 0.75), 2.0)
	# Kiiltävät mineraalit
	draw_circle(Vector2(9, -9), 3.0, Palette.with_alpha(Color("6fa8c0"), 0.8))
	draw_circle(Vector2(-11, 6), 2.5, Palette.with_alpha(Color("8fd0e0"), 0.7))
	# Sammal päällä ja hartioilla
	draw_arc(Vector2(0, -20), 12.0, PI + 0.5, TAU - 0.5, 12, Color("6b8f4e"), 6.0)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(18.0 * side, -12), 5.0, Palette.with_alpha(Color("6b8f4e"), 0.8))
	_eyes(Vector2(0, -6), 8.0, 3.5)


func _paint_titan(c1: Color, c2: Color) -> void:
	# Berserkissä hehkuva raivo-aura (punainen buffi ultin ajaksi).
	if hero.red_buff > 0.0:
		for i in range(3):
			var ra := _time * 9.0 + TAU * i / 3.0
			draw_arc(Vector2.ZERO, 30.0 + sin(_time * 14.0 + i) * 3.0, ra, ra + 0.7, 5,
				Palette.with_alpha(Palette.glow(Color("ff7a3a"), 1.6), 0.55), 2.5)

	# Isot rautakourat (tarttuvat kädet) heiluvat tähtäyksen mukana.
	for side in [-1.0, 1.0]:
		var grip: Vector2 = hero.aim.rotated(0.9 * side) * 30.0
		if side > 0.0:
			grip = hero.aim.rotated(0.9 * side - _attack_anim * 1.6) * (30.0 + _attack_anim * 22.0)
		_limb(grip * 0.5, grip, c1, 7.0)
		# Kourarauta: tumma kämmen + sormet
		draw_circle(grip, 14.0, Palette.darker(c2, 0.6))
		draw_circle(grip, 11.0, Palette.darker(c1, 0.2))
		var kperp: Vector2 = hero.aim.orthogonal().normalized()
		for f in [-1.0, 0.0, 1.0]:
			var tip: Vector2 = grip + hero.aim * 9.0 + kperp * (f * 6.0)
			draw_line(grip, tip, Palette.darker(c2, 0.7), 3.0)
		draw_circle(grip + Vector2(-3, -4), 3.0, Palette.with_alpha(Color.WHITE, 0.5))

	# Massiivinen panssariruho, leveät hartiat.
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(20.0 * side, -14.0), 10.0, Palette.darker(c2, 0.55))
		draw_circle(Vector2(20.0 * side, -14.0), 7.5, c2)
	_body_base(Vector2.ZERO, 27.0, c1, c2)
	# Panssarilevyt ja niitit
	draw_line(Vector2(-20, -4), Vector2(20, -4), Palette.darker(c2, 0.6), 3.0)
	draw_line(Vector2(-16, 8), Vector2(16, 8), Palette.darker(c2, 0.6), 2.5)
	for nx in [-14.0, 0.0, 14.0]:
		draw_circle(Vector2(nx, -12.0), 2.2, Palette.with_alpha(Color("d9cbb0"), 0.7))
	# Rautainen leukasuojus
	draw_rect(Rect2(Vector2(-9, 2), Vector2(18, 7)), Palette.darker(c2, 0.7))
	_eyes(Vector2(0, -8), 8.5, 3.8)
	# Vihaiset kulmakarvat
	for side in [-1.0, 1.0]:
		var bx := 5.0 * side
		draw_line(Vector2(bx - 3.5 * side, -14.0), Vector2(bx + 3.5 * side, -11.5),
			Palette.darker(c2, 0.75), 2.5)


func _paint_volt(c1: Color, c2: Color) -> void:
	# Kipinöivä sähköaura
	for i in range(3):
		var sa := _time * 6.0 + TAU * i / 3.0
		var sr := 22.0 + sin(_time * 12.0 + i * 2.0) * 4.0
		draw_arc(Vector2.ZERO, sr, sa, sa + 0.6, 4,
			Palette.with_alpha(Palette.glow(c1, 1.6), 0.5), 1.5)

	# Salamaharja
	var crest := PackedVector2Array([
		Vector2(-4, -14), Vector2(4, -24), Vector2(-1, -24), Vector2(7, -38),
		Vector2(2, -25), Vector2(9, -25)])
	draw_polyline(crest, Palette.glow(c1, 2.0), 3.0)

	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4))

	# Kelat selässä, joiden välillä hyppii kaari
	var coils := []
	for side in [-1.0, 1.0]:
		var coil := Vector2(16.0 * side, 2.0)
		coils.append(coil)
		draw_circle(coil, 7.5, Palette.darker(c2, 0.8))
		draw_arc(coil, 7.5, 0.0, TAU, 12, c1, 2.0)
		draw_arc(coil, 4.0, _time * 8.0 * side, _time * 8.0 * side + PI, 8,
			Palette.glow(Color.WHITE, 1.4), 1.5)
		draw_circle(coil, 2.5, Palette.glow(Color.WHITE, 1.5))
	# Kelojen välinen rätisevä kaari
	var arc_pts := PackedVector2Array()
	for seg in range(5):
		var t := seg / 4.0
		var mid: Vector2 = coils[0].lerp(coils[1], t)
		mid.y += sin(_time * 40.0 + seg * 3.0) * 4.0 - 6.0
		arc_pts.append(mid)
	draw_polyline(arc_pts, Palette.with_alpha(Palette.glow(Color.WHITE, 1.8), 0.7), 1.5)

	# Kädestä lähtevä kipinä tähtäyssuuntaan
	var spark_pts := PackedVector2Array([hero.aim * 12.0])
	for seg in range(1, 4):
		var t := seg / 3.0
		var jit: Vector2 = hero.aim.orthogonal() * sin(_time * 35.0 + seg * 4.0) * 4.0
		spark_pts.append(hero.aim * (12.0 + t * 16.0) + jit)
	draw_polyline(spark_pts, Palette.glow(c1, 2.0), 2.0)


func _paint_shade(c1: Color, c2: Color) -> void:
	# Savuvanat kiertävät (haihtuva olemus)
	for i in range(4):
		var sa := _time * 1.5 + TAU * i / 4.0
		var sp := Vector2(cos(sa), sin(sa) * 0.6) * (18.0 + sin(_time * 3.0 + i) * 4.0) + Vector2(0, -6)
		draw_circle(sp, 5.0 - i * 0.6, Palette.with_alpha(c2, 0.2))

	_body_base(Vector2.ZERO, 16.0, c1, c2)
	# Viitan kaulus
	draw_arc(Vector2(0, -2), 17.0, PI - 0.5, TAU + 0.5, 18, Palette.darker(c2, 0.6), 5.0)
	# Huppu
	draw_arc(Vector2(0, -8), 14.0, PI - 0.3, TAU + 0.3, 20, c2, 8.0)
	# Kapeat hehkuvat silmät
	var perp: Vector2 = hero.aim.orthogonal().normalized() * 6.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -8) + perp * side + hero.aim * 3.0
		draw_line(eye - perp * 0.35, eye + perp * 0.35, Palette.glow(Color("d9c8ff"), 2.0), 2.5)

	# Käsivarsi ja pyörivä varjokiekko kädessä
	var hand: Vector2 = hero.aim.rotated(-0.7 + _attack_anim * 1.4) * 18.0
	_hold(hand * 0.6, c1, 16.0, 4.0)
	var spin := _time * 8.0
	var disc := PackedVector2Array()
	for i in range(8):
		var rr: float = 8.0 if i % 2 == 0 else 3.5
		disc.append(hand + Vector2.RIGHT.rotated(spin + TAU * i / 8.0) * rr)
	draw_colored_polygon(disc, Palette.glow(c1, 1.3))
	draw_circle(hand, 2.5, Palette.darker(c2, 0.6))


func _paint_tide(c1: Color, c2: Color) -> void:
	# Leijuvat vesipisarat kiertävät
	for i in range(3):
		var da := _time * 1.6 + TAU * i / 3.0
		var dp := Vector2(cos(da), sin(da) * 0.6) * 30.0 + Vector2(0, -8)
		draw_circle(dp, 3.0, Palette.with_alpha(Palette.glow(c1, 1.3), 0.6))

	# Aaltoharja
	for i in range(3):
		var wave_x := -10.0 + i * 10.0
		var wh := 6.0 + sin(_time * 5.0 + i) * 1.5
		draw_arc(Vector2(wave_x, -16), wh, PI, TAU, 10, Palette.glow(c1, 1.3), 3.0)

	_body_base(Vector2.ZERO, 20.0, c1, c2)
	# Märkä kiilto
	draw_circle(Vector2(-6, -8), 5.0, Palette.with_alpha(Color.WHITE, 0.28))
	_eyes(Vector2(0, -5), 7.0)

	# Käsivarsi ja vesikeihäs (piikkikärki + väkäset)
	var reach := 30.0 + _attack_anim * 28.0
	var tip: Vector2 = hero.aim * (16.0 + reach)
	var tail: Vector2 = -hero.aim * 14.0 + hero.aim.orthogonal() * 6.0
	_hold(hero.aim * 12.0, c1, 20.0)
	draw_line(tail, tip, Color("bfeaf7"), 4.0)
	var head_perp: Vector2 = hero.aim.orthogonal() * 6.0
	var spear_head := PackedVector2Array([
		tip + hero.aim * 12.0, tip + head_perp, tip - head_perp])
	draw_colored_polygon(spear_head, Palette.glow(c1, 1.5))
	# Väkäset
	draw_line(tip, tip - hero.aim * 6.0 + head_perp * 1.4, Palette.glow(c1, 1.3), 2.0)
	draw_line(tip, tip - hero.aim * 6.0 - head_perp * 1.4, Palette.glow(c1, 1.3), 2.0)
	# Pisara kärjestä iskiessä
	if _attack_anim > 0.5:
		draw_circle(tip + hero.aim * 14.0, 3.0, Palette.with_alpha(c1, 0.8))


func _paint_scout(c1: Color, c2: Color) -> void:
	_body_base(Vector2.ZERO, 17.0, c1, c2)

	# Lippalakki lipan kanssa (osoittaa tähtäyssuuntaan)
	draw_arc(Vector2(0, -8), 15.0, PI + 0.2, TAU - 0.2, 18, Palette.darker(c2, 0.7), 6.0)
	var brim_perp: Vector2 = hero.aim.orthogonal() * 8.0
	var brim := PackedVector2Array([
		hero.aim * 10.0 + brim_perp, hero.aim * 20.0, hero.aim * 10.0 - brim_perp])
	draw_colored_polygon(brim, Palette.darker(c2, 0.6))

	# Suojalasit hehkuvin linssein
	var perp: Vector2 = hero.aim.orthogonal().normalized() * 7.0
	draw_line(Vector2(0, -6) - perp + hero.aim * 3.0, Vector2(0, -6) + perp + hero.aim * 3.0,
		Palette.darker(c2, 0.6), 2.0)
	for side in [-1.0, 1.0]:
		var lens: Vector2 = Vector2(0, -6) + perp * side + hero.aim * 3.0
		draw_circle(lens, 5.5, Palette.darker(c2, 0.6))
		draw_circle(lens, 4.0, Palette.glow(Color("ffd76d"), 1.3))
		draw_circle(lens + Vector2(-1.2, -1.2), 1.5, Color(1, 1, 1, 0.7))

	# Pallovarasto selässä
	for i in range(3):
		draw_circle(Vector2(-16.0 + i * 4.0, -2.0 + i * 3.0), 3.5,
			Palette.with_alpha(Color("f2f5ff"), 0.85))

	# Vaahtopallokivääri kaksin käsin
	var barrel_start: Vector2 = hero.aim.rotated(0.5) * 12.0
	var barrel_end: Vector2 = hero.aim * (28.0 + _attack_anim * 5.0)
	_hold(barrel_start, c1, 17.0, 4.0)
	_hold(hero.aim * 18.0, c1, 17.0, 4.0)
	draw_line(barrel_start, barrel_end, c2, 5.0)
	# Suppilo ja ladattu vaahtopallo
	draw_circle(barrel_end, 5.5, Palette.darker(c2, 0.7))
	draw_circle(barrel_end + hero.aim * 2.0, 3.5, Color("f2f5ff"))
	# Pallosäiliö kiväärin päällä
	draw_circle(hero.aim * 16.0 + hero.aim.orthogonal() * 6.0, 4.0,
		Palette.with_alpha(Color("f2f5ff"), 0.7))


func _paint_maestro(c1: Color, c2: Color) -> void:
	# Leijuvat nuotit kiertävät
	for i in range(3):
		var na := _time * 1.4 + TAU * i / 3.0
		var np := Vector2(cos(na), sin(na) * 0.5) * 32.0 + Vector2(0, -10)
		np.y += sin(_time * 5.0 + i * 2.0) * 2.0
		draw_circle(np, 3.5, Palette.glow(c1, 1.3))
		draw_line(np + Vector2(3, 0), np + Vector2(3, -10), Palette.glow(c1, 1.3), 1.5)
		draw_line(np + Vector2(3, -10), np + Vector2(7, -7), Palette.glow(c1, 1.3), 1.5)

	# Ääniaallot torven suunnasta
	for i in range(2):
		var wave_r := 20.0 + fmod(_time * 30.0 + i * 14.0, 28.0)
		var wave_alpha: float = 0.5 * (1.0 - (wave_r - 20.0) / 28.0)
		draw_arc(hero.aim * 20.0, wave_r, hero.aim.angle() - 0.7, hero.aim.angle() + 0.7, 12,
			Palette.with_alpha(Palette.glow(c1, 1.4), wave_alpha), 2.5)

	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))
	# Kuulokkeet
	draw_arc(Vector2(0, -12), 14.0, PI + 0.3, TAU - 0.3, 16, c2, 4.0)
	var head_perp: Vector2 = hero.aim.orthogonal().normalized() * 13.0
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(0, -8) + head_perp * side, 5.5, c2)
		draw_circle(Vector2(0, -8) + head_perp * side, 2.5, Palette.glow(c1, 1.3))

	# Käsivarsi ja ääniaaltotorvi tähtäyssuuntaan
	var horn_base: Vector2 = hero.aim.rotated(0.6) * 14.0
	var horn_tip: Vector2 = hero.aim * 26.0
	_hold(horn_base, c1, 18.0)
	draw_line(horn_base, horn_tip, Palette.darker(c2, 0.8), 5.0)
	var horn_perp: Vector2 = hero.aim.orthogonal() * 8.0
	var horn := PackedVector2Array([
		horn_tip + hero.aim * 9.0 + horn_perp, horn_tip + hero.aim * 9.0 - horn_perp,
		horn_tip - horn_perp * 0.4, horn_tip + horn_perp * 0.4])
	draw_colored_polygon(horn, c1)
	draw_circle(horn_tip + hero.aim * 8.0, 2.5, Palette.glow(Color.WHITE, 1.4))


func _paint_quill(c1: Color, c2: Color) -> void:
	# Nuoliviini selässä (rungon takana)
	for i in range(3):
		var qx := -16.0 + i * 4.0
		draw_line(Vector2(qx, 8), Vector2(qx - 6.0, -18.0), Palette.darker(c2, 0.7), 2.5)
		# Sulat
		draw_line(Vector2(qx - 6.0, -18.0), Vector2(qx - 9.0, -15.0), c1, 1.5)
		draw_line(Vector2(qx - 6.0, -18.0), Vector2(qx - 3.0, -15.0), c1, 1.5)
	draw_arc(Vector2(-8, -2), 8.0, PI * 0.3, PI * 1.2, 10, Palette.darker(c2, 0.75), 3.0)

	_body_base(Vector2.ZERO, 17.0, c1, c2)
	# Huppu
	draw_arc(Vector2(0, -6), 15.0, PI + 0.4, TAU - 0.4, 20, c2, 7.0)
	_eyes(Vector2(0, -4), 6.5)

	# Käsivarsi ja recurve-jousi tähtäyksen suunnassa
	var a: float = hero.aim.angle()
	var bow_pos: Vector2 = hero.aim * 22.0
	_hold(hero.aim * 14.0, c1, 17.0)

	# Latausaura kasvaa aux:n mukaan
	if aux > 0.05:
		draw_circle(bow_pos + hero.aim * 12.0, 4.0 + aux * 9.0,
			Palette.with_alpha(Palette.glow(Palette.GOLD, 1.0 + aux), 0.25 + aux * 0.35))

	# Jousen sanka + recurve-kärjet
	draw_arc(bow_pos, 15.0, a - 1.25, a + 1.25, 18, Color("6b4f2a"), 5.0)
	draw_arc(bow_pos, 15.0, a - 1.25, a + 1.25, 18, Color("a5824a"), 3.0)
	var top: Vector2 = bow_pos + Vector2.RIGHT.rotated(a - 1.25) * 15.0
	var bottom: Vector2 = bow_pos + Vector2.RIGHT.rotated(a + 1.25) * 15.0
	draw_line(top, top + hero.aim.rotated(-0.5) * 5.0, Color("6b4f2a"), 4.0)
	draw_line(bottom, bottom + hero.aim.rotated(0.5) * 5.0, Color("6b4f2a"), 4.0)
	# Jänne, jota lataus vetää taakse
	var pull: Vector2 = bow_pos - hero.aim * (4.0 + aux * 11.0)
	draw_line(top, pull, Color("e8e2d0"), 2.0)
	draw_line(bottom, pull, Color("e8e2d0"), 2.0)
	if aux > 0.05:
		# Ladattu nuoli hehkuu voimakkaammin täydessä latauksessa
		var glow_color: Color = Palette.glow(c1, 1.0 + aux * 1.5)
		draw_line(pull, bow_pos + hero.aim * 18.0, glow_color, 3.0)
		var arrow_tip: Vector2 = bow_pos + hero.aim * 18.0
		draw_colored_polygon(PackedVector2Array([
			arrow_tip + hero.aim * 5.0,
			arrow_tip + hero.aim.orthogonal() * 3.0,
			arrow_tip - hero.aim.orthogonal() * 3.0]), glow_color)
		if aux >= 1.0:
			draw_circle(arrow_tip, 5.0 + sin(_time * 12.0) * 1.5, Palette.glow(Palette.GOLD, 2.0))
