extends RefCounted
## R31 · PERSONALIZAÇÃO — página do FRAIHA PREMIUM onde o jogador escolhe:
##   ÍCONE (selo ao lado do nome) · TÍTULO · MOLDURA · UNIVERSO (cenário + tabuleiro) · PEÇAS · LABORATÓRIO.
## Itens bloqueados aparecem em cinza com o requisito. Só aparência: nada altera PL, matchmaking,
## tempo, regras ou resultado. A escolha é salva no aparelho e enviada à conta (acct_set_cosmetics).
const Art := preload("res://monetization/premium_art.gd")
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const ThemeCatalog := preload("res://cosmetics/theme_catalog.gd")
const ClubFrame := preload("res://monetization/club_frame.gd")

const UNIVERSES := ["wood", "club", "fundador"]

static func theme_manager(hub):
    var mh = hub.main_hub
    if mh == null: return null
    var st = mh.get_parent()
    return st.get("theme_manager") if st != null else null

static func build(hub, parent: VBoxContainer):
    var mh = hub.main_hub
    var head := Art.Frame.new("founder", int(24 * hub.k))
    head.name = "PersonalizeHero"
    parent.add_child(head)
    var hv := VBoxContainer.new()
    hv.add_theme_constant_override("separation", 6)
    head.add_child(hv)
    var t := Art.label(hv, "PERSONALIZAÇÃO", hub.fs(30 if hub.narrow else 44), Art.GOLD, Art.FONT_BOLD)
    t.add_theme_constant_override("outline_size", 8)
    t.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0, 0.95))
    Art.label(hv, "Escolha como o reino vê você: ícone, título, moldura, universo e peças.", hub.fs(19), Art.CREAM)
    var who := "Fundador + Club" if mh != null and mh.is_founder() and mh.club_active() else ("Fundador" if mh != null and mh.is_founder() else ("Club FRAIHA" if mh != null and mh.club_active() else "Jogador"))
    hv.add_child(Art.Stamp.new("SEUS DIREITOS: " + who.to_upper(), "ok" if who != "Jogador" else "info", 14))
    if mh == null:
        Art.label(hv, "Personalização indisponível agora.", hub.fs(16), Art.MUTED)
        return
    _badges(hub, parent, mh)
    _titles(hub, parent, mh)
    _frames(hub, parent, mh)
    _universes(hub, parent, mh)
    _pieces(hub, parent, mh)
    _lab(hub, parent, mh)
    parent.add_child(hub.fair_play_note())

## Cartão de opção: prévia + nome + estado. Bloqueado: cinza, não seleciona.
static func option(hub, parent: Node, node_name: String, preview: Control, title: String, selected: bool, locked: bool, hint: String, on_pick: Callable) -> Button:
    var b := Button.new()
    b.name = node_name
    b.focus_mode = Control.FOCUS_ALL
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    var w: float = 150.0 * maxf(hub.k, 0.78)
    b.custom_minimum_size = Vector2(w, w * 1.3)
    for st_name in ["normal", "hover", "pressed", "focus", "disabled"]:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.03, 0.10, 0.06, 0.92) if not selected else Color(0.10, 0.20, 0.08, 0.96)
        sb.border_color = Color("f6d27a") if selected else (Color("f0c45c") if st_name in ["hover", "focus"] else Color(0.79, 0.6, 0.27, 0.55))
        sb.set_border_width_all(3 if selected else 2)
        sb.set_corner_radius_all(6)
        b.add_theme_stylebox_override(st_name, sb)
    b.tooltip_text = title + ("  ·  BLOQUEADO · " + hint if locked else "")
    b.set_meta("locked", locked)
    b.set_meta("selected", selected)
    var v := VBoxContainer.new()
    v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    v.offset_left = 8
    v.offset_right = -8
    v.offset_top = 8
    v.offset_bottom = -6
    v.add_theme_constant_override("separation", 4)
    v.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(v)
    preview.custom_minimum_size = Vector2(w - 16.0, w * 0.66)
    preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if locked: preview.modulate = Color(0.42, 0.42, 0.42, 0.9)
    v.add_child(preview)
    var nl := Art.label(v, title, hub.fs(14), Art.GOLD if not locked else Art.MUTED, Art.FONT_SEMI, HORIZONTAL_ALIGNMENT_CENTER)
    nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var state := "EM USO" if selected else ("BLOQUEADO" if locked else "ESCOLHER")
    var sl := Art.label(v, state, hub.fs(12), Color("8fe08a") if selected else (Color("e89a7a") if locked else Art.CREAM), null, HORIZONTAL_ALIGNMENT_CENTER)
    sl.name = "State"
    sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if locked and not hint.is_empty():
        var hl := Art.label(v, short_hint(hint), hub.fs(11), Art.MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
        hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.pressed.connect(func():
        if locked:
            hub.open_confirm("BLOQUEADO", title + "\n\n" + hint + ".", "", "ENTENDI", Callable())
            return
        on_pick.call()
        hub._rebuild())
    parent.add_child(b)
    return b

static func short_hint(hint: String) -> String:
    if "ou Fundador" in hint: return "Club ou Fundador"
    if "Fundador" in hint: return "Pacote Fundador"
    if "Club" in hint: return "Club FRAIHA"
    if "Ranked" in hint: return "Liga do Ranked"
    return hint

static func _flow(parent: VBoxContainer) -> HFlowContainer:
    var f := HFlowContainer.new()
    f.add_theme_constant_override("h_separation", 12)
    f.add_theme_constant_override("v_separation", 12)
    parent.add_child(f)
    return f

static func _tex(texture: Texture2D) -> TextureRect:
    var r := TextureRect.new()
    r.texture = texture
    r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    return r

static func _glyph(kind: String, col := Art.GOLD) -> Control:
    var c := CenterContainer.new()
    c.add_child(Art.Glyph.new(kind, 56, col, true))
    return c

static func _badges(hub, parent: VBoxContainer, mh):
    var v: VBoxContainer = hub.section(parent, "SEU ÍCONE", "seal", "founder")
    v.get_parent().name = "PersonalizeBadges"
    Art.label(v, "O selo aparece ao lado do seu nome na Home, no Perfil e para os outros jogadores (Amigos, chat e partidas).", hub.fs(16), Art.MUTED)
    var row := _flow(v)
    var pref: String = mh.cosmetic_pref("badge")
    option(hub, row, "Badge_auto", _glyph("star"), "AUTOMÁTICO", pref == "auto", false, "", func(): mh.set_cosmetic("badge", "auto"))
    for id in Cosmetics.BADGES:
        var bid: String = id
        var locked := not Cosmetics.allowed("badge", bid, mh.is_founder(), mh.club_active())
        var pv: Control = _glyph("pawn", Art.MUTED) if bid.is_empty() else _tex(Cosmetics.badge_texture(bid, false))
        option(hub, row, "Badge_" + (bid if not bid.is_empty() else "none"), pv, String(Cosmetics.BADGE_NAMES[bid]).to_upper(), pref == bid, locked, Cosmetics.lock_hint("badge", bid), func(): mh.set_cosmetic("badge", bid))

static func _titles(hub, parent: VBoxContainer, mh):
    var v: VBoxContainer = hub.section(parent, "TÍTULO", "scroll")
    v.get_parent().name = "PersonalizeTitles"
    Art.label(v, "Exibido no seu Perfil e no seu cartão para os outros jogadores.", hub.fs(16), Art.MUTED)
    var row := _flow(v)
    var pref: String = mh.cosmetic_pref("title")
    option(hub, row, "Title_auto", _glyph("star"), "AUTOMÁTICO", pref == "auto", false, "", func(): mh.set_cosmetic("title", "auto"))
    for id in Cosmetics.TITLES:
        var tid: String = id
        var locked := not Cosmetics.allowed("title", tid, mh.is_founder(), mh.club_active())
        var kind := "pawn" if tid.is_empty() else ("crown" if tid == "fundador" else "book")
        option(hub, row, "Title_" + (tid if not tid.is_empty() else "none"), _glyph(kind, Art.MUTED if tid.is_empty() else Art.GOLD), (Cosmetics.title_text(tid) if not tid.is_empty() else "Nenhum").to_upper(), pref == tid, locked, Cosmetics.lock_hint("title", tid), func(): mh.set_cosmetic("title", tid))

static func _frames(hub, parent: VBoxContainer, mh):
    var v: VBoxContainer = hub.section(parent, "MOLDURA DO PERFIL", "frame")
    v.get_parent().name = "PersonalizeFrames"
    var row := _flow(v)
    var pref: String = mh.cosmetic_pref("frame")
    option(hub, row, "Frame_auto", _glyph("star"), "AUTOMÁTICA", pref == "auto", false, "", func(): mh.set_cosmetic("frame", "auto"))
    for id in Cosmetics.FRAMES:
        var fid: String = id
        var locked := not Cosmetics.allowed("frame", fid, mh.is_founder(), mh.club_active())
        option(hub, row, "Frame_" + fid, _frame_preview(mh, fid), String(Cosmetics.FRAME_NAMES[fid]).to_upper(), pref == fid, locked, Cosmetics.lock_hint("frame", fid), func(): mh.set_cosmetic("frame", fid))

static func _frame_preview(mh, fid: String) -> Control:
    var holder := CenterContainer.new()
    var pic := TextureRect.new()
    pic.texture = mh.avatar_texture()
    pic.custom_minimum_size = Vector2(70, 70)
    pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    holder.add_child(pic)
    if fid == "liga":
        var lf = preload("res://profile/league_frame.gd").new()
        lf.league_id = mh.league_profile.data.current_league
        pic.add_child(lf)
    else:
        var cf = ClubFrame.new()
        cf.style = fid
        cf.compact = false
        pic.add_child(cf)
    return holder

static func _universes(hub, parent: VBoxContainer, mh):
    var tm = theme_manager(hub)
    var v: VBoxContainer = hub.section(parent, "UNIVERSO (CENÁRIO + TABULEIRO)", "castle", "club")
    v.get_parent().name = "PersonalizeUniverses"
    Art.label(v, "Universos exclusivos ficam fora das ligas. Os cenários das ligas continuam na página SISTEMA DE LIGAS.", hub.fs(16), Art.MUTED)
    var row := _flow(v)
    for id in UNIVERSES:
        var uid: String = id
        var data := ThemeCatalog.get_theme(uid)
        var locked: bool = tm == null or not tm.is_unlocked(uid)
        var hint := "Exclusivo do Pacote Fundador" if ThemeCatalog.exclusive_of(uid) == "founder" else ("Exclusivo do Club FRAIHA" if ThemeCatalog.exclusive_of(uid) == "club" else "")
        var thumb := _tex(ThemeCatalog.texture(String(data.arena_path) if uid != "wood" else "res://ui_v022/assets/home_forest_v2.png"))
        thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        var title := "FLORESTA (MADEIRA)" if uid == "wood" else String(data.name).to_upper()
        option(hub, row, "Universe_" + uid, thumb, title, tm != null and tm.active_theme == uid, locked, hint, func(): if tm != null: tm.choose_theme(uid, true))
    if tm != null and not (tm.active_theme in UNIVERSES):
        Art.label(v, "Em uso agora: universo da liga %s." % String(ThemeCatalog.get_theme(tm.active_theme).name), hub.fs(15), Art.CREAM)

## Peças: "acompanhar o cenário", clássicas, exclusivas e (Club/Fundador) qualquer conjunto de liga já
## conquistado combinado com qualquer cenário — a "Personalização premium".
static func _pieces(hub, parent: VBoxContainer, mh):
    var tm = theme_manager(hub)
    var v: VBoxContainer = hub.section(parent, "CONJUNTO DE PEÇAS", "pawn")
    v.get_parent().name = "PersonalizePieces"
    Art.label(v, "Fundador e Club podem combinar qualquer conjunto já conquistado com qualquer cenário.", hub.fs(16), Art.MUTED)
    var row := _flow(v)
    if tm == null: return
    var saved: String = tm.saved_piece_set
    option(hub, row, "Pieces_auto", _glyph("castle"), "ACOMPANHAR O CENÁRIO", saved.is_empty(), false, "", func(): tm.choose_piece_set(""))
    var ids: Array = ["classic", "fundador", "club"]
    for id in ThemeCatalog.THEME_DATA:
        if not (id in ids): ids.append(id)
    for id in ids:
        var pid: String = id
        var locked := false
        var hint := ""
        if pid != "classic":
            var ex := ThemeCatalog.exclusive_of(pid)
            if not tm.is_unlocked(pid):
                locked = true
                hint = "Exclusivo do Pacote Fundador" if ex == "founder" else ("Exclusivo do Club FRAIHA" if ex == "club" else "Conquiste a liga no Ranked")
            elif ex.is_empty() and pid != tm.active_theme and not mh.early_access():
                locked = true
                hint = "Club ou Fundador: combine peças e cenários"
        var title := "CLÁSSICAS" if pid == "classic" else String(ThemeCatalog.get_theme(pid).name).to_upper()
        # Prévia só dos conjuntos liberados: recortar o atlas custa caro (Web) e o bloqueado nem é usável.
        var pv: Control = _pieces_preview(pid) if not locked or not ThemeCatalog.exclusive_of(pid).is_empty() else _glyph("lock", Art.MUTED)
        option(hub, row, "Pieces_" + pid, pv, title, saved == pid, locked, hint, func(): tm.choose_piece_set(pid))

static func _pieces_preview(id: String) -> Control:
    var h := HBoxContainer.new()
    h.alignment = BoxContainer.ALIGNMENT_CENTER
    h.add_theme_constant_override("separation", 0)
    var tex: Dictionary = ThemeCatalog.piece_textures(id)
    for code in ["wK", "wQ", "bN"]:
        var r := _tex(tex.get(code))
        r.custom_minimum_size = Vector2(40, 60)
        r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        r.mouse_filter = Control.MOUSE_FILTER_IGNORE
        h.add_child(r)
    return h

static func _lab(hub, parent: VBoxContainer, mh):
    var v: VBoxContainer = hub.section(parent, "LABORATÓRIO · ACESSO ANTECIPADO", "hourglass", "founder")
    v.get_parent().name = "PersonalizeLab"
    Art.label(v, "Novidades em teste chegam aqui antes do lançamento geral (Fundador e Club). Nada muda as regras nem dá vantagem.", hub.fs(16), Art.MUTED)
    var on: bool = mh.lab_coordinates_on()
    var b := Art.Cta.new("COORDENADAS NO TABULEIRO: " + ("LIGADAS" if on else "DESLIGADAS"), "gold" if mh.early_access() else "dark", 52 * maxf(hub.k, 0.85), int(17 * maxf(hub.k, 0.85)))
    b.name = "LabCoordinates"
    b.pressed.connect(func():
        if not mh.early_access():
            hub.open_confirm("ACESSO ANTECIPADO", "O Laboratório é um benefício do Pacote Fundador e do Club FRAIHA.", "", "ENTENDI", Callable())
            return
        mh.set_lab_coordinates(not mh.lab_coords)
        hub._rebuild())
    v.add_child(b)
    if not mh.early_access(): v.add_child(Art.Stamp.new("EXCLUSIVO FUNDADOR / CLUB", "soon", 13))
