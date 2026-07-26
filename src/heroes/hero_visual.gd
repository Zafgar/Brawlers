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
var _cast_anim := 0.0
var _cast_slot := ""
var _draw_scale := Vector2.ONE
var _trail: Array = []            # Blinkin huivia yms. varten
var _was_world_visible := true


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	_time += delta
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_attack_anim = maxf(_attack_anim - delta * 4.0, 0.0)
	_cast_anim = maxf(_cast_anim - delta * 3.2, 0.0)
	var world_visible := true
	if hero != null and hero.arena != null and hero.arena.has_method("visual_position_active"):
		# Reilu marginaali säilyttää kantamarenkaat, kilvet ja suuret siluetit
		# täysin näkyvinä jo ennen kuin niiden keskipiste saapuu ruudulle.
		world_visible = hero.arena.visual_position_active(hero.global_position, 520.0)
	if not world_visible:
		visible = false
		_trail.clear()
		_was_world_visible = false
		return
	visible = true
	if not _was_world_visible:
		_trail.clear()
	_was_world_visible = true
	if hero != null:
		_trail.push_front(hero.global_position)
		if _trail.size() > 10:
			_trail.pop_back()
	# Häive (varjoviitta): koko visuaali haalenee ~0.3 alphaan; palautuu heti
	# häiveen päättyessä. Sama haaleus riittää v1:ssä myös vihollisruuduille.
	modulate.a = 0.3 if (hero != null and hero.stealth_timer > 0.0) else 1.0
	queue_redraw()


func flash() -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	_flash = 1.0


func attack_swing() -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	_attack_anim = 1.0
	squash(1.15, 0.88)


func cast_ability(slot: String) -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	_cast_slot = slot
	_cast_anim = 1.0
	match slot:
		"ult":
			squash(1.3, 0.78)
		"a2":
			squash(0.9, 1.14)
		_:
			squash(1.18, 0.86)


func squash(x: float, y: float) -> void:
	if Game.simulating and not Game.sim_visuals:
		return
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
		"hush":
			_paint_hush(c1, c2)
		"obsidian":
			_paint_obsidian(c1, c2)
		"lance":
			_paint_lance(c1, c2)
		"salvo":
			_paint_salvo(c1, c2)
		"kaira":
			_paint_kaira(c1, c2)
		"vesper":
			_paint_vesper(c1, c2)
		"myria":
			_paint_myria(c1, c2)
		"torq":
			_paint_torq(c1, c2)
		_:
			_paint_generic(c1, c2)

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 26.0, Color(1, 1, 1, _flash * 0.65))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_ultimate_state(bob)

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
		# Kykyvalmiuspallerot piirretään _draw_ability_pips():ssä (yksi rivi).

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

	# Lipas (patruunat) resurssipalkin alla, jos sankarilla on lipasjärjestelmä.
	if hero.ammo >= 0 and hero.ammo_max > 0:
		var ay := 12.0
		draw_rect(Rect2(top + Vector2(-w / 2.0 - 1.0, ay - 1.0), Vector2(w + 2.0, 4.0)), Color(0, 0, 0, 0.45))
		if hero.reloading:
			# Latautuu: pulssaava amber-palkki telegraafina.
			var rp: float = 0.35 + 0.65 * absf(sin(_time * 6.0))
			draw_rect(Rect2(top + Vector2(-w / 2.0, ay), Vector2(w * rp, 2.0)),
				Palette.glow(Color("ffb24a"), 1.3))
		else:
			var afrac: float = clampf(float(hero.ammo) / float(hero.ammo_max), 0.0, 1.0)
			draw_rect(Rect2(top + Vector2(-w / 2.0, ay), Vector2(w * afrac, 2.0)), Color("d9cbb0"))
			# Segmenttiviivat: pienelle latausmäärälle (esim. Tiden 3 syöksyä) yksi
			# viiva per lataus; isolle lippaalle tasainen palkki ilman viivoja.
			if hero.ammo_max <= 8:
				for s in range(1, hero.ammo_max):
					var sx: float = -w / 2.0 + w * float(s) / float(hero.ammo_max)
					draw_line(top + Vector2(sx, ay - 1.0), top + Vector2(sx, ay + 3.0), Color(0, 0, 0, 0.4), 1.0)
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
		if hero.guard_radius > 1.0:
			# Leveä kilpivalli (esim. Bastionin kanavoitu kilpi): kiinteä
			# läpikuultava este eteen, joka torjuu vihollisammukset.
			_draw_shield_wall(a, hero.guard_radius, half)
		else:
			draw_arc(Vector2(0, -14), hero.radius + 13.0, a - half, a + half, 24,
				Palette.glow(Palette.SHIELD, 1.4), 5.0)

	# Häive: pehmeä väreilevä rengas kertoo kantajalle häiveen keston.
	if hero.stealth_timer > 0.0:
		var st_a: float = 0.3 + 0.2 * sin(_time * 6.0)
		draw_arc(Vector2(0, -8), hero.radius + 12.0 + 2.0 * sin(_time * 3.5),
			0.0, TAU, 32, Palette.with_alpha(Color("b48aff"), st_a), 2.5)

	# Baron-artefaktin kantaja: pieni kultatimantti sankarin yllä — myös
	# viholliset näkevät kuka kantaa legendaarista palkintoa.
	if not hero.is_unit and hero.legendary_artifact:
		var art_c := top + Vector2(0, -26.0)
		var art_pulse := 1.0 + 0.18 * sin(_time * 5.0)
		draw_circle(art_c, 7.5 * art_pulse, Palette.with_alpha(Palette.GOLD, 0.22))
		draw_colored_polygon(PackedVector2Array([
			art_c + Vector2(0, -6) * art_pulse, art_c + Vector2(4.5, 0) * art_pulse,
			art_c + Vector2(0, 6) * art_pulse, art_c + Vector2(-4.5, 0) * art_pulse]),
			Palette.glow(Palette.GOLD, 1.5))

	if hero.mark_timer > 0.0:
		# Scoutin merkki: pulssaava kultatimantti pään yläpuolella.
		var mark_center := top + Vector2(0, -16.0)
		var mark_pulse := 1.0 + 0.2 * sin(_time * 8.0)
		var mark := PackedVector2Array([
			mark_center + Vector2(0, -7) * mark_pulse, mark_center + Vector2(6, 0) * mark_pulse,
			mark_center + Vector2(0, 7) * mark_pulse, mark_center + Vector2(-6, 0) * mark_pulse])
		draw_colored_polygon(mark, Palette.glow(Palette.GOLD, 1.7))

	# Void-pinot (Riftin) HP-palkin yllä: 1–4 pinoa pieninä timantteina, mutta
	# täydet 5 näkyvät yhtenä hehkuvana void-merkkinä (valmis räjäytettäväksi).
	if hero.void_stacks > 0:
		var vcol := Color("b48aff")
		var n: int = hero.void_stacks
		if n >= 5:
			var mc: Vector2 = top + Vector2(0, -15.0)
			var pulse: float = 1.0 + 0.25 * sin(_time * 9.0)
			# Hehkukehä
			draw_circle(mc, 9.0 * pulse, Palette.with_alpha(Palette.glow(vcol, 1.6), 0.35))
			# Nelisakarainen void-tähti (kaksi timanttia ristissä)
			for rot in [0.0, PI * 0.25]:
				var pts := PackedVector2Array()
				for k in range(4):
					var a: float = rot + k * PI * 0.5
					pts.append(mc + Vector2(cos(a), sin(a)) * 7.0 * pulse)
				draw_colored_polygon(pts, Palette.glow(vcol, 1.7))
			draw_circle(mc, 2.2, Palette.glow(Color.WHITE, 1.4))
		else:
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
		var clock := Vector2(0, -52.0 - bob)
		draw_circle(clock, 9.0, Palette.with_alpha(Color("201536"), 0.88))
		draw_arc(clock, 9.0, 0.0, TAU, 24, Palette.glow(Color("c9a8ff"), 1.55), 2.5)
		draw_line(clock, clock + Vector2(0, -5), Color.WHITE, 2.0)
		draw_line(clock, clock + Vector2(4, 2), Color.WHITE, 2.0)

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
	if hero.silence_timer > 0.0:
		var sc := Vector2(0, -50.0 - bob)
		draw_arc(Vector2(0, -9), hero.radius + 11.0, PI * 0.12, PI * 0.88, 20,
			Palette.with_alpha(Palette.glow(Color("c7a8ff"), 1.45), 0.72), 3.5)
		draw_circle(sc, 8.0, Palette.with_alpha(Color("3b235d"), 0.9))
		draw_line(sc + Vector2(-6, -6), sc + Vector2(6, 6), Palette.glow(Color("f2ddff"), 1.4), 2.5)
		draw_line(sc + Vector2(-6, 6), sc + Vector2(6, -6), Palette.glow(Color("f2ddff"), 1.4), 2.5)


## Pitkien muodonmuutos-/latausulttien tila seuraa sankaria. Tämä on tärkeämpi
## kuin yksittäinen aloituspurske: vastustaja näkee koko ajan milloin uhka on päällä.
func _draw_ultimate_state(bob: float) -> void:
	var center := Vector2(0, -14.0 - bob)
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	match hero.hero_id:
		"boulder":
			if float(hero.get("_rolling")) > 0.0:
				draw_circle(center, hero.radius + 11.0, Palette.with_alpha(Color("77828d"), 0.42))
				for i in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 4.0)
					draw_line(center + ray * (hero.radius - 4.0), center + ray * (hero.radius + 13.0),
						Palette.glow(Color("d7c9a4"), 1.25), 5.0)
		"obsidian":
			var charging := float(hero.get("_charging"))
			if charging > 0.0:
				var frac := clampf(charging / 2.5, 0.0, 1.0)
				draw_circle(center, hero.radius + 12.0, Palette.with_alpha(Color("ff532f"), 0.16 + pulse * 0.09))
				draw_arc(center, hero.radius + 18.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 42,
					Palette.glow(Color("ff7547"), 1.55), 6.0)
		"shade":
			if float(hero.get("_empower_timer")) > 0.0:
				for i in range(4):
					var ray := Vector2.RIGHT.rotated(TAU * i / 4.0 - _time * 5.0)
					draw_line(center + ray * 22.0, center + ray * (39.0 + pulse * 6.0),
						Palette.with_alpha(Palette.glow(hero.hero_color(), 1.5), 0.72), 4.0)
		"scout":
			if bool(hero.get("_turret")):
				draw_arc(center, hero.radius + 15.0, _time * 1.8, _time * 1.8 + PI * 1.45, 30,
					Palette.with_alpha(Palette.glow(Palette.GOLD, 1.55), 0.75), 4.0)
				for ray in [Vector2.RIGHT, Vector2.DOWN]:
					draw_line(center - ray * 39.0, center - ray * 25.0, Palette.GOLD, 3.0)
					draw_line(center + ray * 25.0, center + ray * 39.0, Palette.GOLD, 3.0)
		"lance":
			if float(hero.get("_frenzy")) > 0.0:
				draw_arc(center, hero.radius + 13.0, -_time * 3.0, -_time * 3.0 + PI * 1.5, 28,
					Palette.with_alpha(Palette.glow(hero.hero_color(), 1.5), 0.68), 4.0)
		"kaira":
			# Kuumuusaura: mitä täydempi raivo, sitä kirkkaammat sulasäteet.
			var kheat := float(hero.call("heat")) if hero.has_method("heat") else 0.0
			if kheat > 0.25:
				for i in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 0.55)
					draw_line(center + ray * (hero.radius + 4.0),
						center + ray * (hero.radius + 12.0 + kheat * 12.0 + pulse * 4.0),
						Palette.with_alpha(Palette.glow(Color("ff5f1f"), 1.5),
							0.25 + kheat * 0.55), 5.0)
		"vesper":
			# Teloituksen jälkihehku: fosforirengas kiristyy hahmon ympärille.
			var vhunt := float(hero.call("hunt_glow")) if hero.has_method("hunt_glow") else 0.0
			if vhunt > 0.02:
				draw_arc(center, hero.radius + 10.0 + (1.0 - vhunt) * 22.0,
					_time * 3.0, _time * 3.0 + PI * 1.5, 26,
					Palette.with_alpha(Palette.glow(Color("b8ff3d"), 1.6), vhunt * 0.8), 4.0)
		"myria":
			# Siitepölykehä: tiheämpi kun kukkia on maassa, kirkas kukinnassa.
			var mb := float(hero.call("bloom_glow")) if hero.has_method("bloom_glow") else 0.0
			var mp := int(hero.call("orchid_count")) if hero.has_method("orchid_count") else 0
			for i in range(4 + mp):
				var a := _time * 1.35 + TAU * float(i) / float(4 + mp)
				var p := center + Vector2(cos(a), sin(a) * 0.48) * (34.0 + pulse * 3.0)
				draw_circle(p, 4.0 + mb * 2.5,
					Palette.with_alpha(Palette.glow(Color("ffb3e6"), 1.5), 0.55 + mb * 0.4))
		"torq":
			# Magneettiaura: kenttäviivat kiertyvät sisäänpäin kyvyn jälkeen.
			var tglow := float(hero.call("field_glow")) if hero.has_method("field_glow") else 0.0
			if tglow > 0.02:
				var rr := hero.radius + 16.0 + tglow * 10.0
				for i in range(8):
					var a := TAU * i / 8.0 - _time * 2.2
					var line := PackedVector2Array()
					for k in range(5):
						var kf := float(k) / 4.0
						line.append(center + Vector2.RIGHT.rotated(a + kf * 0.85)
							* lerpf(rr, hero.radius * 0.4, kf))
					draw_polyline(line, Palette.with_alpha(
						Palette.glow(Color("5ac8ff"), 1.5), 0.2 + tglow * 0.55), 2.5)

	# Kykyvalmiuden pallerot ihmispelaajan hahmon alla (glance-info): R1, L1,
	# väistö, ulti. Hehkuu kirkkaana kun valmis, muuten latauskaari.
	if hero.controller != null and not hero.controller.is_bot():
		_draw_ability_pips()


## Pieni rivi kykyvalmiuspalleroita hahmon alapuolella (vain ihmispelaaja).
func _draw_ability_pips() -> void:
	var c1: Color = hero.hero_color()
	var y := 24.0
	var pr := 3.7
	var gap := 10.0
	var fracs: Array = [
		clampf(1.0 - hero.cd.a1 / maxf(hero.cd_max.a1, 0.001), 0.0, 1.0),
		clampf(1.0 - hero.cd.a2 / maxf(hero.cd_max.a2, 0.001), 0.0, 1.0),
		clampf(1.0 - hero.cd.dodge / maxf(hero.cd_max.dodge, 0.001), 0.0, 1.0),
		clampf(hero.ult_charge / 100.0, 0.0, 1.0),
	]
	var cols: Array = [c1, c1, Palette.glow(c1, 1.15), Palette.GOLD]
	for i in range(4):
		var c := Vector2(-1.5 * gap + i * gap, y)
		var frac: float = fracs[i]
		var col: Color = cols[i]
		if frac >= 1.0:
			draw_circle(c, pr + 0.9, Palette.with_alpha(Palette.glow(col, 1.4), 0.85))
			draw_circle(c, pr * 0.5, Color(1, 1, 1, 0.85))
		else:
			draw_circle(c, pr, Color(0, 0, 0, 0.5))
			if frac > 0.01:
				draw_arc(c, pr, -PI * 0.5, -PI * 0.5 + TAU * frac, 12,
					Palette.with_alpha(col, 0.85), 1.5)


## Leveä kilpivalli: kiinteän näköinen läpikuultava kaarieste eteen (Bastion).
## a = suunta, radius = etäisyys, half = puolikaari (rad). Piirretään sankarin
## paikallisavaruudessa (keskipiste origossa).
func _draw_shield_wall(a: float, radius: float, half: float) -> void:
	var col := Palette.SHIELD
	var c := Vector2(0, -6)
	var inner: float = maxf(radius - 22.0, 8.0)
	var steps := 30
	# Täytetty läpikuultava kilpivyö (este, jonka läpi näkee).
	var band := PackedVector2Array()
	for i in range(steps + 1):
		var ang: float = a - half + (2.0 * half) * i / steps
		band.append(c + Vector2(cos(ang), sin(ang)) * radius)
	for i in range(steps, -1, -1):
		var ang: float = a - half + (2.0 * half) * i / steps
		band.append(c + Vector2(cos(ang), sin(ang)) * inner)
	draw_colored_polygon(band, Palette.with_alpha(Palette.glow(col, 1.2), 0.20))
	# Kirkas ulko- ja sisäreuna.
	draw_arc(c, radius, a - half, a + half, 48,
		Palette.with_alpha(Palette.glow(col, 1.6), 0.9), 5.0)
	draw_arc(c, inner, a - half, a + half, 48,
		Palette.with_alpha(Palette.glow(col, 1.3), 0.5), 2.5)
	# Kimmelluskaari.
	var shimmer := 0.5 + 0.5 * sin(_time * 6.0)
	draw_arc(c, radius - 10.0, a - half, a + half, 48,
		Palette.with_alpha(col, 0.2 + shimmer * 0.2), 2.0)
	# Säteittäiset tukiviivat kilpivyön poikki.
	for k in range(5):
		var ang: float = a - half + (2.0 * half) * float(k) / 4.0
		var op: Vector2 = c + Vector2(cos(ang), sin(ang)) * radius
		var ip: Vector2 = c + Vector2(cos(ang), sin(ang)) * inner
		draw_line(ip, op, Palette.with_alpha(Palette.glow(col, 1.4), 0.5), 2.0)


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
	draw_circle(Vector2.ZERO, (30.0 + _cast_anim * 14.0) * aura,
		Palette.with_alpha(Color("ff8a4a"), 0.10 + _cast_anim * 0.08))

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
		var h := 13.0 + _cast_anim * 11.0 + sin(_time * 8.0 + i * 1.3) * 5.0
		var lean := sin(_time * 3.0 + i) * 3.0
		var flame := PackedVector2Array([
			Vector2(fx - 4, -13), Vector2(fx + lean, -14 - h), Vector2(fx + 4, -13)])
		draw_colored_polygon(flame, Palette.glow(Color("ffcf6b"), 1.6) if i % 2 == 0 else c1)

	_body_base(Vector2.ZERO, 18.0, c1, c2)
	_eyes(Vector2(0, -4))

	# Käsivarsi ja tulilyhty
	var side: Vector2 = hero.aim.rotated(-0.9)
	var grip: Vector2 = side * 16.0 + hero.aim * _cast_anim * 9.0
	_hold(grip, c1, 18.0)
	# Lyhdyn varsi + koukku
	var lantern: Vector2 = grip + Vector2(0, 6.0)
	draw_line(grip, lantern, Palette.darker(c2, 0.6), 3.0)
	# Lyhdyn häkki
	draw_rect(Rect2(lantern + Vector2(-8, -2), Vector2(16, 18)), Palette.darker(c2, 0.6))
	draw_rect(Rect2(lantern + Vector2(-6, 0), Vector2(12, 14)), Color("1a0f08"))
	# Lyhdyn liekki
	var pulse := 0.8 + 0.2 * sin(_time * 11.0) + _cast_anim * 0.55
	var flame_center := lantern + Vector2(0, 8)
	draw_circle(flame_center, 9.0 * pulse, Palette.with_alpha(Color("ffd76d"), 0.4))
	var lantern_flame := PackedVector2Array([
		flame_center + Vector2(-4, 5), flame_center + Vector2(0, -8 * pulse),
		flame_center + Vector2(4, 5)])
	draw_colored_polygon(lantern_flame, Palette.glow(Color("ffb347"), 2.2))
	draw_circle(flame_center + Vector2(0, 2), 3.0 * pulse, Palette.glow(Color("fff0c0"), 1.8))
	if _cast_anim > 0.05:
		for i in range(3):
			var ray := hero.aim.rotated((i - 1) * 0.25)
			draw_line(flame_center + ray * 5.0, flame_center + ray * (14.0 + 12.0 * _cast_anim),
				Palette.with_alpha(Palette.glow(Color("ffcf6b"), 1.6), _cast_anim), 2.5)
	# Häkin ristikot ja kahva
	draw_line(lantern + Vector2(-8, 6), lantern + Vector2(8, 6), Palette.darker(c2, 0.7), 1.5)
	draw_arc(lantern + Vector2(0, -2), 5.0, PI, TAU, 8, Palette.darker(c2, 0.6), 2.0)


func _paint_luma(c1: Color, c2: Color) -> void:
	# Pehmeä hehkuaura
	var aura := 0.9 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, (30.0 + _cast_anim * 16.0) * aura,
		Palette.with_alpha(Color("ffe9a8"), 0.14 + _cast_anim * 0.10))

	# Leijuvat valopallot kiertävät (tuki-identiteetti)
	for i in range(3):
		var ang := _time * 1.2 + TAU * i / 3.0
		var orb := Vector2(cos(ang), sin(ang) * 0.55) * (30.0 + _cast_anim * 13.0) \
			+ Vector2(0, -8)
		var osize := 3.5 + sin(_time * 5.0 + i) * 1.0
		draw_circle(orb, osize * 1.8, Palette.with_alpha(Palette.GOLD, 0.2))
		draw_circle(orb, osize, Palette.glow(Palette.GOLD, 1.5))

	_body_base(Vector2.ZERO, 17.0, c1, c2)
	_eyes(Vector2(0, -4), 6.5)

	# Sädekehä pään yllä
	draw_arc(Vector2(0, -24), 11.0 + _cast_anim * 4.0, 0.0, TAU, 24,
		Palette.glow(Palette.GOLD, 1.8), 3.0 + _cast_anim * 2.0)
	draw_arc(Vector2(0, -24), 11.0, _time * 2.0, _time * 2.0 + PI, 16,
		Palette.glow(Color.WHITE, 1.4), 1.5)

	# Käsivarsi ja valosauva
	var side: Vector2 = hero.aim.rotated(0.9)
	var grip: Vector2 = side * 15.0
	var tip: Vector2 = side * 24.0 + hero.aim * (8.0 + _cast_anim * 13.0)
	_hold(grip, c1, 17.0)
	draw_line(grip, tip, Color("e8d9b0"), 4.0)
	# Tähtikärki hehkulla
	draw_circle(tip, 12.0 + _cast_anim * 11.0,
		Palette.with_alpha(Palette.GOLD, 0.25 + _cast_anim * 0.12))
	var star := PackedVector2Array()
	for i in range(8):
		var r := (10.0 if i % 2 == 0 else 4.0) * (1.0 + _cast_anim * 0.55)
		star.append(tip + Vector2.RIGHT.rotated(TAU * i / 8.0 + _time * 2.0) * r)
	draw_colored_polygon(star, Palette.glow(Palette.GOLD, 2.0))
	draw_circle(tip, 3.0, Palette.glow(Color.WHITE, 1.6))
	if _cast_anim > 0.05:
		for i in range(4):
			var ray := Vector2.RIGHT.rotated(TAU * i / 4.0 + _time)
			draw_line(tip + ray * 5.0, tip + ray * (18.0 + 10.0 * _cast_anim),
				Palette.with_alpha(Palette.glow(Palette.HEAL, 1.5), _cast_anim), 2.0)


func _paint_prism(c1: Color, c2: Color) -> void:
	var aura := 0.9 + 0.1 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, (30.0 + _cast_anim * 12.0) * aura,
		Palette.with_alpha(c1, 0.10 + _cast_anim * 0.07))
	var spectrum := [Color("ff7fc8"), Color("ffd76d"), Color("75e6ff")]
	for i in range(3):
		var ang := _time * 1.4 + TAU * i / 3.0
		var orb := Vector2(cos(ang), sin(ang) * 0.55) * (31.0 + _cast_anim * 9.0) \
			+ Vector2(0, -6)
		draw_colored_polygon(PackedVector2Array([
			orb + Vector2(0, -5), orb + Vector2(4, 0),
			orb + Vector2(0, 5), orb + Vector2(-4, 0)]),
			Palette.glow(spectrum[i], 1.45))

	# Prisma on itse suuri fasetoitu kristalli – kulmikas support-siluetti.
	var outer := PackedVector2Array([
		Vector2(0, -31), Vector2(20, -12), Vector2(23, 7), Vector2(12, 25),
		Vector2(0, 31), Vector2(-13, 24), Vector2(-23, 6), Vector2(-19, -13)])
	draw_colored_polygon(outer, Palette.darker(c2, 0.6))
	var inner := PackedVector2Array([
		Vector2(0, -25), Vector2(15, -9), Vector2(17, 5), Vector2(9, 19),
		Vector2(0, 25), Vector2(-9, 18), Vector2(-17, 4), Vector2(-14, -10)])
	draw_colored_polygon(inner, c1)
	# Kolme eri sävyistä fasettia rikkovat pallomaisen pinnan.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -25), Vector2(15, -9),
		Vector2(0, 1), Vector2(-14, -10)]), Palette.with_alpha(Color.WHITE, 0.26))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 1), Vector2(17, 5),
		Vector2(9, 19), Vector2(0, 25)]), Palette.with_alpha(Color("5aa8ff"), 0.24))
	draw_colored_polygon(PackedVector2Array([Vector2(0, 1), Vector2(0, 25),
		Vector2(-9, 18), Vector2(-17, 4)]), Palette.with_alpha(Color("ff7fc8"), 0.18))
	_eyes(Vector2(0, -5), 7.0, 3.5)

	# Suuri eteen leijuva kolmioprisma korvaa pienen käsikorun.
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var crystal := d * (35.0 + _cast_anim * 11.0)
	var tri := PackedVector2Array([
		crystal + d * 14.0, crystal - d * 8.0 + p * 12.0,
		crystal - d * 8.0 - p * 12.0])
	draw_colored_polygon(tri, Palette.glow(c1, 1.5))
	draw_polyline(tri + PackedVector2Array([tri[0]]),
		Palette.glow(Color.WHITE, 1.45), 2.5)
	draw_line(d * 17.0, crystal - d * 6.0, Palette.with_alpha(Color.WHITE, 0.7), 3.0)
	if _cast_anim > 0.05:
		for i in range(3):
			var ray := d.rotated((i - 1) * 0.22)
			draw_line(crystal + d * 8.0, crystal + ray * (31.0 + _cast_anim * 16.0),
				Palette.with_alpha(Palette.glow(spectrum[i], 1.45), _cast_anim), 3.0)


func _paint_rift(c1: Color, c2: Color) -> void:
	# Jälkikuvavana
	if _trail.size() > 3:
		var pts := PackedVector2Array()
		for i in range(mini(_trail.size(), 7)):
			pts.append(to_local(_trail[i]) + Vector2(0, -16))
		draw_polyline(pts, Palette.with_alpha(Palette.glow(c1, 1.2), 0.25), 5.0)

	# Rikkinäinen portaalikaari ja vain yhdellä puolella leijuvat sirpaleet.
	for i in range(3):
		var a := -1.5 + i * 1.05 + sin(_time * 1.7 + i) * 0.12
		draw_arc(Vector2(0, -5), 29.0 + i * 3.0, a, a + 0.62, 9,
			Palette.with_alpha(Palette.glow(c1, 1.45), 0.48), 3.0)
		var shard_c := Vector2(-22 - i * 4, -20 + i * 15)
		draw_colored_polygon(PackedVector2Array([
			shard_c + Vector2(0, -6), shard_c + Vector2(4, 1),
			shard_c + Vector2(-2, 6), shard_c + Vector2(-5, 0)]),
			Palette.glow(c1, 1.35))

	# Korkea, repeytynyt tyhjyysviitta tekee Riftistä pystysuuntaisen assassinin.
	var cloak := PackedVector2Array([
		Vector2(-21, 21), Vector2(-18, -8), Vector2(-8, -29), Vector2(4, -32),
		Vector2(19, -12), Vector2(17, 17), Vector2(9, 27), Vector2(1, 19),
		Vector2(-8, 29), Vector2(-12, 18)])
	draw_colored_polygon(cloak, Palette.darker(c2, 0.65))
	var inner := PackedVector2Array([
		Vector2(-15, 16), Vector2(-13, -8), Vector2(-5, -23), Vector2(3, -26),
		Vector2(13, -9), Vector2(12, 14), Vector2(7, 20), Vector2(0, 14),
		Vector2(-6, 22), Vector2(-9, 13)])
	draw_colored_polygon(inner, c1)
	# Kasvot ovat lähes tyhjä aukko, eivät pyöreä lelunaama.
	draw_circle(Vector2(0, -10), 12.0, Palette.darker(c2, 0.88))
	var eye_p := hero.aim.orthogonal().normalized() * 6.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -10) + eye_p * side + hero.aim * 2.5
		draw_line(eye - eye_p * 0.30, eye + eye_p * 0.30,
			Palette.glow(Color("e7c7ff"), 1.8), 2.5)

	# Yksi ylisuuri, rikkinäinen tyhjyyden tikari hallitsee etusiluettia.
	var d := hero.aim.rotated(-_attack_anim * 0.75).normalized()
	var p := d.orthogonal()
	var hilt := d * 12.0 + p * 5.0
	var blade_c := d * (34.0 + _attack_anim * 16.0)
	_hold(hilt, c1, 18.0, 5.0)
	var blade := PackedVector2Array([
		blade_c + d * 22.0, blade_c - d * 12.0 + p * 8.0,
		blade_c - d * 5.0, blade_c - d * 12.0 - p * 8.0])
	draw_colored_polygon(blade, Palette.glow(c1, 1.55))
	draw_polyline(blade + PackedVector2Array([blade[0]]),
		Palette.glow(Color.WHITE, 1.3), 2.0)
	draw_circle(blade_c - d * 4.0, 3.0, Palette.darker(c2, 0.9))


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
	if _cast_anim > 0.02:
		draw_circle(Vector2.ZERO, 34.0 + _cast_anim * 15.0,
			Palette.with_alpha(Palette.glow(c1, 1.25), _cast_anim * 0.16))
	# Berserkissä hehkuva raivo-aura (punainen buffi ultin ajaksi).
	if hero.red_buff > 0.0:
		for i in range(3):
			var ra := _time * 9.0 + TAU * i / 3.0
			draw_arc(Vector2.ZERO, 30.0 + sin(_time * 14.0 + i) * 3.0, ra, ra + 0.7, 5,
				Palette.with_alpha(Palette.glow(Color("ff7a3a"), 1.6), 0.55), 2.5)

	# Isot rautakourat (tarttuvat kädet) heiluvat tähtäyksen mukana.
	for side in [-1.0, 1.0]:
		var grip: Vector2 = hero.aim.rotated(0.9 * side) * 30.0
		if _cast_anim > 0.0:
			match _cast_slot:
				"a1":
					grip = hero.aim.rotated(0.28 * side) * (30.0 + _cast_anim * 28.0)
				"a2":
					grip = hero.aim.rotated(1.5 * side) * (30.0 + _cast_anim * 8.0)
				"ult":
					grip = hero.aim.rotated(1.15 * side) * (32.0 + _cast_anim * 22.0)
		if side > 0.0:
			grip = grip.rotated(-_attack_anim * 1.6) * (1.0 + _attack_anim * 0.72)
		_limb(grip * 0.5, grip, c1, 7.0)
		# Kourarauta: tumma kämmen + sormet
		draw_circle(grip, 14.0, Palette.darker(c2, 0.6))
		draw_circle(grip, 11.0, Palette.darker(c1, 0.2))
		var kperp: Vector2 = hero.aim.orthogonal().normalized()
		for f in [-1.0, 0.0, 1.0]:
			var tip: Vector2 = grip + hero.aim * 9.0 + kperp * (f * 6.0)
			draw_line(grip, tip, Palette.darker(c2, 0.7), 3.0)
		draw_circle(grip + Vector2(-3, -4), 3.0, Palette.with_alpha(Color.WHITE, 0.5))
		if _cast_anim > 0.05:
			draw_arc(grip, 17.0 + _cast_anim * 5.0, -1.2, 1.2, 12,
				Palette.with_alpha(Palette.glow(c1, 1.5), _cast_anim), 3.0)

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
		var bx: float = 5.0 * side
		draw_line(Vector2(bx - 3.5 * side, -14.0), Vector2(bx + 3.5 * side, -11.5),
			Palette.darker(c2, 0.75), 2.5)


## Hush: leveä kelloviitta ja suuri vaimennuskello. Pyöreät ääniaallot tekevät
## tukiroolin luettavaksi, mutta tumma aukko ja raskas kello erottavat Lumasta.
func _paint_hush(c1: Color, c2: Color) -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	for i in range(3):
		var rr := 25.0 + fmod(_time * 17.0 + i * 15.0, 42.0)
		var alpha := 0.28 * (1.0 - (rr - 25.0) / 42.0)
		draw_arc(Vector2(0, -5), rr, 0.0, TAU, 38,
			Palette.with_alpha(Palette.glow(c1, 1.45), alpha), 2.0)

	# Kellomainen viitta: leveä helma ja kapea huppu muuttavat peruspallon siluetin.
	var robe_outer := PackedVector2Array([
		Vector2(-25, 17), Vector2(-21, -7), Vector2(-13, -22), Vector2(0, -28),
		Vector2(13, -22), Vector2(21, -7), Vector2(25, 17), Vector2(13, 23),
		Vector2(-13, 23)])
	draw_colored_polygon(robe_outer, Palette.darker(c2, 0.55))
	var robe_inner := PackedVector2Array([
		Vector2(-20, 15), Vector2(-16, -7), Vector2(-9, -18), Vector2(0, -22),
		Vector2(9, -18), Vector2(16, -7), Vector2(20, 15), Vector2(10, 19),
		Vector2(-10, 19)])
	draw_colored_polygon(robe_inner, c1)
	# Hiljaisuuden tumma kaulus ja kellon helmaa muistuttava kultareuna.
	draw_arc(Vector2(0, -9), 15.0, PI - 0.2, TAU + 0.2, 22,
		Palette.darker(c2, 0.8), 8.0)
	draw_line(Vector2(-20, 15), Vector2(20, 15),
		Palette.glow(Color("d8c2ff"), 1.2), 3.0)
	_eyes(Vector2(0, -9), 6.5, 3.3)

	# Suuri vaimennuskello etukädessä.
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var hand := d.rotated(0.75) * 15.0
	var bell_c := d * (31.0 + _cast_anim * 10.0) + p * 5.0
	_hold(hand, c1, 20.0, 5.0)
	var bell := PackedVector2Array([
		bell_c - d * 9.0 - p * 6.0,
		bell_c + d * 7.0 - p * 11.0,
		bell_c + d * 11.0 + p * 11.0,
		bell_c - d * 9.0 + p * 6.0])
	draw_colored_polygon(bell, Palette.darker(c2, 0.45))
	draw_polyline(bell + PackedVector2Array([bell[0]]),
		Palette.glow(c1, 1.35), 2.5)
	draw_line(bell_c + d * 8.0 - p * 11.0, bell_c + d * 8.0 + p * 11.0,
		Palette.glow(Color("e6d7ff"), 1.35), 4.0)
	draw_circle(bell_c + d * 13.0, 4.0 + pulse * 1.2,
		Palette.glow(Color("f7f0ff"), 1.5))


## Obsidian: epäsäännöllinen kivijätti, valtavat nyrkit ja hehkuvat halkeamat.
func _paint_obsidian(c1: Color, c2: Color) -> void:
	var rage := clampf(hero.res / maxf(hero.res_max, 1.0), 0.0, 1.0)
	var molten := Color("ff7547")
	if rage > 0.02 or _cast_anim > 0.02:
		draw_circle(Vector2.ZERO, 35.0 + _cast_anim * 12.0,
			Palette.with_alpha(Palette.glow(molten, 1.4), 0.08 + rage * 0.14))

	# Hartialohkareet ja nyrkit piirtyvät rungon taakse.
	for side in [-1.0, 1.0]:
		var shoulder := Vector2(side * 23.0, -12.0)
		var shard := PackedVector2Array([
			shoulder + Vector2(-9 * side, 8), shoulder + Vector2(-5 * side, -9),
			shoulder + Vector2(5 * side, -14), shoulder + Vector2(11 * side, 3),
			shoulder + Vector2(5 * side, 10)])
		draw_colored_polygon(shard, Palette.darker(c2, 0.45))
		var fist_dir := hero.aim.rotated(1.0 * side)
		var fist := fist_dir * (32.0 + _cast_anim * 13.0)
		_limb(fist * 0.45, fist, c1, 9.0)
		var knuckle := PackedVector2Array()
		for i in range(7):
			var a := TAU * i / 7.0
			var fr := 16.0 if i % 2 == 0 else 13.0
			knuckle.append(fist + Vector2.RIGHT.rotated(a) * fr)
		draw_colored_polygon(knuckle, Palette.darker(c2, 0.35))
		draw_circle(fist, 9.0, c1)
		for k in [-1.0, 0.0, 1.0]:
			draw_line(fist + hero.aim * 4.0 + hero.aim.orthogonal() * k * 5.0,
				fist + hero.aim * 10.0 + hero.aim.orthogonal() * k * 6.0,
				Palette.with_alpha(molten, 0.45 + rage * 0.45), 2.0)

	var body := PackedVector2Array([
		Vector2(-28, 14), Vector2(-31, -4), Vector2(-21, -25), Vector2(-7, -31),
		Vector2(8, -29), Vector2(25, -21), Vector2(31, -2), Vector2(27, 17),
		Vector2(10, 27), Vector2(-12, 26)])
	draw_colored_polygon(body, Palette.darker(c2, 0.65))
	var core := PackedVector2Array([
		Vector2(-23, 12), Vector2(-25, -3), Vector2(-17, -20), Vector2(-5, -25),
		Vector2(8, -24), Vector2(20, -17), Vector2(25, -1), Vector2(21, 13),
		Vector2(8, 21), Vector2(-10, 21)])
	draw_colored_polygon(core, c1)
	# Laavahalkeamat tekevät raivon näkyväksi.
	var crack_col := Palette.with_alpha(Palette.glow(molten, 1.5), 0.48 + rage * 0.48)
	draw_polyline(PackedVector2Array([Vector2(-4, -24), Vector2(-1, -10),
		Vector2(-9, 0), Vector2(-5, 16)]), crack_col, 2.5)
	draw_polyline(PackedVector2Array([Vector2(20, -15), Vector2(8, -7),
		Vector2(13, 5), Vector2(5, 19)]), crack_col, 2.5)
	# Syvälle kiveen upotetut kapeat silmät.
	var eye_p := hero.aim.orthogonal().normalized() * 8.0
	draw_rect(Rect2(Vector2(-13, -16), Vector2(26, 11)),
		Palette.with_alpha(Palette.darker(c2, 0.92), 0.88), true)
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -10) + eye_p * side + hero.aim * 3.0
		draw_line(eye - eye_p * 0.32, eye + eye_p * 0.32,
			Palette.glow(molten, 1.9), 3.5)
		draw_circle(eye, 2.4, Palette.glow(Color("ffd0a6"), 1.7))


## Lance: pitkä keihäs, eteen nojaava teräsduelisti ja korkea kypäräharja.
func _paint_lance(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var reach := 58.0 + _attack_anim * 40.0 + _cast_anim * 14.0
	var tail := -d * 31.0 + p * 5.0
	var spear_tip := d * reach
	# Ase piirretään ensin koko hahmon lävistäväksi selkeäksi linjaksi.
	draw_line(tail, spear_tip, Palette.darker(Color("d9cbb0"), 0.55), 8.0)
	draw_line(tail, spear_tip, Color("d9cbb0"), 4.0)
	var head := PackedVector2Array([
		spear_tip + d * 18.0, spear_tip - d * 6.0 + p * 9.0,
		spear_tip - d * 2.0, spear_tip - d * 6.0 - p * 9.0])
	draw_colored_polygon(head, Palette.glow(Color("f2e4c7"), 1.35))
	draw_polyline(head + PackedVector2Array([head[0]]), Palette.darker(c2, 0.65), 2.0)
	# Viiri tekee suunnasta ja syöksystä luettavan.
	var flag_base := tail + d * 22.0
	var flag := PackedVector2Array([
		flag_base, flag_base - d * 18.0 + p * 4.0,
		flag_base - d * 13.0 + p * 15.0])
	draw_colored_polygon(flag, Palette.glow(c1, 1.2))

	# Terävä panssarivartalo – ei pyöreää peruspalloa.
	var torso := PackedVector2Array([
		Vector2(-18, -13), Vector2(0, -25), Vector2(18, -13),
		Vector2(22, 7), Vector2(8, 23), Vector2(-9, 22), Vector2(-22, 6)])
	draw_colored_polygon(torso, Palette.darker(c2, 0.55))
	var plate := PackedVector2Array([
		Vector2(-13, -10), Vector2(0, -19), Vector2(13, -10),
		Vector2(16, 5), Vector2(5, 17), Vector2(-6, 17), Vector2(-16, 4)])
	draw_colored_polygon(plate, c1)
	# Rintapanssarin keihäskuvio.
	draw_line(Vector2(0, -14), Vector2(0, 14), Palette.glow(Color("f2e4c7"), 1.25), 3.0)
	draw_line(Vector2(-7, 4), Vector2(0, 14), Palette.darker(c2, 0.7), 2.0)
	draw_line(Vector2(7, 4), Vector2(0, 14), Palette.darker(c2, 0.7), 2.0)
	# Kypärä ja korkea punainen harja.
	draw_arc(Vector2(0, -10), 14.0, PI - 0.25, TAU + 0.25, 20,
		Palette.darker(c2, 0.6), 8.0)
	var crest_wave := sin(_time * 5.0) * 2.0
	var crest := PackedVector2Array([
		Vector2(-4, -19), Vector2(-2, -32), Vector2(7 + crest_wave, -28),
		Vector2(7, -18)])
	draw_colored_polygon(crest, Palette.glow(c1, 1.25))
	var eye_p := p * 7.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -9) + eye_p * side + d * 3.0
		draw_line(eye - eye_p * 0.3, eye + eye_p * 0.3,
			Palette.glow(Color("fff0de"), 1.7), 2.5)
	# Kaksi kättä keihään varressa.
	for hand_pos in [d * 11.0 + p * 6.0, -d * 5.0 - p * 5.0]:
		draw_circle(hand_pos, 5.0, Palette.darker(c2, 0.55))
		draw_circle(hand_pos, 3.3, c1)


## Salvo: reppu, ylisuuri miinanheitin, suojalasit ja näkyvä räjähdevyö.
func _paint_salvo(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var bunker: bool = hero.piloting
	# Ultissa Salvo ei katoa: maahan lukittuvat tukijalat ja monikerroksinen
	# panssarikaulus tekevät bunkkeritilan luettavaksi jo siluetista.
	if bunker:
		var bunker_pulse := 0.55 + 0.45 * sin(_time * 8.0)
		draw_circle(Vector2(0, 10), 39.0, Palette.with_alpha(Color("2a211c"), 0.82))
		draw_arc(Vector2(0, 8), 41.0, 0.0, TAU, 48,
			Palette.with_alpha(Palette.glow(Color("ffb03a"), 1.3), 0.55 + bunker_pulse * 0.25), 5.0)
		for i in range(4):
			var brace_dir := Vector2.RIGHT.rotated(PI * 0.25 + TAU * i / 4.0)
			draw_colored_polygon(PackedVector2Array([
				brace_dir * 23.0 + brace_dir.orthogonal() * 7.0,
				brace_dir * 48.0 + brace_dir.orthogonal() * 11.0,
				brace_dir * 51.0 - brace_dir.orthogonal() * 11.0,
				brace_dir * 23.0 - brace_dir.orthogonal() * 7.0]),
				Palette.darker(c2, 0.72))
			draw_line(brace_dir * 31.0, brace_dir * 48.0,
				Palette.with_alpha(Color("ffb03a"), 0.75), 3.0)
	# Raskas raketti-/miinareppu muuttaa takasiluetin neliömäiseksi.
	var back := -d * 16.0
	draw_rect(Rect2(back + Vector2(-14, -18), Vector2(28, 34)),
		Palette.darker(c2, 0.7), true)
	for side in [-1.0, 1.0]:
		var pod: Vector2 = back + p * side * 10.0 - Vector2(0, 8)
		draw_circle(pod, 7.0, Palette.darker(c2, 0.4))
		draw_circle(pod, 4.0, Color("ffb03a"))
		if _cast_anim > 0.05:
			draw_line(pod - d * 5.0, pod - d * (15.0 + _cast_anim * 9.0),
				Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.4), _cast_anim), 4.0)

	# Suojaliivinen, hieman kulmikas insinöörivartalo.
	var body := PackedVector2Array([
		Vector2(-20, -13), Vector2(-10, -23), Vector2(10, -23), Vector2(21, -11),
		Vector2(22, 12), Vector2(12, 21), Vector2(-13, 21), Vector2(-22, 10)])
	draw_colored_polygon(body, Palette.darker(c2, 0.55))
	var vest := PackedVector2Array([
		Vector2(-15, -9), Vector2(-7, -18), Vector2(8, -18), Vector2(16, -8),
		Vector2(16, 10), Vector2(8, 16), Vector2(-9, 16), Vector2(-16, 8)])
	draw_colored_polygon(vest, c1)
	# Räjähdevyö: kolme helposti tunnistettavaa patruunaa.
	for i in range(3):
		var belt_p := Vector2(-8 + i * 8, 10)
		draw_rect(Rect2(belt_p + Vector2(-3, -5), Vector2(6, 11)),
			Color("ffb03a"), true)
		draw_line(belt_p + Vector2(-3, -5), belt_p + Vector2(3, -5),
			Palette.glow(Color("ffe6a3"), 1.25), 2.0)

	# Kypärä ja isot kaksilinssiset suojalasit.
	draw_arc(Vector2(0, -10), 15.0, PI + 0.1, TAU - 0.1, 18,
		Palette.darker(c2, 0.65), 7.0)
	var eye_p := p * 7.0
	for side in [-1.0, 1.0]:
		var lens: Vector2 = Vector2(0, -7) + eye_p * side + d * 3.0
		draw_circle(lens, 6.0, Palette.darker(c2, 0.8))
		draw_circle(lens, 4.2, Palette.glow(Color("ffd76d"), 1.5))
		draw_circle(lens + Vector2(-1.2, -1.4), 1.4, Color(1, 1, 1, 0.75))

	# Miinanheitin on vartaloa pidempi ja siinä on leveä rumpu sekä suppilosuu.
	var grip := d.rotated(0.55) * 13.0
	var barrel_a := d * 11.0
	var muzzle := d * (48.0 + _attack_anim * 8.0 + _cast_anim * 8.0)
	_hold(grip, c1, 20.0, 5.0)
	draw_line(barrel_a, muzzle, Palette.darker(c2, 0.8), 12.0)
	draw_line(barrel_a, muzzle, Color("8d6a4a"), 6.0)
	draw_circle(d * 21.0 + p * 4.0, 11.0, Palette.darker(c2, 0.55))
	for i in range(5):
		var a := _time * 0.7 + TAU * i / 5.0
		draw_circle(d * 21.0 + p * 4.0 + Vector2.RIGHT.rotated(a) * 6.0,
			2.0, Color("ffb03a"))
	var mouth := PackedVector2Array([
		muzzle - d * 7.0 - p * 10.0, muzzle + d * 5.0 - p * 13.0,
		muzzle + d * 5.0 + p * 13.0, muzzle - d * 7.0 + p * 10.0])
	draw_colored_polygon(mouth, Palette.darker(c2, 0.5))
	draw_line(muzzle + d * 4.0 - p * 12.0, muzzle + d * 4.0 + p * 12.0,
		Palette.glow(Color("ffb03a"), 1.35), 3.5)
	if bunker:
		# Etupanssari peittää jalat/vyön ja jättää hahmon silti näkyväksi keskelle.
		var front_plate := PackedVector2Array([
			-d * 8.0 - p * 31.0, d * 17.0 - p * 35.0,
			d * 28.0 - p * 22.0, d * 28.0 + p * 22.0,
			d * 17.0 + p * 35.0, -d * 8.0 + p * 31.0])
		draw_colored_polygon(front_plate, Palette.with_alpha(Palette.darker(c2, 0.5), 0.92))
		draw_arc(Vector2.ZERO, 34.0, d.angle() - 1.25, d.angle() + 1.25, 28,
			Palette.glow(c1, 1.25), 7.0)
		for side in [-1.0, 1.0]:
			var lock_light: Vector2 = d * 21.0 + p * side * 20.0
			draw_circle(lock_light, 4.0,
				Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.7), 0.55 + 0.4 * sin(_time * 10.0)))
		draw_line(-p * 20.0 - d * 4.0, p * 20.0 - d * 4.0,
			Palette.glow(Color("d9c49a"), 1.2), 3.0)
		# Avoin tarkkailuluukku ja tutut suojalasit: pelaaja näkee, että Salvo on
		# yhä panssarin sisällä eikä hahmo ole vain korvattu nimettömällä objektilla.
		var hatch := -d * 5.0
		draw_circle(hatch, 13.0, Palette.darker(Color("251b18"), 0.75))
		draw_arc(hatch, 14.0, 0.0, TAU, 24, Palette.glow(c1, 1.15), 3.0)
		for side in [-1.0, 1.0]:
			var hatch_lens: Vector2 = hatch + p * side * 5.2 + d * 1.5
			draw_circle(hatch_lens, 4.4, Color("39251b"))
			draw_circle(hatch_lens, 2.8, Palette.glow(Color("ffd76d"), 1.75))


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
	# Pitkä savuhäntä tekee Shadesta vaakasuuntaisen ja nopeasti pakenevan hahmon.
	var smoke_dir := -hero.aim.normalized()
	var smoke_side := smoke_dir.orthogonal()
	var smoke := PackedVector2Array()
	for i in range(9):
		var t := i / 8.0
		smoke.append(smoke_dir * (10.0 + t * 55.0) \
			+ smoke_side * sin(_time * 3.0 + t * 7.0) * (4.0 + t * 8.0))
	draw_polyline(smoke, Palette.with_alpha(c2, 0.35), 16.0)
	draw_polyline(smoke, Palette.with_alpha(c1, 0.18), 8.0)

	# Leveä lepakkomainen varjoviitta – vastakohta Riftin korkealle siluetille.
	var cloak := PackedVector2Array([
		Vector2(-31, 7), Vector2(-23, -15), Vector2(-9, -25), Vector2(0, -18),
		Vector2(10, -25), Vector2(24, -14), Vector2(32, 7), Vector2(18, 20),
		Vector2(4, 15), Vector2(0, 24), Vector2(-5, 15), Vector2(-19, 21)])
	draw_colored_polygon(cloak, Palette.darker(c2, 0.7))
	var mantle := PackedVector2Array([
		Vector2(-24, 5), Vector2(-17, -11), Vector2(-7, -19), Vector2(0, -13),
		Vector2(8, -19), Vector2(18, -10), Vector2(25, 5), Vector2(14, 14),
		Vector2(3, 10), Vector2(0, 17), Vector2(-4, 10), Vector2(-14, 15)])
	draw_colored_polygon(mantle, c1)
	# Syvä huppu ja vaakasuora silmäviiru.
	draw_circle(Vector2(0, -8), 12.0, Palette.darker(c2, 0.9))
	var perp := hero.aim.orthogonal().normalized() * 7.0
	for side in [-1.0, 1.0]:
		var eye: Vector2 = Vector2(0, -8) + perp * side + hero.aim * 2.5
		draw_line(eye - perp * 0.32, eye + perp * 0.32,
			Palette.glow(Color("d9c8ff"), 1.9), 2.5)

	# Suuri neliteräinen paluushuriken näkyy myös kaukaa.
	var hand := hero.aim.rotated(-0.62 + _attack_anim * 1.25) \
		* (29.0 + _attack_anim * 11.0)
	var spin := _time * 5.5
	var disc := PackedVector2Array()
	for i in range(16):
		var rr: float = 16.0 if i % 4 == 0 else (7.0 if i % 2 == 0 else 4.5)
		disc.append(hand + Vector2.RIGHT.rotated(spin + TAU * i / 16.0) * rr)
	draw_colored_polygon(disc, Palette.glow(c1, 1.35))
	draw_circle(hand, 5.0, Palette.darker(c2, 0.85))
	draw_circle(hand, 2.3, Palette.glow(Color("ebe4ff"), 1.45))


func _paint_tide(c1: Color, c2: Color) -> void:
	# Leijuvat vesipisarat kiertävät
	for i in range(3):
		var da := _time * 1.6 + TAU * i / 3.0
		var dp := Vector2(cos(da), sin(da) * 0.6) * 30.0 + Vector2(0, -8)
		draw_circle(dp, 3.0, Palette.with_alpha(Palette.glow(c1, 1.3), 0.6))

	# Pisaramainen vartalo ja sivuevät tekevät vesitaistelijasta oman muotonsa.
	var crest := -30.0 - sin(_time * 4.0) * 3.0 - _cast_anim * 6.0
	var outer := PackedVector2Array([
		Vector2(0, crest), Vector2(17, -15), Vector2(24, 3), Vector2(17, 21),
		Vector2(0, 28), Vector2(-17, 21), Vector2(-24, 3), Vector2(-17, -15)])
	draw_colored_polygon(outer, Palette.darker(c2, 0.55))
	var inner := PackedVector2Array([
		Vector2(0, crest + 6), Vector2(13, -11), Vector2(18, 3), Vector2(13, 16),
		Vector2(0, 22), Vector2(-13, 16), Vector2(-18, 3), Vector2(-13, -11)])
	draw_colored_polygon(inner, c1)
	# Läpinäkyvät virtaevät molemmilla sivuilla.
	for side in [-1.0, 1.0]:
		var fin := PackedVector2Array([
			Vector2(side * 16, -5), Vector2(side * 36, -15),
			Vector2(side * 28, 5), Vector2(side * 38, 17), Vector2(side * 15, 12)])
		draw_colored_polygon(fin, Palette.with_alpha(Palette.glow(c1, 1.3), 0.34))
		draw_polyline(fin, Palette.with_alpha(Color("bfeaf7"), 0.5), 1.8)
	# Sisäinen vesipyörre ja märkä kiilto.
	draw_arc(Vector2(0, 4), 12.0, _time * 2.0, _time * 2.0 + PI * 1.55, 18,
		Palette.with_alpha(Color("bfeaf7"), 0.55), 2.5)
	draw_circle(Vector2(-6, -10), 5.0, Palette.with_alpha(Color.WHITE, 0.30))
	_eyes(Vector2(0, -6), 7.0)

	# Käsivarsi ja vesikeihäs (piikkikärki + väkäset)
	var reach := 37.0 + _attack_anim * 31.0 + _cast_anim * 9.0
	var tip: Vector2 = hero.aim * (16.0 + reach)
	var tail: Vector2 = -hero.aim * 14.0 + hero.aim.orthogonal() * 6.0
	_hold(hero.aim * 12.0, c1, 20.0)
	draw_line(tail, tip, Palette.darker(c2, 0.65), 7.0)
	draw_line(tail, tip, Color("bfeaf7"), 3.5)
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
	# Selässä iso läpinäkyvä vaahtopallosäiliö ja radioantenni.
	var back := -hero.aim * 15.0
	draw_circle(back, 14.0, Palette.darker(c2, 0.65))
	draw_circle(back, 11.0, Palette.with_alpha(Color("e8f2c0"), 0.42))
	for i in range(4):
		var a := _time * 0.25 + TAU * i / 4.0
		draw_circle(back + Vector2.RIGHT.rotated(a) * 6.0, 3.2,
			Palette.with_alpha(Color("f7ffdf"), 0.85))
	draw_line(back + Vector2(0, -10), back + Vector2(0, -29),
		Palette.darker(c2, 0.65), 2.5)
	draw_circle(back + Vector2(0, -31), 2.8,
		Palette.glow(Color("ffd76d"), 1.4))

	_body_base(Vector2.ZERO, 19.0, c1, c2)

	# Lippalakki lipan kanssa (osoittaa tähtäyssuuntaan)
	draw_arc(Vector2(0, -9), 17.0, PI + 0.2, TAU - 0.2, 18, Palette.darker(c2, 0.7), 7.0)
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

	# Vaahtopallokivääri on nyt hahmoa selvästi pidempi ja paksumpi.
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var barrel_start := d * 8.0 + p * 5.0
	var barrel_end := d * (48.0 + _attack_anim * 9.0 + _cast_anim * 6.0)
	var stock := -d * 21.0 + p * 5.0
	_hold(barrel_start, c1, 19.0, 5.0)
	_hold(d * 20.0 - p * 5.0, c1, 19.0, 5.0)
	draw_line(stock, barrel_end, Palette.darker(c2, 0.75), 11.0)
	draw_line(stock, barrel_end, Color("8d9b54"), 6.0)
	# Tukeva perä, etukahva ja leveä vaahtosuppilo.
	var stock_poly := PackedVector2Array([
		stock - d * 7.0 - p * 8.0, stock + d * 6.0 - p * 6.0,
		stock + d * 8.0 + p * 5.0, stock - d * 4.0 + p * 10.0])
	draw_colored_polygon(stock_poly, Palette.darker(c2, 0.5))
	draw_line(d * 22.0, d * 22.0 + p * 12.0, Palette.darker(c2, 0.7), 5.0)
	var muzzle := PackedVector2Array([
		barrel_end - d * 6.0 - p * 9.0, barrel_end + d * 4.0 - p * 12.0,
		barrel_end + d * 4.0 + p * 12.0, barrel_end - d * 6.0 + p * 9.0])
	draw_colored_polygon(muzzle, Palette.darker(c2, 0.55))
	draw_line(barrel_end + d * 3.0 - p * 11.0, barrel_end + d * 3.0 + p * 11.0,
		Palette.glow(Color("eaf3bd"), 1.35), 3.0)
	# Iso pallosäiliö kiväärin päällä näyttää aseen käyttötarkoituksen.
	var hopper := d * 18.0 + p * 11.0
	draw_circle(hopper, 9.0, Palette.darker(c2, 0.55))
	draw_circle(hopper, 6.5, Palette.with_alpha(Color("f2f5ff"), 0.78))
	draw_circle(hopper + Vector2(-2, -2), 2.0, Color.WHITE)


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


## KAIRA — sulakuoriainen. Muotokieli: matala kuusikulmainen kuori, taakse
## kaartuvat piikit ja YKSI valtava kartiopora. Kuoren railot hehkuvat
## kuumuuden (raivon) mukaan, joten pelaaja näkee resurssinsa hahmosta.
func _paint_kaira(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var heat := 0.0
	if hero.has_method("heat"):
		heat = float(hero.call("heat"))
	if hero.has_method("hit_glow"):
		heat = clampf(heat + float(hero.call("hit_glow")) * 0.45, 0.0, 1.0)
	var molten := Color("ff5f1f")
	var crack := Palette.glow(molten, 1.2 + heat * 0.9)
	var burrow := hero.has_method("burrowing") and bool(hero.call("burrowing"))

	# Kaivautunut kuoriainen on lähes maan alla: pelkkä pölykumpu ja railot.
	if burrow:
		draw_circle(Vector2(0, 6), 22.0, Palette.with_alpha(Palette.darker(c2, 0.4), 0.85))
		for i in range(5):
			var ray := Vector2.RIGHT.rotated(TAU * i / 5.0 + _time * 2.0)
			draw_line(ray * 8.0, ray * 24.0, Palette.with_alpha(crack, 0.7), 3.0)
		return

	# Taakse kaartuvat lämpöpiikit (kuoriaisen "harja") — silhuetin selkäranka.
	for i in range(5):
		var t := float(i) / 4.0
		var root := -d * (8.0 + t * 16.0) + p * (t - 0.5) * 34.0
		var spike := root - d * (14.0 + sin(_time * 3.0 + i) * 3.0) + p * (t - 0.5) * 16.0
		draw_line(root, spike, Palette.darker(c2, 0.55), 7.0)
		draw_line(root, spike, Palette.with_alpha(crack, 0.35 + heat * 0.5), 3.0)

	# Matala kuusikulmainen kuori: leveä sivuttain, kapea edestä.
	var shell := PackedVector2Array()
	for i in range(6):
		var a := TAU * i / 6.0 + PI / 6.0
		shell.append(d * cos(a) * 21.0 + p * sin(a) * 26.0)
	draw_colored_polygon(shell, Palette.darker(c2, 0.5))
	var inner := PackedVector2Array()
	for i in range(6):
		var a := TAU * i / 6.0 + PI / 6.0
		inner.append(d * cos(a) * 16.0 + p * sin(a) * 20.0)
	draw_colored_polygon(inner, c1)
	# Kolme hehkuvaa railoa kuoren poikki: kuumuusmittari suoraan hahmossa.
	for i in range(3):
		var off := (float(i) - 1.0) * 9.0
		draw_line(-d * 15.0 + p * off, d * 13.0 + p * off * 0.4,
			Palette.with_alpha(crack, 0.35 + heat * 0.6), 3.0 + heat * 2.0)

	# Kaksi raskasta kaivujalkaa eteen — kuoriainen nojaa eteenpäin.
	for side in [-1.0, 1.0]:
		var hip: Vector2 = p * side * 19.0 + d * 4.0
		var claw: Vector2 = hip + d * 16.0 + p * side * 8.0
		draw_line(hip, claw, Palette.darker(c2, 0.62), 8.0)
		draw_colored_polygon(PackedVector2Array([
			claw + d * 9.0, claw + p * side * 7.0, claw - d * 5.0]),
			Palette.darker(Color("c9d1d8"), 0.75))

	# Kaksi hehkuvaa silmää visiirin alla.
	for side in [-1.0, 1.0]:
		draw_circle(d * 12.0 + p * side * 7.0, 3.0, Palette.glow(Color("fff0a8"), 1.6))

	# YKSI valtava kartiopora: hahmon tunnistettavin muoto.
	var base := d * 14.0
	var tip := d * (62.0 + _attack_anim * 14.0)
	draw_line(base, tip - d * 10.0, Palette.darker(c2, 0.7), 20.0)
	draw_line(base, tip - d * 10.0, Palette.with_alpha(crack, 0.5 + heat * 0.4), 11.0)
	draw_colored_polygon(PackedVector2Array([
		tip, tip - d * 32.0 + p * 16.0, tip - d * 32.0 - p * 16.0]), Color("c9d1d8"))
	# Kierteinen hammastus: viivat siirtyvät hyökkäyksessä -> pora pyörii.
	for i in range(5):
		var f := float(i + 1) / 6.0
		var c := tip - d * 32.0 * f
		var w := 2.5 + 13.5 * f
		var skew := sin(_time * 14.0 + f * 6.0) * (2.0 + _attack_anim * 4.0)
		draw_line(c - p * w + d * skew, c + p * w - d * skew,
			Palette.darker(Color("c9d1d8"), 0.5), 2.4)
	draw_circle(tip, 5.0 + _attack_anim * 4.0 + heat * 2.0,
		Palette.glow(Color("fff0a8"), 1.6))


## VESPER — fosforijahtaaja. Muotokieli: yksi suuri SIRPPI (kiskojousi) ja
## fosforilyhty. Kapea, eteenpäin nojaava siluetti; teloituksen jälkeen koko
## hahmo hehkuu hetken kirkkaana.
func _paint_vesper(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var hunt := 0.0
	if hero.has_method("hunt_glow"):
		hunt = clampf(float(hero.call("hunt_glow")), 0.0, 1.0)
	var burn := Color("b8ff3d")
	var glow := Palette.glow(burn, 1.3 + hunt * 0.7)

	# Pieni merkintädroni leijuu olan yllä ja osoittaa tähtäyssuuntaan.
	var drone := -d * 14.0 + Vector2(0, -27.0 + sin(_time * 3.2) * 3.0)
	draw_circle(drone, 7.0, Palette.darker(c2, 0.65))
	draw_circle(drone, 3.6, glow)
	draw_line(drone, drone + d * 13.0, Palette.with_alpha(burn, 0.35 + hunt * 0.4), 1.6)

	# Viitta: kapea, taaksepäin liehuva kolmio — jahtaaja on aina liikkeessä.
	draw_colored_polygon(PackedVector2Array([
		-d * 4.0 + p * 13.0,
		-d * (26.0 + sin(_time * 4.0) * 3.0) + p * 6.0,
		-d * (30.0 + sin(_time * 4.0 + 1.0) * 3.0) - p * 5.0,
		-d * 4.0 - p * 13.0]), Palette.darker(c2, 0.5))

	_body_base(Vector2.ZERO, 16.0, c1, c2)
	# Huppu ja YKSI kirkas tähtäyslinssi — ei kasvoja, vain optiikka.
	draw_colored_polygon(PackedVector2Array([
		-d * 13.0 + Vector2(0, -6),
		d * 6.0 + Vector2(0, -20),
		d * 14.0 + Vector2(0, -4),
		d * 4.0 + Vector2(0, 4)]), Palette.darker(c2, 0.62))
	draw_circle(d * 10.0 + Vector2(0, -7), 4.6, Palette.darker(c2, 0.3))
	draw_circle(d * 10.0 + Vector2(0, -7), 3.0, glow)

	# Fosforilyhty lantiolla: pieni hehkuva lähde, joka sykkii teloituksen jälkeen.
	var lamp := -d * 10.0 + p * 12.0 + Vector2(0, 6)
	draw_circle(lamp, 6.0, Palette.darker(c2, 0.6))
	draw_circle(lamp, 3.4 + hunt * 2.0, Palette.glow(Color("d9ff8f"), 1.4 + hunt * 0.6))

	# SIRPPI: iso kaareva kiskojousi, jännitteinen energiajänne kärkien välissä.
	var grip := d * 12.0 + p * 6.0
	var arc_c := d * 30.0 + p * 4.0
	var bow := PackedVector2Array()
	for i in range(13):
		var a := -1.35 + 2.7 * float(i) / 12.0
		bow.append(arc_c + d * cos(a) * 13.0 + p * sin(a) * (30.0 + _attack_anim * 4.0))
	draw_polyline(bow, Palette.darker(c2, 0.7), 9.0)
	draw_polyline(bow, Color("76b23c"), 4.0)
	_hold(grip, c1, 16.0, 5.0)
	# Jänne: kirkas viiva sirpin kärkien välillä, vetäytyy hyökkäyksessä taakse.
	var tip_a: Vector2 = bow[0]
	var tip_b: Vector2 = bow[bow.size() - 1]
	var pull: Vector2 = (tip_a + tip_b) * 0.5 - d * (4.0 + _attack_anim * 12.0)
	draw_line(tip_a, pull, Palette.glow(Color("eeffc9"), 1.4), 2.4)
	draw_line(pull, tip_b, Palette.glow(Color("eeffc9"), 1.4), 2.4)
	draw_circle(pull, 3.5 + _attack_anim * 3.5 + hunt * 2.0, glow)


## MYRIA — orkideahenki. Muotokieli: KUUSI TERÄLEHTEÄ kruununa, kelluva runko
## ja alaspäin riippuvat juurivarret. Istutetut orkideat näkyvät nuppuina
## hahmon ympärillä, joten pelaaja tietää aina montako Kukinta räjäyttää.
func _paint_myria(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var orchid := Color("c77bff")
	var nectar := Color("ffb3e6")
	var stem := Color("7ee08a")
	var bloom := 0.0
	if hero.has_method("bloom_glow"):
		bloom = clampf(float(hero.call("bloom_glow")), 0.0, 1.0)
	var planted := int(hero.call("orchid_count")) if hero.has_method("orchid_count") else 0

	# Alaspäin riippuvat juurivarret: henki kelluu, juuret laahaavat maassa.
	for i in range(5):
		var sway := sin(_time * 1.8 + float(i)) * 5.0
		var root := Vector2((float(i) - 2.0) * 7.0, 14.0)
		draw_line(root, root + Vector2(sway, 17.0 + float(i % 2) * 5.0),
			Palette.with_alpha(stem, 0.55), 2.6)

	# Kuuden terälehden kruunu — Myrian tunnistettavin muoto.
	for i in range(6):
		var a := TAU * i / 6.0 + _time * 0.35
		var ray := Vector2(cos(a), sin(a) * 0.72)
		draw_colored_polygon(PackedVector2Array([
			ray * 8.0,
			ray * 24.0 + ray.orthogonal() * 10.0,
			ray * (33.0 + bloom * 6.0),
			ray * 24.0 - ray.orthogonal() * 10.0]),
			Palette.with_alpha(Palette.glow(orchid, 1.25 + bloom * 0.5), 0.82))

	# Kelluva runko ja hehkuva mesiydin.
	_body_base(Vector2.ZERO, 15.0, c1, c2)
	draw_circle(Vector2.ZERO, 8.0, Palette.darker(c2, 0.4))
	draw_circle(Vector2.ZERO, 5.0 + sin(_time * 5.0) * 1.2 + bloom * 3.0,
		Palette.glow(nectar, 1.5 + bloom * 0.5))
	# Kasvoton maski: kapea pystyviiru mesiytimen yllä.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -17), Vector2(6, -6), Vector2(0, 4), Vector2(-6, -6)]),
		Color("eadfff"))
	draw_line(Vector2(0, -14), Vector2(0, 1), Palette.glow(orchid, 1.6), 2.4)

	# Istutetut orkideat nuppuina hahmon ympärillä: 0-3 (ultin jälkeen enemmän).
	for i in range(mini(planted, 8)):
		var a := _time * 1.2 + TAU * float(i) / maxf(float(mini(planted, 8)), 1.0)
		var bud := Vector2(cos(a), sin(a) * 0.5) * 40.0
		draw_circle(bud, 5.5, Palette.darker(c2, 0.5))
		draw_circle(bud, 3.2, Palette.glow(nectar, 1.5))
		draw_line(bud, bud + Vector2(0, 7.0), Palette.with_alpha(stem, 0.6), 1.8)

	# Kaksihaarainen kukkasauva tähtäyssuuntaan.
	var hand := d * 11.0 + p * 8.0
	var tip := d * 40.0
	_hold(hand, c1, 15.0, 5.0)
	draw_line(hand, tip, Palette.darker(stem, 0.8), 5.0)
	draw_line(hand, tip, stem, 2.2)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			tip, tip - d * 13.0 + p * side * 11.0, tip - d * 4.0 + p * side * 4.0]),
			Palette.with_alpha(Palette.glow(orchid, 1.4), 0.85))
	draw_circle(tip + d * 3.0, 4.5 + _cast_anim * 5.0 + bloom * 3.0,
		Palette.glow(nectar, 1.55))


## TORQ — magneettivartija. Muotokieli: valtava HEVOSENKENKÄ (U) hartioilla,
## punainen ja sininen napa sen kärjissä, ja kenttäviivat jotka kaartuvat napojen
## välillä. Siluetti kertoo yhdellä silmäyksellä: tämä hahmo vetää sinut luokseen.
func _paint_torq(c1: Color, c2: Color) -> void:
	var d := hero.aim.normalized()
	var p := d.orthogonal()
	var glow := 0.0
	if hero.has_method("field_glow"):
		glow = clampf(float(hero.call("field_glow")), 0.0, 1.0)
	var north := Color("ff5470")
	var south := Color("5ac8ff")

	# Kenttäviivat napojen välillä: aina hiukan, kyvyn jälkeen voimakkaasti.
	var pole_n: Vector2 = p * 26.0 - d * 4.0
	var pole_s: Vector2 = -p * 26.0 - d * 4.0
	for i in range(3):
		var bulge := (float(i) - 1.0) * 13.0 - 20.0
		var mid: Vector2 = (pole_n + pole_s) * 0.5 + d * bulge
		var arc := PackedVector2Array()
		for k in range(9):
			var t := float(k) / 8.0
			var a: Vector2 = pole_n.lerp(mid, t)
			var b: Vector2 = mid.lerp(pole_s, t)
			arc.append(a.lerp(b, t))
		draw_polyline(arc, Palette.with_alpha(Palette.glow(c1, 1.45),
			0.16 + glow * 0.5), 2.5 + glow * 2.0)

	# Hevosenkenkä: paksu U-kaari hartioiden yli, kärjet eteenpäin.
	var horseshoe := PackedVector2Array()
	for i in range(15):
		var a := PI * 0.16 + PI * 1.68 * float(i) / 14.0
		horseshoe.append(d * cos(a) * -27.0 + p * sin(a) * 27.0)
	draw_polyline(horseshoe, Palette.darker(c2, 0.6), 17.0)
	draw_polyline(horseshoe, Palette.darker(Color("c3ccdf"), 0.9), 11.0)

	# Kaksinapaiset kärjet: punainen ja sininen — magneetti tunnistuu heti.
	draw_circle(pole_n, 9.5, Palette.darker(c2, 0.55))
	draw_circle(pole_n, 6.5, Palette.glow(north, 1.3 + glow * 0.5))
	draw_circle(pole_s, 9.5, Palette.darker(c2, 0.55))
	draw_circle(pole_s, 6.5, Palette.glow(south, 1.3 + glow * 0.5))

	# Raskas kuusikulmainen runko ja reaktoriydin kaaren sisällä.
	var body := PackedVector2Array()
	for i in range(6):
		body.append(Vector2.RIGHT.rotated(PI / 6.0 + TAU * i / 6.0) * 21.0)
	draw_colored_polygon(body, Palette.darker(c2, 0.68))
	var inner := PackedVector2Array()
	for i in range(6):
		inner.append(Vector2.RIGHT.rotated(PI / 6.0 + TAU * i / 6.0) * 16.0)
	draw_colored_polygon(inner, c1)
	draw_circle(Vector2.ZERO, 9.0, Color("10254a"))
	draw_circle(Vector2.ZERO, 5.5 + sin(_time * 5.0) * 1.2 + glow * 2.5,
		Palette.glow(Color("d4e4ff"), 1.55))
	# Kapea visiiri: yksi vaakaviiva, ei kasvoja — vartija on kone.
	draw_line(d * 9.0 - p * 9.0, d * 9.0 + p * 9.0, Color("10254a"), 6.0)
	draw_line(d * 10.0 - p * 6.0, d * 10.0 + p * 6.0, Palette.glow(south, 1.4), 2.6)

	# Magneettivasara: varsi ja pieni kaksinapainen U-pää.
	var hand := d * 12.0 + p * 9.0
	var head := d * (46.0 + _attack_anim * 10.0) + p * 4.0
	_hold(hand, c1, 20.0, 6.0)
	draw_line(hand, head, Color("a9b5c7"), 8.0)
	var prong := PackedVector2Array()
	for i in range(9):
		var a := PI * 0.3 + PI * 1.4 * float(i) / 8.0
		prong.append(head + d * cos(a) * -12.0 + p * sin(a) * 12.0)
	draw_polyline(prong, Palette.darker(c2, 0.6), 9.0)
	draw_circle(head + p * 11.0, 4.0 + _cast_anim * 2.0, Palette.glow(north, 1.5))
	draw_circle(head - p * 11.0, 4.0 + _cast_anim * 2.0, Palette.glow(south, 1.5))
