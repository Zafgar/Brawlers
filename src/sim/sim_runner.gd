class_name SimRunner
extends RefCounted
## Bot vs bot -simulaatio MOBA-kartalla. Kolme tilaa:
##   Manuaali — N ottelua kiinteillä (satunnainen/peilattu) kokoonpanoilla.
##              Satunnaiset kokoonpanot nostetaan KIERTOPAKASTA, joten vakioajo
##              (24 ottelua) kattaa takuulla jokaisen heron useita kertoja.
##   Sweep    — käy läpi KAIKKI kokoonpanotyyppien parit (6×6) toistoineen,
##              mukaan lukien täysvahinko- ja täystuki-joukkueet, jotta
##              rikkinäiset herot/yhdistelmät löytyvät.
##   Ladder   — rank vs rank -testi: jokainen vierekkäinen tier-pari (Wood vs
##              Bronze, ... , Champion vs Challenger) + hajautusankkurit pelaavat
##              N ottelua satunnaisin kokoonpanoin, puolet puolet vaihtaen.
##              Raportti kertoo voittaako ylempi rank riittävän usein
##              (LADDER TOIMII / LADDER RIKKI).
##
## Nopeutus tehdään Engine.time_scalella (tarkka: askeleet pysyvät 1/60 s,
## niitä vain otetaan enemmän per ruutu). Lähtölaskenta ja voittobanneri
## ohitetaan simulaatiossa. Ottelut ovat oikeita pelejä — vain super nopeasti.

enum Comp { RANDOM, MIRROR }

var team_size := 4
var blue_level := 2       # indeksi 0–5 (taso 1–6)
var orange_level := 2
var comp_mode := Comp.RANDOM
var match_count := 3
var speed := 8
var show_visuals := true
var sweep := false
var repeats := 1          # sweepissä: montako kertaa jokainen tyyppipari
var ladder := false       # ladder-testi: rank vs rank (ohittaa sweepin)
var ladder_matches := 6   # otteluita per rank-pari (puolet puolin vaihdettuna)

# Ladder-testin parit tier-indekseinä (0 = Wood ... 7 = Challenger). Vierekkäiset
# parit todentavat koko portaikon monotonisuuden; hajautusankkurit (iso rankiero)
# ovat terveystarkistus — niiden KUULUU olla lähes 100 % ylemmälle.
const LADDER_ADJACENT_PAIRS := [
	[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7],
]
const LADDER_ANCHOR_PAIRS := [
	[0, 3],   # Wood vs Gold
	[2, 5],   # Silver vs Diamond
	[0, 7],   # Wood vs Challenger
]
# DIVISIOONAPARIT: saman tason alin (IV) vs ylin (I) — kolmen portaan ero
# TASON SISÄLLÄ. Nämä todentavat että divisioonat eroavat oikeasti toisistaan
# (mistake_chance + jatkuvat käyrät), koska tasoportit ovat parin molemmilla
# puolilla identtiset. Edustajat matalasta, keskeltä ja huipulta.
const LADDER_DIVISION_TIERS := [0, 2, 5]   # Wood, Silver, Diamond

var _results: Array = []          # manuaali: [snap]; sweep/ladder: [{snap, ...}]
var _queue: Array = []            # sweep: {bi, oi}; ladder: {lo, hi, hi_team, anchor}
var _hero_cycle: Array = []       # kiertopakka: takaa kaikkien herojen peliajan
var _cur_ba := ""
var _cur_oa := ""
var _match_index := 0
var _orig_max_steps := 8
var _orig_physics_ticks := 60
var _orig_max_fps := 0
var _progress_layer: CanvasLayer = null   # pysyvä "Ottelu X/Y" -näyttö (yli ottelunvaihtojen)
var _progress_label: Label = null

# 16x / 60 Hz on vanhan simulaation tarkkuustaso (0,267 pelisekuntia per
# fysiikka-askel). Yli 16x -nopeuksilla kasvatetaan fysiikkataajuutta samassa
# suhteessa, jotta 32x/64x ei suurenna askelta ja muuta osuma-/AI-tuloksia lisää.
const REFERENCE_SPEED := 16.0
const REFERENCE_TICKS := 60.0

# Kokoonpanotyypit: kukin määrittää roolikuvion (kierrätetään joukkuekokoon).
# damage = kaikki vahinkoroolit (mage/assassin/fighter/ranger).
const ARCHETYPES := [
	{"name": "Tasapaino",   "pattern": ["tank", "support", "damage", "damage"]},
	{"name": "Täysvahinko", "pattern": ["damage", "damage", "damage", "damage"]},
	{"name": "Täystuki",    "pattern": ["support", "support", "support", "support"]},
	{"name": "Täystankki",  "pattern": ["tank", "tank", "tank", "tank"]},
	{"name": "Kaukotaisto", "pattern": ["ranger", "mage", "ranger", "mage"]},
	{"name": "Sukellus",    "pattern": ["tank", "assassin", "assassin", "assassin"]},
]


func start() -> void:
	Game.simulating = true
	Game.sim_visuals = show_visuals
	Game.sim_runner = self
	_results = []
	_match_index = 0
	_hero_cycle = []
	if ladder:
		sweep = false          # ladder ohittaa sweepin (yksi erikoistila kerrallaan)
		_build_ladder_queue()
		match_count = _queue.size()
	elif sweep:
		_build_queue()
		match_count = _queue.size()
	_orig_max_steps = Engine.max_physics_steps_per_frame
	_orig_physics_ticks = Engine.physics_ticks_per_second
	_orig_max_fps = Engine.max_fps
	Engine.time_scale = float(speed)
	var target_ticks := _orig_physics_ticks
	if speed > int(REFERENCE_SPEED):
		target_ticks = maxi(_orig_physics_ticks,
			int(ceil(REFERENCE_TICKS * float(speed) / REFERENCE_SPEED)))
	Engine.physics_ticks_per_second = target_ticks
	# Turbo piirtää vain etenemistekstin 30 fps:llä. Fysiikka saa silti ajaa
	# 120/240 Hz, ja askelkatto sallii sen myös hetkellisessä FPS-pudotuksessa.
	if not show_visuals:
		Engine.max_fps = 30
	Engine.max_physics_steps_per_frame = maxi(_orig_max_steps,
		int(ceil(float(target_ticks) / 30.0)) + 2)
	Game.mode_id = "moba"
	_make_progress_overlay()
	_start_match()


## Pysyvä etenemisnäyttö: elää Game-autoloadin lapsena, joten se säilyy vaikka
## areena vaihtuu ottelusta toiseen. Näyttää aina "Ottelu X/Y" reaaliajassa.
func _make_progress_overlay() -> void:
	_progress_layer = CanvasLayer.new()
	_progress_layer.layer = 128
	var lbl := Label.new()
	lbl.position = Vector2(22.0, 14.0)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	_progress_layer.add_child(lbl)
	_progress_label = lbl
	Game.add_child(_progress_layer)


func _start_match() -> void:
	if ladder:
		var lq: Dictionary = _queue[_match_index]
		Game.roster = _build_ladder_roster(lq)
	elif sweep:
		var q: Dictionary = _queue[_match_index]
		Game.roster = _build_sweep_roster(int(q["bi"]), int(q["oi"]))
	else:
		Game.roster = _build_roster()
	Game.blue_rounds = 0
	Game.orange_rounds = 0
	Game.start_match()
	# Pidä etenemisoverlay näkyvissä, mutta piilota koko taistelu-CanvasItem.
	# Pelilogiikka ja fysiikka jatkavat normaalisti; vain piirto jää pois.
	if not show_visuals and Game.arena is CanvasItem:
		Game.arena.visible = false
	_announce_progress()


## Näyttää etenemisen ruudulla (ottelut ovat näkyvissä, vain nopeutettuna).
## Pysyvä yläkulman laskuri + lyhyt banneri ottelun vaihtuessa.
func _announce_progress() -> void:
	var sub: String = "%s vs %s" % [_cur_ba, _cur_oa] if (sweep or ladder) else "Bot vs bot"
	var pct := int(round(100.0 * float(_match_index) / float(maxi(match_count, 1))))
	if _progress_label != null and is_instance_valid(_progress_label):
		_progress_label.text = "SIMULAATIO  Ottelu %d/%d  (%d%%)\n%s" % [
			_match_index + 1, match_count, pct, sub]
	if Game.arena == null or not is_instance_valid(Game.arena):
		return
	var hud = Game.arena.hud
	if hud == null:
		return
	hud.show_banner("SIMULAATIO  %d/%d" % [_match_index + 1, match_count], sub, 1.4)


## Kutsutaan Game.match_finishedista simulaation aikana.
func on_match_done() -> void:
	if Game.arena != null and is_instance_valid(Game.arena):
		var snap: Dictionary = Game.arena.sim_snapshot()
		if ladder:
			var lq: Dictionary = _queue[_match_index]
			_results.append({"snap": snap, "lo": int(lq["lo"]), "hi": int(lq["hi"]),
				"hi_team": int(lq["hi_team"]), "anchor": bool(lq["anchor"]),
				"division": bool(lq["division"])})
		elif sweep:
			_results.append({"snap": snap, "ba": _cur_ba, "oa": _cur_oa})
		else:
			_results.append(snap)
	_match_index += 1
	if _match_index < match_count:
		_start_match()
	else:
		_finish()


## Palauttaa nopeutuksen ja siivoaa simulaatiotilan (aikaskaalaus, lippu,
## etenemisnäyttö). Sekä normaalin lopun että keskeytyksen yhteinen siivous.
func _teardown() -> void:
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = _orig_max_steps
	Engine.physics_ticks_per_second = _orig_physics_ticks
	Engine.max_fps = _orig_max_fps
	Game.simulating = false
	Game.sim_visuals = true
	Game.sim_runner = null
	if _progress_layer != null and is_instance_valid(_progress_layer):
		_progress_layer.queue_free()
	_progress_layer = null
	_progress_label = null


## Keskeytys (esim. taukovalikon "Päävalikkoon" kesken sweepin): siivoa tila
## ilman raporttinäkymää — muuten peli jäisi jumiin nopeutettuun sim-tilaan.
func abort() -> void:
	_teardown()


func _finish() -> void:
	_teardown()
	var results := SimResults.new()
	if ladder:
		var lintro := [
			"=== LADDER-TESTI (RANK vs RANK) ===",
			"%dv%d | %d vierekkäistä paria + %d ankkuria + %d divisioonaparia | %d ottelua/pari | Otteluita: %d | Nopeus: %dx" % [
				team_size, team_size, LADDER_ADJACENT_PAIRS.size(),
				LADDER_ANCHOR_PAIRS.size(), LADDER_DIVISION_TIERS.size(),
				ladder_matches, match_count, speed],
			"Kokoonpanot satunnaisia (kiertopakka), puolet otteluista puolin vaihdettuna.",
			"Tasoparit pelataan divisioonassa III; divisioonaparit ovat saman tason IV vs I.",
		]
		results.report_text = MatchReport.build_ladder(_results, lintro)
	elif sweep:
		var intro := [
			"=== KOKOONPANO-SWEEP (MOBA) ===",
			"%dv%d | Taso %d vs %d | Tyyppiparit: %d | Toistot: %d | Otteluita: %d | Nopeus: %dx" % [
				team_size, team_size, blue_level + 1, orange_level + 1,
				ARCHETYPES.size() * ARCHETYPES.size(), repeats, match_count, speed]]
		if blue_level >= 5 or orange_level >= 5:
			intro.append("HUOM: taso 6 (Epäreilu) HUIJAA (vahinko/kesto/CD) — "
				+ "tasapainolukemat eivät ole luotettavia. Käytä tasoa 1–5.")
		results.report_text = MatchReport.build_sweep(_results, intro)
	else:
		var intro := [
			"=== MOBA-SIMULAATIO ===",
			"Kokoonpano: %dv%d | Sininen taso %d vs Oranssi taso %d | Komppa: %s | Otteluita: %d | Nopeus: %dx" % [
				team_size, team_size, blue_level + 1, orange_level + 1,
				("Peilattu" if comp_mode == Comp.MIRROR else "Satunnainen"),
				match_count, speed]]
		results.report_text = MatchReport.build(_results, intro)
	Game._swap(results)


# --- Ladder: rank-parien jono ---

## Rakentaa ladder-jonon: jokaiselle parille ladder_matches ottelua siten, että
## joka toisessa ylempi rank on SININEN ja joka toisessa ORANSSI — mahdollinen
## puolibias (kartta/aloitus) kumoutuu, eikä se vääristä ylemmän voitto-%:a.
func _build_ladder_queue() -> void:
	_queue = []
	var pairs: Array = []
	for p in LADDER_ADJACENT_PAIRS:
		pairs.append({"pair": p, "anchor": false})
	for p in LADDER_ANCHOR_PAIRS:
		pairs.append({"pair": p, "anchor": true})
	for entry in pairs:
		var pair: Array = entry["pair"]
		var lo: int = BotRank.tier_default_rank(int(pair[0]))
		var hi: int = BotRank.tier_default_rank(int(pair[1]))
		for m in range(maxi(ladder_matches, 1)):
			_queue.append({"lo": lo, "hi": hi, "hi_team": m % 2,
				"anchor": bool(entry["anchor"]), "division": false})
	# Divisioonaparit: tason IV vs saman tason I (esim. Wood IV vs Wood I).
	for tier_v in LADDER_DIVISION_TIERS:
		var tier: int = int(tier_v)
		var dlo: int = tier * BotRank.DIVISIONS            # divisioona IV
		var dhi: int = tier * BotRank.DIVISIONS + BotRank.DIVISIONS - 1   # divisioona I
		for m in range(maxi(ladder_matches, 1)):
			_queue.append({"lo": dlo, "hi": dhi, "hi_team": m % 2,
				"anchor": false, "division": true})


## Ladder-ottelun roster: molemmille joukkueille satunnainen kokoonpano
## kiertopakasta; ylemmän rankin joukkue määräytyy jonomerkinnästä (hi_team).
func _build_ladder_roster(lq: Dictionary) -> Array:
	var lo: int = int(lq["lo"])
	var hi: int = int(lq["hi"])
	var hi_team: int = int(lq["hi_team"])
	var blue_rank: int = hi if hi_team == 0 else lo
	var orange_rank: int = lo if hi_team == 0 else hi
	_cur_ba = BotRank.rank_name(blue_rank)
	_cur_oa = BotRank.rank_name(orange_rank)
	var blue_set: Array = _pick_set()
	var orange_set: Array = _pick_set()
	return _assemble_roster(blue_set, orange_set, blue_rank, orange_rank)


# --- Sweep: tyyppiparien jono ---

func _build_queue() -> void:
	_queue = []
	for i in range(ARCHETYPES.size()):
		for j in range(ARCHETYPES.size()):
			for _r in range(repeats):
				_queue.append({"bi": i, "oi": j})


func _build_sweep_roster(bi: int, oi: int) -> Array:
	var blue_arch: Dictionary = ARCHETYPES[bi]
	var orange_arch: Dictionary = ARCHETYPES[oi]
	_cur_ba = str(blue_arch["name"])
	_cur_oa = str(orange_arch["name"])
	var blue_set: Array = _build_arch_team(blue_arch)
	var orange_set: Array = _build_arch_team(orange_arch)
	return _assemble_roster(blue_set, orange_set)


## Rakentaa yhden joukkueen kokoonpanotyypin roolikuvion mukaan. SAMAA heroa ei
## koskaan tule joukkueeseen kahdesti: ensin yritetään roolin pooli, ja jos se
## on loppu (esim. 4 tankkia mutta vain 3 tankkiheroa), täytetään millä tahansa
## käyttämättömällä herolla — ei enää tuplaa (kuten lobbyn lukituksessa).
func _build_arch_team(arch: Dictionary) -> Array:
	var pattern: Array = arch["pattern"]
	var used: Dictionary = {}
	var out: Array = []
	for i in range(team_size):
		var cat: String = str(pattern[i % pattern.size()])
		var pick: String = _pick_unused(_role_pool(cat), used)
		if pick == "":
			# Roolipooli loppui -> ota mikä tahansa käyttämätön hero.
			pick = _pick_unused(HeroDef.ORDER, used)
		if pick == "":
			pick = str(_role_pool(cat)[0])   # varasyy (ei osu 4v4:ssä, 17 heroa)
		used[pick] = true
		out.append(pick)
	return out


## Palauttaa satunnaisen käyttämättömän heron poolista, tai "" jos kaikki on jo
## käytetty.
func _pick_unused(pool: Array, used: Dictionary) -> String:
	var shuffled: Array = pool.duplicate()
	shuffled.shuffle()
	for cand in shuffled:
		if not used.has(cand):
			return str(cand)
	return ""


func _role_pool(cat: String) -> Array:
	match cat:
		"tank":
			return ["bastion", "boulder", "titan", "obsidian", "torq"]
		"mage":
			return ["ember", "volt", "myria"]
		"support":
			return ["luma", "maestro", "prism", "hush"]
		"assassin":
			return ["blink", "shade", "rift"]
		"fighter":
			return ["bramble", "tide", "lance", "kaira"]
		"ranger":
			return ["quill", "scout", "salvo", "vesper"]
		"damage":
			return ["ember", "volt", "blink", "shade", "rift", "bramble", "tide",
				"lance", "quill", "scout", "salvo", "kaira", "vesper", "myria"]
	return HeroDef.ORDER.duplicate()


# --- Manuaali: kokoonpanon rakennus ---

func _build_roster() -> Array:
	var blue_set: Array = _pick_set()
	var orange_set: Array = blue_set.duplicate() if comp_mode == Comp.MIRROR else _pick_set()
	return _assemble_roster(blue_set, orange_set)


## Nostaa joukkueen herot KIERTOPAKASTA: pakassa on jokainen hero kerran
## satunnaisessa järjestyksessä ja se täytetään uudelleen vasta tyhjennyttyä.
## Näin vakioajo (24 ottelua × 8 paikkaa) kattaa takuulla jokaisen heron useita
## kertoja — pelkkä satunnaisotanta voi jättää heron kokonaan ilman pelejä.
## Samaan joukkueeseen ei koskaan tule samaa heroa kahdesti.
func _pick_set() -> Array:
	var out: Array = []
	var used: Dictionary = {}
	for i in range(team_size):
		var pick: String = _draw_from_cycle(used)
		used[pick] = true
		out.append(pick)
	return out


## Yksi nosto kiertopakasta; exclude-herot (jo samassa joukkueessa) palautetaan
## pakan pohjalle. 23 heron pakka ja enintään 3 poissuljettua -> päättyy aina.
func _draw_from_cycle(exclude: Dictionary) -> String:
	var deferred: Array = []
	var pick := ""
	while pick == "":
		if _hero_cycle.is_empty():
			_hero_cycle = HeroDef.ORDER.duplicate()
			_hero_cycle.shuffle()
		var cand: String = str(_hero_cycle.pop_back())
		if exclude.has(cand):
			deferred.append(cand)
		else:
			pick = cand
	for cand in deferred:
		_hero_cycle.push_front(cand)
	return pick


# --- Yhteinen: koota kahdesta sankarisetistä täysi roster ---

## blue_rank/orange_rank >= 0 (ladder-testi) asettaa botille suoran rankin
## (PlayerProfile.bot_rank) — Arena antaa sen BotBrainille sellaisenaan.
## Muuten käytetään vanhaa 6-portaista tasoa (bot_level).
func _assemble_roster(blue_set: Array, orange_set: Array,
		blue_rank := -1, orange_rank := -1) -> Array:
	var roster: Array = []
	var idx := 0
	for t in range(2):
		var hs: Array = blue_set if t == 0 else orange_set
		var lvl: int = blue_level if t == 0 else orange_level
		var rk: int = blue_rank if t == 0 else orange_rank
		for j in range(team_size):
			var p := PlayerProfile.new()
			p.index = idx
			idx += 1
			p.device = -2
			p.is_bot = true
			p.team = t
			p.hero_id = str(hs[j % hs.size()])
			p.bot_level = lvl
			p.bot_rank = rk
			p.display_name = str(hs[j % hs.size()])
			roster.append(p)
	return roster
