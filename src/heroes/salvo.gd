class_name Salvo
extends Hero
## Ranger/tuhotyöläinen: miinanheitin ja ohjus. Kylvää miinoja (enintään 5) ja
## räjäyttää ne kerralla, leijuu kohdistamattomana väistäessään, ja ultissa
## kaivautuu maan alle ohjaamaan hidasta ohjusta seinien ja tornien läpi.
## Ei resurssia — pelkkä jäähdytys ja miinojen enimmäismäärä rajaavat.

const MAX_MINES := 5
const THROW_DIST := 210.0
const MINE_DMG := 52.0
const MINE_BLAST := 132.0
const MINE_TRIGGER := 80.0

const HOVER_DUR := 1.2
const HOVER_SLOW := 0.6

const ROCKET_LIFE := 8.0
const ROCKET_DMG := 155.0
const ROCKET_BLAST := 215.0
const ROCKET_SPEED := 270.0
const ROCKET_TURN := 3.4

var _mines: Array = []
var _rocket = null
var _hover := 0.0


func _init() -> void:
	radius = 23.0


## Perushyökkäys: kranaattipommi — suora ammus kohtalaisella vahingolla.
func _basic(dir: Vector2) -> void:
	AudioMgr.play("pop", 0.1, 2.0)
	visual.attack_swing()
	Fx.spark(arena, global_position + dir * 24.0, Palette.glow(Color("ffb03a"), 1.4))
	Projectile.launch(self, global_position + dir * 26.0, dir, {
		"speed": 880.0,
		"dmg": 16.0,
		"radius": 11.0,
		"life": 0.85,
		"kb": 120.0,
		"color": Color("ffb03a"),
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


## Kyky 2: Räjäytä kaikki — laukaisee kaikki kentällä olevat miinat kerralla.
func _ability2(_dir: Vector2) -> void:
	_prune_mines()
	if _mines.is_empty():
		AudioMgr.play("ui_back", 0.05, -8.0)
		return
	AudioMgr.play("quake", 0.05, 0.0)
	# Kopioi lista: detonate poistaa/mitätöi miinat kesken iteraation.
	var snapshot: Array = _mines.duplicate()
	for m in snapshot:
		if is_instance_valid(m):
			m.detonate()
	_mines = []


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


## Ultimate: Ohjusisku — kaivautuu maan alle (immuuni, näkymätön) ja laukaisee
## ohjattavan ohjuksen. Ohjus kulkee seinien/tornien läpi ja osuu vain
## vihollisiin/olentoihin. Kun ohjus päättyy, Salvo nousee pintaan (surface).
func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		d = aim
	piloting = true
	visible = false
	velocity = Vector2.ZERO
	iframes = maxf(iframes, ROCKET_LIFE + 1.5)
	set_collision_layer_value(2, false)   # maan alla: muut eivät törmää
	arena.popup(global_position + Vector2(0, -90), "OHJUS!", Palette.glow(Color("ffd76d"), 1.6), 26)
	AudioMgr.play("smoke", 0.05, -2.0)
	Fx.dust(arena, global_position)
	Fx.ring(arena, global_position, Palette.glow(Color("ffb03a"), 1.4), radius + 20.0, 0.5, 5.0)
	_rocket = GuidedRocket.launch(self, global_position + d * 44.0, d, {
		"life": ROCKET_LIFE,
		"dmg": ROCKET_DMG,
		"blast": ROCKET_BLAST,
		"speed": ROCKET_SPEED,
		"turn": ROCKET_TURN,
	})


## Nostaa Salvon takaisin pintaan (kutsutaan ohjuksen päättyessä). Idempotentti.
func surface() -> void:
	piloting = false
	_rocket = null
	if not alive:
		return   # tyrmätty ohjauksen aikana (harvinaista) -> _respawn palauttaa törmäyksen
	set_collision_layer_value(2, true)
	visible = true
	iframes = 0.4   # nollaa maan-alla-immuniteetti: pinnalla vain lyhyt suoja-aika
	if arena != null:
		Fx.dust(arena, global_position)
		Fx.ring(arena, global_position, Palette.glow(Color("ffb03a"), 1.4), radius + 18.0, 0.45, 5.0)
		AudioMgr.play("smoke", 0.05, 1.0)


## Kameran seurantapiste: ohjauksen aikana seuraa rakettia (ei maan alla olevaa
## sankaria), jotta pelaaja näkee minne ohjaa.
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
	# Pidä miinalista ajan tasalla (räjähtäneet/vanhentuneet pois) — botin
	# "räjäytä kaikki" -portti lukee koon, joten ei lasketa kuolleita miinoja.
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
