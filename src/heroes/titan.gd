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


## Kyky 1: Tartu ja heitä. Berserkissä muuttuu alueen ilmaanheitoksi.
func _ability1(dir: Vector2) -> void:
	if _berserk > 0.0:
		_aoe_launch()
		return

	var target := _grab_target(dir)
	if target == null:
		# Ei kohdetta -> lyhyt kurotus tyhjään.
		AudioMgr.play("swing", 0.1, -8.0)
		visual.attack_swing()
		Fx.spark(arena, global_position + dir * GRAB_RANGE * 0.6,
			Palette.with_alpha(hero_color(), 0.7))
		return

	AudioMgr.play("slam", 0.1, -2.0)
	arena.shake(0.2)
	visual.squash(1.2, 0.82)
	# Heitto tähtäyssuuntaan: nakkaa vihollisen pois ja tainnuttaa.
	deal_damage_to(target, GRAB_DMG, THROW_KB, dir)
	target.apply_stun(GRAB_STUN)
	target.visual.squash(0.7, 1.4)
	Fx.burst(arena, target.global_position, Palette.glow(hero_color(), 1.5), 14, 300.0, 0.4, 6.0)
	Fx.ring(arena, target.global_position, Palette.glow(hero_color(), 1.4), 46.0, 0.35)
	arena.popup(target.global_position + Vector2(0, -70), "HEITTO!", Palette.glow(hero_color(), 1.4), 18)


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


## Berserk nollataan tyrmäyksestä ja erän vaihtuessa, jottei se jää päälle.
func _respawn() -> void:
	super()
	_berserk = 0.0


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_berserk = 0.0
