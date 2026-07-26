class_name GuidedRocket
extends Node2D
## Salvon ohjattava raketti: lähtee raskaasti, kiihtyy rajusti ja kääntyy lentäjän
## syötteen mukaan sitä huonommin mitä kovempaa se jo kulkee.
## Kulkee seinien ja tornien läpi (ei fysiikkaa), osuu vain vihollisiin ja
## viidakko-olentoihin/minioneihin — ei liittolaisiin eikä rakennuksiin.
## Räjähtää kohteeseen osuessaan tai ajan loputtua, valtava aluevahinko.
## Kun raketti päättyy, se nostaa lentäjän takaisin pintaan (pilot.surface()).

var pilot: Hero = null
var arena = null
var team := 0
var speed := 175.0
var acceleration := 74.0
var max_speed := 690.0
var turn_rate := 2.45              # lähtöhetken kääntyvyys rad/s
var min_turn_rate := 0.58          # huippunopeuden raskas kääntyvyys
var life := 8.0
var hit_radius := 42.0
var blast_radius := 230.0
var dmg := 185.0
var kb := 500.0
var dmg_ramp_time := 2.0            # aika jonka lento tarvitsee täyteen tehoon
var heading := Vector2.RIGHT
var _dead := false
var _t := 0.0
var _trail: Array = []
var _start_speed := 175.0
var _owner_color := Color.WHITE
var _team_color := Color.WHITE
var _owner_number := 0


static func launch(p_pilot: Hero, pos: Vector2, dir: Vector2, cfg := {}) -> GuidedRocket:
	var r := GuidedRocket.new()
	r.pilot = p_pilot
	r.arena = p_pilot.arena
	r.team = p_pilot.team
	r.global_position = pos
	r.heading = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	r.speed = cfg.get("speed", 175.0)
	r._start_speed = r.speed
	r.acceleration = cfg.get("accel", 74.0)
	r.max_speed = cfg.get("max_speed", 690.0)
	r.turn_rate = cfg.get("turn", 2.45)
	r.min_turn_rate = cfg.get("min_turn", 0.58)
	r.life = cfg.get("life", 8.0)
	r.hit_radius = cfg.get("hit_radius", 42.0)
	r.blast_radius = cfg.get("blast", 230.0)
	r.dmg = cfg.get("dmg", 185.0)
	r.dmg_ramp_time = cfg.get("ramp", 2.0)
	r._team_color = Palette.team(p_pilot.team)
	if p_pilot.profile != null and not p_pilot.profile.is_bot:
		r._owner_color = p_pilot.profile.color()
		r._owner_number = p_pilot.profile.index + 1
	else:
		r._owner_color = r._team_color
	p_pilot.arena.add_child(r)
	return r


func _ready() -> void:
	z_index = 22
	rotation = heading.angle()
	AudioMgr.play("salvo_rocket_launch", 0.04, 0.0, global_position)


## Osuuko rakettiin: vihollisjoukkue tai viidakko-olento, ei rakennus/liittolainen.
func _is_target(h) -> bool:
	return is_instance_valid(h) and h.alive and not (h is Structure) and h.team != team


## Tehoramppi: laukaisussa lähes nolla, täysi kun lento on kiihtynyt (~ramp-ajan).
## Lähipamautus naamalle on siis heikko — raketti palkitsee pitkän ohjatun lennon.
func _power() -> float:
	return clampf(0.05 + 0.95 * (_t / maxf(dmg_ramp_time, 0.1)), 0.05, 1.0)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if pilot == null or not is_instance_valid(pilot) or not pilot.piloting:
		_detonate()   # lentäjä katosi -> räjäytä (surface hoidetaan _detonatessa)
		return
	# Erän tauko/loppu: raketti jää paikoilleen (ei räjähdä). Erän nollaus siivoaa.
	if arena == null or arena.state != arena.State.PLAY:
		return
	_t += delta
	life -= delta
	speed = minf(speed + acceleration * delta, max_speed)

	# Ohjaus: lue lentäjän liikesyöte (tai tähtäys), käänny rajoitetusti.
	var steer: Vector2 = pilot.controller.move_vector()
	if steer.length() < 0.2:
		steer = pilot.controller.aim_vector()
	if steer.length() > 0.2:
		var cur := heading.angle()
		var diff: float = wrapf(steer.angle() - cur, -PI, PI)
		var speed_frac := clampf((speed - _start_speed) / maxf(max_speed - _start_speed, 1.0), 0.0, 1.0)
		var live_turn := lerpf(turn_rate, min_turn_rate, speed_frac)
		var step: float = clampf(diff, -live_turn * delta, live_turn * delta)
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
	# Teho lennon kiihtymisen mukaan: heti räjäytetty raketti on pieni pamaus,
	# täyteen kiihtynyt tuhoisa. Myös alue, työntö ja efektit skaalautuvat.
	var power := _power()
	var blast: float = blast_radius * lerpf(0.5, 1.0, power)
	if arena != null:
		AudioMgr.play("salvo_rocket_impact", 0.03, 1.0 - (1.0 - power) * 6.0, global_position)
		arena.shake(0.25 + 0.65 * power)
		Fx.flash(arena, global_position, Palette.glow(Color("fff0a6"), 1.85), blast * 0.82, 0.68)
		Fx.ring(arena, global_position, Palette.glow(Color("ff5c28"), 1.8), blast, 0.82, 13.0)
		Fx.ring(arena, global_position, Palette.glow(Color("ffb03a"), 1.45), blast * 0.68, 0.62, 8.0)
		Fx.ring(arena, global_position, _team_color, blast * 0.42, 0.48, 4.0)
		Fx.burst(arena, global_position, Palette.glow(Color("ffd76d"), 1.75),
			int(14 + 24 * power), 520.0, 0.72, 9.0)
	if pilot != null and is_instance_valid(pilot):
		pilot._act("ult")
		# Raketin räjähdys on aluevahinkoa -> ei pure rakennuksiin.
		var prev_aoe: bool = pilot.damage_is_aoe
		pilot.damage_is_aoe = true
		for h in arena.heroes:
			if not _is_target(h):
				continue
			var d: float = h.global_position.distance_to(global_position)
			if d <= blast + h.radius:
				var away: Vector2 = (h.global_position - global_position).normalized()
				if away == Vector2.ZERO:
					away = Vector2.UP
				pilot.deal_damage_to(h, dmg * power, kb * lerpf(0.4, 1.0, power), away)
		pilot.damage_is_aoe = prev_aoe
		pilot._act_end()
		if pilot.has_method("surface"):
			pilot.surface()
	queue_free()


func _draw() -> void:
	var col := Color("d9542b")
	var speed_frac := clampf((speed - _start_speed) / maxf(max_speed - _start_speed, 1.0), 0.0, 1.0)
	# Vana
	for i in range(_trail.size()):
		var p: Vector2 = to_local(_trail[i])
		var f: float = float(i) / maxf(float(_trail.size()), 1.0)
		draw_circle(p, 5.0 + f * 8.0,
			Palette.with_alpha(Color("6e6255"), 0.10 + f * 0.28))
		if i % 2 == 0:
			draw_circle(p, 2.0 + f * 4.0,
				Palette.with_alpha(Palette.glow(Color("ffb03a"), 1.5), 0.12 + f * 0.32))
	# Raskas runko (osoittaa +X, rotation kääntää), kaksinkertainen panssarireuna.
	var body := PackedVector2Array([
		Vector2(31, 0), Vector2(13, -11), Vector2(-18, -10),
		Vector2(-24, -6), Vector2(-24, 6), Vector2(-18, 10), Vector2(13, 11)])
	draw_colored_polygon(body, Palette.darker(Color("592b20"), 0.55))
	var plate := PackedVector2Array([
		Vector2(27, 0), Vector2(10, -7.0), Vector2(-17, -7.0),
		Vector2(-19, 0), Vector2(-17, 7.0), Vector2(10, 7.0)])
	draw_colored_polygon(plate, col)
	# Kärkikartio hehkuu tehorampin mukaan: himmeä laukaisussa, kirkas täydessä
	# tehossa — lentäjä näkee suoraan koska raketti on tuhoisimmillaan.
	var power := _power()
	var tip_col: Color = Color("8a6a45").lerp(Palette.glow(Color("ffd76d"), 1.7), power)
	draw_colored_polygon(PackedVector2Array([
		Vector2(31, 0), Vector2(12, -10), Vector2(12, 10)]), tip_col)
	# Tehomittari raketin ympärillä (täyttyvä kaari omalla värillä).
	draw_arc(Vector2.ZERO, 42.0, -PI / 2.0, -PI / 2.0 + TAU * power, 30,
		Palette.with_alpha(Palette.glow(_owner_color, 1.3), 0.5 + 0.3 * power), 3.0)
	if power >= 0.999:
		draw_arc(Vector2.ZERO, 48.0, 0.0, TAU, 34,
			Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.6), 0.35 + 0.2 * sin(_t * 9.0)), 2.0)
	for x in [-12.0, -3.0, 6.0]:
		draw_line(Vector2(x, -7), Vector2(x + 6, 7), Color("4c251d"), 3.0)
	# Neljä vakainta ja joukkue-/pelaajamerkintä.
	for sy in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13, sy * 8), Vector2(-23, sy * 18), Vector2(1, sy * 9)]),
			Palette.darker(_team_color, 0.55))
	draw_line(Vector2(-8, 0), Vector2(9, 0), Palette.glow(_owner_color, 1.3), 2.5)
	if _owner_number > 0:
		for i in range(mini(_owner_number, 4)):
			draw_circle(Vector2(-7 + i * 5, 4), 1.5, Palette.glow(_owner_color, 1.5))
	# Peräliekki
	var flame: float = 15.0 + speed_frac * 22.0 + 7.0 * sin(_t * 34.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-23, -8), Vector2(-24 - flame * 0.62, 0), Vector2(-23, 8)]),
		Palette.with_alpha(Color("ff5c28"), 0.65))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-22, -5), Vector2(-22 - flame, 0), Vector2(-22, 5)]),
		Palette.with_alpha(Palette.glow(Color("ffd76d"), 1.75), 0.95))
