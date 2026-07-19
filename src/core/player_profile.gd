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
		"taken": 0.0,         # otettu vahinko
		"structure_damage": 0.0,  # vahinko rakennuksiin (tornit/nexus)
		"jungle_damage": 0.0, # vahinko viidakko-olentoihin (leirit/pomo)
		"minion_kills": 0,    # kaadetut minionit (CS)
		"healing": 0.0,       # parannettu määrä
		"prevented": 0.0,     # estetty vahinko (kilvet, torjunnat, kuplat)
		"carry_time": 0.0,    # reliikin kantoaika sekunteina
		"pickups": 0,         # reliikin poiminnat
		"carrier_stops": 0,   # viholliskantajan pysäytykset
		"saves": 0,           # joukkuetoverin pelastukset
		# Kykytelemetria: slot ("basic"/"a1"/"a2"/"ult"/"dodge") -> {casts, hits,
		# damage, heal, stun, slow, root, kb}. stun/slow/root ovat kokonais-
		# sekunnit joita kyky aiheutti. Täytetään laiskasti Hero._slot_rec:ssä.
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
