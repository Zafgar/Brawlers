class_name Hush
extends Hero
## Tuki: vaimennuskello. Kontrollituki — suojaa liittolaisia isoilla kilvillä
## (paljon enemmän kuin parantaa), tukahduttaa vihollisten liikkeen ja kyvyt.
## Passiivi: lähetä vartioiva kaikupulssi, joka kilpiää haavoittuneimman
## liittolaisen tasaisin väliajoin.
##
## TASAPAINO (72 ottelun mittaus): Hush vaimensi 1164 ottelussa ja teki 167
## vahinkoa/min — kontrollituki, jonka kontrolli ei ratkaissut mitään. Kilvet
## kaksinkertaistettiin ja ne skaalautuvat nyt tasolla ja kykyvahingolla
## (support_power); kenttä puree kovempaa ja Suuri Vaimennus tainnuttaa
## pidempään. Ulti pysyy tarkoituksella VAHINGOTTOMANA: identiteetti on
## kontrolli, ja arvo mitataan CC-sekunneissa.

const SHIELD_AMOUNT := 130.0         # a1: iso kilpi (oli 65; identiteetti: kilpi >> heal)
const SHIELD_DUR := 5.5
const SHIELD_HEAL := 30.0            # a1: paikkaus kilven päälle (oli 14)
const SHIELD_RANGE := 520.0

const FIELD_RADIUS := 140.0          # a2: dissonanssikenttä
const FIELD_DUR := 4.5
const FIELD_SLOW := 0.55
const FIELD_DPS := 26.0              # a2: kentän kalvaminen (oli 12)

const ULT_RADIUS := 260.0            # ult: Suuri Vaimennus
const ULT_RANGE := 560.0
const ULT_STUN := 0.8                # ult: tainnutus (oli 0.65)
const ULT_ROOT := 1.25
const ULT_SILENCE := 3.0

const PULSE_INTERVAL := 3.5          # passiivi: kilpipulssin väli
const PULSE_SHIELD := 34.0           # passiivi: pulssikilpi (oli 16)
const PULSE_DUR := 3.0
const PULSE_RANGE := 260.0

const DODGE_SHIELD := 70.0           # väistö: haamukellon jättämä kilpi (oli 40)
const BASIC_DMG := 19.0              # perus: kaikuisku (oli 13)

var _pulse_timer := 0.0


func _init() -> void:
	radius = 24.0


## Mana: kilvet ja kenttä maksavat manaa mutta jäähtyvät nopeasti — voit
## ketjuttaa suojia kunnes mana loppuu, sitten se palautuu. Perus on ilmainen.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 13.0
	res_cost = {"basic": 0.0, "a1": 26.0, "a2": 30.0, "dodge": 0.0}
	cd_max.a1 = 7.0
	cd_max.a2 = 8.0


## Dissonanssikenttä tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a2"]


func _aim_range(_slot: String) -> float:
	return 520.0


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_default_range(_slot: String) -> float:
	return 360.0


func _aim_target_radius(_slot: String) -> float:
	return FIELD_RADIUS


## Perushyökkäys: Kaikuisku — läpäisevä ääniammus, joka nakuttaa vihollisia.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("light", 0.1, -4.0)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(hero_color(), 1.4))
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 820.0,
		"dmg": BASIC_DMG,
		"radius": 11.0,
		"life": 0.9,
		"kb": 90.0,
		"pierce": 1,
		"color": Color("c7a8ff"),
		"visual": "hush_wave",
	})


## Kyky 1: Suojasointu — iso suojakilpi eniten kärsineelle liittolaiselle
## (identiteetti: kilpiää paljon enemmän kuin parantaa). Pieni paikkaus päälle.
func _ability1(_dir: Vector2) -> void:
	var target: Hero = _lowest_ally()
	if target == null:
		target = self
	AudioMgr.play("shield")
	if target != self:
		Fx.beam(arena, global_position, target.global_position, Palette.glow(hero_color(), 1.3))
	var power := support_power()
	target.add_shield(SHIELD_AMOUNT * power, SHIELD_DUR, self)
	target.heal_hp(SHIELD_HEAL * power, self)
	Fx.ring(arena, target.global_position, Palette.glow(Palette.SHIELD, 1.5), 62.0, 0.4)
	arena.popup(target.global_position + Vector2(0, -70), "SUOJATTU", Palette.SHIELD, 16)


## Eniten kärsinyt liittolainen kantamalla (ei itse). Null jos ketään sopivaa.
func _lowest_ally() -> Hero:
	var target: Hero = null
	var worst := 1.1
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		if ally.global_position.distance_to(global_position) > SHIELD_RANGE:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			target = ally
	return target


## Kyky 2: Dissonanssikenttä — heittää tähtäyksen suuntaan alueen, joka
## hidastaa voimakkaasti ja kalvaa vihollisia (slow + DoT).
func _ability2(dir: Vector2) -> void:
	var target := aimed_ground_position(dir, 520.0, 360.0)
	var travel := target - global_position
	var cast_dir := travel.normalized() if travel.length() > 1.0 else dir.normalized()
	AudioMgr.play("light", 0.08, -8.0)
	Projectile.launch(self, global_position + cast_dir * 30.0, cast_dir, {
		"speed": 680.0,
		"dmg": 6.0,
		"radius": 12.0,
		"life": maxf(travel.length() - 30.0, 20.0) / 680.0,
		"kb": 40.0,
		"color": Color("a678f0"),
		"visual": "hush_field_seed",
		"on_hit": Callable(self, "_field_on_hit"),
		"on_expire": Callable(self, "_spawn_field"),
	})


func _field_on_hit(hit_hero: Hero, proj: Projectile) -> void:
	if hit_hero != null:
		_spawn_field(proj.global_position)


func _spawn_field(pos: Vector2) -> void:
	if arena == null or not is_inside_tree():
		return
	AudioMgr.play("light", 0.1, -10.0)
	Zone.spawn(self, arena.map.clamp_to_field(pos, FIELD_RADIUS), {
		"type": "hush",
		"radius": FIELD_RADIUS,
		"dur": FIELD_DUR,
		"slow_f": FIELD_SLOW,
		"dps": FIELD_DPS,
	})


## Väistö (X): Haamukello — hetkellinen immuniteetti + nopea haamuliike seinien
## läpi, sekä pieni jäljelle jäävä suojakilpi. Pitkä jäähdytys.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 780.0, 0.45, true, true)   # iframes koko liu'un ajan = immuniteetti
	apply_haste(1.35, 1.3)
	add_shield(DODGE_SHIELD * support_power(), 2.2, self)
	AudioMgr.play("dash", 0.1, 4.0)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.5), 52.0, 0.4)
	Fx.dust(arena, global_position)


# --- Ultimate: pidä-ja-vapauta-alue (Suuri Vaimennus) ---

func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return ULT_RANGE


func _ult_default_range() -> float:
	return 380.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


## Suuri Vaimennus: iso alue, joka tainnuttaa, juurruttaa ja vaimentaa
## viholliset — ei lainkaan vahinkoa, pelkkää kovaa kontrollia.
func _ultimate(dir: Vector2) -> void:
	var target := aimed_ult_ground_position(dir)
	target = arena.map.clamp_to_field(target, ULT_RADIUS * 0.35)
	arena.popup(global_position + Vector2(0, -84), "SUURI VAIMENNUS!",
		Palette.glow(hero_color(), 1.5), 26)
	AudioMgr.play("hush_ult", 0.05, -2.0, target)
	Fx.ultimate_warning(arena, target, Palette.glow(Color("c7a8ff"), 1.5),
		Palette.team(team), ULT_RADIUS, 0.42, "hush")
	_great_silence(target)


func _great_silence(target: Vector2) -> void:
	await get_tree().create_timer(0.42).timeout
	if not is_inside_tree():
		return
	_act("ult")
	arena.shake(0.45)
	AudioMgr.play("hush_ult", 0.08, 2.0, target)
	Fx.flash(arena, target, Palette.glow(Color("c7a8ff"), 1.6), ULT_RADIUS * 0.6, 0.5)
	Fx.vortex(arena, target, Palette.glow(hero_color(), 1.4), ULT_RADIUS, 1.1)
	Fx.ring(arena, target, Palette.glow(hero_color(), 1.5), ULT_RADIUS, 0.7, 8.0)
	Fx.ultimate_field(arena, target, hero_color(), Palette.team(team), ULT_RADIUS, ULT_SILENCE, "hush")
	for enemy in arena.heroes_in_circle(target, ULT_RADIUS, 1 - team, true, true):
		enemy.apply_stun(ULT_STUN)
		enemy.apply_root(ULT_ROOT)
		enemy.apply_silence(ULT_SILENCE)
		Fx.ring(arena, enemy.global_position, Palette.glow(hero_color(), 1.3), 46.0, 0.5)
	_act_end()


## Passiivi: Vartijan kaiku — tasaisin väliajoin pulssi, joka kilpiää
## haavoittuneimman lähiliittolaisen. Tukee kilpi-identiteettiä ilman manaa.
func _passive_update(delta: float) -> void:
	_pulse_timer += delta
	if _pulse_timer < PULSE_INTERVAL:
		return
	var target: Hero = null
	var worst := 1.0
	var amount := PULSE_SHIELD * support_power()
	for ally in arena.alive_allies(team):
		if ally.global_position.distance_to(global_position) > PULSE_RANGE:
			continue
		# Ohita liittolaiset joilla on jo merkittävä kilpi: add_shield ylikirjoittaa
		# keston, joten pieni pulssi lyhentäisi Suojasoinnun ison kilven kestoa.
		if ally.shield_hp >= amount:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			target = ally
	if target == null:
		_pulse_timer = PULSE_INTERVAL - 0.25   # ei täyttä nollausta -> kevyt uudelleenyritys, ei joka-framen skannaus
		return
	_pulse_timer = 0.0
	target.add_shield(amount, PULSE_DUR, self)
	Fx.ring(arena, target.global_position, Palette.with_alpha(Palette.SHIELD, 0.8), 40.0, 0.35)


## Tasoskaalaus: kontrollituki — maltillinen vahinko, vahva regen.
func _level_scaling() -> Dictionary:
	return {"hp": 0.95, "damage": 0.80, "spell": 0.85, "melee": 0.85, "regen": 1.20}


## Väistön kehitys: puhdistus (tuki irtoaa kontrollista auttaakseen).
func _dodge_evolution() -> String:
	return "cleanse"


## Botin rankkausjärjestys: Kilvet ensin, dissonanssikenttä toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "dodge", "basic"]
