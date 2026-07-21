class_name Zone
extends Node2D
## Kentällä vaikuttava alue: tulilammikko, hoitokehä, piikkipuutarha,
## hidastusalue, hastealue tai suojakupoli (dome).
##
## Käyttö:  Zone.spawn(sankari, sijainti, { "type": "fire", "radius": 90, ... })
## Tyypit: "fire" (dps), "heal" (heal_ps), "slow" (slow_f), "thorn" (dps+slow),
##         "haste" (haste_f liittolaisille), "dome" (torjuu vihollisammukset).

var source: Hero = null
var team := 0
var type := "fire"
var radius := 90.0
var duration := 4.0
var dps := 12.0
var heal_ps := 14.0
var slow_f := 0.6
var haste_f := 1.3
var tick_interval := 0.4
var color := Color.WHITE

var _age := 0.0
var _tick_timer := 0.0
var _seed := 0.0
var _slot := ""                # mikä kykypaikka loi tämän alueen (telemetria)


static func spawn(src: Hero, pos: Vector2, cfg := {}) -> Zone:
	var z := Zone.new()
	z.source = src
	z._slot = src._cast_context   # luoneen kyvyn slot (asetettu dispatchissa)
	z.team = src.team
	z.global_position = pos
	z.type = cfg.get("type", "fire")
	z.radius = cfg.get("radius", 90.0)
	z.duration = cfg.get("dur", 4.0)
	z.dps = cfg.get("dps", 12.0)
	z.heal_ps = cfg.get("heal_ps", 14.0)
	z.slow_f = cfg.get("slow_f", 0.6)
	z.haste_f = cfg.get("haste_f", 1.3)
	z.tick_interval = cfg.get("tick", 0.4)
	z.color = cfg.get("color", z._default_color())
	src.arena.add_zone(z)
	return z


func _default_color() -> Color:
	match type:
		"fire":
			return Color("ff8a4a")
		"heal":
			return Palette.HEAL
		"slow":
			return Color("9adfff")
		"thorn":
			return Color("7ed957")
		"haste":
			return Palette.GOLD
		"dome":
			return Palette.SHIELD
		"shock":
			return Color("ffe14a")
		"hush":
			return Color("a678f0")
	return Color.WHITE


func _ready() -> void:
	z_index = 5
	_seed = randf() * 100.0
	Fx.ring(get_parent(), global_position, Palette.glow(color, 1.4), radius, 0.35)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return

	var arena = source.arena if source != null and is_instance_valid(source) else null
	if arena == null:
		queue_free()
		return

	_tick_timer -= delta
	var do_tick := _tick_timer <= 0.0
	if do_tick:
		_tick_timer = tick_interval

	# Aseta luoneen kyvyn konteksti alueen vaikutusten ajaksi (telemetria:
	# alueen slow/vahinko/paranukset kirjautuvat oikealle kykypaikalle).
	var acting: bool = source != null and is_instance_valid(source)
	if acting:
		source._act(_slot)
	for hero in arena.heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		if hero.global_position.distance_to(global_position) > radius + hero.radius * 0.5:
			continue
		var is_ally: bool = hero.team == team
		match type:
			"fire":
				if not is_ally and do_tick:
					source.deal_damage_to(hero, dps * tick_interval, 0.0,
						(hero.global_position - global_position).normalized())
			"thorn":
				if not is_ally:
					hero.apply_slow(slow_f, 0.3)
					if do_tick:
						source.deal_damage_to(hero, dps * tick_interval, 0.0,
							(hero.global_position - global_position).normalized())
			"slow":
				if not is_ally:
					hero.apply_slow(slow_f, 0.3)
			"shock":
				if not is_ally:
					hero.apply_slow(slow_f, 0.3)
					if do_tick:
						source.deal_damage_to(hero, dps * tick_interval, 0.0,
							(hero.global_position - global_position).normalized())
			"hush":
				# Dissonanssikenttä (Hush): hidastaa voimakkaasti + kalvaa DoT.
				if not is_ally:
					hero.apply_slow(slow_f, 0.3)
					if do_tick:
						source.deal_damage_to(hero, dps * tick_interval, 0.0,
							(hero.global_position - global_position).normalized())
			"heal":
				if is_ally and do_tick:
					hero.heal_hp(heal_ps * tick_interval, source)
			"haste":
				if is_ally:
					hero.apply_haste(haste_f, 0.3)
			"dome":
				pass  # kupolin torjunta hoidetaan Projectile-luokassa
	if acting:
		source._act_end()

	queue_redraw()


func _draw() -> void:
	var fade := 1.0
	if duration - _age < 0.6:
		fade = (duration - _age) / 0.6
	var pulse := 0.9 + 0.1 * sin(_age * 6.0 + _seed)

	match type:
		"dome":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.10 * fade))
			draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 64,
				Palette.with_alpha(Palette.glow(color, 1.5), 0.75 * fade), 4.0)
			draw_arc(Vector2.ZERO, radius * 0.92, 0.0, TAU, 64,
				Palette.with_alpha(color, 0.25 * fade), 2.0)
		"fire":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.18 * fade))
			for i in range(6):
				var ang: float = _seed + _age * 1.5 + TAU * i / 6.0
				var p := Vector2(cos(ang), sin(ang)) * radius * 0.55
				var h := 10.0 + sin(_age * 8.0 + i * 2.0) * 5.0
				var flame := PackedVector2Array([
					p + Vector2(-6, 4), p + Vector2(0, -h), p + Vector2(6, 4)])
				draw_colored_polygon(flame,
					Palette.with_alpha(Palette.glow(Color("ffb347"), 1.5), 0.7 * fade))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48,
				Palette.with_alpha(color, 0.5 * fade), 3.0)
		"heal", "haste":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.13 * fade))
			draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 48,
				Palette.with_alpha(Palette.glow(color, 1.4), 0.6 * fade), 3.0)
			for i in range(4):
				var ang2: float = _age * 1.2 + TAU * i / 4.0
				var p2 := Vector2(cos(ang2), sin(ang2)) * radius * 0.6
				draw_line(p2 + Vector2(-5, 0), p2 + Vector2(5, 0),
					Palette.with_alpha(color, 0.8 * fade), 3.0)
				draw_line(p2 + Vector2(0, -5), p2 + Vector2(0, 5),
					Palette.with_alpha(color, 0.8 * fade), 3.0)
		"thorn":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(Color("2f7a33"), 0.20 * fade))
			for i in range(10):
				var ang3: float = _seed + TAU * i / 10.0
				var p3 := Vector2(cos(ang3), sin(ang3)) * radius * (0.3 + 0.55 * fmod(_seed * (i + 1), 1.0))
				var thorn := PackedVector2Array([
					p3 + Vector2(-5, 3), p3 + Vector2(0, -12), p3 + Vector2(5, 3)])
				draw_colored_polygon(thorn, Palette.with_alpha(color, 0.85 * fade))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48,
				Palette.with_alpha(color, 0.4 * fade), 3.0)
		"slow":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.15 * fade))
			draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 6,
				Palette.with_alpha(Palette.glow(color, 1.3), 0.6 * fade), 3.0)
		"shock":
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.14 * fade))
			draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 40,
				Palette.with_alpha(Palette.glow(color, 1.4), 0.5 * fade), 2.5)
			# Rätisevät sähkökaaret keskeltä reunalle
			for i in range(5):
				var base_ang: float = _seed + _age * 4.0 + TAU * i / 5.0
				var pts := PackedVector2Array([Vector2.ZERO])
				for seg in range(1, 5):
					var t := seg / 4.0
					var jitter: float = sin(_age * 30.0 + i * 7.0 + seg * 2.0) * radius * 0.08
					var along := Vector2(cos(base_ang), sin(base_ang)) * radius * t
					pts.append(along + Vector2(cos(base_ang + PI / 2.0),
						sin(base_ang + PI / 2.0)) * jitter)
				draw_polyline(pts, Palette.with_alpha(Palette.glow(color, 1.6), 0.7 * fade), 2.0)
		"hush":
			# Vaimentava dissonanssi: sisäänpäin supistuvat kaikurenkaat.
			draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.13 * fade))
			for i in range(4):
				var rf: float = fmod(_age * 0.6 + i / 4.0, 1.0)
				var rr: float = radius * (1.0 - rf)
				draw_arc(Vector2.ZERO, rr, 0.0, TAU, 44,
					Palette.with_alpha(Palette.glow(color, 1.4), (0.5 - rf * 0.4) * fade), 2.5)
			draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 44,
				Palette.with_alpha(Palette.glow(color, 1.3), 0.5 * fade), 3.0)
