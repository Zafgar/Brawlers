class_name Maestro
extends Hero
## Tuki: ääniaaltoheitin. Kiihdyttää ja suojaa joukkuetta.
## Passiivi: lähellä olevien liittolaisten ultimate latautuu nopeammin.

func _init() -> void:
	radius = 24.0


## Mana: riffit ja bassoiskut maksavat manaa mutta jäähtyvät nopeasti — voit
## kiihdyttää ja suojata joukkuetta tiuhaan kunnes mana loppuu. Ääniaalto
## (perus) on ilmainen.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 14.0
	res_cost = {"basic": 0.0, "a1": 26.0, "a2": 30.0, "dodge": 0.0}
	cd_max.a1 = 1.4
	cd_max.a2 = 1.6


## Perushyökkäys: työntävä ääniaalto.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("note", 0.15, -4.0)
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 820.0,
		"dmg": 10.0,
		"radius": 11.0,
		"life": 0.6,
		"kb": 220.0,
		"color": hero_color(),
		"visual": "maestro_note",
	})


## Kyky 1: Kiihdytysriffi — vauhtia ja suojaa lähiliittolaisille.
func _ability1(_dir: Vector2) -> void:
	AudioMgr.play("note", 0.05, 2.0)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 240.0, 0.5, 6.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.6), 170.0, 0.4, 4.0)
	for ally in arena.heroes_in_circle(global_position, 240.0, team):
		ally.apply_haste(1.35, 3.0)
		if ally != self:
			ally.add_shield(20.0, 2.5, self)
			Fx.spark(arena, ally.global_position, Palette.glow(hero_color(), 1.4))
	visual.squash(1.2, 0.85)


## Kyky 2: Basso-isku — työntö ja lyhyt tainnutus eteen.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("bass")
	arena.shake(0.25)
	visual.squash(1.25, 0.8)
	Fx.burst(arena, global_position + dir * 70.0, Palette.glow(hero_color(), 1.5), 16, 380.0, 0.4, 6.0)
	# Bassoaalto kartion suuntaan
	for step in range(1, 4):
		Fx.ring(arena, global_position + dir * step * 55.0,
			Palette.with_alpha(Palette.glow(hero_color(), 1.4), 0.6), 40.0 + step * 20.0, 0.35, 4.0)
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
	AudioMgr.play("dash", 0.12, 2.0)


## Ultimate: Crescendo — suuri parantava ja kiihdyttävä alue.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "CRESCENDO!", Palette.glow(hero_color(), 1.5), 26)
	AudioMgr.play("crescendo")
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), 300.0, 0.7, 8.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.4), 120.0, 0.5)
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
			ally.add_ult(delta * 0.8)   # ultiakku skaalattu uuteen talouteen (oli 1.5)


## Tasoskaalaus: vauhtituki — buffit tärkeämpiä kuin oma vahinko.
func _level_scaling() -> Dictionary:
	return {"hp": 0.95, "damage": 0.80, "spell": 0.85, "melee": 0.80, "regen": 1.20}


## Väistön kehitys: vauhti (kapellimestari kiihdyttää itsensäkin).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Kiihdytysriffi ensin, bassoisku toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "dodge", "basic"]
