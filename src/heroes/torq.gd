class_name Torq
extends JungleHero
## MAGNEETTIVARTIJA. Torq vetää viholliset luokseen ja naulaa ne paikoilleen.
## Jokainen kyky liikuttaa vihollista: perusisku nykäisee, koukku raahaa,
## Napalukko imee koko rykelmän ja Napakenttä ei päästä ketään ulos.
## Vahinko on pieni — arvo on siinä, missä vihollinen seisoo.

const POLE_N := Color("ff5470")     # pohjoisnapa (punainen)
const POLE_S := Color("5ac8ff")     # etelänapa (sininen)
const STEEL := Color("c3ccdf")      # kiillotettu magneettiteräs

const BASIC_REACH := 148.0
const BASIC_DMG := 18.0
const BASIC_ARC := 0.36
const BASIC_TUG := 120.0            # perusiskun magneettinykäisy

const HOOK_RANGE := 640.0
const HOOK_DMG := 26.0
const HOOK_PULL := 900.0
const HOOK_PULL_CRITTER := 1180.0

const LOCK_RADIUS := 232.0
const LOCK_DMG := 25.0
const LOCK_PULL := 560.0
const LOCK_ROOT := 0.75
const LOCK_ROOT_CRITTER := 1.1
const LOCK_SHIELD := 26.0

const SLIDE_SPEED := 1060.0
const SLIDE_TIME := 0.22
const SLIDE_SHIELD := 74.0

const ULT_RADIUS := 300.0
const ULT_DUR := 6.5

var _field_glow := 0.0              # magneettikentän hehku hahmon ympärillä
var _hooked_t := 0.0                # koukku juuri osui (visuaalinen ketju)


func _init() -> void:
	radius = 25.0


func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = res_max
	res_regen = 7.0
	res_cost.a1 = 20.0
	res_cost.a2 = 30.0


func field_glow() -> float:
	return _field_glow


func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return HOOK_RANGE


## Perushyökkäys: Magneettivasara — leveä isku, joka nykäisee osuneen kohteen
## askeleen lähemmäs. Torqin luota on aina vaikea päästä pois.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("torq", 126.0, d)
	Fx.slash(arena, global_position, d, BASIC_REACH, 0.86, Palette.glow(POLE_S, 1.5))
	Fx.flash(arena, global_position + d * BASIC_REACH * 0.72,
		Palette.glow(STEEL, 1.5), 32.0, 0.16)
	AudioMgr.play("torq_hammer", 0.08, -8.0, global_position)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > BASIC_REACH + enemy.radius or dist < 1.0:
			continue
		if d.dot(off / dist) < BASIC_ARC:
			continue
		var dealt := deal_damage_to(enemy, BASIC_DMG)
		if dealt > 0.0:
			# Nykäisy sisäänpäin kb_velocity-impulssikanavan kautta.
			enemy.apply_knockback(-off / dist, BASIC_TUG)
			gain_res(8.0)
			_field_glow = maxf(_field_glow, 0.6)


## Kyky 1: Magneettikoukku — laukaisee magneettiankkurin. Ensimmäinen osuma
## raahataan Torqin eteen. Monsterit tulevat kovempaa ja tainnuttuvat hetkeksi.
func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("torq", 155.0, d)
	Projectile.launch(self, global_position + d * (radius + 9.0), d, {
		"speed": 1150.0, "dmg": HOOK_DMG, "radius": 13.0,
		"life": HOOK_RANGE / 1150.0, "kb": 0.0, "color": POLE_S,
		"visual": "torq_hook", "on_hit": Callable(self, "_hook_hit"),
	})
	AudioMgr.play("torq_hook", 0.08, -5.0, global_position)
	controller_rumble(0.22, 0.42, 0.12)


func _hook_hit(target: Hero, _projectile: Projectile) -> void:
	var pull: Vector2 = global_position - target.global_position
	if pull.length() > 1.0:
		# Vetovoima on jo viritetty kohdetyypin mukaan -> ohita kb_resist.
		target.apply_knockback(pull,
			HOOK_PULL_CRITTER if target is Critter else HOOK_PULL, false)
	if target is Critter:
		target.apply_stun(0.7)
	else:
		target.apply_slow(0.6, 1.0)
	_hooked_t = 0.5
	_field_glow = 1.0
	gain_res(12.0)
	# Ketju kiristyy: paksu magneettisäde ja napavälähdys tartuntapisteessä.
	Fx.beam(arena, global_position, target.global_position, Palette.glow(POLE_S, 1.6), 8.0)
	Fx.flash(arena, target.global_position, Palette.glow(POLE_N, 1.5), 40.0, 0.22)
	Fx.burst(arena, target.global_position, Palette.glow(STEEL, 1.5), 10, 220.0, 0.3, 3.5)
	AudioMgr.play("torq_hook_hit", 0.09, -5.0, target.global_position)
	controller_rumble(0.4, 0.62, 0.16)


## Kyky 2: Napalukko — Torq kääntää navat päälle. Kaikki ympärillä imaistaan
## kiinni ja JUURRUTETAAN paikoilleen. Tämä on Torqin varsinainen aloitus.
func _ability2(_dir: Vector2) -> void:
	ability_signature("torq", 195.0, aim)
	Fx.vortex(arena, global_position, Palette.glow(POLE_S, 1.55), LOCK_RADIUS, 0.6)
	Fx.ring(arena, global_position, Palette.glow(POLE_N, 1.5), LOCK_RADIUS, 0.5, 7.0)
	Fx.ring(arena, global_position, Palette.glow(POLE_S, 1.5), LOCK_RADIUS * 0.55, 0.42, 5.0)
	AudioMgr.play("torq_lock", 0.1, -4.0, global_position)
	AudioMgr.play("torq_hammer", 0.08, -9.0, global_position)
	arena.shake(0.22)
	controller_rumble(0.55, 0.8, 0.22)
	_field_glow = 1.0
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > LOCK_RADIUS + enemy.radius:
			continue
		var toward := -off / dist if dist > 1.0 else Vector2.UP
		# Imu keskelle: viritetty voima -> ohita kb_resist, muuten tankit
		# jäisivät renkaan reunalle eikä lukko lukitsisi mitään.
		enemy.apply_knockback(toward, LOCK_PULL, false)
		deal_damage_to(enemy, LOCK_DMG * (1.35 if enemy is Critter else 1.0))
		enemy.apply_root(LOCK_ROOT_CRITTER if enemy is Critter else LOCK_ROOT)
		Fx.beam(arena, global_position, enemy.global_position,
			Palette.with_alpha(POLE_S, 0.7), 4.0)
		hits += 1
	add_shield(LOCK_SHIELD + hits * 14.0, 3.2, self)


## Väistö: Magneettiliuku — Torq irrottaa navat maasta ja liukuu magneettisesti
## sivuun. Lyhyt osumattomuus ja kilpi; tankki saa vihdoin oikean pakoliikkeen.
func _dodge_action(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	dash(d, SLIDE_SPEED, SLIDE_TIME, true)
	add_shield(SLIDE_SHIELD, 3.0, self)
	_field_glow = 1.0
	ability_signature("torq", 140.0, d)
	Fx.ring(arena, global_position, Palette.glow(POLE_S, 1.5), 120.0, 0.4, 6.0)
	Fx.dust(arena, global_position)
	AudioMgr.play("shield", 0.1, -4.0, global_position)
	controller_rumble(0.35, 0.5, 0.16)


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 620.0


func _ult_default_range() -> float:
	return 360.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


## Ultimate: Napakenttä — valtava magneettikaivo. Sisällä olevia vedetään
## jatkuvasti keskustaan, ne hidastuvat rajusti ja juurtuvat pulssein.
## Kukaan ei kävele ulos: joko he kuolevat kentässä tai polttavat väistön.
func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	Fx.ultimate_warning(arena, target, Palette.glow(POLE_S, 1.6),
		Palette.team(team), ULT_RADIUS, 0.6, "torq")
	Fx.ultimate_field(arena, target, POLE_S, Palette.team(team),
		ULT_RADIUS, ULT_DUR, "torq")
	JungleField.spawn(self, target, "magnet", {
		"radius": ULT_RADIUS, "dur": ULT_DUR, "dps": 26.0, "tick": 0.4,
		"color": POLE_S,
	})
	# Kaksi vastakkaista napaa kertovat heti että kyseessä on magneettikaivo.
	for pole in [-1.0, 1.0]:
		Fx.flash(arena, target + Vector2(pole * ULT_RADIUS * 0.62, 0.0),
			Palette.glow(POLE_N if pole > 0.0 else POLE_S, 1.6), 66.0, 0.45)
	arena.popup(target + Vector2(0, -ULT_RADIUS - 26), "NAPAKENTTÄ!", POLE_S, 25)
	AudioMgr.play("torq_well", 0.12, -2.0, target)
	AudioMgr.play("torq_hook_hit", 0.09, -4.0, target)
	arena.shake(0.4)
	controller_rumble(0.7, 0.95, 0.35)
	_field_glow = 1.0


func _passive_update(delta: float) -> void:
	_field_glow = maxf(_field_glow - delta * 1.2, 0.0)
	_hooked_t = maxf(_hooked_t - delta, 0.0)


## Botti polttaa väistön silloin kun se oikeasti pelastaa: matala HP tai
## isokokoinen objective-taistelu käynnissä.
func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	return hp < max_hp * 0.5 or (is_instance_valid(target) and target is Critter \
		and (target as Critter).is_major_objective() and hp < max_hp * 0.75)


## Tasoskaalaus: kontrollitankki — kesto edellä, vahinko jää tarkoituksella pieneksi.
func _level_scaling() -> Dictionary:
	return {"hp": 1.25, "damage": 0.85, "spell": 0.95, "melee": 0.95, "regen": 1.00}


## Väistön kehitys: kilpi (magneettilevyt sulkeutuvat liu'un aikana).
func _dodge_evolution() -> String:
	return "shield"


## Botin rankkausjärjestys: Napalukko (aloitus) ensin, koukku toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "a1", "basic", "dodge"]
