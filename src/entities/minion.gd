class_name Minion
extends Hero
## MOBA-minioni: heikko yksikkö joka marssii linjaa pitkin kohti vihollisen
## tukikohtaa, hyökkää matkalla vastaan tulevia vihollisia (minionit, sankarit,
## tornit). Kuuluu joukkueeseen (0/1) mutta on yksikkö (is_unit).

enum Kind { MELEE, RANGED, SUPER }

var kind := Kind.MELEE
var attack_reach := 62.0
var attack_dmg := 9.0
var _color := Color("4aa8ff")
var lane_id := ""
var gold_value := 20
var xp_value := 42

# Waves scale gently across the 20-minute match. Early waves stay readable,
# while late waves survive long enough for heroes to support the push.
const LATE_HP_SCALE := 0.28
const LATE_DMG_SCALE := 0.22
const MOBA_SCALE_TIME := 1200.0


## waypoints: reittipisteet järjestyksessä kohti vihollisen tukikohtaa.
func setup_minion(p_arena, p_team: int, pos: Vector2, waypoints: Array,
		p_lane_id: String = "", p_kind: int = Kind.MELEE) -> void:
	arena = p_arena
	team = p_team
	kind = p_kind
	lane_id = p_lane_id
	is_unit = true
	regen_disabled = true
	hero_id = "minion"
	kb_resist = 0.25

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = p_team
	profile.index = 0
	profile.hero_id = "minion"
	match kind:
		Kind.SUPER:
			profile.display_name = "Superminioni"
		Kind.MELEE:
			profile.display_name = "Etuvartio"
		_:
			profile.display_name = "Sädevahti"
	ult_gain_mult = 0.0

	if kind == Kind.SUPER:
		# Superminioni (murretun linjan palkinto): ~3x etuvartion HP, ~1.8x
		# vahinko, hieman isompi ja lähes töytäisynkestävä. Vahvempi ja
		# vaikuttava aallon kärki — ei kuitenkaan tajuton raidboss.
		max_hp = 372.0
		radius = 22.0
		base_speed = 138.0
		attack_reach = 66.0
		attack_dmg = 20.5
		cd_max.basic = 0.8
		kb_resist = 0.85
		gold_value = 40
		xp_value = 80
	elif kind == Kind.MELEE:
		max_hp = 124.0
		radius = 17.0
		base_speed = 140.0
		attack_reach = 58.0
		attack_dmg = 11.5
		cd_max.basic = 0.86
	else:
		max_hp = 86.0
		radius = 15.0
		base_speed = 134.0
		attack_reach = 255.0
		attack_dmg = 8.5
		cd_max.basic = 1.16
	var late: float = clampf(float(p_arena.match_elapsed) / MOBA_SCALE_TIME, 0.0, 1.0)
	max_hp *= 1.0 + late * LATE_HP_SCALE
	attack_dmg *= 1.0 + late * LATE_DMG_SCALE
	hp = max_hp
	_color = Palette.team(p_team).lerp(Color("d8e6ff") if p_team == 0 else Color("ffe6d0"), 0.25)
	if kind == Kind.SUPER:
		# Kristallinhohtoinen kärkiväri: erottuu aallosta mutta joukkue näkyy.
		_color = Palette.glow(Palette.team(p_team).lerp(Color("e6f6ff"), 0.35), 1.15)

	var brain := MinionBrain.new()
	brain.waypoints = waypoints
	brain.aggro_radius = 235.0
	brain.attack_range = attack_reach
	brain._retarget_timer = fposmod(absf(pos.x * 0.013 + pos.y * 0.017) + kind * 0.031,
		MinionBrain.MINION_RETARGET_INTERVAL)
	controller = brain

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	var vis := MinionVisual.new()
	vis.hero = self
	visual = vis
	add_child(vis)

	global_position = pos


func hero_color() -> Color:
	return _color


## Etuvartio lyö kilpiterällä lähietäisyydeltä. Sädevahti ampuu hitaammin
## liikkuvan, selvästi luettavan energiapultin takalinjasta.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	var foe: int = 1 - team
	var best: Hero = null
	var best_d := attack_reach + 60.0
	for h in arena.heroes:
		if not is_instance_valid(h) or not h.alive or h.team != foe:
			continue
		var to_h: Vector2 = h.global_position - global_position
		var d: float = to_h.length()
		if d > attack_reach + h.radius:
			continue
		if d < best_d:
			best_d = d
			best = h
	if best != null:
		var to_b: Vector2 = (best.global_position - global_position)
		if kind == Kind.RANGED:
			var shot_dir := to_b.normalized() if to_b.length() > 0.1 else dir
			Projectile.launch(self, global_position + shot_dir * (radius + 5.0), shot_dir, {
				"speed": 430.0,
				"dmg": attack_dmg,
				"radius": 7.0,
				"life": 1.1,
				"kb": 28.0,
				"color": _color,
				"homing_target": best,
				"homing_rate": 4.2,
				"visual": "minion_bolt",
			})
			if not Game.simulating:
				AudioMgr.play("minion_ranged", 0.07, -13.0, global_position)
		else:
			if not Game.simulating:
				AudioMgr.play("minion_melee", 0.10, -15.0, global_position)
			deal_damage_to(best, attack_dmg, 55.0, to_b.normalized())
			Fx.slash(arena, global_position, to_b.normalized(), attack_reach, 58.0, _color)
			Fx.spark(arena, best.global_position, Palette.with_alpha(_color, 0.8))


func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	set_physics_process(false)
	# CS-luku: viimeinen osuma saa minionitapon (vain oikea sankari).
	if arena != null and arena.has_method("on_minion_ko"):
		arena.on_minion_ko(self, source)
	Fx.burst(arena, global_position, _color, 8, 160.0, 0.3, 4.0)
	# Hiljainen metallinen/energinen kaato kertoo last-hitistä ilman sankari-KO:ta.
	if not Game.simulating:
		AudioMgr.play("minion_down", 0.10, -15.0, global_position)
	# Poisto arena.heroesista ja vapautus hoidetaan areenan siivouksessa
	# (turvallista iteroinnin kannalta) — ei queue_free tässä.


func _respawn() -> void:
	pass   # minionit eivät herää; aallot tuovat uusia


## MOBA on yksieräinen -> minionit eivät osallistu erän nollaukseen. Ohitetaan
## perusluokan reset (joka kutsuisi spawn_pointia); käytännössä ei koskaan kutsuta.
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	pass


## Minionin ohjain: seuraa linjaa kohti vihollistukikohtaa, hyökkää lähelle
## tulevia vihollisia (1 - team). Ei koske neutraaleihin viidakko-olentoihin.
class MinionBrain:
	extends NeutralBrain

	var waypoints: Array = []
	var _wp := 0
	var _off_lane := false
	const MINION_RETARGET_INTERVAL := 0.12

	# Kuinka läheltä liittolaischampionia puolustetaan (LoL: hyökkääjä vetää
	# aallon aggron itseensä) ja kuinka tuoreesta osumasta aggro laukeaa.
	const DEFEND_RADIUS := 240.0
	const DEFEND_WINDOW := 3.5
	const LANE_LEASH := 330.0

	func update(hero, delta: float) -> void:
		_attack = false
		_mv = Vector2.ZERO
		var pos: Vector2 = hero.global_position
		# Knockback must not turn a lane minion into a jungler. A displaced unit
		# returns to its lane before acquiring another target.
		_retarget_timer -= delta
		var target_lost := _target != null and (not is_instance_valid(_target) or not _target.alive)
		if _retarget_timer <= 0.0 or target_lost:
			_retarget_timer = MINION_RETARGET_INTERVAL
			_off_lane = _distance_to_lane(pos) > LANE_LEASH
			_target = null if _off_lane else _pick_target(hero, pos)
		var target = null if _off_lane else _target
		if target != null and is_instance_valid(target):
			var to_t: Vector2 = target.global_position - pos
			if to_t.length() > 0.5:
				_aim = to_t.normalized()
			# Lyöntietäisyyteen on laskettava kohteen säde: iso torni (r46) tai
			# nexus (r72) ei koskaan tule keskipisteiltään 58 px:n päähän
			# (törmäys estää), joten ilman sädettä minion ei ikinä lyönyt niitä.
			var reach: float = attack_range + target.radius
			if to_t.length() > reach:
				_mv = _avoid_walls(hero, to_t.normalized())
			else:
				_attack = true
			return
		_advance_lane(hero, pos)

	## Kohdevalinta LoL-tyyliin:
	##  1) Champion-aggro: sankari (pelaaja/botti) joka on hiljattain lyönyt tätä
	##     minionia TAI lähellä olevaa liittolaischampionia -> käänny sen kimppuun
	##     (leashaa takaisin linjalle kun hyökkääjä pakenee tai ikkuna umpeutuu).
	##  2) Muuten lähin vihollisyksikkö (minioni/torni) aggro-säteellä -> työnnä.
	##  3) Jos yksiköitä ei ole säteellä, lähin vihollischampion (esim. sankari
	##     tukkii aallon ilman minioneja) — muuten minion ei tekisi mitään.
	func _pick_target(hero, pos: Vector2) -> Hero:
		var champ := _aggro_champion(hero, pos)
		if champ != null:
			return champ
		var best_unit: Hero = null
		var aggro_sq := aggro_radius * aggro_radius
		var bu_sq := aggro_sq
		var best_champ: Hero = null
		var bc_sq := aggro_sq
		for h in hero.arena.heroes:
			if not is_instance_valid(h) or not h.alive:
				continue
			if h.team == hero.team or h.team > 1:
				continue   # ohita omat ja neutraalit viidakko-olennot
			# Linja on sitova myös basessa, jossa top- ja bottom-aallot lähestyvät
			# toisiaan. Minioni ei vaihda väärälle torniketjulle oikopolun vuoksi.
			if h is Minion and (h as Minion).lane_id != hero.lane_id:
				continue
			if h is Structure:
				var lane_structure := h as Structure
				if lane_structure.kind == Structure.Kind.TOWER \
						and lane_structure.lane_id != hero.lane_id:
					continue
			var d_sq: float = h.global_position.distance_squared_to(pos)
			if d_sq >= aggro_sq:
				continue
			if h.is_unit:
				# Ohita suojattu (immuuni) torni/nexus -> minioni ei jää jauhamaan
				# sisätornia jota ei voi vahingoittaa, vaan hyökkää järjestyksessä.
				if h is Structure and (h as Structure).is_protected():
					continue
				if d_sq < bu_sq:
					bu_sq = d_sq
					best_unit = h
			elif d_sq < bc_sq:
				bc_sq = d_sq
				best_champ = h
		return best_unit if best_unit != null else best_champ

	## Sankari joka provosoi tämän minionin: löi minionia (kosto) tai lähellä
	## olevaa liittolaischampionia (puolustus). Palauttaa vain sankareita (ei
	## yksiköitä). _recent_attacker hoitaa leashin ja aikaikkunan kostolle.
	func _aggro_champion(hero, pos: Vector2) -> Hero:
		var attacker := _recent_attacker(hero, pos)
		if attacker != null and not attacker.is_unit:
			return attacker
		# Peliaika pitää aggroikkunan oikean mittaisena myös nopeutetussa simissä.
		var now: float = hero.arena.match_elapsed
		for ally in hero.arena.alive_allies(hero.team):
			if ally.global_position.distance_squared_to(pos) > DEFEND_RADIUS * DEFEND_RADIUS:
				continue
			for entry in ally._recent_damagers:
				var h = entry.hero
				if not is_instance_valid(h) or not h.alive or h.is_unit:
					continue
				if h.team == hero.team:
					continue
				if now - float(entry.time) > DEFEND_WINDOW:
					continue
				var defend_leash := aggro_radius * 1.4
				if h.global_position.distance_squared_to(pos) > defend_leash * defend_leash:
					continue
				return h
		return null

	func _advance_lane(hero, pos: Vector2) -> void:
		if waypoints.is_empty():
			return
		if _wp >= waypoints.size():
			_wp = waypoints.size() - 1
		var wp: Vector2 = waypoints[_wp]
		if pos.distance_to(wp) < 95.0 and _wp < waypoints.size() - 1:
			_wp += 1
			wp = waypoints[_wp]
		var d: Vector2 = wp - pos
		if d.length() > 1.0:
			_mv = _avoid_walls(hero, d.normalized())
			_aim = _mv

	func _distance_to_lane(pos: Vector2) -> float:
		if waypoints.size() < 2:
			return 0.0
		var best_sq := INF
		for i in range(waypoints.size() - 1):
			var a: Vector2 = waypoints[i]
			var b: Vector2 = waypoints[i + 1]
			var ab := b - a
			var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
			best_sq = minf(best_sq, pos.distance_squared_to(a + ab * t))
		return sqrt(best_sq)


	## Minionien siluetit ovat tarkoituksella täysin erilaiset: etuvartio on
	## leveä kilpisoturi ja sädevahti korkea, leijuva energiampuja.
class MinionVisual:
	extends HeroVisual

	func _draw() -> void:
		if hero == null or not hero.alive:
			return
		var m := hero as Minion
		if m == null:
			return
		var r: float = hero.radius
		var col: Color = m._color
		var dark: Color = Palette.darker(col, 0.5)
		var moving: float = clampf(hero.velocity.length() / 140.0, 0.0, 1.0)
		var bob: float = sin(_time * 11.0 + hero.global_position.x * 0.05) * 1.5 * moving
		draw_set_transform(Vector2(0, r * 0.7), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, r + 2.0, Color(0.02, 0.03, 0.06, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var body := Vector2(0, -bob)
		if m.kind == Kind.RANGED:
			_draw_ranged(m, body, r, col, dark, moving)
		else:
			_draw_melee(m, body, r, col, dark, moving)
			if m.kind == Kind.SUPER:
				_draw_crown(body, r, col)
		if _flash > 0.0:
			draw_circle(body, r * 1.05, Color(1, 1, 1, _flash * 0.7))
		# Pieni HP-viiva
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		if frac < 0.999:
			draw_rect(Rect2(-r, -r - 7.0, r * 2.0, 3.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-r, -r - 7.0, r * 2.0 * frac, 3.0), Palette.glow(col, 1.1))

	func _draw_melee(_m: Minion, body: Vector2, r: float, col: Color,
			dark: Color, moving: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var stride := sin(_time * 12.0) * 2.6 * moving
		# Kaksi selvästi askeltavaa metallijalkaa.
		for sign_f in [-1.0, 1.0]:
			var sign_v: float = sign_f
			var foot := body - forward * r * 0.45 + side * sign_v * r * 0.48 \
				+ forward * stride * sign_v
			draw_circle(foot, r * 0.27, Color("17202a"))
			draw_line(foot, body + side * sign_v * r * 0.35, dark, 4.0)
		# Haarniskoitu kuusikulmiorunko ja joukkuevärinen olkalevy.
		var hull := PackedVector2Array([
			body + forward * r * 0.78,
			body + forward * r * 0.28 + side * r * 0.72,
			body - forward * r * 0.62 + side * r * 0.52,
			body - forward * r * 0.78,
			body - forward * r * 0.62 - side * r * 0.52,
			body + forward * r * 0.28 - side * r * 0.72,
		])
		draw_colored_polygon(hull, Color("151d28"))
		var armor := PackedVector2Array([
			body + forward * r * 0.63,
			body + side * r * 0.55,
			body - forward * r * 0.55,
			body - side * r * 0.55,
		])
		draw_colored_polygon(armor, col)
		draw_polyline(PackedVector2Array(Array(armor) + [armor[0]]), Palette.glow(col, 1.2), 2.0)
		# Kilpi tekee etulinjan luettavaksi jo kaukaa.
		var shield_c := body + forward * r * 0.42 + side * r * 0.67
		var shield := PackedVector2Array([
			shield_c + forward * r * 0.42,
			shield_c + side * r * 0.42,
			shield_c - forward * r * 0.42,
			shield_c - side * r * 0.42,
		])
		draw_colored_polygon(shield, Palette.darker(col, 0.25))
		draw_polyline(PackedVector2Array(Array(shield) + [shield[0]]), Palette.glow(col, 1.35), 2.0)
		# Lyhyt energiamiekka vastakkaisella puolella, pyyhkäisee hyökkäysanimaatiossa.
		var swing := clampf(_attack_anim, 0.0, 1.0)
		var blade_dir := forward.rotated((-0.65 + swing * 1.3) * (-1.0 if hero.team == 0 else 1.0))
		var hand := body - side * r * 0.62
		draw_line(hand, hand + blade_dir * r * 1.05, Palette.glow(Color("eef7ff"), 1.2), 3.0)
		draw_line(hand, hand + blade_dir * r * 0.82, Palette.glow(col, 1.45), 5.0)
		# Kypärä ja yksi selvä valoaukko.
		draw_circle(body + forward * r * 0.18, r * 0.42, dark)
		draw_line(body + forward * r * 0.43 - side * r * 0.24,
			body + forward * r * 0.43 + side * r * 0.24, Color("eaffff"), 3.0)

	## Superminionin kruunu + sykkivä kristallisärmä: kruunattu siluetti ja
	## kidehehku erottavat murretun linjan kärkiyksikön aallosta heti.
	func _draw_crown(body: Vector2, r: float, col: Color) -> void:
		var glow: Color = Palette.glow(col, 1.5)
		var top := body + Vector2(0, -r * 0.95)
		var crown := PackedVector2Array([
			top + Vector2(-r * 0.52, 0), top + Vector2(-r * 0.52, -r * 0.18),
			top + Vector2(-r * 0.30, -r * 0.02), top + Vector2(-r * 0.12, -r * 0.34),
			top + Vector2(0.0, -r * 0.06), top + Vector2(r * 0.12, -r * 0.34),
			top + Vector2(r * 0.30, -r * 0.02), top + Vector2(r * 0.52, -r * 0.18),
			top + Vector2(r * 0.52, 0),
		])
		draw_colored_polygon(crown, Color("ffd76d"))
		draw_polyline(PackedVector2Array(Array(crown) + [crown[0]]),
			Palette.with_alpha(Color("8a6a2a"), 0.8), 1.5)
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		var gem := top + Vector2(0, -r * 0.16)
		var shard := PackedVector2Array([
			gem + Vector2(0, -r * 0.2), gem + Vector2(r * 0.12, 0),
			gem + Vector2(0, r * 0.14), gem + Vector2(-r * 0.12, 0)])
		draw_colored_polygon(shard, Palette.with_alpha(glow, 0.6 + 0.3 * pulse))
		# Kevyt kidehehku koko yksikön ympärillä.
		draw_arc(body, r + 5.0, 0.0, TAU, 26, Palette.with_alpha(glow, 0.18 + 0.14 * pulse), 2.0)

	func _draw_ranged(_m: Minion, body: Vector2, r: float, col: Color,
			dark: Color, moving: float) -> void:
		var forward: Vector2 = hero.aim.normalized() if hero.aim.length() > 0.1 else Vector2.RIGHT
		var side := forward.orthogonal()
		var pulse := 0.65 + 0.35 * sin(_time * 7.0)
		# Leijuva varjo ja kaksi pientä vakautinjalkaa.
		for sign_f in [-1.0, 1.0]:
			var sign_v: float = sign_f
			var fin: Vector2 = body - forward * r * 0.58 + side * sign_v * r * 0.54
			draw_line(body - forward * r * 0.22, fin, Palette.with_alpha(col, 0.8), 3.0)
			draw_circle(fin, r * 0.18 + moving, dark)
		# Korkea prismamainen viitta/runko.
		var cloak := PackedVector2Array([
			body + forward * r * 0.72,
			body + side * r * 0.58,
			body - forward * r * 0.82 + side * r * 0.38,
			body - forward * r * 0.64 - side * r * 0.38,
			body - side * r * 0.58,
		])
		draw_colored_polygon(cloak, dark)
		draw_polyline(PackedVector2Array(Array(cloak) + [cloak[0]]), Palette.with_alpha(col, 0.85), 2.0)
		# Ydin ja orbit-renkaat kertovat välittömästi ranged/magic-roolin.
		draw_circle(body, r * (0.4 + 0.05 * pulse), Palette.with_alpha(col, 0.3))
		draw_circle(body, r * 0.24, Palette.glow(col, 1.65))
		draw_circle(body + forward * r * 0.06, r * 0.09, Color.WHITE)
		draw_arc(body, r * 0.66, _time * 2.8, _time * 2.8 + PI * 1.35, 18,
			Palette.with_alpha(Palette.glow(col, 1.3), 0.75), 2.0)
		# Pitkä emitteri osoittaa kohteeseen; lataus välähtää kärjessä.
		var emitter_base := body + side * r * 0.48
		var emitter_tip := emitter_base + forward * r * (1.1 + _attack_anim * 0.25)
		draw_line(emitter_base - forward * r * 0.35, emitter_tip, Color("202b38"), 5.0)
		draw_line(emitter_base, emitter_tip, Palette.glow(col, 1.35), 2.0)
		draw_circle(emitter_tip, r * (0.14 + 0.12 * _attack_anim),
			Palette.glow(Color.WHITE.lerp(col, 0.35), 1.5))
