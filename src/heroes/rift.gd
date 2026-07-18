class_name Rift
extends Hero
## Assassin (void): Rift. Perusiskut kasaavat pinoja kohteeseen (max 5), a2
## räjäyttää pinot (enemmän pinoja = enemmän vahinkoa; täydet 5 nollaa a2:n
## jäähdytyksen). a1 heittää merkin (oma tai vihollinen) ja toinen painallus
## varppaa merkatulle. Ultti pysäyttää ajan ympäriltä — kaikki muut jäätyvät,
## Rift liikkuu ja toimii vapaasti (esim. kasaa pinot ja räjäyttää ne rauhassa).

const SLASH_RANGE := 84.0
const SLASH_ARC := 68.0
const SLASH_DMG := 15.0

const MARK_SPEED := 1350.0
const MARK_LIFE := 0.85
const MARK_DUR := 3.0            # kuinka kauan merkki pysyy osumisen jälkeen
const TP_OFFSET := 46.0

const DET_RANGE := 118.0
const DET_ARC := 85.0
const DET_BASE := 20.0
const DET_PER_STACK := 15.0

const FREEZE_RADIUS := 520.0
const FREEZE_DUR := 1.9

var _mark_target: Hero = null
var _mark_timer := 0.0
var _mark_pending := false


func _init() -> void:
	radius = 22.0


## Perushyökkäys: tyhjyysviilto, joka kasaa pinon osumaan.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("blade", 0.15, -1.0)
	Fx.slash(arena, global_position, dir, SLASH_RANGE, SLASH_ARC, hero_color())
	for enemy in arena.alive_enemies(team):
		var to: Vector2 = enemy.global_position - global_position
		if to.length() > SLASH_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to))) > SLASH_ARC:
			continue
		deal_damage_to(enemy, SLASH_DMG, 90.0, to.normalized())
		enemy.add_void_stack(self)
		Fx.spark(arena, enemy.global_position + Vector2(0, -40), Palette.glow(hero_color(), 1.5))


## Kyky 1: merkkiheitto / varppaus. Ensimmäinen painallus heittää merkin;
## kun se osuu (oma tai vihollinen), toinen painallus varppaa kohteelle.
func _ability1(dir: Vector2) -> void:
	if _mark_target != null and is_instance_valid(_mark_target) and _mark_target.alive:
		_teleport_to_mark()
		cd.a1 = cd_max.a1
	elif _mark_pending:
		cd.a1 = 0.15            # merkki vielä lennossa
	else:
		_throw_mark(dir)
		_mark_pending = true
		cd.a1 = 0.15            # lyhyt, jotta varppauspainallus toimii


func _throw_mark(dir: Vector2) -> void:
	AudioMgr.play("blink", 0.1, -2.0)
	var mark := VoidMark.new()
	mark.source = self
	mark.direction = dir.normalized()
	mark.color = hero_color()
	mark.global_position = global_position + dir * 28.0
	arena.add_child(mark)


func on_mark_land(hero: Hero) -> void:
	_mark_target = hero
	_mark_pending = false
	_mark_timer = MARK_DUR


func on_mark_miss() -> void:
	_mark_pending = false


func _teleport_to_mark() -> void:
	var from := global_position
	var t := _mark_target
	var off: Vector2 = (from - t.global_position).normalized() * TP_OFFSET
	if off == Vector2.ZERO:
		off = -aim * TP_OFFSET
	global_position = arena.map.clamp_to_field(t.global_position + off, 40.0)
	aim = (t.global_position - global_position).normalized()
	iframes = maxf(iframes, 0.25)
	_mark_target = null
	_mark_timer = 0.0
	Fx.beam(arena, from, global_position, Palette.glow(hero_color(), 1.4), 6.0)
	Fx.flash(arena, global_position, Palette.glow(hero_color(), 1.6), 44.0, 0.3)
	AudioMgr.play("blink", 0.1, 1.0)


## Kyky 2: räjäytys. Melee-isku edessä olevaan viholliseen; kuluttaa sen
## pinot ja tekee vahinkoa niiden mukaan. Täydet 5 pinoa nollaa jäähdytyksen.
func _ability2(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("zap", 0.1, -3.0)
	Fx.slash(arena, global_position, dir, DET_RANGE, DET_ARC, Palette.glow(hero_color(), 1.4))
	var target := _melee_target(dir)
	if target == null:
		return
	var stacks := target.consume_void_stacks()
	var dmg := DET_BASE + stacks * DET_PER_STACK
	deal_damage_to(target, dmg, 160.0, dir)
	if stacks > 0:
		arena.shake(0.15 + stacks * 0.05)
		Fx.burst(arena, target.global_position, Palette.glow(hero_color(), 1.6),
			8 + stacks * 3, 200.0 + stacks * 40.0, 0.5, 6.0)
		Fx.ring(arena, target.global_position, Palette.glow(hero_color(), 1.5),
			40.0 + stacks * 14.0, 0.45, 5.0)
		arena.popup(target.global_position + Vector2(0, -60),
			"RÄJÄYTYS x%d" % stacks, Palette.glow(hero_color(), 1.5), 20)
	if stacks >= 5:
		cd.a2 = 0.0             # täydet pinot -> voi räjäyttää heti uudelleen


func _melee_target(dir: Vector2) -> Hero:
	var best: Hero = null
	var best_d := DET_RANGE + 40.0
	for enemy in arena.alive_enemies(team):
		var to: Vector2 = enemy.global_position - global_position
		var d: float = to.length()
		if d > DET_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to))) > DET_ARC:
			continue
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Väistö: nopea tyhjyysloikka.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1150.0, 0.12, true)
	AudioMgr.play("smoke", 0.12)
	Fx.burst(arena, global_position, Palette.with_alpha(Palette.darker(hero_color(), 0.5), 0.6),
		8, 150.0, 0.4, 5.0)


## Ultimate: ajanpysäytys. Kaikki muut sankarit (myös omat) säteen sisällä
## jäätyvät hetkeksi; Rift liikkuu ja toimii vapaasti.
func _ultimate(_dir: Vector2) -> void:
	arena.popup(global_position + Vector2(0, -84), "AJANPYSÄYTYS!", Palette.glow(hero_color(), 1.6), 26)
	AudioMgr.play("thunder", 0.05, 2.0)
	arena.shake(0.4)
	Fx.ring(arena, global_position, Palette.glow(hero_color(), 1.7), FREEZE_RADIUS, 0.8, 10.0)
	Fx.ring(arena, global_position, Palette.with_alpha(hero_color(), 0.5), FREEZE_RADIUS * 0.6, 0.6, 6.0)
	for hero in arena.heroes:
		if hero == self or not is_instance_valid(hero) or not hero.alive:
			continue
		if hero.global_position.distance_to(global_position) < FREEZE_RADIUS:
			hero.apply_freeze(FREEZE_DUR)
			Fx.flash(arena, hero.global_position, Palette.with_alpha(hero_color(), 0.7), 40.0, 0.4)


func _passive_update(delta: float) -> void:
	if _mark_target != null:
		if not is_instance_valid(_mark_target) or not _mark_target.alive:
			_mark_target = null
		else:
			_mark_timer -= delta
			if _mark_timer <= 0.0:
				_mark_target = null


## Merkkiammus, joka osuu ensimmäiseen sankariin (oma TAI vihollinen).
class VoidMark:
	extends Node2D

	var source: Hero = null
	var direction := Vector2.RIGHT
	var speed := 1350.0
	var life := 0.85
	var color := Color("9d4edd")
	var _time := 0.0

	func _ready() -> void:
		z_index = 21

	func _physics_process(delta: float) -> void:
		_time += delta
		life -= delta
		if life <= 0.0:
			_miss()
			return
		global_position += direction * speed * delta
		if source == null or not is_instance_valid(source):
			queue_free()
			return
		var arena = source.arena
		if arena == null:
			queue_free()
			return
		for hero in arena.heroes:
			if not is_instance_valid(hero) or not hero.alive or hero == source:
				continue
			if global_position.distance_to(hero.global_position) < 22.0 + hero.radius:
				_land(hero)
				return
		queue_redraw()

	func _land(hero: Hero) -> void:
		if is_instance_valid(source):
			source.on_mark_land(hero)
			Fx.ring(source.arena, hero.global_position, Palette.glow(color, 1.5), 42.0, 0.4)
			AudioMgr.play("mark", 0.05)
		queue_free()

	func _miss() -> void:
		if is_instance_valid(source):
			source.on_mark_miss()
		queue_free()

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 10.0, Palette.with_alpha(color, 0.3))
		draw_circle(Vector2.ZERO, 5.0, Palette.glow(color, 1.6))
		draw_arc(Vector2.ZERO, 12.0, _time * 9.0, _time * 9.0 + TAU * 0.7, 16,
			Palette.glow(color, 1.3), 2.0)
