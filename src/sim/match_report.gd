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
	_survivability_table(lines, agg)
	_ability_table(lines, agg)
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
	_hero_table(lines, agg, avg_min)
	_survivability_table(lines, agg)
	_ability_table(lines, agg)
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
		total += (float(a["damage"]) / maxf(float(a["games"]), 1.0)) / maxf(avg_min, 0.1)
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


static func _accumulate(agg: Dictionary, h: Dictionary, winner: int) -> void:
	var id: String = str(h["hero_id"])
	if not agg.has(id):
		agg[id] = {"hero_id": id, "games": 0, "kos": 0.0, "deaths": 0.0,
			"assists": 0.0, "damage": 0.0, "taken": 0.0, "structure_damage": 0.0,
			"jungle_damage": 0.0, "mitigated": 0.0, "minion_kills": 0.0,
			"healing": 0.0, "wins": 0,
			"taken_hero": 0.0, "taken_tower": 0.0, "taken_minion": 0.0,
			"taken_neutral": 0.0, "deaths_tower": 0.0, "deaths_neutral": 0.0,
			"cc_suffered": 0.0, "time_dead": 0.0}
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
