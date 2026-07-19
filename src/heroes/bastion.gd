class_name Bastion
extends Hero
## Tankki: kilpi ja nuija. Rintaman kallio — suojaa joukkuetta edestä,
## hallitsee aluetta ja pystyttää kentälle turvakupolin.
## Passiivi: vastustaa tönäisyjä ja saa hetkellisen suojan torjuessaan.

const SWING_RANGE := 94.0
const SWING_ARC_DEG := 72.0
const SWING_DMG := 13.0

# Kilpivallin ammustorjunta: iso etukaari, joka syö vihollisammukset ja
# suojaa myös takana olevia liittolaisia (ei anna heille kilpeä, torjuu vain).
const BLOCK_RADIUS := 250.0
const BLOCK_ARC_DEG := 130.0

# Vetoisku (a2): vetää ympäröivät viholliset eteen ja tainnuttaa, ei vahinkoa.
const PULL_RADIUS := 220.0
const PULL_FRONT_DIST := 92.0
const PULL_SPEED := 1000.0
const PULL_DUR := 0.2
const PULL_STUN := 0.8

func _init() -> void:
	kb_resist = 0.55
	radius = 30.0


## Energia: Kilpivalli (R1) kanavoidaan pitämällä nappi pohjassa. Kilpi torjuu
## suurimman osan vahingosta ja kuluttaa energiaa sen mukaan paljonko otat
## osumaa (+ pieni peruskulutus). Energia palautuu kun kilpi ei ole ylhäällä.
## Botit käyttävät yhä kertakäyttöistä ajastettua kilpeä (_ability1).
func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = 100.0
	res_regen = 12.0


func _channeled_slots() -> Array:
	return ["a1"]


func _channel_tick(_slot: String, delta: float) -> void:
	# Ylläpidä leveä kiinteä kilpivalli edessä niin kauan kuin energiaa riittää.
	# guard_arc_deg on puolikaari -> BLOCK_ARC_DEG * 0.5, ja guard_radius tekee
	# kilvestä leveän vallin (hero_visual piirtää sen kiinteänä esteenä).
	start_guard(0.15, 0.9, BLOCK_ARC_DEG * 0.5, BLOCK_RADIUS)
	res = maxf(res - 8.0 * delta, 0.0)
	if res <= 0.0:
		guard_timer = 0.0   # energia loppui -> kilpi putoaa heti
		return
	# Iso etukilpi torjuu vihollisammukset -> takana olevat liittolaiset suojassa.
	_block_front_projectiles()


## Torjuu vihollisammukset isolla etukaarella (ei kosketa taakse jääviä).
func _block_front_projectiles() -> void:
	for child in arena.get_children():
		if not child is Projectile:
			continue
		var proj := child as Projectile
		if proj.team == team:
			continue
		var to: Vector2 = proj.global_position - global_position
		if to.length() > BLOCK_RADIUS or to.dot(aim) <= 0.0:
			continue
		if absf(rad_to_deg(aim.angle_to(to))) > BLOCK_ARC_DEG * 0.5:
			continue
		# Torju ammus.
		profile.stats.prevented += proj.dmg
		profile.add_score(proj.dmg * 0.08)
		Fx.spark(arena, proj.global_position, Palette.glow(Palette.SHIELD, 1.5))
		Fx.ring(arena, proj.global_position, Palette.with_alpha(Palette.SHIELD, 0.8), 20.0, 0.2, 3.0)
		AudioMgr.play("shield", 0.15, 3.0)
		proj.queue_free()


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
	start_guard(2.8, 0.85, 92.0)
	AudioMgr.play("guard_up")
	# Etukilven välähdys ja suojarengas
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.5), radius + 22.0, 0.4, 6.0)
	Fx.flash(arena, global_position + dir * (radius + 10.0),
		Palette.glow(Palette.SHIELD, 1.3), 40.0, 0.3)
	visual.squash(1.1, 0.92)


## Kyky 2: Vetoisku — vetää ympäröivät viholliset eteen ja tainnuttaa. Ei tee
## vahinkoa, mutta kerää viholliset facing-suuntaan Bastionin eteen, jotta hän
## voi hallita taistelua (esim. kilpivallin taakse kerätyt liittolaiset turvaan).
func _ability2(dir: Vector2) -> void:
	visual.squash(1.25, 0.75)
	AudioMgr.play("quake", 0.05, 1.0)
	arena.shake(0.3)
	var front: Vector2 = global_position + dir * PULL_FRONT_DIST
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.4), PULL_RADIUS, 0.5, 7.0)
	Fx.ring(arena, front, Palette.glow(hero_color(), 1.4), 70.0, 0.4, 5.0)
	Fx.dust(arena, front)
	for enemy in arena.heroes_in_circle(global_position, PULL_RADIUS):
		if enemy.team == team:
			continue
		# Vedä kohde eteen (syöksy kohti etupistettä) ja tainnuta — ei vahinkoa.
		var toward: Vector2 = (front - enemy.global_position)
		if toward.length() < 1.0:
			toward = dir
		enemy.dash(toward.normalized(), PULL_SPEED, PULL_DUR, false)
		enemy.apply_stun(PULL_STUN)
		Fx.spark(arena, enemy.global_position, Palette.glow(Palette.SHIELD, 1.4))
		Fx.beam(arena, enemy.global_position, front, Palette.with_alpha(Palette.SHIELD, 0.5), 3.0)


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
		ally.add_shield(65.0, 4.5, self)


## Passiivi: saa hetkellisen pikkusuojan aina torjuessaan kilvellä.
func _passive_update(_delta: float) -> void:
	if guard_timer > 0.0 and shield_hp <= 0.0 and since_damage < 0.2:
		shield_hp = 24.0
		shield_timer = 1.5
		shield_source = self
