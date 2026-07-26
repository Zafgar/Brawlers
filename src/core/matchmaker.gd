class_name Matchmaker
## Ranked-ottelun kokoonpanon rakentaja: ihmispelaajat pitävät paikkansa ja
## vapaat paikat täytetään RankedDB:n nimetyllä bottipopulaatiolla pelaajien
## rankin mukaan. Botit tuovat mukanaan oman nimensä ja rankinsa, joten
## tulostaulussa ja lobbyssä näkyy "Routavasara — Gold II" eikä "Botti 3".
##
## CO-OP-TASAPAINO
## ---------------
## Kun samalla sohvalla pelaa eri rankisia ihmisiä, ottelun kohderank on
## ihmisten rankien KESKIARVO ja joukkueiden voimasummat tasataan:
##
##     ally_bot_sum + human_sum(ally)  ~=  enemy_sum
##
## Vihollisjoukkue arvotaan ensin kohderankin ympäriltä (promo-sarjan aikana
## seuraavan tierin ALIMMASTA divisioonasta), jolloin sen voimasumma on tiedossa.
## Sen jälkeen liittolaisbotit valitaan ahneella ratkaisijalla: jokaiselle
## vapaalle paikalle otetaan jäljellä olevan vajeen keskiarvo ja populaatiosta
## siihen lähin vapaa botti, ja vaje päivitetään TODELLISELLA valitulla rankilla.
## Näin matalan rankin pelaaja korkean rankin kaverin rinnalla saa vahvat
## liittolaisbotit eikä ottelu ole yksipuolinen kumpaankaan suuntaan.
##
## LP jaetaan silti jokaiselle ihmiselle HÄNEN OMAN rankinsa mukaan suhteessa
## vihollisjoukkueen keskirankiin (RankedRules hoitaa kaavan), joten aloittelija
## ei kahmi kokeneen kaverin kyydissä kohtuuttomia pisteitä.

# Sama täyttöjärjestys kuin lobbyssä: jungle ja tuki ensin, sitten top ja carry.
const FILL_ORDER := ["jungle", "support", "top", "carry"]


# --- Rankien luku ---

## Yhden paikan ladder-rank: ensisijaisesti profiiliin merkitty, muuten
## linkitetyn käyttäjän rank tallennuksesta, muuten Wood IV.
static func seat_rank(profile: PlayerProfile) -> int:
	if profile.ranked_rank >= 0:
		return clampi(profile.ranked_rank, 0, BotRank.MAX_RANK)
	if profile.user_id != "":
		var user: Dictionary = RankedDB.get_user(profile.user_id)
		if not user.is_empty():
			return clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
	return 0


## Ottelun kohderank: ihmispelaajien rankien keskiarvo.
static func target_rank_for(humans: Array) -> int:
	if humans.is_empty():
		return 0
	var total := 0
	for entry in humans:
		var profile: PlayerProfile = entry
		total += seat_rank(profile)
	return clampi(int(round(float(total) / float(humans.size()))), 0, BotRank.MAX_RANK)


## Promo-sarjan vastustajakaista jos jollakin pelaajalla on sarja kesken
## (-1 = ei sarjaa). Sarjan ottelut pelataan seuraavan tierin ALINTA
## divisioonaa vastaan — juuri sitä porukkaa johon ollaan nousemassa.
static func promo_band_for(humans: Array) -> int:
	for entry in humans:
		var profile: PlayerProfile = entry
		if profile.user_id == "":
			continue
		var user: Dictionary = RankedDB.get_user(profile.user_id)
		if user.is_empty():
			continue
		var promo: Dictionary = {}
		var promo_raw: Variant = user.get("promo", {})
		if promo_raw is Dictionary:
			promo = promo_raw
		if RankedRules.promo_active(promo):
			return RankedRules.promo_band(int(user.get("rank", 0)))
	return -1


## Joukkueen keskimääräinen ladder-rank. LP-laskenta käyttää tätä
## VIHOLLISJOUKKUEEN arvona.
static func team_avg_rank(roster: Array, team: int) -> float:
	var total := 0.0
	var count := 0
	for entry in roster:
		var profile: PlayerProfile = entry
		if profile.team != team:
			continue
		total += float(seat_rank(profile))
		count += 1
	if count == 0:
		return 0.0
	return total / float(count)


## Merkitsee ihmispaikkojen rankit ja nimet tallennuksesta, jotta lobbyn
## rank-chipit ja LP-laskenta käyttävät samoja lukuja.
static func stamp_humans(roster: Array) -> void:
	for entry in roster:
		var profile: PlayerProfile = entry
		if profile.is_bot or profile.user_id == "":
			continue
		var user: Dictionary = RankedDB.get_user(profile.user_id)
		if user.is_empty():
			continue
		profile.ranked_rank = clampi(int(user.get("rank", 0)), 0, BotRank.MAX_RANK)
		profile.display_name = str(user.get("name", profile.display_name))


# --- Populaation haku ---

## Populaatio rankeittain indeksoituna (nopea haku täytön aikana).
static func _index_by_rank(pool: Array) -> Dictionary:
	var index: Dictionary = {}
	for entry in pool:
		var bot: Dictionary = entry
		var rank: int = clampi(int(bot.get("rank", 0)), 0, BotRank.MAX_RANK)
		if not index.has(rank):
			index[rank] = []
		var list: Array = index[rank]
		list.append(bot)
	return index


## Vapaat (vielä käyttämättömät) botit yhdeltä rankilta.
static func _free_at(by_rank: Dictionary, rank: int, used: Dictionary) -> Array:
	var found: Array = []
	if rank < 0 or rank > BotRank.MAX_RANK or not by_rank.has(rank):
		return found
	var list: Array = by_rank[rank]
	for entry in list:
		var bot: Dictionary = entry
		if not used.has(str(bot.get("name", ""))):
			found.append(bot)
	return found


## Lähin vapaa botti halutulta rankilta. Etsintä laajenee askel kerrallaan
## molempiin suuntiin ja suosii bottia jonka oma positio vastaa haettua.
static func _pick_bot(by_rank: Dictionary, want_rank: int, want_pos: String,
		used: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	for radius in range(BotRank.MAX_RANK + 1):
		var found: Array = []
		if radius == 0:
			found = _free_at(by_rank, want_rank, used)
		else:
			found = _free_at(by_rank, want_rank - radius, used)
			found.append_array(_free_at(by_rank, want_rank + radius, used))
		if found.is_empty():
			continue
		var matching: Array = []
		for entry in found:
			var bot: Dictionary = entry
			if str(bot.get("pos", "")) == want_pos:
				matching.append(bot)
		var take: Array = matching if not matching.is_empty() else found
		var chosen: Dictionary = take[rng.randi_range(0, take.size() - 1)]
		used[str(chosen.get("name", ""))] = true
		return chosen
	return {}


## Botin oma sankaripooli suodatettuna olemassa oleviin sankareihin.
static func _hero_pool(bot: Dictionary) -> Array:
	var pool: Array = []
	var raw: Variant = bot.get("hero_pool", [])
	if raw is Array:
		for hero_id in raw:
			var id := str(hero_id)
			if HeroDef.ORDER.has(id):
				pool.append(id)
	return pool


# --- Joukkueiden täyttö ---

## Ihanteelliset liittolaisrankit annetulle voimasummalle. Puhdas apufunktio
## (Phase B ja testit voivat kutsua tätä ilman populaatiota): jaetaan vaje
## tasan jäljellä oleville paikoille.
static func solve_ally_ranks(target_sum: int, slots: int) -> Array:
	var ranks: Array = []
	var remaining: int = target_sum
	for i in range(maxi(slots, 0)):
		var left: int = slots - i
		var want: int = clampi(int(round(float(remaining) / float(left))), 0, BotRank.MAX_RANK)
		ranks.append(want)
		remaining -= want
	return ranks


## Täyttää yhden joukkueen vapaat paikat boteilla.
## target_sum >= 0 : rankit valitaan niin että joukkueen bottisumma osuu
##                   tavoitteeseen (co-op-tasapaino).
## target_sum <  0 : rankit arvotaan base_rankin ympäriltä (+-1).
static func _fill_team(by_rank: Dictionary, used: Dictionary, rng: RandomNumberGenerator,
		team: int, slots: int, taken_pos: Dictionary, target_sum: int,
		base_rank: int) -> Array:
	var free_positions: Array = []
	for pos in FILL_ORDER:
		if not taken_pos.has(pos):
			free_positions.append(pos)
	var result: Array = []
	var remaining: int = target_sum
	for i in range(maxi(slots, 0)):
		var want: int = clampi(base_rank + rng.randi_range(-1, 1), 0, BotRank.MAX_RANK)
		if target_sum >= 0:
			var left: int = slots - i
			want = clampi(int(round(float(remaining) / float(left))), 0, BotRank.MAX_RANK)
		var pos := ""
		if not free_positions.is_empty():
			pos = str(free_positions.pop_front())

		var profile := PlayerProfile.new()
		profile.is_bot = true
		profile.device = -2
		profile.team = team
		profile.moba_position = pos
		var bot: Dictionary = _pick_bot(by_rank, want, pos, used, rng)
		if bot.is_empty():
			# Populaatio loppui kesken (ei pitäisi tapahtua 320 botilla).
			profile.display_name = "Haastaja %d" % (i + 1)
			profile.bot_rank = want
			profile.ranked_rank = want
		else:
			var rank: int = clampi(int(bot.get("rank", want)), 0, BotRank.MAX_RANK)
			profile.display_name = str(bot.get("name", "Haastaja"))
			profile.bot_rank = rank
			profile.ranked_rank = rank
			profile.hero_pool = _hero_pool(bot)
		# Vaje päivitetään TODELLISELLA rankilla, jotta seuraavat paikat
		# korjaavat edellisen poiminnan heiton.
		remaining -= profile.ranked_rank
		result.append(profile)
	return result


## Rakentaa ranked-ottelun täyden kokoonpanon.
## humans      : PlayerProfile-oliot, jotka pitävät joukkueensa ja paikkansa
## team_size   : paikkoja per joukkue (4)
## target_rank : ottelun kohderank (yleensä ihmisten keskiarvo)
## promo_band  : promo-sarjan vastustajakaista tai -1
static func build_ranked_roster(humans: Array, team_size: int, target_rank: int,
		promo_band: int) -> Array:
	var by_rank: Dictionary = _index_by_rank(RankedDB.ensure_bots())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used: Dictionary = {}

	var human_sum: Array = [0, 0]
	var human_count: Array = [0, 0]
	var taken_pos: Array = [{}, {}]
	for entry in humans:
		var profile: PlayerProfile = entry
		var team: int = clampi(profile.team, 0, 1)
		human_count[team] = int(human_count[team]) + 1
		human_sum[team] = int(human_sum[team]) + seat_rank(profile)
		if profile.moba_position != "":
			var positions: Dictionary = taken_pos[team]
			positions[profile.moba_position] = true

	# Pelaajajoukkue = se jossa on eniten ihmisiä (tasatilanteessa sininen).
	var ally: int = 0 if int(human_count[0]) >= int(human_count[1]) else 1
	var enemy: int = 1 - ally
	var enemy_base: int = promo_band if promo_band >= 0 else target_rank

	# 1) Vihollisbotit ensin — ne määräävät tavoitellun voimasumman.
	var enemy_slots: int = maxi(team_size - int(human_count[enemy]), 0)
	var enemy_bots: Array = _fill_team(by_rank, used, rng, enemy, enemy_slots,
		taken_pos[enemy], -1, enemy_base)
	var enemy_sum: int = int(human_sum[enemy])
	for entry in enemy_bots:
		var profile: PlayerProfile = entry
		enemy_sum += profile.ranked_rank

	# 2) Liittolaisbotit tasaamaan summat: ally_bot_sum = enemy_sum - human_sum.
	var ally_slots: int = maxi(team_size - int(human_count[ally]), 0)
	var ally_bots: Array = _fill_team(by_rank, used, rng, ally, ally_slots,
		taken_pos[ally], enemy_sum - int(human_sum[ally]), target_rank)

	var roster: Array = []
	roster.append_array(humans)
	roster.append_array(ally_bots)
	roster.append_array(enemy_bots)
	# Indeksit uusiksi: ne määräävät tunnusvärin ja spawn-paikan.
	for i in range(roster.size()):
		var profile: PlayerProfile = roster[i]
		profile.index = i
	return roster


## Varmistaa että roster on ranked-kelpoinen ennen ottelua. Idempotentti: jos
## lobby on jo rakentanut kokoonpanon, tämä vain päivittää ihmisten rankit.
static func prepare(roster: Array, team_size: int) -> Array:
	stamp_humans(roster)
	var humans: Array = []
	for entry in roster:
		var profile: PlayerProfile = entry
		if not profile.is_bot:
			humans.append(profile)
	if humans.is_empty() or roster.size() >= team_size * 2:
		return roster
	return build_ranked_roster(humans, team_size, target_rank_for(humans),
		promo_band_for(humans))
