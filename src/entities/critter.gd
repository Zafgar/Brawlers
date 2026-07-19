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
##   BOSS         — keskustan pomo (Viidakkopomo): ilmestyy ajastimella,
##                  raivostuu alle 40 % HP:lla ja iskee alueelle telegrafilla;
##                  kaataja saa ison pitkän boostin.
##
## Hyökkäys on telegrafoitu: olento vetäytyy hetkeksi taakse (varoitus) ennen
## iskua, joten sen voi väistää. Elinkaari kulkee Heron respawn-koneiston kautta.

enum Kind { DAMAGE_CAMP, POINTS_CAMP, BOSS }

# Pomon alueisku
const SLAM_RADIUS := 205.0
const SLAM_DMG := 26.0
const SLAM_KB := 620.0
const SLAM_WINDUP := 0.78
const SLAM_INTERVAL := 6.5

var kind := Kind.DAMAGE_CAMP
var home := Vector2.ZERO
var respawn_delay := 22.0
var attack_reach := 78.0
var attack_dmg := 16.0
var attack_kb := 240.0
var _color := Color("d98a3a")
var _base_color := Color("d98a3a")

# Käyttäytymistila (luetaan myös ulkoasussa telegrafeja varten)
var _windup_time := 0.28
var _wind := 0.0                   # iskun latautuminen jäljellä (0 = ei kesken)
var _attack_tell := 0.0            # 0..1 telegrafi (0 = ei, 1 = juuri ennen iskua)
var _attack_dir := Vector2.RIGHT
var _enraged := false
var _slam_cd := SLAM_INTERVAL
var _slam_tell := 0.0
var _slam_max := SLAM_WINDUP
var _slam_origin := Vector2.ZERO


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
	controller = brain

	# Olennoilla ei ole ultia -> estä latautuminen (muuten "ULTI VALMIS!" -popup).
	ult_gain_mult = 0.0

	match kind:
		Kind.DAMAGE_CAMP:
			max_hp = 240.0
			radius = 34.0
			base_speed = 78.0
			attack_reach = 82.0
			attack_dmg = 15.0
			attack_kb = 250.0
			respawn_delay = 22.0
			kb_resist = 0.6
			_color = Color("e0803a")
			_windup_time = 0.24
			brain.aggro_radius = 250.0
			brain.attack_range = 74.0
			brain.leash = 360.0
			cd_max.basic = 0.95
		Kind.POINTS_CAMP:
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
			brain.aggro_radius = 220.0
			brain.attack_range = 74.0
			brain.leash = 320.0
			cd_max.basic = 1.15
		Kind.BOSS:
			max_hp = 1200.0
			radius = 58.0
			base_speed = 96.0
			attack_reach = 122.0
			attack_dmg = 30.0
			attack_kb = 520.0
			respawn_delay = 95.0
			kb_resist = 0.92
			_color = Color("b64ad6")
			_windup_time = 0.42
			brain.aggro_radius = 460.0
			brain.attack_range = 112.0
			brain.leash = 720.0
			cd_max.basic = 0.9
	hp = max_hp
	_slam_cd = SLAM_INTERVAL
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
			return "Viidakkopomo"
	return "Olento"


func hero_color() -> Color:
	return _color


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
	AudioMgr.play("swing", 0.12, -6.0 if kind != Kind.BOSS else -2.0)
	Fx.slash(arena, global_position, dir, attack_reach, 72.0, _color)
	for enemy in arena.alive_enemies(team):
		var to_e: Vector2 = enemy.global_position - global_position
		if to_e.length() > attack_reach + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_e))) > 72.0:
			continue
		deal_damage_to(enemy, attack_dmg, attack_kb, to_e.normalized())
	if kind == Kind.BOSS:
		arena.shake(0.12)
		Fx.spark(arena, global_position + dir * attack_reach * 0.7, Palette.glow(_color, 1.4))


## Pomon erikoiskäyttäytyminen: raivostuminen ja telegrafoitu alueisku.
func _passive_update(delta: float) -> void:
	if kind != Kind.BOSS:
		return
	if not _enraged and hp <= max_hp * 0.4:
		_enrage()
	if _slam_tell > 0.0:
		_slam_tell -= delta
		if _slam_tell <= 0.0:
			_do_slam()
		return
	_slam_cd -= delta
	if _slam_cd <= 0.0 and _player_near(SLAM_RADIUS + 40.0):
		_slam_cd = SLAM_INTERVAL * (0.62 if _enraged else 1.0)
		_slam_tell = SLAM_WINDUP
		_slam_max = SLAM_WINDUP
		_slam_origin = global_position
		AudioMgr.play("quake", 0.05, -2.0)
		arena.popup(global_position + Vector2(0, -radius - 34.0),
			"ISKU TULEE!", Palette.glow(Color("ff6a4a"), 1.4), 18)


## Raivostuminen alle 40 % HP:lla. Nopeampi ja punertava; iskunopeus ja
## telegrafi hoidetaan _enraged-lipun kautta (ei pysyvää mutaatiota, jotta
## respawn palautuu puhtaasti).
func _enrage() -> void:
	_enraged = true
	apply_haste(1.4, 99999.0)
	_color = _base_color.lerp(Color("ff425a"), 0.45)
	arena.popup(global_position + Vector2(0, -radius - 44.0),
		"RAIVOSTUU!", Palette.glow(Color("ff425a"), 1.6), 22)
	arena.shake(0.3)
	Fx.ring(arena, global_position, Palette.glow(Color("ff425a"), 1.5), radius + 50.0, 0.6, 8.0)


func _player_near(r: float) -> bool:
	for enemy in arena.alive_enemies(team):
		if enemy.global_position.distance_to(global_position) < r:
			return true
	return false


## Alueisku telegrafoidusta pisteestä: vahinko + tainnutus + tönäisy.
func _do_slam() -> void:
	arena.shake(0.55)
	AudioMgr.play("slam", 0.1, -2.0)
	Fx.ring(arena, _slam_origin, Palette.glow(Color("b64ad6"), 1.6), SLAM_RADIUS, 0.5, 12.0)
	Fx.ring(arena, _slam_origin, Palette.with_alpha(Color("ff6a4a"), 0.6), SLAM_RADIUS * 0.55, 0.4, 7.0)
	Fx.dust(arena, _slam_origin)
	for enemy in arena.alive_enemies(team):
		var to_e: Vector2 = enemy.global_position - _slam_origin
		if to_e.length() > SLAM_RADIUS + enemy.radius:
			continue
		var away: Vector2 = to_e.normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		deal_damage_to(enemy, SLAM_DMG, SLAM_KB, away)
		enemy.apply_stun(0.5)
		enemy.visual.squash(0.7, 1.4)


## Tyrmäys: ei sankarin KO-polkua. Ilmoittaa areenalle palkintoa varten ja
## käynnistää respawn-ajastimen (Heron respawn-koneisto herättää olennon).
func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	guard_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	_wind = 0.0
	_attack_tell = 0.0
	_slam_tell = 0.0
	respawn_timer = respawn_delay
	_recent_damagers.clear()
	Fx.knockout_burst(arena, global_position, _color)
	Fx.ring(arena, global_position, Palette.glow(_color, 1.5), radius + 40.0, 0.6, 7.0)
	AudioMgr.play("ko", 0.12, -4.0 if kind != Kind.BOSS else -8.0)
	arena.shake(0.4 if kind == Kind.BOSS else 0.2)
	if arena.has_method("on_critter_ko"):
		arena.on_critter_ko(self, source)


## Palautus kotileirille (Heron respawn-koneisto kutsuu respawn_timerin nollaan).
func _respawn() -> void:
	alive = true
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
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
	_slam_tell = 0.0
	_slam_cd = SLAM_INTERVAL
	for slot in cd:
		cd[slot] = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(_color, 0.9), radius + 30.0, 0.5)
	if arena.has_method("on_critter_respawn"):
		arena.on_critter_respawn(self)


## Erän alku: palauta olento kotileirille (ei HeroDefiä / spawn_pointia).
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
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
	_slam_tell = 0.0
	_slam_cd = SLAM_INTERVAL
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
		var boss: bool = cr.kind == Critter.Kind.BOSS
		var breathe: float = sin(_time * (4.5 if boss else 6.5)) * (2.0 + r * 0.03)
		var tell: float = cr._attack_tell

		# Pomon alueiskun telegrafi maassa (piirretään ensin, hahmon alle).
		if boss and cr._slam_tell > 0.0:
			_slam_telegraph(cr)

		_shadow(r)
		_ground_ring(cr, r)

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
		var a: float = 0.28 if cr.kind == Critter.Kind.BOSS else 0.16
		draw_arc(Vector2(0, r * 0.55), r + 12.0, 0.0, TAU, 40,
			Palette.with_alpha(col, a), 3.0)

	func _eyes(center: Vector2, spread: float, size: float, glow: Color, angry: bool) -> void:
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
		var boss: bool = cr.kind == Critter.Kind.BOSS
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

	## Pomon alueiskun varoitusalue (kasvaa telegrafin edetessä).
	func _slam_telegraph(cr: Critter) -> void:
		var frac: float = clampf(1.0 - cr._slam_tell / maxf(cr._slam_max, 0.01), 0.0, 1.0)
		var c: Vector2 = cr._slam_origin - hero.global_position
		var warn := Color("ff5a3a")
		var rad: float = Critter.SLAM_RADIUS
		draw_circle(c, rad, Palette.with_alpha(warn, 0.10 + 0.14 * frac))
		draw_arc(c, rad, 0.0, TAU, 52, Palette.with_alpha(Palette.glow(warn, 1.4), 0.5 + 0.4 * frac), 3.0)
		draw_arc(c, rad * frac, 0.0, TAU, 52, Palette.with_alpha(Palette.glow(warn, 1.6), 0.85), 4.0)

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
		_eyes(Vector2(0, -r * 0.18), r * 0.34, r * 0.16, eye_glow, true)

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
		_eyes(Vector2(0, -r * 0.16), r * 0.3, r * 0.14, Color("fffdf0"), false)

	## Viidakkopomo: iso uhkaava hirviö — harja, sarvet, hehkuva ydin ja
	## kolme silmää. Raivostuessaan punertava ja halkeileva.
	func _paint_boss(cr: Critter, r: float, col: Color, dark: Color, tell: float) -> void:
		var eng: bool = cr._enraged
		# Pyörivä aura taakse.
		var aura := Color("ff5a4a") if eng else Color("c46adf")
		draw_arc(Vector2.ZERO, r + 20.0, -_time * 0.6, -_time * 0.6 + TAU * 0.85, 44,
			Palette.with_alpha(Palette.glow(aura, 1.3), 0.35 + (0.2 if eng else 0.0)), 3.0)
		draw_arc(Vector2.ZERO, r + 30.0, _time * 0.4, _time * 0.4 + TAU * 0.6, 44,
			Palette.with_alpha(Palette.glow(aura, 1.2), 0.2), 2.0)
		# Rispaantunut harja rungon ympärillä.
		var frills := 16
		for i in range(frills):
			var a: float = TAU * float(i) / float(frills) + _time * 0.2
			var rr: float = r * (1.12 + 0.12 * sin(_time * 3.0 + float(i)))
			var base_p: Vector2 = Vector2(cos(a), sin(a)) * (r * 0.95)
			var tip: Vector2 = Vector2(cos(a), sin(a)) * rr
			draw_colored_polygon(PackedVector2Array([
				base_p + Vector2(-cos(a), -sin(a)).rotated(PI / 2.0) * 4.0,
				base_p + Vector2(-cos(a), -sin(a)).rotated(-PI / 2.0) * 4.0, tip]),
				Palette.darker(col, 0.4))
		# Runko.
		draw_circle(Vector2.ZERO, r + 4.0, Palette.darker(col, 0.55))
		draw_circle(Vector2.ZERO, r, col)
		draw_circle(Vector2(0, r * 0.34), r * 0.72, Palette.with_alpha(dark, 0.45))
		# Hehkuva ydin rinnassa (sykkii, kirkkaampi raivossa).
		var core_pulse: float = 0.6 + 0.4 * sin(_time * (10.0 if eng else 6.0))
		var core_col := Color("ff8a4a") if eng else Color("e6a8ff")
		draw_circle(Vector2(0, r * 0.1), r * (0.3 + 0.06 * core_pulse),
			Palette.with_alpha(Palette.glow(core_col, 1.6), 0.4))
		draw_circle(Vector2(0, r * 0.1), r * 0.16, Palette.glow(core_col, 1.7))
		# Raivon halkeamat.
		if eng:
			for i in range(4):
				var a: float = TAU * float(i) / 4.0 + 0.4
				var p0 := Vector2(cos(a), sin(a)) * (r * 0.2)
				var p1 := Vector2(cos(a + 0.3), sin(a + 0.3)) * (r * 0.75)
				draw_line(p0, p1, Palette.glow(Color("ff8a3a"), 1.6), 2.0)
		# Sarvet.
		for sgn in [-1.0, 1.0]:
			var s: float = sgn
			var horn_base := Vector2(s * r * 0.52, -r * 0.58)
			var horn_mid := Vector2(s * r * 0.86, -r * 0.95)
			var horn_tip := Vector2(s * r * 1.16, -r * 1.5)
			draw_polyline(PackedVector2Array([horn_base, horn_mid, horn_tip]),
				Palette.darker(col, 0.65), 7.0)
			draw_circle(horn_tip, 4.5, Palette.glow(aura, 1.4))
		# Suu ja torahampaat — aukeaa telegrafissa.
		var mw: float = r * (0.5 + tell * 0.4)
		var mh: float = r * (0.14 + tell * 0.32)
		draw_rect(Rect2(-mw * 0.5, r * 0.28, mw, mh), Color("1a0518"))
		for i in range(4):
			var fx: float = -1.0 + 2.0 * float(i) / 3.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(fx * mw * 0.42 - 2.0, r * 0.28), Vector2(fx * mw * 0.42 + 2.0, r * 0.28),
				Vector2(fx * mw * 0.42, r * 0.28 + mh)]), Color("fff2e0"))
		# Kolme hehkuvaa silmää.
		var eye_glow := Palette.glow(Color("ff5a3a"), 1.7) if eng else Palette.glow(Color("ffe14a"), 1.5)
		_eyes(Vector2(0, -r * 0.2), r * 0.38, r * 0.15, eye_glow, true)
		draw_circle(Vector2(0, -r * 0.42), r * 0.12, eye_glow)
		draw_circle(Vector2(0, -r * 0.42), r * 0.05, Color("28101a"))
