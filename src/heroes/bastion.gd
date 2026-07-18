class_name Bastion
extends Hero
## Tankki: kilpi ja nuija. Rintaman kallio — suojaa joukkuetta edestä,
## hallitsee aluetta ja pystyttää kentälle turvakupolin.
## Passiivi: vastustaa tönäisyjä ja saa hetkellisen suojan torjuessaan.

const SWING_RANGE := 94.0
const SWING_ARC_DEG := 72.0
const SWING_DMG := 22.0

func _init() -> void:
	kb_resist = 0.55
	radius = 30.0


## Perushyökkäys: leveä nuijan pyyhkäisy eteen.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.1, -3.0)
	Fx.slash(arena, global_position, dir, SWING_RANGE, SWING_ARC_DEG, hero_color())
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


## Kyky 1: Kilpivalli — torjuu edestä tulevat osumat 2,6 s ajan.
func _ability1(dir: Vector2) -> void:
	start_guard(2.6, 0.78, 85.0)
	AudioMgr.play("guard_up")
	# Etukilven välähdys ja suojarengas
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.5), radius + 22.0, 0.4, 6.0)
	Fx.flash(arena, global_position + dir * (radius + 10.0),
		Palette.glow(Palette.SHIELD, 1.3), 40.0, 0.3)
	visual.squash(1.1, 0.92)


## Kyky 2: Maanjäristys — vahinko, työntö ja hidastus ympärillä.
func _ability2(_dir: Vector2) -> void:
	visual.squash(1.35, 0.65)
	AudioMgr.play("quake")
	arena.shake(0.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 185.0, 0.55, 9.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.6), 120.0, 0.4, 5.0)
	Fx.dust(arena, global_position)
	# Säteittäiset halkeamat
	for i in range(8):
		var ang := TAU * i / 8.0 + randf() * 0.2
		Fx.spark(arena, global_position + Vector2(cos(ang), sin(ang)) * 90.0, Color("6b5a3a"))
	for enemy in arena.heroes_in_circle(global_position, 185.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 20.0, 360.0)
		enemy.apply_slow(0.55, 1.8)


## Väistö: raskas rynnäkkö, joka tönäisee osuessaan.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 800.0, 0.22, false)
	AudioMgr.play("dash", 0.1, -3.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position + dir * 50.0, 72.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 8.0, 400.0, dir)


## Ultimate: Linnake — suuri kupoli, joka torjuu vihollisammukset ja
## antaa sisällä oleville liittolaisille suojakilven.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "LINNAKE!", Palette.glow(Palette.SHIELD, 1.4), 26)
	AudioMgr.play("dome_up")
	arena.shake(0.25)
	Zone.spawn(self, global_position, {
		"type": "dome",
		"radius": 240.0,
		"dur": 5.5,
	})
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.6), 240.0, 0.7, 8.0)
	for ally in arena.heroes_in_circle(global_position, 240.0, team):
		ally.add_shield(45.0, 4.5, self)


## Passiivi: saa hetkellisen pikkusuojan aina torjuessaan kilvellä.
func _passive_update(_delta: float) -> void:
	if guard_timer > 0.0 and shield_hp <= 0.0 and since_damage < 0.2:
		shield_hp = 14.0
		shield_timer = 1.5
		shield_source = self
