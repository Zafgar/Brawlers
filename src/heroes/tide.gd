class_name Tide
extends Hero
## Fighter: vesikeihäs. Liukuu vesivanoja pitkin ja lakaisee viholliset aalloilla.
## Passiivi: virrassa liikkuessa (haste päällä) palautuu hitaasti.

const SPEAR_RANGE := 145.0
const SPEAR_ARC_DEG := 28.0
const SPEAR_DMG := 17.0

const DASH_CHARGES := 3             # syöksylatauksia yhtä aikaa varastossa
const DASH_RECHARGE := 5.0          # yhden latauksen palautuminen (hidas)
const DASH_SHIELD := 48.0           # syöksyn lyhyt vesikilpi (selviytyminen vs assassin)
const DASH_SHIELD_DUR := 1.4

# Ultti: vesiryntäys eteen, nostaa viholliset vesipatsaan päälle ja iskee alas.
const RUSH_SPEED := 1150.0
const RUSH_DUR := 0.3
const RUSH_RADIUS := 210.0
const LIFT_STUN := 0.5
const SLAM_DMG := 34.0
const SLAM_STUN := 0.7

var _dash_recharge := 0.0

func _init() -> void:
	radius = 26.0
	kb_resist = 0.2


## Raivo: kertyy taistelusta ja purkautuu Aaltoon (a2). Syöksy (a1) on irti
## raivosta: sillä on 3 latausta ja lyhyt käyttöväli, mutta lataukset palautuvat
## hitaasti yksitellen — spämmääminen ei kannata.
func _setup_resource() -> void:
	res_type = "rage"
	res_max = 100.0
	res = 0.0
	res_cost = {"basic": 0.0, "a1": 0.0, "a2": 40.0, "dodge": 0.0}
	cd_max.a1 = 0.55
	cd_max.a2 = 0.6
	ammo_max = DASH_CHARGES
	ammo = DASH_CHARGES


## Perushyökkäys: pitkä kapea keihäspisto.
func _basic(dir: Vector2) -> void:
	visual.attack_swing()
	AudioMgr.play("water", 0.12)
	var hits := 0
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > SPEAR_RANGE + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > SPEAR_ARC_DEG:
			continue
		deal_damage_to(enemy, SPEAR_DMG, 170.0, to_enemy.normalized())
		hits += 1
	if hits > 0:
		Fx.spark(arena, global_position + dir * SPEAR_RANGE * 0.8, Color("4ad4ff"))


## Kyky 1: Vesivana — syöksy, joka jättää kiihdyttävän vanan. Käyttää
## syöksylatauksia (max 3) raivon sijaan.
func _ability1(dir: Vector2) -> void:
	if ammo <= 0:
		return                          # ei latauksia jäljellä
	if ammo >= ammo_max:
		_dash_recharge = DASH_RECHARGE  # aloita palautuslaskuri täydestä
	ammo -= 1
	AudioMgr.play("water", 0.1, -3.0)
	dash(dir, 950.0, 0.32, false, true)   # phase_walls: vesisyöksy menee sisäseinien läpi
	# Lyhyt vesikilpi: ottaa vastaan hetken vahinkoa -> selviää assassinin avaukselta.
	add_shield(DASH_SHIELD, DASH_SHIELD_DUR, self)
	Fx.ring(arena, global_position, Palette.glow(Color("4ad4ff"), 1.4), radius + 12.0, 0.35)
	_water_trail()


func _water_trail() -> void:
	for i in range(3):
		if not is_inside_tree() or not alive:
			return
		Zone.spawn(self, global_position, {
			"type": "haste",
			"radius": 80.0,
			"dur": 3.0,
			"haste_f": 1.3,
			"color": Color("4ad4ff"),
		})
		Fx.burst(arena, global_position, Palette.with_alpha(Color("4ad4ff"), 0.6), 6, 120.0, 0.4, 4.0)
		await get_tree().create_timer(0.12).timeout


## Kyky 2: Aalto — työntävä vesiaalto eteen.
func _ability2(dir: Vector2) -> void:
	AudioMgr.play("wave")
	visual.attack_swing()
	Fx.burst(arena, global_position + dir * 80.0, Palette.glow(Color("4ad4ff"), 1.5), 18, 420.0, 0.45, 6.0)
	# Etenevät aaltokaaret
	for step in range(1, 4):
		Fx.ring(arena, global_position + dir * step * 60.0,
			Palette.with_alpha(Palette.glow(Color("4ad4ff"), 1.4), 0.6), 40.0 + step * 22.0, 0.35, 4.0)
	for enemy in arena.alive_enemies(team):
		var to_enemy: Vector2 = enemy.global_position - global_position
		if to_enemy.length() > 220.0 + enemy.radius:
			continue
		if absf(rad_to_deg(dir.angle_to(to_enemy))) > 45.0:
			continue
		deal_damage_to(enemy, 12.0, 540.0, to_enemy.normalized())
		enemy.apply_slow(0.8, 1.0)


## Väistö: virtaliuku.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 1000.0, 0.16, true)
	apply_haste(1.2, 0.8)
	AudioMgr.play("water", 0.12, 2.0)
	Fx.burst(arena, global_position, Palette.with_alpha(Color("4ad4ff"), 0.5), 8, 140.0, 0.4, 4.0)


## Ultti tähdätään: pidä ultti pohjassa niin näet ryntäysviivan (minne se vie)
## ennen kuin päästät. Botit ja varapolku käyttävät välittömästi.
func _ult_is_held() -> bool:
	return true


func _ult_preview_line() -> float:
	return RUSH_SPEED * RUSH_DUR


## Ultimate: Vesipatsas — ryntää vedellä eteen (tähtäyssuuntaan, sisäseinien läpi),
## nostaa lähiviholliset vesipyörteeseen ja iskee heidät alas vahingolla ja
## tainnutuksella.
func _ultimate(dir: Vector2) -> void:
	var d: Vector2 = dir if dir.length() > 0.1 else aim
	arena.popup(global_position + Vector2(0, -84), "VESIPATSAS!", Palette.glow(Color("4ad4ff"), 1.6), 26)
	AudioMgr.play("wave", 0.05, -2.0)
	arena.shake(0.35)
	dash(d, RUSH_SPEED, RUSH_DUR, true, true)   # phase_walls: ryntäys menee seinien läpi
	Fx.burst(arena, global_position, Palette.glow(Color("4ad4ff"), 1.5), 16, 300.0, 0.5, 6.0)
	_rush_slam()


func _rush_slam() -> void:
	await get_tree().create_timer(RUSH_DUR).timeout
	if not is_inside_tree() or not alive:
		return
	_act("ult")   # awaitin jälkeen: palauta konteksti (nosto-stun ilman vahinkoa)
	var center := global_position
	arena.shake(0.3)
	AudioMgr.play("wave", 0.1, 1.0)
	# Näkyvä vesipyörre: imee viholliset keskelle. Kestää nosto- + iskuvaiheen yli,
	# joten tainnutuksen aikana näkee selvästi mitä tapahtuu.
	Fx.vortex(arena, center, Color("4ad4ff"), RUSH_RADIUS * 0.9, 1.05)
	# Nosta viholliset vesipatsaan päälle: vedä keskelle, tainnuta, "ilmaan".
	var lifted: Array = []
	for enemy in arena.heroes_in_circle(center, RUSH_RADIUS):
		if enemy.team == team:
			continue
		var toward: Vector2 = center - enemy.global_position
		if toward.length() > 1.0:
			enemy.dash(toward.normalized(), 320.0, 0.15, false)
		enemy.apply_stun(LIFT_STUN + SLAM_STUN)
		enemy.visual.squash(0.6, 1.6)
		lifted.append(enemy)
		Fx.ring(arena, enemy.global_position, Palette.glow(Color("bfeaf7"), 1.5), 40.0, 0.45, 5.0)
	# Vesipatsas keskellä
	Fx.ring(arena, center, Palette.glow(Color("4ad4ff"), 1.7), 120.0, 0.5, 9.0)
	Fx.burst(arena, center, Palette.glow(Color("bfeaf7"), 1.4), 20, 200.0, 0.5, 6.0)
	_act_end()   # sulje nosto-vaiheen ikkuna ennen awaitia (ei roiku Tidella)
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree() or not alive:
		return
	_act("ult")   # awaitin jälkeen: palauta konteksti slam-vahingolle/-stunille
	# Iske alas: vahinko + tainnutus + isku ulospäin.
	arena.shake(0.5)
	AudioMgr.play("wave", 0.05, -3.0)
	Fx.ring(arena, center, Palette.glow(Color("4ad4ff"), 1.7), RUSH_RADIUS, 0.5, 10.0)
	for enemy in lifted:
		if not is_instance_valid(enemy) or not enemy.alive:
			continue
		var away: Vector2 = enemy.global_position - center
		if away.length() < 1.0:
			away = Vector2.DOWN
		deal_damage_to(enemy, SLAM_DMG, 260.0, away.normalized())
		enemy.apply_stun(SLAM_STUN)
		enemy.visual.squash(1.5, 0.6)
		Fx.burst(arena, enemy.global_position, Palette.glow(Color("4ad4ff"), 1.6), 12, 260.0, 0.45, 6.0)
	_act_end()


func _passive_update(delta: float) -> void:
	if haste_timer > 0.0 and hp < max_hp:
		hp = minf(hp + 5.0 * delta, max_hp)
	# Syöksylataukset palautuvat hitaasti yksitellen.
	if ammo < ammo_max:
		_dash_recharge -= delta
		if _dash_recharge <= 0.0:
			ammo += 1
			_dash_recharge = DASH_RECHARGE
