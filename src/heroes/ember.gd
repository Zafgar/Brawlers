class_name Ember
extends Hero
## Mage: tulilyhty. Alueiden hallitsija — sytyttää kentän palamaan ja
## pakottaa viholliset liikkeelle.
## Passiivi: perusosumat ja lämpöaalto sytyttävät jälkipolton.

const BURN_TICK := 4.0
const BURN_TICKS := 3

func _init() -> void:
	radius = 24.0


## Liekkilammikko tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 520.0


func _ground_targeted_slots() -> Array:
	return ["a1"]


func _aim_default_range(_slot: String) -> float:
	return 360.0


func _aim_target_radius(_slot: String) -> float:
	return 118.0


## Mana: loitsut maksavat manaa mutta latautuvat lähes heti — voit späm­mätä
## kykyjä kunnes mana loppuu, sitten se palautuu tasaisesti.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 15.0
	res_cost = {"basic": 0.0, "a1": 32.0, "a2": 26.0, "dodge": 0.0}
	cd_max.a1 = 0.6
	cd_max.a2 = 0.5


## Perushyökkäys: tulipallo, joka jättää osuessaan jälkipolton.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("ember_bolt", 0.1, -4.0, global_position)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Color("ffb347"), 1.6))
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 880.0,
		"dmg": 21.0,
		"radius": 12.0,
		"life": 0.95,
		"kb": 120.0,
		"color": Color("ff8a4a"),
		"visual": "ember_bolt",
		"on_hit": Callable(self, "_ignite"),
	})


func _ignite(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	# _cast_context on nyt sytyttänyt kyky (ammuksen slot: perus tai a2).
	_burn_ticks(hit_hero, _cast_context)


## Toistuva jälkipoltto kohteeseen. slot = sytyttänyt kyky, jotta jälkipolton
## vahinko kirjautuu oikealle kykypaikalle (re-asetetaan konteksti joka tickillä).
func _burn_ticks(target: Hero, slot: String) -> void:
	for i in range(BURN_TICKS):
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree() or not is_instance_valid(target) or not target.alive:
			return
		if target.team == team:
			return
		_act(slot)
		deal_damage_to(target, BURN_TICK)
		_act_end()
		Fx.spark(target.arena, target.global_position, Color("ff8a4a"))


## Kyky 1: Liekkilammikko — heittää palavan alueen tähtäyksen suuntaan.
func _ability1(dir: Vector2) -> void:
	var target := aimed_ground_position(dir, 520.0, 360.0)
	var travel := target - global_position
	var fire_dir := travel.normalized() if travel.length() > 1.0 else dir.normalized()
	AudioMgr.play("ember_pool", 0.05, 1.0, global_position)
	ability_signature("ember", 135.0, fire_dir)
	controller_rumble(0.12, 0.05, 0.14)
	Projectile.launch(self, global_position + fire_dir * 30.0, fire_dir, {
		"speed": 700.0,
		"dmg": 10.0,
		"radius": 12.0,
		"life": maxf(travel.length() - 30.0, 20.0) / 700.0,
		"kb": 60.0,
		"color": Color("ffb347"),
		"visual": "ember_seed",
		"on_hit": Callable(self, "_pool_on_hit"),
		"on_expire": Callable(self, "_spawn_fire_pool"),
	})


func _pool_on_hit(hit_hero: Hero, proj: Projectile) -> void:
	if hit_hero != null:
		_spawn_fire_pool(proj.global_position)


func _spawn_fire_pool(pos: Vector2) -> void:
	if arena == null or not is_inside_tree():
		return
	AudioMgr.play("ember_impact", 0.08, -2.0, pos)
	Zone.spawn(self, arena.map.clamp_to_field(pos, 80.0), {
		"type": "fire",
		"radius": 118.0,
		"dur": 4.5,
		"visual": "ember_pool",
		"dps": 13.0,   # nerf (sim2: ember 74% voitto, a1-liekkialue oli päävahingon lähde): 16 -> 13
	})
	arena.shake(0.15)


## Kyky 2: Lämpöaalto — kartiopurkaus eteen: vahinko, työntö ja jälkipoltto.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("ember_wave", 0.05, 0.0, global_position)
	ability_signature("ember", 215.0, dir)
	controller_rumble(0.2, 0.10, 0.2)
	visual.squash(1.3, 0.75)
	arena.shake(0.22)
	# Viuhkamainen liekkipurkaus
	for angle_offset in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		Fx.burst(arena, global_position + dir.rotated(angle_offset) * 120.0,
			Palette.glow(Color("ff8a4a"), 1.6), 6, 260.0, 0.4, 6.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > 215.0 + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > 45.0:
			continue
		deal_damage_to(enemy, 22.0, 470.0, to_enemy.normalized())
		_burn_ticks(enemy, _cast_context)


## Väistö: kipinäliuku, joka jättää lyhyen palojäljen.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.15, true)
	AudioMgr.play("dash", 0.12, 2.0, global_position)
	Fx.burst(arena, global_position, Palette.glow(Color("ffb347"), 1.5), 10, 160.0, 0.5, 4.0)


## Ultimate: Tulimyrsky — laajeneva liekkirengas, joka jättää lammikoita.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "TULIMYRSKY!", Palette.glow(Color("ff8a4a"), 1.5), 26)
	AudioMgr.play("ember_ult", 0.03, 1.0, global_position)
	controller_rumble(0.35, 0.55, 0.55)
	arena.shake(0.5)
	_firestorm()


func _firestorm() -> void:
	var origin := global_position
	for step in range(3):
		if not is_inside_tree() or not alive:
			return
		var r := 120.0 + step * 90.0
		Fx.ring(arena, origin, Palette.glow(Color("ff8a4a"), 1.8), r, 0.45, 9.0)
		Fx.ring(arena, origin, Palette.with_alpha(Color("ffd76d"), 0.5), r * 0.7, 0.4, 5.0)
		AudioMgr.play("ember_impact", 0.1, -2.0, origin)
		arena.shake(0.2)
		for enemy in arena.heroes_in_circle(origin, r):
			if enemy.team == team:
				continue
			deal_damage_to(enemy, 16.0, 280.0,
				(enemy.global_position - origin).normalized())
		Zone.spawn(self, origin + Vector2(randf_range(-r, r) * 0.5, randf_range(-r, r) * 0.5), {
			"type": "fire",
			"radius": 95.0,
			"dur": 3.0,
			"dps": 14.0,
			"visual": "ember_storm",
		})
		await get_tree().create_timer(0.4).timeout


## Tasoskaalaus: mage-hypercarry — loitsuvahinko skaalautuu kovaa.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 1.05, "spell": 1.30, "melee": 0.95, "regen": 1.00}


## Väistön kehitys: vauhti (alueiden hallitsija pitää etäisyyden).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Liekkilammikko ensin, lämpöaalto toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]
