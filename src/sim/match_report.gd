class_name MatchReport
## Rakentaa tekstiraportin ottelun tilannekuvista (arena.sim_snapshot).
## build()       — yksi tai muutama ottelu, per-ottelu-detaljit + koosteet.
## build_sweep() — laaja kokoonpanoläpikäynti: kokoonpanotyypit, anomaliat ja
##                 sankarikoosteet, jotta rikkinäiset yhdistelmät/herot löytyvät.
##
## Tilastot per sankari: K/D/A, vahinko, otettu, tornivahinko, viidakkovahinko,
## vaimennettu (kilvet/torjunnat), parannettu ja CS. Ihmiset merkitään *:llä.


static func build(snapshots: Array, intro: Array) -> String:
	var lines: Array = intro.duplicate()
	lines.append("")
	var wins := [0, 0]
	var total_time := 0.0
	var agg: Dictionary = {}

	for mi in range(snapshots.size()):
		var r: Dictionary = snapshots[mi]
		var winner: int = int(r["winner"])
		if winner >= 0 and winner <= 1:
			wins[winner] += 1
		total_time += float(r["elapsed"])
		lines.append("--- OTTELU %d ---" % (mi + 1))
		lines.append("Kesto: %s | Voittaja: %s (%s)" % [
			_fmt(float(r["elapsed"])), _team(winner), str(r["reason"])])
		lines.append("Tapahtumat:")
		for ev in r["events"]:
			lines.append("  %s  %s" % [_fmt(float(ev["t"])), str(ev["text"])])
		for t in range(2):
			lines.append("Sankarit (%s):" % _team(t))
			for h in r["heroes"]:
				if int(h["team"]) != t:
					continue
				lines.append(_hero_line(h))
				_accumulate(agg, h, winner)
		lines.append("")

	var count: int = maxi(snapshots.size(), 1)
	var avg_min: float = (total_time / float(count)) / 60.0
	lines.append("=== YHTEENVETO (%d ottelua) ===" % snapshots.size())
	lines.append("Voitot: Sininen %d - %d Oranssi" % [wins[0], wins[1]])
	lines.append("Keskimääräinen kesto: %s   (* = ihmispelaaja)" % _fmt(total_time / float(count)))
	lines.append("")
	_hero_table(lines, agg, avg_min)
	return "\n".join(PackedStringArray(lines))


## Laaja läpikäynti: kukin ottelu on {snap, ba, oa} (blue/orange-kokoonpanotyyppi).
static func build_sweep(results: Array, intro: Array) -> String:
	var lines: Array = intro.duplicate()
	lines.append("")
	var arch: Dictionary = {}
	var agg: Dictionary = {}
	var total_time := 0.0

	for e in results:
		var snap: Dictionary = e["snap"]
		var winner: int = int(snap["winner"])
		var elapsed: float = float(snap["elapsed"])
		total_time += elapsed
		_arch_add(arch, str(e["ba"]), winner == 0, elapsed)
		_arch_add(arch, str(e["oa"]), winner == 1, elapsed)
		for h in snap["heroes"]:
			_accumulate(agg, h, winner)

	var count: int = maxi(results.size(), 1)
	var avg_min: float = (total_time / float(count)) / 60.0

	lines.append("=== KOKOONPANOTYYPIT (%d ottelua) ===" % results.size())
	lines.append("  tyyppi       | pelit | voitto% | keskikesto | vah/peli")
	var arows: Array = arch.values()
	for a in arows:
		a["wr"] = float(a["wins"]) / maxf(float(a["games"]), 1.0)
	arows.sort_custom(func(x, y): return float(x["wr"]) > float(y["wr"]))
	for a in arows:
		var g: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-12s | %3d   | %5.1f %% | %s      | %6d" % [
			str(a["name"]), int(a["games"]), float(a["wr"]) * 100.0,
			_fmt(float(a["time"]) / g), int(float(a["damage"]) / g)])

	# Anomaliat: epätasapainoiset tyypit ja poikkeavat herot.
	lines.append("")
	lines.append("=== ANOMALIAT (mahdollisesti rikki / epätasapaino) ===")
	var flagged := false
	for a in arows:
		if int(a["games"]) >= 4 and (float(a["wr"]) >= 0.75 or float(a["wr"]) <= 0.25):
			flagged = true
			lines.append("  Kokoonpano '%s': voitto%% %.0f (%d peliä) — %s" % [
				str(a["name"]), float(a["wr"]) * 100.0, int(a["games"]),
				("liian vahva?" if float(a["wr"]) >= 0.75 else "liian heikko?")])
	# Sankaripoikkeamat vahinko/min-keskiarvosta.
	var mean_dpm := _mean_dpm(agg, avg_min)
	for id in agg:
		var a: Dictionary = agg[id]
		if int(a["games"]) < 3:
			continue
		var dpm: float = (float(a["damage"]) / maxf(float(a["games"]), 1.0)) / maxf(avg_min, 0.1)
		if float(a["damage"]) <= 1.0:
			flagged = true
			lines.append("  Sankari '%s': ~0 vahinkoa — rikki tai ei osu?" % id)
		elif mean_dpm > 0.0 and dpm > mean_dpm * 2.0:
			flagged = true
			lines.append("  Sankari '%s': vahinko/min %d (yli 2x keskiarvo %d) — mahd. yli" % [
				id, int(dpm), int(mean_dpm)])
		elif mean_dpm > 0.0 and dpm < mean_dpm * 0.4:
			flagged = true
			lines.append("  Sankari '%s': vahinko/min %d (alle 0.4x keskiarvo %d) — mahd. ali" % [
				id, int(dpm), int(mean_dpm)])
	if not flagged:
		lines.append("  Ei selkeitä anomalioita.")

	lines.append("")
	_hero_table(lines, agg, avg_min)
	return "\n".join(PackedStringArray(lines))


# --- Jaetut apurit ---

static func _hero_line(h: Dictionary) -> String:
	var mark: String = "*" if bool(h.get("human", false)) else " "
	return "  %s%-8s L%d | K/D/A %2d/%2d/%2d | vah %5d | otettu %5d | torni %5d | viidakko %5d | vaimenn %5d | paran %5d | CS %2d" % [
		mark, str(h["hero_id"]), int(h["level"]) + 1,
		int(h["kos"]), int(h["deaths"]), int(h["assists"]),
		int(h["damage"]), int(h["taken"]), int(h["structure_damage"]),
		int(h.get("jungle_damage", 0)), int(h.get("mitigated", 0)),
		int(h["healing"]), int(h["minion_kills"])]


static func _hero_table(lines: Array, agg: Dictionary, avg_min: float) -> void:
	lines.append("Sankariteho (järjestetty vahinko/min):")
	lines.append("  sankari  | pel | K / D / A   |vah/min|torni |viidak|paran |vaim. | CS  |voit%")
	var rows: Array = agg.values()
	for a in rows:
		a["dpm"] = (float(a["damage"]) / maxf(float(a["games"]), 1.0)) / maxf(avg_min, 0.1)
	rows.sort_custom(func(x, y): return float(x["dpm"]) > float(y["dpm"]))
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-8s | %2d  | %4.1f/%4.1f/%4.1f | %5d |%5d |%5d |%5d |%5d |%4.1f |%3d%%" % [
			str(a["hero_id"]), int(a["games"]),
			float(a["kos"]) / g, float(a["deaths"]) / g, float(a["assists"]) / g,
			int(float(a["dpm"])), int(float(a["structure_damage"]) / g),
			int(float(a["jungle_damage"]) / g), int(float(a["healing"]) / g),
			int(float(a["mitigated"]) / g), float(a["minion_kills"]) / g,
			int(round(100.0 * float(a["wins"]) / g))])


static func _mean_dpm(agg: Dictionary, avg_min: float) -> float:
	var total := 0.0
	var n := 0
	for id in agg:
		var a: Dictionary = agg[id]
		if int(a["games"]) < 3 or float(a["damage"]) <= 1.0:
			continue
		total += (float(a["damage"]) / maxf(float(a["games"]), 1.0)) / maxf(avg_min, 0.1)
		n += 1
	return total / maxf(n, 1)


static func _arch_add(arch: Dictionary, name: String, won: bool, elapsed: float) -> void:
	if not arch.has(name):
		arch[name] = {"name": name, "games": 0, "wins": 0, "time": 0.0, "damage": 0.0}
	var a: Dictionary = arch[name]
	a["games"] += 1
	a["time"] += elapsed
	if won:
		a["wins"] += 1


static func _accumulate(agg: Dictionary, h: Dictionary, winner: int) -> void:
	var id: String = str(h["hero_id"])
	if not agg.has(id):
		agg[id] = {"hero_id": id, "games": 0, "kos": 0.0, "deaths": 0.0,
			"assists": 0.0, "damage": 0.0, "taken": 0.0, "structure_damage": 0.0,
			"jungle_damage": 0.0, "mitigated": 0.0, "minion_kills": 0.0,
			"healing": 0.0, "wins": 0}
	var a: Dictionary = agg[id]
	a["games"] += 1
	a["kos"] += float(h["kos"])
	a["deaths"] += float(h["deaths"])
	a["assists"] += float(h["assists"])
	a["damage"] += float(h["damage"])
	a["taken"] += float(h["taken"])
	a["structure_damage"] += float(h["structure_damage"])
	a["jungle_damage"] += float(h.get("jungle_damage", 0))
	a["mitigated"] += float(h.get("mitigated", 0))
	a["minion_kills"] += float(h["minion_kills"])
	a["healing"] += float(h["healing"])
	if int(h["team"]) == winner:
		a["wins"] += 1


static func _team(t: int) -> String:
	if t < 0:
		return "Tasapeli"
	return "Sininen" if t == 0 else "Oranssi"


static func _fmt(sec: float) -> String:
	var s: int = int(sec)
	return "%d:%02d" % [s / 60, s % 60]
