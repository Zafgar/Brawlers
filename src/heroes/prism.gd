class_name Prism
extends Hero
## Tuki (mana): Prisma. Kanavoi säteitä — toinen vahingoittaa ja hidastaa
## vihollisia (R1), toinen parantaa liittolaisia (L1). Ultimate on pidä-ja-
## vapauta-alue, joka buffaa sisällä olevien liittolaisten vahinkoa ja vauhtia.
## Botit käyttävät säteitä kertapurskeina ja ultin välittömästi.

const BEAM_RANGE := 430.0
const BEAM_WIDTH := 26.0
const BEAM_DPS := 30.0             # matalampi vahinko (oli 55, aika OP)
const BEAM_HPS := 46.0
const BEAM_SLOW := 0.5             # voimakkaampi hidastus (0.5 = puolinopeus)
const BEAM_TICK := 0.15            # vaikutus tikeittäin (ei popup-spämmiä)
const MANA_DMG_PER_SEC := 30.0     # polttosäde kuluttaa enemmän manaa
const MANA_HEAL_PER_SEC := 18.0    # hoitosäde kuluttaa vähemmän

const ULT_RADIUS := 220.0
const ULT_DUR := 6.0

var _beam_tick := 0.0


func _init() -> void:
	radius = 24.0


## Mana: säteet kuluttavat manaa jatkuvasti; palautuu passiivisesti.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 14.0
	res_cost = {"basic": 0.0, "a1": 28.0, "a2": 16.0, "dodge": 0.0}
	cd_max.a1 = 0.4
	cd_max.a2 = 0.4


## Perushyökkäys: kevyt valoammus (ilmainen).
func _basic(dir: Vector2) -> void:
	AudioMgr.play("light", 0.12, 2.0)
	visual.attack_swing()
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 920.0,
		"dmg": 12.0,
		"radius": 9.0,
		"life": 0.7,
		"kb": 70.0,
		"color": hero_color(),
		"visual": "prism_shard",
	})


func _channeled_slots() -> Array:
	return ["a1", "a2"]


## Kanavointi (ihmispelaaja): jatkuva säde + manan kulutus + vaikutus tikeittäin.
func _channel_tick(slot: String, delta: float) -> void:
	var mana_cost: float = MANA_DMG_PER_SEC if slot == "a1" else MANA_HEAL_PER_SEC
	res = maxf(res - mana_cost * delta, 0.0)
	_beam_active = true
	_beam_len = BEAM_RANGE
	_beam_heal = slot == "a2"
	_beam_tick -= delta
	if _beam_tick > 0.0:
		return
	_beam_tick = BEAM_TICK
	if slot == "a1":
		for enemy in _beam_targets(1, aim):
			deal_damage_to(enemy, BEAM_DPS * BEAM_TICK, 0.0)
			enemy.apply_slow(BEAM_SLOW, 0.4)
			Fx.spark(arena, enemy.global_position, Palette.glow(hero_color(), 1.4))
	else:
		for ally in _beam_targets(0, aim):
			if ally == self:
				continue
			ally.heal_hp(BEAM_HPS * BEAM_TICK, self)


func _channel_end(_slot: String) -> void:
	_beam_active = false
	_beam_tick = 0.0


## Botti-vara: kertapurske polttosädettä tähtäyssuuntaan.
func _ability1(dir: Vector2) -> void:
	AudioMgr.play("light", 0.1, -2.0)
	Fx.beam(arena, global_position + dir * 20.0, global_position + dir * BEAM_RANGE,
		Palette.glow(hero_color(), 1.4), 8.0)
	for enemy in _beam_targets(1, dir):
		deal_damage_to(enemy, 13.0, 0.0)
		enemy.apply_slow(BEAM_SLOW, 1.0)


## Botti-vara: kertapurske hoitosädettä heikoimman liittolaisen suuntaan.
## HUOM: hoitosäde tähdätään AINA liittolaiseen. Jos parannettavaa liittolaista
## ei ole, sädettä EI ammuta lainkaan — ettei vihreä hoitosäde lähde vihollista
## tai viidakko-olentoa kohti (näytti "healaavan hirviötä" + hukkasi loitsun).
func _ability2(_dir: Vector2) -> void:
	var low := _lowest_ally()
	if low == null:
		return
	var beam_dir: Vector2 = (low.global_position - global_position).normalized()
	AudioMgr.play("heal", 0.1)
	Fx.beam(arena, global_position + beam_dir * 20.0, global_position + beam_dir * BEAM_RANGE,
		Color("6affa0"), 8.0)
	for ally in _beam_targets(0, beam_dir):
		if ally == self:
			continue
		ally.heal_hp(30.0, self)


func _beam_targets(rel: int, dir: Vector2) -> Array:
	# rel: 1 = viholliset, 0 = liittolaiset
	var results: Array = []
	if dir.length() < 0.1:
		return results
	var d: Vector2 = dir.normalized()
	var list: Array = arena.alive_enemies(team) if rel == 1 else arena.alive_allies(team)
	for h in list:
		var to: Vector2 = h.global_position - global_position
		var along: float = to.dot(d)
		if along < 0.0 or along > BEAM_RANGE:
			continue
		var perp: float = (to - d * along).length()
		if perp < BEAM_WIDTH + h.radius:
			results.append(h)
	return results


func _lowest_ally() -> Hero:
	var best: Hero = null
	var worst := 1.0
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			best = ally
	return best


## Väistö: nopea valonpyrähdys.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 950.0, 0.14, true)
	AudioMgr.play("dash", 0.12, 2.0)
	Fx.dust(arena, global_position)


# --- Ultimate: pidä-ja-vapauta-alue ---

func _ult_is_held() -> bool:
	return true


func _ult_preview_radius() -> float:
	return ULT_RADIUS


## Loistokehä: alueen sisällä olevat liittolaiset saavat lisää vahinkoa ja
## vauhtia. (Punainen buffi = +vahinko, haste = +nopeus.)
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "LOISTOKEHÄ!", Palette.glow(hero_color(), 1.5), 26)
	AudioMgr.play("blessing", 0.05, -2.0)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.6), ULT_RADIUS, 0.8, 8.0)
	Fx.burst(arena, global_position, Palette.with_alpha(hero_color(), 0.7), 20, 300.0, 0.6, 6.0)
	for ally in arena.heroes_in_circle(global_position, ULT_RADIUS, team):
		ally.red_buff = maxf(ally.red_buff, ULT_DUR)
		ally.apply_haste(1.3, ULT_DUR)
		Fx.ring(arena, ally.global_position, Palette.glow(hero_color(), 1.4), 46.0, 0.5)
