class_name Fx
## Kertakäyttöiset visuaaliefektit: purskeet, renkaat, välähdykset, pöly.
## Kaikki syntyvät koodista ja siivoavat itsensä pois.


static func _disabled() -> bool:
	return Game.simulating and not Game.sim_visuals


## Lyhytikäisiä efektejä ei tarvitse edes luoda, jos ne eivät voi näkyä yhdessäkään
## paikallisessa viewportissa. Näkyvään taisteluun ei kosketa lainkaan.
static func _visible(parent: Node, pos: Vector2, margin := 240.0) -> bool:
	var cursor := parent
	while cursor != null:
		if cursor.has_method("visual_position_active"):
			return cursor.visual_position_active(pos, margin)
		cursor = cursor.get_parent()
	return true


static func _line_visible(parent: Node, from: Vector2, to: Vector2, margin := 160.0) -> bool:
	return _visible(parent, (from + to) * 0.5, from.distance_to(to) * 0.5 + margin)


static func burst(parent: Node, pos: Vector2, color: Color, amount := 14,
		speed := 260.0, life := 0.5, size := 6.0) -> void:
	if _disabled() or not _visible(parent, pos, maxf(180.0, size * 4.0)):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 30
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 1.1
	p.damping_max = speed * 2.2
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color = color
	var g := Gradient.new()
	g.colors = PackedColorArray([color, Palette.with_alpha(color, 0.0)])
	p.color_ramp = g
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static func ring(parent: Node, pos: Vector2, color: Color, max_radius := 60.0,
		duration := 0.4, width := 5.0) -> void:
	if _disabled() or not _visible(parent, pos, max_radius + width + 80.0):
		return
	var node := RingFx.new()
	node.position = pos
	node.color = color
	node.max_radius = max_radius
	node.duration = duration
	node.width = width
	parent.add_child(node)


## Pyörre (esim. Tiden vesipyörre): kierteiset varret imevät keskelle + hehkuva
## ydin. Näyttää selvästi missä tainnutus/imu tapahtuu.
static func vortex(parent: Node, pos: Vector2, color: Color, radius := 120.0,
		duration := 0.9) -> void:
	if _disabled() or not _visible(parent, pos, radius + 90.0):
		return
	var node := VortexFx.new()
	node.position = pos
	node.color = color
	node.radius = radius
	node.duration = duration
	parent.add_child(node)


static func flash(parent: Node, pos: Vector2, color: Color, radius := 40.0,
		duration := 0.25) -> void:
	if _disabled() or not _visible(parent, pos, radius + 80.0):
		return
	var node := FlashFx.new()
	node.position = pos
	node.color = color
	node.radius = radius
	node.duration = duration
	parent.add_child(node)


static func spark(parent: Node, pos: Vector2, color: Color) -> void:
	burst(parent, pos, Palette.glow(color, 1.5), 8, 220.0, 0.3, 4.0)


## Sankarikohtainen osuma erottaa valon, tulen ja raskaan iskun myös ruuhkassa.
static func ability_impact(parent: Node, pos: Vector2, visual_id: String, color: Color,
		owner_color: Color, team_color: Color) -> void:
	match visual_id:
		"tower_bolt":
			flash(parent, pos, Palette.glow(Color("ff4652"), 1.6), 38.0, 0.18)
			ring(parent, pos, team_color, 48.0, 0.28, 3.0)
			burst(parent, pos, Palette.glow(team_color, 1.45), 12, 250.0, 0.32, 4.0)
		"minion_bolt":
			flash(parent, pos, Palette.glow(color, 1.35), 17.0, 0.14)
			burst(parent, pos, color, 5, 125.0, 0.2, 2.0)
		"kaira_harpoon":
			flash(parent, pos, Palette.glow(Color("ffd45a"), 1.55), 32.0, 0.18)
			ring(parent, pos, team_color, 42.0, 0.28, 3.5)
			burst(parent, pos, Color("d79a42"), 11, 260.0, 0.36, 4.0)
		"torq_hook":
			# Magneettinen napsahdus: kaksi napavälähdystä ja teräskipinät.
			flash(parent, pos, Palette.glow(Color("5ac8ff"), 1.6), 34.0, 0.2)
			ring(parent, pos, Palette.glow(Color("ff5470"), 1.5), 46.0, 0.3, 3.5)
			burst(parent, pos, Color("c3ccdf"), 12, 250.0, 0.34, 4.0)
		"vesper_bolt":
			burst(parent, pos, Palette.glow(color, 1.45), 6, 170.0, 0.22, 2.5)
		"vesper_tracker":
			flash(parent, pos, Palette.glow(Color("d9ff8f"), 1.65), 34.0, 0.2)
			ring(parent, pos, team_color, 50.0, 0.34, 3.0)
			burst(parent, pos, color, 10, 220.0, 0.3, 3.0)
		"vesper_exec":
			# Teloitusosuma: terävä valkoinen välähdys ja fosforisuihku.
			flash(parent, pos, Color.WHITE, 40.0, 0.16)
			flash(parent, pos, Palette.glow(Color("b8ff3d"), 1.7), 56.0, 0.26)
			ring(parent, pos, Palette.glow(Color("b8ff3d"), 1.5), 62.0, 0.32, 4.0)
			burst(parent, pos, Palette.glow(color, 1.6), 16, 320.0, 0.36, 4.5)
		"myria_wisp":
			ring(parent, pos, Palette.glow(color, 1.45), 30.0, 0.25, 2.5)
			burst(parent, pos, color, 7, 140.0, 0.3, 3.0)
		"myria_thread":
			flash(parent, pos, Palette.glow(color, 1.6), 38.0, 0.22)
			ring(parent, pos, team_color, 48.0, 0.32, 3.0)
			burst(parent, pos, Color.WHITE, 9, 190.0, 0.3, 2.5)
		"salvo_grenade":
			flash(parent, pos, Palette.glow(Color("ffb03a"), 1.5), 26.0, 0.18)
			burst(parent, pos, Palette.glow(Color("ff7a32"), 1.55), 11, 230.0, 0.34, 4.5)
			ring(parent, pos, team_color, 32.0, 0.24, 2.5)
		"quill_arrow", "quill_super":
			burst(parent, pos, Palette.glow(Palette.GOLD, 1.5),
				14 if visual_id == "quill_super" else 7, 250.0, 0.34, 3.5)
		"blink_blade":
			burst(parent, pos, Palette.glow(Color("d9c8ff"), 1.6), 9, 250.0, 0.28, 3.0)
		"volt_arc":
			bolt(parent, pos - Vector2(18, 10), pos + Vector2(18, 10), Palette.glow(Color("ffe14a"), 1.6))
			burst(parent, pos, Color("fff18a"), 8, 210.0, 0.25, 2.5)
		"shade_disc":
			ring(parent, pos, Palette.glow(color, 1.45), 38.0, 0.27, 3.5)
			burst(parent, pos, Color("44265e"), 10, 230.0, 0.32, 4.0)
		"scout_bullet":
			burst(parent, pos, Palette.glow(color, 1.35), 5, 150.0, 0.18, 2.0)
		"scout_mark":
			ring(parent, pos, Palette.glow(Palette.GOLD, 1.6), 48.0, 0.32, 3.0)
			burst(parent, pos, Palette.GOLD, 8, 180.0, 0.28, 2.5)
		"scout_stun":
			flash(parent, pos, Color(0.82, 0.94, 1.0, 0.8), 38.0, 0.22)
			ring(parent, pos, Color("80d8ff"), 44.0, 0.3, 3.0)
		"maestro_note":
			ring(parent, pos, Palette.glow(color, 1.4), 42.0, 0.3, 3.0)
			burst(parent, pos, owner_color, 6, 145.0, 0.3, 2.5)
		"hush_wave", "hush_field_seed":
			for wave_r in [28.0, 42.0, 56.0]:
				ring(parent, pos, Palette.with_alpha(color, 0.7), wave_r, 0.32, 2.0)
		"prism_shard":
			flash(parent, pos, Palette.glow(color, 1.55), 30.0, 0.2)
			burst(parent, pos, Color.WHITE, 8, 190.0, 0.3, 2.5)
		"bramble_vine":
			burst(parent, pos, Palette.glow(Color("7ed957"), 1.45), 9, 180.0, 0.34, 3.5)
			ring(parent, pos, team_color, 34.0, 0.28, 2.0)
		"luma_pulse":
			ring(parent, pos, Palette.glow(Palette.HEAL, 1.5), 42.0, 0.32, 3.5)
			burst(parent, pos, Palette.glow(Palette.GOLD, 1.6), 10, 170.0, 0.42, 4.0)
		"ember_bolt", "ember_seed":
			flash(parent, pos, Palette.glow(Color("ff8a4a"), 1.5), 30.0, 0.2)
			burst(parent, pos, Palette.glow(Color("ffb347"), 1.7), 13, 260.0, 0.42, 5.0)
			ring(parent, pos, team_color, 36.0, 0.27, 2.5)
		_:
			spark(parent, pos, color)
	if owner_color != team_color:
		burst(parent, pos, Palette.glow(owner_color, 1.35), 4, 125.0, 0.3, 3.0)


## Lyhyt sankarikohtainen laukaisuglyyfi. Muoto kertoo kyvyn perheen, ulkokehä
## joukkueen ja pieni värikaari paikallisen pelaajan.
static func cast_signature(parent: Node, pos: Vector2, dir: Vector2, visual_id: String,
		main_color: Color, owner_color: Color, team_color: Color, size := 90.0) -> void:
	if _disabled() or not _visible(parent, pos, size + 100.0):
		return
	var node := SignatureFx.new()
	node.position = pos
	node.direction = dir.normalized() if dir.length() > 0.1 else Vector2.RIGHT
	node.visual_id = visual_id
	node.main_color = main_color
	node.owner_color = owner_color
	node.team_color = team_color
	node.size = size
	node.life = 0.72 if size >= 180.0 else 0.38
	parent.add_child(node)


## Ultin vaaravyöhyke ennen osumaa. Supistuva ulkorengas kertoo tarkasti milloin
## vaikutus laukeaa; joukkuevärinen reuna kertoo kenen alue on kyseessä.
static func ultimate_warning(parent: Node, pos: Vector2, color: Color, team_color: Color,
		radius: float, duration := 0.45, style := "generic") -> void:
	if _disabled() or not _visible(parent, pos, radius + 120.0):
		return
	var node := UltimateTargetFx.new()
	node.position = pos
	node.color = color
	node.team_color = team_color
	node.radius = radius
	node.duration = duration
	node.style = style
	parent.add_child(node)


## Ultin aktiivinen alue jää näkyviin koko vaikutuksen ajaksi.
static func ultimate_field(parent: Node, pos: Vector2, color: Color, team_color: Color,
		radius: float, duration: float, style := "generic") -> void:
	if _disabled():
		return
	var node := UltimateFieldFx.new()
	node.position = pos
	node.color = color
	node.team_color = team_color
	node.radius = radius
	node.duration = duration
	node.style = style
	parent.add_child(node)


## Leveän läpäisyultin todellinen osumakäytävä ennen laukeamista.
static func ultimate_line_warning(parent: Node, from: Vector2, to: Vector2, color: Color,
		team_color: Color, half_width: float, duration := 0.32) -> void:
	if _disabled() or not _line_visible(parent, from, to, half_width + 120.0):
		return
	var node := UltimateLineFx.new()
	node.from_point = from
	node.to_point = to
	node.color = color
	node.team_color = team_color
	node.half_width = half_width
	node.duration = duration
	parent.add_child(node)


static func dust(parent: Node, pos: Vector2) -> void:
	burst(parent, pos + Vector2(0, 8), Color(0.8, 0.82, 0.9, 0.35), 6, 90.0, 0.4, 5.0)


static func heal_sparkle(parent: Node, pos: Vector2) -> void:
	if _disabled() or not _visible(parent, pos, 180.0):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 30
	p.amount = 8
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector2.UP
	p.spread = 40.0
	p.gravity = Vector2(0, -160)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	p.color = Palette.glow(Palette.HEAL, 1.4)
	var g := Gradient.new()
	g.colors = PackedColorArray([Palette.HEAL, Palette.with_alpha(Palette.HEAL, 0.0)])
	p.color_ramp = g
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Lähitaistelun sivallus: nopeasti pyyhkäisevä hehkuva kaari.
static func slash(parent: Node, pos: Vector2, dir: Vector2, reach: float,
		arc_deg: float, color: Color) -> void:
	if _disabled() or not _visible(parent, pos, reach + 100.0):
		return
	var node := SlashFx.new()
	node.position = pos
	node.center_angle = dir.angle()
	node.reach = reach
	node.half_arc = deg_to_rad(arc_deg)
	node.color = color
	parent.add_child(node)


## Suora hehkuva valosäde kahden pisteen välille (parannus, kilpi, merkintä).
static func beam(parent: Node, from: Vector2, to: Vector2, color: Color, width := 6.0) -> void:
	if _disabled() or not _line_visible(parent, from, to, width + 100.0):
		return
	var node := BeamFx.new()
	node.from_point = from
	node.to_point = to
	node.color = color
	node.width = width
	parent.add_child(node)


## Salamakaari kahden pisteen välille (Voltin ketjusalamat).
static func bolt(parent: Node, from: Vector2, to: Vector2, color: Color) -> void:
	if _disabled() or not _line_visible(parent, from, to, 120.0):
		return
	var node := BoltFx.new()
	node.from_point = from
	node.to_point = to
	node.color = color
	parent.add_child(node)


## Tyrmäys: pehmeä valopurkaus (ei verta, hahmo "poksahtaa" valoksi).
static func knockout_burst(parent: Node, pos: Vector2, color: Color) -> void:
	flash(parent, pos, Palette.glow(color, 1.6), 70.0, 0.35)
	ring(parent, pos, Palette.glow(Color.WHITE, 1.4), 90.0, 0.45, 7.0)
	burst(parent, pos, Palette.glow(color, 1.8), 22, 420.0, 0.7, 7.0)
	burst(parent, pos, Color(1, 1, 1, 0.9), 10, 300.0, 0.5, 4.0)


class BeamFx:
	extends Node2D
	var from_point := Vector2.ZERO
	var to_point := Vector2.ZERO
	var color := Color.WHITE
	var width := 6.0
	var _t := 0.0
	const LIFE := 0.35

	func _ready() -> void:
		z_index = 23

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f: float = clampf(_t / LIFE, 0.0, 1.0)
		var alpha := 1.0 - f
		draw_line(from_point, to_point, Palette.with_alpha(Palette.glow(color, 1.4), alpha),
			width * (1.0 - f * 0.5))
		draw_line(from_point, to_point, Palette.with_alpha(Color.WHITE, alpha * 0.6), width * 0.35)
		draw_circle(to_point, width * (1.0 - f), Palette.with_alpha(color, alpha * 0.8))


class SlashFx:
	extends Node2D
	var center_angle := 0.0
	var reach := 90.0
	var half_arc := 0.6
	var color := Color.WHITE
	var _t := 0.0
	const LIFE := 0.22

	func _ready() -> void:
		z_index = 22

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f: float = clampf(_t / LIFE, 0.0, 1.0)
		# Kaari pyyhkäisee toisesta reunasta toiseen ja ohenee.
		var sweep := lerpf(-half_arc, half_arc, f)
		var lead := center_angle + sweep
		var alpha := (1.0 - f)
		# Terä
		var pts := PackedVector2Array()
		for i in range(8):
			var t := i / 7.0
			var a := lerpf(lead - 0.5, lead, t)
			var rad := reach * (0.7 + 0.3 * t)
			pts.append(Vector2(cos(a), sin(a)) * rad)
		draw_polyline(pts, Palette.with_alpha(Palette.glow(color, 1.5), alpha), 6.0 * (1.0 - f * 0.5))
		# Häntävana koko kaaren yli
		var trail := PackedVector2Array()
		for i in range(12):
			var a := lerpf(center_angle - half_arc, lead, i / 11.0)
			trail.append(Vector2(cos(a), sin(a)) * reach * 0.92)
		draw_polyline(trail, Palette.with_alpha(color, alpha * 0.4), 3.0)


class BoltFx:
	extends Node2D
	var from_point := Vector2.ZERO
	var to_point := Vector2.ZERO
	var color := Color.WHITE
	var _points := PackedVector2Array()
	var _t := 0.0
	const LIFE := 0.18

	func _ready() -> void:
		z_index = 31
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var segments := 6
		_points.append(from_point)
		for i in range(1, segments):
			var along: Vector2 = from_point.lerp(to_point, float(i) / segments)
			var normal: Vector2 = (to_point - from_point).orthogonal().normalized()
			_points.append(along + normal * rng.randf_range(-16.0, 16.0))
		_points.append(to_point)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade: float = 1.0 - _t / LIFE
		draw_polyline(_points, Palette.with_alpha(Palette.glow(color, 1.8), fade), 3.5 * fade)
		draw_circle(to_point, 6.0 * fade, Palette.with_alpha(Color.WHITE, fade * 0.8))


class VortexFx:
	extends Node2D
	var color := Color("4ad4ff")
	var radius := 120.0
	var duration := 0.9
	var arms := 4
	var _t := 0.0

	func _ready() -> void:
		z_index = 29

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f: float = clampf(_t / duration, 0.0, 1.0)
		var a: float = (1.0 - f) * 0.9
		var spin: float = _t * 10.0
		# Ulkorengas (litistetty top-down-perspektiiviin).
		draw_arc(Vector2.ZERO, radius * (0.55 + 0.45 * (1.0 - f)), 0.0, TAU, 40,
			Palette.with_alpha(color, a * 0.45), 4.0)
		# Kierteiset varret imevät keskelle.
		for arm in range(arms):
			var base: float = TAU * float(arm) / float(arms) + spin
			var pts := PackedVector2Array()
			for i in range(23):
				var tt: float = float(i) / 22.0
				var rr: float = radius * (1.0 - tt) * (0.4 + 0.6 * (1.0 - f))
				var ang: float = base + tt * 3.6
				pts.append(Vector2(cos(ang), sin(ang) * 0.72) * rr)
			draw_polyline(pts, Palette.with_alpha(Palette.glow(color, 1.4), a), 3.0)
		# Hehkuva ydin.
		draw_circle(Vector2.ZERO, radius * 0.13 * (0.7 + 0.3 * sin(_t * 22.0)),
			Palette.with_alpha(Color("bfeaf7"), a))


class RingFx:
	extends Node2D
	var color := Color.WHITE
	var max_radius := 60.0
	var duration := 0.4
	var width := 5.0
	var _t := 0.0

	func _ready() -> void:
		z_index = 30

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f: float = clampf(_t / duration, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - f, 3.0)
		var r: float = max_radius * eased
		if r < 1.0:
			return
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48,
			Palette.with_alpha(color, (1.0 - f)), width * (1.0 - f * 0.6))


class FlashFx:
	extends Node2D
	var color := Color.WHITE
	var radius := 40.0
	var duration := 0.25
	var _t := 0.0

	func _ready() -> void:
		z_index = 29

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f: float = clampf(_t / duration, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius * (0.6 + f * 0.4),
			Palette.with_alpha(color, (1.0 - f) * 0.55))
		draw_circle(Vector2.ZERO, radius * 0.45 * (1.0 - f * 0.5),
			Palette.with_alpha(Color.WHITE, (1.0 - f) * 0.7))


class SignatureFx:
	extends Node2D
	var direction := Vector2.RIGHT
	var visual_id := "generic"
	var main_color := Color.WHITE
	var owner_color := Color.WHITE
	var team_color := Color.WHITE
	var size := 90.0
	var _t := 0.0
	var life := 0.38

	func _ready() -> void:
		z_index = 28

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f := clampf(_t / life, 0.0, 1.0)
		var alpha := 1.0 - f
		var reach := size * (0.45 + f * 0.55)
		var a := direction.angle()
		draw_arc(Vector2.ZERO, reach * 0.48, 0.0, TAU, 32,
			Palette.with_alpha(team_color, alpha * 0.75), 2.5)
		draw_arc(Vector2.ZERO, reach * 0.58, a - 0.3, a + 0.3, 10,
			Palette.with_alpha(Palette.glow(owner_color, 1.4), alpha), 3.5)
		match visual_id:
			"hush":
				for j in range(3):
					var rr: float = reach * (0.25 + j * 0.17)
					draw_arc(Vector2.ZERO, rr, a - 2.45, a + 2.45, 30,
						Palette.with_alpha(Palette.glow(main_color, 1.45), alpha * (0.9 - j * 0.18)), 3.0)
			"volt":
				for j in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * j / 8.0 + f * 0.3)
					var mid := ray * reach * 0.38 + ray.orthogonal() * (7.0 if j % 2 == 0 else -7.0)
					draw_polyline(PackedVector2Array([ray * reach * 0.12, mid, ray * reach * 0.7]),
						Palette.with_alpha(Palette.glow(main_color, 1.7), alpha), 4.0)
			"tide":
				for j in range(3):
					var rr := reach * (0.28 + j * 0.18)
					draw_arc(direction * reach * 0.12, rr, a - 1.05, a + 1.05, 22,
						Palette.with_alpha(Palette.glow(main_color, 1.55), alpha * (1.0 - j * 0.18)), 5.0)
			"quill":
				var side := direction.orthogonal()
				var head := direction * reach * 0.82
				draw_line(-direction * reach * 0.16, head, Palette.with_alpha(Palette.glow(main_color, 1.6), alpha), 5.0)
				draw_polyline(PackedVector2Array([head - direction * 24.0 + side * 18.0, head, head - direction * 24.0 - side * 18.0]),
					Palette.with_alpha(Color.WHITE, alpha * 0.85), 5.0)
			"boulder", "obsidian":
				for j in range(10):
					var ray := Vector2.RIGHT.rotated(TAU * j / 10.0)
					var inner := ray * reach * 0.23
					var outer := ray * reach * (0.55 + 0.12 * float(j % 2))
					draw_line(inner, outer, Palette.with_alpha(Palette.glow(main_color, 1.35), alpha), 7.0)
			"bramble":
				for j in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * j / 8.0 + f * 0.5)
					var tip := ray * reach * 0.68
					draw_line(ray * reach * 0.12, tip, Palette.with_alpha(Palette.glow(main_color, 1.4), alpha), 5.0)
					draw_line(tip, tip - ray * 18.0 + ray.orthogonal() * 10.0, Palette.with_alpha(Color.WHITE, alpha * 0.7), 3.0)
			"luma":
				for i in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * i / 8.0 + f * 0.5)
					draw_line(ray * reach * 0.18, ray * reach * 0.62,
						Palette.with_alpha(Palette.glow(main_color, 1.7), alpha), 3.0)
				draw_circle(Vector2.ZERO, reach * 0.15,
					Palette.with_alpha(Color.WHITE, alpha * 0.8))
			"ember":
				for off in [-0.55, -0.27, 0.0, 0.27, 0.55]:
					var ray := direction.rotated(off)
					var flame := PackedVector2Array([
						ray * reach,
						ray * reach * 0.28 + ray.orthogonal() * 7.0,
						ray * reach * 0.16 - ray.orthogonal() * 7.0])
					draw_colored_polygon(flame,
						Palette.with_alpha(Palette.glow(main_color, 1.6), alpha * 0.78))
			"titan":
				var side := direction.orthogonal()
				for s in [-1.0, 1.0]:
					var start: Vector2 = side * s * reach * 0.23
					var finish: Vector2 = start + direction * reach * 0.78
					draw_line(start, finish, Palette.with_alpha(Color("3a241e"), alpha), 12.0)
					draw_line(start, finish,
						Palette.with_alpha(Palette.glow(main_color, 1.25), alpha), 6.0)
					draw_circle(finish, 9.0, Palette.with_alpha(Color.WHITE, alpha * 0.55))
			"kaira":
				# Poran purenta: kolme eteenpäin osoittavaa sulakiilaa peräkkäin.
				var kside := direction.orthogonal()
				for j in range(3):
					var depth := reach * (0.34 + j * 0.22)
					var wide := reach * (0.30 - j * 0.06)
					draw_colored_polygon(PackedVector2Array([
						direction * (depth + reach * 0.22),
						direction * depth + kside * wide,
						direction * depth - kside * wide]),
						Palette.with_alpha(Palette.glow(main_color, 1.5 + j * 0.1),
							alpha * (0.85 - j * 0.18)))
				draw_circle(direction * reach * 0.2, reach * 0.14,
					Palette.with_alpha(Color("fff0a8"), alpha * 0.8))
			"vesper":
				# Teloittajan tähtäin: supistuva sirppi + neljä ristikkoviivaa.
				draw_arc(Vector2.ZERO, reach * lerpf(0.72, 0.4, f), -1.15, 1.15, 20,
					Palette.with_alpha(Palette.glow(main_color, 1.6), alpha), 5.0)
				draw_arc(Vector2.ZERO, reach * lerpf(0.72, 0.4, f), PI - 1.15, PI + 1.15, 20,
					Palette.with_alpha(Palette.glow(main_color, 1.6), alpha), 5.0)
				for j in range(4):
					var ray := Vector2.RIGHT.rotated(TAU * j / 4.0 + PI * 0.25)
					draw_line(ray * reach * 0.2, ray * reach * 0.8,
						Palette.with_alpha(main_color, alpha * 0.7), 2.5)
				draw_circle(Vector2.ZERO, reach * 0.09,
					Palette.with_alpha(Color.WHITE, alpha * 0.8))
			"myria":
				# Orkidea aukeaa: kuusi terälehteä kasvaa ulos keskuksesta.
				for j in range(6):
					var ang := TAU * j / 6.0 + f * 0.9
					var ray := Vector2.RIGHT.rotated(ang)
					var petal_len: float = reach * lerpf(0.18, 0.78, f)
					draw_colored_polygon(PackedVector2Array([
						ray * reach * 0.1,
						ray * petal_len * 0.7 + ray.orthogonal() * reach * 0.16,
						ray * petal_len,
						ray * petal_len * 0.7 - ray.orthogonal() * reach * 0.16]),
						Palette.with_alpha(Palette.glow(main_color, 1.5), alpha * 0.85))
				draw_circle(Vector2.ZERO, reach * 0.13,
					Palette.with_alpha(Palette.glow(Color("ffb3e6"), 1.6), alpha))
			"torq":
				# Magneettinapa: hevosenkenkäkaari ja sisäänpäin kaartuvat kenttäviivat.
				draw_arc(Vector2.ZERO, reach * 0.66, PI * 0.28, PI * 1.72, 26,
					Palette.with_alpha(Palette.glow(main_color, 1.5), alpha), 9.0)
				draw_circle(Vector2.RIGHT.rotated(PI * 0.28) * reach * 0.66, reach * 0.13,
					Palette.with_alpha(Palette.glow(Color("ff5470"), 1.6), alpha))
				draw_circle(Vector2.RIGHT.rotated(PI * 1.72) * reach * 0.66, reach * 0.13,
					Palette.with_alpha(Palette.glow(Color("5ac8ff"), 1.6), alpha))
				for j in range(8):
					var ang := TAU * j / 8.0 - f * 2.2
					var pts := PackedVector2Array()
					for k in range(5):
						var kf := float(k) / 4.0
						pts.append(Vector2.RIGHT.rotated(ang + kf * 0.9)
							* reach * lerpf(0.92, 0.14, kf))
					draw_polyline(pts, Palette.with_alpha(team_color, alpha * 0.62), 2.5)
			_:
				for j in range(6):
					var ray := Vector2.RIGHT.rotated(TAU * j / 6.0 + f * 0.35)
					draw_line(ray * reach * 0.2, ray * reach * 0.62,
						Palette.with_alpha(Palette.glow(main_color, 1.45), alpha * 0.8), 3.0)


class UltimateTargetFx:
	extends Node2D
	var color := Color.WHITE
	var team_color := Color.WHITE
	var radius := 180.0
	var duration := 0.45
	var style := "generic"
	var _t := 0.0

	func _ready() -> void:
		z_index = 24

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var f := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
		var pulse := 0.72 + 0.28 * sin(_t * 18.0)
		draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.055 + f * 0.035))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Palette.with_alpha(team_color, 0.82), 4.0)
		draw_arc(Vector2.ZERO, radius * lerpf(1.12, 0.12, f), 0.0, TAU, 56,
			Palette.with_alpha(Palette.glow(color, 1.7), 0.55 + pulse * 0.4), 5.0)
		for j in range(8):
			var ray := Vector2.RIGHT.rotated(TAU * j / 8.0)
			draw_line(ray * (radius - 13.0), ray * (radius + 8.0),
				Palette.with_alpha(Palette.glow(color, 1.45), 0.75), 3.0)
		match style:
			"hush":
				for j in range(3):
					var rr := radius * (0.26 + j * 0.2)
					draw_arc(Vector2.ZERO, rr, -2.45, 2.45, 28,
						Palette.with_alpha(color, (0.52 - j * 0.1) * (1.0 - f * 0.45)), 3.0)
			"volt":
				for j in range(5):
					var ray := Vector2.RIGHT.rotated(TAU * j / 5.0 + _t * 1.8)
					draw_line(ray * radius * 0.18, ray * radius * 0.72,
						Palette.with_alpha(Palette.glow(color, 1.7), 0.45 * pulse), 3.0)
			"tide", "lance":
				for j in range(3):
					draw_arc(Vector2.ZERO, radius * (0.3 + j * 0.2), 0.15, PI - 0.15, 22,
						Palette.with_alpha(color, 0.45 - j * 0.08), 3.0)
			"kaira":
				for j in range(14):
					var ray := Vector2.RIGHT.rotated(TAU * j / 14.0 - _t * 1.2)
					draw_line(ray * radius * 0.28, ray * radius * 0.78,
						Palette.with_alpha(Palette.glow(color, 1.5), 0.42 + pulse * 0.22), 5.0)
			"vesper":
				for j in range(4):
					var ray := Vector2.RIGHT.rotated(TAU * j / 4.0 + PI * 0.25)
					draw_line(ray * radius * 0.25, ray * radius * 0.85,
						Palette.with_alpha(color, 0.5 * pulse), 3.0)
			"myria":
				for j in range(6):
					var ray := Vector2.RIGHT.rotated(TAU * j / 6.0 + _t * 0.8)
					draw_colored_polygon(PackedVector2Array([
						ray * radius * 0.12,
						ray * radius * 0.5 + ray.orthogonal() * radius * 0.16,
						ray * radius * 0.72,
						ray * radius * 0.5 - ray.orthogonal() * radius * 0.16]),
						Palette.with_alpha(Palette.glow(color, 1.5), 0.55 + pulse * 0.2))
			"torq":
				# Napakenttä: sisäänpäin kiertyvät kenttäviivat ja kaksi napaa.
				for j in range(8):
					var a := TAU * j / 8.0 - _t * 2.0
					var pts := PackedVector2Array()
					for k in range(6):
						var kf := float(k) / 5.0
						pts.append(Vector2.RIGHT.rotated(a + kf * 1.05)
							* radius * lerpf(0.95, 0.12, kf))
					draw_polyline(pts, Palette.with_alpha(Palette.glow(color, 1.5),
						0.4 + pulse * 0.28), 3.0)
				for pole in [-1.0, 1.0]:
					draw_circle(Vector2(pole * radius * 0.62, 0.0), 11.0,
						Palette.with_alpha(Palette.glow(
							Color("ff5470") if pole > 0.0 else Color("5ac8ff"), 1.6), 0.75))


class UltimateFieldFx:
	extends Node2D
	var color := Color.WHITE
	var team_color := Color.WHITE
	var radius := 180.0
	var duration := 3.0
	var style := "generic"
	var _t := 0.0

	func _ready() -> void:
		z_index = 8

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var fade := clampf((duration - _t) / 0.45, 0.0, 1.0)
		var pulse := 0.65 + 0.35 * sin(_t * 7.0)
		draw_circle(Vector2.ZERO, radius, Palette.with_alpha(color, 0.075 * fade))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Palette.with_alpha(team_color, 0.72 * fade), 3.5)
		draw_arc(Vector2.ZERO, radius - 8.0, _t, _t + PI * 1.45, 42,
			Palette.with_alpha(Palette.glow(color, 1.45), (0.38 + pulse * 0.25) * fade), 3.0)
		match style:
			"volt":
				for j in range(7):
					var a := TAU * j / 7.0 + _t * (0.38 if j % 2 == 0 else -0.28)
					var p := Vector2(cos(a), sin(a) * 0.58) * radius * (0.35 + 0.08 * (j % 3))
					draw_circle(p, 5.0 + pulse * 2.0, Palette.with_alpha(Palette.glow(color, 1.7), 0.5 * fade))
			"hush":
				for j in range(3):
					draw_arc(Vector2.ZERO, radius * (0.3 + j * 0.2), -2.5, 2.5, 30,
						Palette.with_alpha(color, (0.32 + pulse * 0.12) * fade), 2.5)
			"kaira":
				for j in range(12):
					var ray := Vector2.RIGHT.rotated(TAU * j / 12.0 - _t * 0.8)
					draw_line(ray * radius * 0.3, ray * radius * 0.8,
						Palette.with_alpha(Palette.glow(color, 1.5), (0.28 + pulse * 0.22) * fade), 6.0)
			"vesper":
				for j in range(-3, 4):
					var off := float(j) * radius * 0.21
					draw_line(Vector2(-radius * 0.85, off), Vector2(radius * 0.85, off),
						Palette.with_alpha(color, (0.14 + pulse * 0.12) * fade), 2.0)
					draw_line(Vector2(off, -radius * 0.85), Vector2(off, radius * 0.85),
						Palette.with_alpha(color, (0.14 + pulse * 0.12) * fade), 2.0)
			"myria":
				# Puutarha: kehälle nousevat varret ja kiertyvät terälehdet.
				for j in range(8):
					var ray := Vector2.RIGHT.rotated(TAU * j / 8.0 + _t * 0.25)
					draw_line(ray * radius * 0.9, ray * radius * 0.42,
						Palette.with_alpha(Color("7ee08a"), 0.34 * fade), 4.0)
					draw_circle(ray * radius * 0.42, 7.0 + pulse * 2.5,
						Palette.with_alpha(Palette.glow(Color("ffb3e6"), 1.5), 0.6 * fade))
			"torq":
				# Kenttäviivat imevät sisäänpäin koko keston ajan.
				for j in range(10):
					var a := TAU * j / 10.0 - _t * 1.4
					var poly := PackedVector2Array()
					for k in range(6):
						var kf := float(k) / 5.0
						poly.append(Vector2.RIGHT.rotated(a + kf * 1.1)
							* radius * lerpf(0.95, 0.12, kf))
					draw_polyline(poly, Palette.with_alpha(Palette.glow(color, 1.45),
						(0.26 + pulse * 0.18) * fade), 3.0)
				for pole in [-1.0, 1.0]:
					draw_circle(Vector2(pole * radius * 0.62, 0.0), 10.0 + pulse * 4.0,
						Palette.with_alpha(Palette.glow(
							Color("ff5470") if pole > 0.0 else Color("5ac8ff"), 1.6),
							0.7 * fade))


class UltimateLineFx:
	extends Node2D
	var from_point := Vector2.ZERO
	var to_point := Vector2.RIGHT
	var color := Color.WHITE
	var team_color := Color.WHITE
	var half_width := 30.0
	var duration := 0.32
	var _t := 0.0

	func _ready() -> void:
		z_index = 25

	func _process(delta: float) -> void:
		_t += delta
		if _t >= duration:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var d := (to_point - from_point).normalized()
		var side := d.orthogonal() * half_width
		var f := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
		var lane := PackedVector2Array([from_point - side, to_point - side, to_point + side, from_point + side])
		draw_colored_polygon(lane, Palette.with_alpha(color, 0.09 + f * 0.08))
		draw_line(from_point - side, to_point - side, Palette.with_alpha(team_color, 0.82), 3.0)
		draw_line(from_point + side, to_point + side, Palette.with_alpha(team_color, 0.82), 3.0)
		var length := from_point.distance_to(to_point)
		for j in range(7):
			var p := from_point + d * length * fmod(float(j) / 7.0 + f * 0.7, 1.0)
			draw_line(p - d * 11.0 + side.normalized() * 7.0, p, Palette.with_alpha(Color.WHITE, 0.72), 2.5)
			draw_line(p - d * 11.0 - side.normalized() * 7.0, p, Palette.with_alpha(Color.WHITE, 0.72), 2.5)
