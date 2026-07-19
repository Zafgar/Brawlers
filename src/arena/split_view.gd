class_name SplitView
extends Control
## Jaettu ruutu (valinnainen). Maailma renderöidään SubViewporteihin, jotka
## kaikki jakavat saman World2D:n mutta katsovat sitä omilla kameroillaan.
## Näyttö jakautuu dynaamisesti 1–4 osaan sen mukaan, kuinka moneen ryhmään
## ihmispelaajat leviävät: kun he ovat lähekkäin, ruutu on yksi; kun he
## hajaantuvat, jokainen ryhmä (enimmillään neljä) saa oman ruutunsa.
##
## Jokainen ruutu pitää lähellä olevat viholliset näkyvissä, jotta taistelua
## voi seurata omalta ruudulta. HUD piirtyy CanvasLayerina kaikkien päälle.
##
## Otetaan käyttöön Game.options.split_screen. Oletuksena pois -> klassinen
## yksittäiskamera (GameCamera) toimii kuten ennen.

const MAX_PANES := 4
const MARGIN := 260.0
const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.05
const FOLLOW := 3.5
const ZOOM_SPEED := 2.5
const SPLIT_DIST := 1050.0        # ryhmien etäisyys jonka yli -> jako
const MERGE_DIST := 780.0         # ... ja alle jonka -> yhdistys (hystereesi)
const INCLUDE_RADIUS := 640.0     # tämän säteen sisällä olevat viholliset mukaan

var arena = null

var _conts: Array = []            # SubViewportContainer per ruutu
var _vps: Array = []              # SubViewport per ruutu
var _cams: Array = []             # Camera2D per ruutu
var _pane_count := 1
var _prev_group: Dictionary = {}  # sankari -> ryhmäindeksi (hystereesiä varten)
var _snap := false
var _shake := 0.0
var _noise_t := 0.0


func setup(p_arena) -> void:
	arena = p_arena
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in range(MAX_PANES):
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cont)
		var vp := SubViewport.new()
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		cont.add_child(vp)
		var cam := Camera2D.new()
		vp.add_child(cam)
		_conts.append(cont)
		_vps.append(vp)
		_cams.append(cam)

	# Areena elää ruudun 0 viewportissa; muut jakavat saman maailman.
	arena.hosted = true
	arena.split_view = self
	_vps[0].add_child(arena)
	for i in range(1, MAX_PANES):
		_vps[i].world_2d = _vps[0].world_2d

	_pane_count = 1
	_apply_layout()
	resized.connect(_apply_layout)


## Kutsutaan areenan _ready:stä (kartta ja sankarit ovat valmiina). Luodaan HUD
## juuritasolle, tehdään kameroista aktiiviset ja asetetaan ne heti paikoilleen.
func on_arena_ready() -> void:
	var hud := HudLayer.new()
	hud.setup(arena)
	add_child(hud)
	arena.hud = hud
	for cam in _cams:
		cam.make_current()
	var cs := _clusters()
	_pane_count = cs.size()
	_apply_layout()
	for i in range(cs.size()):
		_update_camera(_cams[i], _vps[i], cs[i], 0.0, true)


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if arena == null or arena.heroes.is_empty():
		return
	var cs := _clusters()
	var count: int = cs.size()
	if count != _pane_count:
		_pane_count = count
		_apply_layout()
		_snap = true

	_shake = maxf(_shake - delta * 2.2, 0.0)
	for i in range(count):
		_update_camera(_cams[i], _vps[i], cs[i], delta, _snap)
	_snap = false


# --- Ruutujen asettelu ---

## Näyttää tarvittavan määrän ruutuja ja asettaa ne ruudukkoon. Käyttämättömät
## viewportit sammutetaan (ei renderöintiä) suorituskyvyn vuoksi.
func _apply_layout() -> void:
	var rects := _pane_rects(_pane_count, size)
	for i in range(MAX_PANES):
		var active: bool = i < _pane_count
		_conts[i].visible = active
		_vps[i].render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		if active:
			_conts[i].position = rects[i].position
			_conts[i].size = rects[i].size


## Ruutujen suorakulmiot annetulle määrälle: 1 = koko ruutu, 2 = vasen/oikea,
## 3 = kaksi ylös + yksi leveä alas, 4 = 2x2-ruudukko.
func _pane_rects(count: int, full: Vector2) -> Array:
	var hw := floor(full.x / 2.0)
	var hh := floor(full.y / 2.0)
	match count:
		1:
			return [Rect2(0, 0, full.x, full.y)]
		2:
			return [Rect2(0, 0, hw, full.y), Rect2(hw, 0, full.x - hw, full.y)]
		3:
			return [
				Rect2(0, 0, hw, hh), Rect2(hw, 0, full.x - hw, hh),
				Rect2(0, hh, full.x, full.y - hh)]
		_:
			return [
				Rect2(0, 0, hw, hh), Rect2(hw, 0, full.x - hw, hh),
				Rect2(0, hh, hw, full.y - hh), Rect2(hw, hh, full.x - hw, full.y - hh)]


# --- Ryhmittely (klusterointi) ---

## Ryhmittelee elossa olevat ihmispelaajat 1–4 ryhmään. Jokainen ryhmä saa oman
## ruutunsa. Hystereesi (SPLIT_DIST vs MERGE_DIST parikohtaisesti) estää
## värinän rajalla. Ryhmät järjestetään pelaajanumeron mukaan, jotta ruudut
## eivät vaihda paikkaa.
func _clusters() -> Array:
	var anchors := _human_anchors()
	var groups: Array = []
	if anchors.size() <= 1:
		groups = [anchors] if not anchors.is_empty() else [_fallback_group()]
	else:
		groups = _cluster_by_hysteresis(anchors)
		groups = _cap_groups(groups, MAX_PANES)
	_remember_groups(groups)
	return _sorted_groups(groups)


## Elossa olevat ihmispelaajat (ruutujen ankkurit).
func _human_anchors() -> Array:
	var out: Array = []
	for h in arena.heroes:
		if is_instance_valid(h) and h.alive and h.profile != null and not h.profile.is_bot:
			out.append(h)
	return out


## Vararyhmä kun ihmispelaajia ei ole elossa (esim. kaikki tyrmätty): näytä
## kaikki elossa olevat, tai viime kädessä kaikki sankarit.
func _fallback_group() -> Array:
	var out := _alive_heroes()
	return out if not out.is_empty() else arena.heroes


func _alive_heroes() -> Array:
	var out: Array = []
	for h in arena.heroes:
		if is_instance_valid(h) and h.alive:
			out.append(h)
	return out


## Union-find -klusterointi parikohtaisella hystereesillä: pari yhdistetään
## samaan ruutuun jos etäisyys alittaa kynnyksen (suurempi jos he olivat jo
## samassa ruudussa -> pysyvät helpommin yhdessä).
func _cluster_by_hysteresis(anchors: Array) -> Array:
	var n := anchors.size()
	var parent: Array = []
	for i in range(n):
		parent.append(i)
	for i in range(n):
		for j in range(i + 1, n):
			var same_last := _same_group_last(anchors[i], anchors[j])
			var thr: float = SPLIT_DIST if same_last else MERGE_DIST
			var d: float = anchors[i].global_position.distance_to(anchors[j].global_position)
			if d < thr:
				var ri := _uf_find(parent, i)
				var rj := _uf_find(parent, j)
				if ri != rj:
					parent[ri] = rj
	var buckets: Dictionary = {}
	for i in range(n):
		var r := _uf_find(parent, i)
		if not buckets.has(r):
			buckets[r] = []
		buckets[r].append(anchors[i])
	return buckets.values()


func _uf_find(parent: Array, i: int) -> int:
	var root: int = i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var nxt: int = parent[i]
		parent[i] = root
		i = nxt
	return root


func _same_group_last(a, b) -> bool:
	if not _prev_group.has(a) or not _prev_group.has(b):
		return false
	return _prev_group[a] == _prev_group[b]


## Yhdistää lähimmät ryhmät kunnes niitä on korkeintaan maxn (turvaraja).
func _cap_groups(groups: Array, maxn: int) -> Array:
	while groups.size() > maxn:
		var bi := 0
		var bj := 1
		var best := 1.0e20
		for i in range(groups.size()):
			for j in range(i + 1, groups.size()):
				var d: float = _cluster_center(groups[i]).distance_to(_cluster_center(groups[j]))
				if d < best:
					best = d
					bi = i
					bj = j
		for h in groups[bj]:
			groups[bi].append(h)
		groups.remove_at(bj)
	return groups


func _remember_groups(groups: Array) -> void:
	_prev_group.clear()
	for gi in range(groups.size()):
		for h in groups[gi]:
			_prev_group[h] = gi


## Järjestää ryhmät pienimmän pelaajanumeron mukaan (ruutujen paikat pysyviksi).
func _sorted_groups(groups: Array) -> Array:
	var keyed: Array = []
	for g in groups:
		keyed.append([_group_key(g), g])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for kv in keyed:
		out.append(kv[1])
	return out


func _group_key(g: Array) -> int:
	var k := 9999
	for h in g:
		if is_instance_valid(h) and h.profile != null and not h.profile.is_bot:
			k = mini(k, h.profile.index)
	return k


func _cluster_center(cluster: Array) -> Vector2:
	var c := Vector2.ZERO
	for h in cluster:
		c += h.global_position
	return c / maxf(cluster.size(), 1.0)


## Ruudussa kehystettävät sankarit: ankkurit + lähellä olevat viholliset/omat,
## jotta taistelu näkyy. Yhden ruudun tilassa kehystetään kaikki elossa olevat
## (klassinen kamera), jottei kukaan jää ruudun ulkopuolelle.
func _frame(cluster: Array) -> Array:
	if _pane_count <= 1:
		var everyone := _alive_heroes()
		return everyone if not everyone.is_empty() else cluster
	var framed: Array = cluster.duplicate()
	for h in _alive_heroes():
		if h in cluster:
			continue
		for a in cluster:
			if h.global_position.distance_to(a.global_position) < INCLUDE_RADIUS:
				framed.append(h)
				break
	return framed


# --- Kameran päivitys ---

func _update_camera(cam: Camera2D, vp: SubViewport, cluster: Array, delta: float,
		snap: bool) -> void:
	var framed := _frame(cluster)
	if framed.is_empty():
		return
	var rect := Rect2(framed[0].global_position, Vector2.ONE)
	for h in framed:
		rect = rect.expand(h.global_position)
	rect = rect.grow(MARGIN)

	var vps := Vector2(vp.size)
	if vps.x < 1.0 or vps.y < 1.0:
		vps = Vector2(960.0, 540.0)
	var fit: float = minf(vps.x / rect.size.x, vps.y / rect.size.y)
	var tz: float = clampf(fit, MIN_ZOOM, MAX_ZOOM)
	var target: Vector2 = rect.get_center()

	if snap:
		cam.global_position = target
		cam.zoom = Vector2(tz, tz)
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-FOLLOW * delta))
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
