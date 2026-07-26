class_name Critter
extends Hero
## Viidakko-olento: neutraali taisteltava (joukkue 2). Koska se periytyy
## Herosta, kaikki olemassa oleva taistelu (osumat, ammukset, tähtäys,
## tyrmäys) toimii sellaisenaan — neutraali joukkue tekee siitä vihollisen
## molemmille tiimeille eikä kummankaan liittolaisen.
##
## Kolme tyyppiä:
##   DAMAGE_CAMP  — sivuleirit (Raivopeto): kaataja saa vahinkobuffin.
##   POINTS_CAMP  — pistereiri (Aarrepeto): kaataja saa pisteitä.
##   BOSS         — keskustan pomo (Baron): ilmestyy ajastimella, raivostuu
##                  alle 40 % HP:lla ja purkauttaa telegrafoituja happorenkaita;
##                  kaataja saa ison pitkän boostin.
##
## Aggro: olennot EIVÄT hyökkää ohikulkijoiden kimppuun. Ne aggroutuvat vain
## vahingosta, ja silloin koko sama leiri liittyy taisteluun (_provoke_camp).
## Hyökkäys on telegrafoitu: olento vetäytyy hetkeksi taakse (varoitus) ennen
## iskua, joten sen voi väistää. Elinkaari kulkee Heron respawn-koneiston kautta.

enum Kind { DAMAGE_CAMP, POINTS_CAMP, BOSS, DRAGON, RED_CAMP, BLUE_CAMP, SMALL_CAMP }

# Leiriapu: saman leirin olennot (kodit tämän säteellä toisistaan) aggroutuvat
# yhdessä kun yhtä vahingoitetaan.
const CAMP_ASSIST_RADIUS := 420.0

# Baronin happopurkaus: 3 telegrafoitua maarengasta hyökkääjien alle.
const ACID_INTERVAL := 7.5
const ACID_WARNING := 1.0
const ACID_RADIUS := 110.0
const ACID_DMG := 46.0
const ACID_SLOW := 0.55
const ACID_SLOW_TIME := 1.1

# Dragonin tulihenkäys: levenevä kartiotelegrafi + liekkikartio ja palotikki.
const BREATH_INTERVAL := 7.0
const BREATH_WARNING := 0.8
const BREATH_RANGE := 430.0
const BREATH_HALF_DEG := 34.0
const BREATH_DMG := 36.0
const BREATH_BURN_TICK := 4.0
const BREATH_BURN_TICKS := 3
const BREATH_TICK_GAP := 0.66    # 3 tikkiä ~2 s aikana

var kind := Kind.DAMAGE_CAMP
var home := Vector2.ZERO
var respawn_delay := 22.0
var attack_reach := 78.0
var attack_dmg := 16.0
var attack_kb := 240.0
var gold_value := 65
var xp_value := 110
var _color := Color("d98a3a")
var _base_color := Color("d98a3a")

# Käyttäytymistila (luetaan myös ulkoasussa telegrafeja varten)
var _windup_time := 0.28
var _wind := 0.0                   # iskun latautuminen jäljellä (0 = ei kesken)
var _attack_tell := 0.0            # 0..1 telegrafi (0 = ei, 1 = juuri ennen iskua)
var _attack_dir := Vector2.RIGHT
var _enraged := false
var _special_cd := ACID_INTERVAL   # pomon erikoiskyvyn jäähdytys (Baron/Dragon)
var _acid_tell := 0.0              # happopurkauksen varoitusaika jäljellä
var _acid_spots: Array = []        # happorenkaiden paikat (Vector2)
var _breath_tell := 0.0            # tulihenkäyksen varoitusaika jäljellä
var _breath_dir := Vector2.RIGHT   # lukittu henkäyssuunta
var _burns: Array = []             # palotikit: [{hero, ticks, t}]
var clear_started_at := -1.0
var clear_started_team := -1
var clear_active_time := 0.0
var clear_last_damage_at := -1.0


## Neutraali setup ilman HeroDefiä (olennot eivät ole sankarilistassa).
func setup_critter(p_arena, p_kind: int, p_home: Vector2) -> void:
	arena = p_arena
	kind = p_kind
	home = p_home
	team = 2
	hero_id = "critter"
	is_unit = true

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = 2
	profile.hero_id = "critter"
	profile.index = 0
	profile.display_name = _kind_name()

	var brain := NeutralBrain.new()
	brain.home = home
	brain._retarget_timer = fposmod(absf(home.x * 0.013 + home.y * 0.017),
		NeutralBrain.RETARGET_INTERVAL)
	controller = brain

	# Olennoilla ei ole ultia -> estä latautuminen (muuten "ULTI VALMIS!" -popup).
	ult_gain_mult = 0.0

	match kind:
		Kind.DAMAGE_CAMP:
			gold_value = 70
			xp_value = 120
			max_hp = 240.0
			radius = 34.0
			base_speed = 78.0
			attack_reach = 82.0
			attack_dmg = 15.0
			attack_kb = 250.0
			respawn_delay = 22.0
			kb_resist = 0.6
			_color = Color("d9662a")   # puna-oranssi: erottuu joukkue-oranssista
			_windup_time = 0.24
			brain.attack_range = 74.0
			brain.leash = 360.0
			cd_max.basic = 0.95
		Kind.POINTS_CAMP:
			gold_value = 95
			xp_value = 145
			max_hp = 300.0
			radius = 36.0
			base_speed = 60.0
			attack_reach = 80.0
			attack_dmg = 12.0
			attack_kb = 210.0
			respawn_delay = 26.0
			kb_resist = 0.68
			_color = Color("e0bf3a")
			_windup_time = 0.30
			brain.attack_range = 74.0
			brain.leash = 320.0
			cd_max.basic = 1.15
		Kind.BOSS:
			# Baron lyö nyt läheltä: raskas telegrafoitu viilto (~285 px) korvaa
			# vanhan oudon 560 px:n poken. DPS pidetty ennallaan: 52 / (1.7 + 0.5)
			# = 23.6/s (oli 38 / (1.15 + 0.48) = 23.3/s).
			gold_value = 400
			xp_value = 600
			max_hp = 2200.0
			radius = 58.0
			base_speed = 102.0
			attack_reach = 285.0
			attack_dmg = 52.0
			attack_kb = 520.0
			respawn_delay = 240.0
			kb_resist = 0.92
			_color = Color("b64ad6")
			_windup_time = 0.5
			brain.attack_range = 240.0
			brain.leash = 780.0
			cd_max.basic = 1.7
		Kind.DRAGON:
			# Dragonin kynäisy ~260 px lyhyellä telegrafilla (oli 520 px poke).
			# DPS ennallaan: 30 / (1.35 + 0.34) = 17.8/s (oli 28 / 1.62 = 17.3/s).
			gold_value = 280
			xp_value = 420
			max_hp = 1450.0
			radius = 54.0
			base_speed = 96.0
			attack_reach = 260.0
			attack_dmg = 30.0
			attack_kb = 420.0
			respawn_delay = 150.0
			kb_resist = 0.88
			_color = Color("37cdbb")
			_windup_time = 0.34
			brain.attack_range = 225.0
			brain.leash = 700.0
			cd_max.basic = 1.35
		Kind.RED_CAMP:
			# Palkkiot nostettu (auditointi 2026-07): viidakon vakaa tulo oli vain
			# 42 % linjafarmista kullassa ja 33 % XP:ssa. Ks. BLUE_CAMP/SMALL_CAMP.
			gold_value = 135
			xp_value = 235
			max_hp = 410.0
			radius = 37.0
			base_speed = 85.0
			attack_reach = 360.0
			attack_dmg = 18.0
			attack_kb = 270.0
			respawn_delay = 120.0
			kb_resist = 0.88
			_color = Color("df4938")
			_windup_time = 0.27
			brain.attack_range = 320.0
			brain.leash = 520.0
			cd_max.basic = 1.18
		Kind.BLUE_CAMP:
			gold_value = 135
			xp_value = 235
			max_hp = 400.0
			radius = 37.0
			base_speed = 75.0
			attack_reach = 440.0
			attack_dmg = 15.0
			attack_kb = 240.0
			respawn_delay = 120.0
			kb_resist = 0.88
			_color = Color("4e8ee8")
			_windup_time = 0.31
			brain.attack_range = 400.0
			brain.leash = 540.0
			cd_max.basic = 1.25
		Kind.SMALL_CAMP:
			# Junglerin leipaleiri: kolme per puoli. Arvo ja respawn viritetty
			# niin etta taysi kierros kilpailee linjafarmin kanssa (ks. RED_CAMP).
			gold_value = 80
			xp_value = 150
			max_hp = 235.0
			radius = 30.0
			base_speed = 82.0
			attack_reach = 76.0
			attack_dmg = 12.0
			attack_kb = 185.0
			respawn_delay = 78.0
			kb_resist = 0.78
			_color = Color("79b45e")
			_windup_time = 0.25
			brain.attack_range = 70.0
			brain.leash = 300.0
			cd_max.basic = 1.12
	hp = max_hp
	_special_cd = ACID_INTERVAL if kind == Kind.BOSS else BREATH_INTERVAL
	_base_color = _color

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	var vis := CritterVisual.new()
	vis.hero = self
	visual = vis
	add_child(vis)

	global_position = home


func _kind_name() -> String:
	match kind:
		Kind.DAMAGE_CAMP:
			return "Raivopeto"
		Kind.POINTS_CAMP:
			return "Aarrepeto"
		Kind.BOSS:
			return "Baron"
		Kind.DRAGON:
			return "Dragon"
		Kind.RED_CAMP:
			return "Red Guardian"
		Kind.BLUE_CAMP:
			return "Blue Guardian"
		Kind.SMALL_CAMP:
			return "Wild Camp"
	return "Olento"


func telemetry_kind() -> String:
	match kind:
		Kind.BOSS: return "baron"
		Kind.DRAGON: return "dragon"
		Kind.RED_CAMP: return "red"
		Kind.BLUE_CAMP: return "blue"
		Kind.SMALL_CAMP: return "small"
		Kind.DAMAGE_CAMP: return "damage"
		Kind.POINTS_CAMP: return "points"
	return "unknown"


func is_major_objective() -> bool:
	return kind == Kind.BOSS or kind == Kind.DRAGON


func hero_color() -> Color:
	return _color


## Major objectives resist repeated crowd control so a solo jungler cannot keep
## Baron or Dragon permanently stunned. Ordinary camps retain full CC response.
func apply_stun(duration: float) -> void:
	if is_major_objective():
		duration *= 0.25
	super.apply_stun(duration)


## Sama sääntö juurrutukselle kuin tainnutukselle: Torqin Napalukko ja
## Napakenttä eivät saa pitää Baronia tai Lohikäärmettä pysyvästi kiinni.
func apply_root(duration: float) -> void:
	if is_major_objective():
		duration *= 0.25
	super.apply_root(duration)


func apply_slow(factor: float, duration: float) -> void:
	if is_major_objective():
		factor = maxf(factor, 0.78)
		duration *= 0.5
	super.apply_slow(factor, duration)


## Telegrafoitu isku: kun ohjain haluaa lyödä, olento vetäytyy hetkeksi taakse
## (varoitus) ja iskee vasta sitten lukittuun suuntaan -> pelaaja voi väistää.
func _attack_control(_held: bool, _jp: bool, _jr: bool, dir: Vector2, delta: float) -> void:
	if _wind > 0.0:
		_wind -= delta
		_attack_tell = clampf(1.0 - _wind / maxf(_windup_time, 0.01), 0.0, 1.0)
		if _wind <= 0.0:
			_attack_tell = 0.0
			cd.basic = cd_max.basic * (0.62 if _enraged else 1.0)
			_basic(_attack_dir)
		return
	if _held and cd.basic <= 0.0:
		_attack_dir = dir if dir.length() > 0.1 else aim
		_wind = _windup_time * (0.72 if _enraged else 1.0)
		_attack_tell = 0.0


## Perushyökkäys: lähialueen isku edessä. Osuu vain pelaajiin (joukkue 0/1).
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	match kind:
		Kind.RED_CAMP:
			AudioMgr.play("red_guardian_attack", 0.055, -7.0, global_position)
			Fx.slash(arena, global_position, dir, attack_reach + 12.0, 74.0,
				Palette.glow(Color("ff5a36"), 1.45))
			Fx.ring(arena, global_position + dir * attack_reach * 0.55,
				Palette.with_alpha(Color("ff8a3a"), 0.7), 42.0, 0.22, 4.0)
		Kind.BLUE_CAMP:
			AudioMgr.play("blue_guardian_attack", 0.05, -7.0, global_position)
			Fx.bolt(arena, global_position, global_position + dir * (attack_reach + 18.0),
				Palette.glow(Color("72b8ff"), 1.65))
			Fx.ring(arena, global_position + dir * attack_reach * 0.72,
				Palette.glow(Color("72b8ff"), 1.35), 34.0, 0.25, 3.0)
		Kind.SMALL_CAMP:
			AudioMgr.play("jungle_small_attack", 0.08, -11.0, global_position)
			Fx.slash(arena, global_position, dir.rotated(-0.18), attack_reach, 48.0, Color("9ce06c"))
			Fx.slash(arena, global_position, dir.rotated(0.18), attack_reach, 48.0, Color("d7f59a"))
		Kind.DRAGON:
			AudioMgr.play("dragon_attack", 0.04, -1.0, global_position)
			Fx.slash(arena, global_position, dir, attack_reach + 24.0, 92.0,
				Palette.glow(Color("49e7d2"), 1.55))
			Fx.vortex(arena, global_position + dir * attack_reach * 0.55,
				Palette.with_alpha(Color("37cdbb"), 0.65), 52.0, 0.28)
		Kind.BOSS:
			AudioMgr.play("baron_attack", 0.035, 0.0, global_position)
			Fx.slash(arena, global_position, dir, attack_reach + 20.0, 86.0,
				Palette.glow(Color("d26aff"), 1.55))
			Fx.vortex(arena, global_position + dir * attack_reach * 0.45,
				Palette.with_alpha(Color("8d35b8"), 0.7), 48.0, 0.3)
		_:
			AudioMgr.play("jungle_small_attack", 0.10, -8.0, global_position)
			Fx.slash(arena, global_position, dir, attack_reach, 72.0, _color)
	# Buff-vartijat rankaisevat kaukokitausta ammuksella. Baron ja Dragon lyövät
	# nyt raskaan lähiviillon kartioon — telegrafin voi lukea ja väistää.
	if kind in [Kind.RED_CAMP, Kind.BLUE_CAMP]:
		_launch_ranged_attack(dir)
		return
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		var to_e: Vector2 = enemy.global_position - global_position
		if to_e.length() > attack_reach + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_e))) > 72.0:
			continue
		deal_damage_to(enemy, attack_dmg, attack_kb, to_e.normalized())
		if kind == Kind.BOSS:
			Fx.burst(arena, enemy.global_position, Color("d26aff"), 8, 170.0, 0.26, 4.0)
		elif kind == Kind.DRAGON:
			Fx.spark(arena, enemy.global_position, Color("49e7d2"))
	if is_major_objective():
		arena.shake(0.12)
		Fx.spark(arena, global_position + dir * attack_reach * 0.7, Palette.glow(_color, 1.4))


func _launch_ranged_attack(dir: Vector2) -> void:
	var target: Hero = null
	var best_d := attack_reach + 1.0
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		var off: Vector2 = enemy.global_position - global_position
		var dist := off.length()
		if dist > attack_reach + enemy.radius or dist >= best_d:
			continue
		if dist > 1.0 and absf(rad_to_deg(dir.angle_to(off.normalized()))) > 78.0:
			continue
		target = enemy
		best_d = dist
	if target == null:
		return
	var lead_time := 0.12
	var aim_point: Vector2 = target.global_position + target.velocity * lead_time
	var shot_dir := (aim_point - global_position).normalized()
	var shot_speed := 570.0
	var shot_radius := 11.0
	var homing := 2.5
	var visual_id := "critter_orb"
	match kind:
		Kind.RED_CAMP:
			shot_speed = 650.0
			visual_id = "critter_fire"
		Kind.BLUE_CAMP:
			shot_speed = 540.0
			homing = 3.8
			visual_id = "critter_frost"
	Projectile.launch(self, global_position + shot_dir * (radius + 8.0), shot_dir, {
		"speed": shot_speed,
		"dmg": attack_dmg,
		"radius": shot_radius,
		"life": 1.15,
		"kb": attack_kb * 0.45,
		"color": _color,
		"homing_target": target,
		"homing_rate": homing,
		"visual": visual_id,
	})
	Fx.bolt(arena, global_position, global_position + shot_dir * 74.0,
		Palette.glow(_color, 1.5))


## Pomojen erikoiskäyttäytyminen: raivostuminen + telegrafoitu erikoiskyky
## (Baron: happopurkaus, Dragon: tulihenkäys). Erikoiskyvyt laukeavat VAIN
## aggroutuneena — rauhaan jätetty pomo ei tee mitään.
func _passive_update(delta: float) -> void:
	if not is_major_objective():
		return
	_tick_burns(delta)
	if not _enraged and hp <= max_hp * 0.4:
		_enrage()
	# Käynnissä oleva telegrafi viedään aina loppuun (väistettävä lupaus pitää).
	if _acid_tell > 0.0:
		_acid_tell -= delta
		if _acid_tell <= 0.0:
			_erupt_acid()
		return
	if _breath_tell > 0.0:
		_breath_tell -= delta
		if _breath_tell <= 0.0:
			_breathe_fire()
		return
	if not _in_combat():
		return
	_special_cd -= delta
	if _special_cd > 0.0:
		return
	_special_cd = (ACID_INTERVAL if kind == Kind.BOSS else BREATH_INTERVAL) \
		* (0.62 if _enraged else 1.0)
	if kind == Kind.BOSS:
		_begin_acid()
	else:
		_begin_breath()


## Onko pomo aggroutunut (ohjaimella on elävä kohde)?
func _in_combat() -> bool:
	var brain := controller as NeutralBrain
	return brain != null and brain._target != null \
		and is_instance_valid(brain._target) and brain._target.alive


## Happopurkauksen telegrafi: kolme varoitusrengasta nykyisten hyökkääjien
## alle/lähelle (pieni liike-ennakko, jotta rengas laskeutuu kulkusuuntaan).
func _begin_acid() -> void:
	_acid_spots.clear()
	var attackers: Array = []
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		if enemy.global_position.distance_to(global_position) <= 620.0:
			attackers.append(enemy)
	if attackers.is_empty():
		return
	attackers.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(global_position) \
			< b.global_position.distance_squared_to(global_position))
	for i in range(mini(3, attackers.size())):
		var tgt: Hero = attackers[i]
		_acid_spots.append(tgt.global_position + tgt.velocity * 0.35)
	# Loput renkaat ripotellaan ensimmäisen ympärille (aina kolme purkausta).
	var k := 0
	while _acid_spots.size() < 3:
		k += 1
		var base_p: Vector2 = _acid_spots[0]
		var a: float = float(k) * 2.4 + global_position.x * 0.01
		_acid_spots.append(base_p + Vector2(cos(a), sin(a)) * 150.0)
	_acid_tell = ACID_WARNING
	AudioMgr.play("baron_slam_warning", 0.025, -1.0, global_position)
	arena.popup(global_position + Vector2(0, -radius - 34.0),
		"HAPPOPURKAUS!", Palette.glow(Color("b6ff4a"), 1.4), 18)


## Happorenkaat purkautuvat: vahinko + lyhyt hidastus renkaissa seisoville.
## Yksi osuma per sankari vaikka renkaat limittyisivät.
func _erupt_acid() -> void:
	if _acid_spots.is_empty():
		return
	arena.shake(0.4)
	AudioMgr.play("baron_slam", 0.025, 0.0, global_position)
	var hit: Dictionary = {}
	for spot_v in _acid_spots:
		var spot: Vector2 = spot_v
		Fx.ring(arena, spot, Palette.glow(Color("b6ff4a"), 1.5), ACID_RADIUS, 0.45, 9.0)
		Fx.burst(arena, spot, Color("9be03a"), 10, 190.0, 0.3, 4.0)
		for enemy in arena.alive_enemies(team):
			if enemy.is_unit or hit.has(enemy):
				continue
			var to_e: Vector2 = enemy.global_position - spot
			if to_e.length() > ACID_RADIUS + enemy.radius:
				continue
			hit[enemy] = true
			deal_damage_to(enemy, ACID_DMG, 240.0, to_e.normalized())
			enemy.apply_slow(ACID_SLOW, ACID_SLOW_TIME)
	_acid_spots.clear()


## Tulihenkäyksen telegrafi: kartiosuunta lukitaan nykyistä kohdetta kohti
## (0.8 s varoitus -> sivuaskel riittää väistöön).
func _begin_breath() -> void:
	var brain := controller as NeutralBrain
	var dir: Vector2 = aim
	if brain != null and brain._target != null and is_instance_valid(brain._target):
		var to_t: Vector2 = brain._target.global_position - global_position
		if to_t.length() > 1.0:
			dir = to_t.normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	_breath_dir = dir
	_breath_tell = BREATH_WARNING
	AudioMgr.play("dragon_slam_warning", 0.025, -1.0, global_position)
	arena.popup(global_position + Vector2(0, -radius - 34.0),
		"TULIHENKÄYS!", Palette.glow(Color("ff8a3a"), 1.4), 18)


## Liekkikartio: vahinko + pieni palotikki (~2 s) kartioon jääneille.
func _breathe_fire() -> void:
	arena.shake(0.35)
	AudioMgr.play("dragon_slam", 0.025, 0.0, global_position)
	var dir: Vector2 = _breath_dir
	Fx.slash(arena, global_position, dir, BREATH_RANGE * 0.7, 150.0,
		Palette.glow(Color("ff9a4a"), 1.5))
	Fx.burst(arena, global_position + dir * BREATH_RANGE * 0.45,
		Color("ffb35a"), 14, 260.0, 0.35, 5.0)
	for enemy in arena.alive_enemies(team):
		if enemy.is_unit:
			continue
		var to_e: Vector2 = enemy.global_position - global_position
		var d: float = to_e.length()
		if d > BREATH_RANGE + enemy.radius:
			continue
		if d > 1.0 and absf(rad_to_deg(dir.angle_to(to_e.normalized()))) > BREATH_HALF_DEG:
			continue
		deal_damage_to(enemy, BREATH_DMG, 300.0, to_e.normalized())
		_burns.append({"hero": enemy, "ticks": BREATH_BURN_TICKS, "t": BREATH_TICK_GAP})


## Palotikit henkäysosuman jälkeen: pieni jälkivahinko, lähde pysyy tänä
## olentona (elämänimu/telemetria toimivat normaalisti).
func _tick_burns(delta: float) -> void:
	if _burns.is_empty():
		return
	var alive_burns: Array = []
	for b in _burns:
		var victim: Hero = b.hero
		if victim == null or not is_instance_valid(victim) or not victim.alive:
			continue
		var left: float = float(b.t) - delta
		var ticks: int = int(b.ticks)
		if left <= 0.0:
			deal_damage_to(victim, BREATH_BURN_TICK, 0.0, Vector2.ZERO)
			Fx.spark(arena, victim.global_position, Color("ff9a4a"))
			ticks -= 1
			left += BREATH_TICK_GAP
		if ticks > 0:
			alive_burns.append({"hero": victim, "ticks": ticks, "t": left})
	_burns = alive_burns


## Raivostuminen alle 40 % HP:lla. Nopeampi ja punertava; iskunopeus ja
## telegrafi hoidetaan _enraged-lipun kautta (ei pysyvää mutaatiota, jotta
## respawn palautuu puhtaasti).
func _enrage() -> void:
	_enraged = true
	apply_haste(1.4, 99999.0, false)   # oma raivo, ei kirjata kykytelemetriaan
	_color = _base_color.lerp(Color("ff425a"), 0.45)
	arena.popup(global_position + Vector2(0, -radius - 44.0),
		"RAIVOSTUU!", Palette.glow(Color("ff425a"), 1.6), 22)
	arena.shake(0.3)
	AudioMgr.play("baron_enrage" if kind == Kind.BOSS else "dragon_enrage",
		0.025, 0.0, global_position)
	Fx.ring(arena, global_position, Palette.glow(Color("ff425a"), 1.5), radius + 50.0, 0.6, 8.0)


## Tyrmäys: ei sankarin KO-polkua. Ilmoittaa areenalle palkintoa varten ja
## käynnistää respawn-ajastimen (Heron respawn-koneisto herättää olennon).
func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if alive and amount > 0.0 and source != null and is_instance_valid(source) \
			and not source.is_unit and source.team <= 1:
		var now: float = arena.match_elapsed if arena != null else 0.0
		if clear_started_at < 0.0:
			clear_started_at = now
			clear_started_team = source.team
		elif clear_last_damage_at >= 0.0:
			# Enintään 3 s osumavälistä lasketaan aktiiviseksi taisteluksi. Tätä
			# pidempi tauko jää kokonaisikkunaan ja näkyy kesken jätettynä leirinä.
			clear_active_time += minf(now - clear_last_damage_at, 3.0)
		clear_last_damage_at = now
		# Aggro vain vahingosta: herätä oma ohjain JA koko sama leiri.
		_provoke_camp(source, now)
	return super.take_damage(amount, source, kb, kb_dir)


## Leiriapu: vahingoitettu olento provosoi itsensä ja kaikki leiritoverit
## (olennot joiden kotipesä on CAMP_ASSIST_RADIUS-säteellä omasta kodista)
## samaa hyökkääjää vastaan. Baron ja Dragon ovat yksin leirissään.
func _provoke_camp(attacker: Hero, now: float) -> void:
	var own := controller as NeutralBrain
	if own != null:
		own.provoke(attacker, now)
	if arena == null:
		return
	for c in arena.critters:
		var mate := c as Critter
		if mate == null or mate == self or not mate.alive:
			continue
		if mate.home.distance_squared_to(home) > CAMP_ASSIST_RADIUS * CAMP_ASSIST_RADIUS:
			continue
		var brain := mate.controller as NeutralBrain
		if brain != null:
			brain.provoke(attacker, now)


func clear_duration() -> float:
	if clear_started_at < 0.0 or arena == null:
		return 0.0
	return maxf(arena.match_elapsed - clear_started_at, 0.0)


func active_clear_duration() -> float:
	return maxf(clear_active_time, 0.0)


func on_leash_reset() -> void:
	hp = max_hp
	_recent_damagers.clear()
	clear_started_at = -1.0
	clear_started_team = -1
	clear_active_time = 0.0
	clear_last_damage_at = -1.0


func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	guard_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	_wind = 0.0
	_attack_tell = 0.0
	_acid_tell = 0.0
	_acid_spots.clear()
	_breath_tell = 0.0
	_burns.clear()
	respawn_timer = respawn_delay
	_recent_damagers.clear()
	Fx.knockout_burst(arena, global_position, _color)
	Fx.ring(arena, global_position, Palette.glow(_color, 1.5), radius + 40.0, 0.6, 7.0)
	match kind:
		Kind.BOSS:
			AudioMgr.play("baron_collapse", 0.025, 0.0, global_position)
		Kind.DRAGON:
			AudioMgr.play("dragon_collapse", 0.03, -1.0, global_position)
		Kind.RED_CAMP:
			AudioMgr.play("red_guardian_down", 0.05, -5.0, global_position)
		Kind.BLUE_CAMP:
			AudioMgr.play("blue_guardian_down", 0.05, -5.0, global_position)
		_:
			AudioMgr.play("jungle_small_down", 0.08, -8.0, global_position)
	arena.shake(0.4 if is_major_objective() else 0.2)
	if arena.has_method("on_critter_ko"):
		arena.on_critter_ko(self, source)


## Palautus kotileirille (Heron respawn-koneisto kutsuu respawn_timerin nollaan).
func _respawn() -> void:
	alive = true
	clear_started_at = -1.0
	clear_started_team = -1
	clear_active_time = 0.0
	clear_last_damage_at = -1.0
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	visible = true
	iframes = 0.5
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	haste_factor = 1.0
	haste_timer = 0.0
	_enraged = false
	_color = _base_color
	_wind = 0.0
	_attack_tell = 0.0
	_acid_tell = 0.0
	_acid_spots.clear()
	_breath_tell = 0.0
	_burns.clear()
	_special_cd = ACID_INTERVAL if kind == Kind.BOSS else BREATH_INTERVAL
	var brain := controller as NeutralBrain
	if brain != null:
		brain._returning = false
		brain._target = null
		brain._provoked = null
	for slot in cd:
		cd[slot] = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(_color, 0.9), radius + 30.0, 0.5)
	if arena.has_method("on_critter_respawn"):
		arena.on_critter_respawn(self)


## Erän alku: palauta olento kotileirille (ei HeroDefiä / spawn_pointia).
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	alive = true
	clear_started_at = -1.0
	clear_started_team = -1
	clear_active_time = 0.0
	clear_last_damage_at = -1.0
	visible = true
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	respawn_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	haste_factor = 1.0
	haste_timer = 0.0
	guard_timer = 0.0
	_enraged = false
	_color = _base_color
	_wind = 0.0
	_attack_tell = 0.0
	_acid_tell = 0.0
	_acid_spots.clear()
	_breath_tell = 0.0
	_burns.clear()
	_special_cd = ACID_INTERVAL if kind == Kind.BOSS else BREATH_INTERVAL
	var brain := controller as NeutralBrain
	if brain != null:
		brain._returning = false
		brain._target = null
		brain._provoked = null
	for slot in cd:
		cd[slot] = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	_recent_damagers.clear()


## Viidakko-olennon ulkoasu. Periytyy HeroVisualista (saa flash/squash/animaatiot)
## mutta piirtää oman olentohahmonsa telegrafeineen — ei HeroDef-riippuvuutta.
class CritterVisual:
	extends HeroVisual

	func _draw() -> void:
		if hero == null or not hero.alive:
			return
		var cr := hero as Critter
		if cr == null:
			return
		var r: float = cr.radius
		var col: Color = cr._color
		var dark: Color = Palette.darker(col, 0.5)
		var moving: float = clampf(hero.velocity.length() / 220.0, 0.0, 1.0)
		var boss: bool = cr.is_major_objective()
		var breathe: float = sin(_time * (4.5 if boss else 6.5)) * (2.0 + r * 0.03)
		var tell: float = cr._attack_tell

		# Pomojen erikoiskykyjen telegrafit maassa (piirretään ensin, hahmon alle).
		if boss:
			if cr._acid_tell > 0.0:
				_acid_telegraph(cr)
			if cr._breath_tell > 0.0:
				_breath_telegraph(cr)

		_shadow(r)
		_ground_ring(cr, r)
		if tell > 0.0:
			_attack_telegraph(cr, r, tell)

		# Runko: telegrafissa vetäytyy taakse (-aim), iskun jälkeen nykii eteen.
		var recoil: float = _attack_anim - tell * 1.5
		var lean: Vector2 = hero.aim * (r * 0.16) * clampf(recoil, -1.0, 1.0)
		draw_set_transform(Vector2(0, -breathe) + lean, 0.0, _draw_scale)
		match cr.kind:
			Critter.Kind.DAMAGE_CAMP:
				_paint_beast(cr, r, col, dark, tell, moving)
			Critter.Kind.POINTS_CAMP:
				_paint_treasure(cr, r, col, dark)
			Critter.Kind.BOSS:
				_paint_boss(cr, r, col, dark, tell)
			Critter.Kind.DRAGON:
				_paint_dragon(cr, r, col, dark, tell, moving)
			Critter.Kind.RED_CAMP:
				_paint_red_guardian(cr, r, col, dark, tell, moving)
			Critter.Kind.BLUE_CAMP:
				_paint_blue_guardian(cr, r, col, dark, tell)
			Critter.Kind.SMALL_CAMP:
				_paint_mossling(cr, r, col, dark, tell, moving)
		if _flash > 0.0:
			draw_circle(Vector2.ZERO, r, Color(1, 1, 1, _flash * 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		_hp_bar(cr, r)

	# --- Jaetut osat ---

	func _shadow(r: float) -> void:
		draw_set_transform(Vector2(0, r * 0.72), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, r + 4.0, Color(0.02, 0.03, 0.06, 0.42))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _ground_ring(cr: Critter, r: float) -> void:
		var col: Color = Color("ff425a") if cr._enraged else cr._color
		var a: float = 0.28 if cr.is_major_objective() else 0.16
		draw_arc(Vector2(0, r * 0.55), r + 12.0, 0.0, TAU, 40,
			Palette.with_alpha(col, a), 3.0)

	func _attack_telegraph(cr: Critter, r: float, tell: float) -> void:
		var dir: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var center_angle := dir.angle()
		var warn: Color
		var half_arc := deg_to_rad(72.0)
		match cr.kind:
			Critter.Kind.RED_CAMP:
				warn = Color("ff6038")
				half_arc = deg_to_rad(76.0)
			Critter.Kind.BLUE_CAMP:
				warn = Color("68b8ff")
				half_arc = deg_to_rad(58.0)
			Critter.Kind.SMALL_CAMP:
				warn = Color("a8e56f")
				half_arc = deg_to_rad(52.0)
			Critter.Kind.DRAGON:
				# Kaari vastaa nyt oikeaa osumakartiota (±72°) lyhyellä kantamalla.
				warn = Color("49e7d2")
				half_arc = deg_to_rad(74.0)
			Critter.Kind.BOSS:
				warn = Color("d35cff")
				half_arc = deg_to_rad(76.0)
			_:
				warn = cr._color
		var reach: float = cr.attack_reach + 14.0
		# Täyttyvä kaari kertoo sekä suunnan että tarkan iskuhetken.
		draw_arc(Vector2.ZERO, reach, center_angle - half_arc, center_angle + half_arc,
			28, Palette.with_alpha(Palette.glow(warn, 1.45), 0.35 + 0.55 * tell), 3.0)
		draw_arc(Vector2.ZERO, reach * tell, center_angle - half_arc,
			center_angle + half_arc, 28, Palette.with_alpha(Color.WHITE, 0.62), 2.0)
		if cr.kind == Critter.Kind.BLUE_CAMP:
			var rune_pos := dir * reach * 0.72
			draw_circle(rune_pos, 20.0, Palette.with_alpha(warn, 0.10 + 0.15 * tell))
			draw_arc(rune_pos, 20.0, -_time * 4.0, -_time * 4.0 + TAU * tell,
				20, Palette.glow(warn, 1.5), 2.5)
		elif cr.kind == Critter.Kind.RED_CAMP:
			for claw_s in [-1.0, 0.0, 1.0]:
				var claw_v: float = claw_s
				var a: float = center_angle + claw_v * half_arc * 0.55
				draw_line(dir * r * 0.45, Vector2.RIGHT.rotated(a) * reach,
					Palette.with_alpha(warn, 0.22 + 0.35 * tell), 2.0)

	func _critter_eyes(center: Vector2, spread: float, size: float, glow: Color, angry: bool) -> void:
		var look: Vector2 = hero.aim * (size * 0.5)
		for side in [-1.0, 1.0]:
			var s: float = side
			var eye: Vector2 = center + Vector2(s * spread, 0) + look
			draw_circle(eye, size + 1.6, Color(0.05, 0.02, 0.03))
			draw_circle(eye, size, glow)
			draw_circle(eye + hero.aim * (size * 0.35), size * 0.5, Color("28101a"))
			if angry:
				# Vihainen kulmakarva silmän yllä.
				draw_line(eye + Vector2(s * -size, -size * 1.5),
					eye + Vector2(s * size, -size * 0.4), Palette.darker(glow, 0.7), 3.0)

	func _hp_bar(cr: Critter, r: float) -> void:
		var boss: bool = cr.is_major_objective()
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		var bw: float = r * (2.6 if boss else 2.2)
		var by: float = -r - (24.0 if boss else 16.0)
		if boss:
			UiKit.draw_text(self, Vector2(0, by - 13.0), cr._kind_name(), 15,
				Palette.with_alpha(Color("e6b3ff"), 0.92), true)
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0 if boss else 6.0), Color(0, 0, 0, 0.6))
		var hpc: Color = Color("ff4a5a") if cr._enraged else cr._color
		draw_rect(Rect2(-bw / 2.0, by, bw * frac, 7.0 if boss else 6.0), Palette.glow(hpc, 1.15))
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0 if boss else 6.0),
			Palette.with_alpha(Color.WHITE, 0.25), false, 1.0)
		if boss:
			for k in range(1, 4):
				var sx: float = -bw / 2.0 + bw * float(k) / 4.0
				draw_line(Vector2(sx, by), Vector2(sx, by + 7.0), Color(0, 0, 0, 0.5), 1.0)

	## Baronin happopurkauksen varoitusrenkaat hyökkääjien alla: rengas täyttyy
	## telegrafin edetessä -> purkaushetki on luettavissa tarkasti.
	func _acid_telegraph(cr: Critter) -> void:
		var frac: float = clampf(1.0 - cr._acid_tell / Critter.ACID_WARNING, 0.0, 1.0)
		var warn := Color("b6ff4a")
		for spot_v in cr._acid_spots:
			var spot: Vector2 = spot_v
			var c: Vector2 = spot - hero.global_position
			draw_circle(c, Critter.ACID_RADIUS, Palette.with_alpha(warn, 0.08 + 0.12 * frac))
			draw_arc(c, Critter.ACID_RADIUS, 0.0, TAU, 40,
				Palette.with_alpha(Palette.glow(warn, 1.4), 0.5 + 0.4 * frac), 3.0)
			draw_arc(c, Critter.ACID_RADIUS * frac, 0.0, TAU, 40,
				Palette.with_alpha(Palette.glow(warn, 1.6), 0.85), 4.0)
			# Kuplivat pisteet kertovat että maa alkaa syöpyä.
			for i in range(3):
				var a: float = _time * 5.0 + float(i) * 2.1 + spot.x * 0.01
				var bubble: Vector2 = c + Vector2(cos(a), sin(a)) * Critter.ACID_RADIUS * 0.5
				draw_circle(bubble, 3.0, Palette.with_alpha(Palette.glow(warn, 1.5), 0.3 + 0.5 * frac))

	## Dragonin tulihenkäyksen levenevä kartiotelegrafi lukittuun suuntaan.
	func _breath_telegraph(cr: Critter) -> void:
		var frac: float = clampf(1.0 - cr._breath_tell / Critter.BREATH_WARNING, 0.0, 1.0)
		var dir: Vector2 = cr._breath_dir
		var ang: float = dir.angle()
		var half: float = deg_to_rad(Critter.BREATH_HALF_DEG)
		var warn := Color("ff9a4a")
		var reach: float = Critter.BREATH_RANGE * (0.35 + 0.65 * frac)
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in range(9):
			var a: float = ang - half + half * 2.0 * float(i) / 8.0
			pts.append(Vector2.RIGHT.rotated(a) * reach)
		draw_colored_polygon(pts, Palette.with_alpha(warn, 0.07 + 0.10 * frac))
		# Kartion reunat piirretään täyteen mittaan: alue on selvä alusta asti.
		var edge := Palette.with_alpha(Palette.glow(warn, 1.4), 0.45 + 0.45 * frac)
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(ang - half) * Critter.BREATH_RANGE, edge, 2.5)
		draw_line(Vector2.ZERO, Vector2.RIGHT.rotated(ang + half) * Critter.BREATH_RANGE, edge, 2.5)
		draw_arc(Vector2.ZERO, Critter.BREATH_RANGE, ang - half, ang + half, 24, edge, 2.5)
		# Etenevä rintama näyttää tarkan laukaisuhetken.
		draw_arc(Vector2.ZERO, reach, ang - half, ang + half, 24,
			Palette.with_alpha(Palette.glow(warn, 1.6), 0.85), 4.0)

	# --- Tyyppikohtaiset ulkoasut ---

	## Raivopeto: villi oranssi peto piikkiharjalla ja torahampailla.
	func _paint_beast(cr: Critter, r: float, col: Color, dark: Color, tell: float, moving: float) -> void:
		# Piikkiharja selkään (ylä-takakaari).
		var spikes := 7
		for i in range(spikes):
			var t: float = float(i) / float(spikes - 1)
			var ang: float = PI + 0.35 + t * (PI - 0.7)
			var base_p: Vector2 = Vector2(cos(ang), sin(ang)) * (r * 0.92)
			var tip: Vector2 = Vector2(cos(ang), sin(ang)) * (r * 1.42)
			var mid := (base_p + tip) * 0.5 + Vector2(0, -2)
			draw_colored_polygon(PackedVector2Array([
				base_p + Vector2(-4, 0), base_p + Vector2(4, 0), tip]), dark)
			draw_line(base_p, mid, Palette.glow(col, 1.1), 1.5)
		# Runko.
		draw_circle(Vector2.ZERO, r + 3.0, dark)
		draw_circle(Vector2.ZERO, r, col)
		draw_circle(Vector2(0, r * 0.34), r * 0.72, Palette.with_alpha(dark, 0.45))
		draw_circle(Vector2(-r * 0.32, -r * 0.34), r * 0.3, Palette.with_alpha(Color.WHITE, 0.16))
		# Jalkanystyt (astelevat liikkeessä).
		for fx in [-0.5, 0.5]:
			var f: float = fx
			var step := sin(_time * 12.0 + f * PI) * 2.0 * moving
			draw_circle(Vector2(f * r * 0.7, r * 0.82 + step), r * 0.2, dark)
		# Suu — aukeaa telegrafissa (varoitus).
		var mouth_w: float = r * (0.5 + tell * 0.5)
		var mouth_h: float = r * (0.16 + tell * 0.4)
		draw_circle(Vector2(0, r * 0.28), mouth_h + 1.0, Color("2a0d0d"))
		draw_rect(Rect2(-mouth_w * 0.5, r * 0.2, mouth_w, mouth_h), Color("3a0f10"))
		# Torahampaat.
		for txf in [-1.0, 1.0]:
			var tf: float = txf
			var base_t := Vector2(tf * r * 0.34, r * 0.22)
			draw_colored_polygon(PackedVector2Array([
				base_t + Vector2(-3, 0), base_t + Vector2(3, 0),
				base_t + Vector2(tf * 2.0, -r * 0.38 - tell * r * 0.15)]), Color("fff2d8"))
		# Silmät — hehkuvat, vihaiset.
		var eye_glow := Palette.glow(Color("ffd24a"), 1.3) if tell < 0.2 else Palette.glow(Color("ff5a3a"), 1.5)
		_critter_eyes(Vector2(0, -r * 0.18), r * 0.34, r * 0.16, eye_glow, true)

	## Aarrepeto: kimalteleva kultainen aarrevahti jalokivineen.
	func _paint_treasure(cr: Critter, r: float, col: Color, dark: Color) -> void:
		# Kiertävät kimalteet.
		for i in range(3):
			var a: float = _time * 1.4 + TAU * float(i) / 3.0
			var orb := Vector2(cos(a), sin(a) * 0.6) * (r * 1.35)
			var tw: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(_time * 5.0 + float(i) * 2.0))
			draw_circle(orb, 2.6, Palette.with_alpha(Palette.glow(Color("fff0a0"), 1.6), tw))
		# Kruunupiikit päälle.
		for i in range(3):
			var cx: float = (float(i) - 1.0) * r * 0.5
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - r * 0.16, -r * 0.9), Vector2(cx + r * 0.16, -r * 0.9),
				Vector2(cx, -r * 1.28)]), Palette.glow(Color("ffe27a"), 1.2))
		# Runko (kilpikuori) + fasettiviivat.
		draw_circle(Vector2.ZERO, r + 3.0, Palette.darker(col, 0.55))
		draw_circle(Vector2.ZERO, r, col)
		draw_circle(Vector2(0, r * 0.32), r * 0.7, Palette.with_alpha(dark, 0.4))
		for i in range(4):
			var a: float = TAU * float(i) / 4.0 + PI / 4.0
			draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * r, Palette.with_alpha(Color("fff2c0"), 0.25), 1.5)
		draw_circle(Vector2(-r * 0.3, -r * 0.32), r * 0.28, Palette.with_alpha(Color.WHITE, 0.28))
		# Upotetut jalokivet (välkkyvät).
		for i in range(3):
			var gp := Vector2((float(i) - 1.0) * r * 0.42, r * 0.1)
			var tw: float = 0.55 + 0.45 * sin(_time * 6.0 + float(i) * 2.1)
			var gem := PackedVector2Array([
				gp + Vector2(0, -r * 0.16), gp + Vector2(r * 0.12, 0),
				gp + Vector2(0, r * 0.16), gp + Vector2(-r * 0.12, 0)])
			draw_colored_polygon(gem, Palette.with_alpha(Palette.glow(Color("7affd0"), 1.4), 0.6 + 0.4 * tw))
		# Rauhalliset silmät.
		_critter_eyes(Vector2(0, -r * 0.16), r * 0.3, r * 0.14, Color("fffdf0"), false)

	## Red Guardian: raskas magmahärkä. Kivipanssari, hehkuvat halkeamat,
	## sarvet ja eteen nojaava siluetti kertovat fyysisestä voimabuffista.
	func _paint_red_guardian(_cr: Critter, r: float, col: Color, dark: Color,
			tell: float, moving: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var heat := 0.65 + 0.35 * sin(_time * 8.0)
		# Neljä raskasta kivijalkaa, joiden alla hiillos välähtää.
		for front_f in [-0.42, 0.38]:
			var front_v: float = front_f
			for side_f in [-1.0, 1.0]:
				var side_v: float = side_f
				var step := sin(_time * 9.0 + side_v * 1.8 + front_v) * 2.2 * moving
				var hoof: Vector2 = forward * r * front_v + side * r * side_v * 0.68 + forward * step
				draw_circle(hoof, r * 0.25, Color("251714"))
				draw_line(hoof, hoof + forward * r * 0.18,
					Palette.with_alpha(Color("ff7a38"), 0.45), 2.0)
		# Lohkaremainen vartalo, ei pyöreä pallo.
		var hull := PackedVector2Array([
			forward * r * 0.82,
			forward * r * 0.32 + side * r * 0.80,
			-forward * r * 0.62 + side * r * 0.62,
			-forward * r * 0.86,
			-forward * r * 0.62 - side * r * 0.62,
			forward * r * 0.32 - side * r * 0.80,
		])
		draw_colored_polygon(hull, dark)
		var plate := PackedVector2Array([
			forward * r * 0.65,
			side * r * 0.62,
			-forward * r * 0.55,
			-side * r * 0.62,
		])
		draw_colored_polygon(plate, col)
		draw_polyline(PackedVector2Array(Array(plate) + [plate[0]]), Color("511c18"), 3.0)
		# Magmaydin ja epäsymmetriset halkeamat.
		var core := forward * r * 0.08
		draw_circle(core, r * (0.26 + heat * 0.04), Palette.with_alpha(Color("ff5a32"), 0.38))
		draw_circle(core, r * 0.14, Palette.glow(Color("ffbf55"), 1.65))
		for crack_i in range(5):
			var a: float = -1.8 + float(crack_i) * 0.78
			var p0 := core + Vector2.RIGHT.rotated(a) * r * 0.13
			var p1 := core + Vector2.RIGHT.rotated(a + 0.18) * r * (0.48 + 0.05 * (crack_i % 2))
			draw_line(p0, p1, Palette.with_alpha(Color("ff7a38"), 0.65 + heat * 0.2), 2.0)
		# Härän pää, kaksi ulospäin kaartuvaa sarvea ja hehkuvat silmät.
		var head := forward * r * (0.67 + tell * 0.08)
		draw_circle(head, r * 0.43, Color("391b18"))
		for horn_s in [-1.0, 1.0]:
			var hs: float = horn_s
			var hb := head + side * hs * r * 0.30
			var hm := head + forward * r * 0.12 + side * hs * r * 0.62
			var ht := head + forward * r * 0.48 + side * hs * r * 0.78
			draw_polyline(PackedVector2Array([hb, hm, ht]), Color("ffe1b0"), 5.0)
			draw_circle(ht, 3.0, Palette.glow(Color("ff7a38"), 1.5))
		for eye_s in [-1.0, 1.0]:
			var es: float = eye_s
			var eye := head + forward * r * 0.26 + side * es * r * 0.17
			draw_circle(eye, r * 0.09, Palette.glow(Color("ffd05a"), 1.65))
		# Leukakilpi levenee latauksen aikana.
		var jaw := head + forward * r * 0.31
		draw_line(jaw - side * r * (0.18 + tell * 0.13),
			jaw + side * r * (0.18 + tell * 0.13), Color("1b1010"), 5.0 + tell * 4.0)

	## Blue Guardian: leijuva riimusentinel. Kristalliydin ja itsenäisesti
	## kiertävät panssarilevyt kertovat mana-/spell-power-buffista.
	func _paint_blue_guardian(_cr: Critter, r: float, col: Color, dark: Color,
			tell: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var pulse := 0.6 + 0.4 * sin(_time * 7.0)
		# Neljä orbit-levyä tekevät avoimen, leijuvan siluetin.
		for i in range(4):
			var a: float = _time * (0.8 + tell * 1.6) + TAU * float(i) / 4.0
			var orbit := Vector2(cos(a), sin(a) * 0.72) * r * 0.92
			var plate := PackedVector2Array([
				orbit + Vector2(0, -r * 0.22), orbit + Vector2(r * 0.18, 0),
				orbit + Vector2(0, r * 0.22), orbit + Vector2(-r * 0.18, 0),
			])
			draw_colored_polygon(plate, Palette.with_alpha(col, 0.72))
			draw_polyline(PackedVector2Array(Array(plate) + [plate[0]]),
				Palette.glow(Color("a8dcff"), 1.35), 1.5)
		# Keskimmäinen timanttikeho kerroksittain.
		var shell := PackedVector2Array([
			forward * r * 0.78, side * r * 0.58,
			-forward * r * 0.78, -side * r * 0.58,
		])
		draw_colored_polygon(shell, dark)
		var crystal := PackedVector2Array([
			forward * r * 0.60, side * r * 0.42,
			-forward * r * 0.60, -side * r * 0.42,
		])
		draw_colored_polygon(crystal, Palette.glow(col, 1.3))
		draw_line(-forward * r * 0.52, forward * r * 0.52,
			Palette.with_alpha(Color.WHITE, 0.65), 2.0)
		# Mana-ydin ja pyörivä riimukehä.
		draw_circle(Vector2.ZERO, r * (0.22 + 0.05 * pulse),
			Palette.glow(Color("c8ecff"), 1.6))
		draw_arc(Vector2.ZERO, r * 0.64, -_time * 2.2, -_time * 2.2 + TAU * 0.72,
			26, Palette.with_alpha(Color("d8f3ff"), 0.7), 2.0)
		# Haarautuvat kristallisarvet ja tähtäyssilmä edessä.
		for horn_s in [-1.0, 1.0]:
			var hs: float = horn_s
			var hb := forward * r * 0.45 + side * hs * r * 0.28
			var ht := forward * r * 1.0 + side * hs * r * 0.68
			draw_line(hb, ht, Palette.glow(Color("8ed4ff"), 1.45), 3.0)
			draw_line(ht, ht - forward * r * 0.24 + side * hs * r * 0.22,
				Palette.glow(Color("8ed4ff"), 1.35), 2.0)
		var eye := forward * r * 0.53
		draw_circle(eye, r * (0.10 + tell * 0.06), Color("07192d"))
		draw_circle(eye + forward * r * 0.03, r * (0.065 + tell * 0.05), Color.WHITE)

	## Small camp: nopea sammalraptori. Lehtihäntä, neljä jalkaa ja matala
	## petomainen profiili erottavat sen buffivahdeista.
	func _paint_mossling(_cr: Critter, r: float, col: Color, dark: Color,
			tell: float, moving: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		# Lehtimäinen häntä heiluu takana.
		var tail_dir := (-forward).rotated(sin(_time * 7.0) * 0.28)
		for leaf_i in range(3):
			var lp := tail_dir * r * (0.65 + leaf_i * 0.25)
			var leaf_side: float = -1.0 if leaf_i % 2 == 0 else 1.0
			var leaf := PackedVector2Array([
				lp + tail_dir * r * 0.30,
				lp + side * leaf_side * r * 0.25,
				lp - tail_dir * r * 0.18,
			])
			draw_colored_polygon(leaf, Palette.glow(col, 1.08 + leaf_i * 0.06))
		# Neljä kevyttä jalkaa ja terävät kynnet.
		for front_f in [-0.35, 0.32]:
			var front_v: float = front_f
			for side_f in [-1.0, 1.0]:
				var side_v: float = side_f
				var step := sin(_time * 13.0 + front_v * 4.0 + side_v) * 2.4 * moving
				var paw := forward * r * front_v + side * side_v * r * 0.58 + forward * step
				draw_line(paw, paw + forward * r * 0.30, dark, 4.0)
				draw_line(paw + forward * r * 0.25,
					paw + forward * r * 0.38 + side * side_v * r * 0.10,
					Color("e8f6c5"), 2.0)
		# Pitkä runko ja vaalea selkälehtien rivi.
		var body := PackedVector2Array([
			forward * r * 0.72, forward * r * 0.2 + side * r * 0.52,
			-forward * r * 0.65 + side * r * 0.42, -forward * r * 0.78,
			-forward * r * 0.65 - side * r * 0.42, forward * r * 0.2 - side * r * 0.52,
		])
		draw_colored_polygon(body, dark)
		draw_colored_polygon(PackedVector2Array([
			forward * r * 0.60, side * r * 0.38,
			-forward * r * 0.58, -side * r * 0.38,
		]), col)
		for leaf_i in range(4):
			var along: float = -0.42 + leaf_i * 0.28
			var leaf_p := forward * r * along
			draw_colored_polygon(PackedVector2Array([
				leaf_p - forward * r * 0.18,
				leaf_p + side * r * 0.12,
				leaf_p + forward * r * 0.20,
				leaf_p - side * r * 0.12,
			]), Color("b6df72"))
		# Kiilamainen pää, kaksi korvalehtä ja kirkkaat silmät.
		var head := forward * r * (0.68 + tell * 0.08)
		draw_colored_polygon(PackedVector2Array([
			head + forward * r * 0.42,
			head + side * r * 0.38,
			head - forward * r * 0.30,
			head - side * r * 0.38,
		]), col)
		for ear_s in [-1.0, 1.0]:
			var es: float = ear_s
			draw_colored_polygon(PackedVector2Array([
				head - forward * r * 0.12 + side * es * r * 0.25,
				head - forward * r * 0.42 + side * es * r * 0.52,
				head + side * es * r * 0.18,
			]), Color("b6df72"))
			var eye := head + forward * r * 0.16 + side * es * r * 0.18
			draw_circle(eye, r * 0.08, Palette.glow(Color("efff9b"), 1.55))

	## Dragon: siivekäs käärmelohikäärme. Siivet lepäävät supussa rauhassa,
	## avautuvat taistelussa ja LEIMAHTAVAT auki tulihenkäyksen telegrafissa.
	## Kekäleet leijuvat ympärillä; silmät ja hengitysydin hehkuvat aggrossa,
	## rauhallisena olento on selvästi himmeä ja passiivinen.
	func _paint_dragon(cr: Critter, r: float, col: Color, dark: Color,
			tell: float, moving: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var fighting: bool = cr._in_combat()
		var eng: bool = cr._enraged
		var aura := Color("ff6a52") if eng else Color("49e7d2")
		var breath_frac := 0.0
		if cr._breath_tell > 0.0:
			breath_frac = clampf(1.0 - cr._breath_tell / Critter.BREATH_WARNING, 0.0, 1.0)
		# Siipien levitys: supussa rauhassa, auki taistelussa, levällään henkäyksessä.
		var spread := 0.6
		if fighting:
			spread = 1.0
		if cr._breath_tell > 0.0:
			spread = 1.05 + 0.4 * breath_frac
		var wing_flap := sin(_time * (4.0 + moving * 4.0 + (3.0 if fighting else 0.0))) * r * 0.10
		# Kekäleet: hehkuvia kipinöitä nousee olennosta (taistelussa tiheämmin).
		var embers: int = 6 if fighting else 3
		for i in range(embers):
			var ph: float = _time * (0.7 + 0.13 * float(i)) + float(i) * 2.3
			var lift: float = fposmod(ph * 0.6, 1.0)
			var ep := Vector2(cos(ph * 1.6) * r * 1.15, (0.4 - lift) * r * 1.6)
			var tw: float = (1.0 - lift) * (0.9 if fighting else 0.4)
			draw_circle(ep, 2.6, Palette.with_alpha(Palette.glow(Color("ffb35a"), 1.5), tw))
		# Pitkä, kaareva häntä kapenevista osista.
		var tail := PackedVector2Array()
		for i in range(5):
			var f: float = float(i) / 4.0
			tail.append(-forward * r * (0.55 + f * 1.15)
				+ side * sin(_time * 4.0 - f * 3.0) * r * 0.22 * f)
		draw_polyline(tail, dark, r * 0.42)
		draw_polyline(tail, Palette.with_alpha(col, 0.78), r * 0.24)
		# Suuret siivet ovat dragonin tärkein kaukaa luettava siluetti.
		for wing_s in [-1.0, 1.0]:
			var ws: float = wing_s
			var wing_root := -forward * r * 0.08 + side * ws * r * 0.32
			var wing_mid := -forward * r * 0.48 + side * ws * (r * 1.15 * spread + wing_flap)
			var wing_tip := forward * r * 0.32 + side * ws * (r * 1.50 * spread + wing_flap)
			var wing_back := forward * r * 0.48 + side * ws * r * 0.48 * maxf(spread, 0.8)
			var wing := PackedVector2Array([wing_root, wing_mid, wing_tip, wing_back])
			draw_colored_polygon(wing, Palette.with_alpha(dark, 0.95))
			draw_polyline(PackedVector2Array(Array(wing) + [wing[0]]),
				Palette.with_alpha(Palette.glow(aura, 1.3), 0.4 + (0.4 if fighting else 0.0)), 3.0)
			draw_line(wing_root, wing_tip, Palette.with_alpha(col, 0.62), 2.0)
			# Siipiluut piirtyvät esiin kun siipi on levällään.
			if spread > 0.8:
				draw_line(wing_root, wing_mid, Palette.with_alpha(col, 0.5), 1.5)
		# Suomuinen vartalo ja hengitysydin (hehkuu henkäyksen lähestyessä).
		var torso := PackedVector2Array([
			forward * r * 0.78, side * r * 0.62,
			-forward * r * 0.78, -side * r * 0.62,
		])
		draw_colored_polygon(torso, dark)
		draw_circle(Vector2.ZERO, r * 0.62, col)
		for scale_i in range(5):
			var along: float = -0.42 + scale_i * 0.22
			draw_arc(forward * r * along, r * 0.24, -PI * 0.2, PI * 1.2, 10,
				Palette.with_alpha(Color("a8fff4"), 0.32), 1.5)
		var breath_p := forward * r * 0.18
		var core_boost: float = tell * 0.13 + breath_frac * 0.2
		draw_circle(breath_p, r * (0.18 + core_boost),
			Palette.with_alpha(aura, 0.25 + (0.2 if fighting else 0.0)))
		draw_circle(breath_p, r * (0.09 + core_boost * 0.6),
			Palette.glow(Color("d7fff8"), 1.2 + (0.4 if fighting else 0.0)))
		# Kuono, leukalinja ja taakse suuntautuvat sarvet.
		var head := forward * r * 0.78
		var snout := head + forward * r * (0.36 + tell * 0.10)
		draw_circle(head, r * 0.38, dark)
		draw_colored_polygon(PackedVector2Array([
			snout + forward * r * 0.18, snout + side * r * 0.28,
			head - forward * r * 0.10, snout - side * r * 0.28,
		]), col)
		# Silmät: taistelussa kirkas hehku, rauhassa himmeät.
		var eye_col := Palette.glow(Color("ff8a5a") if eng else Color("f2ff9b"),
			1.7 if fighting else 0.85)
		for horn_s in [-1.0, 1.0]:
			var hs: float = horn_s
			draw_line(head + side * hs * r * 0.24,
				head - forward * r * 0.55 + side * hs * r * 0.48,
				Color("d8fff5"), 4.0)
			var eye := head + forward * r * 0.12 + side * hs * r * 0.22
			draw_circle(eye, r * 0.11, Color("072523"))
			draw_circle(eye, r * 0.085, eye_col)
		# Leuka aukeaa latauksessa/henkäyksessä ja näyttää tulevan iskun.
		var jaw_open: float = maxf(tell, breath_frac)
		draw_line(snout - side * r * (0.22 + jaw_open * 0.12),
			snout + side * r * (0.22 + jaw_open * 0.12), Color("072523"), 4.0 + jaw_open * 5.0)

	## Baron: massiivinen panssaroitu behemotti-mato. Kerrostetut kuorilevyt,
	## aaltoileva häntäpanssari, eteen kaartuvat sarvet ja kolme hehkuvaa
	## silmää. Rauhassa hidas hengityssyke ja himmeät silmät; aggrossa aura
	## ja hehkut kirkastuvat selvästi.
	func _paint_boss(cr: Critter, r: float, col: Color, dark: Color, tell: float) -> void:
		var eng: bool = cr._enraged
		var fighting: bool = cr._in_combat()
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var back_a: float = (-forward).angle()
		var aura := Color("ff5a4a") if eng else Color("c46adf")
		# Hengityssyke: rauhassa hidas ja syvä, taistelussa tiheä.
		var breath_pulse: float = 0.5 + 0.5 * sin(_time * (5.0 if fighting else 2.2))
		var swell: float = 1.0 + 0.035 * breath_pulse
		# Taisteluaura vain aggroutuneena — rauhallinen pomo on selvästi passiivinen.
		if fighting:
			draw_arc(Vector2.ZERO, r + 22.0, -_time * 0.8, -_time * 0.8 + TAU * 0.8, 44,
				Palette.with_alpha(Palette.glow(aura, 1.35), 0.4 + (0.15 if eng else 0.0)), 3.0)
		# Panssaroitu matovartalo: kapenevat häntäsegmentit aaltoilevat takana ja
		# jokaisessa on kuorisauma + taakse osoittava selkäpiikki.
		for seg_i in range(4):
			var f: float = float(seg_i + 1)
			var wob: float = sin(_time * (1.6 + (1.6 if fighting else 0.0)) - f * 1.1) * r * 0.16
			var seg_c: Vector2 = -forward * r * (0.55 + f * 0.5) + side * wob
			var seg_r: float = r * (0.78 - f * 0.13)
			draw_circle(seg_c, seg_r + 3.0, Palette.darker(col, 0.5))
			draw_circle(seg_c, seg_r, col.lerp(dark, 0.22 + f * 0.12))
			draw_arc(seg_c, seg_r * 0.8, back_a - 1.2, back_a + 1.2, 12,
				Palette.with_alpha(Color("2a1435"), 0.8), 3.0)
			draw_colored_polygon(PackedVector2Array([
				seg_c - side * 5.0 - forward * seg_r * 0.55,
				seg_c + side * 5.0 - forward * seg_r * 0.55,
				seg_c - forward * (seg_r + r * 0.26)]),
				Palette.darker(aura, 0.45))
		# Päärunko hengittää (swell) — kerrostetut kuorilevyt limittäin selässä.
		draw_circle(Vector2.ZERO, (r + 4.0) * swell, Palette.darker(col, 0.55))
		draw_circle(Vector2.ZERO, r * swell, col)
		for plate_i in range(3):
			var pf: float = float(plate_i)
			var pr: float = r * (0.96 - pf * 0.22) * swell
			draw_arc(Vector2.ZERO, pr, back_a - 1.35 + pf * 0.12, back_a + 1.35 - pf * 0.12,
				20, Palette.with_alpha(Palette.darker(col, 0.35), 0.9), 6.0 - pf)
			draw_arc(Vector2.ZERO, pr - 3.0, back_a - 1.3 + pf * 0.12, back_a + 1.3 - pf * 0.12,
				20, Palette.with_alpha(Palette.glow(col, 1.25), 0.3), 1.5)
		# Sarvet kaartuvat eteen-ulos; kärjet hehkuvat taistelussa.
		for sgn in [-1.0, 1.0]:
			var s: float = sgn
			var horn_base: Vector2 = forward * r * 0.3 + side * s * r * 0.5
			var horn_mid: Vector2 = forward * r * 0.62 + side * s * r * 0.85
			var horn_tip: Vector2 = forward * r * 1.08 + side * s * r * 0.95
			draw_polyline(PackedVector2Array([horn_base, horn_mid, horn_tip]),
				Palette.darker(col, 0.65), 7.0)
			draw_circle(horn_tip, 4.5, Palette.glow(aura, 1.5 if fighting else 1.0))
		# Hehkuva ydin selässä: syke näkyy kaukaa, kirkastuu aggrossa/raivossa.
		var core_col := Color("ff8a4a") if eng else Color("e6a8ff")
		draw_circle(-forward * r * 0.22, r * (0.2 + 0.05 * breath_pulse),
			Palette.with_alpha(Palette.glow(core_col, 1.6), 0.55 if fighting else 0.3))
		draw_circle(-forward * r * 0.22, r * 0.1,
			Palette.glow(core_col, 1.7 if fighting else 1.1))
		# Raivon halkeamat panssarissa.
		if eng:
			for i in range(4):
				var a: float = TAU * float(i) / 4.0 + 0.4
				var p0 := Vector2(cos(a), sin(a)) * (r * 0.2)
				var p1 := Vector2(cos(a + 0.3), sin(a + 0.3)) * (r * 0.75)
				draw_line(p0, p1, Palette.glow(Color("ff8a3a"), 1.6), 2.0)
		# Kita aukeaa viillon telegrafissa: hammaskehä leviää.
		var maw: Vector2 = forward * r * 0.55
		var mw: float = r * (0.3 + tell * 0.28)
		draw_circle(maw, mw + 2.0, Palette.darker(col, 0.6))
		draw_circle(maw, mw, Color("1a0518"))
		for tooth_i in range(5):
			var ta: float = forward.angle() - 0.9 + float(tooth_i) * 0.45
			var tp: Vector2 = maw + Vector2.RIGHT.rotated(ta) * mw
			draw_colored_polygon(PackedVector2Array([
				tp + Vector2.RIGHT.rotated(ta + PI / 2.0) * 3.0,
				tp + Vector2.RIGHT.rotated(ta - PI / 2.0) * 3.0,
				tp + Vector2.RIGHT.rotated(ta) * (5.0 + tell * 6.0)]), Color("fff2e0"))
		# Kolme silmää kidan yllä: rauhassa himmeät, aggrossa kirkkaat.
		var eye_col := Color("ff5a3a") if eng else Color("ffe14a")
		var eye_glow := Palette.glow(eye_col, 1.7 if fighting else 0.8)
		for es_v in [-1.0, 0.0, 1.0]:
			var es: float = es_v
			var eye: Vector2 = forward * r * 0.8 + side * es * r * 0.28
			draw_circle(eye, r * 0.12, Color(0.05, 0.02, 0.03))
			draw_circle(eye, r * 0.09, eye_glow)
