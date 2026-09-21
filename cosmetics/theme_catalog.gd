extends RefCounted
## Cosmetic metadata only. No progression, positions, legal moves or networking.
const PIECE_ORDER = ["P", "R", "N", "B", "Q", "K"]
const BADGE_ORDER = ["madeira", "ferro", "bronze", "prata", "ouro", "platina", "esmeralda", "diamante", "mestre", "grande_mestre", "challenger"]
static var piece_cache := {}
const THEME_DATA = {
    "wood": {"id":"wood", "name":"Madeira", "home_path":"res://ui_v022/assets/home_forest.png", "arena_path":"res://presentation_v019/forest_wide.png", "pieces_path":"res://cosmetics/assets/wood_pieces.png", "unlock_league":"wood"},
    "iron": {"id":"iron", "name":"Ferro", "home_path":"res://cosmetics/assets/iron_home.png", "arena_path":"res://cosmetics/assets/iron_arena.png", "pieces_path":"res://cosmetics/assets/iron_pieces.png", "unlock_league":"iron"}
}

static func themes() -> Array:
    return [get_theme("wood"), get_theme("iron")]

static func get_theme(id: String) -> Dictionary:
    return THEME_DATA.get(id, THEME_DATA.wood).duplicate(true)

static func texture(path: String) -> Texture2D:
    return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func piece_textures(id: String) -> Dictionary:
    if piece_cache.has(id): return piece_cache[id]
    var result := {}
    if id == "classic":
        for color in ["w","b"]:
            for kind in PIECE_ORDER:
                result[color+kind] = texture("res://visual_v018/pieces/"+color+kind+".tres")
        return result
    if not THEME_DATA.has(id): return result
    var atlas = texture(THEME_DATA[id].pieces_path)
    if atlas == null: return result
    var cell = atlas.get_size() / Vector2(6,2)
    var pixels = atlas.get_image()
    if pixels.is_compressed(): pixels.decompress()
    for row in range(2):
        for column in range(6):
            var sprite := AtlasTexture.new()
            sprite.atlas = atlas
            var bounds = Rect2i(Vector2i(Vector2(column,row)*cell),Vector2i(cell))
            # Upper-row bases slightly cross the nominal atlas midpoint. The
            # lower king starts higher; its cell is already clean and stays full.
            if row == 1 and column < 5:
                bounds.position.y += 24
                bounds.size.y -= 24
            # Ignore almost-transparent generation dust when sizing a figurine.
            var left = bounds.size.x
            var top = bounds.size.y
            var right = -1
            var bottom = -1
            for y in range(bounds.size.y):
                for x in range(bounds.size.x):
                    if pixels.get_pixel(bounds.position.x+x,bounds.position.y+y).a > 0.25:
                        left = mini(left,x)
                        top = mini(top,y)
                        right = maxi(right,x)
                        bottom = maxi(bottom,y)
            var used = Rect2i(left,top,right-left+1,bottom-top+1) if right >= 0 else Rect2i(Vector2i.ZERO,bounds.size)
            sprite.region = Rect2(bounds.position+used.position,used.size)
            sprite.filter_clip = true
            result[("w" if row == 0 else "b")+PIECE_ORDER[column]] = sprite
    piece_cache[id] = result
    return result

static func badge_texture(league_id: String) -> Texture2D:
    var index = BADGE_ORDER.find(league_id)
    if index < 0: return null
    var atlas = texture("res://cosmetics/assets/badges.png")
    if atlas == null: return null
    var cell = atlas.get_size() / Vector2(4,3)
    var sprite := AtlasTexture.new()
    sprite.atlas = atlas
    sprite.region = Rect2(Vector2(index%4,floori(index/4.0))*cell,cell)
    sprite.filter_clip = true
    return sprite
