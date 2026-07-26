class_name MortarShell
extends Node2D
## Salvon pitkän kantaman maamaali: ammus lentää korkeassa kaaressa ja antaa
## vastustajalle selvän laskeutumisvaroituksen. Hidas osuma on voimakas, mutta
## liikkuva kohde ehtii pois — tarkoituksella taitoa vaativa ennakointikyky.

var source: Hero = null
var arena = null
var team := 0
var target_position := Vector2.ZERO
var flight_time := 1.45
var blast_radius := 138.0
var dmg := 64.0
var kb := 360.0

var _origin := Vector2.ZERO
var _elapsed := 0.0
var _dead := false
var _slot := "a2"
var _owner_color := Color.WHITE
var _team_color := Color.WHITE
var _owner_number := 0


static func launch(src: Hero, target: Vector2, cfg := {}) -> MortarShell:
	var shell := MortarShell.new()
	shell.source = src
	shell.arena = src.arena
	shell.team = src.team
	shell._origin = src.global_position
	shell.target_position = target
	shell.global_position = target
	shell.flight_time = cfg.get("flight", 1.45)
	shell.blast_radius = cfg.get("blast", 138.0)
	shell.dmg = cfg.get("dmg", 64.0)
	shell.kb = cfg.get("kb", 360.0)
	shell._slot = src._cast_context if src._cast_context != "" else "a2"
	shell._team_color = Palette.team(src.team)
	if src.profile != null and not src.profile.is_bot:
		shell._owner_color = src.profile.color()
		shell._owner_number = src.profile.index + 1
	else:
		shell._owner_color = shell._team_color
	src.arena.add_child(shell)
	return shell


func _ready() -> void:
	z_index = 19
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if arena == null or arena.state != arena.State.PLAY:
		return
	_elapsed += delta
	if _elapsed >= flight_time:
		_impact()
		return
	queue_redraw()


func _is_target(unit) -> bool:
	return is_instance_valid(unit) and unit.alive and not (unit is Structure) \
		and unit.team != team


func _impact() -> void:
	if _dead:
		return
	_dead = true
	AudioMgr.play("salvo_mortar_impact", 0.05, 0.0, global_position)
	if arena != null:
		arena.shake(0.42)
		Fx.flash(arena, global_position, Palette.glow(Color("ffd46a"), 1.75),
			blast_radius * 0.78, 0.42)
		Fx.ring(arena, global_position, Palette.glow(Color("ff6b2e"), 1.7),
			blast_radius, 0.58, 9.0)
		Fx.ring(arena, global_position, _team_color, blast_radius * 0.63, 0.42, 4.0)
		Fx.burst(arena, global_position, Palette.glow(Color("ffcf65"), 1.65),
			26, 410.0, 0.58, 7.0)
	if source != null and is_instance_valid(source):
		source._act(_slot)
		# Kranaatin osuma on aluevahinkoa -> ei pure rakennuksiin.
		var prev_aoe: bool = source.damage_is_aoe
		source.damage_is_aoe = true
		for unit in arena.heroes:
			if not _is_target(unit):
				continue
			if unit.global_position.distance_to(global_position) <= blast_radius + unit.radius:
				var away: Vector2 = (unit.global_position - global_position).normalized()
				if away == Vector2.ZERO:
					away = Vector2.UP
				source.deal_damage_to(unit, dmg, kb, away)
		source.damage_is_aoe = prev_aoe
		source._act_end()
	queue_free()


func _draw() -> void:
	var progress := clampf(_elapsed / maxf(flight_time, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_elapsed * 12.0)
	# Laskeutumisalue kertoo tarkasti vaaran koon ja omistajan.
	draw_circle(Vector2.ZERO, blast_radius, Palette.with_alpha(Color("ff6b2e"), 0.07 + progress * 0.08))
	draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 64,
		Palette.with_alpha(Palette.glow(Color("ff8b3d"), 1.45), 0.45 + progress * 0.45), 3.0)
	draw_arc(Vector2.ZERO, blast_radius * (1.0 - progress * 0.86), 0.0, TAU, 48,
		Palette.with_alpha(Color("ffd46a"), 0.5 + pulse * 0.35), 2.5)
	for i in range(8):
		var tick_dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		draw_line(tick_dir * (blast_radius - 12.0), tick_dir * (blast_radius + 7.0),
			Palette.with_alpha(_team_color, 0.8), 3.0)
	if _owner_number > 0:
		for i in range(mini(_owner_number, 4)):
			var mark_x := -9.0 + i * 6.0
			draw_line(Vector2(mark_x, blast_radius + 12.0), Vector2(mark_x + 3.0, blast_radius + 18.0),
				Palette.glow(_owner_color, 1.35), 2.5)

	# Ammus liikkuu lähdöstä maaliin ja nousee näkyvästi ruudulla korkealle.
	var ground_path: Vector2 = to_local(_origin).lerp(Vector2.ZERO, progress)
	var altitude := sin(progress * PI) * 190.0
	var shell_pos := ground_path + Vector2(0.0, -altitude)
	var shadow_scale := 1.0 - sin(progress * PI) * 0.62
	draw_circle(ground_path + Vector2(0, 4), 12.0 * shadow_scale,
		Color(0.0, 0.0, 0.0, 0.18 + progress * 0.18))
	# Savupisteet tekevät kaaresta luettavan myös ruuhkassa.
	for i in range(5):
		var trail_p := maxf(progress - 0.025 * float(i + 1), 0.0)
		var trail_ground: Vector2 = to_local(_origin).lerp(Vector2.ZERO, trail_p)
		var trail_alt := sin(trail_p * PI) * 190.0
		draw_circle(trail_ground + Vector2(0, -trail_alt), 5.5 - i * 0.7,
			Color(0.66, 0.59, 0.48, 0.30 - i * 0.045))
	draw_circle(shell_pos, 9.5, Palette.darker(Color("e8722e"), 0.65))
	draw_circle(shell_pos, 6.5, Color("ff9a3d"))
	draw_line(shell_pos + Vector2(-7, 0), shell_pos + Vector2(7, 0),
		Palette.glow(Color("ffe18a"), 1.45), 3.0)
	if progress > 0.78:
		draw_line(shell_pos + Vector2(0, -15), shell_pos + Vector2(0, 18),
			Palette.with_alpha(Palette.glow(Color("fff3bd"), 1.7), progress), 3.0)
