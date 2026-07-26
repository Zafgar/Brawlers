class_name Luma
extends Hero
## Tuki: valosauva. Joukkueen sydän — parantaa, suojaa ja nopeuttaa.
## Passiivi: palautuu itsekseen nopeasti taistelun ulkopuolella.
##
## TASAPAINO (72 ottelun mittaus): Luma paransi 798 ottelussa, kun joukkue teki
## ~45 000 vahinkoa — 1.8 % vaikutus, eli pyöristysvirhe. Parannus- ja
## kilpiarvot nostettiin ~3x ja ne skaalautuvat nyt tasolla ja kykyvahingolla
## (support_power), joten Luman panos kasvaa ottelun mittaan. Hoitokehä myös
## polttaa vihollisia: parantaja ei ole enää pelkkä maalitaulu taistelussa.

const PULSE_DMG := 22.0             # perus: valopulssin vahinko (oli 12)
const PULSE_HEAL := 22.0            # perus: läpäisyparannus liittolaiselle (oli 12)

const BLOOM_RADIUS := 205.0         # a1: hoitokehä
const BLOOM_HEAL := 62.0            # a1: perusparannus (oli 32)
const BLOOM_MISSING := 0.05         # a1: + osuus kohteen puuttuvasta elämästä
const BLOOM_SEAR := 34.0            # a1: kehä polttaa vihollisia

const SHIELD_AMOUNT := 95.0         # a2: suojasäde (oli 50)
const SHIELD_DUR := 4.5
const SHIELD_RANGE := 520.0
const SHIELD_CRISIS := 0.35         # a2: alle tämän HP-osuuden kilpi on pelastus
const SHIELD_CRISIS_MULT := 1.5

const FIELD_RADIUS := 260.0         # ult: valokenttä
const FIELD_DUR := 6.0
const FIELD_HEAL_PS := 38.0         # ult: parannus/s (oli 22)
const FIELD_SEAR_DPS := 12.0        # ult: kenttä polttaa vihollisia
const FIELD_SHIELD := 60.0          # ult: välitön kilpi kentällä (oli 20)


func _init() -> void:
	radius = 24.0


## Mana: hoidot ja suojat maksavat manaa mutta jäähtyvät nopeasti — voit
## ketjuttaa parannuksia ja kilpiä kunnes mana loppuu, sitten se palautuu.
## Valopulssi (perus) on ilmainen.
func _setup_resource() -> void:
	res_type = "mana"
	res_max = 100.0
	res = 100.0
	res_regen = 14.0
	res_cost = {"basic": 0.0, "a1": 30.0, "a2": 24.0, "dodge": 0.0}
	cd_max.a1 = 1.5
	cd_max.a2 = 1.2


## Perushyökkäys: valopulssi — vahingoittaa vihollisia ja parantaa
## liittolaiset, joiden läpi se kulkee.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("luma_pulse", 0.08, -5.0, global_position)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Palette.GOLD, 1.4))
	Projectile.launch(self, global_position + dir * 28.0, dir, {
		"speed": 820.0,
		"dmg": PULSE_DMG,
		"radius": 10.0,
		"life": 0.85,
		"kb": 80.0,
		"pierce": 1,
		"heal_allies": PULSE_HEAL,
		"color": Color("ffe9a8"),
		"visual": "luma_pulse",
	})


## Kyky 1: Hoitokehä — parantava purkaus ympärillä. Parantaa sitä enemmän mitä
## pahemmin liittolainen on haavoittunut (ei ylivuotoa täydessä elämässä) ja
## polttaa samalla kehällä olevia vihollisia.
func _ability1(_dir: Vector2) -> void:
	AudioMgr.play("luma_bloom", 0.05, 0.0, global_position)
	ability_signature("luma", BLOOM_RADIUS)
	controller_rumble(0.12, 0.02, 0.16)
	Fx.ring(arena, global_position, Palette.glow(Palette.HEAL, 1.5), BLOOM_RADIUS, 0.5, 6.0)
	visual.squash(1.2, 0.85)
	var power := support_power()
	# Parannus kohdistuu SANKAREIHIN (ei minioneihin): kehän arvo mitataan
	# taistelusta eikä aallon paikkaamisesta.
	for ally in arena.heroes_in_circle(global_position, BLOOM_RADIUS, team, true, true):
		var missing: float = maxf(ally.max_hp - ally.hp, 0.0)
		ally.heal_hp((BLOOM_HEAL + BLOOM_MISSING * missing) * power, self)
	for enemy in arena.heroes_in_circle(global_position, BLOOM_RADIUS, 1 - team, true, true):
		deal_damage_to(enemy, BLOOM_SEAR, 0.0,
			(enemy.global_position - global_position).normalized())


## Kyky 2: Suojasäde — suojakilpi eniten kärsineelle liittolaiselle. Hädässä
## (alle 35 % elämästä) kilpi on puolitoistakertainen: tämä on Luman pelastus.
func _ability2(_dir: Vector2) -> void:
	var target: Hero = null
	var worst_frac := 1.1
	for ally in arena.alive_allies(team):
		if ally == self:
			continue
		if ally.global_position.distance_to(global_position) > SHIELD_RANGE:
			continue
		var frac: float = ally.hp / ally.max_hp
		if frac < worst_frac:
			worst_frac = frac
			target = ally
	if target == null:
		target = self
	AudioMgr.play("luma_shield", 0.05, 0.0, global_position)
	ability_signature("luma", 105.0, (target.global_position - global_position).normalized())
	if target != self:
		Fx.beam(arena, global_position, target.global_position, Palette.glow(Palette.SHIELD, 1.3))
	var amount := SHIELD_AMOUNT * support_power()
	var crisis: bool = target.hp < target.max_hp * SHIELD_CRISIS
	if crisis:
		amount *= SHIELD_CRISIS_MULT
	target.add_shield(amount, SHIELD_DUR, self)
	Fx.ring(arena, target.global_position, Palette.glow(Palette.SHIELD, 1.5), 62.0, 0.4)
	arena.popup(target.global_position + Vector2(0, -70),
		"PELASTUS" if crisis else "SUOJATTU", Palette.SHIELD, 18 if crisis else 16)


## Väistö: kevyt pyrähdys, joka antaa hetkeksi vauhtia.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.14, true)
	apply_haste(1.25, 1.0)
	AudioMgr.play("dash", 0.1, 2.0, global_position)
	Fx.dust(arena, global_position)


## Ultimate: Valokenttä — suuri alue, joka parantaa ja nopeuttaa joukkuetta
## sekä polttaa alueella seisovia vihollisia. Kentälle jääminen maksaa.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "VALOKENTTÄ!", Palette.glow(Palette.GOLD, 1.5), 26)
	AudioMgr.play("luma_ult", 0.03, 1.0, global_position)
	controller_rumble(0.28, 0.08, 0.42)
	# Valopatsas
	Fx.flash(arena, global_position, Palette.glow(Color("ffe9a8"), 1.6), 130.0, 0.6)
	Fx.ring(arena, global_position, Palette.glow(Palette.HEAL, 1.5), FIELD_RADIUS, 0.7, 8.0)
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.4), 200.0, 0.6, 5.0)
	Zone.spawn(self, global_position, {
		"type": "heal",
		"radius": FIELD_RADIUS,
		"dur": FIELD_DUR,
		"heal_ps": FIELD_HEAL_PS,
		"visual": "luma_field",
	})
	Zone.spawn(self, global_position, {
		"type": "haste",
		"radius": FIELD_RADIUS,
		"dur": FIELD_DUR,
		"haste_f": 1.3,
		"visual": "hidden",
	})
	Zone.spawn(self, global_position, {
		"type": "fire",
		"radius": FIELD_RADIUS,
		"dur": FIELD_DUR,
		"dps": FIELD_SEAR_DPS,
		"visual": "hidden",
	})
	# Välitön suoja kentällä oleville liittolaisille
	var power := support_power()
	for ally in arena.heroes_in_circle(global_position, FIELD_RADIUS, team, true, true):
		ally.add_shield(FIELD_SHIELD * power, 3.5, self)


## Passiivi: nopea itsepalautuminen taistelun ulkopuolella.
func _passive_update(delta: float) -> void:
	if since_damage > 3.0 and hp < max_hp:
		hp = minf(hp + 6.0 * delta, max_hp)


## Tasoskaalaus: parannustuki — hauras, mutta mana riittää pitkään.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 0.80, "spell": 0.85, "melee": 0.80, "regen": 1.25}


## Väistön kehitys: puhdistus (parantaja irtoaa hidasteista hoitamaan).
func _dodge_evolution() -> String:
	return "cleanse"


## Botin rankkausjärjestys: Hoitokehä ensin, kupla toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "dodge", "basic"]
