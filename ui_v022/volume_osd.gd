extends CanvasLayer
## Aviso rápido de volume (OSD): aparece com fade quando Música ou Efeitos mudam,
## fica ~1 s e some sozinho. Não recebe cliques e não mexe no áudio (só mostra).
const GOLD = Color("f4ce7f")
const CREAM = Color("efe3c4")
var panel: PanelContainer
var title: Label
var value_label: Label
var bar: ProgressBar
var _hold := 0.0
var _tween: Tween

func _ready():
    layer = 95
    panel = PanelContainer.new()
    panel.name = "VolumeOSD"
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.09, 0.07, 0.92)
    style.border_color = Color("b19758")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    for side in ["left", "right"]: style.set("content_margin_" + side, 18)
    for side in ["top", "bottom"]: style.set("content_margin_" + side, 10)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    var col = VBoxContainer.new()
    col.mouse_filter = Control.MOUSE_FILTER_IGNORE
    col.add_theme_constant_override("separation", 6)
    panel.add_child(col)
    var row = HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    col.add_child(row)
    title = Label.new()
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_color_override("font_color", GOLD)
    row.add_child(title)
    value_label = Label.new()
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.add_theme_color_override("font_color", CREAM)
    row.add_child(value_label)
    bar = ProgressBar.new()
    bar.show_percentage = false
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bar.max_value = 100
    var bg = StyleBoxFlat.new()
    bg.bg_color = Color("0b1410")
    bg.set_corner_radius_all(4)
    var fill = StyleBoxFlat.new()
    fill.bg_color = GOLD
    fill.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", bg)
    bar.add_theme_stylebox_override("fill", fill)
    col.add_child(bar)
    panel.modulate.a = 0.0
    panel.hide()
    get_viewport().size_changed.connect(_layout)

## kind: "music" ou "effects"; value: 0..100
func show_volume(kind: String, value: float):
    var muted = value <= 0.0
    title.text = ("MÚSICA" if kind == "music" else "EFEITOS") + ("  ·  MUDO" if muted else "")
    value_label.text = "%d%%" % roundi(value)
    bar.value = value
    _layout()
    panel.show()
    if _tween: _tween.kill()
    _tween = create_tween()
    _tween.tween_property(panel, "modulate:a", 1.0, 0.12 * (1.0 - panel.modulate.a))
    _hold = 1.1

func _process(delta):
    if _hold <= 0.0: return
    _hold -= delta
    if _hold <= 0.0:
        if _tween: _tween.kill()
        _tween = create_tween()
        _tween.tween_property(panel, "modulate:a", 0.0, 0.35)
        _tween.tween_callback(panel.hide)

func _layout():
    if not is_instance_valid(panel): return
    var mobile = preload("res://ui_v022/mobile_layout.gd").active(get_viewport())
    var area: Rect2 = preload("res://ui_v022/mobile_layout.gd").safe_rect(get_viewport()) if mobile else get_viewport().get_visible_rect()
    var font = 16 if mobile else 26
    title.add_theme_font_size_override("font_size", font)
    value_label.add_theme_font_size_override("font_size", font)
    var w = minf(area.size.x - 32.0, 260.0 if mobile else 420.0)
    bar.custom_minimum_size = Vector2(w - 36.0, 8.0 if mobile else 12.0)
    panel.reset_size()
    panel.size.x = w
    panel.position = Vector2(area.position.x + (area.size.x - w) / 2.0, area.position.y + (14.0 if mobile else 36.0))
