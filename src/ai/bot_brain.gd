class_name BotBrain
extends RefCounted
## Botin aivot. Toteuttaa saman rajapinnan kuin DeviceInput, joten Hero ei
## erota bottia ihmisestä. Päätökset perustuvat sankarin ROOLIIN, joukkueen
## jaettuun TeamBlackboard-tilannekuvaan ja utility-arviointiin.
##
## Roolit ohjaavat käytöstä:
##   Tankki   — johtaa rintamaa, peelaa suojeltavan edestä
##   Tuki     — pysyy suojeltavan takana, parantaa ja buffaa, välttää etulinjaa
##   Assassin — kiertää takalinjaan, iskee heikoimpia, vetäytyy ajoissa
##   Fighter  — lähitaistelu keskietäisyydeltä, kestävä
##   Mage     — keskietäisyys, alueenhallinta
##   Ranger   — pitää etäisyyttä ja kitettää
##
## Vaikeus tulee ranking-asteikolta (BotRank: Wood IV .. Challenger I) ja
## säätää ensisijaisesti taitoa: reaktioaikaa, tähtäysvirhettä, ennakointia,
## väistämistä ja kykyjen käyttöä. Vain huippupää (Champion IV -> Challenger I)
## huijaa avoimesti myös tilastoilla (vahinko/kesto/jäähdytykset/vauhti).

enum Mode { GET_RELIC, ATTACK_CARRIER, ESCORT, CARRY, RETREAT, FIGHT, SUPPORT, GET_BUFF }

const BACKLINE_ROLES := ["Tuki", "Ranger", "Mage"]
# Loppupelin raja sekunteina — sama kuin Arena.LATE_WAVE_TIME (pidä synkassa):
# aallot kasvavat ja jungler liittyy piiritykseen gank-partioinnin sijaan.
const LATE_PUSH_TIME := 840.0
# PIIRITYSSÄÄNTÖ (Structure.take_damage): rakennukseen sattuu vain sen OMAN
# kantaman sisältä. Botin on siis astuttava kehän sisään — muuten pitkän
# kantaman sankari (Scout 1050, Quill 560+) asemoituisi omalle kantamalleen ja
# plinkkaisi tyhjää loputtomiin. Piiritysasemointi leikataan tällä marginaalilla
# kehän sisäpuolelle, jotta pieni liike ei työnnä ulos vahinkoalueelta.
const SIEGE_STANDOFF := 40.0
# VOITETUN TAISTELUN IKKUNA sekunteina: kuinka kauan kaadetun vastustajan
# jälkeen rakenne on käytännössä ilmainen. Ikkuna on sama kaikilla rankeilla —
# ero syntyy siitä KÄYTTÄÄKÖ botti sen (convert_skill).
const CONVERT_WINDOW := 7.0
# Säde jolta vihollissankarit lasketaan taisteluikkunan seurantaan.
const FIGHT_SCAN := 820.0
# Piiritys on "kesken" kun murrettava rakenne on tämän osuuden alle HP:staan:
# puolikkaalta tornilta ei lähdetä kauppaan eikä paluukanavointiin.
const SIEGE_FINISH_HP := 0.5
# SEISONTAVAHTI (rank-neutraali, ks. _tick_stall_guard). Ikkuna ja matka on
# valittu niin, että normaali pelaaminen ei koskaan laukaise vahtia: hitainkin
# asemointi (piiritysseisonta aallon takana, leirin odotus, kiting) siirtää
# sankaria selvästi yli STALL_DIST:n STALL_WINDOW:n aikana.
const STALL_WINDOW := 7.0        # sekuntia ilman todellista etenemistä
const STALL_DIST := 150.0        # px: tätä lyhyempi siirtymä ei ole etenemistä
const STALL_ESCALATE := 2        # monesko peräkkäinen laukeama ohjaa pyhäkköön
const STALL_GOAL_TIME := 6.0     # kuinka kauan pakotettu maali on voimassa

var level := 1                  # vanha 6-portainen taso (telemetria: ai_level)
var rank := 13                  # ranking-porras 0..31 (BotRank: Wood IV .. Challenger I)

# Vaikeustasoparametrit
var reaction := 0.28
var aim_error_deg := 9.0
var decision_interval := 0.4
var aim_time := 0.5             # tähdättävän skillshotin pitoaika (pito -> viiva -> laukaisu)
var dodge_chance := 0.35
var ability_chance := 0.6
var ult_chance := 0.9
var prediction := 0.5
var aggression := 1.0           # kuinka suuren osan ajasta botti oikeasti hyökkää
var buff_focus := 0.5           # kuinka innokkaasti/kaukaa botti hakee buffeja
var buff_deny := 0.0            # kuinka herkästi botti rikkoo vihollisen buffin
var focus_fire := 0.0           # kuinka hyvin botti keskittää tulen joukkueen kohteeseen
var patience := 0.0             # assassiinin kärsivällisyys (odottaa hyvää avausta)
var self_preserve := 0.0        # kuinka herkästi botti pakenee kyvyillä vaarassa
var jungle_focus := 0.0         # kuinka aktiivisesti botti tunnistaa ja farmaa viidakon leirit/pomon
var farm_skill := 0.0           # linjafarmi: korkea taso hakee matalan HP:n last hitit
var retreat_frac := 0.25        # HP-osuus jonka alla botti vetäytyy taistelusta
var kite_skill := 0.0           # kaukotaistelijan etäisyydenpito taistelussa (kiting)
var combo_skill := 0.0          # muistaako avaajan kohteen ja käyttääkö oikean jatkokyvyn
var cooldown_discipline := 0.0  # säästääkö liikkuvuutta/pakoa ja välttääkö tuplakastit
var tower_judgement := 0.0      # kuinka tarkasti botti arvioi aallon, aggron ja poistumistien
var macro_obedience := 1.0      # todennäköisyys totella joukkuekutsuja (apu/baron/ryhmätyöntö)
var defense_delay := 0.0        # sekunteja ennen kuin nimetty puolustaja reagoi kriisiin
var siege_focus := 1.0          # pysyykö botti rakennuskohteessa vai lähteekö puolustajan perään
var cover_skill := 0.0          # ottaako melee suojaa minioniaallon takaa kaukopokea vastaan

# VOITTOEHTOKERROS (win condition). Mitattu vika: ranking jakoi HENGISSÄ
# SÄILYMISEN ennen VOITTAMISTA. Perääntyminen, kauppareissut, väistö ja
# objektiivikierrokset vetävät botin POIS rakenteilta, kun taas Wood seisoo
# linjassa ja hakkaa tornia — joten alempi rank kaatoi ladderissa ENEMMÄN
# rakenteita ja voitti pareittain ylemmän. Nämä kolme säädintä antavat jokaiselle
# portaalle oman, alempaa PAREMMAN tavan muuttaa etu rakenteiksi. Ne eivät lisää
# vahinkoa: ne ratkaisevat MISSÄ botti seisoo ja MILLOIN se lähtee pois.
var push_skill := 0.0           # tunnistaako ilmaisen rakenteen ja jatkaako piiritystä
var convert_skill := 0.0        # kääntyykö voitetusta taistelusta suoraan rakenteeseen
var tempo_discipline := 0.0     # lähteekö linjalta vain kun poistuminen maksaa vähemmän kuin tuo

# DIVISIOONAKERROS: keskittymiskatkot. Jokainen päätöstikki arpoo virheen, ja
# osuma vie botin lyhyeen katkokseen (_lapse_t): ei kykyjä, harva perusisku,
# harhaileva liike. Tämä on ainoa säädin joka tekee KAIKISTA 32 portaasta eri
# vahvoja — mekaaninen taito on jo lähes katossa Platinumissa, joten
# divisioonaerot syntyvät nimenomaan käytettävyydestä (uptime/johdonmukaisuus).
# Virheet KERTAANTUVAT ottelun mitassa: 0.34 vs 0.25 tarkoittaa satoja
# menetettyjä sekunteja tehokasta peliaikaa 20 minuutissa.
var mistake_chance := 0.0       # todennäköisyys/päätös ajautua keskittymiskatkoon

# TASOPORTIT (tier gates): kyky-lukitukset joita _init soveltaa jatkuvien
# käyrien PÄÄLLE. Nämä vain LEIKKAAVAT alempia tasoja, joten monotonisuus
# säilyy — ylempi rank ei koskaan menetä mitään mitä alemmalla on.
var can_dragon := true          # osallistuuko Dragoniin (Silver+)
var can_baron := true           # osallistuuko Baroniin (Gold+)
var shop_random_chance := 0.0   # todennäköisyys ostaa satunnainen item buildin sijaan
var shop_trip_cooldown := 35.0  # kauppareissujen väli sekunteina (Wood = ei koskaan)

# Huippupään huijaukset: poikkeavat 1.0:sta vasta rankista 24 (Champion IV)
# ylöspäin, portaattomasti Challenger I:een. Hero lukee kertoimet setup()issa.
var damage_mult := 1.0          # aiheutettu vahinko
var damage_taken_mult := 1.0    # otettu vahinko
var cooldown_mult := 1.0        # jäähdytysten kerroin
var ult_gain_mult := 1.0        # ultin latautuminen
var speed_mult := 1.0           # liikkumisnopeus

# Roolikohtaiset (asetetaan ensimmäisellä päivityksellä)
var _role := ""
var _pref_range := 300.0
var _basic_range := 420.0
var _is_tank := false
var _is_support := false
var _is_assassin := false
var _is_ranged := false
var _is_jungler_role := false
var _moba_job := ""
var _moba_lane := ""
var _moba_duty := ""             # bottom-duon työnjako: "carry"/"support" ("" = roolin mukaan)
var _gank_victim: Hero = null    # tilaisuusgankin lukittu uhri (hystereesi)
var _gank_gate := Vector2.INF    # lukitun uhrin gank-portti
var _moba_goal := Vector2.INF
var _lane_returning := false      # laner ajautui liian kauas omalta kaareltaan

var _hero: Hero = null
var _mode: int = Mode.FIGHT
var _target: Hero = null
var _buff_target = null          # tavoiteltu FieldBuff (GET_BUFF-tilassa)
var _jungle_target: Hero = null  # tavoiteltu viidakko-olento (leiri/pomo)
var _defend_pos := Vector2.INF   # MOBA: uhatun oman rakennuksen sijainti (jos nimetty puolustaja)
var _cover_pos := Vector2.INF    # suojapiste oman aallon takana (INF = ei suojaustarvetta)
var _move := Vector2.ZERO
var _aim := Vector2.RIGHT

var _attack := false
var _attack_prev := false
var _flags := {"a1": false, "a2": false, "dodge": false, "ult": false}
var _recall := false             # paluukanavointi käynnissä/haluttu (MOBA)
var _use_active := false         # itemiaktiivin laukaisu (yksi per päätöstikki)

# Tähdättävien kykyjen pitokone: ajastin > 0 = "nappi pohjassa" (Hero piirtää
# tähtäysviivan -> näkyvä, väistettävä telegraafi), nollan alitus nostaa
# vapautuksen tasan yhdeksi frameksi. _aim_lock lukitsee tähtäyssuunnan pidon
# ajaksi (pakosyöksy poispäin ei saa kääntyä takaisin kohteeseen).
var _aim_hold := {"a1": 0.0, "a2": 0.0}
var _aim_release := {"a1": false, "a2": false}
var _aim_lock := Vector2.ZERO
var _aim_lock_t := 0.0
var _hold_seen_t := -1.0        # viimeisin päivityshetki (kuolema nollaa pidot)
var _shop_trip_cd := 0.0        # kauppareissujen välinen jäähdytys (MOBA)
# VOITETUN TAISTELUN IKKUNA: kun lähellä näkyneet vihollissankarit ovat
# kaatuneet eikä uusia näy, rakenne on hetken ilmainen. _fight_foes on
# edellisen päätöksen näkymä, jotta "ne kaatuivat" voidaan havaita ilman
# tapahtumakytkentää (BotBrain ei kuuntele areenan signaaleja).
var _convert_t := 0.0           # ikkunaa jäljellä sekunteina (0 = ei ikkunaa)
var _fight_foes: Array = []     # edellisellä päätöksellä lähellä näkyneet viholliset
var _fight_scan_t := -99.0      # edellisen skannauksen peliaika (vanhentumisvahti)
# Leirin puhdistuksen kannattavuusseuranta. Sweep-data paljasti että tuki-
# sankarit (maestro 0.17 puhdistusta/ottelu @ 124 s taistelua, hush 0.11,
# luma 0.05) hakkasivat leiriä jota eivät pysty tappamaan — siitä tuli 30-38 %
# niiden koko vahingosta. Mitataan edistyminen ja luovutetaan ajoissa.
var _camp_id := 0               # nykyisen leirikohteen instanssi-id
var _camp_t := 0.0              # aika nykyisen leirin kimpussa
var _camp_hp0 := 0.0            # leirin HP kun taistelu alkoi
var _camp_block := {}           # leirityyppi -> match_elapsed johon asti ohitetaan

var _time := 0.0
var _decision_timer := 0.0
var _reaction_left := 0.0
var _aim_err := 0.0
var _aim_err_timer := 0.0
var _dodge_check_timer := 0.0
var _strafe_dir := 1.0
var _avoid_turn := 0.0          # seinänseurannan kiertosuunta (-1 vasen, +1 oikea)
var _avoid_time := 0.0          # kuinka kauan samaa seinää on seurattu (jumitunnistus)
var _atk_phase := 0.0            # hyökkäyksen jaksotus (aggression-vaihtelu)
var _atk_firing := true
var _lapse_t := 0.0             # jäljellä oleva keskittymiskatko (mistake_chance)
var _lapse_drift := 0.0         # katkoksen aikainen liikkeen harha (radiaaneja)
var _lurk := false              # assassin väijyy (odottaa avausta) sen sijaan että syöksyy

# Jumiutumisen tunnistus ja tyhjäkäyntivahti. Tarkoituksella RANK-NEUTRAALIT:
# "en ole jumissa seinässä" ei ole taitoerottelua, joten nämä eivät skaalaudu.
var _stuck_anchor := Vector2.INF # viimeisin todellisen etenemisen piste
var _stuck_goal := Vector2.INF   # maali jota kohti etenemistä mitataan
var _stuck_t := 0.0              # aika ilman etenemistä kohti kaukaista maalia
var _via_point := Vector2.INF    # tilapäinen kiertopiste jumin/tyhjäkäynnin purkuun
var _via_t := 0.0                # kiertopisteen jäljellä oleva voimassaolo
var _idle_t := 0.0               # aika ilman mitään tekemistä (tyhjäkäyntivahti)
# SEISONTAVAHTI: viimeinen turvaverkko. Mittaa TODELLISTA etenemistä maastossa
# (ei liikevektoria eikä maalietäisyyttä), joten se laukeaa myös silloin kun
# botti "liikkuu" koko ajan mutta pysyy paikallaan — esim. kaksi toisiaan
# seuraavaa sankaria, seinään puskeva kiertokulma tai maali oman jalkojen
# juuressa. Sankari ei saa koskaan viettää koko ottelua tekemättä mitään.
var _stall_anchor := Vector2.INF # piste josta todellista etenemistä mitataan
var _stall_t := 0.0              # aika ilman todellista etenemistä
var _stall_hits := 0             # peräkkäiset laukeamiset (porrastus pyhäkköön)
var _unstick_goal := Vector2.INF # vahdin pakottama maali (ohittaa tilan maalin)
var _unstick_t := 0.0            # pakotetun maalin jäljellä oleva voimassaolo

# Lyhyt hero-kohtainen kombomuisti. Se estää kohteen vaihtamisen kesken avauksen
# ja antaa seuraavalle päätökselle etusijan oikeaan jatkokykyyn.
var _combo_target: Hero = null
var _combo_followup := ""
var _combo_timer := 0.0

# Quillin lataus-ammunta
var _hold_timer := 0.0
var _hold_pause := 0.0

# Kutsukuuliaisuuden salvat: yksi arvonta per kutsu, ei uutta joka päätöksellä
# (muuten botti välkkyisi totellun ja oman agendan välillä).
var _help_key := ""
var _help_obey := true
var _macro_key := ""
var _macro_obey := true
var _defend_sid := 0            # uhatun rakenteen instanssi-id
var _defend_since := -1.0       # puolustuskriisin alkuhetki (match_elapsed)


func _init(p_level: int, p_rank := -1) -> void:
	# Ranking-asteikko (BotRank): 32 porrasta Wood IV -> Challenger I. Vanha
	# 6-portainen taso (0-5) kartoitetaan asteikolle, joten vanhat valikot ja
	# simulaatiot toimivat ennallaan. Kaikki säätimet interpoloidaan
	# MONOTONISESTI rankin mukaan -> alempi rank häviää ylemmälle (ladder).
	rank = p_rank if p_rank >= 0 else BotRank.from_legacy_level(p_level)
	rank = clampi(rank, 0, BotRank.MAX_RANK)
	level = BotRank.to_legacy_level(rank)   # telemetria/raportit (ai_level)
	var t := BotRank.t(rank)

	# Reagointi ja mekaniikka: Wood on selvästi kömpelömpi kuin vanha taso 1
	# (hidas reagointi, huono tähtäys, harvat päätökset), Challenger I lähes
	# virheetön. Eksponentit sovittavat käyrän keskikohdan vanhoihin tasoihin.
	reaction = lerpf(1.1, 0.05, pow(t, 0.75))
	# TÄHTÄYSTARKKUUS: pohja nostettu 38 -> 46 astetta ja huippu terävöitetty
	# 1.0 -> 0.6. Mitattu vika oli että kaksi vierekkäistä rankia molemmat
	# HUTASIVAT (35.6 vs 29.5 astetta ei ratkaissut mitään); nyt matalat tasot
	# ovat aidosti avuttomia ja huippupäässä ero on osuma vs. huti.
	aim_error_deg = lerpf(46.0, 0.6, pow(t, 0.95))
	decision_interval = lerpf(0.95, 0.14, pow(t, 0.85))
	# Näkyvä tähtäysaika: skillshotit pidetään pohjassa ennen laukaisua kuten
	# ihmisellä padilla. Wood telegrafoi yli sekunnin (viivan ehtii nähdä ja
	# väistää), Challenger näpsäyttää lähes heti.
	aim_time = lerpf(1.25, 0.12, pow(t, 0.9))
	dodge_chance = lerpf(0.0, 0.95, pow(t, 1.35))
	ability_chance = lerpf(0.15, 1.0, pow(t, 0.85))
	prediction = pow(t, 1.5)
	# Aggressio saavuttaa katon (jatkuva tuli) Champion III:sta ylöspäin.
	aggression = minf(lerpf(0.35, 1.15, t), 1.0)
	# Buffien haku, deny ja keskitetty tuli: matalat tasot eivät osaa lainkaan.
	buff_focus = pow(t, 1.1)
	buff_deny = lerpf(0.0, 0.95, pow(t, 1.8))
	focus_fire = pow(t, 1.2)
	# Malttavuus, itsesuojelu ja viidakko-objektiivit kasvavat keskitasoilta.
	patience = pow(t, 1.5)
	self_preserve = pow(t, 1.3)
	jungle_focus = pow(t, 1.2)
	farm_skill = lerpf(0.05, 1.0, pow(t, 1.1))
	# Itsesuojelu näkyy pelissä: Wood tappelee käytännössä kuolemaansa asti
	# (syöttää silmin nähden), Challenger perääntyy jo noin kolmanneksella.
	# Kiting erottaa kaukotaistelijat: korkea rank pitää välin hyökätessäänkin.
	retreat_frac = lerpf(0.10, 0.34, pow(t, 0.9))
	kite_skill = pow(t, 1.1)
	combo_skill = lerpf(0.03, 1.0, pow(t, 1.3))
	cooldown_discipline = lerpf(0.05, 1.0, pow(t, 1.1))
	# Pohja 0.30 ja loivempi eksponentti: Wood ja Bronze olivat käytännössä
	# identtisiä (0.52 vs 0.58) ja molemmat syöttivät torneille ~16 kuolemaa
	# — pohjapään portaat tarvitsevat leveyttä erottuakseen.
	tower_judgement = lerpf(0.30, 1.0, pow(t, 0.75))
	# Piirityskuri: korkea rank pysyy rakennuskohteessa eikä lähde puolustajan
	# perään. Ilman tätä "fiksut" varovaisuussäätimet (patience/self_preserve)
	# VÄHENSIVÄT tornivahinkoa rankin noustessa ja keskitasot menivät ristiin
	# ladder-testissä (Silver kaatoi 4.3 rakennetta, Gold vain 1.9).
	siege_focus = pow(t, 0.9)
	# Suojautuminen: korkea rank käyttää omaa minioniaaltoa kilpenä kun kohde ei
	# ole vielä lyöntietäisyydellä (ei jää imemään ilmaista kaukopokea tornin
	# viereen); matala rank seisoo avoimena ja soakkaa — juuri se on taitoeroa.
	cover_skill = pow(t, 1.0)
	# VOITTOEHTOTAIDOT: jaettu KOKO tikapuulle, ei vasta Goldista ylöspäin. Wood
	# työntää yhä (kohteenvalinta on rank-neutraali), mutta HUONOSTI: se ei
	# tunnista ilmaista tornia, ei jatka piiritystä puolustajan ilmestyessä eikä
	# käänny voitetusta taistelusta rakenteeseen. Eksponentit ovat loivia (0.5 —
	# 0.7), koska juuri pohjapäässä (Wood/Bronze/Silver) ladder meni ristiin:
	# siellä portaiden pitää erottua eniten.
	push_skill = pow(t, 0.5)
	convert_skill = pow(t, 0.7)
	tempo_discipline = pow(t, 0.6)
	# Joukkuepeli: matala rank ei kuule kutsuja eikä ehdi puolustamaan ajoissa.
	# Tämä erottaa rankit pelin SULKEMISESSA (ryhmätyöntö/Baron/puolustusreaktio)
	# eikä vain mekaniikassa — tasaväkiset aikakattopelit olivat kolikonheittoa.
	macro_obedience = lerpf(0.25, 1.0, pow(t, 0.7))
	defense_delay = lerpf(2.4, 0.0, pow(t, 0.8))
	# Ultimatet ovat arvokkaimpia — niitä käytetään kaikilla tasoilla,
	# heikommilla vain hieman huonommalla ajoituksella.
	ult_chance = clampf(ability_chance + 0.35, 0.0, 1.0)
	# Keskittymiskatkot: Wood IV mokaa noin joka kolmannessa päätöksessä,
	# Challenger I ei koskaan. Loiva eksponentti (0.85) pitää portaat erillään
	# koko matkalla, myös tason sisäisten divisioonien välillä.
	mistake_chance = lerpf(0.34, 0.0, pow(t, 0.85))

	_apply_tier_gates(BotRank.tier_of(rank))

	# Huippupää (Champion IV -> Challenger I) huijaa avoimesti ja PORTAITTAIN:
	# kovempi vahinko, vähemmän otettua, nopeammat jäähdytykset/ultit ja vauhtia.
	# Portaaton kasvu takaa että Challenger voittaa Championin (ladder-testi).
	var cheat := clampf((float(rank) - 23.0) / 8.0, 0.0, 1.0)
	if cheat > 0.0:
		damage_mult = 1.0 + 0.35 * cheat
		damage_taken_mult = 1.0 - 0.3 * cheat
		cooldown_mult = 1.0 - 0.4 * cheat
		ult_gain_mult = 1.0 + 0.6 * cheat
		speed_mult = 1.0 + 0.1 * cheat


## TASOPORTIT — kahden kerroksen taitomallin ISO askel. Jatkuvat käyrät antavat
## divisioonaeron (määrä), tasoportit antavat tasoeron (LAATU): jokainen taso
## AVAA kykyjä joita alempi taso ei osaa lainkaan. Näin Wood III häviää
## Bronze III:lle selvästi eikä vain "hieman huonommilla luvuilla".
##
## Portit vain LEIKKAAVAT alempia tasoja (minf / *-kertoimet / nollaukset), eivät
## koskaan nosta — monotonisuus rankin suhteen säilyy automaattisesti.
##
## Mitä kukin taso AVAA (sama taulukko tulostuu simraportin tier-yhteenvedossa;
## MatchReport.TIER_CAPABILITIES on tämän tekstipeili — pidä ne synkassa):
##   Wood      — ei mitään: ei väistöä, ei kitetystä, ei suojaa, ei keskitettyä
##               tulta, ei komboja, tuskin last hittejä, ei perääntymistä, ei
##               kauppareissuja, ei objektiiveja, ei makroa. TYÖNTÄÄ SILTI, mutta
##               sokeasti: ei tunnista ilmaista tornia, ei jatka piiritystä
##               puolustajan tullessa, ei käänny voitosta rakenteeseen.
##   Bronze    — LAST HIT + PERÄÄNTYMINEN + kauppareissut (70 s) + ENSIMMÄINEN
##               VOITTOEHTOTAITO: kaadetun vastustajan jälkeen se osaa joskus
##               kääntyä torniin. Yhä: ei kitetystä, ei suojaa, tuskin
##               keskitettyä tulta, hatara piirityskuri.
##   Silver    — VÄISTÖ + DRAGON + kohtuullinen keskitetty tuli + parempi
##               piirityskuri. Yhä: heikko kitetys/suoja, ei Baronia.
##   Gold      — KITETYS + SUOJAUTUMINEN + BARON + linjarotaatiot + täysi
##               voitetun taistelun muunto objektiiviksi.
##   Platinum  — täysi keskitetty tuli ja kombot, ei leikkauksia.
##   Diamond+  — vain käyrät (ja Champion IV:stä alkava huijausramppi).
func _apply_tier_gates(tier: int) -> void:
	match tier:
		0:  # --- Wood: ei mekaniikkaa, ei taloutta, ei karttapeliä ---
			dodge_chance = 0.0
			kite_skill = 0.0
			cover_skill = 0.0
			focus_fire = 0.0
			combo_skill = 0.0
			farm_skill *= 0.3            # tuskin osuu last hitteihin
			retreat_frac = minf(retreat_frac, 0.08)   # tappelee kuolemaansa asti
			macro_obedience = minf(macro_obedience, 0.15)
			jungle_focus *= 0.3          # ei objektiiveja
			buff_focus = 0.0
			siege_focus *= 0.5
			# Wood työntää sokeasti. Nämä ovat TAITOJA, eivät vahinkoleikkauksia:
			# Wood hakkaa tornia yhä täydellä teholla, se ei vain tunnista ilmaista
			# kohdetta, ei pysy piirityksessä eikä käänny voitosta rakenteeseen.
			push_skill = 0.0
			convert_skill = 0.0
			tempo_discipline = minf(tempo_discipline, 0.05)
			can_dragon = false
			can_baron = false
			shop_random_chance = 0.40    # ostaa mitä sattuu, ei buildia
			shop_trip_cooldown = 999.0   # ei koskaan lähde varta vasten ostoksille
		1:  # --- Bronze: osaa farmata ja perääntyä, muu on yhä hukassa ---
			dodge_chance *= 0.25
			kite_skill = 0.0
			cover_skill = 0.0
			focus_fire *= 0.3
			combo_skill *= 0.4
			macro_obedience = minf(macro_obedience, 0.35)
			jungle_focus *= 0.6
			push_skill *= 0.75           # piirityskuri vielä hatara
			convert_skill *= 0.6         # kääntyy torniin vain joskus
			can_dragon = false
			can_baron = false
			shop_random_chance = 0.20
			shop_trip_cooldown = 70.0
		2:  # --- Silver: väistö, välit ja Dragon; Baron on yhä liian iso pala ---
			kite_skill *= 0.35
			cover_skill *= 0.3
			focus_fire *= 0.6
			push_skill *= 0.9
			convert_skill *= 0.8
			can_dragon = true
			can_baron = false
			shop_random_chance = 0.05
			shop_trip_cooldown = 50.0
		3:  # --- Gold: kitetys, suojautuminen ja Baron (hitaammin kuin Platinum) ---
			cover_skill *= 0.7
			convert_skill *= 0.9
			can_dragon = true
			can_baron = true
			shop_random_chance = 0.0
			shop_trip_cooldown = 35.0
		_:  # --- Platinum ja ylöspäin: ei leikkauksia, vain käyrät ---
			can_dragon = true
			can_baron = true
			shop_random_chance = 0.0
			shop_trip_cooldown = 35.0


## Onko botti juuri nyt keskittymiskatkossa (divisioonakerros).
func in_lapse() -> bool:
	return _lapse_t > 0.0


## Voittoehtotaidon TEHOLLINEN arvo juuri nyt. Keskittymiskatko nollaa sen ja
## mokatodennäköisyys leikkaa sitä suhteessa. Tämä on divisioona-akselin puuttunut
## puolisko: ennen mistake_chance heilutti vain mekaniikkaa (tähtäys, kykyjen
## käyttö, liikkeen harha), joten Diamond IV ja Diamond I kaatoivat rakenteita
## täsmälleen yhtä hyvin eikä divisioonaparilla ollut voittajaa. Nyt keskittymis-
## katko maksaa nimenomaan VOITTOEHTOA: piiritys katkeaa ja objektiivi-ikkuna
## menee ohi.
func _wc_skill(base: float) -> float:
	if _lapse_t > 0.0:
		return 0.0
	return base * (1.0 - mistake_chance)


## Keskittymiskatkon tikitys ja arvonta. Katko EI koskaan ala kun botti on
## pakenemassa matalalla HP:llä, kanavoimassa paluuta tai pyhäkössä: siellä
## katko olisi epäreilun tappava (kuolema ilman peliteknistä syytä) eikä mittaa
## taitoa. decided = tämä ruutu oli päätöstikki (arvonta vain silloin).
func _tick_lapse(hero: Hero, arena, delta: float, decided: bool) -> void:
	_lapse_t = maxf(_lapse_t - delta, 0.0)
	if not decided or mistake_chance <= 0.0 or _lapse_t > 0.0:
		return
	if _recall or _mode == Mode.RETREAT:
		return
	if hero.hp < hero.max_hp * 0.35:
		return
	var mm := arena.map as MapMoba
	if mm != null and mm.is_in_own_sanctuary(hero.global_position, hero.team):
		return
	if randf() < mistake_chance:
		# Katkon KESTO skaalautuu samalla akselilla kuin sen todennäköisyys:
		# heikompi keskittyminen ei vain katkea useammin vaan myös palautuu
		# hitaammin. Näiden yhteisvaikutus on divisioona-akselin varsinainen
		# purenta tehokkaaseen peliaikaan (Wood IV ~0,89 s, Diamond I ~0,46 s).
		var span: float = 0.35 + 1.6 * mistake_chance
		_lapse_t = randf_range(span * 0.55, span * 1.45)
		_lapse_drift = deg_to_rad(randf_range(-35.0, 35.0))
		# Katko syö myös objektiivi-ikkunan: ajatus katkeaa juuri kun pitäisi
		# kääntyä torniin. Juuri tästä divisioonaero syntyy voittoehdossa.
		_convert_t = 0.0


func _setup_role(hero: Hero) -> void:
	var hero_def := HeroDef.get_def(hero.hero_id)
	_role = hero_def["role"]
	var archetype: String = str(hero_def.get("archetype", ""))
	_is_tank = _role == "Tankki" or archetype == "Tankki"
	_is_support = _role == "Tuki"
	_is_assassin = _role == "Assassin"
	_is_ranged = _role in ["Mage", "Ranger"] or archetype in ["Mage", "Ranger"]
	_is_jungler_role = _role == HeroDef.ROLE_JUNGLER
	match _role:
		"Tankki":
			_pref_range = 75.0
		"Fighter":
			_pref_range = 110.0
		"Assassin":
			_pref_range = 95.0
		"Mage":
			_pref_range = 330.0
		"Ranger":
			_pref_range = 430.0
		"Tuki":
			_pref_range = 280.0
		HeroDef.ROLE_JUNGLER:
			_pref_range = 145.0
		_:
			_pref_range = 200.0

	# Rooli antaa käyttäytymisen, mutta aseen todellinen kantama määrää missä
	# sankari taistelee. Erityisesti Shade on etä-assa eikä saa juosta meleehen.
	match hero.hero_id:
		"bastion":
			_pref_range = 82.0
			_basic_range = 122.0
		"ember":
			_pref_range = 500.0
			_basic_range = 780.0
		"luma":
			_pref_range = 390.0
			_basic_range = 650.0
		"blink":
			_pref_range = 70.0
			_basic_range = 104.0
		"bramble":
			_pref_range = 112.0
			_basic_range = 158.0
		"quill":
			_pref_range = 560.0
			_basic_range = 1050.0
		"boulder":
			_pref_range = 82.0
			_basic_range = 125.0
		"volt":
			_pref_range = 410.0
			_basic_range = 630.0
		"maestro":
			_pref_range = 310.0
			_basic_range = 455.0
		"shade":
			_pref_range = 360.0
			_basic_range = 515.0
		"tide":
			_pref_range = 125.0
			_basic_range = 174.0
		"scout":
			_pref_range = 500.0
			_basic_range = 660.0
		"prism":
			_pref_range = 355.0
			_basic_range = 600.0
		"rift":
			_pref_range = 76.0
			_basic_range = 112.0
		"titan":
			_pref_range = 84.0
			_basic_range = 130.0
		"hush":
			_pref_range = 420.0
			_basic_range = 690.0
		"obsidian":
			_pref_range = 88.0
			_basic_range = 136.0
		"lance":
			_pref_range = 116.0
			_basic_range = 162.0
		"salvo":
			_pref_range = 470.0
			_basic_range = 690.0
		"kaira":
			_pref_range = 108.0
			_basic_range = 158.0
		"vesper":
			_pref_range = 520.0
			_basic_range = 780.0
		"myria":
			_pref_range = 430.0
			_basic_range = 620.0
		"torq":
			_pref_range = 96.0
			_basic_range = 160.0


func _ensure_moba_assignment(hero: Hero, arena) -> void:
	if _moba_job != "":
		return
	# 1) Lobbyssa valittu positio (top/jungle/carry/support) ohittaa heuristiikan:
	#    pelaaja/botti pelaa juuri sitä paikkaa jonka valitsi.
	match str(hero.profile.moba_position):
		"jungle":
			_moba_job = "jungle"
			_moba_lane = ""
			return
		"top":
			_moba_job = "top"
			_moba_lane = MapMoba.TOP
			return
		"carry":
			_moba_job = "bottom"
			_moba_lane = MapMoba.BOTTOM
			_moba_duty = "carry"
			return
		"support":
			_moba_job = "bottom"
			_moba_lane = MapMoba.BOTTOM
			_moba_duty = "support"
			return
	# 2) Automaattijako (ei valittua positiota): ohita positiot jotka joku muu
	#    on jo nimenomaisesti valinnut lobbyssa.
	var team_heroes: Array = []
	for h in arena.heroes:
		if is_instance_valid(h) and not h.is_unit and h.team == hero.team:
			team_heroes.append(h)
	team_heroes.sort_custom(func(a, b): return a.profile.index < b.profile.index)
	var claimed: Dictionary = {}
	for h in team_heroes:
		var p := str(h.profile.moba_position)
		if p != "":
			claimed[p] = true
	var unassigned: Array = team_heroes.filter(
		func(h): return str(h.profile.moba_position) == "")
	var bots: Array = unassigned.filter(func(h): return h.controller is BotBrain)
	var designated = null
	if not claimed.has("jungle"):
		# Tuleva Jungleri-rooli saa paikan aina ensin, myös jos pelaaja valitsee sen.
		for h in unassigned:
			if HeroDef.get_def(h.hero_id).get("role", "") == HeroDef.ROLE_JUNGLER:
				designated = h
				break
		if designated == null and not bots.is_empty():
			designated = bots[1] if bots.size() > 1 else bots[0]
	if hero == designated:
		_moba_job = "jungle"
		_moba_lane = ""
		return
	var bot_laners: Array = bots.filter(func(h): return h != designated)
	# Support kuuluu oletuksena bottom-duoon. Valitse topiksi ensimmäinen muu
	# sankari, jotta XP-roolit ja lane-käyttäytyminen vastaavat 1/1/2-jakoa.
	var top_laner = null
	if not claimed.has("top"):
		for candidate in bot_laners:
			if str(HeroDef.get_def(candidate.hero_id).get("role", "")) != "Tuki":
				top_laner = candidate
				break
		if top_laner == null and not bot_laners.is_empty():
			top_laner = bot_laners[0]
	if hero == top_laner:
		_moba_job = "top"
		_moba_lane = MapMoba.TOP
		return
	_moba_job = "bottom"
	_moba_lane = MapMoba.BOTTOM
	# BOTTOM-DUON TYÖNJAKO (juurisyykorjaus "botti seisoo koko ottelun"): kaksi
	# tukiroolin sankaria samassa duossa jäivät MOLEMMAT SUPPORT-tilaan, jossa
	# ainoa liikemaali on toisen duolaisen selusta (_support_goal). Kummallakaan
	# ei siis ollut omaa linjamaalia: pari astui 120 px kerrallaan poispäin
	# uhkakeskiöstä, ajautui kartan länsireunaan ja jäi sinne koko otteluksi
	# (taso 1, ei itemejä, ei XP:tä, 0/0/0). Nyt duossa on täsmälleen YKSI tuki;
	# muut pelaavat carryn työnjaolla eli normaalia linjapeliä. Sääntö on
	# deterministinen (suurin profile.index jää tueksi), joten jokainen botti
	# päätyy samaan jakoon ilman erillistä sopimista.
	var duo: Array = bot_laners.filter(func(h): return h != top_laner)
	var supports: Array = duo.filter(
		func(h): return str(HeroDef.get_def(h.hero_id).get("role", "")) == "Tuki")
	if supports.size() >= 2 and hero != supports[supports.size() - 1]:
		_moba_duty = "carry"


func update(hero: Hero, delta: float) -> void:
	_hero = hero
	_time += delta
	_attack_prev = _attack
	for key in _flags:
		_flags[key] = false
	_use_active = false
	_tick_aim_holds(hero, delta)
	if _role == "":
		_setup_role(hero)
	_combo_timer = maxf(_combo_timer - delta, 0.0)
	_shop_trip_cd = maxf(_shop_trip_cd - delta, 0.0)
	_convert_t = maxf(_convert_t - delta, 0.0)
	_track_camp_progress(hero, delta)
	if _combo_timer <= 0.0 or _combo_target == null or not is_instance_valid(_combo_target) \
			or not _combo_target.alive:
		_clear_combo()

	var arena = hero.arena
	var bb: TeamBlackboard = arena.blackboard(hero.team)

	_reaction_left = maxf(_reaction_left - delta, 0.0)
	_aim_err_timer -= delta
	if _aim_err_timer <= 0.0:
		_aim_err_timer = 0.3
		_aim_err = deg_to_rad(randf_range(-aim_error_deg, aim_error_deg))

	var decided := false
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = decision_interval
		_decide(hero, arena, bb)
		decided = true

	_update_target(hero, arena, bb)
	# Keskittymiskatko arvotaan päätöstikissä ja tikitetään joka ruudulla.
	# Ajetaan ennen liikettä/hyökkäystä/kykyjä, joten katko puree samalla tikillä.
	_tick_lapse(hero, arena, delta, decided)
	if decided:
		_update_lurk(hero, arena)
		_update_cover(hero, arena)
	_update_movement(hero, arena, bb, delta)
	_update_aim(hero)
	_update_attack(hero, delta)
	_update_abilities(hero, arena, bb, decided)
	_update_dodge(hero, arena, delta)
	_tick_stall_guard(hero, arena, delta)
	# TYHJÄKÄYNTIVAHTI (rank-neutraali): elossa oleva botti ei saa seisoa
	# pyhäkön ulkopuolella yli 3 s ilman liikettä, hyökkäystä tai muuta
	# tarkoitusta. Pakota asemointitavoite (aallon mukana / aallon varjostus)
	# tilapäisenä kiertopisteenä — normaali päätöslogiikka jatkaa siitä.
	if arena.mode == "moba" and not _recall and _via_t <= 0.0 and not _lurk \
			and not is_finite(_defend_pos.x) and not is_finite(_cover_pos.x):
		var idle_now: bool = _move.length() < 0.05 and not _attack \
			and float(_aim_hold.a1) <= 0.0 and float(_aim_hold.a2) <= 0.0 \
			and hero.stun_timer <= 0.0 and not hero.shop_open and not hero.piloting
		if idle_now:
			var mm_idle := arena.map as MapMoba
			if mm_idle != null and mm_idle.is_in_own_sanctuary(hero.global_position, hero.team):
				_idle_t = 0.0
			else:
				_idle_t += delta
				if _idle_t >= 3.0:
					_idle_t = 0.0
					var activity := _activity_goal(hero, arena)
					if is_finite(activity.x) \
							and activity.distance_to(hero.global_position) > 90.0:
						_via_point = activity
						_via_t = 2.5
		else:
			_idle_t = 0.0
	# Paluukanavointi: seiso paikallaan äläkä tee mitään muuta — mikä tahansa
	# liike-/kykysyöte keskeyttäisi kanavoinnin (Hero._update_recall).
	if _recall:
		_move = Vector2.ZERO
		_attack = false
		for key in _flags:
			_flags[key] = false
		_use_active = false


## Onko vetäytymiselle oikea syy. Pelkkä matala HP EI riitä: ilman uhkaa
## vetäytyminen on linja-ajan lahjoitus, ja koska retreat_frac KASVAA rankilla,
## ylempi rank lahjoitti sitä enemmän kuin alempi — yksi mitatun käänteisyyden
## juurisyistä. Uhkasäde kutistuu tempo_disciplinen mukaan: Wood pakenee varjoja
## (1700 px = käytännössä aina), Challenger vasta kun uhka on oikeasti päällä.
func _retreat_has_reason(hero: Hero, arena) -> bool:
	if hero.since_damage < 2.5:
		return true
	var radius: float = lerpf(1700.0, 560.0, tempo_discipline)
	return _nearest_enemy_hero(hero, arena, radius) != null


## Onko käynnissä piiritys jota ei kannata jättää kesken: murrettava rakenne on
## jo lyöntietäisyydellä ja kaatumassa. Kauppareissu ja paluukanavointi
## lykkääntyvät tämän takia — ylempi rank vie tornin loppuun, alempi kävelee pois
## puolikkaalta tornilta ja antaa sen regeneroitua.
func _siege_worth_finishing(hero: Hero, arena) -> bool:
	if arena.mode != "moba":
		return false
	var st := _pick_push_target(hero, arena) as Structure
	if st == null or not st.alive:
		return false
	if st.hp >= st.max_hp * SIEGE_FINISH_HP:
		return false
	var reach: float = maxf(_siege_clamped(_basic_range, st), 320.0) + st.radius
	return hero.global_position.distance_to(st.global_position) <= reach


## Murrettava rakenne jonka piiritystä KANNATTAA jatkaa vaikka vihollissankari on
## lähellä. Ilman tätä siege_focus oli saavuttamaton: _decide_moba palautti
## vihollisen nähdessään heti ilman työntökohdetta, jolloin _moba_push_targetin
## piirityskuriarvonta ei koskaan päässyt ajoon juuri siinä tilanteessa jota
## varten se kirjoitettiin. Nyt ylempi rank tuo rakenteen mukanaan päätökseen ja
## voittaa vaihtokaupan; Woodilla push_skill on nolla, joten se kääntyy yhä
## sankariin ja hukkaa tornin.
func _siege_hold_target(hero: Hero, arena) -> Structure:
	if randf() >= _wc_skill(push_skill):
		return null
	if hero.hp < hero.max_hp * maxf(retreat_frac, 0.2):
		return null
	var st := _pick_push_target(hero, arena) as Structure
	if st == null or not st.alive or st.kind == Structure.Kind.NEXUS:
		return null
	var reach: float = maxf(_siege_clamped(_basic_range, st), 320.0) + st.radius
	if hero.global_position.distance_to(st.global_position) > reach:
		return null
	# Ylivoimainen puolustus katkaisee piirityksen kaikilla tasoilla: piirityskuri
	# on ajoitusta, ei itsemurhaa.
	var foes: int = arena.heroes_in_circle(st.global_position, 640.0,
		1 - hero.team, true, true).size()
	if foes > _allies_near(hero, st.global_position, 640.0) + 1:
		return null
	return st


## Onko objektiivin (Baron/Dragon) kiistäminen oikeasti voitettavissa. Kierros
## maksaa aina linja-aikaa, joten sen saa maksaa vain kun kohde on otettavissa.
## Ylempi rank laskee paikallaolijat ja jättää häviävän kiistan väliin; alempi
## maksaa kierroksen turhaan — juuri se teki "objektiivitaidosta" rakennepaineen
## VÄHENNYKSEN Silverista ylöspäin.
func _objective_contest_ok(hero: Hero, cr: Critter) -> bool:
	if randf() >= _wc_skill(tempo_discipline):
		return true                    # ei taitoa arvioida -> kierretään silti
	var foes: int = hero.arena.heroes_in_circle(cr.global_position, 700.0,
		1 - hero.team, true, true).size()
	if foes == 0:
		return true
	return _allies_near(hero, cr.global_position, 700.0) + 1 > foes


## Päivittää voitetun taistelun ikkunan. Ajetaan vain päätöstikeissä
## (_decide_moba), joten kustannus on sama kuin muullakin makropäätöksellä.
func _scan_fight_window(hero: Hero, arena) -> void:
	var now: float = float(arena.match_elapsed)
	var fresh: bool = now - _fight_scan_t <= 2.0
	_fight_scan_t = now
	var near: Array = []
	for e in arena.enemy_heroes(hero.team):
		if e.global_position.distance_to(hero.global_position) < FIGHT_SCAN \
				and _moba_can_see(hero, e, arena):
			near.append(e)
	if fresh and near.is_empty() and not _fight_foes.is_empty() \
			and hero.hp > hero.max_hp * 0.3:
		for f in _fight_foes:
			var foe := f as Hero
			if foe == null or not is_instance_valid(foe) or not foe.alive:
				_convert_t = CONVERT_WINDOW
				break
	_fight_foes = near


## Assassiinin malttavuus: neutraalissa taistelussa väijy jos kohde ei ole
## tapettavissa (matala hp) tai eristyksissä. Ylemmät tasot odottavat avausta,
## alemmat syöksyvät heti (patience skaalaa).
func _update_lurk(hero: Hero, arena) -> void:
	if not _is_assassin or _mode != Mode.FIGHT:
		return
	# ILMAN POISTUMISTIETÄ EI SYÖKSYTÄ. Tämä on rank-riippumaton perussääntö:
	# assassiinin koko kauppa on sisään-ulos, ja ilman pakokykyä syöksy on vain
	# ilmainen tappo vastustajalle. Mitattu syy blinkin 7.3 ja riftin 11.2
	# kuolemaan ottelussa oli juuri tämä — botti divesi jäähdytykset tyhjinä.
	if not _escape_ready(hero):
		_lurk = true
		return
	if patience < 0.05:
		return
	if _assassin_should_dive(hero, arena):
		return
	if randf() < patience:
		_lurk = true


func _assassin_should_dive(hero: Hero, arena) -> bool:
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return true
	if _is_assassin and not _escape_ready(hero):
		return false                    # pakotie kiinni -> ei avausta
	if _target.hp < _target.max_hp * 0.45:
		return true                     # tapettavissa -> syöksy kannattaa
	# Eristetty kohde (vain se itse lähellä) -> hyvä avaus.
	var guards: int = arena.heroes_in_circle(_target.global_position, 220.0, 1 - hero.team, true, true).size()
	return guards <= 1


## Valitsee toimintatilan roolin ja tilanteen mukaan.
func _decide(hero: Hero, arena, bb: TeamBlackboard) -> void:
	_lurk = false
	# Nollaa viidakko-objektiivi ja puolustuspiste joka päätöksessä; vain
	# _decide_* asettaa ne uudelleen (esim. vetäytyvä botti ei jää leirille).
	_jungle_target = null
	_defend_pos = Vector2.INF
	_moba_goal = Vector2.INF
	_lane_returning = false
	var was_recalling := _recall
	_recall = false
	# Tornin lukitus ohittaa kaikki objektiivit ja jahdit. Päätöstahdin lisäksi
	# liike tarkistetaan joka framella, joten myös hitaat vaikeustasot poistuvat.
	if arena.mode == "moba" and (_tower_emergency(hero, arena) != null \
			or _protected_nexus_danger(hero, arena) != null):
		_mode = Mode.RETREAT
		return
	# PALUU BASEEN (recall): matala HP ilman lähipainetta -> kanavoi kotiin
	# lähteelle sen sijaan että norkoiltaisiin matalilla HP:illa linjan laidalla.
	# Lähdeparannuksen jälkeen normaali lane-logiikka palauttaa reittiä pitkin.
	if arena.mode == "moba":
		_update_recall_decision(hero, arena, bb, was_recalling)
		if _recall:
			_mode = Mode.RETREAT
			return
	if hero.carrying:
		_mode = Mode.CARRY
		return
	# Pakoraja skaalautuu rankilla (retreat_frac); assassinit ja tuet
	# vetäytyvät hieman aikaisemmin (hauraita).
	var retreat_hp: float = retreat_frac
	if _is_assassin or _is_support:
		retreat_hp += 0.08
	if hero.hp < hero.max_hp * retreat_hp and _retreat_has_reason(hero, arena):
		_mode = Mode.RETREAT
		return
	# Jatka vetäytymistä vain jos yhä matala JA vihollinen lähellä. Heti kun on
	# turvassa (ei vihollista lähellä), palaa peliin — ei jäädä seisomaan
	# nurkkaan/respawniin vaikka olisi tekemistä (esim. 1v1).
	if _mode == Mode.RETREAT and hero.hp < hero.max_hp * 0.5 \
			and _enemy_within(hero, arena, 300.0):
		return

	# Viidakko-pelimuoto: ei reliikkiä eikä kenttäbuffeja — botti tunnistaa ja
	# farmaa leirit ja pomon vaikeustason mukaan (jungle_focus).
	if arena.mode == "jungle":
		_decide_jungle(hero, arena)
		return

	# MOBA: taistele lähellä olevia vihollisia, muuten työnnä linjaa kohti
	# vihollisen tornia/nexusta (tai puolusta uhattua omaa rakennusta).
	if arena.mode == "moba":
		_decide_moba(hero, arena, bb)
		return

	# Kenttäbuffit: hae oman tiimin arvokas buffi tai riko vihollisen buffi.
	# Vaikeustaso päättää kuinka innokkaasti ja kaukaa (buff_focus/buff_deny).
	var buff: FieldBuff = _pick_buff(hero, arena)
	if buff != null:
		_mode = Mode.GET_BUFF
		_buff_target = buff
		return

	# Vapaa reliikki: lähin (ei-tuki) hakee sen, muut ottavat roolinsa.
	if arena.relic.is_free():
		var my_dist: float = hero.global_position.distance_to(arena.relic.global_position)
		var closest := true
		var someone_near := false
		for ally in arena.alive_allies(hero.team):
			if ally == hero:
				continue
			var ad: float = ally.global_position.distance_to(arena.relic.global_position)
			if ad < my_dist - 40.0:
				closest = false
			if ad < my_dist + 120.0:
				someone_near = true
		var grab := closest or randf() < 0.2
		# Tuki nappaa reliikin vain jos kukaan muu ei ole lähellä (kanto
		# estäisi sen kykyjä).
		if _is_support and someone_near:
			grab = false
		if grab:
			_mode = Mode.GET_RELIC
		else:
			_mode = Mode.SUPPORT if _is_support else Mode.FIGHT
		return

	# Vihollisella reliikki: koko joukkue kokoontuu kantajan kimppuun.
	if bb.enemy_carrier != null:
		_mode = Mode.ATTACK_CARRIER
		return

	# Omalla joukkueella reliikki: tankit ja tuet saattavat, muut peelaavat.
	if bb.own_carrier != null and bb.own_carrier != hero:
		if _is_support or _is_tank:
			_mode = Mode.ESCORT
		else:
			_mode = Mode.FIGHT
		return

	# Ei reliikkiä kentällä: tuet asemoivat, muut taistelevat.
	_mode = Mode.SUPPORT if _is_support else Mode.FIGHT


## Viidakon päätöksenteko: puolusta itseä lähellä olevaa vihollispelaajaa
## vastaan, muuten hae paras leiri/pomo-objektiivi vaikeustason mukaan. Tuki
## pysyy tukena (seuraa ja parantaa joukkuetta objektiiveille).
func _decide_jungle(hero: Hero, arena) -> void:
	_jungle_target = null
	if _is_support:
		_mode = Mode.SUPPORT
		return
	# Lähellä oleva vihollispelaaja -> taistele (KO-pisteet + itsepuolustus).
	var threat := _nearest_enemy_player(hero, arena, 300.0)
	if threat != null:
		_mode = Mode.FIGHT
		return
	# Objektiivien tunnistus vaikeustason mukaan.
	if jungle_focus >= 0.05:
		_jungle_target = _pick_jungle_objective(hero, arena)
	_mode = Mode.FIGHT


## Paras tavoiteltava viidakko-olento (arvo tyypin mukaan, etäisyys huomioiden).
## Matkan sietokyky ja pomon houkuttelevuus skaalautuvat vaikeustasolla.
func _pick_jungle_objective(hero: Hero, arena) -> Hero:
	if arena.critters.is_empty():
		return null
	var pos: Vector2 = hero.global_position
	var max_travel: float = 480.0 + jungle_focus * 1500.0
	var best: Hero = null
	var best_score := 0.0
	for c in arena.critters:
		var cr := c as Critter
		if cr == null or not cr.alive:
			continue
		var d: float = pos.distance_to(cr.global_position)
		if d > max_travel:
			continue
		var val: float = _jungle_value(hero, cr)
		if val <= 0.0:
			continue
		var score: float = val - d * 0.10
		if score > best_score:
			best_score = score
			best = cr
	return best


## Olennon arvo botille: pistereiri > pomo (jos vahva/ryhmässä) > vahinkoleiri.
func _jungle_value(hero: Hero, cr: Critter) -> float:
	match cr.kind:
		Critter.Kind.POINTS_CAMP:
			return 200.0
		Critter.Kind.DAMAGE_CAMP:
			# Arvokkaampi kun botti terve (ehtii hyödyntää vahinkobuffin).
			return 120.0 if hero.hp > hero.max_hp * 0.5 else 70.0
		Critter.Kind.RED_CAMP:
			return 165.0 if hero.hp > hero.max_hp * 0.45 else 85.0
		Critter.Kind.BLUE_CAMP:
			return 175.0 if hero.res_type != "" else 105.0
		Critter.Kind.SMALL_CAMP:
			return 95.0
		Critter.Kind.BOSS:
			# TASOPORTTI: Wood/Bronze ei ymmärrä pomoa lainkaan (can_baron).
			if not can_baron:
				return 0.0
			# Pomo on iso palkinto mutta vaarallinen: mene vain terveenä ja
			# mieluiten ryhmässä; korkein taso uskaltaa yksinkin.
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 420.0) >= 1
			# Baron always requires a group; difficulty improves timing, not stats.
			# muuta pomoa yksinfarmaajaksi.
			if strong and grouped:
				return 260.0
			return 0.0
	return 0.0


## Botin paluupäätös: kanavoi kotiin kun HP on matala, mikään ei uhkaa lähellä
## eikä botilla ole puolustus-/aputehtävää. Hystereesi (was_recalling) pitää
## kanavoinnin käynnissä kunnes HP palautuu tai uhka ilmestyy — päätös ei värise.
func _update_recall_decision(hero: Hero, arena, bb: TeamBlackboard,
		was_recalling: bool) -> void:
	if hero.carrying:
		return
	var mm := arena.map as MapMoba
	if mm == null:
		return
	# Basessa/lähteellä ei tarvita paluuta; lähderegen hoitaa loput.
	if mm.is_in_own_sanctuary(hero.global_position, hero.team):
		return
	# Puolustus- ja apukutsutehtävät menevät paluun edelle.
	if bb.defender == hero or (bb.help_lane != "" and hero in bb.helpers):
		return
	# Yhteiset vartijat matalan HP:n paluulle JA kauppareissulle:
	# kotimatka kävellen on lyhyt -> 3.5 s kanavointi ei kannata.
	if hero.global_position.distance_to(mm.fountain_spot(hero.team)) < 1000.0:
		return
	# Vihollissankari lähellä (700) tai mikä tahansa vihollinen aivan vieressä ->
	# kanavointi keskeytyisi kuitenkin vahinkoon, joten älä edes aloita.
	if not arena.heroes_in_circle(hero.global_position, 700.0,
			1 - hero.team, true, true).is_empty():
		return
	if _enemy_within(hero, arena, 460.0):
		return
	# LOPETUSKURI: älä kanavoi kotiin kesken piirityksen jossa rakenne on
	# kaatumassa (viholliset ovat jo tarkistetusti kaukana, joten jääminen on
	# turvallista). Kriittisen matalalla mennään silti kotiin.
	if not was_recalling and hero.hp > hero.max_hp * 0.22 \
			and _siege_worth_finishing(hero, arena) \
			and randf() < _wc_skill(tempo_discipline):
		return
	var threshold := 0.5 if was_recalling else 0.35
	if hero.hp < hero.max_hp * threshold:
		_recall = true
		return
	# KAUPPAREISSU: build kesken ja lompakossa iso ostos valmiina -> palaa
	# ostoksille vaikka HP riittäisi. Hystereesi (was_recalling) pitää
	# kanavoinnin käynnissä; jäähdytys ja rank-arvonta vain aloitukseen.
	if _shop_trip_ready(hero, bb, was_recalling):
		if not was_recalling:
			_shop_trip_cd = shop_trip_cooldown
		_recall = true


## Kannattaako kauppareissu: buildista puuttuu itemejä ja varaa on isoon
## ostokseen (yksittäistä halpaa commonia varten ei reissata, paitsi jos
## lompakko pursuaa). Ripeys skaalautuu rankilla — paremmat pelaajat hakevat
## iteminsä aiemmin, mutta jokainen käy lopulta.
func _shop_trip_ready(hero: Hero, bb: TeamBlackboard, was_recalling: bool) -> bool:
	# TASOPORTTI (itemien osto): Wood ei koskaan lähde varta vasten ostoksille —
	# se ostaa vain sattumalta kotona/kuolleena ollessaan. Bronze/Silver reissaavat
	# harvemmin (shop_trip_cooldown). Talousetu vaatii ostamisen, ei vain kullan.
	if shop_trip_cooldown >= 900.0:
		return false
	if hero.items.size() >= 6:
		return false
	if not was_recalling and _shop_trip_cd > 0.0:
		return false
	# Baron-/ryhmätyöntökutsua ei hylätä ostosreissun takia.
	if bb.macro_call != "" and hero in bb.macro_participants:
		return false
	var goal := _shop_goal(hero)
	if goal == "":
		return false
	var wallet: int = int(hero.profile.wallet())
	var nxt: String = ItemDef.next_purchase(goal, hero.items, wallet)
	if nxt == "":
		return false
	if ItemDef.combine_cost(nxt, hero.items) < 700 and wallet < 1500:
		return false
	if not was_recalling and randf() >= 0.25 + 0.75 * BotRank.t(rank):
		return false
	# AJOITUS (voittoehtotaito): reissu maksaa linja-aikaa, ja koska reissujen
	# tiheys kasvaa rankilla, ylempi rank menetti linjapainetta sitä ENEMMÄN mitä
	# parempi se oli. Nyt ylempi lähtee vasta kun lähtö on ilmainen: kaatuvaa
	# tornia ei jätetä kesken. Jäähdytys pitää huolen ettei reissu jää väliin —
	# se vain siirtyy hetkeksi.
	if not was_recalling and _siege_worth_finishing(hero, hero.arena) \
			and randf() < _wc_skill(tempo_discipline):
		return false
	return true


## Seuraava ostotavoite samalla logiikalla kuin Hero._bot_shop: Baron-
## artefaktin legenda ensin jos siihen on varaa, muuten ensimmäinen kesken
## oleva roolibuildin tavoite.
func _shop_goal(hero: Hero) -> String:
	if hero.legendary_artifact:
		var leg := _item_legendary()
		# EI lompakkoehtoa: tavoite on legenda heti kun artefakti on kädessä.
		# Vanha portti vaati koko hinnan valmiiksi lompakossa, jolloin
		# _shop_goal palautti tavallisen runkotavoitteen säästämisen ajaksi —
		# botti lähti kauppareissulle jonka Hero._bot_shop sitten torjui,
		# koska se säästi jo legendaan. Peilaa Hero._bot_shop-porttia.
		if leg != "" and not hero.items.has(leg):
			return leg
	for g in _item_build():
		if not hero.items.has(str(g)):
			return str(g)
	return ""


## MOBA-päätöksenteko: lähellä oleva vihollinen -> taistele; muuten työnnä
## linjaa hyökkäämällä lähintä tuhottavissa olevaa vihollisrakennusta.
func _decide_moba(hero: Hero, arena, bb: TeamBlackboard) -> void:
	_jungle_target = null
	_ensure_moba_assignment(hero, arena)
	_scan_fight_window(hero, arena)
	_maybe_use_item_active(hero, arena)
	# PUOLUSTUS: jos oma rakennus on uhattu ja OLEN nimetty (lähin) puolustaja,
	# kääerry puolustamaan — taistele viholliset pois rakennuksen luota. Vain yksi
	# botti kerrallaan, joten koko joukkue ei hylkää linjaa. Matala rank havahtuu
	# kriisiin viiveellä (defense_delay) — siihen asti se jatkaa omiaan.
	if bb.defender == hero and bb.threatened_structure != null \
			and is_instance_valid(bb.threatened_structure):
		var sid: int = bb.threatened_structure.get_instance_id()
		if sid != _defend_sid:
			_defend_sid = sid
			_defend_since = float(arena.match_elapsed)
		if float(arena.match_elapsed) - _defend_since >= defense_delay:
			_defend_pos = bb.threatened_structure.global_position
			_mode = Mode.FIGHT
			return
	else:
		_defend_sid = 0
	# ROTAATIO: tiimitaulu kutsui minut auttamaan hätälinjaa (esim. top pahasti
	# alakynnessä tai koko vihollisjoukkue puskee yhtä linjaa) -> mene sinne.
	# Kutsu poistuu taululta kun kriisi laukeaa, jolloin normaali lane-logiikka
	# palauttaa omalle linjalle. Ohittaa myös tuen carry-liimauksen (SUPPORT).
	# Kuuliaisuus arvotaan kerran per kutsu: matala rank jättää usein tulematta.
	if bb.help_lane != "" and hero in bb.helpers:
		var hkey := "%s@%s" % [bb.help_lane, str(bb.help_pos)]
		if hkey != _help_key:
			_help_key = hkey
			# Hätäapu on helpompi ymmärtää kuin hyökkäysmakro -> pieni bonus.
			_help_obey = randf() < clampf(macro_obedience + 0.15, 0.0, 1.0)
		if _help_obey:
			_moba_goal = bb.help_pos
			_mode = Mode.FIGHT
			return
	else:
		_help_key = ""
	# LOPETUS (juurisyykorjaus "nexus ei koskaan tuhoudu"): kun vihollisen nexus
	# on AUKI (molempien linjojen base-tornit nurin), se on kaikkien lähellä
	# olevien bottien ykköskohde. Ilman tätä botit jäivät ikuiseen vaihtokauppaan
	# respawnaavien puolustajien kanssa lähteen vieressä eivätkä koskaan lyöneet
	# nexusta -> ottelut päättyivät aina aikakattoon. RETREAT-/hätäsäännöt
	# hoitavat itsesuojelun edelleen (matala HP keskeyttää rynnäkön).
	var enemy_nexus := _enemy_nexus(hero, arena)
	if enemy_nexus != null and not enemy_nexus.is_protected() \
			and hero.global_position.distance_to(enemy_nexus.global_position) < 1250.0:
		_jungle_target = enemy_nexus
		_mode = Mode.FIGHT
		return
	# MAKRO: joukkueen yhteiskutsu — Baron kimppuun tai ryhmätyöntö murrettavan
	# linjan rakenteelle. Puolustus ja apukutsu (yllä) menevät edelle, eikä
	# ihmisiä komenneta (taulu valitsee vain botteja). Kohteen ympärillä pätevät
	# normaalit taistelu- ja turvasäännöt (_moba_push_target, torniturva).
	if bb.macro_call != "" and hero in bb.macro_participants \
			and bb.macro_target != null and is_instance_valid(bb.macro_target) \
			and bool(bb.macro_target.alive):
		var mkey := "%s@%d" % [bb.macro_call, bb.macro_target.get_instance_id()]
		if mkey != _macro_key:
			_macro_key = mkey
			# Matala rank ei kokoonnu Baronille/ryhmätyöntöön luotettavasti ->
			# kutsut jäävät vajaiksi eikä peli sulkeudu yhtä usein.
			_macro_obey = randf() < macro_obedience
			# TASOPORTTI: Baron-kutsu ei koske tasoja jotka eivät osaa Baronia
			# (Wood/Bronze/Silver) — ne eivät yksinkertaisesti tule paikalle,
			# jolloin joukkueen Baron-kutsu jää vajaaksi.
			if bb.macro_call == "baron" and not can_baron:
				_macro_obey = false
		if _macro_obey:
			_jungle_target = bb.macro_target
			_moba_goal = bb.macro_pos
			_mode = Mode.FIGHT
			return
	elif bb.macro_call == "":
		_macro_key = ""
	# ARTEFAKTI: maassa lojuva Baron-artefakti lähellä -> kävele sen päälle
	# (LegendaryArtifact poimii botin automaattisesti pienen viiveen jälkeen).
	# Vain jos oma artefaktipaikka on vapaa; kaukaa ei lähdetä hakemaan.
	if not hero.legendary_artifact and not arena.artifacts.is_empty():
		var near_art = null
		var art_d := 700.0
		for art_v in arena.artifacts:
			if not is_instance_valid(art_v):
				continue
			var d: float = hero.global_position.distance_to(art_v.global_position)
			if d < art_d:
				art_d = d
				near_art = art_v
		if near_art != null:
			_moba_goal = near_art.global_position
			_mode = Mode.FIGHT
			return
	# LINJANVAIHTO: oman linjan vihollistornit on kaikki kaadettu, mutta nexus on
	# yhä suojattu, koska TOISEN linjan base-torni seisoo (nexus vaatii molemmat).
	# Ilman vaihtoa laneri jäi seisomaan tyhjälle linjalleen koko loppupelin ->
	# toinen linja ei murtunut koskaan ja nexus ei auennut (raportoitu vika).
	# Tornit eivät herää henkiin, joten vaihto on pysyvä ja turvallinen.
	if _moba_job != "jungle" and _moba_lane != "" \
			and enemy_nexus != null and enemy_nexus.is_protected() \
			and _enemy_lane_broken(hero, arena, _moba_lane):
		var other_lane: String = MapMoba.BOTTOM if _moba_lane == MapMoba.TOP else MapMoba.TOP
		if not _enemy_lane_broken(hero, arena, other_lane):
			_moba_lane = other_lane
	var lane_map := arena.map as MapMoba
	if _moba_job != "jungle" and _moba_lane != "" and lane_map != null \
			and lane_map.distance_to_lane(hero.global_position, _moba_lane) > 520.0:
		# Katkaise pitkä jungle-jahti. Lähellä oleva uhka sallitaan vielä
		# itsepuolustuksena target-päivityksessä, muuten palataan omalle kaarelle.
		_lane_returning = true
		_moba_goal = _moba_lane_route_goal(hero, arena, hero.global_position)
		_mode = Mode.FIGHT
		return
	# VOITETUN TAISTELUN MUUNTO RAKENTEEKSI (voittoehtotaito): kun lähitaistelu on
	# juuri voitettu eikä vihollisia näy, ylempi rank kääntyy VÄLITTÖMÄSTI lähimpään
	# murrettavaan rakenteeseen sen sijaan että palaisi farmaamaan aaltoa tai
	# kiertäisi leireille. Tämä on puuttunut lenkki, jolla tapoista ja talousjohdosta
	# tulee rakennepainetta — raportin diagnoosi "ylempi dominoi taloutta muttei
	# sulkenut pelejä" osui tähän. Ennen tuen työnjakoa, jotta myös tuki liittyy.
	if _convert_t > 0.0 and randf() < _wc_skill(convert_skill):
		var conv := _pick_push_target(hero, arena)
		if conv != null:
			_jungle_target = conv
			_mode = Mode.FIGHT
			return
	# Tuen työnjako: nimenomainen support-positio TAI (ilman positiota) tukiroolin
	# sankari bottomissa pelaa suojaavaa duo-peliä.
	if _moba_job == "bottom" and (_moba_duty == "support" \
			or (_moba_duty == "" and _is_support)):
		_mode = Mode.SUPPORT
		return
	# Vain oikea vihollissankari laukaisee tiimitaistelun — minionit ja tornit
	# eivat (ne hoidetaan tyontologiikassa, ettei botti jaa jumiin aaltoon eika
	# hylkaa tyontoa minionin takia).
	# Havaitsemisetäisyys seuraa oman aseen/roolin järkevää taistelualuetta:
	# Quill/Scout/Ember eivät kävele melee-etäisyydelle ennen kuin "näkevät"
	# kohteen, mutta lähitaistelijoiden aggro ei myöskään kasva koko ruudun yli.
	var engage_scan: float = clampf(_pref_range + 180.0, 360.0, 700.0)
	var enemy_hero := _nearest_enemy_hero(hero, arena, engage_scan)
	if enemy_hero != null:
		# PIIRITYSKURIN AVAUS: lähellä oleva vihollinen ei enää automaattisesti
		# nollaa työntökohdetta. Ylempi rank kantaa murrettavan rakenteen mukanaan
		# päätökseen, jolloin _moba_push_target ratkaisee siege_focusilla kumpi
		# voittaa; matala rank saa yhä nullin ja kääntyy sankariin.
		_jungle_target = _siege_hold_target(hero, arena)
		_mode = Mode.FIGHT
		return
	# Viidakko-objektiivi (pomo = iso tiimibuffi, leirit = buffit) jos vaikeustaso
	# tunnistaa sen ja se on arvokas & lähellä — MUUTEN työnnä linjaa. Näin
	# jungle_focus vaikuttaa vihdoin MOBAssa: matalat tasot vain työntävät,
	# korkeat kiistävät pomon ja buffit (osa botteista, ei koko joukkue kerralla).
	_jungle_target = _pick_moba_objective(hero, arena)
	if _moba_job == "jungle":
		if _jungle_target == null:
			var mm := arena.map as MapMoba
			if mm != null:
				# TILAISUUSGANK ensin: jos vihollislaneri on työntynyt meidän
				# puolellemme linjan tuntumassa, kierrä lähimmän gank-portin
				# puskan kautta sen selustaan — aikataulukierto väistyy.
				var ambush := _gank_opportunity(hero, arena, mm)
				if is_finite(ambush.x):
					_moba_goal = ambush
				elif arena.match_elapsed >= LATE_PUSH_TIME:
					# LOPPUPELIN RYHMITYS: gank-kierto ei kaada base-torneja.
					# 14 min jälkeen jungler liittyy joukkueen piiritykseen —
					# lähin murrettavissa oleva rakennus millä tahansa linjalla —
					# sen sijaan että partioisi tyhjää viidakkoa ottelun loppuun
					# (botit eivät muuten koskaan ryhmittyneet lopputyöntöön).
					_jungle_target = _pick_push_target(hero, arena)
					if _jungle_target == null:
						var patrol_step := int(arena.match_elapsed / 6.0) + hero.profile.index
						_moba_goal = mm.jungle_patrol(hero.team, patrol_step)
				else:
					var cycle := fposmod(arena.match_elapsed + hero.profile.index * 3.7, 24.0)
					var phase := int(arena.match_elapsed / 24.0) + hero.profile.index
					if cycle < 5.0:
						var gank_lane := MapMoba.TOP if phase % 2 == 0 else MapMoba.BOTTOM
						_moba_goal = mm.gank_point(hero.team, gank_lane, phase % 4 >= 2)
					else:
						# Leirit kuolleet/respawnissa eikä gankkia tai makroa ->
						# varjosta lähintä omaa aaltoa viidakosta rintaman tasalta
						# sen sijaan että norkoilisi tyhjillä leireillä. Tyhjää
						# partiointia vain jos aaltoja ei ole (alkupeli).
						var shadow := _jungler_shadow_goal(hero, arena, mm)
						if is_finite(shadow.x):
							_moba_goal = shadow
						else:
							var patrol_step := int(arena.match_elapsed / 6.0) + hero.profile.index
							_moba_goal = mm.jungle_patrol(hero.team, patrol_step)
	else:
		if _jungle_target == null:
			_jungle_target = _pick_push_target(hero, arena)
		if _jungle_target == null and arena.map is MapMoba:
			_moba_goal = (arena.map as MapMoba).role_anchor(hero.team, _moba_lane)
	_mode = Mode.FIGHT


## Itemiaktiivien käyttö (MOBA): jungleri häiveytyy (varjo) kun gank-latch on
## päällä ja uhri lähellä; tuki asettaa vartijan (vartija) linjassa ollessaan.
## Asettaa yhden laukaisulipun, jonka hero lukee item_active_just()-polusta.
func _maybe_use_item_active(hero: Hero, arena) -> void:
	if _use_active:
		return
	if hero.items.has("varjoviitta") \
			and float(hero.item_active_cd.get("varjoviitta", 0.0)) <= 0.0 \
			and _moba_job == "jungle" and _gank_victim != null \
			and is_instance_valid(_gank_victim) and _gank_victim.alive \
			and hero.global_position.distance_to(_gank_victim.global_position) <= 900.0:
		_use_active = true
		return
	if hero.items.has("vartiolyhty") \
			and float(hero.item_active_cd.get("vartiolyhty", 0.0)) <= 0.0 \
			and _item_role() == "support":
		var mm := arena.map as MapMoba
		if mm != null and not mm.is_in_own_sanctuary(hero.global_position, hero.team):
			_use_active = true


## Viidakko-objektiivin valinta MOBAssa: PAIKALLINEN (ei koko kartan yli), jottei
## botti hylkää linjaa. Pomo on iso palkinto (tiimibuffi) ja vaatii terveyden +
## ryhmän; leirit ovat opportunistisia lähibuffeja. jungle_focus (vaikeustaso)
## säätää sekä kantaman että sen uskaltaako pomon kimppuun.
## Seuraa nykyisen leiritaistelun edistymistä ja luovuttaa jos leiri ei kaadu.
## Ihminen ei hakkaa leiriä kahta minuuttia; botti teki juuri niin. 6 sekunnin
## jälkeen vaaditaan 35 % HP:sta pois, muuten leirityyppi ohitetaan 45 s ajan.
func _track_camp_progress(hero: Hero, delta: float) -> void:
	var cr := _jungle_target as Critter
	if cr == null or not is_instance_valid(cr) or not cr.alive:
		_camp_id = 0
		_camp_t = 0.0
		return
	if cr.is_major_objective():
		return   # Baron/Dragon ovat ryhmäkohteita, ei soolokannattavuutta
	var cid: int = cr.get_instance_id()
	if cid != _camp_id:
		_camp_id = cid
		_camp_t = 0.0
		_camp_hp0 = maxf(cr.hp, 1.0)
		return
	if hero.global_position.distance_to(cr.global_position) > 420.0:
		return   # ei olla vielä kimpussa; matka ei kuluta kärsivällisyyttä
	_camp_t += delta
	if _camp_t < 6.0:
		return
	if cr.hp / _camp_hp0 > 0.65:
		var until: float = float(hero.arena.match_elapsed) + 45.0
		_camp_block[cr.kind] = until
		_jungle_target = null
		_camp_id = 0
		_camp_t = 0.0


## Onko leirityyppi hetkellisesti ohitettu kannattamattomana.
func _camp_blocked(hero: Hero, kind: int) -> bool:
	if not _camp_block.has(kind):
		return false
	var until: float = float(_camp_block[kind])
	if float(hero.arena.match_elapsed) >= until:
		_camp_block.erase(kind)
		return false
	return true


func _pick_moba_objective(hero: Hero, arena) -> Hero:
	if arena.critters.is_empty():
		return null
	if _moba_job != "jungle" and jungle_focus < 0.05:
		return null
	# Kesken oleva piiritys voittaa objektiivikierroksen: ylempi rank ei jätä
	# kaatuvaa tornia Dragonin takia, alempi jättää.
	if _siege_worth_finishing(hero, arena) and randf() < _wc_skill(tempo_discipline):
		return null
	var is_laner := _moba_job != "jungle"
	# Laner voi kiertää vain oikealle major-objectivelle ja vain kun oma aalto
	# on työnnetty. Tavalliset campit kuuluvat junglerille; niiden vuoksi ei
	# enää hylätä topia/bottomia kesken wave-rytmin.
	if is_laner and not _lane_rotation_safe(hero, arena):
		return null
	var pos: Vector2 = hero.global_position
	var max_travel: float = 2600.0 if not is_laner else 1050.0
	var best: Hero = null
	var best_score := 0.0
	for c in arena.critters:
		var cr := c as Critter
		if cr == null or not cr.alive:
			continue
		if is_laner and not cr.is_major_objective():
			continue
		var d: float = pos.distance_to(cr.global_position)
		if d > max_travel:
			continue
		var val: float = _moba_objective_value(hero, cr)
		if not cr.is_major_objective():
			val *= _camp_role_mult(hero)
		if val <= 0.0:
			continue
		var score: float = val - d * (0.055 if _moba_job == "jungle" else 0.14)
		if score > best_score:
			best_score = score
			best = cr
	return best


func _lane_rotation_safe(hero: Hero, arena) -> bool:
	if _moba_lane == "":
		return false
	for minion in arena.minions:
		if not is_instance_valid(minion) or not minion.alive or minion.team == hero.team \
				or minion.lane_id != _moba_lane:
			continue
		# Vihollisaalto omalla kartanpuoliskolla pitää lanerin linjalla.
		if (hero.team == 0 and minion.global_position.x < 250.0) \
				or (hero.team == 1 and minion.global_position.x > -250.0):
			return false
	return true


func _moba_objective_value(hero: Hero, cr: Critter) -> float:
	# Kannattamattomaksi todettu leirityyppi ohitetaan (ks. _track_camp_progress).
	if not cr.is_major_objective() and _camp_blocked(hero, cr.kind):
		return 0.0
	match cr.kind:
		Critter.Kind.BOSS:
			# TASOPORTTI: Baron on Gold+ (can_baron). Wood/Bronze/Silver eivät
			# osallistu lainkaan -> ne menettävät Baron-buffin ja artefaktin,
			# mikä on iso osa tason vs. tason erosta loppupelissä.
			if not can_baron:
				return 0.0
			# Iso tiimibuffi -> korkein prioriteetti, mutta vaarallinen: vain
			# terveenä ja mieluiten ryhmässä (vain korkein taso uskaltaa yksin).
			var strong: bool = hero.hp > hero.max_hp * 0.55 and jungle_focus >= 0.4
			var grouped: bool = _allies_near(hero, cr.global_position, 460.0) >= 1
			if strong and grouped and _objective_contest_ok(hero, cr):
				return 300.0
			return 0.0
		Critter.Kind.DRAGON:
			# TASOPORTTI: Dragon on Silver+ (can_dragon).
			if not can_dragon:
				return 0.0
			var strong: bool = hero.hp > hero.max_hp * 0.5
			var grouped: bool = _allies_near(hero, cr.global_position, 460.0) >= 1
			var solo_ready := _moba_job == "jungle" and jungle_focus >= 0.72 \
				and hero.has_method("bot_can_solo_major") \
				and bool(hero.call("bot_can_solo_major", cr))
			if strong and (grouped or solo_ready) and _objective_contest_ok(hero, cr):
				return 245.0
			return 0.0
		Critter.Kind.DAMAGE_CAMP:
			if _moba_job != "jungle": return 0.0
			return 110.0 if hero.hp > hero.max_hp * 0.5 else 0.0   # opportunistinen buffi
		Critter.Kind.POINTS_CAMP:
			if _moba_job != "jungle": return 0.0
			return 60.0   # pisteet vain 3. tason tiebreak -> matala prioriteetti
		Critter.Kind.RED_CAMP:
			if _moba_job != "jungle": return 0.0
			return 165.0 if hero.hp > hero.max_hp * 0.45 else 55.0
		Critter.Kind.BLUE_CAMP:
			if _moba_job != "jungle": return 0.0
			return 180.0 if hero.res_type != "" else 105.0
		Critter.Kind.SMALL_CAMP:
			return 105.0 if _moba_job == "jungle" else 0.0
	return 0.0


## Tukisankari viidakkovuorossa ei ole jungleri: se puhdistaa hitaasti ja kuolee
## leireille. Painotetaan leirit alas, jolloin se roamaa ja auttaa linjoja.
func _camp_role_mult(hero: Hero) -> float:
	if _is_support and _moba_job == "jungle":
		return 0.45 if hero.level < 5 else 0.7
	return 1.0


## Vihollisen elossa oleva nexus-rakennus tai null.
func _enemy_nexus(hero: Hero, arena) -> Structure:
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != hero.team \
				and s.kind == Structure.Kind.NEXUS:
			return s
	return null


## Onko vihollisen torniketju annetulla linjalla kokonaan tuhottu?
func _enemy_lane_broken(hero: Hero, arena, lane: String) -> bool:
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != hero.team \
				and s.kind == Structure.Kind.TOWER and s.lane_id == lane:
			return false
	return true


## Lähin tuhottavissa oleva vihollisrakennus (torni ensin, nexus vasta avattuna).
func _pick_push_target(hero: Hero, arena) -> Hero:
	var foe: int = 1 - hero.team
	var best: Hero = null
	var best_d := 1.0e20
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team != foe:
			continue
		# Ohita suojatut (immuunit) rakennukset: kohdista uloin torni ensin,
		# ettei botti kävele turhaan sisemmän tornin/nexuksen alueelle.
		if s.is_protected():
			continue
		# Linjasuodatus koskee torneja JA kristalleja (kristalli on suojaamaton
		# ja siksi aina kelvollinen työntökohde omalla linjalla).
		if _moba_lane != "" and s.kind != Structure.Kind.NEXUS \
				and s.lane_id != "" and s.lane_id != _moba_lane:
			continue
		var d: float = hero.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


## Lähin vihollisyksikkö/-sankari (joukkue 0/1, ei neutraaleja) max_dist päässä.
## Ohittaa vielä suojatun nexuksen (siihen ei voi tehdä vahinkoa).
func _nearest_enemy(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for enemy in arena.alive_enemies(hero.team):
		if enemy.team > 1:
			continue
		var st := enemy as Structure
		if st != null and st.is_protected():
			continue   # suojattua nexusta/sisätornia ei voi vahingoittaa -> ohita
		var d: float = enemy.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


## Lähin vihollis*pelaaja*/-yksikkö max_dist päässä (sama suodatus).
func _nearest_enemy_player(hero: Hero, arena, max_dist: float) -> Hero:
	return _nearest_enemy(hero, arena, max_dist)


## Lähin vihollis*sankari* (ei yksiköitä: ei minioneja/torneja) max_dist päässä.
func _nearest_enemy_hero(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for e in arena.enemy_heroes(hero.team):
		if arena.mode == "moba" and not _moba_can_see(hero, e, arena):
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _moba_can_see(observer: Hero, target: Hero, arena) -> bool:
	var dist: float = observer.global_position.distance_to(target.global_position)
	# Häive (varjoviitta): häivetetyn sankarin näkee vain aivan läheltä.
	if target.stealth_timer > 0.0 and dist > 160.0:
		return false
	if dist <= 190.0:
		return true
	var mm := arena.map as MapMoba
	if mm == null:
		return dist <= 760.0
	# Puskan ulkopuolelta näkee sisään vain lähietäisyydeltä. Samassa puskassa
	# olevat näkevät toisensa normaalisti. Tämä ei vielä piirrä pelaajan fogia,
	# mutta poistaa AI:n epäreilun seinän/pimeän läpi tietämisen.
	if mm.is_in_brush(target.global_position) \
			and not mm.same_brush(observer.global_position, target.global_position):
		return dist <= 235.0
	var sight: float = 610.0 if mm.is_dark_jungle(observer.global_position) else 760.0
	if dist > sight:
		return false
	var space := observer.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(observer.global_position,
		target.global_position, 1)
	return space.intersect_ray(query).is_empty()


func _moba_unit_relevant(hero: Hero, unit: Hero) -> bool:
	var d: float = hero.global_position.distance_to(unit.global_position)
	if _moba_job == "jungle":
		return d <= 420.0
	if unit is Minion:
		return (unit as Minion).lane_id == _moba_lane and d <= 620.0
	if unit is Structure:
		var s := unit as Structure
		return (s.kind == Structure.Kind.NEXUS or s.lane_id == _moba_lane) and d <= 850.0
	return d <= 520.0


## Lähin vihollisminioni max_dist päässä (vihollisaallon siivoamiseen).
func _nearest_enemy_minion(hero: Hero, arena, max_dist: float) -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	for e in arena.alive_enemies(hero.team):
		if not (e is Minion):
			continue
		if _moba_lane != "" and (e as Minion).lane_id != _moba_lane:
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d > max_dist:
			continue
		var hp_frac: float = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
		var score: float = d - farm_skill * (1.0 - hp_frac) * 280.0
		# Rehellinen osuma-arvio: perusisku kasvaa tasoista ja itemeistä, joten
		# korkea rank last hittaa täsmällisesti myös myöhäispelissä. Matala
		# farm_skill arvioi yhä alakanttiin — se on taitoero.
		var estimated_hit: float = (16.0 + farm_skill * 30.0) \
			* hero.level_damage_mult * (1.0 + hero.item_stat("attack"))
		if e.hp <= estimated_hit:
			score -= farm_skill * 190.0
		if score < best_score:
			best_score = score
			best = e
	return best


## Montako omaa minionia on annetun pisteen lähellä (onko oma aalto paikalla?).
func _own_minions_near(hero: Hero, arena, pos: Vector2, r: float) -> int:
	var n := 0
	for m in arena.minions:
		if is_instance_valid(m) and m.alive and m.team == hero.team \
				and m.global_position.distance_to(pos) < r:
			n += 1
	return n


## Arvioi tornia suojaavan aallon laadun. Pelkkä "kaksi minionia jossain
## lähellä" ei riitä: tornin pitää oikeasti olla lukittunut elävään omaan
## minioniin (tai vasta valitsemassa vähintään kolmen terveen minionin aaltoa).
func _tower_wave_safe(hero: Hero, arena, tower: Structure) -> bool:
	var count := 0
	var health_equiv := 0.0
	for m in arena.minions:
		if not is_instance_valid(m) or not m.alive or m.team != hero.team:
			continue
		if m.global_position.distance_to(tower.global_position) > Structure.SHOT_RANGE - 12.0:
			continue
		count += 1
		health_equiv += clampf(m.hp / maxf(m.max_hp, 1.0), 0.0, 1.0)
	var lock := tower._target_lock
	if lock == hero:
		return false
	if lock is Minion and is_instance_valid(lock) and lock.alive and lock.team == hero.team:
		# Neljän minionin aallosta pitää olla vähintään kolme ja yhteensä noin
		# kahden täyden minionin HP. Näin hidas tankki lähtee ennen viimeistä laukausta.
		return count >= 3 and health_equiv >= 2.0
	if lock == null:
		return count >= 4 and health_equiv >= 2.7
	return false


func _enemy_tower_covering(hero: Hero, arena, point: Vector2, margin := 0.0) -> Structure:
	var best: Structure = null
	var best_d := 1.0e20
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team or s.kind != Structure.Kind.TOWER:
			continue
		var d: float = point.distance_to(s.global_position)
		if d <= Structure.SHOT_RANGE + margin and d < best_d:
			best_d = d
			best = s
	return best


## Torni on välitön hätä, jos se on lukinnut botin tai botti seisoo sen
## kantamalla ilman oikeasti kestävää minionisuojaa.
func _tower_emergency(hero: Hero, arena) -> Structure:
	if arena.mode != "moba":
		return null
	var pos: Vector2 = hero.global_position
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team or s.kind != Structure.Kind.TOWER:
			continue
		var d: float = pos.distance_to(s.global_position)
		if s._target_lock == hero and d < Structure.SHOT_RANGE + 110.0:
			return s
		if d < Structure.SHOT_RANGE and not _tower_wave_safe(hero, arena, s):
			return s
	return null


func _protected_nexus_danger(hero: Hero, arena) -> Structure:
	if arena.mode != "moba":
		return null
	for st in arena.structures:
		var s := st as Structure
		if s != null and s.alive and s.team != hero.team and s.kind == Structure.Kind.NEXUS \
				and s.is_protected() \
				and hero.global_position.distance_to(s.global_position) < Structure.NEXUS_LASER_RANGE + 70.0:
			return s
	return null


func _tower_escape_point(hero: Hero, arena, tower: Structure, hold_range: float) -> Vector2:
	var pos: Vector2 = hero.global_position
	var home: Vector2 = arena.map.spawn_point(hero.team, 0)
	var home_side: Vector2 = home - tower.global_position
	if home_side.length() < 1.0:
		home_side = pos - tower.global_position
	if home_side.length() < 1.0:
		home_side = Vector2.LEFT if hero.team == 0 else Vector2.RIGHT
	return arena.map.clamp_to_field(tower.global_position + home_side.normalized() * hold_range, 70.0)


func _moba_emergency_goal(hero: Hero, arena) -> Vector2:
	if arena.mode != "moba":
		return Vector2.INF
	var nexus := _protected_nexus_danger(hero, arena)
	if nexus != null:
		return _tower_escape_point(hero, arena, nexus, Structure.NEXUS_LASER_RANGE + 100.0)
	var tower := _tower_emergency(hero, arena)
	if tower != null:
		return _tower_escape_point(hero, arena, tower, Structure.SHOT_RANGE + 95.0)
	return Vector2.INF


## MOBA-työnnön kohteenvalinta: vihollissankari lähellä -> taistele; muuten
## siivoa vihollisaalto (jotta oma aalto crashaa tornille); muuten lyö rakennus.
func _moba_push_target(hero: Hero, arena) -> Hero:
	# Kilpajuoksu nexukselle: AVOIN nexus iskuetäisyyden tuntumassa lyödään
	# loppuun eikä käännytä puolustajaa päin — muuten respawnaava puolustaja
	# keskeytti viimeistelyn loputtomasti (osasyy "nexus ei tuhoudu" -vikaan).
	var open_nexus := _jungle_target as Structure
	if open_nexus != null and open_nexus.kind == Structure.Kind.NEXUS \
			and not open_nexus.is_protected() \
			and hero.global_position.distance_to(open_nexus.global_position) < 700.0:
		return open_nexus
	var hero_scan: float = clampf(_pref_range + 150.0, 280.0, 700.0)
	var enemy_hero := _nearest_enemy_hero(hero, arena, hero_scan)
	# PIIRITYSKURI: kun rakennuskohde on jo lyöntietäisyydellä, korkea rank
	# pysyy siinä eikä lähde puolustajan perään (arvonta per päätös). Matala
	# rank antaa kohteen syöttiytyä — torniturva (_tower_emergency) suojaa yhä.
	if enemy_hero != null:
		var siege_st := _jungle_target as Structure
		# HUOM: iskuetäisyys leikataan piiritysrajaan — muuten Scout luulisi
		# "olevansa jo lyömässä tornia" 1000 px päästä, jossa vahinko on nolla.
		if siege_st != null and siege_st.alive \
				and siege_st.kind != Structure.Kind.NEXUS \
				and hero.global_position.distance_to(siege_st.global_position) \
					< maxf(_siege_clamped(_basic_range, siege_st), 320.0) + siege_st.radius \
				and randf() < _wc_skill(siege_focus):
			return siege_st
		return enemy_hero
	var minion_scan := 420.0 if _moba_job == "jungle" else 950.0
	# Matkalla Baronille/objectivelle ei pysähdytä farmaamaan aaltoa — vain
	# aivan viereen osuva minioni siivotaan (muuten makrokutsu pysähtyisi).
	if _jungle_target is Critter:
		minion_scan = 320.0
	var minion := _nearest_enemy_minion(hero, arena, minion_scan)
	if minion != null:
		return minion
	return _jungle_target


## Leikkaa halutun etäisyyden rakennuskohteille piirityskehän sisään. Sankari-
## ja minionikohteille palauttaa arvon sellaisenaan (sääntö koskee vain
## rakennuksia). Rank-neutraali korjaus: ilman tätä kaukotaistelijabotti seisoisi
## kantamaimmuniteetin ulkopuolella ja "piirittäisi" nollavahingolla.
func _siege_clamped(range_v: float, target) -> float:
	if target is Structure:
		return minf(range_v, Structure.SHOT_RANGE - SIEGE_STANDOFF)
	return range_v


func _allies_near(hero: Hero, pos: Vector2, r: float) -> int:
	var n := 0
	for ally in hero.arena.alive_allies(hero.team):
		if ally == hero:
			continue
		if ally.global_position.distance_to(pos) < r:
			n += 1
	return n


## Kohteenvalinta roolin mukaan.
func _update_target(hero: Hero, arena, bb: TeamBlackboard) -> void:
	var enemies: Array = arena.alive_enemies(hero.team)
	if enemies.is_empty():
		_target = null
		return
	if arena.mode == "moba" and _lane_returning:
		var local_threat := _nearest_enemy_hero(hero, arena, 240.0)
		if local_threat != _target:
			_target = local_threat
			_reaction_left = reaction
		return
	# Jatka samaan sankariin kombon lyhyen toteutusikkunan ajan. Muisti ei seuraa
	# koko kartan yli eikä pakota tornidiveä; turvallisuussäännöt ohittavat iskut.
	if _combo_timer > 0.0 and _combo_target != null and is_instance_valid(_combo_target) \
			and _combo_target.alive \
			and hero.global_position.distance_to(_combo_target.global_position) < 900.0:
		_target = _combo_target
		return

	var pos: Vector2 = hero.global_position
	var pick: Hero = null

	# Viidakko: jos on valittu leiri/pomo-objektiivi, hyökkää sitä — paitsi jos
	# vihollispelaaja tulee lähelle (silloin puolustaudu / KO-pisteet).
	if _jungle_target != null and is_instance_valid(_jungle_target) and _jungle_target.alive:
		var new_target: Hero = null
		if arena.mode == "moba":
			# MOBA: siivoa aalto ennen tornia, taistele sankaria lähellä.
			new_target = _moba_push_target(hero, arena)
		else:
			var near_player := _nearest_enemy_player(hero, arena, 240.0)
			new_target = near_player if near_player != null else _jungle_target
		# HUOM: reaktioaika nollataan VAIN kun kohde vaihtuu — muuten se
		# nollautuisi joka ruutu ja botti ei ikinä ehtisi lyödä (torni/aalto).
		if new_target != _target:
			_target = new_target
			_reaction_left = reaction
		return

	# Oikeat vihollissankarit ENSIN: MOBAssa "enemies" sisältää myös minionit ja
	# rakennukset, eikä botti (etenkään assassin) saa näykkiä aaltoa sankarin
	# sijaan taistelussa. Yksiköt jäävät varasyyksi jos sankaria ei ole lähellä.
	var hero_enemies: Array = arena.enemy_heroes(hero.team)
	if arena.mode == "moba":
		# Syväjahtauksen esto: linjapuoliskon vihollinen kelpaa kohteeksi vain
		# jos se EI ole vetäytynyt vihollistornien taakse (muuten laneri seuraa
		# pakenevaa syvälle vihollisjunglen/tornien väliin ja kävelee takaisin).
		var chase_frontier: float = _enemy_tower_frontier(hero, arena, _moba_lane) \
			if _moba_lane != "" else 3600.0
		hero_enemies = hero_enemies.filter(func(e):
			if not _moba_can_see(hero, e, arena):
				return false
			if _moba_job == "jungle":
				# Jungleri ottaa taistelun lähellä reittiään/gankkia, ei lukitu
				# lähimpään sankariin toisella puolella koko karttaa. Lukittu
				# gank-uhri kelpaa kauempaakin — muuten jungleri jäi seisomaan
				# gank-portille tuijottamaan uhria ~700 px:n päähän.
				var jungler_reach: float = 900.0 if e == _gank_victim else 620.0
				if e.global_position.distance_to(pos) > jungler_reach:
					return false
				# TORNIPORTTI (juurisyy: kaira otti 34 % vahingostaan TORNEILTA).
				# Laneri ei saa lukittua kohteeseen joka on vetäytynyt vihollis-
				# tornien taakse (chase_frontier alempana), mutta junglerilta tämä
				# ehto puuttui kokonaan: gank-latch veti sen 900 px:n päähän tornin
				# alle ja _tower_diving ehti vain estää kyvyt, ei jahtia. Nyt sama
				# aaltovaatimus koskee jungleria: tornin suojaaman kohteen saa ottaa
				# vain kun oma aalto oikeasti tankkaa tornin (_tower_wave_safe).
				var dive_tower := _enemy_tower_covering(hero, arena, e.global_position)
				if dive_tower != null and not _tower_wave_safe(hero, arena, dive_tower):
					return false
				return true
			if _moba_lane == "":
				return e.global_position.distance_to(pos) <= 520.0
			var mm := arena.map as MapMoba
			if e.global_position.distance_to(pos) < 360.0 or mm == null:
				return true
			var depth: float = e.global_position.x if hero.team == 0 \
				else -e.global_position.x
			return mm.nearest_lane(e.global_position) == _moba_lane \
				and depth <= chase_frontier)
	if _mode == Mode.ATTACK_CARRIER and bb.enemy_carrier != null \
			and is_instance_valid(bb.enemy_carrier):
		pick = bb.enemy_carrier
	elif _is_assassin:
		# Assassinit suosivat heikkoja takalinjan SANKAREITA (eivät minioneja).
		var best_score := -1e20
		for enemy in hero_enemies:
			var d: float = enemy.global_position.distance_to(pos)
			if d > 700.0:
				continue
			var score := -d
			if HeroDef.get_def(enemy.hero_id)["role"] in BACKLINE_ROLES:
				score += 260.0
			score += (1.0 - enemy.hp / enemy.max_hp) * 320.0
			if score > best_score:
				best_score = score
				pick = enemy
		if pick == null:
			pick = _nearest(hero_enemies, pos)
	else:
		# Tankki suojaa: jos joku uhkaa suojeltavaa, käännytään sitä vastaan.
		if _is_tank and bb.protect_ally != null and bb.protect_ally != hero:
			var threat := _nearest_to(hero_enemies, bb.protect_ally.global_position, 240.0)
			if threat != null:
				pick = threat
		if pick == null:
			# Keskitetty tuli: ylemmillä tasoilla iske samaan kohteeseen kuin
			# muut joukkueen botit (kunhan se on järkevän matkan päässä).
			if focus_fire >= 0.4 and bb.focus_target != null \
					and is_instance_valid(bb.focus_target) and bb.focus_target.alive \
					and pos.distance_to(bb.focus_target.global_position) < _pref_range + 380.0:
				pick = bb.focus_target
			else:
				pick = _nearest(hero_enemies, pos)

	# Varasyy: jos yhtään vihollissankaria ei ollut valittavissa (esim. puhdas
	# työntötilanne), iske lähintä EI-suojattua yksikköä/rakennusta.
	if pick == null:
		var attackables: Array = enemies
		if arena.mode == "moba":
			attackables = enemies.filter(func(e): return _moba_unit_relevant(hero, e))
		pick = _nearest_attackable(attackables, pos)

	if pick != _target:
		_target = pick
		_reaction_left = reaction


func _nearest(list: Array, from: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1e20
	for h in list:
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


func _nearest_to(list: Array, from: Vector2, max_dist: float) -> Hero:
	var best: Hero = null
	var best_d := max_dist
	for h in list:
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


## Lähin lyötävä kohde: ohittaa suojatut (immuunit) rakennukset, ettei botti
## lukitu iskemään sisätornia/nexusta joka torjuu kaiken (0 vahinkoa).
func _nearest_attackable(list: Array, from: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1e20
	for h in list:
		if not is_instance_valid(h) or not h.alive:
			continue
		var s := h as Structure
		if s != null and s.is_protected():
			continue
		var d: float = h.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = h
	return best


## Paras tavoiteltava buffi (oma napattava tai vihollisen rikottava) tai null.
## Etäisyysraja ja denyaus skaalautuvat vaikeustasolla (buff_focus/buff_deny).
func _pick_buff(hero: Hero, arena) -> FieldBuff:
	if buff_focus < 0.06 or arena.buffs.is_empty():
		return null
	var pos: Vector2 = hero.global_position
	var max_divert := 320.0 + buff_focus * 950.0
	var best: FieldBuff = null
	var best_score := 45.0
	for b in arena.buffs:
		if not is_instance_valid(b):
			continue
		var d: float = pos.distance_to(b.global_position)
		if d > max_divert:
			continue
		var val := 0.0
		if b.owner_team == hero.team:
			# Oman tiimin buffi: nappaa. Sininen hyödyttää vain resurssisankaria.
			if b.type == "red":
				val = 110.0
			elif _has_resource(hero):
				val = 125.0
			else:
				val = 10.0
		else:
			# Vihollisen buffi: riko (deny) jos vaikeustaso sallii.
			if buff_deny < 0.06:
				continue
			val = buff_deny * 95.0
			if _is_assassin or _is_ranged:
				val += 25.0
		var score := val - d * 0.12
		if score > best_score:
			best_score = score
			best = b
	return best


func _has_resource(hero: Hero) -> bool:
	return hero.res_type != ""


func _update_movement(hero: Hero, arena, bb: TeamBlackboard, delta: float) -> void:
	var pos: Vector2 = hero.global_position
	var goal := pos

	match _mode:
		Mode.GET_BUFF:
			if _buff_target != null and is_instance_valid(_buff_target):
				goal = _buff_target.global_position
			else:
				goal = _combat_goal(hero, arena, bb, pos)  # buffi meni -> taistele
		Mode.GET_RELIC:
			goal = arena.relic.global_position
		Mode.RETREAT:
			goal = _retreat_goal(hero, arena, bb, pos)
		Mode.CARRY:
			goal = _carry_goal(arena, pos)
		Mode.ESCORT:
			goal = _escort_goal(hero, arena, bb, pos)
		Mode.SUPPORT:
			goal = _support_goal(hero, arena, bb, pos)
		Mode.FIGHT, Mode.ATTACK_CARRIER:
			goal = _combat_goal(hero, arena, bb, pos)

	# SEISONTAVAHDIN PAKKOMAALI: ohittaa tilan oman maalin kunnes se saavutetaan
	# tai ikkuna umpeutuu. Ajetaan ennen jumin kiertopistettä, jotta seinänkierto
	# toimii myös pakkomaalia kohti — ja ennen tornihätää, joka voittaa yhä.
	if _unstick_t > 0.0:
		_unstick_t -= delta
		if _unstick_t <= 0.0 or pos.distance_to(_unstick_goal) < 110.0:
			_unstick_t = 0.0
			_unstick_goal = Vector2.INF
		else:
			goal = _unstick_goal

	# Jumiutumisen tunnistus + tilapäinen kiertopiste. Ajetaan ENNEN tornihätää,
	# jotta hätäpoistuminen voittaa aina vanhentuneen kiertopisteen.
	goal = _apply_stuck_repath(hero, arena, goal, delta)

	# Framikohtainen turvaverkko: tornin aggro voi vaihtua heti sankariosuman
	# jälkeen, paljon ennen seuraavaa vaikeustason mukaista päätöshetkeä.
	var emergency_goal := _moba_emergency_goal(hero, arena)
	if is_finite(emergency_goal.x):
		goal = emergency_goal

	var desired: Vector2 = goal - pos
	if desired.length() < 24.0:
		desired = Vector2.ZERO
	else:
		desired = desired.normalized()

	# Sivuttaisliike taistelussa, ettei botti seiso maalitauluna.
	if _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER] and _target != null and desired.length() < 0.7:
		if randf() < 0.01:
			_strafe_dir = -_strafe_dir
		var to_t: Vector2 = (_target.global_position - pos).normalized()
		desired += to_t.orthogonal() * sin(_time * 2.5) * 0.5 * _strafe_dir

	# Kiting: kaukotaistelija pakittaa kun vihollissankari tulee liian lähelle.
	# Korkea kite_skill pitää välin määrätietoisesti ja tulittaa pakittaessaan
	# (peruskantama > pref-etäisyys), matala tuskin reagoi ja jää turpaan.
	# Melee-jahti ei muutu.
	if _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER] and _is_ranged \
			and _target != null and is_instance_valid(_target) and not _target.is_unit:
		var kite_dist: float = pos.distance_to(_target.global_position)
		if kite_dist < _pref_range * 0.78:
			var back: Vector2 = (pos - _target.global_position).normalized()
			desired = desired * (1.0 - 0.55 * kite_skill) \
				+ back * (0.35 + 0.65 * kite_skill)

	# Erottelu ENSIN: ei tungeta liittolaisen päälle. Tehdään ennen esteenväistöä,
	# jotta seinänseuranta saa viimeisen sanan eikä erottelu työnnä takaisin seinään.
	# Kuuma polku (joka frame per botti): luetaan player_heroes-välimuistia
	# suoraan eikä rakenneta alive_allies()-välitaulukkoa 60x sekunnissa.
	for ally in arena.player_heroes:
		if ally == hero or not is_instance_valid(ally) or not ally.alive \
				or ally.team != hero.team:
			continue
		var diff: Vector2 = pos - ally.global_position
		if diff.length() < 70.0 and diff.length() > 0.01:
			desired += diff.normalized() * 0.6

	# KESKITTYMISKATKO: liikesuunta harhautuu (+-35 astetta) katkon ajan — botti
	# ei mene sinne minne aikoi. Tehdään ennen esteenväistöä, jotta seinänseuranta
	# korjaa harhan silti kelvolliseksi suunnaksi (ei uusia jumeja).
	if _lapse_t > 0.0 and desired.length() > 0.1:
		desired = desired.rotated(_lapse_drift)

	# Esteenväistö VIIMEISENÄ: seinänseuranta viuhkasäteillä (osaa liukua pitkää
	# seinää pitkin lähimmälle aukolle, esim. MOBA-kartan gank-aukoista).
	if desired.length() > 0.1:
		desired = _steer_around(hero, pos, desired, delta)

	_move = desired.limit_length(1.0)


## SEISONTAVAHTI (rank-neutraali, viimeinen turvaverkko). Kaikki muut vahdit
## katsovat AIKOMUSTA — liikevektoria (_idle_t) tai etäisyyttä maaliin
## (_apply_stuck_repath) — joten ne ovat sokeita tilanteelle jossa botilla on
## maali, se liikkuu sitä kohti ja maali seuraa bottia. Tämä vahti mittaa
## TODELLISTA sijaintia: jos elossa oleva sankari ei ole siirtynyt STALL_DIST
## päähän STALL_WINDOW sekunnissa eikä seisonnalle ole syytä (paluukanavointi,
## tainnutus, kauppa, ohjustila, tähtäyspito, lähdeparannus), päätös pakotetaan
## uusiksi ja sankari ohjataan takaisin peliin: ensin asemointitavoitteeseen
## (oma aalto/linja), ja jos sekään ei auta, omaan pyhäkköön josta normaali
## logiikka lähtee aina uudelleen liikkeelle.
##
## Vahti on tarkoituksella rank-neutraali: "en jää seisomaan koko otteluksi" ei
## ole taitoerottelua vaan pelin perusvaatimus. Kustannus per ruutu on yksi
## etäisyysvertailu, joten se kestää 32x simulaationopeuden.
func _tick_stall_guard(hero: Hero, arena, delta: float) -> void:
	var pos: Vector2 = hero.global_position
	if arena.mode != "moba" or hero.is_unit or not hero.alive:
		_stall_anchor = pos
		_stall_t = 0.0
		_stall_hits = 0
		return
	# Paikallaan olo on näissä tiloissa tarkoituksellista.
	if _recall or hero.shop_open or hero.piloting or hero.frozen > 0.0 \
			or hero.stun_timer > 0.0 or hero.root_timer > 0.0 \
			or float(_aim_hold.a1) > 0.0 or float(_aim_hold.a2) > 0.0:
		_stall_anchor = pos
		_stall_t = 0.0
		return
	# Paikallaan TEKEMINEN on sallittua: tuore taisteluvahinko tai oikeasti
	# lyöntietäisyydellä oleva kohde (piiritys, leiri, aallon farmi) tarkoittaa
	# että sankari tuottaa jotain. Vahti puuttuu vain tyhjään seisontaan.
	if hero.since_damage < 3.0:
		_stall_anchor = pos
		_stall_t = 0.0
		return
	if _target != null and is_instance_valid(_target) and bool(_target.alive) \
			and pos.distance_to(_target.global_position) <= _basic_range + 60.0:
		_stall_anchor = pos
		_stall_t = 0.0
		return
	var mm := arena.map as MapMoba
	# Lähteellä parantuminen ja ostaminen on oikeaa toimintaa; TÄYSISSÄ voimissa
	# pyhäkössä seisominen ei ole (juuri siihen vanha tyhjäkäyntivahti sokeutui).
	if mm != null and hero.hp < hero.max_hp \
			and mm.is_in_own_sanctuary(pos, hero.team):
		_stall_anchor = pos
		_stall_t = 0.0
		return
	if not is_finite(_stall_anchor.x) or pos.distance_to(_stall_anchor) >= STALL_DIST:
		_stall_anchor = pos
		_stall_t = 0.0
		_stall_hits = 0
		return
	_stall_t += delta
	if _stall_t < STALL_WINDOW:
		return
	# Seisonta todettu: nollaa kaikki paikallaan pitävät tilat ja pakota päätös.
	_stall_t = 0.0
	_stall_anchor = pos
	_stall_hits += 1
	_decision_timer = 0.0
	_lurk = false
	_cover_pos = Vector2.INF
	_via_t = 0.0
	_via_point = Vector2.INF
	var goal := Vector2.INF
	if _stall_hits < STALL_ESCALATE:
		goal = _activity_goal(hero, arena)
	if not is_finite(goal.x) and mm != null:
		# Viimeinen oljenkorsi: oma pyhäkkö. Sieltä sankari parantuu, ostaa ja
		# lähtee normaalilla lane-logiikalla takaisin peliin.
		goal = mm.fountain_spot(hero.team)
		_stall_hits = 0
	if is_finite(goal.x) and pos.distance_to(goal) > 90.0:
		_unstick_goal = goal
		_unstick_t = STALL_GOAL_TIME


## JUMIUTUMISEN TUNNISTUS (rank-neutraali): jos liikemaali on kaukana
## (>= 140 px) mutta sankari ei ole edennyt 30 px:ää 2.2 sekuntiin (seinä,
## kite-pakitus nurkkaan, umpikuja), reititä ~2 s ajan lähimmän järkevän
## kiertopisteen (lane-aukko / junglen ylityskohta) kautta ja käännä väistö-
## ja sivuttaissuunta. Ikkuna nollautuu aidosta etenemisestä ja maalin
## vaihtumisesta. Ajetaan kaikissa tiloissa, myös FIGHTissa — kite-pakitus
## seinää vasten laukeaa tästä.
func _apply_stuck_repath(hero: Hero, arena, goal: Vector2, delta: float) -> Vector2:
	var pos: Vector2 = hero.global_position
	# Voimassa oleva kiertopiste ohjaa kunnes se saavutetaan tai vanhenee.
	# Kaukainen piste hylätään (respawn/teleportti siirsi sankarin muualle).
	if _via_t > 0.0:
		_via_t -= delta
		if _via_t <= 0.0 or pos.distance_to(_via_point) < 70.0 \
				or pos.distance_to(_via_point) > 900.0:
			_via_t = 0.0
			_via_point = Vector2.INF
		else:
			return _via_point
	# Paikallaan pysyminen on tarkoituksellista näissä tiloissa.
	if _recall or hero.stun_timer > 0.0 or hero.root_timer > 0.0 \
			or hero.shop_open or hero.piloting:
		_stuck_anchor = pos
		_stuck_t = 0.0
		return goal
	if not is_finite(goal.x) or pos.distance_to(goal) < 140.0:
		_stuck_anchor = pos
		_stuck_t = 0.0
		_stuck_goal = goal
		return goal
	# Maalin vaihtuminen = uusi aikomus, ei jumi.
	if not is_finite(_stuck_goal.x) or _stuck_goal.distance_to(goal) > 220.0:
		_stuck_goal = goal
		_stuck_anchor = pos
		_stuck_t = 0.0
		return goal
	_stuck_goal = goal
	if not is_finite(_stuck_anchor.x) or pos.distance_to(_stuck_anchor) >= 30.0:
		_stuck_anchor = pos
		_stuck_t = 0.0
		return goal
	_stuck_t += delta
	if _stuck_t < 2.2:
		return goal
	# Jumi todettu: kiertopiste ja väistö-/sivuttaissuunnan vaihto.
	_stuck_t = 0.0
	_stuck_anchor = pos
	_strafe_dir = -_strafe_dir
	_avoid_turn = 0.0
	_avoid_time = 0.0
	_via_point = _repath_via(hero, arena, pos, goal)
	_via_t = 2.0
	return _via_point


## Kiertopiste jumin purkuun: lähin lane-aukko tai junglen ylityskohta joka
## vie kohti maalia (kokonaismatka painotettuna), muuten sivuaskel maalin
## suunnasta katsottuna (käännetty strafe hajauttaa suunnat).
func _repath_via(hero: Hero, arena, pos: Vector2, goal: Vector2) -> Vector2:
	var mm := arena.map as MapMoba
	if mm != null:
		var candidates: Array = []
		for lane_id in mm.lane_ids():
			candidates.append_array(mm.lane_entries(lane_id))
		candidates.append_array(mm.jungle_choke_points())
		var best := Vector2.INF
		var best_cost := INF
		for cand_v in candidates:
			var cand: Vector2 = cand_v
			var d_pos: float = pos.distance_to(cand)
			if d_pos < 120.0:
				continue   # piste jossa jo seistään ei pura jumia
			var cost: float = d_pos + cand.distance_to(goal) * 1.15
			if cost < best_cost:
				best_cost = cost
				best = cand
		if is_finite(best.x):
			return best
	# Ei karttatietoa (areena/viidakko): kierrä sivukautta kohti maalia.
	var dir: Vector2 = (goal - pos).normalized()
	return arena.map.clamp_to_field(
		pos + dir.orthogonal() * _strafe_dir * 260.0 + dir * 120.0, 90.0)


## Asemointi oman aallon mukana: piste hieman etumaisimman oman minionin
## takana omalla linjalla. Vector2.INF jos linjalla ei ole omia minioneja
## (silloin pidetään turvallinen rintamapiste ja edetään seuraavan aallon
## mukana, koska tämä lasketaan uudelleen joka päätöksellä).
func _lane_wave_goal(hero: Hero, arena) -> Vector2:
	var front := _lane_front_minion(hero, arena, _moba_lane)
	if not is_finite(front.x):
		return Vector2.INF
	# Kärkiminionin taakse: aalto tankkaa tornin/vihollisen, botti seuraa mukana.
	var push_sign: float = 1.0 if hero.team == 0 else -1.0
	return front - Vector2(push_sign * 130.0, 0.0)


## Etumaisin oma minioni annetulla linjalla, Vector2.INF jos aaltoa ei ole.
func _lane_front_minion(hero: Hero, arena, lane: String) -> Vector2:
	if lane == "":
		return Vector2.INF
	var push_sign: float = 1.0 if hero.team == 0 else -1.0
	var front := Vector2.INF
	var front_depth := -INF
	for m in arena.minions:
		if not is_instance_valid(m) or not m.alive or m.team != hero.team:
			continue
		if (m as Minion).lane_id != lane:
			continue
		var depth: float = m.global_position.x * push_sign
		if depth > front_depth:
			front_depth = depth
			front = m.global_position
	return front


## SUOJAUTUMINEN AALLON TAAKSE (rank-portitettu, arvonta per päätöstikki):
## melee-botti joka odottaa kohdettaan oman kantamansa ulkopuolella (esim.
## piiritys ei ole vielä edennyt lyöntietäisyydelle) ei jää seisomaan avoimena
## imemään kaukopokea. Ehto: tuore sankarivahinko TAI näkyvä vihollisen
## kaukosankari ~620 px sisällä. Vastaus: pidä kärkiminioni itsensä ja ampujan
## välissä (_cover_goal_pos), tai pakita ampujan kantaman ulkopuolelle jos
## aaltoa ei ole. Kohteen ollessa iskuetäisyydellä tämä ei koske — aktiivinen
## hyökkäys ja piirityskuri (siege_focus) jatkuvat. Jungleri viidakossa on
## vapautettu (leirifarmi ei ole poke-tilanne).
func _update_cover(hero: Hero, arena) -> void:
	_cover_pos = Vector2.INF
	if arena.mode != "moba" or _pref_range >= 160.0 or _mode != Mode.FIGHT:
		return
	if _recall or _lurk or _lane_returning or is_finite(_defend_pos.x):
		return
	var mm := arena.map as MapMoba
	if mm == null:
		return
	if _moba_job == "jungle" and mm.is_dark_jungle(hero.global_position):
		return
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return
	if hero.global_position.distance_to(_target.global_position) <= _cover_reach() + 14.0:
		return
	if randf() >= cover_skill:
		return
	var threat := _cover_threat(hero, arena)
	if threat == null:
		return
	_cover_pos = _cover_goal_pos(hero, arena, mm, threat)


## Kohteen todellinen iskuetäisyys tälle botille (rakennuksilla runko mukaan).
## Rakennuksella "todellinen" tarkoittaa piirityssäännön jälkeen sitä etäisyyttä
## jolta vahinko oikeasti menee läpi — ei sankarin nimellistä kantamaa.
func _cover_reach() -> float:
	var reach: float = _basic_range
	var st := _target as Structure
	if st != null:
		reach = _siege_clamped(reach, st) + st.radius
	return reach


## Poke-uhka suojautumista varten: lähin näkyvä vihollisen kaukosankari ~620 px
## sisällä, tai (jos sellaista ei näy) tuoreen sankarivahingon tekijä — ampuja
## voi olla puskassa/savussa, mutta osumat kertovat uhka-akselin silti.
func _cover_threat(hero: Hero, arena) -> Hero:
	var best: Hero = null
	var best_d := 620.0
	for e in arena.enemy_heroes(hero.team):
		if not _hero_is_ranged(e):
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < best_d and _moba_can_see(hero, e, arena):
			best_d = d
			best = e
	if best != null:
		return best
	if hero.since_damage < 2.5:
		var now: float = float(arena.match_elapsed)
		var fallback: Hero = null
		for entry in hero._recent_damagers:
			var attacker := entry.hero as Hero
			if attacker == null or not is_instance_valid(attacker) or not attacker.alive:
				continue
			if attacker.is_unit or attacker.team == hero.team:
				continue
			if now - float(entry.time) > 2.5:
				continue
			# Kaukohyökkääjä on ensisijainen uhka-akseli; melee kelpaa varalle
			# (pääasia on ettei odottelija seiso paikallaan osumia imemässä).
			if _hero_is_ranged(attacker):
				return attacker
			if fallback == null:
				fallback = attacker
		return fallback
	return null


## Halpa kaukotaistelija-arvio roolista/arkkityypistä (poke-uhkien tunnistus).
## Shade on etäassassiini erikoistapauksena (rooli ei kerro kantamaa).
func _hero_is_ranged(h: Hero) -> bool:
	if h.hero_id == "shade":
		return true
	var hero_def := HeroDef.get_def(h.hero_id)
	var role := str(hero_def.get("role", ""))
	var archetype := str(hero_def.get("archetype", ""))
	return role in ["Mage", "Ranger", "Tuki"] or archetype in ["Mage", "Ranger"]


## Suojapiste: kärkiminioni botin ja ampujan väliin (~46 px minionin taakse
## uhka-akselilla) — aalto tankkaa poket. Ilman omaa aaltoa pakitetaan ampujasta
## poispäin ~700 px etäisyydelle (kaukopoken kantaman ulkopuolelle).
func _cover_goal_pos(hero: Hero, arena, mm: MapMoba, threat: Hero) -> Vector2:
	var lane: String = _moba_lane
	if lane == "":
		lane = mm.nearest_lane(hero.global_position)
	var front := _lane_front_minion(hero, arena, lane)
	if is_finite(front.x) and front.distance_to(hero.global_position) < 900.0:
		var axis: Vector2 = front - threat.global_position
		if axis.length() < 1.0:
			axis = hero.global_position - threat.global_position
		if axis.length() < 1.0:
			axis = Vector2.LEFT if hero.team == 0 else Vector2.RIGHT
		return arena.map.clamp_to_field(front + axis.normalized() * 46.0, 70.0)
	var away: Vector2 = hero.global_position - threat.global_position
	if away.length() < 1.0:
		away = arena.map.spawn_point(hero.team, 0) - threat.global_position
	if away.length() < 1.0:
		return hero.global_position
	return arena.map.clamp_to_field(
		threat.global_position + away.normalized() * 700.0, 70.0)


## Junglerin tyhjäkäynnin oletus: kun omat leirit ovat kuolleet eikä gankkia
## tai makroa ole, varjosta lähimmän linjan omaa aaltoa viidakon puolelta
## rintaman tasalla — valmiina gankkiin, objectiveen tai puolustukseen.
## Ei koskaan vihollistornien rintaman ohi.
func _jungler_shadow_goal(hero: Hero, arena, mm: MapMoba) -> Vector2:
	var pos: Vector2 = hero.global_position
	var push_sign: float = 1.0 if hero.team == 0 else -1.0
	var best := Vector2.INF
	var best_d := INF
	for lane_id in mm.lane_ids():
		var lane: String = lane_id
		var front := Vector2.INF
		var front_depth := -INF
		for m in arena.minions:
			if not is_instance_valid(m) or not m.alive or m.team != hero.team:
				continue
			if (m as Minion).lane_id != lane:
				continue
			var depth: float = m.global_position.x * push_sign
			if depth > front_depth:
				front_depth = depth
				front = m.global_position
		if not is_finite(front.x):
			continue
		# Rintaman tasalle mutta viidakon puolelle harjannetta (y kohti keskustaa).
		var frontier: float = _enemy_tower_frontier(hero, arena, lane)
		var depth_x: float = minf(front.x * push_sign - 160.0, frontier)
		var shadow := Vector2(depth_x * push_sign, front.y * 0.62)
		var d: float = pos.distance_to(shadow)
		if d < best_d:
			best_d = d
			best = shadow
	return best


## Tyhjäkäyntivahdin pakotettu asemointitavoite: laneri aallon mukana,
## jungleri varjostamaan aaltoa. Torniturva leikkaa tavoitteen aina.
func _activity_goal(hero: Hero, arena) -> Vector2:
	var mm := arena.map as MapMoba
	if mm == null:
		return Vector2.INF
	var pos: Vector2 = hero.global_position
	if _moba_job == "jungle":
		var shadow := _jungler_shadow_goal(hero, arena, mm)
		if is_finite(shadow.x):
			return _moba_tower_safe(hero, arena, pos, shadow)
		var step: int = int(arena.match_elapsed / 6.0) + hero.profile.index + 1
		return mm.jungle_patrol(hero.team, step)
	if _moba_lane != "":
		var wave := _lane_wave_goal(hero, arena)
		if is_finite(wave.x):
			return _moba_tower_safe(hero, arena, pos, wave)
		return _moba_tower_safe(hero, arena, pos,
			_moba_lane_route_goal(hero, arena, pos))
	return Vector2.INF


## Seinänseuranta: jos eteenpäin on este, valitse kiertosuunta (avoimempi puoli,
## hystereesillä ettei värise) ja kokeile kasvavia kulmia kunnes löytyy vapaa
## suunta. Näin botti liukuu pitkää seinää pitkin lähimmälle aukolle sen sijaan
## että jää jumiin — ja osaa mennä esim. MOBA-kartan gank-aukoista.
func _steer_around(hero: Hero, pos: Vector2, desired: Vector2, delta: float) -> Vector2:
	var space := hero.get_world_2d().direct_space_state
	var look: float = 130.0 + hero.radius
	if _ray_clear(space, pos, desired, look):
		_avoid_turn = 0.0
		_avoid_time = 0.0
		return desired
	_avoid_time += delta
	# Valitse kiertosuunta kun väistö alkaa: avoimempi puoli (pidemmillä luotaimilla
	# jotta ne oikeasti havaitsevat edessä olevan seinän). Tasapelissä käytä botin
	# omaa strafe-suuntaa -> botit hajautuvat eri puolille eikä kaikki käänny samaan.
	if _avoid_turn == 0.0:
		var left_open: float = _open_dist(space, pos, desired.rotated(-0.6), look * 2.5)
		var right_open: float = _open_dist(space, pos, desired.rotated(0.6), look * 2.5)
		if left_open > right_open + 20.0:
			_avoid_turn = -1.0
		elif right_open > left_open + 20.0:
			_avoid_turn = 1.0
		else:
			_avoid_turn = _strafe_dir
	elif _avoid_time > 1.1:
		# Sama seinä liian kauan (mahd. väärä puoli tai umpikulma) -> vaihda puolta.
		_avoid_turn = -_avoid_turn
		_avoid_time = 0.0
	# Kokeile kasvavia kulmia valitulle puolelle.
	for mag in [0.5, 0.9, 1.3, 1.7, 2.2]:
		var cand: Vector2 = desired.rotated(_avoid_turn * mag)
		if _ray_clear(space, pos, cand, look):
			return cand
	# Valittu puoli täysin tukossa -> vaihda puolta ja kokeile.
	_avoid_turn = -_avoid_turn
	for mag2 in [0.5, 0.9, 1.3, 1.7]:
		var cand2: Vector2 = desired.rotated(_avoid_turn * mag2)
		if _ray_clear(space, pos, cand2, look):
			return cand2
	# Kaikki tukossa -> peräänny hieman (irrota kulmasta).
	return -desired * 0.4


func _ray_clear(space: PhysicsDirectSpaceState2D, pos: Vector2, dir: Vector2, dist: float) -> bool:
	var q := PhysicsRayQueryParameters2D.create(pos, pos + dir.normalized() * dist, 1)
	return space.intersect_ray(q).is_empty()


## Vapaan matkan pituus suuntaan (osumaan asti, tai koko dist jos vapaa).
func _open_dist(space: PhysicsDirectSpaceState2D, pos: Vector2, dir: Vector2, dist: float) -> float:
	var q := PhysicsRayQueryParameters2D.create(pos, pos + dir.normalized() * dist, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return dist
	var hp: Vector2 = hit["position"]
	return pos.distance_to(hp)


## Vetäytyminen: kite poispäin uhasta kohtuullinen matka (ei aivan nurkkaan).
## Kun uhkaa ei ole, liiku takaisin objektille — ei jäädä seisomaan respawniin.
func _retreat_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var away := Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		away = pos - _target.global_position
	elif bb.threat_center != Vector2.ZERO:
		away = pos - bb.threat_center
	# MOBA: vetäydy kohti OMAA tukikohtaa — ei reliikin piilopaikkaan (0,0) eikä
	# "pois uhasta" -suuntaan joka voi viedä SYVEMMÄLLE vihollisen alueelle.
	# Sekoita pako + kotisuunta -> palaa käytävää pitkin kotiin.
	if arena.mode == "moba":
		if _moba_job != "jungle" and _moba_lane != "":
			return _moba_lane_route_goal(hero, arena, pos, false)
		var home: Vector2 = arena.map.spawn_point(hero.team, 0)
		var to_home: Vector2 = home - pos
		var dir: Vector2 = to_home
		if away.length() > 1.0 and to_home.length() > 1.0:
			dir = away.normalized() * 0.5 + to_home.normalized()
		if dir.length() < 1.0:
			dir = to_home
		if dir.length() < 1.0:
			return home
		return arena.map.clamp_to_field(pos + dir.normalized() * 300.0, 100.0)
	if away.length() < 1.0:
		# Ei uhkaa: palaa peliin (reliikki/keskusta), älä jää nurkkaan.
		return arena.relic.global_position
	return arena.map.clamp_to_field(pos + away.normalized() * 280.0, 100.0)


func _enemy_within(hero: Hero, arena, dist: float) -> bool:
	for e in arena.alive_enemies(hero.team):
		if e.global_position.distance_to(hero.global_position) < dist:
			return true
	return false


## Kantaja kiertää keskustaa ja pakoilee lähintä vihollista.
func _carry_goal(arena, pos: Vector2) -> Vector2:
	var flee := Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		var away: Vector2 = pos - _target.global_position
		if away.length() < 420.0:
			flee = away.normalized() * 300.0
	var orbit: Vector2 = (pos - Vector2.ZERO).orthogonal().normalized() * 120.0 * _strafe_dir
	return arena.map.clamp_to_field(pos + flee + orbit, 160.0)


## Saatto: tankki asettuu kantajan eteen, tuki taakse.
func _escort_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var anchor: Hero = bb.own_carrier
	if anchor == null:
		return _combat_goal(hero, arena, bb, pos)
	var to_threat := Vector2.RIGHT
	if bb.threat_center != Vector2.ZERO:
		to_threat = (bb.threat_center - anchor.global_position).normalized()
	if _is_tank:
		# Tankki rintaman puolelle, valmiina blokkaamaan.
		return anchor.global_position + to_threat * 150.0
	# Tuki suojaan kantajan taakse.
	return anchor.global_position - to_threat * 110.0


## Tuki pysyy suojeltavan takana ja pakenee jos vihollinen pääsee lähelle.
func _support_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	var pocket: Hero = bb.protect_ally
	if arena.mode == "moba" and _moba_lane != "":
		var lane_partner := _moba_lane_partner(hero, arena)
		if lane_partner != null:
			pocket = lane_partner
	if pocket == null or pocket == hero:
		pocket = bb.frontline_ally
	# Ankkuri ei saa olla toinen tuki, jolla ei itsellään ole linjamaalia:
	# kaksi tukea ankkuroituisi toisiinsa ja pari ajautuisi yhdessä pois pelistä.
	if pocket != null and pocket != hero and arena.mode == "moba" \
			and _passive_anchor(pocket):
		pocket = null
	if pocket == null or pocket == hero:
		# MOBA: ei jäädä keskustaan — seuraa linjan työntöä oman aallon takana.
		if arena.mode == "moba":
			return _moba_support_goal(hero, arena, pos)
		# Ei suojeltavaa: pysy lähellä keskustaa mutta poissa vihollisista.
		var base: Vector2 = arena.relic.global_position
		if _target != null and is_instance_valid(_target) \
				and _target.global_position.distance_to(pos) < 240.0:
			return pos + (pos - _target.global_position).normalized() * 200.0
		return base
	var back := Vector2.ZERO
	if bb.threat_center != Vector2.ZERO:
		back = (pocket.global_position - bb.threat_center).normalized()
	var goal: Vector2 = pocket.global_position + back * 120.0
	# Väistä jos vihollinen liian lähellä (tuki ei kestä etulinjaa).
	if _target != null and is_instance_valid(_target):
		var d: float = _target.global_position.distance_to(pos)
		if d < 200.0:
			goal = pos + (pos - _target.global_position).normalized() * 200.0
	# MOBA: älä seuraa sukeltavaa etulinjaa vihollistornin kantamalle (tuki kestää
	# huonosti torni-iskuja) — sama kantamaklamppi kuin muullakin liikkeellä.
	if arena.mode == "moba":
		goal = _moba_tower_safe(hero, arena, pos, goal)
	return goal


## Onko liittolainen "passiivinen ankkuri" eli botti, jonka AINOA liikemaali on
## jonkun toisen selusta? Tämä on täsmälleen bottom-duon tukityönjako
## (_decide_moba -> Mode.SUPPORT). Tuki ei saa koskaan ankkuroitua tällaiseen
## liittolaiseen: kaksi tukea ankkuroituisi toisiinsa, kummallakaan ei olisi
## omaa linjamaalia, ja pari kävelisi toisiaan seuraten ulos pelistä.
func _passive_anchor(ally: Hero) -> bool:
	var brain := ally.controller as BotBrain
	if brain == null or brain._moba_job != "bottom":
		return false
	return brain._moba_duty == "support" \
		or (brain._moba_duty == "" and brain._is_support)


## Bottom-tuki valitsee oman laneparinsa, ei globaalin blackboardin jungleria
## tai top-laneria. Tämä estää tukibottia seuraamasta sattumalta heikointä
## liittolaista junglen läpi usean campin ajaksi.
func _moba_lane_partner(hero: Hero, arena) -> Hero:
	var best: Hero = null
	var best_score := 1.0e20
	var mm := arena.map as MapMoba
	for ally in arena.alive_allies(hero.team):
		if ally == hero:
			continue
		var same_lane := false
		if ally.controller is BotBrain:
			same_lane = (ally.controller as BotBrain)._moba_lane == _moba_lane
		elif mm != null:
			same_lane = mm.nearest_lane(ally.global_position) == _moba_lane
		if not same_lane or _passive_anchor(ally):
			continue
		var score: float = ally.global_position.distance_to(hero.global_position)
		if HeroDef.get_def(ally.hero_id).get("role", "") == "Tuki":
			score += 300.0
		if score < best_score:
			best_score = score
			best = ally
	return best


## MOBA-tuki ilman selvää suojeltavaa: seuraa työntävää liittolaista (pysy
## hänen takanaan vihollisen puolelle nähden), tai etene painostettavaa
## rakennusta kohti — ei ajauta keskustan jokivyöhykkeeseen.
func _moba_support_goal(hero: Hero, arena, pos: Vector2) -> Vector2:
	var push := _pick_push_target(hero, arena)
	var aim_pos: Vector2 = push.global_position if push != null else pos
	var lead := _moba_frontline_ally(hero, arena, aim_pos)
	var goal: Vector2 = pos
	if lead != null:
		# Asetu työntävän liittolaisen taakse (omalle puolelle päin).
		var back: Vector2 = (pos - aim_pos).normalized()
		goal = lead.global_position + back * 120.0
	else:
		# Yksin jäänyt tuki: älä sukella yksin linjaa pitkin MUTTA älä myöskään
		# jää seisomaan tukikohtaan. Vanha paluu spawn_pointiin oli toinen puoli
		# "botti seisoo koko ottelun" -viasta: baseen kävellyt tuki ei enää
		# koskaan saanut syytä lähteä sieltä. Nyt pelataan omaa linjaa oman
		# aallon mukana (sama asemointi kuin tyhjäkäyntivahdilla).
		var solo := _activity_goal(hero, arena)
		goal = solo if is_finite(solo.x) else arena.map.spawn_point(hero.team, 0)
	return _moba_tower_safe(hero, arena, pos, goal)


## Liittolainen, joka on lähimpänä painostettavaa rakennusta (työnnön kärki).
func _moba_frontline_ally(hero: Hero, arena, aim_pos: Vector2) -> Hero:
	var best: Hero = null
	var best_d := 1.0e20
	for a in arena.alive_allies(hero.team):
		if a == hero:
			continue
		if a.controller is BotBrain and (a.controller as BotBrain)._moba_lane != _moba_lane:
			continue
		# Toinen tuki ei kelpaa työnnön kärjeksi: sillä ei ole omaa maalia.
		if _passive_anchor(a):
			continue
		var d: float = a.global_position.distance_to(aim_pos)
		if d < best_d:
			best_d = d
			best = a
	return best


## Seuraa Eternal Dividen kaarevaa lanea waypointilta seuraavalle. Jos botti
## on ajautunut jungleen, ensimmäinen tavoite on lähin kohta omalla linjalla;
## vasta linjalle palattuaan se etenee kohti vihollisen basea.
func _moba_lane_route_goal(hero: Hero, arena, pos: Vector2,
		toward_enemy := true) -> Vector2:
	var mm := arena.map as MapMoba
	if mm == null or _moba_lane == "":
		return pos
	var path: Array = mm.lane_path(_moba_lane)
	if hero.team == 1:
		path = path.duplicate()
		path.reverse()
	if path.size() < 2:
		return pos
	var closest: Vector2 = path[0]
	var best_sq := INF
	var best_segment := 0
	var best_t := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		var point := a + ab * t
		var d_sq := pos.distance_squared_to(point)
		if d_sq < best_sq:
			best_sq = d_sq
			closest = point
			best_segment = i
			best_t = t
	var on_jungle_side := (pos.y > -1250.0) if _moba_lane == MapMoba.TOP \
		else (pos.y < 1250.0)
	if best_sq > 260.0 * 260.0 and on_jungle_side:
		return _safe_lane_entry(hero, arena, mm)
	if best_sq > 175.0 * 175.0:
		return closest
	if toward_enemy:
		var advance := best_segment + (2 if best_t > 0.72 else 1)
		return path[mini(advance, path.size() - 1)]
	var retreat := best_segment - (1 if best_t < 0.25 else 0)
	return path[maxi(retreat, 0)]


## Tilaisuusgank: vihollislaneri on ylittänyt joen meidän puolellemme linjan
## tuntumassa -> palauta gank-portti (puskan kohta) josta jungleri lähestyy sen
## selustaa. Vector2.INF jos tilaisuutta ei ole. Taito portitettu: matalat
## rankit eivät tunnista tilaisuutta (jungle_focus) eikä hutera botti gankkaa.
func _gank_opportunity(hero: Hero, arena, mm: MapMoba) -> Vector2:
	if jungle_focus < 0.25 or hero.hp < hero.max_hp * 0.45:
		_gank_victim = null
		return Vector2.INF
	# Hystereesi: pidä valittu uhri ja portti niin kauan kuin uhri täyttää ehdot
	# — muuten portti sinkoilisi (1020<->2350 / top<->bottom) joka päätöstikillä.
	# Huom: tunnistus toimii minimap-tiedolla (ei vaadi näköyhteyttä) — tämä on
	# tarkoituksellista: ylityöntö NÄKYY kartalla, ja gank rankaisee siitä.
	if _gank_victim != null and is_instance_valid(_gank_victim) \
			and _gank_gate_if_valid(hero, mm, _gank_victim) != Vector2.INF:
		return _gank_gate
	_gank_victim = null
	var best_d := 1900.0   # gank-matkan katto: ei ristiin koko kartan yli
	for e in arena.enemy_heroes(hero.team):
		var gate := _gank_gate_if_valid(hero, mm, e)
		if gate == Vector2.INF:
			continue
		var d: float = hero.global_position.distance_to(e.global_position)
		if d >= best_d:
			continue
		best_d = d
		_gank_victim = e
		_gank_gate = gate
	return _gank_gate if _gank_victim != null else Vector2.INF


## Uhrin gank-portti jos uhri on kelvollinen (meidän puolella, linjan tuntumassa,
## matkakaton sisällä); muuten Vector2.INF. Portin syvyysvalinnassa leveä
## vaihtokaista (1500/1800) estää edestakaisen vaihtelun rajalla.
func _gank_gate_if_valid(hero: Hero, mm: MapMoba, e: Hero) -> Vector2:
	if not is_instance_valid(e) or not e.alive:
		return Vector2.INF
	var own_sign: float = -1.0 if hero.team == 0 else 1.0
	var depth: float = e.global_position.x * own_sign
	if depth < 200.0:
		return Vector2.INF
	var lane := mm.nearest_lane(e.global_position)
	if mm.distance_to_lane(e.global_position, lane) > 520.0:
		return Vector2.INF
	if hero.global_position.distance_to(e.global_position) > 1900.0:
		return Vector2.INF
	var deep_gate: bool = absf(e.global_position.x) >= \
		(1500.0 if e == _gank_victim and absf(_gank_gate.x) > 2000.0 else 1800.0)
	var gate_x: float = own_sign * (2350.0 if deep_gate else 1020.0)
	var gate_y: float = -1130.0 if lane == MapMoba.TOP else 1130.0
	return Vector2(gate_x, gate_y)


## Vihollistornien rintaman syvyys tällä linjalla: etumaisimman ELOSSA olevan
## vihollistornin |x| - marginaali. Syvemmälle (kohti vihollisnexusta) ei ole
## turvallista kävellä ilman aaltoa. Kaikki tornit kaatuneet -> koko linja auki.
func _enemy_tower_frontier(hero: Hero, arena, lane: String) -> float:
	var frontier := 3600.0
	var foe: int = 1 - hero.team
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team != foe:
			continue
		if s.kind != Structure.Kind.TOWER or s.lane_id != lane:
			continue
		frontier = minf(frontier, absf(s.global_position.x) - 260.0)
	return frontier


## Lähin TURVALLINEN aukko omalle linjalle: ei koskaan aukkoa joka on
## vihollistornien takana (botti käveli aiemmin vihollisen sisä- ja base-tornin
## VÄLIIN palatessaan junglen kautta ja joutui kävelemään sieltä pois).
func _safe_lane_entry(hero: Hero, arena, mm: MapMoba) -> Vector2:
	var frontier := _enemy_tower_frontier(hero, arena, _moba_lane)
	var best := Vector2.INF
	var best_sq := INF
	var nearest := Vector2.INF   # varapaikka: lähin aukko suodattimesta riippumatta
	var nearest_sq := INF
	for candidate in mm.lane_entries(_moba_lane):
		var entry: Vector2 = candidate
		var d_sq: float = hero.global_position.distance_squared_to(entry)
		if d_sq < nearest_sq:
			nearest_sq = d_sq
			nearest = entry
		# Syvyys vihollisen suuntaan: sininen työntää +x, oranssi -x. Oman
		# puolen aukot läpäisevät aina (frontier >= 790 kun torneja pystyssä).
		var depth: float = entry.x if hero.team == 0 else -entry.x
		if depth > frontier:
			continue
		if d_sq < best_sq:
			best_sq = d_sq
			best = entry
	# Ilman varapaikkaa paluuarvo oli Vector2.ZERO (joen keskus) jos JOKAINEN
	# aukko oli vihollistornien takana — botti käveli kartan keskelle luullen
	# palaavansa linjalle.
	if is_finite(best.x):
		return best
	if is_finite(nearest.x):
		return nearest
	return hero.global_position


## Taisteluasemointi: lähesty kohdetta roolin ihannematkalle. Tankki peelaa.
func _combat_goal(hero: Hero, arena, bb: TeamBlackboard, pos: Vector2) -> Vector2:
	# PUOLUSTUS (MOBA): pysy uhatun oman rakennuksen luona. Taistele kohdetta vain
	# jos se on lähellä rakennusta; muuten asetu rakennuksen ja uhkasuunnan väliin
	# (odota hyökkääjää siellä, älä lähde perään syvälle).
	if is_finite(_defend_pos.x):
		var enemy_at_base: bool = _target != null and is_instance_valid(_target) \
			and _target.global_position.distance_to(_defend_pos) < 520.0
		if not enemy_at_base:
			var d2: Vector2 = bb.threat_center - _defend_pos
			if d2.length() < 1.0:
				d2 = Vector2.ZERO - _defend_pos   # kohti keskustaa jos ei uhkapistettä
			if d2.length() < 1.0:
				return _defend_pos
			return _defend_pos + d2.normalized() * 140.0

	# Tankin peel: jos vihollinen uhkaa suojeltavaa, asetu väliin. Ei rakennuksia
	# vastaan (tornia ei "peelata" — sitä työnnetään).
	if _is_tank and bb.protect_ally != null and bb.protect_ally != hero \
			and _target != null and is_instance_valid(_target) and not (_target is Structure):
		var pd: float = _target.global_position.distance_to(bb.protect_ally.global_position)
		if pd < 220.0:
			return bb.protect_ally.global_position \
				+ (_target.global_position - bb.protect_ally.global_position).normalized() * 60.0

	if _target == null or not is_instance_valid(_target):
		if bb.own_carrier != null and is_instance_valid(bb.own_carrier):
			return bb.own_carrier.global_position
		if arena.mode == "moba":
			if is_finite(_moba_goal.x):
				return _moba_goal
			var mm := arena.map as MapMoba
			if mm != null:
				if _moba_job == "jungle":
					var step := int(arena.match_elapsed / 8.0) + hero.profile.index
					return mm.jungle_patrol(hero.team, step)
				return mm.role_anchor(hero.team, _moba_lane)
			return arena.map.spawn_point(hero.team, 0)
		return arena.relic.global_position

	var dist: float = pos.distance_to(_target.global_position)
	# SUOJAUTUMINEN: kohde ei ole lyöntietäisyydellä ja kaukopoke satelee ->
	# pidä kärkiminioni itsensä ja ampujan välissä (tai pakita kantaman ulko-
	# puolelle). Heti kun kohde on iskuetäisyydellä, ehto raukeaa ja normaali
	# taistelu/piiritys jatkuu — suoja ei koskaan keskeytä aktiivista lyömistä.
	if arena.mode == "moba" and is_finite(_cover_pos.x) and not _lurk \
			and dist > _cover_reach() + 14.0:
		return _moba_tower_safe(hero, arena, pos, _cover_pos)
	if arena.mode == "moba" and _moba_job != "jungle" and _moba_lane != "":
		var lane_objective := false
		var behind := false
		if _target is Minion:
			lane_objective = (_target as Minion).lane_id == _moba_lane
			behind = (_target.global_position.x < pos.x) if hero.team == 0 \
				else (_target.global_position.x > pos.x)
		elif _target is Structure:
			var structure := _target as Structure
			lane_objective = structure.kind == Structure.Kind.NEXUS \
				or structure.lane_id == _moba_lane
			# TYHJÄKÄYNNIN POISTO: tornikohde jota ei vielä ylety lyömään ->
			# asemoidu OMAN AALLON mukana sen sijaan että seisoisi tyhjällä
			# rintamalla odottamassa ("botti norkoilee linjan alkupäässä").
			# Aalto edellä -> seuraa sen taakse; aalto takana -> peräänny sen
			# tasalle. Kun aalto on jo tornilla (crash), normaali piiritys
			# jatkaa — muuten melee ei koskaan etenisi lyömään tornia.
			if structure.kind == Structure.Kind.TOWER and lane_objective \
					and dist > _siege_clamped(_basic_range, structure) + structure.radius:
				var wave_goal := _lane_wave_goal(hero, arena)
				if is_finite(wave_goal.x) \
						and wave_goal.distance_to(structure.global_position) \
							> Structure.SHOT_RANGE + 60.0:
					if pos.distance_to(wave_goal) > 620.0:
						return _moba_lane_route_goal(hero, arena, pos)
					return _moba_tower_safe(hero, arena, pos, wave_goal)
		# Kaukaiseen waveen/torniin ei juosta suoraa viivaa junglen läpi.
		if lane_objective and not behind and dist > 620.0:
			return _moba_lane_route_goal(hero, arena, pos)
	var to_target: Vector2 = (_target.global_position - pos).normalized()
	var goal: Vector2 = pos
	# PIIRITYSASEMOINTI: rakennuskohteelle haluttu etäisyys leikataan kehän
	# sisään. Ilman leikkausta kaukotaistelija (Scout _pref_range 500, Quill 500)
	# jäisi kantamaimmuniteetin ulkopuolelle eikä tekisi tornille yhtään mitään.
	var want_range: float = _siege_clamped(_pref_range, _target)
	if _lurk:
		# Väijy keskietäisyydeltä: älä syöksy sisään ennen avausta (assassin).
		var lurk_range := 360.0
		if dist < lurk_range - 60.0:
			goal = pos - to_target * 160.0
		elif dist > lurk_range + 140.0:
			goal = _target.global_position - to_target * lurk_range
		else:
			goal = pos
	elif dist > want_range + 40.0:
		goal = _target.global_position - to_target * want_range
	elif dist < want_range - 60.0:
		# Liian lähellä (etenkin kaukotaistelijat): peräänny. Askel on >= 140,
		# jotta seinään pinnautunut pakitus näkyy jumintunnistimelle.
		goal = pos - to_target * 160.0
	# Keep ranged jungle movement inside the camp leash. Otherwise a ranged bot
	# can repeatedly reset the same camp to full health while kiting it.
	if _target is Critter:
		var camp := _target as Critter
		var leash_limit := maxf(float(camp.controller.leash) - 90.0, 150.0)
		var from_home: Vector2 = goal - camp.home
		if from_home.length() > leash_limit:
			goal = camp.home + from_home.normalized() * leash_limit
	# MOBA: älä astu vihollistornin kantamalle ilman omaa aaltoa — riippumatta
	# siitä onko kohde torni vai sitä vartioiva minioni (torni ampuu minioneja
	# ensin, joten oman aallon on annettava crashata). Kaukotaistelijat ohitetaan.
	return _moba_tower_safe(hero, arena, pos, goal)


## Leikkaa maalipisteen tornin ulkopuolelle, ellei torni ole oikeasti lukittunut
## kestävään minioniaaltoon. Jos aggro on jo botissa, poistumispuoli valitaan
## oman tukikohdan suunnasta eikä satunnaisesti tornin toiselta puolelta.
func _moba_tower_safe(hero: Hero, arena, pos: Vector2, goal: Vector2) -> Vector2:
	if arena.mode != "moba":
		return goal
	var tower_hold: float = Structure.SHOT_RANGE + 85.0
	var out: Vector2 = goal
	for st in arena.structures:
		var s := st as Structure
		if s == null or not s.alive or s.team == hero.team:
			continue
		if s.kind == Structure.Kind.NEXUS:
			# Suojattu nexus polttaa laserilla (tappaa nopeasti) -> pysy AINA kaukana,
			# myös kaukotaistelijana. Haavoittuvana laser sammuu -> saa lähestyä (tuho).
			if not s.is_protected():
				continue
			var nhold: float = Structure.NEXUS_LASER_RANGE + 100.0
			if out.distance_to(s.global_position) >= nhold:
				continue
			out = _tower_escape_point(hero, arena, s, nhold)
			continue
		# Jo lukittu sankari vetäytyy kotiin päin, vaikka sen nykyinen maalipiste
		# olisi sattumalta kantaman ulkopuolella.
		if s._target_lock == hero and pos.distance_to(s.global_position) < tower_hold + 70.0:
			out = _tower_escape_point(hero, arena, s, tower_hold + 20.0)
			continue
		if out.distance_to(s.global_position) >= tower_hold:
			continue
		var min_hp_ratio: float = 0.67 - tower_judgement * 0.22
		var healthy: bool = hero.hp > hero.max_hp * min_hp_ratio
		if healthy and _tower_wave_safe(hero, arena, s):
			continue
		out = _tower_escape_point(hero, arena, s, tower_hold)
	return out


## Onko sankarikohteen jahtaaminen tornin alla kielletty? Minioniaalto ei tee
## vihollissankarin lyömisestä turvallista: torni siirtää aggron välittömästi
## hyökkääjään. Vain korkeat tasot saavat tehdä tarkasti rajatun execute-diven.
func _tower_diving(hero: Hero, arena) -> bool:
	if arena.mode != "moba":
		return false
	if _target == null or not is_instance_valid(_target) or not _target.alive or _target.is_unit:
		return false
	var tower := _enemy_tower_covering(hero, arena, _target.global_position)
	if tower == null:
		return false
	# Ulkopuolelta ampuva ranger/mage saa pokettaa tornin alla olevaa kohdetta;
	# puolustusaggro ei valitse kantaman ulkopuolella olevaa hyökkääjää.
	if hero.global_position.distance_to(tower.global_position) > Structure.SHOT_RANGE + 12.0:
		return false
	return not _calculated_tower_execute(hero, arena, tower)


func _calculated_tower_execute(hero: Hero, arena, tower: Structure) -> bool:
	# Näytetty vaikeustaso 4+ (sisäinen indeksi 3+) oppii dive-executet. Alemmat
	# pelaavat turvallisemmin sen sijaan, että niiden vaikeus syntyisi ruokkimisesta.
	if level < 3 or _target == null or not _target_is_hero():
		return false
	if tower._target_lock == hero or tower._charge >= 0.62:
		return false
	var target_ratio: float = _target.hp / maxf(_target.max_hp, 1.0)
	var execute_limit: float = 0.08 + float(level - 3) * 0.035
	var own_limit: float = 0.82 - float(level - 3) * 0.04
	if target_ratio > execute_limit or hero.hp < hero.max_hp * own_limit:
		return false
	if hero.global_position.distance_to(tower.global_position) < 280.0:
		return false                         # liian syvällä: poistumistie on liian pitkä
	if hero.global_position.distance_to(_target.global_position) > _basic_range:
		return false                         # ei lisäjahtia executea varten
	if arena.heroes_in_circle(_target.global_position, 240.0, 1 - hero.team, true, true).size() > 1:
		return false                         # ei diveä usean puolustajan keskelle
	return _escape_ready(hero)


## Onko sankarilla poistumistie valmiina. Assassiineilla kaksivaiheisen kyvyn
## AVATTU toinen vaihe (kaiku, varjo, merkki) on jo maksettu pakotie ja lasketaan
## valmiiksi, vaikka kyvyn oma jäähdytys olisi käynnissä.
func _escape_ready(hero: Hero) -> bool:
	if hero.cd.dodge <= 0.0:
		return true
	match hero.hero_id:
		"blink":
			if (hero as Blink).echo_fraction() > 0.0:
				return true
			return hero.cd.a1 <= 0.0 and hero._can_afford("a1")
		"shade":
			if (hero as Shade).shadow_fraction() > 0.0:
				return true
			return hero.cd.a1 <= 0.0
		"rift":
			# Riftin pakotie on väistö (räjäytys hyvittää sen) tai varppaus merkille.
			return hero.cd.a1 <= 0.0 or (hero as Rift).has_mark()
		"obsidian", "lance":
			return hero.cd.a1 <= 0.0 and hero._can_afford("a1")
		"tide":
			return hero.cd.a1 <= 0.0 and hero.ammo > 0
	return false


## Assassiinin kaksivaiheisen kyvyn VALMIS jatko: Blinkin Jälkiterä ja kaikupaluu
## sekä Shaden varjopaluu. Nämä eivät saa jäädä roikkumaan satunnaisheiton,
## väijynnän tai tornidive-eston taakse: ikkuna on jo maksettu, ja käyttämättä
## jättäminen on aina huonompi lopputulos kuin käyttäminen.
func _assassin_finish(hero: Hero, arena) -> String:
	match hero.hero_id:
		"blink":
			var bl := hero as Blink
			if bl.follow_fraction() > 0.0:
				return "a2"                 # lopetusikkuna auki -> Jälkiterä
			if bl.echo_fraction() > 0.0 and _assassin_should_return(hero, arena,
					bl.echo_fraction()):
				return "a1"
		"shade":
			var sh := hero as Shade
			if sh.shadow_fraction() > 0.0 and _assassin_should_return(hero, arena,
					sh.shadow_fraction()):
				return "a1"
	return ""


## Palataanko heti: matala HP, kohde kaatunut, ikkuna loppumassa tai ylivoima
## päällä. Muuten assassiini jää vielä lyömään — paluu ei ole pakokauhu vaan
## ajoitettu poistuminen.
func _assassin_should_return(hero: Hero, arena, window_frac: float) -> bool:
	if hero.hp < hero.max_hp * 0.55:
		return true
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return true
	if window_frac < 0.35:
		return true
	return arena.heroes_in_circle(hero.global_position, 220.0,
		1 - hero.team, true, true).size() >= 2


func _update_aim(hero: Hero) -> void:
	# Pakopidon lukittu suunta: tähtäystä ei käännetä takaisin kohteeseen
	# kesken tähdättävän pakokyvyn pidon.
	if _aim_lock_t > 0.0:
		_aim = _aim_lock
		return
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		if _move.length() > 0.1:
			_aim = _move.normalized()
		return
	var to_target: Vector2 = _target.global_position - hero.global_position
	# Ennakointi: tähtää sinne minne kohde on menossa.
	var lead: Vector2 = _target.velocity * (to_target.length() / 900.0) * prediction
	_aim = (to_target + lead).normalized().rotated(_aim_err)


func _update_attack(hero: Hero, delta: float) -> void:
	_attack = false
	if _target == null or not is_instance_valid(_target) or not _target.alive:
		return
	if _reaction_left > 0.0:
		return
	if _lurk:
		return                          # väijyvä assassin ei tulita, odottaa avausta
	# Keskittymiskatko: perusisku jää puolet ruuduista väliin (tehollinen
	# vahinko puolittuu katkon ajaksi) — kykyjä ei käytetä lainkaan.
	if _lapse_t > 0.0 and randf() < 0.5:
		return
	if hero.arena.mode == "moba":
		# Älä jatka perusiskua aggron vaihduttua, äläkä aktivoi puolustusaggroa
		# vihollissankariin ilman hyväksyttyä execute-divenä.
		if _tower_emergency(hero, hero.arena) != null \
				or _protected_nexus_danger(hero, hero.arena) != null:
			return
		if _target_is_hero() and _tower_diving(hero, hero.arena):
			return
	# HUOM: vetäytyessä botti saa puolustautua (ampua takaa-ajajaa), liike vie
	# silti poispäin — ei enää avutonta seisoskelua.
	var dist: float = hero.global_position.distance_to(_target.global_position)
	# Rakennukselle katto on TODELLINEN vahinkoetäisyys (kantama + kohteen säde),
	# ei sankarin oma kantama: kauempaa ammuttu osuma ei tee mitään, ja esim.
	# Scoutin lipas valuisi tyhjäksi matkalla. Katto on tarkoituksella löysempi
	# kuin asemointietäisyys (_siege_clamped), jottei niiden väliin jää kuollutta
	# vyöhykettä jossa botti ei liikkuisi eikä ampuisi.
	var reach: float = _basic_range
	if _target is Structure:
		reach = minf(reach, Structure.SHOT_RANGE + _target.radius)
	if dist > reach:
		_hold_timer = 0.0
		return

	if hero.hero_id == "quill":
		# Lataa ja vapauta: pidä pohjassa hetki, sitten irti.
		_hold_pause -= delta
		if _hold_timer > 0.0:
			_hold_timer -= delta
			_attack = _hold_timer > 0.0  # kun ajastin loppuu, release-reuna syntyy
		elif _hold_pause <= 0.0:
			# Latauksen kesto skaalautuu vaikeustasolla: korkeat tasot lataavat
			# lähes täyteen (>=0.9 s), matalat ampuvat vajaalla.
			_hold_timer = randf_range(0.4, 0.7) + ability_chance * 0.4
			# Tauko latauksen JÄLKEEN on yli perushyökkäyksen cd:n, ettei uusi
			# lataus ala cd:n päällä (silloin lataus ei käynnisty -> ei ammu
			# mitään joka toinen kierros, mikä puolitti Quillin vahingon).
			_hold_pause = _hold_timer + float(hero.cd_max.basic) + 0.1
			_attack = true
	else:
		_attack = _combat_engaged(delta)


## Aggression-jaksotus: heikommat botit hyökkäävät vain osan ajasta, jolloin
## niiden tehollinen vahinko laskee eikä pelaajaa tulita jatkuvasti.
func _combat_engaged(delta: float) -> bool:
	if aggression >= 0.999:
		return true
	_atk_phase -= delta
	if _atk_phase <= 0.0:
		_atk_phase = randf_range(0.5, 1.0)
		_atk_firing = randf() < aggression
	return _atk_firing


## Tähdättävien kykyjen pitokone: tikittää pitoajastimia ja nostaa vapautuksen
## tasan yhdeksi frameksi kun pito päättyy. Tainnutus, vaimennus, kauppa,
## ohjaustila ja paluukanavointi keskeyttävät pidon (vapautus ei jää
## kummittelemaan), ja kuoleman/jäädytyksen yli jäänyt pito nollataan
## päivitysaukosta (update ei aja kuolleena, joten aukko paljastaa sen).
func _tick_aim_holds(hero: Hero, delta: float) -> void:
	for slot in _aim_release:
		_aim_release[slot] = false
	var now: float = float(hero.arena.match_elapsed)
	var gap: bool = _hold_seen_t >= 0.0 and now - _hold_seen_t > 0.4
	_hold_seen_t = now
	var blocked: bool = not hero.alive or hero.stun_timer > 0.0 \
		or hero.silence_timer > 0.0 or hero.shop_open or hero.piloting or _recall
	if gap or blocked:
		_aim_hold.a1 = 0.0
		_aim_hold.a2 = 0.0
		_aim_lock_t = 0.0
		return
	for slot in _aim_hold:
		var left: float = float(_aim_hold[slot])
		if left <= 0.0:
			continue
		left -= delta
		_aim_hold[slot] = maxf(left, 0.0)
		if left <= 0.0:
			_aim_release[slot] = true
	_aim_lock_t = maxf(_aim_lock_t - delta, 0.0)


## Botin "kykypainallus": tähdättävä kyky alkaa näkyvänä pitona jonka kesto
## skaalautuu rankilla (aim_time); muut laukeavat heti lippujen kautta.
## lock_dir lukitsee tähtäyssuunnan pidon ajaksi (pakosyöksy poispäin) ja
## time_scale lyhentää hätäpidon (pako ei saa telegrafoitua täyttä aikaa).
func _request_cast(hero: Hero, slot: String, lock_dir := Vector2.ZERO,
		time_scale := 1.0) -> void:
	if slot in ["a1", "a2"] and slot in hero._aimed_slots():
		if float(_aim_hold[slot]) > 0.0 or bool(_aim_release[slot]):
			return   # pito jo käynnissä -> ei uudelleenkäynnistystä
		_aim_hold[slot] = aim_time * time_scale * randf_range(0.85, 1.25)
		if lock_dir != Vector2.ZERO:
			_aim_lock = lock_dir
			_aim_lock_t = float(_aim_hold[slot]) + 0.2
		return
	_flags[slot] = true


## Kyvyt harkitaan vain päätöstahdissa, portitettuna vaikeustasolla.
func _update_abilities(hero: Hero, arena, bb: TeamBlackboard, decided: bool) -> void:
	if not decided:
		return
	if arena == null or not is_instance_valid(arena):
		return
	# Keskittymiskatko: ei kykyjä eikä ulttia (ei _request_cast, ei _flags).
	# Juuri tämä tekee katkosta kalliin — hukatut kykyikkunat ovat se ero jonka
	# ylempi divisioona voittaa.
	if _lapse_t > 0.0:
		return
	# Ottelun/objektiivin vaihtuessa vanha kohde voi vapautua saman fysiikkaruudun
	# Clear it before the typed hero-specific utility callback.
	if _target != null and not is_instance_valid(_target):
		_target = null
	var pos: Vector2 = hero.global_position
	var dist := 1e20
	if _target != null and is_instance_valid(_target):
		dist = pos.distance_to(_target.global_position)
	var near_enemies: int = arena.heroes_in_circle(pos, 320.0, 1 - hero.team, true, true).size()

	# Onko kohde vihollistornin alla ilman turvallista dive-syytä? Jos on, ei
	# käytetä syöksy-/hyökkäyskykyjä eikä ulttia sinne (ei tornidiveä tappoja
	# jahdaten -> bait-kuolemat loppuvat). Liike hoidetaan _moba_tower_safella.
	var diving: bool = _tower_diving(hero, arena)

	# PIIRITYS EI OLE KYKYJEN PAIKKA: rakennus ottaa kyvyiltä vain murto-osan
	# (Structure.ABILITY_SIEGE_MULT) eikä aluevahingosta yhtään mitään, joten
	# jäähdytyksen polttaminen torniin on lähes puhdasta hukkaa — perusisku on
	# piiritysase. Sääntö on TAITOILMAISU eikä kova esto: matala combo_skill
	# heittää kyvyt silti joskus seinään (sama akseli joka hoitaa kombot ja
	# kykyvalinnan), korkea rank säästää ne saapuvalle puolustajalle.
	# Yksi arvonta per päätöstahti kattaa sekä ultin että a1/a2:n.
	var structure_target: bool = _target != null and is_instance_valid(_target) \
		and _target is Structure
	var siege_ability_ok: bool = not structure_target \
		or randf() < 0.15 * (1.0 - combo_skill)

	# Ultimate — arvokkain, käytetään herkemmin kaikilla vaikeustasoilla.
	# Lukittua ulttia (ranki 0, aukeaa tasolla 4) ei edes harkita.
	if hero.ult_charge >= 100.0 and hero.ult_unlocked():
		if not diving and siege_ability_ok \
				and _want_ult(hero, arena, bb, dist, near_enemies) and randf() < ult_chance:
			_flags.ult = true
			_begin_ult_combo(hero)
			return

	# Itsesuojelu: hädässä (matala hp tai monta vihollista lähellä) pakene
	# liikkumiskyvyllä tai väistöllä. Ylemmät tasot reagoivat, alemmat eivät.
	if self_preserve > 0.05 and _in_danger(hero, arena) and randf() < self_preserve:
		if _try_escape(hero, bb):
			return

	# ASSASSIININ TOINEN VAIHE ennen kaikkia portteja: kaiku, varjo ja
	# lopetusikkuna ovat jo maksettuja ja ne ovat kitin pakotie sekä purske.
	# Ne eivät saa hukkua satunnaisheittoon, väijyntään tai piiritysestoon.
	if _is_assassin:
		var finish: String = _assassin_finish(hero, arena)
		if finish != "" and hero.cd[finish] <= 0.0 and hero._can_afford(finish):
			_request_cast(hero, finish)
			return

	# Scout: lataa lipas RULLAAMALLA (X) kun se on kolmanneksessa eikä ole
	# välitöntä vaaraa (rulla lataa heti; muuten 2.5 s auto-lataus kesken
	# taistelun syö perusvahingon). Perustaito -> lähes kaikilla tasoilla.
	# (Tornitilassa ammo pysyy täynnä, joten tämä ei laukea silloin turhaan.)
	if hero.hero_id == "scout" and dodge_chance > 0.05 and hero.cd.dodge <= 0.0 \
			and not hero.reloading and hero.ammo <= maxi(2, hero.ammo_max / 3) \
			and not _in_danger(hero, arena):
		_flags.dodge = true
		return

	# Junglerien X on kitin utility, ei geneerinen pakohyppy. Hahmo itse kertoo
	# milloin leiri/objective tarvitsee sen; näin botti käyttää ankkurin, dronin,
	# junglerin väistön myös farmissa eikä vain paniikkiväistönä.
	if _is_jungler_role and hero.cd.dodge <= 0.0 and hero.has_method("bot_wants_utility") \
			and bool(hero.call("bot_wants_utility")) \
			and randf() < 0.35 + combo_skill * 0.6:
		_flags.dodge = true
		return

	# Rakennuskohteen kykyesto vasta TÄSSÄ: itsesuojelu ja junglerin utility
	# (yllä) saavat yhä laueta, koska piirittäjä joutuu nyt seisomaan tornin
	# kantamalla ja tarvitsee pakokykynsä.
	if not siege_ability_ok:
		return

	if _lurk:
		return                          # väijyessä ei käytetä engage-kykyjä (a1/a2)

	if randf() > ability_chance:
		return

	# Tornidive-esto: älä käytä engage-/syöksykykyjä kohteeseen joka on
	# vihollistornin alla ilman omaa aaltoa (pako-a1 hoidetaan _try_escapessa yllä).
	if diving:
		_clear_combo()
		return

	# Valmis kombon jatko ohittaa tavallisen satunnaisheiton. Resurssi ja oikea
	# kantama tarkistetaan uudelleen, joten muisti ei pakota mahdotonta castia.
	if _combo_followup != "" and _combo_target == _target:
		var follow_ready: bool = hero.cd[_combo_followup] <= 0.0 \
			and hero._can_afford(_combo_followup)
		if follow_ready:
			var follow_wanted: bool = _want_a1(hero, arena, bb, dist, pos) \
				if _combo_followup == "a1" else _want_a2(hero, arena, bb, dist, pos)
			if follow_wanted:
				var used: String = _combo_followup
				_request_cast(hero, used)
				# Kolmas isku: assassiinien kaksivaiheiset kyvyt ketjuttavat vielä
				# kerran (Riftin varppaus -> räjäytys tyhjyysaukossa).
				_combo_followup = _chain_after(hero, used)
				if _combo_followup != "":
					_combo_timer = maxf(_combo_timer, 1.4)
				return

	var want_a1: bool = hero.cd.a1 <= 0.0 and hero._can_afford("a1") \
		and _want_a1(hero, arena, bb, dist, pos)
	var want_a2: bool = hero.cd.a2 <= 0.0 and hero._can_afford("a2") \
		and _want_a2(hero, arena, bb, dist, pos)

	# Taitava liikkuva sankari ei polta viimeistä poistumistietään aggressiiviseen
	# avaukseen, kun HP on jo matala ja väistö on jäähtymässä. Auki oleva
	# assassiini-ikkuna on poikkeus: silloin a1 ON paluu eikä uusi avaus.
	if want_a1 and cooldown_discipline >= 0.45 and hero.cd.dodge > 0.0 \
			and hero.hp < hero.max_hp * 0.62 \
			and hero.hero_id in ["blink", "shade", "rift"] \
			and not _assassin_window_open(hero):
		want_a1 = false

	var chosen := _select_ability_slot(hero, want_a1, want_a2, dist)
	if chosen != "":
		_request_cast(hero, chosen)
		_begin_combo(hero, chosen)


## Onko assassiinin kaksivaiheinen ikkuna auki (kaiku / varjo / merkki). Auki
## oleva ikkuna tarkoittaa että a1 on PALUU eikä uusi avaus.
func _assassin_window_open(hero: Hero) -> bool:
	match hero.hero_id:
		"blink":
			return (hero as Blink).echo_fraction() > 0.0
		"shade":
			return (hero as Shade).shadow_fraction() > 0.0
		"rift":
			return (hero as Rift).has_mark()
	return false


func _select_ability_slot(hero: Hero, want_a1: bool, want_a2: bool, dist: float) -> String:
	if not want_a1 and not want_a2:
		return ""
	if want_a1 and not want_a2:
		return "a1"
	if want_a2 and not want_a1:
		return "a2"
	# Alemmat tasot tuntevat käyttöehdot, mutta eivät aina valitse optimaalista
	# järjestystä. Ylemmät valitsevat sankarin oikean avaajan/jatkon.
	if randf() > combo_skill:
		return "a1" if randf() < 0.5 else "a2"
	match hero.hero_id:
		"blink":
			# Avatut ikkunat menevät aina uuden avauksen edelle.
			var bl := hero as Blink
			if bl.follow_fraction() > 0.0:
				return "a2"             # Jälkiterä
			if bl.echo_fraction() > 0.0:
				return "a1"             # kaikupaluu
			return "a1" if dist > 220.0 else "a2"
		"bramble":
			return "a1" if dist > 150.0 else "a2"
		"ember":
			return "a1" if dist > 210.0 else "a2"
		"volt", "scout", "salvo":
			return "a2"                 # alue/stun/morttari avaa
		"shade":
			# Varjopaluu ennen uutta shurikenia: pakotie on arvokkaampi.
			if (hero as Shade).shadow_fraction() > 0.0:
				return "a1"
			return "a2"                 # shuriken avaa, loikka viimeistelee
		"lance", "obsidian":
			return "a1" if dist > 175.0 else "a2"
		"rift":
			# Merkki kiinni -> varppaa ensin selän taakse: se asemoi ja avaa
			# tyhjyysaukon, jossa räjäytys tekee 30 % enemmän.
			if (hero as Rift).has_mark():
				return "a1"
			return "a2"                 # pinoräjäytys on aina arvokkain kun valmis
		"kaira":
			# Sulasyöksy avaa kaukaa, Maanjyrä kun kohde on jo kiinni.
			return "a1" if dist > 190.0 else "a2"
		"vesper":
			# Merkitse ensin, teloita sitten — merkitty kohde avaa Teloituksen.
			return "a1" if _target != null and _target.mark_timer <= 0.0 else "a2"
		"myria":
			# Istuta ensin, kuki sitten. Ilman kukkia a2 on vain pieni purkaus.
			return "a2" if int(hero.get("_orchids").size()) >= 2 else "a1"
		"torq":
			# Koukku raahaa kaukaa, Napalukko juurruttaa lähellä.
			return "a1" if dist > 230.0 else "a2"
		"luma", "prism", "hush":
			return "a2"                 # kiireellinen suoja/hoito ennen vahinkoa
	return "a2" if cooldown_discipline >= 0.7 else "a1"


func _begin_combo(hero: Hero, opener: String) -> void:
	if _target == null or not _target_is_hero() or randf() > combo_skill:
		return
	_combo_target = _target
	_combo_timer = 3.2
	_combo_followup = ""
	match hero.hero_id:
		"blink":
			# Välähdys -> viuhka, ja viuhka -> Jälkiterä: molemmat jatkot ovat a2.
			_combo_followup = "a2"
		"bramble":
			if opener == "a1": _combo_followup = "a2"
		"volt":
			if opener == "a2": _combo_followup = "a1"
		"shade":
			# Loikka -> shuriken, ja shuriken -> kutsu takaisin: molemmat a2.
			_combo_followup = "a2"
		"rift":
			if opener == "a1": _combo_followup = "a1"   # merkki -> varppaus
		"lance", "obsidian":
			if opener == "a1": _combo_followup = "a2"
		"kaira", "vesper", "myria", "torq":
			if opener == "a1": _combo_followup = "a2"


## Kombon kolmas isku kun jatko on juuri käytetty. Vain assassiinien
## kaksivaiheisilla kyvyillä on aitoa arvoa jatkaa: varppaus avaa tyhjyysaukon,
## jonka sisällä räjäytys on kitin kovin isku.
func _chain_after(hero: Hero, used: String) -> String:
	if hero.hero_id == "rift" and used == "a1":
		return "a2"
	return ""


func _begin_ult_combo(hero: Hero) -> void:
	if _target == null or not _target_is_hero() or randf() > combo_skill:
		return
	_combo_target = _target
	_combo_timer = 3.8
	match hero.hero_id:
		"titan":
			_combo_followup = "a1"
		"scout":
			_combo_followup = "a2"
		"shade", "blink", "rift":
			# Assassiinin ulti on avaus purskeelle: Shadelle täydet varjopisteet
			# teloitusvetoon, Blinkille viuhka + Jälkiterä, Riftille räjäytys.
			_combo_followup = "a2"
		_:
			_combo_followup = ""


func _clear_combo() -> void:
	_combo_target = null
	_combo_followup = ""
	_combo_timer = 0.0


## Onko botti hädässä. Hauraat roolit (assassin/tuki/kaukotaistelu) pakenevat
## herkemmin ja myös piiritettynä; tankit ja fighterit pitävät linjan ja
## pakenevat vain kriittisen matalalla — ne eivät hylkää etulinjaa.
func _in_danger(hero: Hero, arena) -> bool:
	if arena.mode == "moba" and (_tower_emergency(hero, arena) != null \
			or _protected_nexus_danger(hero, arena) != null):
		return true
	var archetype: String = str(HeroDef.get_def(hero.hero_id).get("archetype", ""))
	var frail: bool = not _is_tank and _role != "Fighter" and archetype != "Bruiser"
	var hp_thresh: float = 0.4 if frail else 0.25
	if hero.hp < hero.max_hp * hp_thresh:
		return true
	if frail and arena.heroes_in_circle(hero.global_position, 180.0, 1 - hero.team, true, true).size() >= 2:
		return true
	return false


## Yritä paeta vaarasta: liikkumiskyvyllä (Blink/Shade/Tide) poispäin, muuten
## väistöllä. Kääntää tähtäyksen pois, jotta syöksy/teleportti vie turvaan.
func _try_escape(hero: Hero, bb: TeamBlackboard) -> bool:
	var away := _escape_dir(hero, bb)
	if away == Vector2.ZERO:
		return false
	match hero.hero_id:
		"blink", "shade", "obsidian", "lance":
			# Blinkillä ja Shadella auki oleva ikkuna tekee tästä PALUUN
			# (kaikupaluu / varjopaluu): painallus laukaisee sen välittömästi,
			# tähtäyssuunnalla ei ole silloin väliä.
			if hero.cd.a1 <= 0.0 and hero._can_afford("a1"):
				_aim = away
				# Tähdättävä pakokyky pitää suunnan lukittuna poispäin ja käyttää
				# lyhennettyä pitoa (hätätilanteessa ei telegrafoida täyttä aikaa).
				_request_cast(hero, "a1", away, 0.6)
				return true
		"quill":
			# Quillin väistöhyppy liikkuu taaksepäin tähtäyksestä, joten tähtää
			# uhkaa kohti päästäksesi siitä poispäin.
			if hero.cd.a1 <= 0.0 and hero._can_afford("a1"):
				_aim = -away
				_request_cast(hero, "a1", -away, 0.6)
				return true
		"tide":
			if hero.cd.a1 <= 0.0 and hero.ammo > 0:
				_aim = away
				_request_cast(hero, "a1", away, 0.6)
				return true
	if hero.cd.dodge <= 0.0:
		_move = away.limit_length(1.0)
		_flags.dodge = true
		return true
	return false


func _escape_dir(hero: Hero, bb: TeamBlackboard) -> Vector2:
	var pos: Vector2 = hero.global_position
	if hero.arena != null and hero.arena.mode == "moba":
		var tower := _tower_emergency(hero, hero.arena)
		if tower == null:
			tower = _protected_nexus_danger(hero, hero.arena)
		if tower != null:
			var home: Vector2 = hero.arena.map.spawn_point(hero.team, 0)
			var d0: Vector2 = (pos - tower.global_position).normalized() * 0.45 \
				+ (home - pos).normalized()
			if d0.length() > 0.1:
				return d0.normalized()
	if bb.threat_center != Vector2.ZERO:
		var d: Vector2 = pos - bb.threat_center
		if d.length() > 1.0:
			return d.normalized()
	if _target != null and is_instance_valid(_target):
		var d2: Vector2 = pos - _target.global_position
		if d2.length() > 1.0:
			return d2.normalized()
	return Vector2.ZERO


func _want_ult(hero: Hero, arena, bb: TeamBlackboard, dist: float, near_enemies: int) -> bool:
	var pos: Vector2 = hero.global_position
	var target_cluster := 0
	if _target != null and is_instance_valid(_target):
		target_cluster = arena.heroes_in_circle(_target.global_position, 240.0,
			1 - hero.team, true, true).size()
	match hero.hero_id:
		"bastion":
			return (hero.carrying and near_enemies >= 1) or near_enemies >= 2 \
				or (bb.own_carrier != null and pos.distance_to(bb.own_carrier.global_position) < 250.0 and near_enemies >= 1)
		"ember", "bramble":
			return near_enemies >= 2
		"blink":
			# Valotanssi teleporttaa haavoittuneimpiin ja nollaa Välähdyksen
			# lopuksi: se on lopetusnappi, ei avaus tyhjään ilmaan.
			return _target_is_hero() and dist < 520.0 and hero.hp > hero.max_hp * 0.35 \
				and (_target.hp < _target.max_hp * 0.75 or target_cluster >= 2)
		"luma":
			var hurt := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team, true, true):
				if ally.hp < ally.max_hp * 0.6:
					hurt += 1
			return hurt >= 2 or (bb.own_carrier != null and bb.own_carrier.hp < bb.own_carrier.max_hp * 0.5)
		"quill":
			# Koko kartan läpäisevä nuoli ei vaadi vihollista Quillin vierelle.
			return _target_is_hero() and dist < 1500.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.65 \
				or _mode == Mode.ATTACK_CARRIER)
		"boulder":
			# Vyöry on pitkä linjaultti, ei lähialueulti.
			return _target_is_hero() and dist < 770.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.58)
		"tide":
			return _target_is_hero() and dist < 620.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.55 \
				or hero.carrying)
		"volt":
			return _target_is_hero() and dist < 560.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.5)
		"shade":
			# Varjoteurastus teleporttaa kohteen selän taakse ja teloittaa; se
			# jättää varjon, joten pakotie tulee ultin mukana.
			return _target_is_hero() and dist < 500.0 \
				and hero.hp > hero.max_hp * 0.35 \
				and (_target.hp < _target.max_hp * 0.8 or target_cluster >= 2)
		"scout":
			return arena.heroes_in_circle(pos, 640.0, 1 - hero.team, true, true).size() >= 2
		"maestro":
			var hurt_allies := 0
			for ally in arena.heroes_in_circle(pos, 300.0, hero.team, true, true):
				if ally.hp < ally.max_hp * 0.6:
					hurt_allies += 1
			return hurt_allies >= 2 or near_enemies >= 3
		"prism":
			return arena.heroes_in_circle(pos, 220.0, hero.team, true, true).size() >= 2
		"rift":
			# Ajanpysäytys iskee ja lataa kaksi pinoa kaikkiin sisään jääneisiin,
			# joten se kannattaa myös yhtä haavoittunutta kohdetta vastaan.
			return _target_is_hero() and dist < 460.0 \
				and (near_enemies >= 2 or _target.hp < _target.max_hp * 0.6)
		"titan":
			return dist < 380.0 and near_enemies >= 1
		"hush":
			# Maahan tähdättävä kontrollialue: käytä ryhmään kantaman päästä tai
			# pelasta kantaja yhdeltäkin päälle tulevalta viholliselta.
			var carrier_threat: bool = bb.own_carrier != null \
				and pos.distance_to(bb.own_carrier.global_position) < 560.0 \
				and arena.heroes_in_circle(bb.own_carrier.global_position, 280.0,
					1 - hero.team, true, true).size() >= 1
			return (_target_is_hero() and dist < 560.0 and target_cluster >= 2) \
				or carrier_threat
		"obsidian":
			# Ydinräjähdys: telegrafoitu latausräjähdys — laukaise kun kimpussa on
			# vihollisia (2+ lähellä tai 1 kiinni ja hyvä hp).
			return near_enemies >= 2 or (dist < 200.0 and near_enemies >= 1)
		"lance":
			# Taivaankeihäs: loikkaa kohteeseen kun se on kantamalla (ult-range ~520).
			return dist < 540.0 and (near_enemies >= 1 or _target_is_hero())
		"salvo":
			# Ohjus on pitkämatkainen ohjattava execute; lähivihollista ei vaadita.
			return _target_is_hero() and dist > 220.0 and dist < 1200.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.72)
		"kaira":
			# Sulakita on 820 px viiva: se osuu kauas eikä vaadi rykelmää, mutta
			# kohteen pitää olla suunnilleen tähtäyslinjalla.
			if _target is Critter and (_target as Critter).is_major_objective():
				var contested: bool = arena.heroes_in_circle(_target.global_position, 520.0,
					1 - hero.team, true, true).size() >= 1
				return contested or _target.hp < _target.max_hp * 0.7
			return _target_is_hero() and dist < 780.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.6)
		"vesper":
			# Fosforisalama on 1050 px läpäisevä lopetuslinja: se kannattaa kun
			# kohde on jo haavoittunut tai linjalla on useampi vihollinen.
			if _target is Critter and (_target as Critter).is_major_objective():
				return arena.heroes_in_circle(_target.global_position, 620.0,
					1 - hero.team, true, true).size() >= 1
			return _target_is_hero() and dist < 1020.0 \
				and (target_cluster >= 2 or _target.hp < _target.max_hp * 0.55)
		"myria":
			# Orkideapuutarha on kestoalue: sen arvo on objectivessa ja ryhmässä,
			# ei yksittäisen kohteen perässä.
			if _target is Critter and (_target as Critter).is_major_objective():
				return _target.hp < _target.max_hp * 0.7 \
					or arena.heroes_in_circle(_target.global_position, 540.0,
						1 - hero.team, true, true).size() >= 1
			return _target_is_hero() and dist < 700.0 \
				and (target_cluster >= 2 or near_enemies >= 2)
		"torq":
			# Napakenttä on puhdas kontrolliulti: se kannattaa vain kun sisään jää
			# useampi vihollinen TAI kun objective on kiistelty.
			if _target is Critter and (_target as Critter).is_major_objective():
				var foe_near: int = arena.heroes_in_circle(_target.global_position, 560.0,
					1 - hero.team, true, true).size()
				return foe_near >= 1
			return _target_is_hero() and dist < 640.0 \
				and (target_cluster >= 2 or near_enemies >= 2)
	return near_enemies >= 2


func _want_a1(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return dist < 320.0 and (hero.hp < hero.max_hp * 0.82 \
				or arena.heroes_in_circle(pos, 260.0, 1 - hero.team, true, true).size() >= 2)
		"ember":
			return dist > 100.0 and dist < 520.0
		"luma":
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.75 \
				and pos.distance_to(bb.lowest_ally.global_position) < 190.0
		"blink":
			# Kaiku pystyssä: paluu (pakotie) päättää ikkunan; muuten Välähdys on
			# avaus keskietäisyydeltä. Saapumisisku tekee siitä oikean aloituksen.
			var bl := hero as Blink
			if bl.echo_fraction() > 0.0:
				return _assassin_should_return(hero, arena, bl.echo_fraction())
			return dist > 150.0 and dist < 380.0 and _target_is_hero() \
				and _mode in [Mode.FIGHT, Mode.ATTACK_CARRIER] and _escape_ready(hero)
		"bramble":
			return dist > 145.0 and dist < 480.0
		"quill":
			return dist < 260.0 and _target_is_hero()
		"boulder":
			# Vaatii panoksen (muuri kuluttaa ammoa, 3 latausta) eikä hukkaa niitä
			# tiuhaan satunnaisheitolla.
			return dist > 200.0 and dist < 500.0 and hero.ammo > 0 and _target_is_hero() \
				and (hero.carrying or _mode == Mode.ESCORT or randf() < 0.2)
		"volt":
			return dist < 450.0
		"shade":
			# Varjo pystyssä: paluu päättää väijytyksen. Muuten loikka on avaus,
			# joka merkitsee kohteen ja avaa teloitusvedon.
			var sh := hero as Shade
			if sh.shadow_fraction() > 0.0:
				return _assassin_should_return(hero, arena, sh.shadow_fraction())
			return dist > 170.0 and dist < 400.0 and _target_is_hero() \
				and _escape_ready(hero)
		"tide":
			# Syöksy kuluttaa ammoa (3 latausta); säästä yksi pakoon (_try_escape).
			return dist > 250.0 and dist < 600.0 and hero.ammo > 1 \
				and (_target_is_hero() or arena.mode != "moba")
		"scout":
			# Merkkitikka (+45 % otettu vahinko) on sankarikohde -> ei minioniin.
			return dist > 200.0 and dist < 700.0 and _target_is_hero()
		"maestro":
			# ≥2 = itse + väh. 1 liittolainen (heroes_in_circle sisältää aina itsen,
			# joten pelkkä "ei tyhjä" oli aina tosi -> buffi laukesi turhaan).
			# _target_is_hero(): haste+kilpi-buffi on tiimibuffi oikeaa taistelua
			# varten -> ei tuhlata viidakko-olentoa (Critter) vastaan farmatessa.
			return _target_is_hero() and dist < 500.0 \
				and arena.heroes_in_circle(pos, 240.0, hero.team, true, true).size() >= 2
		"prism":
			return dist < 430.0
		"rift":
			# VoidMark lentää yksiköiden läpi -> vain oikeaa sankaria vastaan.
			var rift := hero as Rift
			if rift.has_mark():
				return true                  # toinen painallus varppaa merkille
			if rift._mark_pending:
				return false                 # odota ammuksen osumaa, älä hakkaa nappia
			# Avaus kuluttaa merkkiheiton, joten poistumistien (väistö) on oltava
			# valmiina ennen sitoutumista — Riftin pako ei tule a1:stä.
			return dist > 190.0 and dist < 700.0 and _target_is_hero() \
				and hero.cd.dodge <= 0.0
		"titan":
			# Tartunta ei tartu yksiköihin (torni/minioni) -> vain sankaria vastaan.
			return dist < 150.0 and _target_is_hero()
		"hush":
			# Suojasointu: kilpiää haavoittuneimman liittolaisen kantamalta.
			return bb.lowest_ally != null \
				and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.8 \
				and pos.distance_to(bb.lowest_ally.global_position) < 520.0
		"obsidian":
			# Louhintaloikka: hyppää keskietäisyydeltä vihollisen niskaan.
			return dist > 165.0 and dist < 420.0 \
				and (_target_is_hero() or arena.mode != "moba")
		"lance":
			# Lävistyssyöksy: syöksy vihollisen läpi keskietäisyydeltä (merkit).
			return dist > 135.0 and dist < 365.0 \
				and (_target_is_hero() or arena.mode != "moba")
		"salvo":
			# Miina heitetään 210 px päähän: kylvä se oikeasti kulkureitille.
			return dist > 105.0 and dist < 310.0
		"kaira":
			# Sulasyöksy on 440 px ryntäys: käytä kun kohde on oikeasti edessä.
			return dist > 150.0 and dist < 470.0
		"vesper":
			# Fosforipiikki merkitsee: käytä aina kun kohde on kantamalla eikä
			# merkkiä ole vielä päällä.
			return dist < 780.0 and (_target == null or _target.mark_timer <= 0.5)
		"myria":
			# Kukkaistutus: sijoita kukka kohteen päälle 620 px kantamalta.
			return dist < 620.0
		"torq":
			# Magneettikoukku: pitkä yksittäiskohteen veto, ei lähitaistelussa.
			return dist > 170.0 and dist < 620.0
	return false


## Onko nykyinen kohde oikea vihollissankari (ei minioni/torni/nexus/olento)?
func _target_is_hero() -> bool:
	return _target != null and is_instance_valid(_target) and not _target.is_unit


func _want_a2(hero: Hero, arena, bb: TeamBlackboard, dist: float, pos: Vector2) -> bool:
	match hero.hero_id:
		"bastion":
			return arena.heroes_in_circle(pos, 170.0, 1 - hero.team, true, true).size() >= 1
		"ember":
			return dist < 210.0
		"luma":
			return bb.lowest_ally != null and bb.lowest_ally.hp < bb.lowest_ally.max_hp * 0.7 \
				and (bb.lowest_ally == hero \
				or pos.distance_to(bb.lowest_ally.global_position) < 520.0)
		"blink":
			# Lopetusikkuna auki -> Jälkiterä heti; muuten viuhka avaa ikkunan.
			if (hero as Blink).follow_fraction() > 0.0:
				return true
			return dist < 400.0 and _target_is_hero()
		"bramble":
			return dist < 150.0
		"quill":
			return dist > 250.0 and dist < 500.0
		"boulder":
			return arena.heroes_in_circle(pos, 190.0, 1 - hero.team, true, true).size() >= 1
		"volt":
			return dist > 120.0 and dist < 540.0
		"shade":
			# Shuriken lennossa: kutsu se takaisin vasta kun se on OHITTANUT
			# kohteen — paluuveto on teloitus, ulosveto pelkkä naputus. Kutsun
			# ajoitus on kyvyn taito, ja päätöstahti tekee siitä rank-eron.
			var flying = (hero as Shade)._active_shuriken
			if flying != null and is_instance_valid(flying):
				if flying.returning:
					return false
				if _target == null or not is_instance_valid(_target):
					return true
				var shuri_d: float = hero.global_position.distance_to(flying.global_position)
				return shuri_d > dist + 30.0
			return dist > 120.0 and dist < 460.0 and _target_is_hero()
		"tide":
			return dist < 220.0
		"scout":
			return dist < 500.0 and _target_is_hero()
		"maestro":
			return dist < 200.0
		"prism":
			# a2 ei paranna itseä -> kohteena Prisman OMA lowest (ei-itse) ja sen
			# on oltava säteellä (430), muuten säde whiffaa.
			var low: Hero = (hero as Prism)._lowest_ally()
			return low != null and low.hp < low.max_hp * 0.7 \
				and pos.distance_to(low.global_position) < 430.0
		"rift":
			# Räjäytä vasta kun purske kannattaa: pinoja tarpeeksi, tai tyhjyysaukko
			# auki (ikkuna sulkeutuu, joten pienempikin lataus kannattaa purkaa),
			# tai kohde on jo teloitusrajoilla.
			if _target == null or not is_instance_valid(_target) or dist > 130.0:
				return false
			if (hero as Rift).void_window_fraction() > 0.0:
				return _target.void_stacks >= 2
			return _target.void_stacks >= 3 \
				or (_target.void_stacks >= 2 and _target.hp < _target.max_hp * 0.45)
		"titan":
			return hero.hp < hero.max_hp * 0.55 and hero.res > 35.0
		"hush":
			# Dissonanssikenttä (slow+DoT) heitetään lähelle vihollisia keskietäisyydeltä.
			return dist > 120.0 and dist < 430.0 and _target_is_hero()
		"obsidian":
			# Kiviho: kertakäyttöinen torjunta/heijastus kun vihollinen on lähellä.
			return dist < 220.0 and hero.res > 35.0
		"lance":
			# Pyörremyrsky: lähitaistelun AoE + vaimennus + merkit (maksaa 40 raivoa).
			return dist < 175.0 and hero.res >= 40.0
		"salvo":
			# Kaarimorttari: pitkä viive palkitsee kaukaa ennakoinnin; botti tähtää
			# nykyiseen kohteeseen oletuskantamalla kuten muut maamaalikyvyt.
			return dist > 150.0 and dist < 780.0 and _target_is_hero()
		"kaira":
			# Maanjyrä maksaa 35 raivoa ja osuu 218 px säteellä.
			return dist < 205.0 and hero.res >= 35.0
		"vesper":
			# Teloitus kannattaa vasta kun kohteelta puuttuu elämää tai se on
			# merkitty — täydessä elämässä olevaan se on hukkaan heitetty.
			if _target == null or not is_instance_valid(_target):
				return false
			return dist < 720.0 and (_target.mark_timer > 0.0 \
				or _target.hp < _target.max_hp * 0.6)
		"myria":
			# Kukinta: puhkaise vasta kun maassa on vähintään kaksi orkideaa.
			return hero.res >= 26.0 and int(hero.get("_orchids").size()) >= 2
		"torq":
			# Napalukko imee ja juurruttaa 232 px säteellä — se on aloitus.
			return dist < 225.0 and hero.res >= 30.0
	return false


func _update_dodge(hero: Hero, arena, delta: float) -> void:
	_dodge_check_timer -= delta
	if _dodge_check_timer > 0.0 or hero.cd.dodge > 0.0:
		return
	_dodge_check_timer = 0.1
	# Tornilaukausta ei voi väistää, mutta dash lyhentää aikaa vaaravyöhykkeellä
	# ja katkaisee ramppauksen. Käytä sitä heti kun lukitus on pitkällä.
	if arena.mode == "moba":
		var tower := _tower_emergency(hero, arena)
		if tower != null and tower._target_lock == hero and tower._charge >= 0.5 \
				and randf() < 0.45 + tower_judgement * 0.5:
			var home: Vector2 = arena.map.spawn_point(hero.team, 0)
			_move = (home - hero.global_position).normalized()
			_flags.dodge = true
			return
	# Väistöennakko: korkea rank huomaa ammuksen kauempaa ja astuu sivuun
	# ennakoivan näköisesti; matala reagoi vasta aivan lähellä (ja Woodin
	# dodge_chance 0 tarkoittaa ettei se väistä koskaan).
	var detect_radius: float = lerpf(150.0, 330.0, prediction)
	# Vain rekisteröidyt ammukset (arena.projectiles) — ei koko areenan
	# lapsilistan (sankarit, minionit, efektit, popupit) läpikäyntiä 10 Hz
	# per botti. Lista siivotaan areenan fysiikkavaiheessa.
	for child in arena.projectiles:
		if not is_instance_valid(child):
			continue
		if child.team == hero.team:
			continue
		var to_hero: Vector2 = hero.global_position - child.global_position
		if to_hero.length() > detect_radius:
			continue
		if child.direction.dot(to_hero.normalized()) < 0.6:
			continue
		if randf() < dodge_chance:
			_flags.dodge = true
			_move = child.direction.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
		return


# --- DeviceInput-rajapinta ---

func move_vector() -> Vector2:
	return _move


func aim_vector() -> Vector2:
	return _aim


## Maatähtäyksen kursoriliike: botti ei liikuta ristikkoa tatilla — Hero
## asettaa maamaalin suoraan ennakoituun kohteeseen (_update_ground_aim).
func aim_cursor_vector() -> Vector2:
	return Vector2.ZERO


func attack_held() -> bool:
	return _attack


func attack_just_pressed() -> bool:
	return _attack and not _attack_prev


func attack_just_released() -> bool:
	return (not _attack) and _attack_prev


func ability1_just() -> bool:
	return _flags.a1


func ability2_just() -> bool:
	return _flags.a2


# Tähdättävät kyvyt: botti "pitää nappia pohjassa" pitoajastimen ajan, jolloin
# Hero piirtää tähtäysviivan (näkyvä telegraafi), ja vapautus laukaisee castin.
# Ultit botti laukaisee yhä välittömästi (ult_held/released jäävät falseksi).
func ability1_held() -> bool:
	return float(_aim_hold.a1) > 0.0


func ability2_held() -> bool:
	return float(_aim_hold.a2) > 0.0


func ability1_released() -> bool:
	return bool(_aim_release.a1)


func ability2_released() -> bool:
	return bool(_aim_release.a2)


func ult_held() -> bool:
	return false


func ult_released() -> bool:
	return false


func dodge_just() -> bool:
	return _flags.dodge


func ult_just() -> bool:
	return _flags.ult


func drop_just() -> bool:
	return false


## Itemiaktiivi: yksi laukaisu per päätöstikki (_maybe_use_item_active asettaa).
func item_active_just() -> bool:
	return _use_active


## Paluukanavointi: botti "pitää nappia pohjassa" niin kauan kuin päätös elää.
func recall_held() -> bool:
	return _recall


## Kykypisteiden kehitystila on vain ihmisille; botti käyttää pisteet suoraan
## Hero._bot_spend_points-polun kautta.
func spend_held() -> bool:
	return false


# --- Itemien ostolista (Hero._bot_shop kutsuu tukikohdassa/kuolleena) ---

## Botin roolibuildin ostoprioriteetti: rooliavain työnjaosta (_moba_job/duty)
## tai sankarin roolista jos työnjakoa ei ole vielä tehty.
func _item_role() -> String:
	var role := _role
	if role == "" and _hero != null:
		role = str(HeroDef.get_def(_hero.hero_id).get("role", ""))
	if _moba_job == "jungle" or role == HeroDef.ROLE_JUNGLER:
		return "jungle"
	if _moba_duty == "support" or role == "Tuki":
		return "support"
	if role == "Tankki":
		return "tank"
	if role == "Mage":
		return "ap"
	return "carry"


## Roolin tavoite-epicit järjestyksessä. Hero ostaa keskeneräisen tavoitteen
## osat ItemDef.next_purchase-apurilla halvimmasta ostettavasta päästä
## (commonit -> raret -> epic).
func _item_build() -> Array:
	match _item_role():
		"jungle":
			return ["riistanraatelija", "ansalanka", "varjoviitta"]
		"support":
			return ["kolikkotalismaani", "vartiolyhty", "hoivasydän"]
		"tank":
			return ["jäätikkövyö", "torjuntakupu", "elonlähde"]
		"ap":
			return ["arkkisauva", "kaikukide", "manaydin"]
	return ["myrskynsilma", "verikuu", "teräsarmä"]


## Roolin legenda: ostetaan heti kun Baron-artefakti on hallussa ja varaa on.
func _item_legendary() -> String:
	match _item_role():
		"jungle":
			return "alfaturkki"
		"support":
			return "aamunkoitto"
		"tank":
			return "maailmanpuu"
		"ap":
			return "tyhjyydenydin"
	return "kuninkaansurma"


func is_bot() -> bool:
	return true
