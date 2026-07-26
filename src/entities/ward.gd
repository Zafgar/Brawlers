class_name Ward
extends Node2D
## Vartiolyhdyn vartija (aktiivi "vartija"): tikun päässä hehkuva lyhty, joka
## tähystää aluetta 60 sekuntia. Näkyy OMAN joukkueen minimapilla; säteellä
## liikkuvat vihollissankarit merkitään detected-listaan, jonka PaneHud nostaa
## kirkkaampina blippeinä omistajajoukkueen kartalle. Vartija on v1:ssä
## kohdistamaton (ei HP:ta); enintään 2 per sankari — vanhin poistuu.

const LIFETIME := 60.0
const DETECT_RADIUS := 520.0
const MAX_PER_HERO := 2

var arena = null
var owner_hero = null
var team := 0
var age := 0.0
var detected: Array = []         # säteellä olevat vihollissankarit (PaneHud lukee)

var _time := 0.0
var _detect_t := 0.0
var _seen: Dictionary = {}       # instanssi-id -> nähty viime tikillä (reunatunnistus)


func setup(p_arena, p_owner) -> void:
	arena = p_arena
	owner_hero = p_owner
	team = p_owner.team
	global_position = p_owner.global_position
	z_index = 6
	# Enintään MAX_PER_HERO vartijaa per sankari: vanhin poistuu tieltä.
	var own: Array = []
	for w in arena.wards:
		if is_instance_valid(w) and w.owner_hero == owner_hero:
			own.append(w)
	while own.size() >= MAX_PER_HERO:
		var oldest = own.pop_front()
		arena.wards.erase(oldest)
		oldest.queue_free()
	arena.wards.append(self)


func _physics_process(delta: float) -> void:
	_time += delta
	age += delta
	if age >= LIFETIME:
		# Vartijan sammuminen on taktinen tieto: se kuuluu omistajalle.
		if not Game.simulating:
			AudioMgr.play("ward_expire", 0.05, -9.0, global_position)
		arena.wards.erase(self)
		queue_free()
		return
	# Havainnot kevyellä tikillä (ei joka framea).
	_detect_t -= delta
	if _detect_t <= 0.0:
		_detect_t = 0.25
		detected = []
		var fresh: Dictionary = {}
		var new_contact := false
		for enemy in arena.enemy_heroes(team):
			if enemy.global_position.distance_to(global_position) > DETECT_RADIUS:
				continue
			detected.append(enemy)
			var eid: int = enemy.get_instance_id()
			fresh[eid] = true
			if not _seen.has(eid):
				new_contact = true
		_seen = fresh
		# Vain UUSI kontakti soi — muuten säteellä seisova vihollinen piippaisi
		# neljä kertaa sekunnissa.
		if new_contact and not Game.simulating:
			AudioMgr.play("ward_spot", 0.0, -8.0)
	if arena.visual_position_active(global_position, 560.0):
		queue_redraw()


func _draw() -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	var tcol: Color = Palette.team(team)
	var glow := Palette.glow(Palette.GOLD, 1.3)
	# Varjo ja tikku.
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0.02, 0.03, 0.08, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(Vector2(0, 6), Vector2(0, -26), Color("6b5637"), 3.0)
	# Lyhty: pieni kehikko + lämmin liekki, joukkuevärinen rengas.
	var lamp := Vector2(0, -32)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(lamp, 10.0 + pulse * 2.0, Palette.with_alpha(glow, 0.16))
	draw_rect(Rect2(lamp + Vector2(-6, -8), Vector2(12, 15)), Color("2c2418"))
	draw_rect(Rect2(lamp + Vector2(-4.5, -6), Vector2(9, 11)),
		Palette.with_alpha(glow, 0.8 + pulse * 0.2))
	draw_line(lamp + Vector2(-6, -8), lamp + Vector2(6, -8), Color("6b5637"), 2.0)
	draw_arc(lamp, 13.0, 0.0, TAU, 20, Palette.with_alpha(tcol, 0.75), 2.0)
	# Jäljellä oleva elinaika kaarena lyhdyn ympärillä.
	var left := clampf(1.0 - age / LIFETIME, 0.0, 1.0)
	draw_arc(lamp, 16.0, -PI / 2.0, -PI / 2.0 + TAU * left, 26,
		Palette.with_alpha(tcol, 0.45), 2.0)
	# Havainto: laajeneva hälytysrengas kun vihollinen on tähystysalueella.
	if not detected.is_empty():
		var ping := fmod(_time, 1.1) / 1.1
		draw_arc(Vector2.ZERO, DETECT_RADIUS * ping, 0.0, TAU, 48,
			Palette.with_alpha(Palette.glow(tcol, 1.4), (1.0 - ping) * 0.4), 2.5)
		draw_arc(Vector2.ZERO, DETECT_RADIUS, 0.0, TAU, 48,
			Palette.with_alpha(tcol, 0.14), 1.5)
