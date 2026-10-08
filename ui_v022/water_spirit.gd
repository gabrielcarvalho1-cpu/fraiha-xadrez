extends Control
## Espírito das águas (arte de referência) sobre o lago da Home: luz azul-ciano translúcida,
## flutuação vertical lenta, respiração de opacidade, brilho suave atrás, reflexo ondulado na
## água e partículas azuladas discretas. Só aparece com a arte oficial da floresta.
## Posição/tamanho em coordenadas do canvas 1672 x 941 (quem cria define rect).
const TEX := preload("res://ui_v022/assets/water_spirit.png")

const Disc := preload("res://ui_v022/static_disc.gd")
const MAX_PARTS := 14

var t := randf() * 10.0
var parts: Array = []
var _add_mat: CanvasItemMaterial
## R52e · os círculos (brilho, partículas, luz na água) são nós desenhados uma vez e animados por
## posição/escala/opacidade: o _draw por quadro fica só com retângulos de textura (sem recriar buffers na Web).
var _glows: Array = []        # 3 discos atrás do espírito
var _lights: Array = []       # 3 discos da luz elíptica na água
var _light_root: Node2D
var _part_root: Node2D
var _part_nodes: Array = []   # pool: [nó, disco externo, disco interno]
var _last_size := Vector2(-1, -1)

func _init():
    name = "WaterSpirit"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _add_mat = CanvasItemMaterial.new()
    _add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    for i in 3:
        var g = Disc.new(1.0, Color(0.35, 0.75, 1.0, 1.0))
        g.show_behind_parent = true   # o brilho fica atrás do reflexo e do espírito (como antes)
        add_child(g)
        _glows.append(g)
    _part_root = Node2D.new()
    add_child(_part_root)
    for i in MAX_PARTS:
        var n := Node2D.new()
        var outer = Disc.new(1.0, Color(0.5, 0.85, 1.0, 0.18))
        var inner = Disc.new(1.0, Color(0.85, 0.97, 1.0, 0.75))
        n.add_child(outer)
        n.add_child(inner)
        n.modulate.a = 0.0   # R52f · escondido por alfa: mostrar/esconder com visible redesenha os discos (buffers novos na Web)
        _part_root.add_child(n)
        _part_nodes.append([n, outer, inner])
    _light_root = Node2D.new()
    _light_root.scale = Vector2(1.0, 0.28)
    add_child(_light_root)
    for i in 3:
        var l = Disc.new(1.0, Color(0.4, 0.8, 1.0, 1.0))
        _light_root.add_child(l)
        _lights.append(l)

func _process(delta):
    if not is_visible_in_tree(): return
    t += delta
    for p in parts:
        p.life -= delta
        p.pos += p.vel * delta
        p.vel.x += sin(t * 2.0 + p.seed) * 6.0 * delta
    for p in parts:
        if p.life <= 0.0: _part_nodes[p.slot][0].modulate.a = 0.0   # some (por alfa, sem redesenho) e libera o nó
    parts = parts.filter(func(p): return p.life > 0.0)
    if parts.size() < MAX_PARTS and randf() < delta * 5.0:
        var used := {}
        for p in parts: used[p.slot] = true
        var slot := 0
        while used.has(slot): slot += 1
        var np := {"pos": Vector2(randf_range(size.x * 0.25, size.x * 0.8), randf_range(size.y * 0.35, size.y * 0.95)),
            "vel": Vector2(randf_range(-4, 4), randf_range(-14, -6)), "life": randf_range(2.0, 4.0), "max": 3.0, "seed": randf() * TAU, "r": randf_range(0.8, 1.8), "slot": slot}
        parts.append(np)
        # R52f · raio da partícula = escala do disco de raio 1 (mesma geometria: o círculo tem sempre o mesmo
        # número de pontos). Nascer não redesenha mais nada (antes: 2 redesenhos = buffers novos a cada partícula).
        var sl: Array = _part_nodes[slot]
        sl[1].scale = Vector2.ONE * (np.r * 2.4)
        sl[2].scale = Vector2.ONE * np.r
    _update_discs()
    queue_redraw()   # só retângulos de textura (reflexo + espírito): não cria buffers

func _metrics() -> Dictionary:
    var ts := TEX.get_size()
    var k := minf(size.x / ts.x, size.y / ts.y)
    var dsz := ts * k
    var bob := sin(t * 0.8) * size.y * 0.012          # flutuação lenta, quase imperceptível
    var breath := 0.82 + 0.10 * sin(t * 1.3) + 0.04 * sin(t * 3.1)   # respiração de opacidade
    var pos := Vector2((size.x - dsz.x) / 2.0, size.y - dsz.y + bob)
    return {"ts": ts, "dsz": dsz, "bob": bob, "breath": breath, "pos": pos, "center": pos + dsz * Vector2(0.45, 0.55)}

func _update_discs():
    var m := _metrics()
    var dsz: Vector2 = m.dsz
    if size != _last_size:   # raio depende do tamanho: só redesenha quando o tamanho muda
        _last_size = size
        for i in 3:
            _glows[i].radius = dsz.x * (0.22 + i * 0.1)
            _glows[i].queue_redraw()
            _lights[i].radius = dsz.x * (0.25 + i * 0.12)
            _lights[i].queue_redraw()
    # brilho suave atrás (bem discreto)
    for i in 3:
        _glows[i].position = m.center
        _glows[i].modulate.a = (0.05 - i * 0.013) * m.breath
    # partículas azuladas (pool de nós; o raio só muda quando nasce uma partícula)
    for p in parts:
        var n: Node2D = _part_nodes[p.slot][0]
        n.position = p.pos + Vector2(0, m.bob)
        n.modulate.a = clampf(p.life / p.max, 0.0, 1.0) * clampf((p.max - p.life) * 2.0, 0.0, 1.0)
    # luz do espírito tocando a água logo abaixo (brilho elíptico)
    _light_root.position = Vector2(m.center.x, size.y + 2.0)
    for i in 3:
        _lights[i].modulate.a = (0.07 - i * 0.02) * m.breath

func _draw():
    var m := _metrics()
    var ts: Vector2 = m.ts
    var dsz: Vector2 = m.dsz
    var bob: float = m.bob
    var breath: float = m.breath
    var pos: Vector2 = m.pos
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
    # o espírito (translúcido)
    draw_texture_rect(TEX, Rect2(pos, dsz), false, Color(1, 1, 1, 0.78 * breath))
