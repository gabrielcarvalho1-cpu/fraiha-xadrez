extends Control
## R47 · Home do CELULAR em pé = arte de REFERÊNCIA do dono (home_mobile_v8.png, 854 x 1842 = 427 x 921 CSS
## a 2x; tools/home_ref_v8.py). A arte é o fundo inteiro (logo, cartão, menu com pilares e tochas, cena e
## barra de baixo); por cima só entram áreas de toque e o que é VIVO: textos dos botões (fonte do jogo),
## placa CLUB (ativo/inativo), som, retrato/nome/liga/PL do jogador, insígnia de outras ligas.
## Ações: as MESMAS da Home (cada botão chama o botão correspondente da Home do PC).
## Telas de outra proporção: a arte encaixa pela largura (corte de no máx. ~3% de cada lado em telas mais
## estreitas); a barra de baixo fica sempre colada no fim da tela — em telas mais baixas ela cobre parte da
## cena (gata/mochila), em telas mais altas o chão da cena se estende até ela.
const ART_PATH := "res://ui_v022/assets/home_mobile_v11.png"   # R200 · Marcha/Xeque nas placas grandes   # R199 · v9 + o pé da cena que a v9 cortava (tools/home_mobile_v10_r199.py)
const DESIGN := Vector2(854, 1938)   # R199 · +96 (a cena continua por baixo da barra)
const NAV_TOP := 1751.0        # topo do recorte da barra (inclui a pedra azul de cima)
const NAV_FADE := 34.0         # fileiras de cima do recorte que se misturam com a cena
const MIN_H := 1712.0          # altura mínima da composição (menu inteiro + barra sem encostar na moldura), px da arte · R180c: +56 para o botão do WhatsApp caber entre o menu e a barra
const GROUND := Rect2(0, 1700, 854, 51)   # R199 · o fim da cena estendida   # chão da cena, estendido quando a tela é mais alta
const RefText := preload("res://ui_v022/ref_text.gd")
const GLOW := preload("res://ui_v022/home_button_glow.gdshader")
const ThemeCatalog := preload("res://cosmetics/theme_catalog.gd")

## [título do botão da Home, retângulo do botão na arte, título (x, topo, largura, maiúsculas), fonte, subtítulo, (x, topo, largura)]
const MENU := [
    ["JOGAR RANQUEADO", Rect2(140, 738, 575, 120), "JOGAR RANQUEADO", Rect2(279, 765, 346, 29), "default", "Compita e conquiste seu lugar", Rect2(281, 805, 341, 0)],
    # R200 · MARCHA REAL e XEQUE nas placas grandes (estavam apagados nas pequenas); ONLINE e COMPUTADOR descem
    # para as pequenas com a observação "Xadrez" (arte v11: ícones trocados, tools/home_mobile_v11_r200.py)
    ["MARCHA REAL", Rect2(142, 877, 573, 108), "MARCHA REAL", Rect2(280, 902, 260, 25), "default", "Corrida com cartas · até 4 jogadores", Rect2(282, 939, 330, 17)],
    ["XEQUE", Rect2(140, 1002, 575, 105), "XEQUE", Rect2(283, 1025, 200, 24), "default", "Jogo de cartas e blefe", Rect2(282, 1059, 300, 17)],
    ["JOGAR ONLINE", Rect2(138, 1256, 282, 75), "JOGAR ONLINE", Rect2(214, 1268, 170, 16), "squeeze", "Xadrez", Rect2(216, 1294, 160, 13)],
    ["JOGAR CONTRA O COMPUTADOR", Rect2(433, 1256, 282, 75), "CONTRA O PC", Rect2(510, 1268, 150, 16), "squeeze", "Xadrez", Rect2(512, 1294, 160, 13)],
    ["LIGAS E RANKING", Rect2(138, 1346, 282, 75), "LIGAS E RANKING", Rect2(229, 1372, 161, 19), "squeeze", "", Rect2()],
    ["HISTÓRICO DE PARTIDAS", Rect2(433, 1346, 282, 75), "HISTÓRICO", Rect2(544, 1372, 109, 19), "squeeze", "", Rect2()],
]
## barra de baixo: [id, retângulo, texto, (x, topo, largura, maiúsculas)]
## R178 · 5 abas: o PASSE entra no meio (embaixo do losango azul) — arte refeita em assets/home_nav5.png
## (tools/home_nav5_r178.py). Casas de 159 px a partir de x 30.
const NAV := [
    ["inicio", Rect2(22, 1786, 167, 130), "INÍCIO", Rect2(30, 1874, 159, 17)],
    ["amigos", Rect2(189, 1786, 159, 130), "AMIGOS", Rect2(189, 1872, 159, 19)],
    ["passe", Rect2(348, 1786, 159, 130), "PASSE", Rect2(348, 1872, 159, 19)],
    ["conta", Rect2(507, 1786, 160, 130), "MINHA CONTA", Rect2(517, 1877, 140, 15)],
    ["mais", Rect2(667, 1786, 168, 130), "MAIS", Rect2(667, 1875, 159, 16)],
]
const NAV_ART := "res://ui_v022/assets/home_nav5.png"
const PASS_STRIP := Rect2(146, 1110, 562, 139)   # R178d · botão do PASSE no meio do menu (a arte v9 abriu 44 px ali)
const WA_STRIP := Rect2(228, 1458, 398, 108)   # R180 · R196: a arte do dono (1000x270), mesmo tamanho das duas
const WA_SIDE_L := Rect2(22, 1458, 398, 108)    # R184c · WhatsApp à esquerda quando tem o BAIXAR O APP
const WA_SIDE_R := Rect2(434, 1458, 398, 108)   # R184c · BAIXAR O APP à direita
const WA_MENU_END := 1446.0   # R180c · fim da moldura do menu (o botão nunca sobe por cima dela)
const CLUB_RECT := Rect2(25, 45, 355, 73)
const SOUND_RECT := Rect2(730, 45, 82, 75)
const CARD_RECT := Rect2(108, 495, 637, 173)
const PORTRAIT := Rect2(145, 523, 125, 125)   # R168: vão medido (x 145–269, y 523–647); antes sobrava faixa escura nas bordas
const SHIELD := Rect2(620, 515, 90, 133)
## R86 · cor do brilho atrás do elo, por liga
const GLOW_COLORS := {"ferro": Color(0.75, 0.8, 0.9), "bronze": Color(1.0, 0.65, 0.35), "prata": Color(0.85, 0.9, 1.0), "ouro": Color(1.0, 0.8, 0.3), "platina": Color(0.5, 0.9, 1.0), "esmeralda": Color(0.35, 1.0, 0.55), "diamante": Color(0.4, 0.65, 1.0), "mestre": Color(0.8, 0.45, 1.0), "grande_mestre": Color(1.0, 0.35, 0.3), "challenger": Color(0.55, 0.75, 1.0)}

## o elo recortado (atlas sem o fundo escuro), na mesma grade 4x3 do atlas original
static func _badge_cut(league_id: String) -> Texture2D:
    var src: Texture2D = ThemeCatalog.badge_texture(league_id)
    if not (src is AtlasTexture): return src
    var t := AtlasTexture.new()
    t.atlas = load("res://ui_v022/assets/r86/insignias_recorte.png")
    t.region = (src as AtlasTexture).region
    return t
const BAR := Rect2(300, 604, 291, 14)

var hub
var mobile                     # ui_v022/mobile_hub.gd (dono da página e dos botões de som/Club)
var backdrop: TextureRect
var back_edges: Array = []
var art_fade: ShaderMaterial   # R203 · bordas da arte da frente se fundem na de trás
var top: Control               # px da arte, linhas 0 → NAV_TOP
var ground: TextureRect
var nav: Control               # px da arte, a barra (linhas NAV_TOP → fim)
var club_entry
var sound_button: Button
var portrait: TextureRect
var club_host: Control
var name_text
var league_text
var title_text   # R169 · título escolhido em PERSONALIZAR, embaixo da barra de PL
var bar_fill: ColorRect
var badge: TextureRect
var badge_plate: TextureRect
var badge_glow: TextureRect
var seal: TextureRect
var buttons := {}              # título → Button (área de toque)
var wa_button: Control         # R180 · WhatsApp (dúvidas/bugs)
var app_button: Control        # R184c · BAIXAR O APP (ao lado do WhatsApp)
var _shown := ""

func setup(owner_hub, owner_mobile):
    hub = owner_hub
    mobile = owner_mobile
    name = "MobileHomeRef"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    backdrop = TextureRect.new()
    backdrop.name = "RefBackdrop"
    # R203 · tela mais larga que a arte: a ARTE DE TRÁS é a mesma cena ESTICADA na largura da tela (mesma altura
    # da arte da frente, só mais larga) e a arte da frente se funde nela pelas bordas (degradê) — sem faixa
    # escura, sem emenda, sem a cena repetida
    backdrop.texture = _region(Rect2(0, 0, 854, NAV_TOP))
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_SCALE
    # na faixa de cima (SEJA MEMBRO e ícones) a arte de trás não pode mostrar a ponta da placa: ali as laterais
    # usam só a beirada da cena (folhagem / céu)
    for side in 2:
        var tc := TextureRect.new()
        tc.name = "RefBackTopEdge%d" % side
        tc.texture = _region(Rect2(0 if side == 0 else 836, 0, 18, 140))
        tc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tc.stretch_mode = TextureRect.STRETCH_SCALE
        tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
        backdrop.add_child(tc)
        back_edges.append(tc)
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
    var fm := ShaderMaterial.new()
    fm.shader = Shader.new()
    fm.shader.code = "shader_type canvas_item;\nuniform float fx = 0.0;\nuniform float y0 = 0.09;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); float a = 1.0; if (fx > 0.0001) { float e = smoothstep(0.0, fx, UV.x) * smoothstep(0.0, fx, 1.0 - UV.x); a = mix(1.0, e, smoothstep(y0 - 0.02, y0 + 0.02, UV.y)); } COLOR = vec4(c.rgb, c.a * a); }"
    art.material = fm
    art_fade = fm
    top.add_child(art)
    _build_fx()
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
    nav_art.texture = load(NAV_ART) if ResourceLoader.exists(NAV_ART) else _region(Rect2(0, NAV_TOP, 854, DESIGN.y - NAV_TOP))
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

var _atlases: Array = []
var _art: Texture2D = null
func _art_tex() -> Texture2D:
    if _art == null: _art = load(ART_PATH)
    return _art

## R89 · a arte (6 MB) só fica na memória enquanto a Home em pé aparece
func _notification(what):
    if what == NOTIFICATION_VISIBILITY_CHANGED and not _atlases.is_empty():
        var on := is_visible_in_tree()
        if not on:
            for t in _atlases: (t as AtlasTexture).atlas = null
            _art = null
        elif (_atlases[0] as AtlasTexture).atlas == null:
            for t in _atlases: (t as AtlasTexture).atlas = _art_tex()

## R197 · VIDA na Home do celular em pé (a mesma animação da Home do PC, home_fx.gd, com as posições desta arte):
## tochas mais vivas e suaves com fagulhas, água correndo com reflexos e névoa, folhas balançando com o vento,
## a gatinha respirando, passarinhos voando e cantando bem baixinho. Tudo por cima da arte e por baixo dos botões.
var fx: Control
func _build_fx():
    fx = preload("res://ui_v022/home_fx.gd").new()
    fx.name = "HomeFxMobile"
    fx.auto_build = false
    fx.forest_path = ART_PATH
    fx.art_size = Vector2(854, NAV_TOP)
    fx.torches = [
        [Vector2(98, 1190), Vector2(36, 62), 58.0],     # pilar esquerdo do menu
        [Vector2(752, 1192), Vector2(36, 62), 58.0],    # pilar direito do menu
        [Vector2(740, 408), Vector2(16, 24), 24.0],     # tochas da ponte (lá no fundo)
        [Vector2(795, 400), Vector2(16, 24), 24.0],
        [Vector2(822, 388), Vector2(14, 22), 22.0],
        [Vector2(786, 1168), Vector2(18, 26), 26.0],    # tochinha da ponte de baixo
    ]
    fx.lantern_last = false
    fx.water_rects = [Rect2(690, 380, 164, 1060), Rect2(470, 1380, 210, 371), Rect2(790, 1380, 64, 371)]
    fx.leaf_rects = [Rect2(0, 0, 854, 250), Rect2(0, 250, 124, 1250), Rect2(720, 250, 134, 520), Rect2(480, 1300, 374, 451)]
    fx.mists = [[Vector2(785, 530), 70.0], [Vector2(792, 640), 80.0], [Vector2(806, 760), 40.0], [Vector2(830, 1470), 44.0]]
    fx.belly = [Rect2(30, 1495, 190, 110), Vector2(115, 1550), Vector2(60, 32)]
    fx.sky = Rect2(580, 90, 274, 80)
    fx.noses = []
    top.add_child(fx)
    fx.set_awake(true)

func _region(r: Rect2) -> AtlasTexture:
    var t := AtlasTexture.new()
    t.atlas = _art_tex()
    _atlases.append(t)
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
    # R178 · PASSE DA TEMPORADA: faixa dourada no meio do menu, no lugar do filete com o losango
    var pass_strip = load("res://economy/pass_home_card.gd").new()
    pass_strip.setup(hub, "card")   # R178d · com espaço: o mesmo cartão do PC
    pass_strip.name = "PassHomeStrip"
    pass_strip.neon = true   # R196 · neon roxo acendendo e apagando (só no celular)
    pass_strip.position = PASS_STRIP.position
    pass_strip.size = PASS_STRIP.size
    top.add_child(pass_strip)
    # R180 · BETA: WhatsApp do dono embaixo do menu (dúvidas e bugs) — fica acima da barra de baixo até no MIN_H
    wa_button = load("res://ui_kit/whatsapp_button.gd").new()
    var wa = wa_button
    wa.art = true   # R196 · a arte do dono no lugar do desenho
    wa.position = WA_STRIP.position
    wa.size = WA_STRIP.size
    top.add_child(wa)
    # R184c · BAIXAR O APP bem visível na Home do celular (site, menos iPhone): ao lado do WhatsApp, as duas
    # placas lado a lado no mesmo lugar (cabe até na tela mais baixa). Sem o app (iPhone), o WhatsApp fica como era.
    var AppBtn = load("res://ui_kit/app_download_button.gd")
    if AppBtn.should_show():
        wa.position.x = WA_SIDE_L.position.x
        wa.size = WA_SIDE_L.size
        app_button = AppBtn.new()
        app_button.art = true
        app_button.position = WA_SIDE_R.position
        app_button.size = WA_SIDE_R.size
        top.add_child(app_button)
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
    club_entry.pressed.connect(func(): hub.open_premium())   # R63 · SEJA MEMBRO → FRAIHA PREMIUM
    top.add_child(club_entry)
    sound_button = preload("res://ui_v022/hud_button.gd").make("sound_on")
    sound_button.name = "SoundButtonMobile"
    sound_button.position = SOUND_RECT.position
    sound_button.size = SOUND_RECT.size
    sound_button.set_frame(hub.TOP_FRAME_CEL, 16.0)   # R122 · moldura azul (antes: só o ícone sobre a arte)
    sound_button.pressed.connect(func(): hub.open_home_volume(sound_button))   # R96 · painel MÚSICA / EFEITOS
    top.add_child(sound_button)
    # R96 · RANKING (troféu) e CHAT GLOBAL (balão) à esquerda do som · R112 COROAS · R162 MENSAGENS (envelope)
    # R162 · cinco botões na fileira de cima: um pouco mais estreitos (74) para caber ao lado do SEJA MEMBRO
    var bw := 66.0   # R176.8c · seis botões (+ SUPORTE)
    var gap := 5.0
    var right := SOUND_RECT.end.x
    var slot := func(i: int) -> Vector2: return Vector2(right - bw - (bw + gap) * i, SOUND_RECT.position.y)
    sound_button.position = slot.call(0)
    sound_button.size = Vector2(bw, SOUND_RECT.size.y)
    for spec in [["trophy", "Ranking", hub.open_leaderboard, 2], ["chat", "Chat global", hub.open_global_chat, 1]]:
        var tb: Button = hub.make_top_button(spec[0], spec[1], spec[2], SOUND_RECT.size.y)
        tb.size = Vector2(bw, SOUND_RECT.size.y)
        tb.position = slot.call(int(spec[3]))
        top.add_child(tb)
    var chip: Button = hub.crowns_client().make_chip(SOUND_RECT.size.y, bw)
    chip.set_frame(hub.TOP_FRAME_CEL, 16.0)   # R113 · mesma moldura do som
    chip.name = "CrownsTopButtonMobile"
    chip.position = slot.call(3)
    top.add_child(chip)
    var mail: Button = hub.make_mail_button(SOUND_RECT.size.y)
    mail.name = "MailTopButtonMobile"
    mail.size = Vector2(bw, SOUND_RECT.size.y)
    mail.position = slot.call(4)
    top.add_child(mail)
    # R176.8c · SUPORTE: fone ao lado do envelope
    var sup: Button = hub.make_top_button("support", "Falar com o suporte", hub.open_support, SOUND_RECT.size.y)
    sup.name = "SupportTopButtonMobile"
    sup.size = Vector2(bw, SOUND_RECT.size.y)
    sup.position = slot.call(5)
    top.add_child(sup)
    # R177b · os seis botões com a MESMA largura (os de make_top_button tinham mínimo quadrado de 75 e passavam
    # por cima do vizinho; a coroa, com 66, parecia menor e fora de esquadro)
    for b in [sound_button, chip, mail, sup] + top.get_children().filter(func(n): return n is Button and (String(n.name) == "TrophyTopButton" or String(n.name) == "ChatTopButton")):
        b.custom_minimum_size = Vector2(bw, SOUND_RECT.size.y)
        b.size = Vector2(bw, SOUND_RECT.size.y)
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
    title_text = RefText.make("", Rect2(298, 630, 296, 14), "default", Color("f6d27a"), true)
    title_text.name = "RefTitle"
    title_text.outline_size = 2
    title_text.visible = false
    top.add_child(title_text)
    # R86 · sem placa lisa: o pedaço do cartão com o escudo de madeira apagado cobre a arte, e o elo recortado
    # (sem o quadrado escuro) fica por cima com um brilho suave pulsando atrás
    badge_plate = TextureRect.new()
    badge_plate.texture = load("res://ui_v022/assets/r86/escudo_vazio.png")
    badge_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge_plate.position = SHIELD.position
    badge_plate.size = SHIELD.size
    badge_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(badge_plate)
    badge_glow = TextureRect.new()
    var gt := GradientTexture2D.new()
    gt.width = 128
    gt.height = 128
    gt.fill = GradientTexture2D.FILL_RADIAL
    gt.fill_from = Vector2(0.5, 0.5)
    gt.fill_to = Vector2(0.5, 0.0)
    var gr := Gradient.new()
    gr.set_color(0, Color(1, 1, 1, 0.95))
    gr.set_color(1, Color(1, 1, 1, 0.0))
    gt.gradient = gr
    badge_glow.texture = gt
    badge_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge_glow.position = SHIELD.position + SHIELD.size / 2.0 - Vector2(70, 70)
    badge_glow.size = Vector2(140, 140)
    badge_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var add := CanvasItemMaterial.new()
    add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    badge_glow.material = add
    top.add_child(badge_glow)
    badge = TextureRect.new()
    badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    badge.position = SHIELD.position + Vector2(-20, -6)
    badge.size = SHIELD.size + Vector2(40, 12)
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(badge)
    var tw := create_tween().set_loops()
    tw.tween_property(badge_glow, "modulate:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
    tw.tween_property(badge_glow, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
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
            var st = RefText.make(row[5], Rect2(sr.position - o, sr.size), "default", Color("f6f2e8"))   # R200 · altura limita a letra
            st.name = "RefSubtitle"
            st.outline_size = 3
            b.add_child(st)

## R200/R201 · CONVITE para os modos novos: um balão roxo-neon (o mesmo brilho do PASSE) do lado DIREITO da placa
## da MARCHA REAL e, 15 s depois, da placa do XEQUE — alternando, 2 vezes cada por abertura do jogo — só para
## quem ainda não abriu aquele modo. Toque = abre o modo; cada balão some sozinho em 7 s.
var _invite_t := 15.0
var _invite_n := 0
const INVITE_EVERY := 15.0
const INVITE_MAX := 4
const InviteBubble := preload("res://ui_v022/mode_invite_bubble.gd")
func _tick_invite(d: float):
    if _invite_n >= INVITE_MAX or not is_visible_in_tree(): return
    _invite_t -= d
    if _invite_t > 0.0: return
    _invite_t = INVITE_EVERY
    var order := ["marcha", "xeque"]
    var id := ""
    for k in 2:
        var c: String = order[(_invite_n + k) % 2]
        if not hub.mode_seen(c) or "--convite-teste" in OS.get_cmdline_user_args():
            id = c
            break
    _invite_n += 1
    if id.is_empty(): return
    var row: Rect2 = MENU[1][1] if id == "marcha" else MENU[2][1]
    var b = InviteBubble.new()
    b.name = "ModeInviteBubble"
    b.text_line = "JOGUE AGORA!"
    top.add_child(b)
    b.size = Vector2(150, 52)
    b.position = Vector2(row.end.x - b.size.x - 40.0, row.get_center().y - b.size.y / 2.0)   # lado direito, antes da seta
    b.pressed.connect(func():
        b.queue_free()
        if id == "marcha": hub.open_marcha()
        else: hub.open_xeque())
    b.appear(7.0)

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
            "passe": action = func(): if hub.has_method("crowns_client"): hub.crowns_client().open_pass()
            "mais": action = func(): mobile.show_page("mais")
        var b := _hit(nav, item[1], item[2], action)
        b.name = "RefNav_" + id
        # R187 · barra de baixo: o brilho que copia a arte desenhava por cima um "fantasma" transparente do botão
        # (a arte tem ícone/texto em outra posição que a do jogo). Aqui o toque só acende o título e o ícone.
        var gl := b.get_node_or_null("RefHover")
        if gl != null: (gl as TextureRect).texture = null   # (sem copiar a arte: não aparece nada)
        b.button_down.connect(func(): b.modulate = Color(1.35, 1.28, 1.12))
        b.button_up.connect(func(): b.modulate = Color.WHITE)
        b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
        buttons[item[2]] = b
        var o: Vector2 = item[1].position
        var tr: Rect2 = item[3]
        var t = RefText.make(item[2], Rect2(tr.position - o, tr.size), "default", Color("ffd84e") if id == "inicio" else (Color("ffe7a0") if id == "passe" else Color("f6f1e4")), true)   # R178 · casas novas: centralizado
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
    backdrop.position = Vector2.ZERO
    backdrop.size = Vector2(w, NAV_TOP * k)
    backdrop.visible = x0 > 0.5
    for i in back_edges.size():
        var tc: TextureRect = back_edges[i]
        tc.size = Vector2(x0 + 2.0, 140.0 * k)
        tc.position = Vector2(0.0 if i == 0 else w - x0 - 2.0, 0.0)
    # degradê de ~34 px da arte nas bordas (abaixo da faixa do SEJA MEMBRO/ícones, que não somem)
    art_fade.set_shader_parameter("fx", (34.0 / DESIGN.x) if x0 > 0.5 else 0.0)
    art_fade.set_shader_parameter("y0", 140.0 / NAV_TOP)
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
    # R180c · o WhatsApp fica SEMPRE visível entre o menu e a barra de baixo (em tela baixa a barra sobe e
    # cobria o botão): encosta logo acima da barra, sem subir além do fim do menu
    if wa_button != null:
        # R201 · tela baixa: o botão do WhatsApp (e o BAIXAR O APP) encolhe para caber entre o menu e a barra — antes a
        # Home inteira encolhia (MIN_H 1750 da R196) e sobravam faixas escuras nas laterais do celular
        var room: float = (nav_y + 26.0 * k) / k - WA_MENU_END
        var hh: float = clampf(room, 62.0, WA_STRIP.size.y)
        var ww: float = hh * (WA_SIDE_L.size.x / WA_SIDE_L.size.y)
        var above_nav := (nav_y + 26.0 * k) / k - hh
        var yy: float = clampf(above_nav, WA_MENU_END, WA_STRIP.position.y)
        if app_button != null:
            wa_button.size = Vector2(ww, hh)
            app_button.size = Vector2(ww, hh)
            wa_button.position = Vector2(WA_SIDE_L.end.x - ww, yy)
            app_button.position = Vector2(WA_SIDE_R.position.x, yy)
        else:
            wa_button.size = Vector2(ww, hh)
            wa_button.position = Vector2(DESIGN.x / 2.0 - ww / 2.0, yy)

func refresh():
    if hub == null: return
    var pname := String(hub.player_name)
    if name_text.text != pname: name_text.set_text(pname)
    var data = hub.league_profile.data
    var league = hub.LeagueCatalog.entry(data.current_league, data)
    var ltxt := "%s · %d / 100 PL" % [league.display_name, int(data.lp)]
    if league_text.text != ltxt: league_text.set_text(ltxt)
    bar_fill.size.x = BAR.size.x * clampf(float(data.lp) / 100.0, 0.0, 1.0)
    if title_text != null and hub.has_method("current_title"):
        var tt := preload("res://profile/premium_cosmetics.gd").title_text(hub.current_title())
        if title_text.text != tt: title_text.set_text(tt)
        var tcol := preload("res://profile/premium_cosmetics.gd").title_color(hub.current_title())   # R176.9 · cor do título
        if title_text.get("color") != null and title_text.color != tcol:
            title_text.color = tcol
            title_text.outline = Color(tcol.r, tcol.g, tcol.b, 0.35)
            title_text.outline_size = 4
            title_text.queue_redraw()
        title_text.visible = not tt.is_empty()
    portrait.texture = hub.avatar_texture()
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if hub.avatar_id == "warrior" else TextureRect.STRETCH_KEEP_ASPECT_COVERED
    hub.attach_club_frame(club_host)
    var league_id := String(data.current_league)
    var madeira := league_id in ["madeira", "wood"]
    badge.texture = null if madeira else _badge_cut(league_id)
    badge.visible = not madeira
    badge_plate.visible = not madeira
    badge_glow.visible = not madeira
    badge_glow.self_modulate = GLOW_COLORS.get(league_id, Color(1.0, 0.82, 0.45))
    var st: Texture2D = hub.current_badge_texture()
    seal.texture = st
    seal.visible = false   # R138 · como no PC: o cartão da Home não mostra o ícone (segue no Perfil e na partida)
    if st != null:
        var nw: float = name_text.ink_width()
        seal.position = name_text.position + Vector2(nw + 10.0, -9.0)
    club_entry.set_active(hub.entitlements != null and hub.entitlements.club_active())
    sound_button.glyph = "sound_off" if hub.home_sound_off() else "sound_on"
    sound_button.queue_redraw()

func _process(_delta):
    _tick_invite(_delta)
    # nome/liga podem mudar fora da Home (conta, Ranked): confere barato enquanto aparece
    if is_visible_in_tree() and hub != null:
        var key := "%s|%s|%s|%s|%s|%s" % [hub.player_name, hub.league_profile.data.current_league, hub.league_profile.data.lp, hub.avatar_id, hub.title_pref, hub.frame_pref]
        if key != _shown:
            _shown = key
            refresh()
