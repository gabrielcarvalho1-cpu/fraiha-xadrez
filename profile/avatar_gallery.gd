extends GridContainer
## Galeria de progressão dos avatares (Perfil, PC e celular).
## Mostra TODOS os avatares da coleção (profile/avatar_catalog.gd): iniciais + recompensas da escada.
##   • conquistado  → colorido, moldura dourada viva, clicável (seleciona)
##   • bloqueado    → retrato em tons de cinza escurecido, cadeado, "BLOQUEADO · Derrote o BOT X"
##   • selecionado  → moldura esmeralda com brilho + selo "EM USO"
##   • sem arte ainda → silhueta + brasão da liga, "ARTE EM BREVE" (não selecionável)
## Desbloqueio vem de hub.bot_progress (derivado da escada; servidor é a autoridade para conta).
signal picked(id: String)       # (R32) não é mais emitido no clique: aplicar é pelo botão APLICAR AVATAR
signal inspected(id: String)    # clique em qualquer avatar (para a área de detalhe)

const Catalog = preload("res://profile/avatar_catalog.gd")
const ThemeCatalog = preload("res://cosmetics/theme_catalog.gd")
const Art = preload("res://monetization/premium_art.gd")
const GOLD := Color("ffd98a")
const CREAM := Color("f4ead2")
const MUTED := Color("9c9886")
const EMERALD := Color("49d17a")
const GRAY_SHADER := "shader_type canvas_item;\nuniform float amount = 1.0;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float l = dot(c.rgb, vec3(0.299,0.587,0.114)); vec3 g = vec3(l) * vec3(0.78,0.82,0.80) * 0.62; COLOR = vec4(mix(c.rgb, g, amount), c.a); }"

var hub
var card_size := Vector2(128, 166)
var cards := {}
var focus_id := ""   # R32: avatar em foco (tocado), ainda não aplicado
## R53 · cartões do celular no visual da referência (ui_kit/mobile/pf_mcard*.png: moldura por cima do retrato,
## nome e selo "Inicial / Conquistado / BLOQUEADO / EM USO" embaixo). Desligado = cartões de sempre (PC).
var ref_cards := false
const REF_CARD := Vector2(222, 296)
const REF_PORTRAIT := Rect2(12, 12, 198, 181)
static var _gray: Shader

func setup(p_hub, p_columns: int, p_card: Vector2):
    hub = p_hub
    columns = p_columns
    card_size = p_card
    add_theme_constant_override("h_separation", 10)
    add_theme_constant_override("v_separation", 10)
    refresh()

func refresh():
    for c in get_children():
        remove_child(c)
        c.queue_free()
    cards.clear()
    for e in Catalog.entries():
        var card := Card.new()
        card.gallery = self
        card.avatar = String(e.id)
        card.custom_minimum_size = card_size
        card.pressed.connect(_on_card.bind(String(e.id)))
        add_child(card)
        cards[String(e.id)] = card
    update_states()

func update_states():
    for id in cards: cards[id].queue_redraw()

func state_of(id: String) -> String:
    if hub == null: return "locked"
    if not Catalog.has_art(id): return "no_art_unlocked" if unlocked(id) else "locked"
    if not unlocked(id): return "locked"
    return "selected" if hub.avatar_id == id and hub.custom_avatar() == null else "unlocked"

func unlocked(id: String) -> bool:
    return hub == null or hub.avatar_unlocked(id)

func hint(id: String) -> String:
    if hub == null: return ""
    return String(hub.avatar_lock_hint(id))   # "Derrote o BOT X" | "Exclusivo do Pacote Fundador"

func count_unlocked() -> int:
    var n := 0
    for id in cards:
        if unlocked(id): n += 1
    return n

## R32: tocar num avatar só o coloca em foco (detalhe + botão APLICAR AVATAR); não troca o avatar.
func _on_card(id: String):
    focus_id = id
    update_states()
    inspected.emit(id)

static func gray_material() -> ShaderMaterial:
    if _gray == null:
        _gray = Shader.new()
        _gray.code = GRAY_SHADER
    var m := ShaderMaterial.new()
    m.shader = _gray
    return m

# ---------------------------------------------------------------- cartão
class Card extends Button:
    var gallery
    var avatar := ""
    var portrait: TextureRect
    var frame_art: NinePatchRect
    func _init():
        flat = true
        set_meta("no_club_frame", true)   # avatares de escolha não recebem a moldura do Club
        focus_mode = Control.FOCUS_ALL
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        clip_contents = false
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
    func _ready():
        portrait = TextureRect.new()
        portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
        portrait.clip_contents = true
        add_child(portrait)
        resized.connect(_layout)
        mouse_entered.connect(queue_redraw)
        mouse_exited.connect(queue_redraw)
        _layout()
    func _layout():
        if portrait == null: return
        if gallery != null and gallery.ref_cards:
            var k: Vector2 = size / gallery.REF_CARD
            portrait.position = gallery.REF_PORTRAIT.position * k
            portrait.size = gallery.REF_PORTRAIT.size * k
            _ref_nodes()
            ref_frame.size = size
            ref_name.position = Vector2(8, 196) * k
            ref_name.size = Vector2(206, 42) * k
            ref_sub.position = Vector2(26, 244) * k
            ref_sub.size = Vector2(170, 38) * k
            queue_redraw()
            return
        var side := minf(size.x - 16.0, size.y - 46.0)
        portrait.position = Vector2((size.x - side) / 2.0, 8)
        portrait.size = Vector2(side, side)
        queue_redraw()
    var ref_frame: TextureRect
    var ref_name: Label
    var ref_sub: Label
    func _ref_nodes():
        if ref_frame != null: return
        ref_frame = TextureRect.new()
        ref_frame.name = "RefCardFrame"
        ref_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ref_frame.stretch_mode = TextureRect.STRETCH_SCALE
        ref_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        ref_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(ref_frame)   # depois do retrato: a moldura (e os losangos dos cantos) ficam por cima
        for i in 2:
            var l := Label.new()
            l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            l.clip_text = true
            l.mouse_filter = Control.MOUSE_FILTER_IGNORE
            l.add_theme_font_override("font", preload("res://ui_kit/fonts/Alegreya-Bold.woff"))
            l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
            l.add_theme_constant_override("outline_size", 2)
            add_child(l)
            if i == 0: ref_name = l
            else: ref_sub = l
    func _draw_ref(st: String, e2: Dictionary):
        var k: float = size.x / gallery.REF_CARD.x
        var locked := st == "locked"
        ref_frame.texture = load("res://ui_kit/mobile/pf_mcard_locked.png" if locked else "res://ui_kit/mobile/pf_mcard.png")
        var focused: bool = gallery.focus_id == avatar
        ref_frame.modulate = Color(0.72, 1.3, 0.86) if st == "selected" else (Color(1.25, 1.18, 1.0) if (focused or is_hovered()) else Color.WHITE)
        var title := String(e2.get("name", avatar)).to_upper()
        var fs := _fit(ref_name.get_theme_font("font"), title, int(round(30 * k)), size.x - 14.0)
        if ref_name.text != title: ref_name.text = title
        ref_name.add_theme_font_size_override("font_size", maxi(7, fs))
        ref_name.add_theme_color_override("font_color", Color("efe6cf") if not locked else Color("c9c9c4"))
        var sub := "BLOQUEADO"
        match st:
            "selected": sub = "EM USO"
            "unlocked": sub = "Inicial" if String(e2.get("source", "")) == "initial" else "Conquistado"
            "no_art_unlocked": sub = "Arte em breve"
        if ref_sub.text != sub: ref_sub.text = sub
        ref_sub.add_theme_font_size_override("font_size", maxi(7, _fit(ref_sub.get_theme_font("font"), sub, int(round(28 * k)), ref_sub.size.x - 6.0)))
        ref_sub.add_theme_color_override("font_color", Color("f08a7c") if locked else (Color("c9ffd9") if st == "selected" else Color("efe6cf")))
        tooltip_text = _tip(st, e2)
    func _draw():
        if gallery == null or portrait == null: return
        var st: String = gallery.state_of(avatar)
        var has_art: bool = Catalog.has_art(avatar)
        var tex: Texture2D = gallery.hub.avatar_texture(avatar) if has_art else null
        portrait.texture = tex
        portrait.material = gallery.gray_material() if st == "locked" and tex != null else null
        if gallery.ref_cards:
            if ref_frame == null: _layout()
            if tex == null:
                # sem arte: silhueta + brasão da liga (mesmo desenho dos cartões do PC), por baixo da moldura
                var pr0 := Rect2(portrait.position, portrait.size)
                draw_rect(pr0, Color("0a120e"))
                var hc0 := Color("1f2a24") if st == "locked" else Color("2c3a30")
                draw_circle(pr0.position + pr0.size * Vector2(0.5, 0.42), pr0.size.x * 0.17, hc0)
                draw_colored_polygon(PackedVector2Array([pr0.position + pr0.size * Vector2(0.18, 1.0), pr0.position + pr0.size * Vector2(0.26, 0.70), pr0.position + pr0.size * Vector2(0.5, 0.62), pr0.position + pr0.size * Vector2(0.74, 0.70), pr0.position + pr0.size * Vector2(0.82, 1.0)]), hc0)
                var b0 := ThemeCatalog.badge_texture(String(Catalog.entry(avatar).get("league", "")))
                if b0 != null:
                    var bs0 := pr0.size.x * 0.38
                    draw_texture_rect(b0, Rect2(pr0.end - Vector2(bs0 + 4, bs0 + 4), Vector2(bs0, bs0)), false, Color(1, 1, 1, 0.45 if st == "locked" else 0.95))
            _draw_ref(st, Catalog.entry(avatar))
            return
        var lit := is_hovered() or has_focus()
        var r := Rect2(Vector2.ZERO, size)
        # base do cartão
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("10241a") if st != "locked" else Color("0c1511")
        sb.set_corner_radius_all(6)
        sb.set_border_width_all(3 if st == "selected" else 2)
        sb.border_color = {"selected": EMERALD, "unlocked": GOLD, "no_art_unlocked": GOLD.darkened(0.2), "locked": Color("3a4038")}[st]
        if lit and st != "locked": sb.border_color = sb.border_color.lightened(0.2)
        var focused: bool = gallery.focus_id == avatar
        if focused and st != "selected":
            sb.border_color = Color("fff0b8")
            sb.set_border_width_all(3)
        if st == "selected":
            sb.shadow_color = Color(0.3, 0.9, 0.5, 0.45)
            sb.shadow_size = 10
        elif lit:
            sb.shadow_color = Color(1.0, 0.85, 0.45, 0.30)
            sb.shadow_size = 6
        # R51 · moldura recortada da referência (escolhido / comum / bloqueado), quando o kit existe
        var art_name: String = "pf_card_sel" if st == "selected" else ("pf_card_locked" if st == "locked" else "pf_card")
        var ap := "res://ui_kit/pages/%s.png" % art_name
        if ResourceLoader.exists(ap):
            if frame_art == null:
                frame_art = NinePatchRect.new()
                frame_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
                for m in ["patch_margin_left", "patch_margin_right", "patch_margin_top", "patch_margin_bottom"]: frame_art.set(m, 14)
                frame_art.show_behind_parent = true
                add_child(frame_art)
                move_child(frame_art, 0)
            frame_art.texture = load(ap)
            frame_art.size = size
            frame_art.modulate = Color(1.2, 1.15, 1.0) if (lit or gallery.focus_id == avatar) else Color.WHITE
        else:
            draw_style_box(sb, r)
        var pr := Rect2(portrait.position, portrait.size)
        # sem arte: silhueta + brasão da liga
        if tex == null:
            draw_rect(pr, Color("0a120e"))
            var c := pr.position + pr.size * Vector2(0.5, 0.42)
            var hc := Color("1f2a24") if st == "locked" else Color("2c3a30")
            draw_circle(c, pr.size.x * 0.17, hc)
            draw_colored_polygon(PackedVector2Array([pr.position + pr.size * Vector2(0.18, 1.0), pr.position + pr.size * Vector2(0.26, 0.70), pr.position + pr.size * Vector2(0.5, 0.62), pr.position + pr.size * Vector2(0.74, 0.70), pr.position + pr.size * Vector2(0.82, 1.0)]), hc)
            var e: Dictionary = Catalog.entry(avatar)
            var badge := ThemeCatalog.badge_texture(String(e.get("league", "")))
            if badge != null:
                var bs := pr.size.x * 0.38
                draw_texture_rect(badge, Rect2(pr.end - Vector2(bs + 4, bs + 4), Vector2(bs, bs)), false, Color(1, 1, 1, 0.45 if st == "locked" else 0.95))
            var f := get_theme_default_font()
            # canto inferior esquerdo (o cadeado fica em cima à direita e o brasão embaixo à direita)
            draw_string(f, pr.position + Vector2(6, pr.size.y - 20), "ARTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
            draw_string(f, pr.position + Vector2(6, pr.size.y - 8), "EM BREVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.5))
        # moldura do retrato
        draw_rect(pr.grow(1), Color("5a4520") if st == "locked" else Color("d9b45e"), false, 2.0)
        # cadeado
        if st == "locked":
            var lc := pr.position + Vector2(pr.size.x - 16, 16)
            draw_circle(lc, 13, Color(0, 0, 0, 0.7))
            draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Color("e6d6a8"), 2.0)
            draw_rect(Rect2(lc + Vector2(-6, -2), Vector2(12, 9)), Color("e6d6a8"))
        # selo EM USO
        if st == "selected" and frame_art == null:
            var f2 := get_theme_default_font()
            var tag := Rect2(pr.position + Vector2(pr.size.x / 2.0 - 30, pr.size.y - 16), Vector2(60, 18))
            draw_rect(tag, Color("163b25"))
            draw_rect(tag, EMERALD, false, 1.5)
            draw_string(f2, tag.position + Vector2(0, 13), "EM USO", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 11, Color("c9ffd9"))
        # legenda
        var font: Font = preload("res://ui_kit/fonts/Alegreya-Bold.woff") if frame_art != null else get_theme_default_font()
        var name_col := GOLD if st in ["unlocked", "selected"] else (CREAM if st == "no_art_unlocked" else MUTED)
        var e2: Dictionary = Catalog.entry(avatar)
        var y := pr.end.y + 16
        var title := String(e2.get("name", avatar)).to_upper()
        var fs := _fit(font, title, 15 if frame_art != null else 13, size.x - 8)
        var cut := title.rfind(" ")
        if fs < 11 and cut > 0 and size.y - pr.end.y >= 50.0:
            # nome comprido em cartão estreito (celular): duas linhas em vez de cortar o texto
            var l1 := title.left(cut)
            var l2 := title.substr(cut + 1)
            var f2s := mini(_fit(font, l1, 12, size.x - 8), _fit(font, l2, 12, size.x - 8))
            draw_string(font, Vector2(4, y - 2), l1, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, f2s, name_col)
            draw_string(font, Vector2(4, y + 11), l2, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, f2s, name_col)
            y += 12
        else:
            draw_string(font, Vector2(4, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, fs, name_col)
        var sub := ""
        match st:
            "locked": sub = "BLOQUEADO"
            "selected": sub = "EM USO" if frame_art != null else "SELECIONADO"
            "unlocked": sub = "Inicial" if String(e2.get("source", "")) == "initial" else "Conquistado"
            "no_art_unlocked": sub = "Conquistado · arte em breve"
        var sub_col: Color = Color("e89a7a") if st == "locked" else (EMERALD if st == "selected" else MUTED)
        if frame_art != null and st == "selected": sub_col = Color("f4fff6")
        elif frame_art != null and st != "locked": sub_col = Color("ece3cc")
        draw_string(font, Vector2(4, y + 16), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 13 if frame_art != null else 11, sub_col)
        tooltip_text = _tip(st, e2)
    func _tip(st: String, e: Dictionary) -> String:
        if st == "locked": return "BLOQUEADO · " + gallery.hint(avatar)
        if st == "no_art_unlocked": return "Conquistado · a arte deste avatar ainda será adicionada"
        return String(e.get("name", avatar))
    static func _fit(font: Font, text: String, fs: int, room: float) -> int:
        var s := fs
        while s > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > room: s -= 1
        return s
