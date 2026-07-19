class_name SimRunner
extends RefCounted
## Bot vs bot -simulaatio MOBA-kartalla. Kaksi tilaa:
##   Manuaali — N ottelua kiinteillä (satunnainen/peilattu) kokoonpanoilla.
##   Sweep    — käy läpi KAIKKI kokoonpanotyyppien parit (6×6) toistoineen,
##              mukaan lukien täysvahinko- ja täystuki-joukkueet, jotta
##              rikkinäiset herot/yhdistelmät löytyvät.
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
var sweep := false
var repeats := 1          # sweepissä: montako kertaa jokainen tyyppipari

var _results: Array = []          # manuaali: [snap]; sweep: [{snap, ba, oa}]
var _queue: Array = []            # sweep: lista {bi, oi}
var _cur_ba := ""
var _cur_oa := ""
var _match_index := 0
var _orig_max_steps := 8

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
	Game.sim_runner = self
	_results = []
	_match_index = 0
	if sweep:
		_build_queue()
		match_count = _queue.size()
	_orig_max_steps = Engine.max_physics_steps_per_frame
	Engine.time_scale = float(speed)
	Engine.max_physics_steps_per_frame = maxi(8, speed + 6)
	Game.mode_id = "moba"
	_start_match()


func _start_match() -> void:
	if sweep:
		var q: Dictionary = _queue[_match_index]
		Game.roster = _build_sweep_roster(int(q["bi"]), int(q["oi"]))
	else:
		Game.roster = _build_roster()
	Game.blue_rounds = 0
	Game.orange_rounds = 0
	Game.start_match()
	_announce_progress()


## Näyttää etenemisen ruudulla (ottelut ovat näkyvissä, vain nopeutettuna).
func _announce_progress() -> void:
	if Game.arena == null or not is_instance_valid(Game.arena):
		return
	var hud = Game.arena.hud
	if hud == null:
		return
	var sub: String = "%s vs %s" % [_cur_ba, _cur_oa] if sweep else "Bot vs bot"
	hud.show_banner("SIMULAATIO  %d/%d" % [_match_index + 1, match_count], sub, 1.4)


## Kutsutaan Game.match_finishedista simulaation aikana.
func on_match_done() -> void:
	if Game.arena != null and is_instance_valid(Game.arena):
		var snap: Dictionary = Game.arena.sim_snapshot()
		if sweep:
			_results.append({"snap": snap, "ba": _cur_ba, "oa": _cur_oa})
		else:
			_results.append(snap)
	_match_index += 1
	if _match_index < match_count:
		_start_match()
	else:
		_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = _orig_max_steps
	Game.simulating = false
	Game.sim_runner = null
	var results := SimResults.new()
	if sweep:
		var intro := [
			"=== KOKOONPANO-SWEEP (MOBA) ===",
			"%dv%d | Taso %d vs %d | Tyyppiparit: %d | Toistot: %d | Otteluita: %d | Nopeus: %dx" % [
				team_size, team_size, blue_level + 1, orange_level + 1,
				ARCHETYPES.size() * ARCHETYPES.size(), repeats, match_count, speed]]
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


## Rakentaa yhden joukkueen kokoonpanotyypin roolikuvion mukaan. Valitsee eri
## herot samaan joukkueeseen jos poolissa riittää, muuten kierrättää.
func _build_arch_team(arch: Dictionary) -> Array:
	var pattern: Array = arch["pattern"]
	var used: Dictionary = {}
	var out: Array = []
	for i in range(team_size):
		var cat: String = str(pattern[i % pattern.size()])
		var pool: Array = _role_pool(cat)
		var shuffled: Array = pool.duplicate()
		shuffled.shuffle()
		var pick: String = str(shuffled[0])
		for cand in shuffled:
			if not used.has(cand):
				pick = str(cand)
				break
		used[pick] = true
		out.append(pick)
	return out


func _role_pool(cat: String) -> Array:
	match cat:
		"tank":
			return ["bastion", "boulder", "titan"]
		"mage":
			return ["ember", "volt"]
		"support":
			return ["luma", "maestro", "prism"]
		"assassin":
			return ["blink", "shade", "rift"]
		"fighter":
			return ["bramble", "tide"]
		"ranger":
			return ["quill", "scout"]
		"damage":
			return ["ember", "volt", "blink", "shade", "rift", "bramble", "tide", "quill", "scout"]
	return HeroDef.ORDER.duplicate()


# --- Manuaali: kokoonpanon rakennus ---

func _build_roster() -> Array:
	var pool: Array = HeroDef.ORDER.duplicate()
	var blue_set := _pick_set(pool)
	var orange_set: Array = blue_set.duplicate() if comp_mode == Comp.MIRROR else _pick_set(pool)
	return _assemble_roster(blue_set, orange_set)


func _pick_set(pool: Array) -> Array:
	var shuffled: Array = pool.duplicate()
	shuffled.shuffle()
	var out: Array = []
	for i in range(team_size):
		out.append(shuffled[i % shuffled.size()])
	return out


# --- Yhteinen: koota kahdesta sankarisetistä täysi roster ---

func _assemble_roster(blue_set: Array, orange_set: Array) -> Array:
	var roster: Array = []
	var idx := 0
	for t in range(2):
		var hs: Array = blue_set if t == 0 else orange_set
		var lvl: int = blue_level if t == 0 else orange_level
		for j in range(team_size):
			var p := PlayerProfile.new()
			p.index = idx
			idx += 1
			p.device = -2
			p.is_bot = true
			p.team = t
			p.hero_id = str(hs[j % hs.size()])
			p.bot_level = lvl
			p.display_name = str(hs[j % hs.size()])
			roster.append(p)
	return roster
