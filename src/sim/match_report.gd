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

# Ladder-testin hyväksymisrajat. TASOPARIT (tier vs tier, divisioona III) ovat
# eri kysymys kuin DIVISIOONAPARIT (saman tason IV vs I):
#   tasopari      — alemman tason KUULUU hävitä selvästi (tasoportit avaavat
#                   ylemmälle kykyjä joita alemmalla ei ole lainkaan)
#   divisioonapari — kolmen portaan ero saman tason sisällä: ylemmän kuuluu
#                   johtaa selvästi muttei murskata (portit ovat samat, ero
#                   syntyy vain mistake_chancesta ja jatkuvista käyristä)
const LADDER_OK_WINRATE := 0.8
const LADDER_CLEAR_WINRATE := 0.9      # tasopari tästä ylöspäin = "SELKEÄ"
const LADDER_DIVISION_WINRATE := 0.65  # divisioonaparin hyväksymisraja

# Tasoporttien taulukko raporttiin (sama kuin BotBrain._apply_tier_gates).
# Selittää MIKSI rankit eroavat — pelkät voitto-%:t eivät kerro sitä.
const TIER_CAPABILITIES := [
	"ei väistöä, ei kitetystä, ei suojautumista, ei keskitettyä tulta, ei komboja; farmi 30 %, ei perääntymistä, ei kauppareissuja, ei objektiiveja, ei makroa",
	"AVAA: last hit + perääntyminen + kauppareissut (70 s). Väistö 25 %, ei kitetystä/suojaa, keskitetty tuli 30 %, ei Dragonia/Baronia",
	"AVAA: väistö + Dragon. Kitetys 35 %, suoja 30 %, keskitetty tuli 60 %, ei Baronia",
	"AVAA: kitetys + suojautuminen + Baron + linjarotaatiot. Suoja 70 %",
	"AVAA: täysi keskitetty tuli ja kombot — ei enää leikkauksia, vain käyrät",
	"vain käyrät: tarkempi tähtäys, nopeammat päätökset, vähemmän keskittymiskatkoja",
	"vain käyrät + avoin huijausramppi alkaa (vahinko/kesto/jäähdytykset/vauhti)",
	"käyrien katto: lähes virheetön tähtäys, ei keskittymiskatkoja, täysi huijausramppi",
]

# --- Balanssiraportin hälytysrajat (itemit, sankarit, järjestelmä) ----------
# Kaikki liputukset kulkevat _flag()-apurin kautta, joka kerää ne myös raportin
# ylimpään YHTEENVETO-laatikkoon. Rajat ovat tietoisen väljiä: raportti nostaa
# esiin TARKISTUSKOHTEITA, ei julista itemiä tai sankaria rikkinäiseksi.
const ITEM_MIN_N := 8              # pienin otanta jolla itemi ylipäätään liputetaan
const ITEM_STRONG_WR := 62.0       # haltijan voitto% >= -> "vahva?"
const ITEM_WEAK_WR := 38.0         # haltijan voitto% <= -> "heikko?"
const ITEM_EFF_LOW := 0.60         # kultatehokkuus alle 60 % vertailupohjasta -> TEHOTON
const ITEM_EFF_HIGH := 1.50        # kultatehokkuus yli 150 % vertailupohjasta -> YLIVOIMAINEN
const ITEM_ROLE_MIN_N := 12        # pienin roolin otanta jolla rooli kelpaa vertailupohjaksi
const FIRST_EPIC_DOMINANT := 35.0  # yhden ensiepicin osuus %-yksikköinä -> avaus dominoi
const EARLY_EPIC_T := 600.0        # "aikainen" ensiepic: valmis ennen 10:00
const WALLET_HOARD := 1000.0       # roolin käyttämätön kulta ottelun lopussa -> hamstraus
const ARTIFACT_WASTE := 30.0       # % otteluista joissa pudonnut artefakti jäi käyttämättä
const HERO_MIN_N := 8              # pienin otanta sankarin voitto%-liputukseen
const HERO_WR_LOW := 42.0          # sankarin voitto% alle tämän -> TARKISTA
const HERO_WR_HIGH := 58.0         # sankarin voitto% yli tämän -> TARKISTA
const ROLE_WR_DEV := 8.0           # roolin voitto%:n sallittu poikkeama 50:stä (%-yks)
const PHASE_RATIO := 2.0           # loppu/alku-vahinkosuhde jolla hahmo luokitellaan
const PHASE_MIN_GAMES := 3         # voimakäyrän pienin otanta
const TIMECAP_SHARE := 40.0        # % otteluista aikakattoon -> liputus
const SNOWBALL_MIN_N := 4          # lumipallokauhan pienin otanta liputukseen
const SNOWBALL_HIGH := 90.0        # iso johto voittaa yli tämän -> lumipallo liian vahva
const SNOWBALL_LOW := 55.0         # iso johto voittaa alle tämän -> johdolla ei ole väliä
const BARON_SKIP_SHARE := 30.0     # % otteluista joissa Baronia ei kaadettu lainkaan
const BUILD_DOMINANT := 80.0       # yhden lopullisen buildin osuus %-yksikköinä

# --- Sweepin ristiintaulukot: "mikä on itemin rooli tässä kaikessa" ---------
# Nämä vastaavat kysymyksiin joita pelkät itemi- ja sankaritaulukot eivät
# vastaa: mitä KUKIN ROOLI rakentaa, mitä KOVIMMAT/KEVEIMMÄT sankarit avaavat
# ja muuttuuko AIKAINEN itemi oikeasti loppupelin voimaksi.
const CROSS_TOP_ITEMS := 3         # montako epiciä listataan per rooli
const CROSS_HERO_N := 6            # montako sankaria kummastakin vahinkopäästä
const CROSS_EARLY_T := 480.0       # ensiepic ennen 8:00 = "aikainen avaus"
const CROSS_LATE_DEV := 3.0        # loppuvaiheen osuuseron liputusraja (%-yks)

static func build(snapshots: Array, intro: Array) -> String:
	# Runko kootaan ensin omaan taulukkoonsa: YHTEENVETO-laatikko tarvitsee
	# osioiden keräämät liput ja se ladotaan raportin kärkeen vasta lopuksi.
	var lines: Array = []
	var flags: Array = []
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
	# Osiot ovat jaettuja: sama koonti ladotaan myös sweep- ja ladder-raporttiin.
	var opts: Dictionary = {"flags": flags}
	_section_items(lines, snapshots, opts)
	_section_heroes(lines, snapshots, opts)
	_section_match_health(lines, snapshots, opts)
	_section_levels(lines, snapshots, opts)
	_section_ability_ranks(lines, snapshots, opts)
	var head: Array = intro.duplicate()
	head.append("")
	_summary_box(head, snapshots, opts)
	head.append("")
	head.append_array(lines)
	return "\n".join(PackedStringArray(head))


## Laaja läpikäynti: kukin ottelu on {snap, ba, oa} (blue/orange-kokoonpanotyyppi).
## Sweep on käyttäjän varsinainen sankaritasapainoajo, joten se saa kokoonpano-
## analyysin lisäksi TÄYDEN balanssikoosteen: itemit, itemin rooli ristiin
## roolien/sankarien/voimakäyrän kanssa, voimakäyrä, tasot ja kykyrankit.
static func build_sweep(results: Array, intro: Array) -> String:
	# Runko kootaan omaan taulukkoonsa: YHTEENVETO-laatikko tarvitsee osioiden
	# keräämät liput ja se ladotaan raportin kärkeen vasta lopuksi.
	var lines: Array = []
	var flags: Array = []
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
	# Sankaripoikkeamat vahinko/min-keskiarvosta. HUOM: vertailu tehdään
	# SANKARIVAHINGOSTA (_combat_damage), ei kokonaisvahingosta — muuten
	# jungleri liputtuu leirifarmista (mitattu: kaira 1863 vahinkoa/min "yli 2x
	# keskiarvo", josta 44 % oli leirivahinkoa).
	var mean_dpm := _mean_dpm(agg, avg_min)
	for id in agg:
		var a: Dictionary = agg[id]
		if int(a["games"]) < 3:
			continue
		var hero_min: float = _hero_minutes(a, avg_min)
		var dpm: float = _combat_damage(a) / maxf(hero_min, 0.1)
		if float(a["damage"]) <= 1.0:
			flagged = true
			lines.append("  Sankari '%s': ~0 vahinkoa — rikki tai ei osu?" % id)
		elif mean_dpm > 0.0 and dpm > mean_dpm * 2.0:
			flagged = true
			lines.append("  Sankari '%s': sankarivahinko/min %d (yli 2x keskiarvo %d) — mahd. yli" % [
				id, int(dpm), int(mean_dpm)])
		elif mean_dpm > 0.0 and dpm < mean_dpm * 0.4:
			# Rooli-tietoinen: tuki/tankki tekee vähän vahinkoa mutta parantaa/estää,
			# joten matala vahinko ei ole "ali" jos utility (paran+vaimennus)/peli riittää.
			var role: String = str(HeroDef.get_def(id).get("role", ""))
			var util: float = (float(a["healing"]) + float(a["mitigated"])) / maxf(float(a["games"]), 1.0)
			if not ((role == "Tuki" or role == "Tankki") and util >= 150.0):
				flagged = true
				lines.append("  Sankari '%s': sankarivahinko/min %d (alle 0.4x keskiarvo %d) — mahd. ali (%s)" % [
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
	# Balanssikooste: samat osiot kuin vakiosimulaatiossa + sweepin omat
	# ristiintaulukot, jotka kertovat MITÄ itemi tekee roolille ja sankarille.
	var opts: Dictionary = {"flags": flags}
	_section_items(lines, results, opts)
	_section_item_cross(lines, results, opts)
	_section_power_curve(lines, results, opts)
	_section_levels(lines, results, opts)
	_section_ability_ranks(lines, results, opts)
	var head: Array = intro.duplicate()
	head.append("")
	_summary_box(head, results, opts)
	head.append("")
	head.append_array(lines)
	return "\n".join(PackedStringArray(head))


## Ladder-testin raportti. Kukin tulos on {snap, lo, hi, hi_team, anchor}:
## lo/hi = parin rankit (BotRank 0..31), hi_team = kumpi joukkue pelasi ylempää
## rankia (0/1, vuorotellen -> puolibias kumoutuu), anchor = hajautusankkuri
## (iso rankiero, terveystarkistus). Tuomio: ylemmän on voitettava vähintään
## LADDER_OK_WINRATE otteluista, muuten "LADDER RIKKI kohdassa X".
static func build_ladder(results: Array, intro: Array) -> String:
	# Runko kootaan omaan taulukkoonsa: YHTEENVETO-laatikko tarvitsee osioiden
	# keräämät liput ja se ladotaan raportin kärkeen vasta lopuksi.
	var lines: Array = []
	var flags: Array = []
	var table: Dictionary = {}   # "lo-hi" -> koonti (säilyttää lisäysjärjestyksen)
	for e in results:
		var snap: Dictionary = e["snap"]
		var lo: int = int(e["lo"])
		var hi: int = int(e["hi"])
		var key := "%d-%d" % [lo, hi]
		if not table.has(key):
			table[key] = {"lo": lo, "hi": hi, "games": 0, "hi_wins": 0,
				"hi_wins_blue": 0, "hi_wins_orange": 0, "draws": 0, "time": 0.0,
				"anchor": bool(e["anchor"]),
				"division": bool(e.get("division", false)), "nexus_ends": 0,
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
	lines.append("  Rajat: tasopari %d %% (SELKEÄ %d %%), divisioonapari %d %%." % [
		int(round(LADDER_OK_WINRATE * 100.0)),
		int(round(LADDER_CLEAR_WINRATE * 100.0)),
		int(round(LADDER_DIVISION_WINRATE * 100.0))])
	lines.append("  pari                             | pelit | ylempi voitti | tasap | voitto% | keskikesto | tulos")
	var broken: Array = []
	for key in table:
		var a: Dictionary = table[key]
		var games: int = maxi(int(a["games"]), 1)
		var wr: float = float(a["hi_wins"]) / float(games)
		var limit: float = _ladder_limit(a)
		var ok: bool = wr >= limit
		var name := _ladder_pair_name(a)
		if not ok:
			broken.append("%s (%d %%, vaadittu %d %%)" % [
				name, int(round(wr * 100.0)), int(round(limit * 100.0))])
		var verdict := "VAROITUS"
		if ok:
			# "SELKEÄ" varataan tasopareille: siellä alemman KUULUU hävitä
			# murskaavasti. Divisioonaparissa riittää selvä johto.
			verdict = "OK"
			if not bool(a["division"]) and wr >= LADDER_CLEAR_WINRATE:
				verdict = "SELKEÄ"
		lines.append("  %-32s | %5d | %6d (%d+%d)  | %5d | %5.1f %% | %10s | %s" % [
			name, int(a["games"]), int(a["hi_wins"]),
			int(a["hi_wins_blue"]), int(a["hi_wins_orange"]), int(a["draws"]),
			wr * 100.0, _fmt(float(a["time"]) / float(games)), verdict])

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
		var name := _ladder_pair_name(a)
		lines.append("  %-32s | %5.1f/%4.1f/%4.1f | %5.1f/%4.1f/%4.1f | %3.0f/%3.0f  | %4.0f/%4.0f | %3.1f/%3.1f | %2.1f/%2.1f | %d/%d" % [
			name,
			float(a["hi_kills"]) / g, float(a["hi_deaths"]) / g, float(a["hi_assists"]) / g,
			float(a["lo_kills"]) / g, float(a["lo_deaths"]) / g, float(a["lo_assists"]) / g,
			float(a["hi_cs"]) / g, float(a["lo_cs"]) / g,
			float(a["hi_gold"]) / mins, float(a["lo_gold"]) / mins,
			float(a["hi_towers"]) / g, float(a["lo_towers"]) / g,
			float(a["hi_obj"]) / g, float(a["lo_obj"]) / g,
			int(a["nexus_ends"]), int(a["games"])])

	# Tasoyhteenveto: MIKSI rankit eroavat. Voitto-%:t kertovat että eroavat,
	# tämä taulukko kertoo mistä ero syntyy (tasoportit = kykylukitukset).
	lines.append("")
	lines.append("=== LADDER: TIER-YHTEENVETO (mitä kukin taso osaa) ===")
	lines.append("  Kaksi kerrosta: TASOPORTIT avaavat kykyjä tason vaihtuessa,")
	lines.append("  DIVISIOONAT eroavat keskittymiskatkoista (mistake_chance) ja käyristä.")
	for ti in range(BotRank.TIER_NAMES.size()):
		lines.append("  %-11s | %s" % [str(BotRank.TIER_NAMES[ti]),
			str(TIER_CAPABILITIES[ti])])

	# Balanssikooste: rankkierotteluun kuuluva itemi- ja tasodata ensin
	# tiereittäin, sitten koko otannan yhteiset osiot. LADDER-YHTEENVETO jää
	# viimeiseksi, koska ladder-ajon tuomio on raportin lopputulos.
	var opts: Dictionary = {"flags": flags, "pairs": table.size()}
	_section_items_by_rank(lines, results, opts)
	_section_levels_by_rank(lines, results, opts)
	_section_items(lines, results, opts)
	_section_power_curve(lines, results, opts)
	_section_levels(lines, results, opts)
	_section_ability_ranks(lines, results, opts)

	lines.append("")
	lines.append("=== LADDER-YHTEENVETO ===")
	if broken.is_empty():
		lines.append("LADDER TOIMII — jokainen pari ylitti rajansa (tasopari %d %%, divisioonapari %d %%)." % [
			int(round(LADDER_OK_WINRATE * 100.0)),
			int(round(LADDER_DIVISION_WINRATE * 100.0))])
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
		if wr2 >= _ladder_limit(a):
			continue
		var name2 := _ladder_pair_name(a)
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
	var head: Array = intro.duplicate()
	head.append("")
	_summary_box(head, results, opts)
	head.append("")
	head.append_array(lines)
	return "\n".join(PackedStringArray(head))


# --- Ladder-apurit ---

## Parin hyväksymisraja: divisioonaparilta vaaditaan vähemmän kuin tasoparilta
## (saman tason IV ja I eroavat vain käyristä, eivät kykylukituksista).
static func _ladder_limit(a: Dictionary) -> float:
	return LADDER_DIVISION_WINRATE if bool(a.get("division", false)) \
		else LADDER_OK_WINRATE


## Parin nimi raporttiin, tyyppimerkinnällä.
static func _ladder_pair_name(a: Dictionary) -> String:
	var name := "%s vs %s" % [BotRank.rank_name(int(a["lo"])),
		BotRank.rank_name(int(a["hi"]))]
	if bool(a.get("division", false)):
		name += " (divisioona)"
	elif bool(a.get("anchor", false)):
		name += " (ankkuri)"
	return name


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


## Sankarin TAISTELUVAHINKO minuutissa: kokonaisvahingosta on vähennetty
## viidakko- ja rakennusvahinko. Molemmat ovat sim_snapshotissa kokonaisvahingon
## OSAJOUKKOJA (Hero.deal_damage_to kasvattaa aina damagea ja sen LISÄKSI
## structure_/jungle_damagea kohteen mukaan), ja molemmilla on taulukossa oma
## sarakkeensa — samassa vah/min-luvussa ne olisivat kaksoislaskentaa.
## Mitattu vääränä hälytyksenä: kaira 1863 vahinkoa/min "yli 2x keskiarvo",
## kun 44 % siitä oli leirifarmia; oikea sankarivahinko ~1000/min eli samaa
## luokkaa kuin obsidian. Piiritys ja farmi ovat omia kysymyksiään, eivät
## sankaritehoa.
static func _combat_damage(a: Dictionary) -> float:
	return maxf(float(a.get("damage", 0.0)) - float(a.get("jungle_damage", 0.0))
		- float(a.get("structure_damage", 0.0)), 0.0)


## Sankarin peliminuutit koosteessa: oma kertynyt aika, tai jos sitä ei ole
## (vanha tilannekuva), pelien määrä * otannan keskikesto.
static func _hero_minutes(a: Dictionary, avg_min: float) -> float:
	var hero_min: float = float(a.get("time", 0.0)) / 60.0
	if hero_min <= 0.0:
		hero_min = maxf(float(a.get("games", 0)), 1.0) * avg_min
	return hero_min


static func _hero_table(lines: Array, agg: Dictionary, avg_min: float) -> void:
	lines.append("Sankariteho (järjestetty SANKARIVAHINKO/min):")
	lines.append("  vah/min = kokonaisvahinko - viidakko - rakennukset; ne ovat omina sarakkeinaan (torn/m, vidk/m)")
	lines.append("  sankari  | pel | LV  | K / D / A      |vah/min|torn/m|vidk/m|paran |vaim. | CS  |voit%")
	var rows: Array = agg.values()
	for a in rows:
		var hero_min: float = _hero_minutes(a, avg_min)
		a["dpm"] = _combat_damage(a) / maxf(hero_min, 0.1)
		a["str_pm"] = float(a["structure_damage"]) / maxf(hero_min, 0.1)
		a["jgl_pm"] = float(a["jungle_damage"]) / maxf(hero_min, 0.1)
	rows.sort_custom(func(x, y): return float(x["dpm"]) > float(y["dpm"]))
	for a in rows:
		var g: float = maxf(float(a["games"]), 1.0)
		lines.append("  %-8s | %2d  |%4.1f | %4.1f/%4.1f/%4.1f | %5d |%5d |%5d |%5d |%5d |%4.1f |%3d%%" % [
			str(a["hero_id"]), int(a["games"]), float(a.get("level_sum", 0.0)) / g,
			float(a["kos"]) / g, float(a["deaths"]) / g, float(a["assists"]) / g,
			int(float(a["dpm"])), int(float(a["str_pm"])),
			int(float(a["jgl_pm"])), int(float(a["healing"]) / g),
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


## Kirjaa tarkistuskohteen YHTEENVETO-laatikkoa varten ja palauttaa saman tekstin,
## jotta liputus voidaan tulostaa myös taulukon tuomio-sarakkeeseen.
##   kind: "itemi" | "sankari" | "järjestelmä"; name: rivin nimi koostetta varten.
static func _flag(flags: Array, kind: String, name: String, text: String) -> String:
	flags.append({"kind": kind, "name": name, "text": text})
	return text


## Osuus prosenttitekstinä; "-" kun otantaa ei ole (nollalla ei jaeta).
static func _pct_text(part: int, total: int) -> String:
	if total <= 0:
		return "-"
	return "%.1f %%" % (100.0 * float(part) / float(total))


## Poimii tilannekuvat mistä tahansa tulosjoukosta: vakiosimulaatio antaa
## snapshotit sellaisenaan, sweep ja ladder käärivät ne merkintöihin
## ({snap, ba, oa} / {snap, lo, hi, ...}). Näin sama osio kelpaa joka tilaan.
static func _snapshots(results: Array) -> Array:
	var out: Array = []
	for e_v in results:
		if e_v is Dictionary:
			var e: Dictionary = e_v
			if e.has("snap"):
				out.append(e["snap"])
			else:
				out.append(e)
	return out


## Osioiden yhteinen liputuslista opts-paketista. Lista luodaan jos sitä ei
## annettu, jolloin osion voi ladota myös ilman yhteenvetolaatikkoa.
static func _opt_flags(opts: Dictionary) -> Array:
	if not opts.has("flags"):
		opts["flags"] = []
	var out: Array = opts["flags"]
	return out


## Itembalanssi neljänä lohkona:
##   (a) epicit ja legendat + tiivis rare-lohko: rakennusmäärä, poimintaosuus,
##       valmistumisaika, haltijan voitto%, kultatehokkuus, vahinko-osuus
##       joukkueesta sekä vah/GPM-kertoimet.
##   (b) ensiepic: mikä epic valmistuu ensimmäisenä, dominoiko yksi avaus ja
##       kannattaako avaus ennen 10:00.
##   (c) legendat ja artefaktit: muuttuvatko Baronin artefaktipudotukset
##       legendoiksi vai jääkö koko mekaniikka saavuttamatta.
##   (d) käyttämätön kulta rooleittain: hamstraako botti lompakkoa (AI- tai
##       kauppapääsyongelma) vai valuuko kulta itemeihin.
## Kaikki kentät luetaan .get-oletuksilla, joten vanhat tilannekuvat kelpaavat.
static func _section_items(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	var flags: Array = _opt_flags(opts)
	var flag_start: int = flags.size()
	lines.append("")
	lines.append("=== ITEMIT (balanssi) ===")
	lines.append("  Haltijan voitto% = ostajan joukkue voitti (tasapelit ohitettu).")
	lines.append("  osto% = rakennettiin / ne sankariottelut joissa kulta olisi riittänyt hintaan.")
	lines.append("  kulta-teho = (vahinko + parannus + vaimennettu) / (haltijan käyttämä kulta / 1000).")
	lines.append("  TEHOTON/YLIVOIMAINEN vertaa itemiä SAMAN ROOLIVIHJEEN keskiarvoon, ei koko otantaan:")
	lines.append("  luvun osoittaja on haltijan koko tuotos ja nimittäjä haltijan koko kulta, joten se")
	lines.append("  mittaa ROOLIA jos vertailupohja on roolien sekoitus (tuen vahinko-osuus on 6.5 %).")
	lines.append("  vah-os% = haltijan osuus oman joukkueen kokonaisvahingosta.")
	lines.append("  vah/GPM = kerroin samojen ottelujen kaikkien sankarien keskiarvoon.")
	# Hinnasto kerran: poimintaosuuden nimittäjä tarvitsee itemin kokonaishinnan.
	var priced: Dictionary = {}
	for id_v in ItemDef.all_ids():
		var pid: String = str(id_v)
		var pdef: Dictionary = ItemDef.get_item(pid)
		var ptier: String = str(pdef.get("tier", ""))
		if ptier == "epic" or ptier == "legendary" or ptier == "rare":
			priced[pid] = {"cost": float(pdef.get("cost", 0)), "tier": ptier}
	var table: Dictionary = {}        # epic + legendary
	var rare_tab: Dictionary = {}     # rare (tiivis lohko)
	var common_pop: Dictionary = {}   # common-ostojen suosio
	var opp: Dictionary = {}          # id -> sankariottelut joissa oli varaa
	var first_epic: Dictionary = {}   # id -> ensiepic-koonti
	var wallet_role: Dictionary = {}  # rooli -> käyttämätön kulta
	var fe_total := 0
	var fe_time_sum := 0.0
	var fe_early_n := 0
	var fe_early_wins := 0
	var fe_late_n := 0
	var fe_late_wins := 0
	var hero_obs := 0
	var wallet_sum := 0.0
	var artifacts := 0                # pudonneet artefaktit = Baron-kaadot
	var legend_n := 0
	var legend_t_sum := 0.0
	var legend_wins := 0
	var legend_decided := 0
	var matches_with_artifact := 0
	var matches_wasted := 0
	var eff_value := 0.0              # epic+legendary: tuotettu arvo yhteensä
	var eff_spent := 0.0
	var eff_value_rare := 0.0
	var eff_spent_rare := 0.0
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var decided: bool = winner == 0 or winner == 1
		var elapsed_min: float = maxf(float(snap.get("elapsed", 0.0)) / 60.0, 0.1)
		var heroes: Array = snap.get("heroes", [])
		# Ottelun vertailupohjat: joukkueen kokonaisvahinko (osuutta varten) sekä
		# kaikkien sankarien keskivahinko ja -GPM (kertoimia varten).
		var team_dmg: Array = [0.0, 0.0]
		var avg_dmg := 0.0
		var avg_gpm := 0.0
		for hv in heroes:
			var hh: Dictionary = hv
			var hdmg: float = float(hh.get("damage", 0.0))
			avg_dmg += hdmg
			avg_gpm += float(hh.get("gold", 0.0)) / elapsed_min
			var ht: int = int(hh.get("team", -1))
			if ht == 0 or ht == 1:
				team_dmg[ht] = float(team_dmg[ht]) + hdmg
		var n_heroes: float = maxf(float(heroes.size()), 1.0)
		avg_dmg /= n_heroes
		avg_gpm /= n_heroes
		var barons := 0
		for ev_v in snap.get("objective_events", []):
			var oev: Dictionary = ev_v
			if str(oev.get("kind", "")) == "baron":
				barons += 1
		artifacts += barons
		var match_legends := 0
		for hv in heroes:
			var h: Dictionary = hv
			hero_obs += 1
			var team: int = int(h.get("team", -1))
			var won: bool = decided and team == winner
			var dmg: float = float(h.get("damage", 0.0))
			var team_total: float = 1.0
			if team == 0 or team == 1:
				team_total = maxf(float(team_dmg[team]), 1.0)
			var dmg_share: float = 100.0 * dmg / team_total
			var kda: float = (float(h.get("kos", 0)) + float(h.get("assists", 0))) \
				/ maxf(float(h.get("deaths", 0)), 1.0)
			var gold_total: float = float(h.get("gold", 0.0))
			var gpm: float = gold_total / elapsed_min
			var spent: float = float(h.get("gold_spent", 0.0))
			var value: float = dmg + float(h.get("healing", 0.0)) \
				+ float(h.get("mitigated", 0.0))
			# (d) käyttämätön kulta rooleittain: lompakko = kulta - käytetty.
			var role: String = str(h.get("progression_role", h.get("role", "unknown")))
			if role == "":
				role = "unknown"
			if not wallet_role.has(role):
				wallet_role[role] = {"sum": 0.0, "n": 0}
			var wa: Dictionary = wallet_role[role]
			var unspent: float = maxf(gold_total - spent, 0.0)
			wa["sum"] = float(wa["sum"]) + unspent
			wa["n"] = int(wa["n"]) + 1
			wallet_sum += unspent
			var built: Dictionary = {}   # tässä ottelussa valmistuneet (uniikit)
			var fe_id := ""
			var fe_t := -1.0
			for ev_v2 in h.get("item_log", []):
				var ev: Dictionary = ev_v2
				if bool(ev.get("sold", false)):
					continue
				var tier: String = str(ev.get("tier", ""))
				var id: String = str(ev.get("id", "?"))
				var t_buy: float = float(ev.get("t", 0.0))
				if tier == "common":
					common_pop[id] = int(common_pop.get(id, 0)) + 1
					continue
				if tier != "rare" and tier != "epic" and tier != "legendary":
					continue
				built[id] = true
				var dst: Dictionary = rare_tab if tier == "rare" else table
				if not dst.has(id):
					dst[id] = {"id": id, "tier": tier, "n": 0, "hm": 0, "t_sum": 0.0,
						"wins": 0, "decided": 0, "kda_sum": 0.0, "share_sum": 0.0,
						"val_sum": 0.0, "spent_sum": 0.0, "dmg_sum": 0.0,
						"dmg_base": 0.0, "gpm_sum": 0.0, "gpm_base": 0.0}
				var a: Dictionary = dst[id]
				a["n"] = int(a["n"]) + 1
				a["t_sum"] = float(a["t_sum"]) + t_buy
				if decided:
					a["decided"] = int(a["decided"]) + 1
					if won:
						a["wins"] = int(a["wins"]) + 1
				a["kda_sum"] = float(a["kda_sum"]) + kda
				a["share_sum"] = float(a["share_sum"]) + dmg_share
				a["val_sum"] = float(a["val_sum"]) + value
				a["spent_sum"] = float(a["spent_sum"]) + spent
				a["dmg_sum"] = float(a["dmg_sum"]) + dmg
				a["dmg_base"] = float(a["dmg_base"]) + avg_dmg
				a["gpm_sum"] = float(a["gpm_sum"]) + gpm
				a["gpm_base"] = float(a["gpm_base"]) + avg_gpm
				if tier == "rare":
					eff_value_rare += value
					eff_spent_rare += spent
				else:
					eff_value += value
					eff_spent += spent
				if tier == "epic" and (fe_t < 0.0 or t_buy < fe_t):
					fe_t = t_buy
					fe_id = id
				if tier == "legendary":
					match_legends += 1
					legend_n += 1
					legend_t_sum += t_buy
					if decided:
						legend_decided += 1
						if won:
							legend_wins += 1
			# Poimintaosuuden nimittäjä: oliko itemiin ylipäätään varaa. Rakennettu
			# itemi lasketaan aina mahdollisuudeksi (hinta maksettiin osissa).
			for id_v2 in priced:
				var qid: String = str(id_v2)
				var qd: Dictionary = priced[qid]
				if built.has(qid) or gold_total + 0.5 >= float(qd["cost"]):
					opp[qid] = int(opp.get(qid, 0)) + 1
			# Osoittaja: montako sankariottelua itemi oli valmiina (uniikkeina).
			for id_v3 in built:
				var bid: String = str(id_v3)
				if table.has(bid):
					var ta: Dictionary = table[bid]
					ta["hm"] = int(ta["hm"]) + 1
				elif rare_tab.has(bid):
					var ra: Dictionary = rare_tab[bid]
					ra["hm"] = int(ra["hm"]) + 1
			if fe_id != "":
				if not first_epic.has(fe_id):
					first_epic[fe_id] = {"id": fe_id, "n": 0, "t_sum": 0.0,
						"wins": 0, "decided": 0}
				var fa: Dictionary = first_epic[fe_id]
				fa["n"] = int(fa["n"]) + 1
				fa["t_sum"] = float(fa["t_sum"]) + fe_t
				fe_total += 1
				fe_time_sum += fe_t
				if decided:
					fa["decided"] = int(fa["decided"]) + 1
					if won:
						fa["wins"] = int(fa["wins"]) + 1
					if fe_t < EARLY_EPIC_T:
						fe_early_n += 1
						if won:
							fe_early_wins += 1
					else:
						fe_late_n += 1
						if won:
							fe_late_wins += 1
		if barons > 0:
			matches_with_artifact += 1
			if match_legends <= 0:
				matches_wasted += 1

	# --- (a) epicit ja legendat ---
	var mean_eff: float = 1000.0 * eff_value / maxf(eff_spent, 1.0)
	var mean_eff_rare: float = 1000.0 * eff_value_rare / maxf(eff_spent_rare, 1.0)
	var rows: Array = table.values()
	for a_v in rows:
		var a: Dictionary = a_v
		a["wr"] = 100.0 * float(a["wins"]) / maxf(float(a["decided"]), 1.0)
		a["eff"] = 1000.0 * float(a["val_sum"]) / maxf(float(a["spent_sum"]), 1.0)
	rows.sort_custom(func(x, y): return float(x["wr"]) > float(y["wr"]))
	var role_eff: Dictionary = _role_eff_means(rows, mean_eff)
	lines.append("")
	lines.append("  -- (a) epicit ja legendat (otannan kulta-tehon keskiarvo %d) --" % int(mean_eff))
	lines.append("  vertailupohjat rooleittain: " + _role_eff_text(role_eff, mean_eff))
	lines.append("  itemi                | tieri     |   n | osto% | valm. ka | voitto% | kulta-teho | vah-os% |  KDA  |  vah   |  GPM   | tuomio")
	for a_v in rows:
		var a: Dictionary = a_v
		var id: String = str(a["id"])
		var iname: String = str(ItemDef.get_item(id).get("name", id))
		var n: int = int(a["n"])
		var chances: int = maxi(int(opp.get(id, 0)), int(a["hm"]))
		var wr_text: String = "-" if int(a["decided"]) <= 0 else "%5.1f %%" % float(a["wr"])
		lines.append("  %-20s | %-9s | %3d | %4.0f%% | %8s | %-7s | %10d | %6.1f%% | %5.2f | ×%5.2f | ×%5.2f | %s" % [
			iname, str(a["tier"]), n,
			100.0 * float(a["hm"]) / maxf(float(chances), 1.0),
			_fmt(float(a["t_sum"]) / maxf(float(n), 1.0)), wr_text, int(float(a["eff"])),
			float(a["share_sum"]) / maxf(float(n), 1.0),
			float(a["kda_sum"]) / maxf(float(n), 1.0),
			float(a["dmg_sum"]) / maxf(float(a["dmg_base"]), 1.0),
			float(a["gpm_sum"]) / maxf(float(a["gpm_base"]), 1.0),
			_item_verdict(a, iname, float(role_eff.get(_item_role(id), mean_eff)), flags)])
	if rows.is_empty():
		lines.append("  Yhtään epic/legendary-itemiä ei valmistunut otannassa.")
	# Rare-lohko tiiviinä: sama tuomiologiikka, mutta oma kulta-tehon keskiarvo
	# (raret ostetaan aikaisin ja pienemmällä kokonaiskululla).
	var rare_rows: Array = rare_tab.values()
	for a_v in rare_rows:
		var a: Dictionary = a_v
		a["wr"] = 100.0 * float(a["wins"]) / maxf(float(a["decided"]), 1.0)
		a["eff"] = 1000.0 * float(a["val_sum"]) / maxf(float(a["spent_sum"]), 1.0)
	rare_rows.sort_custom(func(x, y): return int(x["n"]) > int(y["n"]))
	var role_eff_rare: Dictionary = _role_eff_means(rare_rows, mean_eff_rare)
	lines.append("")
	lines.append("  -- raret tiiviisti (oma kulta-tehon keskiarvo %d) --" % int(mean_eff_rare))
	lines.append("  itemi                |   n | osto% | valm. ka | voitto% | kulta-teho | tuomio")
	for a_v in rare_rows:
		var a: Dictionary = a_v
		var id: String = str(a["id"])
		var iname: String = str(ItemDef.get_item(id).get("name", id))
		var n: int = int(a["n"])
		var chances: int = maxi(int(opp.get(id, 0)), int(a["hm"]))
		var wr_text: String = "-" if int(a["decided"]) <= 0 else "%5.1f %%" % float(a["wr"])
		lines.append("  %-20s | %3d | %4.0f%% | %8s | %-7s | %10d | %s" % [
			iname, n, 100.0 * float(a["hm"]) / maxf(float(chances), 1.0),
			_fmt(float(a["t_sum"]) / maxf(float(n), 1.0)), wr_text, int(float(a["eff"])),
			_item_verdict(a, iname,
				float(role_eff_rare.get(_item_role(id), mean_eff_rare)), flags)])
	if rare_rows.is_empty():
		lines.append("  Ei rare-ostoja otannassa.")
	# Perusitemien suosio: mihin common-kulta oikeasti valuu.
	var minor_rows: Array = []
	for id_v4 in common_pop:
		minor_rows.append({"id": str(id_v4), "n": int(common_pop[id_v4])})
	minor_rows.sort_custom(func(x, y): return int(x["n"]) > int(y["n"]))
	var parts: Array = []
	for i in range(mini(minor_rows.size(), 5)):
		var m: Dictionary = minor_rows[i]
		parts.append("%s x%d" % [
			str(ItemDef.get_item(str(m["id"])).get("name", str(m["id"]))), int(m["n"])])
	if parts.is_empty():
		lines.append("  Suosituimmat perusitemit (common): ei ostoja.")
	else:
		lines.append("  Suosituimmat perusitemit (common, top 5): "
			+ ", ".join(PackedStringArray(parts)))

	# --- (b) ensiepic ---
	lines.append("")
	lines.append("  -- (b) ensiepic: ensimmäisenä valmistunut epic (dominoiko yksi avaus) --")
	var fe_rows: Array = first_epic.values()
	for a_v in fe_rows:
		var a: Dictionary = a_v
		a["wr"] = 100.0 * float(a["wins"]) / maxf(float(a["decided"]), 1.0)
	fe_rows.sort_custom(func(x, y): return int(x["n"]) > int(y["n"]))
	lines.append("  itemi                |   n | osuus | ka aika | voitto% | tuomio")
	for a_v in fe_rows:
		var a: Dictionary = a_v
		var id: String = str(a["id"])
		var iname: String = str(ItemDef.get_item(id).get("name", id))
		var n: int = int(a["n"])
		var share: float = 100.0 * float(n) / maxf(float(fe_total), 1.0)
		var wr_text: String = "-" if int(a["decided"]) <= 0 else "%5.1f %%" % float(a["wr"])
		var note := ""
		var fe_notes: Array = []
		if n >= ITEM_MIN_N and share >= FIRST_EPIC_DOMINANT:
			fe_notes.append(_flag(flags, "itemi", iname,
				"TARKISTA: avaus dominoi (%.0f %% ensiepiceistä)" % share))
		if int(a["decided"]) >= ITEM_MIN_N:
			if float(a["wr"]) >= ITEM_STRONG_WR:
				fe_notes.append(_flag(flags, "itemi", iname, "TARKISTA: avaus vahva?"))
			elif float(a["wr"]) <= ITEM_WEAK_WR:
				fe_notes.append(_flag(flags, "itemi", iname, "TARKISTA: avaus heikko?"))
		if not fe_notes.is_empty():
			note = " + ".join(PackedStringArray(fe_notes))
		lines.append("  %-20s | %3d | %4.0f%% | %7s | %-7s | %s" % [
			iname, n, share, _fmt(float(a["t_sum"]) / maxf(float(n), 1.0)), wr_text, note])
	if fe_rows.is_empty():
		lines.append("  Yksikään sankari ei saanut epiciä valmiiksi otannassa.")
	else:
		lines.append("  Ensiepic valmistui %d/%d sankariottelussa (%.0f %%), ka aika %s." % [
			fe_total, hero_obs, 100.0 * float(fe_total) / maxf(float(hero_obs), 1.0),
			_fmt(fe_time_sum / maxf(float(fe_total), 1.0))])
		lines.append("  Ensiepic ennen 10:00: voitto %s (n=%d) | 10:00 jälkeen: voitto %s (n=%d)" % [
			_pct_text(fe_early_wins, fe_early_n), fe_early_n,
			_pct_text(fe_late_wins, fe_late_n), fe_late_n])

	# --- (c) legendat ja artefaktit ---
	lines.append("")
	lines.append("  -- (c) legendat ja artefaktit (legenda vaatii Baronin artefaktin) --")
	var mcount: int = snapshots.size()
	lines.append("  Artefaktipudotuksia (Baron-kaadot): %d = %.2f / ottelu" % [
		artifacts, float(artifacts) / maxf(float(mcount), 1.0)])
	var leg_time: String = "-" if legend_n <= 0 else _fmt(legend_t_sum / float(legend_n))
	lines.append("  Legendoja valmistui: %d (%s pudotuksista), valmistumisaika ka %s" % [
		legend_n, _pct_text(legend_n, artifacts), leg_time])
	lines.append("  Legendan rakentaneen joukkueen voitto%%: %s (n=%d ratkennutta)" % [
		_pct_text(legend_wins, legend_decided), legend_decided])
	var waste: float = 100.0 * float(matches_wasted) / maxf(float(matches_with_artifact), 1.0)
	lines.append("  Ottelut joissa artefakti putosi mutta legendaa EI rakennettu: %d/%d (%.1f %%)" % [
		matches_wasted, matches_with_artifact, waste])
	if matches_with_artifact > 0 and waste > ARTIFACT_WASTE:
		lines.append("  " + _flag(flags, "järjestelmä", "artefakti",
			"TARKISTA: yli %d %% artefakteista jäi käyttämättä — legendamekaniikka ei ole saavutettavissa"
			% int(ARTIFACT_WASTE)))

	# --- (d) käyttämätön kulta ---
	lines.append("")
	lines.append("  -- (d) käyttämätön kulta ottelun lopussa (lompakko = kulta - käytetty) --")
	var wkeys: Array = wallet_role.keys()
	wkeys.sort_custom(func(x, y): return _role_rank(str(x)) < _role_rank(str(y)))
	var wparts: Array = []
	var hoard: Array = []
	for role_v in wkeys:
		var role: String = str(role_v)
		var wa: Dictionary = wallet_role[role]
		var avg_w: float = float(wa["sum"]) / maxf(float(wa["n"]), 1.0)
		wparts.append("%s %d" % [role, int(avg_w)])
		if int(wa["n"]) >= 4 and avg_w >= WALLET_HOARD:
			hoard.append(_flag(flags, "järjestelmä", "lompakko",
				"TARKISTA: rooli '%s' istuu %d kullan päällä — botti hamstraa tai kauppaan ei pääse"
				% [role, int(avg_w)]))
	if wparts.is_empty():
		lines.append("  Ei sankaridataa otannassa.")
	else:
		lines.append("  " + " | ".join(PackedStringArray(wparts))
			+ "   (koko otanta ka %d)" % int(wallet_sum / maxf(float(hero_obs), 1.0)))
	for hline in hoard:
		lines.append("  " + str(hline))
	lines.append("  Itemiosion tarkistuskohteita: %d (yksityiskohdat tuomio-sarakkeissa)."
		% (flags.size() - flag_start))


## Itemin roolivihje katalogista ("" -> "any"). Kulta-tehon vertailupohja
## ryhmitellään tällä.
static func _item_role(id: String) -> String:
	var role: String = str(ItemDef.get_item(id).get("role_hint", ""))
	return "any" if role == "" else role


## Kulta-tehon ROOLIKOHTAISET vertailupohjat (rooli -> painotettu keskiarvo).
##
## MITTAUSVIRHE JOKA TÄMÄ KORJAA (sama laji kuin junglerin vahinkohälytys):
## rivin kulta-teho on HALTIJAN koko tuotos (vahinko + parannus + vaimennettu)
## jaettuna HALTIJAN koko kulankäytöllä — se ei ole itemin ominaisuus vaan
## sankarin. Kun vertailupohjana oli koko otannan keskiarvo, jokainen tukitavara
## liputtui TEHOTTOMAKSI riippumatta siitä mitä se tekee: otannan osoittajasta
## yli 90 % on vahinkoa ja tuen vahinko-osuus on suunnitellusti 6.5 %.
## Mitattu esimerkki: Airutlyhty 1383, Kolikkotalismaani 1103, Vartiolyhty 1047
## vs. otannan keskiarvo 3113 -> kaikki TEHOTON, vaikka samojen itemien
## voitto% oli korjausten jälkeen 42.6 / 46.8 / 62.5.
##
## Nyt vertailu tehdään saman roolivihjeen sisällä: "TEHOTON" tarkoittaa
## huonompaa kuin oman roolin muut itemit. Roolit EIVÄT ole vertailukelpoisia
## keskenään, joten roolikeskiarvoja ei liputeta — ne tulostetaan
## vertailupohjariville, jotta koko roolin romahdus näkyisi silmällä.
## Alle ITEM_ROLE_MIN_N havainnon roolit käyttävät otannan keskiarvoa (pieni
## ryhmä vertaisi itemiä lähinnä itseensä).
static func _role_eff_means(rows: Array, overall: float) -> Dictionary:
	var acc: Dictionary = {}
	for a_v in rows:
		var a: Dictionary = a_v
		var role: String = _item_role(str(a["id"]))
		if not acc.has(role):
			acc[role] = {"val": 0.0, "spent": 0.0, "n": 0, "items": 0}
		var g: Dictionary = acc[role]
		g["val"] = float(g["val"]) + float(a["val_sum"])
		g["spent"] = float(g["spent"]) + float(a["spent_sum"])
		g["n"] = int(g["n"]) + int(a["n"])
		g["items"] = int(g["items"]) + 1
	var out: Dictionary = {}
	for role_v in acc:
		var rname: String = str(role_v)
		var grp: Dictionary = acc[rname]
		# Yhden itemin rooli vertaisi itemiä ITSEENSÄ (raja ei laukeaisi
		# koskaan), ja liian pieni otanta olisi kohinaa -> otannan keskiarvo.
		if int(grp["items"]) < 2 or int(grp["n"]) < ITEM_ROLE_MIN_N \
				or float(grp["spent"]) <= 0.0:
			out[rname] = overall
		else:
			out[rname] = 1000.0 * float(grp["val"]) / maxf(float(grp["spent"]), 1.0)
	return out


## Vertailupohjarivi: "carry 3800 · support 1150 · tank* 3113" (aakkosjärjestys,
## jotta rivi on vakaa ajosta toiseen). Tähti = roolilla ei ole omaa pohjaa
## (alle 2 itemiä tai alle ITEM_ROLE_MIN_N havaintoa) -> otannan keskiarvo.
static func _role_eff_text(role_eff: Dictionary, overall: float) -> String:
	var names: Array = role_eff.keys()
	names.sort()
	var parts: Array = []
	for rname_v in names:
		var rname: String = str(rname_v)
		var value: float = float(role_eff[rname])
		var mark := "*" if is_equal_approx(value, overall) else ""
		parts.append("%s%s %d" % [rname, mark, int(value)])
	if parts.is_empty():
		return "-"
	return " · ".join(PackedStringArray(parts)) \
		+ "   (* = ei omaa pohjaa, käytetään otannan keskiarvoa)"


## Yhden itemirivin tuomio + liputus. Otanta n on rakennuskerrat; voitto%:n
## liputus vaatii lisäksi ratkenneita otteluita, jotta pelkät tasapelit eivät
## näytä itemiä heikolta.
static func _item_verdict(a: Dictionary, iname: String, mean_eff: float, flags: Array) -> String:
	if int(a["n"]) < ITEM_MIN_N:
		return "otanta pieni"
	var parts: Array = []
	if int(a["decided"]) >= ITEM_MIN_N:
		var wr: float = float(a["wr"])
		if wr >= ITEM_STRONG_WR:
			parts.append(_flag(flags, "itemi", iname, "TARKISTA: vahva?"))
		elif wr <= ITEM_WEAK_WR:
			parts.append(_flag(flags, "itemi", iname, "TARKISTA: heikko?"))
	if mean_eff > 0.0:
		var eff: float = float(a["eff"])
		if eff < mean_eff * ITEM_EFF_LOW:
			parts.append(_flag(flags, "itemi", iname,
				"TEHOTON: kultatehokkuus alle 60 % vertailupohjasta"))
		elif eff > mean_eff * ITEM_EFF_HIGH:
			parts.append(_flag(flags, "itemi", iname,
				"YLIVOIMAINEN: kultatehokkuus yli 150 % vertailupohjasta"))
	if parts.is_empty():
		return ""
	return " + ".join(PackedStringArray(parts))


## Ajoitusryhmän tyhjä koonti (aikainen / myöhäinen ensiepic).
static func _cross_group(name: String) -> Dictionary:
	return {"name": name, "n": 0, "wins": 0, "decided": 0, "t_sum": 0.0,
		"early_sum": 0.0, "early_n": 0, "late_sum": 0.0, "late_n": 0}


## Lajittelu: suurin rakennusmäärä ensin, tasatilanne aakkosjärjestyksellä
## (vakaa järjestys — sort_custom ei ole vakaa, joten sija ratkaistaan aina).
static func _cross_before(x: Dictionary, y: Dictionary) -> bool:
	if int(x["n"]) != int(y["n"]):
		return int(x["n"]) > int(y["n"])
	return str(x["id"]) < str(y["id"])


## Lajittelu vahinko/peli laskevasti, tasatilanne aakkosjärjestyksellä.
static func _cross_before_dpg(x: Dictionary, y: Dictionary) -> bool:
	if absf(float(x["dpg"]) - float(y["dpg"])) > 0.0:
		return float(x["dpg"]) > float(y["dpg"])
	return str(x["id"]) < str(y["id"])


## Sweepin ristiintaulukot — vastaus kysymykseen "mikä on itemin rooli tässä
## kaikessa". Kolme näkökulmaa joita itemi- ja sankaritaulukot eivät anna:
##   (a) itemi × rooli: mitä kukin rooli oikeasti rakentaa ja voittaako sillä
##   (b) itemi × sankari: mitä kovimmat ja keveimmät vahingontekijät avaavat
##   (c) voimakäyrä × ensiepicin ajoitus: muuttuuko aikainen itemi loppupelin
##       voimaksi (vahinko-osuus 14-20 min) vai valuuko etu hukkaan
## Kaikki kentät .get-oletuksilla: vanhat tilannekuvat tulostavat "ei dataa".
static func _section_item_cross(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	lines.append("")
	lines.append(str(opts.get("cross_title", "=== ITEMIN ROOLI (ristiintaulukot) ===")))
	lines.append("  Vastaa kysymykseen: mitä itemi tekee roolille, sankarille ja voimakäyrälle.")
	var role_item: Dictionary = {}   # rooli -> itemi -> {n, wins, decided}
	var hero_item: Dictionary = {}   # sankari -> {games, damage, fe}
	var early_grp: Dictionary = _cross_group("ennen %s" % _fmt(CROSS_EARLY_T))
	var late_grp: Dictionary = _cross_group("%s jälkeen" % _fmt(CROSS_EARLY_T))
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var decided: bool = winner == 0 or winner == 1
		var heroes: Array = snap.get("heroes", [])
		# Vaihekohtaiset joukkuesummat: (c) tarvitsee osuuden OMASTA joukkueesta.
		var t_ph: Array = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for hv in heroes:
			var hh: Dictionary = hv
			var ht: int = int(hh.get("team", -1))
			if ht != 0 and ht != 1:
				continue
			var ph: Array = hh.get("damage_phase", [])
			var acc: Array = t_ph[ht]
			for i in range(mini(ph.size(), 3)):
				acc[i] = float(acc[i]) + float(ph[i])
		for hv in heroes:
			var h: Dictionary = hv
			var id: String = str(h.get("hero_id", "?"))
			var team: int = int(h.get("team", -1))
			var won: bool = decided and team == winner
			var role: String = str(h.get("progression_role", h.get("role", "unknown")))
			if role == "":
				role = "unknown"
			if not hero_item.has(id):
				hero_item[id] = {"id": id, "games": 0, "damage": 0.0, "fe": {}}
			var ha: Dictionary = hero_item[id]
			ha["games"] = int(ha["games"]) + 1
			ha["damage"] = float(ha["damage"]) + float(h.get("damage", 0.0))
			# Ottelun uniikit epicit + ensimmäisenä valmistunut.
			var seen: Dictionary = {}
			var fe_id := ""
			var fe_t := -1.0
			for ev_v in h.get("item_log", []):
				var ev: Dictionary = ev_v
				if bool(ev.get("sold", false)) or str(ev.get("tier", "")) != "epic":
					continue
				var iid: String = str(ev.get("id", "?"))
				var t_buy: float = float(ev.get("t", 0.0))
				seen[iid] = true
				if fe_t < 0.0 or t_buy < fe_t:
					fe_t = t_buy
					fe_id = iid
			if not role_item.has(role):
				role_item[role] = {}
			var rmap: Dictionary = role_item[role]
			for iid_v in seen:
				var rid: String = str(iid_v)
				if not rmap.has(rid):
					rmap[rid] = {"id": rid, "n": 0, "wins": 0, "decided": 0}
				var ra: Dictionary = rmap[rid]
				ra["n"] = int(ra["n"]) + 1
				if decided:
					ra["decided"] = int(ra["decided"]) + 1
					if won:
						ra["wins"] = int(ra["wins"]) + 1
			if fe_id == "":
				continue
			var femap: Dictionary = ha["fe"]
			if not femap.has(fe_id):
				femap[fe_id] = {"id": fe_id, "n": 0, "wins": 0, "decided": 0}
			var fa: Dictionary = femap[fe_id]
			fa["n"] = int(fa["n"]) + 1
			if decided:
				fa["decided"] = int(fa["decided"]) + 1
				if won:
					fa["wins"] = int(fa["wins"]) + 1
			var grp: Dictionary = early_grp if fe_t < CROSS_EARLY_T else late_grp
			grp["n"] = int(grp["n"]) + 1
			grp["t_sum"] = float(grp["t_sum"]) + fe_t
			if decided:
				grp["decided"] = int(grp["decided"]) + 1
				if won:
					grp["wins"] = int(grp["wins"]) + 1
			if team == 0 or team == 1:
				var ph2: Array = h.get("damage_phase", [])
				var tot: Array = t_ph[team]
				if ph2.size() >= 1 and float(tot[0]) > 0.0:
					grp["early_sum"] = float(grp["early_sum"]) \
						+ 100.0 * float(ph2[0]) / float(tot[0])
					grp["early_n"] = int(grp["early_n"]) + 1
				if ph2.size() >= 3 and float(tot[2]) > 0.0:
					grp["late_sum"] = float(grp["late_sum"]) \
						+ 100.0 * float(ph2[2]) / float(tot[2])
					grp["late_n"] = int(grp["late_n"]) + 1

	# --- (a) itemi x rooli ---
	lines.append("")
	lines.append("  -- (a) itemi × rooli: %d rakennetuinta epiciä per rooli --" % CROSS_TOP_ITEMS)
	lines.append("  rooli   | epic                 |   n | osuus | haltijan voitto%")
	var rkeys: Array = role_item.keys()
	rkeys.sort_custom(func(x, y): return _role_rank(str(x)) < _role_rank(str(y)))
	for role_v in rkeys:
		var role: String = str(role_v)
		var rmap: Dictionary = role_item[role]
		var rows: Array = rmap.values()
		rows.sort_custom(func(x, y): return _cross_before(x, y))
		var total := 0
		for r_v in rows:
			var ra: Dictionary = r_v
			total += int(ra["n"])
		if rows.is_empty():
			lines.append("  %-7s | ei epicejä otannassa" % role)
			continue
		for i in range(mini(rows.size(), CROSS_TOP_ITEMS)):
			var rb: Dictionary = rows[i]
			var iname: String = str(ItemDef.get_item(str(rb["id"])).get("name", str(rb["id"])))
			lines.append("  %-7s | %-20s | %3d | %4.0f%% | %s" % [
				(role if i == 0 else ""), iname, int(rb["n"]),
				100.0 * float(rb["n"]) / maxf(float(total), 1.0),
				_pct_text(int(rb["wins"]), int(rb["decided"]))])
	if rkeys.is_empty():
		lines.append("  Ei rooliaineistoa otannassa.")

	# --- (b) itemi x sankari ---
	lines.append("")
	lines.append("  -- (b) itemi × sankari: %d kovinta ja %d kevyintä vahingontekijää --" % [
		CROSS_HERO_N, CROSS_HERO_N])
	lines.append("  ryhmä | sankari  | vah/peli | yleisin 1. epic      |   n | voitto%")
	var hrows: Array = hero_item.values()
	for a_v in hrows:
		var a: Dictionary = a_v
		a["dpg"] = float(a["damage"]) / maxf(float(a["games"]), 1.0)
	hrows.sort_custom(func(x, y): return _cross_before_dpg(x, y))
	var top_n: int = mini(hrows.size(), CROSS_HERO_N)
	var low_start: int = maxi(hrows.size() - CROSS_HERO_N, top_n)
	var low_rows: Array = []
	for i in range(hrows.size() - 1, low_start - 1, -1):
		low_rows.append(hrows[i])
	var groups: Array = [["kova", hrows.slice(0, top_n)], ["kevyt", low_rows]]
	for g_v in groups:
		var g: Array = g_v
		var gname: String = str(g[0])
		var grows: Array = g[1]
		for i in range(grows.size()):
			var hb: Dictionary = grows[i]
			var femap: Dictionary = hb["fe"]
			var best: Dictionary = {}
			for fid_v in femap:
				var b: Dictionary = femap[fid_v]
				if best.is_empty() or int(b["n"]) > int(best["n"]) \
						or (int(b["n"]) == int(best["n"]) and str(b["id"]) < str(best["id"])):
					best = b
			var iname := "-"
			var bn := 0
			var wr_text := "-"
			if not best.is_empty():
				iname = str(ItemDef.get_item(str(best["id"])).get("name", str(best["id"])))
				bn = int(best["n"])
				wr_text = _pct_text(int(best["wins"]), int(best["decided"]))
			lines.append("  %-5s | %-8s | %8d | %-20s | %3d | %s" % [
				(gname if i == 0 else ""), str(hb["id"]), int(float(hb["dpg"])),
				iname, bn, wr_text])
	if hrows.is_empty():
		lines.append("  Ei sankaridataa otannassa.")

	# --- (c) voimakayra x ensiepicin ajoitus ---
	lines.append("")
	lines.append("  -- (c) voimakäyrä × ensiepicin ajoitus: muuttuuko aikainen itemi loppupelin voimaksi --")
	lines.append("  ryhmä        | sank.ott | 1. epic ka | 0-7 min | 14-20 min | voitto%")
	for grp_v in [early_grp, late_grp]:
		var grp: Dictionary = grp_v
		if int(grp["n"]) <= 0:
			lines.append("  %-12s | ei dataa" % str(grp["name"]))
			continue
		lines.append("  %-12s | %8d | %10s | %6.1f%% | %8.1f%% | %s" % [
			str(grp["name"]), int(grp["n"]),
			_fmt(float(grp["t_sum"]) / maxf(float(grp["n"]), 1.0)),
			float(grp["early_sum"]) / maxf(float(grp["early_n"]), 1.0),
			float(grp["late_sum"]) / maxf(float(grp["late_n"]), 1.0),
			_pct_text(int(grp["wins"]), int(grp["decided"]))])
	if int(early_grp["late_n"]) > 0 and int(late_grp["late_n"]) > 0:
		var diff: float = float(early_grp["late_sum"]) / float(early_grp["late_n"]) \
			- float(late_grp["late_sum"]) / float(late_grp["late_n"])
		var verdict := "ei eroa — ensiepicin ajoitus ei näy loppupelissä"
		if diff >= CROSS_LATE_DEV:
			verdict = "aikainen ensiepic muuttuu loppupelin voimaksi"
		elif diff <= -CROSS_LATE_DEV:
			verdict = "aikainen ensiepic EI kanna loppupeliin — myöhäinen avaus skaalaa paremmin"
		lines.append("  Ero loppuvaiheessa (14-20 min): %+.1f %%-yks -> %s" % [diff, verdict])
	else:
		lines.append("  Ei riittävää vaihedataa ajoitusvertailuun (ei damage_phase-tietoa).")


## Tasot ja XP: muuntuuko talous- ja tasojohto voitoiksi. Voittaja- vs häviäjä-
## joukkueen päätöstasot, ulttiaikataulu (L4) ja XP-/kultajohdon konversio.
static func _section_levels(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	lines.append("")
	lines.append(str(opts.get("levels_title", "=== TASOT JA XP ===")))
	lines.append("  Muuntuuko talousjohto voitoiksi: tasoerot, ulttiaikataulu ja johdon konversio.")
	var win_level_sum := 0.0
	var lose_level_sum := 0.0
	var decided := 0
	var xp_lead_games := 0
	var xp_lead_wins := 0
	var gold_lead_games := 0
	var gold_lead_wins := 0
	var l4_times: Array = []
	var l12_times: Array = []
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var level_sum := [0.0, 0.0]
		var team_n := [0.0, 0.0]
		var xp_sum := [0.0, 0.0]
		var gold_sum := [0.0, 0.0]
		for hv in snap.get("heroes", []):
			var h: Dictionary = hv
			var team: int = int(h.get("team", -1))
			if team == 0 or team == 1:
				level_sum[team] += float(h.get("level", 1))
				team_n[team] += 1.0
				xp_sum[team] += float(h.get("xp", 0.0))
				gold_sum[team] += float(h.get("gold", 0.0))
			var lt: Dictionary = h.get("level_times", {})
			if lt.has("4"):
				l4_times.append(float(lt["4"]))
			if lt.has("12"):
				l12_times.append(float(lt["12"]))
		if winner != 0 and winner != 1:
			continue   # tasapeli ei kerro johdon konversiosta
		if float(team_n[0]) <= 0.0 or float(team_n[1]) <= 0.0:
			continue
		decided += 1
		win_level_sum += float(level_sum[winner]) / float(team_n[winner])
		lose_level_sum += float(level_sum[1 - winner]) / float(team_n[1 - winner])
		if not is_equal_approx(float(xp_sum[0]), float(xp_sum[1])):
			xp_lead_games += 1
			var xp_leader: int = 0 if float(xp_sum[0]) > float(xp_sum[1]) else 1
			if xp_leader == winner:
				xp_lead_wins += 1
		if not is_equal_approx(float(gold_sum[0]), float(gold_sum[1])):
			gold_lead_games += 1
			var gold_leader: int = 0 if float(gold_sum[0]) > float(gold_sum[1]) else 1
			if gold_leader == winner:
				gold_lead_wins += 1
	if decided > 0:
		var wl: float = win_level_sum / float(decided)
		var ll: float = lose_level_sum / float(decided)
		lines.append("  Päätöstaso ka: voittajat %.1f vs häviäjät %.1f (tasojohto %+.1f)" % [
			wl, ll, wl - ll])
	else:
		lines.append("  Ei ratkenneita otteluita — tasovertailu ohitettu.")
	lines.append("  Mediaani L4 (ultti auki): %s (n=%d) | mediaani L12: %s (n=%d)" % [
		_median_fmt(l4_times), l4_times.size(), _median_fmt(l12_times), l12_times.size()])
	lines.append("  XP-johto voitti %d/%d ottelusta (%d %%)" % [xp_lead_wins, xp_lead_games,
		int(round(100.0 * float(xp_lead_wins) / maxf(float(xp_lead_games), 1.0)))])
	lines.append("  Kultajohto voitti %d/%d ottelusta (%d %%)" % [gold_lead_wins, gold_lead_games,
		int(round(100.0 * float(gold_lead_wins) / maxf(float(gold_lead_games), 1.0)))])


## Kykyrankit: lopputilanteen rankit per slotti. Lopputila EI kerro maksaus-
## järjestystä ("ensin maksattu" vaatisi aikaleimatun lokin), joten raportoidaan
## rehellisesti keskirankki per slotti sekä rank 3:n saavuttaneiden voitto%
## verrattuna muihin — iso ero vihjaa yli-/alivoimaisesta kyvystä.
static func _section_ability_ranks(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	lines.append("")
	lines.append(str(opts.get("ranks_title", "=== KYKYRANKIT ===")))
	lines.append("  Lopputila ei kerro maksausjärjestystä; vertailu: slotin rank 3 vs alle 3.")
	lines.append("  TARKISTA kun ero >= 12 %-yks ja molemmissa ryhmissä n >= 16 (tasapelit ohitettu).")
	var order := ["basic", "a1", "a2", "dodge", "ult"]
	var slots: Dictionary = {}
	for sname in order:
		slots[sname] = {"rank_sum": 0.0, "n": 0,
			"n3": 0, "wins3": 0, "nlow": 0, "winslow": 0}
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		for hv in snap.get("heroes", []):
			var h: Dictionary = hv
			var build: Dictionary = h.get("skill_build", {})
			if build.is_empty():
				continue   # vanha snapshot tai sankari ilman rankkeja
			var won: bool = int(h.get("team", -1)) == winner
			var counted: bool = winner == 0 or winner == 1
			for sname in order:
				var rank: int = int(build.get(sname, 0))
				var s: Dictionary = slots[sname]
				s["rank_sum"] = float(s["rank_sum"]) + float(rank)
				s["n"] = int(s["n"]) + 1
				if not counted:
					continue
				if rank >= 3:
					s["n3"] = int(s["n3"]) + 1
					if won:
						s["wins3"] = int(s["wins3"]) + 1
				else:
					s["nlow"] = int(s["nlow"]) + 1
					if won:
						s["winslow"] = int(s["winslow"]) + 1
	var names := {"basic": "perus", "a1": "a1", "a2": "a2", "dodge": "väistö", "ult": "ult"}
	lines.append("  slotti | rank ka | n r3 | voitto% r3 | n <3 | voitto% <3 | ero    | huomio")
	var any_data := false
	for sname in order:
		var s: Dictionary = slots[sname]
		if int(s["n"]) <= 0:
			continue
		any_data = true
		var n3: int = int(s["n3"])
		var nlow: int = int(s["nlow"])
		var wr3: float = 100.0 * float(s["wins3"]) / maxf(float(n3), 1.0)
		var wrlow: float = 100.0 * float(s["winslow"]) / maxf(float(nlow), 1.0)
		var gap: float = wr3 - wrlow
		var note := ""
		if n3 >= 16 and nlow >= 16 and absf(gap) >= 12.0:
			note = "TARKISTA"
		var wr3_text: String = "-" if n3 <= 0 else "%5.1f %%" % wr3
		var wrlow_text: String = "-" if nlow <= 0 else "%5.1f %%" % wrlow
		var gap_text: String = "-" if (n3 <= 0 or nlow <= 0) else "%+5.1f" % gap
		lines.append("  %-6s | %7.2f | %4d | %-10s | %4d | %-10s | %-6s | %s" % [
			str(names.get(sname, sname)),
			float(s["rank_sum"]) / maxf(float(s["n"]), 1.0),
			n3, wr3_text, nlow, wrlow_text, gap_text, note])
	if not any_data:
		lines.append("  Ei skill build -dataa otannassa (vanhat snapshotit?).")
	_common_build_table(lines, snapshots)


## Mediaaniaika muotoiltuna (m:ss); "-" jos havaintoja ei ole.
static func _median_fmt(times: Array) -> String:
	if times.is_empty():
		return "-"
	var sorted_times: Array = times.duplicate()
	sorted_times.sort()
	var mid: int = sorted_times.size() / 2
	if sorted_times.size() % 2 == 1:
		return _fmt(float(sorted_times[mid]))
	return _fmt((float(sorted_times[mid - 1]) + float(sorted_times[mid])) * 0.5)


## Otannan keskimääräinen SANKARIVAHINKO/min (sama pohja kuin taulukon
## vah/min-sarakkeessa, jotta anomaliaraja vertaa samaa suuretta).
static func _mean_dpm(agg: Dictionary, avg_min: float) -> float:
	var total := 0.0
	var n := 0
	for id in agg:
		var a: Dictionary = agg[id]
		if int(a["games"]) < 3 or float(a["damage"]) <= 1.0:
			continue
		total += _combat_damage(a) / maxf(_hero_minutes(a, avg_min), 0.1)
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


## Sankaridatan koonti yhdessä paikassa: per-sankari-rivit ja roolikooste.
## Sama koonti palvelee sekä SANKARIBALANSSI-osiota että itsenäistä
## voimakäyrätaulukkoa, joten luvut eivät pääse erilleen toisistaan.
static func _hero_stats(snapshots: Array) -> Dictionary:
	var hero: Dictionary = {}
	var roles: Dictionary = {}
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var decided: bool = winner == 0 or winner == 1
		var elapsed: float = float(snap.get("elapsed", 0.0))
		var heroes: Array = snap.get("heroes", [])
		var t_dmg: Array = [0.0, 0.0]
		var t_str: Array = [0.0, 0.0]
		var t_gold: Array = [0.0, 0.0]
		var t_ph: Array = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for hv in heroes:
			var hh: Dictionary = hv
			var ht: int = int(hh.get("team", -1))
			if ht != 0 and ht != 1:
				continue
			t_dmg[ht] = float(t_dmg[ht]) + float(hh.get("damage", 0.0))
			t_str[ht] = float(t_str[ht]) + float(hh.get("structure_damage", 0.0))
			t_gold[ht] = float(t_gold[ht]) + float(hh.get("gold", 0.0))
			var ph: Array = hh.get("damage_phase", [])
			var acc: Array = t_ph[ht]
			for i in range(mini(ph.size(), 3)):
				acc[i] = float(acc[i]) + float(ph[i])
		for hv in heroes:
			var h: Dictionary = hv
			var id: String = str(h.get("hero_id", "?"))
			var team: int = int(h.get("team", -1))
			var won: bool = decided and team == winner
			if not hero.has(id):
				hero[id] = {"id": id, "games": 0, "wins": 0, "decided": 0,
					"kos": 0.0, "deaths": 0.0, "assists": 0.0, "level_sum": 0.0,
					"dmg_share": 0.0, "str_share": 0.0, "gold_share": 0.0,
					"fe_sum": 0.0, "fe_n": 0,
					"ph_share": [0.0, 0.0, 0.0], "ph_n": [0, 0, 0]}
			var a: Dictionary = hero[id]
			a["games"] = int(a["games"]) + 1
			a["kos"] = float(a["kos"]) + float(h.get("kos", 0))
			a["deaths"] = float(a["deaths"]) + float(h.get("deaths", 0))
			a["assists"] = float(a["assists"]) + float(h.get("assists", 0))
			a["level_sum"] = float(a["level_sum"]) + float(h.get("level", 1))
			if decided:
				a["decided"] = int(a["decided"]) + 1
				if won:
					a["wins"] = int(a["wins"]) + 1
			if team == 0 or team == 1:
				a["dmg_share"] = float(a["dmg_share"]) + 100.0 * float(h.get("damage", 0.0)) \
					/ maxf(float(t_dmg[team]), 1.0)
				a["str_share"] = float(a["str_share"]) \
					+ 100.0 * float(h.get("structure_damage", 0.0)) / maxf(float(t_str[team]), 1.0)
				a["gold_share"] = float(a["gold_share"]) + 100.0 * float(h.get("gold", 0.0)) \
					/ maxf(float(t_gold[team]), 1.0)
				# Voimakäyrä: vaihe lasketaan vain jos joukkue teki vaiheessa vahinkoa
				# (ottelu voi päättyä ennen loppuvaihetta -> ei nollien keskiarvoa).
				var ph: Array = h.get("damage_phase", [])
				var tot: Array = t_ph[team]
				var shares: Array = a["ph_share"]
				var counts: Array = a["ph_n"]
				for i in range(mini(ph.size(), 3)):
					if float(tot[i]) <= 0.0:
						continue
					shares[i] = float(shares[i]) + 100.0 * float(ph[i]) / float(tot[i])
					counts[i] = int(counts[i]) + 1
			# Ensimmäisen epicin valmistumisaika ostologista.
			var fe_t := -1.0
			for ev_v in h.get("item_log", []):
				var ev: Dictionary = ev_v
				if bool(ev.get("sold", false)) or str(ev.get("tier", "")) != "epic":
					continue
				var t_buy: float = float(ev.get("t", 0.0))
				if fe_t < 0.0 or t_buy < fe_t:
					fe_t = t_buy
			if fe_t >= 0.0:
				a["fe_sum"] = float(a["fe_sum"]) + fe_t
				a["fe_n"] = int(a["fe_n"]) + 1
			# Roolikooste (progression_role).
			var role: String = str(h.get("progression_role", h.get("role", "unknown")))
			if role == "":
				role = "unknown"
			if not roles.has(role):
				roles[role] = {"role": role, "games": 0, "wins": 0, "decided": 0,
					"gold": 0.0, "time": 0.0, "dmg_share": 0.0, "deaths": 0.0}
			var r: Dictionary = roles[role]
			r["games"] = int(r["games"]) + 1
			r["gold"] = float(r["gold"]) + float(h.get("gold", 0.0))
			r["time"] = float(r["time"]) + elapsed
			r["deaths"] = float(r["deaths"]) + float(h.get("deaths", 0))
			if team == 0 or team == 1:
				r["dmg_share"] = float(r["dmg_share"]) + 100.0 * float(h.get("damage", 0.0)) \
					/ maxf(float(t_dmg[team]), 1.0)
			if decided:
				r["decided"] = int(r["decided"]) + 1
				if won:
					r["wins"] = int(r["wins"]) + 1
	return {"hero": hero, "roles": roles}


## Voimakäyrätaulukko omana lohkonaan: sama taulukko ladotaan sekä
## sankariosion sisälle että sweep-raporttiin omana osionaan.
static func _power_curve_block(lines: Array, hero: Dictionary) -> void:
	lines.append("")
	lines.append("  -- voimakäyrä: vahingon osuus omasta joukkueesta pelivaiheittain --")
	lines.append("  Loppu/alku-suhde yli ×%.1f = loppupelin hahmo, alle ×%.2f = alkupelin hahmo." % [
		PHASE_RATIO, 1.0 / PHASE_RATIO])
	lines.append("  Tulkinta on TIETOA: se kertoo osuuko _level_scaling-profiili suunnitteluaikeeseen.")
	lines.append("  sankari  | 0-7 min | 7-14 min | 14-20 min | loppu/alku | tulkinta")
	var curve_rows: Array = hero.values()
	curve_rows.sort_custom(func(x, y): return str(x["id"]) < str(y["id"]))
	var any_curve := false
	for a_v in curve_rows:
		var a: Dictionary = a_v
		var shares: Array = a["ph_share"]
		var counts: Array = a["ph_n"]
		if int(counts[0]) <= 0 and int(counts[1]) <= 0 and int(counts[2]) <= 0:
			continue
		any_curve = true
		var early: float = float(shares[0]) / maxf(float(counts[0]), 1.0)
		var mid: float = float(shares[1]) / maxf(float(counts[1]), 1.0)
		var late: float = float(shares[2]) / maxf(float(counts[2]), 1.0)
		var ratio_text := "-"
		var verdict := ""
		var enough: bool = int(a["games"]) >= PHASE_MIN_GAMES \
			and int(counts[0]) > 0 and int(counts[2]) > 0 and early > 0.0
		if enough:
			var ratio: float = late / early
			ratio_text = "×%.2f" % ratio
			if ratio >= PHASE_RATIO:
				verdict = "LOPPUPELIN HAHMO"
			elif ratio <= 1.0 / PHASE_RATIO:
				verdict = "ALKUPELIN HAHMO"
		lines.append("  %-8s | %6.1f%% | %7.1f%% | %8.1f%% | %10s | %s" % [
			str(a["id"]), early, mid, late, ratio_text, verdict])
	if not any_curve:
		lines.append("  Ei vaihekohtaista vahinkodataa (vanhat tilannekuvat ilman damage_phasea).")


## Voimakäyrä omana osionaan: sama taulukko kuin sankariosion sisällä, mutta
## oma otsikko ja selitys. Sweepissä tämä on itsenäinen tulos — se vastaa
## kysymykseen "kuinka tehokas sankari on pelin eri vaiheissa".
static func _section_power_curve(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	lines.append("")
	lines.append(str(opts.get("curve_title", "=== VOIMAKÄYRÄ (alku- / keski- / loppupeli) ===")))
	lines.append("  Sama taulukko kuin sankariosiossa: vahingon osuus omasta joukkueesta vaiheittain.")
	var stats: Dictionary = _hero_stats(snapshots)
	var hero: Dictionary = stats["hero"]
	_power_curve_block(lines, hero)


## Sankaribalanssin syvyys kolmena taulukkona:
##   - per-sankari: voitto%, KDA ja panosten OSUUDET oman joukkueen summasta
##     (vahinko, tornivahinko, kulta) sekä päätöstaso ja ensiepicin aika.
##   - voimakäyrä: vahingon osuus pelivaiheittain (0-7 / 7-14 / 14+ min). Tämä on
##     _level_scaling-profiilien todentaja: kertoo onko sankari toteutuneesti
##     alku- vai loppupelin hahmo. Luokittelu on TIETOA, ei virhe.
##   - roolikooste: voitto%, kulta/min, vahinko-osuus ja kuolemat rooleittain.
## Osuudet lasketaan ottelukohtaisina ja keskiarvoistetaan, jotta yksi pitkä
## ottelu ei paina enempää kuin lyhyt.
static func _section_heroes(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	var flags: Array = _opt_flags(opts)
	var flag_start: int = flags.size()
	lines.append("")
	lines.append("=== SANKARIBALANSSI ===")
	lines.append("  Osuus = sankarin osuus OMAN joukkueen summasta, ottelukohtaisten osuuksien ka.")
	lines.append("  1. epic = ensimmäisen epicin valmistumisaika (ostologista).")
	var stats: Dictionary = _hero_stats(snapshots)
	var hero: Dictionary = stats["hero"]
	var roles: Dictionary = stats["roles"]

	# --- per-sankari, järjestetty voitto%:n mukaan ---
	var rows: Array = hero.values()
	for a_v in rows:
		var a: Dictionary = a_v
		a["wr"] = 100.0 * float(a["wins"]) / maxf(float(a["decided"]), 1.0)
	rows.sort_custom(func(x, y): return float(x["wr"]) > float(y["wr"]))
	lines.append("")
	lines.append("  sankari  | pel | voitto% |  KDA  | vah-os% | torni-os% | kulta-os% | LV ka | 1. epic | tuomio")
	for a_v in rows:
		var a: Dictionary = a_v
		var g: float = maxf(float(a["games"]), 1.0)
		var wr_text: String = "-" if int(a["decided"]) <= 0 else "%5.1f %%" % float(a["wr"])
		var fe_text: String = "-" if int(a["fe_n"]) <= 0 \
			else _fmt(float(a["fe_sum"]) / float(a["fe_n"]))
		var note := ""
		if int(a["decided"]) >= HERO_MIN_N:
			var wr: float = float(a["wr"])
			if wr > HERO_WR_HIGH:
				note = _flag(flags, "sankari", str(a["id"]),
					"TARKISTA: voitto%% %.1f yli %.0f" % [wr, HERO_WR_HIGH])
			elif wr < HERO_WR_LOW:
				note = _flag(flags, "sankari", str(a["id"]),
					"TARKISTA: voitto%% %.1f alle %.0f" % [wr, HERO_WR_LOW])
		lines.append("  %-8s | %3d | %-7s | %5.2f | %6.1f%% | %8.1f%% | %8.1f%% | %5.1f | %7s | %s" % [
			str(a["id"]), int(a["games"]), wr_text,
			(float(a["kos"]) + float(a["assists"])) / maxf(float(a["deaths"]), 1.0),
			float(a["dmg_share"]) / g, float(a["str_share"]) / g, float(a["gold_share"]) / g,
			float(a["level_sum"]) / g, fe_text, note])
	if rows.is_empty():
		lines.append("  Ei sankaridataa otannassa.")
	_power_curve_block(lines, hero)

	# --- roolikooste ---
	lines.append("")
	lines.append("  -- roolikooste (progression_role) --")
	lines.append("  rooli   | pel | voitto% | G/min | vah-os% | kuol/peli | tuomio")
	var role_rows: Array = roles.values()
	role_rows.sort_custom(func(x, y): return _role_rank(str(x["role"])) < _role_rank(str(y["role"])))
	for a_v in role_rows:
		var a: Dictionary = a_v
		var g: float = maxf(float(a["games"]), 1.0)
		var minutes: float = maxf(float(a["time"]) / 60.0, 0.1)
		var wr: float = 100.0 * float(a["wins"]) / maxf(float(a["decided"]), 1.0)
		var wr_text: String = "-" if int(a["decided"]) <= 0 else "%5.1f %%" % wr
		var note := ""
		if int(a["decided"]) >= HERO_MIN_N and absf(wr - 50.0) > ROLE_WR_DEV:
			note = _flag(flags, "järjestelmä", "rooli",
				"TARKISTA: rooli '%s' voitto%% %.1f (poikkeama %+.1f %%-yks)" % [
					str(a["role"]), wr, wr - 50.0])
		lines.append("  %-7s | %3d | %-7s | %5d | %6.1f%% | %9.2f | %s" % [
			str(a["role"]), int(a["games"]), wr_text, int(float(a["gold"]) / minutes),
			float(a["dmg_share"]) / g, float(a["deaths"]) / g, note])
	if role_rows.is_empty():
		lines.append("  Ei rooliaineistoa otannassa.")
	lines.append("  Sankariosion tarkistuskohteita: %d." % (flags.size() - flag_start))


## Ladderin sankariottelut tiereittain: kumpi rank pelasi kummallakin puolella.
## Palauttaa tyhjän sanakirjan jos tulosjoukko ei ole ladder-muotoinen (sweep ja
## vakiosimulaatio eivät kanna rank-tietoa) — kutsuja tulostaa silloin "ei dataa".
static func _tier_rows(results: Array) -> Dictionary:
	var out: Dictionary = {}
	for e_v in results:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		if not (e.has("snap") and e.has("lo") and e.has("hi") and e.has("hi_team")):
			continue
		var snap: Dictionary = e["snap"]
		var hi_team: int = int(e["hi_team"])
		for hv in snap.get("heroes", []):
			var h: Dictionary = hv
			var rank: int = int(e["hi"]) if int(h.get("team", -1)) == hi_team else int(e["lo"])
			var tier: int = BotRank.tier_of(rank)
			if not out.has(tier):
				out[tier] = []
			var bucket: Array = out[tier]
			bucket.append(h)
	return out


## Tierikohtainen koonti: valmiit epicit, ensiepicin aika, käyttämätön kulta,
## rakennetuimmat itemit sekä tasot (LV ka, L4- ja L12-ajat). Yksi kerays
## palvelee molempia per rank -taulukoita, joten luvut eivät pääse erilleen.
static func _tier_aggregate(rows: Dictionary) -> Dictionary:
	var agg: Dictionary = {}
	for tier_v in rows:
		var tier: int = int(tier_v)
		var bucket: Array = rows[tier]
		if not agg.has(tier):
			agg[tier] = {"n": 0, "epics": 0, "fe_sum": 0.0, "fe_n": 0, "unspent": 0.0,
				"items": {}, "level_sum": 0.0, "l4": [], "l12": []}
		var a: Dictionary = agg[tier]
		for hv in bucket:
			var h: Dictionary = hv
			a["n"] = int(a["n"]) + 1
			a["unspent"] = float(a["unspent"]) + maxf(
				float(h.get("gold", 0.0)) - float(h.get("gold_spent", 0.0)), 0.0)
			a["level_sum"] = float(a["level_sum"]) + float(h.get("level", 1))
			var lt: Dictionary = h.get("level_times", {})
			if lt.has("4"):
				var l4: Array = a["l4"]
				l4.append(float(lt["4"]))
			if lt.has("12"):
				var l12: Array = a["l12"]
				l12.append(float(lt["12"]))
			var seen: Dictionary = {}
			var fe_t := -1.0
			for ev_v in h.get("item_log", []):
				var ev: Dictionary = ev_v
				if bool(ev.get("sold", false)) or str(ev.get("tier", "")) != "epic":
					continue
				var iid: String = str(ev.get("id", "?"))
				seen[iid] = true
				var t_buy: float = float(ev.get("t", 0.0))
				if fe_t < 0.0 or t_buy < fe_t:
					fe_t = t_buy
			a["epics"] = int(a["epics"]) + seen.size()
			var items: Dictionary = a["items"]
			for sid_v in seen:
				var sid: String = str(sid_v)
				items[sid] = int(items.get(sid, 0)) + 1
			if fe_t >= 0.0:
				a["fe_sum"] = float(a["fe_sum"]) + fe_t
				a["fe_n"] = int(a["fe_n"]) + 1
	return agg


## Tierin nimi; tuntematon indeksi ei kaada raporttia.
static func _tier_name(tier: int) -> String:
	if tier < 0 or tier >= BotRank.TIER_NAMES.size():
		return "?"
	return str(BotRank.TIER_NAMES[tier])


## ITEMIT PER RANK — itemoiko ylempi rank oikeasti paremmin. Tämä on ladderin
## ydinkysymyksen (miksi ylempi voittaa) talouspuoli: valmiiden epicien määrä,
## avauksen aika ja lompakkoon jäänyt kulta tiereittäin.
static func _section_items_by_rank(lines: Array, results: Array, opts: Dictionary) -> void:
	lines.append("")
	lines.append(str(opts.get("rank_items_title", "=== ITEMIT PER RANK ===")))
	lines.append("  Itemoiko ylempi rank paremmin: valmiit epicit, avauksen aika ja lompakkoon jäänyt kulta.")
	lines.append("  tier        | sank.ott | epicejä/s | 1. epic ka | käyttämätön | rakennetuin epic")
	var rows: Dictionary = _tier_rows(results)
	if rows.is_empty():
		lines.append("  Ei rank-tietoa otannassa (vain ladder-ajo tuottaa sen).")
		return
	var agg: Dictionary = _tier_aggregate(rows)
	var keys: Array = agg.keys()
	keys.sort()
	for tier_v in keys:
		var tier: int = int(tier_v)
		var a: Dictionary = agg[tier]
		var items: Dictionary = a["items"]
		var ikeys: Array = items.keys()
		ikeys.sort()
		var best_id := ""
		var best_n := 0
		for iid_v in ikeys:
			var iid: String = str(iid_v)
			if int(items[iid]) > best_n:
				best_id = iid
				best_n = int(items[iid])
		var best := "-"
		if best_id != "":
			best = "%s (%d)" % [str(ItemDef.get_item(best_id).get("name", best_id)), best_n]
		var fe_text := "-"
		if int(a["fe_n"]) > 0:
			fe_text = _fmt(float(a["fe_sum"]) / float(a["fe_n"]))
		lines.append("  %-11s | %8d | %9.2f | %10s | %11d | %s" % [
			_tier_name(tier), int(a["n"]),
			float(a["epics"]) / maxf(float(a["n"]), 1.0), fe_text,
			int(float(a["unspent"]) / maxf(float(a["n"]), 1.0)), best])
	if keys.size() >= 2:
		var lo: Dictionary = agg[int(keys[0])]
		var hi: Dictionary = agg[int(keys[keys.size() - 1])]
		var d_epics: float = float(hi["epics"]) / maxf(float(hi["n"]), 1.0) \
			- float(lo["epics"]) / maxf(float(lo["n"]), 1.0)
		var note := "ylempi tier itemoi tehokkaammin"
		if d_epics <= -0.05:
			note = "TARKISTA: ylempi tier saa VÄHEMMÄN epicejä valmiiksi"
		elif absf(d_epics) < 0.05:
			note = "TARKISTA: tierien itemointi ei eroa"
		lines.append("  %s -> %s: %+.2f epiciä/sankariottelu -> %s" % [
			_tier_name(int(keys[0])), _tier_name(int(keys[keys.size() - 1])), d_epics, note])


## TASOT PER RANK — pääseekö ylempi rank nopeammin ultille ja loppupelin
## tasoille. Mediaani (ei keskiarvo): yksi venynyt ottelu ei vääristä lukua.
static func _section_levels_by_rank(lines: Array, results: Array, opts: Dictionary) -> void:
	lines.append("")
	lines.append(str(opts.get("rank_levels_title", "=== TASOT PER RANK ===")))
	lines.append("  Pääseekö ylempi rank nopeammin ultille (L4) ja loppupelin tasoille (L12).")
	lines.append("  tier        | pelaajia | LV ka | mediaani L4 | mediaani L12")
	var rows: Dictionary = _tier_rows(results)
	if rows.is_empty():
		lines.append("  Ei rank-tietoa otannassa (vain ladder-ajo tuottaa sen).")
		return
	var agg: Dictionary = _tier_aggregate(rows)
	var keys: Array = agg.keys()
	keys.sort()
	for tier_v in keys:
		var tier: int = int(tier_v)
		var a: Dictionary = agg[tier]
		lines.append("  %-11s | %8d | %5.1f | %11s | %12s" % [
			_tier_name(tier), int(a["n"]),
			float(a["level_sum"]) / maxf(float(a["n"]), 1.0),
			_median_fmt(a["l4"]), _median_fmt(a["l12"])])


## Ottelutason systeeminen terveys: kestojakauma ja päättymistapa, lumipallo vs
## comeback (kultajohto 10:00 vs lopputulos), ensitapahtumien konversio voitoiksi,
## objektiivimäärät, talouden lähteet rooleittain sekä CC/vaimennus.
## Tämä osio vastaa kysymykseen "onko itse peli terve", ei "onko itemi vahva".
static func _section_match_health(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	var flags: Array = _opt_flags(opts)
	var flag_start: int = flags.size()
	lines.append("")
	lines.append("=== OTTELUIDEN TERVEYS ===")
	if snapshots.is_empty():
		lines.append("  Ei otteluita otannassa.")
		return
	var times: Array = []
	var nexus_n := 0
	var cap_n := 0
	var other_n := 0
	# Lumipallokauhat: johto 10:00 kohdalla suhteessa jäljessä olevan kultaan.
	var bucket_n: Array = [0, 0, 0]
	var bucket_w: Array = [0, 0, 0]
	var snow_n := 0
	var comeback_n := 0
	var no_snow_data := 0
	var fb_n := 0
	var fb_w := 0
	var ft_n := 0
	var ft_w := 0
	var fd_n := 0
	var fd_w := 0
	var fbar_n := 0
	var fbar_w := 0
	var dragons := 0
	var barons := 0
	var crystals := 0
	var supers := 0
	var no_baron_matches := 0
	var econ: Dictionary = {}
	var cc_sum := 0.0
	var mit_sum := 0.0
	var taken_sum := 0.0
	var hero_obs := 0
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var decided: bool = winner == 0 or winner == 1
		var elapsed: float = float(snap.get("elapsed", 0.0))
		times.append(elapsed)
		var reason: String = str(snap.get("reason", ""))
		if reason.find("nexus") >= 0:
			nexus_n += 1
		elif reason.find("aikakatto") >= 0:
			cap_n += 1
		else:
			other_n += 1
		var heroes: Array = snap.get("heroes", [])
		# Kultajohto 10:00: joukkueen summa niistä sankareista jotka ehtivät näytteeseen.
		var g10: Array = [0.0, 0.0]
		var g10_n: Array = [0, 0]
		for hv in heroes:
			var hh: Dictionary = hv
			hero_obs += 1
			var ht: int = int(hh.get("team", -1))
			cc_sum += float(hh.get("cc_suffered", 0.0))
			mit_sum += float(hh.get("mitigated", 0.0))
			taken_sum += float(hh.get("taken", 0.0))
			var v10: float = float(hh.get("gold_at_10", -1.0))
			if v10 >= 0.0 and (ht == 0 or ht == 1):
				g10[ht] = float(g10[ht]) + v10
				g10_n[ht] = int(g10_n[ht]) + 1
			# Talouden lähteet rooleittain.
			var role: String = str(hh.get("progression_role", hh.get("role", "unknown")))
			if role == "":
				role = "unknown"
			if not econ.has(role):
				econ[role] = {"role": role, "n": 0, "gold": 0.0, "passive": 0.0,
					"cs": 0.0, "prox": 0.0, "kills": 0.0, "tower": 0.0, "jungle": 0.0}
			var e: Dictionary = econ[role]
			e["n"] = int(e["n"]) + 1
			e["gold"] = float(e["gold"]) + float(hh.get("gold", 0.0))
			e["passive"] = float(e["passive"]) + float(hh.get("passive_gold", 0.0))
			e["cs"] = float(e["cs"]) + float(hh.get("last_hit_gold", 0.0))
			e["prox"] = float(e["prox"]) + float(hh.get("proximity_gold", 0.0))
			e["kills"] = float(e["kills"]) + float(hh.get("kill_gold", 0.0)) \
				+ float(hh.get("assist_gold_earned", 0.0))
			e["tower"] = float(e["tower"]) + float(hh.get("tower_gold", 0.0))
			e["jungle"] = float(e["jungle"]) + float(hh.get("jungle_gold", 0.0))
		if decided and int(g10_n[0]) > 0 and int(g10_n[1]) > 0:
			var hi: int = 0 if float(g10[0]) >= float(g10[1]) else 1
			var lead: float = 100.0 * (float(g10[hi]) - float(g10[1 - hi])) \
				/ maxf(float(g10[1 - hi]), 1.0)
			var bi := 0
			if lead >= 15.0:
				bi = 2
			elif lead >= 5.0:
				bi = 1
			bucket_n[bi] = int(bucket_n[bi]) + 1
			snow_n += 1
			if hi == winner:
				bucket_w[bi] = int(bucket_w[bi]) + 1
			else:
				comeback_n += 1
		elif decided:
			no_snow_data += 1
		# Ensitapahtumat: ensiveri (tapahtumaloki), ensitorni, ensidragon, ensibaron.
		if decided:
			var fb_team := -1
			for ev_v in snap.get("events", []):
				var ev: Dictionary = ev_v
				var txt: String = str(ev.get("text", ""))
				if txt.begins_with("Ensiveri: SININEN"):
					fb_team = 0
					break
				if txt.begins_with("Ensiveri: ORANSSI"):
					fb_team = 1
					break
			if fb_team >= 0:
				fb_n += 1
				if fb_team == winner:
					fb_w += 1
			var tev: Array = snap.get("tower_events", [])
			if not tev.is_empty():
				var t0: Dictionary = tev[0]
				var tt: int = int(t0.get("attacker_team", -1))
				if tt == 0 or tt == 1:
					ft_n += 1
					if tt == winner:
						ft_w += 1
		var m_dragons := 0
		var m_barons := 0
		var first_dragon := -1
		var first_baron := -1
		for ev_v in snap.get("objective_events", []):
			var oev: Dictionary = ev_v
			var kind: String = str(oev.get("kind", ""))
			var ot: int = int(oev.get("team", -1))
			if kind == "dragon":
				m_dragons += 1
				if first_dragon < 0:
					first_dragon = ot
			elif kind == "baron":
				m_barons += 1
				if first_baron < 0:
					first_baron = ot
		dragons += m_dragons
		barons += m_barons
		if m_barons <= 0:
			no_baron_matches += 1
		if decided:
			if first_dragon == 0 or first_dragon == 1:
				fd_n += 1
				if first_dragon == winner:
					fd_w += 1
			if first_baron == 0 or first_baron == 1:
				fbar_n += 1
				if first_baron == winner:
					fbar_w += 1
		for cv in snap.get("crystals_broken", []):
			crystals += int(cv)
		for sv in snap.get("super_minions", []):
			supers += int(sv)

	# --- kesto ja päättymistapa ---
	var mcount: int = snapshots.size()
	times.sort()
	lines.append("  -- kesto ja päättymistapa --")
	lines.append("  Kesto: lyhin %s | mediaani %s | pisin %s" % [
		_fmt(float(times[0])), _median_fmt(times), _fmt(float(times[times.size() - 1]))])
	var cap_share: float = 100.0 * float(cap_n) / float(mcount)
	lines.append("  Päättyminen: nexus %d (%s) | aikakatto %d (%s) | muu %d (%s)" % [
		nexus_n, _pct_text(nexus_n, mcount), cap_n, _pct_text(cap_n, mcount),
		other_n, _pct_text(other_n, mcount)])
	if cap_share > TIMECAP_SHARE:
		lines.append("  " + _flag(flags, "järjestelmä", "aikakatto",
			"TARKISTA: yli %d %% otteluista päättyi aikakattoon — piiritys ei etene" % int(TIMECAP_SHARE)))

	# --- lumipallo ja comeback ---
	lines.append("")
	lines.append("  -- lumipallo ja comeback (kultajohto 10:00 = johtajan yliote jäljessä olevaan) --")
	lines.append("  johto          |   n | johtaja voitti | tuomio")
	var labels: Array = ["alle 5 %", "5-15 %", "yli 15 %"]
	for i in range(3):
		var bn: int = int(bucket_n[i])
		var bw: int = int(bucket_w[i])
		var note := ""
		if i == 2 and bn >= SNOWBALL_MIN_N:
			var bwr: float = 100.0 * float(bw) / float(bn)
			if bwr > SNOWBALL_HIGH:
				note = _flag(flags, "järjestelmä", "lumipallo",
					"TARKISTA: yli 15 %% johto voittaa %.0f %% — lumipallo liian vahva" % bwr)
			elif bwr < SNOWBALL_LOW:
				note = _flag(flags, "järjestelmä", "lumipallo",
					"TARKISTA: yli 15 %% johto voittaa vain %.0f %% — johdolla ei ole merkitystä" % bwr)
		lines.append("  %-14s | %3d | %-14s | %s" % [str(labels[i]), bn, _pct_text(bw, bn), note])
	lines.append("  Comeback: %d/%d (%s) ottelua voitti se joukkue joka oli 10:00 jäljessä." % [
		comeback_n, snow_n, _pct_text(comeback_n, snow_n)])
	if no_snow_data > 0:
		lines.append("  (%d ratkennutta ottelua päättyi ennen 10:00 -> ei lumipallonäytettä)" % no_snow_data)

	# --- ensitapahtumat ---
	lines.append("")
	lines.append("  -- ensitapahtuman tehnyt joukkue -> voitto% --")
	lines.append("  ensiveri %s (n=%d) | ensitorni %s (n=%d) | ensidragon %s (n=%d) | ensibaron %s (n=%d)" % [
		_pct_text(fb_w, fb_n), fb_n, _pct_text(ft_w, ft_n), ft_n,
		_pct_text(fd_w, fd_n), fd_n, _pct_text(fbar_w, fbar_n), fbar_n])

	# --- objektiivit ---
	lines.append("")
	lines.append("  -- objektiivit per ottelu --")
	var mf: float = float(mcount)
	lines.append("  dragoneja %.2f | baroneja %.2f | kristalleja %.2f | superminioneja %.2f" % [
		float(dragons) / mf, float(barons) / mf, float(crystals) / mf, float(supers) / mf])
	var no_baron_share: float = 100.0 * float(no_baron_matches) / mf
	lines.append("  Otteluita joissa Baronia ei kaadettu kertaakaan: %d/%d (%.1f %%)" % [
		no_baron_matches, mcount, no_baron_share])
	if no_baron_share > BARON_SKIP_SHARE:
		lines.append("  " + _flag(flags, "järjestelmä", "baron",
			"TARKISTA: yli %d %% otteluista ilman Baronia — objektiivi ei houkuttele" % int(BARON_SKIP_SHARE)))

	# --- talouden lähteet rooleittain ---
	lines.append("")
	lines.append("  -- talouden lähteet rooleittain (%-osuus roolin kokonaiskullasta) --")
	lines.append("  rooli   | kulta/peli | passi  | CS     | lähi   | tapot  | tornit | jungle | muu")
	var erows: Array = econ.values()
	erows.sort_custom(func(x, y): return _role_rank(str(x["role"])) < _role_rank(str(y["role"])))
	for e_v in erows:
		var e: Dictionary = e_v
		var total: float = maxf(float(e["gold"]), 1.0)
		var passive: float = 100.0 * float(e["passive"]) / total
		var cs: float = 100.0 * float(e["cs"]) / total
		var prox: float = 100.0 * float(e["prox"]) / total
		var kills: float = 100.0 * float(e["kills"]) / total
		var tower: float = 100.0 * float(e["tower"]) / total
		var jungle: float = 100.0 * float(e["jungle"]) / total
		var rest: float = maxf(100.0 - passive - cs - prox - kills - tower - jungle, 0.0)
		lines.append("  %-7s | %10d | %5.0f%% | %5.0f%% | %5.0f%% | %5.0f%% | %5.0f%% | %5.0f%% | %5.0f%%" % [
			str(e["role"]), int(float(e["gold"]) / maxf(float(e["n"]), 1.0)),
			passive, cs, prox, kills, tower, jungle, rest])
	if erows.is_empty():
		lines.append("  Ei talousaineistoa otannassa.")

	# --- CC ja vaimennus ---
	lines.append("")
	lines.append("  -- CC ja vaimennus (per sankari per ottelu; tankki-itemien järkitarkistus) --")
	var ho: float = maxf(float(hero_obs), 1.0)
	lines.append("  kärsitty CC %.1f s | vaimennettu %d | otettu %d | vaimennus/otettu %.0f %%" % [
		cc_sum / ho, int(mit_sum / ho), int(taken_sum / ho),
		100.0 * mit_sum / maxf(taken_sum, 1.0)])
	lines.append("  Ottelu-osion tarkistuskohteita: %d." % (flags.size() - flag_start))


## Raportin kärkilaatikko: ensimmäinen asia jonka lukija näkee. Kokoaa otannan
## koon, keskikeston, nexus-loppujen osuuden, eniten liputetut itemit ja
## sankarit sekä yhden rivin tuomion.
static func _summary_box(lines: Array, results: Array, opts: Dictionary) -> void:
	var snapshots: Array = _snapshots(results)
	var flags: Array = _opt_flags(opts)
	var total_time := 0.0
	var nexus := 0
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		total_time += float(snap.get("elapsed", 0.0))
		if str(snap.get("reason", "")).find("nexus") >= 0:
			nexus += 1
	var n: int = snapshots.size()
	lines.append("=== YHTEENVETO ===")
	# Ladder mittaa rankpareja, ei kokoonpanoja: parimäärä kertoo otannan laajuuden.
	var pairs: int = int(opts.get("pairs", 0))
	if pairs > 0:
		lines.append("  Rankpareja %d (tasoparit, ankkurit ja divisioonaparit)" % pairs)
	lines.append("  Otteluita %d | keskikesto %s | nexus-loppuja %d (%s)" % [
		n, _fmt(total_time / maxf(float(n), 1.0)), nexus, _pct_text(nexus, n)])
	lines.append("  Eniten liputetut itemit:   %s" % _top_flags(flags, "itemi"))
	lines.append("  Eniten liputetut sankarit: %s" % _top_flags(flags, "sankari"))
	lines.append("  Järjestelmähuomioita (talous/objektiivit/roolit): %d" % _count_kind(flags, "järjestelmä"))
	if flags.is_empty():
		lines.append("  TUOMIO: TASAPAINO OK — yksikään mittari ei ylittänyt hälytysrajaa.")
	else:
		lines.append("  TUOMIO: %d TARKISTUSKOHDETTA — yksityiskohdat osioissa alla." % flags.size())


## Kolme eniten liputettua nimeä annetusta liputusluokasta, muodossa "nimi (n)".
static func _top_flags(flags: Array, kind: String) -> String:
	var counts: Dictionary = {}
	for f_v in flags:
		var f: Dictionary = f_v
		if str(f.get("kind", "")) != kind:
			continue
		var name: String = str(f.get("name", "?"))
		counts[name] = int(counts.get(name, 0)) + 1
	var rows: Array = []
	for name_v in counts:
		rows.append({"name": str(name_v), "n": int(counts[name_v])})
	if rows.is_empty():
		return "-"
	rows.sort_custom(func(x, y): return int(x["n"]) > int(y["n"]))
	var parts: Array = []
	for i in range(mini(rows.size(), 3)):
		var r: Dictionary = rows[i]
		parts.append("%s (%d)" % [str(r["name"]), int(r["n"])])
	return ", ".join(PackedStringArray(parts))


## Liputusten lukumäärä luokassa.
static func _count_kind(flags: Array, kind: String) -> int:
	var n := 0
	for f_v in flags:
		var f: Dictionary = f_v
		if str(f.get("kind", "")) == kind:
			n += 1
	return n


## Yleisin lopullinen kykybuild per sankari: näyttää dominoivan maksautuskuvion
## ja sen voitto%:n. Rankit merkkijonona "a1:3 a2:2 ult:3 basic:2 dodge:0".
static func _common_build_table(lines: Array, snapshots: Array) -> void:
	var order: Array = ["a1", "a2", "ult", "basic", "dodge"]
	var per_hero: Dictionary = {}
	for snap_v in snapshots:
		var snap: Dictionary = snap_v
		var winner: int = int(snap.get("winner", -1))
		var decided: bool = winner == 0 or winner == 1
		for hv in snap.get("heroes", []):
			var h: Dictionary = hv
			var build: Dictionary = h.get("skill_build", {})
			if build.is_empty():
				continue
			var id: String = str(h.get("hero_id", "?"))
			var parts: Array = []
			for sname in order:
				parts.append("%s:%d" % [str(sname), int(build.get(sname, 0))])
			var key: String = " ".join(PackedStringArray(parts))
			if not per_hero.has(id):
				per_hero[id] = {"id": id, "total": 0, "builds": {}}
			var ph: Dictionary = per_hero[id]
			ph["total"] = int(ph["total"]) + 1
			var builds: Dictionary = ph["builds"]
			if not builds.has(key):
				builds[key] = {"key": key, "n": 0, "wins": 0, "decided": 0}
			var b: Dictionary = builds[key]
			b["n"] = int(b["n"]) + 1
			if decided:
				b["decided"] = int(b["decided"]) + 1
				if int(h.get("team", -1)) == winner:
					b["wins"] = int(b["wins"]) + 1
	lines.append("")
	lines.append("  -- yleisin lopullinen build per sankari (osuus = kuinka usein sama kuvio) --")
	lines.append("  sankari  | build                            |   n | osuus | voitto% | huomio")
	var ids: Array = per_hero.keys()
	ids.sort()
	for id_v in ids:
		var phd: Dictionary = per_hero[id_v]
		var builds: Dictionary = phd["builds"]
		var best: Dictionary = {}
		for key_v in builds:
			var b: Dictionary = builds[key_v]
			if best.is_empty() or int(b["n"]) > int(best["n"]):
				best = b
		if best.is_empty():
			continue
		var total: int = maxi(int(phd["total"]), 1)
		var share: float = 100.0 * float(best["n"]) / float(total)
		var note := ""
		if int(best["n"]) >= ITEM_MIN_N and share >= BUILD_DOMINANT:
			note = "yksi kuvio dominoi"
		lines.append("  %-8s | %-32s | %3d | %4.0f%% | %-7s | %s" % [
			str(id_v), str(best["key"]), int(best["n"]), share,
			_pct_text(int(best["wins"]), int(best["decided"])), note])
	if ids.is_empty():
		lines.append("  Ei skill build -dataa otannassa.")
