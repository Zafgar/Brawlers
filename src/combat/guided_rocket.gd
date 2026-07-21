class_name GuidedRocket
extends Node2D
## Salvon ohjattava raketti: lentää hitaasti ja kääntyy lentäjän syötteen mukaan.
## Kulkee seinien ja tornien läpi (ei fysiikkaa), osuu vain vihollisiin ja
## viidakko-olentoihin/minioneihin — ei liittolaisiin eikä rakennuksiin.
## Räjähtää kohteeseen osuessaan tai ajan loputtua, valtava aluevahinko.
## Kun raketti päättyy, se nostaa lentäjän takaisin pintaan (pilot.surface()).

var pilot: Hero = null
var arena = null
var team := 0
var speed := 270.0
var turn_rate := 3.4               # kääntyvyys rad/s (hidas, iso raketti)
var life := 8.0
var hit_radius := 42.0
var blast_radius := 215.0
var dmg := 155.0
var kb := 500.0
var heading := Vector2.RIGHT
var _dead := false
var _t := 0.0
var _trail: Array = []


static func launch(p_pilot: Hero, pos: Vector2, dir: Vector2, cfg := {}) -> GuidedRocket:
	var r := GuidedRocket.new()
	r.pilot = p_pilot
	r.arena = p_pilot.arena
	r.team = p_pilot.team
	r.global_position = pos
	r.heading = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	r.speed = cfg.get("speed", 270.0)
	r.turn_rate = cfg.get("turn", 3.4)
	r.life = cfg.get("life", 8.0)
	r.hit_radius = cfg.get("hit_radius", 42.0)
	r.blast_radius = cfg.get("blast", 215.0)
	r.dmg = cfg.get("dmg", 155.0)
	p_pilot.arena.add_child(r)
	return r


func _ready() -> void:
	z_index = 22
	rotation = heading.angle()


## Osuuko rakettiin: vihollisjoukkue tai viidakko-olento, ei rakennus/liittolainen.
func _is_target(h) -> bool:
	return is_instance_valid(h) and h.alive and not (h is Structure) and h.team != team


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if pilot == null or not is_instance_valid(pilot) or not pilot.piloting:
		_detonate()   # lentäjä katosi -> räjäytä (surface hoidetaan _detonatessa)
		return
	_t += delta
	life -= delta

	# Ohjaus: lue lentäjän liikesyöte (tai tähtäys), käänny rajoitetusti.
	var steer: Vector2 = pilot.controller.move_vector()
	if steer.length() < 0.2:
		steer = pilot.controller.aim_vector()
	if steer.length() > 0.2:
		var cur := heading.angle()
		var diff: float = wrapf(steer.angle() - cur, -PI, PI)
		var step: float = clampf(diff, -turn_rate * delta, turn_rate * delta)
		heading = Vector2.from_angle(cur + step)

	global_position += heading * speed * delta
	rotation = heading.angle()
	if arena.map != null:
		global_position = arena.map.clamp_to_field(global_position, hit_radius)

	_trail.append(global_position)
	if _trail.size() > 14:
		_trail.remove_at(0)

	for h in arena.heroes:
		if not _is_target(h):
			continue
		if h.global_position.distance_to(global_position) <= hit_radius + h.radius:
			_detonate()
			return
	if life <= 0.0:
		_detonate()
		return
	queue_redraw()


## Räjähdys: valtava aluevahinko vihollisiin/olentoihin. Nostaa lentäjän pintaan.
func _detonate() -> void:
	if _dead:
		return
	_dead = true
	if arena != null:
		AudioMgr.play("inferno", 0.05, -1.0, global_position)
		arena.shake(0.7)
		Fx.flash(arena, global_position, Palette.glow(Color("ffd76d"), 1.7), blast_radius * 0.7, 0.6)
		Fx.ring(arena, global_position, Palette.glow(Color("ff7a3a"), 1.7), blast_radius, 0.75, 11.0)
		Fx.ring(arena, global_position, Palette.with_alpha(Color("ffb03a"), 0.7), blast_radius * 0.6, 0.55, 7.0)
		Fx.burst(arena, global_position, Palette.glow(Color("ffd76d"), 1.6), 30, 460.0, 0.65, 8.0)
	if pilot != null and is_instance_valid(pilot):
		pilot._act("ult")
		for h in arena.heroes:
			if not _is_target(h):
				continue
			var d: float = h.global_position.distance_to(global_position)
			if d <= blast_radius + h.radius:
				var away: Vector2 = (h.global_position - global_position).normalized()
				if away == Vector2.ZERO:
					away = Vector2.UP
				pilot.deal_damage_to(h, dmg, kb, away)
		pilot._act_end()
		if pilot.has_method("surface"):
			pilot.surface()
	queue_free()


func _draw() -> void:
	var col := Color("ff7a3a")
	# Vana
	for i in range(_trail.size()):
		var p: Vector2 = to_local(_trail[i])
		var f: float = float(i) / maxf(float(_trail.size()), 1.0)
		draw_circle(p, 3.0 + f * 6.0, Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.4), 0.15 + f * 0.3))
	# Runko (osoittaa +X, rotation kääntää)
	var body := PackedVector2Array([
		Vector2(20, 0), Vector2(4, -8), Vector2(-14, -7),
		Vector2(-14, 7), Vector2(4, 8)])
	draw_colored_polygon(body, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(20, 0), Vector2(6, -5), Vector2(6, 5)]), Palette.glow(Color("ffd76d"), 1.5))
	# Peräliekki
	var flame: float = 10.0 + 6.0 * sin(_t * 30.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-14, -5), Vector2(-14 - flame, 0), Vector2(-14, 5)]),
		Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.6), 0.9))
