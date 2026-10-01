extends CanvasLayer
## GameResultOverlay — tela cinematográfica de fim de partida do FRAIHA Xadrez.
## show_result("victory" | "defeat"): escurece e desfoca o tabuleiro (shader de tela), abre um
## brilho dourado (vitória) ou um flash vermelho (derrota) atrás da arte, a arte entra com
## fade + scale e um leve impacto, e partículas (confetes / brasas e fragmentos) completam.
## Fica por cima de tudo (layer 60), não desloca nenhum elemento, some ao clicar, ESC ou após
## alguns segundos. Reutilizável: não conhece o tabuleiro — quem chama decide o resultado real
## (vencedor comparado com a cor do jogador), nunca só pela cor das peças.
signal dismissed(result: String)

const VICTORY_ART := preload("res://presentation_v019/results/victory.png")
const DEFEAT_ART := preload("res://presentation_v019/results/defeat.png")
const AUTO_HIDE := 6.0        # segundos até sumir sozinho (0 = só ao clicar)
const ART_HEIGHT := 0.68      # fração da altura da tela ocupada pela arte
const ART_MAX_WIDTH := 0.92   # nunca mais largo que isto da tela

var result := ""
var root: Control
var backdrop: ColorRect
var flash: ColorRect
var glow: Control
var art: TextureRect
var particles: Control
var hint: Label
var t := 0.0
var _parts: Array = []
var _showing := false
var _hide_at := 0.0
var _shake := 0.0

func _init():
    layer = 60
    name = "GameResultOverlay"

func _ready():
    _build()
    visible = false
    set_process(false)
    get_viewport().size_changed.connect(_layout)

func is_showing() -> bool:
    return _showing

# ---------------------------------------------------------------- construção
func _build():
    root = Control.new()
    root.name = "ResultRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    root.gui_input.connect(_on_input)
    add_child(root)
    backdrop = ColorRect.new()
    backdrop.name = "ResultBackdrop"
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://presentation_v019/result_backdrop.gdshader")
    backdrop.material = mat
    root.add_child(backdrop)
    flash = ColorRect.new()
    flash.name = "ResultFlash"
    flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
    flash.color = Color(1, 0.15, 0.1, 0.0)
    root.add_child(flash)
    glow = Control.new()
    glow.name = "ResultGlow"
    glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glow.draw.connect(_draw_glow)
    root.add_child(glow)
    art = TextureRect.new()
    art.name = "ResultArt"
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(art)
    particles = Control.new()
    particles.name = "ResultParticles"
    particles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    particles.mouse_filter = Control.MOUSE_FILTER_IGNORE
    particles.draw.connect(_draw_particles)
    root.add_child(particles)
    hint = Label.new()
    hint.name = "ResultHint"
    hint.text = "Clique para continuar"
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.add_theme_font_size_override("font_size", 15)
    hint.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75, 0.85))
    hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    hint.add_theme_constant_override("shadow_offset_y", 1)
    hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(hint)

func _layout():
    if root == null: return
    var vs := root.get_viewport_rect().size
    var tex: Texture2D = art.texture
    if tex == null: return
    var ts := tex.get_size()
    var h := vs.y * ART_HEIGHT
    var w := h * ts.x / ts.y
    if w > vs.x * ART_MAX_WIDTH:
        w = vs.x * ART_MAX_WIDTH
        h = w * ts.y / ts.x
    art.size = Vector2(w, h)
    art.pivot_offset = art.size / 2.0
    art.position = (vs - art.size) / 2.0 - Vector2(0, vs.y * 0.02)
    glow.size = Vector2(w, h) * 1.6
    glow.pivot_offset = glow.size / 2.0
    glow.position = art.position + art.size / 2.0 - glow.size / 2.0
    hint.size = Vector2(vs.x, 24)
    hint.position = Vector2(0, art.position.y + art.size.y + 8.0)

# ---------------------------------------------------------------- mostrar / esconder
## result: "victory" | "defeat". Qualquer outro valor é ignorado.
func show_result(p_result: String):
    if p_result not in ["victory", "defeat"]: return
    result = p_result
    art.texture = VICTORY_ART if result == "victory" else DEFEAT_ART
    _layout()
    _parts.clear()
    t = 0.0
    _shake = 0.0
    _showing = true
    _hide_at = AUTO_HIDE
    visible = true
    set_process(true)
    var mat: ShaderMaterial = backdrop.material
    mat.set_shader_parameter("amount", 0.0)
    mat.set_shader_parameter("tint", Color(0.0, 0.02, 0.01) if result == "victory" else Color(0.06, 0.0, 0.0))
    glow.modulate = Color(1, 1, 1, 0)
    glow.scale = Vector2(0.2, 0.2)
    art.modulate = Color(1, 1, 1, 0)
    art.scale = Vector2(0.8, 0.8) if result == "victory" else Vector2(1.18, 1.18)
    hint.modulate = Color(1, 1, 1, 0)
    flash.color.a = 0.0
    var tw := create_tween()
    tw.set_parallel(true)
    # 1) fundo escurece e desfoca
    tw.tween_method(func(v): mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.45).set_ease(Tween.EASE_OUT)
    if result == "victory":
        # 2) brilho dourado se abrindo atrás
        tw.tween_property(glow, "modulate:a", 1.0, 0.6).set_delay(0.15)
        tw.tween_property(glow, "scale", Vector2.ONE, 0.9).set_delay(0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        # 3) arte cresce 80% → 100% com leve impacto ao chegar
        tw.tween_property(art, "modulate:a", 1.0, 0.35).set_delay(0.25)
        tw.tween_property(art, "scale", Vector2.ONE, 0.7).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_callback(_impact.bind(4.0)).set_delay(0.78)
        tw.tween_callback(_burst_confetti).set_delay(0.78)
    else:
        # 2) flash vermelho discreto
        tw.tween_property(flash, "color:a", 0.32, 0.12).set_delay(0.2)
        tw.tween_property(flash, "color:a", 0.0, 0.6).set_delay(0.32)
        tw.tween_property(glow, "modulate:a", 1.0, 0.5).set_delay(0.2)
        tw.tween_property(glow, "scale", Vector2.ONE, 0.5).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        # 3) arte surge com scale e impacto (bate no lugar)
        tw.tween_property(art, "modulate:a", 1.0, 0.22).set_delay(0.22)
        tw.tween_property(art, "scale", Vector2.ONE, 0.38).set_delay(0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
        tw.tween_callback(_impact.bind(7.0)).set_delay(0.58)
        tw.tween_callback(_burst_embers).set_delay(0.58)
    tw.tween_property(hint, "modulate:a", 1.0, 0.5).set_delay(1.4)

func hide_result():
    if not _showing: return
    _showing = false
    var mat: ShaderMaterial = backdrop.material
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(art, "modulate:a", 0.0, 0.35)
    tw.tween_property(art, "scale", Vector2(1.04, 1.04), 0.35)
    tw.tween_property(glow, "modulate:a", 0.0, 0.3)
    tw.tween_property(hint, "modulate:a", 0.0, 0.2)
    tw.tween_method(func(v): mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.4)
    tw.chain().tween_callback(func():
        visible = false
        set_process(false)
        _parts.clear()
        dismissed.emit(result))

func _on_input(event: InputEvent):
    if not _showing: return
    if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
        root.accept_event()
        hide_result()

func _input(event):
    if _showing and event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
        get_viewport().set_input_as_handled()
        hide_result()

# ---------------------------------------------------------------- animação contínua
func _process(delta):
    t += delta
    if _showing and AUTO_HIDE > 0.0:
        _hide_at -= delta
        if _hide_at <= 0.0: hide_result()
    if _shake > 0.0:
        _shake = maxf(0.0, _shake - delta * 28.0)
        art.position = (root.get_viewport_rect().size - art.size) / 2.0 - Vector2(0, root.get_viewport_rect().size.y * 0.02) + Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
    # partículas
    var vs := root.get_viewport_rect().size
    var alive := []
    for p in _parts:
        p.life -= delta
        if p.life <= 0.0: continue
        p.vel += p.grav * delta
        p.vel *= 1.0 - p.drag * delta
        p.pos += p.vel * delta
        p.rot += p.spin * delta
        if p.pos.y < vs.y + 40.0: alive.append(p)
    _parts = alive
    # vitória: confetes e faíscas continuam caindo enquanto aberto; derrota: brasas subindo
    if _showing and t > 0.8:
        if result == "victory" and randf() < delta * 26.0: _spawn_confetti(1)
        elif result == "defeat" and randf() < delta * 18.0: _spawn_ember(1)
    glow.queue_redraw()
    particles.queue_redraw()

func _impact(strength: float):
    _shake = strength

## Vitória: brilho dourado em raios girando devagar atrás da composição.
func _draw_glow():
    var c := glow.size / 2.0
    var r := minf(glow.size.x, glow.size.y) / 2.0
    if result == "victory":
        for i in 3:
            glow.draw_circle(c, r * (0.55 - i * 0.12), Color(1.0, 0.82, 0.35, 0.10 + 0.04 * sin(t * 2.0 + i)))
        var n := 18
        for i in n:
            var a0 := t * 0.25 + TAU * i / n
            var wdt := 0.10 + 0.04 * sin(t * 1.7 + i * 1.3)
            var len := r * (0.95 + 0.08 * sin(t * 2.3 + i))
            var pts := PackedVector2Array([c, c + Vector2(cos(a0 - wdt), sin(a0 - wdt)) * len, c + Vector2(cos(a0 + wdt), sin(a0 + wdt)) * len])
            glow.draw_colored_polygon(pts, Color(1.0, 0.85, 0.4, 0.07 + 0.03 * sin(t * 3.0 + i * 0.7)))
        glow.draw_circle(c, r * 0.32, Color(1.0, 0.93, 0.7, 0.14 + 0.06 * sin(t * 2.6)))
    else:
        for i in 4:
            glow.draw_circle(c, r * (0.6 - i * 0.12), Color(0.9, 0.08, 0.04, 0.09 + 0.03 * sin(t * 3.0 + i)))
        var n := 14
        for i in n:
            var a0 := -t * 0.12 + TAU * i / n
            var wdt := 0.07 + 0.03 * sin(t * 2.1 + i)
            var len := r * (0.9 + 0.1 * sin(t * 1.9 + i * 0.9))
            var pts := PackedVector2Array([c, c + Vector2(cos(a0 - wdt), sin(a0 - wdt)) * len, c + Vector2(cos(a0 + wdt), sin(a0 + wdt)) * len])
            glow.draw_colored_polygon(pts, Color(1.0, 0.2, 0.08, 0.05 + 0.03 * sin(t * 2.4 + i)))

# ---------------------------------------------------------------- partículas
func _burst_confetti():
    _spawn_confetti(90)
    for i in 40:   # faíscas douradas saindo do centro
        var a := randf() * TAU
        var sp := randf_range(180.0, 520.0)
        _parts.append({"pos": _art_center(), "vel": Vector2(cos(a), sin(a)) * sp, "grav": Vector2(0, 240), "drag": 1.6, "life": randf_range(0.6, 1.3),
            "col": Color(1.0, randf_range(0.8, 0.95), randf_range(0.4, 0.7)), "size": randf_range(2.0, 4.5), "kind": "spark", "rot": 0.0, "spin": 0.0})

func _spawn_confetti(n: int):
    var vs := root.get_viewport_rect().size
    var ac := _art_center()
    for i in n:
        var from_top := randf() < 0.6
        var pos := Vector2(randf_range(ac.x - art.size.x * 0.65, ac.x + art.size.x * 0.65), randf_range(ac.y - art.size.y * 0.8, ac.y - art.size.y * 0.3)) if from_top else ac + Vector2(randf_range(-80, 80), randf_range(-60, 60))
        var vel := Vector2(randf_range(-90, 90), randf_range(-40, 60)) if from_top else Vector2(randf_range(-320, 320), randf_range(-420, -120))
        var gold := randf() < 0.55
        _parts.append({"pos": pos, "vel": vel, "grav": Vector2(0, randf_range(160, 260)), "drag": 1.2, "life": randf_range(2.0, 3.5),
            "col": Color(1.0, randf_range(0.75, 0.9), randf_range(0.25, 0.45)) if gold else Color(randf_range(0.15, 0.3), randf_range(0.4, 0.6), 1.0),
            "size": randf_range(5.0, 10.0), "kind": "confetti", "rot": randf() * TAU, "spin": randf_range(-6.0, 6.0)})
        if vs.y <= 0.0: break

func _burst_embers():
    _spawn_ember(60)
    for i in 36:   # fragmentos cinza/pedra caindo
        var a := randf_range(-PI, 0.0)
        var sp := randf_range(120.0, 420.0)
        var g := randf_range(0.3, 0.55)
        _parts.append({"pos": _art_center() + Vector2(randf_range(-art.size.x * 0.35, art.size.x * 0.35), randf_range(-20, 60)), "vel": Vector2(cos(a), sin(a)) * sp, "grav": Vector2(0, 520), "drag": 0.6, "life": randf_range(1.0, 1.8),
            "col": Color(g, g * 0.95, g * 0.9), "size": randf_range(3.0, 7.0), "kind": "shard", "rot": randf() * TAU, "spin": randf_range(-9.0, 9.0)})

func _spawn_ember(n: int):
    var ac := _art_center()
    for i in n:
        var pos := ac + Vector2(randf_range(-art.size.x * 0.5, art.size.x * 0.5), randf_range(art.size.y * 0.1, art.size.y * 0.5))
        _parts.append({"pos": pos, "vel": Vector2(randf_range(-30, 30), randf_range(-140, -50)), "grav": Vector2(randf_range(-20, 20), -30), "drag": 0.4, "life": randf_range(1.2, 2.6),
            "col": Color(1.0, randf_range(0.25, 0.6), randf_range(0.0, 0.15)), "size": randf_range(1.5, 3.5), "kind": "ember", "rot": 0.0, "spin": 0.0})

func _art_center() -> Vector2:
    return art.position + art.size / 2.0

func _draw_particles():
    for p in _parts:
        var a: float = clampf(p.life / 0.6, 0.0, 1.0)
        var col: Color = p.col
        col.a = a
        match p.kind:
            "confetti":
                var s: float = p.size
                var r: float = p.rot
                var pts := PackedVector2Array()
                for v in [Vector2(-s * 0.5, -s * 0.3), Vector2(s * 0.5, -s * 0.3), Vector2(s * 0.5, s * 0.3), Vector2(-s * 0.5, s * 0.3)]:
                    pts.append(p.pos + v.rotated(r) * Vector2(1.0, 0.4 + 0.6 * absf(sin(t * 4.0 + r))))
                particles.draw_colored_polygon(pts, col)
            "shard":
                var s2: float = p.size
                var pts2 := PackedVector2Array([p.pos + Vector2(0, -s2).rotated(p.rot), p.pos + Vector2(s2 * 0.8, s2 * 0.5).rotated(p.rot), p.pos + Vector2(-s2 * 0.7, s2 * 0.6).rotated(p.rot)])
                particles.draw_colored_polygon(pts2, col)
            "ember":
                particles.draw_circle(p.pos, p.size * 2.2, Color(col.r, col.g, col.b, col.a * 0.25))
                particles.draw_circle(p.pos, p.size, col)
            _:
                particles.draw_circle(p.pos, p.size, col)
                particles.draw_circle(p.pos, p.size * 0.45, Color(1, 1, 0.95, col.a))
