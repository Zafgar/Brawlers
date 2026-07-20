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
# Ei-pelaajayksikkö (viidakko-olento, minioni, rakennus). Jätetään pois
# pelaajakeskeisistä järjestelmistä (kamera, muodostelmat, tuen kohteet).
var is_unit := false
var regen_disabled := false         # rakennukset/minionit eivät palaudu

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
var shield_slot := ""                # antajan kykypaikka (telemetria: kilven arvo)
var slow_timer := 0.0
var slow_factor := 1.0
var haste_timer := 0.0
var haste_factor := 1.0
var root_timer := 0.0
var stun_timer := 0.0
var mark_timer := 0.0               # merkitty kohde ottaa lisävahinkoa (Scout)
var mark_amp := 1.25                # merkin vahinkokerroin (asetetaan apply_markissa)
var kb_resist := 0.0                # 0..1, tankeille

# Lipasjärjestelmä (valinnainen, esim. Scoutin konekivääri). ammo < 0 = ei
# lipasta -> ei piirretä. hero_visual näyttää patruunat ja lataustilan.
var ammo := -1
var ammo_max := 0
var reloading := false

# Suuntatorjunta (Bastionin kilpivalli, geneerinen mekaniikka)
var guard_timer := 0.0
var guard_absorb := 0.7
var guard_arc_deg := 80.0
var guard_radius := 0.0             # > 0 = piirrä leveä kilpivalli tälle säteelle
var guard_slot := ""                # torjunnan kykypaikka (telemetria: torjunnan arvo)

# Tartunta (Titaani pitää kiinni): kohde ei törmää muihin sankareihin oteen
# aikana, jottei se estä/tönäise kantajaa. Ote vapautuu itsestään jos sitä ei
# virkistetä (esim. kantaja kuolee tai pudottaa otteen).
var grabbed_by = null
var _grab_hold_timer := 0.0

# Väistösyöksy
var dash_timer := 0.0
var dash_velocity := Vector2.ZERO

var visual: HeroVisual = null
var _recent_damagers: Array = []    # [{hero, time}]
var _ult_ready_announced := false
var _buf := {"a1": 0.0, "a2": 0.0, "ult": 0.0, "dodge": 0.0}  # syötepuskurin ajastimet
var _heartbeat_t := 0.0             # matalan HP:n sydämenlyöntivaroituksen ajastin
var _deny_cd := 0.0                 # "ei resurssia" -äänen debounce
var _dodge_was_cooling := false     # väistön jäähdytys -> valmis siirtymän havaitsemiseen

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

# Resurssijärjestelmä (valinnainen sankarikohtaisesti). res_type "" = ei
# resurssia -> pelkkä jäähdytys kuten ennen. "mana"/"energy" palautuvat
# ajan myötä, "rage" rakentuu taistelusta. Kyvyt voivat maksaa resurssia.
var res_type := ""
var res := 0.0
var res_max := 100.0
var res_regen := 0.0               # passiivinen palautuminen/s (mana, energy)
var res_cost := {"basic": 0.0, "a1": 0.0, "a2": 0.0, "dodge": 0.0}
var _channel_slot := ""            # kanavoitava kyky pohjassa (esim. kilpi)
var _channel_locked := ""          # resurssi loppui kesken pidon -> lukossa napin vapautukseen asti
var _cast_context := ""            # mikä kykypaikka juuri suorittaa (telemetria)
var _rage_idle := 0.0              # aika viime taistelutoiminnasta (rage-vaimeneminen)

# Kenttäbuffit (blue/red). blue = resurssin nopea palautuminen, red = +vahinko
# ja elämän palautuminen. Aika jäljellä sekunneissa.
var blue_buff := 0.0
var red_buff := 0.0

# Pidä-ja-vapauta ultimate (esim. Prisman alue-esikatselu) ja säde-overlay
# (Prisman kanavoitavat säteet). Overlay piirretään AimGuidessa.
var _ult_holding := false
var _beam_active := false
var _beam_len := 0.0
var _beam_heal := false

# Void-assassin (Rift): pinot tähän sankariin ja ajanpysäytys. void_stacker on
# assassiini joka pinoja asetti (räjäytyksen palkinnot menevät sille).
var void_stacks := 0
var void_stack_timer := 0.0
var void_stacker: Hero = null
var frozen := 0.0                  # ajanpysäytys: > 0 = ei voi liikkua/toimia


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

	# Sankari voi määrittää resurssin (mana/energy/rage) ja säätää cd_max.
	_setup_resource()

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
		_channel_slot = ""
		_ult_holding = false
		_beam_active = false
		return
	if not alive:
		_aim_active = false
		_aiming_slot = ""
		_channel_slot = ""
		_ult_holding = false
		_beam_active = false
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	# Ajanpysäytys (Riftin ulti): jäätynyt sankari ei liiku eikä toimi, eivätkä
	# sen ajastimet kulu (aika pysähtynyt). Vain jäätymisajastin vähenee.
	if frozen > 0.0:
		frozen -= delta
		velocity = Vector2.ZERO
		_aim_active = false
		_aiming_slot = ""
		_channel_slot = ""
		_beam_active = false
		_ult_holding = false
		return

	controller.update(self, delta)
	_tick_status(delta)
	_tick_resource(delta)

	# Tartunnan itsevapautus: jos otetta ei virkistetä (kantaja kuoli, pudotti
	# otteen tms.), palauta törmäys ettei kohde jää haamuksi.
	if grabbed_by != null:
		_grab_hold_timer -= delta
		if _grab_hold_timer <= 0.0 or not is_instance_valid(grabbed_by) or not grabbed_by.alive:
			release_grabbed()

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
		# Perushyökkäyksen konteksti telemetriaan. Tallenna/palauta tarttuva
		# konteksti ettei perushyökkäys pyyhi kesken olevaa kykyä (esim.
		# kanavoitava ult, jonka viivästynyt vahinko tulee awaitin takaa).
		var _prev_ctx := _cast_context
		_act("basic")
		_attack_control(
			controller.attack_held(),
			controller.attack_just_pressed(),
			controller.attack_just_released(),
			aim, delta)
		_act_end()
		_cast_context = _prev_ctx
		# Kyvyt toimivat myös reliikkiä kannettaessa (kuten väistökin).
		# Tähdättävät kyvyt (pito -> vapautus) hoidetaan _run_ability_slotissa.
		_run_ability_slot("a1", 1, delta)
		_run_ability_slot("a2", 2, delta)
		# Ultimate: välitön (oletus) tai pidä-ja-vapauta (esim. Prisman alue).
		if _ult_is_held() and not controller.is_bot():
			if _ult_holding:
				# Viivaesikatselu ultille (esim. Quillin tähdättävä supernuoli).
				var ul: float = _ult_preview_line()
				if ul > 0.0:
					_aim_active = true
					_aim_len = ul
					_aim_color = Palette.glow(Palette.GOLD, 1.4)
					_aim_charge = 1.0
				if controller.ult_released():
					if ult_charge >= 100.0:
						_fire_ult()
					_ult_holding = false
			elif controller.ult_held() and ult_charge >= 100.0:
				_ult_holding = true
		elif _buf.ult > 0.0 and ult_charge >= 100.0:
			_buf.ult = 0.0
			_fire_ult()
		if _buf.dodge > 0.0 and cd.dodge <= 0.0:
			_buf.dodge = 0.0
			cd.dodge = cd_max.dodge * (1.5 if carrying else 1.0)
			var dodge_dir := mv if mv.length() > 0.2 else aim
			_act("dodge")
			_log_cast("dodge")
			_dodge_action(dodge_dir.normalized())
			_act_end()
		if carrying and controller.drop_just():
			arena.relic.drop_from_carrier(false)
	else:
		_aiming_slot = ""   # tainnutus keskeyttää tähtäyksen

	# Palautuminen
	since_damage += delta
	if not regen_disabled and since_damage > REGEN_DELAY and hp < max_hp:
		hp = minf(hp + REGEN_PER_SEC * delta, max_hp)
	if red_buff > 0.0 and hp < max_hp:
		hp = minf(hp + 11.0 * delta, max_hp)   # punainen buffi: elämän palautuminen

	# Matalan HP:n varoitus omalle (ei-botti) sankarille: tup-tup kiihtyy ja
	# voimistuu HP:n laskiessa. Ei-positionaalinen (henkilökohtainen varoitus).
	_heartbeat_t = maxf(_heartbeat_t - delta, 0.0)
	if not controller.is_bot() and hp < max_hp * 0.30 and _heartbeat_t <= 0.0:
		var sev: float = clampf((max_hp * 0.30 - hp) / (max_hp * 0.30), 0.0, 1.0)
		AudioMgr.play("heartbeat", 0.03, lerpf(-8.0, 1.0, sev))
		_heartbeat_t = lerpf(0.62, 0.34, sev)
	_deny_cd = maxf(_deny_cd - delta, 0.0)

	# Latautumiset (+ väistön valmistumisen hiljainen äänivihje)
	for slot in cd:
		if cd[slot] > 0.0:
			cd[slot] -= delta
	if _dodge_was_cooling and cd.dodge <= 0.0 and not controller.is_bot():
		AudioMgr.play("count_tick", 0.0, -14.0)
	_dodge_was_cooling = cd.dodge > 0.0
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
	blue_buff = maxf(blue_buff - delta, 0.0)
	red_buff = maxf(red_buff - delta, 0.0)
	void_stack_timer = maxf(void_stack_timer - delta, 0.0)
	if void_stack_timer <= 0.0 and void_stacks > 0:
		void_stacks = 0
		void_stacker = null


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
func _run_ability_slot(slot: String, num: int, delta: float) -> void:
	var is_bot: bool = controller.is_bot()
	var held: bool = controller.ability1_held() if num == 1 else controller.ability2_held()
	var released: bool = controller.ability1_released() if num == 1 else controller.ability2_released()

	# Kanavoitava kyky: pito ylläpitää vaikutusta (esim. Bastionin energiakilpi).
	# Kun resurssi loppuu kesken pidon, kyky lukittuu: se ei käynnisty uudelleen
	# ennen kuin nappi vapautetaan (muuten regen-tippa käynnistäisi sen heti
	# uudelleen -> säde/kilpi "toimisi" nollaresurssilla).
	if not is_bot and slot in _channeled_slots():
		if _channel_slot == slot:
			if held and res > 0.0:
				_act(slot)
				_channel_tick(slot, delta)
				_act_end()
			else:
				_channel_slot = ""
				_channel_end(slot)
				if held and res <= 0.0:
					_channel_locked = slot
		else:
			if not held and _channel_locked == slot:
				_channel_locked = ""
			if _channel_slot == "" and held and cd[slot] <= 0.0 \
					and res > 0.0 and _channel_locked != slot:
				_channel_slot = slot
				_log_cast(slot)
				_act(slot)
				_channel_tick(slot, delta)
				_act_end()
		return

	# Tähdättävä kyky: pito tähtää, vapautus laukaisee.
	if not is_bot and slot in _aimed_slots():
		if _aiming_slot == slot:
			_aim_active = true
			_aim_len = _aim_range(slot)
			_aim_color = hero_color()
			_aim_charge = 1.0
			_aim_hold(slot, delta)
			if released:
				_aiming_slot = ""
				if cd[slot] <= 0.0 and _can_afford(slot):
					cd[slot] = cd_max[slot]
					_spend(slot)
					_cast_slot(slot)
		elif _aiming_slot == "" and held and cd[slot] <= 0.0 and _can_afford(slot):
			# _aim_begin voi keskeyttää tähtäyksen aloituksen (palauttaa false),
			# esim. Titaanin tartunta jos edessä ei ole kohdetta.
			if _aim_begin(slot):
				_aiming_slot = slot
		return

	# Välitön (puskuroitu) laukaisu.
	if _buf[slot] > 0.0 and cd[slot] <= 0.0 and _can_afford(slot):
		_buf[slot] = 0.0
		cd[slot] = cd_max[slot]
		_spend(slot)
		_cast_slot(slot)
	elif not is_bot and _buf[slot] > 0.0 and cd[slot] <= 0.0 and not _can_afford(slot):
		# Jäähdytys valmis mutta resurssi ei riitä -> kuuluva "ei onnistu" -vihje
		# (aiemmin painallus katosi täysin äänettä). Jäähdytys-odotus jätetään
		# puskurin hoidettavaksi, joten sitä ei kuittausäänellä hämmennetä.
		if _deny_cd <= 0.0:
			AudioMgr.play("ui_back", 0.05, -8.0)
			_deny_cd = 0.45


func _cast_slot(slot: String) -> void:
	_act(slot)
	_log_cast(slot)
	if slot == "a1":
		_ability1(aim)
	else:
		_ability2(aim)
	_act_end()


## Ylikirjoita palauttamaan kykypaikat ("a1"/"a2") jotka tähdätään pitämällä
## nappi pohjassa. Oletuksena tyhjä -> kaikki kyvyt laukeavat heti painettaessa.
func _aimed_slots() -> Array:
	return []


## Tähtäysviivan pituus kyvylle (ylikirjoitettavissa sankarikohtaisesti).
func _aim_range(_slot: String) -> float:
	return 420.0


## Kutsutaan kun tähdättävän kyvyn tähtäys alkaa. Palauta false keskeyttääksesi
## aloituksen (esim. Titaanin tartunta: ei kohdetta -> ei tähtäystä). Oletus true.
func _aim_begin(_slot: String) -> bool:
	return true


## Kutsutaan joka framessa tähtäyksen aikana (ennen vapautuksen tarkistusta).
## Ylikirjoita sankarissa (esim. Titaani pitää kohdetta edessään).
func _aim_hold(_slot: String, _delta: float) -> void:
	pass


# --- Resurssit: mana / energy / rage ---

## Ylikirjoita asettamaan resurssi: res_type, res_max, res, res_regen, res_cost
## ja mahdollisesti cd_max-säädöt. Oletuksena ei resurssia (pelkkä jäähdytys).
func _setup_resource() -> void:
	pass


func _tick_resource(delta: float) -> void:
	var boost := 3.0 if blue_buff > 0.0 else 1.0   # sininen buffi: nopea palautuminen
	if res_type == "mana" or res_type == "energy":
		# Ei palaudu kanavoinnin aikana (säde/kilpi kuluttaa sitä), jotta
		# resurssi todella loppuu eikä regen-tippa pidä kykyä hengissä.
		if _channel_slot == "":
			res = minf(res + res_regen * boost * delta, res_max)
	elif res_type == "rage":
		_rage_idle += delta
		if _rage_idle > 3.5:
			res = maxf(res - 6.0 * delta, 0.0)


func _reset_resource() -> void:
	_channel_slot = ""
	_channel_locked = ""
	_cast_context = ""
	_rage_idle = 0.0
	if res_type == "rage":
		res = 0.0
	elif res_type != "":
		res = res_max
	# Lipas täyteen ja lataus poikki (jos sankarilla on lipasjärjestelmä).
	if ammo_max > 0:
		ammo = ammo_max
		reloading = false


func _can_afford(slot: String) -> bool:
	if res_type == "":
		return true
	return res >= float(res_cost.get(slot, 0.0))


func _spend(slot: String) -> void:
	if res_type == "":
		return
	res = maxf(res - float(res_cost.get(slot, 0.0)), 0.0)
	if res_type == "rage":
		_rage_idle = 0.0


func gain_res(amount: float) -> void:
	if res_type == "":
		return
	if res_type == "rage" and blue_buff > 0.0:
		amount *= 1.5          # sininen buffi: raivo kertyy kovempaa
	res = clampf(res + amount, 0.0, res_max)
	if res_type == "rage":
		_rage_idle = 0.0


## Kenttäbuffin antaminen (FieldBuff kutsuu murskattaessa).
func apply_field_buff(t: String, dur: float) -> void:
	if t == "blue":
		blue_buff = maxf(blue_buff, dur)
		if arena != null:
			arena.popup(global_position + Vector2(0, -82), "SININEN BUFFI!", Color("6aa0ff"), 20)
	else:
		red_buff = maxf(red_buff, dur)
		if arena != null:
			arena.popup(global_position + Vector2(0, -82), "PUNAINEN BUFFI!", Color("ff7a6a"), 20)
	AudioMgr.play("blessing", 0.05)


## Void-pino (Riftin perushyökkäys) — enintään 5 kohdetta kohti.
func add_void_stack(source: Hero) -> void:
	void_stacks = mini(void_stacks + 1, 5)
	void_stack_timer = 6.0
	void_stacker = source


## Nollaa ja palauttaa pinojen määrän (Riftin räjäytys kuluttaa ne).
func consume_void_stacks() -> int:
	var n := void_stacks
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	return n


func apply_freeze(dur: float) -> void:
	var before := frozen
	frozen = maxf(frozen, dur)
	_record_cc("stun", frozen - before)   # jäädytys = kova CC, kirjataan stuniksi
	profile.stats.cc_suffered += frozen - before


## Kanavoitavat kykypaikat (pito ylläpitää). Oletuksena ei mitään.
func _channeled_slots() -> Array:
	return []


## Kutsutaan joka framessa kanavoinnin aikana. Ylikirjoita sankarissa.
func _channel_tick(_slot: String, _delta: float) -> void:
	pass


func _channel_end(_slot: String) -> void:
	pass


func _fire_ult() -> void:
	ult_charge = 0.0
	_ult_ready_announced = false
	_ult_holding = false
	AudioMgr.play("ult")
	arena.shake(0.35)
	_act("ult")
	_log_cast("ult")
	_ultimate(aim)
	_act_end()


## Ylikirjoita palauttamaan true jos ultimate pidetään pohjassa (esikatselu) ja
## laukaistaan vapautettaessa. Oletuksena välitön.
func _ult_is_held() -> bool:
	return false


## Pidä-ja-vapauta-ultin esikatselualueen säde (AimGuide piirtää renkaan).
func _ult_preview_radius() -> float:
	return 0.0


## Pidä-ja-vapauta-ultin tähtäysviivan pituus (0 = ei viivaa). Esim. Quillin
## tähdättävä supernuoli näyttää viivan ennen laukaisua.
func _ult_preview_line() -> float:
	return 0.0


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
	AudioMgr.play("dash", 0.08, 0.0, global_position)
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


# --- Kykytelemetria (kuka/mikä kykypaikka juuri toimii) ---
# Kohteen apply_stun/apply_slow/apply_root ja heal_hp lukevat arena._act_hero/
# _act_slot tietääkseen kenelle vaikutus kirjataan. Ammukset ja alueet asettavat
# kontekstin osuman/tickin ajaksi, lähikyvyt kyvyn suorituksen ajaksi.

func _act(slot: String) -> void:
	_cast_context = slot
	if arena != null:
		arena._act_hero = self
		arena._act_slot = slot


## Sulkee arenan CC-ikkunan. _cast_context jää voimaan (TARTTUVA), jotta await-
## kykyjen (esim. kanavoitavat ultit) viivästynyt vahinko kirjautuu yhä oikealle
## kykypaikalle awaitin jälkeenkin. Konteksti nollataan kuolemassa/erän alussa.
func _act_end() -> void:
	if arena != null:
		arena._act_hero = null
		arena._act_slot = ""


## Hakee (tai luo) kykypaikan telemetriatietueen tälle sankarille.
func _slot_rec(slot: String) -> Dictionary:
	if not profile.stats.slots.has(slot):
		profile.stats.slots[slot] = {"casts": 0, "hits": 0, "damage": 0.0,
			"heal": 0.0, "stun": 0.0, "slow": 0.0, "root": 0.0, "kb": 0,
			"shield": 0.0, "buff": 0.0}
	return profile.stats.slots[slot]


## Kirjaa yhden kykypaikan käyttökerran (kutsutaan dispatchissa kun kyky lähtee).
func _log_cast(slot: String) -> void:
	_slot_rec(slot)["casts"] += 1


## Kirjaa CC-vaikutus (stun/slow/root) sekunteina toimijalle. Kutsutaan kohteen
## apply_*-funktiosta: toimija ja slot luetaan arenan aktiivikontekstista.
func _record_cc(kind: String, duration: float) -> void:
	if duration <= 0.0 or arena == null:
		return
	var actor: Hero = arena._act_hero
	if actor == null or not is_instance_valid(actor):
		return
	var slot: String = arena._act_slot
	if slot == "":
		return
	actor._slot_rec(slot)[kind] += duration


## Kirjaa buffi-sekunnit (haste/nopeus/vahinkobuffi-ikkuna) toimijan kykypaikalle,
## kuten _record_cc. Vain LISÄTTY aika (uusi-vanha) -> ei paisu kun buffia uusitaan.
## Näyttää raportissa paljonko hyötyä buffikyvyt oikeasti tuottivat.
func _record_buff(duration: float) -> void:
	if duration <= 0.0 or arena == null:
		return
	var actor: Hero = arena._act_hero
	if actor == null or not is_instance_valid(actor):
		return
	var slot: String = arena._act_slot
	if slot == "":
		return
	actor._slot_rec(slot)["buff"] += duration


func deal_damage_to(target: Hero, amount: float, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if target == null or not is_instance_valid(target) or not target.alive:
		return 0.0
	if target.team == team:
		return 0.0
	if kb_dir == Vector2.ZERO:
		kb_dir = (target.global_position - global_position).normalized()
	# Virkistä CC-ikkuna tarttuvasta kontekstista jos se on tyhjä (await-kykyjen
	# viivästynyt vahinko + samassa iskussa tuleva CC osuu oikealle kyvylle).
	if arena != null and arena._act_hero == null and _cast_context != "":
		arena._act_hero = self
		arena._act_slot = _cast_context
	var dealt := target.take_damage(amount, self, kb, kb_dir)
	if dealt > 0.0:
		profile.stats.damage += dealt
		if target is Structure:
			profile.stats.structure_damage += dealt
		elif target is Critter:
			profile.stats.jungle_damage += dealt
		# Per-kykypaikka: vahinko + osumat (+ töytäisyt) telemetriaan.
		if _cast_context != "":
			var rec := _slot_rec(_cast_context)
			rec["hits"] += 1
			rec["damage"] += dealt
			if kb > 0.0:
				rec["kb"] += 1
		profile.add_score(dealt * 0.1)
		add_ult(dealt * 0.22)
		if res_type == "rage":
			gain_res(dealt * 0.4)
		elif res_type == "energy":
			gain_res(dealt * 0.2)   # energia kertyy myös hyökkäämisestä (assassinit)
	return dealt


func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if not alive or iframes > 0.0:
		return 0.0

	# Vaikeustason huijauskertoimet (vain epäreilu botti poikkeaa 1.0:sta):
	# hyökkääjän aiheuttama vahinko ja kohteen ottama vahinko.
	if source != null and is_instance_valid(source):
		amount *= source.dmg_out_mult
		if source.red_buff > 0.0:
			amount *= 1.25         # punainen buffi: hyökkääjä tekee enemmän vahinkoa
	amount *= dmg_in_mult

	# Merkitty kohde (Scoutin vaahtomerkki) ottaa lisävahinkoa kaikilta.
	if mark_timer > 0.0:
		amount *= mark_amp

	# Suuntatorjunta (kilpivalli): edestä tulevat osumat vaimenevat.
	if guard_timer > 0.0 and kb_dir != Vector2.ZERO:
		var from_dir := -kb_dir
		if absf(rad_to_deg(from_dir.angle_to(aim))) < guard_arc_deg:
			var absorbed := amount * guard_absorb
			amount -= absorbed
			profile.stats.prevented += absorbed
			profile.add_score(absorbed * 0.08)
			if guard_slot != "":
				_slot_rec(guard_slot)["shield"] += absorbed
			# Energiakilpi (Bastion): torjuminen kuluttaa energiaa vahingon mukaan.
			if res_type == "energy" and _channel_slot != "":
				res = maxf(res - absorbed * 0.6, 0.0)
			Fx.spark(arena, global_position + aim * radius, Palette.SHIELD)
			AudioMgr.play("shield", 0.08, 0.0, global_position)

	# Suojakilpi imee ensin.
	if shield_hp > 0.0:
		var soak := minf(shield_hp, amount)
		shield_hp -= soak
		amount -= soak
		if shield_source != null and is_instance_valid(shield_source):
			shield_source.profile.stats.prevented += soak
			shield_source.profile.add_score(soak * 0.08)
			if shield_slot != "":
				shield_source._slot_rec(shield_slot)["shield"] += soak
		arena.popup(global_position + Vector2(0, -46), str(int(soak)), Palette.SHIELD, 18)
		# Kilven imemä osuma kuuluu (aiemmin täysin vaimennettu osuma oli mykkä).
		if soak > 0.0:
			AudioMgr.play("shield", 0.1, -7.0, global_position)

	if amount <= 0.0:
		return 0.0

	hp -= amount
	since_damage = 0.0
	profile.stats.taken += amount
	# Otettu vahinko lähteen mukaan (telemetria: ottaako AI turhia torni-/mob-osumia).
	if source != null and is_instance_valid(source):
		if source is Structure:
			profile.stats.taken_tower += amount
		elif source is Critter:
			profile.stats.taken_neutral += amount
		elif source is Minion:
			profile.stats.taken_minion += amount
		else:
			profile.stats.taken_hero += amount
	if res_type == "rage":
		gain_res(amount * 0.6)
	if kb > 0.0 and kb_dir != Vector2.ZERO:
		velocity += kb_dir.normalized() * kb * (1.0 - kb_resist)

	visual.flash()
	arena.popup(global_position + Vector2(0, -46), str(int(amount)), Color.WHITE, 20)
	AudioMgr.play("hit", 0.08, -6.0, global_position)   # tiheä ääni -> hillitympi taso
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
		# Per-kykypaikka parannus toimijalle (arenan aktiivikonteksti).
		if arena != null and arena._act_hero == source and arena._act_slot != "":
			source._slot_rec(arena._act_slot)["heal"] += healed
	arena.popup(global_position + Vector2(0, -46), "+%d" % int(healed), Palette.HEAL, 18)
	Fx.heal_sparkle(arena, global_position)
	return healed


## record=false: kilpi on neutraali palkinto (pomobuffi) eikä kuulu millekään
## kyvylle -> shield_slot jää tyhjäksi eikä imetty vahinko sotke kyky­telemetriaa.
func add_shield(amount: float, duration: float, source: Hero, record := true) -> void:
	shield_hp = maxf(shield_hp, amount)
	shield_timer = duration
	shield_source = source
	# Kirjaa antajan aktiivinen kykypaikka -> imetty vahinko osataan kohdistaa
	# oikealle kyvylle (esim. Luman kupla vs. Maestron kilpi).
	shield_slot = source._cast_context if (record and source != null and is_instance_valid(source)) else ""
	AudioMgr.play("shield", 0.08, 0.0, global_position)
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
	# Kirjaa VAIN lisätty aika (uusi kesto - vanha), ei raakaa duration-arvoa:
	# alueet uusivat slow'n joka ruutu -> summa vastaa todellista slow-aikaa
	# eikä paisu (esim. 2 s alueessa seisominen ~= 2 s, ei 36 s).
	var before := slow_timer
	slow_timer = maxf(slow_timer, duration)
	_record_cc("slow", slow_timer - before)


## record=false: buffi tulee neutraalista lähteestä (pomobuffi, raivostuminen)
## eikä kuulu millekään kykypaikalle -> ei kirjata telemetriaan (muuten se
## kirjautuisi vahingossa sille sankarille joka sattuu olemaan kesken kykyään).
func apply_haste(factor: float, duration: float, record := true) -> void:
	var before := haste_timer
	haste_factor = maxf(haste_factor, factor)
	haste_timer = maxf(haste_timer, duration)
	if record:
		_record_buff(haste_timer - before)   # buffi-hyöty kirjataan antajan kyvylle


func apply_root(duration: float) -> void:
	var before := root_timer
	root_timer = maxf(root_timer, duration)
	arena.popup(global_position + Vector2(0, -60), "JUURTUNUT", Palette.BAD, 16)
	AudioMgr.play("root", 0.08, 0.0, global_position)
	_record_cc("root", root_timer - before)
	profile.stats.cc_suffered += root_timer - before


func apply_stun(duration: float) -> void:
	var before := stun_timer
	stun_timer = maxf(stun_timer, duration)
	_record_cc("stun", stun_timer - before)
	profile.stats.cc_suffered += stun_timer - before


func apply_mark(duration: float, amp := 1.25) -> void:
	mark_timer = maxf(mark_timer, duration)
	mark_amp = amp
	arena.popup(global_position + Vector2(0, -60), "MERKITTY", Palette.GOLD, 14)


func start_guard(duration: float, absorb := 0.7, arc_deg := 80.0, radius := 0.0) -> void:
	guard_timer = duration
	guard_absorb = absorb
	guard_arc_deg = arc_deg
	guard_radius = radius
	guard_slot = _cast_context   # telemetria: torjuttu vahinko kirjataan tälle kyvylle


## Merkitsee sankarin tartutuksi (Titaani): poistaa sankari-sankari-törmäyksen
## jottei kohde estä kantajaa. Virkistetään joka framessa kantajan _aim_holdista;
## ellei virkistetä, ote vapautuu itsestään (_physics_process).
func set_grabbed(holder) -> void:
	if grabbed_by == null:
		set_collision_layer_value(2, false)
		set_collision_mask_value(2, false)
	grabbed_by = holder
	_grab_hold_timer = 0.2


func release_grabbed() -> void:
	if grabbed_by == null:
		return
	grabbed_by = null
	_grab_hold_timer = 0.0
	if alive:
		set_collision_layer_value(2, true)
		set_collision_mask_value(2, true)


# --- Tyrmäys ja paluu ---

## Paluuaika. MOBASSA se kasvaa otteluajan myötä (kuten oikeassa MOBASSA):
## alkupelin kuolema on halpa, myöhemmin kallis -> voitettu taistelu muuttuu
## piiritykseksi ja ottelut ratkeavat nexuksen tuhoon aikakaton sijaan.
func _respawn_delay() -> float:
	if arena != null and arena.mode == "moba":
		return clampf(6.0 + arena.match_elapsed / 28.0, 6.0, 26.0)
	return RESPAWN_TIME


func _knockout(source: Hero) -> void:
	alive = false
	_aiming_slot = ""
	_aim_active = false
	_channel_slot = ""
	_channel_locked = ""
	_cast_context = ""
	_ult_holding = false
	_beam_active = false
	blue_buff = 0.0           # tyrmäys rikkoo kantajan buffit (vihollisen "murskaus")
	red_buff = 0.0
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	frozen = 0.0
	respawn_timer = _respawn_delay()
	profile.stats.deaths += 1
	profile.stats.time_dead += respawn_timer   # kuolleena vietetty aika (snowball-mittari)
	# Tappajan tyyppi (näkee kaatuvatko AI-unitit torneille/mobeille turhaan).
	if source != null and is_instance_valid(source):
		if source is Structure:
			profile.stats.deaths_tower += 1
		elif source is Critter:
			profile.stats.deaths_neutral += 1
	velocity = Vector2.ZERO
	shield_hp = 0.0
	guard_timer = 0.0
	guard_radius = 0.0
	grabbed_by = null
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
	AudioMgr.play("ko", 0.08, 0.0, global_position)
	arena.shake(0.3)
	knocked_out.emit(self, source)
	arena.on_hero_ko(self, source)


func _respawn() -> void:
	alive = true
	_reset_resource()
	hp = max_hp
	iframes = 2.0
	global_position = arena.map.spawn_point(team, profile.index)
	visible = true
	grabbed_by = null
	guard_radius = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	for slot in cd:
		cd[slot] = 0.0
	_dodge_was_cooling = false   # ei valheellista "väistö valmis" -piippausta respawnissa
	_heartbeat_t = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(profile.color(), 0.9), 60.0, 0.5)
	AudioMgr.play("respawn")
	arena.on_hero_respawn(self)


## Palauttaa sankarin täyteen kuntoon erän alussa.
func reset_for_round(keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	_aiming_slot = ""
	_aim_active = false
	_ult_holding = false
	_beam_active = false
	_reset_resource()
	blue_buff = 0.0
	red_buff = 0.0
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	frozen = 0.0
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
	guard_radius = 0.0
	grabbed_by = null
	ult_charge = ult_charge * keep_ult_fraction
	_ult_ready_announced = ult_charge >= 100.0
	_dodge_was_cooling = false
	_heartbeat_t = 0.0
	_deny_cd = 0.0
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

	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if hero == null or not is_instance_valid(hero) or not hero.alive:
			return

		# Ultin alue-esikatselu (pidä-ja-vapauta, esim. Prisma)
		if hero._ult_holding:
			var ur: float = hero._ult_preview_radius()
			if ur > 0.0:
				var uc: Color = hero.hero_color()
				var up := 0.5 + 0.5 * sin(_t * 4.0)
				draw_circle(Vector2.ZERO, ur, Palette.with_alpha(uc, 0.07))
				draw_arc(Vector2.ZERO, ur, 0.0, TAU, 52,
					Palette.with_alpha(Palette.glow(uc, 1.3), 0.5 + up * 0.3), 3.0)
				draw_arc(Vector2.ZERO, ur * 0.6, 0.0, TAU, 40, Palette.with_alpha(uc, 0.3), 2.0)

		# Kanavoitava säde (Prisma)
		if hero._beam_active and hero.aim.length() > 0.1:
			var bdir: Vector2 = hero.aim.normalized()
			var bcol: Color = Color("6affa0") if hero._beam_heal else Palette.glow(hero.hero_color(), 1.3)
			var bstart: Vector2 = bdir * (hero.radius + 4.0)
			var bend: Vector2 = bdir * float(hero._beam_len)
			var bpulse := 0.7 + 0.3 * sin(_t * 22.0)
			draw_line(bstart, bend, Palette.with_alpha(bcol, 0.22), 12.0)
			draw_line(bstart, bend, Palette.with_alpha(bcol, 0.55), 6.0 * bpulse)
			draw_line(bstart, bend, Palette.with_alpha(Color.WHITE, 0.7), 2.0)
			draw_circle(bend, 8.0 * bpulse, Palette.with_alpha(bcol, 0.6))

		# Tähtäysviiva (pito-tähtää-kyvyt ja latauskyvyt)
		if hero._aim_active and hero.aim.length() > 0.1:
			var dir: Vector2 = hero.aim.normalized()
			var length: float = hero._aim_len
			var charge: float = clampf(hero._aim_charge, 0.0, 1.0)
			var col: Color = hero._aim_color
			var start: Vector2 = dir * (float(hero.radius) + 6.0)
			var tip: Vector2 = dir * length
			var dist := start.distance_to(tip)
			var steps: int = int(dist / 16.0)
			for i in range(steps):
				var f := float(i) / maxf(float(steps), 1.0)
				var p: Vector2 = start.lerp(tip, f)
				var a: float = (0.14 + charge * 0.34) * (1.0 - f * 0.35)
				draw_circle(p, 2.0 + charge * 1.5, Palette.with_alpha(col, a))
			var ring_a: float = 0.35 + charge * 0.45
			draw_arc(tip, 12.0 + charge * 6.0, 0.0, TAU, 22, Palette.with_alpha(col, ring_a), 2.0)
			draw_circle(tip, 3.0 + charge * 2.0, Palette.with_alpha(col, ring_a))
