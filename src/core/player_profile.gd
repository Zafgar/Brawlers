class_name PlayerProfile
extends RefCounted
## Yksi pelipaikka: ihminen tai botti. Sisältää laitteen, joukkueen,
## sankarivalinnan ja ottelun aikana kertyvät tilastot.

var index := 0            # 0..7, liittymisjärjestys (määrää tunnusvärin)
var device := -2          # -2 = botti, -1 = näppäimistö + hiiri, >= 0 = peliohjaimen id
var team := 0             # 0 = sininen, 1 = oranssi
var hero_id := ""
var is_bot := false
var display_name := ""
var bot_level := -1        # -1 = käytä Game.bot_level; muuten oma taso (simulaatio)

var stats := {}


func _init() -> void:
	reset_stats()


func reset_stats() -> void:
	stats = {
		"score": 0.0,         # henkilökohtaiset pisteet
		"kos": 0,             # tyrmäykset
		"assists": 0,         # avustukset
		"deaths": 0,          # omat tyrmäytymiset
		"damage": 0.0,        # aiheutettu vahinko (sankareihin/yksiköihin)
		"taken": 0.0,         # otettu vahinko (yhteensä)
		# Otettu vahinko LÄHTEEN mukaan (näkee ottaako AI turhia torni-/mob-osumia):
		"taken_hero": 0.0,    # vihollissankareilta
		"taken_tower": 0.0,   # torneilta/nexukselta
		"taken_minion": 0.0,  # minioneilta
		"taken_neutral": 0.0, # viidakko-olennoilta (leirit/pomo)
		"deaths_tower": 0,    # tornin tappamana kaatunut
		"deaths_neutral": 0,  # viidakko-olennon tappamana kaatunut
		"cc_suffered": 0.0,   # kärsityn CC:n sekunnit (stun+root+freeze)
		"time_dead": 0.0,     # kuolleena vietetty aika sekunteina (respawn-odotus)
		"structure_damage": 0.0,  # vahinko rakennuksiin (tornit/nexus)
		"jungle_damage": 0.0, # vahinko viidakko-olentoihin (leirit/pomo)
		"minion_kills": 0,    # kaadetut minionit (CS)
		"gold": 0,            # MOBA-talouden pohja
		"xp": 0.0,            # kokonais-XP; taso pysähtyy 12:een, telemetria jatkuu
		"level": 1,           # varsinainen ottelutaso (AI-vaikeustaso on eri asia)
		"level_times": {"1": 0.0}, # taso -> ensimmäinen saavuttamisaika
		"healing": 0.0,       # parannettu määrä
		"prevented": 0.0,     # estetty vahinko (kilvet, torjunnat, kuplat)
		"carry_time": 0.0,    # reliikin kantoaika sekunteina
		"pickups": 0,         # reliikin poiminnat
		"carrier_stops": 0,   # viholliskantajan pysäytykset
		"saves": 0,           # joukkuetoverin pelastukset
		# Kykytelemetria: slot ("basic"/"a1"/"a2"/"ult"/"dodge") -> {casts, hits,
		# damage, heal, stun, slow, root, kb}. stun/slow/root ovat kokonais-
		# sekunnit joita kyky aiheutti. Täytetään laiskasti Hero._slot_rec:ssä.
		"passive_gold": 0.0,
		"proximity_gold": 0,
		"last_hit_gold": 0,
		"lane_xp": 0.0,
		"jungle_gold": 0,
		"jungle_xp": 0.0,
		"hero_xp": 0.0,
		# MOBA-analytiikka: strateginen alue, etenemisnopeus ja jungle-clearit.
		"time_top": 0.0,
		"time_bottom": 0.0,
		"time_jungle": 0.0,
		"time_base": 0.0,
		"jungle_clears": 0,
		"jungle_clear_time": 0.0,
		"jungle_active_clear_time": 0.0,
		"jungle_clear_kinds": {}, # kind -> {count, time}
		"gold_milestones": {},    # rajapyykki merkkijonona -> peliaika
		"xp_milestones": {},
		"tower_gold": 0,
		"tower_xp": 0,
		# Neutraalibuffit erotetaan kykyjen omista buffeista. "during" kertoo
		# mitä kantaja sai aikaan buffin ollessa aktiivinen; bonus/heal mittaa
		# buffin suoraan tuottaman lisäarvon.
		"red_pickups": 0,
		"blue_pickups": 0,
		"baron_buffs": 0,
		"dragon_buffs": 0,
		"red_buff_time": 0.0,
		"blue_buff_time": 0.0,
		"baron_buff_time": 0.0,
		"dragon_buff_time": 0.0,
		"red_bonus_damage": 0.0,
		"blue_bonus_damage": 0.0,
		"red_healing": 0.0,
		"damage_during_red": 0.0,
		"damage_during_blue": 0.0,
		"damage_during_baron": 0.0,
		"damage_during_dragon": 0.0,
		"structure_during_red": 0.0,
		"structure_during_blue": 0.0,
		"structure_during_baron": 0.0,
		"structure_during_dragon": 0.0,
		"kos_during_red": 0,
		"kos_during_blue": 0,
		"kos_during_baron": 0,
		"kos_during_dragon": 0,
		"gold_during_red": 0.0,
		"gold_during_blue": 0.0,
		"gold_during_baron": 0.0,
		"gold_during_dragon": 0.0,
		"xp_during_red": 0.0,
		"xp_during_blue": 0.0,
		"xp_during_baron": 0.0,
		"xp_during_dragon": 0.0,
		"slots": {},
	}


func color() -> Color:
	return Palette.player(index)


func add_score(points: float) -> void:
	stats.score += points


func is_human() -> bool:
	return not is_bot


func hero_name() -> String:
	if hero_id == "":
		return "?"
	return HeroDef.get_def(hero_id)["name"]
