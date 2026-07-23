class_name BotRank
## Ranking-tasot = bottivaikeudet. Kahdeksan tasoa (Wood -> Challenger), joissa
## kussakin 4 divisioonaa (IV = alin, I = ylin) -> 32-portainen jatkuva
## vaikeusasteikko (rank 0 = Wood IV ... 31 = Challenger I).
##
## Sama asteikko toimii myöhemmin pelaajan ranking-tasona (save/load): pelaaja
## nousee divisioonia voittamalla oman tasonsa botteja vastaan. Asteikko on
## rakennettu niin, että alempi rank häviää ylemmälle (monotoniset parametrit),
## minkä simulaatio-laddertesti varmistaa.

const TIER_NAMES := [
	"Wood", "Bronze", "Silver", "Gold",
	"Platinum", "Diamond", "Champion", "Challenger",
]
const DIVISIONS := 4
const MAX_RANK := 31               # TIER_NAMES.size() * DIVISIONS - 1
const ROMAN := ["IV", "III", "II", "I"]

# Vanhat 6 vaikeustasoa (0-5) vastaavina rankeina — vanhat valikot/simit
# jatkavat toimintaansa tällä kartalla.
const LEGACY_LEVEL_RANKS := [1, 7, 13, 19, 25, 31]


## Rankin taso (0..7).
static func tier_of(rank: int) -> int:
	return clampi(rank, 0, MAX_RANK) / DIVISIONS


## Rankin divisioona roomalaisena (IV = alin, I = ylin).
static func division_of(rank: int) -> String:
	return ROMAN[clampi(rank, 0, MAX_RANK) % DIVISIONS]


## Näyttönimi, esim. "Gold II".
static func rank_name(rank: int) -> String:
	return "%s %s" % [TIER_NAMES[tier_of(rank)], division_of(rank)]


## Normalisoitu vaikeus 0..1 (Wood IV = 0, Challenger I = 1).
static func t(rank: int) -> float:
	return clampi(rank, 0, MAX_RANK) / float(MAX_RANK)


## Tason (0..7) oletusrank valikoihin: divisioona III (toiseksi alin).
static func tier_default_rank(tier: int) -> int:
	return clampi(tier, 0, TIER_NAMES.size() - 1) * DIVISIONS + 1


## Vanha 6-portainen taso (0-5) -> rank.
static func from_legacy_level(level: int) -> int:
	return LEGACY_LEVEL_RANKS[clampi(level, 0, 5)]


## Rank -> lähin vanha 6-portainen taso (telemetria/raportit).
static func to_legacy_level(rank: int) -> int:
	return clampi(roundi(t(rank) * 5.0), 0, 5)
