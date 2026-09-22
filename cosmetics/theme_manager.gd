extends Node
## Session-only development previews. This never grants a league or writes PL.
signal theme_changed(theme_id: String, piece_set_id: String)
const Catalog = preload("res://cosmetics/theme_catalog.gd")
var stage
var game
var hub
var active_theme := "wood"
var active_piece_set := "classic"
var classic_pieces := {}
var iron_arena: Sprite2D

func setup(presentation: Node):
    stage = presentation
    game = stage.game
    hub = stage.hub
    classic_pieces = game.piece_textures.duplicate()
    iron_arena = Sprite2D.new()
    iron_arena.name = "IronArena"
    iron_arena.z_index = -15
    iron_arena.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    iron_arena.hide()
    stage.add_child(iron_arena)
    apply_theme("wood")

func apply_theme(theme_id: String) -> bool:
    if not Catalog.THEME_DATA.has(theme_id): return false
    var data = Catalog.get_theme(theme_id)
    var home_texture = Catalog.texture(data.home_path)
    var arena_texture = Catalog.texture(data.arena_path)
    # A partial asset import must never replace the working scene with a blank.
    if theme_id != "wood" and (home_texture == null or arena_texture == null): return false
    active_theme = theme_id
    if hub.has_method("apply_theme") and home_texture != null:
        hub.apply_theme(home_texture)
    game.set_visual_theme(theme_id)
    stage.forest.visible = theme_id == "wood"
    iron_arena.texture = arena_texture if theme_id != "wood" else null
    iron_arena.visible = theme_id != "wood"
    apply_piece_set(theme_id)
    stage._layout()
    theme_changed.emit(active_theme,active_piece_set)
    return true

func apply_piece_set(piece_set_id: String) -> bool:
    if piece_set_id != "classic" and not Catalog.THEME_DATA.has(piece_set_id): return false
    var textures = classic_pieces if piece_set_id == "classic" else Catalog.piece_textures(piece_set_id)
    if textures.size() != 12:
        if piece_set_id == active_theme:
            textures = classic_pieces
            piece_set_id = "classic"
        else: return false
    game.piece_textures = textures.duplicate()
    active_piece_set = piece_set_id
    game.queue_redraw()
    theme_changed.emit(active_theme,active_piece_set)
    return true

func layout():
    if not is_instance_valid(iron_arena) or iron_arena.texture == null: return
    var size: Vector2 = stage.get_viewport_rect().size
    var art_size = iron_arena.texture.get_size()
    # Match the painted stone rim to the existing 600-unit playable grid.
    var centers = {"iron":Vector2(836,491),"bronze":Vector2(836,477),"silver":Vector2(837,463),"gold":Vector2(836,500)}
    var spans = {"iron":548.0,"bronze":440.0,"silver":461.0,"gold":458.0}
    var center: Vector2 = centers.get(active_theme,art_size/2.0)
    var cover = maxf(maxf(size.x/2.0/center.x,size.x/2.0/(art_size.x-center.x)),maxf(size.y/2.0/center.y,size.y/2.0/(art_size.y-center.y)))
    var factor = maxf(game.scale.x * game.BOARD / spans.get(active_theme,548.0),cover)
    if active_theme == "bronze":
        # Cover the old perspective rim with the square playable surface. Both
        # axes share one factor; the surrounding illustration stays proportional.
        factor = cover
        game.scale = Vector2.ONE * (620.0*factor/game.BOARD)
        game.position = size/2.0-(game.ORIGIN+Vector2.ONE*game.BOARD/2.0)*game.scale.x
        game.update_presentation(Rect2(-game.position/game.scale.x,size/game.scale.x))
    iron_arena.scale = Vector2.ONE*factor
    iron_arena.position = size/2.0 + (art_size/2.0-center)*factor
