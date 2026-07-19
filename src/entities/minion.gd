class_name Minion
extends Hero
## MOBA-minioni: heikko yksikkö joka marssii linjaa pitkin kohti vihollisen
## tukikohtaa, hyökkää matkalla vastaan tulevia vihollisia (minionit, sankarit,
## tornit). Kuuluu joukkueeseen (0/1) mutta on yksikkö (is_unit).

var attack_reach := 62.0
var attack_dmg := 9.0
var _color := Color("4aa8ff")


## waypoints: reittipisteet järjestyksessä kohti vihollisen tukikohtaa.
func setup_minion(p_arena, p_team: int, pos: Vector2, waypoints: Array) -> void:
	arena = p_arena
	team = p_team
	is_unit = true
	regen_disabled = true
	hero_id = "minion"
	kb_resist = 0.25

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = p_team
	profile.index = 0
	profile.hero_id = "minion"
	profile.display_name = "Minioni"
	ult_gain_mult = 0.0

	max_hp = 90.0
	hp = 90.0
	radius = 15.0
	base_speed = 118.0
	attack_reach = 62.0
	attack_dmg = 9.0
	cd_max.basic = 0.85
	_color = Palette.team(p_team).lerp(Color("d8e6ff") if p_team == 0 else Color("ffe6d0"), 0.25)

	var brain := MinionBrain.new()
	brain.waypoints = waypoints
	brain.aggro_radius = 235.0
	brain.attack_range = 58.0
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


## Perushyökkäys: yksittäisosuma lähimpään vihollisyksikköön edessä.
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
		deal_damage_to(best, attack_dmg, 45.0, to_b.normalized())
		Fx.spark(arena, best.global_position, Palette.with_alpha(_color, 0.8))


func _knockout(_source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	set_physics_process(false)
	Fx.burst(arena, global_position, _color, 8, 160.0, 0.3, 4.0)
	# Poisto arena.heroesista ja vapautus hoidetaan areenan siivouksessa
	# (turvallista iteroinnin kannalta) — ei queue_free tässä.


func _respawn() -> void:
	pass   # minionit eivät herää; aallot tuovat uusia


## Minionin ohjain: seuraa linjaa kohti vihollistukikohtaa, hyökkää lähelle
## tulevia vihollisia (1 - team). Ei koske neutraaleihin viidakko-olentoihin.
class MinionBrain:
	extends NeutralBrain

	var waypoints: Array = []
	var _wp := 0

	func update(hero, _delta: float) -> void:
		_attack = false
		_mv = Vector2.ZERO
		var pos: Vector2 = hero.global_position
		var foe := _nearest_foe(hero, pos)
		if foe != null:
			var to_t: Vector2 = foe.global_position - pos
			if to_t.length() > 0.5:
				_aim = to_t.normalized()
			if to_t.length() > attack_range:
				_mv = to_t.normalized()
			else:
				_attack = true
			return
		_advance_lane(pos)

	func _nearest_foe(hero, pos: Vector2) -> Hero:
		var foe_team: int = 1 - hero.team
		var best: Hero = null
		var best_d := aggro_radius
		for h in hero.arena.heroes:
			if not is_instance_valid(h) or not h.alive or h.team != foe_team:
				continue
			var d: float = h.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = h
		return best

	func _advance_lane(pos: Vector2) -> void:
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
			_mv = d.normalized()
			_aim = _mv


## Minionin ulkoasu: pieni joukkuevärinen olento.
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
		draw_circle(body, r + 1.5, dark)
		draw_circle(body, r, col)
		draw_circle(body + Vector2(-r * 0.3, -r * 0.3), r * 0.35,
			Palette.with_alpha(Color.WHITE, 0.2))
		# Silmät suuntaan
		var look: Vector2 = hero.aim * (r * 0.3)
		for side in [-1.0, 1.0]:
			var s: float = side
			var eye: Vector2 = body + Vector2(s * r * 0.35, -r * 0.1) + look
			draw_circle(eye, r * 0.22, Color(0.06, 0.03, 0.04))
			draw_circle(eye, r * 0.12, Color.WHITE)
		if _flash > 0.0:
			draw_circle(body, r, Color(1, 1, 1, _flash * 0.7))
		# Pieni HP-viiva
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		if frac < 0.999:
			draw_rect(Rect2(-r, -r - 7.0, r * 2.0, 3.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-r, -r - 7.0, r * 2.0 * frac, 3.0), Palette.glow(col, 1.1))
