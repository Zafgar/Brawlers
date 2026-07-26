class_name Myria
extends JungleHero
## ORKIDEAHENKI. Myria istuttaa taistelukentälle orkideoita ja puhkaisee ne
## kukkimaan. Kaksi nappia, yksi selkeä silmukka: ISTUTA (R1) — KUKI (L1).
## Orkidea vahingoittaa vihollisia ja parantaa liittolaisia niin kauan kuin se
## seisoo; kukinta räjäyttää kaikki kerralla. Ei essenssikirjanpitoa.

const ORCHID := Color("c77bff")     # orkidean terälehti
const NECTAR := Color("ffb3e6")     # medensävy: kukinta ja parannus
const STEM := Color("7ee08a")       # varsi ja lehdet

const MAX_ORCHIDS := 3
const ORCHID_RADIUS := 128.0
const ORCHID_DUR := 11.0
const ORCHID_DPS := 17.0
const ORCHID_RANGE := 620.0

const BLOOM_DMG := 52.0
const BLOOM_BLAST := 168.0
const BLOOM_HEAL := 22.0            # parannus per puhjennut orkidea

const DRIFT_SPEED := 1080.0
const DRIFT_TIME := 0.22

const ULT_RADIUS := 285.0
const ULT_DUR := 8.0
const ULT_ORCHIDS := 5

var _orchids: Array = []            # elossa olevat orkideat (JungleField)
var _bloom_glow := 0.0


func _init() -> void:
	radius = 19.0


func _setup_resource() -> void:
	# Kenttähenki vaihtaa osan puhdistusnopeudesta turvallisuuteen, mutta ei
	# saa jumittua yhdelle leirille minuutiksi.
	jungle_clear_mult = 2.0
	res_type = "mana"
	res_max = 120.0
	res = res_max
	res_regen = 11.0
	res_cost.a1 = 20.0
	res_cost.a2 = 26.0


## Elossa olevien orkideoiden määrä — hero_visual ja HUD lukevat tämän.
func orchid_count() -> int:
	_prune_orchids()
	return _orchids.size()


func bloom_glow() -> float:
	return _bloom_glow


func _aimed_slots() -> Array:
	return ["a1"]


func _ground_targeted_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return ORCHID_RANGE


func _aim_default_range(_slot: String) -> float:
	return 400.0


func _aim_target_radius(_slot: String) -> float:
	return ORCHID_RADIUS


## Perushyökkäys: Siitepölysyöksy — kevyesti hakeutuva itiöpallo.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	ability_signature("myria", 105.0, d)
	Projectile.launch(self, global_position + d * (radius + 7.0), d, {
		"speed": 800.0, "dmg": 16.0, "radius": 10.0, "life": 0.95,
		"kb": 55.0, "homing_rate": 1.2, "color": ORCHID,
		"visual": "myria_wisp", "on_hit": Callable(self, "_spore_hit"),
	})
	AudioMgr.play("light", 0.05, -10.0, global_position)


func _spore_hit(target: Hero, _projectile: Projectile) -> void:
	# Itiöt ruokkivat lähintä orkideaa: pieni parannus Myrialle kun kukkia on maassa.
	if orchid_count() > 0:
		heal_hp(3.5, self)
	target.apply_slow(0.86, 0.5)


## Kyky 1: Kukkaistutus — istuttaa orkidean valittuun kohtaan. Orkidea polttaa
## vihollisia ja parantaa liittolaisia 11 sekunnin ajan. Enintään kolme
## kerrallaan; neljäs kuihduttaa vanhimman.
func _ability1(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, ORCHID_RANGE, 400.0)
	_prune_orchids()
	if _orchids.size() >= MAX_ORCHIDS:
		var oldest = _orchids.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	ability_signature("myria", 150.0, target - global_position)
	var flower := JungleField.spawn(self, target, "orchid", {
		"radius": ORCHID_RADIUS, "dur": ORCHID_DUR, "dps": ORCHID_DPS,
		"tick": 0.5, "color": ORCHID,
	})
	_orchids.append(flower)
	# Istutus luetaan heti: varsi nousee maasta ja terälehdet aukeavat.
	Fx.ring(arena, target, Palette.glow(STEM, 1.5), ORCHID_RADIUS * 0.5, 0.4, 4.0)
	for i in range(6):
		var ray := Vector2.RIGHT.rotated(TAU * i / 6.0)
		Fx.beam(arena, target, target + ray * ORCHID_RADIUS * 0.62,
			Palette.with_alpha(ORCHID, 0.7), 4.0)
	Fx.flash(arena, target, Palette.glow(NECTAR, 1.5), 42.0, 0.3)
	AudioMgr.play("vine", 0.08, -7.0, target)


## Kyky 2: Kukinta — kaikki istutetut orkideat puhkeavat kerralla. Jokainen
## räjähtää omalla paikallaan (52 vahinkoa, 168 px) ja parantaa Myriaa.
## Ilman orkideoita Myria kukkii itse, joten nappi ei ole koskaan kuollut.
func _ability2(_dir: Vector2) -> void:
	_prune_orchids()
	ability_signature("myria", 175.0, aim)
	AudioMgr.play("luma_bloom", 0.09, -3.0, global_position)
	controller_rumble(0.4, 0.7, 0.2)
	_bloom_glow = 1.0
	var popped := 0
	for flower in _orchids:
		if not is_instance_valid(flower):
			continue
		if flower.bloom(BLOOM_DMG, BLOOM_BLAST):
			popped += 1
	_orchids.clear()
	if popped > 0:
		heal_hp(BLOOM_HEAL * float(popped), self)
		arena.shake(0.12 * float(popped))
		return
	# Ei kukkia maassa: pienempi kukinta Myrian omalla paikalla.
	Fx.ring(arena, global_position, Palette.glow(NECTAR, 1.6), BLOOM_BLAST, 0.45, 6.0)
	Fx.burst(arena, global_position, Palette.glow(ORCHID, 1.6), 16, 300.0, 0.42, 5.0)
	for enemy in arena.alive_enemies(team):
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > BLOOM_BLAST + enemy.radius:
			continue
		var away := off / dist if dist > 1.0 else Vector2.UP
		deal_damage_to(enemy, BLOOM_DMG * 0.6, 200.0, away)
		enemy.apply_slow(0.68, 1.0)


## Väistö: Terälehtiliuku — Myria hajoaa terälehdiksi ja liukuu sivuun
## osumattomana. Puhdistava liike: henki livahtaa kontrollista.
func _dodge_action(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	dash(d, DRIFT_SPEED, DRIFT_TIME, true)
	add_shield(26.0, 2.0, self)
	ability_signature("myria", 128.0, d)
	Fx.ring(arena, global_position, Palette.glow(NECTAR, 1.5), 82.0, 0.42, 4.0)
	Fx.burst(arena, global_position, Palette.with_alpha(ORCHID, 0.8), 14, 190.0, 0.5, 4.0)
	AudioMgr.play("pickup", 0.07, -6.0, global_position)
	controller_rumble(0.2, 0.32, 0.12)


## Leirin kaato ruokkii henkeä: ultia latautuu ja istutuksen jäähdytys nopeutuu.
func on_jungle_camp_defeated(camp: Critter) -> void:
	super.on_jungle_camp_defeated(camp)
	add_ult(5.0 if camp.is_major_objective() else 2.0)
	cd.a1 = maxf(cd.a1 - 2.5, 0.0)
	Fx.ring(arena, global_position, Palette.glow(STEM, 1.5), 70.0, 0.4, 3.5)


func _prune_orchids() -> void:
	_orchids = _orchids.filter(func(f): return is_instance_valid(f))


func _ult_is_held() -> bool:
	return true


func _ult_ground_targeted() -> bool:
	return true


func _ult_range() -> float:
	return 700.0


func _ult_default_range() -> float:
	return 450.0


func _ult_target_radius() -> float:
	return ULT_RADIUS


## Ultimate: Orkideapuutarha — Myria avaa kokonaisen puutarhan. Iso kenttä
## polttaa vihollisia ja parantaa liittolaisia, ja kehälle nousee viisi
## orkideaa, jotka voi vielä puhkaista Kukinnalla.
func _ultimate(dir: Vector2) -> void:
	var target := jungle_ground_target(dir, _ult_range(), _ult_default_range())
	Fx.ultimate_warning(arena, target, Palette.glow(ORCHID, 1.6),
		Palette.team(team), ULT_RADIUS, 0.55, "myria")
	Fx.ultimate_field(arena, target, ORCHID, Palette.team(team),
		ULT_RADIUS, ULT_DUR, "myria")
	JungleField.spawn(self, target, "garden", {
		"radius": ULT_RADIUS, "dur": ULT_DUR, "dps": 26.0, "tick": 0.45,
		"color": ORCHID,
	})
	_prune_orchids()
	# Viisi orkideaa kehälle: puutarha on myös ladattu Kukinta.
	for i in range(ULT_ORCHIDS):
		if _orchids.size() >= MAX_ORCHIDS + ULT_ORCHIDS:
			break
		var p := target + Vector2.RIGHT.rotated(TAU * i / float(ULT_ORCHIDS) - PI * 0.5) \
			* ULT_RADIUS * 0.66
		var flower := JungleField.spawn(self, p, "orchid", {
			"radius": ORCHID_RADIUS * 0.82, "dur": ULT_DUR, "dps": ORCHID_DPS,
			"tick": 0.5, "color": NECTAR,
		})
		_orchids.append(flower)
		Fx.flash(arena, p, Palette.glow(NECTAR, 1.6), 44.0, 0.35)
	arena.popup(target + Vector2(0, -ULT_RADIUS - 26), "ORKIDEAPUUTARHA!", ORCHID, 25)
	AudioMgr.play("ult", 0.12, -3.0, target)
	AudioMgr.play("luma_bloom", 0.07, -6.0, target)
	arena.shake(0.4)
	controller_rumble(0.6, 0.9, 0.34)
	_bloom_glow = 1.0


func _passive_update(delta: float) -> void:
	_bloom_glow = maxf(_bloom_glow - delta * 1.4, 0.0)


func _respawn() -> void:
	super()
	_orchids.clear()
	_bloom_glow = 0.0


## Botti käyttää väistön pakoliikkeenä: se on puhdas liike + kilpi.
func bot_wants_utility() -> bool:
	return hp < max_hp * 0.45


## Tasoskaalaus: kenttähenki — loitsuvoima ja regen edellä, ei raakaa kestoa.
func _level_scaling() -> Dictionary:
	return {"hp": 0.95, "damage": 0.90, "spell": 1.15, "melee": 0.80, "regen": 1.20}


## Väistön kehitys: puhdistus (henki hajoaa terälehdiksi kontrollista).
func _dodge_evolution() -> String:
	return "cleanse"


## Botin rankkausjärjestys: Kukkaistutus ensin, Kukinta toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]
