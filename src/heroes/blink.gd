class_name Blink
extends Hero
## VÄLÄHDYSDUELLISTI. Blink menee sisään ja tulee ULOS: Välähdys jättää
## lähtöpaikkaan KAIUN, jolle voi palata koko ikkunan ajan — se on kitin pakotie,
## ei koriste. Vahinko ei tule tasaisesta naputtelusta vaan kahdesta luettavasta
## ikkunasta: perusiskun KOLMEN ISKUN RYTMISTÄ ja Valoviuhkan avaamasta
## JÄLKITERÄ-lopetuksesta. Kaato lataa Välähdyksen heti uudelleen, joten
## onnistunut avaus ketjuttuu — epäonnistunut jättää Blinkin keskelle kenttää.
##
## Itemikäyrä: kykyjen vahinko skaalaa hyökkäysvoimalla poikkeuksellisen kovaa
## (ITEM_ATK_SCALE, tulee perusmoottorin ap-skaalauksen PÄÄLLE). Nälkäinen Blink
## on vaaraton, syötetty Blink poistaa takalinjan yhdellä syöksyllä.

const BLADE := Color("d9c8ff")

# Perushyökkäys: kolmen iskun rytmi.
const SLASH_RANGE := 82.0
const SLASH_ARC_DEG := 68.0
const SLASH_DMG := 20.0
const CADENCE_NEED := 3             # monesko isku rytmissä on tehostettu
const CADENCE_WINDOW := 1.5         # rytmi katkeaa jos seuraava osuma viivästyy
const CADENCE_MULT := 2.3
const CADENCE_REACH := 26.0         # tehostettu isku ulottuu pidemmälle
const CADENCE_CRIT_SCALE := 0.6     # kriittinen osuus vahvistaa juuri tätä iskua
const CADENCE_REFUND := 0.8         # hyvitys Välähdyksen jäähdytyksestä

# Kyky 1: Välähdys ja kaiku.
const FLASH_DIST := 300.0
const FLASH_DMG := 28.0
const FLASH_RADIUS := 104.0
const ECHO_WINDOW := 3.5            # kuinka kauan kaiulle voi palata
const ECHO_DMG := 24.0
const ECHO_RADIUS := 118.0

# Kyky 2: Valoviuhka -> Jälkiterä.
const FAN_DMG := 16.0
const FAN_SPEED := 1020.0
const FAN_LIFE := 0.45
const FOLLOW_WINDOW := 0.45         # lopetusikkuna osuman jälkeen (padille sopiva)
const FOLLOW_DMG := 30.0
const FOLLOW_MISSING := 0.35        # osuus kohteen puuttuvasta elämästä
const FOLLOW_SPEED := 1500.0

# Ultimate: Valotanssi.
const DANCE_RANGE := 560.0
const DANCE_DMG := 34.0
const DANCE_MISSING := 0.30
const DANCE_STRIKES := 4
const DANCE_MAX := 7                # kaadot pidentävät tanssia tähän asti

const ITEM_ATK_SCALE := 0.85        # assassiinin kykyjen hyökkäysvoimaskaalaus

var _cadence := 0                   # osumia rytmissä (0..CADENCE_NEED-1)
var _cadence_t := 0.0
var _echo_active := false
var _echo_pos := Vector2.ZERO
var _echo_t := 0.0
var _follow_t := 0.0                # Jälkiterän ikkuna auki
var _follow_target: Hero = null
var _dance_t := 0.0                 # ultin jälkihehku (visuaali)


func _init() -> void:
	radius = 22.0


## Energia: kyvyt maksavat energiaa, joka palautuu tasaisesti JA kertyy
## osumista. Hyökkääminen ruokkii liikkuvuutta — Blink saa teleportata paljon,
## kunhan se myös osuu. Jäähdytykset tulevat HeroDefistä (HUD ja logiikka samat).
func _setup_resource() -> void:
	res_type = "energy"
	res_max = 100.0
	res = 100.0
	res_regen = 17.0
	res_cost = {"basic": 0.0, "a1": 26.0, "a2": 24.0, "dodge": 0.0}


## Välähdys tähdätään (pito -> viiva -> vapautus). Toinen painallus kaiun ollessa
## pystyssä hoituu heti ilman tähtäystä, ks. _aim_begin.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return FLASH_DIST


## Kaiku pystyssä -> painallus palauttaa heti (ei uutta tähtäystä).
func _aim_begin(slot: String) -> bool:
	if slot == "a1" and _echo_active:
		_return_to_echo()
		return false
	return true


## Assassiinin itemikäyrä: kykyvahinko skaalaa hyökkäysvoimalla erikseen. Tämä
## tulee moottorin oman ap-skaalauksen PÄÄLLE, joten syötetty Blink kasvaa
## rajummin kuin kukaan muu — ja jäljessä oleva Blink on aidosti heikko.
func _item_power() -> float:
	return 1.0 + ITEM_ATK_SCALE * item_stat("attack")


## Rytmin täyttöaste käyttöliittymälle ja hahmovisuaalille (0..1).
func cadence_fraction() -> float:
	return clampf(float(_cadence) / float(CADENCE_NEED), 0.0, 1.0)


## Kaiun jäljellä oleva osuus (0 = ei kaikua) — visuaali piirtää sen.
func echo_fraction() -> float:
	if not _echo_active:
		return 0.0
	return clampf(_echo_t / ECHO_WINDOW, 0.0, 1.0)


func echo_position() -> Vector2:
	return _echo_pos


## Jälkiterän ikkunan jäljellä oleva osuus (0..1).
func follow_fraction() -> float:
	return clampf(_follow_t / FOLLOW_WINDOW, 0.0, 1.0)


func dance_glow() -> float:
	return _dance_t


## Perushyökkäys: Valoviilto. Kolme peräkkäistä OSUMAA rytmi-ikkunan sisällä
## laukaisee Kaksoisviillon: 2,3x vahinko, pidempi ulottuvuus ja hyvitys
## Välähdyksen jäähdytyksestä. Huti nollaa rytmin — kohteessa pitää pysyä.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var empowered: bool = _cadence >= CADENCE_NEED - 1
	var reach: float = SLASH_RANGE + (CADENCE_REACH if empowered else 0.0)
	var arc: float = SLASH_ARC_DEG + (16.0 if empowered else 0.0)
	visual.attack_swing()
	AudioMgr.play("blade", 0.15, 2.0 if empowered else -1.0, global_position)
	Fx.slash(arena, global_position, d, reach, arc,
		Palette.glow(BLADE, 1.7) if empowered else BLADE)
	var landed := false
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > reach + enemy.radius:
			continue
		if absf(rad_to_deg(d.angle_to(to_enemy))) > arc:
			continue
		var dmg := SLASH_DMG
		if empowered:
			dmg *= CADENCE_MULT * (1.0 + CADENCE_CRIT_SCALE * item_stat("crit"))
		deal_damage_to(enemy, dmg, 150.0 if empowered else 110.0, to_enemy.normalized())
		landed = true
		if not enemy.alive:
			_on_takedown()
	if not landed:
		_reset_cadence()
		return
	if empowered:
		_reset_cadence()
		cd.a1 = maxf(float(cd.a1) - CADENCE_REFUND, 0.0)
		if _echo_active:
			_echo_t = minf(_echo_t + 0.6, ECHO_WINDOW)
		arena.popup(global_position + Vector2(0, -72), "KAKSOISVIILTO!",
			Palette.glow(BLADE, 1.6), 20)
		Fx.ring(arena, global_position, Palette.glow(BLADE, 1.6), 78.0, 0.3, 5.0)
		AudioMgr.play("zap", 0.08, 3.0, global_position)
		controller_rumble(0.25, 0.5, 0.14)
	else:
		_cadence += 1
		_cadence_t = CADENCE_WINDOW
	if visual != null:
		visual.aux = cadence_fraction()


func _reset_cadence() -> void:
	_cadence = 0
	_cadence_t = 0.0
	if visual != null:
		visual.aux = 0.0


## Kyky 1: Välähdys ja kaiku. Teleportti tähtäyssuuntaan tekee saapumisiskun
## (aiemmin teleportti oli pelkkä siirtymä ilman vahinkoa) ja jättää lähtöpaikkaan
## kaiun. Toinen painallus ikkunan sisällä tuo takaisin: dive -> tappo -> ulos.
func _ability1(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	var origin := global_position
	AudioMgr.play("blink", 0.1, 0.0, origin)
	Fx.flash(arena, origin, Palette.glow(hero_color(), 1.6), 40.0, 0.3)
	global_position = arena.map.clamp_to_field(origin + d * FLASH_DIST, 40.0)
	iframes = maxf(iframes, 0.3)
	ability_signature("blink", 120.0, d)
	Fx.beam(arena, origin, global_position, Palette.glow(BLADE, 1.4), 8.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.6), 46.0, 0.3)
	Fx.ring(arena, global_position, Palette.glow(BLADE, 1.5), FLASH_RADIUS, 0.35, 5.0)
	_burst(global_position, FLASH_DMG, FLASH_RADIUS, d)
	_echo_active = true
	_echo_pos = origin
	_echo_t = ECHO_WINDOW
	cd.a1 = 0.2                      # lyhyt, jotta paluupainallus toimii
	controller_rumble(0.2, 0.4, 0.12)


## Kaikupaluu: teleportti takaisin lähtöpaikkaan, purskeisku saapumisessa ja
## vauhtia irtoamiseen. Tämä on Blinkin pakotie eikä vaadi omaa jäähdytystään.
func _return_to_echo() -> void:
	var from := global_position
	global_position = arena.map.clamp_to_field(_echo_pos, 40.0)
	iframes = maxf(iframes, 0.35)
	apply_haste(1.25, 1.2)
	AudioMgr.play("blink", 0.1, 4.0, global_position)
	Fx.beam(arena, from, global_position, Palette.glow(BLADE, 1.5), 7.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.7), 50.0, 0.3)
	Fx.ring(arena, global_position, Palette.glow(BLADE, 1.5), ECHO_RADIUS, 0.4, 6.0)
	arena.popup(global_position + Vector2(0, -74), "KAIKU!", Palette.glow(BLADE, 1.5), 20)
	_act("a1")
	_burst(global_position, ECHO_DMG, ECHO_RADIUS, aim)
	_act_end()
	_clear_echo()
	cd.a1 = float(cd_max.a1)
	controller_rumble(0.3, 0.55, 0.16)


## Alueosuma teleportin päässä. Piirityssääntö: aluevahinko ei satu rakennuksiin,
## joten lippu on päällä vain osuman ajan ja palautetaan heti perään.
func _burst(center: Vector2, amount: float, blast: float, fallback_dir: Vector2) -> void:
	var prev_aoe: bool = damage_is_aoe
	damage_is_aoe = true
	var power: float = amount * _item_power()
	for enemy in arena.heroes_in_circle(center, blast):
		if enemy.team == team:
			continue
		var away: Vector2 = enemy.global_position - center
		var kbdir: Vector2 = away.normalized() if away.length() > 1.0 else fallback_dir
		deal_damage_to(enemy, power, 170.0, kbdir)
		if not enemy.alive:
			_on_takedown()
	damage_is_aoe = prev_aoe


## Kyky 2: Valoviuhka -> Jälkiterä. Ensimmäinen painallus heittää kolme valoterää
## viuhkana; ensimmäinen sankariosuma avaa 0,45 s LOPETUSIKKUNAN. Painallus
## ikkunan sisällä ampuu Jälkiterän, jonka vahinko kasvaa kohteen puuttuvan
## elämän mukaan. Ikkunan ohittaminen palauttaa kyvyn täydelle jäähdytykselle.
func _ability2(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	if _follow_t > 0.0:
		_after_blade(d)
		return
	visual.attack_swing()
	AudioMgr.play("blade", 0.1, -3.0, global_position)
	ability_signature("blink", 110.0, d)
	for angle_offset in [-0.24, 0.0, 0.24]:
		Projectile.launch(self, global_position + d * 24.0, d.rotated(float(angle_offset)), {
			"speed": FAN_SPEED,
			"dmg": FAN_DMG * _item_power(),
			"radius": 11.0,
			"life": FAN_LIFE,
			"kb": 90.0,
			"color": BLADE,
			"visual": "blink_blade",
			"on_hit": Callable(self, "_fan_hit"),
		})


## Viuhkan osuma sankariin avaa lopetusikkunan (kirkas rengas + korkea ping).
func _fan_hit(target: Hero, _projectile: Projectile) -> void:
	if target.is_unit or _follow_t > 0.0:
		return
	_follow_target = target
	_follow_t = FOLLOW_WINDOW
	cd.a2 = 0.0                      # ikkuna on auki: toinen painallus toimii heti
	Fx.ring(arena, target.global_position, Palette.glow(BLADE, 1.7), 48.0, 0.28, 4.0)
	Fx.spark(arena, target.global_position, Palette.glow(Color.WHITE, 1.4))
	AudioMgr.play("mark", 0.05, 5.0, target.global_position)
	arena.popup(global_position + Vector2(0, -92), "JÄLKITERÄ!", Palette.glow(BLADE, 1.6), 18)
	controller_rumble(0.15, 0.25, 0.09)


## Jälkiterä: ikkunan sisällä painettu lopetus. Kaartaa loivasti merkittyyn
## kohteeseen (ohjaimella osuttava) ja teloittaa haavoittuneen.
func _after_blade(d: Vector2) -> void:
	var t: Hero = _follow_target
	var shot := d
	if t != null and is_instance_valid(t) and t.alive:
		shot = (t.global_position - global_position).normalized()
	visual.attack_swing()
	AudioMgr.play("blade", 0.08, 5.0, global_position)
	Fx.flash(arena, global_position + shot * 26.0, Palette.glow(Color.WHITE, 1.6), 30.0, 0.16)
	Projectile.launch(self, global_position + shot * 26.0, shot, {
		"speed": FOLLOW_SPEED,
		"dmg": 0.0,                  # koko vahinko lasketaan osumassa (puuttuva elämä)
		"radius": 15.0,
		"life": 0.42,
		"kb": 0.0,
		"color": Palette.glow(BLADE, 1.6),
		"visual": "blink_blade",
		"homing_target": t,
		"homing_rate": 4.2,
		"on_hit": Callable(self, "_after_hit"),
	})
	_follow_t = 0.0
	_follow_target = null
	controller_rumble(0.35, 0.65, 0.18)


func _after_hit(target: Hero, _projectile: Projectile) -> void:
	# Teloitusbonus vain oikeisiin sankareihin: rakennusten valtava puuttuva
	# elämä ei saa muuttua piiritysaseeksi (piirityssäännöt).
	var missing := 0.0
	if not target.is_unit:
		missing = maxf(target.max_hp - target.hp, 0.0)
	var dmg: float = (FOLLOW_DMG + missing * FOLLOW_MISSING) * _item_power()
	var gp: Vector2 = target.global_position
	deal_damage_to(target, dmg, 180.0, aim)
	Fx.burst(arena, gp, Palette.glow(BLADE, 1.6), 14, 300.0, 0.36, 4.0)
	Fx.flash(arena, gp, Palette.glow(Color.WHITE, 1.5), 44.0, 0.22)
	AudioMgr.play("zap", 0.06, 5.0, gp)
	arena.shake(0.16)
	if not target.alive:
		_on_takedown()


## Väistö: salamannopea sivuaskel.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	AudioMgr.play("dash", 0.12, 0.0, global_position)
	Fx.dust(arena, global_position)


## Ultimate: Valotanssi — sarja selkäänteleportteja haavoittuneimpiin kohteisiin.
## Jokainen isku teloittaa (vahinko kasvaa puuttuvan elämän mukaan) ja jokainen
## KAATO pidentää tanssia yhdellä iskulla. Lopuksi Välähdys on heti valmis, joten
## ultin päätteeksi pääsee ulos — tämä on assassiinin purskeikkuna kokonaisuutena.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "VALOTANSSI!",
		Palette.glow(BLADE, 1.6), 26)
	AudioMgr.play("blink", 0.05, -2.0, global_position)
	arena.shake(0.3)
	controller_rumble(0.45, 0.8, 0.3)
	_light_dance()


func _light_dance() -> void:
	var strikes := DANCE_STRIKES
	var done := 0
	while done < strikes:
		if not is_inside_tree() or not alive:
			return
		var target := _dance_target()
		if target == null:
			break
		var facing := Vector2.RIGHT
		if target.aim.length() > 0.1:
			facing = target.aim.normalized()
		var spot: Vector2 = target.global_position - facing * (target.radius + 42.0)
		_dance_t = 1.0
		Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.5), 36.0, 0.25)
		global_position = arena.map.clamp_to_field(spot, 40.0)
		iframes = maxf(iframes, 0.32)
		aim = (target.global_position - global_position).normalized()
		visual.attack_swing()
		AudioMgr.play("blade", 0.12, 3.0, global_position)
		Fx.slash(arena, global_position, aim, 76.0, 84.0, Palette.glow(BLADE, 1.5))
		var missing := 0.0
		if not target.is_unit:
			missing = maxf(target.max_hp - target.hp, 0.0)
		var dmg: float = (DANCE_DMG + missing * DANCE_MISSING) * _item_power()
		# Await katkaisee dispatch-kontekstin, joten jokainen isku avaa sen itse.
		_act("ult")
		deal_damage_to(target, dmg, 210.0, aim)
		_act_end()
		Fx.spark(arena, target.global_position, Palette.glow(BLADE, 1.9))
		if not target.alive:
			strikes = mini(strikes + 1, DANCE_MAX)
			arena.popup(global_position + Vector2(0, -70), "KAATO!",
				Palette.glow(BLADE, 1.7), 20)
			_on_takedown()
		done += 1
		await get_tree().create_timer(0.2).timeout
	if not is_inside_tree() or not alive:
		return
	cd.a1 = 0.0                      # tanssin jälkeen aina pakotie valmiina
	apply_haste(1.3, 1.5)


## Tanssin kohde: säteen sisällä oleva haavoittunein vihollissankari.
func _dance_target() -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		var d: float = enemy.global_position.distance_to(global_position)
		if d > DANCE_RANGE:
			continue
		var score: float = enemy.hp / maxf(enemy.max_hp, 1.0) * 1000.0 + d * 0.2
		if score < best_score:
			best_score = score
			best = enemy
	return best


## Kaato lataa Välähdyksen heti: ketjutappo tai puhdas poistuminen. Tämä on
## assassiinin palkinto onnistuneesta avauksesta — ja ainoa tapa selvitä
## useamman vihollisen keskeltä.
func _on_takedown() -> void:
	cd.a1 = 0.0
	gain_res(30.0)
	if _echo_active:
		_echo_t = ECHO_WINDOW
	arena.popup(global_position + Vector2(0, -100), "VÄLÄHDYS LADATTU!",
		Palette.glow(BLADE, 1.7), 20)
	AudioMgr.play("ult_ready", 0.05, -5.0, global_position)


## Passiivi: kevyt vauhti kun ei ole paineen alla + ikkunoiden ajastimet.
func _passive_update(delta: float) -> void:
	if _cadence_t > 0.0:
		_cadence_t = maxf(_cadence_t - delta, 0.0)
		if _cadence_t <= 0.0:
			_reset_cadence()
	if _follow_t > 0.0:
		_follow_t = maxf(_follow_t - delta, 0.0)
		if _follow_t <= 0.0:
			_follow_target = null
			cd.a2 = maxf(float(cd.a2), float(cd_max.a2))
	if _echo_active:
		_echo_t -= delta
		if _echo_t <= 0.0:
			_clear_echo()
			cd.a1 = maxf(float(cd.a1), float(cd_max.a1))
	_dance_t = maxf(_dance_t - delta * 1.6, 0.0)
	if since_damage > 2.0:
		apply_haste(1.08, 0.2)


func _clear_echo() -> void:
	_echo_active = false
	_echo_t = 0.0


## Yhdistelmätilat nollataan tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_reset_blink_state()


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_reset_blink_state()


func _reset_blink_state() -> void:
	_reset_cadence()
	_follow_t = 0.0
	_follow_target = null
	_dance_t = 0.0
	_clear_echo()


## Tasoskaalaus: assassiini — erittäin hauras, mutta kyky- ja lähivahinko
## kasvavat rajusti. Yhdessä itemikäyrän kanssa tämä tekee syötetystä Blinkistä
## roolin kovimman purskeen ja jäljessä olevasta selvästi heikoimman.
func _level_scaling() -> Dictionary:
	return {"hp": 0.70, "damage": 1.25, "spell": 1.32, "melee": 1.32, "regen": 1.05}


## Väistön kehitys: faasi (katoaa syöksyssä seinienkin läpi).
func _dodge_evolution() -> String:
	return "phase"


## Botin rankkausjärjestys: Valoviuhka + Jälkiterä ensin, Välähdys toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "a1", "basic", "dodge"]
