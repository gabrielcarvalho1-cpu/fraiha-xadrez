extends Control
## Touch layout only. Actions and page state remain owned by the existing Home.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
var hub
var heading: Label
var profile: Button
var back_button: Button
var scroll: ScrollContainer
var borrowed: Control
var borrowed_parent: Node
var current_page := "main"

func setup(owner_hub):
    hub = owner_hub
    name = "MobileHome"
    mouse_filter = Control.MOUSE_FILTER_STOP
    var background = ColorRect.new()
    background.color = Color("0b1110")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    heading = _text(self,"FRAIHA XADREZ",22)
    heading.add_theme_color_override("font_color",Color("efcf83"))
    profile = _button(self,hub.player_name + " · PERFIL",func(): hub.show_page("profile"))
    back_button = _button(self,"← VOLTAR",hub.back)
    scroll = ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    add_child(scroll)

func layout():
    var area = Mobile.safe_rect(get_viewport())
    position = area.position
    size = area.size
    heading.position = Vector2(8,7)
    heading.size = Vector2(maxf(120,size.x-275),36)
    profile.position = Vector2(size.x-242,0)
    profile.size = Vector2(234,46)
    back_button.position = Vector2(size.x-166,0)
    back_button.size = Vector2(158,46)
    scroll.position = Vector2(8,54)
    scroll.size = Vector2(size.x-16,maxf(60,size.y-58))

func _text(parent: Node, text: String, font_size := 18) -> Label:
    var label = Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size",font_size)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _button(parent: Node, text: String, action: Callable) -> Button:
    var button = Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(0,48)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size",18)
    var style = StyleBoxFlat.new()
    style.bg_color = Color("14221d")
    style.border_color = Color("84754b")
    style.set_border_width_all(1)
    style.set_corner_radius_all(5)
    style.content_margin_left = 10
    style.content_margin_right = 10
    button.add_theme_stylebox_override("normal",style)
    var highlighted = style.duplicate()
    highlighted.bg_color = Color("26382b")
    highlighted.border_color = Color("e5c37c")
    for state in ["pressed","hover","focus"]: button.add_theme_stylebox_override(state,highlighted)
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _grid(parent: Node, columns: int) -> GridContainer:
    var grid = GridContainer.new()
    grid.columns = columns
    grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid.add_theme_constant_override("h_separation",10)
    grid.add_theme_constant_override("v_separation",10)
    parent.add_child(grid)
    return grid

func show_page(id: String):
    current_page = id
    if is_instance_valid(borrowed):
        borrowed.reparent(borrowed_parent,false)
        borrowed = null
    for child in scroll.get_children():
        scroll.remove_child(child)
        child.queue_free()
    profile.visible = id == "main"
    profile.text = hub.player_name + " · PERFIL"
    back_button.visible = id != "main"
    heading.text = {"main":"FRAIHA XADREZ","bot":"JOGAR CONTRA O BOT","bot_side":"ESCOLHA SEU LADO","profile":"PERFIL","ranking":"LIGAS E RANKING","about":"CONHEÇA O FRAIHA","settings":"CONFIGURAÇÕES","ranked":"JOGAR RANQUEADO"}.get(id,"FRAIHA XADREZ")
    if hub.page_scrolls.has(id):
        borrowed = hub.page_scrolls[id].get_child(0)
        borrowed_parent = borrowed.get_parent()
        borrowed.reparent(scroll,false)
        _touch_content(borrowed)
    else:
        var content = VBoxContainer.new()
        content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        content.add_theme_constant_override("separation",12)
        scroll.add_child(content)
        match id:
            "main":
                var grid = _grid(content,2)
                for original in hub.menu_buttons:
                    var source = original
                    var button = _button(grid,source.tooltip_text,func(): source.pressed.emit())
                    button.custom_minimum_size.y = 54
            "profile": _profile(content)
            "ranking": _ranking(content)
            "about": _about(content)
    scroll.scroll_vertical = 0
    layout()

func _touch_content(node: Node):
    if node is TextureButton:
        node.custom_minimum_size.y = maxf(56,node.custom_minimum_size.y)
        var margin = node.get_child(0)
        if margin is MarginContainer:
            var fit = func():
                margin.add_theme_constant_override("margin_left",int(node.size.x*0.232))
                margin.add_theme_constant_override("margin_right",int(node.size.x*0.094))
            if not node.has_meta("mobile_fit"):
                node.resized.connect(fit)
                node.set_meta("mobile_fit",true)
            fit.call_deferred()
    if node is HSlider: node.custom_minimum_size.y = 48
    for child in node.get_children(): _touch_content(child)

func _profile(content: VBoxContainer):
    var avatars = _grid(content,4)
    for id in ["warrior","archer","mage","paladin"]:
        var avatar_id: String = id
        var box = VBoxContainer.new()
        box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        avatars.add_child(box)
        var portrait = TextureButton.new()
        portrait.texture_normal = hub.avatar_texture(id)
        portrait.ignore_texture_size = true
        portrait.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
        portrait.custom_minimum_size = Vector2(100,100)
        portrait.pressed.connect(func():
            hub.choose_avatar(avatar_id)
            show_page.call_deferred("profile")
        )
        box.add_child(portrait)
        hub.attach_league_frame(portrait)
        _text(box,{"warrior":"Guerreiro","archer":"Arqueira","mage":"Mago","paladin":"Paladino"}[id]+(" ✓" if hub.avatar_id == id else ""),16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _text(content,"SEU NOME",16)
    var input = LineEdit.new()
    input.text = hub.player_name
    input.max_length = 20
    input.custom_minimum_size.y = 48
    input.add_theme_font_size_override("font_size",20)
    content.add_child(input)
    input.text_changed.connect(func(value):
        hub.player_name = value.strip_edges() if not value.strip_edges().is_empty() else "Jogador"
        hub.profile_name.text = hub.player_name
        hub._save_preferences()
    )
    for mode in hub.Ranked.MODES: _text(content,hub.ranked.summary(mode),17)

func _ranking(content: VBoxContainer):
    var grid = _grid(content,3)
    for entry in hub.LeagueCatalog.entries(hub.league_profile.data):
        var id: String = entry.league_id
        _button(grid,entry.display_name,func():
            hub._select_league(id)
            show_page.call_deferred("ranking")
        )
    _text(content,hub.league_detail_title.text,20)
    _text(content,hub.league_details.text,17)
    var preview = TextureRect.new()
    preview.texture = hub.league_scene_preview.texture
    preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.custom_minimum_size.y = 160
    content.add_child(preview)
    _button(content,"TESTAR UNIVERSO",hub._preview_league)
    _button(content,"PEÇAS CLÁSSICAS",func(): hub.piece_set_requested.emit("classic"))

func _about(content: VBoxContainer):
    var grid = _grid(content,2)
    var text = _text(content,hub.about_title.text+"\n\n"+hub.about_body.text,18)
    for original in hub.pages.about.find_children("*","TextureButton",true,false):
        if original.tooltip_text.begins_with("VOLTAR"): continue
        var source = original
        _button(grid,source.tooltip_text,func():
            source.pressed.emit()
            text.text = hub.about_title.text+"\n\n"+hub.about_body.text
        )
