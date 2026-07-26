class_name RankEmblem
## Sarjatasojen tunnukset. Kahdeksan omaa taideteosta, jotka piirretään
## kokonaan koodilla — pelissä ei ole kuvatiedostoja. Sama funktio palvelee
## sekä pientä lobbychippiä (r ~ 16) että ylennyskohtauksen jättitunnusta
## (r ~ 220), joten KAIKKI mitat ovat säteen kerrannaisia.
##
## Piirtoalue on noin keskipiste ± r * 1.30 (kruunut, siivet ja jalusta
## kurkottavat perusympyrän ulkopuolelle). Kutsuja varaa siis tunnukselle
## hieman enemmän tilaa kuin r * 2.
##
## Tasojen prestiisijärjestys näkyy materiaalissa ja tekemisen jäljessä:
##   Wood       karkea kirveellä veistetty lankkukilpi, rautanaulat, sammal
##   Bronze     valettu pronssikilpi, taottu vanne, yksi jalokivi
##   Silver     kiillotetut hopeasiivet kilven ympärillä, pyyhkivä kiilto
##   Gold       laakeriseppele, kruunu ja lämpimät säteet
##   Platinum   kylmä kidelevy, särmät ja revontulihuntu
##   Diamond    hiottu briljantti ja taittuneet valonsirut
##   Champion   obsidiaani, liekki ja feeniks
##   Challenger taivaallinen valokruunu, kiertävät tähdet, nousevat säteet
##
## Divisioona (IV..I) näkyy jalustan neljänä merkkinä: valaistut merkit
## kertovat monennessako divisioonassa ollaan (Wood IV = 1, Wood I = 4).
##
## Jokaisella tunnuksella on hidas oma tyhjäkäyntianimaatio (t = aika
## sekunteina): puu huojuu, pronssi kiiltää, hopea hengittää, kulta säteilee,
## platina väreilee, timantti kimaltaa, liekki lepattaa ja tähdet kiertävät.

const STAGES := 4                    # rakennusanimaation vaiheet (ylennyskohtaus)
const PIPS := 4                      # divisioonamerkkien määrä (= BotRank.DIVISIONS)
const PIP_MIN_RADIUS := 20.0         # tätä pienemmissä tunnuksissa jalusta jätetään pois

# Syvä pohjasävy per taso (varjot, taustalevy).
const DEEP := [
	Color("2e2114"), Color("4a260c"), Color("2f3950"), Color("5b3d09"),
	Color("12354a"), Color("10404a"), Color("120a1c"), Color("241246"),
]
# Hehkuva korkeavalo per taso (kiillot, kärjet, kimallukset).
const BRIGHT := [
	Color("dcc09a"), Color("ffc07a"), Color("ffffff"), Color("fff3c2"),
	Color("e6fbff"), Color("ffffff"), Color("ff8a3c"), Color("fff8dc"),
]
# Tehosteväri per taso (sammal, jalokivi, revontuli, liekki, tähdet).
const ACCENT := [
	Color("5f8a3a"), Color("ff5a45"), Color("9fd8ff"), Color("ff7a5c"),
	Color("7cffd0"), Color("ff7ae0"), Color("ffd24a"), Color("9fd0ff"),
]
const IRON := Color("9aa4b0")         # naulat ja vanteet


# --- Julkiset piirtofunktiot ---

## Yhden rankin tunnus: tason taide + divisioonamerkit.
static func draw(canvas: CanvasItem, rank: int, center: Vector2, r: float, t: float) -> void:
	draw_ex(canvas, rank, center, r, t, 1.0, 1.0, -1.0)


## Pelkkä tason taide ilman divisioonamerkkejä (esim. tier-valikot).
static func draw_tier(canvas: CanvasItem, tier: int, center: Vector2, r: float,
		t: float) -> void:
	_tier_art(canvas, clampi(tier, 0, DEEP.size() - 1), center, r, t, 1.0, 1.0)


## Laajennettu piirto ylennyskohtausta varten.
## alpha    : koko tunnuksen läpinäkyvyys
## build    : 0..1 kokoamisanimaatio (osat ilmestyvät järjestyksessä), 1 = valmis
## pip_fill : valaistujen divisioonamerkkien määrä liukulukuna (-1 = rankista)
static func draw_ex(canvas: CanvasItem, rank: int, center: Vector2, r: float, t: float,
		alpha := 1.0, build := 1.0, pip_fill := -1.0) -> void:
	if alpha <= 0.004 or r <= 0.5:
		return
	var clamped: int = clampi(rank, 0, BotRank.MAX_RANK)
	var tier: int = BotRank.tier_of(clamped)
	_tier_art(canvas, tier, center, r, t, alpha, build)
	if r < PIP_MIN_RADIUS:
		return
	var fill: float = pip_fill
	if fill < 0.0:
		fill = float(clamped % BotRank.DIVISIONS + 1)
	_draw_pips(canvas, tier, center, r, t, alpha * _stage(build, 3), fill)


## Tason kolme sävyä: [syvä, perus, kirkas]. Ylennyskohtaus värittää näillä
## sirpaleensa ja valopatsaansa.
static func tier_gradient(tier: int) -> Array:
	var i: int = clampi(tier, 0, DEEP.size() - 1)
	var deep: Color = DEEP[i]
	var bright: Color = BRIGHT[i]
	return [deep, BotRank.tier_color(i), bright]


## Tason tehosteväri (jalokivi, liekki, revontuli).
static func accent(tier: int) -> Color:
	var col: Color = ACCENT[clampi(tier, 0, ACCENT.size() - 1)]
	return col


## Pieni sarjamerkki tekstillä: "◈ Gold II" tason väreissä. pos on merkin
## vasen reuna (tai keskipiste kun centered = true), pystysuunnassa keskitetty.
## Palauttaa merkin leveyden, jotta kutsuja voi asemoida seuraavan elementin.
static func draw_chip(canvas: CanvasItem, rank: int, pos: Vector2, height := 28.0,
		t := 0.0, centered := false) -> float:
	var clamped: int = clampi(rank, 0, BotRank.MAX_RANK)
	var tier: int = BotRank.tier_of(clamped)
	var text: String = BotRank.rank_name(clamped)
	var font := ThemeDB.fallback_font
	var fs: int = maxi(int(height * 0.50), 8)
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w: float = text_w + height * 1.72
	var left: float = pos.x - (w / 2.0 if centered else 0.0)
	var rect := Rect2(left, pos.y - height / 2.0, w, height)
	var base: Color = BotRank.tier_color(tier)
	var deep: Color = DEEP[tier]
	_rounded(canvas, rect, Palette.with_alpha(deep, 0.86),
		Palette.with_alpha(base, 0.85), maxf(height * 0.07, 1.0), height / 2.0)
	# Miniatyyritunnus: tason värinen vinoneliö jonka sisällä divisioonan sakarat.
	var badge := Vector2(left + height * 0.60, pos.y)
	var pulse: float = 0.72 + 0.28 * sin(t * 2.0 + float(tier))
	_diamond(canvas, badge, height * 0.34, Palette.with_alpha(Palette.glow(base, 1.3), 0.30))
	_diamond(canvas, badge, height * 0.24, Palette.glow(base, 0.9 + pulse * 0.5))
	var spikes: int = clamped % BotRank.DIVISIONS + 1
	for i in range(spikes):
		var ang: float = -PI * 0.5 + TAU * float(i) / float(BotRank.DIVISIONS)
		canvas.draw_line(badge, badge + Vector2(cos(ang), sin(ang)) * height * 0.20,
			Palette.with_alpha(BRIGHT[tier], 0.9), maxf(height * 0.05, 1.0))
	UiKit.draw_text(canvas, Vector2(left + height * 1.06, pos.y), text, fs, base, false)
	return w


# --- Jaetut apurit ---

## Rakennusvaiheen näkyvyys: build 0..1 jaetaan STAGES-vaiheeseen, jotka
## ilmestyvät järjestyksessä. build >= 1 = kaikki valmiina.
static func _stage(build: float, index: int) -> float:
	if build >= 1.0:
		return 1.0
	var span: float = 1.0 / float(STAGES)
	return clampf((build - float(index) * span) / (span * 0.8), 0.0, 1.0)


static func _fade(col: Color, alpha: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * clampf(alpha, 0.0, 1.0))


## Pyöristetty laatikko (täyttö + reunus) — sama tyyli kuin muissa valikoissa.
static func _rounded(canvas: CanvasItem, rect: Rect2, bg: Color, border: Color,
		border_w: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(maxf(border_w, 1.0)))
	sb.set_corner_radius_all(int(maxf(radius, 0.0)))
	sb.draw(canvas.get_canvas_item(), rect)


## Kilven oikean reunan x-etäisyys keskilinjasta. f = 0 hartioilla, f = 1 kärjessä.
static func _shield_x(r: float, f: float) -> float:
	return r * 0.82 * pow(cos(clampf(f, 0.0, 1.0) * PI * 0.5), 0.6)


## Kilven korkeus samalla parametrilla.
static func _shield_y(r: float, f: float) -> float:
	return lerpf(-r * 0.68, r * 1.02, clampf(f, 0.0, 1.0))


## Kilven ääriviiva (heater shield): hartiat, olkapäät ja kärki.
static func _shield_points(c: Vector2, r: float, steps := 16) -> PackedVector2Array:
	var w: float = _shield_x(r, 0.0)
	var top: float = -r * 0.86
	var shoulder: float = _shield_y(r, 0.0)
	var pts := PackedVector2Array()
	pts.append(c + Vector2(-w, shoulder))
	pts.append(c + Vector2(-w * 0.90, top))
	pts.append(c + Vector2(w * 0.90, top))
	pts.append(c + Vector2(w, shoulder))
	for i in range(1, steps + 1):
		var fr: float = float(i) / float(steps)
		pts.append(c + Vector2(_shield_x(r, fr), _shield_y(r, fr)))
	for j in range(steps - 1, 0, -1):
		var fl: float = float(j) / float(steps)
		pts.append(c + Vector2(-_shield_x(r, fl), _shield_y(r, fl)))
	return pts


## Vaakakaista kilven sisällä (kiillot ja huntukerrokset pysyvät ääriviivan
## sisäpuolella ilman leikkausmaskia).
static func _shield_band(c: Vector2, r: float, f0: float, f1: float,
		steps := 6) -> PackedVector2Array:
	var a: float = clampf(minf(f0, f1), 0.0, 1.0)
	var b: float = clampf(maxf(f0, f1), 0.0, 1.0)
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var fr: float = lerpf(a, b, float(i) / float(steps))
		pts.append(c + Vector2(_shield_x(r, fr), _shield_y(r, fr)))
	for j in range(steps, -1, -1):
		var fl: float = lerpf(a, b, float(j) / float(steps))
		pts.append(c + Vector2(-_shield_x(r, fl), _shield_y(r, fl)))
	return pts


static func _rotated(pts: PackedVector2Array, c: Vector2, ang: float) -> PackedVector2Array:
	if absf(ang) < 0.0005:
		return pts
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var p: Vector2 = pts[i]
		out.append(c + (p - c).rotated(ang))
	return out


## Sulkee ääriviivan: draw_polyline ei yhdistä viimeistä pistettä ensimmäiseen.
static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


static func _scaled(pts: PackedVector2Array, c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var p: Vector2 = pts[i]
		out.append(c + (p - c) * s)
	return out


## Säännöllinen monikulmio.
static func _ngon(c: Vector2, r: float, n: int, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(maxi(n, 3)):
		var ang: float = rot + TAU * float(i) / float(maxi(n, 3))
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts


## Vinoneliö (divisioonamerkit, jalokivet).
static func _diamond(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.2:
		return
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.7, 0),
		c + Vector2(0, r), c + Vector2(-r * 0.7, 0)]), col)


## Kapeneva säde: leveä tyvestä, kärki lähes pisteessä.
static func _ray_points(c: Vector2, ang: float, inner: float, outer: float,
		half_w: float) -> PackedVector2Array:
	var dir := Vector2(cos(ang), sin(ang))
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		c + dir * inner + side * half_w,
		c + dir * outer + side * half_w * 0.12,
		c + dir * outer - side * half_w * 0.12,
		c + dir * inner - side * half_w])


## Nelisakarainen kimallus.
static func _sparkle(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.3:
		return
	canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.22, -r * 0.22),
		c + Vector2(r, 0), c + Vector2(r * 0.22, r * 0.22),
		c + Vector2(0, r), c + Vector2(-r * 0.22, r * 0.22),
		c + Vector2(-r, 0), c + Vector2(-r * 0.22, -r * 0.22)]), col)


## Monisakarainen tähti (kruunut ja kiertävät tähdet).
static func _star_points(c: Vector2, outer: float, inner: float, tips: int,
		rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var count: int = maxi(tips, 3) * 2
	for i in range(count):
		var ang: float = rot + TAU * float(i) / float(count)
		var rad: float = outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts


## Laakerinlehti: mantelinmuotoinen polygoni annettuun suuntaan.
static func _leaf_points(pos: Vector2, length: float, width: float,
		ang: float) -> PackedVector2Array:
	var dir := Vector2(cos(ang), sin(ang))
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		pos, pos + dir * length * 0.34 + side * width,
		pos + dir * length * 0.72 + side * width * 0.72,
		pos + dir * length,
		pos + dir * length * 0.72 - side * width * 0.72,
		pos + dir * length * 0.34 - side * width])


## Kruunun ääriviiva: tips-piikkiä, keskimmäinen korkein.
static func _crown_points(c: Vector2, w: float, h: float, tips: int) -> PackedVector2Array:
	var count: int = maxi(tips, 3) * 2 - 1
	var pts := PackedVector2Array()
	pts.append(c + Vector2(-w, 0))
	for i in range(count):
		var f: float = float(i) / float(count - 1)
		var x: float = -w + 2.0 * w * f
		var y: float = -h * 0.30
		if i % 2 == 0:
			y = -h * (1.24 if i == count / 2 else 1.0)
		pts.append(c + Vector2(x, y))
	pts.append(c + Vector2(w, 0))
	return pts


## Lepattava liekki: leveä tyvi, aaltoileva kärki.
static func _flame_points(c: Vector2, half_w: float, height: float, t: float,
		phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 11
	for i in range(steps + 1):
		var fr: float = float(i) / float(steps)
		var xr: float = half_w * (1.0 - fr) * (1.0 + 0.28 * sin(fr * 6.0 + t * 4.5 + phase))
		pts.append(c + Vector2(xr + sin(fr * 3.4 + t * 3.2 + phase) * half_w * 0.18,
			-height * fr))
	for j in range(steps, -1, -1):
		var fl: float = float(j) / float(steps)
		var xl: float = half_w * (1.0 - fl) * (1.0 + 0.28 * sin(fl * 6.0 + t * 4.5 + phase + 1.9))
		pts.append(c + Vector2(-xl + sin(fl * 3.4 + t * 3.2 + phase) * half_w * 0.18,
			-height * fl))
	return pts


# --- Divisioonamerkit ---

## Jalusta tunnuksen alle: neljä merkkiä, joista valaistut kertovat divisioonan.
static func _draw_pips(canvas: CanvasItem, tier: int, c: Vector2, r: float, t: float,
		alpha: float, fill: float) -> void:
	if alpha <= 0.01:
		return
	var base: Color = BotRank.tier_color(tier)
	var deep: Color = DEEP[tier]
	var bright: Color = BRIGHT[tier]
	var w: float = r * 1.30
	var h: float = r * 0.30
	var y: float = c.y + r * 1.13
	var rect := Rect2(c.x - w / 2.0, y - h / 2.0, w, h)
	_rounded(canvas, rect, _fade(deep, 0.92 * alpha), _fade(base, 0.72 * alpha),
		maxf(r * 0.028, 1.0), h / 2.0)
	var gap: float = w / float(PIPS + 1)
	for i in range(PIPS):
		var pos := Vector2(rect.position.x + gap * float(i + 1), y)
		var pr: float = h * 0.30
		var lit: float = clampf(fill - float(i), 0.0, 1.0)
		if lit <= 0.01:
			_diamond(canvas, pos, pr * 0.85, _fade(base, 0.20 * alpha))
			continue
		# Syttyvä merkki napsahtaa hetkeksi yli koon (sin(lit * PI) = 0 kun valmis).
		var pop: float = 0.55 + 0.45 * lit + sin(lit * PI) * 0.55
		var pulse: float = 0.75 + 0.25 * sin(t * 2.2 + float(i) * 0.9)
		_diamond(canvas, pos, pr * pop * 1.9, _fade(Palette.glow(base, 1.4), 0.22 * alpha * lit))
		_diamond(canvas, pos, pr * pop, _fade(Palette.glow(base, 0.95 + pulse * 0.5), alpha * lit))
		_diamond(canvas, pos + Vector2(0, -pr * 0.28), pr * pop * 0.34,
			_fade(bright, 0.85 * alpha * lit))


# --- Tason taiteen jako ---

static func _tier_art(canvas: CanvasItem, tier: int, c: Vector2, r: float, t: float,
		alpha: float, build: float) -> void:
	match clampi(tier, 0, 7):
		0:
			_wood(canvas, c, r, t, alpha, build)
		1:
			_bronze(canvas, c, r, t, alpha, build)
		2:
			_silver(canvas, c, r, t, alpha, build)
		3:
			_gold(canvas, c, r, t, alpha, build)
		4:
			_platinum(canvas, c, r, t, alpha, build)
		5:
			_diamond_tier(canvas, c, r, t, alpha, build)
		6:
			_champion(canvas, c, r, t, alpha, build)
		_:
			_challenger(canvas, c, r, t, alpha, build)


# --- 0: WOOD — kirveellä veistetty lankkukilpi ---

static func _wood(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[0]
	var base: Color = BotRank.tier_color(0)
	var bright: Color = BRIGHT[0]
	var moss: Color = ACCENT[0]
	var sway: float = sin(t * 0.55) * 0.022        # kilpi huojuu kuin naruista riippuen

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.12, _fade(deep, 0.34 * alpha * s0))
		var backing: PackedVector2Array = _rotated(_scaled(_shield_points(c, r), c, 1.07), c, sway)
		canvas.draw_colored_polygon(backing, _fade(Color(0.05, 0.04, 0.03, 1.0), 0.85 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		var body: PackedVector2Array = _rotated(_shield_points(c, r), c, sway)
		canvas.draw_colored_polygon(body, _fade(base, alpha * s1))
		# Kolme lankkua: saumat ja karkea syykuvio.
		for i in range(2):
			var sx: float = (-1.0 if i == 0 else 1.0) * r * 0.27
			var seam := PackedVector2Array()
			for k in range(9):
				var fr: float = float(k) / 8.0
				seam.append(c + Vector2(sx + sin(fr * 5.0 + float(i)) * r * 0.02,
					lerpf(-r * 0.80, r * 0.90, fr)).rotated(sway))
			canvas.draw_polyline(seam, _fade(deep, 0.75 * alpha * s1), maxf(r * 0.035, 1.0), true)
		for g in range(5):
			var gy: float = lerpf(-r * 0.58, r * 0.72, float(g) / 4.0)
			var gx: float = (-1.0 if g % 2 == 0 else 1.0) * r * 0.42
			canvas.draw_arc(c + Vector2(gx, gy).rotated(sway), r * 0.13,
				PI * 0.15, PI * 1.05, 10, _fade(deep, 0.34 * alpha * s1), maxf(r * 0.02, 1.0))
		# Kirveen jättämä vino valo yläreunaan.
		canvas.draw_colored_polygon(_rotated(_shield_band(c, r, 0.02, 0.16), c, sway),
			_fade(bright, 0.14 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Rautavanteet ylä- ja alaosaan.
		for band in [0.10, 0.78]:
			var strip: PackedVector2Array = _rotated(
				_shield_band(c, r, band, band + 0.11), c, sway)
			canvas.draw_colored_polygon(strip, _fade(IRON, 0.55 * alpha * s2))
			canvas.draw_polyline(strip, _fade(Color(0.10, 0.11, 0.13, 1.0), 0.6 * alpha * s2),
				maxf(r * 0.02, 1.0), true)
		# Rautanaulat: kupu + korkeavalo.
		var nails := [
			Vector2(-0.56, -0.52), Vector2(0.56, -0.52), Vector2(-0.50, 0.30),
			Vector2(0.50, 0.30), Vector2(0.0, -0.74), Vector2(0.0, 0.74)]
		for entry in nails:
			var off: Vector2 = entry
			var pos: Vector2 = c + (off * r).rotated(sway)
			canvas.draw_circle(pos, r * 0.085, _fade(Color(0.13, 0.14, 0.16, 1.0), alpha * s2))
			canvas.draw_circle(pos, r * 0.060, _fade(IRON, alpha * s2))
			canvas.draw_circle(pos + Vector2(-r * 0.018, -r * 0.018), r * 0.022,
				_fade(Color.WHITE, 0.7 * alpha * s2))

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Sammal kasvaa kilven alalaitaan ja hengittää hitaasti.
		var breath: float = 0.85 + 0.15 * sin(t * 0.9)
		var spots := [
			Vector2(-0.34, 0.62), Vector2(-0.14, 0.78), Vector2(0.20, 0.72),
			Vector2(0.40, 0.50), Vector2(-0.52, 0.36)]
		for i in range(spots.size()):
			var sp: Vector2 = spots[i]
			var pos: Vector2 = c + (sp * r).rotated(sway)
			var rad: float = r * (0.10 + 0.035 * float(i % 3)) * breath
			canvas.draw_circle(pos, rad * 1.5, _fade(moss, 0.16 * alpha * s3))
			canvas.draw_circle(pos, rad, _fade(moss, 0.62 * alpha * s3))
			canvas.draw_circle(pos + Vector2(rad * 0.3, -rad * 0.3), rad * 0.42,
				_fade(Palette.glow(moss, 1.3), 0.5 * alpha * s3))


# --- 1: BRONZE — valettu kilpi, taottu vanne ja jalokivi ---

static func _bronze(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[1]
	var base: Color = BotRank.tier_color(1)
	var bright: Color = BRIGHT[1]
	var gem: Color = ACCENT[1]

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.20, _fade(base, 0.10 * alpha * s0))
		canvas.draw_colored_polygon(_scaled(_shield_points(c, r), c, 1.06),
			_fade(deep, 0.95 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		canvas.draw_colored_polygon(_shield_points(c, r), _fade(base, alpha * s1))
		# Valun epätasainen pinta: kolme leveää sävykaistaa.
		canvas.draw_colored_polygon(_shield_band(c, r, 0.0, 0.30),
			_fade(bright, 0.16 * alpha * s1))
		canvas.draw_colored_polygon(_shield_band(c, r, 0.62, 1.0),
			_fade(deep, 0.30 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Taottu vanne: 22 vasaraniskun jälkeä, joiden yli kiertää kiilto.
		var segments := 22
		for i in range(segments):
			var a0: float = TAU * float(i) / float(segments)
			var a1: float = TAU * float(i + 1) / float(segments)
			var mid: float = (a0 + a1) * 0.5
			var facet: float = 0.45 + 0.30 * sin(float(i) * 2.1)
			var shine: float = pow(maxf(cos(mid - t * 0.75), 0.0), 8.0)
			var col: Color = _fade(base, (facet + shine * 0.9) * alpha * s2)
			canvas.draw_arc(c, r * 0.94, a0, a1, 4, col, maxf(r * 0.11, 1.5))
			if shine > 0.35:
				canvas.draw_arc(c, r * 0.94, a0, a1, 4,
					_fade(bright, (shine - 0.35) * 1.2 * alpha * s2), maxf(r * 0.06, 1.0))
		canvas.draw_arc(c, r * 1.00, 0.0, TAU, 48, _fade(deep, 0.8 * alpha * s2),
			maxf(r * 0.025, 1.0))
		# Niitit vanteessa.
		for i in range(8):
			var ang: float = TAU * float(i) / 8.0 + 0.4
			var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * r * 0.94
			canvas.draw_circle(pos, r * 0.042, _fade(deep, alpha * s2))
			canvas.draw_circle(pos, r * 0.028, _fade(bright, 0.8 * alpha * s2))

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Keskuskohokas ja siihen upotettu jalokivi.
		var boss := c + Vector2(0, -r * 0.06)
		canvas.draw_circle(boss, r * 0.40, _fade(deep, 0.9 * alpha * s3))
		canvas.draw_circle(boss, r * 0.34, _fade(base, alpha * s3))
		canvas.draw_circle(boss + Vector2(-r * 0.10, -r * 0.10), r * 0.13,
			_fade(bright, 0.32 * alpha * s3))
		var pulse: float = 0.72 + 0.28 * sin(t * 1.8)
		_diamond(canvas, boss, r * 0.30, _fade(Palette.glow(gem, 1.3), 0.20 * alpha * s3 * pulse))
		_diamond(canvas, boss, r * 0.21, _fade(gem, alpha * s3))
		_diamond(canvas, boss + Vector2(0, -r * 0.04), r * 0.11,
			_fade(Palette.glow(gem, 1.6), 0.9 * alpha * s3))
		canvas.draw_colored_polygon(PackedVector2Array([
			boss + Vector2(0, -r * 0.20), boss + Vector2(r * 0.09, -r * 0.03),
			boss + Vector2(-r * 0.05, -r * 0.02)]),
			_fade(Color.WHITE, 0.55 * alpha * s3))
		_sparkle(canvas, boss + Vector2(r * 0.16, -r * 0.18), r * 0.10 * pulse,
			_fade(Color.WHITE, 0.7 * alpha * s3))


# --- 2: SILVER — hopeasiivet kilven ympärillä ---

static func _silver(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[2]
	var base: Color = BotRank.tier_color(2)
	var bright: Color = BRIGHT[2]
	var gem: Color = ACCENT[2]
	var breath: float = sin(t * 0.8)                # siivet hengittävät

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.24, _fade(base, 0.09 * alpha * s0))
		canvas.draw_circle(c, r * 0.92, _fade(deep, 0.35 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		# Neljä sulkaa kummallakin puolella, ulommat pisimmät.
		for side in [-1.0, 1.0]:
			for k in range(4):
				var fr: float = float(k) / 3.0
				var spread: float = breath * r * 0.035 * (1.0 + fr)
				var root: Vector2 = c + Vector2(side * r * 0.42,
					-r * 0.44 + fr * r * 0.52)
				var length: float = r * (0.86 - fr * 0.22)
				var ang: float = (0.0 if side > 0.0 else PI) \
					+ side * (-0.62 + fr * 0.72) * 1.0
				var tip: Vector2 = root + Vector2(cos(ang), sin(ang)) * length \
					+ Vector2(0, -spread)
				var normal := Vector2(-(tip - root).normalized().y,
					(tip - root).normalized().x)
				var wid: float = r * (0.17 - fr * 0.03)
				var feather := PackedVector2Array([
					root + normal * wid * 0.5, root - normal * wid * 0.5,
					root.lerp(tip, 0.55) - normal * wid, tip,
					root.lerp(tip, 0.62) + normal * wid * 0.72])
				canvas.draw_colored_polygon(feather, _fade(deep, 0.85 * alpha * s1))
				canvas.draw_colored_polygon(_scaled(feather, root.lerp(tip, 0.5), 0.86),
					_fade(base, alpha * s1))
				canvas.draw_line(root.lerp(tip, 0.1), tip,
					_fade(bright, 0.5 * alpha * s1), maxf(r * 0.018, 1.0), true)

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		var shield: PackedVector2Array = _scaled(_shield_points(c, r), c, 0.76)
		canvas.draw_colored_polygon(_scaled(shield, c, 1.10), _fade(deep, 0.95 * alpha * s2))
		canvas.draw_colored_polygon(shield, _fade(base, alpha * s2))
		canvas.draw_colored_polygon(_scaled(_shield_band(c, r * 0.76, 0.0, 0.34), c, 1.0),
			_fade(bright, 0.20 * alpha * s2))
		canvas.draw_polyline(_closed(shield), _fade(bright, 0.55 * alpha * s2),
			maxf(r * 0.02, 1.0), true)

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Kiilto pyyhkii kilven yli ylhäältä alas.
		var sweep: float = fmod(t * 0.32, 1.6) - 0.3
		if sweep > -0.14 and sweep < 1.0:
			var f0: float = clampf(sweep, 0.0, 1.0)
			var f1: float = clampf(sweep + 0.15, 0.0, 1.0)
			if f1 - f0 > 0.005:
				canvas.draw_colored_polygon(_shield_band(c, r * 0.76, f0, f1),
					_fade(Color.WHITE, 0.28 * alpha * s3))
		# Kilven kivi ja kimallukset.
		var boss := c + Vector2(0, -r * 0.10)
		_diamond(canvas, boss, r * 0.20, _fade(deep, alpha * s3))
		_diamond(canvas, boss, r * 0.14, _fade(gem, alpha * s3))
		_diamond(canvas, boss + Vector2(0, -r * 0.03), r * 0.06,
			_fade(Color.WHITE, 0.85 * alpha * s3))
		for i in range(3):
			var ph: float = t * 1.6 + float(i) * 2.1
			var twinkle: float = maxf(sin(ph), 0.0)
			var pos: Vector2 = c + Vector2(cos(float(i) * 2.4) * r * 0.55,
				sin(float(i) * 2.4) * r * 0.5 - r * 0.1)
			_sparkle(canvas, pos, r * 0.09 * twinkle, _fade(Color.WHITE, 0.8 * alpha * s3))


# --- 3: GOLD — laakeriseppele, kruunu ja säteet ---

static func _gold(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[3]
	var base: Color = BotRank.tier_color(3)
	var bright: Color = BRIGHT[3]
	var gem: Color = ACCENT[3]

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		# Lämpimät säteet kiertävät hitaasti ja elävät pituudessa.
		canvas.draw_circle(c, r * 1.26, _fade(base, 0.10 * alpha * s0))
		for i in range(16):
			var ang: float = TAU * float(i) / 16.0 + t * 0.11
			var reach: float = r * (1.10 + 0.16 * sin(float(i) * 1.7 + t * 1.2))
			canvas.draw_colored_polygon(_ray_points(c, ang, r * 0.30, reach, r * 0.075),
				_fade(base, (0.10 + 0.06 * sin(float(i) * 2.3 + t)) * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		canvas.draw_circle(c, r * 0.90, _fade(deep, alpha * s1))
		canvas.draw_circle(c, r * 0.80, _fade(base, alpha * s1))
		canvas.draw_circle(c, r * 0.62, _fade(deep, 0.55 * alpha * s1))
		# Auringonkiilat medaljongin sisällä.
		for i in range(12):
			var ang: float = TAU * float(i) / 12.0 - t * 0.18
			canvas.draw_colored_polygon(_ray_points(c, ang, r * 0.06, r * 0.60, r * 0.055),
				_fade(bright, 0.30 * alpha * s1))
		canvas.draw_circle(c, r * 0.20, _fade(bright, 0.85 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Laakeriseppele: kaksi kaarta, kummassakin 7 lehteä.
		for side in [1.0, -1.0]:
			for k in range(7):
				var fr: float = float(k) / 6.0
				var ang: float = lerpf(PI * 0.44, -PI * 0.30, fr)
				if side < 0.0:
					ang = PI - ang
				var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * r * 0.93
				var lean: float = ang - side * PI * 0.5 + side * 0.28
				var length: float = r * (0.34 - fr * 0.10)
				var leaf: PackedVector2Array = _leaf_points(pos, length, length * 0.34, lean)
				canvas.draw_colored_polygon(leaf, _fade(deep, 0.9 * alpha * s2))
				canvas.draw_colored_polygon(_scaled(leaf, pos, 0.84), _fade(base, alpha * s2))
				canvas.draw_line(pos, pos + Vector2(cos(lean), sin(lean)) * length * 0.9,
					_fade(bright, 0.45 * alpha * s2), maxf(r * 0.014, 1.0), true)
		# Seppeleen solmu alhaalla.
		canvas.draw_circle(c + Vector2(0, r * 0.94), r * 0.09, _fade(base, alpha * s2))

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Kruunu tunnuksen päällä + tuikkivat jalokivet.
		var crown_c := c + Vector2(0, -r * 0.86)
		var crown: PackedVector2Array = _crown_points(crown_c, r * 0.46, r * 0.40, 5)
		canvas.draw_colored_polygon(_scaled(crown, crown_c, 1.10), _fade(deep, alpha * s3))
		canvas.draw_colored_polygon(crown, _fade(base, alpha * s3))
		canvas.draw_polyline(_closed(crown), _fade(bright, 0.65 * alpha * s3),
			maxf(r * 0.018, 1.0), true)
		for i in range(3):
			var gx: float = (float(i) - 1.0) * r * 0.26
			var twinkle: float = 0.65 + 0.35 * sin(t * 2.6 + float(i) * 1.7)
			_diamond(canvas, crown_c + Vector2(gx, -r * 0.10), r * 0.07 * twinkle,
				_fade(gem, alpha * s3))
			_sparkle(canvas, crown_c + Vector2(gx, -r * (0.40 if i == 1 else 0.32)),
				r * 0.10 * twinkle, _fade(Color.WHITE, 0.8 * alpha * s3))


# --- 4: PLATINUM — kidelevy ja revontulihuntu ---

static func _platinum(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[4]
	var base: Color = BotRank.tier_color(4)
	var bright: Color = BRIGHT[4]
	var aurora: Color = ACCENT[4]
	var aurora_b := Color("b08aff")

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.22, _fade(base, 0.08 * alpha * s0))
		canvas.draw_circle(c, r * 1.04, _fade(deep, 0.55 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		var outer: PackedVector2Array = _ngon(c, r * 1.00, 6, -PI * 0.5)
		canvas.draw_colored_polygon(outer, _fade(deep, alpha * s1))
		var plate: PackedVector2Array = _ngon(c, r * 0.88, 6, -PI * 0.5)
		canvas.draw_colored_polygon(plate, _fade(base, 0.55 * alpha * s1))
		# Kuusi fasettia: valo kiertää levyn yli.
		for i in range(6):
			var a0: float = -PI * 0.5 + TAU * float(i) / 6.0
			var a1: float = -PI * 0.5 + TAU * float(i + 1) / 6.0
			var mid: float = (a0 + a1) * 0.5
			var lit: float = 0.30 + 0.55 * pow(maxf(cos(mid - t * 0.42), 0.0), 2.0)
			canvas.draw_colored_polygon(PackedVector2Array([
				c, c + Vector2(cos(a0), sin(a0)) * r * 0.88,
				c + Vector2(cos(a1), sin(a1)) * r * 0.88]),
				_fade(base, lit * alpha * s1))
		canvas.draw_polyline(_closed(_ngon(c, r * 0.88, 6, -PI * 0.5)), _fade(bright, 0.4 * alpha * s1),
			maxf(r * 0.02, 1.0), true)

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Kiteet työntyvät ulos kuudesta kulmasta.
		for i in range(6):
			var ang: float = -PI * 0.5 + TAU * float(i) / 6.0 + PI / 6.0
			var reach: float = r * (1.16 + 0.06 * sin(t * 1.1 + float(i)))
			var dir := Vector2(cos(ang), sin(ang))
			var side := Vector2(-dir.y, dir.x)
			var shard := PackedVector2Array([
				c + dir * r * 0.70 + side * r * 0.12,
				c + dir * reach,
				c + dir * r * 0.70 - side * r * 0.12,
				c + dir * r * 0.86])
			canvas.draw_colored_polygon(shard, _fade(deep, 0.9 * alpha * s2))
			canvas.draw_colored_polygon(_scaled(shard, c + dir * r * 0.9, 0.72),
				_fade(bright, 0.75 * alpha * s2))
		canvas.draw_circle(c, r * 0.34, _fade(deep, 0.8 * alpha * s2))
		_diamond(canvas, c, r * 0.26, _fade(bright, 0.9 * alpha * s2))

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Revontulihuntu: kolme aaltoilevaa nauhaa levyn yli.
		for band in range(3):
			var col: Color = aurora if band % 2 == 0 else aurora_b
			var pts := PackedVector2Array()
			for k in range(13):
				var fr: float = float(k) / 12.0
				var x: float = lerpf(-r * 0.78, r * 0.78, fr)
				var y: float = -r * 0.30 + float(band) * r * 0.30 \
					+ sin(fr * 4.4 + t * (0.7 + 0.2 * float(band))) * r * 0.13
				pts.append(c + Vector2(x, y * (1.0 - absf(fr - 0.5) * 0.4)))
			canvas.draw_polyline(pts, _fade(col, 0.14 * alpha * s3), maxf(r * 0.15, 1.5), true)
			canvas.draw_polyline(pts, _fade(col, 0.30 * alpha * s3), maxf(r * 0.05, 1.0), true)
		for i in range(4):
			var ph: float = t * 1.3 + float(i) * 1.6
			var twinkle: float = maxf(sin(ph), 0.0)
			var pos: Vector2 = c + Vector2(cos(float(i) * 1.9) * r * 0.52,
				sin(float(i) * 2.7) * r * 0.52)
			_sparkle(canvas, pos, r * 0.08 * twinkle, _fade(Color.WHITE, 0.75 * alpha * s3))


# --- 5: DIAMOND — hiottu briljantti ---

static func _diamond_tier(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[5]
	var base: Color = BotRank.tier_color(5)
	var bright: Color = BRIGHT[5]
	var prism_a: Color = ACCENT[5]
	var prism_b := Color("7ae0ff")
	var girdle: float = r * 0.80
	var table_r: float = r * 0.50
	var table_y: float = -r * 0.36
	var tip := c + Vector2(0, r * 0.98)

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.24, _fade(prism_b, 0.08 * alpha * s0))
		canvas.draw_circle(c, r * 0.98, _fade(deep, 0.5 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		# Taittuneet valonsirut: pitkiä ohuita kolmioita prismavärein.
		for i in range(9):
			var ang: float = TAU * float(i) / 9.0 + t * 0.22
			var reach: float = r * (1.05 + 0.30 * absf(sin(float(i) * 1.4 + t * 0.9)))
			var col: Color = prism_a if i % 3 == 0 else (prism_b if i % 3 == 1 else Color.WHITE)
			canvas.draw_colored_polygon(_ray_points(c, ang, r * 0.35, reach, r * 0.055),
				_fade(col, 0.20 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Pavillion: kahdeksan kolmiota girdlestä kärkeen, vuorotellen kirkkaat.
		for i in range(8):
			var a0: float = TAU * float(i) / 8.0
			var a1: float = TAU * float(i + 1) / 8.0
			var p0: Vector2 = c + Vector2(cos(a0), sin(a0) * 0.34) * girdle
			var p1: Vector2 = c + Vector2(cos(a1), sin(a1) * 0.34) * girdle
			var lit: float = 0.35 + 0.45 * pow(maxf(cos((a0 + a1) * 0.5 - t * 0.5), 0.0), 2.0)
			if p0.y > c.y - girdle * 0.10 or p1.y > c.y - girdle * 0.10:
				canvas.draw_colored_polygon(PackedVector2Array([p0, p1, tip]),
					_fade(base, lit * alpha * s2))
				canvas.draw_line(p0, tip, _fade(deep, 0.5 * alpha * s2),
					maxf(r * 0.012, 1.0), true)
		# Kruunufasetit: girdlestä pöytään.
		for i in range(8):
			var b0: float = TAU * float(i) / 8.0
			var b1: float = TAU * float(i + 1) / 8.0
			var g0: Vector2 = c + Vector2(cos(b0), sin(b0) * 0.34) * girdle
			var g1: Vector2 = c + Vector2(cos(b1), sin(b1) * 0.34) * girdle
			var t0: Vector2 = c + Vector2(cos(b0) * table_r, table_y + sin(b0) * table_r * 0.30)
			var t1: Vector2 = c + Vector2(cos(b1) * table_r, table_y + sin(b1) * table_r * 0.30)
			var lit: float = 0.45 + 0.50 * pow(maxf(cos((b0 + b1) * 0.5 + t * 0.6), 0.0), 2.0)
			canvas.draw_colored_polygon(PackedVector2Array([g0, g1, t1, t0]),
				_fade(base, lit * alpha * s2))
		# Pöytä: kirkas kahdeksankulmio.
		var table := PackedVector2Array()
		for i in range(8):
			var ang: float = TAU * float(i) / 8.0
			table.append(c + Vector2(cos(ang) * table_r, table_y + sin(ang) * table_r * 0.30))
		canvas.draw_colored_polygon(table, _fade(bright, 0.85 * alpha * s2))
		canvas.draw_polyline(_closed(table), _fade(deep, 0.55 * alpha * s2), maxf(r * 0.015, 1.0), true)

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Pöydän heijastus liukuu, kimallukset välähtelevät.
		var slide: float = sin(t * 0.6)
		canvas.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-table_r * 0.6 + slide * table_r * 0.3, table_y - table_r * 0.14),
			c + Vector2(table_r * 0.1 + slide * table_r * 0.3, table_y - table_r * 0.22),
			c + Vector2(table_r * 0.3 + slide * table_r * 0.3, table_y + table_r * 0.10),
			c + Vector2(-table_r * 0.4 + slide * table_r * 0.3, table_y + table_r * 0.16)]),
			_fade(Color.WHITE, 0.35 * alpha * s3))
		for i in range(5):
			var ph: float = t * 1.9 + float(i) * 1.27
			var twinkle: float = maxf(sin(ph), 0.0)
			var ang: float = float(i) * 1.9 + t * 0.35
			var rad: float = r * (0.55 + 0.28 * float(i % 3))
			var pos: Vector2 = c + Vector2(cos(ang) * rad, sin(ang) * rad * 0.6)
			_sparkle(canvas, pos, r * 0.13 * twinkle, _fade(Color.WHITE, 0.9 * alpha * s3))
		canvas.draw_circle(tip + Vector2(0, r * 0.04), r * 0.06 * (0.6 + 0.4 * sin(t * 2.2)),
			_fade(bright, 0.7 * alpha * s3))


# --- 6: CHAMPION — obsidiaani, liekki ja feeniks ---

static func _champion(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[6]
	var base: Color = BotRank.tier_color(6)
	var bright: Color = BRIGHT[6]
	var flame_hot: Color = ACCENT[6]
	var flame_mid := Color("ff5a2a")

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.28, _fade(base, 0.10 * alpha * s0))
		canvas.draw_circle(c, r * 1.02, _fade(deep, 0.85 * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		# Liekit tunnuksen takana: syvä violetti, oranssi, keltainen.
		var root := c + Vector2(0, r * 0.92)
		canvas.draw_colored_polygon(_flame_points(root, r * 0.80, r * 1.90, t, 0.0),
			_fade(base, 0.35 * alpha * s1))
		canvas.draw_colored_polygon(_flame_points(root, r * 0.58, r * 1.55, t, 1.3),
			_fade(flame_mid, 0.55 * alpha * s1))
		canvas.draw_colored_polygon(_flame_points(root, r * 0.34, r * 1.15, t, 2.6),
			_fade(flame_hot, 0.65 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Obsidiaanikilpi: kulmikas ja terävä, violetit heijastukset.
		var crest := PackedVector2Array([
			c + Vector2(0, -r * 0.98), c + Vector2(r * 0.62, -r * 0.62),
			c + Vector2(r * 0.86, r * 0.02), c + Vector2(r * 0.44, r * 0.66),
			c + Vector2(0, r * 1.00), c + Vector2(-r * 0.44, r * 0.66),
			c + Vector2(-r * 0.86, r * 0.02), c + Vector2(-r * 0.62, -r * 0.62)])
		canvas.draw_colored_polygon(_scaled(crest, c, 1.08),
			_fade(Palette.glow(base, 1.2), 0.45 * alpha * s2))
		canvas.draw_colored_polygon(crest, _fade(Color(0.04, 0.03, 0.07, 1.0), alpha * s2))
		canvas.draw_polyline(_closed(crest), _fade(base, 0.75 * alpha * s2), maxf(r * 0.02, 1.0), true)
		for i in range(3):
			var y0: float = -r * 0.55 + float(i) * r * 0.40
			canvas.draw_line(c + Vector2(-r * 0.50 + float(i) * r * 0.10, y0),
				c + Vector2(r * 0.30 + float(i) * r * 0.10, y0 - r * 0.22),
				_fade(base, 0.30 * alpha * s2), maxf(r * 0.03, 1.0), true)

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Feeniks: siivet, runko, pää ja liekkihäntä.
		var beat: float = sin(t * 1.6)
		var body := c + Vector2(0, r * 0.06)
		for side in [-1.0, 1.0]:
			for k in range(3):
				var fr: float = float(k) / 2.0
				var lift: float = beat * r * 0.05 * (1.0 + fr)
				var root: Vector2 = body + Vector2(side * r * 0.10, -r * 0.10 + fr * r * 0.10)
				var dir := Vector2(side * cos(0.9 - fr * 0.55), -sin(0.9 - fr * 0.30))
				var tip: Vector2 = root + dir * r * (0.80 - fr * 0.14) + Vector2(0, -lift)
				var normal := Vector2(-dir.y, dir.x) * r * (0.13 - fr * 0.02)
				canvas.draw_colored_polygon(PackedVector2Array([
					root + normal, tip, root - normal,
					root.lerp(tip, 0.45) - normal * 1.5]),
					_fade(flame_hot if k == 0 else flame_mid, (0.95 - fr * 0.2) * alpha * s3))
				canvas.draw_line(root, tip, _fade(bright, 0.6 * alpha * s3),
					maxf(r * 0.014, 1.0), true)
		canvas.draw_colored_polygon(PackedVector2Array([
			body + Vector2(0, -r * 0.30), body + Vector2(r * 0.13, r * 0.16),
			body + Vector2(0, r * 0.46), body + Vector2(-r * 0.13, r * 0.16)]),
			_fade(flame_hot, alpha * s3))
		canvas.draw_circle(body + Vector2(0, -r * 0.36), r * 0.11, _fade(bright, alpha * s3))
		canvas.draw_colored_polygon(PackedVector2Array([
			body + Vector2(r * 0.08, -r * 0.40), body + Vector2(r * 0.26, -r * 0.34),
			body + Vector2(r * 0.08, -r * 0.29)]), _fade(flame_mid, alpha * s3))
		for k in range(3):
			var tx: float = (float(k) - 1.0) * r * 0.16
			canvas.draw_colored_polygon(PackedVector2Array([
				body + Vector2(tx * 0.4, r * 0.40),
				body + Vector2(tx, r * 0.92 + sin(t * 3.0 + float(k)) * r * 0.06),
				body + Vector2(tx * 0.4 + r * 0.07, r * 0.44)]),
				_fade(flame_hot, 0.8 * alpha * s3))
		# Nousevat kipinät.
		for i in range(7):
			var rise: float = fmod(t * 0.5 + float(i) * 0.143, 1.0)
			var sx: float = sin(float(i) * 2.3 + t * 0.8) * r * 0.62
			var pos: Vector2 = c + Vector2(sx, r * 1.00 - rise * r * 2.0)
			canvas.draw_circle(pos, r * 0.030 * (1.0 - rise),
				_fade(bright, 0.75 * (1.0 - rise) * alpha * s3))


# --- 7: CHALLENGER — taivaallinen valokruunu ---

static func _challenger(canvas: CanvasItem, c: Vector2, r: float, t: float, alpha: float,
		build: float) -> void:
	var deep: Color = DEEP[7]
	var base: Color = BotRank.tier_color(7)
	var bright: Color = BRIGHT[7]
	var star: Color = ACCENT[7]

	var s0: float = _stage(build, 0)
	if s0 > 0.0:
		canvas.draw_circle(c, r * 1.30, _fade(base, 0.10 * alpha * s0))
		canvas.draw_circle(c, r * 0.98, _fade(deep, 0.70 * alpha * s0))
		# Nousevat valopatsaat alhaalta.
		for i in range(5):
			var x: float = (float(i) - 2.0) * r * 0.34
			var pulse: float = 0.45 + 0.55 * maxf(sin(t * 1.1 + float(i) * 0.9), 0.0)
			var height: float = r * (1.30 + 0.30 * pulse)
			canvas.draw_colored_polygon(PackedVector2Array([
				c + Vector2(x - r * 0.10, r * 1.10),
				c + Vector2(x - r * 0.03, r * 1.10 - height),
				c + Vector2(x + r * 0.03, r * 1.10 - height),
				c + Vector2(x + r * 0.10, r * 1.10)]),
				_fade(bright, 0.10 * pulse * alpha * s0))

	var s1: float = _stage(build, 1)
	if s1 > 0.0:
		# Kaksi kallistettua halokehää + taakse jäävät tähdet.
		for ring in range(2):
			var tilt: float = 0.30 + float(ring) * 0.16
			var rad: float = r * (0.94 - float(ring) * 0.16)
			var pts := PackedVector2Array()
			for k in range(37):
				var ang: float = TAU * float(k) / 36.0
				pts.append(c + Vector2(cos(ang) * rad, sin(ang) * rad * tilt))
			canvas.draw_polyline(pts, _fade(base, (0.45 - float(ring) * 0.12) * alpha * s1),
				maxf(r * 0.022, 1.0), true)
		for i in range(3):
			var ang: float = t * 0.5 + float(i) * TAU / 3.0
			var depth: float = sin(ang)
			if depth >= 0.0:
				continue
			var pos: Vector2 = c + Vector2(cos(ang) * r * 0.94, sin(ang) * r * 0.30)
			_sparkle(canvas, pos, r * 0.10 * (0.6 + 0.4 * absf(depth)),
				_fade(star, 0.55 * alpha * s1))

	var s2: float = _stage(build, 2)
	if s2 > 0.0:
		# Valokruunu: seitsemän kapenevaa piikkiä ja kirkas ydin.
		var crown_c := c + Vector2(0, r * 0.42)
		for i in range(7):
			var fr: float = float(i) / 6.0
			var ang: float = -PI * 0.5 + (fr - 0.5) * 1.75
			var reach: float = r * (1.06 - absf(fr - 0.5) * 0.78) \
				* (1.0 + 0.05 * sin(t * 2.0 + float(i)))
			canvas.draw_colored_polygon(_ray_points(crown_c, ang, 0.0, reach, r * 0.085),
				_fade(bright, 0.30 * alpha * s2))
			canvas.draw_colored_polygon(_ray_points(crown_c, ang, 0.0, reach * 0.94, r * 0.045),
				_fade(Color.WHITE, 0.72 * alpha * s2))
		var arc_pts := PackedVector2Array()
		for k in range(19):
			var ang: float = PI + PI * float(k) / 18.0
			arc_pts.append(crown_c + Vector2(cos(ang) * r * 0.68, sin(ang) * r * 0.24))
		canvas.draw_polyline(arc_pts, _fade(base, 0.85 * alpha * s2), maxf(r * 0.05, 1.5), true)
		canvas.draw_circle(crown_c + Vector2(0, -r * 0.18), r * 0.20,
			_fade(bright, 0.35 * alpha * s2))
		canvas.draw_colored_polygon(_star_points(crown_c + Vector2(0, -r * 0.18),
			r * 0.30, r * 0.11, 5, -PI * 0.5 + t * 0.25), _fade(Color.WHITE, 0.95 * alpha * s2))

	var s3: float = _stage(build, 3)
	if s3 > 0.0:
		# Etualalle kiertävät tähdet.
		for i in range(3):
			var ang: float = t * 0.5 + float(i) * TAU / 3.0
			var depth: float = sin(ang)
			if depth < 0.0:
				continue
			var pos: Vector2 = c + Vector2(cos(ang) * r * 0.94, sin(ang) * r * 0.30)
			var size: float = r * (0.09 + 0.07 * depth)
			_sparkle(canvas, pos, size * 2.0, _fade(star, 0.20 * alpha * s3))
			_sparkle(canvas, pos, size, _fade(Color.WHITE, 0.95 * alpha * s3))
		for i in range(3):
			var ang2: float = -t * 0.36 + float(i) * TAU / 3.0 + 1.0
			var pos2: Vector2 = c + Vector2(cos(ang2) * r * 0.70, sin(ang2) * r * 0.70 * 0.42)
			_sparkle(canvas, pos2, r * 0.07 * (0.6 + 0.4 * sin(t * 2.4 + float(i))),
				_fade(star, 0.80 * alpha * s3))
