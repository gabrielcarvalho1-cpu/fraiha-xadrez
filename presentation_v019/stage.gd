extends Node2D
# Only this presentation root handles the screen dimensions. Game coordinates stay intact.
@onready var game: Node2D = $World
@onready var forest: Sprite2D = $ForestExtensions
var windowed_size := Vector2i(1280, 720)
var windowed_position := Vector2i.ZERO
var windowed_mode := Window.MODE_WINDOWED

func _ready():
    get_viewport().size_changed.connect(_layout)
    _layout()

func _layout():
    var size = get_viewport_rect().size
    var factor = min(size.y / 1024.0, size.x / 1024.0)
    game.scale = Vector2.ONE * factor
    var board_center = game.ORIGIN + Vector2.ONE * game.BOARD / 2.0
    game.position = size / 2.0 - board_center * factor
    # The outpaint has its own board center; align its terrain while covering every edge.
    var texture_size = forest.texture.get_size()
    var art_center = texture_size * Vector2(802.0/1672.0, 445.5/941.0)
    var cover = max(max(size.x/2.0/art_center.x, size.x/2.0/(texture_size.x-art_center.x)), max(size.y/2.0/art_center.y, size.y/2.0/(texture_size.y-art_center.y)))
    forest.scale = Vector2.ONE * cover
    forest.position = size/2.0 + (texture_size/2.0-art_center)*cover
    game.update_presentation(Rect2(-game.position / factor, size / factor))

func toggle_fullscreen():
    var window = get_window()
    if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
        window.mode = Window.MODE_WINDOWED
        window.size = windowed_size
        window.position = windowed_position
        if windowed_mode == Window.MODE_MAXIMIZED:
            window.mode = Window.MODE_MAXIMIZED
    else:
        windowed_size = window.size
        windowed_position = window.position
        windowed_mode = window.mode
        window.mode = Window.MODE_FULLSCREEN
    game.queue_redraw()
