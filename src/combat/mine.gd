class_name Mine
extends Node2D
## Salvon miina: viritetään hetken kuluttua, laukeaa vihollisen (tai
## viidakko-olennon/minionin) tullessa lähelle tai kun Salvo räjäyttää kaikki.
## Ei osu liittolaisiin eikä rakennuksiin. Kirjaa vahingon a1-kykypaikalle.

var source: Hero = null
var arena = null
var team := 0
var trigger_radius := 80.0
var blast_radius := 132.0
var dmg := 52.0
var kb := 280.0

var _arm := 0.5                    # viritysaika (ei laukea heti)
var _life := 26.0                  # elinaika ennen hiljaista poistoa
var _slot := "a1"
var _dead := false
var _t := 0.0


static func plant(src: Hero, pos: Vector2, cfg := {}) -> Mine:
	var m := Mine.new()
	m.source = src
	m.arena = src.arena
	m.team = src.team
	m._slot = src._cast_context if src._cast_context != "" else "a1"
	m.global_position = pos
	m.trigger_radius = cfg.get("trigger", 80.0)
	m.blast_radius = cfg.get("blast", 132.0)
	m.dmg = cfg.get("dmg", 52.0)
	m.kb = cfg.get("kb", 280.0)
	src.arena.add_child(m)
	return m


func _ready() -> void:
	z_index = 6
	AudioMgr.play("pop", 0.05, -4.0, global_position)


## Voiko kohteeseen osua: vihollisjoukkue tai viidakko-olento, ei rakennus.
func _is_target(h) -> bool:
	return is_instance_valid(h) and h.alive and not (h is Structure) and h.team != team


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	# Erän tauko/loppu: miina lepää (ei laukea). Siivotaan erän nollauksessa.
	if arena == null or arena.state != arena.State.PLAY:
		return
	_t += delta
	_life -= delta
	if _life <= 0.0:
		_quiet_remove()
		return
	if _arm > 0.0:
		_arm -= delta
		queue_redraw()
		return
	for h in arena.heroes:
		if not _is_target(h):
			continue
		if h.global_position.distance_to(global_position) <= trigger_radius + h.radius:
			detonate()
			return
	queue_redraw()


## Räjäyttää miinan: aluevahinko kohteisiin. Turvallinen kutsua monta kertaa.
func detonate() -> void:
	if _dead:
		return
	_dead = true
	AudioMgr.play("quake", 0.05, 2.0, global_position)
	if arena != null:
		arena.shake(0.28)
		Fx.flash(arena, global_position, Palette.glow(Color("ffb03a"), 1.6), blast_radius * 0.7, 0.45)
		Fx.ring(arena, global_position, Palette.glow(Color("ff7a3a"), 1.6), blast_radius, 0.5, 8.0)
		Fx.burst(arena, global_position, Palette.glow(Color("ffd76d"), 1.5), 18, 340.0, 0.5, 6.0)
	if source != null and is_instance_valid(source):
		source._act(_slot)
		for h in arena.heroes:
			if not _is_target(h):
				continue
			var d: float = h.global_position.distance_to(global_position)
			if d <= blast_radius + h.radius:
				var away: Vector2 = (h.global_position - global_position).normalized()
				if away == Vector2.ZERO:
					away = Vector2.UP
				source.deal_damage_to(h, dmg, kb, away)
		source._act_end()
	queue_free()


func _quiet_remove() -> void:
	_dead = true
	if arena != null:
		Fx.spark(arena, global_position, Palette.with_alpha(Color("ffb03a"), 0.6))
	queue_free()


func _draw() -> void:
	var arming: bool = _arm > 0.0
	var blink: float = 0.5 + 0.5 * sin(_t * (6.0 if arming else 12.0))
	var col: Color = Color("c9954a") if arming else Color("ff7a3a")
	# Runko
	draw_circle(Vector2.ZERO, 9.0, Palette.darker(col, 0.6))
	draw_circle(Vector2.ZERO, 6.5, col)
	# Piikit
	for i in range(6):
		var a: float = TAU * i / 6.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(dir * 7.0, dir * 12.0, Palette.darker(col, 0.5), 2.5)
	# Vilkkuvalo
	draw_circle(Vector2(0, -2.0), 2.6, Palette.with_alpha(Palette.glow(Color("ff5a3a"), 1.5), blink))
	# Laukaisukehä kun viritetty
	if not arming:
		draw_arc(Vector2.ZERO, trigger_radius, 0.0, TAU, 40,
			Palette.with_alpha(Color("ff7a3a"), 0.12 + 0.06 * blink), 1.5)
