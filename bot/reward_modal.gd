extends CanvasLayer
## "NOVA RECOMPENSA — Avatar desbloqueado!" depois da 1ª vitória contra um bot da escada.
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Ladder = preload("res://bot/bot_ladder.gd")
const LadderUI = preload("res://bot/bot_ladder_ui.gd")
var root: Control
var avatar_for: Callable   # id -> Texture2D (avatar do hub)

func _ready():
    layer = 60

func show_reward(bot_id: String, reward: Dictionary):
    if is_instance_valid(root): root.queue_free()
    var bot := Ladder.bot(bot_id)
    root = Control.new()
    root.name = "RewardModal"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.62)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(420, 0)
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("13241a")
    sb.border_color = Color("f0c45c")
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(8)
    sb.shadow_color = Color(0.96, 0.78, 0.36, 0.45)
    sb.shadow_size = 16
    for side in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + side, 22)
    panel.add_theme_stylebox_override("panel", sb)
    center.add_child(panel)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 10)
    panel.add_child(box)
    _lab(box, "NOVA RECOMPENSA", 30, Color("ffd98a"))
    _lab(box, "Você derrotou o " + String(bot.get("name", "bot")) + " pela primeira vez!", 17, Color("f4ead2"))
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 18)
    box.add_child(row)
    _tex(row, ThemeCatalog.badge_texture(String(bot.get("league", bot_id))), 96)
    var aid := String(reward.get("id", ""))
    var tex: Texture2D = avatar_for.call(aid) if avatar_for.is_valid() and LadderUI.AVATAR_NAMES.has(aid) else null
    if tex != null: _tex(row, tex, 120)
    _lab(box, "Avatar desbloqueado!" if LadderUI.AVATAR_NAMES.has(aid) else "Recompensa registrada!", 22, Color("8fe0a0"))
    _lab(box, LadderUI.reward_text(reward), 16, Color("f4ead2"))
    var nxt := Ladder.index_of(bot_id) + 1
    if nxt < Ladder.bots().size(): _lab(box, "Próximo desafio liberado: " + String(Ladder.bots()[nxt].name), 15, Color("b9b29c"))
    var ok := Button.new()
    ok.text = "CONTINUAR"
    ok.custom_minimum_size = Vector2(220, 46)
    ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    ok.add_theme_font_size_override("font_size", 18)
    ok.pressed.connect(close)
    box.add_child(ok)
    panel.pivot_offset = panel.custom_minimum_size / 2
    panel.scale = Vector2(0.6, 0.6)
    panel.modulate.a = 0.0
    var tw := create_tween().set_parallel(true)
    tw.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(panel, "modulate:a", 1.0, 0.25)

func close():
    if is_instance_valid(root): root.queue_free()
    root = null

func is_open() -> bool:
    return is_instance_valid(root)

func _lab(parent: Node, text: String, size: int, color: Color):
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_y", 1)
    parent.add_child(l)

func _tex(parent: Node, tex: Texture2D, px: int):
    var t := TextureRect.new()
    t.texture = tex
    t.custom_minimum_size = Vector2(px, px)
    t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    parent.add_child(t)
