class_name Bramble
extends Hero
## Fighter: köynnösruoska. Sitoo viholliset paikoilleen ja hallitsee
## lähialuetta piikkialueilla.
## Passiivi: elämänvarkaus — osumat parantavat Bramblea hieman.

const WHIP_RANGE := 125.0
const WHIP_ARC_DEG := 55.0
const WHIP_DMG := 16.0
const LIFESTEAL := 0.2

func _init() -> void:
	radius = 27.0
	kb_resist = 0.25


## Perushyökkäys: ruoskan pyyhkäisy kaaressa.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.1, -1.0)
	var total_dealt := 0.0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > WHIP_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > WHIP_ARC_DEG:
			continue
		total_dealt += deal_damage_to(enemy, WHIP_DMG, 190.0, to_enemy.normalized())
	if total_dealt > 0.0:
		hp = minf(hp + total_dealt * LIFESTEAL, max_hp)
		Fx.heal_sparkle(arena, global_position)


## Kyky 1: Juurisidonta — köynnös, joka juurruttaa ensimmäisen osuman.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("swing", 0.1)
	Projectile.launch(self, global_position + dir * 30.0, dir, {
		"speed": 900.0,
		"dmg": 8.0,
		"radius": 10.0,
		"life": 0.75,
		"kb": 60.0,
		"color": Color("7ed957"),
		"on_hit": Callable(self, "_root_target"),
	})


func _root_target(hero: Hero, _proj: Projectile) -> void:
	if hero == null or not is_instance_valid(hero) or not hero.alive:
		return
	hero.apply_root(1.4)
	Fx.spark(arena, hero.global_position, Color("7ed957"))


## Kyky 2: Piikkipyörre — piikit sinkoutuvat ympärille ja jäävät maahan.
func _ability2(_dir: Vector2) -> void:
	visual.squash(1.3, 0.7)
	arena.shake(0.25)
	AudioMgr.play("slam", 0.1, -2.0)
	Fx.ring(arena, global_position, Palette.glow(Color("7ed957"), 1.5), 150.0, 0.45, 7.0)
	for enemy in arena.heroes_in_circle(global_position, 150.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 14.0, 280.0)
	Zone.spawn(self, global_position, {
		"type": "thorn",
		"radius": 120.0,
		"dur": 2.5,
		"dps": 8.0,
		"slow_f": 0.75,
	})


## Väistö: köynnösheitto — vetäisee itsensä vauhdilla eteenpäin.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 900.0, 0.18, false)
	AudioMgr.play("dash", 0.1, -2.0)
	Fx.dust(arena, global_position)


## Ultimate: Piikkipuutarha — suuri piikkialue, joka juurruttaa heti
## sisällä olevat viholliset.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "PIIKKIPUUTARHA!", Palette.glow(Color("7ed957"), 1.5), 24)
	arena.shake(0.4)
	AudioMgr.play("slam")
	Zone.spawn(self, global_position, {
		"type": "thorn",
		"radius": 300.0,
		"dur": 6.0,
		"dps": 10.0,
		"slow_f": 0.65,
	})
	for enemy in arena.heroes_in_circle(global_position, 300.0):
		if enemy.team == team:
			continue
		enemy.apply_root(0.8)
