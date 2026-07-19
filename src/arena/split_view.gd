class_name SplitView
extends Control
## Jaettu ruutu (valinnainen). Maailma renderöidään SubViewportiin. Kun kaikki
## elossa olevat pelaajat mahtuvat yhteen näkymään, ruutu on yksi; kun he
## leviävät kahteen ryhmään (klusteriin), ruutu jakautuu kahtia (vasen/oikea).
## Areena elää SubViewport A:ssa; B jakaa saman World2D:n ja renderöi omasta
## kamerastaan. HUD piirtyy juuritasolla molempien näkymien päälle.
##
## Otetaan käyttöön Game.options.split_screen. Oletuksena pois -> klassinen
## yksittäiskamera (GameCamera) toimii kuten ennen.

const MARGIN := 260.0
const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.05
const FOLLOW := 3.5
const ZOOM_SPEED := 2.5
const SPLIT_DIST := 1050.0        # klustereiden etäisyys jonka yli -> jako
const MERGE_DIST := 780.0         # ... ja alle jonka -> yhdistys (hystereesi)

var arena = null

var _vp_a: SubViewport = null
var _vp_b: SubViewport = null
var _cont_a: SubViewportContainer = null
var _cont_b: SubViewportContainer = null
var _cam_a: Camera2D = null
var _cam_b: Camera2D = null
var _split := false
var _shake := 0.0
var _noise_t := 0.0


func setup(p_arena) -> void:
	arena = p_arena
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cont_a = SubViewportContainer.new()
	_cont_a.stretch = true
	_cont_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cont_a)
	_vp_a = SubViewport.new()
	_vp_a.disable_3d = true
	_vp_a.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cont_a.add_child(_vp_a)

	_cont_b = SubViewportContainer.new()
	_cont_b.stretch = true
	_cont_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cont_b)
	_vp_b = SubViewport.new()
	_vp_b.disable_3d = true
	_vp_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_cont_b.add_child(_vp_b)

	# Areena maailmana A-viewportiin; kamerat kumpaankin viewporttiin.
	arena.hosted = true
	arena.split_view = self
	_vp_a.add_child(arena)
	_cam_a = Camera2D.new()
	_vp_a.add_child(_cam_a)
	_cam_b = Camera2D.new()
	_vp_b.add_child(_cam_b)
	# B jakaa A:n maailman (sama World2D) -> renderöi samat sankarit/kartan.
	_vp_b.world_2d = _vp_a.world_2d

	_apply_layout()
	resized.connect(_apply_sizes)


## Kutsutaan areenan _ready:stä (kartta ja sankarit ovat valmiina). Luodaan HUD
## juuritasolle ja tehdään kameroista aktiiviset.
func on_arena_ready() -> void:
	var hud = HudLayer.new()
	hud.setup(arena)
	add_child(hud)
	arena.hud = hud
	_apply_sizes()
	_cam_a.make_current()
	_cam_b.make_current()
	# Aseta kamerat heti oikeille paikoille (ei nykäystä ruudulle).
	var cs := _clusters()
	if not cs.is_empty() and not cs[0].is_empty():
		_cam_a.global_position = _cluster_center(cs[0])
	if cs.size() >= 2:
		_cam_b.global_position = _cluster_center(cs[1])


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _apply_sizes() -> void:
	var full := size
	if _split:
		var half := Vector2(floor(full.x / 2.0), full.y)
		_cont_a.position = Vector2.ZERO
		_cont_a.size = half
		_cont_b.position = Vector2(half.x, 0.0)
		_cont_b.size = Vector2(full.x - half.x, full.y)
	else:
		_cont_a.position = Vector2.ZERO
		_cont_a.size = full


func _apply_layout() -> void:
	_cont_b.visible = _split
	_apply_sizes()


func _process(delta: float) -> void:
	if arena == null or arena.heroes.is_empty():
		return
	var cs := _clusters()
	var want_split: bool = cs.size() >= 2
	if want_split != _split:
		_split = want_split
		_apply_layout()

	_shake = maxf(_shake - delta * 2.2, 0.0)
	if not cs.is_empty():
		_update_camera(_cam_a, _vp_a, cs[0], delta)
	if _split and cs.size() >= 2:
		_update_camera(_cam_b, _vp_b, cs[1], delta)


## Ryhmittelee elossa olevat sankarit yhteen tai kahteen klusteriin. Hystereesi
## (SPLIT_DIST vs MERGE_DIST) estää värinän. Ryhmä johon heroes[0] kuuluu on aina
## A, jottei näyttö vaihda puolta.
func _clusters() -> Array:
	var alive: Array = []
	for h in arena.heroes:
		if is_instance_valid(h) and h.alive:
			alive.append(h)
	if alive.size() <= 1:
		return [alive if not alive.is_empty() else arena.heroes]

	# Kaukaisin pari = klusterien siemenet.
	var seed_a = alive[0]
	var seed_b = alive[1]
	var best := -1.0
	for i in range(alive.size()):
		for j in range(i + 1, alive.size()):
			var d: float = alive[i].global_position.distance_to(alive[j].global_position)
			if d > best:
				best = d
				seed_a = alive[i]
				seed_b = alive[j]

	var thresh: float = MERGE_DIST if _split else SPLIT_DIST
	if best < thresh:
		return [alive]

	var ga: Array = []
	var gb: Array = []
	for h in alive:
		var da: float = h.global_position.distance_to(seed_a.global_position)
		var db: float = h.global_position.distance_to(seed_b.global_position)
		if da <= db:
			ga.append(h)
		else:
			gb.append(h)
	if gb.is_empty() or ga.is_empty():
		return [alive]
	# Pidä heroes[0]:n ryhmä A-puolella pysyvyyden vuoksi.
	var anchor = arena.heroes[0]
	if anchor in gb:
		var tmp := ga
		ga = gb
		gb = tmp
	return [ga, gb]


func _cluster_center(cluster: Array) -> Vector2:
	var c := Vector2.ZERO
	for h in cluster:
		c += h.global_position
	return c / maxf(cluster.size(), 1.0)


func _update_camera(cam: Camera2D, vp: SubViewport, cluster: Array, delta: float) -> void:
	if cluster.is_empty():
		return
	var rect := Rect2(cluster[0].global_position, Vector2.ONE)
	for h in cluster:
		rect = rect.expand(h.global_position)
	rect = rect.grow(MARGIN)

	var vps := Vector2(vp.size)
	if vps.x < 1.0 or vps.y < 1.0:
		vps = Vector2(960.0, 1080.0)
	var fit: float = minf(vps.x / rect.size.x, vps.y / rect.size.y)
	var tz: float = clampf(fit, MIN_ZOOM, MAX_ZOOM)

	cam.global_position = cam.global_position.lerp(rect.get_center(), 1.0 - exp(-FOLLOW * delta))
	var z: float = lerpf(cam.zoom.x, tz, 1.0 - exp(-ZOOM_SPEED * delta))
	cam.zoom = Vector2(z, z)

	if arena.map != null:
		var hs: Vector2 = arena.map.size() / 2.0
		cam.limit_left = int(-hs.x - 48.0)
		cam.limit_right = int(hs.x + 48.0)
		cam.limit_top = int(-hs.y - 48.0)
		cam.limit_bottom = int(hs.y + 48.0)

	if _shake > 0.001 and Game.options.shake:
		_noise_t += delta * 40.0
		var amp: float = _shake * _shake * 20.0
		cam.offset = Vector2(sin(_noise_t * 1.1) * amp, cos(_noise_t * 0.9) * amp)
	else:
		cam.offset = Vector2.ZERO
