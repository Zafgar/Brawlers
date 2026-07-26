class_name RankPromoScene
extends Control
## Ranked-ottelun jälkeinen virstanpylväskohtaus: divisioonan nousu, TASON
## vaihtuminen, promootiosarjan eteneminen, sarjan kaatuminen, pudotus ja
## suojapeli. Kohtaus pyörii tulosruudun EDELLÄ ja luovuttaa vuoron eteenpäin
## kutsujan antamalla takaisinkutsulla.
##
## Useampi paikallinen ihminen = useampi kohtaus: jono käydään läpi yksi
## kerrallaan ja jokaisen yläreunassa lukee kenen kiipeämisestä on kyse.
##
## Kaikki piirretään koodilla samaan tapaan kuin muissakin valikoissa. Aikajana
## on kirjoitettu auki sekunteina (_seg-apuri poimii osuuden), jotta rytmiä voi
## säätää yhdestä paikasta. Mikä tahansa painike ohittaa käynnissä olevan
## kohtauksen.
##
## Aikajanat sekunteina:
##   division   3.2  LP-palkki täyteen -> purske -> jalustan merkki syttyy
##   tier       6.2  pimennys -> vanha tunnus halkeaa -> valopatsas ->
##                   uusi tunnus kootaan osa kerrallaan -> paineaalto -> banneri
##   promo_start 3.2 kolme tyhjää ruutua napsahtaa esiin tavoitetunnuksen eteen
##   promo_game  2.8 uusin ruutu napsahtaa: kultainen rasti tai punainen risti
##   promo_lost  3.2 viimeinen risti -> arvokas häivytys -> "LP 75"
##   demote      2.6 tunnus himmenee askeleen, ei pilkkaa
##   shield      2.0 pieni ilmoitus suojapelistä

const DURATION := {
	"division": 3.2, "tier": 6.2, "promo_start": 3.2, "promo_game": 2.8,
	"promo_lost": 3.2, "demote": 2.6, "shield": 2.0,
}
const SKIP_GUARD := 0.35              # ottelun viimeinen napinpainallus ei saa ohittaa
const SERIES := 3                     # promootiosarjan ruudut

var _queue: Array = []
var _index := 0
var _t := 0.0                         # nykyisen kohtauksen aika
var _time := 0.0                      # kokonaisaika (tyhjäkäyntianimaatiot)
var _shake := Vector2.ZERO
var _fired: Dictionary = {}           # jo soitetut äänivihjeet (avain per kohtaus)
var _finished := false
var _on_done := Callable()


# --- Jonon rakentaminen ---

## Onko tuloksessa jotain näytettävää?
static func has_milestone(res: Dictionary) -> bool:
	return _kind_of(res) != ""


## Ottelun tuloksista kohtausjono. Tyhjä jono = suoraan tulosruutuun.
static func build_queue(results: Array) -> Array:
	var queue: Array = []
	for entry in results:
		if not (entry is Dictionary):
			continue
		var res: Dictionary = entry
		var kind: String = _kind_of(res)
		if kind == "":
			continue
		queue.append({"kind": kind, "res": res, "name": str(res.get("name", ""))})
	return queue


## Yhden tuloksen tärkein tapahtuma. Yhdestä ottelusta syntyy enintään yksi
## kohtaus: ylennykset ohittavat sarjatilanteet, ne pudotuksen ja se suojan.
static func _kind_of(res: Dictionary) -> String:
	var promoted: String = str(res.get("promoted", ""))
	if promoted == "tier":
		return "tier"
	if promoted == "division":
		return "division"
	var state: String = str(res.get("promo_state", ""))
	if state == "started":
		return "promo_start"
	if state == "running":
		return "promo_game"
	if bool(res.get("promo_failed", false)) or state == "lost":
		return "promo_lost"
	if bool(res.get("demoted", false)):
		return "demote"
	if bool(res.get("shield_used", false)):
		return "shield"
	return ""


# --- Elinkaari ---

## results = Game.last_ranked_results, done = mitä tehdään kohtausten jälkeen.
func setup(results: Array, done: Callable) -> void:
	_queue = build_queue(results)
	_on_done = done


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	AudioMgr.play_music_pool("menu")
	if _queue.is_empty():
		_finish()


func _process(delta: float) -> void:
	_time += delta
	if _finished:
		return
	_t += delta
	_update_shake(delta)
	_play_cues()
	if _t >= _duration():
		_next()
	queue_redraw()


func _duration() -> float:
	var kind: String = _kind()
	if kind == "":
		return 0.1
	return float(DURATION.get(kind, 2.5))


func _next() -> void:
	_index += 1
	_t = 0.0
	_shake = Vector2.ZERO
	_fired.clear()
	if _index >= _queue.size():
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_shake = Vector2.ZERO
	# Vaihto tehdään seuraavalla ruudulla: tämä solmu on parhaillaan omassa
	# _process-kutsussaan eikä sitä pidä vapauttaa kesken kaiken.
	if _on_done.is_valid():
		_on_done.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _finished or _time < SKIP_GUARD:
		return
	var pressed: bool = false
	if event is InputEventKey:
		var key: InputEventKey = event
		pressed = key.pressed and not key.echo
	elif event is InputEventJoypadButton:
		var pad: InputEventJoypadButton = event
		pressed = pad.pressed
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		pressed = mouse.pressed
	if not pressed:
		return
	AudioMgr.play("ui_back", 0.02, -6.0)
	_next()


# --- Nykyisen kohtauksen tiedot ---

func _entry() -> Dictionary:
	if _index < 0 or _index >= _queue.size():
		return {}
	var entry: Dictionary = _queue[_index]
	return entry


func _kind() -> String:
	return str(_entry().get("kind", ""))


func _res() -> Dictionary:
	var res: Dictionary = {}
	var raw: Variant = _entry().get("res", {})
	if raw is Dictionary:
		res = raw
	return res


## Promo-sarjan jo pelatut ottelut. Ratkenneesta sarjasta säännöt tyhjentävät
## tilan, joten voitettu sarja näytetään kahtena voittona ja kaatunut kahtena
## tappiona — juuri se mikä sarjan ratkaisi.
func _promo_games(res: Dictionary) -> Array:
	var kind: String = _kind()
	if kind == "tier":
		return [true, true]
	if kind == "promo_lost":
		return [false, false]
	var promo: Dictionary = {}
	var promo_raw: Variant = res.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	var games: Array = []
	var games_raw: Variant = promo.get("games", [])
	if games_raw is Array:
		games = games_raw
	return games


# --- Aika-apurit ---

## Osuus aikavälistä [a, b]: 0 ennen, 1 jälkeen.
func _seg(a: float, b: float) -> float:
	if b <= a:
		return 1.0 if _t >= b else 0.0
	return clampf((_t - a) / (b - a), 0.0, 1.0)


static func _ease_out(x: float) -> float:
	var f: float = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - f, 3.0)


static func _ease_in(x: float) -> float:
	var f: float = clampf(x, 0.0, 1.0)
	return f * f


## Sisääntulo joka käy hetken yli tavoitekoon.
static func _pop(x: float) -> float:
	var f: float = clampf(x, 0.0, 1.0)
	return _ease_out(f) * (1.0 + 0.22 * sin(f * PI))


func _scene_alpha() -> float:
	var dur: float = _duration()
	return clampf(minf(_t / 0.26, (dur - _t) / 0.30), 0.0, 1.0)


# --- Äänet ja tärinä ---

func _cue(id: String, at: float, sound: String, db := 0.0, pitch := 0.06) -> void:
	if _t < at or _fired.has(id):
		return
	_fired[id] = true
	AudioMgr.play(sound, pitch, db)


## Kertaalleen laukeava musiikkimotiivi (duckaa taustabiisin alleen).
func _music_cue(id: String, at: float, cue: String) -> void:
	if _t < at or _fired.has(id):
		return
	_fired[id] = true
	AudioMgr.music_cue(cue)


func _play_cues() -> void:
	match _kind():
		"division":
			_cue("t1", 0.40, "count_tick", -8.0)
			_cue("t2", 0.72, "count_tick", -6.0)
			_cue("t3", 1.02, "count_tick", -4.0)
			_cue("burst", 1.15, "promo_div_up", -2.0)
			_music_cue("motif", 1.15, "promo_division")
			_cue("banner", 1.40, "rank_hub_confirm", -4.0)
		"tier":
			_cue("low", 0.15, "heartbeat", -4.0)
			_cue("crack", 0.95, "tower_crack", -1.0)
			_cue("break", 1.55, "crystal_break", -1.0)
			_cue("light", 1.80, "light", -2.0)
			_cue("rise", 2.35, "ult_unlock", -4.0)
			_cue("bless", 2.70, "promo_tier_up", 0.0)
			_music_cue("motif", 2.70, "promo_tier")
			_cue("boom", 3.50, "crescendo", -2.0)
			_cue("fanfare", 3.64, "promo_slot_win", -4.0)
		"promo_start":
			_cue("open", 0.05, "rank_hub_open", -2.0)
			_cue("s1", 0.50, "ui_lock", -4.0)
			_cue("s2", 0.75, "ui_lock", -3.0)
			_cue("s3", 1.00, "ui_lock", -2.0)
			_cue("go", 1.40, "rank_hub_confirm", -2.0)
		"promo_game":
			_cue("open", 0.05, "rank_hub_open", -5.0)
			if bool(_last_game_won()):
				_cue("snap", 0.55, "promo_slot_win", 0.0)
				_cue("win", 0.78, "score", -4.0)
			else:
				_cue("snap", 0.55, "promo_slot_loss", -1.0)
		"promo_lost":
			_cue("open", 0.05, "rank_hub_open", -6.0)
			_cue("snap", 0.50, "promo_slot_loss", -2.0)
			_cue("fade", 1.25, "promo_failed", -2.0)
			_cue("low", 1.40, "heartbeat", -9.0)
		"demote":
			_cue("back", 0.30, "promo_demote", -2.0)
			_cue("crack", 0.60, "tower_crack", -9.0)
		"shield":
			_cue("shield", 0.15, "promo_shield", -2.0)


func _last_game_won() -> bool:
	var games: Array = _promo_games(_res())
	if games.is_empty():
		return false
	return bool(games[games.size() - 1])


## Tärinä on kohtauksen oma (areenakameraa ei ole): koko piirto siirtyy
## _shaken verran. Asetuksissa pois kytketty tärinä kunnioitetaan.
func _update_shake(delta: float) -> void:
	var amount: float = 0.0
	if _kind() == "tier":
		amount = _seg(0.90, 1.55) * 7.0
		if _t >= 1.55:
			amount = maxf(amount, 13.0 * (1.0 - _seg(1.55, 1.95)))
		if _t >= 3.50:
			amount = maxf(amount, 15.0 * (1.0 - _seg(3.50, 3.95)))
	if amount <= 0.05 or not bool(Game.options.get("shake", true)):
		_shake = _shake.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		return
	_shake = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))


# --- Yhteiset piirtoapurit ---

func _card(rect: Rect2, bg: Color, border: Color, bw: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(maxf(bw, 0.0)))
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.draw(get_canvas_item(), rect)


## Pelaajan nimi kohtauksen yläreunaan — sohvalla voi olla useampi kiipeäjä.
func _draw_header(alpha: float) -> void:
	var pname: String = str(_entry().get("name", ""))
	UiKit.draw_text(self, Vector2(960, 70), "RANKED", 18,
		Palette.with_alpha(Palette.TEXT_DIM, alpha * 0.9), true)
	if pname != "":
		UiKit.draw_text(self, Vector2(960, 112), pname.to_upper(), 38,
			Palette.with_alpha(Palette.GOLD, alpha), true, 5)
	if _queue.size() > 1:
		UiKit.draw_text(self, Vector2(960, 148),
			"PELAAJA %d / %d" % [_index + 1, _queue.size()], 16,
			Palette.with_alpha(Palette.TEXT_DIM, alpha * 0.8), true)


func _draw_skip_hint(alpha: float) -> void:
	UiKit.draw_text(self, Vector2(960, 1042), "MIKÄ TAHANSA PAINIKE OHITTAA", 16,
		Palette.with_alpha(Palette.TEXT_DIM, alpha * 0.55), true)


## LP-palkki: tausta, täyttö, kärjen hehku ja lukema.
func _draw_lp_bar(center: Vector2, w: float, h: float, value: float, col: Color,
		alpha: float, flash := 0.0) -> void:
	var rect := Rect2(center.x - w / 2.0, center.y - h / 2.0, w, h)
	_card(rect, Palette.with_alpha(Color(0.02, 0.03, 0.07, 1.0), 0.88 * alpha),
		Palette.with_alpha(col, 0.55 * alpha), 2, h / 2.0)
	var f: float = clampf(value / float(RankedRules.LP_MAX), 0.0, 1.0)
	if f > 0.004:
		var inner := Rect2(rect.position.x + 4.0, rect.position.y + 4.0,
			(w - 8.0) * f, h - 8.0)
		_card(inner, Palette.with_alpha(Palette.glow(col, 1.25), alpha),
			Color(0, 0, 0, 0), 0, (h - 8.0) / 2.0)
		draw_circle(Vector2(inner.end.x, rect.get_center().y), h * 0.52,
			Palette.with_alpha(Palette.glow(col, 1.5), 0.30 * alpha))
	if flash > 0.01:
		_card(rect, Palette.with_alpha(Color.WHITE, 0.65 * flash * alpha),
			Color(0, 0, 0, 0), 0, h / 2.0)
	UiKit.draw_text(self, center, "%d / %d LP" % [int(round(value)), RankedRules.LP_MAX],
		int(h * 0.52), Palette.with_alpha(Palette.TEXT_MAIN, alpha), true, 3)


## Ilmestyvä pääbanneri: hehku, otsikko, alaviiva ja alaotsikko.
func _draw_banner(center: Vector2, text: String, sub: String, col: Color,
		appear: float, alpha: float, size := 74) -> void:
	if appear <= 0.005:
		return
	var pop: float = _pop(appear)
	var fs: int = maxi(int(float(size) * pop), 8)
	draw_circle(center, 340.0 * pop, Palette.with_alpha(col, 0.06 * alpha * appear))
	UiKit.draw_text(self, center, text, fs,
		Palette.with_alpha(Palette.glow(col, 1.25), alpha), true,
		maxi(int(float(fs) / 8.0), 2))
	var uw: float = 460.0 * _ease_out(appear)
	draw_rect(Rect2(center.x - uw / 2.0, center.y + float(size) * 0.44, uw, 5.0),
		Palette.with_alpha(Palette.glow(col, 1.3), alpha * appear))
	if sub != "":
		UiKit.draw_text(self, center + Vector2(0, float(size) * 0.86), sub,
			int(float(size) * 0.40), Palette.with_alpha(Palette.TEXT_MAIN, alpha * appear),
			true, 3)


## Laajeneva paineaalto.
func _draw_ring(center: Vector2, prog: float, max_r: float, col: Color,
		alpha: float) -> void:
	if prog <= 0.0 or prog >= 1.0:
		return
	var rad: float = max_r * _ease_out(prog)
	var fade: float = (1.0 - prog) * alpha
	draw_arc(center, rad, 0.0, TAU, 72, Palette.with_alpha(Palette.glow(col, 1.4), fade),
		maxf(16.0 * (1.0 - prog), 1.0), true)
	draw_arc(center, rad * 0.88, 0.0, TAU, 72,
		Palette.with_alpha(Color.WHITE, fade * 0.5), maxf(5.0 * (1.0 - prog), 1.0), true)


## Kimallepurske: säteittäin lentäviä tähtiä.
func _draw_burst(center: Vector2, prog: float, reach: float, col: Color,
		alpha: float, count := 18) -> void:
	if prog <= 0.0 or prog >= 1.0:
		return
	var fade: float = (1.0 - prog) * alpha
	for i in range(count):
		var ang: float = TAU * float(i) / float(count) + float(i) * 0.13
		var dist: float = reach * _ease_out(prog) * (0.55 + 0.45 * sin(float(i) * 2.3))
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
		var size: float = reach * 0.055 * (1.0 - prog)
		_star4(pos, size * 2.0, Palette.with_alpha(col, fade * 0.35))
		_star4(pos, size, Palette.with_alpha(Color.WHITE, fade))


func _star4(c: Vector2, r: float, col: Color) -> void:
	if r <= 0.4:
		return
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.24, -r * 0.24),
		c + Vector2(r, 0), c + Vector2(r * 0.24, r * 0.24),
		c + Vector2(0, r), c + Vector2(-r * 0.24, r * 0.24),
		c + Vector2(-r, 0), c + Vector2(-r * 0.24, -r * 0.24)]), col)


## Promootiosarjan kolme ruutua. games = jo pelatut ottelut (true = voitto),
## reveal = kuinka moni ruutu on jo napsahtanut paikalleen (liukuluku).
func _draw_slots(center: Vector2, games: Array, reveal: float, alpha: float,
		box := 96.0) -> void:
	var gap: float = box * 0.36
	var total: float = float(SERIES) * box + float(SERIES - 1) * gap
	for i in range(SERIES):
		var pop: float = clampf(reveal - float(i), 0.0, 1.0)
		if pop <= 0.005:
			continue
		var scale: float = _pop(pop)
		var side: float = box * scale
		var pos := Vector2(center.x - total / 2.0 + box * 0.5 + float(i) * (box + gap),
			center.y)
		var rect := Rect2(pos.x - side / 2.0, pos.y - side / 2.0, side, side)
		var played: bool = i < games.size()
		var won: bool = played and bool(games[i])
		var tint: Color = Palette.TEXT_DIM
		if played:
			tint = Palette.GOLD if won else Palette.BAD
		_card(rect, Palette.with_alpha(Color(0.02, 0.03, 0.08, 1.0), 0.85 * alpha),
			Palette.with_alpha(tint, (0.45 if not played else 0.95) * alpha),
			3, side * 0.22)
		if not played:
			draw_circle(pos, side * 0.10, Palette.with_alpha(Palette.TEXT_DIM, 0.3 * alpha))
			continue
		var mark: float = side * 0.26
		if won:
			draw_circle(pos, side * 0.40, Palette.with_alpha(Palette.GOLD, 0.16 * alpha))
			draw_line(pos + Vector2(-mark, 0), pos + Vector2(-mark * 0.25, mark * 0.72),
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4), alpha),
				maxf(side * 0.10, 2.0), true)
			draw_line(pos + Vector2(-mark * 0.25, mark * 0.72), pos + Vector2(mark, -mark * 0.7),
				Palette.with_alpha(Palette.glow(Palette.GOLD, 1.4), alpha),
				maxf(side * 0.10, 2.0), true)
		else:
			draw_line(pos + Vector2(-mark, -mark), pos + Vector2(mark, mark),
				Palette.with_alpha(Palette.BAD, 0.9 * alpha), maxf(side * 0.09, 2.0), true)
			draw_line(pos + Vector2(mark, -mark), pos + Vector2(-mark, mark),
				Palette.with_alpha(Palette.BAD, 0.9 * alpha), maxf(side * 0.09, 2.0), true)


# --- Piirto ---

func _draw() -> void:
	if _queue.is_empty() or _index >= _queue.size():
		return
	draw_set_transform(_shake, 0.0, Vector2.ONE)
	var res: Dictionary = _res()
	var alpha: float = _scene_alpha()
	match _kind():
		"division":
			_draw_division(res, alpha)
		"tier":
			_draw_tier_up(res, alpha)
		"promo_start":
			_draw_promo_start(res, alpha)
		"promo_game":
			_draw_promo_game(res, alpha)
		"promo_lost":
			_draw_promo_lost(res, alpha)
		"demote":
			_draw_demote(res, alpha)
		"shield":
			_draw_shield(res, alpha)
	_draw_header(alpha)
	_draw_skip_hint(alpha)


## Tumma huntu taustan päälle.
func _veil(amount: float) -> void:
	if amount <= 0.005:
		return
	draw_rect(Rect2(-400, -400, 2720, 1880), Color(0.015, 0.02, 0.05, clampf(amount, 0.0, 1.0)))


# --- DIVISIOONA YLÖS ---

func _draw_division(res: Dictionary, alpha: float) -> void:
	var rank_before: int = int(res.get("rank_before", 0))
	var rank_after: int = int(res.get("rank_after", 0))
	var lp_before: float = float(int(res.get("lp_before", 0)))
	var lp_after: float = float(int(res.get("lp_after", 0)))
	var col: Color = BotRank.rank_color(rank_after)
	var center := Vector2(960, 404)
	_veil(0.55 * alpha)

	# LP kiipeää sataan, purskahtaa ja putoaa uuden divisioonan lähtötasoon.
	var rise: float = _seg(0.35, 1.15)
	var drop: float = _seg(1.32, 1.78)
	var value: float = lerpf(lp_before, float(RankedRules.LP_MAX), _ease_out(rise))
	if _t >= 1.32:
		value = lerpf(0.0, lp_after, _ease_out(drop))
	var flash: float = 1.0 - _seg(1.15, 1.42)
	if _t < 1.15:
		flash = 0.0

	# Jalustan merkki syttyy yhden askeleen eteenpäin.
	var pips_before: float = float(rank_before % BotRank.DIVISIONS + 1)
	var pips_after: float = float(rank_after % BotRank.DIVISIONS + 1)
	var pip_fill: float = lerpf(pips_before, pips_after, _ease_out(_seg(1.30, 1.72)))

	draw_circle(center, 300.0, Palette.with_alpha(col, (0.05 + 0.05 * rise) * alpha))
	RankEmblem.draw_ex(self, rank_after, center, 168.0, _time, alpha, 1.0, pip_fill)
	_draw_ring(center, _seg(1.15, 1.85), 520.0, col, alpha)
	_draw_burst(center, _seg(1.15, 2.05), 460.0, col, alpha, 20)

	_draw_lp_bar(Vector2(960, 664), 720.0, 42.0, value, col, alpha, flash)
	_draw_banner(Vector2(960, 800), "YLENNYS — %s" % BotRank.rank_name(rank_after),
		"DIVISIOONA NOUSI", Palette.GOLD, _seg(1.38, 1.95), alpha, 66)


# --- UUSI TASO (iso kohtaus) ---

func _draw_tier_up(res: Dictionary, alpha: float) -> void:
	var rank_before: int = int(res.get("rank_before", 0))
	var rank_after: int = int(res.get("rank_after", 0))
	var old_tier: int = BotRank.tier_of(rank_before)
	var new_tier: int = BotRank.tier_of(rank_after)
	var col: Color = BotRank.tier_color(new_tier)
	var center := Vector2(960, 452)

	# 1) Pimennys syvenee koko kohtauksen ajan.
	_veil((0.45 + 0.45 * _seg(0.0, 1.6)) * alpha)

	# 2) Voitettu promootiosarja kuitataan lyhyesti ennen halkeamista.
	var series_fade: float = 1.0 - _seg(0.85, 1.30)
	if series_fade > 0.01:
		_draw_slots(Vector2(960, 232), _promo_games(res), 3.0,
			alpha * series_fade * 0.9, 62.0)
		UiKit.draw_text(self, Vector2(960, 300), "PROMOOTIOSARJA VOITETTU", 22,
			Palette.with_alpha(Palette.GOLD, alpha * series_fade), true, 3)

	# 3) Vanha tunnus halkeaa ja hajoaa sirpaleiksi.
	var shatter: float = _seg(1.50, 2.20)
	var old_alpha: float = alpha * (1.0 - _seg(1.50, 1.80))
	if old_alpha > 0.01:
		RankEmblem.draw_ex(self, rank_before, center, 172.0, _time, old_alpha, 1.0, -1.0)
		_draw_cracks(center, 172.0, _seg(0.90, 1.52), old_alpha)
	if shatter > 0.0 and shatter < 1.0:
		_draw_shards(center, 172.0, old_tier, shatter, alpha)

	# 4) Valopatsas nousee lattiasta ja tuo uuden tason mukanaan.
	var column: float = _seg(1.70, 2.75)
	if column > 0.0 and _t < 4.4:
		_draw_light_column(center, column, alpha * (1.0 - _seg(3.60, 4.40)), col)
		_draw_rising_sparks(center, _seg(1.70, 4.40), alpha * (1.0 - _seg(3.80, 4.40)), col)

	# 5) Uusi tunnus kootaan osa kerrallaan, säteet levittäytyvät ympärille.
	var build: float = _ease_out(_seg(2.60, 4.20))
	if build > 0.0:
		var halo: float = _seg(2.60, 3.60)
		draw_circle(center, 260.0 + 120.0 * halo,
			Palette.with_alpha(col, 0.10 * halo * alpha))
		for i in range(18):
			var ang: float = TAU * float(i) / 18.0 + _time * 0.14
			var reach: float = 240.0 + 300.0 * halo * (0.6 + 0.4 * sin(float(i) * 1.9))
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(cos(ang), sin(ang)) * 190.0
					+ Vector2(-sin(ang), cos(ang)) * 16.0,
				center + Vector2(cos(ang), sin(ang)) * reach,
				center + Vector2(cos(ang), sin(ang)) * 190.0
					- Vector2(-sin(ang), cos(ang)) * 16.0]),
				Palette.with_alpha(col, 0.10 * halo * alpha))
		RankEmblem.draw_ex(self, rank_after, center, 212.0, _time, alpha, build, -1.0)

	# 6) Paineaalto ja banneri.
	_draw_ring(center, _seg(3.50, 4.30), 900.0, col, alpha)
	_draw_burst(center, _seg(3.50, 4.60), 720.0, col, alpha, 26)
	var tier_name: String = str(BotRank.TIER_NAMES[clampi(new_tier, 0,
		BotRank.TIER_NAMES.size() - 1)]).to_upper()
	_draw_banner(Vector2(960, 858), "UUSI TASO — %s" % tier_name,
		BotRank.rank_name(rank_after), col, _seg(3.60, 4.35), alpha, 84)


## Halkeamat leviävät keskeltä ulos.
func _draw_cracks(center: Vector2, r: float, prog: float, alpha: float) -> void:
	if prog <= 0.01:
		return
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0 + 0.35
		var pts := PackedVector2Array()
		var p := center
		pts.append(p)
		for k in range(6):
			ang += sin(float(i) * 3.1 + float(k) * 1.7) * 0.42
			p += Vector2(cos(ang), sin(ang)) * r * 0.22 * prog
			pts.append(p)
		draw_polyline(pts, Palette.with_alpha(Color.WHITE, 0.75 * prog * alpha),
			maxf(4.0 * prog, 1.0), true)
		draw_polyline(pts, Palette.with_alpha(Color(0.02, 0.02, 0.05, 1.0),
			0.5 * prog * alpha), maxf(1.6 * prog, 1.0), true)


## Sirpaleet lentävät ulos ja putoavat.
func _draw_shards(center: Vector2, r: float, tier: int, prog: float, alpha: float) -> void:
	var grad: Array = RankEmblem.tier_gradient(tier)
	var deep: Color = grad[0]
	var base: Color = grad[1]
	for i in range(16):
		var ang: float = TAU * float(i) / 16.0 + 0.2
		var dist: float = r * prog * (1.5 + 0.8 * sin(float(i) * 2.1))
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist \
			+ Vector2(0, prog * prog * r * 0.7)
		var rot: float = prog * (2.2 + float(i % 5) * 0.7)
		var s: float = r * 0.22 * (1.0 - prog * 0.35)
		draw_colored_polygon(PackedVector2Array([
			pos + Vector2(0, -s).rotated(rot),
			pos + Vector2(s * 0.82, s * 0.62).rotated(rot),
			pos + Vector2(-s * 0.70, s * 0.52).rotated(rot)]),
			Palette.with_alpha(base if i % 2 == 0 else deep, (1.0 - prog) * alpha))


## Valopatsas nousee ruudun alareunasta tunnuksen kohdalle.
func _draw_light_column(center: Vector2, prog: float, alpha: float, col: Color) -> void:
	var top: float = lerpf(1120.0, center.y - 90.0, _ease_out(prog))
	var w: float = 120.0 * (0.35 + 0.65 * sin(clampf(prog, 0.0, 1.0) * PI * 0.85))
	draw_colored_polygon(PackedVector2Array([
		Vector2(960.0 - w * 1.9, 1140.0), Vector2(960.0 - w * 0.35, top),
		Vector2(960.0 + w * 0.35, top), Vector2(960.0 + w * 1.9, 1140.0)]),
		Palette.with_alpha(col, 0.16 * alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(960.0 - w * 0.85, 1140.0), Vector2(960.0 - w * 0.16, top),
		Vector2(960.0 + w * 0.16, top), Vector2(960.0 + w * 0.85, 1140.0)]),
		Palette.with_alpha(Color.WHITE, 0.30 * alpha))
	draw_circle(Vector2(960.0, top), w * 1.2, Palette.with_alpha(col, 0.20 * alpha))


## Nousevia kipinöitä valopatsaan mukana.
func _draw_rising_sparks(center: Vector2, prog: float, alpha: float, col: Color) -> void:
	if prog <= 0.0:
		return
	for i in range(22):
		var phase: float = fmod(_time * 0.55 + float(i) * 0.045, 1.0)
		var x: float = 960.0 + sin(float(i) * 2.7 + _time * 0.6) * 210.0
		var y: float = lerpf(1120.0, center.y - 160.0, phase)
		var fade: float = (1.0 - phase) * prog * alpha
		draw_circle(Vector2(x, y), 3.4 + 2.0 * (1.0 - phase),
			Palette.with_alpha(Palette.glow(col, 1.4), 0.7 * fade))


# --- PROMOOTIOSARJA ALKAA ---

func _draw_promo_start(res: Dictionary, alpha: float) -> void:
	var rank: int = int(res.get("rank_after", 0))
	var promo: Dictionary = {}
	var promo_raw: Variant = res.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	var target: int = clampi(int(promo.get("target_rank", rank + 1)), 0, BotRank.MAX_RANK)
	var col: Color = BotRank.rank_color(target)
	_veil(0.62 * alpha)

	# Tavoitetaso häämöttää kortin takana.
	var glimpse: float = _ease_out(_seg(0.1, 1.2))
	RankEmblem.draw_ex(self, target, Vector2(960, 430), 230.0, _time,
		alpha * 0.20 * glimpse, 1.0, -1.0)

	var card := Rect2(560, 268, 800, 372)
	var appear: float = _pop(_seg(0.05, 0.45))
	if appear > 0.01:
		var scaled := Rect2(card.get_center() - card.size * 0.5 * appear, card.size * appear)
		_card(scaled, Palette.with_alpha(Palette.UI_PANEL, 0.92 * alpha),
			Palette.with_alpha(col, 0.75 * alpha), 3, 22)
	UiKit.draw_text(self, Vector2(960, 330), "PROMOOTIOSARJA", 54,
		Palette.with_alpha(Palette.glow(Palette.GOLD, 1.2), alpha * _seg(0.2, 0.5)), true, 7)
	UiKit.draw_text(self, Vector2(960, 382), "PARAS KOLMESTA", 24,
		Palette.with_alpha(Palette.TEXT_DIM, alpha * _seg(0.25, 0.55)), true)

	_draw_slots(Vector2(960, 500), [], _seg(0.45, 1.15) * 3.0, alpha)

	UiKit.draw_text(self, Vector2(960, 600),
		"Vastassa %s — voita kaksi ja taso vaihtuu." % BotRank.rank_name(target), 22,
		Palette.with_alpha(Palette.TEXT_MAIN, alpha * _seg(1.0, 1.4)), true)
	_draw_banner(Vector2(960, 790), "TÄSTÄ ON KYSE", BotRank.rank_name(target), col,
		_seg(1.40, 2.00), alpha, 52)


# --- PROMOOTIOSARJAN OTTELU ---

func _draw_promo_game(res: Dictionary, alpha: float) -> void:
	var games: Array = _promo_games(res)
	var promo: Dictionary = {}
	var promo_raw: Variant = res.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	var wins: int = int(promo.get("wins", 0))
	var losses: int = int(promo.get("losses", 0))
	var target: int = clampi(int(promo.get("target_rank", int(res.get("rank_after", 0)) + 1)),
		0, BotRank.MAX_RANK)
	var won: bool = _last_game_won()
	var col: Color = Palette.GOLD if won else Palette.BAD
	_veil(0.62 * alpha)

	RankEmblem.draw_ex(self, target, Vector2(960, 430), 230.0, _time, alpha * 0.16, 1.0, -1.0)

	var card := Rect2(560, 268, 800, 372)
	var appear: float = _pop(_seg(0.02, 0.32))
	if appear > 0.01:
		var scaled := Rect2(card.get_center() - card.size * 0.5 * appear, card.size * appear)
		_card(scaled, Palette.with_alpha(Palette.UI_PANEL, 0.92 * alpha),
			Palette.with_alpha(col, 0.7 * alpha), 3, 22)
	UiKit.draw_text(self, Vector2(960, 330), "PROMOOTIOSARJA %d–%d" % [wins, losses], 48,
		Palette.with_alpha(Palette.glow(Palette.GOLD, 1.15), alpha), true, 6)
	UiKit.draw_text(self, Vector2(960, 382), "PARAS KOLMESTA", 22,
		Palette.with_alpha(Palette.TEXT_DIM, alpha), true)

	# Aiemmat ruudut ovat valmiina, uusin napsahtaa paikalleen.
	var played: int = games.size()
	var reveal: float = float(maxi(played - 1, 0)) + _pop(_seg(0.45, 0.85))
	_draw_slots(Vector2(960, 500), games, reveal, alpha)
	if _t >= 0.45:
		var idx: float = float(maxi(played - 1, 0))
		var slot_x: float = 960.0 - (3.0 * 96.0 + 2.0 * 34.56) / 2.0 + 48.0 \
			+ idx * (96.0 + 34.56)
		_draw_ring(Vector2(slot_x, 500.0), _seg(0.50, 1.05), 190.0, col, alpha)

	var need: int = maxi(RankedRules.SERIES_TARGET - wins, 0)
	var tail: String = "Vielä %d voitto tasonvaihtoon." % need
	if need <= 0:
		tail = "Sarja on ratkennut."
	UiKit.draw_text(self, Vector2(960, 600), tail, 22,
		Palette.with_alpha(Palette.TEXT_MAIN, alpha * _seg(0.9, 1.3)), true)
	_draw_banner(Vector2(960, 790), "VOITTO" if won else "TAPPIO",
		"Vastassa %s" % BotRank.rank_name(target), col, _seg(0.95, 1.5), alpha, 50)


# --- PROMOOTIO HYLÄTTY ---

func _draw_promo_lost(res: Dictionary, alpha: float) -> void:
	var lp_after: int = int(res.get("lp_after", RankedRules.PROMO_FAIL_LP))
	var rank: int = int(res.get("rank_after", 0))
	# Arvokas hiipuminen: kortti himmenee eikä ketään pilkata.
	var dim: float = 1.0 - 0.45 * _seg(1.25, 2.10)
	var col: Color = Palette.with_alpha(Palette.BAD, 1.0)
	_veil(0.66 * alpha)

	var card := Rect2(560, 268, 800, 372)
	_card(card, Palette.with_alpha(Palette.UI_PANEL, 0.92 * alpha * dim),
		Palette.with_alpha(Palette.TEXT_DIM, 0.6 * alpha * dim), 3, 22)
	UiKit.draw_text(self, Vector2(960, 330), "PROMOOTIOSARJA", 48,
		Palette.with_alpha(Palette.TEXT_DIM, alpha * dim), true, 6)
	_draw_slots(Vector2(960, 470), _promo_games(res),
		1.0 + _pop(_seg(0.40, 0.80)), alpha * dim)

	UiKit.draw_text(self, Vector2(960, 592), "Sarja jatkuu kun LP on taas täynnä.", 21,
		Palette.with_alpha(Palette.TEXT_DIM, alpha * dim * _seg(1.3, 1.8)), true)
	_draw_banner(Vector2(960, 762), "PROMOOTIO HYLÄTTY",
		"%s %d LP — yritä uudelleen" % [BotRank.rank_name(rank), lp_after],
		col, _seg(1.25, 1.95), alpha * 0.92, 58)


# --- PUDOTUS ---

func _draw_demote(res: Dictionary, alpha: float) -> void:
	var rank_before: int = int(res.get("rank_before", 0))
	var rank_after: int = int(res.get("rank_after", 0))
	var lp_after: int = int(res.get("lp_after", 0))
	var center := Vector2(960, 420)
	var step: float = _ease_out(_seg(0.45, 1.20))
	_veil(0.58 * alpha)

	if BotRank.tier_of(rank_before) == BotRank.tier_of(rank_after):
		# Sama taso: jalustan merkki sammuu yhden askeleen.
		var pips: float = lerpf(float(rank_before % BotRank.DIVISIONS + 1),
			float(rank_after % BotRank.DIVISIONS + 1), step)
		RankEmblem.draw_ex(self, rank_after, center, 156.0, _time,
			alpha * (1.0 - 0.30 * step), 1.0, pips)
	else:
		# Taso vaihtuu: vanha häipyy, alempi tulee tilalle.
		RankEmblem.draw_ex(self, rank_before, center, 156.0, _time,
			alpha * (1.0 - step), 1.0, -1.0)
		RankEmblem.draw_ex(self, rank_after, center, 156.0, _time,
			alpha * step * 0.85, 1.0, -1.0)
	draw_circle(center, 250.0, Palette.with_alpha(Color(0.01, 0.02, 0.05, 1.0),
		0.22 * step * alpha))

	_draw_banner(Vector2(960, 720), "PUDOTUS — %s" % BotRank.rank_name(rank_after),
		"%d LP — nouse takaisin." % lp_after,
		Palette.with_alpha(Palette.TEXT_DIM, 1.0), _seg(0.85, 1.55), alpha, 56)


# --- SUOJAPELI ---

func _draw_shield(res: Dictionary, alpha: float) -> void:
	var rank: int = int(res.get("rank_after", 0))
	var center := Vector2(960, 430)
	_veil(0.50 * alpha)
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
	draw_arc(center, 210.0 + pulse * 8.0, 0.0, TAU, 64,
		Palette.with_alpha(Palette.SHIELD, (0.25 + 0.20 * pulse) * alpha), 4.0, true)
	RankEmblem.draw_ex(self, rank, center, 150.0, _time, alpha, 1.0, -1.0)

	var appear: float = _pop(_seg(0.15, 0.55))
	if appear > 0.01:
		var rect := Rect2(960.0 - 380.0 * appear, 726.0, 760.0 * appear, 108.0)
		_card(rect, Palette.with_alpha(Palette.UI_PANEL, 0.94 * alpha),
			Palette.with_alpha(Palette.SHIELD, 0.8 * alpha), 3, 20)
		if appear > 0.85:
			var badge := Vector2(rect.position.x + 62.0, rect.get_center().y)
			draw_circle(badge, 30.0, Palette.with_alpha(Palette.SHIELD, 0.20 * alpha))
			draw_colored_polygon(PackedVector2Array([
				badge + Vector2(0, -26), badge + Vector2(22, -14),
				badge + Vector2(22, 8), badge + Vector2(0, 27),
				badge + Vector2(-22, 8), badge + Vector2(-22, -14)]),
				Palette.with_alpha(Palette.glow(Palette.SHIELD, 1.2), alpha))
			UiKit.draw_text(self, Vector2(rect.position.x + 118.0, rect.get_center().y - 16.0),
				"SUOJA — LP 0", 30, Palette.with_alpha(Palette.SHIELD, alpha), false, 3)
			UiKit.draw_text(self, Vector2(rect.position.x + 118.0, rect.get_center().y + 20.0),
				"Seuraava tappio pudottaa divisioonan.", 20,
				Palette.with_alpha(Palette.TEXT_DIM, alpha), false)
