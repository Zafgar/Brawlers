class_name MatchReport
## Rakentaa tekstiraportin ottelun tilannekuvista (arena.sim_snapshot).
## build()        — yksi tai muutama ottelu, per-ottelu-detaljit + koosteet.
## build_sweep()  — laaja kokoonpanoläpikäynti: kokoonpanotyypit, anomaliat ja
##                  sankarikoosteet, jotta rikkinäiset yhdistelmät/herot löytyvät.
## build_ladder() — rank vs rank -laddertesti: voittaako ylempi rank tarpeeksi
##                  usein jokaisessa parissa (LADDER TOIMII / LADDER RIKKI).
##
## Tilastot per sankari: K/D/A, vahinko, otettu, tornivahinko, viidakkovahinko,
## vaimennettu (kilvet/torjunnat), parannettu ja CS. Ihmiset merkitään *:llä.

# Ladder-testin hyväksymisraja: ylemmän rankin on voitettava vähintään tämä
# osuus parin otteluista, muuten pari merkitään varoitukseksi (ladder rikki).
const LADDER_OK_WINRATE := 0.8


static func build(snapshots: Array, intro: Array) -> String:
	var lines: Array = intro.duplicate()
	lines.append("")
	var wins := [0, 0]
	var total_time := 0.0
	var agg: Dictionary = {}
	var comps: Dictionary = {}
	var pairs: Dictionary = {}
	var roles: Dictionary = {}

	for mi in range(snapshots.size()):
		var r: Dictionary = snapshots[mi]
		var winner: int = int(r["winner"])
		if winner >= 0 and winner <= 1:
			wins[winner] += 1
		total_time += float(r["elapsed"])
		_accumulate_meta(comps, pairs, r, winner)
		lines.append("--- OTTELU %d ---" % (mi + 1))
		lines.append("Kesto: %s | Voittaja: %s (%s)" % [
			_fmt(float(r["elapsed"])), _team(winner), str(r["reason"])])
		if float(r.get("first_wave_crash", -1.0)) >= 0.0:
			lines.append("Ensimmäinen wave crash / jungle avautui: %s" %
				_fmt(float(r["first_wave_crash"])))
		lines.append("Tapahtumat:")
		for ev in r["events"]:
			lines.append("  %s  %s" % [_fmt(float(ev["t"])), str(ev["text"])])
		for t in range(2):
			lines.append("Sankarit (%s):" % _team(t))
			for h in r["heroes"]:
				if int(h["team"]) != t:
					continue
				lines.append(_hero_line(h))
				lines.append(_hero_level_line(h))
				_accumulate(agg, h, winner, float(r["elapsed"]))
				_accumulate_role(roles, h, float(r["elapsed"]))
		_match_objective_timeline(lines, r)
		lines.append("")

	var count: int = maxi(snapshots.size(), 1)
	var avg_min: float = (total_time / float(count)) / 60.0
	lines.append("=== YHTEENVETO (%d ottelua) ===" % snapshots.size())
	lines.append("Voitot: Sininen %d - %d Oranssi" % [wins[0], wins[1]])
	lines.append("Keskimääräinen kesto: %s   (* = ihmispelaaja)" % _fmt(total_time / float(count)))
	lines.append("")
	_meta_tables(lines, comps, pairs)
	_role_progression_table(lines, roles)
	_level_progression_table(lines, roles)
	_map_time_table(lines, agg)
	_jungle_clear_table(lines, agg)
	_tower_timing_table(lines, snapshots)
	_buff_impact_tables(lines, agg, snapshots)
	_hero_table(lines, agg, avg_min)
	_economy_table(lines, agg)
	_survivability_table(lines, agg)
	_tanking_table(lines, agg)
	_ability_table(lines, agg)
	return "\n".join(PackedStringArray(lines))


## Laaja läpikäynti: kukin ottelu on {snap, ba, oa} (blue/orange-kokoonpanotyyppi).
static func build_sweep(results: Array, intro: Array) -> String:
	var lines: Array = intro.duplicate()
	lines.append("")
	var arch: Dictionary = {}
	var agg: Dictionary = {}
	var comps: Dictionary = {}
	var pairs: Dictionary = {}
	var roles: Dictionary = {}
	var snapshots: Array = []
	var total_time := 0.0

	for e in results:
		var snap: Dictionary = e["snap"]
		var winner: int = int(snap["winner"])
		var elapsed: float = float(snap["elapsed"])
		snapshots.append(snap)
		_accumulate_meta(comps, pairs, snap, winner)
		total_time += elapsed
		# Kokoonpanon vah/peli: summaa joukkueen sankarien vahinko (ba=sininen, oa=oranssi).
		var dmg0 := 0.0
		var dmg1 := 0.0
		for h in snap["heroes"]:
			if int(h["team"]) == 0:
				dmg0 += float(h["damage"])
			else:
				dmg1 += float(h["damage"])
		_arch_add(arch, str(e["ba"]), winner == 0, elapsed, dmg0)
		_arch_add(arch, str(e["oa"]), winner == 1, elapsed, dmg1)
		for h in snap["heroes"]:
			_accumulate(agg, h, winner, elapsed)
			_accumulate_role(roles, h, elapsed)

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
		var hero_min: float = float(a.get("time", 0.0)) / 60.0
		if hero_min <= 0.0:
			hero_min = maxf(float(a["games"]), 1.0) * avg_min
		var dpm: float = float(a["damage"]) / maxf(hero_min, 0.1)
		if float(a["damage"]) <= 1.0:
			flagged = true
			lines.append("  Sankari '%s': ~0 vahinkoa — rikki tai ei osu?" % id)
		elif mean_dpm > 0.0 and dpm > mean_dpm * 2.0:
			flagged = true
			lines.append("  Sankari '%s': vahinko/min %d (yli 2x keskiarvo %d) — mahd. yli" % [
				id, int(dpm), int(mean_dpm)])
		elif mean_dpm > 0.0 and dpm < mean_dpm * 0.4:
			# Rooli-tietoinen: tuki/tankki tekee vähän vahinkoa mutta parantaa/estää,
			# joten matala vahinko ei ole "ali" jos utility (paran+vaimennus)/peli riittää.
			var role: String = str(HeroDef.get_def(id).get("role", ""))
			var util: float = (float(a["healing"]) + float(a["mitigated"])) / maxf(float(a["games"]), 1.0)
			if not ((role == "Tuki" or role == "Tankki") and util >= 150.0):
				flagged = true
				lines.append("  Sankari '%s': vahinko/min %d (alle 0.4x keskiarvo %d) — mahd. ali (%s)" % [
					id, int(dpm), int(mean_dpm), role if role != "" else "?"])
	if not flagged:
		lines.append("  Ei selkeitä anomalioita.")

	lines.append("")
	_meta_tables(lines, comps, pairs)
	_role_progression_table(lines, roles)
	_level_progression_table(lines, roles)
	_map_time_table(lines, agg)
	_jungle_clear_table(lines, agg)
	_tower_timing_table(lines, snapshots)
	_buff_impact_tables(lines, agg, snapshots)
	_hero_table(lines, agg, avg_min)
	_economy_table(lines, agg)
	_survivability_table(lines, agg)
	_tanking_table(lines, agg)
	_ability_table(lines, agg)
	return "\n".join(PackedStringArray(lines))


## Ladder-testin raportti. Kukin tulos on {snap, lo, hi, hi_team, anchor}:
## lo/hi = parin rankit (BotRank 0..31), hi_team = kumpi joukkue pelasi ylempää
## rankia (0/1, vuorotellen -> puolibias kumoutuu), anchor = hajautusankkuri
## (iso rankiero, terveystarkistus). Tuomio: ylemmän on voitettava vähintään
## LADDER_OK_WINRATE otteluista, muuten "LADDER RIKKI kohdassa X".
static func build_ladder(results: Array, intro: Array) -> String:
	var lines: Array = intro.duplicate()
	lines.append("")
	var table: Dictionary = {}   # "lo-hi" -> koonti (säilyttää lisäysjärjestyksen)
	for e in results:
		var snap: Dictionary = e["snap"]
		var lo: int = int(e["lo"])
		var hi: int = int(e["hi"])
		var key := "%d-%d" % [lo, hi]
		if not table.has(key):
			table[key] = {"lo": lo, "hi": hi, "games": 0, "hi_wins": 0,
				"hi_wins_blue": 0, "hi_wins_orange": 0, "draws": 0, "time": 0.0,
				"anchor": bool(e["anchor"]), "nexus_ends": 0,
				"hi_kills": 0.0, "lo_kills": 0.0, "hi_deaths": 0.0, "lo_deaths": 0.0,
				"hi_assists": 0.0, "lo_assists": 0.0, "hi_cs": 0.0, "lo_cs": 0.0,
				"hi_gold": 0.0, "lo_gold": 0.0, "hi_towers": 0.0, "lo_towers": 0.0,
				"hi_obj": 0.0, "lo_obj": 0.0}
		var a: Dictionary = table[key]
		var winner: int = int(snap["winner"])
		var hi_team: int = int(e["hi_team"])
		a["games"] += 1
		a["time"] += float(snap["elapsed"])
		if winner < 0:
			a["draws"] += 1
		elif winner == hi_team:
			a["hi_wins"] += 1
			if hi_team == 0:
				a["hi_wins_blue"] += 1
			else:
				a["hi_wins_orange"] += 1
		# Tilastodominanssi: kerää joukkuetason KDA/CS/kulta/rakenteet/objektiivit
		# ylemmän ja alemman puolelle -> raportti kertoo MITEN paljon paremmin
		# ylempi pelasi silloinkin kun peli ei päättynyt nexukseen.
		if str(snap.get("reason", "")).begins_with("nexus"):
			a["nexus_ends"] = int(a["nexus_ends"]) + 1
		for hv in snap.get("heroes", []):
			var hd: Dictionary = hv
			var pre := "hi_" if int(hd.get("team", -1)) == hi_team else "lo_"
			a[pre + "kills"] = float(a[pre + "kills"]) + float(hd.get("kos", 0))
			a[pre + "deaths"] = float(a[pre + "deaths"]) + float(hd.get("deaths", 0))
			a[pre + "assists"] = float(a[pre + "assists"]) + float(hd.get("assists", 0))
			a[pre + "cs"] = float(a[pre + "cs"]) + float(hd.get("minion_kills", 0))
			a[pre + "gold"] = float(a[pre + "gold"]) + float(hd.get("gold", 0))
		for tv in snap.get("tower_events", []):
			var te: Dictionary = tv
			var at := int(te.get("attacker_team", -1))
			if at == 0 or at == 1:
				var pre_t := "hi_" if at == hi_team else "lo_"
				a[pre_t + "towers"] = float(a[pre_t + "towers"]) + 1.0
		var cb: Array = snap.get("crystals_broken", [])
		if cb.size() >= 2:
			a["hi_towers"] = float(a["hi_towers"]) + float(cb[hi_team])
			a["lo_towers"] = float(a["lo_towers"]) + float(cb[1 - hi_team])
		for ov in snap.get("objective_events", []):
			var oe: Dictionary = ov
			var ot := int(oe.get("team", -1))
			if (ot == 0 or ot == 1) and str(oe.get("kind", "")) in ["baron", "dragon"]:
				var pre_o := "hi_" if ot == hi_team else "lo_"
				a[pre_o + "obj"] = float(a[pre_o + "obj"]) + 1.0

	lines.append("=== LADDER: PARIKOHTAISET TULOKSET (alempi vs ylempi rank) ===")
	lines.append("  'ylempi voitti (sin+ora)' erittelee kummalla puolella ylempi pelasi -> puolibias näkyy.")
	lines.append("  pari                             | pelit | ylempi voitti | tasap | voitto% | keskikesto | tulos")
	var broken: Array = []
	for key in table:
		var a: Dictionary = table[key]
		var games: int = maxi(int(a["games"]), 1)
		var wr: float = float(a["hi_wins"]) / float(games)
		var ok: bool = wr >= LADDER_OK_WINRATE
		var name := "%s vs %s" % [BotRank.rank_name(int(a["lo"])),
			BotRank.rank_name(int(a["hi"]))]
		if bool(a["anchor"]):
			name += " (ankkuri)"
		if not ok:
			broken.append("%s (%d %%)" % [name, int(round(wr * 100.0))])
		lines.append("  %-32s | %5d | %6d (%d+%d)  | %5d | %5.1f %% | %10s | %s" % [
			name, int(a["games"]), int(a["hi_wins"]),
			int(a["hi_wins_blue"]), int(a["hi_wins_orange"]), int(a["draws"]),
			wr * 100.0, _fmt(float(a["time"]) / float(games)),
			"OK" if ok else "VAROITUS"])

	# Tilastodominanssi: näyttää KUINKA paljon paremmin ylempi pelasi — myös
	# silloin kun voitto ratkesi aikakatossa eikä nexuksessa.
	lines.append("")
	lines.append("=== LADDER: TILASTODOMINANSSI (joukkuekeskiarvot per ottelu, ylempi/alempi) ===")
	lines.append("  KDA = joukkueen tapot/kuolemat/avustukset. CS = last hitit. GPM = kultaa/min.")
	lines.append("  rakent. = tornit+kristallit. obj = baron+dragon. nexus = nexukseen päättyneet pelit.")
	lines.append("  pari                             | KDA ylempi      | KDA alempi      | CS yl/al | GPM yl/al | rakent. | obj     | nexus")
	for key in table:
		var a: Dictionary = table[key]
		var g := float(maxi(int(a["games"]), 1))
		var mins: float = maxf(float(a["time"]) / 60.0, 0.1)
		var name := "%s vs %s" % [BotRank.rank_name(int(a["lo"])),
			BotRank.rank_name(int(a["hi"]))]
		if bool(a["anchor"]):
			name += " (ankkuri)"
		lines.append("  %-32s | %5.1f/%4.1f/%4.1f | %5.1f/%4.1f/%4.1f | %3.0f/%3.0f  | %4.0f/%4.0f | %3.1f/%3.1f | %2.1f/%2.1f | %d/%d" % [
			name,
			float(a["hi_kills"]) / g, float(a["hi_deaths"]) / g, float(a["hi_assists"]) / g,
			float(a["lo_kills"]) / g, float(a["lo_deaths"]) / g, float(a["lo_assists"]) / g,
			float(a["hi_cs"]) / g, float(a["lo_cs"]) / g,
			float(a["hi_gold"]) / mins, float(a["lo_gold"]) / mins,
			float(a["hi_towers"]) / g, float(a["lo_towers"]) / g,
			float(a["hi_obj"]) / g, float(a["lo_obj"]) / g,
			int(a["nexus_ends"]), int(a["games"])])

	lines.append("")
	lines.append("=== LADDER-YHTEENVETO ===")
	if broken.is_empty():
		lines.append("LADDER TOIMII — ylempi rank voitti vähintään %d %% otteluista jokaisessa parissa." % [
			int(round(LADDER_OK_WINRATE * 100.0))])
	else:
		lines.append("LADDER RIKKI kohdassa: %s" % ", ".join(PackedStringArray(broken)))
		lines.append("Tarkista BotRank-parametrikäyrien monotonisuus näiden rankien välillä")
		lines.append("(src/ai/bot_rank.gd + BotBrain._init) ja aja testi uudelleen isommalla otannalla.")
	# Diagnoosi: erottele "käyrät eivät eroa" vs "ylempi dominoi muttei sulje".
	var stat_notes: Array = []
	for key in table:
		var a: Dictionary = table[key]
		var games2: int = maxi(int(a["games"]), 1)
		var wr2: float = float(a["hi_wins"]) / float(games2)
		if wr2 >= LADDER_OK_WINRATE:
			continue
		var name2 := "%s vs %s" % [BotRank.rank_name(int(a["lo"])),
			BotRank.rank_name(int(a["hi"]))]
		var lo_gold: float = maxf(float(a["lo_gold"]), 1.0)
		var gold_lead: float = (float(a["hi_gold"]) - lo_gold) / lo_gold
		if gold_lead >= 0.08:
			stat_notes.append("  %s: ylempi dominoi taloutta +%d %% muttei sulkenut pelejä -> lopetusmekaniikka, ei käyräongelma." % [
				name2, int(round(gold_lead * 100.0))])
		elif gold_lead <= 0.02:
			stat_notes.append("  %s: ei tilastoeroa (kulta %+d %%) -> rankkierot eivät pure tällä välillä." % [
				name2, int(round(gold_lead * 100.0))])
	if not stat_notes.is_empty():
		lines.append("Diagnoosi:")
		for note in stat_notes:
			lines.append(str(note))
	return "\n".join(PackedStringArray(lines))


# --- Jaetut apurit ---

static func _hero_line(h: Dictionary) -> String:
	var mark: String = "*" if bool(h.get("human", false)) else " "
	var ai_level := int(h.get("ai_level", -1))
	var ai_text := "-" if ai_level < 0 else str(ai_level + 1)
	return "  %s%-8s %-7s LV%02d AI%s | K/D/A %2d/%2d/%2d | vah %5d | torni %5d | viidakko %5d | CS %2d | %4dG %5dXP" % [
		mark, str(h["hero_id"]), str(h.get("progression_role", h.get("role", "?"))),
		int(h.get("level", 1)), ai_text,
		int(h["kos"]), int(h["deaths"]), int(h["assists"]),
		int(h["damage"]), int(h["structure_damage"]),
		int(h.get("jungle_damage", 0)), int(h["minion_kills"]),
		int(h.get("gold", 0)), int(h.get("xp", 0))]


static func _hero_level_line(h: Dictionary) -> String:
	var reached: Dictionary = h.get("level_times", {})
	var parts: Array = []
	for lvl in range(2, Hero.MAX_LEVEL + 1):
		var key := str(lvl)
		if reached.has(key):
			parts.append("L%d@%s" % [lvl, _fmt(float(reached[key]))])
	return "      tasot: %s" % (", ".join(PackedStringArray(parts)) if not parts.is_empty() else "vain L1")


static func _match_objective_timeline(lines: Array, snap: Dictionary) -> void:
	var objectives: Array = snap.get("objective_events", [])
	var towers: Array = snap.get("tower_events", [])
	if objectives.is_empty() and towers.is_empty():
		return
	lines.append("Strategiset ajoitukset:")
	var timeline: Array = []
	for ev in objectives:
		var copy: Dictionary = ev.duplicate()
		copy["event_type"] = "objective"
		timeline.append(copy)
	for ev in towers:
		var copy: Dictionary = ev.duplicate()
		copy["event_type"] = "tower"
		timeline.append(copy)
	timeline.sort_custom(func(a, b): return float(a.get("t", 0)) < float(b.get("t", 0)))
	for ev in timeline:
		if str(ev.get("event_type", "")) == "objective":
			lines.append("  %s  %-6s %s / %s | active %.1fs, ikkuna %.1fs | buff %.0fs" % [
				_fmt(float(ev.get("t", 0))), str(ev.get("kind", "?")),
				_team(int(ev.get("team", -1))), str(ev.get("hero", "?")),
				float(ev.get("active", ev.get("clear", 0))), float(ev.get("clear", 0)),
				float(ev.get("duration", 0))])
			continue
		var flags := ""
		if bool(ev.get("baron", false)):
			flags += " BARON"
		if bool(ev.get("dragon", false)):
			flags += " DRAGON"
		lines.append("  %s  TORNI %s T%d | %s menetti | viimeisteli %s%s" % [
			_fmt(float(ev.get("t", 0))), str(ev.get("lane", "?")), int(ev.get("tier", 0)),
			_team(int(ev.get("lost_team", -1))), str(ev.get("hero", "?")), flags])


static func _role_rank(role: String) -> int:
	match role:
		"top": return 0
		"jungle": return 1
		"bottom": return 2
		"support": return 3
	return 4


static func _accumulate_meta(comps: Dictionary, pairs: Dictionary,
		snap: Dictionary, winner: int) -> void:
	for team in range(2):
		var members: Array = []
		for h in snap.get("heroes", []):
			if int(h.get("team", -1)) == team:
				members.append(h)
		members.sort_custom(func(a, b):
			var ar := _role_rank(str(a.get("role", "unknown")))
			var br := _role_rank(str(b.get("role", "unknown")))
			return ar < br if ar != br else str(a.get("hero_id", "")) < str(b.get("hero_id", "")))
		var labels: Array = []
		var ids: Array = []
		for h in members:
			labels.append("%s:%s" % [str(h.get("role", "?")), str(h.get("hero_id", "?"))])
			ids.append(str(h.get("hero_id", "?")))
		_meta_add(comps, " | ".join(PackedStringArray(labels)), winner == team)
		ids.sort()
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				_meta_add(pairs, "%s + %s" % [str(ids[i]), str(ids[j])], winner == team)


static func _meta_add(table: Dictionary, name: String, won: bool) -> void:
	if name == "":
		return
	if not table.has(name):
		table[name] = {"name": name, "games": 0, "wins": 0}
	table[name]["games"] += 1
	if won:
		table[name]["wins"] += 1


static func _meta_tables(lines: Array, comps: Dictionary, pairs: Dictionary) -> void:
	lines.append("=== META: TARKAT JOUKKUEET JA HERO-COMBOT ===")
	lines.append("  Voitto% ilman ottelumäärää on harhaanjohtava; alle 3 peliä = alustava havainto.")
	lines.append("  Tarkka 4 heron kokoonpano (roolijärjestys):")
	lines.append("  pelit | voitot | voitto% | kokoonpano")
	var rows: Array = comps.values()
	rows.sort_custom(func(a, b):
		var aw := float(a["wins"]) / maxf(float(a["games"]), 1.0)
		var bw := float(b["wins"]) / maxf(float(b["games"]), 1.0)
		return aw > bw if not is_equal_approx(aw, bw) else int(a["games"]) > int(b["games"]))
	for i in range(mini(rows.size(), 20)):
		var a: Dictionary = rows[i]
		var note := " *" if int(a["games"]) < 3 else ""
		lines.append("  %5d | %6d | %6.1f%% | %s%s" % [int(a["games"]), int(a["wins"]),
			100.0 * float(a["wins"]) / maxf(float(a["games"]), 1.0), str(a["name"]), note])
	lines.append("  Parhaat sankariparit (saman joukkueen pelit):")
	lines.append("  pelit | voitot | voitto% | pari")
	rows = pairs.values()
	rows.sort_custom(func(a, b):
		var aw := float(a["wins"]) / maxf(float(a["games"]), 1.0)
		var bw := float(b["wins"]) / maxf(float(b["games"]), 1.0)
		return aw > bw if not is_equal_approx(aw, bw) else int(a["games"]) > int(b["games"]))
	for i in range(mini(rows.size(), 15)):
		var a: Dictionary = rows[i]
		var note := " *" if int(a["games"]) < 3 else ""
		lines.append("  %5d | %6d | %6.1f%% | %s%s" % [int(a["games"]), int(a["wins"]),
			100.0 * float(a["wins"]) / maxf(float(a["games"]), 1.0), str(a["name"]), note])
	lines.append("")


static func _accumulate_role(roles: Dictionary, h: Dictionary, elapsed: float) -> void:
	var role := str(h.get("progression_role", h.get("role", "unknown")))
	if role == "":
		role = "unknown"
	if not roles.has(role):
		roles[role] = {"role": role, "games": 0, "time": 0.0, "gold": 0.0, "xp": 0.0,
			"lane_xp": 0.0, "jungle_gold": 0.0, "jungle_xp": 0.0,
			"level_sum": 0.0, "level_time_sum": {}, "level_reached": {},
			"g500_sum": 0.0, "g500_n": 0, "x500_sum": 0.0, "x500_n": 0,
			"x1000_sum": 0.0, "x1000_n": 0}
	var a: Dictionary = roles[role]
	a["games"] += 1
	a["time"] += elapsed
	a["level_sum"] += float(h.get("level", 1))
	for key in ["gold", "xp", "lane_xp", "jungle_gold", "jungle_xp"]:
		a[key] += float(h.get(key, 0))
	var level_times: Dictionary = h.get("level_times", {})
	for lvl in range(2, Hero.MAX_LEVEL + 1):
		var key := str(lvl)
		if not level_times.has(key):
			continue
		if not a["level_time_sum"].has(key):
			a["level_time_sum"][key] = 0.0
			a["level_reached"][key] = 0
		a["level_time_sum"][key] += float(level_times[key])
		a["level_reached"][key] += 1
	var gm: Dictionary = h.get("gold_milestones", {})
	var xm: Dictionary = h.get("xp_milestones", {})
	if gm.has("500"):
		a["g500_sum"] += float(gm["500"])
		a["g500_n"] += 1
	if xm.has("500"):
		a["x500_sum"] += float(xm["500"])
		a["x500_n"] += 1
	if xm.has("1000"):
		a["x1000_sum"] += float(xm["1000"])
		a["x1000_n"] += 1


static func _milestone_text(sum: float, reached: int, games: int) -> String:
	if reached <= 0:
		return "-"
	return "%s %d/%d" % [_fmt(sum / float(reached)), reached, games]


static func _role_progression_table(lines: Array, roles: Dictionary) -> void:
	lines.append("=== ROOLIEN KULTA, XP JA ETENEMISNOPEUS ===")
	lines.append("  rooli   | pel | G/min | XP/min | laneXP | jungleG | jungleXP | 500G (saavutti) | 500XP | 1000XP")
	var rows: Array = roles.values()
	rows.sort_custom(func(a, b): return _role_rank(str(a["role"])) < _role_rank(str(b["role"])))
	for a in rows:
		var minutes: float = maxf(float(a["time"]) / 60.0, 0.1)
		var g: int = maxi(int(a["games"]), 1)
		lines.append("  %-7s | %3d | %5d | %6d | %6d | %7d | %8d | %-14s | %-10s | %s" % [
			str(a["role"]), g, int(float(a["gold"]) / minutes), int(float(a["xp"]) / minutes),
			int(float(a["lane_xp"]) / g), int(float(a["jungle_gold"]) / g),
			int(float(a["jungle_xp"]) / g),
			_milestone_text(float(a["g500_sum"]), int(a["g500_n"]), g),
			_milestone_text(float(a["x500_sum"]), int(a["x500_n"]), g),
			_milestone_text(float(a["x1000_sum"]), int(a["x1000_n"]), g)])
	lines.append("")


static func _level_progression_table(lines: Array, roles: Dictionary) -> void:
	lines.append("=== LEVEL 1–12: ROOLIKOHTAISET SAAVUTUSAJAT ===")
	lines.append("  Aika on saavutettujen keskiarvo; sulkeissa saavutti/pelit. Tavoite: top hieman ennen junglea, bottom myöhemmin, support viimeisenä.")
	var rows: Array = roles.values()
	rows.sort_custom(func(a, b): return _role_rank(str(a["role"])) < _role_rank(str(b["role"])))
	for a in rows:
		var games := maxi(int(a["games"]), 1)
		lines.append("  %-7s | päätös-LV %.1f | %s" % [str(a["role"]),
			float(a["level_sum"]) / float(games), _level_band_text(a, 2, 6, games)])
		lines.append("            %s" % _level_band_text(a, 7, Hero.MAX_LEVEL, games))
	lines.append("")


static func _level_band_text(a: Dictionary, first: int, last: int, games: int) -> String:
	var parts: Array = []
	for lvl in range(first, last + 1):
		var key := str(lvl)
		var reached := int(a["level_reached"].get(key, 0))
		var time_text := "-"
		if reached > 0:
			time_text = _fmt(float(a["level_time_sum"].get(key, 0.0)) / float(reached))
		parts.append("L%d %s (%d/%d)" % [lvl, time_text, reached, games])
	return " | ".join(PackedStringArray(parts))


static func _map_time_table(lines: Array, agg: Dictionary) -> void:
	lines.append("=== AI:N ALUEAIKA (per peli; elossa mitattu) ===")
	lines.append("  sankari  | top    | bottom | jungle | base   | painotus")
	var rows: Array = agg.values()
	rows.sort_custom(func(a, b): return float(a.get("time_jungle", 0)) > float(b.get("time_jungle", 0)))
	for a in rows:
		var g := maxf(float(a["games"]), 1.0)
		var top := float(a.get("time_top", 0)) / g
		var bottom := float(a.get("time_bottom", 0)) / g
		var jungle := float(a.get("time_jungle", 0)) / g
		var base := float(a.get("time_base", 0)) / g
		var total := maxf(top + bottom + jungle + base, 0.1)
		var focus := "top" if top >= bottom and top >= jungle else ("bottom" if bottom >= jungle else "jungle")
		lines.append("  %-8s | %6s | %6s | %6s | %6s | %s %.0f%%" % [str(a["hero_id"]),
			_fmt(top), _fmt(bottom), _fmt(jungle), _fmt(base), focus,
			100.0 * maxf(top, maxf(bottom, jungle)) / total])
	lines.append("")


static func _jungle_clear_table(lines: Array, agg: Dictionary) -> void:
	lines.append("=== JUNGLE CLEAR ===")
	lines.append("  active = osumien välinen taistelu; ikkuna = ensimmäinen osuma -> kaato (paljastaa keskeytykset).")
	lines.append("  sankari  | clear/peli | active ka | ikkuna ka | jungleG | jungleXP | leirityypit (määrä@active/ikkuna)")
	var rows: Array = agg.values().filter(func(a): return float(a.get("jungle_clears", 0)) > 0.0)
	rows.sort_custom(func(a, b): return float(a.get("jungle_clears", 0)) > float(b.get("jungle_clears", 0)))
	for a in rows:
		var clears := maxf(float(a.get("jungle_clears", 0)), 1.0)
		var kinds: Array = []
		for kind in a.get("jungle_clear_kinds", {}):
			var rec: Dictionary = a["jungle_clear_kinds"][kind]
			kinds.append("%s %d@%.1f/%.1fs" % [str(kind), int(rec.get("count", 0)),
				float(rec.get("active", 0)) / maxf(float(rec.get("count", 0)), 1.0),
				float(rec.get("time", 0)) / maxf(float(rec.get("count", 0)), 1.0)])
		lines.append("  %-8s | %10.2f | %9.1fs | %9.1fs | %7d | %8d | %s" % [str(a["hero_id"]),
			clears / maxf(float(a["games"]), 1.0),
			float(a.get("jungle_active_clear_time", 0)) / clears,
			float(a.get("jungle_clear_time", 0)) / clears,
			int(float(a.get("jungle_gold", 0)) / maxf(float(a["games"]), 1.0)),
			int(float(a.get("jungle_xp", 0)) / maxf(float(a["games"]), 1.0)),
			", ".join(PackedStringArray(kinds))])
	if rows.is_empty():
		lines.append("  Ei kirjattuja jungle-cleareja.")
	lines.append("")


static func _tower_timing_table(lines: Array, snapshots: Array) -> void:
	lines.append("=== TORNIEN KAATOAJAT ===")
	lines.append("  torni     | kaatui/mahd | keskiaika | aikaisin | myöhäisin | Baron | Dragon")
	var table: Dictionary = {}
	for snap in snapshots:
		for ev in snap.get("tower_events", []):
			var key := "%s T%d" % [str(ev.get("lane", "?")), int(ev.get("tier", 0))]
			if not table.has(key):
				table[key] = {"name": key, "count": 0, "time": 0.0, "min": 1.0e20,
					"max": 0.0, "baron": 0, "dragon": 0}
			var a: Dictionary = table[key]
			var t := float(ev.get("t", 0))
			a["count"] += 1
			a["time"] += t
			a["min"] = minf(float(a["min"]), t)
			a["max"] = maxf(float(a["max"]), t)
			if bool(ev.get("baron", false)): a["baron"] += 1
			if bool(ev.get("dragon", false)): a["dragon"] += 1
	var rows: Array = table.values()
	rows.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	var possible := snapshots.size() * 2
	for a in rows:
		lines.append("  %-9s | %5d/%-4d | %9s | %7s | %8s | %5d | %6d" % [str(a["name"]),
			int(a["count"]), possible, _fmt(float(a["time"]) / maxf(float(a["count"]), 1.0)),
			_fmt(float(a["min"])), _fmt(float(a["max"])), int(a["baron"]), int(a["dragon"])])
	if rows.is_empty():
		lines.append("  Yhtään tornia ei kaatunut.")
	lines.append("")


static func _buff_impact_tables(lines: Array, agg: Dictionary, snapshots: Array) -> void:
	lines.append("=== RED / BLUE -BUFFIEN VAIKUTUS ===")
	lines.append("  sankari  buff | otot | uptime/peli | suora bonus | heal | vahinko buffissa | torni buffissa")
	var rows: Array = agg.values()
	rows.sort_custom(func(a, b): return float(a.get("red_pickups", 0)) + float(a.get("blue_pickups", 0)) \
		> float(b.get("red_pickups", 0)) + float(b.get("blue_pickups", 0)))
	var any_small := false
	for a in rows:
		for kind in ["red", "blue"]:
			var pickups := float(a.get("%s_pickups" % kind, 0))
			if pickups <= 0.0:
				continue
			any_small = true
			var direct := float(a.get("%s_bonus_damage" % kind, 0))
			var heal := float(a.get("red_healing", 0)) if kind == "red" else 0.0
			lines.append("  %-8s %-4s | %4d | %11s | %11d | %4d | %15d | %14d" % [
				str(a["hero_id"]), kind, int(pickups),
				_fmt(float(a.get("%s_buff_time" % kind, 0)) / maxf(float(a["games"]), 1.0)),
				int(direct), int(heal), int(float(a.get("damage_during_%s" % kind, 0))),
				int(float(a.get("structure_during_%s" % kind, 0)))])
	if not any_small:
		lines.append("  Ei Red/Blue-buffeja otannassa.")
	lines.append("  Suora bonus = Redin/Blue'n oikeasti lisäämä vahinko ennen kohteen muita vaimennuksia.")
	lines.append("")
	lines.append("=== DRAGON / BARON POWER SPIKE ===")
	lines.append("  buff   | kaadot | hero-buffit | uptime | vahinko | torni-vah | KO | kulta | XP | tornit")
	for kind in ["dragon", "baron"]:
		var objectives := 0
		var towers := 0
		for snap in snapshots:
			for ev in snap.get("objective_events", []):
				if str(ev.get("kind", "")) == kind: objectives += 1
			for ev in snap.get("tower_events", []):
				if bool(ev.get(kind, false)): towers += 1
		var sessions := 0.0
		var uptime := 0.0
		var damage := 0.0
		var structure := 0.0
		var kos := 0.0
		var gold := 0.0
		var xp := 0.0
		for a in rows:
			sessions += float(a.get("%s_buffs" % kind, 0))
			uptime += float(a.get("%s_buff_time" % kind, 0))
			damage += float(a.get("damage_during_%s" % kind, 0))
			structure += float(a.get("structure_during_%s" % kind, 0))
			kos += float(a.get("kos_during_%s" % kind, 0))
			gold += float(a.get("gold_during_%s" % kind, 0))
			xp += float(a.get("xp_during_%s" % kind, 0))
		lines.append("  %-6s | %6d | %11d | %6s | %7d | %9d | %2d | %5d | %4d | %6d" % [
			kind, objectives, int(sessions), _fmt(uptime), int(damage), int(structure),
			int(kos), int(gold), int(xp), towers])
	lines.append("  Tornit lasketaan vain, jos buffi oli joukkueella aktiivinen juuri tornin kaatuessa.")
	lines.append("")


static func _hero_table(lines: Array, agg: Dictionary, avg_min: float) -> void:
	lines.append("Sankariteho (järjestetty vahinko/min):")
	lines.append("  sankari  | pel | LV  | K / D / A   |vah/min|torni |viidak|paran |vaim. | CS  |voit%")
	var rows: Array = agg.values()
	for a in rows:
		var hero_min: float = float(a.get("time", 0.0)) / 60.0
		if hero_min <= 0.0:
			hero_min = maxf(float(a["games"]), 1.0) * avg_min
		a["dpm"] = float(a["damage"]) / maxf(hero_min, 0.1)
	rows.sort_custom(func(x, y): return float(x["dpm"]) > float(y["dpm"]))
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-8s | %2d  |%4.1f | %4.1f/%4.1f/%4.1f | %5d |%5d |%5d |%5d |%5d |%4.1f |%3d%%" % [
			str(a["hero_id"]), int(a["games"]), float(a.get("level_sum", 0.0)) / g,
			float(a["kos"]) / g, float(a["deaths"]) / g, float(a["assists"]) / g,
			int(float(a["dpm"])), int(float(a["structure_damage"]) / g),
			int(float(a["jungle_damage"]) / g), int(float(a["healing"]) / g),
			int(float(a["mitigated"]) / g), float(a["minion_kills"]) / g,
			int(round(100.0 * float(a["wins"]) / g))])


static func _economy_table(lines: Array, agg: Dictionary) -> void:
	lines.append("")
	lines.append("=== MOBA-TALOUS (per sankari, per peli) ===")
	lines.append("  sankari  | kulta | XP   | passi | lähikul | last hit | jungle | CS")
	var rows: Array = agg.values()
	rows.sort_custom(func(x, y): return float(x.get("gold", 0)) > float(y.get("gold", 0)))
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-8s | %5d | %4d | %5d | %7d | %8d | %6d | %3.1f" % [
			str(a["hero_id"]), int(float(a.get("gold", 0)) / g),
			int(float(a.get("xp", 0)) / g), int(float(a.get("passive_gold", 0)) / g),
			int(float(a.get("proximity_gold", 0)) / g),
			int(float(a.get("last_hit_gold", 0)) / g),
			int(float(a.get("jungle_gold", 0)) / g), float(a["minion_kills"]) / g])


## Vahingon lähteet + selviytyminen: paljonko OTETTUA vahinkoa tuli sankareilta
## vs torneilta vs minioneilta vs viidakko-olennoilta, kuka tappoi ja paljonko
## CC:tä kärsittiin. Näkee ottaako AI turhia torni-/mob-osumia ja jää lukkoon.
static func _survivability_table(lines: Array, agg: Dictionary) -> void:
	lines.append("")
	lines.append("=== VAHINGON LÄHTEET JA SELVIYTYMINEN (per sankari, per peli) ===")
	lines.append("  OTETTU vahinko lähteittäin + tappajan tyyppi -> osaako AI varoa torneja/mobeja")
	lines.append("  sankari  |otettu|sankar| torni| minio| neutr|%torni|%neutr| CC s |kuolT|kuolN|kuoll_s")
	var rows: Array = agg.values()
	rows.sort_custom(func(x, y): return float(x.get("taken_tower", 0)) > float(y.get("taken_tower", 0)))
	var flags: Array = []
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		var taken: float = float(a["taken"])
		var tower: float = float(a.get("taken_tower", 0))
		var neutral: float = float(a.get("taken_neutral", 0))
		var pct_t: float = 100.0 * tower / maxf(taken, 1.0)
		var pct_n: float = 100.0 * neutral / maxf(taken, 1.0)
		lines.append("  %-8s |%5d |%5d |%5d |%5d |%5d | %3.0f%% | %3.0f%% |%5.1f |%5.2f|%5.2f|%6.1f" % [
			str(a["hero_id"]), int(taken / g), int(float(a.get("taken_hero", 0)) / g),
			int(tower / g), int(float(a.get("taken_minion", 0)) / g), int(neutral / g),
			pct_t, pct_n, float(a.get("cc_suffered", 0)) / g,
			float(a.get("deaths_tower", 0)) / g, float(a.get("deaths_neutral", 0)) / g,
			float(a.get("time_dead", 0)) / g])
		if int(a["games"]) >= 3 and taken > 1.0:
			if pct_t >= 22.0:
				flags.append("  '%s': %.0f%% vahingosta TORNEILTA — dive-turva/positiointi?" % [str(a["hero_id"]), pct_t])
			if pct_n >= 18.0:
				flags.append("  '%s': %.0f%% vahingosta VIIDAKOSTA — varoo mobeja huonosti?" % [str(a["hero_id"]), pct_n])
	if not flags.is_empty():
		lines.append("  -- huomiot (AI ottaa turhia osumia) --")
		for f in flags:
			lines.append(str(f))


## Etulinja / tankkaus: kuka imee vahinkoa tiimin puolesta. soak = otettu + estetty
## (keho JA kilvet/torjunnat), eli koko määrä jonka sankari otti pois muilta.
## soak/kuolema = kuinka paljon kestää ennen kaatumista (iso = kestävä etulinja).
## Tankin arvo EI ole vahinko/min vaan tämä: paljon soakia, vähän kuolemia,
## jolloin oma takalinja pysyy elossa. Näkee myös ketkä ottavat turhaan osumaa.
static func _tanking_table(lines: Array, agg: Dictionary) -> void:
	lines.append("")
	lines.append("=== ETULINJA / TANKKAUS (kuka imee vahinkoa tiimin puolesta) ===")
	lines.append("  soak = otettu + estetty (keho + kilvet). soak/kuol = paljonko kestää per elämä.")
	lines.append("  sankari  | soak/peli | otettu | estetty | soak/kuol | kuol/peli")
	var rows: Array = agg.values()
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		a["_soak"] = (float(a["taken"]) + float(a.get("mitigated", 0))) / g
	rows.sort_custom(func(x, y): return float(x["_soak"]) > float(y["_soak"]))
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		var taken: float = float(a["taken"])
		var mit: float = float(a.get("mitigated", 0))
		var deaths: float = float(a["deaths"])
		lines.append("  %-8s | %8d | %6d | %6d | %8d | %6.2f" % [
			str(a["hero_id"]), int((taken + mit) / g), int(taken / g), int(mit / g),
			int((taken + mit) / maxf(deaths, 1.0)), deaths / g])


## Kykykohtainen taulukko: per sankari per slot käytöt/osumat/vahinko/parannus/
## kilpi/buffi ja CC-sekunnit (stun/slow/root). "arvo/k" = yhden käytön tuoma arvo
## (vahinko-ekvivalentti) -> näkee tuottaako kyky/ultti oikeasti hyötyä per lataus.
## Roolipofiili näyttää menikö panos vahinkoon, tukeen vai kontrolliin (esim.
## kuinka paljon healer healasi vs. teki vahinkoa).
static func _ability_table(lines: Array, agg: Dictionary) -> void:
	# Arvopainot: buffi-sekunti ja CC-sekunti muunnetaan vahinko-ekvivalentiksi,
	# jotta tuki-/kontrollikykyjen arvoa voi verrata vahinkokykyihin yhtenä lukuna.
	const BUFF_W := 22.0
	const CC_W := 35.0
	lines.append("")
	lines.append("=== KYVYT JA ARVO (per sankari, koko otanta; aika = sek, arvo = vahinko-ekv.) ===")
	lines.append("  arvo/k = (vahinko+paran+kilpi+buff*%d+CC*%d) / käytöt -> yhden käytön hyöty" % [
		int(BUFF_W), int(CC_W)])
	lines.append("  sankari  slot | käyt osui | vahin| paran| kilpi| buff| stun| slow| root|töyt| arvo/k")
	var order := ["basic", "a1", "a2", "ult", "dodge"]
	var names := {"basic": "perus", "a1": "a1", "a2": "a2", "ult": "ult", "dodge": "väis"}
	var suspects: Array = []
	var profiles: Array = []
	var ult_flags: Array = []
	var ids: Array = agg.keys()
	ids.sort()
	for id in ids:
		var a: Dictionary = agg[id]
		if not a.has("agg_slots"):
			continue
		var slots: Dictionary = a["agg_slots"]
		var off_v := 0.0     # vahinkoarvo
		var sup_v := 0.0     # paran + kilpi + buffi
		var ctl_v := 0.0     # kontrolli (CC)
		var abil_vpc: Array = []
		var ult_vpc := -1.0
		var ult_casts := 0.0
		for sname in order:
			if not slots.has(sname):
				continue
			var s: Dictionary = slots[sname]
			var casts: float = float(s["casts"])
			var hits: float = float(s["hits"])
			var dmg: float = float(s["damage"])
			var heal: float = float(s["heal"])
			var stun: float = float(s["stun"])
			var slow: float = float(s["slow"])
			var root: float = float(s["root"])
			var kbn: float = float(s["kb"])
			var shield: float = float(s.get("shield", 0))
			var buff: float = float(s.get("buff", 0))
			var value: float = dmg + heal + shield + buff * BUFF_W + (stun + slow + root) * CC_W
			# Perushyökkäys ei kasvata casts-laskuria (casts=0) -> käytä osumia
			# nimittäjänä, jotta arvo/k on per-isku eikä koko summa.
			var denom: float = casts if casts > 0.0 else hits
			var vpc: float = value / maxf(denom, 1.0)
			off_v += dmg
			sup_v += heal + shield + buff * BUFF_W
			ctl_v += (stun + slow + root) * CC_W
			var used: bool = casts > 2.0 or hits > 2.0
			var effect: bool = value > 1.0 or kbn > 0.0
			var flag: String = "*" if used and not effect else " "
			if used and not effect:
				suspects.append("%s/%s" % [id, str(names.get(sname, sname))])
			if sname == "ult":
				ult_vpc = vpc
				ult_casts = casts
			elif (sname == "a1" or sname == "a2") and casts > 1.0:
				abil_vpc.append(vpc)
			lines.append("%s %-8s %-4s | %4d %4d | %5d| %5d| %5d| %4.1f| %4.1f| %4.1f| %4.1f|%3d| %6d" % [
				flag, id, str(names.get(sname, sname)),
				int(casts), int(hits), int(dmg), int(heal), int(shield),
				buff, stun, slow, root, int(kbn), int(vpc)])
		var tot_v: float = maxf(off_v + sup_v + ctl_v, 1.0)
		profiles.append("  %-8s | vahinko %3.0f%% | tuki(heal/kilpi/buff) %3.0f%% | kontrolli %3.0f%%" % [
			id, 100.0 * off_v / tot_v, 100.0 * sup_v / tot_v, 100.0 * ctl_v / tot_v])
		if ult_vpc >= 0.0 and ult_casts >= 2.0 and not abil_vpc.is_empty():
			var abil_mean := 0.0
			for v in abil_vpc:
				abil_mean += float(v)
			abil_mean /= float(abil_vpc.size())
			if abil_mean > 0.0 and ult_vpc < abil_mean:
				ult_flags.append("  '%s': ult arvo/käyttö %d < kykyjen ka %d — ult tuottaa vähän per lataus?" % [
					id, int(ult_vpc), int(abil_mean)])
	lines.append("")
	lines.append("  -- roolipofiili (mihin panos meni; vastaa: healasiko vai teki vahinkoa) --")
	for p in profiles:
		lines.append(str(p))
	if not ult_flags.is_empty():
		lines.append("")
		lines.append("  -- ultit joiden arvo/käyttö jää perus-kykyjen alle (harkitse tehostusta) --")
		for f in ult_flags:
			lines.append(str(f))
	lines.append("")
	if suspects.is_empty():
		lines.append("  Kaikki käytetyt kyvyt tuottivat mitattavaa arvoa (vahinko/CC/paran/kilpi/buff).")
	else:
		lines.append("  * = käytetty >=3 kertaa mutta EI mitattavaa arvoa (vahinko/CC/paran/kilpi/buff).")
		lines.append("      Tarkista rikki VAI tarkoituksella liikkumis-/asemointikyky: " + ", ".join(PackedStringArray(suspects)))


static func _mean_dpm(agg: Dictionary, avg_min: float) -> float:
	var total := 0.0
	var n := 0
	for id in agg:
		var a: Dictionary = agg[id]
		if int(a["games"]) < 3 or float(a["damage"]) <= 1.0:
			continue
		var hero_min: float = float(a.get("time", 0.0)) / 60.0
		if hero_min <= 0.0:
			hero_min = maxf(float(a["games"]), 1.0) * avg_min
		total += float(a["damage"]) / maxf(hero_min, 0.1)
		n += 1
	return total / maxf(n, 1)


static func _arch_add(arch: Dictionary, name: String, won: bool, elapsed: float, damage := 0.0) -> void:
	if not arch.has(name):
		arch[name] = {"name": name, "games": 0, "wins": 0, "time": 0.0, "damage": 0.0}
	var a: Dictionary = arch[name]
	a["games"] += 1
	a["time"] += elapsed
	a["damage"] += damage
	if won:
		a["wins"] += 1


static func _accumulate(agg: Dictionary, h: Dictionary, winner: int, elapsed := 0.0) -> void:
	var id: String = str(h["hero_id"])
	if not agg.has(id):
		agg[id] = {"hero_id": id, "games": 0, "time": 0.0,
			"kos": 0.0, "deaths": 0.0,
			"assists": 0.0, "damage": 0.0, "taken": 0.0, "structure_damage": 0.0,
			"jungle_damage": 0.0, "mitigated": 0.0, "minion_kills": 0.0,
			"healing": 0.0, "wins": 0,
			"taken_hero": 0.0, "taken_tower": 0.0, "taken_minion": 0.0,
			"taken_neutral": 0.0, "deaths_tower": 0.0, "deaths_neutral": 0.0,
			"cc_suffered": 0.0, "time_dead": 0.0,
			"gold": 0.0, "xp": 0.0, "passive_gold": 0.0,
			"proximity_gold": 0.0, "last_hit_gold": 0.0, "jungle_gold": 0.0,
			"level_sum": 0.0}
	var a: Dictionary = agg[id]
	a["games"] += 1
	a["time"] += float(elapsed)
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
	a["gold"] += float(h.get("gold", 0))
	a["xp"] += float(h.get("xp", 0))
	a["level_sum"] += float(h.get("level", 1))
	a["passive_gold"] += float(h.get("passive_gold", 0))
	a["proximity_gold"] += float(h.get("proximity_gold", 0))
	a["last_hit_gold"] += float(h.get("last_hit_gold", 0))
	a["jungle_gold"] += float(h.get("jungle_gold", 0))
	for key in [
		"lane_xp", "jungle_xp", "tower_gold", "tower_xp",
		"time_top", "time_bottom", "time_jungle", "time_base",
		"jungle_clears", "jungle_clear_time", "jungle_active_clear_time",
		"red_pickups", "blue_pickups", "baron_buffs", "dragon_buffs",
		"red_buff_time", "blue_buff_time", "baron_buff_time", "dragon_buff_time",
		"red_bonus_damage", "blue_bonus_damage", "red_healing",
		"damage_during_red", "damage_during_blue", "damage_during_baron", "damage_during_dragon",
		"structure_during_red", "structure_during_blue", "structure_during_baron", "structure_during_dragon",
		"kos_during_red", "kos_during_blue", "kos_during_baron", "kos_during_dragon",
		"gold_during_red", "gold_during_blue", "gold_during_baron", "gold_during_dragon",
		"xp_during_red", "xp_during_blue", "xp_during_baron", "xp_during_dragon",
	]:
		if not a.has(key):
			a[key] = 0.0
		a[key] += float(h.get(key, 0))
	if h.has("jungle_clear_kinds"):
		if not a.has("jungle_clear_kinds"):
			a["jungle_clear_kinds"] = {}
		for kind in h["jungle_clear_kinds"]:
			var src: Dictionary = h["jungle_clear_kinds"][kind]
			if not a["jungle_clear_kinds"].has(kind):
				a["jungle_clear_kinds"][kind] = {"count": 0, "time": 0.0, "active": 0.0}
			var dst_kind: Dictionary = a["jungle_clear_kinds"][kind]
			dst_kind["count"] += int(src.get("count", 0))
			dst_kind["time"] += float(src.get("time", 0))
			dst_kind["active"] += float(src.get("active", 0))
	# Otetun vahingon lähteet + selviytyminen (.get -> vanhat snapshotit kelpaavat).
	a["taken_hero"] += float(h.get("taken_hero", 0))
	a["taken_tower"] += float(h.get("taken_tower", 0))
	a["taken_minion"] += float(h.get("taken_minion", 0))
	a["taken_neutral"] += float(h.get("taken_neutral", 0))
	a["deaths_tower"] += float(h.get("deaths_tower", 0))
	a["deaths_neutral"] += float(h.get("deaths_neutral", 0))
	a["cc_suffered"] += float(h.get("cc_suffered", 0))
	a["time_dead"] += float(h.get("time_dead", 0))
	# Kykytelemetria per slot (basic/a1/a2/ult/dodge).
	if h.has("slots"):
		if not a.has("agg_slots"):
			a["agg_slots"] = {}
		var asl: Dictionary = a["agg_slots"]
		for sname in h["slots"]:
			var sr: Dictionary = h["slots"][sname]
			if not asl.has(sname):
				asl[sname] = {"casts": 0.0, "hits": 0.0, "damage": 0.0,
					"heal": 0.0, "stun": 0.0, "slow": 0.0, "root": 0.0, "kb": 0.0,
					"shield": 0.0, "buff": 0.0}
			var dst: Dictionary = asl[sname]
			for key in ["casts", "hits", "damage", "heal", "stun", "slow", "root", "kb",
					"shield", "buff"]:
				dst[key] += float(sr.get(key, 0))
	if int(h["team"]) == winner:
		a["wins"] += 1


static func _team(t: int) -> String:
	if t < 0:
		return "Tasapeli"
	return "Sininen" if t == 0 else "Oranssi"


static func _fmt(sec: float) -> String:
	var s: int = int(sec)
	return "%d:%02d" % [s / 60, s % 60]
