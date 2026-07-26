class_name SoundDefs
extends RefCounted
## Äänirekisteri: YKSI paikka, joka kertoo jokaisesta tehosteesta kaiken.
##
## Aiemmin sama tieto oli hajallaan neljässä joukossa (UI_SOUNDS, ALERT_SOUNDS,
## AMBIENT_SOUNDS, SOUND_COOLDOWNS) eikä äänekkyyttä ohjattu mitenkään. Nyt
## avain -> määrittely kertoo kategorian, ja kategoria johtaa väylän, soitinpoolin,
## äänekkyystavoitteen, toistorajan, prioriteetin, sävelvaihtelun ja sen onko
## ääni positionaalinen.
##
## Kenttä       Merkitys
##   cat        kategoria (alla CATEGORIES)
##   gain       avainkohtainen trimmi dB — hienosäätö kategorian sisällä
##   cooldown   ms: sama avain ei käynnisty tätä tiheämmin
##   prio       0..3: kuka saa varastaa soittimen keneltä (3 = tärkein)
##   pitch_var  ± puolisävelaskelta satunnaista sävelvaihtelua
##   positional maailmakoordinaatti vaimentaa ja panoroi äänen
##
## Puuttuvat kentät täydentyvät kategorian oletuksista, joten uusi avain toimii
## heti järkevästi pelkällä {"cat": "..."} -merkinnällä.

## Kategorioiden oletukset. rms = lyhyen aikavälin äänekkyystavoite dBFS,
## johon jokainen puskuri normalisoidaan synteesin jälkeen. voices = montako
## saman kategorian ääntä saa soida yhtä aikaa.
const CATEGORIES := {
	"combat": {
		"bus": "SFX", "pool": "world", "rms": -12.0, "gain": 0.0,
		"cooldown": 45, "prio": 1, "pitch_var": 0.55, "positional": true, "voices": 10,
	},
	"ability": {
		"bus": "SFX", "pool": "world", "rms": -13.0, "gain": 0.0,
		"cooldown": 60, "prio": 2, "pitch_var": 0.40, "positional": true, "voices": 8,
	},
	"structure": {
		"bus": "SFX", "pool": "world", "rms": -12.5, "gain": 0.0,
		"cooldown": 100, "prio": 2, "pitch_var": 0.30, "positional": true, "voices": 5,
	},
	"ui": {
		"bus": "SFX_UI", "pool": "ui", "rms": -16.0, "gain": 0.0,
		"cooldown": 28, "prio": 2, "pitch_var": 0.25, "positional": false, "voices": 4,
	},
	"econ": {
		"bus": "SFX_UI", "pool": "ui", "rms": -15.0, "gain": 0.0,
		"cooldown": 45, "prio": 2, "pitch_var": 0.20, "positional": false, "voices": 3,
	},
	"alert": {
		"bus": "SFX_ALERT", "pool": "alert", "rms": -10.0, "gain": 0.0,
		"cooldown": 200, "prio": 3, "pitch_var": 0.15, "positional": false, "voices": 3,
	},
	"objective": {
		"bus": "SFX_ALERT", "pool": "alert", "rms": -11.0, "gain": 0.0,
		"cooldown": 180, "prio": 3, "pitch_var": 0.20, "positional": false, "voices": 3,
	},
	"ambient": {
		"bus": "SFX_AMBIENT", "pool": "ambient", "rms": -24.0, "gain": 0.0,
		"cooldown": 1800, "prio": 0, "pitch_var": 0.30, "positional": true, "voices": 4,
	},
}

## Käytetään jos avainta ei löydy rekisteristä lainkaan (ei saisi tapahtua —
## audio_probe.py kaatuu tähän — mutta peli ei jää mykäksi virheen takia).
const UNKNOWN_CAT := "combat"

const DEFS := {
	# --- Valikot ja lukemat: kuiva väylä, ei kaikuhäntää ---
	"ui_move": {"cat": "ui", "gain": -3.0, "cooldown": 32, "prio": 1},
	"ui_ok": {"cat": "ui"},
	"ui_back": {"cat": "ui", "gain": -1.0},
	"ui_open": {"cat": "ui", "gain": 1.0, "cooldown": 90},
	"ui_lock": {"cat": "ui", "gain": 1.0, "cooldown": 60},
	"ui_deny": {"cat": "ui", "cooldown": 120},
	"ui_team": {"cat": "ui"},
	"count_tick": {"cat": "ui", "cooldown": 60, "pitch_var": 0.0},
	"count_go": {"cat": "ui", "gain": 2.0, "cooldown": 300, "prio": 3},
	"score": {"cat": "ui", "gain": -1.0, "cooldown": 40},

	# --- Erän rytmi: harvat, aina kuuluvat julistukset ---
	"round_start": {"cat": "alert", "cooldown": 600},
	"round_win": {"cat": "alert", "cooldown": 800},
	"match_win": {"cat": "alert", "gain": 1.0, "cooldown": 1200},
	"moba_start": {"cat": "alert", "gain": 1.0, "cooldown": 1200},
	"minion_wave": {"cat": "alert", "gain": -4.0, "cooldown": 2000, "prio": 2},
	"heartbeat": {"cat": "alert", "gain": -6.0, "cooldown": 700, "prio": 2},

	# --- Perustaistelu: fyysiset iskut ---
	"hit": {"cat": "combat", "cooldown": 38},
	"swing": {"cat": "combat", "gain": -3.0, "cooldown": 40, "prio": 0},
	"slam": {"cat": "combat", "gain": 1.0},
	"quake": {"cat": "combat", "gain": 2.0, "cooldown": 120},
	"rock": {"cat": "combat"},
	"ko": {"cat": "combat", "gain": 2.0, "cooldown": 150, "prio": 2},
	"bump": {"cat": "combat", "gain": -2.0, "cooldown": 70},
	"pop": {"cat": "combat", "gain": -3.0, "cooldown": 45},
	"dash": {"cat": "combat", "gain": -3.0, "cooldown": 60, "prio": 0},
	"blade": {"cat": "combat", "cooldown": 45},
	"disc": {"cat": "combat", "cooldown": 50},
	"respawn": {"cat": "ability", "cooldown": 300, "prio": 3},

	# --- Minionit: tiheimmät tapahtumat, pidetään sankarien alla ---
	"minion_melee": {"cat": "combat", "gain": -5.0, "cooldown": 85, "prio": 0},
	"minion_ranged": {"cat": "combat", "gain": -5.0, "cooldown": 90, "prio": 0},
	"minion_impact": {"cat": "combat", "gain": -6.0, "cooldown": 75, "prio": 0},
	"minion_down": {"cat": "combat", "gain": -4.0, "cooldown": 80, "prio": 0},

	# --- Viidakon leirit ---
	"jungle_small_attack": {"cat": "combat", "gain": -2.0, "cooldown": 110, "prio": 0},
	"jungle_small_down": {"cat": "combat", "gain": -1.0, "cooldown": 120},
	"red_guardian_attack": {"cat": "combat", "cooldown": 150},
	"red_guardian_impact": {"cat": "combat", "cooldown": 110},
	"red_guardian_down": {"cat": "combat", "gain": 1.0, "cooldown": 300, "prio": 2},
	"blue_guardian_attack": {"cat": "combat", "cooldown": 150},
	"blue_guardian_impact": {"cat": "combat", "cooldown": 110},
	"blue_guardian_down": {"cat": "combat", "gain": 1.0, "cooldown": 300, "prio": 2},
	"red_buff": {"cat": "objective", "cooldown": 400},
	"blue_buff": {"cat": "objective", "cooldown": 400},

	# --- Dragon: siivekäs myrsky ---
	"dragon_attack": {"cat": "combat", "cooldown": 210},
	"dragon_impact": {"cat": "combat", "cooldown": 180},
	"dragon_slam_warning": {"cat": "combat", "gain": 1.0, "cooldown": 500, "prio": 2},
	"dragon_slam": {"cat": "combat", "gain": 2.0, "cooldown": 400, "prio": 2},
	"dragon_warning": {"cat": "objective", "cooldown": 900},
	"dragon_spawn": {"cat": "objective", "gain": 1.0, "cooldown": 1200},
	"dragon_enrage": {"cat": "objective", "gain": 1.0, "cooldown": 900},
	"dragon_collapse": {"cat": "objective", "cooldown": 900},
	"dragon_defeat": {"cat": "objective", "gain": 1.0, "cooldown": 1200},

	# --- Baron: hidas void-paine ---
	"baron_attack": {"cat": "combat", "cooldown": 210},
	"baron_impact": {"cat": "combat", "cooldown": 180},
	"baron_slam_warning": {"cat": "combat", "gain": 1.0, "cooldown": 500, "prio": 2},
	"baron_slam": {"cat": "combat", "gain": 2.0, "cooldown": 400, "prio": 2},
	"baron_warning": {"cat": "objective", "cooldown": 900},
	"baron_spawn": {"cat": "objective", "gain": 1.0, "cooldown": 1200},
	"baron_enrage": {"cat": "objective", "gain": 1.0, "cooldown": 900},
	"baron_collapse": {"cat": "objective", "cooldown": 900},
	"baron_defeat": {"cat": "objective", "gain": 1.0, "cooldown": 1200},

	# --- Rakenteet: kylmää arcane-tekniikkaa, raskaat matalat hännät ---
	"tower_lock": {"cat": "structure", "gain": -4.0, "cooldown": 180, "prio": 1},
	"tower_fire": {"cat": "structure", "cooldown": 120},
	"tower_impact": {"cat": "structure", "cooldown": 100},
	"tower_guard": {"cat": "structure", "cooldown": 420},
	"tower_crack": {"cat": "structure", "gain": 1.0, "cooldown": 300},
	"tower_destroy": {"cat": "objective", "gain": 1.0, "cooldown": 900},
	"nexus_laser": {"cat": "structure", "cooldown": 220},
	"nexus_guard": {"cat": "structure", "cooldown": 420},
	"nexus_crack": {"cat": "structure", "gain": 1.0, "cooldown": 300},
	"nexus_exposed": {"cat": "objective", "gain": 2.0, "cooldown": 2000},
	"nexus_destroy": {"cat": "objective", "gain": 2.0, "cooldown": 3000},

	# --- Talous ja poiminta ---
	"pickup": {"cat": "econ", "cooldown": 60},
	"drop": {"cat": "econ", "cooldown": 60},
	"mark": {"cat": "econ", "gain": -2.0, "cooldown": 70, "positional": true},

	# --- Yleiset kyvyt (jaettu useamman sankarin kesken) ---
	"guard_up": {"cat": "ability"},
	"dome_up": {"cat": "ability", "cooldown": 200},
	"fire": {"cat": "ability"},
	"fire_whoosh": {"cat": "ability"},
	"inferno": {"cat": "ability", "gain": 1.0, "cooldown": 300},
	"bow": {"cat": "ability", "gain": -2.0, "cooldown": 55},
	"bow_charged": {"cat": "ability", "cooldown": 120},
	"arrow_rain": {"cat": "ability", "cooldown": 250},
	"heal": {"cat": "ability", "cooldown": 120},
	"light": {"cat": "ability", "cooldown": 70},
	"blessing": {"cat": "ability", "cooldown": 160},
	"shield": {"cat": "ability", "cooldown": 90},
	"note": {"cat": "ability", "gain": -2.0, "cooldown": 45},
	"bass": {"cat": "ability", "cooldown": 60},
	"crescendo": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"smoke": {"cat": "ability", "gain": -2.0, "cooldown": 120},
	"water": {"cat": "ability", "cooldown": 60},
	"wave": {"cat": "ability", "cooldown": 150},
	"blink": {"cat": "ability", "cooldown": 70},
	"zap": {"cat": "ability", "cooldown": 55},
	"thunder": {"cat": "ability", "gain": 1.0, "cooldown": 300},
	"root": {"cat": "ability", "cooldown": 120},
	"vine": {"cat": "ability", "cooldown": 70},
	"thorns": {"cat": "ability", "cooldown": 120},
	"ult": {"cat": "ability", "gain": 1.0, "cooldown": 300, "prio": 3},
	"ult_ready": {"cat": "alert", "gain": -3.0, "cooldown": 900, "positional": false},

	# --- Luma: lasikellot ja pehmeä nouseva sointu ---
	"luma_pulse": {"cat": "ability", "cooldown": 55},
	"luma_bloom": {"cat": "ability", "cooldown": 120},
	"luma_shield": {"cat": "ability", "cooldown": 150},
	"luma_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},

	# --- Ember: sytytys, pyyhkäisy, myrskyroihu ---
	"ember_bolt": {"cat": "ability", "gain": -2.0, "cooldown": 55},
	"ember_pool": {"cat": "ability", "cooldown": 150},
	"ember_impact": {"cat": "ability", "cooldown": 80},
	"ember_wave": {"cat": "ability", "cooldown": 150},
	"ember_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},

	# --- Sankarikohtaiset ultit ---
	"hush_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"volt_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"tide_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"quill_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"boulder_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"bramble_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},
	"obsidian_ult": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},

	# --- Titan: metallinen isku, painava runko ---
	"titan_punch": {"cat": "combat", "cooldown": 60},
	"titan_grab": {"cat": "combat", "cooldown": 150},
	"titan_throw": {"cat": "combat", "cooldown": 150},
	"titan_launch": {"cat": "combat", "gain": 1.0, "cooldown": 200},
	"titan_brace": {"cat": "ability", "cooldown": 200},
	"titan_rage": {"cat": "ability", "gain": 1.0, "cooldown": 400, "prio": 3},

	# --- Salvo: kranaatit, mortarit, hydraulinen bunkkeri ---
	"salvo_grenade": {"cat": "combat", "gain": -2.0, "cooldown": 60},
	"salvo_mortar_launch": {"cat": "ability", "cooldown": 120},
	"salvo_mortar_impact": {"cat": "combat", "gain": 1.0, "cooldown": 120},
	"salvo_bunker": {"cat": "ability", "cooldown": 300},
	"salvo_bunker_open": {"cat": "ability", "cooldown": 200},
	"salvo_rocket_launch": {"cat": "ability", "cooldown": 200},
	"salvo_rocket_impact": {"cat": "combat", "gain": 2.0, "cooldown": 150},

	# --- Ympäristökerrokset: pitkiä ja hyvin hiljaisia ---
	"ambient_jungle": {"cat": "ambient", "cooldown": 1800},
	"ambient_river": {"cat": "ambient", "cooldown": 1800},
	"ambient_lane": {"cat": "ambient", "cooldown": 1800},
	"ambient_brush": {"cat": "ambient", "gain": -2.0, "cooldown": 1600},
	"ambient_blue_base": {"cat": "ambient", "cooldown": 1800},
	"ambient_orange_base": {"cat": "ambient", "cooldown": 1800},
	"ambient_baron_pit": {"cat": "ambient", "gain": 1.0, "cooldown": 2200},
	"ambient_dragon_pit": {"cat": "ambient", "gain": 1.0, "cooldown": 2200},

	# --- Kauppa ---
	"shop_open": {"cat": "ui", "gain": 1.0, "cooldown": 90},
	"shop_close": {"cat": "ui", "cooldown": 90},
	"shop_move": {"cat": "ui", "gain": -3.0, "cooldown": 32, "prio": 1},
	"shop_buy": {"cat": "econ", "cooldown": 90},
	"shop_sell": {"cat": "econ", "gain": -1.0, "cooldown": 90},
	"shop_deny": {"cat": "econ", "gain": -1.0, "cooldown": 140},
	"shop_legendary": {"cat": "econ", "gain": 2.0, "cooldown": 400, "prio": 3},

	# --- Baronin artefakti ---
	"artifact_drop": {"cat": "objective", "cooldown": 600, "positional": true},
	"artifact_pickup": {"cat": "econ", "gain": 1.0, "cooldown": 400, "positional": true},
	"artifact_lost": {"cat": "objective", "cooldown": 600, "positional": true},

	# --- Vartiolyhty ---
	"ward_place": {"cat": "econ", "gain": -1.0, "cooldown": 200, "positional": true},
	"ward_expire": {"cat": "econ", "gain": -4.0, "cooldown": 400, "positional": true},
	"ward_spot": {"cat": "ui", "gain": -4.0, "cooldown": 900, "prio": 1},

	# --- Häive ---
	"stealth_in": {"cat": "ability", "gain": -2.0, "cooldown": 200},
	"stealth_out": {"cat": "ability", "gain": -3.0, "cooldown": 200},
	"stealth_strike": {"cat": "combat", "gain": 2.0, "cooldown": 150, "prio": 2},

	# --- Eteneminen ---
	"rank_up": {"cat": "econ", "gain": -2.0, "cooldown": 160, "positional": true},
	"ult_unlock": {"cat": "alert", "gain": -1.0, "cooldown": 800},

	# --- Piiritys estetty ---
	"siege_blocked": {"cat": "structure", "gain": -2.0, "cooldown": 500},
	"siege_immune": {"cat": "structure", "gain": -2.0, "cooldown": 500},

	# --- Kristalli ---
	"crystal_rise": {"cat": "objective", "cooldown": 900, "positional": true},
	"crystal_break": {"cat": "objective", "gain": 1.0, "cooldown": 900, "positional": true},

	# --- Superminionit ---
	"super_wave": {"cat": "alert", "gain": -2.0, "cooldown": 2000},

	# --- Paluukanavointi ---
	"recall_start": {"cat": "ability", "gain": -3.0, "cooldown": 300},
	"recall_done": {"cat": "ability", "cooldown": 300},
	"recall_cancel": {"cat": "ability", "gain": -2.0, "cooldown": 300},

	# --- Lähderegen (hiljainen, toistuva) ---
	"fountain_regen": {"cat": "ability", "gain": -9.0, "cooldown": 900, "prio": 0},

	# --- Tyrmäyssarjat ---
	"first_blood": {"cat": "alert", "gain": 1.0, "cooldown": 3000},
	"multi_kill_2": {"cat": "alert", "cooldown": 1200},
	"multi_kill_3": {"cat": "alert", "gain": 1.0, "cooldown": 1200},
	"multi_kill_4": {"cat": "alert", "gain": 2.0, "cooldown": 1200},

	# --- Ranked-ylennykset ja aula ---
	"promo_div_up": {"cat": "alert", "cooldown": 600},
	"promo_tier_up": {"cat": "alert", "gain": 2.0, "cooldown": 1500},
	"promo_slot_win": {"cat": "alert", "gain": -2.0, "cooldown": 250},
	"promo_slot_loss": {"cat": "alert", "gain": -2.0, "cooldown": 250},
	"promo_failed": {"cat": "alert", "cooldown": 900},
	"promo_demote": {"cat": "alert", "cooldown": 900},
	"promo_shield": {"cat": "alert", "gain": -1.0, "cooldown": 600},
	"rank_hub_open": {"cat": "ui", "gain": 1.0, "cooldown": 300},
	"rank_hub_move": {"cat": "ui", "gain": -3.0, "cooldown": 32, "prio": 1},
	"rank_hub_lp": {"cat": "ui", "gain": -8.0, "cooldown": 55, "prio": 0},
	"rank_hub_confirm": {"cat": "ui", "gain": 1.0, "cooldown": 200},

	# --- Kaira: repeämä ja laavalammikot ---
	"kaira_drill": {"cat": "combat", "gain": -1.0, "cooldown": 50},
	"kaira_charge": {"cat": "ability", "cooldown": 200},
	"kaira_slam": {"cat": "ability", "gain": 1.0, "cooldown": 200},
	"kaira_fissure": {"cat": "ability", "gain": 2.0, "cooldown": 400, "prio": 3},
	"kaira_lava": {"cat": "ability", "gain": -2.0, "cooldown": 220},

	# --- Torq: koukku ja magneettikaivo ---
	"torq_hammer": {"cat": "combat", "gain": -1.0, "cooldown": 50},
	"torq_hook": {"cat": "ability", "cooldown": 150},
	"torq_hook_hit": {"cat": "combat", "gain": 1.0, "cooldown": 150},
	"torq_lock": {"cat": "ability", "cooldown": 200},
	"torq_well": {"cat": "ability", "gain": 2.0, "cooldown": 400, "prio": 3},

	# --- Vesper: merkintä, teloitus ja kisko ---
	"vesper_bolt": {"cat": "combat", "gain": -3.0, "cooldown": 45},
	"vesper_spike": {"cat": "ability", "gain": -1.0, "cooldown": 120},
	"vesper_mark": {"cat": "ability", "gain": -2.0, "cooldown": 90},
	"vesper_execute": {"cat": "ability", "gain": 1.0, "cooldown": 150},
	"vesper_kill": {"cat": "ability", "gain": 1.0, "cooldown": 200},
	"vesper_rail": {"cat": "ability", "gain": 2.0, "cooldown": 400, "prio": 3},

	# --- Myria: orkidea ja kukinta ---
	"myria_wisp": {"cat": "combat", "gain": -3.0, "cooldown": 45},
	"myria_plant": {"cat": "ability", "gain": -1.0, "cooldown": 120},
	"myria_drift": {"cat": "ability", "gain": -3.0, "cooldown": 120},
	"myria_bloom": {"cat": "ability", "gain": 1.0, "cooldown": 180},
	"myria_garden": {"cat": "ability", "gain": 2.0, "cooldown": 400, "prio": 3},
}


## Rakentaa täydet määrittelyt kerran käynnistyksessä: avain -> kaikki kentät.
## AudioMgr pitää tulosta muistissa, joten play() ei allokoi mitään.
static func resolve_all() -> Dictionary:
	var out := {}
	for key in DEFS:
		out[key] = resolve(String(key))
	return out


static func resolve(key: String) -> Dictionary:
	var raw: Dictionary = DEFS.get(key, {})
	var cat: String = String(raw.get("cat", UNKNOWN_CAT))
	var base: Dictionary = CATEGORIES.get(cat, CATEGORIES[UNKNOWN_CAT])
	var out: Dictionary = base.duplicate()
	out["cat"] = cat
	for field in raw:
		if String(field) == "cat":
			continue
		out[field] = raw[field]
	return out


## Kategorian oletukset tuntemattomalle avaimelle (peli ei jää mykäksi).
static func fallback() -> Dictionary:
	var out: Dictionary = CATEGORIES[UNKNOWN_CAT].duplicate()
	out["cat"] = UNKNOWN_CAT
	return out


static func voice_cap(cat: String) -> int:
	var c: Dictionary = CATEGORIES.get(cat, CATEGORIES[UNKNOWN_CAT])
	return int(c["voices"])
