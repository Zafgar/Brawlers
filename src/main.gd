extends Node
## Pelin juurisolmu. Kaikki ruudut (valikot, areena, tulokset) elävät tämän lapsina.
## Varsinainen tilanhallinta on Game-autoloadissa.


func _ready() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Game.boot(self)
