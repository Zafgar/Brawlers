class_name Palette
## Pelin väripaletti. Kaikki värit yhdestä paikasta, jotta ulkoasu pysyy yhtenäisenä.
## HDR-hehkua varten (hdr_2d päällä) käytä glow()-apuria, joka nostaa värin yli 1.0:n.

const TEAM_BLUE := Color("4aa8ff")
const TEAM_ORANGE := Color("ffa03c")
const TEAM_NEUTRAL := Color("8f9aa8")   # viidakko-olennot (joukkue 2)

const BG_DARK := Color("101830")
const BG_MID := Color("18243f")
const BG_LIGHT := Color("223354")

const UI_PANEL := Color(0.07, 0.1, 0.19, 0.94)
const UI_PANEL_LIGHT := Color(0.13, 0.18, 0.3, 0.96)
const UI_STROKE := Color(0.45, 0.56, 0.8, 0.5)

const TEXT_MAIN := Color("f2f5ff")
const TEXT_DIM := Color("9aa7c9")
const TEXT_DARK := Color("2a3450")

const GOOD := Color("6dffa8")
const BAD := Color("ff6d7a")
const GOLD := Color("ffd76d")
const SHIELD := Color("8ad8ff")
const HEAL := Color("8dffb0")

# Kahdeksan selkeästi erottuvaa pelaajaväriä (tunnusrenkaat, kortit, kursorit).
const PLAYER_COLORS := [
	Color("4ac8ff"), # 1 sininen
	Color("ff5d6e"), # 2 punainen
	Color("6dff8a"), # 3 vihreä
	Color("ffd44a"), # 4 keltainen
	Color("c98aff"), # 5 violetti
	Color("ff9d3c"), # 6 oranssi
	Color("6dfff2"), # 7 turkoosi
	Color("ff7ad9"), # 8 pinkki
]


static func team(team_index: int) -> Color:
	if team_index == 0:
		return TEAM_BLUE
	if team_index == 1:
		return TEAM_ORANGE
	return TEAM_NEUTRAL


static func player(index: int) -> Color:
	return PLAYER_COLORS[index % PLAYER_COLORS.size()]


## Nostaa värin energiaa yli 1.0:n, jolloin 2D-glow tarttuu siihen.
static func glow(c: Color, energy := 1.7) -> Color:
	return Color(c.r * energy, c.g * energy, c.b * energy, c.a)


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func darker(c: Color, f := 0.55) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)
