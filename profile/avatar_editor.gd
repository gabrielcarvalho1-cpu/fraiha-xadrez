extends CanvasLayer
## Editor de foto de perfil: mover (arrastar), zoom (barra, roda do mouse ou pinça),
## centralizar, prévia QUADRADA com a moldura em uso (R169), CANCELAR / SALVAR FOTO. Ao salvar: recorta o quadrado
## enquadrado, redimensiona para 512x512, comprime em WebP (≤ 400 KB), grava no cache local
## e envia ao servidor quando há conta (acct_avatar_upload). Funciona com mouse e toque.
signal saved(image: Image, bytes: PackedByteArray)
signal cancelled

const Art := preload("res://monetization/premium_art.gd")
const Store := preload("res://profile/avatar_store.gd")
const OUT := 512
const MAX_SOURCE := 2048    # fotos enormes são reduzidas antes de editar (desempenho/memória)
const MIN_SOURCE := 64

var source: Image
var source_tex: ImageTexture
var root: Control
var frame: Control            # moldura da prévia (quadrado)
var view: Control             # área onde a foto é desenhada
var zoom_slider: HSlider
var status: Label
var save_button: Button
var zoom := 1.0               # 1 = a foto cobre exatamente o quadrado (menor lado)
var pan := Vector2.ZERO    # deslocamento do centro, em pixels da prévia
var dragging := false
var last_drag := Vector2.ZERO
var touches := {}
var pinch_start := 0.0
var pinch_zoom := 1.0
var preview_size := 320.0
## R169 · a foto é enquadrada em QUADRADO dentro da moldura que o jogador usa (o círculo saiu)
var frame_id := ""            # moldura em uso (main_hub.current_frame()); "" = só o filete dourado
var league_id := "madeira"    # para a moldura "liga"
var stage_box: CenterContainer
var overlay: Control

func _init():
    layer = 70
    name = "AvatarEditor"
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC fecha

func _ready():
    _build()
    visible = false

## Abre com os bytes do arquivo escolhido. Retorna "" ou a mensagem de erro.
func open_with(bytes: PackedByteArray) -> String:
    var img := Store.decode(bytes)
    if img == null: return "Não foi possível ler esta imagem. Use PNG, JPG ou WebP."
    if img.get_width() < MIN_SOURCE or img.get_height() < MIN_SOURCE: return "A imagem é pequena demais (mínimo 64x64)."
    var big := maxi(img.get_width(), img.get_height())
    if big > MAX_SOURCE:
        var k := float(MAX_SOURCE) / big
        img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
    source = img
    source_tex = ImageTexture.create_from_image(img)
    zoom = 1.0
    pan = Vector2.ZERO
    zoom_slider.set_value_no_signal(1.0)
    status.text = "Arraste para mover · use a barra, a roda do mouse ou a pinça para aproximar"
    visible = true
    _layout()
    view.queue_redraw()
    return ""

func close():
    visible = false
    source = null
    source_tex = null

# ---------------------------------------------------------------- construção
func _build():
    root = Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.78)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(center)
    frame = Art.Frame.new("founder", 18)
    frame.name = "AvatarEditorPanel"
    frame.mouse_filter = Control.MOUSE_FILTER_STOP
    center.add_child(frame)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    frame.add_child(v)
    Art.label(v, "FOTO DE PERFIL", 26, Art.GOLD, Art.FONT_BOLD, HORIZONTAL_ALIGNMENT_CENTER)
    view = Control.new()
    view.name = "AvatarView"
    view.custom_minimum_size = Vector2(preview_size, preview_size)
    # quadrado exato e centralizado (sem esticar na largura do painel — senão o círculo fica torto)
    view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    view.mouse_filter = Control.MOUSE_FILTER_STOP
    view.clip_contents = true
    view.draw.connect(_draw_view)
    view.gui_input.connect(_view_input)
    stage_box = CenterContainer.new()
    stage_box.name = "AvatarStage"
    stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_child(stage_box)
    stage_box.add_child(view)
    overlay = Control.new()   # a moldura por cima da prévia (sai para fora do quadrado; não recebe toque)
    overlay.name = "AvatarFrameOverlay"
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    stage_box.add_child(overlay)
    status = Art.label(v, "", 14, Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
    status.name = "AvatarStatus"
    var zrow := HBoxContainer.new()
    zrow.add_theme_constant_override("separation", 10)
    v.add_child(zrow)
    var zl := Art.label(zrow, "ZOOM", 14, Art.GOLD, Art.FONT_SEMI)
    zl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    zl.autowrap_mode = TextServer.AUTOWRAP_OFF
    zoom_slider = HSlider.new()
    zoom_slider.name = "AvatarZoom"
    zoom_slider.min_value = 1.0
    zoom_slider.max_value = 4.0
    zoom_slider.step = 0.01
    zoom_slider.value = 1.0
    zoom_slider.custom_minimum_size = Vector2(0, 36)
    zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    zoom_slider.value_changed.connect(func(val): set_zoom(val))
    zrow.add_child(zoom_slider)
    var centre := Art.Cta.new("CENTRALIZAR", "dark", 40, 14)
    centre.name = "AvatarCenter"
    centre.custom_minimum_size.x = 130
    centre.pressed.connect(center_photo)
    zrow.add_child(centre)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 12)
    v.add_child(buttons)
    var cancel := Art.Cta.new("CANCELAR", "dark", 54, 18)
    cancel.name = "AvatarCancel"
    cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel.pressed.connect(func():
        close()
        cancelled.emit())
    buttons.add_child(cancel)
    save_button = Art.Cta.new("SALVAR FOTO", "gold", 54, 18)
    save_button.name = "AvatarSave"
    save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_button.pressed.connect(_save)
    buttons.add_child(save_button)
    get_viewport().size_changed.connect(_layout)

func _layout():
    var vs := root.get_viewport_rect().size
    var k := 1.5 if _has_frame() else 1.0   # espaço para a moldura em volta
    preview_size = clampf(minf((vs.x - 80.0) / k, (vs.y - 300.0) / k), 160.0, 330.0)
    view.custom_minimum_size = Vector2(preview_size, preview_size)
    view.size = view.custom_minimum_size
    overlay.custom_minimum_size = view.custom_minimum_size
    stage_box.custom_minimum_size = view.custom_minimum_size * k
    frame.custom_minimum_size.x = minf(vs.x - 24.0, 520.0)
    view.queue_redraw()

func _has_frame() -> bool:
    return not frame_id.is_empty() and frame_id != "none"

## R169 · troca a moldura da prévia (chamado antes de abrir)
func set_frame(fid: String, league := "madeira"):
    frame_id = fid
    league_id = league
    if overlay == null: return
    for c in overlay.get_children():
        overlay.remove_child(c)
        c.queue_free()
    if _has_frame():
        var f
        if fid == "liga":
            f = preload("res://profile/league_frame.gd").new()
            f.league_id = league
        else:
            f = preload("res://monetization/club_frame.gd").new()
            f.style = fid
        f.name = "Frame"
        overlay.add_child(f)
    if visible: _layout()

## CENTRALIZAR: recoloca o centro da foto no centro do círculo (mantém o zoom).
func center_photo():
    pan = Vector2.ZERO
    if status != null: status.text = "Foto centralizada · arraste para ajustar"
    view.queue_redraw()

# ---------------------------------------------------------------- geometria
## Escala base: a foto cobre o quadrado da prévia pelo menor lado.
func _base_scale() -> float:
    if source == null: return 1.0
    return preview_size / float(mini(source.get_width(), source.get_height()))

func _scale() -> float:
    return _base_scale() * zoom

## Retângulo da foto desenhada na prévia (coordenadas da prévia), já limitado para cobrir o quadrado.
func _photo_rect() -> Rect2:
    var s := _scale()
    var size := Vector2(source.get_width(), source.get_height()) * s
    var half := Vector2(preview_size, preview_size) / 2.0
    var pos := half - size / 2.0 + pan
    # não deixa aparecer borda vazia dentro do quadrado
    pos.x = clampf(pos.x, preview_size - size.x, 0.0)
    pos.y = clampf(pos.y, preview_size - size.y, 0.0)
    pan = pos - (half - size / 2.0)
    return Rect2(pos, size)

func set_zoom(value: float):
    var old := _scale()
    zoom = clampf(value, 1.0, 4.0)
    # mantém o centro da prévia fixo ao aproximar
    var k := _scale() / old
    pan *= k
    zoom_slider.set_value_no_signal(zoom)
    view.queue_redraw()

func _draw_view():
    if source_tex == null: return
    if absf(view.size.x - preview_size) > 1.0 or absf(view.size.y - preview_size) > 1.0:
        preview_size = minf(view.size.x, view.size.y)   # geometria sempre no quadrado real
    var r := _photo_rect()
    view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.029, 0.043, 0.071))
    view.draw_texture_rect(source_tex, r, false)
    # R169 · enquadramento QUADRADO: o que aparece aqui é exatamente o que fica no retrato (a moldura vem por cima)
    if not _has_frame():
        view.draw_rect(Rect2(Vector2.ZERO, view.size), Color("f1d58a"), false, 2.5)

# ---------------------------------------------------------------- entrada
func _view_input(event: InputEvent):
    if source == null: return
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            dragging = event.pressed
            last_drag = event.position
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: set_zoom(zoom * 1.08)
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: set_zoom(zoom / 1.08)
        view.accept_event()
    elif event is InputEventMouseMotion and dragging and touches.size() < 2:
        pan += event.position - last_drag
        last_drag = event.position
        view.queue_redraw()
        view.accept_event()
    elif event is InputEventScreenTouch:
        if event.pressed: touches[event.index] = event.position
        else: touches.erase(event.index)
        if touches.size() == 2:
            var p := touches.values()
            pinch_start = (p[0] - p[1]).length()
            pinch_zoom = zoom
        view.accept_event()
    elif event is InputEventScreenDrag:
        touches[event.index] = event.position
        if touches.size() == 2 and pinch_start > 0.0:
            var p := touches.values()
            set_zoom(pinch_zoom * (p[0] - p[1]).length() / pinch_start)
        view.accept_event()
    elif event is InputEventMagnifyGesture:
        set_zoom(zoom * event.factor)
        view.accept_event()

# ---------------------------------------------------------------- salvar
func _save():
    if source == null: return
    var r := _photo_rect()
    var s := _scale()
    # quadrado da prévia → região da foto original
    var x0 := int(round(-r.position.x / s))
    var y0 := int(round(-r.position.y / s))
    var side := int(round(preview_size / s))
    side = clampi(side, 1, mini(source.get_width() - x0, source.get_height() - y0))
    var region := source.get_region(Rect2i(x0, y0, side, side))
    region.resize(OUT, OUT, Image.INTERPOLATE_LANCZOS)
    if region.get_format() != Image.FORMAT_RGBA8: region.convert(Image.FORMAT_RGBA8)
    var bytes := Store.encode_webp(region)
    close()
    saved.emit(region, bytes)
