class_name Rift
extends Hero
## TYHJYYSKAHAKOITSIJA. Rift LATAA ja PURKAA. Perusiskut kasaavat kohteeseen
## pinoja (max 5) ja tekevät sitä kovempaa mitä enemmän pinoja jo on — pinot
## ovat samalla lataus ja näkyvä mittari. Merkkiheitto (R1) tekee vahinkoa ja
## kasaa kaksi pinoa; toinen painallus VARPPAA merkille (viholliseen selän
## taakse, omaan sankariin pakoreittinä) ja avaa 0,45 sekunnin TYHJYYSAUKON,
## jonka sisällä Räjäytys tekee 30 % enemmän. Räjäytys kuluttaa pinot, teloittaa
## neljästä pinosta alkaen ja HYVITTÄÄ VÄISTÖN JÄÄHDYTYSTÄ — onnistunut purske
## ostaa poistumisen. Ultti pysäyttää ajan ympäriltä: se on kitin katto.
##
## Itemikäyrä: räjäytys, merkki ja varppausisku skaalaavat hyökkäysvoimalla
## erikseen (ITEM_ATK_SCALE) moottorin ap-skaalauksen PÄÄLLE.

# Perushyökkäys: tyhjyysviilto, joka lataa pinon.
const SLASH_RANGE := 86.0
const SLASH_ARC := 68.0
const SLASH_DMG := 15.0
const STACK_BONUS := 3.5            # lisävahinko per kohteessa jo oleva pino

# Kyky 1: merkkiheitto ja varppaus.
const MARK_SPEED := 1350.0
const MARK_LIFE := 0.85
const MARK_DUR := 4.0               # kuinka kauan merkki pysyy osumisen jälkeen
const MARK_DMG := 26.0
const MARK_AMP := 1.18
const WARP_DMG := 30.0
const TP_OFFSET := 52.0
const VOID_WINDOW := 0.45           # varppauksen jälkeinen tyhjyysaukko
const VOID_WINDOW_MULT := 1.3

# Kyky 2: räjäytys.
const DET_RANGE := 118.0
const DET_ARC := 85.0
const DET_BASE := 24.0
const DET_PER_STACK := 17.0
const DET_EXEC_STACKS := 4          # tästä pinomäärästä alkaen mukaan teloitus
const DET_MISSING := 0.30           # osuus kohteen puuttuvasta elämästä
const DODGE_REFUND := 0.7           # väistöhyvitys per kulutettu pino

# Ultimate: ajanpysäytys.
const FREEZE_RADIUS := 520.0
const FREEZE_DUR := 2.0
const FREEZE_DMG := 45.0
const FREEZE_POWER := 1.4           # vahinkokerroin pysäytyksen ajan
const FREEZE_POWER_DUR := 2.6

const ITEM_ATK_SCALE := 0.8         # assassiinin kykyjen hyökkäysvoimaskaalaus

var _mark_target: Hero = null
var _mark_timer := 0.0
var _mark_pending := false
var _void_window := 0.0             # tyhjyysaukko auki (s)
var _freeze_power := 0.0            # ajanpysäytyksen tehostus jäljellä (s)


func _init() -> void:
	radius = 22.0


## Merkkiheitto tähdätään: pidä R1 pohjassa (tähtäysviiva) ja vapauta
## heittääksesi merkin. Varppaus (kun merkki on kiinni) sekä odotus lennon
## aikana hoituvat välittömästi ilman tähtäystä.
func _aimed_slots() -> Array:
	return ["a1"]


func _aim_range(_slot: String) -> float:
	return 720.0


func _aim_begin(_slot: String) -> bool:
	# Merkki kiinni -> varppaa heti (ei tähtäystä).
	if _mark_target != null and is_instance_valid(_mark_target) and _mark_target.alive:
		_teleport_to_mark()
		cd.a1 = float(cd_max.a1)
		return false
	# Merkki vielä lennossa -> odota (ei uutta heittoa).
	if _mark_pending:
		return false
	# Ei merkkiä -> aloita tähtäys (heitto laukeaa vapautettaessa).
	return true


## Assassiinin itemikäyrä: kykyvahinko skaalaa hyökkäysvoimalla erikseen, tämä
## tulee moottorin oman ap-skaalauksen PÄÄLLE.
func _item_power() -> float:
	return 1.0 + ITEM_ATK_SCALE * item_stat("attack")


## Tyhjyysaukon jäljellä oleva osuus (0..1) — visuaali ja HUD lukevat tämän.
func void_window_fraction() -> float:
	return clampf(_void_window / VOID_WINDOW, 0.0, 1.0)


func freeze_power_active() -> bool:
	return _freeze_power > 0.0


func has_mark() -> bool:
	return _mark_target != null and is_instance_valid(_mark_target) and _mark_target.alive


func mark_position() -> Vector2:
	if has_mark():
		return _mark_target.global_position
	return global_position


## Perushyökkäys: tyhjyysviilto. Lataa pinon JA tekee sitä kovempaa mitä enemmän
## pinoja kohteessa jo on — kohteessa pysyminen on perusiskun mekaniikka.
## Ajanpysäytyksen aikana viilto lataa kaksi pinoa kerralla.
func _basic(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	AudioMgr.play("blade", 0.15, -1.0, global_position)
	Fx.slash(arena, global_position, d, SLASH_RANGE, SLASH_ARC, hero_color())
	var gain: int = 2 if _freeze_power > 0.0 else 1
	for enemy in arena.alive_enemies(team):
		var to: Vector2 = enemy.global_position - global_position
		if to.length() > SLASH_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(d.angle_to(to))) > SLASH_ARC:
			continue
		var dmg: float = SLASH_DMG + float(enemy.void_stacks) * STACK_BONUS
		if _freeze_power > 0.0:
			dmg *= FREEZE_POWER
		deal_damage_to(enemy, dmg, 90.0, to.normalized())
		if not enemy.alive:
			_on_takedown()
			continue
		var before: int = enemy.void_stacks
		for _step in range(gain):
			enemy.add_void_stack(self)
		if enemy.void_stacks >= 5 and before < 5:
			arena.popup(enemy.global_position + Vector2(0, -64), "TÄYDET PINOT!",
				Palette.glow(hero_color(), 1.6), 18)
			AudioMgr.play("ult_ready", 0.04, -7.0, enemy.global_position)
		Fx.spark(arena, enemy.global_position + Vector2(0, -40),
			Palette.glow(hero_color(), 1.5))


## Kyky 1: merkkiheitto / varppaus. Ensimmäinen painallus heittää merkin;
## kun se osuu (oma tai vihollinen), toinen painallus varppaa kohteelle.
func _ability1(dir: Vector2) -> void:
	if has_mark():
		_teleport_to_mark()
		cd.a1 = float(cd_max.a1)
	elif _mark_pending:
		cd.a1 = 0.15            # merkki vielä lennossa
	else:
		_throw_mark(dir)
		_mark_pending = true
		cd.a1 = 0.15            # lyhyt, jotta varppauspainallus toimii


func _throw_mark(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	AudioMgr.play("blink", 0.1, -2.0, global_position)
	ability_signature("rift", 118.0, d)
	var mark := VoidMark.new()
	mark.source = self
	mark.direction = d
	mark.color = hero_color()
	mark.speed = MARK_SPEED
	mark.life = MARK_LIFE
	mark.global_position = global_position + d * 28.0
	arena.add_child(mark)


## Merkki osui. Vihollisessa se tekee vahinkoa, lataa kaksi pinoa ja merkitsee
## kohteen (aiemmin heitto oli mitätön: 1621 castia ilman mitattavaa arvoa).
## Omaan sankariin osunut merkki on puhdas pakoreitti eikä tee mitään muuta.
func on_mark_land(hero: Hero) -> void:
	_mark_target = hero
	_mark_pending = false
	_mark_timer = MARK_DUR
	if hero.team == team:
		return
	_act("a1")
	var dmg := MARK_DMG * _item_power()
	if _freeze_power > 0.0:
		dmg *= FREEZE_POWER
	var away: Vector2 = (hero.global_position - global_position).normalized()
	deal_damage_to(hero, dmg, 110.0, away)
	if hero.alive:
		hero.add_void_stack(self)
		hero.add_void_stack(self)
		if not hero.is_unit:
			hero.apply_mark(MARK_DUR, MARK_AMP)
	else:
		_on_takedown()
	_act_end()


func on_mark_miss() -> void:
	_mark_pending = false


## Varppaus merkille. Viholliseen Rift ilmestyy SELÄN TAAKSE, iskee saapumisessa,
## lataa kaksi pinoa ja avaa tyhjyysaukon. Omaan sankariin varppaus on pakoliike.
func _teleport_to_mark() -> void:
	var from := global_position
	var t := _mark_target
	var ally: bool = t.team == team
	var spot: Vector2 = t.global_position
	if ally:
		var side: Vector2 = (from - t.global_position).normalized()
		if side == Vector2.ZERO:
			side = -aim
		spot += side * TP_OFFSET
	else:
		var facing := Vector2.RIGHT
		if t.aim.length() > 0.1:
			facing = t.aim.normalized()
		spot -= facing * (t.radius + TP_OFFSET)
	global_position = arena.map.clamp_to_field(spot, 40.0)
	aim = (t.global_position - global_position).normalized()
	iframes = maxf(iframes, 0.3)
	_mark_target = null
	_mark_timer = 0.0
	Fx.beam(arena, from, global_position, Palette.glow(hero_color(), 1.4), 6.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.6), 44.0, 0.3)
	AudioMgr.play("blink", 0.1, 1.0, global_position)
	controller_rumble(0.25, 0.45, 0.14)
	if ally:
		return
	_act("a1")
	var dmg := WARP_DMG * _item_power()
	if _freeze_power > 0.0:
		dmg *= FREEZE_POWER
	deal_damage_to(t, dmg, 140.0, aim)
	if t.alive:
		t.add_void_stack(self)
		t.add_void_stack(self)
	else:
		_on_takedown()
	_act_end()
	# TYHJYYSAUKKO: lyhyt ikkuna jossa Räjäytys tekee 30 % enemmän. Selkeä
	# rengas + ping, ja ikkuna on ohjaimella ehdittävä (0,45 s).
	_void_window = VOID_WINDOW
	arena.popup(global_position + Vector2(0, -78), "TYHJYYSAUKKO!",
		Palette.glow(hero_color(), 1.6), 20)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.7), 92.0, 0.35, 5.0)
	AudioMgr.play("mark", 0.05, 4.0, global_position)


## Kyky 2: räjäytys — kitin purskeikkuna. Kuluttaa kohteen pinot ja tekee niiden
## mukaan vahinkoa; neljästä pinosta alkaen mukaan tulee teloitusosuus kohteen
## puuttuvasta elämästä. Tyhjyysaukon sisällä +30 %. Kulutetut pinot hyvittävät
## väistön jäähdytystä ja täydet 5 pinoa avaavat pakotien kokonaan.
func _ability2(dir: Vector2) -> void:
	var d := dir.normalized() if dir.length() > 0.1 else aim
	visual.attack_swing()
	AudioMgr.play("zap", 0.1, -3.0, global_position)
	ability_signature("rift", 122.0, d)
	Fx.slash(arena, global_position, d, DET_RANGE, DET_ARC, Palette.glow(hero_color(), 1.4))
	var target := _melee_target(d)
	if target == null:
		return
	var stacks := target.consume_void_stacks()
	var dmg := DET_BASE + float(stacks) * DET_PER_STACK
	if stacks >= DET_EXEC_STACKS and not target.is_unit:
		dmg += maxf(target.max_hp - target.hp, 0.0) * DET_MISSING
	dmg *= _item_power()
	var in_window: bool = _void_window > 0.0
	if in_window:
		dmg *= VOID_WINDOW_MULT
		_void_window = 0.0
	if _freeze_power > 0.0:
		dmg *= FREEZE_POWER
	var gp: Vector2 = target.global_position
	deal_damage_to(target, dmg, 160.0, d)
	if stacks > 0:
		arena.shake(0.15 + float(stacks) * 0.05)
		Fx.burst(arena, gp, Palette.glow(hero_color(), 1.6),
			8 + stacks * 3, 200.0 + float(stacks) * 40.0, 0.5, 6.0)
		Fx.ring(arena, gp, Palette.glow(hero_color(), 1.5),
			40.0 + float(stacks) * 14.0, 0.45, 5.0)
		var label: String = "TYHJYYSAUKKO x%d" % stacks if in_window \
			else "RÄJÄYTYS x%d" % stacks
		arena.popup(gp + Vector2(0, -60), label, Palette.glow(hero_color(), 1.5), 20)
		controller_rumble(0.3, 0.6, 0.18)
		cd.dodge = maxf(float(cd.dodge) - float(stacks) * DODGE_REFUND, 0.0)
	if stacks >= 5:
		cd.a2 = 0.0             # täydet pinot -> voi räjäyttää heti uudelleen
		cd.dodge = 0.0          # ja pakotie on auki
	if not target.alive:
		_on_takedown()


func _melee_target(dir: Vector2) -> Hero:
	var best: Hero = null
	var best_d := DET_RANGE + 40.0
	for enemy in arena.alive_enemies(team):
		var to: Vector2 = enemy.global_position - global_position
		var d: float = to.length()
		if d > DET_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to))) > DET_ARC:
			continue
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Väistö: nopea tyhjyysloikka. Räjäytys hyvittää sen jäähdytystä, joten tämä on
## Riftin varsinainen pakotie eikä pelkkä satunnainen loikka.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	AudioMgr.play("smoke", 0.12, 0.0, global_position)
	Fx.burst(arena, global_position, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.6),
		8, 150.0, 0.4, 5.0)


## Ultimate: ajanpysäytys — kitin katto. Kaikki muut sankarit (myös omat) säteen
## sisällä jäätyvät, Rift liikkuu ja toimii vapaasti. Pysäytys myös ISKEE ja
## LATAA: sisään jääneet viholliset ottavat vahinkoa ja saavat kaksi pinoa, ja
## pysäytyksen ajan Riftin perusisku lataa kaksi pinoa kerralla ja kaikki vahinko
## on +40 %. Ulti muuttuu siis takuuvarmaksi täydeksi räjäytykseksi, ei tauoksi.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "AJANPYSÄYTYS!",
		Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("thunder", 0.05, 2.0, global_position)
	arena.shake(0.4)
	controller_rumble(0.5, 0.9, 0.35)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.7), FREEZE_RADIUS, 0.8, 10.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.5),
		FREEZE_RADIUS * 0.6, 0.6, 6.0)
	_freeze_power = FREEZE_POWER_DUR
	# Purkaus on aluevahinkoa: rakennuksiin se ei pure lainkaan (piirityssääntö).
	var prev_aoe: bool = damage_is_aoe
	damage_is_aoe = true
	var blast := FREEZE_DMG * _item_power() * FREEZE_POWER
	for other in arena.heroes:
		if other == self or not is_instance_valid(other) or not other.alive:
			continue
		if other.global_position.distance_to(global_position) >= FREEZE_RADIUS:
			continue
		other.apply_freeze(FREEZE_DUR)
		Fx.flash(arena, other.global_position, Palette.with_alpha(hero_color(), 0.7), 40.0, 0.4)
		if other.team == team:
			continue
		var push: Vector2 = (other.global_position - global_position).normalized()
		deal_damage_to(other, blast, 0.0, push)
		if not other.alive:
			_on_takedown()
		elif not other.is_unit:
			other.add_void_stack(self)
			other.add_void_stack(self)
	damage_is_aoe = prev_aoe


## Kaato palkitaan: merkkiheitto latautuu heti ja väistö on valmis. Riftin
## poistuminen ostetaan onnistuneella purskeella, ei kykyjen säästämisellä.
func _on_takedown() -> void:
	cd.a1 = 0.0
	cd.dodge = 0.0
	_mark_pending = false
	arena.popup(global_position + Vector2(0, -100), "TYHJYYS LADATTU!",
		Palette.glow(hero_color(), 1.7), 20)
	AudioMgr.play("ult_ready", 0.05, -5.0, global_position)


func _passive_update(delta: float) -> void:
	_void_window = maxf(_void_window - delta, 0.0)
	_freeze_power = maxf(_freeze_power - delta, 0.0)
	if _mark_target != null:
		if not is_instance_valid(_mark_target) or not _mark_target.alive:
			_mark_target = null
		else:
			_mark_timer -= delta
			if _mark_timer <= 0.0:
				_mark_target = null


## Nollaa yhdistelmätilat tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_reset_rift_state()


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	super(keep_ult_fraction)
	_reset_rift_state()


func _reset_rift_state() -> void:
	_mark_target = null
	_mark_timer = 0.0
	_mark_pending = false
	_void_window = 0.0
	_freeze_power = 0.0


## Merkkiammus, joka osuu ensimmäiseen sankariin (oma TAI vihollinen).
class VoidMark:
	extends Node2D

	var source: Hero = null
	var direction := Vector2.RIGHT
	var speed := 1350.0
	var life := 0.85
	var color := Color("9d4edd")
	var _time := 0.0

	func _ready() -> void:
		z_index = 21

	func _physics_process(delta: float) -> void:
		_time += delta
		life -= delta
		if life <= 0.0:
			_miss()
			return
		global_position += direction * speed * delta
		if source == null or not is_instance_valid(source):
			queue_free()
			return
		var arena = source.arena
		if arena == null:
			queue_free()
			return
		for hero in arena.heroes:
			if not is_instance_valid(hero) or not hero.alive or hero == source:
				continue
			if hero.is_unit:
				continue   # ei tartu minioneihin/torneihin/olentoihin (vain sankarit)
			if global_position.distance_to(hero.global_position) < 22.0 + hero.radius:
				_land(hero)
				return
		queue_redraw()

	func _land(hero: Hero) -> void:
		if is_instance_valid(source):
			source.on_mark_land(hero)
			Fx.ring(source.arena, hero.global_position, Palette.glow(color, 1.5), 42.0, 0.4)
			AudioMgr.play("mark", 0.05)
		queue_free()

	func _miss() -> void:
		if is_instance_valid(source):
			source.on_mark_miss()
		queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 10.0, Palette.with_alpha(color, 0.3))
		draw_circle(Vector2.ZERO, 5.0, Palette.glow(color, 1.6))
		draw_arc(Vector2.ZERO, 12.0, _time * 9.0, _time * 9.0 + TAU * 0.7, 16,
			Palette.glow(color, 1.3), 2.0)


## Tasoskaalaus: void-assassiini — roolin haurain, mutta pinoräjäytys ja
## perusisku kasvavat rajusti. Itemikäyrän kanssa tämä on aito snowball-rooli.
func _level_scaling() -> Dictionary:
	return {"hp": 0.68, "damage": 1.25, "spell": 1.35, "melee": 1.32, "regen": 1.0}


## Väistön kehitys: faasi (void-olento liukuu todellisuuden läpi).
func _dodge_evolution() -> String:
	return "phase"


## Botin rankkausjärjestys: Pinoräjäytys ensin, perus (pinot) toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "basic", "a1", "dodge"]
