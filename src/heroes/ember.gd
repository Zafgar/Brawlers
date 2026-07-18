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
	return 360.0


## Perushyökkäys: tulipallo, joka jättää osuessaan jälkipolton.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("fire", 0.12)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Color("ffb347"), 1.6))
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 880.0,
		"dmg": 21.0,
		"radius": 12.0,
		"life": 0.95,
		"kb": 120.0,
		"color": Color("ff8a4a"),
		"on_hit": Callable(self, "_ignite"),
	})


func _ignite(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	_burn_ticks(hit_hero)


## Toistuva jälkipoltto kohteeseen.
func _burn_ticks(target: Hero) -> void:
	for i in range(BURN_TICKS):
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree() or not is_instance_valid(target) or not target.alive:
			return
		if target.team == team:
			return
		deal_damage_to(target, BURN_TICK)
		Fx.spark(target.arena, target.global_position, Color("ff8a4a"))


## Kyky 1: Liekkilammikko — heittää palavan alueen tähtäyksen suuntaan.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("fire", 0.05, 2.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 700.0,
		"dmg": 10.0,
		"radius": 12.0,
		"life": 360.0 / 700.0,
		"kb": 60.0,
		"color": Color("ffb347"),
		"on_hit": Callable(self, "_pool_on_hit"),
		"on_expire": Callable(self, "_spawn_fire_pool"),
	})


func _pool_on_hit(hit_hero: Hero, proj: Projectile) -> void:
	if hit_hero != null:
		_spawn_fire_pool(proj.global_position)


func _spawn_fire_pool(pos: Vector2) -> void:
	if arena == null or not is_inside_tree():
		return
	AudioMgr.play("fire", 0.1, -2.0)
	Zone.spawn(self, arena.map.clamp_to_field(pos, 80.0), {
		"type": "fire",
		"radius": 118.0,
		"dur": 4.5,
		"dps": 16.0,
	})
	arena.shake(0.15)


## Kyky 2: Lämpöaalto — kartiopurkaus eteen: vahinko, työntö ja jälkipoltto.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("fire_whoosh")
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
		_burn_ticks(enemy)


## Väistö: kipinäliuku, joka jättää lyhyen palojäljen.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.15, true)
	AudioMgr.play("dash", 0.12, 2.0)
	Fx.burst(arena, global_position, Palette.glow(Color("ffb347"), 1.5), 10, 160.0, 0.5, 4.0)


## Ultimate: Tulimyrsky — laajeneva liekkirengas, joka jättää lammikoita.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "TULIMYRSKY!", Palette.glow(Color("ff8a4a"), 1.5), 26)
	AudioMgr.play("inferno")
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
		AudioMgr.play("fire", 0.1)
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
		})
		await get_tree().create_timer(0.4).timeout
