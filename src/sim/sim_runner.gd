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
	var report := _build_report()
	var results := SimResults.new()
	results.report_text = report
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


# --- Raportti ---

func _build_report() -> String:
	var lines: Array = []
	lines.append("=== MOBA-SIMULAATIO ===")
	lines.append("Kokoonpano: %dv%d | Sininen taso %d vs Oranssi taso %d | Komppa: %s | Otteluita: %d | Nopeus: %dx" % [
		team_size, team_size, blue_level + 1, orange_level + 1,
		("Peilattu" if comp_mode == Comp.MIRROR else "Satunnainen"),
		match_count, speed])
	lines.append("")

	var wins := [0, 0]
	var total_time := 0.0
	var agg: Dictionary = {}   # hero_id -> koostetut arvot

	for mi in range(_results.size()):
		var r: Dictionary = _results[mi]
		var winner: int = r["winner"]
		wins[winner] += 1
		total_time += float(r["elapsed"])
		lines.append("--- OTTELU %d ---" % (mi + 1))
		lines.append("Kesto: %s | Voittaja: %s (%s)" % [
			_fmt(float(r["elapsed"])), _team(winner), str(r["reason"])])
		# Tapahtumat
		lines.append("Tapahtumat:")
		for ev in r["events"]:
			lines.append("  %s  %s" % [_fmt(float(ev["t"])), str(ev["text"])])
		# Sankarit joukkueittain
		for t in range(2):
			lines.append("Sankarit (%s):" % _team(t))
			for h in r["heroes"]:
				if int(h["team"]) != t:
					continue
				lines.append("  %-9s L%d | K/D/A %d/%d/%d | vah %d | otettu %d | rak.vah %d | CS %d | paran %d" % [
					str(h["hero_id"]), int(h["level"]) + 1,
					int(h["kos"]), int(h["deaths"]), int(h["assists"]),
					int(h["damage"]), int(h["taken"]), int(h["structure_damage"]),
					int(h["minion_kills"]), int(h["healing"])])
				_accumulate(agg, h, winner)
		lines.append("")

	# Yhteenveto
	lines.append("=== YHTEENVETO (%d ottelua) ===" % _results.size())
	lines.append("Voitot: Sininen %d - %d Oranssi" % [wins[0], wins[1]])
	var avg := total_time / maxf(_results.size(), 1.0)
	lines.append("Keskimääräinen kesto: %s" % _fmt(avg))
	lines.append("")
	lines.append("Sankariteho (kaikki ottelut, järjestetty vahinko/min):")
	lines.append("  sankari    | pelit | KDA (k/d/a) | vah/min | rak.vah/peli | CS/peli | voitto%")
	var rows: Array = agg.values()
	for a in rows:
		a["dpm"] = _dpm(a)
	rows.sort_custom(func(x, y): return float(x["dpm"]) > float(y["dpm"]))
	for a in rows:
		var games: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-9s |  %2d   | %.1f/%.1f/%.1f | %6d | %6d | %4.1f | %3d%%" % [
			str(a["hero_id"]), int(a["games"]),
			float(a["kos"]) / games, float(a["deaths"]) / games, float(a["assists"]) / games,
			int(float(a["dpm"])), int(float(a["structure_damage"]) / games),
			float(a["minion_kills"]) / games,
			int(round(100.0 * float(a["wins"]) / games))])

	return "\n".join(PackedStringArray(lines))


func _accumulate(agg: Dictionary, h: Dictionary, winner: int) -> void:
	var id: String = str(h["hero_id"])
	if not agg.has(id):
		agg[id] = {"hero_id": id, "games": 0, "kos": 0.0, "deaths": 0.0,
			"assists": 0.0, "damage": 0.0, "taken": 0.0, "structure_damage": 0.0,
			"minion_kills": 0.0, "healing": 0.0, "time": 0.0, "wins": 0}
	var a: Dictionary = agg[id]
	a["games"] += 1
	a["kos"] += float(h["kos"])
	a["deaths"] += float(h["deaths"])
	a["assists"] += float(h["assists"])
	a["damage"] += float(h["damage"])
	a["taken"] += float(h["taken"])
	a["structure_damage"] += float(h["structure_damage"])
	a["minion_kills"] += float(h["minion_kills"])
	a["healing"] += float(h["healing"])
	if int(h["team"]) == winner:
		a["wins"] += 1


## Vahinko per peliminuutti (koostettu). Käyttää keskimääräistä ottelukestoa.
func _dpm(a: Dictionary) -> float:
	var games: float = maxf(float(a["games"]), 1.0)
	var minutes: float = maxf(_avg_minutes(), 0.1)
	return (float(a["damage"]) / games) / minutes


func _avg_minutes() -> float:
	var total := 0.0
	for r in _results:
		total += float(r["elapsed"])
	return (total / maxf(_results.size(), 1.0)) / 60.0


func _team(t: int) -> String:
	return "Sininen" if t == 0 else "Oranssi"


func _fmt(sec: float) -> String:
	var s: int = int(sec)
	return "%d:%02d" % [s / 60, s % 60]
