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
var menu_grid: GridContainer
var backdrop: ColorRect
var leaves: TextureRect
var hero: TextureRect
var hero_fade: TextureRect
var subtitle: Label
const Art = preload("res://account/login_art.gd")
const ROW_RECTS = [Rect2(615,338,444,58), Rect2(615,398,444,59), Rect2(568,443,534,103), Rect2(615,534,444,60), Rect2(615,596,444,60), Rect2(615,659,444,61), Rect2(615,723,444,61), Rect2(615,787,444,61)]
const CARD_ART = preload("res://ui_v022/assets/home_profile_card.png")
const Widgets = preload("res://account/login_widgets.gd")

func setup(owner_hub):
    hub = owner_hub
    name = "MobileHome"
    mouse_filter = Control.MOUSE_FILTER_STOP
    var background = ColorRect.new()
    background.color = Color("0b1110")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    backdrop = background
    # Fundo: folhagem pixel art (da própria floresta) escurecida.
    leaves = TextureRect.new()
    leaves.texture = _leaf_tile()
    leaves.stretch_mode = TextureRect.STRETCH_TILE
    leaves.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    leaves.modulate = Color(0.22, 0.27, 0.22)
    leaves.mouse_filter = Control.MOUSE_FILTER_IGNORE
    background.add_child(leaves)
    # Topo da Home: rei e rainha dourados (arte da abertura) com o título por cima.
    hero = TextureRect.new()
    hero.texture = preload("res://branding/fraiha_loading_splash.png")
    hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(hero)
    hero_fade = TextureRect.new()
    var grad = Gradient.new()
    grad.set_color(0, Color(0.04, 0.07, 0.05, 0.0))
    grad.set_color(1, Color(0.04, 0.07, 0.05, 1.0))
    var gt = GradientTexture2D.new()
    gt.gradient = grad
    gt.fill_from = Vector2(0, 0.35)
    gt.fill_to = Vector2(0, 1)
    hero_fade.texture = gt
    hero_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hero.add_child(hero_fade)
    heading = _text(self,"FRAIHA XADREZ",22)
    heading.add_theme_font_override("font", Art.FONT_BOLD)
    heading.add_theme_color_override("font_color",Color("f1d58a"))
    heading.add_theme_color_override("font_outline_color",Color("2a1905"))
    heading.add_theme_constant_override("outline_size",6)
    heading.add_theme_color_override("font_shadow_color",Color(0,0,0,0.7))
    heading.add_theme_constant_override("shadow_offset_y",3)
    subtitle = _text(self,"ESTRATÉGIA PARA IR MAIS LONGE",13)
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.add_theme_color_override("font_color",Color("e9d29a"))
    subtitle.add_theme_font_override("font", Art.FONT_SEMI)
    profile = _button(self,hub.player_name + " · PERFIL",func(): hub.show_page("profile"))
    back_button = _button(self,"VOLTAR",hub.back)
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    add_child(scroll)

func _leaf_tile() -> Texture2D:
    var img: Image = preload("res://presentation_v019/forest_wide.png").get_image()
    if img.is_compressed(): img.decompress()
    var leaf := img.get_region(Rect2i(1470, 250, 160, 160))
    var tile := Image.create(320, 320, false, leaf.get_format())
    for i in 4:
        var part := leaf.duplicate()
        if i % 2 == 1: part.flip_x()
        if i >= 2: part.flip_y()
        tile.blit_rect(part, Rect2i(0, 0, 160, 160), Vector2i((i % 2) * 160, (i / 2) * 160))
    return ImageTexture.create_from_image(tile)

func layout():
    var area = Mobile.safe_rect(get_viewport())
    position = area.position
    size = area.size
    # Cover the notch/rounded-corner margins too; only the controls respect the safe area.
    backdrop.set_anchors_preset(Control.PRESET_TOP_LEFT)
    backdrop.position = -area.position
    backdrop.size = get_viewport().get_visible_rect().size
    leaves.size = backdrop.size
    var portrait = size.x < 560.0
    var main = current_page == "main"
    # Home do celular sem faixa de título: o cartão do jogador e o menu ocupam a tela.
    hero.visible = false
    subtitle.visible = false
    heading.visible = not main
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if main else HORIZONTAL_ALIGNMENT_LEFT
    heading.add_theme_font_size_override("font_size", (34 if portrait else 26) if main else 22)
    if main:
        var hero_h = minf(size.y * 0.30, 260.0) if portrait else minf(size.y * 0.30, 120.0)
        hero.position = Vector2(-area.position.x, -area.position.y)
        hero.size = Vector2(backdrop.size.x, hero_h + area.position.y)
        hero_fade.size = hero.size
        if not portrait: heading.add_theme_font_size_override("font_size", 22)
        heading.position = Vector2(8, hero_h - (78 if portrait else 62))
        heading.size = Vector2(size.x - 16, 44)
        subtitle.position = Vector2(8, hero_h - 34)
        subtitle.size = Vector2(size.x - 16, 20)
        if is_instance_valid(menu_grid): menu_grid.columns = 1 if portrait else 2
        _fit_width(portrait)
        profile.hide()
        scroll.position = Vector2(8, 4)
        scroll.size = Vector2(size.x - 16, maxf(60, size.y - 8))
        for row in scroll.find_children("*", "Button", true, false):
            if row is ArtRow or row is ProfileCard: row.fit()
        return
    if is_instance_valid(menu_grid): menu_grid.columns = 1 if portrait else 2
    _fit_width(portrait)
    if portrait:
        # Title on its own row; profile/back as a full-width touch bar below it.
        heading.position = Vector2(8,4)
        heading.size = Vector2(size.x-16,34)
        for bar in [profile, back_button]:
            bar.position = Vector2(8,42)
            bar.size = Vector2(size.x-16,46)
        scroll.position = Vector2(8,98)
        scroll.size = Vector2(size.x-16,maxf(60,size.y-102))
        return
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
    # Botão ornamentado do jogo (moldura dourada com pontas); o texto é desenhado pelo próprio botão.
    var button = Widgets.OrnateButton.new()
    button.text = text
    button.label = text
    button.font_size = 17
    button.custom_minimum_size = Vector2(0,50)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.pressed.connect(action)
    parent.add_child(button)
    return button

func _old_button(parent: Node, text: String, action: Callable) -> Button:
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

## JOGAR RANQUEADO em destaque também no Mobile V2 (moldura dourada e texto dourado).
func _feature(button: Button):
    if button is Widgets.OrnateButton:
        button.primary = true
        button.font_size = 19
        button.custom_minimum_size.y = 58
        return
    var style: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
    style.bg_color = Color("223a2a")
    style.border_color = Color("f0cf7a")
    style.set_border_width_all(2)
    style.shadow_color = Color(0.96,0.78,0.36,0.3)
    style.shadow_size = 6
    button.add_theme_stylebox_override("normal", style)
    var hi: StyleBoxFlat = style.duplicate()
    hi.bg_color = Color("2e4a33")
    for state in ["pressed","hover","focus"]: button.add_theme_stylebox_override(state, hi)
    button.add_theme_color_override("font_color", Color("ffd98a"))
    button.add_theme_color_override("font_hover_color", Color("ffe3a3"))

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
    heading.text = {"main":"FRAIHA XADREZ","bot":"JOGAR CONTRA O COMPUTADOR","bot_side":"ESCOLHA SEU LADO","profile":"PERFIL","ranking":"LIGAS E RANKING","about":"CONHEÇA O FRAIHA","settings":"CONFIGURAÇÕES","ranked":"JOGAR RANQUEADO"}.get(id,"FRAIHA XADREZ")
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
                # Cartão do jogador recortado da própria arte do PC, com dados vivos por cima.
                var head_gap = Control.new()
                head_gap.custom_minimum_size.y = 6
                content.add_child(head_gap)
                var card = ProfileCard.new()
                card.hub = hub
                card.text = hub.player_name + " · PERFIL"
                card.pressed.connect(func(): hub.show_page("profile"))
                content.add_child(card)
                # CLUB FRAIHA: linha própria, separada do menu.
                club_row = load("res://monetization/club_home_entry.gd").new()
                club_row.compact = true
                club_row.custom_minimum_size.y = 50
                club_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                club_row.pressed.connect(func(): hub.open_club())
                content.add_child(club_row)
                refresh_club(hub.entitlements != null and hub.entitlements.club_active())
                if hub.has_signal("account_requested"):
                    _button(content,hub.account_caption,func(): hub.account_requested.emit()).custom_minimum_size.y = 50
                var grid = _grid(content,2)
                menu_grid = grid
                # Botões do menu: os mesmos da Home do PC (ícone, título e descrição), recortados da arte.
                for i in hub.menu_buttons.size():
                    var source = hub.menu_buttons[i]
                    var row = ArtRow.new()
                    row.text = hub.title_of(source)
                    # Recorte exato de cada botão na arte (bordas douradas inteiras).
                    var r: Rect2 = ROW_RECTS[i] if i < ROW_RECTS.size() else Rect2(source.position, source.size)
                    if row.text == "JOGAR RANQUEADO":
                        row.art = preload("res://ui_v022/assets/home_ranked_row.png")
                        # corpo do botão na arte: 467 de 538 px; comuns: 444 px → mesma largura visual
                        row.draw_scale = 0.92
                        row.featured = true
                    else:
                        var atlas = AtlasTexture.new()
                        atlas.atlas = hub.FOREST
                        atlas.region = r
                        row.art = atlas
                    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                    row.pressed.connect(func(): source.pressed.emit())
                    grid.add_child(row)
                # Folga no fim para o último botão (SAIR) nunca ficar cortado pela barra do navegador.
                var tail = Control.new()
                tail.custom_minimum_size.y = 90
                tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
                content.add_child(tail)
            "profile": _profile(content)
            "ranking": _ranking(content)
            "about": _about(content)
    scroll.scroll_vertical = 0
    _fit_width.call_deferred(size.x < 560.0)
    layout()

var club_row = null

func refresh_club(on: bool):
    if is_instance_valid(club_row): club_row.set_active(on)

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
        _button(grid,entry.display_name if hub.league_unlocked(id) else entry.display_name + " · BLOQUEADA",func():
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
    if hub.DEV_PREVIEW_BUTTON: _button(content,"TESTAR UNIVERSO",hub._preview_league)
    _button(content,"PEÇAS CLÁSSICAS",func(): hub.piece_set_requested.emit("classic"))

func _about(content: VBoxContainer):
    var grid = _grid(content,2)
    var text = _text(content,hub.about_title.text+"\n\n"+hub.about_body.text,18)
    for original in hub.pages.about.find_children("*","TextureButton",true,false):
        if hub.title_of(original).begins_with("VOLTAR"): continue
        var source = original
        _button(grid,hub.title_of(source),func():
            source.pressed.emit()
            text.text = hub.about_title.text+"\n\n"+hub.about_body.text
        )

## Nada da página pode ser mais largo que a tela: botões cortam o texto (…) em vez de
## esticar a grade; em retrato, grades de botões viram 1 coluna e a de avatares 2.
func _fit_width(portrait: bool):
    for grid in scroll.find_children("*", "GridContainer", true, false):
        if grid == menu_grid: continue
        var has_avatars = grid.find_children("*", "TextureButton", true, false).size() > 0
        if portrait: grid.columns = 2 if has_avatars else 1
    for b in scroll.find_children("*", "Button", true, false):
        b.clip_text = true
        b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    for tb in scroll.find_children("*", "TextureButton", true, false):
        tb.custom_minimum_size = Vector2(minf(tb.custom_minimum_size.x, 84.0), minf(tb.custom_minimum_size.y, 84.0)) if portrait else tb.custom_minimum_size
    for r in scroll.find_children("*", "TextureRect", true, false):
        r.custom_minimum_size.x = minf(r.custom_minimum_size.x, size.x - 24.0)
    for l in scroll.find_children("*", "LineEdit", true, false):
        l.custom_minimum_size.x = 0
    for c in scroll.get_children():
        if c is Control: c.custom_minimum_size.x = 0


## Linha do menu desenhada com o recorte da arte do PC (mesmo visual); hover/toque = mais brilho.
class ArtRow extends Button:
    var art: Texture2D
    # Largura desenhada relativa à linha: botões comuns a 92%; o Ranqueado (com louros) é
    # desenhado maior para o corpo do botão ter a mesma largura dos outros.
    var draw_scale := 0.92
    var featured := false   # JOGAR RANQUEADO: mesmo botão dos outros + título dourado e louros
    func _init():
        focus_mode = Control.FOCUS_NONE
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        button_down.connect(func(): self_modulate = Color(1.25, 1.2, 1.05))
        button_up.connect(func(): self_modulate = Color.WHITE)
    func fit():
        if art == null or size.x <= 0.0: return
        var s: Vector2 = art.get_size()
        custom_minimum_size.y = roundf(size.x * draw_scale * s.y / s.x)
    func _notification(what):
        if what == NOTIFICATION_RESIZED: fit.call_deferred()
    func _draw():
        if art == null: return
        var w := size.x * draw_scale
        var r := Rect2(Vector2((size.x - w) / 2.0, 0), Vector2(w, size.y))
        if featured:
            # Brilho dourado suave atrás do botão.
            for i in 4:
                var g := r.grow(2.0 + i * 2.0)
                draw_rect(g, Color(1.0, 0.8, 0.3, 0.07 - i * 0.015), false, 2.0)
        draw_texture_rect(art, r, false)
        if not featured: return
        var k := w / 444.0
        var font := get_theme_default_font()
        var fs1 := int(round(19 * k))
        var fs2 := int(round(12.5 * k))
        var tx := r.position.x + 102.0 * k
        draw_string_outline(font, Vector2(tx, r.position.y + 26.0 * k), "JOGAR RANQUEADO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs1, 4, Color(0.1, 0.06, 0, 0.8))
        draw_string(font, Vector2(tx, r.position.y + 26.0 * k), "JOGAR RANQUEADO", HORIZONTAL_ALIGNMENT_LEFT, -1, fs1, Color("ffd46b"))
        draw_string(font, Vector2(tx, r.position.y + 45.0 * k), "Compita, evolua e conquiste seu lugar", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("f4ecd8"))
        # Louros dourados desenhados (um de cada lado, abraçando as pontas).
        for side in [-1.0, 1.0]:
            var cx: float = r.position.x + 3.0 * k if side < 0 else r.end.x - 3.0 * k
            var cy := r.get_center().y
            var rad := size.y * 0.55
            for j in 7:
                var t := -1.0 + 2.0 * float(j) / 6.0
                var ang := t * 1.1
                var p := Vector2(cx + side * (cos(ang) * rad * 0.35 - rad * 0.12), cy + sin(ang) * rad)
                var dir := Vector2(side * cos(ang + side * 0.0), sin(ang)).rotated(-side * 0.9 * signf(t + 0.001))
                var leaf := PackedVector2Array()
                var along := Vector2(-side * 0.45, -1.0).normalized().rotated(side * t * 0.8)
                var perp := Vector2(-along.y, along.x)
                var L := 9.5 * k
                var W := 4.0 * k
                for q in 9:
                    var u := float(q) / 8.0
                    leaf.append(p + along * (u - 0.5) * L * 2.0 + perp * sin(u * PI) * W)
                for q in range(8, -1, -1):
                    var u := float(q) / 8.0
                    leaf.append(p + along * (u - 0.5) * L * 2.0 - perp * sin(u * PI) * W)
                draw_colored_polygon(leaf, Color("f3c649").lerp(Color("b7822a"), absf(t) * 0.5))
                draw_polyline(leaf, Color("6a4210"), 1.2)

## Cartão do jogador (retrato, nome, liga e barra de PL) sobre o painel da arte do PC.
class ProfileCard extends Button:
    const REGION := Rect2(1225, 30, 415, 208)
    var hub
    var art: AtlasTexture
    func _init():
        focus_mode = Control.FOCUS_NONE
        size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
        for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
            add_theme_color_override(c, Color(0, 0, 0, 0))
        button_down.connect(func(): self_modulate = Color(1.2, 1.2, 1.05))
        button_up.connect(func(): self_modulate = Color.WHITE)
    func fit():
        var parent_w: float = get_parent().size.x if get_parent() is Control else size.x
        var w := minf(parent_w, 420.0)
        if w > 0.0: custom_minimum_size = Vector2(w, roundf(w * REGION.size.y / REGION.size.x))
    func _notification(what):
        if what == NOTIFICATION_RESIZED: fit.call_deferred()
    func _draw():
        if hub == null: return
        var k := size.x / REGION.size.x
        var o := REGION.position
        # Painel recortado com fundo transparente (sem sobras de céu/folhagem nos cantos).
        draw_texture_rect(CARD_ART, Rect2(Vector2.ZERO, size), false)
        var pr := Rect2((Vector2(1256, 65) - o) * k, Vector2(87, 94) * k)
        var av: Texture2D = hub.avatar_texture()
        if av != null:
            var ts := av.get_size()
            var sc := minf(pr.size.x / ts.x, pr.size.y / ts.y)
            var d := ts * sc
            draw_texture_rect(av, Rect2(pr.position + (pr.size - d) / 2.0, d), false)
        var font := get_theme_default_font()
        var data = hub.league_profile.data
        var league = hub.LeagueCatalog.entry(data.current_league, data)
        var fs := int(22 * k)
        while fs > 8 and font.get_string_size(hub.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 150 * k: fs -= 1
        draw_string_outline(font, (Vector2(1394, 80) - o) * k, hub.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
        draw_string(font, (Vector2(1394, 80) - o) * k, hub.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f4edda"))
        draw_string(font, (Vector2(1364, 106) - o) * k, "%s · %d / 100 PL" % [league.display_name, int(data.lp)], HORIZONTAL_ALIGNMENT_LEFT, 190 * k, int(15 * k), Color("f4ce7f"))
        var bar := Rect2((Vector2(1372, 118) - o) * k, Vector2(168 * clampf(float(data.lp) / 100.0, 0.0, 1.0), 6) * k)
        draw_rect(bar, Color("e9c46a"))
