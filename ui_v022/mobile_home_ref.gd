extends Control
## R47 · Home do CELULAR em pé = arte de REFERÊNCIA do dono (home_mobile_v8.png, 854 x 1842 = 427 x 921 CSS
## a 2x; tools/home_ref_v8.py). A arte é o fundo inteiro (logo, cartão, menu com pilares e tochas, cena e
## barra de baixo); por cima só entram áreas de toque e o que é VIVO: textos dos botões (fonte do jogo),
## placa CLUB (ativo/inativo), som, retrato/nome/liga/PL do jogador, insígnia de outras ligas.
## Ações: as MESMAS da Home (cada botão chama o botão correspondente da Home do PC).
## Telas de outra proporção: a arte encaixa pela largura (corte de no máx. ~3% de cada lado em telas mais
## estreitas); a barra de baixo fica sempre colada no fim da tela — em telas mais baixas ela cobre parte da
## cena (gata/mochila), em telas mais altas o chão da cena se estende até ela.
const ART := preload("res://ui_v022/assets/home_mobile_v8.png")
const DESIGN := Vector2(854, 1842)
const NAV_TOP := 1655.0        # topo do recorte da barra (inclui a pedra azul de cima)
const NAV_FADE := 34.0         # fileiras de cima do recorte que se misturam com a cena
const MIN_H := 1560.0          # altura mínima da composição (menu inteiro + barra sem encostar na moldura), px da arte
const GROUND := Rect2(0, 1600, 854, 90)   # chão da cena, estendido quando a tela é mais alta
const RefText := preload("res://ui_v022/ref_text.gd")
const GLOW := preload("res://ui_v022/home_button_glow.gdshader")
const ThemeCatalog := preload("res://cosmetics/theme_catalog.gd")

## [título do botão da Home, retângulo do botão na arte, título (x, topo, largura, maiúsculas), fonte, subtítulo, (x, topo, largura)]
const MENU := [
    ["JOGAR RANQUEADO", Rect2(140, 738, 575, 120), "JOGAR RANQUEADO", Rect2(279, 765, 346, 29), "default", "Compita e conquiste seu lugar", Rect2(281, 805, 341, 0)],
    ["JOGAR ONLINE", Rect2(142, 877, 573, 108), "JOGAR ONLINE", Rect2(280, 902, 241, 25), "default", "Partida casual · fila automática", Rect2(282, 939, 325, 0)],
    ["JOGAR CONTRA O COMPUTADOR", Rect2(140, 1002, 575, 105), "CONTRA O COMPUTADOR", Rect2(283, 1025, 354, 24), "default", "Treine e evolua seu jogo", Rect2(282, 1059, 268, 0)],
    ["MARCHA REAL", Rect2(138, 1160, 282, 75), "MARCHA REAL", Rect2(217, 1188, 112, 17), "squeeze", "", Rect2()],
    ["XEQUE", Rect2(433, 1160, 282, 75), "XEQUE", Rect2(542, 1188, 60, 17), "squeeze", "", Rect2()],
    ["LIGAS E RANKING", Rect2(138, 1250, 282, 75), "LIGAS E RANKING", Rect2(229, 1276, 161, 19), "squeeze", "", Rect2()],
    ["HISTÓRICO DE PARTIDAS", Rect2(433, 1250, 282, 75), "HISTÓRICO", Rect2(544, 1276, 109, 19), "squeeze", "", Rect2()],
]
## barra de baixo: [id, retângulo, texto, (x, topo, largura, maiúsculas)]
const NAV := [
    ["inicio", Rect2(22, 1690, 192, 130), "INÍCIO", Rect2(90, 1778, 63, 17)],
    ["amigos", Rect2(214, 1690, 211, 130), "AMIGOS", Rect2(279, 1776, 82, 19)],
    ["conta", Rect2(425, 1690, 213, 130), "MINHA CONTA", Rect2(457, 1780, 143, 16)],
    ["mais", Rect2(638, 1690, 197, 130), "MAIS", Rect2(709, 1779, 48, 16)],
]
const CLUB_RECT := Rect2(25, 45, 355, 73)
const SOUND_RECT := Rect2(730, 45, 82, 75)
const CARD_RECT := Rect2(108, 495, 637, 173)
const PORTRAIT := Rect2(150, 524, 116, 118)
const SHIELD := Rect2(620, 515, 90, 133)
const BAR := Rect2(300, 604, 291, 14)

var hub
var mobile                     # ui_v022/mobile_hub.gd (dono da página e dos botões de som/Club)
var backdrop: TextureRect
var top: Control               # px da arte, linhas 0 → NAV_TOP
var ground: TextureRect
var nav: Control               # px da arte, a barra (linhas NAV_TOP → fim)
var club_entry
var sound_button: Button
var portrait: TextureRect
var club_host: Control
var name_text
var league_text
var bar_fill: ColorRect
var badge: TextureRect
var badge_plate: Panel
var seal: TextureRect
var buttons := {}              # título → Button (área de toque)
var _shown := ""

func setup(owner_hub, owner_mobile):
    hub = owner_hub
    mobile = owner_mobile
    name = "MobileHomeRef"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    backdrop = TextureRect.new()
    backdrop.name = "RefBackdrop"
    backdrop.texture = _region(Rect2(0, 0, 854, 1655))
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.modulate = Color(0.42, 0.45, 0.42)   # sobras (telas largas): a própria cena, escurecida
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)
    top = Control.new()
    top.name = "RefTop"
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(top)
    var art := TextureRect.new()
    art.name = "RefArtTop"
    art.texture = _region(Rect2(0, 0, 854, NAV_TOP))
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE
    art.size = Vector2(854, NAV_TOP)
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(art)
    ground = TextureRect.new()
    ground.name = "RefGround"
    ground.texture = _region(GROUND)
    ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ground.stretch_mode = TextureRect.STRETCH_SCALE
    ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(ground)
    nav = Control.new()
    nav.name = "RefNav"
    nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(nav)
    var nav_art := TextureRect.new()
    nav_art.name = "RefArtNav"
    nav_art.texture = _region(Rect2(0, NAV_TOP, 854, DESIGN.y - NAV_TOP))
    nav_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    nav_art.stretch_mode = TextureRect.STRETCH_SCALE
    nav_art.position = Vector2(0, NAV_TOP)
    nav_art.size = Vector2(854, DESIGN.y - NAV_TOP)
    nav_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var fade := ShaderMaterial.new()
    fade.shader = Shader.new()
    fade.shader.code = "shader_type canvas_item;\nuniform float edge;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); COLOR = vec4(c.rgb, c.a * smoothstep(0.0, edge, UV.y)); }"
    fade.set_shader_parameter("edge", NAV_FADE / (DESIGN.y - NAV_TOP))
    nav_art.material = fade
    nav.add_child(nav_art)
    _build_top()
    _build_nav()
    refresh()

func _region(r: Rect2) -> AtlasTexture:
    var t := AtlasTexture.new()
    t.atlas = ART
    t.region = r
    t.filter_clip = true
    return t

## Área de toque transparente sobre o botão desenhado; ao tocar/passar, o próprio botão da arte reluz.
func _hit(parent: Control, rect: Rect2, caption: String, action: Callable) -> Button:
    var b := Button.new()
    b.text = caption
    b.name = "Ref_" + caption.replace(" ", "_")
    for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
    for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
        b.add_theme_color_override(c, Color(0, 0, 0, 0))
    b.focus_mode = Control.FOCUS_NONE
    b.position = rect.position
    b.size = rect.size
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    parent.add_child(b)
    var glow := TextureRect.new()
    glow.name = "RefHover"
    glow.texture = _region(rect.grow(3))
    glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    glow.stretch_mode = TextureRect.STRETCH_SCALE
    glow.position = Vector2(-3, -3)
    glow.size = rect.size + Vector2(6, 6)
    var m := ShaderMaterial.new()
    m.shader = GLOW
    glow.material = m
    glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    glow.hide()
    b.add_child(glow)
    b.button_down.connect(func(): glow.show())
    b.button_up.connect(func(): glow.hide())
    b.mouse_entered.connect(func(): if not DisplayServer.is_touchscreen_available(): glow.show())
    b.mouse_exited.connect(func(): glow.hide())
    b.pressed.connect(action)
    b.pressed.connect(func():
        var audio = hub.get_parent().get_node_or_null("GameAudio") if hub.get_parent() != null else null
        if audio != null: audio.play_cue("ui"))
    return b

func _source(title: String) -> TextureButton:
    for b in hub.menu_buttons:
        if hub.title_of(b) == title: return b
    return null

func _build_top():
    # placa CLUB FRAIHA (a placa e a coroa são da arte; o jogo escreve o estado)
    club_entry = load("res://monetization/club_home_entry.gd").new()
    club_entry.name = "ClubHomeEntryMobile"
    club_entry.over_art = true
    club_entry.art_sub = false
    club_entry.art_tx = 106.0
    club_entry.art_title_y = 49.0
    club_entry.art_title_size = 30
    club_entry.art_title_room = 175.0
    club_entry.art_seal = Vector2(318, 37)
    club_entry.position = CLUB_RECT.position
    club_entry.size = CLUB_RECT.size
    club_entry.pressed.connect(func(): hub.open_club())
    top.add_child(club_entry)
    sound_button = preload("res://ui_v022/hud_button.gd").make("sound_on")
    sound_button.name = "SoundButtonMobile"
    sound_button.position = SOUND_RECT.position
    sound_button.size = SOUND_RECT.size
    sound_button.set_over_art(true)
    sound_button.pressed.connect(func(): hub.toggle_sound())
    top.add_child(sound_button)
    # cartão do jogador (toque abre o Perfil)
    var card := _hit(top, CARD_RECT, "PERFIL", func(): hub.show_page("profile"))
    card.name = "RefProfileCard"
    var clip := Control.new()
    clip.name = "RefPortraitClip"
    clip.clip_contents = true
    clip.position = PORTRAIT.position
    clip.size = PORTRAIT.size
    clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(clip)
    portrait = TextureRect.new()
    portrait.name = "RefPortrait"
    portrait.set_meta("no_league_frame", true)
    portrait.set_meta("no_club_frame", true)
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.size = PORTRAIT.size
    portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip.add_child(portrait)
    club_host = Control.new()
    club_host.name = "RefPortraitClubHost"
    club_host.position = PORTRAIT.position - Vector2(5, 5)
    club_host.size = PORTRAIT.size + Vector2(10, 10)
    club_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(club_host)
    name_text = RefText.make("", Rect2(346, 524, 254, 24), "default", Color("f6f1e4"))
    name_text.name = "RefProfileName"
    top.add_child(name_text)
    seal = TextureRect.new()
    seal.name = "RefSeal"
    seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    seal.size = Vector2(44, 44)
    seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(seal)
    league_text = RefText.make("", Rect2(298, 565, 300, 19), "default", Color("f2cd72"))
    league_text.name = "RefLeague"
    league_text.outline_size = 2
    top.add_child(league_text)
    bar_fill = ColorRect.new()
    bar_fill.name = "RefBarFill"
    bar_fill.color = Color("e9c46a")
    bar_fill.position = BAR.position
    bar_fill.size = Vector2(0, BAR.size.y)
    bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(bar_fill)
    badge_plate = Panel.new()
    var plate := StyleBoxFlat.new()
    plate.bg_color = Color(0.0, 0.13, 0.07)
    plate.set_corner_radius_all(8)
    badge_plate.add_theme_stylebox_override("panel", plate)
    badge_plate.position = SHIELD.position
    badge_plate.size = SHIELD.size
    badge_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(badge_plate)
    badge = TextureRect.new()
    badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    badge.position = SHIELD.position + Vector2(2, 4)
    badge.size = SHIELD.size - Vector2(4, 8)
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(badge)
    # botões do menu
    for row in MENU:
        var src := _source(row[0])
        if src == null: continue
        var b := _hit(top, row[1], row[0], func(): src.pressed.emit())
        buttons[row[0]] = b
        var o: Vector2 = row[1].position
        var tr: Rect2 = row[3]
        var ranked: bool = row[0] == "JOGAR RANQUEADO"
        var t = RefText.make(row[2], Rect2(tr.position - o, tr.size), row[4], Color("ffd36e") if ranked else Color("f6f1e4"))
        t.name = "RefTitle"
        t.bold = 0 if row[4] == "squeeze" else 1
        t.outline_size = 4
        b.add_child(t)
        if not String(row[5]).is_empty():
            var sr: Rect2 = row[6]
            var st = RefText.make(row[5], Rect2(sr.position - o, Vector2(sr.size.x, 0)), "default", Color("f6f2e8"))
            st.name = "RefSubtitle"
            st.outline_size = 3
            b.add_child(st)

func _build_nav():
    for item in NAV:
        var id: String = item[0]
        var action: Callable
        match id:
            "inicio": action = func(): pass   # já está no Início
            "amigos":
                var src := _source("AMIGOS")
                action = func(): if src != null: src.pressed.emit()
            "conta": action = func(): hub.account_requested.emit()
            "mais": action = func(): mobile.show_page("mais")
        var b := _hit(nav, item[1], item[2], action)
        b.name = "RefNav_" + id
        buttons[item[2]] = b
        var o: Vector2 = item[1].position
        var tr: Rect2 = item[3]
        var t = RefText.make(item[2], Rect2(tr.position - o, tr.size), "default", Color("ffd84e") if id == "inicio" else Color("f6f1e4"))
        t.name = "RefTitle"
        t.bold = 1
        t.outline_size = 3
        b.add_child(t)

## Encaixe na tela: `box` = onde a composição cabe; `full` = a tela inteira (fundo), ambos nas
## coordenadas do pai (a Home do celular).
func layout(box: Rect2, full: Rect2):
    position = box.position
    size = box.size
    var w := box.size.x
    var h := box.size.y
    var k := maxf(w / DESIGN.x, minf(h / DESIGN.y, w * 1.06 / DESIGN.x))
    if k * MIN_H > h: k = h / MIN_H
    var x0 := (w - DESIGN.x * k) / 2.0
    backdrop.position = full.position - box.position
    backdrop.size = full.size
    top.scale = Vector2.ONE * k
    top.position = Vector2(x0, 0)
    var nav_y := h - (DESIGN.y - NAV_TOP) * k     # topo do recorte da barra, colado no fim da tela
    nav.scale = Vector2.ONE * k
    nav.position = Vector2(x0, nav_y - NAV_TOP * k)
    var gap_from := GROUND.position.y * k
    var gap_to := nav_y + NAV_FADE * k
    ground.visible = gap_to > NAV_TOP * k + 0.5
    ground.position = Vector2(x0, gap_from)
    ground.size = Vector2(DESIGN.x * k, maxf(0.0, gap_to - gap_from))

func refresh():
    if hub == null: return
    var pname := String(hub.player_name)
    if name_text.text != pname: name_text.set_text(pname)
    var data = hub.league_profile.data
    var league = hub.LeagueCatalog.entry(data.current_league, data)
    var ltxt := "%s · %d / 100 PL" % [league.display_name, int(data.lp)]
    if league_text.text != ltxt: league_text.set_text(ltxt)
    bar_fill.size.x = BAR.size.x * clampf(float(data.lp) / 100.0, 0.0, 1.0)
    portrait.texture = hub.avatar_texture()
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if hub.avatar_id == "warrior" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
    hub.attach_club_frame(club_host)
    var league_id := String(data.current_league)
    var madeira := league_id in ["madeira", "wood"]
    badge.texture = null if madeira else ThemeCatalog.badge_texture(league_id)
    badge.visible = not madeira
    badge_plate.visible = not madeira
    var st: Texture2D = hub.current_badge_texture()
    seal.texture = st
    seal.visible = st != null
    if st != null:
        var nw: float = name_text.ink_width()
        seal.position = name_text.position + Vector2(nw + 10.0, -9.0)
    club_entry.set_active(hub.entitlements != null and hub.entitlements.club_active())
    sound_button.glyph = "sound_off" if hub.sound_muted else "sound_on"
    sound_button.queue_redraw()

func _process(_delta):
    # nome/liga podem mudar fora da Home (conta, Ranked): confere barato enquanto aparece
    if is_visible_in_tree() and hub != null:
        var key := "%s|%s|%s|%s" % [hub.player_name, hub.league_profile.data.current_league, hub.league_profile.data.lp, hub.avatar_id]
        if key != _shown:
            _shown = key
            refresh()
