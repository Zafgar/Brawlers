class_name TeamBlackboard
extends RefCounted
## Joukkueen jaettu taktinen tilannekuva. Kaikki saman joukkueen botit
## lukevat tätä, jotta ne toimivat yhtenä ryhmänä: kuka kantaa reliikkiä,
## ketä suojataan, kuka johtaa rintamaa ja missä viholliset ovat.

var arena = null
var team := 0

var own_carrier: Hero = null       # oma reliikinkantaja (jos on)
var enemy_carrier: Hero = null     # vihollisen kantaja (jos on)
var lowest_ally: Hero = null       # eniten kärsinyt elossa oleva liittolainen
var frontline_ally: Hero = null    # lähimpänä vihollisia oleva liittolainen (johtaa rintamaa)
var protect_ally: Hero = null      # tärkein suojeltava (kantaja > tuki > kärsinyt)
var focus_target: Hero = null      # joukkueen keskitetyn tulen kohde (focus fire)
var threat_center := Vector2.ZERO  # elossa olevien vihollisten painopiste
var retreat_pos := Vector2.ZERO
var alert_timer := 0.0             # hetkellinen hälytystila (reliikki vaihtoi omistajaa)
var threatened_structure = null    # oma rakennus jota vihollissankari juuri uhkaa (MOBA)
var defender: Hero = null          # lähin liittolainen nimetty puolustamaan sitä

# MOBA-rotaatio: kun jokin linja on pahasti alakynnessä (vihollisia selvästi
# enemmän kuin puolustajia tai torni uhattuna ylivoimalla), taululle merkitään
# hätälinja ja sinne KUTSUTAAN apuun sopivimmat vapaat botit (jungle ensin,
# sitten tuki jonka carry on turvassa, sitten muut joiden oma linja on rauhassa).
# Kutsu poistuu kun kriisi laukeaa -> autetut palaavat omille linjoilleen.
var help_lane := ""                # hätälinja ("top"/"bottom", "" = ei kriisiä)
var help_pos := Vector2.ZERO       # piste jonne apu suunnataan
var helpers: Array = []            # apuun kutsutut sankarit (Hero)
var _help_timer := 0.0             # kriisiarvion tahdistus (ei joka framea)


func setup(p_arena, p_team: int) -> void:
	arena = p_arena
	team = p_team
	retreat_pos = arena.map.spawn_point(team, 0)


func update(delta: float) -> void:
	alert_timer = maxf(alert_timer - delta, 0.0)

	own_carrier = null
	enemy_carrier = null
	var carrier: Hero = arena.relic.carrier
	if carrier != null and is_instance_valid(carrier) and carrier.alive:
		if carrier.team == team:
			own_carrier = carrier
		else:
			enemy_carrier = carrier

	var allies: Array = arena.alive_allies(team)

	# Vihollisten painopiste — vain oikeat vihollissankarit (ei minioneja/
	# rakennuksia/olentoja), jotta uhka-arvio ja keskitetty tuli eivät vääristy.
	var enemies: Array = arena.enemy_heroes(team)
	if enemies.is_empty():
		threat_center = Vector2.ZERO
	else:
		var sum := Vector2.ZERO
		for enemy in enemies:
			sum += enemy.global_position
		threat_center = sum / enemies.size()

	# Eniten kärsinyt liittolainen
	lowest_ally = null
	var worst := 2.0
	for ally in allies:
		var frac: float = ally.hp / ally.max_hp
		if frac < worst:
			worst = frac
			lowest_ally = ally

	# Rintamaa johtava (lähimpänä vihollisia)
	frontline_ally = null
	if threat_center != Vector2.ZERO:
		var best_d := 1e20
		for ally in allies:
			var d: float = ally.global_position.distance_to(threat_center)
			if d < best_d:
				best_d = d
				frontline_ally = ally

	# Suojeltava: kantaja tärkein, sitten oma tuki, sitten kärsinyt
	protect_ally = own_carrier
	if protect_ally == null:
		for ally in allies:
			if HeroDef.get_def(ally.hero_id)["role"] == "Tuki":
				protect_ally = ally
				break
		if protect_ally == null:
			protect_ally = lowest_ally

	# Keskitetyn tulen kohde: vihollisen kantaja on aina focus; muuten
	# tapettavin kohde lähellä liittolaisten painopistettä (matala hp + lähellä
	# + arvokas takalinja). Botit iskevät tähän yhdessä.
	var prev_focus: Hero = focus_target
	focus_target = enemy_carrier
	if focus_target == null and not enemies.is_empty() and not allies.is_empty():
		var ally_center := Vector2.ZERO
		for ally in allies:
			ally_center += ally.global_position
		ally_center /= allies.size()
		var best_score := -1e20
		for enemy in enemies:
			var score: float = (1.0 - enemy.hp / enemy.max_hp) * 300.0
			score -= enemy.global_position.distance_to(ally_center) * 0.22
			if HeroDef.get_def(enemy.hero_id)["role"] in ["Tuki", "Ranger", "Mage"]:
				score += 55.0
			# Hystereesi: edellinen kohde saa bonuksen, jottei focus värise
			# kahden lähes samanarvoisen vihollisen välillä (nollaisi reaktiot).
			if enemy == prev_focus:
				score += 90.0
			if score > best_score:
				best_score = score
				focus_target = enemy

	# MOBA: uhattu oma rakennus + nimetty puolustaja. Rakennus on "uhattu" jos
	# vihollissankari on juuri (viim. 3 s) osunut siihen. Nimetään VAIN lähin
	# liittolainen puolustamaan -> koko joukkue ei romahda kotiin.
	threatened_structure = null
	defender = null
	if arena.mode == "moba":
		# Vahinkohistoria käyttää areenan peliaikaa. Sama kello on välttämätön
		# etenkin 16x/32x/64x-simulaatiossa; seinäkello teki puolustusikkunasta
		# virheellisen ja jätti uhatun tornin usein ilman nimettyä puolustajaa.
		var now: float = arena.match_elapsed
		var worst_pri := -1.0
		for st in arena.structures:
			var s := st as Structure
			if s == null or not s.alive or s.team != team:
				continue
			var hit := false
			for entry in s._recent_damagers:
				var h = entry.hero
				if is_instance_valid(h) and h.alive and not h.is_unit \
						and h.team != team and now - float(entry.time) < 3.0:
					hit = true
					break
			if not hit:
				continue
			var pri: float = s.max_hp   # nexus 1600 > torni 900 -> nexus etusijalla
			if pri > worst_pri:
				worst_pri = pri
				threatened_structure = s
		# Nimeä lähin TERVE liittolainen (matala hp vetäytyisi heti -> ei jäisi
		# puolustamaan). Jos yksikään ei ole terve, valitse silti lähin.
		if threatened_structure != null and not allies.is_empty():
			var spos: Vector2 = threatened_structure.global_position
			var best_d := 1.0e20
			var best_any: Hero = null
			var any_d := 1.0e20
			for ally in allies:
				var dd: float = ally.global_position.distance_to(spos)
				if dd < any_d:
					any_d = dd
					best_any = ally
				if ally.hp > ally.max_hp * 0.42 and dd < best_d:
					best_d = dd
					defender = ally
			if defender == null:
				defender = best_any

		# Linjakriisi + apuun kutsuttavat (tahdistettu, ei joka framea).
		_help_timer -= delta
		if _help_timer <= 0.0:
			_help_timer = 0.6
			_update_moba_crisis(allies, enemies)


## Arvioi linjojen tilanteen ja kutsuu apuun sopivimmat botit. Kriisi = linjalla
## on selvä vihollisylivoima (erotus >= 2) TAI oma torni siellä on uhattuna
## ylivoimalla (erotus >= 1). Apuun kutsutaan enintään 2 bottia kerralla, jotta
## koko joukkue ei hylkää omia linjojaan. Ihmisiä ei komenneta.
func _update_moba_crisis(allies: Array, enemies: Array) -> void:
	var prev_helpers: Array = helpers.filter(func(h): return is_instance_valid(h) and h.alive)
	var help_lane_prev := help_lane
	help_lane = ""
	help_pos = Vector2.ZERO
	helpers = []
	var mm := arena.map as MapMoba
	if mm == null:
		return

	var worst_lane := ""
	var worst_deficit := 0
	var worst_center := Vector2.ZERO
	var worst_tower_threat := false
	var threat_lane := _structure_lane(mm, threatened_structure)
	const LANE_NEAR := 480.0
	for lane in [MapMoba.TOP, MapMoba.BOTTOM]:
		var enemy_n := 0
		var enemy_sum := Vector2.ZERO
		for e in enemies:
			# Tukikohdassa (respawn/ostot) seisova ei ole "linjalla" — lähteet
			# ovat lähellä molempien linjojen päitä ja vääristäisivät laskun.
			if mm.is_in_own_sanctuary(e.global_position, e.team):
				continue
			if mm.distance_to_lane(e.global_position, str(lane)) < LANE_NEAR:
				enemy_n += 1
				enemy_sum += e.global_position
		if enemy_n == 0:
			continue
		var ally_n := 0
		for a in allies:
			if mm.is_in_own_sanctuary(a.global_position, a.team):
				continue
			# Matkalla oleva apuun kutsuttu lasketaan jo puolustajaksi: kriisi ei
			# "ratkea" siitä että auttaja saapuu linjan laidalle (ei sinkoilua).
			if mm.distance_to_lane(a.global_position, str(lane)) < LANE_NEAR \
					or (str(lane) == help_lane_prev and a in prev_helpers):
				ally_n += 1
		var tower_threat: bool = threat_lane == str(lane)
		var deficit: int = enemy_n - ally_n
		# Torniuhka laskee kynnystä: yksikin ylivoima riittää kriisiin.
		var is_crisis: bool = deficit >= 2 or (tower_threat and deficit >= 1)
		if not is_crisis:
			continue
		if deficit > worst_deficit or (deficit == worst_deficit and tower_threat):
			worst_deficit = deficit
			worst_lane = str(lane)
			worst_center = enemy_sum / float(enemy_n)
			worst_tower_threat = tower_threat

	if worst_lane == "":
		return
	help_lane = worst_lane
	# Apu suunnataan uhatulle tornille jos sellainen on, muuten vihollisryhmään.
	if worst_tower_threat and threatened_structure != null \
			and is_instance_valid(threatened_structure):
		help_pos = threatened_structure.global_position
	else:
		help_pos = worst_center

	# Valitse auttajat: botit jotka EIVÄT jo ole hätälinjalla, terveet, lähimmät.
	# Jungle on paras rotatoija; tuki lähtee vain jos sen carry on turvassa (tai
	# carry lähtee myös); muut vain jos oma linja on rauhassa.
	var need: int = clampi(worst_deficit - 1, 1, 2)
	var scored: Array = []
	for a in allies:
		if not (a.controller is BotBrain):
			continue
		if a.hp < a.max_hp * 0.4:
			continue
		# Linjalla jo valmiiksi oleva on puolustaja, ei "apu" — mutta saapunut
		# AUTTAJA pysyy tehtävässään kunnes kriisi oikeasti laukeaa (ei käänny
		# kotiin heti linjan laidalla).
		if mm.distance_to_lane(a.global_position, help_lane) < LANE_NEAR \
				and not a in prev_helpers:
			continue
		var brain: BotBrain = a.controller
		var score := 0.0
		match str(brain._moba_job):
			"jungle":
				score = 3.0
			"bottom":
				if str(brain._moba_duty) == "support":
					# Tuki irtoaa carrysta vain jos carry ei ole vaarassa.
					if not _ally_in_danger(_bottom_carry(allies)):
						score = 2.0
					else:
						continue
				else:
					score = 1.0 if not _lane_contested(mm, a, enemies) else 0.0
			_:
				score = 1.0 if not _lane_contested(mm, a, enemies) else 0.0
		if score <= 0.0:
			continue
		if a in prev_helpers:
			score += 1.5   # hystereesi: sama auttaja jatkaa, ei sinkoilua
		score -= a.global_position.distance_to(help_pos) / 2200.0
		scored.append({"hero": a, "score": score})
	scored.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	for i in range(mini(need, scored.size())):
		helpers.append(scored[i]["hero"])
	if helpers.is_empty():
		help_lane = ""


## Minkä linjan rakennus on (lähin linja); "" jos ei rakennusta.
func _structure_lane(mm: MapMoba, s) -> String:
	if s == null or not is_instance_valid(s):
		return ""
	var best := ""
	var best_d := 1.0e20
	for lane in [MapMoba.TOP, MapMoba.BOTTOM]:
		var d: float = mm.distance_to_lane(s.global_position, str(lane))
		if d < best_d:
			best_d = d
			best = str(lane)
	return best


## Bottom-duon carry; null jos ei löydy. Ihmispelaajan positiovalinta (lobby)
## tunnistetaan ensin — tuki ei saa hylätä IHMIS-carryakaan vaaraan.
func _bottom_carry(allies: Array) -> Hero:
	for a in allies:
		if str(a.profile.moba_position) == "carry":
			return a
	for a in allies:
		if not (a.controller is BotBrain):
			continue
		var brain: BotBrain = a.controller
		if str(brain._moba_job) == "bottom" and str(brain._moba_duty) != "support":
			return a
	return null


## Onko liittolainen vaarassa (vihollissankari lähellä tai matala HP)?
func _ally_in_danger(ally: Hero) -> bool:
	if ally == null or not is_instance_valid(ally) or not ally.alive:
		return false
	if ally.hp < ally.max_hp * 0.45:
		return true
	return not arena.heroes_in_circle(ally.global_position, 560.0, 1 - team, true, true).is_empty()


## Onko botin OMALLA linjalla vihollissankareita (linja kiistetty)?
func _lane_contested(mm: MapMoba, a: Hero, enemies: Array) -> bool:
	var brain: BotBrain = a.controller
	var lane := str(brain._moba_lane)
	if lane == "":
		return false
	for e in enemies:
		if mm.distance_to_lane(e.global_position, lane) < 480.0:
			return true
	return false


func on_relic_taken(_hero) -> void:
	alert_timer = 3.0


func on_enemy_has_relic(_hero) -> void:
	alert_timer = 4.0


func on_relic_free() -> void:
	alert_timer = 2.0
