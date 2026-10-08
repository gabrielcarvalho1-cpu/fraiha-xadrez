extends Node2D
## Vida sutil no cenário da floresta (arte "wood"): brasas subindo das tochas com brilho
## tremulante, reflexos na água, vaga-lumes e, de vez em quando, um bando de pássaros.
## Filho do sprite do cenário: coordenadas em pixels da textura (origem no centro).
## Nada aqui recebe clique nem toca na partida; fica fora da área do tabuleiro.
const WOOD_ART := preload("res://presentation_v019/forest_wide.png")
const TORCHES := [Vector2(0.288, 0.042), Vector2(0.276, 0.551), Vector2(0.693, 0.426), Vector2(0.697, 0.835)]
const BOARD := Rect2(0.300, 0.165, 0.360, 0.615)   # área do tabuleiro (UV) com folga: sem efeitos
var tex_size := Vector2(1672, 941)
var rng := RandomNumberGenerator.new()
var time := 0.0
var embers: Array = []
var glints: Array = []
var water_spots := PackedVector2Array()
var flies: Array = []
var birds: Array = []
var next_flock := 6.0
var glow_layer: Node2D
var bird_layer: Node2D
## R52e · círculos (halo das tochas e brilho dos vaga-lumes) viram nós desenhados uma vez e animados por
## escala/posição/opacidade; o _draw por quadro fica só com retângulos (brasas, reflexos, miolo dos vaga-lumes).
## Antes cada draw_circle por quadro criava buffers novos de GPU na Web (memória crescendo com a cena parada).
const Disc := preload("res://ui_v022/static_disc.gd")
var _halos: Array = []      # por tocha: [disco 30 px, disco 14 px]
var _fly_discs: Array = []

func _ready():
    rng.randomize()
    tex_size = WOOD_ART.get_size()
    z_index = 12
    # Brilhos somam luz (fogo, água, vaga-lumes); pássaros ficam numa camada normal.
    glow_layer = Node2D.new()
    glow_layer.name = "Glow"
    var add := CanvasItemMaterial.new()
    add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    glow_layer.material = add
    glow_layer.draw.connect(_draw_glow)
    add_child(glow_layer)
    for i in TORCHES.size():
        var big = Disc.new(30.0, Color(1.0, 0.42, 0.06, 1.0))
        var small = Disc.new(14.0, Color(1.0, 0.62, 0.18, 1.0))
        for d in [big, small]:
            d.material = add            # mesma luz somada da camada
            d.show_behind_parent = true # halo por baixo das brasas, como antes
            d.position = _uv(TORCHES[i]) + Vector2(0, -4)
            glow_layer.add_child(d)
        _halos.append([big, small])
    bird_layer = Node2D.new()
    bird_layer.name = "Birds"
    bird_layer.draw.connect(_draw_birds)
    add_child(bird_layer)
    _sample_water()
    for i in 12:
        flies.append(_new_fly())
        var fd = Disc.new(5.0, Color(0.85, 1.0, 0.45, 1.0))
        fd.material = add
        glow_layer.add_child(fd)
        _fly_discs.append(fd)

func _uv(p: Vector2) -> Vector2:
    return p * tex_size - tex_size / 2.0

func _sample_water():
    var img := WOOD_ART.get_image()
    if img == null: return
    if img.is_compressed(): img.decompress()
    var w := img.get_width()
    var h := img.get_height()
    for y in range(int(h * 0.46), h, 4):
        for x in range(0, int(w * 0.33), 4):
            var c := img.get_pixel(x, y)
            if c.b > c.r * 1.4 and c.b > c.g * 0.95 and c.b > 0.35:
                water_spots.append(Vector2(x, y) - tex_size / 2.0)

func _new_fly() -> Dictionary:
    var p := Vector2.ZERO
    for tries in 20:
        p = Vector2(rng.randf_range(0.03, 0.97), rng.randf_range(0.08, 0.95))
        if not BOARD.has_point(p): break
    return {"home": _uv(p), "phase": rng.randf() * TAU, "speed": rng.randf_range(0.35, 0.7), "life": rng.randf_range(5.0, 11.0), "age": 0.0}

func _process(delta):
    var art_ok := get_parent() is Sprite2D and (get_parent() as Sprite2D).texture == WOOD_ART
    visible = art_ok
    if not art_ok or not is_visible_in_tree(): return
    time += delta
    # Brasas: poucas por tocha, sobem balançando e apagam.
    for t in TORCHES:
        if rng.randf() < delta * 5.0:
            var base: Vector2 = _uv(t) + Vector2(rng.randf_range(-3, 3), -14)
            embers.append({"pos": base, "vel": Vector2(rng.randf_range(-7, 7), rng.randf_range(-62, -40)), "life": rng.randf_range(1.2, 2.2), "max": 2.2})
    var alive := []
    for e in embers:
        e.life -= delta
        e.pos += e.vel * delta
        e.vel.x += sin(time * 6.0 + e.pos.y * 0.2) * 12.0 * delta
        if e.life > 0.0: alive.append(e)
    embers = alive
    # Reflexos na água.
    if not water_spots.is_empty():
        while glints.size() < 22:
            glints.append({"pos": water_spots[rng.randi() % water_spots.size()], "age": 0.0, "life": rng.randf_range(0.9, 1.8), "len": rng.randi_range(3, 7)})
        var g_alive := []
        for g in glints:
            g.age += delta
            g.pos.x += 5.0 * delta
            if g.age < g.life: g_alive.append(g)
        glints = g_alive
    for i in flies.size():
        flies[i].age += delta
        if flies[i].age > flies[i].life: flies[i] = _new_fly()
    # Pássaros: um bando pequeno de tempos em tempos, pelas bordas de cima ou de baixo.
    next_flock -= delta
    if next_flock <= 0.0 and birds.is_empty():
        next_flock = rng.randf_range(14.0, 26.0)
        var left_to_right := rng.randf() < 0.5
        var y := rng.randf_range(0.03, 0.13) if rng.randf() < 0.6 else rng.randf_range(0.84, 0.95)
        var start := Vector2(-0.04 if left_to_right else 1.04, y)
        var dir := Vector2(1 if left_to_right else -1, rng.randf_range(-0.08, 0.08)).normalized()
        var count := rng.randi_range(2, 4)
        for i in count:
            var offset := Vector2(-dir.x * i * 16.0, (i % 2) * 11.0 - 5.0 + i * 2.0)
            birds.append({"pos": _uv(start) + offset, "vel": dir * rng.randf_range(80.0, 105.0), "phase": rng.randf() * TAU})
    var b_alive := []
    for b in birds:
        b.pos += b.vel * delta
        if absf(b.pos.x) < tex_size.x / 2.0 + 140.0: b_alive.append(b)
    birds = b_alive
    _update_discs()
    glow_layer.queue_redraw()   # só retângulos: não cria buffers
    if not birds.is_empty() or bird_layer.get_meta("drawn_birds", false):
        bird_layer.set_meta("drawn_birds", not birds.is_empty())
        bird_layer.queue_redraw()   # linhas (sem buffers) e só enquanto há bando passando

func _update_discs():
    for i in _halos.size():
        var f := _flicker(i)
        _halos[i][0].scale = Vector2.ONE * ((30.0 + 6.0 * f) / 30.0)
        _halos[i][0].modulate.a = 0.07 + 0.06 * f
        _halos[i][1].scale = Vector2.ONE * ((14.0 + 3.0 * f) / 14.0)
        _halos[i][1].modulate.a = 0.10 + 0.08 * f
    for i in flies.size():
        var fly: Dictionary = flies[i]
        var t: float = time * fly.speed + fly.phase
        var p: Vector2 = fly.home + Vector2(sin(t) * 18.0 + sin(t * 2.3) * 6.0, cos(t * 0.8) * 12.0)
        var fade: float = clampf(minf(fly.age, fly.life - fly.age), 0.0, 1.0)
        var pulse: float = 0.45 + 0.55 * maxf(0.0, sin(time * 2.2 + fly.phase * 3.0))
        _fly_discs[i].position = p
        _fly_discs[i].modulate.a = 0.10 * pulse * fade

func _flicker(i: int) -> float:
    return 0.5 + 0.3 * sin(time * 9.0 + i * 1.7) + 0.2 * sin(time * 23.0 + i * 3.1)

func _draw_glow():
    # Halo tremulante das tochas: discos em _halos (atrás), animados em _update_discs.
    for e in embers:
        var k: float = clampf(e.life / 1.4, 0.0, 1.0)
        glow_layer.draw_rect(Rect2(e.pos.round(), Vector2(3, 3)), Color(1.0, 0.45 + 0.45 * k, 0.15 + 0.3 * k, 1.0 * k))
    for g in glints:
        var a: float = sin(PI * g.age / g.life)
        glow_layer.draw_rect(Rect2(g.pos.round(), Vector2(g.len, 2)), Color(0.6, 0.85, 1.0, 0.7 * a))
    for fly in flies:
        var t: float = time * fly.speed + fly.phase
        var p: Vector2 = fly.home + Vector2(sin(t) * 18.0 + sin(t * 2.3) * 6.0, cos(t * 0.8) * 12.0)
        var fade: float = clampf(minf(fly.age, fly.life - fly.age), 0.0, 1.0)
        var pulse: float = 0.45 + 0.55 * maxf(0.0, sin(time * 2.2 + fly.phase * 3.0))
        # brilho em volta: disco em _fly_discs (animado em _update_discs)
        glow_layer.draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 1.0, 0.6, 0.8 * pulse * fade))

func _draw_birds():
    for b in birds:
        var flap: float = sin(time * 11.0 + b.phase)
        var p: Vector2 = b.pos.round()
        var wing := Vector2(7.0, -3.0 * flap)
        var ink := Color(0.10, 0.08, 0.07, 0.85)
        # Sombra bem leve no chão, deslocada.
        var sh := p + Vector2(10, 16)
        bird_layer.draw_line(sh - Vector2(wing.x, wing.y), sh, Color(0, 0, 0, 0.18), 2.0)
        bird_layer.draw_line(sh, sh + Vector2(wing.x, -wing.y) * Vector2(1, 1), Color(0, 0, 0, 0.18), 2.0)
        bird_layer.draw_line(p + Vector2(-wing.x, wing.y), p, ink, 2.0)
        bird_layer.draw_line(p, p + Vector2(wing.x, wing.y), ink, 2.0)
        bird_layer.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), ink)
