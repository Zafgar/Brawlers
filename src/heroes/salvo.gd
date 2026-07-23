class_name Salvo
extends Hero
## Ranger/tuhotyöläinen: miinanheitin, pitkän kantaman morttari ja bunkkeriohjus.
## Kylvää miinoja (enintään 5), ennakoi hitaasti putoavalla kranaatilla ja ultissa
## lukittuu panssaroiduksi laukaisuasemaksi ohjaamaan kiihtyvää raskasta ohjusta.
## Ei resurssia — pelkkä jäähdytys ja miinojen enimmäismäärä rajaavat.

const MAX_MINES := 5
const THROW_DIST := 210.0
const MINE_DMG := 52.0
const MINE_BLAST := 132.0
const MINE_TRIGGER := 80.0

const MORTAR_RANGE := 780.0
const MORTAR_DEFAULT_RANGE := 500.0
const MORTAR_DMG := 64.0
const MORTAR_BLAST := 138.0
const MORTAR_FLIGHT := 1.45

const HOVER_DUR := 1.2
const HOVER_SLOW := 0.6

const ROCKET_LIFE := 8.0
const ROCKET_DMG := 185.0
const ROCKET_BLAST := 230.0
const ROCKET_SPEED := 175.0
const ROCKET_ACCEL := 74.0
const ROCKET_MAX_SPEED := 690.0
const ROCKET_TURN := 2.45
const ROCKET_MIN_TURN := 0.58
const BUNKER_DAMAGE_MULT := 0.28

var _mines: Array = []
var _rocket = null
var _hover := 0.0


func _init() -> void:
	radius = 23.0


## L1: pidä pohjassa, siirrä maalia oikealla tatilla ja vapauta.
func _aimed_slots() -> Array:
	return ["a2"]


func _ground_targeted_slots() -> Array:
	return ["a2"]


func _aim_range(_slot: String) -> float:
	return MORTAR_RANGE


func _aim_default_range(_slot: String) -> float:
	return MORTAR_DEFAULT_RANGE


func _aim_target_radius(_slot: String) -> float:
	return MORTAR_BLAST


## Perushyökkäys: kranaattipommi — suora ammus kohtalaisella vahingolla.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("salvo_grenade", 0.08, -2.0, global_position)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Color("ffb03a"), 1.4))
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 880.0,
		"dmg": 16.0,
		"radius": 11.0,
		"life": 0.85,
		"kb": 120.0,
		"color": Color("ffb03a"),
		"visual": "salvo_grenade",
		"spin": true,
	})


## Kyky 1: Miina — heittää miinan tähtäyssuuntaan. Enintään 5 kentällä; jos
## raja täyttyy, vanhin räjähtää tehden tilaa.
func _ability1(dir: Vector2) -> void:
	_prune_mines()
	if _mines.size() >= MAX_MINES:
		var oldest = _mines.pop_front()
		if is_instance_valid(oldest):
			oldest.detonate()
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	var pos: Vector2 = global_position + d * THROW_DIST
	if arena.map != null:
		pos = arena.map.clamp_to_field(pos, MINE_BLAST * 0.5)
	AudioMgr.play("pop", 0.08, -2.0)
	Fx.dust(arena, pos)
	var m := Mine.plant(self, pos, {
		"dmg": MINE_DMG,
		"blast": MINE_BLAST,
		"trigger": MINE_TRIGGER,
	})
	_mines.append(m)


## Kyky 2 / L1: Kaarimorttari — pitkän kantaman, hitaasti alas tuleva osuma.
## Tarkka varoitus tekee siitä väistettävän; onnistunut ennakointi palkitaan.
func _ability2(dir: Vector2) -> void:
	var target := aimed_ground_position(dir, MORTAR_RANGE, MORTAR_DEFAULT_RANGE)
	AudioMgr.play("salvo_mortar_launch", 0.05, -1.0, global_position)
	ability_signature("salvo", 150.0, target - global_position)
	controller_rumble(0.18, 0.30, 0.22)
	visual.squash(0.88, 1.12)
	Fx.dust(arena, global_position - aim * 12.0)
	MortarShell.launch(self, target, {
		"flight": MORTAR_FLIGHT,
		"blast": MORTAR_BLAST,
		"dmg": MORTAR_DMG,
		"kb": 360.0,
	})


## Poistaa mitätöityneet/räjähtäneet miinat listasta.
func _prune_mines() -> void:
	_mines = _mines.filter(func(m): return is_instance_valid(m) and not m._dead)


## Väistö (X): Leijunta — nousee ilmaan kohdistamattomaksi (immuuni) hetkeksi ja
## liikkuu kelluen. Voi käyttää kykyjä ilmassa. Pitkä jäähdytys.
func _dodge_action(_dir: Vector2) -> void:
	_hover = HOVER_DUR
	iframes = maxf(iframes, HOVER_DUR)
	visual.squash(0.8, 1.25)
	AudioMgr.play("dash", 0.1, 4.0)
	Fx.ring(arena, global_position, Palette.glow(Color("ffd76d"), 1.4), radius + 16.0, 0.4, 4.0)
	arena.popup(global_position + Vector2(0, -68), "LEIJUNTA", Palette.glow(Color("ffd76d"), 1.3), 15)


## Leijunnan aikana liike on kelluvan hidasta.
func _move_speed_mult() -> float:
	return HOVER_SLOW if _hover > 0.0 else 1.0


## Ultimate: Bunkkeriohjus — Salvo jää näkyviin panssaroituna laukaisuasemana ja
## ottaa vain osan vahingosta. Ohjus kiihtyy rajusti, jolloin sen kääntäminen
## vaikeutuu lennon edetessä. Suuri vahinko palkitsee vaikean osuman.
func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	piloting = true
	visible = true
	velocity = Vector2.ZERO
	iframes = maxf(iframes, 0.18)   # vain bunkkerin lukittumisen lyhyt siirtymäsuoja
	set_collision_layer_value(2, true)
	arena.popup(global_position + Vector2(0, -90), "BUNKKERI!", Palette.glow(Color("ffd76d"), 1.6), 26)
	AudioMgr.play("salvo_bunker", 0.04, 0.0, global_position)
	controller_rumble(0.32, 0.65, 0.55)
	Fx.dust(arena, global_position)
	Fx.ring(arena, global_position, Palette.glow(Color("ffb03a"), 1.5), radius + 34.0, 0.55, 7.0)
	_rocket = GuidedRocket.launch(self, global_position + d * 44.0, d, {
		"life": ROCKET_LIFE,
		"dmg": ROCKET_DMG,
		"blast": ROCKET_BLAST,
		"speed": ROCKET_SPEED,
		"accel": ROCKET_ACCEL,
		"max_speed": ROCKET_MAX_SPEED,
		"turn": ROCKET_TURN,
		"min_turn": ROCKET_MIN_TURN,
	})


## Avaa bunkkerin ohjuksen päättyessä. Nimi säilyy yhteensopivana raketin kanssa.
func surface() -> void:
	piloting = false
	_rocket = null
	if not alive:
		return
	set_collision_layer_value(2, true)
	visible = true
	iframes = maxf(iframes, 0.2)
	if arena != null:
		Fx.dust(arena, global_position)
		Fx.ring(arena, global_position, Palette.glow(Color("ffb03a"), 1.4), radius + 18.0, 0.45, 5.0)
		AudioMgr.play("salvo_bunker_open", 0.05, -2.0, global_position)


## Bunkkeri ei ole immuniteetti: Salvo voidaan yhä tyrmätä, mutta raskaat levyt
## vaimentavat 72 % sisään tulevasta vahingosta ohjuksen lennon ajan.
func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if piloting and iframes <= 0.0 and amount > 0.0:
		var prevented := amount * (1.0 - BUNKER_DAMAGE_MULT)
		if profile != null:
			profile.stats.prevented += prevented
			profile.add_score(prevented * 0.05)
		if arena != null:
			Fx.spark(arena, global_position + kb_dir.normalized() * radius,
				Palette.glow(Color("ffb03a"), 1.45))
		AudioMgr.play("shield", 0.1, -8.0, global_position)
		amount *= BUNKER_DAMAGE_MULT
	return super(amount, source, kb, kb_dir)


## Kameran seurantapiste: ohjauksen aikana seuraa rakettia. Salvo itse jää silti
## kentälle näkyväksi ja vahingoitettavaksi bunkkeriksi.
func camera_focus() -> Vector2:
	if piloting and _rocket != null and is_instance_valid(_rocket):
		return _rocket.global_position
	return global_position


func _passive_update(delta: float) -> void:
	if _hover > 0.0:
		_hover = maxf(_hover - delta, 0.0)
	# Turvaverkko: jos ohjaus jäi päälle mutta raketti katosi, nouse pintaan.
	if piloting and (_rocket == null or not is_instance_valid(_rocket)):
		surface()
	# Pidä miinalista ajan tasalla (räjähtäneet/vanhentuneet pois).
	elif not _mines.is_empty():
		_prune_mines()


## Miinat ja ohjaustila nollataan tyrmäyksestä ja erän vaihtuessa.
func _respawn() -> void:
	super()
	_clear_rocket()
	_clear_mines()
	_hover = 0.0


func reset_for_round(keep_ult_fraction := 0.5) -> void:
	_clear_rocket()
	super(keep_ult_fraction)
	visible = true
	set_collision_layer_value(2, true)
	_clear_mines()
	_hover = 0.0


func _clear_rocket() -> void:
	if _rocket != null and is_instance_valid(_rocket):
		_rocket.queue_free()
	_rocket = null


func _clear_mines() -> void:
	for m in _mines:
		if is_instance_valid(m):
			m.queue_free()
	_mines = []


## Tasoskaalaus: tuhotyöläinen-hypercarry — räjähteet skaalautuvat rajusti.
func _level_scaling() -> Dictionary:
	return {"hp": 0.85, "damage": 1.15, "spell": 1.30, "melee": 0.90, "regen": 0.95}


## Väistön kehitys: vauhti (miinoittaja pitää välimatkan).
func _dodge_evolution() -> String:
	return "haste"


## Botin rankkausjärjestys: Morttari ensin, miinat toisena.
func _bot_skill_order() -> Array:
	return ["ult", "a2", "a1", "basic", "dodge"]
