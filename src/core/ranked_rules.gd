class_name RankedRules
## Ranked-tilan LP- ja ylennyssäännöt. Kaikki funktiot ovat PUHTAITA: ne lukevat
## tilan sanakirjasta ja palauttavat uuden tilan + yhteenvedon koskematta
## tallennukseen. Näin RankedDB, käyttöliittymä ja testit voivat kutsua samoja
## sääntöjä ilman sivuvaikutuksia.
##
## Rank on BotRankin 32-portainen asteikko (0 = Wood IV ... 31 = Challenger I).
## Jokaisella rankilla on 0..99 LP. Sadasta LP:stä noustaan:
##   * saman tierin sisällä (esim. Wood IV -> Wood III) heti, LP putoaa 25:een
##   * tierin rajan yli (esim. Wood I -> Bronze IV) vasta voitetun PROMO-SARJAN
##     jälkeen: paras kolmesta seuraavan tierin alinta divisioonaa vastaan.
##
## Tila-sanakirja (sama muoto kuin RankedDB:n käyttäjärivi):
##   {"rank": int, "lp": int, "streak": int, "promo": Dictionary, "shield": int}
## promo on tyhjä kun sarjaa ei ole kesken, muuten
##   {"target_rank": int, "wins": int, "losses": int, "games": Array[bool]}

const LP_MAX := 100              # 100 LP = ylennysraja (LP itsessään on 0..99)
const BASE_WIN := 20             # voiton perus-LP
const BASE_LOSS := 16            # tappion perus-LP
const MULT_SLOPE := 0.12         # yksi rank-porras eroa = 12 % kertoimeen
const MULT_MIN := 0.6
const MULT_MAX := 1.6
const STREAK_MIN := 3            # putkibonus alkaa kolmannesta voitosta
const STREAK_STEP := 2           # +2 LP per voitto putken jatkuessa
const STREAK_CAP := 6            # bonus ei kasva tästä ylös
const PROMO_LP := 25             # ylennyksen jälkeinen LP uudella rankilla
const PROMO_FAIL_LP := 75        # kaatuneen promo-sarjan jälkeinen LP
const DEMOTE_LP := 70            # putoamisen jälkeinen LP alemmalla rankilla
const SERIES_TARGET := 2         # paras kolmesta = 2 voittoa tai 2 tappiota
const SERIES_LENGTH := 3
const SHIELD_GAMES := 1          # armonpelit LP 0:ssa ennen pudotusta


# --- Kertoimet ---

## Voiton LP-kerroin: vahvempaa vastustajajoukkuetta vastaan voittaminen
## maksaa enemmän, heikompaa vastaan vähemmän.
static func win_mult(own_rank: int, enemy_avg_rank: float) -> float:
	return clampf(1.0 + MULT_SLOPE * (enemy_avg_rank - float(own_rank)), MULT_MIN, MULT_MAX)


## Tappion kerroin on voittokertoimen käänteisluku: heikommalle häviäminen
## sattuu enemmän, vahvemmalle häviäminen vähemmän.
static func loss_mult(own_rank: int, enemy_avg_rank: float) -> float:
	return clampf(1.0 / win_mult(own_rank, enemy_avg_rank), MULT_MIN, MULT_MAX)


## Putkibonus: kolmannesta peräkkäisestä voitosta alkaen +2 LP per voitto,
## enintään +6 LP.
static func streak_bonus(win_streak: int) -> int:
	if win_streak < STREAK_MIN:
		return 0
	return clampi((win_streak - STREAK_MIN + 1) * STREAK_STEP, 0, STREAK_CAP)


## Voiton LP-tuotto (putki mukaan luettuna).
static func win_gain(own_rank: int, enemy_avg_rank: float, win_streak: int) -> int:
	var gain: int = int(round(float(BASE_WIN) * win_mult(own_rank, enemy_avg_rank)))
	return gain + streak_bonus(win_streak)


## Tappion LP-menetys positiivisena lukuna.
static func loss_drop(own_rank: int, enemy_avg_rank: float) -> int:
	return int(round(float(BASE_LOSS) * loss_mult(own_rank, enemy_avg_rank)))


# --- Tier-rajat ja promo-sarjat ---

## Ylittääkö nousu tästä rankista tierin rajan (= vaatii promo-sarjan)?
static func crosses_tier(rank: int) -> bool:
	if rank >= BotRank.MAX_RANK:
		return false
	return BotRank.tier_of(rank + 1) != BotRank.tier_of(rank)


## Promo-sarjan vastustajakaista: SEURAAVAN tierin alin divisioona.
## Esim. Wood I (rank 3) -> Bronze IV (rank 4). Matchmaker käyttää tätä.
static func promo_band(rank: int) -> int:
	var target: int = clampi(rank + 1, 0, BotRank.MAX_RANK)
	return BotRank.tier_of(target) * BotRank.DIVISIONS


## Onko promo-sarja kesken?
static func promo_active(promo: Dictionary) -> bool:
	return promo.has("target_rank")


## Kesken olevan sarjan tilanne lyhyesti, esim. "1–1" (pelaajalle näkyvä).
static func promo_score(promo: Dictionary) -> String:
	if not promo_active(promo):
		return ""
	return "%d–%d" % [int(promo.get("wins", 0)), int(promo.get("losses", 0))]


## Uuden käyttäjän/tilan pohja.
static func new_state(rank := 0) -> Dictionary:
	return {
		"rank": clampi(rank, 0, BotRank.MAX_RANK),
		"lp": 0, "streak": 0, "promo": {}, "shield": 0,
	}


# --- Ottelun vaikutus ---

## Yhden ottelun vaikutus ranked-tilaan. PUHDAS: ei muuta annettua sanakirjaa.
##
## Palautettu yhteenveto sisältää sekä ENNEN- että JÄLKEEN-arvot; kentät
## rank_after / lp_after / streak_after / promo / shield ovat suoraan uusi tila.
## "delta" on KAAVAN tuottama LP-muutos (promo-sarjan otteluissa 0) — todellinen
## lopputulos luetaan aina lp_afterista ja rank_afterista.
static func apply_match(state: Dictionary, won: bool, enemy_avg_rank: float) -> Dictionary:
	var rank: int = clampi(int(state.get("rank", 0)), 0, BotRank.MAX_RANK)
	var lp: int = clampi(int(state.get("lp", 0)), 0, LP_MAX)
	var streak: int = int(state.get("streak", 0))
	var shield: int = maxi(int(state.get("shield", 0)), 0)
	var promo: Dictionary = {}
	var promo_raw: Variant = state.get("promo", {})
	if promo_raw is Dictionary:
		promo = promo_raw
	promo = promo.duplicate(true)

	var res: Dictionary = {
		"rank_before": rank,
		"lp_before": lp,
		"streak_before": streak,
		"won": won,
		"enemy_avg_rank": enemy_avg_rank,
		"delta": 0,
		"streak_bonus": 0,
		"mult": 1.0,
		"promoted": "",          # "" | "division" | "tier"
		"demoted": false,
		"promo_failed": false,
		"promo_state": "",       # "" | "started" | "running" | "won" | "lost"
		"shield_used": false,
		"rank_after": rank,
		"lp_after": lp,
		"streak_after": streak,
		"promo": promo,
		"shield": shield,
	}

	# Putki: positiivinen = voittoputki, negatiivinen = tappioputki.
	if won:
		streak = maxi(streak, 0) + 1
	else:
		streak = mini(streak, 0) - 1
	res["streak_after"] = streak

	if promo_active(promo):
		# Promo-sarjan aikana LP jäädytetään sataan; ratkaisu tulee sarjasta.
		var games: Array = []
		var games_raw: Variant = promo.get("games", [])
		if games_raw is Array:
			games = games_raw
		games.append(won)
		var wins: int = int(promo.get("wins", 0)) + (1 if won else 0)
		var losses: int = int(promo.get("losses", 0)) + (0 if won else 1)
		var target: int = clampi(int(promo.get("target_rank", rank + 1)), 0, BotRank.MAX_RANK)
		promo["games"] = games
		promo["wins"] = wins
		promo["losses"] = losses
		promo["target_rank"] = target
		if wins >= SERIES_TARGET:
			rank = target
			lp = PROMO_LP
			shield = 0
			promo = {}
			res["promoted"] = "tier"
			res["promo_state"] = "won"
		elif losses >= SERIES_TARGET:
			# Sarja kaatui: LP tippuu 75:een ja sarjan voi yrittää uudelleen
			# heti kun LP on taas 100.
			lp = PROMO_FAIL_LP
			promo = {}
			res["promo_failed"] = true
			res["promo_state"] = "lost"
		else:
			lp = LP_MAX
			res["promo_state"] = "running"
		res["rank_after"] = rank
		res["lp_after"] = lp
		res["streak_after"] = streak
		res["promo"] = promo
		res["shield"] = shield
		return res

	if won:
		var bonus: int = streak_bonus(streak)
		var mult: float = win_mult(rank, enemy_avg_rank)
		var gain: int = int(round(float(BASE_WIN) * mult)) + bonus
		res["mult"] = mult
		res["streak_bonus"] = bonus
		res["delta"] = gain
		lp += gain
		shield = 0
		if lp >= LP_MAX:
			if rank >= BotRank.MAX_RANK:
				lp = LP_MAX - 1                     # huipulla ei ole mihin nousta
			elif crosses_tier(rank):
				lp = LP_MAX
				promo = {"target_rank": rank + 1, "wins": 0, "losses": 0, "games": []}
				res["promo_state"] = "started"
			else:
				rank += 1
				lp = PROMO_LP
				res["promoted"] = "division"
	else:
		var mult: float = loss_mult(rank, enemy_avg_rank)
		var drop: int = int(round(float(BASE_LOSS) * mult))
		res["mult"] = mult
		res["delta"] = -drop
		lp -= drop
		if lp < 0:
			if rank <= 0:
				lp = 0                              # Wood IV on pohja
			elif shield < SHIELD_GAMES:
				shield += 1                         # yksi armonpeli LP 0:ssa
				lp = 0
				res["shield_used"] = true
			else:
				rank -= 1
				lp = DEMOTE_LP
				shield = 0
				res["demoted"] = true

	res["rank_after"] = clampi(rank, 0, BotRank.MAX_RANK)
	res["lp_after"] = clampi(lp, 0, LP_MAX)
	res["promo"] = promo
	res["shield"] = shield
	return res


# --- Kevyt botti-ladder ---

## Voittotodennäköisyys rank-erosta (bottien keskinäinen ladder-simulaatio).
## p = 1 / (1 + e^(-(rA - rB) * 0.35)) — tasaväkisillä 50 %, kolmen portaan
## erolla noin 74 %.
static func win_chance(rank_a: int, rank_b: int) -> float:
	return 1.0 / (1.0 + exp(-float(rank_a - rank_b) * 0.35))


## Yksinkertaistettu LP-päivitys boteille: ei promo-sarjoja eikä kilpiä, vain
## suora nousu/lasku samoilla peruskaavoilla. Palauttaa {"rank", "lp"}.
static func simple_step(rank: int, lp: int, won: bool, enemy_rank: int) -> Dictionary:
	var r: int = clampi(rank, 0, BotRank.MAX_RANK)
	var points: int = clampi(lp, 0, LP_MAX - 1)
	if won:
		points += win_gain(r, float(enemy_rank), 0)
		if points >= LP_MAX:
			if r >= BotRank.MAX_RANK:
				points = LP_MAX - 1
			else:
				r += 1
				points = PROMO_LP
	else:
		points -= loss_drop(r, float(enemy_rank))
		if points < 0:
			if r <= 0:
				points = 0
			else:
				r -= 1
				points = DEMOTE_LP
	return {"rank": r, "lp": clampi(points, 0, LP_MAX - 1)}


# --- Pelaajalle näkyvät tekstit ---

## Rankin ja LP:n tiivistys, esim. "Silver II · 42 LP" tai promo-sarjan tila.
static func rank_label(rank: int, lp: int, promo: Dictionary) -> String:
	if promo_active(promo):
		return "%s · PROMO %s" % [BotRank.rank_name(rank), promo_score(promo)]
	return "%s · %d LP" % [BotRank.rank_name(rank), lp]


## Ottelun tuloksen otsikko (Phase B piirtää oman version tästä tiedosta).
static func result_headline(res: Dictionary) -> String:
	var promoted: String = str(res.get("promoted", ""))
	if promoted == "tier":
		return "YLENNYS! %s" % BotRank.rank_name(int(res.get("rank_after", 0)))
	if promoted == "division":
		return "DIVISIOONA YLÖS — %s" % BotRank.rank_name(int(res.get("rank_after", 0)))
	if bool(res.get("promo_failed", false)):
		return "PROMO-SARJA KAATUI — YRITÄ UUDELLEEN"
	if str(res.get("promo_state", "")) == "started":
		return "PROMO-SARJA ALKAA — PARAS KOLMESTA"
	if str(res.get("promo_state", "")) == "running":
		var promo: Dictionary = {}
		var promo_raw: Variant = res.get("promo", {})
		if promo_raw is Dictionary:
			promo = promo_raw
		return "PROMO-SARJA %s" % promo_score(promo)
	if bool(res.get("demoted", false)):
		return "PUDOTUS — %s" % BotRank.rank_name(int(res.get("rank_after", 0)))
	if bool(res.get("shield_used", false)):
		return "SUOJAPELI — RANK SÄILYI"
	var delta: int = int(res.get("delta", 0))
	if delta >= 0:
		return "+%d LP" % delta
	return "%d LP" % delta
