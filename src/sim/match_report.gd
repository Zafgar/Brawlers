class_name MatchReport
## Rakentaa tekstiraportin yhdestä tai useammasta ottelun tilannekuvasta
## (arena.sim_snapshot). Käytetään sekä simulaatiossa (bot vs bot) että
## pelaajien otteluissa — pelaaja voi antaa raporttinsa kehittäjälle.
##
## Tilastot per sankari: K/D/A, aiheutettu vahinko, otettu vahinko, tornivahinko,
## viidakkovahinko, vaimennettu (kilvet/torjunnat), parannettu ja CS (minionit).
## Ihmispelaajat merkitään *-tähdellä.


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
				var mark: String = "*" if bool(h.get("human", false)) else " "
				lines.append("  %s%-8s L%d | K/D/A %2d/%2d/%2d | vah %5d | otettu %5d | torni %5d | viidakko %5d | vaimenn %5d | paran %5d | CS %2d" % [
					mark, str(h["hero_id"]), int(h["level"]) + 1,
					int(h["kos"]), int(h["deaths"]), int(h["assists"]),
					int(h["damage"]), int(h["taken"]), int(h["structure_damage"]),
					int(h.get("jungle_damage", 0)), int(h.get("mitigated", 0)),
					int(h["healing"]), int(h["minion_kills"])])
				_accumulate(agg, h, winner)
		lines.append("")

	var count: int = maxi(snapshots.size(), 1)
	var avg_min: float = (total_time / float(count)) / 60.0
	lines.append("=== YHTEENVETO (%d ottelua) ===" % snapshots.size())
	lines.append("Voitot: Sininen %d - %d Oranssi" % [wins[0], wins[1]])
	lines.append("Keskimääräinen kesto: %s" % _fmt(total_time / float(count)))
	lines.append("(* = ihmispelaaja)")
	lines.append("")
	lines.append("Sankariteho (kaikki ottelut, järjestetty vahinko/min):")
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

	return "\n".join(PackedStringArray(lines))


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
	return "Sininen" if t == 0 else "Oranssi"


static func _fmt(sec: float) -> String:
	var s: int = int(sec)
	return "%d:%02d" % [s / 60, s % 60]
