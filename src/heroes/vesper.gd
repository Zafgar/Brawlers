class_name Vesper
extends JungleHero
## FOSFORIJAHTAAJA. Vesper merkitsee saaliin ja lopettaa sen. Koko kitti on
## kaksivaiheinen ja luettava: MERKITSE ensin, TELOITA sitten. Teloituskyvyt
## tekevät sitä enemmän vahinkoa mitä vähemmän kohteella on elämää jäljellä,
## joten Vesper on se sankari joka vie haavoittuneen pois pelistä.

const PHOSPHOR := Color("d9ff8f")   # fosforin hehku
const BURN := Color("b8ff3d")       # kirkas syttymisvälähdys

const BOLT_DMG := 14.0
const MARK_BONUS := 9.0             # perusiskun lisävahinko merkittyyn

const SPIKE_RANGE := 780.0
const SPIKE_DMG := 22.0
const MARK_DUR := 6.0
const MARK_AMP := 1.22

const EXEC_RANGE := 720.0
const EXEC_BASE := 42.0
const EXEC_MISSING := 0.40          # osuus kohteen puuttuvasta elämästä
const EXEC_MARK_MULT := 1.25        # merkittyyn kohteeseen kovempi
const EXEC_REFUND := 5.0            # jäähdytyshyvitys taposta

const LEAP_SPEED := 1260.0
const LEAP_TIME := 0.2

const ULT_LENGTH := 1050.0
const ULT_HALF_WIDTH := 48.0
const ULT_BASE := 128.0
const ULT_MISSING := 0.45

var _hunt_glow := 0.0               # teloituksen jälkihehku (visuaali)


func _init() -> void:
	radius = 19.0


func _setup_resource() -> void:
	# Kaukotaistelijan leiripuhdistus on turvallisempaa, joten se saa olla
	# hitaampaa — mutta ei moninkertaisesti hitaampaa kuin lähitaistelijalla.
	jungle_clear_mult = 2.0
	res_type = "energy"
	res_max = 100.0
	res = res_max
	res_regen = 12.0
	res_cost.a1 = 18.0
	res_cost.a2 = 26.0


func hunt_glow() -> float:
	return _hunt_glow


func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _aim_range(slot: String) -> float:
	return SPIKE_RANGE if slot == "a1" else EXEC_RANGE


func _aim_default_range(slot: String) -> float:
	return 520.0 if slot == "a1" else 480.0


## Perushyökkäys: Fosforipultti — nopea pultti. Merkittyyn kohteeseen se tekee
## lisävahinkoa ja palauttaa energiaa, joten merkki kannattaa aina käyttää.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("vesper", 105.0, d)
	Projectile.launch(self, global_position + d * (radius + 9.0), d, {
		"speed": 1140.0, "dmg": BOLT_DMG, "radius": 7.5, "life": 0.8,
		"kb": 55.0, "color": PHOSPHOR, "visual": "vesper_bolt",
		"on_hit": Callable(self, "_bolt_hit"),
	})
	AudioMgr.play("bow", 0.06, -11.0, global_position)


func _bolt_hit(target: Hero, _projectile: Projectile) -> void:
	if target.mark_timer <= 0.0:
		return
	deal_damage_to(target, MARK_BONUS)
	gain_res(8.0)
	Fx.bolt(arena, target.global_position - aim.orthogonal() * 16.0,
		target.global_position + aim.orthogonal() * 16.0, Palette.glow(BURN, 1.6))


## Kyky 1: Fosforipiikki — pitkä läpäisevä piikki, joka MERKITSEE saaliin.
## Merkki on Vesperin koko kitin ehto: se kirkastaa kohteen ja avaa teloituksen.
func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("vesper", 148.0, d)
	Projectile.launch(self, global_position + d * (radius + 10.0), d, {
		"speed": 1320.0, "dmg": SPIKE_DMG, "radius": 9.0,
		"life": SPIKE_RANGE / 1320.0, "kb": 80.0, "pierce": 1, "color": BURN,
		"visual": "vesper_tracker", "on_hit": Callable(self, "_spike_hit"),
	})
	AudioMgr.play("bow_charged", 0.08, -5.0, global_position)
	controller_rumble(0.18, 0.42, 0.12)


func _spike_hit(target: Hero, _projectile: Projectile) -> void:
	target.apply_mark(MARK_DUR, MARK_AMP)
	if target is Critter:
		target.apply_slow(0.72, 1.0)
	gain_res(10.0)
	# Lukitus näkyy tähtäinristinä saaliin päällä + mark-ping kuuluu.
	var gp: Vector2 = target.global_position
	Fx.ring(arena, gp, Palette.glow(PHOSPHOR, 1.5), 52.0, 0.35, 4.0)
	Fx.beam(arena, gp + Vector2(-30, 0), gp + Vector2(30, 0), Palette.glow(BURN, 1.5), 3.0)
	Fx.beam(arena, gp + Vector2(0, -30), gp + Vector2(0, 30), Palette.glow(BURN, 1.5), 3.0)
	AudioMgr.play("mark", 0.07, -6.0, gp)


## Kyky 2: Teloitus — raskas fosforipultti, jonka vahinko kasvaa sen mukaan
## kuinka paljon kohteelta PUUTTUU elämää. Merkittyyn kohteeseen 25 % kovempaa.
## Tappo hyvittää jäähdytyksestä 5 s, joten onnistunut lopetus palkitaan heti.
func _ability2(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	ability_signature("vesper", 160.0, d)
	Projectile.launch(self, global_position + d * (radius + 11.0), d, {
		"speed": 1560.0, "dmg": 0.0, "radius": 11.0,
		"life": EXEC_RANGE / 1560.0, "kb": 0.0, "color": BURN,
		"visual": "vesper_exec", "on_hit": Callable(self, "_execute_hit"),
	})
	Fx.flash(arena, global_position + d * 26.0, Palette.glow(BURN, 1.7), 34.0, 0.18)
	AudioMgr.play("bow_charged", 0.06, 0.0, global_position)
	controller_rumble(0.3, 0.6, 0.16)


func _execute_hit(target: Hero, _projectile: Projectile) -> void:
	# Koko vahinko lasketaan täällä (ammuksen perusvahinko on 0), jotta
	# puuttuva elämä mitataan ennen osumaa eikä sen jälkeen.
	var missing: float = maxf(target.max_hp - target.hp, 0.0)
	var dmg: float = EXEC_BASE + missing * EXEC_MISSING
	if target.mark_timer > 0.0:
		dmg *= EXEC_MARK_MULT
	if target is Critter:
		dmg *= 1.15
	var gp: Vector2 = target.global_position
	deal_damage_to(target, dmg, 140.0, aim)
	_hunt_glow = 1.0
	gain_res(9.0)
	Fx.flash(arena, gp, Palette.glow(BURN, 1.7), 48.0, 0.24)
	Fx.burst(arena, gp, Palette.glow(PHOSPHOR, 1.6), 14, 300.0, 0.36, 4.0)
	if not target.alive:
		# Vain merkityksellinen tapahtuma saa popupin: saalis kaatui.
		cd.a2 = maxf(cd.a2 - EXEC_REFUND, 0.0)
		arena.popup(gp + Vector2(0, -70), "TELOITUS!", Palette.glow(BURN, 1.6), 22)
		AudioMgr.play("mark", 0.06, 2.0, gp)
		controller_rumble(0.45, 0.8, 0.2)
	else:
		AudioMgr.play("mark", 0.07, -4.0, gp)


## Väistö: Fosforiloikka — pitkä loikka osumattomana. Jahtaaja pitää itse
## etäisyyden, ei enää jätä kenttää jonka joku muu hoitaisi.
func _dodge_action(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	dash(d, LEAP_SPEED, LEAP_TIME, true)
	apply_haste(1.2, 1.6)
	ability_signature("vesper", 125.0, d)
	Fx.ring(arena, global_position, Palette.glow(PHOSPHOR, 1.5), 74.0, 0.4, 3.5)
	Fx.burst(arena, global_position, Palette.with_alpha(BURN, 0.7), 10, 180.0, 0.4, 3.0)
	AudioMgr.play("blink", 0.08, -7.0, global_position)
	controller_rumble(0.2, 0.3, 0.12)


func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return ULT_LENGTH


func _ult_preview_width() -> float:
	return ULT_HALF_WIDTH


## Ultimate: Fosforisalama — pitkä ohut kiskolaukaus, joka lävistää kaiken
## linjalla. Vahinko kasvaa jokaisen kohteen puuttuvan elämän mukaan, joten
## tämä on koko joukkueen lopetusnappi haavoittunutta vihollisryhmää vastaan.
func _ultimate(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var origin := global_position + d * (radius + 8.0)
	var finish: Vector2 = origin + d * ULT_LENGTH
	if arena.map != null:
		finish = arena.map.clamp_to_field(finish, 16.0)
	var span := origin.distance_to(finish)
	var side := d.orthogonal()
	visual.attack_swing()
	arena.popup(global_position + Vector2(0, -86), "FOSFORISALAMA!",
		Palette.glow(BURN, 1.6), 26)
	Fx.ultimate_line_warning(arena, origin, finish, Palette.glow(BURN, 1.6),
		Palette.team(team), ULT_HALF_WIDTH, 0.26)
	# Kolme yhdensuuntaista sädettä: ohut kirkas ydin ja kaksi hehkuvaa reunaa.
	Fx.beam(arena, origin, finish, Palette.glow(PHOSPHOR, 1.5), 22.0)
	Fx.beam(arena, origin, finish, Color.WHITE, 7.0)
	Fx.beam(arena, origin + side * 26.0, finish + side * 26.0,
		Palette.with_alpha(BURN, 0.6), 3.0)
	Fx.beam(arena, origin - side * 26.0, finish - side * 26.0,
		Palette.with_alpha(BURN, 0.6), 3.0)
	AudioMgr.play("ult", 0.1, -3.0, global_position)
	AudioMgr.play("quill_ult", 0.05, -2.0, global_position)
	arena.shake(0.45)
	controller_rumble(0.5, 0.85, 0.3)
	_hunt_glow = 1.0
	var executed := 0
	for enemy in arena.alive_enemies(team):
		var rel: Vector2 = enemy.global_position - origin
		var along := rel.dot(d)
		var across := rel.dot(side)
		if along < -enemy.radius or along > span + enemy.radius:
			continue
		if absf(across) > ULT_HALF_WIDTH + enemy.radius:
			continue
		var missing: float = maxf(enemy.max_hp - enemy.hp, 0.0)
		var dmg: float = ULT_BASE + missing * ULT_MISSING
		var gp: Vector2 = enemy.global_position
		deal_damage_to(enemy, dmg, 260.0, d)
		enemy.apply_mark(MARK_DUR, MARK_AMP)
		Fx.flash(arena, gp, Palette.glow(BURN, 1.7), 46.0, 0.26)
		if not enemy.alive:
			executed += 1
	if executed > 0:
		arena.popup(global_position + Vector2(0, -110),
			"TELOITUS x%d" % executed, Palette.glow(BURN, 1.7), 24)


func _passive_update(delta: float) -> void:
	_hunt_glow = maxf(_hunt_glow - delta * 1.3, 0.0)


## Botti polttaa loikan pakoon eikä leirille: se on puhdas liikekyky.
func bot_wants_utility() -> bool:
	return hp < max_hp * 0.45


## Tasoskaalaus: teloittaja — pultit ja teloitukset kasvavat rajusti.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 1.20, "spell": 1.25, "melee": 0.95, "regen": 0.95}


## Väistön kehitys: vauhti (jahtaaja pitää saalistusetäisyyden).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Teloitus ensin, merkkipiikki toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "a1", "basic", "dodge"]
