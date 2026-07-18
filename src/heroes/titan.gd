class_name Titan
extends Hero
## Tankki: rautakourainen jättiläinen. Tekee vähän vahinkoa mutta kestää
## valtavasti. Nappaa vihollisen kiinni ja heittää pois, kanavoi raivosuojaa
## kestääkseen enemmän, ja muuttuu ultissaan berserkiksi joka nakkaa
## lähiviholliset ilmaan.
## Passiivi: kestää tönäisyt hyvin.

const SWING_RANGE := 100.0
const SWING_ARC_DEG := 75.0
const SWING_DMG := 8.0
const GRAB_CD_REFUND := 1.3        # jokainen perusosuma lyhentää a1:tä

const GRAB_RANGE := 132.0
const GRAB_ARC_DEG := 62.0
const GRAB_DMG := 10.0
const THROW_KB := 780.0
const GRAB_STUN := 0.75
const GRAB_HOLD_DIST := 54.0        # kuinka kaukana edessä kohdetta pidetään
const GRAB_MAX_HOLD := 1.1          # pisin tähtäysaika ennen automaattista heittoa
const GRAB_AIM_LEN := 250.0         # heiton tähtäysviivan pituus

const RAGE_DRAIN := 18.0            # raivon kulutus/s suojaa kanavoitaessa
const BRACE_HPS := 28.0            # elämän palautus/s suojan aikana
const BRACE_ABSORB := 0.55         # vaimennettu osuus otetusta vahingosta

const BERSERK_DUR := 8.0
const BERSERK_HASTE := 1.4
const BERSERK_BASIC_CD_MULT := 0.42
const BERSERK_DMG_MULT := 2.0

const AOE_LAUNCH_RADIUS := 210.0
const AOE_LAUNCH_DMG := 14.0
const AOE_LAUNCH_KB := 340.0
const AOE_LAUNCH_STUN := 0.95

# Bottien kertakäyttöinen suoja (ne eivät osaa kanavoida).
const BOT_BRACE_GUARD := 2.2
const BOT_BRACE_HEAL := 55.0

var _berserk := 0.0                # berserk-tilan aika jäljellä (0 = ei)
var _brace_fx := 0.0               # suojatehosteen ajastin
var _held_target: Hero = null      # tartuttu kohde (pidetään edessä ennen heittoa)
var _hold_time := 0.0              # kuinka kauan kohdetta on pidetty


func _init() -> void:
	kb_resist = 0.6
	radius = 31.0


## Raivo: kertyy taistelusta (vahingon anto ja otto). Raivosuoja (L1) kuluttaa
## raivoa vähentääkseen otettua vahinkoa ja parantaakseen. Ulti latautuu
## erikseen. Perusiskut ja tartunta eivät maksa raivoa.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	# a2:n kustannus koskee vain botteja (ne käyttävät _ability2-kertasuojaa);
	# ihmisen kanavointi kuluttaa raivoa _channel_tickissä eikä kertakuluna.
	res_cost = {"basic": 0.0, "a1": 0.0, "a2": 35.0, "dodge": 0.0}


## Raivosuoja kanavoidaan pitämällä L1 pohjassa.
func _channeled_slots() -> Array:
	return ["a2"]


func _channel_tick(_slot: String, delta: float) -> void:
	# Kaikkisuuntainen vaimennus (180° kaari) niin kauan kuin raivoa riittää.
	start_guard(0.2, BRACE_ABSORB, 180.0)
	res = maxf(res - RAGE_DRAIN * delta, 0.0)
	if hp < max_hp:
		hp = minf(hp + BRACE_HPS * delta, max_hp)
	_brace_fx -= delta
	if _brace_fx <= 0.0:
		_brace_fx = 0.22
		Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.3), radius + 16.0, 0.3, 4.0)
		Fx.heal_sparkle(arena, global_position)
	if res <= 0.0:
		guard_timer = 0.0        # raivo loppui -> suoja putoaa heti


func _channel_end(_slot: String) -> void:
	AudioMgr.play("ui_back", 0.05, -4.0)
	visual.squash(1.1, 0.9)


## Perushyökkäys: raskas murskaava isku. Jokainen osuma lyhentää tartuntaa.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.1, -5.0)
	var dmg: float = SWING_DMG * (BERSERK_DMG_MULT if _berserk > 0.0 else 1.0)
	Fx.slash(arena, global_position, dir, SWING_RANGE, SWING_ARC_DEG, hero_color())
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SWING_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SWING_ARC_DEG:
			continue
		deal_damage_to(enemy, dmg, 240.0, to_enemy.normalized())
		hits += 1
	if hits > 0:
		# Osuma lataa tartunnan nopeammin uudelleen ("lyö -> kyky palaa").
		cd.a1 = maxf(cd.a1 - GRAB_CD_REFUND, 0.0)
		arena.shake(0.1)
		Fx.spark(arena, global_position + dir * SWING_RANGE * 0.7, hero_color())


## Tartunta tähdätään: pidä R1 pohjassa (nappaa edessä olevan vihollisen),
## käännä tähtäys ja vapauta heittääksesi. Berserkissä a1 ei tähtää.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return GRAB_AIM_LEN


## Tähtäyksen aloitus (R1 painettu): berserkissä välitön alueheitto; muuten
## yritä napata edessä oleva kohde. Palauta false jos ei kohdetta -> ei tähtäystä.
func _aim_begin(_slot: String) -> bool:
	if _berserk > 0.0:
		if cd.a1 <= 0.0:
			cd.a1 = cd_max.a1
			_aoe_launch()
		return false
	var t := _grab_target(aim)
	if t == null:
		return false
	_held_target = t
	_hold_time = 0.0
	t.global_position = global_position + aim * GRAB_HOLD_DIST
	t.velocity = Vector2.ZERO
	t.apply_stun(0.3)
	AudioMgr.play("slam", 0.1, -4.0)
	visual.squash(1.15, 0.85)
	Fx.ring(arena, t.global_position, Palette.glow(hero_color(), 1.4), 42.0, 0.3)
	arena.popup(global_position + Vector2(0, -84), "TARTU!", Palette.glow(hero_color(), 1.3), 16)
	return true


## Tähtäyksen aikana: pidä kohde edessä tähtäyssuuntaan; heitä automaattisesti
## jos aikaraja täyttyy tai berserk alkaa kesken tartunnan.
func _aim_hold(_slot: String, delta: float) -> void:
	if _berserk > 0.0:
		_drop_target()
		_aiming_slot = ""
		return
	if _held_target == null or not is_instance_valid(_held_target) or not _held_target.alive:
		_held_target = null
		_aiming_slot = ""
		return
	_hold_time += delta
	_held_target.global_position = global_position + aim * GRAB_HOLD_DIST
	_held_target.velocity = Vector2.ZERO
	_held_target.apply_stun(0.2)
	if _hold_time >= GRAB_MAX_HOLD:
		cd.a1 = cd_max.a1
		_throw_target(_held_target, aim)
		_held_target = null
		_aiming_slot = ""


## Kyky 1 laukeaa: ihmisellä vapautuksesta (heitä pidelty kohde), botilla ja
## berserkissä välittömästi.
func _ability1(dir: Vector2) -> void:
	if _berserk > 0.0:
		_aoe_launch()
		return
	if _held_target != null and is_instance_valid(_held_target) and _held_target.alive:
		_throw_target(_held_target, dir)
		_held_target = null
		return
	# Botti / varapolku: välitön tartunta ja heitto.
	var target := _grab_target(dir)
	if target == null:
		AudioMgr.play("swing", 0.1, -8.0)
		visual.attack_swing()
		Fx.spark(arena, global_position + dir * GRAB_RANGE * 0.6,
			Palette.with_alpha(hero_color(), 0.7))
		return
	_throw_target(target, dir)


## Heittää kohteen annettuun suuntaan tainnutuksella.
func _throw_target(target: Hero, dir: Vector2) -> void:
	AudioMgr.play("slam", 0.1, -1.0)
	arena.shake(0.25)
	visual.squash(1.25, 0.8)
	deal_damage_to(target, GRAB_DMG, THROW_KB, dir)
	target.apply_stun(GRAB_STUN)
	target.visual.squash(0.7, 1.4)
	Fx.burst(arena, target.global_position, Palette.glow(hero_color(), 1.5), 14, 320.0, 0.4, 6.0)
	Fx.ring(arena, target.global_position, Palette.glow(hero_color(), 1.4), 46.0, 0.35)
	arena.popup(target.global_position + Vector2(0, -70), "HEITTO!", Palette.glow(hero_color(), 1.4), 18)


## Pudottaa pidellyn kohteen heittämättä (tähtäys keskeytyi).
func _drop_target() -> void:
	_held_target = null


## Berserkin alueheitto: kaikki lähiviholliset lentävät ilmaan.
func _aoe_launch() -> void:
	AudioMgr.play("quake", 0.05, 1.0)
	arena.shake(0.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), AOE_LAUNCH_RADIUS, 0.55, 8.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.6), AOE_LAUNCH_RADIUS * 0.6, 0.4, 5.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position, AOE_LAUNCH_RADIUS):
		if enemy.team == team:
			continue
		var away: Vector2 = (enemy.global_position - global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		deal_damage_to(enemy, AOE_LAUNCH_DMG, AOE_LAUNCH_KB, away)
		enemy.apply_stun(AOE_LAUNCH_STUN)
		enemy.visual.squash(0.65, 1.5)
		Fx.spark(arena, enemy.global_position, Palette.glow(hero_color(), 1.5))
		arena.popup(enemy.global_position + Vector2(0, -74), "ILMAAN!", Palette.glow(hero_color(), 1.4), 16)


## Etummainen tartuttava kohde tähtäyskaaren sisällä.
func _grab_target(dir: Vector2) -> Hero:
	var best: Hero = null
	var best_dist := GRAB_RANGE + 40.0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var d := to_enemy.length()
		if d > GRAB_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > GRAB_ARC_DEG:
			continue
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## Kyky 2 (vain botit): kertakäyttöinen puolustusryhti + parannus, koska botit
## eivät kanavoi. Kustannus (raivo) hoidetaan res_costin kautta.
func _ability2(_dir: Vector2) -> void:
	start_guard(BOT_BRACE_GUARD, BRACE_ABSORB, 180.0)
	heal_hp(BOT_BRACE_HEAL, self)
	AudioMgr.play("guard_up")
	Fx.ring(arena, global_position, Palette.glow(Palette.SHIELD, 1.4), radius + 18.0, 0.4, 6.0)


## Väistö: raskas rynnäkkö, joka tönäisee ja hidastaa osuessaan.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 820.0, 0.22, false)
	AudioMgr.play("dash", 0.1, -5.0)
	Fx.dust(arena, global_position)
	for enemy in arena.heroes_in_circle(global_position + dir * 55.0, 82.0):
		if enemy.team == team:
			continue
		deal_damage_to(enemy, 8.0, 420.0, dir)
		enemy.apply_slow(0.65, 1.0)


## Ultimate: Raivotila — berserk. Nopeampi, vahvempi ja tartunta muuttuu
## alueheitoksi. Punainen buffi ultin ajaksi antaa +vahinko-auran ja
## elämän palautuksen.
func _ultimate(_dir: Vector2) -> void:
	_berserk = BERSERK_DUR
	red_buff = maxf(red_buff, BERSERK_DUR)
	apply_haste(BERSERK_HASTE, BERSERK_DUR)
	arena.popup(global_position + Vector2(0, -90), "RAIVOTILA!", Palette.glow(hero_color(), 1.6), 28)
	AudioMgr.play("quake", 0.05, -1.0)
	arena.shake(0.4)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.5), 120.0, 0.5)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), 200.0, 0.7, 9.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.6), 130.0, 0.5, 5.0)


## Berserkin ajastin; iskunopeus nopeutuu berserkissä (_attack_control).
func _attack_control(held: bool, _just_pressed: bool, _just_released: bool,
		dir: Vector2, _delta: float) -> void:
	if held and cd.basic <= 0.0:
		cd.basic = cd_max.basic * (BERSERK_BASIC_CD_MULT if _berserk > 0.0 else 1.0)
		_basic(dir)


func _passive_update(delta: float) -> void:
	if _berserk > 0.0:
		_berserk = maxf(_berserk - delta, 0.0)
	# Jos tartunta oli käynnissä mutta tähtäys keskeytyi (tainnutus, tyrmäys,
	# jäätyminen tms.) ilman heittoa, pudota kohde. Vapautus/heitto tyhjentää
	# _held_targetin itse, joten tähän jää vain oikeat keskeytykset.
	if _held_target != null and _aiming_slot != "a1":
		_held_target = null


## Berserk ja tartunta nollataan tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_berserk = 0.0
	_held_target = null


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_berserk = 0.0
	_held_target = null
