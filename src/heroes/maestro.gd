class_name Maestro
extends Hero
## Tuki: ääniaaltoheitin. Kiihdyttää ja suojaa joukkuetta.
## Passiivi: lähellä olevien liittolaisten ultimate latautuu nopeammin.

func _init() -> void:
	radius = 24.0


## Perushyökkäys: työntävä ääniaalto.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("bow", 0.2, -7.0)
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 820.0,
		"dmg": 10.0,
		"radius": 11.0,
		"life": 0.6,
		"kb": 220.0,
		"color": hero_color(),
	})


## Kyky 1: Kiihdytysriffi — vauhtia ja suojaa lähiliittolaisille.
func _ability1(_dir: Vector2) -> void:
	AudioMgr.play("heal", 0.1, -2.0)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 240.0, 0.5, 6.0)
	for ally in arena.heroes_in_circle(global_position, 240.0, team):
		ally.apply_haste(1.35, 3.0)
		if ally != self:
			ally.add_shield(20.0, 2.5, self)
	visual.squash(1.2, 0.85)


## Kyky 2: Basso-isku — työntö ja lyhyt tainnutus eteen.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("slam", 0.1, -3.0)
	arena.shake(0.2)
	Fx.burst(arena, global_position + dir * 70.0, Palette.glow(hero_color(), 1.5), 16, 380.0, 0.4, 6.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > 200.0 + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > 50.0:
			continue
		deal_damage_to(enemy, 10.0, 520.0, to_enemy.normalized())
		enemy.apply_stun(0.35)


## Väistö: tahdinvaihto.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1050.0, 0.14, true)
	AudioMgr.play("dash", 0.12)


## Ultimate: Crescendo — suuri parantava ja kiihdyttävä alue.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "CRESCENDO!", Palette.glow(hero_color(), 1.5), 24)
	AudioMgr.play("round_win", 0.05, -2.0)
	Zone.spawn(self, global_position, {
		"type": "heal",
		"radius": 300.0,
		"dur": 5.0,
		"heal_ps": 14.0,
		"color": hero_color(),
	})
	Zone.spawn(self, global_position, {
		"type": "haste",
		"radius": 300.0,
		"dur": 5.0,
		"haste_f": 1.3,
	})
	for enemy in arena.heroes_in_circle(global_position, 300.0):
		if enemy.team != team:
			enemy.apply_slow(0.75, 2.0)


## Passiivi: lähiliittolaisten ulti latautuu nopeammin.
func _passive_update(delta: float) -> void:
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		if ally.global_position.distance_to(global_position) < 300.0:
			ally.add_ult(delta * 1.5)
