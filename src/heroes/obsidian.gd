class_name Obsidian
extends Hero
## Tankki: obsidiaaninyrkit. Kivinen jättiläinen joka hallitsee lähialuetta,
## kääntää vahingon takaisin hyökkääjiin ja lataa itsensä eläväksi pommiksi.
## Perusisku hidastaa ja parantaa itseä; kiviho heijastaa + torjuu; louhinta-
## loikka hyppää seinien yli ja iskee alas tainnuttaen; ultti lataa ja räjähtää.
## Passiivi: kestää tönäisyt hyvin.

const MOLTEN := Color("ff7a3a")      # hehkuva laavavärikorostus tehosteisiin

const SWING_RANGE := 106.0
const SWING_ARC_DEG := 82.0
const SWING_DMG := 12.0
const SWING_SLOW := 0.6
const SWING_SLOW_DUR := 1.2
const SWING_LIFESTEAL := 0.5         # osuus aiheutetusta vahingosta parantuu itselle

const LEAP_DIST := 340.0
const LEAP_SPEED := 1400.0
const LEAP_RADIUS := 150.0
const LEAP_DMG := 22.0
const LEAP_STUN := 0.9
const LEAP_KB := 300.0

# Kiviho (a2): kanavoitava heijastuspanssari. Ihminen kanavoi (kuluttaa raivoa
# _channel_tickissä), botti saa kertakäyttöisen ajastetun version.
const SKIN_RAGE_DRAIN := 20.0
const SKIN_ABSORB := 0.5             # torjuttu osuus otetusta vahingosta
const SKIN_REFLECT := 0.35           # heijastettu osuus (takaisin hyökkääjälle)
const BOT_SKIN_DUR := 2.4

# Ydinräjähdys (ult): lataa hetken (ottaa paljon vähemmän vahinkoa), sitten
# räjähtää — lähempänä olevat ottavat enemmän vahinkoa. Obsidiaani selviää.
const CHARGE_DUR := 2.5
const CHARGE_ABSORB := 0.8           # torjuttu osuus latauksen aikana
const CHARGE_SLOW := 0.5             # liikenopeuskerroin latauksen aikana
const ULT_RADIUS := 240.0
const ULT_MIN_DMG := 60.0            # reunalla
const ULT_MAX_DMG := 175.0           # aivan vieressä
const ULT_KB := 620.0
const ULT_STUN := 1.0

var _charging := 0.0                 # ydinlatauksen aika jäljellä (0 = ei lataa)
var _charge_fx := 0.0
var _skin_fx := 0.0


func _init() -> void:
	kb_resist = 0.62
	radius = 31.0


## Raivo: kertyy taistelusta (vahingon anto ja otto). Kiviho (L1) kuluttaa
## raivoa heijastaakseen ja torjuakseen. Perusiskut ja loikka eivät maksa raivoa.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	# a2:n kustannus koskee vain botteja (kertakäyttöinen kiviho); ihmisen
	# kanavointi kuluttaa raivoa _channel_tickissä.
	res_cost = {"basic": 0.0, "a1": 0.0, "a2": 35.0, "dodge": 0.0}


## Louhintaloikka tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return LEAP_DIST


## Kiviho kanavoidaan pitämällä L1 pohjassa.
func _channeled_slots() -> Array:
	return ["a2"]


## Perushyökkäys: raskas kiviisku joka hidastaa viholliset ja parantaa itseä
## osuessaan (elinvoiman imu).
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.1, -5.0)
	Fx.slash(arena, global_position, dir, SWING_RANGE, SWING_ARC_DEG, hero_color())
	var dealt := 0.0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SWING_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SWING_ARC_DEG:
			continue
		dealt += deal_damage_to(enemy, SWING_DMG, 220.0, to_enemy.normalized())
		enemy.apply_slow(SWING_SLOW, SWING_SLOW_DUR)
	if dealt > 0.0:
		heal_hp(dealt * SWING_LIFESTEAL, self)
		arena.shake(0.08)
		Fx.spark(arena, global_position + dir * SWING_RANGE * 0.7, hero_color())


## Kyky 1: Louhintaloikka — hyppää tähtäyssuuntaan seinien yli ja iskee alas
## tainnuttavalla aluevahingolla laskeutuessaan.
func _ability1(dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	var landing: Vector2 = global_position + d * LEAP_DIST
	if arena.map != null:
		landing = arena.map.clamp_to_field(landing, radius)
	var leap_dur: float = maxf(global_position.distance_to(landing) / LEAP_SPEED, 0.12)
	dash(d, LEAP_SPEED, leap_dur, true, true)   # iframes + seinien yli
	AudioMgr.play("dash", 0.1, -6.0)
	visual.squash(0.7, 1.35)
	Fx.dust(arena, global_position)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.3), radius + 10.0, 0.3, 4.0)
	await get_tree().create_timer(leap_dur).timeout
	if not is_inside_tree() or not alive:
		return
	_land_slam()


## Laskeutumisisku: tainnuttava aluevahinko Obsidiaanin ympärille.
func _land_slam() -> void:
	_act("a1")
	AudioMgr.play("slam", 0.1, -2.0)
	arena.shake(0.32)
	visual.squash(1.3, 0.75)
	Fx.ring(arena, global_position, Palette.glow(MOLTEN, 1.5), LEAP_RADIUS, 0.5, 8.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.6), LEAP_RADIUS * 0.6, 0.4, 5.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position, LEAP_RADIUS):
		if enemy.team == team:
			continue
		var away: Vector2 = (enemy.global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		deal_damage_to(enemy, LEAP_DMG, LEAP_KB, away)
		enemy.apply_stun(LEAP_STUN)
		Fx.spark(arena, enemy.global_position, Palette.glow(MOLTEN, 1.4))
	_act_end()


func _channel_tick(_slot: String, delta: float) -> void:
	# Torju + heijasta niin kauan kuin raivoa riittää (kaikkisuuntainen 180°).
	start_guard(0.2, SKIN_ABSORB, 180.0)
	apply_reflect(0.2, SKIN_REFLECT, "a2")
	res = maxf(res - SKIN_RAGE_DRAIN * delta, 0.0)
	_skin_fx -= delta
	if _skin_fx <= 0.0:
		_skin_fx = 0.2
		Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.3), radius + 14.0, 0.28, 4.0)
	if res <= 0.0:
		guard_timer = 0.0        # raivo loppui -> panssari putoaa heti
		reflect_timer = 0.0


func _channel_end(_slot: String) -> void:
	AudioMgr.play("ui_back", 0.05, -4.0)
	visual.squash(1.1, 0.9)


## Kyky 2 (vain botit): kertakäyttöinen kiviho, koska botit eivät kanavoi.
func _ability2(_dir: Vector2) -> void:
	start_guard(BOT_SKIN_DUR, SKIN_ABSORB, 180.0)
	apply_reflect(BOT_SKIN_DUR, SKIN_REFLECT, "a2")
	AudioMgr.play("guard_up")
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.4), radius + 18.0, 0.4, 6.0)


## Väistö: raskas kivirynnäkkö, joka tönäisee ja hidastaa osuessaan.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 820.0, 0.22, false)
	AudioMgr.play("dash", 0.1, -5.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position + dir * 55.0, 84.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 8.0, 400.0, dir)
		enemy.apply_slow(0.7, 1.0)


## Ultimate: Ydinräjähdys — aloittaa latauksen. Latauksen aikana Obsidiaani ottaa
## paljon vähemmän vahinkoa ja liikkuu hitaasti; kun lataus täyttyy, se räjähtää.
func _ultimate(_dir: Vector2) -> void:
	_charging = CHARGE_DUR
	_charge_fx = 0.0
	arena.popup(global_position + Vector2(0, -92), "YDINLATAUS!", Palette.glow(MOLTEN, 1.6), 26)
	AudioMgr.play("obsidian_ult", 0.05, -2.0, global_position)
	controller_rumble(0.35, 0.75, 0.7)
	arena.shake(0.35)
	Fx.flash(arena, global_position, Palette.glow(MOLTEN, 1.4), 110.0, 0.5)


## Räjähdys: lähempänä olevat viholliset ottavat enemmän vahinkoa. Obsidiaani ei
## ota itse vahinkoa (deal_damage_to ohittaa oman joukkueen ja itsen).
func _detonate() -> void:
	_act("ult")
	arena.popup(global_position + Vector2(0, -92), "RÄJÄHDYS!", Palette.glow(MOLTEN, 1.7), 30)
	AudioMgr.play("obsidian_ult", 0.05, 3.0, global_position)
	arena.shake(0.7)
	Fx.flash(arena, global_position, Palette.glow(MOLTEN, 1.7), ULT_RADIUS * 0.7, 0.55)
	Fx.ring(arena, global_position, Palette.glow(MOLTEN, 1.7), ULT_RADIUS, 0.7, 10.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.7), ULT_RADIUS * 0.65, 0.55, 6.0)
	Fx.burst(arena, global_position, Palette.glow(MOLTEN, 1.6), 26, 420.0, 0.6, 7.0)
	for enemy in arena.heroes_in_circle(global_position, ULT_RADIUS):
		if enemy.team == team:
			continue
		var dist: float = enemy.global_position.distance_to(global_position)
		var prox: float = 1.0 - clampf(dist / ULT_RADIUS, 0.0, 1.0)
		var dmg: float = lerpf(ULT_MIN_DMG, ULT_MAX_DMG, prox)
		var away: Vector2 = (enemy.global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		deal_damage_to(enemy, dmg, ULT_KB, away)
		enemy.apply_stun(ULT_STUN)
		Fx.spark(arena, enemy.global_position, Palette.glow(MOLTEN, 1.5))
	_act_end()


## Liikenopeus: latauksen aikana Obsidiaani liikkuu hitaasti.
func _move_speed_mult() -> float:
	return CHARGE_SLOW if _charging > 0.0 else 1.0


func _passive_update(delta: float) -> void:
	if _charging <= 0.0:
		return
	var prev := _charging
	_charging = maxf(_charging - delta, 0.0)
	# Vahva torjunta latauksen ajan (kirjataan ultille).
	_act("ult")
	start_guard(0.15, CHARGE_ABSORB, 180.0)
	_act_end()
	_charge_fx -= delta
	if _charge_fx <= 0.0:
		_charge_fx = 0.16
		var pr: float = 1.0 - _charging / CHARGE_DUR
		Fx.ring(arena, global_position, Palette.glow(MOLTEN, 1.5),
			radius + 8.0 + pr * (ULT_RADIUS - radius), 0.3, 3.0)
	if _charging <= 0.0 and prev > 0.0:
		_detonate()


## Lataus nollataan tyrmäyksestä ja erän vaihtuessa (ei räjähdystä kuoleman jälkeen).
func _respawn() -> void:
	super()
	_charging = 0.0


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_charging = 0.0


## Tasoskaalaus: tankki — valtava kesto, heijastus tekee työn.
func _level_scaling() -> Dictionary:
	return {"hp": 1.35, "damage": 0.80, "spell": 0.90, "melee": 0.90, "regen": 0.95}


## Väistön kehitys: kilpi (obsidiaanipanssari paksunee väistössä).
func _dodge_evolution() -> String:
	return "shield"


## Botin rankkausjärjestys: Louhintaloikka ensin, kiviho toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]
