class_name Kaira
extends JungleHero
## Melee-bruiser: kokoaa leirin, rakentaa raivoa ja jauhaa lukitun alueen.

const BASIC_REACH := 132.0
const A2_RADIUS := 185.0
const ULT_RADIUS := 255.0

var _drill_chain := 0
var _anchor_glow := 0.0


func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost.a2 = 35.0


func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 560.0


func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	_drill_chain = (_drill_chain + 1) % 3
	var breaker := _drill_chain == 0
	var dmg := 27.0 if breaker else 17.0
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("kaira", 120.0, d)
	Fx.slash(arena, global_position, d, BASIC_REACH, 0.72,
		Palette.glow(Color("ffd45a") if breaker else hero_color(), 1.5))
	if breaker:
		# Ydinmurskaus: poranterä kipinöi — sulametallisuihku iskusuuntaan.
		Fx.burst(arena, global_position + d * BASIC_REACH * 0.6,
			Palette.glow(Color("ffcf4a"), 1.6), 12, 260.0, 0.32, 4.0)
	AudioMgr.play("rock" if breaker else "swing", 0.08, -4.0 if breaker else -7.0,
		global_position)
	controller_rumble(0.22, 0.52 if breaker else 0.26, 0.1)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		if off.length() > BASIC_REACH + enemy.radius or off.length() < 1.0:
			continue
		if d.dot(off.normalized()) < 0.48:
			continue
		var dealt := deal_damage_to(enemy, dmg, 150.0 if breaker else 60.0, d)
		if breaker and dealt > 0.0:
			enemy.apply_slow(0.72, 0.8)
			if enemy is Critter:
				heal_hp(8.0, self)
				gain_res(12.0)


func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("kaira", 150.0, d)
	Projectile.launch(self, global_position + d * (radius + 8.0), d, {
		"speed": 880.0, "dmg": 22.0, "radius": 12.0, "life": 0.72,
		"kb": 0.0, "color": hero_color(), "visual": "kaira_harpoon",
		"on_hit": Callable(self, "_harpoon_hit"),
	})
	AudioMgr.play("titan_launch", 0.08, -4.0, global_position)
	controller_rumble(0.2, 0.38, 0.12)


func _harpoon_hit(target: Hero, _projectile: Projectile) -> void:
	var pull := global_position - target.global_position
	if pull.length() > 1.0:
		# Vetovoima on jo viritetty kohdetyypin mukaan -> ohita kb_resist.
		target.apply_knockback(pull, 760.0 if target is Critter else 470.0, false)
	if target is Critter:
		target.apply_stun(0.62)
		gain_res(18.0)
	else:
		target.apply_slow(0.58, 1.1)
	# Ketju kiristyy: raskas vetosäde ja kipinäpurske tartuntapisteessä.
	Fx.beam(arena, global_position, target.global_position,
		Palette.glow(hero_color(), 1.5), 7.0)
	Fx.burst(arena, target.global_position, Palette.glow(Color("ffcf4a"), 1.5),
		9, 210.0, 0.3, 3.5)
	AudioMgr.play("titan_grab", 0.08, -7.0, target.global_position)


func _ability2(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("kaira", 175.0, d)
	# Painepurkaus luetaan kartiona: kaksi jauhavaa sivallusta ja kuumuusvälähdys,
	# ei pyörre (pyörteet ovat Torqin magneettikieltä).
	Fx.slash(arena, global_position, d, A2_RADIUS * 0.92, 1.05,
		Palette.glow(Color("ff8f2a"), 1.5))
	Fx.slash(arena, global_position, d, A2_RADIUS * 0.6, 1.2,
		Palette.glow(Color("ffd45a"), 1.4))
	Fx.flash(arena, global_position + d * 88.0, Palette.glow(hero_color(), 1.5), 70.0, 0.3)
	Fx.burst(arena, global_position + d * 95.0, Color("ffcf59"), 22, 360.0, 0.5, 6.0)
	AudioMgr.play("quake", 0.1, -6.0, global_position)
	controller_rumble(0.45, 0.75, 0.18)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		if off.length() > A2_RADIUS + enemy.radius or off.length() < 1.0:
			continue
		if d.dot(off.normalized()) < 0.18:
			continue
		deal_damage_to(enemy, 40.0 if enemy is Critter else 33.0, 240.0, d)
		enemy.apply_slow(0.55, 1.25)
		if enemy is Critter:
			enemy.apply_stun(0.42)


func _dodge_action(_dir: Vector2) -> void:
	_anchor_glow = 1.15
	ability_signature("kaira", 145.0, aim)
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = global_position - enemy.global_position
		if off.length() > 175.0 + enemy.radius:
			continue
		hits += 1
		if off.length() > 1.0:
			# Sisäänveto kohti Kairaa; voima viritetty kohdetyypin mukaan.
			enemy.apply_knockback(off, 430.0 if enemy is Critter else 210.0, false)
		if enemy is Critter:
			enemy.apply_stun(0.55)
		else:
			enemy.apply_slow(0.65, 0.85)
	add_shield(34.0 + hits * 18.0, 3.2, self)
	cc_immune_timer = maxf(cc_immune_timer, 0.7)
	# Maapiikki: raskas maavälähdys + kipinärengas — eri kieli kuin Torqin kilpikupla.
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.4), 60.0, 0.28)
	Fx.ring(arena, global_position, Palette.glow(Color("ffd45a"), 1.6), 178.0, 0.45, 7.0)
	Fx.burst(arena, global_position, Palette.glow(Color("ffcf4a"), 1.5), 14, 200.0, 0.4, 5.0)
	AudioMgr.play("slam", 0.1, -4.0, global_position)
	controller_rumble(0.5, 0.7, 0.2)


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 620.0


func _ult_default_range() -> float:
	return 390.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	Fx.ultimate_warning(arena, target, Palette.glow(hero_color(), 1.6),
		Palette.team(team), ULT_RADIUS, 0.5, "kaira")
	Fx.ultimate_field(arena, target, hero_color(), Palette.team(team),
		ULT_RADIUS, 6.4, "kaira")
	JungleField.spawn(self, target, "bore", {
		"radius": ULT_RADIUS, "dur": 6.4, "dps": 24.0, "tick": 0.4,
		"color": hero_color(),
	})
	arena.popup(target + Vector2(0, -ULT_RADIUS - 25), "SYVÄPORA!", Color("ffd45a"), 24)
	AudioMgr.play("ult", 0.12, -2.0, target)
	AudioMgr.play("quake", 0.08, -8.0, target)
	controller_rumble(0.75, 1.0, 0.35)


func _passive_update(delta: float) -> void:
	_anchor_glow = maxf(_anchor_glow - delta, 0.0)


func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	return is_instance_valid(target) and target is Critter \
		and (hp < max_hp * 0.72 or (target as Critter).is_major_objective())
