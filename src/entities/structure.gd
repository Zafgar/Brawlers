class_name Structure
extends Hero
## MOBA-rakennus: torni tai nexus. Kuuluu joukkueeseen (0/1) mutta on yksikkö
## (is_unit) — jää pois pelaajakeskeisistä järjestelmistä. Periytyy Herosta,
## joten sankarien osumat/ammukset osuvat siihen normaalisti.
##
## Torni ampuu lähellä olevia vihollisia (minionit etusijalla). Nexus on voiton
## kohde: se on suojattu (haavoittumaton) kunnes sen molemmat tornit on tuhottu.

enum Kind { TOWER, NEXUS }

const SHOT_RANGE := 360.0
const SHOT_DMG := 42.0
const CHARGE_TIME := 1.05      # latausaika ennen laukausta (näkyvä telegrafi)
const AIM_LOCK_AT := 0.6       # missä latauksen vaiheessa kohde lukitaan
const MUZZLE_TIME := 0.14      # piipun välähdyksen kesto
const DEFEND_WINDOW := 2.5     # kuinka tuoreesta osumasta torni puolustaa liittolaista

var kind := Kind.TOWER
var _color := Color("4aa8ff")
var _invuln := false          # nexus: suojattu kunnes tornit kaadettu
var _charge := 0.0            # latausvaihe 0..1 (visuaalinen telegrafi)
var _target_lock: Hero = null # lukittu kohde (asetetaan latauksen loppuvaiheessa)
var _muzzle := 0.0            # piipun välähdyksen ajastin


func setup_structure(p_arena, p_kind: int, p_team: int, pos: Vector2) -> void:
	arena = p_arena
	kind = p_kind
	team = p_team
	is_unit = true
	regen_disabled = true
	hero_id = "structure"
	kb_resist = 1.0

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = p_team
	profile.index = 0
	profile.hero_id = "structure"
	profile.display_name = _sname()
	controller = StillBrain.new()
	ult_gain_mult = 0.0

	match kind:
		Kind.TOWER:
			max_hp = 900.0
			radius = 46.0
			_charge = randf_range(0.0, 0.6)   # porrasta aloituslataus
		Kind.NEXUS:
			max_hp = 1600.0
			radius = 72.0
			_invuln = true
	_color = Palette.team(p_team).lerp(Color.WHITE, 0.15)
	hp = max_hp

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	var vis := StructureVisual.new()
	vis.hero = self
	visual = vis
	add_child(vis)

	global_position = pos


func _sname() -> String:
	return "Nexus" if kind == Kind.NEXUS else "Torni"


func hero_color() -> Color:
	return _color


func set_vulnerable() -> void:
	_invuln = false


## Torni lataa ensin näkyvästi (telegrafi), lukitsee kohteen latauksen
## loppuvaiheessa ja ampuu kun lataus on täynnä. Kohdejärjestys: liittolaisen
## puolustus (LoL) > minionit > lähin vihollissankari.
func _passive_update(delta: float) -> void:
	if kind != Kind.TOWER:
		return
	_muzzle = maxf(_muzzle - delta, 0.0)
	if _charge < 1.0:
		_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
		# Lukitse kohde latauksen loppuvaiheessa -> näkyvä tähtäys ennen laukausta.
		if _charge >= AIM_LOCK_AT:
			_target_lock = _valid_lock()
		return
	# Lataus täynnä: varmista/valitse kohde ja ammu.
	var target := _valid_lock()
	_target_lock = target
	if target == null:
		return   # valmis mutta ei kohdetta -> pysyy ladattuna, ampuu heti kun kohde tulee
	_charge = 0.0
	_muzzle = MUZZLE_TIME
	var dir: Vector2 = (target.global_position - global_position).normalized()
	Projectile.launch(self, global_position + dir * (radius + 6.0), dir, {
		"speed": 880.0,
		"dmg": SHOT_DMG,
		"radius": 12.0,
		"life": 0.55,
		"kb": 40.0,
		"color": _color,
	})
	AudioMgr.play("light", 0.1, -4.0)


## Lukitun kohteen validointi: pidä lukittu kohde jos se on yhä elossa ja
## kantamalla, muuten valitse uusi normaalilla prioriteetilla.
func _valid_lock() -> Hero:
	if _target_lock != null and is_instance_valid(_target_lock) and _target_lock.alive \
			and _target_lock.global_position.distance_to(global_position) <= SHOT_RANGE:
		return _target_lock
	return _tower_target()


func _tower_target() -> Hero:
	# LoL-tornin puolustus: jos vihollissankari on hiljattain lyönyt liittolais-
	# sankaria tornin kantamassa, kohdista siihen heti (minionien ohi).
	var defend := _defend_target()
	if defend != null:
		return defend
	var foe: int = 1 - team
	var best_m: Hero = null
	var bm := SHOT_RANGE
	var best_h: Hero = null
	var bh := SHOT_RANGE
	for h in arena.heroes:
		if not is_instance_valid(h) or not h.alive or h.team != foe:
			continue
		if h is Structure:
			continue
		var d: float = h.global_position.distance_to(global_position)
		if d > SHOT_RANGE:
			continue
		if h is Minion:
			if d < bm:
				bm = d
				best_m = h
		elif not h.is_unit:
			if d < bh:
				bh = d
				best_h = h
	return best_m if best_m != null else best_h


## Vihollissankari joka on hiljattain lyönyt liittolaissankaria tornin
## kantamassa -> tornin aggro siirtyy häneen (rankaisee sukeltajaa).
func _defend_target() -> Hero:
	var now: float = Time.get_ticks_msec() / 1000.0
	for ally in arena.heroes:
		if not is_instance_valid(ally) or not ally.alive or ally.team != team or ally.is_unit:
			continue
		if ally.global_position.distance_to(global_position) > SHOT_RANGE:
			continue
		for entry in ally._recent_damagers:
			var h = entry.hero
			if not is_instance_valid(h) or not h.alive or h.is_unit or h.team == team:
				continue
			if now - float(entry.time) > DEFEND_WINDOW:
				continue
			if h.global_position.distance_to(global_position) > SHOT_RANGE:
				continue
			return h
	return null


## Nexus torjuu kaiken vahingon kunnes sen tornit on kaadettu.
func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if kind == Kind.NEXUS and _invuln:
		if arena != null:
			arena.popup(global_position + Vector2(0, -radius - 22.0),
				"SUOJATTU", Palette.SHIELD, 16)
		return 0.0
	return super.take_damage(amount, source, kb, kb_dir)


## Tuho: ilmoita areenalle (voitto / nexuksen avautuminen). Ei herää henkiin.
func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	Fx.knockout_burst(arena, global_position, _color)
	Fx.ring(arena, global_position, Palette.glow(_color, 1.6), radius + 60.0, 0.9, 12.0)
	Fx.flash(arena, global_position, Palette.glow(_color, 1.5), radius + 40.0, 0.6)
	# Rakennuksen romahdus: kivinen jyrähdys + tyrmäys. Nexus isompi.
	AudioMgr.play("rock", 0.05, 1.0 if kind == Kind.NEXUS else -3.0)
	AudioMgr.play("quake", 0.05, -1.0 if kind == Kind.NEXUS else -5.0)
	AudioMgr.play("ko", 0.1, -6.0)
	arena.shake(0.5)
	if arena.has_method("on_structure_destroyed"):
		arena.on_structure_destroyed(self, source)
	set_physics_process(false)


func _respawn() -> void:
	pass   # rakennukset pysyvät tuhottuina


## Erän alku: palauta rakennus täyteen (nexus taas suojattu).
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	hp = max_hp
	velocity = Vector2.ZERO
	respawn_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	_invuln = (kind == Kind.NEXUS)
	_charge = randf_range(0.0, 0.6)
	_target_lock = null
	_muzzle = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	set_physics_process(true)
	_recent_damagers.clear()


## Paikallaan pysyvä ohjain rakennuksille (ei liikettä eikä hyökkäystä).
class StillBrain:
	extends NeutralBrain

	func update(_hero, _delta: float) -> void:
		_mv = Vector2.ZERO
		_attack = false


## Rakennuksen ulkoasu (torni-spire tai nexus-kristalli) + HP-palkki.
class StructureVisual:
	extends HeroVisual

	func _draw() -> void:
		if hero == null or not hero.alive:
			return
		var s := hero as Structure
		if s == null:
			return
		var r: float = hero.radius
		var col: Color = s._color
		var dark: Color = Palette.darker(col, 0.55)
		draw_set_transform(Vector2(0, r * 0.32), 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, r * 1.05, Color(0.02, 0.03, 0.06, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if s.kind == Structure.Kind.TOWER:
			_paint_tower(s, r, col, dark)
		else:
			_paint_nexus(s, r, col, dark)
		if _flash > 0.0:
			draw_circle(Vector2.ZERO, r, Color(1, 1, 1, _flash * 0.55))
		_hp_bar(s, r, col)

	func _paint_tower(s: Structure, r: float, col: Color, dark: Color) -> void:
		# Kivijalka + kapeneva torni + hehkuva kärki josta ammukset lähtevät.
		var glow: Color = Palette.glow(col, 1.6)
		# Kivijalka: leveä matala kuusikulmio.
		var base_ring := PackedVector2Array()
		for i in range(6):
			var a: float = TAU * float(i) / 6.0 + PI / 6.0
			base_ring.append(Vector2(cos(a) * r * 0.98, r * 0.5 + sin(a) * r * 0.34))
		draw_colored_polygon(base_ring, Palette.darker(dark, 0.2))
		# Runko: kapeneva kivitorni kahdessa savyssa.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 0.58, r * 0.5), Vector2(r * 0.58, r * 0.5),
			Vector2(r * 0.42, -r * 0.4), Vector2(-r * 0.42, -r * 0.4)]), dark)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 0.46, r * 0.45), Vector2(r * 0.46, r * 0.45),
			Vector2(r * 0.32, -r * 0.4), Vector2(-r * 0.32, -r * 0.4)]), col)
		# Kivisaumat + riimuvyo.
		for sy in [0.28, 0.02, -0.24]:
			var yy: float = r * sy
			var wx: float = r * (0.44 - sy * 0.18)
			draw_line(Vector2(-wx, yy), Vector2(wx, yy), Palette.with_alpha(dark, 0.6), 1.5)
		draw_line(Vector2(-r * 0.4, -r * 0.12), Vector2(r * 0.4, -r * 0.12),
			Palette.with_alpha(glow, 0.5), 3.0)
		# Ampuma-alusta + rintavarustus (battlements).
		draw_colored_polygon(PackedVector2Array([
			Vector2(-r * 0.5, -r * 0.4), Vector2(r * 0.5, -r * 0.4),
			Vector2(r * 0.4, -r * 0.6), Vector2(-r * 0.4, -r * 0.6)]), Palette.darker(col, 0.35))
		for bx in [-0.36, -0.12, 0.12, 0.36]:
			draw_rect(Rect2(bx * r - r * 0.07, -r * 0.74, r * 0.14, r * 0.18), dark)

		# --- Latauskristalli karjessa: TELEGRAFI ---
		# Koko, hehku ja tayttyva rengas kasvavat latauksen (_charge) mukaan,
		# joten seuraavan laukauksen nakee tulossa.
		var tip := Vector2(0, -r * 0.86)
		var ch: float = clampf(s._charge, 0.0, 1.0)
		var ready: bool = ch >= 0.999
		var crys: float = r * (0.14 + 0.20 * ch)
		draw_circle(tip, crys + r * 0.18, Palette.with_alpha(glow, 0.10 + 0.35 * ch))
		if ch > 0.02:
			draw_arc(tip, crys + r * 0.13, -PI / 2.0, -PI / 2.0 + TAU * ch, 30,
				Palette.with_alpha(glow, 0.9), 3.0)
		var core: Color = Color.WHITE.lerp(glow, 0.35) if ready else glow
		draw_circle(tip, crys, Palette.with_alpha(core, 0.9))
		draw_circle(tip, crys * 0.5, Color(1, 1, 1, 0.85 if ready else 0.45))

		# Tahtaysviiva + tahtain lukittuun kohteeseen (nakyy kun kohde lukittu).
		var lock: Hero = s._target_lock
		if ch >= Structure.AIM_LOCK_AT and lock != null and is_instance_valid(lock) and lock.alive:
			var to_t: Vector2 = lock.global_position - s.global_position
			var d: float = to_t.length()
			if d > 1.0:
				var reticle: Vector2 = to_t / d * minf(d, Structure.SHOT_RANGE)
				var beam_a: float = 0.20 + 0.45 * ch
				draw_line(tip, reticle, Palette.with_alpha(glow, beam_a), 1.5)
				draw_arc(reticle, 15.0, 0.0, TAU, 20, Palette.with_alpha(glow, beam_a + 0.15), 2.0)
				draw_line(reticle - Vector2(20, 0), reticle + Vector2(20, 0),
					Palette.with_alpha(glow, beam_a), 1.5)
				draw_line(reticle - Vector2(0, 20), reticle + Vector2(0, 20),
					Palette.with_alpha(glow, beam_a), 1.5)

		# Piipun valahdys laukaisuhetkella.
		if s._muzzle > 0.0:
			var mf: float = s._muzzle / Structure.MUZZLE_TIME
			draw_circle(tip, crys + r * 0.34 * mf, Color(1, 1, 1, 0.6 * mf))

	func _paint_nexus(s: Structure, r: float, col: Color, dark: Color) -> void:
		var vuln: bool = not s._invuln
		var spin: float = _time * (1.3 if vuln else 0.4)
		var ring_col: Color = Palette.glow(col, 1.5) if vuln else Palette.with_alpha(col, 0.6)
		draw_arc(Vector2.ZERO, r + 14.0, spin, spin + TAU * 0.82, 46, ring_col, 4.0)
		var pulse: float = 0.6 + 0.4 * sin(_time * (6.0 if vuln else 3.0))
		for layer in [1.3, 1.0, 0.55]:
			var sc: float = layer
			var a: float = 0.9 if sc < 0.6 else (0.45 if sc < 1.05 else 0.22)
			var dia := PackedVector2Array([
				Vector2(0, -r * sc), Vector2(r * 0.7 * sc, 0),
				Vector2(0, r * sc), Vector2(-r * 0.7 * sc, 0)])
			draw_colored_polygon(dia, Palette.with_alpha(Palette.glow(col, 1.3), a * (0.7 + 0.3 * pulse)))
		if s._invuln:
			draw_arc(Vector2.ZERO, r + 6.0, 0.0, TAU, 44,
				Palette.with_alpha(Palette.SHIELD, 0.4 + 0.2 * pulse), 3.0)

	func _hp_bar(s: Structure, r: float, col: Color) -> void:
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		var bw: float = r * 2.4
		var by: float = -r - 22.0
		UiKit.draw_text(self, Vector2(0, by - 12.0), s._sname(), 14,
			Palette.with_alpha(col, 0.9), true)
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw / 2.0, by, bw * frac, 7.0), Palette.glow(col, 1.15))
		draw_rect(Rect2(-bw / 2.0, by, bw, 7.0), Palette.with_alpha(Color.WHITE, 0.25), false, 1.0)
