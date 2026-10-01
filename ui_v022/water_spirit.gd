extends Control
## Espírito das águas (arte de referência) sobre o lago da Home: luz azul-ciano translúcida,
## flutuação vertical lenta, respiração de opacidade, brilho suave atrás, reflexo ondulado na
## água e partículas azuladas discretas. Só aparece com a arte oficial da floresta.
## Posição/tamanho em coordenadas do canvas 1672 x 941 (quem cria define rect).
const TEX := preload("res://ui_v022/assets/water_spirit.png")

var t := randf() * 10.0
var parts: Array = []
var _add_mat: CanvasItemMaterial

func _init():
    name = "WaterSpirit"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _add_mat = CanvasItemMaterial.new()
    _add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

func _process(delta):
    if not is_visible_in_tree(): return
    t += delta
    for p in parts:
        p.life -= delta
        p.pos += p.vel * delta
        p.vel.x += sin(t * 2.0 + p.seed) * 6.0 * delta
    parts = parts.filter(func(p): return p.life > 0.0)
    if parts.size() < 14 and randf() < delta * 5.0:
        parts.append({"pos": Vector2(randf_range(size.x * 0.25, size.x * 0.8), randf_range(size.y * 0.35, size.y * 0.95)),
            "vel": Vector2(randf_range(-4, 4), randf_range(-14, -6)), "life": randf_range(2.0, 4.0), "max": 3.0, "seed": randf() * TAU, "r": randf_range(0.8, 1.8)})
    queue_redraw()

func _draw():
    var ts := TEX.get_size()
    var k := minf(size.x / ts.x, size.y / ts.y)
    var dsz := ts * k
    var bob := sin(t * 0.8) * size.y * 0.012          # flutuação lenta, quase imperceptível
    var breath := 0.82 + 0.10 * sin(t * 1.3) + 0.04 * sin(t * 3.1)   # respiração de opacidade
    var pos := Vector2((size.x - dsz.x) / 2.0, size.y - dsz.y + bob)
    var center := pos + dsz * Vector2(0.45, 0.55)
    # brilho suave atrás (aditivo, bem discreto)
    draw_set_transform(Vector2.ZERO)
    for i in 3:
        draw_circle(center, dsz.x * (0.22 + i * 0.1), Color(0.35, 0.75, 1.0, (0.05 - i * 0.013) * breath))
    # reflexo na água: espelhado, achatado, ondulado e mais fraco (fatias horizontais deslocadas)
    var ry0 := size.y + bob * 0.5
    var rh := dsz.y * 0.42
    var slices := 18
    for i in slices:
        var f0 := float(i) / slices
        var f1 := float(i + 1) / slices
        var wobble := sin(t * 2.2 + i * 0.9) * 2.0 + sin(t * 1.1 + i * 0.4) * 1.5
        var src := Rect2(Vector2(0, ts.y * (1.0 - f1)), Vector2(ts.x, ts.y * (f1 - f0)))
        var dst := Rect2(Vector2(pos.x + wobble, ry0 + rh * f0), Vector2(dsz.x, rh * (f1 - f0) + 0.5))
        draw_texture_rect_region(TEX, dst, src, Color(0.7, 0.9, 1.0, 0.22 * breath * (1.0 - f0 * 0.8)))
    # o espírito (translúcido; um passe normal + um passe aditivo fraco = luz, não personagem sólido)
    draw_texture_rect(TEX, Rect2(pos, dsz), false, Color(1, 1, 1, 0.78 * breath))
    # partículas azuladas
    for p in parts:
        var a: float = clampf(p.life / p.max, 0.0, 1.0) * clampf((p.max - p.life) * 2.0, 0.0, 1.0)
        draw_circle(p.pos + Vector2(0, bob), p.r * 2.4, Color(0.5, 0.85, 1.0, 0.18 * a))
        draw_circle(p.pos + Vector2(0, bob), p.r, Color(0.85, 0.97, 1.0, 0.75 * a))
    # luz do espírito tocando a água logo abaixo (brilho elíptico)
    draw_set_transform(Vector2(center.x, size.y + 2.0), 0.0, Vector2(1.0, 0.28))
    for i in 3:
        draw_circle(Vector2.ZERO, dsz.x * (0.25 + i * 0.12), Color(0.4, 0.8, 1.0, (0.07 - i * 0.02) * breath))
    draw_set_transform(Vector2.ZERO)
