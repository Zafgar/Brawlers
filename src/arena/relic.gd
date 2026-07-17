class_name Relic
extends Node2D
## Relic Hold -pelimuodon kannettava reliikki. Vapaana leijuu kentällä,
## poimitaan koskettamalla. Kantaja kerää joukkueelleen pisteitä ja
## pudottaa reliikin tyrmättäessä.

const PICKUP_RADIUS := 46.0
const DROP_LOCK := 0.7

var arena = null
var carrier: Hero = null

var _time := 0.0
var _drop_lock := 0.0
var _home := Vector2.ZERO


func setup(p_arena, home: Vector2) -> void:
	arena = p_arena
	_home = home
	global_position = home
	z_index = 25


func reset_to_home() -> void:
	if carrier != null:
		carrier.carrying = false
	carrier = null
	global_position = _home
	_drop_lock = 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	_drop_lock = maxf(_drop_lock - delta, 0.0)

	if carrier != null:
		if not is_instance_valid(carrier) or not carrier.alive:
			carrier = null
		else:
			global_position = carrier.global_position + Vector2(0, -74.0 + sin(_time * 4.0) * 4.0)
	elif arena != null and arena.state == arena.State.PLAY and _drop_lock <= 0.0:
		for hero in arena.heroes:
			if not is_instance_valid(hero) or not hero.alive or hero.iframes > 1.0:
				continue
			if hero.global_position.distance_to(global_position) < PICKUP_RADIUS:
				_picked_by(hero)
				break
	queue_redraw()


func _picked_by(hero: Hero) -> void:
	carrier = hero
	hero.carrying = true
	hero.profile.stats.pickups += 1
	hero.profile.add_score(10.0)
	AudioMgr.play("pickup")
	Fx.ring(arena, global_position, Palette.glow(Palette.GOLD, 1.6), 70.0, 0.4)
	arena.popup(hero.global_position + Vector2(0, -90),
		"%s vei reliikin!" % hero.profile.display_name, Palette.GOLD, 20)
	arena.on_relic_taken(hero)


## Pudotus: tyrmäyksestä (scatter=true) tai vapaaehtoisesti (B/Ympyrä).
func drop_from_carrier(scatter := true) -> void:
	if carrier == null:
		return
	var hero := carrier
	carrier = null
	hero.carrying = false
	var drop_pos: Vector2 = hero.global_position
	if scatter:
		drop_pos += Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))
	global_position = arena.map.clamp_to_field(drop_pos, 60.0)
	_drop_lock = DROP_LOCK
	AudioMgr.play("drop")
	Fx.ring(arena, global_position, Palette.GOLD, 50.0, 0.35)
	arena.on_relic_dropped(hero)


func is_free() -> bool:
	return carrier == null


func _draw() -> void:
	var bob := sin(_time * 3.0) * 5.0 if carrier == null else 0.0
	var center := Vector2(0, -14.0 + bob)
	var pulse := 0.9 + 0.1 * sin(_time * 5.0)

	if carrier == null:
		# Varjo ja poimintakehä vapaana ollessa
		draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 16.0, Color(0.02, 0.03, 0.08, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_arc(Vector2(0, 4), PICKUP_RADIUS * pulse, 0.0, TAU, 40,
			Palette.with_alpha(Palette.GOLD, 0.35), 2.5)

	# Hehkuva timantti
	var glow_color := Palette.glow(Palette.GOLD, 1.9)
	var team_tint := glow_color
	if carrier != null:
		team_tint = Palette.glow(Palette.team(carrier.team), 1.8)
	draw_circle(center, 22.0 * pulse, Palette.with_alpha(team_tint, 0.20))
	var gem := PackedVector2Array([
		center + Vector2(0, -16), center + Vector2(12, 0),
		center + Vector2(0, 16), center + Vector2(-12, 0)])
	draw_colored_polygon(gem, team_tint)
	var inner := PackedVector2Array([
		center + Vector2(0, -8), center + Vector2(6, 0),
		center + Vector2(0, 8), center + Vector2(-6, 0)])
	draw_colored_polygon(inner, Palette.glow(Color.WHITE, 1.5))
	# Kimallus
	var spark_angle := _time * 2.0
	var spark_pos := center + Vector2(cos(spark_angle), sin(spark_angle)) * 14.0
	draw_circle(spark_pos, 2.5, Color(1, 1, 1, 0.9))
