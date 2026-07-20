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
	res_cost = {"basic": 0.0, "a1": 34.0, "a2": 34.0, "dodge": 0.0}   # a1 30->34 (nerf 2: harvempi spämmi)
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
		"on_hit": Callable(self, "_spark_jump"),
	})


func _spark_jump(hit_hero: Hero, proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	add_ult(4.0)
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
	# Nerf 2 (sim2: volt yhä 920 vah/min = 2.2x ka, 73% voitto; a1 tuotti 139k
	# vahinkoa + 78 866 s hidastusta -> 93% arvosta oli kontrollia). Ketju 3->2,
	# lyhyempi hidastus (0.55->0.45s). Vahinko pysyy 18 (24->18 oli nerf 1).
	var dmg := 18.0
	while target != null and chain.size() < 2:
		Fx.bolt(arena, from, target.global_position, hero_color())
		Fx.flash(arena, target.global_position, Palette.glow(hero_color(), 1.5), 38.0, 0.25)
		deal_damage_to(target, dmg, 120.0, (target.global_position - from).normalized())
		target.apply_slow(0.85, 0.45)
		chain.append(target)
		from = target.global_position
		dmg *= 0.8
		target = _nearest_enemy(from, 300.0, chain)


## Kyky 2: Sähkökenttä — rätisevä hidastava alue.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("zap", 0.15, -5.0)
	var pos: Vector2 = arena.map.clamp_to_field(global_position + dir * 260.0, 80.0)
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


## Ultimate: Ukkosmyrsky — viisi salamaa lähivihollisiin.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "UKKOSMYRSKY!", Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("thunder")
	_thunderstorm()


func _thunderstorm() -> void:
	for strike in range(5):
		if not is_inside_tree() or not alive:
			return
		var enemies: Array = arena.alive_enemies(team)
		enemies = enemies.filter(
			func(e): return e.global_position.distance_to(global_position) < 620.0)
		if not enemies.is_empty():
			var target: Hero = enemies[randi() % enemies.size()]
			Fx.bolt(arena, global_position + Vector2(0, -60), target.global_position, hero_color())
			Fx.flash(arena, target.global_position, Palette.glow(hero_color(), 1.7), 54.0, 0.28)
			AudioMgr.play("zap", 0.2, -2.0)
			arena.shake(0.18)
			deal_damage_to(target, 22.0, 180.0)
			target.apply_stun(0.25)
		await get_tree().create_timer(0.35).timeout
