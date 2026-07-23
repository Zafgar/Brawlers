class_name Volt
extends Hero
## Mage: sähkökelat. Salamat ketjuttavat vihollisesta toiseen.
## Passiivi: osumat lataavat ultimatea tavallista nopeammin.

func _init() -> void:
	radius = 23.0


## Mana: salamat maksavat manaa mutta latautuvat lähes heti — voit spämmätä
## ketjusalamoja ja kenttiä kunnes mana loppuu. Kipinä (perus) on ilmainen.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 15.0
	res_cost = {"basic": 0.0, "a1": 38.0, "a2": 34.0, "dodge": 0.0}   # a1 30->34->38 (nerf 2-3: harvempi spämmi)
	cd_max.a1 = 0.6
	cd_max.a2 = 0.6


## Perushyökkäys: kipinä, joka hyppää lähimpään toiseen viholliseen.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("zap", 0.15, -3.0)
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 900.0,
		"dmg": 18.0,
		"radius": 10.0,
		"life": 0.75,
		"kb": 90.0,
		"color": Color("ffe14a"),
		"visual": "volt_arc",
		"on_hit": Callable(self, "_spark_jump"),
	})


func _spark_jump(hit_hero: Hero, proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	add_ult(2.0)   # skaalattu uuteen ultitalouteen (oli 4)
	var next := _nearest_enemy(hit_hero.global_position, 260.0, [hit_hero])
	if next != null:
		Fx.bolt(arena, hit_hero.global_position, next.global_position, hero_color())
		AudioMgr.play("zap", 0.2, -6.0)
		deal_damage_to(next, proj.dmg * 0.6, 60.0,
			(next.global_position - hit_hero.global_position).normalized())


func _nearest_enemy(from: Vector2, max_dist: float, exclude: Array) -> Hero:
	var best: Hero = null
	var best_dist := max_dist
	for enemy in arena.alive_enemies(team):
		if enemy in exclude:
			continue
		var d: float = enemy.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## Kyky 1: Ketjusalama — jopa kolme vihollista sarjassa.
func _ability1(dir: Vector2) -> void:
	var first: Hero = null
	var best := 520.0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > best or dir.dot(to_enemy.normalized()) < 0.3:
			continue
		best = to_enemy.length()
		first = enemy
	if first == null:
		# Ei kohdetta: pieni kipinä eteen, kyky ei mene hukkaan kokonaan.
		Fx.bolt(arena, global_position, global_position + dir * 220.0, hero_color())
		AudioMgr.play("zap", 0.1, -4.0)
		cd.a1 = 1.5
		return
	AudioMgr.play("zap", 0.1, -2.0)
	var from := global_position
	var chain: Array = []
	var target := first
	# Nerf 3 (sim4: volt YHÄ 807 vah/min = 2x ka, 67% voitto; a1 = 149k vahinkoa
	# + 90 970 s hidastusta, 93% arvosta kontrollia -> kestänyt 2 pehmeää nerffiä).
	# Kova nerffi: pohjavahinko 18->14, hidastus lievempi ja lyhyempi
	# (0.85/0.45 -> 0.88/0.35), manahinta 34->38 (ks. _setup_resource).
	var dmg := 14.0
	while target != null and chain.size() < 2:
		Fx.bolt(arena, from, target.global_position, hero_color())
		Fx.flash(arena, target.global_position, Palette.glow(hero_color(), 1.5), 38.0, 0.25)
		deal_damage_to(target, dmg, 120.0, (target.global_position - from).normalized())
		target.apply_slow(0.88, 0.35)
		chain.append(target)
		from = target.global_position
		dmg *= 0.8
		target = _nearest_enemy(from, 300.0, chain)


## Kyky 2: Sähkökenttä — rätisevä hidastava alue.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("zap", 0.15, -5.0)
	var pos: Vector2 = aimed_ground_position(dir, 540.0, 260.0)
	pos = arena.map.clamp_to_field(pos, 80.0)
	Zone.spawn(self, pos, {
		"type": "shock",
		"radius": 130.0,
		"dur": 3.5,
		"dps": 9.0,
		"slow_f": 0.7,
		"color": Color("ffe14a"),
	})


## Väistö: kipinähyppy.
func _dodge_action(dir: Vector2) -> void:
	Fx.bolt(arena, global_position, global_position + dir * 140.0, hero_color())
	dash(dir, 1100.0, 0.13, true)
	AudioMgr.play("zap", 0.15, 2.0)


## Ultimate: Ukkosmyrsky — oikealla tatilla sijoitettava myrskykeskus. Jokainen
## salama näyttää pienen ennakkorenkaan, joten voimakas sarja on myös väistettävissä.
func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 620.0


func _ult_default_range() -> float:
	return 380.0


func _ult_target_radius() -> float:
	return 245.0


func _ultimate(dir: Vector2) -> void:
	var center := aimed_ult_ground_position(dir)
	center = arena.map.clamp_to_field(center, 86.0)
	arena.popup(global_position + Vector2(0, -84), "UKKOSMYRSKY!", Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("volt_ult", 0.03, -2.0, center)
	Fx.ultimate_warning(arena, center, hero_color(), Palette.team(team), 245.0, 0.48, "volt")
	_thunderstorm(center)


func _thunderstorm(center: Vector2) -> void:
	await get_tree().create_timer(0.48).timeout
	if not is_inside_tree():
		return
	Fx.ultimate_field(arena, center, hero_color(), Palette.team(team), 245.0, 3.05, "volt")
	for strike in range(7):
		if not is_inside_tree():
			return
		var enemies: Array = arena.alive_enemies(team)
		enemies = enemies.filter(
			func(e): return e.global_position.distance_to(center) < 245.0 + e.radius)
		var strike_pos: Vector2
		if not enemies.is_empty():
			var target: Hero = enemies[randi() % enemies.size()]
			strike_pos = target.global_position
		else:
			var a := TAU * float(strike) / 7.0 + 0.45
			strike_pos = center + Vector2(cos(a), sin(a)) * (70.0 + 18.0 * float(strike % 3))
		Fx.ring(arena, strike_pos, Palette.glow(hero_color(), 1.55), 58.0, 0.18, 3.0)
		await get_tree().create_timer(0.16).timeout
		if not is_inside_tree():
			return
		_act("ult")
		Fx.bolt(arena, strike_pos + Vector2(0, -180), strike_pos, Palette.glow(hero_color(), 1.7))
		Fx.flash(arena, strike_pos, Palette.glow(hero_color(), 1.7), 58.0, 0.28)
		AudioMgr.play("zap", 0.2, float(strike) * 0.35 - 2.0, strike_pos)
		arena.shake(0.2)
		for enemy in arena.heroes_in_circle(strike_pos, 58.0):
			if enemy.team == team:
				continue
			deal_damage_to(enemy, 24.0, 180.0, (enemy.global_position - strike_pos).normalized())
			enemy.apply_stun(0.22)
		_act_end()
		await get_tree().create_timer(0.27).timeout
func _aimed_slots() -> Array:
	return ["a2"]


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_range(_slot: String) -> float:
	return 540.0


func _aim_default_range(_slot: String) -> float:
	return 260.0


func _aim_target_radius(_slot: String) -> float:
	return 130.0


## Tasoskaalaus: mage-hypercarry — ketjusalamat skaalautuvat kovimmin.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 1.10, "spell": 1.35, "melee": 0.95, "regen": 1.00}


## Väistön kehitys: vauhti (kelamestari kiertää taistelun reunaa).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Ketjusalama ensin, salamakenttä toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]
