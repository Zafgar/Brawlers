class_name Bastion
extends Hero
## Tankki: kilpi ja nuija. Suojaa joukkuetta edestä, hallitsee aluetta.
## Passiivi: vastustaa tönäisyjä ja saa vähän suojaa osumista.

const SWING_RANGE := 88.0
const SWING_ARC_DEG := 70.0
const SWING_DMG := 22.0

func _init() -> void:
	kb_resist = 0.55
	radius = 30.0


## Perushyökkäys: leveä nuijan heilautus eteen.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing")
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SWING_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SWING_ARC_DEG:
			continue
		deal_damage_to(enemy, SWING_DMG, 260.0, to_enemy.normalized())
		hits += 1
	if hits > 0:
		arena.shake(0.12)
		Fx.spark(arena, global_position + dir * SWING_RANGE * 0.7, hero_color())


## Kyky 1: Kilpivalli — torjuu edestä tulevat osumat.
func _ability1(_dir: Vector2) -> void:
	start_guard(2.5, 0.75, 80.0)
	AudioMgr.play("shield")
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.4), radius + 20.0, 0.4)


## Kyky 2: Maanjäristys — vahinko ja hidastus ympärillä.
func _ability2(_dir: Vector2) -> void:
	visual.squash(1.3, 0.7)
	AudioMgr.play("slam")
	arena.shake(0.3)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 170.0, 0.5, 8.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position, 170.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 18.0, 320.0)
		enemy.apply_slow(0.55, 1.6)


## Väistö: raskas rynnäkkö, joka tönäisee osuessaan.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 780.0, 0.22, false)
	AudioMgr.play("dash")
	Fx.dust(arena, global_position)
	# Tönäisy syöksyn alussa lähellä oleville
	for enemy in arena.heroes_in_circle(global_position + dir * 50.0, 70.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 8.0, 380.0, dir)


## Ultimate: Linnake — suuri kupoli, joka torjuu vihollisammukset
## ja rauhoittaa alueen joukkueelle.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -80), "LINNAKE!", Palette.glow(Palette.SHIELD, 1.3), 24)
	Zone.spawn(self, global_position, {
		"type": "dome",
		"radius": 240.0,
		"dur": 5.0,
	})
	# Pieni suoja kaikille kuplan sisällä oleville liittolaisille heti.
	for ally in arena.heroes_in_circle(global_position, 240.0, team):
		ally.add_shield(40.0, 4.0, self)


## Passiivi: saa pienen suojan aina kun torjuu vahinkoa kilpivallilla.
func _passive_update(_delta: float) -> void:
	if guard_timer > 0.0 and shield_hp <= 0.0 and since_damage < 0.2:
		shield_hp = 12.0
		shield_timer = 1.5
		shield_source = self
