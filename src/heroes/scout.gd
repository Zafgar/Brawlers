class_name Scout
extends Hero
## Ranger: vaahtopallokivääri. Merkitsee kohteet, jolloin koko joukkue
## tekee niihin lisävahinkoa. Passiivi: väistö lataa kiväärin heti.

func _init() -> void:
	radius = 23.0


## Perushyökkäys: kolmen vaahtopallon purske.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	_burst_fire(dir)


func _burst_fire(dir: Vector2) -> void:
	for shot in range(3):
		if not is_inside_tree() or not alive:
			return
		AudioMgr.play("bow", 0.2, -8.0)
		var spread := randf_range(-0.06, 0.06)
		Projectile.launch(self, global_position + dir * 28.0, dir.rotated(spread), {
			"speed": 980.0,
			"dmg": 6.0,
			"radius": 7.0,
			"life": 0.7,
			"kb": 70.0,
			"color": hero_color(),
		})
		await get_tree().create_timer(0.07).timeout


## Kyky 1: Merkkipanos — osuma merkitsee kohteen.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("bow", 0.08, -2.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 1200.0,
		"dmg": 10.0,
		"radius": 8.0,
		"life": 0.9,
		"kb": 100.0,
		"color": Palette.glow(Palette.GOLD, 1.3),
		"on_hit": Callable(self, "_mark_target"),
	})


func _mark_target(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	hit_hero.apply_mark(4.0)
	AudioMgr.play("score", 0.1)
	Fx.ring(arena, hit_hero.global_position, Palette.glow(Palette.GOLD, 1.5), 50.0, 0.4)


## Kyky 2: Tainnutuspallo — tahmea vaahtopallo.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("bow", 0.08, -1.0)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 850.0,
		"dmg": 8.0,
		"radius": 11.0,
		"life": 0.8,
		"kb": 60.0,
		"color": Color("f2f5ff"),
		"on_hit": Callable(self, "_stun_target"),
	})


func _stun_target(hit_hero: Hero, _proj: Projectile) -> void:
	if hit_hero == null or not is_instance_valid(hit_hero):
		return
	hit_hero.apply_stun(0.8)
	Fx.burst(arena, hit_hero.global_position, Color(1, 1, 1, 0.8), 12, 200.0, 0.4, 5.0)


## Väistö: kierähdys, joka lataa kiväärin.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	cd.basic = 0.0
	AudioMgr.play("dash")
	Fx.dust(arena, global_position)


## Ultimate: Merkkisade — merkitsee kaikki lähiviholliset ja kiihdyttää joukkueen.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "MERKKISADE!", Palette.glow(Palette.GOLD, 1.5), 24)
	AudioMgr.play("ult_ready", 0.05)
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.6), 640.0, 0.7, 6.0)
	for enemy in arena.alive_enemies(team):
		if enemy.global_position.distance_to(global_position) < 640.0:
			enemy.apply_mark(5.0)
	for ally in arena.alive_allies(team):
		ally.apply_haste(1.2, 3.0)
