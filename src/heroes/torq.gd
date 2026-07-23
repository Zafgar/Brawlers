class_name Torq
extends JungleHero
## Tankki-jungleri: majakka kokoaa leirin ja Ankkuritila korvaa väistöloikan.

const BASIC_REACH := 142.0
const PULSE_RADIUS := 205.0
const ULT_RADIUS := 290.0

var _anchor_time := 0.0
var _fortress_time := 0.0
var _anchor_release_pending := false


func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = res_max
	res_regen = 5.5
	res_cost.a1 = 20.0
	res_cost.a2 = 30.0


func _aimed_slots() -> Array:
	return ["a1"]


func _ground_targeted_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 500.0


func _aim_default_range(_slot: String) -> float:
	return 300.0


func _aim_target_radius(_slot: String) -> float:
	return 150.0


func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("torq", 125.0, d)
	Fx.slash(arena, global_position, d, BASIC_REACH, 0.82,
		Palette.glow(hero_color(), 1.45))
	AudioMgr.play("titan_punch", 0.08, -8.0, global_position)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		if off.length() > BASIC_REACH + enemy.radius or off.length() < 1.0:
			continue
		if d.dot(off.normalized()) < 0.38:
			continue
		var dealt := deal_damage_to(enemy, 17.0, 170.0, d)
		if dealt > 0.0 and enemy is Critter:
			gain_res(10.0)
			cd.a1 = maxf(cd.a1 - 0.65, 0.0)


func _ability1(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, 500.0, 300.0)
	ability_signature("torq", 155.0, target - global_position)
	JungleField.spawn(self, target, "beacon", {
		"radius": 150.0, "dur": 5.8, "dps": 15.0, "tick": 0.46,
		"color": hero_color(),
	})
	Fx.ring(arena, target, Palette.glow(hero_color(), 1.5), 150.0, 0.45, 6.0)
	AudioMgr.play("dome_up", 0.08, -7.0, target)


func _ability2(_dir: Vector2) -> void:
	ability_signature("torq", 190.0, aim)
	Fx.vortex(arena, global_position, Palette.glow(hero_color(), 1.5), PULSE_RADIUS, 0.58)
	var enemy_hits := 0
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		if off.length() > PULSE_RADIUS + enemy.radius:
			continue
		enemy_hits += 1
		var away := off.normalized() if off.length() > 1.0 else Vector2.UP
		# Kaksipulssi luetaan liikkeessä: ensin pieni imu, sitten magneettinen repäisy.
		enemy.apply_knockback(-away, 170.0, false)
		deal_damage_to(enemy, 28.0 if enemy is Critter else 21.0, 360.0, away)
		enemy.apply_slow(0.67, 0.9)
		if enemy is Critter:
			enemy.apply_stun(0.35)
	for ally in arena.heroes_in_circle(global_position, PULSE_RADIUS, team, true, true):
		ally.add_shield(32.0 + enemy_hits * 7.0, 3.2, self)
	Fx.ring(arena, global_position, Color("b7d5ff"), PULSE_RADIUS, 0.5, 7.0)
	AudioMgr.play("shield", 0.1, -4.0, global_position)
	controller_rumble(0.5, 0.75, 0.2)


func _dodge_action(_dir: Vector2) -> void:
	_anchor_time = 2.25
	_anchor_release_pending = true
	cc_immune_timer = maxf(cc_immune_timer, _anchor_time)
	add_shield(72.0, _anchor_time + 0.5, self)
	ability_signature("torq", 160.0, aim)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 125.0, 0.4, 7.0)
	AudioMgr.play("shield", 0.12, -2.0, global_position)
	controller_rumble(0.6, 0.82, 0.24)


func _move_speed_mult() -> float:
	return 0.18 if _anchor_time > 0.0 else 1.0


func take_damage(amount: float, source: Hero, kb := 0.0,
		kb_dir := Vector2.ZERO) -> float:
	if _anchor_time > 0.0:
		amount *= 0.48
	elif _fortress_time > 0.0:
		amount *= 0.72
	return super.take_damage(amount, source, kb, kb_dir)


func _passive_update(delta: float) -> void:
	var was_anchor := _anchor_time > 0.0
	_anchor_time = maxf(_anchor_time - delta, 0.0)
	_fortress_time = maxf(_fortress_time - delta, 0.0)
	if was_anchor and _anchor_time <= 0.0 and _anchor_release_pending:
		_anchor_release_pending = false
		_anchor_release()


func _anchor_release() -> void:
	Fx.ring(arena, global_position, Palette.glow(Color("b7d5ff"), 1.5), 155.0, 0.42, 7.0)
	Fx.burst(arena, global_position, hero_color(), 16, 280.0, 0.45, 5.0)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		if off.length() > 155.0 + enemy.radius:
			continue
		var away := off.normalized() if off.length() > 1.0 else Vector2.UP
		deal_damage_to(enemy, 14.0, 410.0, away)
		if enemy is Critter:
			enemy.apply_stun(0.32)


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 580.0


func _ult_default_range() -> float:
	return 330.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	_fortress_time = 8.0
	Fx.ultimate_warning(arena, target, Palette.glow(hero_color(), 1.6),
		Palette.team(team), ULT_RADIUS, 0.62, "torq")
	Fx.ultimate_field(arena, target, hero_color(), Palette.team(team),
		ULT_RADIUS, 8.0, "torq")
	JungleField.spawn(self, target, "fortress", {
		"radius": ULT_RADIUS, "dur": 8.0, "dps": 0.0, "tick": 0.4,
		"color": hero_color(),
	})
	arena.popup(target + Vector2(0, -ULT_RADIUS - 25), "NOLLAVYÖHYKE!", Color("b7d5ff"), 24)
	AudioMgr.play("dome_up", 0.13, -1.0, target)
	controller_rumble(0.7, 0.95, 0.35)


func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	return is_instance_valid(target) and target is Critter \
		and (hp < max_hp * 0.7 or (target as Critter).is_major_objective())
