class_name JungleHero
extends Hero
## Tulevien jungler-sankarien yhteinen pohja. Tästä ei vielä synny valittavaa
## sankaria: neljä varsinaista jungleria suunnitellaan erikseen myöhemmin.
## Pohja määrittää vain roolin ydinsopimuksen, jotta jokainen jungleri ei rakenna
## camp-vahinkoa, monsterikestoa ja leiripalautusta omalla eri tavallaan.

const ROLE := HeroDef.ROLE_JUNGLER

var jungle_damage_bonus := 1.16
var jungle_clear_mult := 1.0
var jungle_damage_taken := 0.84
var camp_sustain_fraction := 0.045
var major_sustain_fraction := 0.085


func deal_damage_to(target: Hero, amount: float, kb := 0.0,
		kb_dir := Vector2.ZERO) -> float:
	if target is Critter:
		amount *= jungle_damage_bonus * jungle_clear_mult
	return super.deal_damage_to(target, amount, kb, kb_dir)


func take_damage(amount: float, source: Hero, kb := 0.0,
		kb_dir := Vector2.ZERO) -> float:
	if source is Critter:
		amount *= jungle_damage_taken
	return super.take_damage(amount, source, kb, kb_dir)


func on_jungle_camp_defeated(camp: Critter) -> void:
	if camp == null or not alive:
		return
	var fraction := major_sustain_fraction if camp.is_major_objective() \
		else camp_sustain_fraction
	heal_hp(max_hp * fraction, self)


## Only durable melee junglers may attempt Dragon alone. Baron always requires
## a group; ranged safety must not become a minute-long risk-free objective.
func bot_can_solo_major(camp: Critter) -> bool:
	return camp != null and camp.kind == Critter.Kind.DRAGON and max_hp >= 260.0


## Botin maamaali ankkuroidaan sen oikeaan leirikohteeseen. Hero-kantaluokan
## yleinen maamaali etsii vain vihollispelaajia, koska tavalliset sankarit eivät
## yleensä sijoita objective-kykyjä neutraalin monsterin alle.
func jungle_ground_target(dir: Vector2, max_range: float, default_range: float) -> Vector2:
	if controller != null and controller.is_bot():
		var bot_target = controller.get("_target")
		if bot_target is Hero and is_instance_valid(bot_target) and bot_target.alive:
			var off: Vector2 = bot_target.global_position - global_position
			if off.length() <= max_range:
				return bot_target.global_position
	return aimed_ground_position(dir, max_range, default_range)
