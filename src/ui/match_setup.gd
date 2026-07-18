class_name MatchSetup
extends Control
## Ottelun asetukset: joukkuekoko, ottelun pituus, bottien taso.
## Rivit toimivat sekä hiirellä (klikkaus = seuraava arvo) että
## ohjaimella/näppäimistöllä (vasen/oikea säätää).

var _desc_label: Label = null

const MAP_IDS := ["geargarden", "moonstone", "splashport", "sparkring", "dustcanyon"]
const MAP_NAMES := ["Geargarden", "Moonstone Ruins", "Splashport", "Sparkring", "Dust Canyon"]
const MAP_DESC := {
	"geargarden": "Geargarden: tasapainoinen perusareena — symmetrinen, keskusrattaat suojana, pensasaidat ja kuljetinhihnat.",
	"moonstone": "Moonstone Ruins: portit aukeavat vuorotellen sivuilla — ajoita oikoreittisi. Avoin keskusta, hohtavat kristallit.",
	"splashport": "Splashport: keskilaituri ja kaksi vesikaistaa. Vesi hidastaa, lautat kuljettavat ja hyppyalustat sinkoavat laiturille.",
	"sparkring": "Sparkring: tiivis neon-areena. Kimmoketolpat singahduttavat pois — pinball-kaaosta, ihanteellinen 1v1/2v2.",
	"dustcanyon": "Dust Canyon: suuri avoin autiomaa. Pitkät näkölinjat kaukotaistelulle; hiekkamyrsky pyyhkii poikki, hidastaa ja työntää.",
}

const DESCRIPTIONS := {
	"size": "Montako pelaajaa kummassakin joukkueessa. Tyhjät paikat täytetään boteilla.",
	"rounds": "Paras kolmesta = kaksi erävoittoa, paras viidestä = kolme.",
	"bots": "Taso vaikuttaa bottien reaktioihin ja tarkkuuteen — ei niiden voimaan.",
	"mode": "Relic Hold: pidä reliikkiä hallussa — 40 pistettä voittaa erän.",
	"map": "Geargarden: mekaaninen puutarha, jossa on kuljetinhihnoja ja rattaita.",
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())

	var center := UiKit.fullscreen_center(self)
	var box := UiKit.vbox(14)
	center.add_child(box)

	box.add_child(UiKit.title("OTTELUN ASETUKSET", 64))
	box.add_child(UiKit.spacer(20))

	var size_row := OptionRow.new("Joukkuekoko", ["1v1", "2v2", "3v3", "4v4"],
		Game.team_size - 1,
		func(i): Game.team_size = i + 1)
	size_row.desc_key = "size"
	_add_row(box, size_row)

	var rounds_row := OptionRow.new("Ottelun pituus", ["Paras 3:sta", "Paras 5:stä"],
		0 if Game.rounds_to_win <= 2 else 1,
		func(i): Game.rounds_to_win = 2 + i)
	rounds_row.desc_key = "rounds"
	_add_row(box, rounds_row)

	var bots_row := OptionRow.new("Bottien taso", Game.BOT_LEVEL_NAMES,
		Game.bot_level,
		func(i): Game.bot_level = i)
	bots_row.desc_key = "bots"
	_add_row(box, bots_row)

	var mode_row := OptionRow.new("Pelimuoto", ["Relic Hold  (lisää tulossa)"], 0, Callable())
	mode_row.locked = true
	mode_row.desc_key = "mode"
	_add_row(box, mode_row)

	var map_start: int = maxi(MAP_IDS.find(Game.map_id), 0)
	var map_row := OptionRow.new("Kenttä", MAP_NAMES, map_start,
		func(i):
			Game.map_id = MAP_IDS[i]
			if _desc_label != null:
				_desc_label.text = MAP_DESC[Game.map_id])
	# desc_key jätetään tyhjäksi -> _add_row ei liitä yleiskäsittelijää;
	# kenttärivi näyttää valitun kartan oman kuvauksen.
	map_row.focus_entered.connect(func():
		if _desc_label != null:
			_desc_label.text = MAP_DESC[Game.map_id])
	_add_row(box, map_row)

	box.add_child(UiKit.spacer(6))
	_desc_label = UiKit.dim_label(DESCRIPTIONS["size"], 20)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.custom_minimum_size = Vector2(760, 56)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc_label)
	box.add_child(UiKit.spacer(6))

	var continue_btn := UiKit.button("Jatka pelaajien valintaan", func(): Game.go_lobby())
	continue_btn.custom_minimum_size = Vector2(520, 0)
	box.add_child(continue_btn)
	var back_btn := UiKit.button("Takaisin", func(): Game.go_menu(), 24)
	back_btn.custom_minimum_size = Vector2(520, 0)
	box.add_child(back_btn)

	size_row.call_deferred("grab_focus")


func _add_row(parent: Control, row: OptionRow) -> void:
	row.custom_minimum_size = Vector2(760, 0)
	parent.add_child(row)
	if row.desc_key != "":
		row.focus_entered.connect(func():
			if _desc_label != null:
				_desc_label.text = DESCRIPTIONS.get(row.desc_key, ""))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		AudioMgr.play("ui_back")
		Game.go_menu()


## Asetusrivi: fokusattava nappi, jonka arvoa vaihdetaan vasen/oikea-
## painalluksilla tai klikkaamalla.
class OptionRow:
	extends Button

	var row_label := ""
	var values: Array = []
	var idx := 0
	var on_change := Callable()
	var locked := false
	var desc_key := ""

	func _init(p_label: String, p_values: Array, p_idx: int, p_on_change: Callable) -> void:
		row_label = p_label
		values = p_values
		idx = clampi(p_idx, 0, values.size() - 1)
		on_change = p_on_change
		add_theme_font_size_override("font_size", 28)
		add_theme_color_override("font_color", Palette.TEXT_MAIN)
		add_theme_color_override("font_hover_color", Color.WHITE)
		add_theme_color_override("font_focus_color", Color.WHITE)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Palette.UI_PANEL
		normal.set_corner_radius_all(14)
		normal.content_margin_left = 30.0
		normal.content_margin_right = 30.0
		normal.content_margin_top = 12.0
		normal.content_margin_bottom = 12.0
		add_theme_stylebox_override("normal", normal)
		var focus: StyleBoxFlat = normal.duplicate()
		focus.bg_color = Palette.UI_PANEL_LIGHT
		focus.border_color = Color(1, 1, 1, 0.85)
		focus.set_border_width_all(3)
		add_theme_stylebox_override("focus", focus)
		add_theme_stylebox_override("hover", focus)
		add_theme_stylebox_override("pressed", normal)
		if locked:
			modulate = Color(1, 1, 1, 0.55)
		_sync_text()
		pressed.connect(func(): _cycle(1))

	func _ready() -> void:
		if locked:
			modulate = Color(1, 1, 1, 0.55)
			focus_mode = Control.FOCUS_NONE
			disabled = true
		_sync_text()

	func _gui_input(event: InputEvent) -> void:
		if locked:
			return
		if event.is_action_pressed("ui_left"):
			_cycle(-1)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			_cycle(1)
			accept_event()

	func _cycle(dir: int) -> void:
		if locked or values.size() <= 1:
			return
		idx = (idx + dir + values.size()) % values.size()
		_sync_text()
		AudioMgr.play("ui_move")
		if on_change.is_valid():
			on_change.call(idx)

	func _sync_text() -> void:
		var value := str(values[idx])
		if locked:
			text = "%s      %s" % [row_label, value]
		else:
			text = "%s      ‹ %s ›" % [row_label, value]
