class_name Structure
extends Hero
## MOBA-rakennus: torni tai nexus. Kuuluu joukkueeseen (0/1) mutta on yksikkö
## (is_unit) — jää pois pelaajakeskeisistä järjestelmistä. Periytyy Herosta,
## joten sankarien osumat/ammukset osuvat siihen normaalisti.
##
## Torni ampuu lähellä olevia vihollisia (minionit etusijalla). Nexus on voiton
## kohde: se on suojattu (haavoittumaton) kunnes sen molemmat tornit on tuhottu.

enum Kind { TOWER, NEXUS }

const SHOT_RANGE := 360.0
const SHOT_DMG := 42.0
const SHOT_INTERVAL := 1.05

var kind := Kind.TOWER
var _color := Color("4aa8ff")
var _invuln := false          # nexus: suojattu kunnes tornit kaadettu
var _shot_cd := 0.0


func setup_structure(p_arena, p_kind: int, p_team: int, pos: Vector2) -> void:
	arena = p_arena
	kind = p_kind
	team = p_team
	is_unit = true
	regen_disabled = true
	hero_id = "structure"
	kb_resist = 1.0

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = p_team
	profile.index = 0
	profile.hero_id = "structure"
	profile.display_name = _sname()
	controller = StillBrain.new()
	ult_gain_mult = 0.0

	match kind:
		Kind.TOWER:
			max_hp = 900.0
			radius = 46.0
			_shot_cd = randf_range(0.0, SHOT_INTERVAL)
		Kind.NEXUS:
			max_hp = 1600.0
			radius = 72.0
			_invuln = true
	_color = Palette.team(p_team).lerp(Color.WHITE, 0.15)
	hp = max_hp

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	var vis := StructureVisual.new()
	vis.hero = self
	visual = vis
	add_child(vis)

	global_position = pos


func _sname() -> String:
	return "Nexus" if kind == Kind.NEXUS else "Torni"


func hero_color() -> Color:
	return _color


func set_vulnerable() -> void:
	_invuln = false


## Torni ampuu: minionit etusijalla, muuten lähin vihollissankari kantamalla.
func _passive_update(delta: float) -> void:
	if kind != Kind.TOWER:
		return
	_shot_cd -= delta
	if _shot_cd > 0.0:
		return
	var target := _tower_target()
	if target == null:
		return
	_shot_cd = SHOT_INTERVAL
	var dir: Vector2 = (target.global_position - global_position).normalized()
	Projectile.launch(self, global_position + dir * (radius + 6.0), dir, {
		"speed": 880.0,
		"dmg": SHOT_DMG,
		"radius": 12.0,
		"life": 0.55,
		"kb": 40.0,
		"color": _color,
	})
	AudioMgr.play("light", 0.1, -4.0)


func _tower_target() -> Hero:
	var foe: int = 1 - team
	var best_m: Hero = null
	var bm := SHOT_RANGE
	var best_h: Hero = null
	var bh := SHOT_RANGE
	for h in arena.heroes:
		if not is_instance_valid(h) or not h.alive or h.team != foe:
			continue
		if h is Structure:
			continue
		var d: float = h.global_position.distance_to(global_position)
		if d > SHOT_RANGE:
			continue
		if h is Minion:
			if d < bm:
				bm = d
				best_m = h
		elif not h.is_unit:
			if d < bh:
				bh = d
				best_h = h
	return best_m if best_m != null else best_h


## Nexus torjuu kaiken vahingon kunnes sen tornit on kaadettu.
func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if kind == Kind.NEXUS and _invuln:
		if arena != null:
			arena.popup(global_position + Vector2(0, -radius - 22.0),
				"SUOJATTU", Palette.SHIELD, 16)
		return 0.0
	return super.take_damage(amount, source, kb, kb_dir)


## Tuho: ilmoita areenalle (voitto / nexuksen avautuminen). Ei herää henkiin.
func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	Fx.knockout_burst(arena, global_position, _color)
	Fx.ring(arena, global_position, Palette.glow(_color, 1.6), radius + 60.0, 0.9, 12.0)
	Fx.flash(arena, global_position, Palette.glow(_color, 1.5), radius + 40.0, 0.6)
	AudioMgr.play("ko", 0.1, -6.0)
	arena.shake(0.5)
	if arena.has_method("on_structure_destroyed"):
		arena.on_structure_destroyed(self, source)
	set_physics_process(false)


func _respawn() -> void:
	pass   # rakennukset pysyvät tuhottuina


## Erän alku: palauta rakennus täyteen (nexus taas suojattu).
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	hp = max_hp
	velocity = Vector2.ZERO
	respawn_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	_invuln = (kind == Kind.NEXUS)
	_shot_cd = randf_range(0.0, SHOT_INTERVAL)
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	set_physics_process(true)
	_recent_damagers.clear()


## Paikallaan pysyvä ohjain rakennuksille (ei liikettä eikä hyökkäystä).
class StillBrain:
	extends NeutralBrain

	func update(_hero, _delta: float) -> void:
		_mv = Vector2.ZERO
		_attack = false


## Rakennuksen ulkoasu (torni-spire tai nexus-kristalli) + HP-palkki.
class StructureVisual:
	extends HeroVisual

	func _draw() -> void:
		if hero == null or not hero.alive:
			return
		var s := hero as Structure
		if s == null:
			return
		var r: float = hero.radius
		var col: Color = s._color
		var dark: Color = Palette.darker(col, 0.55)
		draw_set_transform(Vector2(0, r * 0.32), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, r * 1.05, Color(0.02, 0.03, 0.06, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if s.kind == Structure.Kind.TOWER:
			_paint_tower(r, col, dark)
		else:
			_paint_nexus(s, r, col, dark)
		if _flash > 0.0:
			draw_circle(Vector2.ZERO, r, Color(1, 1, 1, _flash * 0.55))
		_hp_bar(s, r, col)

	func _paint_tower(r: float, col: Color, dark: Color) -> void:
		# Kivijalka + kapeneva torni + hehkuva kärki josta ammukset lähtevät.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 0.62, r * 0.55), Vector2(r * 0.62, r * 0.55),
			Vector2(r * 0.4, -r * 0.7), Vector2(-r * 0.4, -r * 0.7)]), dark)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 0.46, r * 0.45), Vector2(r * 0.46, r * 0.45),
			Vector2(r * 0.26, -r * 0.7), Vector2(-r * 0.26, -r * 0.7)]), col)
		draw_line(Vector2(-r * 0.3, -r * 0.1), Vector2(r * 0.3, -r * 0.1),
			Palette.with_alpha(Color.WHITE, 0.2), 2.0)
		var tip := Vector2(0, -r * 0.95)
		var pulse: float = 0.6 + 0.4 * sin(_time * 4.0)
		draw_circle(tip, r * 0.34, Palette.with_alpha(Palette.glow(col, 1.6), 0.35 + 0.3 * pulse))
		draw_circle(tip, r * 0.2, Palette.glow(col, 1.7))

	func _paint_nexus(s: Structure, r: float, col: Color, dark: Color) -> void:
		var vuln: bool = not s._invuln
		var spin: float = _time * (1.3 if vuln else 0.4)
		var ring_col: Color = Palette.glow(col, 1.5) if vuln else Palette.with_alpha(col, 0.6)
		draw_arc(Vector2.ZERO, r + 14.0, spin, spin + TAU * 0.82, 46, ring_col, 4.0)
		var pulse: float = 0.6 + 0.4 * sin(_time * (6.0 if vuln else 3.0))
		for layer in [1.3, 1.0, 0.55]:
			var sc: float = layer
			var a: float = 0.9 if sc < 0.6 else (0.45 if sc < 1.05 else 0.22)
			var dia := PackedVector2Array([
				Vector2(0, -r * sc), Vector2(r * 0.7 * sc, 0),
				Vector2(0, r * sc), Vector2(-r * 0.7 * sc, 0)])
			draw_colored_polygon(dia, Palette.with_alpha(Palette.glow(col, 1.3), a * (0.7 + 0.3 * pulse)))
		if s._invuln:
			draw_arc(Vector2.ZERO, r + 6.0, 0.0, TAU, 44,
				Palette.with_alpha(Palette.SHIELD, 0.4 + 0.2 * pulse), 3.0)

	func _hp_bar(s: Structure, r: float, col: Color) -> void:
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		var bw: float = r * 2.4
		var by: float = -r - 22.0
		UiKit.draw_text(self, Vector2(0, by - 12.0), s._sname(), 14,
			Palette.with_alpha(col, 0.9), true)
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw / 2.0, by, bw * frac, 7.0), Palette.glow(col, 1.15))
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0), Palette.with_alpha(Color.WHITE, 0.25), false, 1.0)
