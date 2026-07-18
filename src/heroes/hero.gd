class_name Hero
extends CharacterBody2D
## Kaikkien sankarien kantaluokka. Hoitaa liikkeen, kykyjen ajoituksen,
## kestävyyden, tilavaikutukset, tyrmäyksen ja paluun kentälle.
##
## Sankarikohtaiset kyvyt toteutetaan aliluokissa ylikirjoittamalla:
##   _basic(dir), _ability1(dir), _ability2(dir), _dodge_action(dir),
##   _ultimate(dir), _passive_update(delta)
## Latautuvia perushyökkäyksiä varten voi ylikirjoittaa _attack_control().

signal knocked_out(hero, source)

const ACCEL := 2600.0
const REGEN_DELAY := 5.0
const REGEN_PER_SEC := 14.0
const RESPAWN_TIME := 4.5
const CARRY_SPEED_MULT := 0.82
const ASSIST_WINDOW := 5.0
const INPUT_BUFFER := 0.15           # syötepuskuri: kyky laukeaa vaikka nappi painettiin hieman etuajassa

var arena = null                    # Arena, asetetaan ennen add_childia
var profile: PlayerProfile = null
var controller = null               # DeviceInput tai BotBrain (sama rajapinta)
var hero_id := ""
var team := 0

var max_hp := 200.0
var hp := 200.0
var base_speed := 320.0
var radius := 26.0

var alive := true
var respawn_timer := 0.0
var iframes := 0.0
var since_damage := 99.0

var aim := Vector2.RIGHT
var move_dir := Vector2.ZERO
var carrying := false               # kantaa reliikkiä

var ult_charge := 0.0               # 0..100
var cd := {"basic": 0.0, "a1": 0.0, "a2": 0.0, "dodge": 0.0}
var cd_max := {"basic": 0.5, "a1": 8.0, "a2": 8.0, "dodge": 4.0}

# Suojat ja tilavaikutukset
var shield_hp := 0.0
var shield_timer := 0.0
var shield_source: Hero = null
var slow_timer := 0.0
var slow_factor := 1.0
var haste_timer := 0.0
var haste_factor := 1.0
var root_timer := 0.0
var stun_timer := 0.0
var mark_timer := 0.0               # merkitty kohde ottaa lisävahinkoa (Scout)
var kb_resist := 0.0                # 0..1, tankeille

# Suuntatorjunta (Bastionin kilpivalli, geneerinen mekaniikka)
var guard_timer := 0.0
var guard_absorb := 0.7
var guard_arc_deg := 80.0

# Väistösyöksy
var dash_timer := 0.0
var dash_velocity := Vector2.ZERO

var visual: HeroVisual = null
var _recent_damagers: Array = []    # [{hero, time}]
var _ult_ready_announced := false
var _buf := {"a1": 0.0, "a2": 0.0, "ult": 0.0, "dodge": 0.0}  # syötepuskurin ajastimet

# Tähtäys: osa kyvyistä tähdätään pitämällä nappi pohjassa (tähtäysviiva
# näkyy) ja laukaistaan vapautettaessa. Latauskyvyt (Quill) näyttävät myös viivan.
var _aiming_slot := ""              # "" = ei tähtäystä, muuten "a1"/"a2"
var aim_guide = null                # AimGuide-lapsisolmu
var _aim_active := false            # piirretäänkö tähtäysviiva juuri nyt
var _aim_len := 420.0
var _aim_charge := 0.0              # 0..1, vaikuttaa viivan paksuuteen/kirkkauteen
var _aim_color := Color.WHITE

# Vaikeustason kertoimet (vain epäreilu botti poikkeaa 1.0:sta); setup() lukee
# nämä bottiohjaimelta ja soveltaa combatissa.
var dmg_out_mult := 1.0
var dmg_in_mult := 1.0
var ult_gain_mult := 1.0


func setup(p_arena, p_profile: PlayerProfile, p_controller) -> void:
	arena = p_arena
	profile = p_profile
	controller = p_controller
	hero_id = p_profile.hero_id
	team = p_profile.team

	var def := HeroDef.get_def(hero_id)
	max_hp = def["hp"]
	hp = max_hp
	base_speed = def["speed"]
	for slot in ["basic", "a1", "a2", "dodge"]:
		cd_max[slot] = HeroDef.cooldown(hero_id, slot)

	# Bottien vaikeustason kertoimet (taso 6 = epäreilu huijaa).
	if controller != null and controller.is_bot():
		dmg_out_mult = controller.damage_mult
		dmg_in_mult = controller.damage_taken_mult
		ult_gain_mult = controller.ult_gain_mult
		base_speed *= controller.speed_mult
		for slot in cd_max:
			cd_max[slot] = float(cd_max[slot]) * controller.cooldown_mult

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	aim_guide = AimGuide.new()
	aim_guide.hero = self
	add_child(aim_guide)

	visual = HeroVisual.new()
	visual.hero = self
	add_child(visual)


func _physics_process(delta: float) -> void:
	if arena == null or arena.state != arena.State.PLAY:
		velocity = Vector2.ZERO
		_aim_active = false
		_aiming_slot = ""
		return
	if not alive:
		_aim_active = false
		_aiming_slot = ""
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	controller.update(self, delta)
	_tick_status(delta)

	# Tähtäys
	var aim_input: Vector2 = controller.aim_vector()
	if aim_input.length() > 0.2:
		aim = aim_input.normalized()
	elif move_dir.length() > 0.2:
		aim = move_dir.normalized()

	# Liike
	var mv := Vector2.ZERO
	if root_timer <= 0.0 and stun_timer <= 0.0:
		mv = controller.move_vector()
	var speed := base_speed * slow_factor * haste_factor
	if carrying:
		speed *= CARRY_SPEED_MULT
	if arena.map != null:
		speed *= arena.map.terrain_mult(global_position)  # esim. vesi hidastaa

	if dash_timer > 0.0:
		dash_timer -= delta
		velocity = dash_velocity
	else:
		velocity = velocity.move_toward(mv * speed, ACCEL * delta)

	if arena.map != null:
		velocity += arena.map.conveyor_push(global_position)
	move_and_slide()
	move_dir = mv

	# Syötepuskurit: painallukset jäävät hetkeksi muistiin, joten kyky laukeaa
	# heti kun jäähdytys sallii vaikka nappi painettiin hiukan etuajassa tai
	# tainnutuksen aikana. Tämä tekee ohjaimesta paljon luotettavamman.
	_buffer_inputs(delta)
	_aim_active = false   # nollataan joka framessa; kyvyt/lataus aktivoivat tarvittaessa

	# Toiminnot
	if stun_timer <= 0.0:
		_attack_control(
			controller.attack_held(),
			controller.attack_just_pressed(),
			controller.attack_just_released(),
			aim, delta)
		# Kyvyt toimivat myös reliikkiä kannettaessa (kuten väistökin).
		# Tähdättävät kyvyt (pito -> vapautus) hoidetaan _run_ability_slotissa.
		_run_ability_slot("a1", 1)
		_run_ability_slot("a2", 2)
		if _buf.ult > 0.0 and ult_charge >= 100.0:
			_buf.ult = 0.0
			ult_charge = 0.0
			_ult_ready_announced = false
			AudioMgr.play("ult")
			arena.shake(0.35)
			_ultimate(aim)
		if _buf.dodge > 0.0 and cd.dodge <= 0.0:
			_buf.dodge = 0.0
			cd.dodge = cd_max.dodge * (1.5 if carrying else 1.0)
			var dodge_dir := mv if mv.length() > 0.2 else aim
			_dodge_action(dodge_dir.normalized())
		if carrying and controller.drop_just():
			arena.relic.drop_from_carrier(false)
	else:
		_aiming_slot = ""   # tainnutus keskeyttää tähtäyksen

	# Palautuminen
	since_damage += delta
	if since_damage > REGEN_DELAY and hp < max_hp:
		hp = minf(hp + REGEN_PER_SEC * delta, max_hp)

	# Latautumiset
	for slot in cd:
		if cd[slot] > 0.0:
			cd[slot] -= delta
	add_ult(delta * 2.2)

	_passive_update(delta)
	iframes = maxf(iframes - delta, 0.0)


func _tick_status(delta: float) -> void:
	slow_timer -= delta
	if slow_timer <= 0.0:
		slow_factor = 1.0
	haste_timer -= delta
	if haste_timer <= 0.0:
		haste_factor = 1.0
	root_timer = maxf(root_timer - delta, 0.0)
	stun_timer = maxf(stun_timer - delta, 0.0)
	mark_timer = maxf(mark_timer - delta, 0.0)
	guard_timer = maxf(guard_timer - delta, 0.0)
	shield_timer -= delta
	if shield_timer <= 0.0:
		shield_hp = 0.0


## Lukee ohjaimen kykypainallukset puskuriin ja vanhentaa vanhat painallukset.
## Painallus säilyy INPUT_BUFFER-sekuntia, joten se ei huku framejen välissä.
func _buffer_inputs(delta: float) -> void:
	_buf.a1 = maxf(float(_buf.a1) - delta, 0.0)
	_buf.a2 = maxf(float(_buf.a2) - delta, 0.0)
	_buf.ult = maxf(float(_buf.ult) - delta, 0.0)
	_buf.dodge = maxf(float(_buf.dodge) - delta, 0.0)
	if controller.ability1_just():
		_buf.a1 = INPUT_BUFFER
	if controller.ability2_just():
		_buf.a2 = INPUT_BUFFER
	if controller.ult_just():
		_buf.ult = INPUT_BUFFER
	if controller.dodge_just():
		_buf.dodge = INPUT_BUFFER


## Käsittelee yhden kykypaikan. Tähdättävä kyky (pito -> vapautus) näyttää
## tähtäysviivan ja laukeaa vasta vapautettaessa; muut laukeavat heti
## syötepuskurin kautta. Botit käyttävät aina välitöntä laukaisua.
func _run_ability_slot(slot: String, num: int) -> void:
	var aimed: bool = not controller.is_bot() and slot in _aimed_slots()
	if aimed:
		var held: bool = controller.ability1_held() if num == 1 else controller.ability2_held()
		var released: bool = controller.ability1_released() if num == 1 else controller.ability2_released()
		if _aiming_slot == slot:
			_aim_active = true
			_aim_len = _aim_range(slot)
			_aim_color = hero_color()
			_aim_charge = 1.0
			if released:
				_aiming_slot = ""
				if cd[slot] <= 0.0:
					cd[slot] = cd_max[slot]
					_cast_slot(slot)
		elif _aiming_slot == "" and held and cd[slot] <= 0.0:
			_aiming_slot = slot
	elif _buf[slot] > 0.0 and cd[slot] <= 0.0:
		_buf[slot] = 0.0
		cd[slot] = cd_max[slot]
		_cast_slot(slot)


func _cast_slot(slot: String) -> void:
	if slot == "a1":
		_ability1(aim)
	else:
		_ability2(aim)


## Ylikirjoita palauttamaan kykypaikat ("a1"/"a2") jotka tähdätään pitämällä
## nappi pohjassa. Oletuksena tyhjä -> kaikki kyvyt laukeavat heti painettaessa.
func _aimed_slots() -> Array:
	return []


## Tähtäysviivan pituus kyvylle (ylikirjoitettavissa sankarikohtaisesti).
func _aim_range(_slot: String) -> float:
	return 420.0


## Oletushyökkäyskontrolli: liipaisin pohjassa -> ammu aina kun cd sallii.
## Quill ylikirjoittaa tämän lataukselle.
func _attack_control(held: bool, _just_pressed: bool, _just_released: bool,
		dir: Vector2, _delta: float) -> void:
	if held and cd.basic <= 0.0:
		cd.basic = cd_max.basic
		_basic(dir)


# --- Sankarikohtaiset kyvyt (ylikirjoitetaan aliluokissa) ---

func _basic(_dir: Vector2) -> void:
	pass


func _ability1(_dir: Vector2) -> void:
	pass


func _ability2(_dir: Vector2) -> void:
	pass


func _ultimate(_dir: Vector2) -> void:
	pass


func _passive_update(_delta: float) -> void:
	pass


## Oletusväistö: nopea syöksy, lyhyet suojaruudut.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 950.0, 0.16, true)
	AudioMgr.play("dash")
	Fx.dust(arena, global_position)


# --- Taisteluapurit ---

func dash(dir: Vector2, speed: float, duration: float, with_iframes := false) -> void:
	if dir.length() < 0.1:
		dir = aim
	dash_timer = duration
	dash_velocity = dir.normalized() * speed
	if with_iframes:
		iframes = maxf(iframes, duration + 0.05)
	visual.squash(0.75, 1.25)


func deal_damage_to(target: Hero, amount: float, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if target == null or not is_instance_valid(target) or not target.alive:
		return 0.0
	if target.team == team:
		return 0.0
	if kb_dir == Vector2.ZERO:
		kb_dir = (target.global_position - global_position).normalized()
	var dealt := target.take_damage(amount, self, kb, kb_dir)
	if dealt > 0.0:
		profile.stats.damage += dealt
		profile.add_score(dealt * 0.1)
		add_ult(dealt * 0.22)
	return dealt


func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if not alive or iframes > 0.0:
		return 0.0

	# Vaikeustason huijauskertoimet (vain epäreilu botti poikkeaa 1.0:sta):
	# hyökkääjän aiheuttama vahinko ja kohteen ottama vahinko.
	if source != null and is_instance_valid(source):
		amount *= source.dmg_out_mult
	amount *= dmg_in_mult

	# Merkitty kohde (Scoutin vaahtomerkki) ottaa lisävahinkoa kaikilta.
	if mark_timer > 0.0:
		amount *= 1.25

	# Suuntatorjunta (kilpivalli): edestä tulevat osumat vaimenevat.
	if guard_timer > 0.0 and kb_dir != Vector2.ZERO:
		var from_dir := -kb_dir
		if absf(rad_to_deg(from_dir.angle_to(aim))) < guard_arc_deg:
			var absorbed := amount * guard_absorb
			amount -= absorbed
			profile.stats.prevented += absorbed
			profile.add_score(absorbed * 0.08)
			Fx.spark(arena, global_position + aim * radius, Palette.SHIELD)
			AudioMgr.play("shield")

	# Suojakilpi imee ensin.
	if shield_hp > 0.0:
		var soak := minf(shield_hp, amount)
		shield_hp -= soak
		amount -= soak
		if shield_source != null and is_instance_valid(shield_source):
			shield_source.profile.stats.prevented += soak
			shield_source.profile.add_score(soak * 0.08)
		arena.popup(global_position + Vector2(0, -46), str(int(soak)), Palette.SHIELD, 18)

	if amount <= 0.0:
		return 0.0

	hp -= amount
	since_damage = 0.0
	if kb > 0.0 and kb_dir != Vector2.ZERO:
		velocity += kb_dir.normalized() * kb * (1.0 - kb_resist)

	visual.flash()
	arena.popup(global_position + Vector2(0, -46), str(int(amount)), Color.WHITE, 20)
	AudioMgr.play("hit")
	add_ult(amount * 0.14)

	if source != null:
		_recent_damagers = _recent_damagers.filter(
			func(entry): return is_instance_valid(entry.hero))
		_recent_damagers.append({"hero": source, "time": Time.get_ticks_msec() / 1000.0})

	if hp <= 0.0:
		hp = 0.0
		_knockout(source)
	return amount


func heal_hp(amount: float, source: Hero) -> float:
	if not alive or hp >= max_hp:
		return 0.0
	var healed := minf(amount, max_hp - hp)
	hp += healed
	if source != null and source != self:
		source.profile.stats.healing += healed
		source.profile.add_score(healed * 0.12)
		source.add_ult(healed * 0.15)
	arena.popup(global_position + Vector2(0, -46), "+%d" % int(healed), Palette.HEAL, 18)
	Fx.heal_sparkle(arena, global_position)
	return healed


func add_shield(amount: float, duration: float, source: Hero) -> void:
	shield_hp = maxf(shield_hp, amount)
	shield_timer = duration
	shield_source = source
	AudioMgr.play("shield")
	Fx.ring(arena, global_position, Palette.SHIELD, radius + 14.0, 0.35)


func add_ult(points: float) -> void:
	if ult_charge >= 100.0:
		return
	ult_charge = minf(ult_charge + points * ult_gain_mult, 100.0)
	if ult_charge >= 100.0 and not _ult_ready_announced:
		_ult_ready_announced = true
		AudioMgr.play("ult_ready")
		if arena != null:
			arena.popup(global_position + Vector2(0, -70), "ULTI VALMIS!", Palette.GOLD, 20)


func apply_slow(factor: float, duration: float) -> void:
	if factor < slow_factor or slow_timer <= 0.0:
		slow_factor = factor
	slow_timer = maxf(slow_timer, duration)


func apply_haste(factor: float, duration: float) -> void:
	haste_factor = maxf(haste_factor, factor)
	haste_timer = maxf(haste_timer, duration)


func apply_root(duration: float) -> void:
	root_timer = maxf(root_timer, duration)
	arena.popup(global_position + Vector2(0, -60), "JUURTUNUT", Palette.BAD, 16)
	AudioMgr.play("root")


func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)


func apply_mark(duration: float) -> void:
	mark_timer = maxf(mark_timer, duration)
	arena.popup(global_position + Vector2(0, -60), "MERKITTY", Palette.GOLD, 14)


func start_guard(duration: float, absorb := 0.7, arc_deg := 80.0) -> void:
	guard_timer = duration
	guard_absorb = absorb
	guard_arc_deg = arc_deg


# --- Tyrmäys ja paluu ---

func _knockout(source: Hero) -> void:
	alive = false
	_aiming_slot = ""
	_aim_active = false
	respawn_timer = RESPAWN_TIME
	profile.stats.deaths += 1
	velocity = Vector2.ZERO
	shield_hp = 0.0
	guard_timer = 0.0
	dash_timer = 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	root_timer = 0.0
	stun_timer = 0.0
	mark_timer = 0.0

	var now := Time.get_ticks_msec() / 1000.0
	if source != null and is_instance_valid(source) and source != self:
		source.profile.stats.kos += 1
		source.profile.add_score(30.0)
		source.add_ult(20.0)
		for entry in _recent_damagers:
			if not is_instance_valid(entry.hero):
				continue
			if entry.hero == source or entry.hero == self:
				continue
			if now - entry.time <= ASSIST_WINDOW and entry.hero.team != team:
				entry.hero.profile.stats.assists += 1
				entry.hero.profile.add_score(15.0)
	_recent_damagers.clear()

	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	Fx.knockout_burst(arena, global_position, profile.color())
	AudioMgr.play("ko")
	arena.shake(0.3)
	knocked_out.emit(self, source)
	arena.on_hero_ko(self, source)


func _respawn() -> void:
	alive = true
	hp = max_hp
	iframes = 2.0
	global_position = arena.map.spawn_point(team, profile.index)
	visible = true
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	for slot in cd:
		cd[slot] = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(profile.color(), 0.9), 60.0, 0.5)
	AudioMgr.play("respawn")
	arena.on_hero_respawn(self)


## Palauttaa sankarin täyteen kuntoon erän alussa.
func reset_for_round(keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	_aiming_slot = ""
	_aim_active = false
	hp = max_hp
	shield_hp = 0.0
	carrying = false
	iframes = 0.0
	respawn_timer = 0.0
	velocity = Vector2.ZERO
	dash_timer = 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	haste_factor = 1.0
	haste_timer = 0.0
	root_timer = 0.0
	stun_timer = 0.0
	mark_timer = 0.0
	guard_timer = 0.0
	ult_charge = ult_charge * keep_ult_fraction
	_ult_ready_announced = ult_charge >= 100.0
	for slot in cd:
		cd[slot] = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	_recent_damagers.clear()
	global_position = arena.map.spawn_point(team, profile.index)


func is_threatened() -> bool:
	return hp < max_hp * 0.35


func hero_color() -> Color:
	return HeroDef.get_def(hero_id)["color"]


## Tähtäysviiva: piirtää sankarin edestä katkoviivan ja tähtäimen kun kykyä
## tähdätään tai latauskykyä ladataan. Lukee tilan sankarilta joka framessa.
class AimGuide:
	extends Node2D

	var hero = null

	func _ready() -> void:
		z_index = -1

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if hero == null or not is_instance_valid(hero):
			return
		if not hero.alive or not hero._aim_active:
			return
		var dir: Vector2 = hero.aim
		if dir.length() < 0.1:
			return
		dir = dir.normalized()
		var length: float = hero._aim_len
		var charge: float = clampf(hero._aim_charge, 0.0, 1.0)
		var col: Color = hero._aim_color
		var rad: float = hero.radius
		var start: Vector2 = dir * (rad + 6.0)
		var tip: Vector2 = dir * length
		# Katkoviiva pisteinä — näyttää suunnan peittämättä koko kenttää.
		var dist := start.distance_to(tip)
		var steps: int = int(dist / 16.0)
		for i in range(steps):
			var f := float(i) / maxf(float(steps), 1.0)
			var p: Vector2 = start.lerp(tip, f)
			var a: float = (0.14 + charge * 0.34) * (1.0 - f * 0.35)
			draw_circle(p, 2.0 + charge * 1.5, Palette.with_alpha(col, a))
		# Tähtäin kärkeen
		var ring_a: float = 0.35 + charge * 0.45
		draw_arc(tip, 12.0 + charge * 6.0, 0.0, TAU, 22, Palette.with_alpha(col, ring_a), 2.0)
		draw_circle(tip, 3.0 + charge * 2.0, Palette.with_alpha(col, ring_a))
