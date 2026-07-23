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

# MOBA-makro: joukkueen yhteinen iso siirto. Kun jokin vihollislinja on täysin
# murrettu TAI loppupeli (>10 min) on käynnissä, vapaat terveet botit kutsutaan
# joko Baronille (iso tiimibuffi) tai ryhmätyöntöön murrettavimman vihollis-
# rakenteen linjalle aallon mukana. Puolustus ja apukutsut menevät aina edelle;
# ihmisiä ei komenneta. Hystereesi estää kutsun välkkymisen.
const MACRO_LATE_TIME := 600.0     # loppupeliraja makrokutsuille (sekunteina)
var macro_call := ""               # "" / "baron" / "push"
var macro_pos := Vector2.ZERO      # kutsun kohdepiste
var macro_target = null            # Baron (Critter) tai rakennus (Structure)
var macro_participants: Array = [] # kutsutut botit (Hero)
var _macro_timer := 0.0            # makroarvion tahdistus
var _macro_hold := 0.0             # hystereesi: tuore kutsu ei vaihdu heti


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
	# Häivetetty (varjoviitta) vihollinen puuttuu tilannekuvasta, ellei joku
	# liittolainen ole aivan sen vieressä (sama 160 px raja kuin botin näössä).
	var enemies: Array = arena.enemy_heroes(team)
	enemies = enemies.filter(func(e):
		if e.stealth_timer <= 0.0:
			return true
		for ally_h in allies:
			if ally_h.global_position.distance_to(e.global_position) <= 160.0:
				return true
		return false)
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
			var pri: float = s.max_hp   # nexus 2200 > tornit 1100–1450 -> nexus etusijalla
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

		# Makrokutsut (Baron / ryhmätyöntö) omalla, hitaammalla tahdillaan.
		_macro_timer -= delta
		_macro_hold = maxf(_macro_hold - delta, 0.0)
		if _macro_timer <= 0.0:
			_macro_timer = 0.9
			_update_moba_macro(allies, enemies)


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


## Makropäätös: Baron-kutsu kun jokin vihollislinja on kokonaan auki TAI
## loppupeli käynnissä, vähintään kolme tervettä vapaata bottia, Baron elossa
## eikä vihollisia sen lähellä (tai viholliset kuolleet). Baronin kaaduttua
## (tai kun se ei ole saatavilla) ryhmätyöntö: osallistujat kerääntyvät
## murrettavimman vihollisrakenteen linjalle aallon kanssa.
func _update_moba_macro(allies: Array, enemies: Array) -> void:
	var prev_call := macro_call
	var prev_target = macro_target
	var prev_participants: Array = macro_participants.filter(
		func(h): return is_instance_valid(h) and h.alive)
	macro_call = ""
	macro_pos = Vector2.ZERO
	macro_target = null
	macro_participants = []

	# Vapaat botit: ei puolustaja, ei apukutsussa, ei ihminen. Ihmisiä ei
	# koskaan komenneta; puolustus ja apurotaatio menevät makron edelle.
	var free_bots: Array = []
	var healthy := 0
	for a in allies:
		if not (a.controller is BotBrain):
			continue
		if a == defender or a in helpers:
			continue
		free_bots.append(a)
		if a.hp > a.max_hp * 0.55:
			healthy += 1

	var trigger: bool = float(arena.match_elapsed) > MACRO_LATE_TIME \
		or _any_enemy_lane_broken()
	if not trigger or free_bots.size() < 2:
		_macro_hold = 0.0
		return

	var want := ""
	var target = null
	var baron := _alive_baron()
	if baron != null and not _enemy_nexus_open() and healthy >= 3 \
			and _enemies_clear_of(enemies, baron.global_position, 700.0):
		want = "baron"
		target = baron
	if want == "":
		var push_target := _group_push_structure()
		if push_target != null and healthy >= 2:
			want = "push"
			target = push_target

	# Hystereesi: tuore kutsu ei vaihdu heti toiseksi niin kauan kuin sen
	# kohde on yhä olemassa (esim. Baron-taistelu ei keskeydy välkkyen).
	if want != prev_call and prev_call != "" and _macro_hold > 0.0 \
			and prev_target != null and is_instance_valid(prev_target) \
			and bool(prev_target.alive):
		want = prev_call
		target = prev_target
	if want == "" or target == null:
		_macro_hold = 0.0
		return
	if want != prev_call:
		_macro_hold = 6.0
		arena._sim_event("Makrokutsu (%s): %s" % [Game.team_name(team),
			"Baron" if want == "baron" else "ryhmätyöntö"])
	macro_call = want
	macro_target = target
	macro_pos = target.global_position
	# Osallistujat: vapaat terveehköt botit. Jo kutsussa oleva jatkaa matalammalla
	# kynnyksellä (ei sinkoilua edestakaisin parannusten/osumien rajalla).
	for a in free_bots:
		var join_frac := 0.4 if a in prev_participants else 0.5
		if a.hp > a.max_hp * join_frac:
			macro_participants.append(a)
	if macro_participants.size() < 2:
		macro_call = ""
		macro_target = null
		macro_pos = Vector2.ZERO
		macro_participants = []


## Baron-olento (arena boss critter) jos se on elossa, muuten null.
func _alive_baron() -> Critter:
	for c in arena.critters:
		var cr := c as Critter
		if cr != null and cr.alive and cr.kind == Critter.Kind.BOSS:
			return cr
	return null


## Onko jokin VIHOLLISEN linja kokonaan murrettu (kaikki tornit nurin)?
func _any_enemy_lane_broken() -> bool:
	for lane in [MapMoba.TOP, MapMoba.BOTTOM]:
		if _enemy_lane_towers_alive(str(lane)) == 0:
			return true
	return false


func _enemy_lane_towers_alive(lane: String) -> int:
	var n := 0
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != team \
				and s.kind == Structure.Kind.TOWER and s.lane_id == lane:
			n += 1
	return n


## Onko vihollisen nexus jo haavoittuvainen? Silloin Baronille ei kierretä —
## ryhmätyöntö suoraan nexukselle on aina arvokkaampi.
func _enemy_nexus_open() -> bool:
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != team \
				and s.kind == Structure.Kind.NEXUS:
			return not s.is_protected()
	return false


## Ei vihollissankareita pisteen lähellä — tai lähes koko vihollistiimi kuollut.
func _enemies_clear_of(enemies: Array, pos: Vector2, r: float) -> bool:
	if enemies.size() <= 1:
		return true
	for e in enemies:
		if e.global_position.distance_to(pos) < r:
			return false
	return true


## Ryhmätyönnön kohde: murrettavin haavoittuva vihollisrakennus. Avoin nexus on
## aina paras; muuten linja jolla on vähiten torneja pystyssä (kristalli = linja
## käytännössä murrettu, vain suoja jäljellä).
func _group_push_structure() -> Structure:
	var best: Structure = null
	var best_rank := 1 << 30
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == team or s.is_protected():
			continue
		var rank := 0
		match s.kind:
			Structure.Kind.NEXUS:
				rank = -1
			Structure.Kind.TOWER:
				rank = _enemy_lane_towers_alive(s.lane_id)
			_:
				rank = 0
		if rank < best_rank:
			best_rank = rank
			best = s
	return best


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
