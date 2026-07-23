class_name DeviceInput
extends RefCounted
## Yhden pelaajan syöttölaite. device = -1 tarkoittaa näppäimistöä ja hiirtä,
## device >= 0 on peliohjaimen laitenumero (PS5 DualSense toimii suoraan).
##
## BotBrain toteuttaa täsmälleen saman rajapinnan (duck typing), joten Hero
## ei tiedä ohjaako sitä ihminen vai botti.
##
## PS5-ohjain:  vasen tatti = liike, oikea tatti = tähtäys, R2 = perushyökkäys,
## R1 = kyky 1, L1 = kyky 2, Risti = väistö, L2 = ultimate, Ympyrä = pudota,
## D-pad alas = paluu baseen (pidä pohjassa; näppäimistöllä B),
## D-pad ylös = kykypisteiden kehitystila (pidä pohjassa + kyvyn nappi;
## näppäimistöllä T), D-pad vasen = itemiaktiivi (näppäimistöllä G).
## Ulti on L2-liipaisimessa: helpompi pitää pohjassa ja tähdätä oikealla tatilla
## kuin kolmiolla. Kolmio toimii yhä vaihtoehtoisena ultinappina.

const DEADZONE := 0.22
# Liipaisimien hystereesi: painallus rekisteröityy 0.45:ssä mutta irtoaa vasta
# 0.28:ssa. Ilman tätä liipaisimen värähtely kynnyksen ympärillä laukaisi
# pito-ja-vapauta-ultin (L2) vahingossa kesken tähtäyksen.
const TRIGGER_PRESS := 0.45
const TRIGGER_RELEASE := 0.28
# Vastekäyrät (expo): tatin keskialue on tarkempi, reuna yhä täysi nopeus.
# Tähtäyksellä jyrkempi käyrä -> hienosäätö (maamaalit, skillshotit) ei nyki.
const MOVE_EXPO := 1.15
const AIM_EXPO := 1.45

const PAD_BUTTONS := {
	"a1": JOY_BUTTON_RIGHT_SHOULDER,
	"a2": JOY_BUTTON_LEFT_SHOULDER,
	"dodge": JOY_BUTTON_A,
	"drop": JOY_BUTTON_B,
	"recall": JOY_BUTTON_DPAD_DOWN,
	"spend": JOY_BUTTON_DPAD_UP,
	"item_active": JOY_BUTTON_DPAD_LEFT,
}

var device := -1

var _move := Vector2.ZERO
var _aim := Vector2.RIGHT
var _aim_cursor := Vector2.ZERO       # oikean tatin hetkellinen, deadzone-korjattu liike
var _attack := false
var _attack_prev := false
var _pressed := {}
var _prev := {}


func _init(dev: int) -> void:
	device = dev


## Kutsutaan kerran per fysiikkaframe ennen lukuja (hoitaa reunatunnistuksen).
func update(hero, _delta: float) -> void:
	_prev = _pressed.duplicate()
	_attack_prev = _attack
	if device < 0:
		_update_keyboard_mouse(hero)
	else:
		_update_gamepad()


func _update_keyboard_mouse(hero) -> void:
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		mv.x += 1.0
	_move = mv.normalized() if mv.length() > 1.0 else mv

	if hero != null and is_instance_valid(hero):
		var to_mouse: Vector2 = hero.get_global_mouse_position() - hero.global_position
		if to_mouse.length() > 6.0:
			_aim = to_mouse.normalized()
	_aim_cursor = Vector2.ZERO

	_attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_pressed = {
		"a1": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
		"a2": Input.is_physical_key_pressed(KEY_Q),
		"dodge": Input.is_physical_key_pressed(KEY_SPACE),
		"ult": Input.is_physical_key_pressed(KEY_E),
		"drop": Input.is_physical_key_pressed(KEY_F),
		"recall": Input.is_physical_key_pressed(KEY_B),
		"spend": Input.is_physical_key_pressed(KEY_T),
		"item_active": Input.is_physical_key_pressed(KEY_G),
	}


func _update_gamepad() -> void:
	_move = _read_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, MOVE_EXPO)
	var aim_stick := _read_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, AIM_EXPO)
	_aim_cursor = aim_stick
	# Suunta rekisteröityy jo kevyestä poikkeutuksesta (0.1 deadzonen jälkeen):
	# nopeat flickit kääntävät tähtäyksen heti; voimakkuus ohjaa vain kursoria.
	if aim_stick.length() > 0.1:
		_aim = aim_stick.normalized()
	_attack = _trigger_held(JOY_AXIS_TRIGGER_RIGHT, _attack)
	_pressed = {}
	for key in PAD_BUTTONS:
		_pressed[key] = Input.is_joy_button_pressed(device, PAD_BUTTONS[key])
	# Ultimate = L2-liipaisin (helpompi tähdätä), kolmio vaihtoehtona.
	_pressed["ult"] = _trigger_held(JOY_AXIS_TRIGGER_LEFT, bool(_prev.get("ult", false))) \
		or Input.is_joy_button_pressed(device, JOY_BUTTON_Y)


## Liipaisimen luku hystereesillä: kynnys riippuu siitä oliko jo pohjassa.
func _trigger_held(axis: int, was_held: bool) -> bool:
	var value := Input.get_joy_axis(device, axis)
	return value > (TRIGGER_RELEASE if was_held else TRIGGER_PRESS)


func _read_stick(axis_x: int, axis_y: int, expo := 1.0) -> Vector2:
	var v := Vector2(
		Input.get_joy_axis(device, axis_x),
		Input.get_joy_axis(device, axis_y)
	)
	var magnitude := v.length()
	if magnitude < DEADZONE:
		return Vector2.ZERO
	# Pehmeä radiaalinen deadzone: liike alkaa nollasta deadzonen reunalta.
	# Expo-käyrä tekee keskialueesta tarkan ilman että reunan huippunopeus kärsii.
	var scaled: float = clampf((magnitude - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	return v / magnitude * pow(scaled, expo)


# --- Luettava rajapinta (sama kuin BotBrainilla) ---

func move_vector() -> Vector2:
	return _move


func aim_vector() -> Vector2:
	return _aim


## Maamaalitähtäyksen kursori. Toisin kuin aim_vector, tämä palauttaa oikean
## tatin nykyisen voimakkuuden eikä muista viimeistä suuntaa. Näin tatilla voi
## siirtää kohdistuspistettä tarkasti lähelle tai kauas kykyä pidettäessä.
func aim_cursor_vector() -> Vector2:
	return _aim_cursor


func uses_pointer_aim() -> bool:
	return device < 0


func attack_held() -> bool:
	return _attack


func attack_just_pressed() -> bool:
	return _attack and not _attack_prev


func attack_just_released() -> bool:
	return (not _attack) and _attack_prev


func _just(name: String) -> bool:
	return bool(_pressed.get(name, false)) and not bool(_prev.get(name, false))


func ability1_just() -> bool:
	return _just("a1")


func ability2_just() -> bool:
	return _just("a2")


func ability1_held() -> bool:
	return bool(_pressed.get("a1", false))


func ability2_held() -> bool:
	return bool(_pressed.get("a2", false))


func ability1_released() -> bool:
	return bool(_prev.get("a1", false)) and not bool(_pressed.get("a1", false))


func ability2_released() -> bool:
	return bool(_prev.get("a2", false)) and not bool(_pressed.get("a2", false))


func ult_held() -> bool:
	return bool(_pressed.get("ult", false))


func ult_released() -> bool:
	return bool(_prev.get("ult", false)) and not bool(_pressed.get("ult", false))


func dodge_just() -> bool:
	return _just("dodge")


func ult_just() -> bool:
	return _just("ult")


func drop_just() -> bool:
	return _just("drop")


## Itemiaktiivi (D-pad vasen / G): laukaisee ensimmäisen omistetun aktiivin
## (vartija/varjo) jonka sisäinen jäähdytys on valmis.
func item_active_just() -> bool:
	return _just("item_active")


## Paluukanavointi (B / D-pad alas): pidetään pohjassa koko kanavoinnin ajan.
func recall_held() -> bool:
	return bool(_pressed.get("recall", false))


## Kykypisteiden kehitystila (D-pad ylös / T): pidä pohjassa ja paina kyvyn
## nappia — painallus käyttää kykypisteen castin sijaan.
func spend_held() -> bool:
	return bool(_pressed.get("spend", false))


func is_bot() -> bool:
	return false
