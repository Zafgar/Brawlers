class_name Critter
extends Hero
## Viidakko-olento: neutraali taisteltava (joukkue 2). Koska se periytyy
## Herosta, kaikki olemassa oleva taistelu (osumat, ammukset, tähtäys,
## tyrmäys) toimii sellaisenaan — neutraali joukkue tekee siitä vihollisen
## molemmille tiimeille eikä kummankaan liittolaisen.
##
## Kolme tyyppiä:
##   DAMAGE_CAMP  — sivuleirit (molemmin puolin): kaataja saa vahinkobuffin.
##   POINTS_CAMP  — pistereiri: kaataja saa joukkueelleen pisteitä.
##   BOSS         — keskustan pomo: ilmestyy ajastimella; kaataja saa ison,
##                  pitkäkestoisen boostin koko joukkueelleen.
##
## Elinkaari kulkee Heron respawn-koneiston kautta: _knockout asettaa
## respawn_timerin ja _respawn palauttaa olennon kotileirilleen.

enum Kind { DAMAGE_CAMP, POINTS_CAMP, BOSS }

var kind := Kind.DAMAGE_CAMP
var home := Vector2.ZERO
var respawn_delay := 22.0
var attack_reach := 78.0
var attack_dmg := 16.0
var attack_kb := 240.0
var _color := Color("d98a3a")


## Neutraali setup ilman HeroDefiä (olennot eivät ole sankarilistassa).
func setup_critter(p_arena, p_kind: int, p_home: Vector2) -> void:
	arena = p_arena
	kind = p_kind
	home = p_home
	team = 2
	hero_id = "critter"

	profile = PlayerProfile.new()
	profile.is_bot = true
	profile.team = 2
	profile.hero_id = "critter"
	profile.index = 0
	profile.display_name = _kind_name()

	var brain := NeutralBrain.new()
	brain.home = home
	controller = brain

	# Olennoilla ei ole ultia -> estä latautuminen (muuten "ULTI VALMIS!" -popup).
	ult_gain_mult = 0.0

	match kind:
		Kind.DAMAGE_CAMP:
			max_hp = 240.0
			radius = 34.0
			base_speed = 74.0
			attack_reach = 80.0
			attack_dmg = 15.0
			attack_kb = 240.0
			respawn_delay = 22.0
			kb_resist = 0.6
			_color = Color("e08a3c")
			brain.aggro_radius = 250.0
			brain.attack_range = 74.0
			brain.leash = 360.0
			cd_max.basic = 1.0
		Kind.POINTS_CAMP:
			max_hp = 300.0
			radius = 36.0
			base_speed = 62.0
			attack_reach = 80.0
			attack_dmg = 13.0
			attack_kb = 220.0
			respawn_delay = 26.0
			kb_resist = 0.65
			_color = Color("e0c23c")
			brain.aggro_radius = 230.0
			brain.attack_range = 74.0
			brain.leash = 340.0
			cd_max.basic = 1.1
		Kind.BOSS:
			max_hp = 1200.0
			radius = 58.0
			base_speed = 96.0
			attack_reach = 122.0
			attack_dmg = 30.0
			attack_kb = 520.0
			respawn_delay = 95.0
			kb_resist = 0.92
			_color = Color("b64ad6")
			brain.aggro_radius = 460.0
			brain.attack_range = 112.0
			brain.leash = 720.0        # pysyy keskustan montussa (ei jahtaa kauas)
			cd_max.basic = 0.9
	hp = max_hp

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	var vis := CritterVisual.new()
	vis.hero = self
	visual = vis
	add_child(vis)

	global_position = home


func _kind_name() -> String:
	match kind:
		Kind.DAMAGE_CAMP:
			return "Raivopeto"
		Kind.POINTS_CAMP:
			return "Aarrepeto"
		Kind.BOSS:
			return "Viidakkopomo"
	return "Olento"


func hero_color() -> Color:
	return _color


## Perushyökkäys: lähialueen isku edessä. Osuu vain pelaajiin (joukkue 0/1).
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("swing", 0.12, -6.0 if kind != Kind.BOSS else -2.0)
	Fx.slash(arena, global_position, dir, attack_reach, 70.0, _color)
	for enemy in arena.alive_enemies(team):
		var to_e: Vector2 = enemy.global_position - global_position
		if to_e.length() > attack_reach + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_e))) > 70.0:
			continue
		deal_damage_to(enemy, attack_dmg, attack_kb, to_e.normalized())
	if kind == Kind.BOSS:
		arena.shake(0.12)
		Fx.spark(arena, global_position + dir * attack_reach * 0.7, Palette.glow(_color, 1.4))


## Tyrmäys: ei sankarin KO-polkua. Ilmoittaa areenalle palkintoa varten ja
## käynnistää respawn-ajastimen (Heron respawn-koneisto herättää olennon).
func _knockout(source: Hero) -> void:
	alive = false
	velocity = Vector2.ZERO
	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	guard_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	respawn_timer = respawn_delay
	_recent_damagers.clear()
	Fx.knockout_burst(arena, global_position, _color)
	Fx.ring(arena, global_position, Palette.glow(_color, 1.5),
		radius + 40.0, 0.6, 7.0)
	AudioMgr.play("ko", 0.12, -4.0 if kind != Kind.BOSS else -8.0)
	arena.shake(0.4 if kind == Kind.BOSS else 0.2)
	if arena.has_method("on_critter_ko"):
		arena.on_critter_ko(self, source)


## Palautus kotileirille (Heron respawn-koneisto kutsuu respawn_timerin nollaan).
func _respawn() -> void:
	alive = true
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
	visible = true
	iframes = 0.5
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	for slot in cd:
		cd[slot] = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(_color, 0.9), radius + 30.0, 0.5)
	if arena.has_method("on_critter_respawn"):
		arena.on_critter_respawn(self)


## Erän alku: palauta olento kotileirille (ei HeroDefiä / spawn_pointia).
func reset_for_round(_keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	hp = max_hp
	global_position = home
	velocity = Vector2.ZERO
	respawn_timer = 0.0
	stun_timer = 0.0
	slow_timer = 0.0
	slow_factor = 1.0
	guard_timer = 0.0
	for slot in cd:
		cd[slot] = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	_recent_damagers.clear()


## Viidakko-olennon ulkoasu. Periytyy HeroVisualista (saa flash/squash/animaatiot)
## mutta piirtää oman olentohahmonsa ja HP-palkin — ei HeroDef-riippuvuutta.
class CritterVisual:
	extends HeroVisual

	func _draw() -> void:
		if hero == null or not hero.alive:
			return
		var cr := hero as Critter
		if cr == null:
			return
		var r: float = cr.radius
		var col: Color = cr._color
		var dark: Color = Palette.darker(col, 0.5)
		var moving: float = clampf(hero.velocity.length() / 200.0, 0.0, 1.0)
		var bob: float = sin(_time * 6.0) * 2.0 + absf(sin(_time * 10.0)) * 3.0 * moving

		# Varjo
		draw_set_transform(Vector2(0, r * 0.7), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, r + 3.0, Color(0.02, 0.03, 0.06, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		var body := Vector2(0, -bob)
		# Piikikäs/karvainen ääriviiva olennolle
		var spikes := 12 if cr.kind == Critter.Kind.BOSS else 9
		var ring := PackedVector2Array()
		for i in range(spikes * 2):
			var a: float = _time * (0.6 if cr.kind == Critter.Kind.BOSS else 0.9) + TAU * i / (spikes * 2)
			var rr: float = (r + 6.0) if i % 2 == 0 else (r - 2.0)
			ring.append(body + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(ring, dark)
		# Runko
		draw_circle(body, r, col)
		draw_circle(body + Vector2(0, r * 0.32), r * 0.7, Palette.with_alpha(dark, 0.5))
		draw_circle(body + Vector2(-r * 0.3, -r * 0.35), r * 0.32,
			Palette.with_alpha(Color.WHITE, 0.18))
		if _flash > 0.0:
			draw_circle(body, r, Color(1, 1, 1, _flash * 0.7))

		# Silmät suunnattuina tähtäykseen (uhkaava katse)
		var look: Vector2 = hero.aim * (r * 0.14)
		var perp: Vector2 = hero.aim.orthogonal().normalized() * (r * 0.32)
		for side in [-1.0, 1.0]:
			var eye: Vector2 = body + perp * side + look + Vector2(0, -r * 0.12)
			var es: float = r * 0.16
			draw_circle(eye, es + 1.5, Color(0.05, 0.02, 0.02))
			draw_circle(eye, es, Color("ffef9c") if cr.kind == Critter.Kind.BOSS else Color.WHITE)
			draw_circle(eye + hero.aim * es * 0.4, es * 0.5, Color("2a0f14"))

		# Pomolla lisäsarvet
		if cr.kind == Critter.Kind.BOSS:
			for sgn in [-1.0, 1.0]:
				var s: float = sgn
				var base: Vector2 = body + Vector2(s * r * 0.5, -r * 0.6)
				var tip: Vector2 = base + Vector2(s * r * 0.5, -r * 0.7)
				draw_line(base, tip, dark, 6.0)
				draw_circle(tip, 4.0, Palette.glow(col, 1.3))

		# HP-palkki olennon yllä (aina näkyvissä, kertoo kaadon edistymisen)
		var frac: float = clampf(hero.hp / hero.max_hp, 0.0, 1.0)
		var bw: float = r * 2.2
		var by: float = -r - 16.0
		draw_rect(Rect2(-bw / 2.0, by, bw, 6.0), Color(0, 0, 0, 0.55))
		var hpc: Color = col if cr.kind != Critter.Kind.BOSS else Palette.glow(col, 1.2)
		draw_rect(Rect2(-bw / 2.0, by, bw * frac, 6.0), hpc)
		draw_rect(Rect2(-bw / 2.0, by, bw, 6.0), Palette.with_alpha(Color.WHITE, 0.25), false, 1.0)
