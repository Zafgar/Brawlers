class_name Fx
## Kertakäyttöiset visuaaliefektit: purskeet, renkaat, välähdykset, pöly.
## Kaikki syntyvät koodista ja siivoavat itsensä pois.


static func burst(parent: Node, pos: Vector2, color: Color, amount := 14,
		speed := 260.0, life := 0.5, size := 6.0) -> void:
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
	var node := RingFx.new()
	node.position = pos
	node.color = color
	node.max_radius = max_radius
	node.duration = duration
	node.width = width
	parent.add_child(node)


static func flash(parent: Node, pos: Vector2, color: Color, radius := 40.0,
		duration := 0.25) -> void:
	var node := FlashFx.new()
	node.position = pos
	node.color = color
	node.radius = radius
	node.duration = duration
	parent.add_child(node)


static func spark(parent: Node, pos: Vector2, color: Color) -> void:
	burst(parent, pos, Palette.glow(color, 1.5), 8, 220.0, 0.3, 4.0)


static func dust(parent: Node, pos: Vector2) -> void:
	burst(parent, pos + Vector2(0, 8), Color(0.8, 0.82, 0.9, 0.35), 6, 90.0, 0.4, 5.0)


static func heal_sparkle(parent: Node, pos: Vector2) -> void:
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
	var node := SlashFx.new()
	node.position = pos
	node.center_angle = dir.angle()
	node.reach = reach
	node.half_arc = deg_to_rad(arc_deg)
	node.color = color
	parent.add_child(node)


## Suora hehkuva valosäde kahden pisteen välille (parannus, kilpi, merkintä).
static func beam(parent: Node, from: Vector2, to: Vector2, color: Color, width := 6.0) -> void:
	var node := BeamFx.new()
	node.from_point = from
	node.to_point = to
	node.color = color
	node.width = width
	parent.add_child(node)


## Salamakaari kahden pisteen välille (Voltin ketjusalamat).
static func bolt(parent: Node, from: Vector2, to: Vector2, color: Color) -> void:
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
