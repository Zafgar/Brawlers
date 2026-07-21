class_name Lance
extends Hero
## Fighter/kaksintaistelija: teräskeihäs. Merkkien mestari — kasaa
## kaksintaistelumerkkejä kohteisiin ja viimeistelee ne isolla iskulla.
## Perus merkitsee joka 3. osumalla; 3 merkkiä laukaisee viimeistelyn
## (bonusvahinko + elinvoiman imu + vauhti). Lävistyssyöksy menee seinien ja
## sankarien läpi merkiten matkalla, pyörremyrsky vahingoittaa ja vaimentaa,
## ja ultti loikkaa kaukaa tähdättyyn pisteeseen.
## Passiivi: kerää raivoa taistelusta.

const THRUST_RANGE := 132.0
const THRUST_ARC_DEG := 34.0
const THRUST_DMG := 15.0

const DETONATE_DMG := 40.0          # 3 merkin viimeistely
const DETONATE_HEAL := 45.0
const DETONATE_HASTE := 1.35
const DETONATE_HASTE_DUR := 2.5

const DASH_SPEED := 1250.0
const DASH_DUR := 0.26
const DASH_DMG := 12.0

const WHIRL_TICKS := 4
const WHIRL_INTERVAL := 0.3
const WHIRL_RADIUS := 156.0
const WHIRL_DMG := 9.0
const WHIRL_SILENCE := 0.45

const ULT_RANGE := 520.0
const ULT_LEAP_SPEED := 1500.0
const ULT_RADIUS := 176.0
const ULT_DMG := 45.0
const ULT_STUN := 0.9
const ULT_KB := 300.0
const ULT_FRENZY_DUR := 5.0
const FRENZY_BASIC_CD_MULT := 0.5   # ult: perusisku kaksi kertaa nopeammin

var _thrust_count := 0              # perusiskujen laskuri (joka 3. merkitsee)
var _frenzy := 0.0                  # ultin iskunopeusbuffi jäljellä
var _spear_dashing := false         # lävistyssyöksy käynnissä (merkitsee läpi mentäessä)
var _dash_hits: Array = []          # tässä syöksyssä jo merkityt kohteet


func _init() -> void:
	radius = 25.0


## Raivo: kertyy taistelusta. Pyörremyrsky (L1) kuluttaa raivoa; syöksy ja
## perusiskut eivät maksa raivoa.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost = {"basic": 0.0, "a1": 0.0, "a2": 40.0, "dodge": 0.0}
	cd_max.a1 = 8.0
	cd_max.a2 = 8.0


## Lävistyssyöksy tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return DASH_SPEED * DASH_DUR


## Perushyökkäys: kapea keihäänpisto. Joka 3. osuma merkitsee kohteen; jos
## kohteessa on jo 3 merkkiä, isku viimeistelee ne.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.1, -2.0)
	Fx.slash(arena, global_position, dir, THRUST_RANGE, THRUST_ARC_DEG, hero_color())
	var target: Hero = _thrust_target(dir)
	if target == null:
		return
	deal_damage_to(target, THRUST_DMG, 150.0, dir)
	_thrust_count += 1
	if _thrust_count % 3 == 0:
		_mark_enemy(target)
	elif target.duel_marks >= 3:
		# Kohteessa on jo täydet merkit (esim. syöksystä/pyörteestä) -> viimeistele.
		_detonate_marks(target)


## Kapean pistokaaren lähin vihollissankari (ei yksiköitä ensisijaisesti, mutta
## osuu myös yksikköön jos se on ainoa edessä).
func _thrust_target(dir: Vector2) -> Hero:
	var best: Hero = null
	var best_dist := THRUST_RANGE + 60.0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var d := to_enemy.length()
		if d > THRUST_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > THRUST_ARC_DEG:
			continue
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## Lisää merkki kohteeseen; jos merkit täyttyvät (3), viimeistele heti.
func _mark_enemy(enemy: Hero) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_unit:
		return
	var n := enemy.add_duel_mark(self)
	Fx.spark(arena, enemy.global_position, Palette.glow(hero_color(), 1.4))
	arena.popup(enemy.global_position + Vector2(0, -58), "MERKKI %d" % n, hero_color(), 13)
	if n >= 3:
		_detonate_marks(enemy)


## Viimeistelyisku: kuluttaa merkit, tekee bonusvahingon, imee elinvoimaa ja
## antaa Lancelle vauhtia.
func _detonate_marks(enemy: Hero) -> void:
	enemy.consume_duel_marks()
	deal_damage_to(enemy, DETONATE_DMG, 260.0, (enemy.global_position - global_position).normalized())
	heal_hp(DETONATE_HEAL, self)
	apply_haste(DETONATE_HASTE, DETONATE_HASTE_DUR)
	AudioMgr.play("slam", 0.1, 2.0)
	arena.shake(0.25)
	Fx.burst(arena, enemy.global_position, Palette.glow(hero_color(), 1.6), 16, 300.0, 0.45, 6.0)
	Fx.ring(arena, enemy.global_position, Palette.glow(hero_color(), 1.5), 60.0, 0.4)
	arena.popup(enemy.global_position + Vector2(0, -76), "VIIMEISTELY!", Palette.glow(hero_color(), 1.5), 20)


## Kyky 1: Lävistyssyöksy — syöksy seinien ja sankarien läpi. Merkitsee jokaisen
## läpi mennyn vihollissankarin. Syöksyn aikana immuuni CC:lle.
func _ability1(dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	_dash_hits = []
	_spear_dashing = true
	dash(d, DASH_SPEED, DASH_DUR, true, true)   # iframes + seinien läpi
	set_collision_mask_value(2, false)          # myös sankarien läpi
	cc_immune_timer = DASH_DUR + 0.05
	AudioMgr.play("dash", 0.1, 0.0)
	visual.squash(0.65, 1.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.3), radius + 10.0, 0.3, 4.0)


## Kyky 2: Pyörremyrsky — pyörivä keihäs vahingoittaa ja vaimentaa lähiviholliset
## sekä merkitsee heidät. Vaikutus toistuu hetken (merkki kerran per kohde).
func _ability2(_dir: Vector2) -> void:
	AudioMgr.play("swing", 0.08, -4.0)
	_whirlwind()


func _whirlwind() -> void:
	var marked: Array = []
	for tick in range(WHIRL_TICKS):
		if not is_inside_tree() or not alive:
			return
		_act("a2")
		Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.4), WHIRL_RADIUS, 0.28, 6.0)
		visual.attack_swing()
		for enemy in arena.heroes_in_circle(global_position, WHIRL_RADIUS):
			if enemy.team == team:
				continue
			var away: Vector2 = (enemy.global_position - global_position).normalized()
			deal_damage_to(enemy, WHIRL_DMG, 60.0, away)
			enemy.apply_silence(WHIRL_SILENCE)
			if not enemy.is_unit and enemy not in marked:
				marked.append(enemy)
				_mark_enemy(enemy)
		_act_end()
		await get_tree().create_timer(WHIRL_INTERVAL).timeout


## Väistö: nopea sivuloikka.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.15, true)
	AudioMgr.play("dash", 0.1, 3.0)
	Fx.dust(arena, global_position)


# --- Ultimate: loikka kaukaa tähdättyyn pisteeseen ---

func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return ULT_RANGE


## Taivaankeihäs: loikkaa tähtäyssuuntaan kaukaiseen pisteeseen ja iskee alas
## aluevahingolla + tainnutuksella; Lance saa iskunopeusbuffin.
func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	var landing: Vector2 = global_position + d * ULT_RANGE
	if arena.map != null:
		landing = arena.map.clamp_to_field(landing, radius)
	var leap_dur: float = maxf(global_position.distance_to(landing) / ULT_LEAP_SPEED, 0.12)
	dash(d, ULT_LEAP_SPEED, leap_dur, true, true)   # iframes + seinien yli
	cc_immune_timer = leap_dur + 0.05
	arena.popup(global_position + Vector2(0, -90), "TAIVAANKEIHÄS!", Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("dash", 0.1, -4.0)
	visual.squash(0.6, 1.5)
	await get_tree().create_timer(leap_dur).timeout
	if not is_inside_tree() or not alive:
		return
	_ult_land()


func _ult_land() -> void:
	_act("ult")
	AudioMgr.play("slam", 0.1, -2.0)
	arena.shake(0.5)
	visual.squash(1.35, 0.7)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.5), ULT_RADIUS * 0.7, 0.5)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), ULT_RADIUS, 0.6, 9.0)
	Fx.burst(arena, global_position, Palette.glow(hero_color(), 1.5), 20, 360.0, 0.5, 6.0)
	for enemy in arena.heroes_in_circle(global_position, ULT_RADIUS):
		if enemy.team == team:
			continue
		var away: Vector2 = (enemy.global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		deal_damage_to(enemy, ULT_DMG, ULT_KB, away)
		enemy.apply_stun(ULT_STUN)
		Fx.spark(arena, enemy.global_position, Palette.glow(hero_color(), 1.5))
	_frenzy = ULT_FRENZY_DUR
	apply_haste(1.2, ULT_FRENZY_DUR)
	_act_end()


## Iskunopeus: ultin frenzy-tilassa perusisku laukeaa nopeammin.
func _attack_control(held: bool, _just_pressed: bool, _just_released: bool,
		dir: Vector2, _delta: float) -> void:
	if held and cd.basic <= 0.0:
		cd.basic = cd_max.basic * (FRENZY_BASIC_CD_MULT if _frenzy > 0.0 else 1.0)
		_basic(dir)


func _passive_update(delta: float) -> void:
	if _frenzy > 0.0:
		_frenzy = maxf(_frenzy - delta, 0.0)
	# Lävistyssyöksy: merkitse läpi mennyt vihollissankari; palauta sankaritörmäys
	# kun syöksy päättyy.
	if _spear_dashing:
		if dash_timer > 0.0:
			for enemy in arena.alive_enemies(team):
				if enemy.is_unit or enemy in _dash_hits:
					continue
				if enemy.global_position.distance_to(global_position) <= radius + enemy.radius + 14.0:
					_dash_hits.append(enemy)
					_act("a1")
					deal_damage_to(enemy, DASH_DMG, 0.0)
					_act_end()
					_mark_enemy(enemy)
		else:
			_spear_dashing = false
			set_collision_mask_value(2, true)


## Syöksytila ja frenzy nollataan tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_end_spear_dash()
	_frenzy = 0.0


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_end_spear_dash()
	_frenzy = 0.0
	_thrust_count = 0


## Varmista että sankaritörmäys on palautettu (jos syöksy keskeytyi).
func _end_spear_dash() -> void:
	if _spear_dashing:
		_spear_dashing = false
		set_collision_mask_value(2, true)
	_dash_hits = []
