class_name JungleField
extends Node2D
## Neljän junglerin yhteiset pysyvät kentät. Mekaniikka ja piirto ovat samassa
## solmussa, jotta osuma-alue vastaa aina pelaajalle näkyvää aluetta.

var source: Hero
var team := 0
var mode := "bore"
var variant := ""
var radius := 180.0
var duration := 5.0
var dps := 18.0
var tick_interval := 0.45
var color := Color.WHITE
var team_color := Color.WHITE

var _age := 0.0
var _tick := 0.0
var _pulse := 0
var _slot := ""
var _entered := {}


static func spawn(src: Hero, pos: Vector2, field_mode: String, cfg := {}) -> JungleField:
	var field := JungleField.new()
	field.source = src
	field.team = src.team
	field.mode = field_mode
	field.variant = str(cfg.get("variant", ""))
	field.radius = float(cfg.get("radius", 180.0))
	field.duration = float(cfg.get("dur", 5.0))
	field.dps = float(cfg.get("dps", 18.0))
	field.tick_interval = float(cfg.get("tick", 0.45))
	field.color = cfg.get("color", src.hero_color())
	field.team_color = Palette.team(src.team)
	field._slot = src._cast_context
	field.global_position = pos
	src.arena.add_child(field)
	return field


func _ready() -> void:
	z_index = 7
	Fx.ring(get_parent(), global_position, Palette.glow(color, 1.5), radius, 0.42, 5.0)


func _process(delta: float) -> void:
	if Game.simulating and not Game.sim_visuals:
		return
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	if source == null or not is_instance_valid(source) or source.arena == null:
		queue_free()
		return
	_tick -= delta
	var do_tick := _tick <= 0.0
	if do_tick:
		_tick = tick_interval
		_pulse += 1

	var arena = source.arena
	var acting := is_instance_valid(source)
	if acting:
		source._act(_slot)
	for actor in arena.heroes:
		if not is_instance_valid(actor) or not actor.alive:
			continue
		if actor is Structure or actor is Minion:
			continue
		var dist: float = actor.global_position.distance_to(global_position)
		if dist > radius + actor.radius * 0.45:
			continue
		var ally: bool = actor.team == team
		var neutral: bool = actor is Critter
		match mode:
			"bore":
				if not ally:
					actor.apply_slow(0.70, 0.32)
					_pull(actor, 145.0 * delta)
					if do_tick:
						source.deal_damage_to(actor, dps * tick_interval * (1.5 if neutral else 1.0))
			"trap":
				if not ally:
					actor.apply_slow(0.52, 0.34)
					var key: int = actor.get_instance_id()
					if not _entered.has(key):
						_entered[key] = true
						source.deal_damage_to(actor, dps * (1.35 if neutral else 1.0))
						if neutral:
							actor.apply_stun(0.9)
						else:
							actor.apply_root(0.7)
						Fx.burst(arena, actor.global_position, Palette.glow(color, 1.5), 10, 190.0, 0.35, 4.0)
					elif do_tick:
						source.deal_damage_to(actor, dps * tick_interval * 0.28)
			"grid":
				if not ally:
					actor.apply_mark(0.9, 1.18)
					if _pulse % 3 == 0:
						actor.apply_slow(0.62, 0.55)
					if do_tick:
						source.deal_damage_to(actor, dps * tick_interval * (1.25 if neutral else 1.0))
			"drone":
				if not ally:
					actor.apply_mark(0.55, 1.12)
					if neutral:
						actor.apply_slow(0.82, 0.3)
					if do_tick and neutral:
						source.deal_damage_to(actor, dps * tick_interval)
				elif actor == source:
					actor.apply_haste(1.12, 0.32)
			"essence":
				_apply_essence(actor, ally, neutral, do_tick, delta)
			"beacon":
				if not ally:
					actor.apply_slow(0.68 if neutral else 0.78, 0.32)
					_pull(actor, 105.0 * delta)
					if do_tick:
						source.deal_damage_to(actor, dps * tick_interval * (1.25 if neutral else 0.65))
						if neutral and _pulse % 2 == 0:
							actor.apply_stun(0.16)
			"fortress":
				if ally:
					actor.cc_immune_timer = maxf(actor.cc_immune_timer, 0.26)
					var akey: int = actor.get_instance_id()
					if not _entered.has(akey):
						_entered[akey] = true
						actor.add_shield(80.0 if actor == source else 58.0,
							duration - _age + 0.5, source)
				else:
					actor.apply_slow(0.72, 0.32)
					if neutral:
						_pull(actor, 70.0 * delta)
	if acting:
		source._act_end()


func _apply_essence(actor: Hero, ally: bool, neutral: bool, do_tick: bool,
		delta: float) -> void:
	match variant:
		"green":
			if ally:
				actor.apply_haste(1.14, 0.32)
				if do_tick:
					actor.heal_hp(dps * tick_interval, source)
			elif neutral and do_tick:
				# Green remains a support field in PvP, but its living energy burns
				# neutral monsters so Myria's starting essence can clear a camp.
				source.deal_damage_to(actor, dps * tick_interval * 1.2)
		"blue":
			if not ally:
				actor.apply_slow(0.48, 0.34)
				if do_tick:
					source.deal_damage_to(actor, dps * tick_interval * (1.25 if neutral else 0.75))
		"void":
			if not ally:
				actor.apply_slow(0.62, 0.34)
				_pull(actor, 125.0 * delta)
				if do_tick:
					source.deal_damage_to(actor, dps * tick_interval * (1.4 if neutral else 1.0))
		_:
			if not ally and do_tick:
				source.deal_damage_to(actor, dps * tick_interval * (1.45 if neutral else 1.0))


func _pull(actor: Hero, strength: float) -> void:
	var toward: Vector2 = global_position - actor.global_position
	if toward.length() > 8.0:
		actor.velocity += toward.normalized() * strength


func _draw() -> void:
	var fade := clampf((duration - _age) / 0.55, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_age * 7.0)
	draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.07 * fade))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72,
		Palette.with_alpha(team_color, 0.86 * fade), 3.5)
	var remain := clampf(1.0 - _age / maxf(duration, 0.01), 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius - 7.0, -PI * 0.5,
		-PI * 0.5 + TAU * remain, 64,
		Palette.with_alpha(Palette.glow(color, 1.5), 0.72 * fade), 3.0)
	match mode:
		"bore":
			for i in range(16):
				var a := TAU * i / 16.0 - _age * (0.9 if i % 2 == 0 else -0.55)
				var ray := Vector2.RIGHT.rotated(a)
				var tooth := PackedVector2Array([
					ray * radius * 0.38 + ray.orthogonal() * 10.0,
					ray * radius * (0.83 + pulse * 0.05),
					ray * radius * 0.38 - ray.orthogonal() * 10.0])
				draw_colored_polygon(tooth, Palette.with_alpha(Palette.glow(color, 1.35), 0.45 * fade))
			draw_circle(Vector2.ZERO, 25.0 + pulse * 8.0,
				Palette.with_alpha(Color("fff0a8"), 0.45 * fade))
		"trap":
			for i in range(-2, 3):
				var off := float(i) * radius * 0.28
				draw_line(Vector2(-radius * 0.78, off), Vector2(radius * 0.78, -off),
					Palette.with_alpha(color, 0.52 * fade), 2.5)
				draw_circle(Vector2(-radius * 0.78, off), 5.0, team_color)
				draw_circle(Vector2(radius * 0.78, -off), 5.0, team_color)
		"grid":
			for i in range(-3, 4):
				var off := float(i) * radius / 4.0
				draw_line(Vector2(-radius * 0.9, off), Vector2(radius * 0.9, off),
					Palette.with_alpha(color, (0.18 + pulse * 0.16) * fade), 2.0)
				draw_line(Vector2(off, -radius * 0.9), Vector2(off, radius * 0.9),
					Palette.with_alpha(color, (0.18 + pulse * 0.16) * fade), 2.0)
			for q in range(4):
				var p := Vector2.RIGHT.rotated(PI * 0.25 + q * PI * 0.5) * radius * 0.72
				draw_circle(p, 10.0 + pulse * 3.0, Palette.glow(color, 1.45))
		"drone":
			draw_arc(Vector2.ZERO, radius * (0.28 + fmod(_age * 0.45, 0.62)),
				0.0, TAU, 44, Palette.with_alpha(color, 0.5 * fade), 2.5)
			for i in range(3):
				var a := _age * 2.2 + TAU * i / 3.0
				var p := Vector2.RIGHT.rotated(a) * radius * 0.34
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, -9), p + Vector2(9, 7), p + Vector2(-9, 7)]),
					Palette.glow(color, 1.35))
		"essence":
			var ec := _essence_color()
			for i in range(4):
				var a := _age * (1.1 + i * 0.1) + TAU * i / 4.0
				var p := Vector2(cos(a), sin(a) * 0.58) * radius * (0.3 + i * 0.11)
				draw_circle(p, 9.0 + pulse * 3.0, Palette.with_alpha(Palette.glow(ec, 1.5), 0.72 * fade))
				draw_line(Vector2.ZERO, p, Palette.with_alpha(ec, 0.22 * fade), 2.0)
		"beacon":
			for i in range(6):
				var a := TAU * i / 6.0 + _age * 0.35
				var ray := Vector2.RIGHT.rotated(a)
				draw_line(ray * 30.0, ray * radius * 0.78,
					Palette.with_alpha(color, (0.3 + pulse * 0.24) * fade), 5.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -34), Vector2(24, 20), Vector2(-24, 20)]),
				Palette.with_alpha(Palette.glow(color, 1.4), 0.72 * fade))
		"fortress":
			for ring_i in range(2):
				var rr := radius * (0.55 + ring_i * 0.25)
				var poly := PackedVector2Array()
				for i in range(7):
					poly.append(Vector2.RIGHT.rotated(TAU * i / 6.0 + _age * (0.08 if ring_i == 0 else -0.05)) * rr)
				draw_polyline(poly, Palette.with_alpha(Palette.glow(color, 1.35), (0.34 + pulse * 0.16) * fade), 4.0)
			for i in range(6):
				var ray := Vector2.RIGHT.rotated(TAU * i / 6.0)
				draw_line(ray * radius * 0.58, ray * radius * 0.9,
					Palette.with_alpha(team_color, 0.62 * fade), 6.0)


func _essence_color() -> Color:
	match variant:
		"red": return Color("ff704a")
		"blue": return Color("66b7ff")
		"green": return Color("79df76")
		"void": return Color("c477ff")
	return color
