class_name Ember
extends Hero
## Mage: tulilyhty. Hallitsee aluetta palavilla lammikoilla.
## Passiivi: perusosumat sytyttävät pienen jälkipolton.

const BURN_DPS := 6.0

func _init() -> void:
	radius = 24.0


## Perushyökkäys: tulipallo, joka jättää osuessaan jälkipolton.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("fire")
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 860.0,
		"dmg": 16.0,
		"radius": 11.0,
		"life": 0.95,
		"kb": 120.0,
		"color": Color("ff8a4a"),
		"on_hit": Callable(self, "_ignite"),
	})


func _ignite(hero: Hero, _proj: Projectile) -> void:
	# Pieni jälkipoltto: kolme tikkiä.
	if hero == null or not is_instance_valid(hero):
		return
	_burn_ticks(hero)


func _burn_ticks(hero: Hero) -> void:
	for i in range(3):
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree() or not is_instance_valid(hero) or not hero.alive:
			return
		deal_damage_to(hero, BURN_DPS * 0.5)


## Kyky 1: Liekkilammikko tähtäyksen suuntaan.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("fire")
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 700.0,
		"dmg": 8.0,
		"radius": 12.0,
		"life": 340.0 / 700.0,
		"kb": 60.0,
		"color": Color("ffb347"),
		"on_hit": Callable(self, "_pool_on_hit"),
		"on_expire": Callable(self, "_spawn_fire_pool"),
	})


func _pool_on_hit(hero: Hero, proj: Projectile) -> void:
	if hero != null:
		_spawn_fire_pool(proj.global_position)


func _spawn_fire_pool(pos: Vector2) -> void:
	if arena == null or not is_inside_tree():
		return
	Zone.spawn(self, arena.map.clamp_to_field(pos, 80.0), {
		"type": "fire",
		"radius": 110.0,
		"dur": 4.0,
		"dps": 16.0,
	})
	arena.shake(0.15)


## Kyky 2: Lämpöaalto — kartiopurkaus eteen, vahinko ja työntö.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("slam")
	visual.squash(1.25, 0.8)
	arena.shake(0.2)
	Fx.burst(arena, global_position + dir * 60.0, Palette.glow(Color("ff8a4a"), 1.7), 20, 380.0, 0.4, 6.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > 210.0 + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > 45.0:
			continue
		deal_damage_to(enemy, 20.0, 460.0, to_enemy.normalized())


## Väistö: kipinäliuku, joka jättää lyhyen kipinäjäljen.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.15, true)
	AudioMgr.play("dash")
	Fx.burst(arena, global_position, Palette.glow(Color("ffb347"), 1.5), 10, 160.0, 0.5, 4.0)


## Ultimate: Tulimyrsky — laajeneva liekkirengas Emberin ympärillä.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "TULIMYRSKY!", Palette.glow(Color("ff8a4a"), 1.4), 24)
	arena.shake(0.5)
	_firestorm()


func _firestorm() -> void:
	var origin := global_position
	for step in range(3):
		var r := 120.0 + step * 90.0
		Fx.ring(arena, origin, Palette.glow(Color("ff8a4a"), 1.8), r, 0.45, 9.0)
		AudioMgr.play("fire")
		for enemy in arena.heroes_in_circle(origin, r):
			if enemy.team == team:
				continue
			deal_damage_to(enemy, 16.0, 260.0,
				(enemy.global_position - origin).normalized())
		Zone.spawn(self, origin + Vector2(randf_range(-r, r) * 0.5, randf_range(-r, r) * 0.5), {
			"type": "fire",
			"radius": 90.0,
			"dur": 3.0,
			"dps": 14.0,
		})
		await get_tree().create_timer(0.4).timeout
		if not is_inside_tree() or not alive:
			return
