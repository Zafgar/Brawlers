class_name Projectile
extends Area2D
## Yleiskäyttöinen ammus. Osuu vihollisiin (etäisyystesti, max 8 sankaria)
## ja seiniin (fysiikka-alue). Piirtää hehkuvan ytimen ja häntäjäljen.
##
## Käyttö:  Projectile.launch(sankari, lähtöpiste, suunta, { asetukset })
## Asetukset (kaikilla järkevä oletus):
##   speed, dmg, radius, life, kb, color, pierce, trail, heal_allies,
##   on_hit: Callable(hero, projectile), on_expire: Callable(pos), spin

var source: Hero = null
var team := 0
var speed := 900.0
var dmg := 12.0
var hit_radius := 10.0
var life := 1.2
var kb := 140.0
var color := Color.WHITE
var pierce := 0
var show_trail := true
var heal_allies := 0.0
var on_hit := Callable()
var on_expire := Callable()
var spin := false

var direction := Vector2.RIGHT
var _hit_heroes: Array = []
var _trail_points := PackedVector2Array()
var _time := 0.0


static func launch(src: Hero, pos: Vector2, dir: Vector2, cfg := {}) -> Projectile:
	var p := Projectile.new()
	p.source = src
	p.team = src.team
	p.global_position = pos
	p.direction = dir.normalized()
	p.speed = cfg.get("speed", 900.0)
	p.dmg = cfg.get("dmg", 12.0)
	p.hit_radius = cfg.get("radius", 10.0)
	p.life = cfg.get("life", 1.2)
	p.kb = cfg.get("kb", 140.0)
	p.color = cfg.get("color", src.hero_color())
	p.pierce = cfg.get("pierce", 0)
	p.show_trail = cfg.get("trail", true)
	p.heal_allies = cfg.get("heal_allies", 0.0)
	p.on_hit = cfg.get("on_hit", Callable())
	p.on_expire = cfg.get("on_expire", Callable())
	p.spin = cfg.get("spin", false)
	src.arena.add_projectile(p)
	return p


func _ready() -> void:
	z_index = 20
	collision_layer = 0
	collision_mask = 1  # vain seinät fysiikan kautta
	monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_wall_hit)


func _physics_process(delta: float) -> void:
	_time += delta
	life -= delta
	if life <= 0.0:
		_expire()
		return

	global_position += direction * speed * delta

	if show_trail:
		_trail_points.insert(0, global_position)
		if _trail_points.size() > 8:
			_trail_points.resize(8)

	var arena = source.arena if source != null and is_instance_valid(source) else null
	if arena == null:
		queue_free()
		return

	# Kuplat (Bastionin Linnake) torjuvat vihollisammukset.
	for zone in arena.zones:
		if not is_instance_valid(zone):
			continue
		if zone.type == "dome" and zone.team != team:
			if global_position.distance_to(zone.global_position) < zone.radius:
				if zone.source != null and is_instance_valid(zone.source):
					zone.source.profile.stats.prevented += dmg
					zone.source.profile.add_score(dmg * 0.08)
				Fx.spark(arena, global_position, Palette.SHIELD)
				AudioMgr.play("shield")
				queue_free()
				return

	# Osumat sankareihin etäisyystestillä.
	for hero in arena.heroes:
		if not is_instance_valid(hero) or not hero.alive:
			continue
		if hero in _hit_heroes:
			continue
		var dist: float = global_position.distance_to(hero.global_position)
		if dist > hit_radius + hero.radius:
			continue
		if hero.team == team:
			if heal_allies > 0.0 and hero != source and hero.hp < hero.max_hp:
				_hit_heroes.append(hero)
				hero.heal_hp(heal_allies, source)
			continue
		# Vihollisosuma
		_hit_heroes.append(hero)
		if source != null and is_instance_valid(source):
			source.deal_damage_to(hero, dmg, kb, direction)
		if on_hit.is_valid():
			on_hit.call(hero, self)
		Fx.spark(arena, global_position, color)
		if pierce > 0:
			pierce -= 1
		else:
			queue_free()
			return

	queue_redraw()


func _on_wall_hit(_body: Node) -> void:
	_expire()


func _expire() -> void:
	if on_expire.is_valid():
		on_expire.call(global_position)
	if source != null and is_instance_valid(source) and source.arena != null:
		Fx.spark(source.arena, global_position, color)
	queue_free()


func _draw() -> void:
	# Häntä
	if show_trail and _trail_points.size() > 1:
		var pts := PackedVector2Array()
		for point in _trail_points:
			pts.append(to_local(point))
		draw_polyline(pts, Palette.with_alpha(color, 0.4), hit_radius * 0.9)
	# Hehkuva ydin
	var wobble := 1.0 + sin(_time * 20.0) * 0.08
	var angle := _time * 9.0 if spin else 0.0
	draw_circle(Vector2.ZERO, hit_radius * 1.5 * wobble, Palette.with_alpha(color, 0.25))
	draw_circle(Vector2.ZERO, hit_radius * wobble, Palette.glow(color, 1.6))
	draw_circle(Vector2.RIGHT.rotated(angle) * hit_radius * 0.25, hit_radius * 0.45,
		Palette.glow(Color.WHITE, 1.3))
