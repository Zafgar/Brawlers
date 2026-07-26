class_name Kaira
extends JungleHero
## SULAKUORIAINEN. Kaira kaivertaa maan auki hehkuvalla poranterällä ja imee
## kuumuudesta voimansa: jokainen lähiosuma parantaa häntä, ja jokainen kyky
## jättää maahan laavaa. Kestävä lähitaistelujyrä — ei tähtäyspulmia, ei
## kirjanpitoa: mene päälle, pysy laavassa, pysyt hengissä.

const MOLTEN := Color("ff5f1f")     # sula kivi — Kairan pääväri
const EMBER := Color("ffb03a")      # hehkuva hiillos
const CORE := Color("fff0a8")       # poran valkohehkuinen kärki

# TASAPAINO (kokoonpanoluotaus 108 ottelua): Kaira teki 1876 vahinkoa/min eli
# yli 2x otannan keskiarvon (599) ja voitti 88 % peleistään. Trimmi kohdistuu
# LUKUIHIN, ei mekaniikkoihin: syöksy, jyrä, kuilu ja laava tekevät noin 27 %
# vähemmän, imu 0.32 -> 0.28. Silmukka (mene päälle, pysy laavassa, pysyt
# hengissä) on ennallaan. Neutraalikertoimet (jyrä 1.3 -> 1.12, kuilu
# 1.25 -> 1.10) hidastavat nimenomaan leirifarmia (29.63 clearia/ottelu),
# eivät sankaritaistelua.
const BASIC_REACH := 142.0
const BASIC_DMG := 20.0
const BASIC_ARC := 0.42             # osumakartion dot-kynnys
const LIFESTEAL := 0.28             # osumasta imetty kuumuus -> parannus

const CHARGE_DIST := 440.0
const CHARGE_SPEED := 1480.0
const CHARGE_DMG := 26.0
const CHARGE_WIDTH := 64.0
const MAGMA_RADIUS := 88.0
const MAGMA_DUR := 4.6

const SLAM_RADIUS := 218.0
const SLAM_DMG := 33.0
const SLAM_HEAL := 15.0

const BURROW_SPEED := 1200.0
const BURROW_TIME := 0.2
const BURROW_BLAST := 140.0
const BURROW_DMG := 20.0

const ULT_LENGTH := 820.0
const ULT_HALF_WIDTH := 108.0
const ULT_DMG := 86.0
const ULT_DELAY := 0.45

var _heat_glow := 0.0               # viimeisimmän osuman hehku (visuaali)
var _burrow_t := 0.0                # kaivautumisen jäljellä oleva aika


func _init() -> void:
	radius = 24.0


func _setup_resource() -> void:
	# Raivo = kuumuus. Se kertyy osumista ja otetusta vahingosta ja puretaan
	# Maanjyrään. Mittari näkyy sekä HUDissa että poran hehkuna.
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost.a2 = 35.0


## Kuumuus 0..1 — hero_visual värjää kuoren halkeamat tällä.
func heat() -> float:
	return clampf(res / maxf(res_max, 1.0), 0.0, 1.0)


func hit_glow() -> float:
	return _heat_glow


func burrowing() -> bool:
	return _burrow_t > 0.0


func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return CHARGE_DIST


## Perushyökkäys: Poranterä — leveä sivallus, joka imee kuumuutta takaisin.
## Kaira parantuu osuudella tekemästään vahingosta: mitä useampaan osuu,
## sitä enemmän jää henkiin.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("kaira", 118.0, d)
	Fx.slash(arena, global_position, d, BASIC_REACH, 0.8, Palette.glow(MOLTEN, 1.55))
	AudioMgr.play("kaira_drill", 0.08, -8.0, global_position)
	var healed := 0.0
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > BASIC_REACH + enemy.radius or dist < 1.0:
			continue
		if d.dot(off / dist) < BASIC_ARC:
			continue
		var dealt := deal_damage_to(enemy, BASIC_DMG, 95.0, d)
		if dealt > 0.0:
			healed += dealt * LIFESTEAL
			gain_res(9.0)
			Fx.spark(arena, enemy.global_position, Palette.glow(EMBER, 1.6))
	if healed > 0.0:
		heal_hp(healed, self)
		_heat_glow = 1.0
		controller_rumble(0.18, 0.3, 0.09)


## Kyky 1: Sulasyöksy — Kaira ryntää eteenpäin poranterä edellä. Kaikki reitillä
## olevat saavat vahinkoa ja lentävät sivuun, ja maahan jää palava laavavana,
## jossa Kaira itse parantuu.
func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var from := global_position
	var finish: Vector2 = from + d * CHARGE_DIST
	if arena.map != null:
		finish = arena.map.clamp_to_field(finish, radius + 8.0)
	var span := from.distance_to(finish)
	ability_signature("kaira", 170.0, d)
	dash(d, CHARGE_SPEED, maxf(span / CHARGE_SPEED, 0.08), false)
	visual.squash(1.22, 0.84)
	# Vana luetaan yhdellä silmäyksellä: paksu sula juova ja kipinäpurske kärjessä.
	Fx.beam(arena, from, finish, Palette.glow(MOLTEN, 1.6), 26.0)
	Fx.beam(arena, from, finish, Palette.glow(CORE, 1.4), 8.0)
	Fx.burst(arena, finish, Palette.glow(EMBER, 1.6), 16, 300.0, 0.4, 5.0)
	Fx.dust(arena, from)
	AudioMgr.play("kaira_charge", 0.08, -3.0, from)
	AudioMgr.play("kaira_lava", 0.06, -7.0, from)
	controller_rumble(0.35, 0.62, 0.18)
	var side := d.orthogonal()
	var healed := 0.0
	for enemy in arena.alive_enemies(team):
		var rel: Vector2 = enemy.global_position - from
		var along := rel.dot(d)
		var across := rel.dot(side)
		if along < -enemy.radius or along > span + enemy.radius:
			continue
		if absf(across) > CHARGE_WIDTH + enemy.radius:
			continue
		# Sivuun sinkoutuminen kulkee kb_velocity-impulssikanavan kautta.
		var push := side * (1.0 if across >= 0.0 else -1.0)
		var dealt := deal_damage_to(enemy, CHARGE_DMG, 340.0, push)
		if dealt > 0.0:
			healed += dealt * LIFESTEAL * 0.6
			gain_res(14.0)
	if healed > 0.0:
		heal_hp(healed, self)
	_heat_glow = 1.0
	# Kolme laavalammikkoa vanan varrelle: reitti jää näkyviin ja polttaa.
	for i in range(3):
		var f := (float(i) + 0.5) / 3.0
		JungleField.spawn(self, from.lerp(finish, f), "magma", {
			"radius": MAGMA_RADIUS, "dur": MAGMA_DUR, "dps": 19.0, "tick": 0.4,
			"color": MOLTEN,
		})


## Kyky 2: Maanjyrä — kuluttaa kerätyn kuumuuden yhteen maaniskuun. Ympärillä
## olevat saavat vahinkoa, sinkoutuvat ulos ja hidastuvat; Kaira parantuu
## jokaisesta osumasta. Mitä isompi rykelmä, sitä isompi parannus.
func _ability2(_dir: Vector2) -> void:
	ability_signature("kaira", 195.0, aim)
	Fx.ring(arena, global_position, Palette.glow(MOLTEN, 1.6), SLAM_RADIUS, 0.45, 8.0)
	Fx.flash(arena, global_position, Palette.glow(CORE, 1.5), 74.0, 0.26)
	# Kymmenen sulapiikkiä purkautuu maasta renkaana — luettava heti.
	for i in range(10):
		var ray := Vector2.RIGHT.rotated(TAU * i / 10.0 + 0.15)
		Fx.beam(arena, global_position + ray * 42.0,
			global_position + ray * SLAM_RADIUS * 0.94, Palette.glow(EMBER, 1.55), 6.0)
	Fx.burst(arena, global_position, Palette.glow(MOLTEN, 1.6), 22, 380.0, 0.5, 6.0)
	AudioMgr.play("kaira_slam", 0.1, -4.0, global_position)
	AudioMgr.play("kaira_lava", 0.08, -6.0, global_position)
	arena.shake(0.32)
	controller_rumble(0.55, 0.85, 0.22)
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > SLAM_RADIUS + enemy.radius:
			continue
		var away := off / dist if dist > 1.0 else Vector2.UP
		var neutral: bool = enemy is Critter
		deal_damage_to(enemy, SLAM_DMG * (1.12 if neutral else 1.0),
			200.0 if neutral else 330.0, away)
		enemy.apply_slow(0.6, 1.3)
		hits += 1
	if hits > 0:
		# Katto neljään kohteeseen: rykelmäparannus ei saa tehdä Kairasta
		# kuolematonta täydessä minioniaallossa.
		heal_hp(SLAM_HEAL * float(mini(hits, 4)), self)
		_heat_glow = 1.0


## Väistö: Kaivautuminen — Kaira sukeltaa maan alle lyhyeksi hetkeksi
## (osumaton) ja puhkaisee pinnan uudessa paikassa sulapurkauksena.
func _dodge_action(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	_burrow_t = BURROW_TIME + 0.1
	dash(d, BURROW_SPEED, BURROW_TIME, true)
	ability_signature("kaira", 130.0, d)
	Fx.dust(arena, global_position)
	Fx.burst(arena, global_position, Palette.darker(MOLTEN, 0.45), 14, 210.0, 0.4, 5.0)
	AudioMgr.play("kaira_drill", 0.09, -5.0, global_position)
	controller_rumble(0.3, 0.45, 0.14)


## Pinnalle puhkeaminen: purkaus laukeaa itsestään kun kaivautuminen loppuu,
## joten väistö on aina myös pieni hyökkäys.
func _burrow_surface() -> void:
	Fx.ring(arena, global_position, Palette.glow(EMBER, 1.6), BURROW_BLAST, 0.4, 7.0)
	Fx.burst(arena, global_position, Palette.glow(MOLTEN, 1.6), 16, 300.0, 0.42, 5.5)
	AudioMgr.play("kaira_slam", 0.08, -9.0, global_position)
	_act("dodge")
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > BURROW_BLAST + enemy.radius:
			continue
		var away := off / dist if dist > 1.0 else Vector2.UP
		deal_damage_to(enemy, BURROW_DMG, 260.0, away)
		gain_res(6.0)
	_act_end()


func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return ULT_LENGTH


func _ult_preview_width() -> float:
	return ULT_HALF_WIDTH


## Ultimate: Sulakita — Kaira repii maahan pitkän tulikuilun tähtäyssuuntaan.
## Kuilu telegrafoidaan viivavaroituksella; purkauksessa se lyö kaiken linjalla
## sivuun ja jättää laavaa koko matkalle. Yksi selkeä viiva, ei arvailua.
func _ultimate(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var origin := global_position + d * (radius + 8.0)
	var finish: Vector2 = origin + d * ULT_LENGTH
	if arena.map != null:
		finish = arena.map.clamp_to_field(finish, 24.0)
	visual.attack_swing()
	Fx.ultimate_line_warning(arena, origin, finish, Palette.glow(MOLTEN, 1.6),
		Palette.team(team), ULT_HALF_WIDTH, ULT_DELAY)
	arena.popup(global_position + Vector2(0, -92), "SULAKITA!",
		Palette.glow(EMBER, 1.6), 26)
	AudioMgr.play("kaira_charge", 0.12, -2.0, global_position)
	AudioMgr.play("kaira_slam", 0.08, -5.0, global_position)
	controller_rumble(0.8, 1.0, 0.4)
	_open_fissure(origin, d, origin.distance_to(finish))


func _open_fissure(origin: Vector2, d: Vector2, span: float) -> void:
	await get_tree().create_timer(ULT_DELAY).timeout
	if not is_inside_tree() or arena == null:
		return
	_act("ult")
	var side := d.orthogonal()
	var finish := origin + d * span
	arena.shake(0.6)
	AudioMgr.play("kaira_fissure", 0.05, -1.0, origin)
	Fx.beam(arena, origin, finish, Palette.glow(MOLTEN, 1.6), 62.0)
	Fx.beam(arena, origin, finish, Palette.glow(CORE, 1.7), 34.0)
	for i in range(7):
		var p := origin.lerp(finish, (float(i) + 0.5) / 7.0)
		Fx.burst(arena, p, Palette.glow(EMBER, 1.65), 14, 340.0, 0.5, 6.0)
		Fx.flash(arena, p, Palette.glow(CORE, 1.5), 52.0, 0.3)
	var healed := 0.0
	for enemy in arena.alive_enemies(team):
		var rel: Vector2 = enemy.global_position - origin
		var along := rel.dot(d)
		var across := rel.dot(side)
		if along < -enemy.radius or along > span + enemy.radius:
			continue
		if absf(across) > ULT_HALF_WIDTH + enemy.radius:
			continue
		var neutral: bool = enemy is Critter
		# Kuilu sinkoaa uhrit sivuun kb_velocity-impulssina.
		var push := side * (1.0 if across >= 0.0 else -1.0)
		var dealt := deal_damage_to(enemy, ULT_DMG * (1.10 if neutral else 1.0),
			280.0 if neutral else 430.0, push)
		enemy.apply_slow(0.62, 1.6)
		healed += dealt * 0.12
	if healed > 0.0:
		heal_hp(minf(healed, 70.0), self)
	# Laavakuilu jää palamaan: neljä lammikkoa linjan varrelle.
	for i in range(4):
		var p := origin.lerp(finish, (float(i) + 0.5) / 4.0)
		JungleField.spawn(self, p, "magma", {
			"radius": 132.0, "dur": 6.0, "dps": 25.0, "tick": 0.4,
			"color": MOLTEN,
		})
	_act_end()


func _passive_update(delta: float) -> void:
	_heat_glow = maxf(_heat_glow - delta * 1.6, 0.0)
	if _burrow_t > 0.0:
		_burrow_t = maxf(_burrow_t - delta, 0.0)
		if _burrow_t <= 0.0 and alive and arena != null:
			_burrow_surface()


func _respawn() -> void:
	super()
	_burrow_t = 0.0
	_heat_glow = 0.0


## Botti polttaa väistön hyökkäävästi: kaivautuminen on myös purkaus, joten se
## kannattaa käyttää leirillä ja kohteen kimpussa.
func bot_wants_utility() -> bool:
	var target = controller.get("_target")
	return is_instance_valid(target) and target is Critter \
		and (hp < max_hp * 0.75 or (target as Critter).is_major_objective())


## Tasoskaalaus: lähitaistelujyrä — perusvahinko ja kesto kasvavat yhdessä.
func _level_scaling() -> Dictionary:
	return {"hp": 1.10, "damage": 1.10, "spell": 0.90, "melee": 1.20, "regen": 1.05}


## Väistön kehitys: vauhti (kaivautunut kuoriainen tulee ulos kiitäen).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: perusisku (imu) ensin, sitten Maanjyrä.
func _bot_skill_order() -> Array:
	return ["ult", "basic", "a2", "a1", "dodge"]
