class_name PopupText
extends Node2D
## Leijuva teksti (vahinkoluvut, parannukset, ilmoitukset).

var text := ""
var color := Color.WHITE
var size := 20

var _t := 0.0
var _duration := 0.9
var _rise := 46.0
var _start := Vector2.ZERO


static func spawn(parent: Node, pos: Vector2, p_text: String, p_color: Color,
		p_size := 20) -> void:
	var node := PopupText.new()
	node.position = pos + Vector2(randf_range(-8.0, 8.0), 0)
	node.text = p_text
	node.color = p_color
	node.size = p_size
	parent.add_child(node)


func _ready() -> void:
	z_index = 40
	_start = position


func _process(delta: float) -> void:
	_t += delta
	if _t >= _duration:
		queue_free()
		return
	var f: float = _t / _duration
	var eased := 1.0 - pow(1.0 - f, 2.5)
	position = _start + Vector2(0, -_rise * eased)
	queue_redraw()


func _draw() -> void:
	var f: float = clampf(_t / _duration, 0.0, 1.0)
	var a: float = 1.0 if f < 0.6 else 1.0 - (f - 0.6) / 0.4
	var pop: float = 1.0 + maxf(0.0, 0.25 - _t) * 2.0
	UiKit.draw_text(self, Vector2.ZERO, text, int(size * pop),
		Palette.with_alpha(color, a), true, 4,
		Color(0.05, 0.07, 0.16, 0.85 * a))
