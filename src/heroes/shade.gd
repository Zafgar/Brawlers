class_name Shade
extends Hero
## VARJOVÄIJYJÄ. Shaden koko kitti on yksi silmukka: KERÄÄ VARJOPISTEET SELÄN
## TAKAA -> TELOITA PALUUVEDOLLA -> KATOA VARJOON.
## - Varjokiekko (perus): poispäin katsovaan kohteeseen osuva kiekko tekee
##   lisävahinkoa ja kerää varjopisteen. Asemointi on perusiskun taito.
## - Varjoloikka (R1): tähtää ja loikkaa; lähtöpaikkaan jää VARJO, jolle voi
##   palata koko ikkunan ajan. Paluu on kitin pakotie ja jättää häiveen.
## - Paluushuriken (L1): tähtää ja heitä; toinen painallus kutsuu takaisin.
##   PALUUVETO on teloitus — sen vahinko kasvaa kohteen puuttuvan elämän ja
##   kerättyjen varjopisteiden mukaan, joten kutsun AJOITUS ratkaisee.
## Jäähdytyspohjainen (ei resurssia). Passiivi: väistö lataa ultimatea.
##
## Itemikäyrä: teloitus ja varjopurkaukset skaalaavat hyökkäysvoimalla erikseen
## (ITEM_ATK_SCALE) moottorin ap-skaalauksen PÄÄLLE — syötetty Shade tappaa
## takalinjan yhdellä silmukalla, jäljessä oleva ei uhkaa ketään.

# Perushyökkäys: varjokiekko + selkäänisku.
const DISC_DMG := 20.0
const DISC_SPEED := 1010.0
const DISC_LIFE := 0.5
const BACKSTAB_BONUS := 0.6         # lisävahinko osuutena, kun kohde katsoo poispäin
const BACKSTAB_DOT := 0.25
const MAX_CHARGE := 3
const CHARGE_BONUS := 0.15          # per varjopiste paluuvedon teloitukseen

# Kyky 1: Varjoloikka ja varjopaluu.
const LEAP_RANGE := 320.0
const LEAP_DMG := 24.0
const LEAP_RADIUS := 120.0
const SHADOW_WINDOW := 4.0          # kuinka kauan varjolle voi palata
const RETURN_DMG := 32.0
const RETURN_RADIUS := 150.0
const RETURN_STEALTH := 0.9         # häive paluun jälkeen (katkeaa omaan osumaan)
const MARK_DUR := 4.0
const MARK_AMP := 1.15

# Kyky 2: Paluushuriken.
const SHURI_SPEED := 940.0
const SHURI_DMG := 22.0
const SHURI_RADIUS := 30.0          # iso osuma-alue (helppo ohjaimella)
const SHURI_OUT_TIME := 0.42
const SHURI_KB := 110.0
const SHURI_CATCH_RADIUS := 36.0
const EXEC_BASE := 26.0
const EXEC_MISSING := 0.32          # osuus kohteen puuttuvasta elämästä

# Ultimate: Varjoteurastus.
const ULT_RANGE := 520.0
const ULT_BASE := 90.0
const ULT_MISSING := 0.35
const ULT_EMPOWER := 4.0
const EMPOWER_MULT := 1.6

const ITEM_ATK_SCALE := 0.9         # assassiinin kykyjen hyökkäysvoimaskaalaus

var _empower_timer := 0.0
var _charge := 0                    # varjopisteet (0..MAX_CHARGE)

# Varjoloikka (a1)
var _shadow_active := false
var _shadow_pos := Vector2.ZERO
var _shadow_timer := 0.0
var _shadow_decoy: Decoy = null

# Paluushuriken (a2)
var _active_shuriken: Shuriken = null


func _init() -> void:
	radius = 22.0


## Jäähdytyspohjainen assassiini (ei resurssipalkkia). Molemmat kyvyt ovat
## kaksivaiheisia; jäähdytykset tulevat HeroDefistä, joten HUD ja logiikka
## kertovat saman luvun.
func _setup_resource() -> void:
	res_type = ""


## Molemmat kyvyt tähdätään: pidä pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1", "a2"]


func _aim_range(slot: String) -> float:
	return LEAP_RANGE if slot == "a1" else 460.0


## Ensimmäinen painallus aloittaa tähtäyksen; jos kyvyn toinen vaihe on
## saatavilla (varjo pystyssä / shuriken lennossa), se laukeaa heti.
func _aim_begin(slot: String) -> bool:
	if slot == "a1":
		if _shadow_active:
			_return_to_shadow()
			return false
		return true
	if _active_shuriken != null and is_instance_valid(_active_shuriken):
		_active_shuriken.recall()
		return false
	return true


## Assassiinin itemikäyrä: kykyvahinko skaalaa hyökkäysvoimalla erikseen, tämä
## tulee moottorin oman ap-skaalauksen PÄÄLLE.
func _item_power() -> float:
	return 1.0 + ITEM_ATK_SCALE * item_stat("attack")


func charge_count() -> int:
	return _charge


func shadow_fraction() -> float:
	if not _shadow_active:
		return 0.0
	return clampf(_shadow_timer / SHADOW_WINDOW, 0.0, 1.0)


func shadow_position() -> Vector2:
	return _shadow_pos


## Perushyökkäys: nopea varjokiekko (tehostuu ultin aikana).
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	AudioMgr.play("disc", 0.15, -2.0, global_position)
	visual.attack_swing()
	var dmg := DISC_DMG
	if _empower_timer > 0.0:
		dmg *= EMPOWER_MULT
	Projectile.launch(self, global_position + d * 26.0, d, {
		"speed": DISC_SPEED,
		"dmg": dmg,
		"radius": 10.0,
		"life": DISC_LIFE,
		"kb": 90.0,
		"spin": true,
		"color": Palette.glow(hero_color(), 1.3) if _empower_timer > 0.0 else hero_color(),
		"visual": "shade_disc",
		"on_hit": Callable(self, "_disc_hit"),
	})


## SELKÄÄNISKU: poispäin katsovaan kohteeseen osunut kiekko tekee lisävahinkoa
## ja kerää VARJOPISTEEN. Pisteet tehostavat Paluushurikenin teloitusvetoa, joten
## kiertäminen kohteen selän taakse on Shaden perusiskun mekaniikka.
func _disc_hit(target: Hero, _projectile: Projectile) -> void:
	if target.is_unit:
		return
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() < 1.0:
		return
	if target.aim.dot(to_target.normalized()) < BACKSTAB_DOT:
		return
	var bonus := DISC_DMG * BACKSTAB_BONUS * _item_power()
	if _empower_timer > 0.0:
		bonus *= EMPOWER_MULT
	deal_damage_to(target, bonus, 0.0, to_target.normalized())
	_gain_charge()
	Fx.spark(arena, target.global_position, Palette.glow(hero_color(), 1.8))
	arena.popup(target.global_position + Vector2(0, -56), "SELKÄÄN!", hero_color(), 15)
	AudioMgr.play("mark", 0.05, 2.0, target.global_position)
	if not target.alive:
		_on_takedown()


func _gain_charge() -> void:
	if _charge >= MAX_CHARGE:
		return
	_charge += 1
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.4), 34.0, 0.25, 3.0)
	if _charge >= MAX_CHARGE:
		AudioMgr.play("ult_ready", 0.04, -8.0, global_position)


## Kyky 1: Varjoloikka — loikkaa tähtäyssuuntaan, iske saapumisessa ja jätä varjo
## lähtöpaikkaan. Toinen painallus palaa varjolle. Sama polku myös botilla: ilman
## paluuta assassiini jää keskelle vihollisia (juuri se tappoi vanhan Shaden).
func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var origin := global_position
	AudioMgr.play("smoke", 0.1, 0.0, origin)
	var smoke := Palette.darker(hero_color(), 0.5)
	Fx.burst(arena, origin, Palette.with_alpha(smoke, 0.7), 12, 200.0, 0.5, 7.0)
	global_position = arena.map.clamp_to_field(origin + d * LEAP_RANGE, 40.0)
	Fx.burst(arena, global_position, Palette.with_alpha(smoke, 0.6), 10, 180.0, 0.5, 6.0)
	ability_signature("shade", 120.0, d)
	apply_haste(1.2, 1.0)
	iframes = maxf(iframes, 0.3)
	_shadow_burst(global_position, LEAP_DMG, LEAP_RADIUS, true)
	_plant_shadow(origin)
	controller_rumble(0.2, 0.4, 0.12)


## Paluu varjolle: purkaus ympärille, häive irtoamiseen. Tämä on kitin pakotie
## eikä vaadi omaa jäähdytystään — se on jo maksettu loikassa.
func _return_to_shadow() -> void:
	AudioMgr.play("smoke", 0.1, 2.0, global_position)
	var from := global_position
	global_position = arena.map.clamp_to_field(_shadow_pos, 40.0)
	iframes = maxf(iframes, 0.4)
	Fx.beam(arena, from, global_position, Palette.glow(hero_color(), 1.3), 5.0)
	arena.popup(global_position + Vector2(0, -76), "VARJOPALUU!",
		Palette.glow(hero_color(), 1.5), 20)
	_act("a1")
	_shadow_burst(global_position, RETURN_DMG, RETURN_RADIUS, false)
	_act_end()
	# Häive vasta purkauksen JÄLKEEN: oma vahinko katkaisisi sen heti.
	stealth_timer = maxf(stealth_timer, RETURN_STEALTH)
	AudioMgr.play("stealth_in", 0.05, -5.0, global_position)
	_clear_shadow()
	cd.a1 = float(cd_max.a1)
	controller_rumble(0.3, 0.55, 0.16)


## Varjopurkaus. Piirityssääntö: aluevahinko ei satu rakennuksiin, joten lippu on
## päällä vain purkauksen ajan ja palautetaan heti perään.
func _shadow_burst(center: Vector2, amount: float, blast: float, mark: bool) -> void:
	AudioMgr.play("disc", 0.1, -1.0, center)
	arena.shake(0.2)
	Fx.ring(arena, center, Palette.glow(hero_color(), 1.5), blast, 0.5, 7.0)
	Fx.burst(arena, center, Palette.with_alpha(Palette.darker(hero_color(), 0.4), 0.7),
		14, 240.0, 0.5, 6.0)
	var prev_aoe: bool = damage_is_aoe
	damage_is_aoe = true
	var power: float = amount * _item_power()
	for enemy in arena.heroes_in_circle(center, blast):
		if enemy.team == team:
			continue
		var away: Vector2 = enemy.global_position - center
		var kbdir: Vector2 = away.normalized() if away.length() > 1.0 else aim
		deal_damage_to(enemy, power, 260.0, kbdir)
		if mark and not enemy.is_unit and enemy.alive:
			enemy.apply_mark(MARK_DUR, MARK_AMP)
		if not enemy.alive:
			_on_takedown()
	damage_is_aoe = prev_aoe


## Istuttaa varjon annettuun pisteeseen ja avaa paluuikkunan.
func _plant_shadow(spot: Vector2) -> void:
	if is_instance_valid(_shadow_decoy):
		_shadow_decoy.queue_free()
	var decoy := Decoy.new()
	decoy.global_position = spot
	decoy.body_color = hero_color()
	decoy.facing = aim
	decoy.lifetime = SHADOW_WINDOW + 0.2
	arena.add_child(decoy)
	_shadow_decoy = decoy
	_shadow_pos = spot
	_shadow_active = true
	_shadow_timer = SHADOW_WINDOW
	cd.a1 = 0.2                     # lyhyt, jotta paluupainallus toimii


## Kyky 2: Paluushuriken — tähdättävä shuriken, joka lentää ulos ja palaa
## (automaattisesti tai painamalla uudelleen). Ulosveto naputtaa, PALUUVETO
## teloittaa. Kopatessa jäähdytys lyhenee reilusti.
func _ability2(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	AudioMgr.play("disc", 0.1, -4.0, global_position)
	ability_signature("shade", 110.0, d)
	if _active_shuriken != null and is_instance_valid(_active_shuriken):
		_active_shuriken.queue_free()
	var sh := Shuriken.new()
	sh.source = self
	sh.direction = d
	sh.color = hero_color()
	sh.speed = SHURI_SPEED
	sh.hit_radius = SHURI_RADIUS
	sh.out_time = SHURI_OUT_TIME
	sh.kb = SHURI_KB
	sh.catch_radius = SHURI_CATCH_RADIUS
	sh.global_position = global_position + d * 26.0
	arena.add_child(sh)
	_active_shuriken = sh
	cd.a2 = 0.2                     # lyhyt, jotta kutsupainallus toimii


## Shurikenin osuma. Koko vahinkologiikka on täällä yhdessä paikassa: ulosveto on
## naputus, paluuveto on TELOITUS jonka vahinko kasvaa kohteen puuttuvan elämän
## ja kerättyjen varjopisteiden mukaan.
func shuriken_hit(target: Hero, returning: bool, kbdir: Vector2) -> void:
	_act("a2")
	var dmg := SHURI_DMG
	if returning:
		var missing := 0.0
		if not target.is_unit:
			missing = maxf(target.max_hp - target.hp, 0.0)
		dmg = (EXEC_BASE + missing * EXEC_MISSING) * (1.0 + CHARGE_BONUS * float(_charge))
	dmg *= _item_power()
	if _empower_timer > 0.0:
		dmg *= EMPOWER_MULT
	var gp: Vector2 = target.global_position
	deal_damage_to(target, dmg, SHURI_KB, kbdir)
	if returning and not target.is_unit:
		if _charge > 0:
			_charge = 0
			Fx.burst(arena, gp, Palette.glow(hero_color(), 1.6), 12, 260.0, 0.4, 5.0)
		Fx.flash(arena, gp, Palette.glow(hero_color(), 1.6), 40.0, 0.22)
		AudioMgr.play("mark", 0.05, 3.0, gp)
	Fx.spark(arena, gp, Palette.glow(hero_color(), 1.4))
	if not target.alive:
		arena.popup(gp + Vector2(0, -66), "VARJOTELOITUS!",
			Palette.glow(hero_color(), 1.7), 20)
		_on_takedown()
	_act_end()


## Shuriken kopattiin -> jäähdytys lyhenee reilusti ja saa hieman ultia.
func on_shuriken_caught() -> void:
	_active_shuriken = null
	cd.a2 = maxf(float(cd_max.a2) * 0.35, 0.3)
	add_ult(3.0)
	arena.popup(global_position + Vector2(0, -70), "KOPPI!",
		Palette.glow(hero_color(), 1.4), 18)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 40.0, 0.35)


## Shuriken katosi ilman koppia -> täysi jäähdytys.
func on_shuriken_expired() -> void:
	_active_shuriken = null
	cd.a2 = maxf(float(cd.a2), float(cd_max.a2))


## Väistö: varjoaskel, joka lataa ultia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	add_ult(3.0)
	AudioMgr.play("smoke", 0.12, 3.0, global_position)
	Fx.burst(arena, global_position, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.5),
		8, 150.0, 0.4, 5.0)


## Ultimate: Varjoteurastus — Shade katoaa savuun ja ilmestyy haavoittuneimman
## vihollisen SELÄN TAAKSE teloittavalla iskulla (vanha ulti ei tehnyt lainkaan
## vahinkoa). Lähtöpaikkaan jää varjo, joten purskeen jälkeen on aina pakotie, ja
## varjopisteet nousevat täyteen seuraavaa Paluushurikenia varten.
func _ultimate(_dir: Vector2) -> void:
	var origin := global_position
	var target := _ult_target()
	arena.popup(global_position + Vector2(0, -84), "VARJOTEURASTUS!",
		Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("smoke", 0.05, -3.0, origin)
	AudioMgr.play("disc", 0.1, 2.0, origin)
	_empower_timer = ULT_EMPOWER
	apply_haste(1.4, ULT_EMPOWER)
	iframes = maxf(iframes, 0.4)
	_charge = MAX_CHARGE
	Fx.burst(arena, origin, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.7),
		16, 240.0, 0.6, 7.0)
	if target != null:
		var facing := Vector2.RIGHT
		if target.aim.length() > 0.1:
			facing = target.aim.normalized()
		global_position = arena.map.clamp_to_field(
			target.global_position - facing * (target.radius + 44.0), 40.0)
		aim = (target.global_position - global_position).normalized()
		visual.attack_swing()
		Fx.beam(arena, origin, global_position, Palette.glow(hero_color(), 1.4), 6.0)
		Fx.slash(arena, global_position, aim, 90.0, 90.0, Palette.glow(hero_color(), 1.6))
		var missing := 0.0
		if not target.is_unit:
			missing = maxf(target.max_hp - target.hp, 0.0)
		var dmg: float = (ULT_BASE + missing * ULT_MISSING) * _item_power()
		var gp: Vector2 = target.global_position
		deal_damage_to(target, dmg, 240.0, aim)
		if target.alive:
			target.apply_mark(MARK_DUR, MARK_AMP)
		Fx.flash(arena, gp, Palette.glow(hero_color(), 1.7), 52.0, 0.28)
		arena.shake(0.35)
		if not target.alive:
			_on_takedown()
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), 160.0, 0.5, 7.0)
	controller_rumble(0.5, 0.85, 0.3)
	_plant_shadow(origin)


## Ultin kohde: kantaman sisällä oleva haavoittunein vihollissankari.
func _ult_target() -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		var d: float = enemy.global_position.distance_to(global_position)
		if d > ULT_RANGE:
			continue
		var score: float = enemy.hp / maxf(enemy.max_hp, 1.0) * 1000.0 + d * 0.25
		if score < best_score:
			best_score = score
			best = enemy
	return best


## Kaato palkitaan: varjoikkuna alkaa alusta (tai loikka latautuu heti),
## varjopisteet täyteen ja tehostus jatkuu. Väijytyksen palkinto on ulospääsy.
func _on_takedown() -> void:
	_charge = MAX_CHARGE
	if _shadow_active:
		_shadow_timer = SHADOW_WINDOW
		if is_instance_valid(_shadow_decoy):
			_shadow_decoy.refresh(SHADOW_WINDOW + 0.2)
	else:
		cd.a1 = 0.0
	if _empower_timer > 0.0:
		_empower_timer += 1.5
	arena.popup(global_position + Vector2(0, -100), "VARJO LADATTU!",
		Palette.glow(hero_color(), 1.7), 20)
	AudioMgr.play("ult_ready", 0.05, -5.0, global_position)


func _passive_update(delta: float) -> void:
	_empower_timer = maxf(_empower_timer - delta, 0.0)
	if _shadow_active:
		_shadow_timer -= delta
		if _shadow_timer <= 0.0:
			# Varjo haihtui käyttämättä -> täysi jäähdytys.
			_clear_shadow()
			cd.a1 = maxf(float(cd.a1), float(cd_max.a1))


func _clear_shadow() -> void:
	if is_instance_valid(_shadow_decoy):
		_shadow_decoy.queue_free()
	_shadow_decoy = null
	_shadow_active = false
	_shadow_timer = 0.0


## Nollaa yhdistelmätilat tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_reset_shade_state()


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_reset_shade_state()


func _reset_shade_state() -> void:
	_clear_shadow()
	if _active_shuriken != null and is_instance_valid(_active_shuriken):
		_active_shuriken.queue_free()
	_active_shuriken = null
	_empower_timer = 0.0
	_charge = 0


## Paikalleen jäävä harhakuva, joka haihtuu hitaasti.
class Decoy:
	extends Node2D

	var lifetime := 2.2
	var body_color := Color.WHITE
	var facing := Vector2.RIGHT
	var _age := 0.0

	func _ready() -> void:
		z_index = 1

	## Kaato uusii varjon: ikä nollaan ja uusi kesto.
	func refresh(new_lifetime: float) -> void:
		lifetime = new_lifetime
		_age = 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = clampf(1.0 - _age / lifetime, 0.0, 1.0) * 0.65
		draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 22.0, Color(0.02, 0.03, 0.08, 0.3 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(Vector2(0, -14), 18.0, Palette.with_alpha(Palette.darker(body_color, 0.5), fade))
		draw_circle(Vector2(0, -14), 15.0, Palette.with_alpha(body_color, fade))
		var perp: Vector2 = facing.orthogonal().normalized() * 6.0
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(0, -18) + perp * side + facing * 2.5, 3.0,
				Palette.with_alpha(Color.WHITE, fade))


## Paluushuriken: lentää ulos, palaa (auto tai kutsuttaessa) ja osuu molempiin
## suuntiin. Ulosveto naputtaa, paluuveto teloittaa (ks. Shade.shuriken_hit).
## Kun se saavuttaa Shaden (koppi), Shaden jäähdytys lyhenee.
class Shuriken:
	extends Node2D

	var source: Shade = null
	var direction := Vector2.RIGHT
	var color := Color("b48aff")
	var speed := 940.0
	var hit_radius := 30.0
	var out_time := 0.42
	var kb := 110.0
	var catch_radius := 36.0
	var returning := false
	var _t := 0.0
	var _out := 0.0
	var _return_target := Vector2.ZERO
	var _hit: Array = []

	func _ready() -> void:
		z_index = 20

	func _physics_process(delta: float) -> void:
		_t += delta
		if source == null or not is_instance_valid(source) or not source.alive:
			queue_free()
			return
		var arena = source.arena
		if arena == null:
			queue_free()
			return
		if not returning:
			_out += delta
			global_position += direction * speed * delta
			if _out >= out_time:
				_start_return()
		else:
			if global_position.distance_to(source.global_position) < catch_radius:
				source.on_shuriken_caught()
				_pop(arena)
				queue_free()
				return
			var to_t: Vector2 = _return_target - global_position
			if to_t.length() < 22.0:
				source.on_shuriken_expired()
				_pop(arena)
				queue_free()
				return
			global_position += to_t.normalized() * (speed * 1.1) * delta
		_hit_pass(arena)
		queue_redraw()

	func _start_return() -> void:
		returning = true
		_return_target = source.global_position
		_hit.clear()

	func recall() -> void:
		if not returning:
			_start_return()

	func _hit_pass(arena) -> void:
		for enemy in arena.alive_enemies(source.team):
			if enemy in _hit:
				continue
			if global_position.distance_to(enemy.global_position) < hit_radius + enemy.radius:
				_hit.append(enemy)
				var kbdir: Vector2 = direction
				if returning:
					kbdir = (enemy.global_position - global_position).normalized()
				source.shuriken_hit(enemy, returning, kbdir)

	func _pop(arena) -> void:
		Fx.burst(arena, global_position, Palette.with_alpha(color, 0.7), 8, 160.0, 0.4, 5.0)

	func _draw() -> void:
		var spin := _t * 18.0
		# Paluuveto piirtyy kirkkaampana: se on teloitusveto, ei naputus.
		var body: Color = Palette.glow(color, 1.9 if returning else 1.4)
		for rot in [0.0, PI * 0.25]:
			var pts := PackedVector2Array()
			for k in range(4):
				var a: float = spin + float(rot) + k * PI * 0.5
				pts.append(Vector2(cos(a), sin(a)) * (16.0 if returning else 14.0))
			draw_colored_polygon(pts, body)
		draw_circle(Vector2.ZERO, 4.0, Palette.glow(Color.WHITE, 1.3))


## Tasoskaalaus: varjoassassiini — hauras, mutta teloitus- ja kykyvahinko
## kasvavat rajusti. Yhdessä itemikäyrän kanssa Shade on aito snowball-rooli.
func _level_scaling() -> Dictionary:
	return {"hp": 0.70, "damage": 1.25, "spell": 1.35, "melee": 1.28, "regen": 1.0}


## Väistön kehitys: faasi (varjo kulkee seinien läpi).
func _dodge_evolution() -> String:
	return "phase"


## Botin rankkausjärjestys: Paluushuriken (teloitus) ensin, Varjoloikka toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "a1", "basic", "dodge"]
