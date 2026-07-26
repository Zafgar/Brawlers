class_name JungleField
extends Node2D
## Junglereiden pysyvät kentät. Mekaniikka ja piirto ovat samassa solmussa,
## jotta osuma-alue vastaa aina pelaajalle näkyvää aluetta.
##
## Neljä tilaa, yksi per kenttiä käyttävä jungleri — jokainen tekee YHDEN asian:
##   magma   (Kaira) — polttaa vihollisia, parantaa Kairaa itseään
##   magnet  (Torq)  — imee keskustaan, hidastaa ja juurruttaa pulssein
##   orchid  (Myria) — pieni kukka: polttaa vihollisia, parantaa liittolaisia
##   garden  (Myria) — ultin suuri puutarha: sama vahvempana ja laajempana

var source: Hero
var team := 0
var mode := "magma"
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


func _process(_delta: float) -> void:
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
	# Viidakkokenttä on aluevahinkoa: merkitse lippu koko tikin ajaksi. Kenttä
	# ohittaa rakennukset jo silmukassa, mutta lippu pitää säännön voimassa myös
	# jos kohdesuodatus joskus löystyy (tallenna/palauta).
	var prev_aoe: bool = false
	if acting:
		source._act(_slot)
		prev_aoe = source.damage_is_aoe
		source.damage_is_aoe = true
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
			"magma":
				# Kairan laava: polttaa vihollisia ja parantaa Kairaa itseään.
				# Kestävän lähitaistelijan fantasia näkyy suoraan maassa.
				if not ally:
					actor.apply_slow(0.78, 0.32)
					if do_tick:
						source.deal_damage_to(actor,
							dps * tick_interval * (1.35 if neutral else 1.0))
				elif actor == source and do_tick:
					actor.heal_hp(dps * tick_interval * 0.55, source)
			"magnet":
				# Torqin napakenttä: jatkuva imu keskustaan, raskas hidastus ja
				# juurrutuspulssi joka kolmas tikki. Ulos ei kävellä.
				if not ally:
					actor.apply_slow(0.52, 0.34)
					_pull(actor, 300.0 * delta)
					if do_tick:
						source.deal_damage_to(actor,
							dps * tick_interval * (1.3 if neutral else 1.0))
						if _pulse % 3 == 0:
							actor.apply_root(0.55)
			"orchid", "garden":
				# Myrian kukat: vihollisille polttoa ja hidastusta, liittolaisille
				# parannusta. Puutarha (ulti) on sama vahvempana ja laajempana.
				if not ally:
					actor.apply_slow(0.74 if mode == "orchid" else 0.66, 0.32)
					if do_tick:
						source.deal_damage_to(actor,
							dps * tick_interval * (1.3 if neutral else 1.0))
				elif not neutral and do_tick:
					actor.heal_hp(dps * tick_interval * (0.45 if mode == "orchid" else 0.6),
						source)
	if acting:
		source.damage_is_aoe = prev_aoe
		source._act_end()


## Kukinta: orkidea puhkeaa kerralla ja katoaa. Kutsutaan Myrian Kukinta-kyvyn
## sisältä, joten telemetriakonteksti (_act) on jo kutsujalla oikein.
func bloom(dmg: float, blast: float) -> bool:
	if source == null or not is_instance_valid(source) or source.arena == null:
		queue_free()
		return false
	var arena = source.arena
	Fx.ring(arena, global_position, Palette.glow(color, 1.6), blast, 0.45, 7.0)
	Fx.flash(arena, global_position, Palette.glow(Color("ffb3e6"), 1.6), 56.0, 0.3)
	Fx.burst(arena, global_position, Palette.glow(color, 1.6), 20, 340.0, 0.46, 5.5)
	# Kuusi terälehteä sinkoaa ulos: kukinta erottuu kaikista muista purkauksista.
	for i in range(6):
		var ray := Vector2.RIGHT.rotated(TAU * i / 6.0 + _age)
		Fx.beam(arena, global_position + ray * 18.0, global_position + ray * blast * 0.9,
			Palette.with_alpha(Color("ffb3e6"), 0.75), 6.0)
	AudioMgr.play("luma_bloom", 0.07, -6.0, global_position)
	var prev_aoe: bool = source.damage_is_aoe
	source.damage_is_aoe = true
	for actor in arena.heroes:
		if not is_instance_valid(actor) or not actor.alive:
			continue
		if actor is Structure or actor is Minion or actor.team == team:
			continue
		var off: Vector2 = actor.global_position - global_position
		var dist := off.length()
		if dist > blast + actor.radius:
			continue
		var away := off / dist if dist > 1.0 else Vector2.UP
		source.deal_damage_to(actor, dmg * (1.3 if actor is Critter else 1.0), 240.0, away)
		actor.apply_slow(0.62, 1.2)
	source.damage_is_aoe = prev_aoe
	queue_free()
	return true


## Jatkuva veto kohti kentän keskustaa. Siirretään sijaintia suoraan: jatkuva
## per-frame-veto häviäisi kb-kanavan kitkalle, ja velocity-lisäyksen söi
## aiemmin ohjausliikkeen move_toward -> veto ei tuntunut miltään.
## strength on jo delta-skaalattu siirtymä (px tälle framelle).
func _pull(actor: Hero, strength: float) -> void:
	if actor.grabbed_by != null or actor.dash_timer > 0.0:
		return
	var toward: Vector2 = global_position - actor.global_position
	if toward.length() > 8.0:
		actor.global_position += toward.normalized() * minf(strength, toward.length())


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
		"magma":
			# Halkeillut sulakivi: epäsäännöllinen laavalammikko ja hehkuvat railot.
			var pool := PackedVector2Array()
			for i in range(11):
				var a := TAU * i / 11.0
				var rr := radius * (0.74 + 0.2 * sin(a * 3.0 + _age * 1.6))
				pool.append(Vector2.RIGHT.rotated(a) * rr)
			draw_colored_polygon(pool, Palette.with_alpha(Palette.glow(color, 1.3),
				(0.3 + pulse * 0.14) * fade))
			for i in range(5):
				var ray := Vector2.RIGHT.rotated(TAU * i / 5.0 + _age * 0.25)
				draw_line(ray * radius * 0.12, ray * radius * 0.7,
					Palette.with_alpha(Color("fff0a8"), (0.4 + pulse * 0.3) * fade), 3.5)
			draw_circle(Vector2.ZERO, 16.0 + pulse * 6.0,
				Palette.with_alpha(Color("fff0a8"), 0.55 * fade))
		"magnet":
			# Magneettikaivo: sisäänpäin kiertyvät kenttäviivat ja kaksi napaa.
			for i in range(10):
				var a := TAU * i / 10.0 - _age * 1.3
				var pts := PackedVector2Array()
				for k in range(7):
					var f := float(k) / 6.0
					pts.append(Vector2.RIGHT.rotated(a + f * 1.15)
						* radius * lerpf(1.0, 0.14, f))
				draw_polyline(pts, Palette.with_alpha(Palette.glow(color, 1.45),
					(0.24 + pulse * 0.2) * fade), 2.5)
			for pole in [-1.0, 1.0]:
				draw_circle(Vector2(pole * radius * 0.62, 0.0), 12.0 + pulse * 4.0,
					Palette.with_alpha(Palette.glow(
						Color("ff5470") if pole > 0.0 else Color("5ac8ff"), 1.6), 0.7 * fade))
			draw_circle(Vector2.ZERO, 22.0 + pulse * 9.0,
				Palette.with_alpha(Palette.glow(color, 1.7), 0.5 * fade))
		"orchid":
			# Yksi orkidea: kuusi terälehteä, varsi ja hehkuva mesikeskus.
			_draw_flower(Vector2.ZERO, radius, fade, pulse, 1.0)
		"garden":
			# Puutarha: kehälle nousevat varret ja keskellä suuri kukka.
			for i in range(8):
				var a := TAU * i / 8.0 + _age * 0.18
				var root := Vector2.RIGHT.rotated(a) * radius * 0.92
				draw_line(root, root * 0.45,
					Palette.with_alpha(Color("7ee08a"), 0.4 * fade), 4.0)
				_draw_flower(root * 0.45, radius * 0.2, fade, pulse, 0.75)
			_draw_flower(Vector2.ZERO, radius * 0.34, fade, pulse, 1.0)


## Yhteinen kukkapiirto: kuusi terälehteä ja hehkuva mesikeskus.
func _draw_flower(at: Vector2, size: float, fade: float, pulse: float, alpha: float) -> void:
	for i in range(6):
		var a := TAU * i / 6.0 + _age * 0.4
		var ray := Vector2.RIGHT.rotated(a)
		var petal := PackedVector2Array([
			at + ray * size * 0.16,
			at + ray * size * 0.78 + ray.orthogonal() * size * 0.3,
			at + ray * size * (0.94 + pulse * 0.06),
			at + ray * size * 0.78 - ray.orthogonal() * size * 0.3])
		draw_colored_polygon(petal, Palette.with_alpha(Palette.glow(color, 1.35),
			(0.34 + pulse * 0.16) * fade * alpha))
	draw_circle(at, size * (0.2 + pulse * 0.05),
		Palette.with_alpha(Palette.glow(Color("ffb3e6"), 1.5), 0.8 * fade * alpha))
