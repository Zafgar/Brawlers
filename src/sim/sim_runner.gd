class_name SimRunner
extends RefCounted
## Bot vs bot -simulaatio MOBA-kartalla. Ajaa N ottelua kahdella eritasoisella
## botti-joukkueella, kerää telemetrian ja tuottaa tekstiraportin, jonka voi
## liittää kehittäjälle tekoälyn ja tasapainon säätöä varten.
##
## Nopeutus tehdään Engine.time_scalella (tarkka: askeleet pysyvät 1/60 s,
## niitä vain otetaan enemmän per ruutu). Lähtölaskenta ja voittobanneri
## ohitetaan simulaatiossa.

enum Comp { RANDOM, MIRROR }

var team_size := 3
var blue_level := 2       # indeksi 0–5 (taso 1–6)
var orange_level := 4
var comp_mode := Comp.RANDOM
var match_count := 3
var speed := 6

var _results: Array = []
var _match_index := 0
var _orig_max_steps := 8


func start() -> void:
	Game.simulating = true
	Game.sim_runner = self
	_results = []
	_match_index = 0
	_orig_max_steps = Engine.max_physics_steps_per_frame
	Engine.time_scale = float(speed)
	Engine.max_physics_steps_per_frame = maxi(8, speed + 6)
	Game.mode_id = "moba"
	_start_match()


func _start_match() -> void:
	Game.roster = _build_roster()
	Game.blue_rounds = 0
	Game.orange_rounds = 0
	Game.start_match()


## Kutsutaan Game.match_finishedista simulaation aikana.
func on_match_done() -> void:
	if Game.arena != null and is_instance_valid(Game.arena):
		_results.append(Game.arena.sim_snapshot())
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
	var intro := [
		"=== MOBA-SIMULAATIO ===",
		"Kokoonpano: %dv%d | Sininen taso %d vs Oranssi taso %d | Komppa: %s | Otteluita: %d | Nopeus: %dx" % [
			team_size, team_size, blue_level + 1, orange_level + 1,
			("Peilattu" if comp_mode == Comp.MIRROR else "Satunnainen"),
			match_count, speed]]
	var results := SimResults.new()
	results.report_text = MatchReport.build(_results, intro)
	Game._swap(results)


# --- Kokoonpanon rakennus ---

func _build_roster() -> Array:
	var pool: Array = HeroDef.ORDER.duplicate()
	var blue_set := _pick_set(pool)
	var orange_set: Array = blue_set.duplicate() if comp_mode == Comp.MIRROR else _pick_set(pool)
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
			p.hero_id = hs[j % hs.size()]
			p.bot_level = lvl
			p.display_name = "%s" % hs[j % hs.size()]
			roster.append(p)
	return roster


func _pick_set(pool: Array) -> Array:
	var shuffled: Array = pool.duplicate()
	shuffled.shuffle()
	var out: Array = []
	for i in range(team_size):
		out.append(shuffled[i % shuffled.size()])
	return out
