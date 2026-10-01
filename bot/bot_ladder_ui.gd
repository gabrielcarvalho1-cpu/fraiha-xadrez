extends GridContainer
## Tela "JOGAR CONTRA O COMPUTADOR": a escada de bots pelas ligas (Madeira → Challenger).
## Cada cartão: brasão da liga (arte existente em cosmetics/assets/badges.png), nome do bot,
## personalidade, status BLOQUEADO / DISPONÍVEL / DERROTADO, recompensa e DESAFIAR.
## Usado no PC (página larga, 6 colunas) e no celular (1–2 colunas). Retrato/nome próprios de cada
## bot entram depois: o cartão já lê "portrait" do bot_ladder.json se existir.
signal challenge(bot_id: String)

const Ladder = preload("res://bot/bot_ladder.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const GOLD := Color("ffd98a")
const CREAM := Color("f4ead2")
const MUTED := Color("b9b29c")
const OK_GREEN := Color("8fe0a0")
const AVATAR_NAMES := {"warrior": "Guerreiro", "archer": "Arqueira", "mage": "Mago", "paladin": "Paladino"}

var progress            # bot/bot_progress.gd
var card_size := Vector2(222, 268)
var badge_size := 104
var compact := false    # celular: cartão horizontal
var cards := {}

func setup(p_progress, p_columns: int, p_card_size: Vector2, p_compact := false):
    progress = p_progress
    columns = p_columns
    card_size = p_card_size
    compact = p_compact
    badge_size = 74 if compact else 56
    add_theme_constant_override("h_separation", 12)
    add_theme_constant_override("v_separation", 12)
    if progress != null and not progress.changed.is_connected(refresh): progress.changed.connect(refresh)
    refresh()

func refresh():
    for c in get_children():
        remove_child(c)
        c.queue_free()
    cards.clear()
    for b in Ladder.bots(): add_child(_card(b))

static func reward_text(reward: Dictionary, short := false) -> String:
    if String(reward.get("type", "")) != "avatar": return "—"
    var id := String(reward.get("id", ""))
    if AVATAR_NAMES.has(id): return "Avatar " + AVATAR_NAMES[id]
    return "Avatar exclusivo (em breve)" if not short else "Avatar em breve"

func _card(b: Dictionary) -> Control:
    var id := String(b.id)
    var st: String = progress.status(id) if progress != null else ("available" if Ladder.index_of(id) == 0 else "locked")
    var panel := PanelContainer.new()
    panel.name = "Bot_" + id
    panel.custom_minimum_size = card_size
    if compact: panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("13241a") if st != "locked" else Color("101512")
    sb.border_color = {"defeated": Color("7fc48c"), "available": Color("d9a441"), "locked": Color("3d4a40")}[st]
    sb.set_border_width_all(3 if st == "available" else 2)
    sb.set_corner_radius_all(6)
    sb.shadow_color = Color(0.96, 0.78, 0.36, 0.35) if st == "available" else Color(0, 0, 0, 0.4)
    sb.shadow_size = 8 if st == "available" else 4
    sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 8
    panel.add_theme_stylebox_override("panel", sb)
    var box: BoxContainer = HBoxContainer.new() if compact else VBoxContainer.new()
    box.add_theme_constant_override("separation", 4 if not compact else 8)
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(box)
    var badge := TextureRect.new()
    badge.texture = ThemeCatalog.badge_texture(String(Ladder.bot(id).get("league", id)))
    badge.custom_minimum_size = Vector2(badge_size, badge_size)
    badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    if st == "locked": badge.modulate = Color(0.28, 0.3, 0.3)
    box.add_child(badge)
    var info := VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.add_theme_constant_override("separation", 1)
    box.add_child(info)
    var name_l := _lab(info, String(b.name), 18, GOLD if st != "locked" else MUTED)
    name_l.name = "Name"
    _lab(info, String(b.get("title", "")), 12, CREAM if st != "locked" else MUTED)
    var status_l := _lab(info, {"defeated": "DERROTADO", "available": "DISPONÍVEL", "locked": "BLOQUEADO"}[st], 14,
        {"defeated": OK_GREEN, "available": GOLD, "locked": Color("8a8f86")}[st])
    status_l.name = "Status"
    var lock_hint := ""
    if st == "locked":
        var i := Ladder.index_of(id)
        lock_hint = "Vença o " + String(Ladder.bots()[i - 1].name)
    panel.tooltip_text = String(b.get("description", ""))
    if compact or not lock_hint.is_empty():
        _lab(info, lock_hint if not lock_hint.is_empty() else String(b.get("description", "")), 11 if not compact else 12, MUTED).name = "Detail"
    _lab(info, ("Prêmio: " if not compact else "Recompensa: ") + reward_text(b.get("reward", {}), not compact) + (" (obtido)" if st == "defeated" else ""), 11 if not compact else 12, CREAM if st != "locked" else MUTED).name = "Reward"
    var btn := Button.new()
    btn.name = "Challenge"
    btn.text = "DESAFIAR" if st == "available" else ("JOGAR DE NOVO" if st == "defeated" else "BLOQUEADO")
    btn.disabled = st == "locked"
    btn.custom_minimum_size = Vector2(0, 34 if not compact else 40)
    btn.add_theme_font_size_override("font_size", 14 if not compact else 15)
    _style_button(btn, st)
    btn.pressed.connect(func(): challenge.emit(id))
    info.add_child(btn)
    cards[id] = panel
    return panel

func _lab(parent: Node, text: String, size: int, color: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("shadow_offset_y", 1)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(l)
    return l

func _style_button(btn: Button, st: String):
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("6b4a12") if st == "available" else (Color("23402b") if st == "defeated" else Color("1a201c"))
    normal.border_color = Color("f0c45c") if st != "locked" else Color("3d4a40")
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(4)
    var hover: StyleBoxFlat = normal.duplicate()
    hover.bg_color = normal.bg_color.lightened(0.15)
    btn.add_theme_stylebox_override("normal", normal)
    btn.add_theme_stylebox_override("hover", hover)
    btn.add_theme_stylebox_override("pressed", hover)
    btn.add_theme_stylebox_override("focus", hover)
    btn.add_theme_stylebox_override("disabled", normal)
    btn.add_theme_color_override("font_color", Color("ffe3a3"))
    btn.add_theme_color_override("font_disabled_color", Color("6f766c"))
