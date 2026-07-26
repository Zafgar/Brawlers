class_name Projectile
extends Area2D
## Yleiskäyttöinen ammus. Osuu vihollisiin (etäisyystesti, max 8 sankaria)
## ja seiniin (fysiikka-alue). Piirtää hehkuvan ytimen ja häntäjäljen.
##
## Käyttö:  Projectile.launch(sankari, lähtöpiste, suunta, { asetukset })
## Asetukset (kaikilla järkevä oletus):
##   speed, dmg, radius, life, kb, color, pierce, trail, heal_allies,
##   on_hit: Callable(hero, projectile), on_expire: Callable(pos), spin

var source: Hero = null
var team := 0
var speed := 900.0
var dmg := 12.0
var hit_radius := 10.0
var life := 1.2
var kb := 140.0
var color := Color.WHITE
var pierce := 0
var show_trail := true
var heal_allies := 0.0
var on_hit := Callable()
var on_expire := Callable()
var spin := false
var homing_target: Hero = null   # jos asetettu, ammus kaartaa tätä kohti
var homing_rate := 0.0           # maksimikääntyminen rad/s (0 = ei hakeutumista)
var ignore_terrain_walls := false # esim. tornin lukittu laukaus ohittaa karttageometrian
var visual_id := "orb"
var owner_color := Color.WHITE
var team_color := Color.WHITE
var owner_number := 0

var direction := Vector2.RIGHT
var _slot := ""                # mikä kykypaikka ampui tämän (telemetria)
var _hit_heroes: Array = []
var _trail_points := PackedVector2Array()
var _time := 0.0


static func launch(src: Hero, pos: Vector2, dir: Vector2, cfg := {}) -> Projectile:
	var p := Projectile.new()
	p.source = src
	p._slot = src._cast_context   # ampuva kyky (asetettu dispatch-kontekstissa)
	p.team = src.team
	p.global_position = pos
	p.direction = dir.normalized()
	p.speed = cfg.get("speed", 900.0)
	p.dmg = cfg.get("dmg", 12.0)
	p.hit_radius = cfg.get("radius", 10.0)
	p.life = cfg.get("life", 1.2)
	p.kb = cfg.get("kb", 140.0)
	p.color = cfg.get("color", src.hero_color())
	p.pierce = cfg.get("pierce", 0)
	p.show_trail = cfg.get("trail", true)
	p.heal_allies = cfg.get("heal_allies", 0.0)
	p.on_hit = cfg.get("on_hit", Callable())
	p.on_expire = cfg.get("on_expire", Callable())
	p.spin = cfg.get("spin", false)
	p.homing_target = cfg.get("homing_target", null)
	p.homing_rate = cfg.get("homing_rate", 0.0)
	p.ignore_terrain_walls = cfg.get("ignore_terrain_walls", false)
	p.visual_id = cfg.get("visual", "orb")
	p.team_color = Palette.team(src.team)
	if src.profile != null and not src.profile.is_bot:
		p.owner_color = src.profile.color()
		p.owner_number = src.profile.index + 1
	else:
		p.owner_color = p.team_color
	src.arena.add_projectile(p)
	return p


func _ready() -> void:
	z_index = 20
	collision_layer = 0
	collision_mask = 1  # vain seinät fysiikan kautta
	monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_wall_hit)


func _physics_process(delta: float) -> void:
	_time += delta
	life -= delta
	if life <= 0.0:
		_expire()
		return

	# Hakeutuminen: kaarra kohti kohdetta rajoitetulla kääntönopeudella (esim.
	# Scoutin lukittu kohde -> luodit hakeutuvat siihen).
	if homing_rate > 0.0 and homing_target != null and is_instance_valid(homing_target) \
			and homing_target.alive:
		var want: Vector2 = homing_target.global_position - global_position
		if want.length() > 1.0:
			var ang: float = clampf(direction.angle_to(want.normalized()),
				-homing_rate * delta, homing_rate * delta)
			direction = direction.rotated(ang)

	global_position += direction * speed * delta

	if show_trail:
		_trail_points.insert(0, global_position)
		if _trail_points.size() > 8:
			_trail_points.resize(8)

	var arena = source.arena if source != null and is_instance_valid(source) else null
	if arena == null:
		queue_free()
		return

	# Kuplat (Bastionin Linnake) torjuvat vihollisammukset.
	for zone in arena.zones:
		if not is_instance_valid(zone):
			continue
		if zone.type == "dome" and zone.team != team:
			if global_position.distance_to(zone.global_position) < zone.radius:
				if zone.source != null and is_instance_valid(zone.source):
					zone.source.profile.stats.prevented += dmg
					zone.source.profile.add_score(dmg * 0.08)
				Fx.spark(arena, global_position, Palette.SHIELD)
				AudioMgr.play("shield", 0.08, 0.0, global_position)
				queue_free()
				return

	# Osumat sankareihin etäisyystestillä.
	for hero in arena.heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		if hero in _hit_heroes:
			continue
		var dist: float = global_position.distance_to(hero.global_position)
		if dist > hit_radius + hero.radius:
			continue
		var have_src: bool = source != null and is_instance_valid(source)
		if hero.team == team:
			if heal_allies > 0.0 and hero != source and hero.hp < hero.max_hp:
				_hit_heroes.append(hero)
				if have_src:
					source._act(_slot)
				hero.heal_hp(heal_allies, source)
				if have_src:
					source._act_end()
			continue
		# Vihollisosuma: aseta ampuvan kyvyn konteksti vahingon + on_hit-CC:n ajaksi.
		_hit_heroes.append(hero)
		if have_src:
			source._act(_slot)
			source.deal_damage_to(hero, dmg, kb, direction)
		if on_hit.is_valid():
			on_hit.call(hero, self)
		if have_src:
			source._act_end()
		Fx.ability_impact(arena, global_position, visual_id, color, owner_color, team_color)
		# Maailmayksiköiden osumat saavat oman äänensä. Sankariammusten soundi
		# kuuluu yleensä jo laukaisussa, joten niitä ei tuplata tässä.
		match visual_id:
			"tower_bolt":
				AudioMgr.play("tower_impact", 0.045, -3.0, global_position)
			"minion_bolt":
				AudioMgr.play("minion_impact", 0.08, -17.0, global_position)
			"critter_fire":
				AudioMgr.play("red_guardian_impact", 0.06, -9.0, global_position)
			"critter_frost":
				AudioMgr.play("blue_guardian_impact", 0.05, -9.0, global_position)
			"dragon_breath":
				AudioMgr.play("dragon_impact", 0.04, -2.0, global_position)
			"baron_orb":
				AudioMgr.play("baron_impact", 0.035, -1.0, global_position)
		if pierce > 0:
			pierce -= 1
		else:
			queue_free()
			return

	queue_redraw()


func _on_wall_hit(body: Node) -> void:
	# Tuhoutuvat esteet (esim. Boulderin kivimuuri) ottavat vahinkoa ammuksista.
	var wall := body.get_parent()
	if wall != null and wall.has_method("hit_by_projectile"):
		wall.hit_by_projectile(dmg, team)
		_expire()
		return
	# Lukittu tornin laukaus ei katoa tavalliseen karttaseinään. Se voidaan silti
	# pysäyttää oikeilla kyvyillä: kivimuuri yllä, Bastionin kilpi ja dome-looppi.
	if ignore_terrain_walls:
		return
	_expire()


func _expire() -> void:
	if on_expire.is_valid():
		# Aseta ampuneen kyvyn konteksti, jotta on_expire-vahingot (esim. Emberin
		# liekkilammikko) kirjautuvat oikealle kykypaikalle.
		var have_src: bool = source != null and is_instance_valid(source)
		if have_src:
			source._act(_slot)
		on_expire.call(global_position)
		if have_src:
			source._act_end()
	if source != null and is_instance_valid(source) and source.arena != null:
		Fx.ability_impact(source.arena, global_position, visual_id, color, owner_color, team_color)
	queue_free()


func _draw() -> void:
	var pts := PackedVector2Array()
	if show_trail and _trail_points.size() > 1:
		for point in _trail_points:
			pts.append(to_local(point))
	var forward := direction.normalized()
	var side := forward.orthogonal()
	var wobble := 1.0 + sin(_time * 20.0) * 0.08
	var angle := _time * 9.0 if spin else 0.0

	match visual_id:
		"tower_bolt":
			# Tornin laukaus on raskas, lukittu energiakeihäs: punainen vaaraydin,
			# joukkueväriset siivekkeet ja pitkä pyrstö erottuvat ruuhkassa.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Color("ff3d45"), 0.30), hit_radius * 1.65)
				draw_polyline(pts, Palette.with_alpha(team_color, 0.70), hit_radius * 0.72)
				draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.55), 2.0)
			var spear := PackedVector2Array([
				forward * hit_radius * 1.8,
				side * hit_radius * 0.66,
				-forward * hit_radius * 1.35,
				-side * hit_radius * 0.66,
			])
			draw_colored_polygon(spear, Palette.glow(team_color, 1.5))
			for fin_s in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([
					-forward * hit_radius * 0.35 + side * fin_s * hit_radius * 0.35,
					-forward * hit_radius * 1.35 + side * fin_s * hit_radius * 1.0,
					-forward * hit_radius * 1.05 + side * fin_s * hit_radius * 0.2,
				]), Color("ff4652"))
			draw_circle(Vector2.ZERO, hit_radius * 0.72, Palette.glow(Color("ff4652"), 1.65))
			draw_circle(forward * hit_radius * 0.25, hit_radius * 0.30, Color.WHITE)
			draw_arc(Vector2.ZERO, hit_radius * (1.05 + 0.12 * sin(_time * 18.0)),
				_time * 6.0, _time * 6.0 + PI * 1.45, 18, Color("fff0dd"), 2.0)
		"minion_bolt":
			# Ranged-minionin pultti: pieni nuolenkärki ja katkonainen energiavana.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.38), 3.0)
				for i in range(1, pts.size(), 2):
					draw_circle(pts[i], maxf(1.0, hit_radius * (0.28 - i * 0.018)),
						Palette.with_alpha(Color.WHITE, 0.34))
			draw_colored_polygon(PackedVector2Array([
				forward * hit_radius * 1.45,
				-forward * hit_radius * 0.8 + side * hit_radius * 0.7,
				-forward * hit_radius * 0.48,
				-forward * hit_radius * 0.8 - side * hit_radius * 0.7,
			]), Palette.glow(color, 1.5))
			draw_circle(Vector2.ZERO, hit_radius * 0.34, Color.WHITE)
		"critter_fire", "critter_frost", "dragon_breath", "baron_orb", "critter_orb":
			# Neutral shots need distinct silhouettes: flame, ice crystal, wide
			# breath lance and the Baron's rotating void core.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.42), hit_radius * 0.72)
				draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.28), 2.0)
			if visual_id == "critter_fire":
				var flame := PackedVector2Array([
					forward * hit_radius * 1.65,
					side * hit_radius * 0.78 - forward * hit_radius * 0.25,
					-forward * hit_radius * 1.45,
					-side * hit_radius * 0.78 - forward * hit_radius * 0.25,
				])
				draw_colored_polygon(flame, Palette.glow(color, 1.6))
				draw_circle(forward * hit_radius * 0.35, hit_radius * 0.34, Color("fff0b0"))
			elif visual_id == "critter_frost":
				var crystal := PackedVector2Array([
					forward * hit_radius * 1.7, side * hit_radius * 0.7,
					-forward * hit_radius * 1.25, -side * hit_radius * 0.7,
				])
				draw_colored_polygon(crystal, Palette.glow(color, 1.55))
				draw_line(-forward * hit_radius, forward * hit_radius * 1.35, Color.WHITE, 2.2)
			elif visual_id == "dragon_breath":
				for width in [1.35, 0.82, 0.36]:
					draw_arc(-forward * hit_radius * 0.15, hit_radius * width,
						-forward.angle() - 0.78, -forward.angle() + 0.78, 14,
						Palette.with_alpha(Palette.glow(color, 1.5), 0.8), 3.0)
				draw_circle(forward * hit_radius * 0.7, hit_radius * 0.45, Color.WHITE)
			else:
				var spikes := PackedVector2Array()
				for i in range(12):
					var rr := hit_radius * (1.2 if i % 2 == 0 else 0.72)
					spikes.append(Vector2.RIGHT.rotated(angle + TAU * i / 12.0) * rr)
				draw_colored_polygon(spikes, Palette.glow(color, 1.5))
				draw_circle(Vector2.ZERO, hit_radius * 0.46, Color("25102f"))
				draw_arc(Vector2.ZERO, hit_radius * 0.76, 0.0, TAU, 20, Color.WHITE, 2.0)
		"torq_hook":
			# Magneettikoukku: raskas ketju ja kaksinapainen ankkuripää.
			if pts.size() > 1:
				for i in range(1, pts.size()):
					var link_a = pts[i - 1]
					var link_b = pts[i]
					draw_line(link_a, link_b, Palette.with_alpha(Color("6f7d99"), 0.8), 5.0)
					if i % 2 == 0:
						draw_circle(link_b, 3.4, Palette.glow(color, 1.3))
			var claw := forward * hit_radius * 1.6
			draw_colored_polygon(PackedVector2Array([
				claw, -forward * hit_radius * 0.3 + side * hit_radius * 1.05,
				-forward * hit_radius * 0.7,
				-forward * hit_radius * 0.3 - side * hit_radius * 1.05]),
				Palette.glow(Color("c3ccdf"), 1.35))
			# Punainen ja sininen napa kärjessä: magneetti tunnistuu yhdellä silmäyksellä.
			draw_circle(claw * 0.55 + side * hit_radius * 0.6, hit_radius * 0.34,
				Palette.glow(Color("ff5470"), 1.6))
			draw_circle(claw * 0.55 - side * hit_radius * 0.6, hit_radius * 0.34,
				Palette.glow(Color("5ac8ff"), 1.6))
		"kaira_harpoon":
			# Poraharppuuna näyttää raskaalta ketjuaseelta, ei tavalliselta ammuspallolta.
			if pts.size() > 1:
				for i in range(1, pts.size()):
					var a := pts[i - 1]
					var b := pts[i]
					draw_line(a, b, Palette.with_alpha(Color("7f5a32"), 0.72), 5.0)
					if i % 2 == 0:
						draw_circle(b, 3.2, Palette.glow(color, 1.2))
			var nose := forward * hit_radius * 1.75
			draw_colored_polygon(PackedVector2Array([
				nose, -forward * hit_radius * 0.45 + side * hit_radius * 0.9,
				-forward * hit_radius * 0.15,
				-forward * hit_radius * 0.45 - side * hit_radius * 0.9]),
				Palette.glow(Color("e6bd68"), 1.4))
			for barb in [-1.0, 1.0]:
				draw_line(-forward * hit_radius * 0.1,
					-forward * hit_radius * 0.75 + side * barb * hit_radius,
					Color("fff0a8"), 3.0)
		"vesper_bolt", "vesper_tracker":
			var tracker := visual_id == "vesper_tracker"
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.55 if tracker else 0.34),
					5.0 if tracker else 2.5)
				if tracker:
					draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.42), 1.5)
			var tip := forward * hit_radius * (1.9 if tracker else 1.5)
			draw_line(-forward * hit_radius, tip, Palette.glow(color, 1.55),
				4.0 if tracker else 2.5)
			draw_colored_polygon(PackedVector2Array([
				tip, tip - forward * hit_radius * 0.9 + side * hit_radius * 0.55,
				tip - forward * hit_radius * 0.72 - side * hit_radius * 0.55]), Color.WHITE)
			for fin_side in [-1.0, 1.0]:
				draw_line(-forward * hit_radius * 0.65,
					-forward * hit_radius * 0.15 + side * fin_side * hit_radius * 0.75,
					team_color, 2.0)
			if tracker:
				draw_arc(Vector2.ZERO, hit_radius * (1.15 + 0.16 * sin(_time * 16.0)),
					_time * 4.0, _time * 4.0 + PI * 1.4, 16, Palette.glow(color, 1.45), 2.0)
		"myria_wisp", "myria_thread":
			var thread := visual_id == "myria_thread"
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.42), 5.0 if thread else 3.0)
				for i in range(1, pts.size(), 2):
					draw_circle(pts[i], 2.5, Palette.with_alpha(Color.WHITE, 0.42))
			var orbit_r := hit_radius * (1.0 if thread else 0.72)
			for i in range(3 if thread else 2):
				var a := angle + TAU * i / (3.0 if thread else 2.0)
				var orb := Vector2(cos(a), sin(a)) * orbit_r
				draw_circle(orb, hit_radius * 0.32, Palette.glow(color, 1.5))
			draw_circle(Vector2.ZERO, hit_radius * 0.62, Palette.glow(color, 1.7))
			draw_circle(forward * hit_radius * 0.18, hit_radius * 0.25, Color.WHITE)
		"salvo_grenade":
			# Pyörivä metallikranaatti, ei geneerinen hehkuva pallo.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Color("665b50"), 0.34), hit_radius * 1.05)
				for i in range(1, pts.size(), 2):
					draw_circle(pts[i], maxf(1.5, hit_radius * (0.32 - i * 0.018)),
						Palette.with_alpha(Color("d0b58a"), 0.3))
			var spin_f := _time * 13.0
			var axis := forward.rotated(spin_f)
			var cross := axis.orthogonal()
			var shell := PackedVector2Array([
				axis * hit_radius * 1.25, cross * hit_radius * 0.82,
				-axis * hit_radius * 1.25, -cross * hit_radius * 0.82])
			draw_colored_polygon(shell, Palette.darker(Color("805737"), 0.55))
			draw_circle(Vector2.ZERO, hit_radius * 0.68, Color("d97832"))
			draw_line(-cross * hit_radius * 0.7, cross * hit_radius * 0.7,
				Palette.glow(Color("ffd76d"), 1.45), 3.0)
			for fin_dir in [axis, -axis]:
					draw_colored_polygon(PackedVector2Array([
						fin_dir * hit_radius * 0.7 + cross * 3.0,
						fin_dir * hit_radius * 1.4,
						fin_dir * hit_radius * 0.7 - cross * 3.0]), team_color)
		"quill_arrow", "quill_super":
			# Selvä nuolisiluetti: pitkä varsi, kärki ja sulat. Täysi lataus saa
			# kaksinkertaisen kultaisen valojuovan.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.48),
					hit_radius * (0.72 if visual_id == "quill_super" else 0.38))
				if visual_id == "quill_super":
					draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.55), 2.0)
			draw_line(-forward * hit_radius * 1.55, forward * hit_radius * 1.25,
				Palette.glow(color, 1.5), 3.0 if visual_id == "quill_super" else 2.0)
			draw_colored_polygon(PackedVector2Array([
				forward * hit_radius * 1.7,
				forward * hit_radius * 0.72 + side * hit_radius * 0.5,
				forward * hit_radius * 0.82 - side * hit_radius * 0.5]),
				Palette.glow(Color.WHITE, 1.35) if visual_id == "quill_super" else color)
			for feather_side in [-1.0, 1.0]:
				draw_line(-forward * hit_radius * 1.15,
					-forward * hit_radius * 0.55 + side * feather_side * hit_radius * 0.65,
					team_color, 2.0)
		"blink_blade":
			# Valoterä on ohut sirppi eikä pallo.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.36), hit_radius * 0.45)
			var blade_tip := forward * hit_radius * 1.7
			var blade_tail := -forward * hit_radius * 1.15
			draw_colored_polygon(PackedVector2Array([
				blade_tip, side * hit_radius * 0.72,
				blade_tail, -side * hit_radius * 0.28]), Palette.glow(color, 1.65))
			draw_line(blade_tail, blade_tip, Color(1, 1, 1, 0.78), 1.5)
		"volt_arc":
			# Kulmikas salamasalama, jonka muoto elää joka framella.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.28), hit_radius * 0.65)
			var zig := PackedVector2Array()
			for i in range(7):
				var f := float(i) / 6.0
				zig.append(-forward * hit_radius * 1.5 + forward * hit_radius * 3.0 * f
					+ side * sin(_time * 31.0 + i * 2.4) * hit_radius * 0.48)
			draw_polyline(zig, Palette.glow(color, 1.75), 3.2)
			draw_circle(Vector2.ZERO, hit_radius * 0.34, Color(1, 1, 1, 0.82))
		"shade_disc":
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Color("21132f"), 0.6), hit_radius * 1.1)
			var disc := PackedVector2Array()
			for i in range(12):
				var dr := hit_radius * (1.35 if i % 2 == 0 else 0.72)
				disc.append(Vector2.RIGHT.rotated(_time * 12.0 + TAU * i / 12.0) * dr)
			draw_colored_polygon(disc, Palette.glow(color, 1.4))
			draw_circle(Vector2.ZERO, hit_radius * 0.46, Color("21132f"))
			draw_arc(Vector2.ZERO, hit_radius * 0.72, 0.0, TAU, 18, owner_color, 2.0)
		"scout_bullet":
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.34), 2.5)
			draw_line(-forward * hit_radius * 1.25, forward * hit_radius * 0.75,
				Palette.glow(color, 1.45), 5.0)
			draw_colored_polygon(PackedVector2Array([
				forward * hit_radius * 1.35,
				forward * hit_radius * 0.55 + side * 3.0,
				forward * hit_radius * 0.55 - side * 3.0]), Color("f4ead6"))
		"scout_mark":
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Palette.GOLD, 0.48), 3.0)
			draw_circle(Vector2.ZERO, hit_radius * 0.7, Palette.with_alpha(Palette.GOLD, 0.22))
			draw_arc(Vector2.ZERO, hit_radius * 1.05, 0.0, TAU, 24, Palette.glow(Palette.GOLD, 1.6), 2.4)
			for cross_dir in [forward, side]:
				draw_line(-cross_dir * hit_radius * 1.35, cross_dir * hit_radius * 1.35,
					Palette.glow(Palette.GOLD, 1.45), 2.0)
		"scout_stun":
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.3), hit_radius * 0.5)
			draw_circle(Vector2.ZERO, hit_radius * 1.08, Palette.with_alpha(Color("d7edff"), 0.35))
			draw_arc(Vector2.ZERO, hit_radius, 0.0, TAU, 28, Color.WHITE, 2.5)
			draw_arc(Vector2.ZERO, hit_radius * 0.62, _time * 8.0, _time * 8.0 + PI * 1.35,
				20, Palette.glow(Color("80d8ff"), 1.45), 2.5)
		"maestro_note":
			# Nuottipää, varsi ja lippu sekä siniaaltona väreilevä vana.
			if pts.size() > 1:
				var music_trail := PackedVector2Array()
				for i in range(pts.size()):
					music_trail.append(pts[i] + side * sin(_time * 18.0 - i * 1.1) * 5.0)
				draw_polyline(music_trail, Palette.with_alpha(color, 0.48), 3.0)
			draw_circle(-side * hit_radius * 0.36, hit_radius * 0.62, Palette.glow(color, 1.55))
			draw_line(-side * hit_radius * 0.36 + forward * hit_radius * 0.2,
				-side * hit_radius * 0.36 - side * hit_radius * 1.45,
				Palette.glow(color, 1.5), 3.0)
			draw_arc(-side * hit_radius * 1.75, hit_radius * 0.72,
				-forward.angle(), -forward.angle() + 1.8, 12, Palette.glow(color, 1.45), 3.0)
		"hush_wave", "hush_field_seed":
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.25), hit_radius * 0.7)
			var wave_angle := forward.angle()
			for i in range(3):
				draw_arc(-forward * i * 4.0, hit_radius * (0.58 + i * 0.34),
					wave_angle - 0.85, wave_angle + 0.85, 14,
					Palette.with_alpha(Palette.glow(color, 1.45), 0.9 - i * 0.18), 2.4)
			if visual_id == "hush_field_seed":
				draw_circle(Vector2.ZERO, hit_radius * 0.48, Palette.glow(Color("a678f0"), 1.55))
		"prism_shard":
			if pts.size() > 1:
				for ribbon_side in [-1.0, 1.0]:
					var ribbon := PackedVector2Array()
					for i in range(pts.size()):
						ribbon.append(pts[i] + side * ribbon_side * (3.0 + i * 0.35))
					draw_polyline(ribbon, Palette.with_alpha(color, 0.35), 2.0)
			draw_colored_polygon(PackedVector2Array([
				forward * hit_radius * 1.55, side * hit_radius * 0.86,
				-forward * hit_radius * 1.25, -side * hit_radius * 0.86]),
				Palette.glow(color, 1.5))
			draw_line(-side * hit_radius * 0.75, forward * hit_radius * 1.35,
				Color(1, 1, 1, 0.75), 1.5)
		"bramble_vine":
			if pts.size() > 1:
				var vine := PackedVector2Array()
				for i in range(pts.size()):
					vine.append(pts[i] + side * sin(_time * 15.0 - i * 0.9) * 4.0)
				draw_polyline(vine, Palette.with_alpha(color, 0.55), 4.0)
			draw_line(-forward * hit_radius, forward * hit_radius,
				Palette.glow(color, 1.35), 4.0)
			for thorn_side in [-1.0, 1.0]:
				draw_line(forward * hit_radius * 0.15,
					forward * hit_radius * 0.65 + side * thorn_side * hit_radius * 0.65,
					Palette.glow(Color("b7f56a"), 1.35), 2.5)
			draw_colored_polygon(PackedVector2Array([
				forward * hit_radius * 1.55,
				forward * hit_radius * 0.55 + side * hit_radius * 0.65,
				forward * hit_radius * 0.55 - side * hit_radius * 0.65]), color)
		"luma_pulse":
			# Kaksi kiertyvää valonauhaa + pehmeä kahdeksansakarainen tähti.
			if pts.size() > 1:
				var ribbon_a := PackedVector2Array()
				var ribbon_b := PackedVector2Array()
				for i in range(pts.size()):
					var off := side * sin(_time * 16.0 - i * 1.2) * hit_radius * 0.45
					ribbon_a.append(pts[i] + off)
					ribbon_b.append(pts[i] - off)
				draw_polyline(ribbon_a, Palette.with_alpha(Palette.GOLD, 0.6), hit_radius * 0.45)
				draw_polyline(ribbon_b, Palette.with_alpha(Palette.HEAL, 0.5), hit_radius * 0.32)
			draw_circle(Vector2.ZERO, hit_radius * 1.9 * wobble, Palette.with_alpha(color, 0.22))
			var star := PackedVector2Array()
			for i in range(16):
				var r := hit_radius * (1.15 if i % 2 == 0 else 0.48)
				star.append(Vector2.RIGHT.rotated(_time * 3.5 + TAU * i / 16.0) * r)
			draw_colored_polygon(star, Palette.glow(Palette.GOLD, 1.8))
			draw_circle(Vector2.ZERO, hit_radius * 0.38, Palette.glow(Color.WHITE, 1.6))
		"ember_bolt", "ember_seed":
			# Emberin ammus on terävä pisara/comet, ei geneerinen pallo.
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(Color("8f241f"), 0.45), hit_radius * 1.35)
				draw_polyline(pts, Palette.with_alpha(Color("ffb347"), 0.72), hit_radius * 0.62)
			var scale_f := 1.25 if visual_id == "ember_seed" else 1.0
			var flame := PackedVector2Array([
				forward * hit_radius * 1.45 * scale_f,
				side * hit_radius * 0.78 * scale_f - forward * hit_radius * 0.25,
				-forward * hit_radius * 1.55 * scale_f,
				-side * hit_radius * 0.78 * scale_f - forward * hit_radius * 0.25,
			])
			draw_colored_polygon(flame, Palette.glow(color, 1.6))
			draw_circle(forward * hit_radius * 0.2, hit_radius * 0.48,
				Palette.glow(Color("fff0c0"), 1.5))
			for i in range(3):
				var ember_p := -forward * hit_radius * (1.2 + i * 0.55) \
					+ side * sin(_time * 22.0 + i * 2.1) * 5.0
				draw_circle(ember_p, maxf(1.5, hit_radius * (0.28 - i * 0.05)),
					Palette.glow(Color("ffcf6b"), 1.5))
		_:
			if pts.size() > 1:
				draw_polyline(pts, Palette.with_alpha(color, 0.4), hit_radius * 0.9)
			draw_circle(Vector2.ZERO, hit_radius * 1.5 * wobble, Palette.with_alpha(color, 0.25))
			draw_circle(Vector2.ZERO, hit_radius * wobble, Palette.glow(color, 1.6))
			draw_circle(Vector2.RIGHT.rotated(angle) * hit_radius * 0.25, hit_radius * 0.45,
				Palette.glow(Color.WHITE, 1.3))

	# Sama lukukieli kaikissa ammuksissa: joukkueen reunus + P1–P4-väriviivat.
	draw_arc(Vector2.ZERO, hit_radius * 1.3, 0.0, TAU, 24,
		Palette.with_alpha(team_color, 0.88), 2.0)
	if owner_number > 0:
		var marks := mini(owner_number, 4)
		for i in range(marks):
			var ma := -0.55 + i * 0.36
			draw_arc(Vector2.ZERO, hit_radius * 1.62, ma - 0.11, ma + 0.11, 5,
				Palette.glow(owner_color, 1.45), 2.8)
