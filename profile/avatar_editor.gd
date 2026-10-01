extends CanvasLayer
## Editor de foto de perfil: mover (arrastar), zoom (barra, roda do mouse ou pinça),
## centralizar, prévia redonda, CANCELAR / SALVAR FOTO. Ao salvar: recorta o quadrado
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

func _init():
    layer = 70
    name = "AvatarEditor"

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
    v.add_child(view)
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
    preview_size = clampf(minf(vs.x - 80.0, vs.y - 300.0), 180.0, 360.0)
    view.custom_minimum_size = Vector2(preview_size, preview_size)
    view.size = view.custom_minimum_size
    frame.custom_minimum_size.x = minf(vs.x - 24.0, 520.0)
    view.queue_redraw()

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
    view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0.02, 0.05, 0.03))
    view.draw_texture_rect(source_tex, r, false)
    # escurece fora do círculo (prévia de como fica no medalhão) e desenha a borda
    var c := Vector2(preview_size, preview_size) / 2.0
    var rad := preview_size / 2.0
    var pts := PackedVector2Array()
    for i in 64:
        var a := TAU * i / 64.0
        pts.append(c + Vector2(cos(a), sin(a)) * rad)
    var outer := PackedVector2Array([Vector2(0, 0), Vector2(preview_size, 0), Vector2(preview_size, preview_size), Vector2(0, preview_size)])
    # quatro cantos escurecidos (aproximação: polígono do quadrado menos círculo)
    for i in 64:
        var a0 := TAU * i / 64.0
        var a1 := TAU * (i + 1) / 64.0
        var p0 := c + Vector2(cos(a0), sin(a0)) * rad
        var p1 := c + Vector2(cos(a1), sin(a1)) * rad
        var far0 := c + Vector2(cos(a0), sin(a0)) * rad * 1.6
        var far1 := c + Vector2(cos(a1), sin(a1)) * rad * 1.6
        view.draw_colored_polygon(PackedVector2Array([p0, far0, far1, p1]), Color(0, 0, 0, 0.68))
    view.draw_arc(c, rad - 1.0, 0, TAU, 96, Color("f1d58a"), 2.5)
    view.draw_arc(c, rad - 6.0, 0, TAU, 96, Color(0.95, 0.84, 0.54, 0.35), 1.0)
    view.draw_rect(Rect2(Vector2.ZERO, view.size), Color("c99a45"), false, 2.0)

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
