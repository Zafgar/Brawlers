class_name Hero
extends CharacterBody2D
## Kaikkien sankarien kantaluokka. Hoitaa liikkeen, kykyjen ajoituksen,
## kestävyyden, tilavaikutukset, tyrmäyksen ja paluun kentälle.
##
## Sankarikohtaiset kyvyt toteutetaan aliluokissa ylikirjoittamalla:
##   _basic(dir), _ability1(dir), _ability2(dir), _dodge_action(dir),
##   _ultimate(dir), _passive_update(delta)
## Latautuvia perushyökkäyksiä varten voi ylikirjoittaa _attack_control().

signal knocked_out(hero, source)

const ACCEL := 2600.0
const KB_FRICTION := 1400.0          # työntöimpulssin hiipumiskitka (px/s²)
const REGEN_DELAY := 5.0
const REGEN_PER_SEC := 14.0
const RESPAWN_TIME := 4.5
const CARRY_SPEED_MULT := 0.82
const ASSIST_WINDOW := 5.0
const INPUT_BUFFER := 0.15           # syötepuskuri: kyky laukeaa vaikka nappi painettiin hieman etuajassa
const GROUND_AIM_CURSOR_SPEED := 720.0

# Lähderegen (MOBA): oman lähteen äärellä sanctuaryssa HP ja resurssi palautuvat
# erittäin nopeasti — tukikohtakäynti on lyhyt mutta kannattava.
const FOUNTAIN_RADIUS := 300.0       # lähteen vaikutusalue lähdepisteestä
const FOUNTAIN_HEAL_FRAC := 0.14     # parannus osuutena max HP:sta sekunnissa
const FOUNTAIN_RES_FRAC := 0.30      # resurssipalautus osuutena res_maxista sekunnissa

# Paluukanavointi (recall): pidä nappi pohjassa paikallaan — teleportti kotiin.
const RECALL_TIME := 3.5

# Kumulatiivinen MOBA-XP-käyrä. Level 12 vaatii 12 000 XP:tä: nykyisellä
# 18 sekunnin wave-rytmillä normaali farmaus osuu ottelun viimeiseen vaiheeseen.
const MAX_LEVEL := 12
const LEVEL_XP_THRESHOLDS := [
	0.0, 450.0, 1050.0, 1800.0, 2650.0, 3600.0,
	4650.0, 5800.0, 7050.0, 8400.0, 9850.0, 12000.0,
]
const HP_GROWTH_PER_LEVEL := 0.032
# Vahinkokasvun budjetti (1.0-profiilin sankari tasolla 12, steps = 11):
#   yleinen kasvu   1 + 11 * 0.015 = 1.165
#   spell/melee     1 + 11 * 0.020 = 1.220
#   yhteensä        1.165 * 1.22  ≈ 1.42  -> ~+42 % vahinkoa (tavoite 40–45 %).
# DAMAGE_GROWTH_PER_LEVEL laskettiin 0.018 -> 0.015 kun spell/melee-kasvu
# lisättiin, jottei kokonaiskasvu karkaa käsistä.
const DAMAGE_GROWTH_PER_LEVEL := 0.015
const SPELL_GROWTH_PER_LEVEL := 0.02     # a1/a2/ult-vahingon kasvu per taso
const MELEE_GROWTH_PER_LEVEL := 0.02     # perushyökkäyksen kasvu per taso
const REGEN_GROWTH_PER_LEVEL := 0.03     # mana/energia-regenin kasvu per taso

# Kykyrankit: perus/a1/a2/väistö ovat käytettävissä rankilla 0 (perusvoima),
# rankit 1–3 vahvistavat niitä. Ulti on LUKOSSA rankilla 0: ranki N vaatii
# tason ULT_RANK_LEVELS[N-1] (avaus aikaisintaan tasolla 4, sitten 8 ja 12).
const RANK_CAP := 3
const ULT_RANK_LEVELS := [4, 8, 12]
const RANK_POWER_STEP := 0.10            # perus/a1/a2/väistö: +10 % voimaa/ranki
const ULT_RANK_POWER_STEP := 0.12        # ulti: +12 %/ranki rankin 1 jälkeen
const RANK_CD_STEP := 0.06               # a1/a2/väistö: -6 % jäähdytys/ranki
const SLOT_NAMES := {"basic": "PERUS", "a1": "KYKY 1", "a2": "KYKY 2",
	"dodge": "VÄISTÖ", "ult": "ULTI"}

var arena = null                    # Arena, asetetaan ennen add_childia
var profile: PlayerProfile = null
var controller = null               # DeviceInput tai BotBrain (sama rajapinta)
var hero_id := ""
var team := 0
# Ei-pelaajayksikkö (viidakko-olento, minioni, rakennus). Jätetään pois
# pelaajakeskeisistä järjestelmistä (kamera, muodostelmat, tuen kohteet).
var is_unit := false
var regen_disabled := false         # rakennukset/minionit eivät palaudu

var max_hp := 200.0
var hp := 200.0
var base_speed := 320.0
var radius := 26.0
var level := 1
var level_damage_mult := 1.0
var level_spell_mult := 1.0         # tasokasvu a1/a2/ult-vahingolle
var level_melee_mult := 1.0         # tasokasvu perushyökkäykselle
var _regen_level_mult := 1.0        # tasokasvu mana/energia-regenille
var _level_base_max_hp := 200.0

var alive := true
var respawn_timer := 0.0
var iframes := 0.0
var since_damage := 99.0

var aim := Vector2.RIGHT
var move_dir := Vector2.ZERO
var carrying := false               # kantaa reliikkiä

var ult_charge := 0.0               # 0..100
var cd := {"basic": 0.0, "a1": 0.0, "a2": 0.0, "dodge": 0.0}
var cd_max := {"basic": 0.5, "a1": 8.0, "a2": 8.0, "dodge": 4.0}

# Kykyrankit ja -pisteet. Piste per taso (+1 aloituspiste) = 12 pistettä;
# paikkoja on 4 * 3 + 3 = 15, joten kaikkea ei saa täyteen -> oikeita valintoja.
var ability_ranks := {"basic": 0, "a1": 0, "a2": 0, "dodge": 0, "ult": 0}
var skill_points := 0
var _base_cd_max := {}              # cd_max-pohja rankkien jäähdytysalennukselle
var _spend_locked := {}             # kehitystilassa painetut napit: ei castia ennen vapautusta
var _pending_dodge_shield := 0.0    # väistön kilpiarkkityyppi: kilpi syöksyn päätyttyä

# Suojat ja tilavaikutukset
var shield_hp := 0.0
var shield_timer := 0.0
var shield_source: Hero = null
var shield_slot := ""                # antajan kykypaikka (telemetria: kilven arvo)
var slow_timer := 0.0
var slow_factor := 1.0
var haste_timer := 0.0
var haste_factor := 1.0
var root_timer := 0.0
var stun_timer := 0.0
var silence_timer := 0.0            # ei voi käyttää kykyjä (a1/a2/ult/väistö); voi liikkua
var reflect_timer := 0.0            # kiviho: heijasta osa otetusta vahingosta takaisin lähisankarille
var reflect_factor := 0.0           # heijastettu osuus (0..1)
var reflect_slot := ""              # heijastuksen kirjaava kykypaikka (telemetria)
var _applying_reflect := false      # estää heijastuksen ketjuuntumisen (kaksi kiviho-sankaria)
var cc_immune_timer := 0.0          # immuuni CC:lle (stun/root/slow/silence); esim. Lancen syöksy
var mark_timer := 0.0               # merkitty kohde ottaa lisävahinkoa (Scout)
var mark_amp := 1.25                # merkin vahinkokerroin (asetetaan apply_markissa)
var kb_resist := 0.0                # 0..1, tankeille

# Lipasjärjestelmä (valinnainen, esim. Scoutin konekivääri). ammo < 0 = ei
# lipasta -> ei piirretä. hero_visual näyttää patruunat ja lataustilan.
var ammo := -1
var ammo_max := 0
var reloading := false

# Suuntatorjunta (Bastionin kilpivalli, geneerinen mekaniikka)
var guard_timer := 0.0
var guard_absorb := 0.7
var guard_arc_deg := 80.0
var guard_radius := 0.0             # > 0 = piirrä leveä kilpivalli tälle säteelle
var guard_slot := ""                # torjunnan kykypaikka (telemetria: torjunnan arvo)

# Tartunta (Titaani pitää kiinni): kohde ei törmää muihin sankareihin oteen
# aikana, jottei se estä/tönäise kantajaa. Ote vapautuu itsestään jos sitä ei
# virkistetä (esim. kantaja kuolee tai pudottaa otteen).
var grabbed_by = null
var _grab_hold_timer := 0.0

# Väistösyöksy
var dash_timer := 0.0
var dash_velocity := Vector2.ZERO
var _phase_walls := false          # syöksy sisäseinien läpi (Tide) — reunat rajataan

# Työntö/veto-impulssikanava. Töytäisyt kulkevat OMASSA kanavassaan erillään
# ohjausliikkeestä: aiemmin ne lisättiin suoraan velocityyn, jonka move_toward
# (ACCEL) söi ~0.2 sekunnissa — kaikki liikuttamiskyvyt tuntuivat rikkinäisiltä.
var kb_velocity := Vector2.ZERO
var _control_velocity := Vector2.ZERO

var visual: HeroVisual = null
var _recent_damagers: Array = []    # [{hero, time}]
var _ult_ready_announced := false
var _buf := {"a1": 0.0, "a2": 0.0, "ult": 0.0, "dodge": 0.0}  # syötepuskurin ajastimet
var _heartbeat_t := 0.0             # matalan HP:n sydämenlyöntivaroituksen ajastin
var _deny_cd := 0.0                 # "ei resurssia" -äänen debounce
var _dodge_was_cooling := false     # väistön jäähdytys -> valmis siirtymän havaitsemiseen

# Tähtäys: osa kyvyistä tähdätään pitämällä nappi pohjassa (tähtäysviiva
# näkyy) ja laukaistaan vapautettaessa. Latauskyvyt (Quill) näyttävät myös viivan.
var _aiming_slot := ""              # "" = ei tähtäystä, muuten "a1"/"a2"
var aim_guide = null                # AimGuide-lapsisolmu
var _aim_active := false            # piirretäänkö tähtäysviiva juuri nyt
var _aim_len := 420.0
var _aim_charge := 0.0              # 0..1, vaikuttaa viivan paksuuteen/kirkkauteen
var _aim_color := Color.WHITE
var _aim_radius := 0.0              # > 0 = piirrä maamaalin todellinen vaikutusalue
var _aim_width := 0.0               # > 0 = piirrä suuntakyvylle todellinen osumakäytävä
var _ground_aim_offset := Vector2.ZERO
var _ground_cast_target := Vector2.ZERO
var _ground_cast_valid := false

# Vaikeustason kertoimet (vain epäreilu botti poikkeaa 1.0:sta); setup() lukee
# nämä bottiohjaimelta ja soveltaa combatissa.
var dmg_out_mult := 1.0
var dmg_in_mult := 1.0
var ult_gain_mult := 1.0

# Resurssijärjestelmä (valinnainen sankarikohtaisesti). res_type "" = ei
# resurssia -> pelkkä jäähdytys kuten ennen. "mana"/"energy" palautuvat
# ajan myötä, "rage" rakentuu taistelusta. Kyvyt voivat maksaa resurssia.
var res_type := ""
var res := 0.0
var res_max := 100.0
var res_regen := 0.0               # passiivinen palautuminen/s (mana, energy)
var res_cost := {"basic": 0.0, "a1": 0.0, "a2": 0.0, "dodge": 0.0}
var _channel_slot := ""            # kanavoitava kyky pohjassa (esim. kilpi)
var _channel_locked := ""          # resurssi loppui kesken pidon -> lukossa napin vapautukseen asti
var _cast_context := ""            # mikä kykypaikka juuri suorittaa (telemetria)
var _rage_idle := 0.0              # aika viime taistelutoiminnasta (rage-vaimeneminen)

# Kenttäbuffit (blue/red). blue = resurssin nopea palautuminen, red = +vahinko
# ja elämän palautuminen. Aika jäljellä sekunneissa.
var blue_buff := 0.0
var red_buff := 0.0
# Jungle-buffien omat lähdemerkit. red_buff/blue_buff säilyvät yhteisinä
# mekaniikka-ajastimina myös sankarikyvyille; nämä tekevät raportista tarkan.
var red_camp_buff := 0.0
var blue_camp_buff := 0.0
var baron_buff := 0.0
var dragon_buff := 0.0

# Pidä-ja-vapauta ultimate (esim. Prisman alue-esikatselu) ja säde-overlay
# (Prisman kanavoitavat säteet). Overlay piirretään AimGuidessa.
var _ult_holding := false
var _beam_active := false
var _beam_len := 0.0
var _beam_heal := false

# Void-assassin (Rift): pinot tähän sankariin ja ajanpysäytys. void_stacker on
# assassiini joka pinoja asetti (räjäytyksen palkinnot menevät sille).
var void_stacks := 0
var void_stack_timer := 0.0
var void_stacker: Hero = null

# Lähderegen: visuaalitikin ja popupin kuristus + parannuksen kertymä popupiin.
var _fountain_fx_t := 0.0
var _fountain_popup_t := 0.0
var _fountain_heal_accum := 0.0

# Paluukanavointi: 0 = ei kanavoida, muuten kulunut aika 0..RECALL_TIME.
var _recall_t := 0.0
var _recall_fx_t := 0.0
# Kaksintaistelumerkit (Lance): kasautuvat kohteeseen; 3 merkkiä -> viimeistely.
var duel_marks := 0
var duel_mark_timer := 0.0
var duel_marker: Hero = null
var frozen := 0.0                  # ajanpysäytys: > 0 = ei voi liikkua/toimia
var piloting := false              # ohjaa ohjattavaa ammusta (Salvon raketti): maan alla, ei toimi


func setup(p_arena, p_profile: PlayerProfile, p_controller) -> void:
	arena = p_arena
	profile = p_profile
	controller = p_controller
	hero_id = p_profile.hero_id
	team = p_profile.team

	var def := HeroDef.get_def(hero_id)
	max_hp = def["hp"]
	_level_base_max_hp = max_hp
	hp = max_hp
	base_speed = def["speed"]
	for slot in ["basic", "a1", "a2", "dodge"]:
		cd_max[slot] = HeroDef.cooldown(hero_id, slot)

	# Sankari voi määrittää resurssin (mana/energy/rage) ja säätää cd_max.
	_setup_resource()

	# Bottien vaikeustason kertoimet (taso 6 = epäreilu huijaa).
	if controller != null and controller.is_bot():
		dmg_out_mult = controller.damage_mult
		dmg_in_mult = controller.damage_taken_mult
		ult_gain_mult = controller.ult_gain_mult
		base_speed *= controller.speed_mult
		for slot in cd_max:
			cd_max[slot] = float(cd_max[slot]) * controller.cooldown_mult

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)

	aim_guide = AimGuide.new()
	aim_guide.hero = self
	add_child(aim_guide)

	visual = HeroVisual.new()
	visual.hero = self
	add_child(visual)

	# Game.start_match nollaa profilen, mutta tämä tekee myös suorista testeistä
	# deterministisiä ja erottaa ottelutason AI:n vaikeustasosta.
	level = 1
	profile.stats.level = level
	profile.stats.level_times = {"1": 0.0}
	_apply_level_stats(false)

	# Kykyrankit: cd_max-pohja otetaan talteen VASTA kaikkien säätöjen jälkeen
	# (_setup_resource + botin cooldown_mult), joten rankkien jäähdytysalennus
	# ei sodi sankarikohtaisten cd_max-asetusten kanssa. Jokainen saa yhden
	# aloituspisteen tasolla 1; botit käyttävät sen heti.
	_base_cd_max = cd_max.duplicate()
	if not is_unit:
		skill_points = 1
		if controller != null and controller.is_bot():
			_bot_spend_points()


static func xp_for_level(target_level: int) -> float:
	var idx := clampi(target_level, 1, MAX_LEVEL) - 1
	return float(LEVEL_XP_THRESHOLDS[idx])


func xp_level_fraction() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	var floor_xp := xp_for_level(level)
	var ceiling_xp := xp_for_level(level + 1)
	return clampf((float(profile.stats.xp) - floor_xp) /
		maxf(ceiling_xp - floor_xp, 1.0), 0.0, 1.0)


func xp_in_current_level() -> float:
	return maxf(float(profile.stats.xp) - xp_for_level(level), 0.0)


func xp_needed_for_next_level() -> float:
	if level >= MAX_LEVEL:
		return 0.0
	return xp_for_level(level + 1) - xp_for_level(level)


## Kokonais-XP jatkaa kasvuaan myös max-tasolla, jotta raportti kertoo todellisen
## farmausvauhdin ja käyrää voidaan myöhemmin kalibroida ilman kadonnutta dataa.
func gain_xp(amount: float) -> float:
	if amount <= 0.0 or profile == null or is_unit:
		return 0.0
	profile.stats.xp += amount
	while level < MAX_LEVEL and float(profile.stats.xp) >= xp_for_level(level + 1):
		level += 1
		skill_points += 1   # jokainen taso antaa yhden kykypisteen
		profile.stats.level = level
		var reached_at := 0.0
		if arena != null:
			reached_at = float(arena.match_elapsed)
		profile.stats.level_times[str(level)] = reached_at
		_apply_level_stats(true)
	# Botti käyttää uudet pisteet heti prioriteettilistansa mukaan.
	if skill_points > 0 and controller != null and controller.is_bot():
		_bot_spend_points()
	return amount


func _apply_level_stats(show_feedback: bool) -> void:
	var old_max := maxf(max_hp, 1.0)
	var steps := float(level - 1)
	# Sankarikohtainen skaalausprofiili (ks. _level_scaling): hypercarryt saavat
	# ison spell/melee-kertoimen, tankit ison hp:n mutta matalan vahingon jne.
	var prof := _level_scaling()
	var hp_f: float = prof.get("hp", 1.0)
	var dmg_f: float = prof.get("damage", 1.0)
	var spell_f: float = prof.get("spell", 1.0)
	var melee_f: float = prof.get("melee", 1.0)
	var regen_f: float = prof.get("regen", 1.0)
	max_hp = _level_base_max_hp * (1.0 + steps * HP_GROWTH_PER_LEVEL * hp_f)
	level_damage_mult = 1.0 + steps * DAMAGE_GROWTH_PER_LEVEL * dmg_f
	level_spell_mult = 1.0 + steps * SPELL_GROWTH_PER_LEVEL * spell_f
	level_melee_mult = 1.0 + steps * MELEE_GROWTH_PER_LEVEL * melee_f
	_regen_level_mult = 1.0 + steps * REGEN_GROWTH_PER_LEVEL * regen_f
	if show_feedback and alive:
		# Level-up antaa vain kasvaneen max-HP:n erotuksen, ei ilmaista täysparannusta.
		hp = minf(max_hp, hp + max_hp - old_max)
		if arena != null:
			arena.popup(global_position + Vector2(0, -78), "LEVEL %d" % level,
				Palette.GOLD, 20)
			Fx.ring(arena, global_position, Palette.with_alpha(Palette.GOLD, 0.9),
				radius + 32.0, 0.45, 6.0)
			if not Game.simulating and profile.is_human():
				AudioMgr.play("blessing", 0.04, -3.0, global_position)
	else:
		hp = minf(hp, max_hp)


## Tasoskaalauksen profiili. Ylikirjoitetaan sankarissa: kertoimet skaalaavat
## per-taso-kasvua (1.0 = normaali). Avaimet: hp, damage (yleinen), spell
## (a1/a2/ult), melee (perus), regen (mana/energia-palautuminen).
func _level_scaling() -> Dictionary:
	return {"hp": 1.0, "damage": 1.0, "spell": 1.0, "melee": 1.0, "regen": 1.0}


# --- Kykyrankit ---

## Kykypaikan rankin voimakerroin: perus/a1/a2/väistö +10 %/ranki; ulti
## +12 %/ranki rankin 1 jälkeen (ranki 1 = ultin perustaso).
func rank_power(slot: String) -> float:
	var rank: int = ability_ranks.get(slot, 0)
	if slot == "ult":
		return 1.0 + ULT_RANK_POWER_STEP * float(maxi(rank - 1, 0))
	return 1.0 + RANK_POWER_STEP * float(rank)


func ult_unlocked() -> bool:
	return int(ability_ranks.ult) >= 1


## Voiko kykypaikan rankata: piste jäljellä, ranki alle katon ja ultille
## tasovaatimus (seuraava ranki N vaatii tason ULT_RANK_LEVELS[N-1] = 4/8/12).
func can_rank(slot: String) -> bool:
	if is_unit or skill_points <= 0 or not ability_ranks.has(slot):
		return false
	var rank: int = ability_ranks[slot]
	if rank >= RANK_CAP:
		return false
	if slot == "ult" and level < int(ULT_RANK_LEVELS[rank]):
		return false
	return true


## Käyttää kykypisteen: nostaa rankia, laskee a1/a2/väistön jäähdytystä
## pohja-arvosta ja kutsuu sankarin _on_rank_up-koukun. Palauttaa onnistumisen.
func rank_up(slot: String) -> bool:
	if not can_rank(slot):
		return false
	skill_points -= 1
	ability_ranks[slot] = int(ability_ranks[slot]) + 1
	var new_rank: int = ability_ranks[slot]
	# Jäähdytysalennus lasketaan aina setupin lopussa otetusta pohjasta, joten
	# se ei kertaudu eikä sodi sankarien omien cd_max-asetusten kanssa.
	if (slot == "a1" or slot == "a2" or slot == "dodge") and _base_cd_max.has(slot):
		cd_max[slot] = float(_base_cd_max[slot]) * (1.0 - RANK_CD_STEP * float(new_rank))
	_on_rank_up(slot, new_rank)
	# Lopullinen build talteen raporttia varten (turvallinen lisäavain).
	if profile != null:
		profile.stats["skill_build"] = ability_ranks.duplicate()
	if arena != null and not Game.simulating and is_inside_tree():
		var label := "ULTI AVATTU!" if slot == "ult" and new_rank == 1 \
			else "%s RANK %d" % [str(SLOT_NAMES.get(slot, slot)), new_rank]
		arena.popup(global_position + Vector2(0, -64), label, Palette.GOLD, 16)
		Fx.ring(arena, global_position, Palette.with_alpha(Palette.GOLD, 0.85),
			radius + 24.0, 0.4, 4.0)
		if profile != null and profile.is_human():
			AudioMgr.play("blessing", 0.04, -5.0, global_position)
	# Täysi lataus odotti vain avausta -> "ulti valmis" heti avattaessa.
	if slot == "ult" and new_rank == 1 and ult_charge >= 100.0:
		_announce_ult_ready()
	return true


## Sankarikohtainen signatuuribonus rankin noustessa (ylikirjoitettavissa).
func _on_rank_up(_slot: String, _new_rank: int) -> void:
	pass


## Lähteen kokonaisvahinkokerroin: yleinen tasokasvu, kykytyypin tasokasvu
## (perus = melee, a1/a2/ult = spell) ja toimivan kykypaikan ranki. Kykypaikka
## luetaan tarttuvasta kontekstista (sama malli kuin punainen/sininen buffi).
func combat_damage_mult() -> float:
	var mult := level_damage_mult
	if _cast_context == "basic":
		mult *= level_melee_mult
	elif _cast_context == "a1" or _cast_context == "a2" or _cast_context == "ult":
		mult *= level_spell_mult
	if _cast_context != "":
		mult *= rank_power(_cast_context)
	return mult


# --- Bottien kykypisteet ---

## Botin rankkausjärjestys (ylikirjoitetaan sankarissa). Ulti otetaan aina
## ensin jos mahdollista; muuten ensimmäinen listan paikka jolla on tilaa.
func _bot_skill_order() -> Array:
	return ["ult", "a1", "a2", "basic", "dodge"]


## Käyttää botin kaikki vapaat kykypisteet. Toimii myös simulaatiossa
## (rank_up ei näytä palautetta kun Game.simulating).
func _bot_spend_points() -> void:
	if controller == null or not controller.is_bot():
		return
	while skill_points > 0:
		var slot := ""
		if can_rank("ult"):
			slot = "ult"
		else:
			for cand in _bot_skill_order():
				if can_rank(str(cand)):
					slot = str(cand)
					break
		if slot == "" or not rank_up(slot):
			break


# --- Kykypisteiden käyttö (kehitystila: pidä D-pad ylös / T + kyvyn nappi) ---

func _spend_mode_active() -> bool:
	if controller == null or controller.is_bot():
		return false
	if not controller.has_method("spend_held"):
		return false
	return bool(controller.spend_held())


## Kehitystilan syötteet: kyvyn napin painallus käyttää kykypisteen castin
## sijaan. Puskurit tyhjennetään ja pohjassa olevat napit lukitaan vapautukseen
## asti, ettei pisteen käyttö vuoda castiksi kun tila päästetään irti.
func _handle_spend_inputs() -> void:
	_buf.a1 = 0.0
	_buf.a2 = 0.0
	_buf.ult = 0.0
	_buf.dodge = 0.0
	if _channel_slot != "":
		var ch := _channel_slot
		_channel_slot = ""
		_channel_end(ch)
	_ult_holding = false
	if controller.attack_held():
		_spend_locked["basic"] = true
	if controller.ability1_held():
		_spend_locked["a1"] = true
	if controller.ability2_held():
		_spend_locked["a2"] = true
	if controller.ult_held():
		_spend_locked["ult"] = true
	if controller.attack_just_pressed():
		_try_spend("basic")
	if controller.ability1_just():
		_try_spend("a1")
	if controller.ability2_just():
		_try_spend("a2")
	if controller.dodge_just():
		_try_spend("dodge")
	if controller.ult_just():
		_try_spend("ult")


## Pisteen käyttö + kuuluva "ei onnistu" -vihje jos rankkaus ei ole sallittu.
func _try_spend(slot: String) -> void:
	if rank_up(slot):
		return
	if _deny_cd <= 0.0:
		AudioMgr.play("ui_back", 0.05, -8.0)
		_deny_cd = 0.45


## Palauttaa true jos slotin nappi on yhä pohjassa kehitystilan jäljiltä.
## Esto vapautuu vasta kun nappi irrotetaan — pisteen käyttö ei vuoda castiksi.
func _spend_release_locked(slot: String) -> bool:
	if not bool(_spend_locked.get(slot, false)):
		return false
	var held := false
	match slot:
		"basic":
			held = bool(controller.attack_held())
		"a1":
			held = bool(controller.ability1_held())
		"a2":
			held = bool(controller.ability2_held())
		"ult":
			held = bool(controller.ult_held())
	if held:
		return true
	_spend_locked[slot] = false
	return false


# --- Väistön kehitys (arkkityypit) ---

## Väistön kehityksen arkkityyppi: "haste" / "shield" / "cleanse" / "phase".
## Sankari ylikirjoittaa kittiinsä sopivan. Ranki 0 = pelkkä syöksy.
func _dodge_evolution() -> String:
	return "haste"


## Väistön käyttöhetkellä: rankin mukainen utility arkkityypin mukaan. Efektit
## pidetään maltillisina — väistö on ensisijaisesti liikkumiskyky. Kutsutaan
## _act("dodge")-kontekstissa, joten esim. hasten buffisekunnit kirjautuvat
## väistölle telemetriassa.
func _apply_dodge_evolution() -> void:
	var rank: int = ability_ranks.get("dodge", 0)
	if rank <= 0:
		return
	match _dodge_evolution():
		"haste":
			# Vauhtipyrähdys syöksyn jälkeen; ranki 3 puhdistaa myös hidasteet.
			apply_haste(1.08 if rank == 1 else 1.14, 1.0 if rank == 1 else 1.4)
			if rank >= 3:
				slow_timer = 0.0
				slow_factor = 1.0
		"shield":
			# Kilpi: rankeilla 1–2 syöksyn päätyttyä, rankilla 3 jo syöksyn alussa.
			var frac := 0.06 + 0.04 * float(rank - 1)
			if rank >= 3:
				_grant_dodge_shield(frac)
			else:
				_pending_dodge_shield = frac
		"cleanse":
			# Puhdistus: hidasteet; ranki 2 myös juurrutukset; ranki 3 lyhyt CC-suoja.
			slow_timer = 0.0
			slow_factor = 1.0
			if rank >= 2:
				root_timer = 0.0
			if rank >= 3:
				cc_immune_timer = maxf(cc_immune_timer, 0.4)
		"phase":
			# Pidempi/aavemaisempi syöksy (matka = nopeus * kesto). Ranki 3 menee
			# sisäseinien läpi vain tämän syöksyn ajan; _end_phase palauttaa
			# törmäyksen syöksyn päättyessä (Tidellä faasi on aina, se säilyy).
			if dash_timer > 0.0:
				dash_timer *= 1.10
				if rank >= 2:
					iframes = maxf(iframes, dash_timer + 0.08)
				if rank >= 3 and not _phase_walls:
					_phase_walls = true
					set_collision_mask_value(1, false)


## Väistökilpi suoraan (ilman add_shieldin rank-kerrointa — arkkityypin arvot
## ovat jo rankin mukaiset). Imetty vahinko kirjautuu väistön telemetriaan.
func _grant_dodge_shield(frac: float) -> void:
	shield_hp = maxf(shield_hp, max_hp * frac)
	shield_timer = 1.5
	shield_source = self
	shield_slot = "dodge"
	AudioMgr.play("shield", 0.06, -4.0, global_position)
	Fx.ring(arena, global_position, Palette.SHIELD, radius + 14.0, 0.35)


func _physics_process(delta: float) -> void:
	if arena == null or arena.state != arena.State.PLAY:
		velocity = Vector2.ZERO
		_aim_active = false
		_aiming_slot = ""
		_channel_slot = ""
		_ult_holding = false
		_beam_active = false
		return
	if not alive:
		_aim_active = false
		_aiming_slot = ""
		_channel_slot = ""
		_ult_holding = false
		_beam_active = false
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return

	# Ajanpysäytys (Riftin ulti): jäätynyt sankari ei liiku eikä toimi, eivätkä
	# sen ajastimet kulu (aika pysähtynyt). Vain jäätymisajastin vähenee.
	if frozen > 0.0:
		frozen -= delta
		velocity = Vector2.ZERO
		_aim_active = false
		_aiming_slot = ""
		_channel_slot = ""
		_beam_active = false
		_ult_holding = false
		return

	controller.update(self, delta)
	_tick_status(delta)
	_tick_resource(delta)

	# Ohjaustila (Salvon ohjattava raketti): sankari on maan alla — ei liiku eikä
	# käytä muita kykyjä, mutta ohjain päivittyy (jotta raketti ohjautuu) ja
	# _passive_update ajetaan (siellä raketti liikkuu). Muu toiminta ohitetaan.
	if piloting:
		velocity = Vector2.ZERO
		_aim_active = false
		_aiming_slot = ""
		_recall_t = 0.0   # ohjaustila keskeyttää paluukanavoinnin
		_passive_update(delta)
		# Ohjaustila palaa ennen fysiikkaprosessin normaalia ajastinpäivitystä.
		# Vähennä siirtymä-iframe tässä, ettei bunkkerista tule vahingossa täysin
		# immuunia koko ohjuksen lennon ajaksi.
		iframes = maxf(iframes - delta, 0.0)
		return

	# Tartunnan itsevapautus: jos otetta ei virkistetä (kantaja kuoli, pudotti
	# otteen tms.), palauta törmäys ettei kohde jää haamuksi.
	if grabbed_by != null:
		_grab_hold_timer -= delta
		if _grab_hold_timer <= 0.0 or not is_instance_valid(grabbed_by) or not grabbed_by.alive:
			release_grabbed()

	# Tähtäys
	var aim_input: Vector2 = controller.aim_vector()
	if aim_input.length() > 0.2:
		aim = aim_input.normalized()
	elif move_dir.length() > 0.2:
		aim = move_dir.normalized()

	# Liike
	var mv := Vector2.ZERO
	if root_timer <= 0.0 and stun_timer <= 0.0:
		mv = controller.move_vector()
	var speed := base_speed * slow_factor * haste_factor * _move_speed_mult()
	if carrying:
		speed *= CARRY_SPEED_MULT
	if arena.map != null:
		speed *= arena.map.terrain_mult(global_position)  # esim. vesi hidastaa

	if dash_timer > 0.0:
		dash_timer -= delta
		velocity = dash_velocity
		_control_velocity = dash_velocity
		# Syöksy ohittaa impulssit; impulssi hiipuu silti taustalla eikä jää odottamaan.
		kb_velocity = kb_velocity.move_toward(Vector2.ZERO, KB_FRICTION * delta)
	else:
		# Ohjausliike ja työntöimpulssi eri kanavissa: move_toward ei enää syö
		# töytäisyä, vaan impulssi hiipuu omalla kitkallaan (KB_FRICTION).
		# Tainnutettu/juurtunut liikkuu silti töytäisystä (mv on niillä nolla).
		_control_velocity = _control_velocity.move_toward(mv * speed, ACCEL * delta)
		kb_velocity = kb_velocity.move_toward(Vector2.ZERO, KB_FRICTION * delta)
		velocity = _control_velocity + kb_velocity
		if _phase_walls:
			_end_phase()   # syöksy loppui -> palauta seinätörmäys
		# Väistön kilpiarkkityyppi (ranki 1–2): kilpi annetaan syöksyn päätyttyä.
		if _pending_dodge_shield > 0.0:
			_grant_dodge_shield(_pending_dodge_shield)
			_pending_dodge_shield = 0.0

	if arena.map != null:
		velocity += arena.map.conveyor_push(global_position)
	move_and_slide()
	move_dir = mv

	# Seinien-läpi-syöksy: rajaa vain kartan reunoihin (sisäseinät ohitetaan,
	# mutta kentältä ei pääse ulos).
	if _phase_walls and arena.map != null:
		var ph: Vector2 = arena.map.size() / 2.0
		global_position = Vector2(
			clampf(global_position.x, -ph.x + radius, ph.x - radius),
			clampf(global_position.y, -ph.y + radius, ph.y - radius))

	# Turvaverkko: jos hahmo on jostain syystä paennut kentän ulkopuolelle
	# (fysiikan tunnelointi, teleportti reunaseinän yli, kova töytäisy), vedä se
	# takaisin kentälle ettei se jää loppuotteluksi jumiin reunan taakse.
	if arena.map != null:
		var fh: Vector2 = arena.map.size() / 2.0
		if absf(global_position.x) > fh.x or absf(global_position.y) > fh.y:
			global_position = arena.map.clamp_to_field(global_position, radius + 6.0)
			velocity = Vector2.ZERO
			kb_velocity = Vector2.ZERO
			_control_velocity = Vector2.ZERO

	# Syötepuskurit: painallukset jäävät hetkeksi muistiin, joten kyky laukeaa
	# heti kun jäähdytys sallii vaikka nappi painettiin hiukan etuajassa tai
	# tainnutuksen aikana. Tämä tekee ohjaimesta paljon luotettavamman.
	_buffer_inputs(delta)
	_aim_active = false   # nollataan joka framessa; kyvyt/lataus aktivoivat tarvittaessa

	# Toiminnot
	if _spend_mode_active():
		# Kehitystila: pidä D-pad ylös (näppäimistöllä T) ja paina kyvyn nappia
		# käyttääksesi kykypisteen. Painallukset eivät vuoda casteiksi.
		_handle_spend_inputs()
		_aiming_slot = ""
	elif stun_timer <= 0.0:
		# Perushyökkäyksen konteksti telemetriaan. Tallenna/palauta tarttuva
		# konteksti ettei perushyökkäys pyyhi kesken olevaa kykyä (esim.
		# kanavoitava ult, jonka viivästynyt vahinko tulee awaitin takaa).
		var _prev_ctx := _cast_context
		var _atk_locked := _spend_release_locked("basic")
		_act("basic")
		_attack_control(
			controller.attack_held() and not _atk_locked,
			controller.attack_just_pressed() and not _atk_locked,
			controller.attack_just_released(),
			aim, delta)
		_act_end()
		_cast_context = _prev_ctx
		# Kyvyt toimivat myös reliikkiä kannettaessa (kuten väistökin).
		# Tähdättävät kyvyt (pito -> vapautus) hoidetaan _run_ability_slotissa.
		# VAIMENNUS (silence) estää kyvyt (a1/a2/ult/väistö), perus sallitaan.
		if silence_timer <= 0.0:
			_run_ability_slot("a1", 1, delta)
			_run_ability_slot("a2", 2, delta)
		# Ultimate: välitön (oletus) tai pidä-ja-vapauta (esim. Prisman alue).
		if silence_timer <= 0.0 and _ult_is_held() and not controller.is_bot():
			if _ult_holding:
				if _ult_ground_targeted():
					_aim_active = true
					_aim_color = Palette.glow(Palette.GOLD, 1.4)
					_aim_charge = 1.0
					_update_ult_ground_aim(delta)
				else:
					# Viivaesikatselu ultille (esim. Quillin tähdättävä supernuoli).
					var ul: float = _ult_preview_line()
					if ul > 0.0:
						_aim_active = true
						_aim_len = ul
						_aim_radius = 0.0
						_aim_width = _ult_preview_width()
						_aim_color = Palette.glow(Palette.GOLD, 1.4)
						_aim_charge = 1.0
				if controller.ult_released():
					if _ult_ground_targeted():
						_ground_cast_target = global_position + _ground_aim_offset
						_ground_cast_valid = true
					if ult_charge >= 100.0 and ult_unlocked():
						_fire_ult()
					_ground_cast_valid = false
					_ult_holding = false
			elif controller.ult_held() and ult_charge >= 100.0 and ult_unlocked() \
					and not _spend_release_locked("ult"):
				_ult_holding = true
				if _ult_ground_targeted():
					_begin_ult_ground_aim()
		elif silence_timer <= 0.0 and _buf.ult > 0.0 and ult_charge >= 100.0 \
				and ult_unlocked():
			_buf.ult = 0.0
			_fire_ult()
		if silence_timer <= 0.0 and _buf.dodge > 0.0 and cd.dodge <= 0.0:
			_buf.dodge = 0.0
			cd.dodge = cd_max.dodge * (1.5 if carrying else 1.0)
			var dodge_dir := mv if mv.length() > 0.2 else aim
			_act("dodge")
			_log_cast("dodge")
			_dodge_action(dodge_dir.normalized())
			_apply_dodge_evolution()
			_act_end()
		if carrying and controller.drop_just():
			arena.relic.drop_from_carrier(false)
	else:
		_aiming_slot = ""   # tainnutus keskeyttää tähtäyksen

	# Paluukanavointi ja lähderegen (vain MOBA). Ajetaan ennen normaalia
	# palautumista, jotta teleportti ja lähdeparannus näkyvät samassa framessa.
	_update_recall(delta)
	_fountain_regen(delta)

	# Palautuminen
	since_damage += delta
	if not regen_disabled and since_damage > REGEN_DELAY and hp < max_hp:
		hp = minf(hp + REGEN_PER_SEC * delta, max_hp)
	if red_buff > 0.0 and hp < max_hp:
		var before_red_hp := hp
		hp = minf(hp + 9.0 * delta, max_hp)   # Red: jatkuva elämän palautuminen
		if red_camp_buff > 0.0:
			profile.stats.red_healing += hp - before_red_hp

	# Matalan HP:n varoitus omalle (ei-botti) sankarille: tup-tup kiihtyy ja
	# voimistuu HP:n laskiessa. Ei-positionaalinen (henkilökohtainen varoitus).
	_heartbeat_t = maxf(_heartbeat_t - delta, 0.0)
	if not controller.is_bot() and hp < max_hp * 0.30 and _heartbeat_t <= 0.0:
		var sev: float = clampf((max_hp * 0.30 - hp) / (max_hp * 0.30), 0.0, 1.0)
		AudioMgr.play("heartbeat", 0.03, lerpf(-8.0, 1.0, sev))
		_heartbeat_t = lerpf(0.62, 0.34, sev)
	_deny_cd = maxf(_deny_cd - delta, 0.0)

	# Latautumiset (+ väistön valmistumisen hiljainen äänivihje)
	for slot in cd:
		if cd[slot] > 0.0:
			cd[slot] -= delta
	if _dodge_was_cooling and cd.dodge <= 0.0 and not controller.is_bot():
		AudioMgr.play("count_tick", 0.0, -14.0)
	_dodge_was_cooling = cd.dodge > 0.0
	# Passiivinen ultilataus on hidas pohjavire (täyteen ~2:47 tyhjän panttina):
	# ulti ansaitaan taistelusta, ei odottamalla. (Oli 2.2/s = täysi 45 s -> spam.)
	add_ult(delta * 0.6)

	_passive_update(delta)
	iframes = maxf(iframes - delta, 0.0)


func _tick_status(delta: float) -> void:
	# Pidä ajastimet nollassa niiden päätyttyä. Negatiivinen arvo paisutti
	# telemetriaa seuraavalla apply_slow/apply_haste-kutsulla, koska koko
	# negatiivinen väli tulkittiin uutena vaikutusaikana.
	slow_timer = maxf(slow_timer - delta, 0.0)
	if slow_timer <= 0.0:
		slow_factor = 1.0
	haste_timer = maxf(haste_timer - delta, 0.0)
	if haste_timer <= 0.0:
		haste_factor = 1.0
	root_timer = maxf(root_timer - delta, 0.0)
	stun_timer = maxf(stun_timer - delta, 0.0)
	silence_timer = maxf(silence_timer - delta, 0.0)
	reflect_timer = maxf(reflect_timer - delta, 0.0)
	cc_immune_timer = maxf(cc_immune_timer - delta, 0.0)
	mark_timer = maxf(mark_timer - delta, 0.0)
	guard_timer = maxf(guard_timer - delta, 0.0)
	shield_timer -= delta
	if shield_timer <= 0.0:
		shield_hp = 0.0
	blue_buff = maxf(blue_buff - delta, 0.0)
	red_buff = maxf(red_buff - delta, 0.0)
	if red_camp_buff > 0.0:
		profile.stats.red_buff_time += minf(delta, red_camp_buff)
	if blue_camp_buff > 0.0:
		profile.stats.blue_buff_time += minf(delta, blue_camp_buff)
	if baron_buff > 0.0:
		profile.stats.baron_buff_time += minf(delta, baron_buff)
	if dragon_buff > 0.0:
		profile.stats.dragon_buff_time += minf(delta, dragon_buff)
	red_camp_buff = maxf(red_camp_buff - delta, 0.0)
	blue_camp_buff = maxf(blue_camp_buff - delta, 0.0)
	baron_buff = maxf(baron_buff - delta, 0.0)
	dragon_buff = maxf(dragon_buff - delta, 0.0)
	void_stack_timer = maxf(void_stack_timer - delta, 0.0)
	if void_stack_timer <= 0.0 and void_stacks > 0:
		void_stacks = 0
		void_stacker = null
	duel_mark_timer = maxf(duel_mark_timer - delta, 0.0)
	if duel_mark_timer <= 0.0 and duel_marks > 0:
		duel_marks = 0
		duel_marker = null


## Lukee ohjaimen kykypainallukset puskuriin ja vanhentaa vanhat painallukset.
## Painallus säilyy INPUT_BUFFER-sekuntia, joten se ei huku framejen välissä.
func _buffer_inputs(delta: float) -> void:
	_buf.a1 = maxf(float(_buf.a1) - delta, 0.0)
	_buf.a2 = maxf(float(_buf.a2) - delta, 0.0)
	_buf.ult = maxf(float(_buf.ult) - delta, 0.0)
	_buf.dodge = maxf(float(_buf.dodge) - delta, 0.0)
	if controller.ability1_just():
		_buf.a1 = INPUT_BUFFER
	if controller.ability2_just():
		_buf.a2 = INPUT_BUFFER
	if controller.ult_just():
		_buf.ult = INPUT_BUFFER
	if controller.dodge_just():
		_buf.dodge = INPUT_BUFFER


## Käsittelee yhden kykypaikan. Tähdättävä kyky (pito -> vapautus) näyttää
## tähtäysviivan ja laukeaa vasta vapautettaessa; muut laukeavat heti
## syötepuskurin kautta. Botit käyttävät aina välitöntä laukaisua.
func _run_ability_slot(slot: String, num: int, delta: float) -> void:
	var is_bot: bool = controller.is_bot()
	# Kehitystilassa painettu nappi ei saa aloittaa tähtäystä/castia ennen kuin
	# se on välillä vapautettu (muuten piste-painallus vuotaisi kyvyksi).
	if not is_bot and _spend_release_locked(slot):
		return
	var held: bool = controller.ability1_held() if num == 1 else controller.ability2_held()
	var released: bool = controller.ability1_released() if num == 1 else controller.ability2_released()

	# Kanavoitava kyky: pito ylläpitää vaikutusta (esim. Bastionin energiakilpi).
	# Kun resurssi loppuu kesken pidon, kyky lukittuu: se ei käynnisty uudelleen
	# ennen kuin nappi vapautetaan (muuten regen-tippa käynnistäisi sen heti
	# uudelleen -> säde/kilpi "toimisi" nollaresurssilla).
	if not is_bot and slot in _channeled_slots():
		if _channel_slot == slot:
			if held and res > 0.0:
				_act(slot)
				_channel_tick(slot, delta)
				_act_end()
			else:
				_channel_slot = ""
				_channel_end(slot)
				if held and res <= 0.0:
					_channel_locked = slot
		else:
			if not held and _channel_locked == slot:
				_channel_locked = ""
			if _channel_slot == "" and held and cd[slot] <= 0.0 \
					and res > 0.0 and _channel_locked != slot:
				_channel_slot = slot
				if visual != null:
					visual.cast_ability(slot)
				_log_cast(slot)
				_act(slot)
				_channel_tick(slot, delta)
				_act_end()
		return

	# Tähdättävä kyky: pito tähtää, vapautus laukaisee.
	if not is_bot and slot in _aimed_slots():
		if _aiming_slot == slot:
			_aim_active = true
			_aim_color = hero_color()
			_aim_charge = 1.0
			_aim_width = 0.0
			if slot in _ground_targeted_slots():
				_update_ground_aim(slot, delta)
			else:
				_aim_len = _aim_range(slot)
				_aim_radius = 0.0
			_aim_hold(slot, delta)
			if released:
				if slot in _ground_targeted_slots():
					_ground_cast_target = global_position + _ground_aim_offset
					_ground_cast_valid = true
				_aiming_slot = ""
				if cd[slot] <= 0.0 and _can_afford(slot):
					cd[slot] = cd_max[slot]
					_spend(slot)
					_cast_slot(slot)
				_ground_cast_valid = false
		elif _aiming_slot == "" and held and cd[slot] <= 0.0 and _can_afford(slot):
			# _aim_begin voi keskeyttää tähtäyksen aloituksen (palauttaa false),
			# esim. Titaanin tartunta jos edessä ei ole kohdetta.
			if _aim_begin(slot):
				_aiming_slot = slot
				if slot in _ground_targeted_slots():
					_begin_ground_aim(slot)
		return

	# Välitön (puskuroitu) laukaisu.
	if _buf[slot] > 0.0 and cd[slot] <= 0.0 and _can_afford(slot):
		_buf[slot] = 0.0
		cd[slot] = cd_max[slot]
		_spend(slot)
		_cast_slot(slot)
	elif not is_bot and _buf[slot] > 0.0 and cd[slot] <= 0.0 and not _can_afford(slot):
		# Jäähdytys valmis mutta resurssi ei riitä -> kuuluva "ei onnistu" -vihje
		# (aiemmin painallus katosi täysin äänettä). Jäähdytys-odotus jätetään
		# puskurin hoidettavaksi, joten sitä ei kuittausäänellä hämmennetä.
		if _deny_cd <= 0.0:
			AudioMgr.play("ui_back", 0.05, -8.0)
			_deny_cd = 0.45


func _cast_slot(slot: String) -> void:
	if visual != null:
		visual.cast_ability(slot)
	_act(slot)
	_log_cast(slot)
	if slot == "a1":
		_ability1(aim)
	else:
		_ability2(aim)
	_act_end()


## Yhteinen kyvyn omistajuusmerkki: sankarimuoto + joukkue + paikallisen P1–P4-väri.
func ability_signature(visual_family: String, size := 90.0, dir := Vector2.ZERO) -> void:
	if arena == null:
		return
	var cast_dir: Vector2 = aim if dir.length() <= 0.1 else dir
	var owner := Palette.team(team)
	if profile != null and not profile.is_bot:
		owner = profile.color()
	Fx.cast_signature(arena, global_position, cast_dir, visual_family,
		hero_color(), owner, Palette.team(team), size)


## Paikallinen tuntopalaute vain kyvyn omalle ohjaimelle; näppäimistö ja botit ohitetaan.
func controller_rumble(weak: float, strong: float, duration: float) -> void:
	if profile != null and not profile.is_bot and profile.device >= 0:
		Input.start_joy_vibration(profile.device, clampf(weak, 0.0, 1.0),
			clampf(strong, 0.0, 1.0), maxf(duration, 0.01))


## Ylikirjoita palauttamaan kykypaikat ("a1"/"a2") jotka tähdätään pitämällä
## nappi pohjassa. Oletuksena tyhjä -> kaikki kyvyt laukeavat heti painettaessa.
func _aimed_slots() -> Array:
	return []


## Tähtäysviivan pituus kyvylle (ylikirjoitettavissa sankarikohtaisesti).
func _aim_range(_slot: String) -> float:
	return 420.0


## Maahan osuvat tähdättävät kyvyt käyttävät oikealla tatilla liikutettavaa
## kohdistuspistettä pelkän kiinteän suuntaviivan sijaan.
func _ground_targeted_slots() -> Array:
	return []


func _aim_default_range(slot: String) -> float:
	return _aim_range(slot) * 0.65


func _aim_target_radius(_slot: String) -> float:
	return 0.0


func _begin_ground_aim(slot: String) -> void:
	var d := aim.normalized() if aim.length() > 0.1 else Vector2.RIGHT
	_ground_aim_offset = d * clampf(_aim_default_range(slot), 0.0, _aim_range(slot))
	_aim_len = _ground_aim_offset.length()
	_aim_radius = _aim_target_radius(slot)
	# Hiirellä kohde napsahtaa heti osoittimen alle. Ohjaimella lähtökohta on
	# käyttökelpoinen keskikantama, josta oikea tatti siirtää ristikkoa.
	if controller.has_method("uses_pointer_aim") and controller.uses_pointer_aim():
		_update_ground_aim(slot, 0.0)


func _update_ground_aim(slot: String, delta: float) -> void:
	var max_range := maxf(_aim_range(slot), 1.0)
	if controller.has_method("uses_pointer_aim") and controller.uses_pointer_aim():
		_ground_aim_offset = get_global_mouse_position() - global_position
	elif controller.has_method("aim_cursor_vector"):
		_ground_aim_offset += controller.aim_cursor_vector() * GROUND_AIM_CURSOR_SPEED * delta

	if _ground_aim_offset.length() > max_range:
		_ground_aim_offset = _ground_aim_offset.normalized() * max_range
	if _ground_aim_offset.length() < 4.0:
		_ground_aim_offset = (aim.normalized() if aim.length() > 0.1 else Vector2.RIGHT) * 4.0

	var target := global_position + _ground_aim_offset
	if arena != null and arena.map != null:
		target = arena.map.clamp_to_field(target, maxf(_aim_target_radius(slot) * 0.35, 8.0))
		_ground_aim_offset = target - global_position
	_aim_len = _ground_aim_offset.length()
	_aim_radius = _aim_target_radius(slot)
	aim = _ground_aim_offset.normalized()


## Palauttaa juuri vapautetun maamaalin. Botit ja välittömät kutsut saavat
## edelleen järkevän oletusetäisyyden tähtäyssuunnasta.
func aimed_ground_position(dir: Vector2, max_range: float, default_range: float) -> Vector2:
	var target: Vector2
	if _ground_cast_valid:
		target = _ground_cast_target
	elif controller != null and controller.is_bot() and arena != null:
		# Botit kohdistavat AoE:n oikeaan viholliseen eivätkä kiinteälle
		# oletusetäisyydelle. Tämä korjaa tilanteet, joissa päätös oli oikea mutta
		# Emberin allas, Voltin kenttä, Quillin nuolisade tai Salvon morttari putosi
		# järjestelmällisesti kohteen eteen/taakse.
		var cast_dir := dir.normalized() if dir.length() > 0.1 else aim.normalized()
		if cast_dir.length() < 0.1:
			cast_dir = Vector2.RIGHT
		var best: Hero = null
		var best_score := INF
		for enemy in arena.enemy_heroes(team):
			var off: Vector2 = enemy.global_position - global_position
			var dist := off.length()
			if dist < 1.0 or dist > max_range:
				continue
			var alignment := cast_dir.dot(off / dist)
			if alignment < 0.18:
				continue
			var score := dist * (1.4 - alignment)
			if score < best_score:
				best_score = score
				best = enemy
		if best != null:
			var predict_skill := clampf(float(controller.get("prediction")), 0.0, 1.0)
			var best_dist: float = global_position.distance_to(best.global_position)
			var lead_time := 0.15
			match hero_id:
				"salvo":
					lead_time = 1.05   # morttari putoaa hitaasti
				"quill":
					lead_time = 0.7    # nuolisateen varoitusviive
				"ember":
					lead_time = minf(best_dist / 700.0, 0.7) * 0.65
				"volt", "hush":
					lead_time = 0.2
			target = best.global_position + best.velocity * lead_time * predict_skill
		else:
			target = global_position + cast_dir * minf(default_range, max_range)
	else:
		var d := dir.normalized() if dir.length() > 0.1 else aim.normalized()
		if d.length() < 0.1:
			d = Vector2.RIGHT
		target = global_position + d * minf(default_range, max_range)
	var off := target - global_position
	if off.length() > max_range:
		target = global_position + off.normalized() * max_range
	if arena != null and arena.map != null:
		target = arena.map.clamp_to_field(target, 8.0)
	return target


## Maahan tähdättävän ultin yhteinen PS5-/hiirikohdistus. Oikea tatti liikuttaa
## kohdistinta vapaasti kantaman sisällä; botit käyttävät järkevää oletusetäisyyttä.
func _begin_ult_ground_aim() -> void:
	var d := aim.normalized() if aim.length() > 0.1 else Vector2.RIGHT
	_ground_aim_offset = d * clampf(_ult_default_range(), 0.0, _ult_range())
	_aim_len = _ground_aim_offset.length()
	_aim_radius = _ult_target_radius()
	_aim_width = 0.0
	if controller.has_method("uses_pointer_aim") and controller.uses_pointer_aim():
		_update_ult_ground_aim(0.0)


func _update_ult_ground_aim(delta: float) -> void:
	var max_range := maxf(_ult_range(), 1.0)
	if controller.has_method("uses_pointer_aim") and controller.uses_pointer_aim():
		_ground_aim_offset = get_global_mouse_position() - global_position
	elif controller.has_method("aim_cursor_vector"):
		_ground_aim_offset += controller.aim_cursor_vector() * GROUND_AIM_CURSOR_SPEED * delta
	if _ground_aim_offset.length() > max_range:
		_ground_aim_offset = _ground_aim_offset.normalized() * max_range
	if _ground_aim_offset.length() < 4.0:
		_ground_aim_offset = (aim.normalized() if aim.length() > 0.1 else Vector2.RIGHT) * 4.0
	var target := global_position + _ground_aim_offset
	if arena != null and arena.map != null:
		target = arena.map.clamp_to_field(target, maxf(_ult_target_radius() * 0.35, 8.0))
		_ground_aim_offset = target - global_position
	_aim_len = _ground_aim_offset.length()
	_aim_radius = _ult_target_radius()
	_aim_width = 0.0
	aim = _ground_aim_offset.normalized()


func aimed_ult_ground_position(dir: Vector2) -> Vector2:
	# Botin ei tarvitse teeskennellä oikean tatin kursoria: ankkuroidaan maamaali
	# sen tähtäyskartiossa olevaan oikeaan vihollissankariin. Aiempi kiinteä
	# oletusetäisyys sai etenkin Tiden syöksymään kohteen yli ja Voltin myrskyn
	# putoamaan tyhjään, vaikka päätös käyttää ulti oli muuten oikea.
	if controller != null and controller.is_bot() and arena != null:
		var cast_dir := dir.normalized() if dir.length() > 0.1 else aim.normalized()
		var best: Hero = null
		var best_score := INF
		for enemy in arena.enemy_heroes(team):
			var off: Vector2 = enemy.global_position - global_position
			var dist := off.length()
			if dist > _ult_range() or dist < 1.0:
				continue
			var alignment := cast_dir.dot(off / dist)
			if alignment < 0.15:
				continue
			var score := dist * (1.35 - alignment)
			if score < best_score:
				best_score = score
				best = enemy
		if best != null:
			var bot_target: Vector2 = best.global_position
			if arena.map != null:
				bot_target = arena.map.clamp_to_field(bot_target, maxf(_ult_target_radius() * 0.35, 8.0))
			return bot_target
	return aimed_ground_position(dir, _ult_range(), _ult_default_range())


## Kutsutaan kun tähdättävän kyvyn tähtäys alkaa. Palauta false keskeyttääksesi
## aloituksen (esim. Titaanin tartunta: ei kohdetta -> ei tähtäystä). Oletus true.
func _aim_begin(_slot: String) -> bool:
	return true


## Kutsutaan joka framessa tähtäyksen aikana (ennen vapautuksen tarkistusta).
## Ylikirjoita sankarissa (esim. Titaani pitää kohdetta edessään).
func _aim_hold(_slot: String, _delta: float) -> void:
	pass


# --- Resurssit: mana / energy / rage ---

## Ylikirjoita asettamaan resurssi: res_type, res_max, res, res_regen, res_cost
## ja mahdollisesti cd_max-säädöt. Oletuksena ei resurssia (pelkkä jäähdytys).
func _setup_resource() -> void:
	pass


func _tick_resource(delta: float) -> void:
	var boost := 2.25 if blue_buff > 0.0 else 1.0   # Blue: nopeampi mana/energy-palautuminen
	if res_type == "mana" or res_type == "energy":
		# Ei palaudu kanavoinnin aikana (säde/kilpi kuluttaa sitä), jotta
		# resurssi todella loppuu eikä regen-tippa pidä kykyä hengissä.
		# _regen_level_mult: regen kasvaa tasojen myötä (profiilin regen-kerroin).
		if _channel_slot == "":
			res = minf(res + res_regen * boost * _regen_level_mult * delta, res_max)
	elif res_type == "rage":
		_rage_idle += delta
		if _rage_idle > 3.5:
			res = maxf(res - 6.0 * delta, 0.0)


func _reset_resource() -> void:
	_channel_slot = ""
	_channel_locked = ""
	_cast_context = ""
	_rage_idle = 0.0
	if res_type == "rage":
		res = 0.0
	elif res_type != "":
		res = res_max
	# Lipas täyteen ja lataus poikki (jos sankarilla on lipasjärjestelmä).
	if ammo_max > 0:
		ammo = ammo_max
		reloading = false


func _can_afford(slot: String) -> bool:
	if res_type == "":
		return true
	return res >= float(res_cost.get(slot, 0.0))


func _spend(slot: String) -> void:
	if res_type == "":
		return
	res = maxf(res - float(res_cost.get(slot, 0.0)), 0.0)
	if res_type == "rage":
		_rage_idle = 0.0


func gain_res(amount: float) -> void:
	if res_type == "":
		return
	if res_type == "rage" and blue_buff > 0.0:
		amount *= 1.3          # Blue auttaa myös rage-sankaria, mutta maltillisemmin
	res = clampf(res + amount, 0.0, res_max)
	if res_type == "rage":
		_rage_idle = 0.0


## Kenttäbuffin antaminen (FieldBuff kutsuu murskattaessa).
func apply_field_buff(t: String, dur: float) -> void:
	if t == "blue":
		blue_buff = maxf(blue_buff, dur)
		if arena != null:
			arena.popup(global_position + Vector2(0, -82), "SININEN BUFFI!", Color("6aa0ff"), 20)
	else:
		red_buff = maxf(red_buff, dur)
		if arena != null:
			arena.popup(global_position + Vector2(0, -82), "PUNAINEN BUFFI!", Color("ff7a6a"), 20)
	AudioMgr.play("blessing", 0.05)


## Void-pino (Riftin perushyökkäys) — enintään 5 kohdetta kohti.
func add_void_stack(source: Hero) -> void:
	void_stacks = mini(void_stacks + 1, 5)
	void_stack_timer = 6.0
	void_stacker = source


## Nollaa ja palauttaa pinojen määrän (Riftin räjäytys kuluttaa ne).
func consume_void_stacks() -> int:
	var n := void_stacks
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	return n


## Kaksintaistelumerkki (Lance): kasaa merkin kohteeseen (enintään 3).
## Palauttaa merkkien määrän lisäyksen jälkeen.
func add_duel_mark(source: Hero) -> int:
	duel_marks = mini(duel_marks + 1, 3)
	duel_mark_timer = 5.0
	duel_marker = source
	return duel_marks


## Nollaa ja palauttaa merkkien määrän (Lancen viimeistelyisku kuluttaa ne).
func consume_duel_marks() -> int:
	var n := duel_marks
	duel_marks = 0
	duel_mark_timer = 0.0
	duel_marker = null
	return n


func apply_freeze(dur: float) -> void:
	var before := frozen
	frozen = maxf(frozen, dur)
	_record_cc("stun", frozen - before)   # jäädytys = kova CC, kirjataan stuniksi
	profile.stats.cc_suffered += frozen - before


## Kanavoitavat kykypaikat (pito ylläpitää). Oletuksena ei mitään.
func _channeled_slots() -> Array:
	return []


## Kutsutaan joka framessa kanavoinnin aikana. Ylikirjoita sankarissa.
func _channel_tick(_slot: String, _delta: float) -> void:
	pass


func _channel_end(_slot: String) -> void:
	pass


func _fire_ult() -> void:
	ult_charge = 0.0
	_ult_ready_announced = false
	_ult_holding = false
	AudioMgr.play("ult")
	arena.shake(0.35)
	if visual != null:
		visual.cast_ability("ult")
	# Jokainen ulti saa suuren sankarikohtaisen laukaisusinetin. Se erottaa ultin
	# tavallisista kyvyistä ja kertoo ruuhkassakin heti kuka vaikutuksen aiheutti.
	ability_signature(hero_id, 220.0, aim)
	_act("ult")
	_log_cast("ult")
	_ultimate(aim)
	_act_end()


## Ylikirjoita palauttamaan true jos ultimate pidetään pohjassa (esikatselu) ja
## laukaistaan vapautettaessa. Oletuksena välitön.
func _ult_is_held() -> bool:
	return false


## Maahan tähdättävä hold-ulti käyttää samaa vapaata oikean tatin kohdistinta kuin
## muut AoE-kyvyt. Sankari ylikirjoittaa kantaman, oletusetäisyyden ja alueen.
func _ult_ground_targeted() -> bool:
	return false


func _ult_range() -> float:
	return 520.0


func _ult_default_range() -> float:
	return _ult_range() * 0.65


func _ult_target_radius() -> float:
	return _ult_preview_radius()


## Pidä-ja-vapauta-ultin esikatselualueen säde (AimGuide piirtää renkaan).
func _ult_preview_radius() -> float:
	return 0.0


## Pidä-ja-vapauta-ultin tähtäysviivan pituus (0 = ei viivaa). Esim. Quillin
## tähdättävä supernuoli näyttää viivan ennen laukaisua.
func _ult_preview_line() -> float:
	return 0.0


## Viiva-ultin puolikas osumaleveys. AimGuide piirtää tämän todellisena käytävänä.
func _ult_preview_width() -> float:
	return 0.0


## Oletushyökkäyskontrolli: liipaisin pohjassa -> ammu aina kun cd sallii.
## Quill ylikirjoittaa tämän lataukselle.
func _attack_control(held: bool, _just_pressed: bool, _just_released: bool,
		dir: Vector2, _delta: float) -> void:
	if held and cd.basic <= 0.0:
		cd.basic = cd_max.basic
		_basic(dir)


# --- Sankarikohtaiset kyvyt (ylikirjoitetaan aliluokissa) ---

## Liikkumisnopeuden kerroin (ylikirjoitettavissa; esim. Scoutin tornitila
## hidastaa). Oletus 1.0 = ei vaikutusta.
func _move_speed_mult() -> float:
	return 1.0


## Kameran seurantapiste (oletus: sankarin sijainti). Salvo ylikirjoittaa
## palauttamaan ohjattavan raketin sijainnin, jotta näkymä seuraa rakettia.
func camera_focus() -> Vector2:
	return global_position


func _basic(_dir: Vector2) -> void:
	pass


func _ability1(_dir: Vector2) -> void:
	pass


func _ability2(_dir: Vector2) -> void:
	pass


func _ultimate(_dir: Vector2) -> void:
	pass


func _passive_update(_delta: float) -> void:
	pass


## Oletusväistö: nopea syöksy, lyhyet suojaruudut.
func _dodge_action(dir: Vector2) -> void:
	dash(dir, 950.0, 0.16, true)
	AudioMgr.play("dash", 0.08, 0.0, global_position)
	Fx.dust(arena, global_position)


# --- Lähderegen ja paluu baseen (MOBA) ---

## Lähderegen: oman lähteen äärellä (sanctuaryssa) HP ja resurssi palautuvat
## erittäin nopeasti. Parannus tehdään suoraan (EI heal_hp:n kautta) — se ei
## lataa ultia eikä kirjaudu kenenkään kyvyn ansioksi. Visuaali: pehmeä vihreä
## sparkle-tikki + joukkuevärinen rengas, popup kuristettuna.
func _fountain_regen(delta: float) -> void:
	if arena == null or arena.mode != "moba" or is_unit or piloting:
		return
	var mm := arena.map as MapMoba
	if mm == null:
		return
	if not mm.is_in_own_sanctuary(global_position, team):
		return
	if global_position.distance_to(mm.fountain_spot(team)) > FOUNTAIN_RADIUS:
		return
	var healed := 0.0
	if hp < max_hp:
		var before := hp
		hp = minf(max_hp, hp + max_hp * FOUNTAIN_HEAL_FRAC * delta)
		healed = hp - before
	# Rage rakentuu vain taistelusta — lähde täyttää manan ja energian.
	if res_type != "" and res_type != "rage":
		res = minf(res_max, res + res_max * FOUNTAIN_RES_FRAC * delta)
	if healed <= 0.0:
		return
	_fountain_heal_accum += healed
	_fountain_fx_t -= delta
	_fountain_popup_t -= delta
	if _fountain_fx_t <= 0.0:
		_fountain_fx_t = 0.45
		Fx.heal_sparkle(arena, global_position
			+ Vector2(randf_range(-radius, radius), randf_range(-8.0, 8.0)))
		Fx.ring(arena, global_position,
			Palette.with_alpha(Palette.team(team).lerp(Palette.HEAL, 0.5), 0.55),
			radius + 14.0, 0.4, 2.5)
	if _fountain_popup_t <= 0.0 and _fountain_heal_accum >= 1.0:
		_fountain_popup_t = 1.0
		arena.popup(global_position + Vector2(0, -radius - 26.0),
			"+%d" % int(_fountain_heal_accum), Palette.HEAL, 14)
		_fountain_heal_accum = 0.0


## Pito-kanavoitava paluu omaan tukikohtaan (tuleva kauppa nojaa tähän).
## Vahinko, liikesyöte, mikä tahansa kykysyöte, tainnutus ja napin vapautus
## keskeyttävät. Valmistuessaan teleporttaa omalle lähteelle (Fx molempiin
## päihin). Ei toimi kuolleena/tainnutettuna/ohjaustilassa/reliikkiä kantaen.
func _update_recall(delta: float) -> void:
	if arena == null or arena.mode != "moba" or is_unit:
		_recall_t = 0.0
		return
	if controller == null or not controller.has_method("recall_held"):
		return
	var wants: bool = bool(controller.recall_held())
	if not wants or carrying or stun_timer > 0.0 or piloting:
		_recall_interrupt()
		return
	# Liike tai mikä tahansa puskuroitu kykysyöte keskeyttää kanavoinnin.
	if controller.move_vector().length() > 0.15 or controller.attack_held() \
			or float(_buf.a1) > 0.0 or float(_buf.a2) > 0.0 \
			or float(_buf.ult) > 0.0 or float(_buf.dodge) > 0.0:
		_recall_interrupt()
		return
	var mm := arena.map as MapMoba
	if mm == null:
		return
	# Basessa ollessa ei ole mitään minne palata.
	if mm.is_in_own_sanctuary(global_position, team):
		_recall_t = 0.0
		return
	if _recall_t <= 0.0:
		arena.popup(global_position + Vector2(0, -radius - 34.0), "PALUU...",
			Palette.glow(Palette.team(team), 1.3), 16)
		if not Game.simulating:
			AudioMgr.play("blessing", 0.04, -8.0, global_position)
	_recall_t += delta
	_recall_fx_t -= delta
	if _recall_fx_t <= 0.0:
		_recall_fx_t = 0.7
		Fx.ring(arena, global_position, Palette.with_alpha(Palette.team(team), 0.6),
			radius + 30.0 + 26.0 * (_recall_t / RECALL_TIME), 0.6, 3.0)
	if _recall_t >= RECALL_TIME:
		_finish_recall(mm)


## Keskeyttää käynnissä olevan paluukanavoinnin (pieni palaute jos oli kesken).
func _recall_interrupt() -> void:
	if _recall_t <= 0.0:
		return
	_recall_t = 0.0
	if arena != null:
		arena.popup(global_position + Vector2(0, -radius - 34.0), "PALUU KESKEYTYI",
			Palette.BAD, 14)


## Paluu valmis: teleportti omalle lähteelle, välähdys molemmissa päissä.
func _finish_recall(mm: MapMoba) -> void:
	_recall_t = 0.0
	var team_col: Color = Palette.team(team)
	var from := global_position
	var dest: Vector2 = mm.fountain_spot(team)
	Fx.flash(arena, from, Palette.glow(team_col, 1.5), radius + 46.0, 0.4)
	Fx.ring(arena, from, Palette.with_alpha(team_col, 0.8), radius + 60.0, 0.5, 5.0)
	global_position = dest
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	iframes = maxf(iframes, 0.4)
	Fx.flash(arena, dest, Palette.glow(team_col, 1.5), radius + 46.0, 0.5)
	Fx.ring(arena, dest, Palette.with_alpha(Palette.HEAL, 0.7), radius + 40.0, 0.6, 4.0)
	arena.popup(dest + Vector2(0, -radius - 34.0), "KOTONA",
		Palette.glow(team_col, 1.3), 16)
	AudioMgr.play("respawn", 0.05, -4.0, dest)


# --- Taisteluapurit ---

## phase_walls: syöksy menee sisäseinien läpi (mutta EI kartan ulkopuolelle;
## reunat rajataan _physics_processissa). Esim. Tiden vesisyöksy ja ultti.
func dash(dir: Vector2, speed: float, duration: float, with_iframes := false, phase_walls := false) -> void:
	if dir.length() < 0.1:
		dir = aim
	dash_timer = duration
	dash_velocity = dir.normalized() * speed
	if with_iframes:
		iframes = maxf(iframes, duration + 0.05)
	# Sovita seinä-faasi TÄHÄN syöksyyn (ei peritä edellisestä): faasi-syöksy
	# ottaa faasin päälle, ei-faasi-syöksy keskeyttää mahdollisen aiemman faasin.
	if phase_walls:
		if not _phase_walls:
			_phase_walls = true
			set_collision_mask_value(1, false)   # ohita seinät syöksyn ajaksi
	elif _phase_walls:
		_end_phase()
	visual.squash(0.75, 1.25)


## Lopeta seinien-läpi-tila: palauta seinätörmäys ja työnnä ulos jos jäätiin
## seinän sisään (ettei jää jumiin).
func _end_phase() -> void:
	if not _phase_walls:
		return
	_phase_walls = false
	set_collision_mask_value(1, true)
	if arena != null and arena.map != null:
		global_position = arena.map.clamp_to_field(global_position, radius)


# --- Kykytelemetria (kuka/mikä kykypaikka juuri toimii) ---
# Kohteen apply_stun/apply_slow/apply_root ja heal_hp lukevat arena._act_hero/
# _act_slot tietääkseen kenelle vaikutus kirjataan. Ammukset ja alueet asettavat
# kontekstin osuman/tickin ajaksi, lähikyvyt kyvyn suorituksen ajaksi.

func _act(slot: String) -> void:
	_cast_context = slot
	if arena != null:
		arena._act_hero = self
		arena._act_slot = slot


## Sulkee arenan CC-ikkunan. _cast_context jää voimaan (TARTTUVA), jotta await-
## kykyjen (esim. kanavoitavat ultit) viivästynyt vahinko kirjautuu yhä oikealle
## kykypaikalle awaitin jälkeenkin. Konteksti nollataan kuolemassa/erän alussa.
func _act_end() -> void:
	if arena != null:
		arena._act_hero = null
		arena._act_slot = ""


## Hakee (tai luo) kykypaikan telemetriatietueen tälle sankarille.
func _slot_rec(slot: String) -> Dictionary:
	if not profile.stats.slots.has(slot):
		profile.stats.slots[slot] = {"casts": 0, "hits": 0, "damage": 0.0,
			"heal": 0.0, "stun": 0.0, "slow": 0.0, "root": 0.0, "kb": 0,
			"shield": 0.0, "buff": 0.0}
	return profile.stats.slots[slot]


## Kirjaa yhden kykypaikan käyttökerran (kutsutaan dispatchissa kun kyky lähtee).
func _log_cast(slot: String) -> void:
	_slot_rec(slot)["casts"] += 1


## Kirjaa CC-vaikutus (stun/slow/root) sekunteina toimijalle. Kutsutaan kohteen
## apply_*-funktiosta: toimija ja slot luetaan arenan aktiivikontekstista.
func _record_cc(kind: String, duration: float) -> void:
	if duration <= 0.0 or arena == null:
		return
	var actor: Hero = arena._act_hero
	if actor == null or not is_instance_valid(actor):
		return
	var slot: String = arena._act_slot
	if slot == "":
		return
	actor._slot_rec(slot)[kind] += duration


## Kirjaa buffi-sekunnit (haste/nopeus/vahinkobuffi-ikkuna) toimijan kykypaikalle,
## kuten _record_cc. Vain LISÄTTY aika (uusi-vanha) -> ei paisu kun buffia uusitaan.
## Näyttää raportissa paljonko hyötyä buffikyvyt oikeasti tuottivat.
func _record_buff(duration: float) -> void:
	if duration <= 0.0 or arena == null:
		return
	var actor: Hero = arena._act_hero
	if actor == null or not is_instance_valid(actor):
		return
	var slot: String = arena._act_slot
	if slot == "":
		return
	actor._slot_rec(slot)["buff"] += duration


func deal_damage_to(target: Hero, amount: float, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if target == null or not is_instance_valid(target) or not target.alive:
		return 0.0
	if target.team == team:
		return 0.0
	if kb_dir == Vector2.ZERO:
		kb_dir = (target.global_position - global_position).normalized()
	# Virkistä CC-ikkuna tarttuvasta kontekstista jos se on tyhjä (await-kykyjen
	# viivästynyt vahinko + samassa iskussa tuleva CC osuu oikealle kyvylle).
	if arena != null and arena._act_hero == null and _cast_context != "":
		arena._act_hero = self
		arena._act_slot = _cast_context
	var dealt := target.take_damage(amount, self, kb, kb_dir)
	if dealt > 0.0:
		profile.stats.damage += dealt
		_record_neutral_buff_damage(dealt, target is Structure)
		if target is Structure:
			profile.stats.structure_damage += dealt
		elif target is Critter:
			profile.stats.jungle_damage += dealt
		# Per-kykypaikka: vahinko + osumat (+ töytäisyt) telemetriaan.
		if _cast_context != "":
			var rec := _slot_rec(_cast_context)
			rec["hits"] += 1
			rec["damage"] += dealt
			if kb > 0.0:
				rec["kb"] += 1
		profile.add_score(dealt * 0.1)
		# Ulti latautuu taistelusta SANKAREITA vastaan; farmi (minionit, olennot,
		# rakennukset) lataa vain murto-osan — aallon siivoaminen ei täytä ulttia.
		# (Oli 0.22 kaikesta vahingosta -> ulti oli spam-kyky.)
		add_ult(dealt * (0.12 if not target.is_unit else 0.03))
		if res_type == "rage":
			gain_res(dealt * 0.4)
		elif res_type == "energy":
			gain_res(dealt * 0.2)   # energia kertyy myös hyökkäämisestä (assassinit)
	return dealt


## Kirjaa kaiken buffin aikana syntyneen paineen erikseen. Sama teko saa kuulua
## kahteen samanaikaiseen buffi-ikkunaan: tämä on tarkoituksellista ja kertoo
## kummankin power spike -ikkunan aikana saavutetun kokonaisarvon.
func _record_neutral_buff_damage(dealt: float, structure_hit: bool) -> void:
	if profile == null or dealt <= 0.0:
		return
	for entry in [
		["red", red_camp_buff], ["blue", blue_camp_buff],
		["baron", baron_buff], ["dragon", dragon_buff],
	]:
		if float(entry[1]) <= 0.0:
			continue
		var key := "structure_during_%s" % str(entry[0]) if structure_hit \
			else "damage_during_%s" % str(entry[0])
		profile.stats[key] += dealt


func take_damage(amount: float, source: Hero, kb := 0.0, kb_dir := Vector2.ZERO) -> float:
	if not alive or iframes > 0.0:
		return 0.0

	# Vaikeustason huijauskertoimet (vain epäreilu botti poikkeaa 1.0:sta):
	# hyökkääjän aiheuttama vahinko ja kohteen ottama vahinko.
	if source != null and is_instance_valid(source):
		# Tasokasvu (yleinen + melee/spell) ja toimivan kykypaikan ranki.
		amount *= source.dmg_out_mult * source.combat_damage_mult()
		if source.red_buff > 0.0 and source._cast_context == "basic":
			if source.red_camp_buff > 0.0:
				source.profile.stats.red_bonus_damage += amount * 0.18
			amount *= 1.18         # Red: perushyökkäysvoima
		if source.blue_buff > 0.0 and source._cast_context in ["a1", "a2", "ult"]:
			if source.blue_camp_buff > 0.0:
				source.profile.stats.blue_bonus_damage += amount * 0.14
			amount *= 1.14         # Blue: spell power
	amount *= dmg_in_mult

	# Merkitty kohde (Scoutin vaahtomerkki) ottaa lisävahinkoa kaikilta.
	if mark_timer > 0.0:
		amount *= mark_amp

	# Kiviho (heijastus): heijasta osa otetusta vahingosta takaisin hyökkäävälle
	# vihollissankarille. Vain oikeat sankarit (ei tornit/olennot/minionit) ja
	# konteksti tallennetaan/palautetaan, koska olemme hyökkääjän vahinkokutsun
	# sisällä (arenan aktiivikonteksti on hyökkääjän).
	if reflect_timer > 0.0 and reflect_factor > 0.0 and amount > 0.0 \
			and source != null and is_instance_valid(source) and source != self \
			and not source.is_unit and source.team != team \
			and not source._applying_reflect:   # älä heijasta heijastettua osumaa (ei ketjua)
		var refl: float = amount * reflect_factor
		var prev_hero = arena._act_hero if arena != null else null
		var prev_slot: String = arena._act_slot if arena != null else ""
		var prev_ctx := _cast_context
		_act(reflect_slot)
		_applying_reflect = true
		deal_damage_to(source, refl)
		_applying_reflect = false
		_cast_context = prev_ctx
		if arena != null:
			arena._act_hero = prev_hero
			arena._act_slot = prev_slot

	# Suuntatorjunta (kilpivalli): edestä tulevat osumat vaimenevat.
	if guard_timer > 0.0 and kb_dir != Vector2.ZERO:
		var from_dir := -kb_dir
		if absf(rad_to_deg(from_dir.angle_to(aim))) < guard_arc_deg:
			var absorbed := amount * guard_absorb
			amount -= absorbed
			profile.stats.prevented += absorbed
			profile.add_score(absorbed * 0.08)
			if guard_slot != "":
				_slot_rec(guard_slot)["shield"] += absorbed
			# Energiakilpi (Bastion): torjuminen kuluttaa energiaa vahingon mukaan.
			if res_type == "energy" and _channel_slot != "":
				res = maxf(res - absorbed * 0.6, 0.0)
			Fx.spark(arena, global_position + aim * radius, Palette.SHIELD)
			AudioMgr.play("shield", 0.08, 0.0, global_position)

	# Suojakilpi imee ensin.
	if shield_hp > 0.0:
		var soak := minf(shield_hp, amount)
		shield_hp -= soak
		amount -= soak
		if shield_source != null and is_instance_valid(shield_source):
			shield_source.profile.stats.prevented += soak
			shield_source.profile.add_score(soak * 0.08)
			if shield_slot != "":
				shield_source._slot_rec(shield_slot)["shield"] += soak
		arena.popup(global_position + Vector2(0, -46), str(int(soak)), Palette.SHIELD, 18)
		# Kilven imemä osuma kuuluu (aiemmin täysin vaimennettu osuma oli mykkä).
		if soak > 0.0:
			AudioMgr.play("shield", 0.1, -7.0, global_position)

	if amount <= 0.0:
		return 0.0

	hp -= amount
	since_damage = 0.0
	_recall_interrupt()   # vahinko keskeyttää paluukanavoinnin
	profile.stats.taken += amount
	# Otettu vahinko lähteen mukaan (telemetria: ottaako AI turhia torni-/mob-osumia).
	if source != null and is_instance_valid(source):
		if source is Structure:
			profile.stats.taken_tower += amount
		elif source is Critter:
			profile.stats.taken_neutral += amount
		elif source is Minion:
			profile.stats.taken_minion += amount
		else:
			profile.stats.taken_hero += amount
	if res_type == "rage":
		gain_res(amount * 0.6)
	if kb > 0.0 and kb_dir != Vector2.ZERO:
		apply_knockback(kb_dir, kb)

	visual.flash()
	arena.popup(global_position + Vector2(0, -46), str(int(amount)), Color.WHITE, 20)
	AudioMgr.play("hit", 0.08, -6.0, global_position)   # tiheä ääni -> hillitympi taso
	# Tuntopalaute isosta osumasta (>12 % maksimista): voimakkuus vahingon mukaan.
	if amount > max_hp * 0.12:
		controller_rumble(0.0, clampf(amount / max_hp * 1.8, 0.25, 0.7), 0.14)
	add_ult(amount * 0.07)   # otettu vahinko lataa maltillisesti (oli 0.14)

	if source != null:
		# Käytä peliaikaa, jotta ikkunan pituus pysyy samana myös nopeutetussa
		# simulaatiossa (Time.get_ticks_msec mittaa oikeaa seinäkelloa).
		var now: float = arena.match_elapsed if arena != null \
			else Time.get_ticks_msec() / 1000.0
		# Yksi merkintä per vahingontekijä. Aiemmin jokainen osuma/tikki lisäsi
		# uuden rivin, joten sama sankari sai yhdestä tyrmäyksestä avustuksen
		# monta kertaa (ja DoT kasvatti listaa tarpeettomasti koko elämän ajan).
		_recent_damagers = _recent_damagers.filter(func(entry):
			return is_instance_valid(entry.hero) and now - float(entry.time) <= ASSIST_WINDOW)
		var refreshed := false
		for entry in _recent_damagers:
			if entry.hero == source:
				entry.time = now
				refreshed = true
				break
		if not refreshed:
			_recent_damagers.append({"hero": source, "time": now})

	if hp <= 0.0:
		hp = 0.0
		_knockout(source)
	return amount


func heal_hp(amount: float, source: Hero) -> float:
	if not alive or hp >= max_hp:
		return 0.0
	# Rankki vahvistaa parannuksia, jotka tulevat kyvyn _act-kontekstissa
	# (esim. Luman hoitokehä). Kontekstittomat parannukset jäävät ennalleen.
	if source != null and is_instance_valid(source) and arena != null \
			and arena._act_hero == source and arena._act_slot != "":
		amount *= source.rank_power(arena._act_slot)
	var healed := minf(amount, max_hp - hp)
	hp += healed
	if source != null and source != self:
		source.profile.stats.healing += healed
		source.profile.add_score(healed * 0.12)
		source.add_ult(healed * 0.08)   # parannus lataa maltillisesti (oli 0.15)
		# Per-kykypaikka parannus toimijalle (arenan aktiivikonteksti).
		if arena != null and arena._act_hero == source and arena._act_slot != "":
			source._slot_rec(arena._act_slot)["heal"] += healed
	arena.popup(global_position + Vector2(0, -46), "+%d" % int(healed), Palette.HEAL, 18)
	Fx.heal_sparkle(arena, global_position)
	return healed


## record=false: kilpi on neutraali palkinto (pomobuffi) eikä kuulu millekään
## kyvylle -> shield_slot jää tyhjäksi eikä imetty vahinko sotke kyky­telemetriaa.
func add_shield(amount: float, duration: float, source: Hero, record := true) -> void:
	# Rankki vahvistaa kykyjen antamia kilpiä (neutraalit palkinnot record=false
	# ja kontekstittomat kilvet jäävät ennalleen).
	if record and source != null and is_instance_valid(source) \
			and source._cast_context != "":
		amount *= source.rank_power(source._cast_context)
	shield_hp = maxf(shield_hp, amount)
	shield_timer = duration
	shield_source = source
	# Kirjaa antajan aktiivinen kykypaikka -> imetty vahinko osataan kohdistaa
	# oikealle kyvylle (esim. Luman kupla vs. Maestron kilpi).
	shield_slot = source._cast_context if (record and source != null and is_instance_valid(source)) else ""
	AudioMgr.play("shield", 0.08, 0.0, global_position)
	Fx.ring(arena, global_position, Palette.SHIELD, radius + 14.0, 0.35)


func add_ult(points: float) -> void:
	if ult_charge >= 100.0:
		return
	# Lataus kertyy myös lukitulle ultille, mutta "ULTI VALMIS" ilmoitetaan
	# vasta kun ulti on sekä ladattu että avattu (rank_up hoitaa avaushetken).
	ult_charge = minf(ult_charge + points * ult_gain_mult, 100.0)
	if ult_charge >= 100.0 and ult_unlocked():
		_announce_ult_ready()


## "Ulti valmis" -ilmoitus (ääni + tärinä + popup) kerran per lataus. Laukeaa
## vain kun ulti on sekä täydessä latauksessa että avattu (ranki >= 1).
func _announce_ult_ready() -> void:
	if _ult_ready_announced:
		return
	_ult_ready_announced = true
	AudioMgr.play("ult_ready")
	controller_rumble(0.3, 0.12, 0.2)   # tuntopalaute: ulti valmis
	if arena != null:
		arena.popup(global_position + Vector2(0, -70), "ULTI VALMIS!", Palette.GOLD, 20)


## Työntö/veto-impulssi omaan kanavaansa (kb_velocity), jota ohjausliikkeen
## move_toward EI syö — impulssi hiipuu KB_FRICTION-kitkalla. Tartutettua ei
## töytäistä (ote hallitsee sijaintia; heitto vapauttaa otteen ensin).
## respect_resist=false kun voima on jo viritetty kohdetyypin mukaan
## (esim. junglereiden olentokohtaiset veto-arvot).
func apply_knockback(dir: Vector2, strength: float, respect_resist := true) -> void:
	if not alive or strength <= 0.0 or dir.length() < 0.01:
		return
	if grabbed_by != null:
		return
	var mult := (1.0 - kb_resist) if respect_resist else 1.0
	if mult <= 0.0:
		return
	kb_velocity += dir.normalized() * strength * mult


func apply_slow(factor: float, duration: float) -> void:
	if cc_immune_timer > 0.0:
		return
	if factor < slow_factor or slow_timer <= 0.0:
		slow_factor = factor
	# Kirjaa VAIN lisätty aika (uusi kesto - vanha), ei raakaa duration-arvoa:
	# alueet uusivat slow'n joka ruutu -> summa vastaa todellista slow-aikaa
	# eikä paisu (esim. 2 s alueessa seisominen ~= 2 s, ei 36 s).
	var before := maxf(slow_timer, 0.0)
	slow_timer = maxf(slow_timer, duration)
	_record_cc("slow", slow_timer - before)


## record=false: buffi tulee neutraalista lähteestä (pomobuffi, raivostuminen)
## eikä kuulu millekään kykypaikalle -> ei kirjata telemetriaan (muuten se
## kirjautuisi vahingossa sille sankarille joka sattuu olemaan kesken kykyään).
func apply_haste(factor: float, duration: float, record := true) -> void:
	var before := maxf(haste_timer, 0.0)
	haste_factor = maxf(haste_factor, factor)
	haste_timer = maxf(haste_timer, duration)
	if record:
		_record_buff(haste_timer - before)   # buffi-hyöty kirjataan antajan kyvylle


func apply_root(duration: float) -> void:
	if cc_immune_timer > 0.0:
		return
	var before := root_timer
	root_timer = maxf(root_timer, duration)
	arena.popup(global_position + Vector2(0, -60), "JUURTUNUT", Palette.BAD, 16)
	AudioMgr.play("root", 0.08, 0.0, global_position)
	_record_cc("root", root_timer - before)
	profile.stats.cc_suffered += root_timer - before


func apply_stun(duration: float) -> void:
	if cc_immune_timer > 0.0:
		return
	var before := stun_timer
	stun_timer = maxf(stun_timer, duration)
	_record_cc("stun", stun_timer - before)
	profile.stats.cc_suffered += stun_timer - before


## Vaimennus: kohde ei voi käyttää kykyjä (a1/a2/ult/väistö) mutta voi liikkua.
func apply_silence(duration: float) -> void:
	if cc_immune_timer > 0.0:
		return
	var before := silence_timer
	silence_timer = maxf(silence_timer, duration)
	if silence_timer - before > 0.0:
		_record_cc("stun", silence_timer - before)   # vaimennus = kova CC, kirjataan stuniksi
		profile.stats.cc_suffered += silence_timer - before
		if arena != null:
			arena.popup(global_position + Vector2(0, -60), "VAIMENNETTU", Color("b06aff"), 15)


## Kiviho: aseta heijastus (osa otetusta vahingosta takaisin hyökkääjälle) ja
## sen kirjaava kykypaikka. Kutsutaan joka framessa kanavoinnin aikana.
func apply_reflect(duration: float, factor: float, slot: String) -> void:
	reflect_timer = maxf(reflect_timer, duration)
	reflect_factor = factor
	reflect_slot = slot


func apply_mark(duration: float, amp := 1.25) -> void:
	mark_timer = maxf(mark_timer, duration)
	mark_amp = amp
	arena.popup(global_position + Vector2(0, -60), "MERKITTY", Palette.GOLD, 14)


func start_guard(duration: float, absorb := 0.7, arc_deg := 80.0, radius := 0.0) -> void:
	guard_timer = duration
	guard_absorb = absorb
	guard_arc_deg = arc_deg
	guard_radius = radius
	guard_slot = _cast_context   # telemetria: torjuttu vahinko kirjataan tälle kyvylle


## Merkitsee sankarin tartutuksi (Titaani): poistaa sankari-sankari-törmäyksen
## jottei kohde estä kantajaa. Virkistetään joka framessa kantajan _aim_holdista;
## ellei virkistetä, ote vapautuu itsestään (_physics_process).
func set_grabbed(holder) -> void:
	if grabbed_by == null:
		set_collision_layer_value(2, false)
		set_collision_mask_value(2, false)
	grabbed_by = holder
	_grab_hold_timer = 0.2


func release_grabbed() -> void:
	if grabbed_by == null:
		return
	grabbed_by = null
	_grab_hold_timer = 0.0
	if alive:
		set_collision_layer_value(2, true)
		set_collision_mask_value(2, true)


# --- Tyrmäys ja paluu ---

## Paluuaika. MOBASSA se kasvaa otteluajan myötä (kuten oikeassa MOBASSA):
## alkupelin kuolema on halpa, myöhemmin kallis -> voitettu taistelu muuttuu
## piiritykseksi ja ottelut ratkeavat nexuksen tuhoon aikakaton sijaan.
func _respawn_delay() -> float:
	if arena != null and arena.mode == "moba":
		return clampf(6.0 + arena.match_elapsed / 28.0, 6.0, 26.0)
	return RESPAWN_TIME


func _knockout(source: Hero) -> void:
	alive = false
	_aiming_slot = ""
	_aim_active = false
	_channel_slot = ""
	_channel_locked = ""
	_cast_context = ""
	_ult_holding = false
	_beam_active = false
	blue_buff = 0.0           # tyrmäys rikkoo kantajan buffit (vihollisen "murskaus")
	red_buff = 0.0
	red_camp_buff = 0.0
	blue_camp_buff = 0.0
	baron_buff = 0.0
	dragon_buff = 0.0
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	duel_marks = 0
	duel_mark_timer = 0.0
	duel_marker = null
	cc_immune_timer = 0.0
	frozen = 0.0
	piloting = false
	_recall_t = 0.0
	respawn_timer = _respawn_delay()
	profile.stats.deaths += 1
	profile.stats.time_dead += respawn_timer   # kuolleena vietetty aika (snowball-mittari)
	# Tappajan tyyppi (näkee kaatuvatko AI-unitit torneille/mobeille turhaan).
	if source != null and is_instance_valid(source):
		if source is Structure:
			profile.stats.deaths_tower += 1
		elif source is Critter:
			profile.stats.deaths_neutral += 1
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	shield_hp = 0.0
	guard_timer = 0.0
	guard_radius = 0.0
	grabbed_by = null
	dash_timer = 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	root_timer = 0.0
	stun_timer = 0.0
	silence_timer = 0.0
	reflect_timer = 0.0
	_applying_reflect = false
	mark_timer = 0.0
	_pending_dodge_shield = 0.0
	_spend_locked.clear()
	# HUOM: ability_ranks ja skill_points säilyvät — rankit ovat ottelun mittaisia.

	var now: float = arena.match_elapsed if arena != null \
		else Time.get_ticks_msec() / 1000.0
	if source != null and is_instance_valid(source) and source != self:
		source.profile.stats.kos += 1
		if source.red_camp_buff > 0.0:
			source.profile.stats.kos_during_red += 1
		if source.blue_camp_buff > 0.0:
			source.profile.stats.kos_during_blue += 1
		if source.baron_buff > 0.0:
			source.profile.stats.kos_during_baron += 1
		if source.dragon_buff > 0.0:
			source.profile.stats.kos_during_dragon += 1
		source.profile.add_score(30.0)
		source.add_ult(15.0)   # tappo on iso mutta ei puolta ulttia (oli 20)
		var assisted: Dictionary = {}
		for entry in _recent_damagers:
			if not is_instance_valid(entry.hero):
				continue
			if entry.hero == source or entry.hero == self:
				continue
			var helper_id: int = entry.hero.get_instance_id()
			if assisted.has(helper_id):
				continue
			if now - entry.time <= ASSIST_WINDOW and entry.hero.team != team:
				assisted[helper_id] = true
				entry.hero.profile.stats.assists += 1
				entry.hero.profile.add_score(15.0)
	_recent_damagers.clear()

	visible = false
	set_collision_layer_value(2, false)
	set_collision_mask_value(2, false)
	Fx.knockout_burst(arena, global_position, profile.color())
	AudioMgr.play("ko", 0.08, 0.0, global_position)
	arena.shake(0.3)
	knocked_out.emit(self, source)
	arena.on_hero_ko(self, source)


func _respawn() -> void:
	alive = true
	_reset_resource()
	hp = max_hp
	iframes = 2.0
	global_position = arena.map.spawn_point(team, profile.index)
	visible = true
	grabbed_by = null
	guard_radius = 0.0
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(1, true)   # varmista seinätörmäys (jos kuoli syöksyn aikana)
	_phase_walls = false
	for slot in cd:
		cd[slot] = 0.0
	_dodge_was_cooling = false   # ei valheellista "väistö valmis" -piippausta respawnissa
	_heartbeat_t = 0.0
	Fx.ring(arena, global_position, Palette.with_alpha(profile.color(), 0.9), 60.0, 0.5)
	AudioMgr.play("respawn")
	arena.on_hero_respawn(self)


## Palauttaa sankarin täyteen kuntoon erän alussa.
func reset_for_round(keep_ult_fraction := 0.5) -> void:
	alive = true
	visible = true
	_aiming_slot = ""
	_aim_active = false
	_ult_holding = false
	_beam_active = false
	_reset_resource()
	blue_buff = 0.0
	red_buff = 0.0
	red_camp_buff = 0.0
	blue_camp_buff = 0.0
	baron_buff = 0.0
	dragon_buff = 0.0
	void_stacks = 0
	void_stack_timer = 0.0
	void_stacker = null
	duel_marks = 0
	duel_mark_timer = 0.0
	duel_marker = null
	cc_immune_timer = 0.0
	frozen = 0.0
	piloting = false
	_recall_t = 0.0
	_fountain_heal_accum = 0.0
	_fountain_fx_t = 0.0
	_fountain_popup_t = 0.0
	hp = max_hp
	shield_hp = 0.0
	carrying = false
	iframes = 0.0
	respawn_timer = 0.0
	velocity = Vector2.ZERO
	kb_velocity = Vector2.ZERO
	_control_velocity = Vector2.ZERO
	dash_timer = 0.0
	slow_factor = 1.0
	slow_timer = 0.0
	haste_factor = 1.0
	haste_timer = 0.0
	root_timer = 0.0
	stun_timer = 0.0
	silence_timer = 0.0
	reflect_timer = 0.0
	_applying_reflect = false
	mark_timer = 0.0
	guard_timer = 0.0
	guard_radius = 0.0
	grabbed_by = null
	ult_charge = ult_charge * keep_ult_fraction
	_ult_ready_announced = ult_charge >= 100.0 and ult_unlocked()
	_pending_dodge_shield = 0.0
	_spend_locked.clear()
	# HUOM: ability_ranks ja skill_points säilyvät erien yli (ottelun mittaisia).
	_dodge_was_cooling = false
	_heartbeat_t = 0.0
	_deny_cd = 0.0
	for slot in cd:
		cd[slot] = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(1, true)   # varmista seinätörmäys (jos erä vaihtui syöksyn aikana)
	_phase_walls = false
	_recent_damagers.clear()
	global_position = arena.map.spawn_point(team, profile.index)


func is_threatened() -> bool:
	return hp < max_hp * 0.35


func hero_color() -> Color:
	return HeroDef.get_def(hero_id)["color"]


## Tähtäysviiva: piirtää sankarin edestä katkoviivan ja tähtäimen kun kykyä
## tähdätään tai latauskykyä ladataan. Lukee tilan sankarilta joka framessa.
class AimGuide:
	extends Node2D

	var hero = null

	func _ready() -> void:
		z_index = -1

	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if hero == null or not is_instance_valid(hero) or not hero.alive:
			return

		# Paluukanavointi: kasvava joukkuevärinen rengas + täyttyvä kaari ja
		# kiertävät riimut kertovat kanavoinnin etenemisen yhdellä silmäyksellä.
		var recall_t: float = hero._recall_t
		if recall_t > 0.0:
			var rfrac: float = clampf(recall_t / Hero.RECALL_TIME, 0.0, 1.0)
			var rcol: Color = Palette.glow(Palette.team(hero.team), 1.3)
			var rr: float = float(hero.radius) + 18.0 + 30.0 * rfrac
			draw_circle(Vector2.ZERO, rr, Palette.with_alpha(rcol, 0.06 + 0.06 * rfrac))
			draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU * rfrac, 40, rcol, 3.0)
			draw_arc(Vector2.ZERO, rr + 6.0, 0.0, TAU, 40,
				Palette.with_alpha(rcol, 0.30), 1.5)
			for i in range(4):
				var ra: float = _t * 1.8 + TAU * float(i) / 4.0
				var rp: Vector2 = Vector2(cos(ra), sin(ra)) * (rr - 8.0)
				var rune := PackedVector2Array([
					rp + Vector2(0, -7), rp + Vector2(5, 0),
					rp + Vector2(0, 7), rp + Vector2(-5, 0)])
				draw_colored_polygon(rune, Palette.with_alpha(rcol, 0.5 + 0.4 * rfrac))

		# Ultin alue-esikatselu (pidä-ja-vapauta, esim. Prisma)
		if hero._ult_holding and not hero._ult_ground_targeted():
			var ur: float = hero._ult_preview_radius()
			if ur > 0.0:
				var uc: Color = hero.hero_color()
				var up := 0.5 + 0.5 * sin(_t * 4.0)
				draw_circle(Vector2.ZERO, ur, Palette.with_alpha(uc, 0.07))
				draw_arc(Vector2.ZERO, ur, 0.0, TAU, 52,
					Palette.with_alpha(Palette.glow(uc, 1.3), 0.5 + up * 0.3), 3.0)
				draw_arc(Vector2.ZERO, ur * 0.6, 0.0, TAU, 40, Palette.with_alpha(uc, 0.3), 2.0)

		# Kanavoitava säde (Prisma)
		if hero._beam_active and hero.aim.length() > 0.1:
			var bdir: Vector2 = hero.aim.normalized()
			var bcol: Color = Color("6affa0") if hero._beam_heal else Palette.glow(hero.hero_color(), 1.3)
			var bstart: Vector2 = bdir * (hero.radius + 4.0)
			var bend: Vector2 = bdir * float(hero._beam_len)
			var bpulse := 0.7 + 0.3 * sin(_t * 22.0)
			draw_line(bstart, bend, Palette.with_alpha(bcol, 0.22), 12.0)
			draw_line(bstart, bend, Palette.with_alpha(bcol, 0.55), 6.0 * bpulse)
			draw_line(bstart, bend, Palette.with_alpha(Color.WHITE, 0.7), 2.0)
			draw_circle(bend, 8.0 * bpulse, Palette.with_alpha(bcol, 0.6))

		# Tähtäysviiva (pito-tähtää-kyvyt ja latauskyvyt)
		if hero._aim_active and hero.aim.length() > 0.1:
			var dir: Vector2 = hero.aim.normalized()
			var length: float = hero._aim_len
			var charge: float = clampf(hero._aim_charge, 0.0, 1.0)
			var col: Color = hero._aim_color
			var start: Vector2 = dir * (float(hero.radius) + 6.0)
			var tip: Vector2 = dir * length
			if hero._aim_width > 1.0:
				var side: Vector2 = dir.orthogonal() * hero._aim_width
				var lane := PackedVector2Array([start - side, tip - side, tip + side, start + side])
				draw_colored_polygon(lane, Palette.with_alpha(col, 0.075 + charge * 0.035))
				draw_line(start - side, tip - side, Palette.with_alpha(Palette.team(hero.team), 0.72), 2.0)
				draw_line(start + side, tip + side, Palette.with_alpha(Palette.team(hero.team), 0.72), 2.0)
			if hero._aim_radius > 1.0:
				var target_radius: float = hero._aim_radius
				var pulse := 0.72 + 0.28 * sin(_t * 7.0)
				var target_team: Color = Palette.team(hero.team)
				draw_circle(tip, target_radius, Palette.with_alpha(col, 0.07 + charge * 0.05))
				draw_arc(tip, target_radius, 0.0, TAU, 56,
					Palette.with_alpha(Palette.glow(col, 1.35), 0.55 + pulse * 0.28), 3.0)
				draw_arc(tip, target_radius + 5.0, 0.0, TAU, 56,
					Palette.with_alpha(target_team, 0.72), 2.0)
				draw_arc(tip, target_radius * 0.55, -PI * 0.5,
					-PI * 0.5 + TAU * pulse, 32, Palette.with_alpha(col, 0.38), 2.0)
				for cross_dir in [Vector2.RIGHT, Vector2.DOWN]:
					draw_line(tip - cross_dir * 10.0, tip + cross_dir * 10.0,
						Palette.with_alpha(Palette.glow(col, 1.4), 0.75), 2.0)
				if hero.profile != null and not hero.profile.is_bot:
					var owner_col: Color = hero.profile.color()
					for i in range(mini(hero.profile.index + 1, 4)):
						var mark_a := -0.35 + i * 0.24
						var mark_dir := Vector2.DOWN.rotated(mark_a)
						draw_line(tip + mark_dir * (target_radius - 7.0),
							tip + mark_dir * (target_radius + 9.0),
							Palette.glow(owner_col, 1.35), 2.5)
			var dist := start.distance_to(tip)
			var steps: int = int(dist / 16.0)
			for i in range(steps):
				var f := float(i) / maxf(float(steps), 1.0)
				var p: Vector2 = start.lerp(tip, f)
				var a: float = (0.14 + charge * 0.34) * (1.0 - f * 0.35)
				draw_circle(p, 2.0 + charge * 1.5, Palette.with_alpha(col, a))
			var ring_a: float = 0.35 + charge * 0.45
			draw_arc(tip, 12.0 + charge * 6.0, 0.0, TAU, 22, Palette.with_alpha(col, ring_a), 2.0)
			draw_circle(tip, 3.0 + charge * 2.0, Palette.with_alpha(col, ring_a))
