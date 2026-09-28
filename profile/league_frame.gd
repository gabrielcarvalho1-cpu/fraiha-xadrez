extends Control
## Cosmetic border: uses the actual profile league, never the scene preview.
const Catalog = preload("res://cosmetics/theme_catalog.gd")
const IDS = Catalog.BADGE_ORDER
const COLORS = [Color("b18750"),Color("a5aeb9"),Color("d59861"),Color("dce7ef"),Color("f4ce73"),Color("86d6e7"),Color("50d397"),Color("9de5ff"),Color("c295f0"),Color("e7a956"),Color("ffd66c")]
var league_id := "madeira"
func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    resized.connect(queue_redraw)
func _draw():
    var index = maxi(0,IDS.find(league_id))
    var color: Color = COLORS[index]
    var rect = Rect2(Vector2(2,2),size-Vector2(4,4))
    draw_rect(rect,Color("101c17"),false,6)
    draw_rect(rect,color,false,2)
    draw_rect(rect.grow(-4),Color("dfb96c"),false,1)
    for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
        draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),color)
    var badge = Catalog.badge_texture(league_id)
    if badge != null:
        var side = minf(28,size.x*0.24)
        draw_texture_rect(badge,Rect2(Vector2((size.x-side)/2,size.y-side*0.62),Vector2(side,side)),false)
