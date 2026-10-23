extends CanvasLayer
## MARCHA REAL — tela do modo (lobby, partida, tutorial e fim de jogo).
## A composição segue as telas de referência enviadas (tela_desktop.png 1920x1080 e tela_celular.png
## 1080x1920): tabuleiro, cartas, peões e retratos são as PRÓPRIAS artes do ZIP; a moldura da interface
## (placas, barra, botões) é desenhada em traço limpo nas mesmas posições, cores e fontes.
## Tudo é desenhado em coordenadas do layout de referência e escalado para a tela (PC, celular em pé,
## celular deitado). Jogo contra bots: você (Marfim) + aliado (Ônix) contra Rubi e Esmeralda.
signal closed

const Rules := preload("res://marcha/rules.gd")
const AI := preload("res://marcha/ai.gd")
const LayoutStd := preload("res://marcha/board_layout.gd")
const LayoutR57 := preload("res://marcha/board_layout_r57.gd")   # R57 · tabuleiro da arte final (PC)
const MobileLayout := preload("res://ui_v022/mobile_layout.gd")
const BOARD_UNITS := 1600.0       # largura do tabuleiro em unidades de desenho (os dois layouts)
## R57 · no PC (não celular, não em pé) a mesa e o salão são as referências finais do dono
## (tools/ui_ref/r57, placas em marcha/art/r57). No celular nada muda.
var Layout = LayoutStd
var desk := false
const R57_SIZE := Vector2(1672, 941)          # referência 3 (partida)
const R57_LOBBY := Vector2(1494, 834)         # referência 4 (antes da partida)
var r57 := {}
const Access := preload("res://marcha/marcha_access.gd")
const Sound := preload("res://ui_v022/mode_sound.gd")
const FullscreenControl := preload("res://ui_v022/fullscreen_control.gd")
const VoiceGlyph := preload("res://voice/voice_glyph.gd")   # R45
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const PlayerPortrait := preload("res://profile/player_portrait.gd")
const MUSIC := "res://marcha/audio/musica_marcha.mp3"    # música enviada pelo dono do projeto (loop)
const SFX := {
    "card": "res://marcha/audio/carta.wav", "discard": "res://marcha/audio/descarte.wav",
    "step": "res://marcha/audio/passo.wav", "exit": "res://marcha/audio/saida.wav",
    "capture": "res://marcha/audio/captura.wav", "swap": "res://marcha/audio/troca.wav",
    "crown": "res://marcha/audio/coroa.wav", "your_turn": "res://xeque/audio/sua_vez.wav",
    "victory": "res://xeque/audio/vitoria.wav", "defeat": "res://xeque/audio/derrota.wav",
    "arrive": "res://marcha/audio/chegada.wav", "victory_final": "res://marcha/audio/vitoria_final.wav",
    # R83 · fim da partida = o XEQUE-MATE do modo XEQUE (estouro + voz "XEQUE-MATE!"), para quem ganhar
    "mate_boom": "res://xeque/audio/xeque_mate_boom.wav", "voice_mate": "res://xeque/audio/voz_xeque_mate.wav",
    "voice_mate_lost": "res://xeque/audio/voz_xeque_mate_derrota.mp3",
    "promote": "res://marcha/audio/promocao_dama.wav",     # R37: fanfarra da chegada (vira DAMA)
    # R50 · sons enviados pelo dono do projeto
    "move": "res://audio_v025/padrao/movimento.mp3",         # a cada casa (toc quando o peão pousa)
}
const MOVE_HIT := 0.50       # R50: o toc do movimento.mp3 acontece aos 0,5 s do arquivo
const SFX_R50 := {
    "capture": "res://audio_v025/padrao/captura.mp3",
    "swap": "res://audio_v025/padrao/captura.mp3",
    "arrive": "res://marcha/audio/r70/coroacao_do_peao.mp3",   # R70: coroação do peão (áudio do dono)
    "exit": "res://marcha/audio/r70/saida_do_peao.mp3",         # R70: saída do peão da base (áudio do dono)
}
const SFX_DB := {"mate_boom": 0.0, "voice_mate": 0.0, "voice_mate_lost": -1.0, "exit": -6.0, "promote": -3.0, "arrive": -5.0, "victory_final": -5.0, "step": -12.0, "your_turn": -9.0, "crown": -7.0, "victory": -7.0, "defeat": -7.0, "capture": -6.0, "move": -8.0}

## R78 · arte do layout antigo (sem uso desde o visual novo em todo lugar): só carrega se for desenhada
var _board_tex: Texture2D = null
var _bg_tex: Texture2D = null
var BOARD: Texture2D:
    get:
        if _board_tex == null: _board_tex = load("res://marcha/art/board.png")
        return _board_tex
var BG: Texture2D:
    get:
        if _bg_tex == null: _bg_tex = load("res://marcha/art/table_bg.png")
        return _bg_tex
## R89 · artes da coroação só enquanto a MARCHA está aberta (antes: constantes, ~7 MB para sempre)
var _mtex := {}
func _mt(path: String) -> Texture2D:
    if not _mtex.has(path): _mtex[path] = load(path)
    return _mtex[path]
var SYMBOLS: Texture2D:
    get: return _mt("res://marcha/art/simbolos_de_acao.png")
var CROWN_TEX: Texture2D:
    get: return _mt("res://marcha/art/coroa_coroacao.png")   # R70: coroa da coroação (arte do dono)
var CROWN_TITLE: Texture2D:
    get: return _mt("res://marcha/art/coroado_pixel.png")   # R83.3: letreiro COROADO (arte de referência do dono)
var CROWN_EMBLEM: Texture2D:
    get: return _mt("res://marcha/art/coroacao_emblema.png")   # R83.3: escudo + coroa + brilho roxo
const FONT_TITLE := preload("res://account/fonts/Cinzel-Bold.woff")
const FONT_BOLD := preload("res://marcha/art/fonts/oswald-latin-700-normal.woff")
const FONT_SEMI := preload("res://marcha/art/fonts/oswald-latin-600-normal.woff")
const CARD_FILES := {"A": "carta_A_copas", "K": "carta_K_espadas", "Q": "carta_Q_copas", "J": "carta_J_ouros",
    "10": "carta_10_paus", "9": "carta_9_ouros", "8": "carta_8_espadas", "7": "carta_7_paus", "6": "carta_6_copas",
    "5": "carta_5_ouros", "4": "carta_4_paus", "3": "carta_3_copas", "2": "carta_2_espadas"}
const PAWN_FILES := ["marfim", "rubi", "onix", "esmeralda"]
const KINGDOM_LABEL := ["MARFIM", "RUBI", "ÔNIX", "ESMERALDA"]
const KINGDOM_COLOR := [Color("efe6cf"), Color("e3283a"), Color("d6dde3"), Color("35c27c")]
const KINGDOM_DOT := [Color("f3ecdc"), Color("d81f33"), Color("2c3340"), Color("1aa364")]
const GOLD := Color("e7b84a")
const GOLD_LINE := Color("b8892f")
const CREAM := Color("f3ead2")
const PANEL := Color("15213b")
const PANEL_DARK := Color("0e1729")
const TURN_MS := 15000   # R54 · 15 s por vez (servidor: online_v021/modes/party.js marchaTurnMs)
const BOT_DELAY := 0.95
const SWAP_MIN := 1.0             # R35.1: troca do J leva de 1,0 a 2,4 s (+0,7 s de brilho)
const SWAP_MAX := 2.4
const STEP_TIME := 0.26           # R37: 0,26 s por casa, em pulinho suave (antes 0,18 em saltos secos)
const HOP_H := 22.0               # R37: altura do pulinho entre casas (coordenadas do tabuleiro)
const EXIT_TIME := 0.55           # R37: saída da base em arco
const CAPTURE_TIME := 1.3         # R38.3: o peão abatido volta para a base girando, sem pressa (antes sumia em 0,5 s)
const CAPTURE_SPINS := 2.0        # R38.3: voltas completas no caminho até a base
const CROWN_WAIT := 1.9           # R37: chegada ao Salão · R83: tempo do brasão chegar ao peão
const CARD_FLY := 0.45            # R37.3: a carta jogada voa da mão (ou da placa do bot) até o centro da mesa
## Espelho no servidor: online_v021/modes/party.js (T.stepMs/exitMs/captureMs/crownMs/cardFlyMs) — conferido em tests/server/marcha_sync_test.cjs
## Bots da mesa (nomes e retratos da tela de referência).
const BOTS := {1: {"name": "ReiDoBlitz", "portrait": "rei_do_blitz"}, 2: {"name": "Lady Torre", "portrait": "lady_torre"}, 3: {"name": "Cavalo_Louco", "portrait": "cavalo_louco"}}
const PAWN_SCALE := 0.24          # peão PNG (211x279) sobre a casa da arte 1600x1600
const PAWN_BASE := 11.0           # a base do peão assenta 11 px abaixo do centro da casa
const DESK_PAWN_H := 84.0         # R66 · altura do peão no Pátio, no PC (unidades do tabuleiro de 1600)
const DESK_PAWN_H_TRACK := 62.0   # R68 · altura do peão na Muralha (menor: do tamanho da conta)

var hub = null
var stage = null
## R45 · FRAIHA Voice (módulo único do jogo); null fora do jogo completo.
func voice():
    return stage.get("voice") if stage != null else null
## R43 · controle de tela cheia do jogo (o mesmo do botão da Home); null fora do jogo completo.
func screen_mode():
    return stage.get("screen_mode") if stage != null else null
var access = null
var root: Control
var view: TableView
var g = null
var mode := "lobby"               # lobby | game | over
var tut_page := -1                # tutorial aberto (página) ou -1
var menu_open := false
var portrait := false
var wide_land := false   # R82 · celular DEITADO: blocos lado a lado, tabuleiro na altura toda
var blk := false         # layout por blocos (em pé ou celular deitado)
var design := Vector2(1920, 1080)
var k := 1.0
var origin := Vector2.ZERO
const DEFAULT_NAMES := ["Você", "ReiDoBlitz", "Lady Torre", "Cavalo_Louco"]
var names := DEFAULT_NAMES.duplicate()
# ---- R35 · partida ONLINE com amigo (o servidor é a autoridade; aqui só pedimos jogadas e animamos)
var online := false
var room_id := ""
var players: Array = []           # [{name, bot, connected, left}] já girados (você = 0)
var ev_queue: Array = []
var ev_running := false
var waiting_server := false
var cards := {}
var peek_card := -1      # R78 · carta segurada (aparece grande)
var card_back: Texture2D
var pawn_tex := {}
var portraits := {}
var my_portrait: Texture2D = null
var fonts := {}
# ---- estado da jogada humana
var sel_card := -1
var sel_pawn := []                # [seat, i]
var sel_target := []              # J: peça alvo
var split_first := 0              # 7: casas do 1º peão (0 = ainda não escolhido)
var sel_second := []              # 7: 2º peão
var pending := {}                 # jogada completa pronta para JOGAR CARTA
var turn_left_ms := TURN_MS
## R54 · prazo do turno em relógio real (Time.get_ticks_msec, que continua correndo com a aba em segundo plano).
## Online: vem do servidor (turn_left_ms do snapshot); o navegador só mostra. Local: o jogo marca o prazo.
var turn_deadline := 0
var busy := false                 # animando ou bot pensando
var anim := {}                    # [seat,i] -> posição desenhada (coordenadas do tabuleiro) durante animação
var anim_alpha := {}
var anim_rot := {}                # R38.3 · [seat_i] -> giro (rad) do peão abatido voltando para a base
var choice_open := false         # R35.1 · caixa "o que você quer fazer?" (cartas de 2 funções: A e 10)
var card_mode := ""               # função escolhida: "" | "move" | "exit" | "burn"
var ace_steps := 0                # R37 · Ás: 11 ou 1 (0 = ainda não escolhido)
var five_seat := -1               # R37 · 5: de que cor é a peça que vai andar (-1 = qualquer; R38.2: não pergunta mais)
var card_played := false          # R38.2 · a carta já foi JOGADA na mesa; agora o jogador toca na(s) peça(s)
var choice_commits := true       # R38.3 · escolher na caixa (TIRAR DA BASE, ANDAR 10/11/1, PERDE A VEZ) já JOGA a carta
var split_chosen := false         # R38.2 · 7: o jogador já escolheu a divisão (botões 7 / 6+1 / …)
var flies: Array = []             # R37.3 · cartas voando até a mesa: [{"rank", "from": Rect2 (tela de referência), "t", "idx"}]
var pile: Array = []              # R37.3 · monte da mesa: [{"rank", "dead": bool}] — "dead" = descartada sem jogada (cor apagada)
var swap_glow: Array = []         # R35.1 · as duas peças da troca (J) brilham durante a animação
var celebs: Array = []            # R35 · festa de chegada ao Salão: [{"p": Vector2 (tabuleiro), "t", "seat"}]
const CELEB_T := 2.2
var over_t := 0.0                 # R35 · tempo desde o fim (animação da vitória final)
var flash := ""                   # aviso curto (ex.: "Sem jogada: descarte uma carta")
var flash_t := 0.0
var hits: Array = []              # áreas de toque desta moldura: [{"rect","id"}]
var gate_info := {}               # resultado do acesso (Club / grátis do dia)
var t := 0.0
var started_at := 0
var started_unix := 0
var plays := 0
var recorded := false

func _init():
    layer = 64
    name = "MarchaReal"

func setup(p_hub, p_stage):
    hub = p_hub
    stage = p_stage

## R89 · cartas, peões e retratos: carregados ao ABRIR a Marcha e soltos ao FECHAR (antes: no início do jogo)
func _load_art():
    if not cards.is_empty(): return
    _load_cards()
    card_back = load("res://marcha/art/cards/carta_verso.png")
    for s in 4:
        var fc: String = PAWN_FILES[(s + view_seat) % 4]   # R92 · cor real de quem está no lugar s
        pawn_tex[s] = load("res://marcha/art/pawns/peao_" + fc + ".png")
        pawn_tex[s + 10] = load("res://marcha/art/pawns/peao_" + fc + "_dama.png")   # R37: no Salão o peão vira DAMA
    for key in ["lady_torre", "rei_do_blitz", "cavalo_louco", "voce"]: portraits[key] = load("res://marcha/art/portraits/" + key + ".png")

func _release_art():
    cards.clear(); pawn_tex.clear(); portraits.clear(); _mtex.clear(); _sfx.clear()
    card_back = null
    my_portrait = null

func _ready():
    for pair in [["title", FONT_TITLE, 0], ["bold", FONT_BOLD, 0], ["semi", FONT_SEMI, 0], ["bold_sp", FONT_BOLD, 3], ["semi_sp", FONT_SEMI, 3], ["semi_sp2", FONT_SEMI, 5]]:
        var fv := FontVariation.new()
        fv.base_font = pair[1]
        fv.spacing_glyph = pair[2]
        fonts[pair[0]] = fv
    access = Access.new()
    access.name = "MarchaAccess"
    add_child(access)
    access.setup(hub)
    access.changed.connect(func(info):
        gate_info = info
        _redraw())
    root = Control.new()
    root.name = "MarchaRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    view = TableView.new()
    view.ui = self
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(view)
    get_viewport().size_changed.connect(_relayout)
    visible = false
    root.visible = false
    _relayout()

# ---------------------------------------------------------------- abrir / fechar
func _load_cards():
    for r in CARD_FILES: cards[r] = load("res://marcha/art/cards/" + CARD_FILES[r] + ".png")

func open():
    _load_art()
    visible = true
    root.visible = true
    Sound.music_on(stage, MUSIC)
    mode = "lobby"
    menu_open = false
    tut_page = -1
    _refresh_my_portrait()
    access.refresh()
    if not Access.tutorial_seen(): tut_page = 0
    _relayout()

func close():
    Sound.close_popup(hub)   # R88
    _popup_close()
    if online:
        if mode == "game": _record_history("abandon")
        _online_leave()
    visible = false
    root.visible = false
    Sound.music_off(stage)
    Sound.release_samples(stage)   # R99 · amostras de áudio Web do modo
    mode = "lobby"
    g = null
    # R78 · solta a memória das artes grandes (mesa, salão, cartas); voltam a carregar ao abrir de novo
    r57.clear()
    _release_art()   # R89
    Sound.release_fonts()   # R89
    if view != null: view.tex_cache.clear()
    preload("res://ui_v022/crisp_tex.gd").clear_cache()
    closed.emit()

func is_open() -> bool:
    return visible

func _refresh_my_portrait():
    # A arte aprovada (tela_desktop/tela_celular) mostra o retrato do reino Marfim para "Você":
    # a placa segue a referência, sem trocar pelo avatar do perfil.
    my_portrait = null
    if hub != null and String(hub.get("player_name")) != "": names[0] = "Você"

func _input(event):
    if not visible: return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        if tut_page >= 0: tut_page = -1
        elif menu_open: menu_open = false
        elif mode == "game": menu_open = true
        else: close()
        _redraw()

func _relayout():
    if root == null: return
    var vs := root.get_viewport_rect().size
    portrait = vs.y > vs.x * 1.15
    desk = true   # R71 deitado / R74 em pé: o visual novo do PC em todo lugar (em pé, por blocos: PORTRAIT_GAME/LOBBY)
    Layout = LayoutR57 if desk else LayoutStd
    if desk and r57.is_empty():
        for key in ["mesa", "salao", "botao_jogar_vazio", "botao_jogar_agora_vazio", "mesa_wide", "salao_wide", "placa_perfil_1", "placa_perfil_2", "placa_perfil_3", "salao_botoes_cel"]: r57[key] = load("res://marcha/art/r57/%s.png" % key)
        for pair in [["r57_name", "res://marcha/art/fonts/oswald-latin-400-normal.woff", 0], ["r57_head", FONT_SEMI, 1], ["r57_bold", FONT_BOLD, 0]]:
            var fv := FontVariation.new()
            fv.base_font = pair[1] if pair[1] is Font else load(pair[1])
            fv.spacing_glyph = pair[2]
            fonts[pair[0]] = fv
    wide_land = not portrait and MobileLayout.active(get_viewport())
    blk = portrait or wide_land
    design = Vector2(1080, clampf(1080.0 * vs.y / maxf(1.0, vs.x), 1700.0, 2400.0)) if portrait else Vector2(1920, 1080)
    if wide_land: design = Vector2(clampf(1080.0 * vs.x / maxf(1.0, vs.y), 1920.0, 3300.0), 1080)
    if portrait:
        _portrait_layout()
        _portrait_lobby_layout()
    elif wide_land:
        _wide_layout()
    k = minf(vs.x / design.x, vs.y / design.y)
    origin = (vs - design * k) / 2.0
    _redraw()

func _redraw():
    # As áreas de toque da moldura anterior deixam de valer até o próximo desenho
    # (um 2º toque logo após JOGAR AGORA não pode cair no botão do lobby que já sumiu).
    hits.clear()
    if view != null: view.queue_redraw()

# ---------------------------------------------------------------- partida
var _starting := false
func start_game():
    if _starting or mode == "game": return
    _set_view_seat(0)   # R92 · partida contra os bots: você é sempre o Marfim
    _starting = true
    var ok: bool = await access.request_start()
    _starting = false
    if not ok:
        _flash("Você já jogou suas partidas grátis de hoje.")
        mode = "lobby"
        _redraw()
        return
    online = false
    names = DEFAULT_NAMES.duplicate()
    pile = []
    g = Rules.new()
    g.setup(0)
    for s in 4: g.names[s] = names[s] if s > 0 else (String(hub.player_name) if hub != null and String(hub.player_name) != "" else "Você")
    g.names[0] = "Você"
    mode = "game"
    menu_open = false
    started_at = Time.get_ticks_msec()
    started_unix = int(Time.get_unix_time_from_system())
    plays = 0
    recorded = false
    _clear_selection()
    _begin_turn()

func _begin_turn():
    if g == null or mode != "game" or online: return
    turn_left_ms = TURN_MS
    turn_deadline = Time.get_ticks_msec() + TURN_MS
    _clear_selection()
    _redraw()
    if g.winner >= 0:
        _finish()
        return
    if g.hands[g.turn].is_empty():
        g.next_turn()
        _begin_turn()
        return
    if g.turn != 0:
        busy = true
        await get_tree().create_timer(BOT_DELAY).timeout
        if g == null or mode != "game": return
        var mv := AI.choose(g, g.turn, null)
        await _play(g.turn, mv)
    else:
        busy = false
        _cue("your_turn")              # aviso sonoro: é a sua vez
        if not g.has_any_move(0): _flash("Sem jogada possível: escolha uma carta para descartar.")

func _snap_origin():
    _origin = {}
    if g == null: return
    for s in 4:
        for i in 4: _origin[_key([s, i])] = (g.pawns[s][i] as Dictionary).duplicate()

## Placa do jogador (coordenadas de referência): de onde sai a carta de quem não é você.
func seat_card_from(seat: int) -> Rect2:
    var r: Rect2
    if desk:
        r = rr(Rect2(r57_seat(seat).av))
        return Rect2(r.get_center() - Vector2(46, 64), Vector2(92, 128))
    if portrait: r = [Rect2(20, 1563, 130, 130), Rect2(20, 278, 272, 116), Rect2(360, 138, 360, 124), Rect2(788, 278, 272, 116)][seat]
    else: r = [Rect2(40, 898, 390, 124), Rect2(40, 262, 390, 122), Rect2(40, 120, 390, 122), Rect2(40, 404, 390, 122)][seat]
    return Rect2(r.get_center() - Vector2(46, 64), Vector2(92, 128))

## Centro do monte na mesa (coordenadas de referência) e tamanho de uma carta lá.
func pile_rect() -> Rect2:
    var br := board_rect()
    var s: float = br.size.x / BOARD_UNITS
    var cs := Vector2(270, 378) * s
    return Rect2(br.position + pile_center() * s - cs / 2.0, cs)

## centro do emblema da mesa (onde as cartas jogadas caem), em unidades do tabuleiro
func pile_center() -> Vector2:
    return LayoutR57.CENTER if desk else Vector2(800, 805)

## R37.3 · a(s) carta(s) jogada(s) voam até a mesa antes das peças andarem.
## idxs: posições na SUA mão (escondidas enquanto voam); vazio = carta de outro jogador (sai da placa dele).
var fly_hide: Array = []
func _fly_cards(seat: int, ranks: Array, idxs: Array, staged := false):
    if ranks.is_empty(): return
    if staged and seat == 0 and ranks.size() == 1: return     # R38.2: a carta já está na mesa (JOGAR CARTA antes da peça)
    flies = []
    var n: int = g.hands[0].size()
    for k in ranks.size():
        var from: Rect2 = card_rect(int(idxs[k]), n) if seat == 0 and k < idxs.size() else seat_card_from(seat)
        flies.append({"rank": String(ranks[k]), "from": from, "t": -0.08 * k})
    fly_hide = idxs.duplicate() if seat == 0 else []
    var tt := 0.0
    var total := CARD_FLY + 0.08 * (ranks.size() - 1)
    while tt < total:
        await get_tree().process_frame
        var d := get_process_delta_time()
        tt += d
        for f in flies: f.t += d
        _redraw()
    flies = []
    fly_hide = []

## Monte da mesa: cada carta que cai; as descartadas sem jogada ficam com a cor apagada.
func _pile_add(events: Array, mv: Dictionary, rank: String):
    var kind := String(mv.get("kind", ""))
    if kind in ["discard", "discard_all"]:
        for e in events: if String(e.type) == "discard": pile.append({"rank": String(e.rank), "dead": true})
    else:
        pile.append({"rank": rank, "dead": false})
        for e in events: if String(e.type) == "burn": pile.append({"rank": String(e.rank), "dead": true})
    if pile.size() > 6: pile = pile.slice(pile.size() - 6)

func _play(seat: int, mv: Dictionary):
    busy = true
    _snap_origin()
    if g.is_legal(seat, mv):
        var played: Array = [g.hands[seat][int(mv.card)]]
        var idxs: Array = [int(mv.card)]
        if String(mv.get("kind", "")) == "discard_all":
            played = g.hands[seat].duplicate()
            idxs = range(played.size())
        await _fly_cards(seat, played, idxs, seat == 0 and card_played)
    var rank0: String = g.hands[seat][int(mv.card)] if int(mv.get("card", -1)) >= 0 and int(mv.card) < g.hands[seat].size() else ""
    var events: Array = g.apply(seat, mv)
    if events.is_empty():
        # recusada pelo motor de regras (a mesma validação do bot): nada muda
        busy = false
        if seat == 0:
            _flash("Jogada inválida.")
            _redraw()
        else: _begin_turn()
        return
    plays += 1
    _clear_selection()
    _pile_add(events, mv, rank0)
    _cue("discard" if String(mv.get("kind", "")) in ["discard", "discard_all"] else "card")
    await _animate(events)
    busy = false
    if g == null or mode != "game": return
    if g.winner >= 0:
        _finish()
        return
    g.next_turn()
    _begin_turn()

func _finish():
    mode = "over"
    busy = false
    over_t = 0.0
    # R83 · XEQUE-MATE (o mesmo do modo XEQUE): estouro e, logo depois, a voz; a fanfarra/derrota vem em seguida
    _cue("mate_boom")
    var won: bool = g.winner == 0
    # R86 · a voz sombria "checkmate" com a espada toca para todos (ganhando ou perdendo); a fanfarra/derrota vem depois dela
    get_tree().create_timer(0.45).timeout.connect(func(): if mode == "over": _cue("voice_mate_lost"))
    get_tree().create_timer(5.4).timeout.connect(func(): if mode == "over": _cue("victory_final" if won else "defeat"))
    _record_history("win" if g.winner == 0 else "loss")
    _show_result_overlay(g.winner == 0)
    _redraw()

## R37 · a MESMA tela de VITÓRIA / DERROTA da partida contra bot (GameResultOverlay da stage), por cima
## da mesa; o painel de fim da Marcha (placar, JOGAR NOVAMENTE) aparece quando ela sai da tela.
var overlay_wait := false
func _show_result_overlay(won: bool):
    var ov = stage.get("result_overlay") if stage != null else null
    if ov == null or not ov.has_method("show_result") or overlay_wait: return
    overlay_wait = true
    ov.layer = layer + 1
    ov.show_result("victory" if won else "defeat")
    await ov.dismissed
    ov.layer = 60
    overlay_wait = false
    over_t = 0.0

## Histórico comum (o mesmo das partidas de xadrez), com mode_id e versão das regras.
func _record_history(result: String) -> Dictionary:
    if g == null or recorded or started_unix <= 0: return {}
    var mh = stage.get("match_history") if stage != null else null
    if mh == null or not mh.has_method("add_entry"): return {}
    recorded = true
    return mh.add_entry({
        "mode_id": "marcha_real", "ruleset_version": Rules.RULESET_VERSION, "mode": "marcha",
        "result": result, "reason": "abandono" if result == "abandon" else "coroação",
        "online": online, "room_id": room_id,
        "player": "Você", "ally": String(g.names[2]), "opponent": "%s e %s" % [g.names[1], g.names[3]],
        "started_at": started_unix, "finished_at": int(Time.get_unix_time_from_system()), "plies": plays,
        "data": {"rounds": g.round_no, "crowned": [g.team_crowned(0), g.team_crowned(1)], "seat": 0, "log": g.log.slice(-12)},
    })

func _process(delta):
    if not visible: return
    _sync_chat_block()
    t += delta
    for c in celebs: c.t += delta
    celebs = celebs.filter(func(c): return c.t < CELEB_T)
    if mode == "over" and not overlay_wait: over_t += delta
    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0: flash = ""
    if mode == "game" and g != null and g.turn == 0:
        # R54 · tempo restante = prazo − agora (relógio real): trocar de aba/minimizar não congela o turno.
        # Online o prazo é do servidor, que resolve a vez mesmo sem a aba voltar; aqui só se mostra.
        if online:
            turn_left_ms = maxi(0, turn_deadline - Time.get_ticks_msec())
        else:
            # jogo local: animação, menu e tutorial seguram o relógio (como antes)
            if busy or menu_open or tut_page >= 0: turn_deadline += int(delta * 1000.0)
            turn_left_ms = maxi(0, turn_deadline - Time.get_ticks_msec())
            if turn_left_ms <= 0 and not busy and not menu_open and tut_page < 0: _auto_play()
    _redraw()

## Tempo esgotado: a jogada sugerida (a mesma do bot) é feita no lugar do jogador.
func _auto_play():
    if busy or g == null: return
    var mv := AI.choose(g, 0, null)
    _play(0, mv)

func _flash(text: String):
    flash = text
    flash_t = 3.2

# ---------------------------------------------------------------- seleção do jogador
func _clear_selection():
    sel_card = -1
    sel_pawn = []
    sel_target = []
    split_first = 0
    sel_second = []
    pending = {}
    choice_open = false
    card_mode = ""
    ace_steps = 0
    five_seat = -1
    card_played = false
    split_chosen = false

## Jogadas da carta escolhida, já filtradas pela função escolhida na caixa (Ás: sair / 11 / 1; 5: a cor).
func my_moves() -> Array:
    if g == null or sel_card < 0: return []
    var mv: Array = g.legal_moves(0, sel_card)
    if card_mode == "exit": mv = mv.filter(func(m): return m.kind == "exit")
    elif card_mode == "move" and ace_steps > 0: mv = mv.filter(func(m): return m.kind == "move" and int(m.steps) == ace_steps)
    if five_seat >= 0: mv = mv.filter(func(m): return int(m.pawn[0]) == five_seat)
    return mv

## R37 · ABATER / CHEGADA: peões da OUTRA dupla que esta jogada manda de volta à base (simulada no próprio motor).
## Devolve {"enemy": [[s,i]...], "ally": [[s,i]...]}. Guardado por estado da mesa (não recalcula a cada quadro).
var _cap_cache := {}
func captures_of(mv: Dictionary) -> Dictionary:
    if g == null or mv.is_empty() or String(mv.get("kind", "")) in ["discard", "burn"]: return {"enemy": [], "ally": [], "crown": []}
    var key := JSON.stringify([g.pawns, g.hands[0], Rules._move_key(mv)])
    if _cap_cache.has(key): return _cap_cache[key]
    if _cap_cache.size() > 400: _cap_cache.clear()
    var sim = g.clone()
    var out := {"enemy": [], "ally": [], "crown": []}
    for e in sim.apply(0, mv):
        if String(e.type) == "crown" and Rules.team_of(int(e.pawn[0])) == Rules.team_of(0): out.crown.append(e.pawn)
        if String(e.type) != "capture": continue
        var w: Array = e.pawn
        out["enemy" if Rules.team_of(int(w[0])) != Rules.team_of(0) else "ally"].append(w)
    _cap_cache[key] = out
    return out

## Avisos da mão (por carta): {c: {"capture": bool, "crown": bool}}. Calculado uma vez por estado da mesa.
var _hand_flags_key := ""
var _hand_flags := {}
func _flags(c: int) -> Dictionary:
    if g == null or g.turn != 0 or c < 0 or c >= g.hands[0].size(): return {}
    var key := JSON.stringify([g.pawns, g.hands[0], g.turn, g.round_no])
    if key != _hand_flags_key:
        _hand_flags_key = key
        _hand_flags = {}
        for k in g.hands[0].size():
            var f := {"capture": false, "crown": false}
            for m in g.legal_moves(0, k):
                var o := captures_of(m)
                if not o.enemy.is_empty(): f.capture = true
                if not o.crown.is_empty(): f.crown = true
            _hand_flags[k] = f
    return _hand_flags.get(c, {})

## Esta carta da mão tem alguma jogada que ABATE um peão adversário?
func card_can_capture(c: int) -> bool:
    return bool(_flags(c).get("capture", false))

## Esta carta leva algum peão da sua dupla para dentro do Salão (as 4 vagas da chegada)?
func card_can_crown(c: int) -> bool:
    return bool(_flags(c).get("crown", false))

func all_moves() -> Array:
    if g == null or sel_card < 0: return []
    return g.legal_moves(0, sel_card)

func pick_card(i: int):
    if busy or g == null or g.turn != 0 or i >= g.hands[0].size(): return
    _clear_selection()
    sel_card = i
    if not g.has_any_move(0):
        pending = {"card": i, "rank": g.hands[0][i], "kind": "discard"}
    elif my_moves().is_empty():
        _flash("Esta carta não tem jogada agora.")
    else:
        # uma ação só possível → já fica pronta (ex.: A/K sem peão na pista = sair do Pátio;
        # carta que só um peão pode jogar). Só se escolhe peão quando há mais de uma opção.
        var opts := _options(my_moves())
        var ch := two_choices()
        var able := ch.filter(func(o): return bool(o[3]))
        if able.size() >= 2: choice_open = true          # A, 5 e 10: primeiro escolhe a função / a cor
        elif able.size() == 1:
            # R37 · só uma função (ou uma cor) é possível: ela já é ativada sozinha
            choice_open = true
            choose_function(String(able[0][0]), true)
            if pending.is_empty() and card_mode == "exit":
                for m in my_moves(): if m.kind == "exit": pending = m
        elif g.hands[0][i] == "J":
            pass        # R38.3 · J: sempre o jogador escolhe — 1º toque no SEU peão, 2º na peça que troca com ele
        elif opts.size() == 1:
            # R37.3 · uma jogada só possível (ex.: J com só 2 peões na mesa): já fica pronta, sem tocar em peça
            pending = opts.values()[0]
            if pending.kind == "swap":
                sel_pawn = pending.pawn
                sel_target = pending.target
            elif pending.kind == "split" or (pending.has("pawn") and pending.kind != "exit"):
                pick_pawn(pending.parts[0].pawn if pending.kind == "split" else pending.pawn)
        elif not sole_pawn().is_empty(): _auto_sole_pawn()
    _redraw()

## Caixa de escolha das cartas com mais de uma função. Devolve [[id, texto do botão, texto menor, possível?]]
## ou [] (segue direto). R37: o Ás tem 3 funções (sair do Pátio / andar 11 / andar 1) e o 5 pergunta de que
## cor é a peça que vai andar. A caixa só abre quando 2 ou mais opções são possíveis (as impossíveis ficam
## apagadas com o motivo); com uma só, ela é ativada direto (pick_card).
func two_choices() -> Array:
    if g == null or sel_card < 0 or sel_card >= g.hands[0].size(): return []
    var rank: String = g.hands[0][sel_card]
    var mv := all_moves()
    if mv.is_empty(): return []
    if rank == "10" and mv.any(func(m): return m.kind == "burn") and mv.any(func(m): return m.kind == "move"):
        return [["move", "ANDAR 10 CASAS", "um peão seu avança 10", true], ["burn", "%s PERDE A VEZ" % String(names[g.burn_target(0)]).to_upper(), "ele descarta 1 carta da mão (sorteada)", true]]
    if rank == "A":
        var can_exit := mv.any(func(m): return m.kind == "exit")
        var can11 := mv.any(func(m): return m.kind == "move" and int(m.steps) == 11)
        var can1 := mv.any(func(m): return m.kind == "move" and int(m.steps) == 1)
        var who: int = g.controlled(0)
        var exit_why := "um peão sai da base para o Portão" if can_exit else ("nenhum peão na base" if g.in_home(who) == 0 else "o seu Portão está ocupado")
        return [["exit", "TIRAR UM PEÃO DA BASE", exit_why, can_exit],
            ["move11", "ANDAR 11 CASAS", "um peão seu avança 11" if can11 else "nenhum peão pode andar 11", can11],
            ["move1", "ANDAR 1 CASA", "um peão seu avança 1" if can1 else "nenhum peão pode andar 1", can1]]
    # R38.2 · o 5 não pergunta mais a cor: JOGAR CARTA e depois toque direto na peça (de qualquer cor)
    return []

## Título da caixa de escolha.
func choice_title() -> String:
    if g == null or sel_card < 0 or sel_card >= g.hands[0].size(): return ""
    return "VOCÊ QUER MOVER QUAL PEÇA?" if g.hands[0][sel_card] == "5" else "O QUE VOCÊ QUER FAZER?"

## auto = ativada sozinha (só uma função possível) ao tocar na carta: aí a carta ainda NÃO foi jogada.
## Escolhida pelo jogador na caixa = carta jogada: a jogada completa acontece na hora (TIRAR DA BASE sai
## sozinho; ANDAR com peça única anda sozinho); se ainda falta tocar na peça, o próximo toque já joga.
func choose_function(kind: String, auto := false):
    if not choice_open: return
    for o in two_choices():
        if String(o[0]) == kind and not bool(o[3]): return        # opção apagada: não faz nada
    choice_open = false
    if kind.begins_with("seat"):
        five_seat = int(kind.substr(4))
        _auto_sole_pawn()
        _redraw()
        return
    if kind in ["move11", "move1"]:
        ace_steps = 11 if kind == "move11" else 1
        kind = "move"
    card_mode = kind
    match kind:
        "burn": pick_burn()
        "exit":
            for m in my_moves():
                if m.kind == "exit":
                    pending = m
                    break
        "move": _auto_sole_pawn()
    _redraw()
    if not auto and choice_commits: _commit_choice()

func _commit_choice():
    if needs_pieces():
        card_played = true
        _cue("card")
        _redraw()
    elif not pending.is_empty(): confirm()

## R34.2 · um peão só pode receber a carta (ex.: uma peça só rodando no tabuleiro) → ele já fica
## escolhido: não precisa tocar nele. Vale para toda carta que age sobre o peão (10 = ANDAR 10
## já marcado, J = só falta escolher a peça para trocar). Saída do Pátio conta como outra opção.
func sole_pawn() -> Array:
    # R38.5 · peça única = a ÚNICA peça que pode fazer algo com esta carta. Se uma peça no Salão (chegada)
    # também pode andar com ela, são duas opções: o jogador escolhe (antes a da Muralha era escolhida sozinha).
    var who := []
    for m in my_moves():
        if m.kind == "burn": continue
        if m.kind == "exit":
            if card_mode == "move": continue
            return []
        var w: Array = m.parts[0].pawn if m.kind == "split" else m.pawn
        if not who.has(w): who.append(w)
    if who.size() == 1: return who[0]
    return []

func _auto_sole_pawn():
    var w := sole_pawn()
    if not w.is_empty(): pick_pawn(w)

## Agrupa as jogadas em ações distintas para o jogador (todas as saídas do Pátio são a mesma ação).
func _options(moves: Array) -> Dictionary:
    var out := {}
    for m in moves:
        var k: String
        match String(m.kind):
            "exit": k = "exit"
            "burn": k = "burn"
            "split": k = "split:" + str(m.parts)
            _: k = String(m.kind) + str(m.get("pawn", [])) + str(m.get("target", []))
        if not out.has(k): out[k] = m
    return out

## 10 com as duas funções: o jogador escolhe ANDAR 10 ou FAZER DESCARTAR.
func ten_choice() -> bool:
    return false        # R35.1: a escolha do 10 (e do A) agora é a caixa de diálogo (two_choices)

func pick_burn():
    for m in my_moves():
        if m.kind == "burn":
            sel_pawn = []
            pending = m
    _redraw()

## Peões que podem receber o próximo toque (para os aros dourados).
func candidate_pawns() -> Array:
    var out := []
    if g == null or sel_card < 0 or g.turn != 0 or busy or choice_open: return out
    if card_mode == "burn" or awaiting_play(): return out      # R38.2: primeiro JOGAR CARTA, depois a peça
    var mv := my_moves()
    var rank: String = g.hands[0][sel_card]
    if rank == "J" and not sel_pawn.is_empty():
        for m in mv:
            if m.pawn == sel_pawn and not out.has(m.target): out.append(m.target)
            if m.pawn != sel_pawn and not out.has(m.pawn): out.append(m.pawn)     # trocar a escolha do 1º toque
        return out
    if rank == "7" and split_first > 0 and split_first < 7:
        for m in mv:
            if m.parts.size() == 2 and m.parts[0].pawn == sel_pawn and int(m.parts[0].steps) == split_first and not out.has(m.parts[1].pawn): out.append(m.parts[1].pawn)
        return out
    for m in mv:
        if m.kind == "burn": continue
        if m.kind == "exit" and card_mode == "move": continue
        if m.kind == "exit":
            # sair do Pátio: qualquer peão do Pátio serve (o toque escolhe qual)
            var who: int = m.pawn[0]
            for i in 4:
                if g.pawns[who][i].zone == "home" and not out.has([who, i]): out.append([who, i])
            continue
        var w: Array = m.parts[0].pawn if m.kind == "split" else m.pawn
        if not out.has(w): out.append(w)
    return out

func pick_pawn(w: Array):
    if g == null or sel_card < 0 or busy or choice_open: return
    if card_mode == "move" and g.pawns[w[0]][w[1]].zone == "home": return
    var rank: String = g.hands[0][sel_card]
    var mv := my_moves()
    if rank == "J" and not sel_pawn.is_empty() and sel_pawn != w and int(w[0]) != int(sel_pawn[0]):   # R70: o 1º pode ser do aliado
        for m in mv:
            if m.pawn == sel_pawn and m.target == w:
                sel_target = w
                pending = m
        _redraw()
        _after_pick()
        return
    if rank == "7" and split_first > 0 and split_first < 7 and not sel_pawn.is_empty() and w != sel_pawn:
        for m in mv:
            if m.parts.size() == 2 and m.parts[0].pawn == sel_pawn and int(m.parts[0].steps) == split_first and m.parts[1].pawn == w:
                sel_second = w
                pending = m
        _redraw()
        _after_pick()
        return
    sel_pawn = w
    sel_target = []
    split_first = 0
    split_chosen = false
    sel_second = []
    pending = {}
    var mine := mv.filter(func(m): return m.kind != "burn" and (m.parts[0].pawn if m.kind == "split" else m.pawn) == w)
    if rank in ["A", "K"]:
        # peão no Pátio → sair; peão na Muralha → andar
        var home: bool = g.pawns[w[0]][w[1]].zone == "home"
        for m in mine:
            if (m.kind == "exit") == home: pending = m
        if home:
            for m in mv:
                if m.kind == "exit":
                    pending = m.duplicate()
                    pending.pawn = w
    elif rank == "7":
        for m in mine:
            if m.parts.size() == 1: pending = m
        split_first = 7 if not pending.is_empty() else 0
    elif rank != "J" and not mine.is_empty():
        pending = mine[0]
    _redraw()
    _after_pick()

## 7: quantas casas vão para o 1º peão (7 = tudo nele).
func split_options() -> Array:
    var out := []
    if g == null or sel_card < 0 or sel_pawn.is_empty() or g.hands[0][sel_card] != "7": return out
    for m in my_moves():
        if m.parts[0].pawn != sel_pawn: continue
        var a := int(m.parts[0].steps)
        if not out.has(a): out.append(a)
    out.sort()
    out.reverse()
    return out

func pick_split(a: int):
    split_first = a
    split_chosen = true
    sel_second = []
    pending = {}
    if a == 7:
        for m in my_moves():
            if m.parts.size() == 1 and m.parts[0].pawn == sel_pawn: pending = m
    _redraw()
    _after_pick()

## R38.2 · a carta escolhida ainda precisa de peça(s): primeiro JOGAR CARTA (ela vai para a mesa), depois
## o toque na peça. Verdadeiro enquanto falta escolher peça/divisão para a jogada ficar completa.
func needs_pieces() -> bool:
    if g == null or sel_card < 0 or sel_card >= g.hands[0].size() or choice_open or card_mode == "burn": return false
    if String(pending.get("kind", "")) in ["discard", "exit", "burn"]: return false
    if pending.is_empty(): return not my_moves().is_empty()
    if g.hands[0][sel_card] == "7" and not split_chosen and sel_second.is_empty() and split_options().size() > 1: return true
    return false

## A carta foi escolhida mas ainda não foi jogada, e a jogada depende de tocar em peça(s).
func awaiting_play() -> bool:
    return not card_played and needs_pieces()

## JOGAR CARTA habilitado.
func can_play() -> bool:
    return g != null and g.turn == 0 and not busy and not waiting_server and (awaiting_play() or not pending.is_empty())

## Depois que a carta foi jogada, a jogada fica pronta no último toque e já acontece (sem 2º JOGAR CARTA).
func _after_pick():
    if card_played and not pending.is_empty() and not needs_pieces(): confirm()

func confirm():
    if busy or g == null or g.turn != 0: return
    if awaiting_play():
        card_played = true
        _cue("card")
        _redraw()
        return
    if pending.is_empty(): return
    if online:
        _online_send(pending)
        return
    var mv := pending
    _play(0, mv)

## R37.3 · nenhuma carta da mão tem jogada nesta rodada: pode descartar TODAS de uma vez.
func can_discard_all() -> bool:
    return g != null and mode == "game" and g.turn == 0 and not busy and not waiting_server and g.hands[0].size() >= 2 and not g.has_any_move(0)

func discard_all():
    if not can_discard_all(): return
    var mv := {"card": 0, "rank": g.hands[0][0], "kind": "discard_all"}
    if online:
        _online_send(mv)
        return
    _play(0, mv)

func cancel():
    _clear_selection()
    _redraw()

## Frase da linha de ajuda (ex.: "10 de Paus · seu peão avança 10 casas").
func help_line() -> String:
    if g == null: return ""
    if mode != "game": return ""
    if g.turn != 0: return "Seu aliado está jogando…" if g.turn == 2 else "Adversário pensando…"
    if sel_card < 0:
        return "Sem jogada: escolha uma carta para descartar" if not g.has_any_move(0) else "Escolha uma carta"
    var rank: String = g.hands[0][sel_card]
    var head := Rules.card_label(rank)
    if pending.get("kind", "") == "discard": return head + " · descartar" + (" (ou todas)" if can_discard_all() else "")
    if choice_open: return head + " · escolha o que fazer"
    if awaiting_play(): return head + " · toque em JOGAR CARTA e depois na peça"
    match rank:
        "A", "K":
            if not pending.is_empty() and pending.kind == "exit": return head + " · seu peão sai da base"
            if rank == "K": return head + " · tira um peão da base"
            if ace_steps > 0 and card_played: return head + " · anda %d casa%s: toque no peão" % [ace_steps, "s" if ace_steps > 1 else ""]
            return head + " · sai da base, anda 11 ou anda 1"
        "J":
            if not pending.is_empty(): return head + " · troca pronta: toque em JOGAR CARTA"
            if sel_pawn.is_empty(): return head + " · 1º toque no SEU peão que vai trocar"
            return head + " · 2º toque na peça do amigo ou do adversário"
        "10":
            if not pending.is_empty() and pending.kind == "burn": return head + " · %s perde a vez (descarta 1 carta)" % names[int(pending.target_seat)]
            if ten_choice(): return head + " · anda 10 casas ou faz %s descartar" % names[g.burn_target(0)]
        "7":
            if split_first > 0 and split_first < 7: return head + " · %d casas + %d casas: escolha o 2º peão" % [split_first, 7 - split_first]
            if card_played and sel_pawn.is_empty(): return head + " · toque no 1º peão"
            if card_played and needs_pieces(): return head + " · escolha a divisão das 7 casas"
            return head + " · até 2 peças dividem 7 casas"
        "5":
            if card_played and pending.is_empty(): return head + " · toque na peça (de qualquer cor) que vai andar 5"
            return head + " · qualquer peça anda 5 casas"
        "4": return head + " · seu peão volta 4 casas"
    return head + " · seu peão avança %d casas" % int(Rules.STEPS.get(rank, 0))

# ---------------------------------------------------------------- animação
func _animate(events: Array):
    # R83 · todo peão que vai ANDAR nesta jogada fica parado na casa de onde sai até chegar a vez dele (no 7
    # dividido o 2º peão aparecia já no destino e depois "voltava" para andar: parecia teletransporte)
    for e in events:
        if String(e.type) == "move":
            var mk := _key(e.pawn)
            if _origin.has(mk) and String(_origin[mk].zone) != "home": anim[mk] = _cell_of(int(e.pawn[0]), _origin[mk])
    # R37 · peão que vai ser ABATIDO fica na casa dele até o atacante chegar (só então some)
    for e in events:
        if String(e.type) == "capture":
            var ck := _key(e.pawn)
            if _origin.has(ck) and String(_origin[ck].zone) != "home": anim[ck] = _cell_of(int(e.pawn[0]), _origin[ck])
    for e in events:
        match String(e.type):
            "move":
                var w: Array = e.pawn
                var key := _key(w)
                # R37 · cada casa é um pulinho suave (sobe e desce em arco, com aceleração e freio)
                var from: Vector2 = pawn_point(w[0], w[1]) if not anim.has(key) else anim[key]
                if not anim.has(key) and e.path.size() > 0:
                    from = _cell_of(w[0], _prev_cell(w, e))
                for step in e.path:
                    var to: Vector2 = _cell_of(w[0], step)
                    # R50 · um som por casa; começa no ponto em que o toc cai quando o peão pousa nesta casa
                    _cue("move", 1.0, maxf(0.0, MOVE_HIT - STEP_TIME))
                    await _tween_hop(key, from, to, STEP_TIME, HOP_H)
                    from = to
                if e.path.size() > 0: _origin[key] = e.path[e.path.size() - 1]
                anim.erase(key)
            "exit":
                _cue("exit")
                var w: Array = e.pawn
                var key := _key(w)
                var a: Vector2 = Layout.home_center(w[0])
                var b: Vector2 = Layout.track_cell(Layout.gate_index(w[0]))
                await _tween_hop(key, a, b, EXIT_TIME, 60.0)
                anim.erase(key)
            "capture":
                # R38.3 · o abatido volta para a base: arco suave girando (o motor já o pôs no Pátio)
                _cue("capture")
                var w: Array = e.pawn
                var key := _key(w)
                var a: Vector2 = anim[key] if anim.has(key) else (_cell_of(w[0], _origin[key]) if _origin.has(key) else pawn_point(w[0], w[1]))
                var pw: Dictionary = g.pawns[w[0]][w[1]]
                var b: Vector2 = Layout.home_cell(w[0], int(pw.pos)) if pw.zone == "home" else pawn_point(w[0], w[1])
                var tt := 0.0
                while tt < CAPTURE_TIME:
                    await get_tree().process_frame
                    tt += get_process_delta_time()
                    var f := clampf(tt / CAPTURE_TIME, 0.0, 1.0)
                    var ee := f * f * (3.0 - 2.0 * f)
                    anim[key] = a.lerp(b, ee) + Vector2(0, -90.0 * sin(PI * f))
                    anim_rot[key] = TAU * CAPTURE_SPINS * ee
                    _redraw()
                anim_rot.erase(key)
                anim_alpha.erase(key)
                anim.erase(key)
                _redraw()
            "burn":
                _cue("discard")
                if int(e.seat) == 0: _flash("%s te fez descartar %s." % [names[g.turn], Rules.card_label(String(e.rank))])
                _redraw()
                await get_tree().create_timer(0.4).timeout
            "crown":
                # R35 · peão chegou às 4 casas do Salão: som de vitória + coroa estourando na casa
                var w: Array = e.pawn
                _cue("arrive")
                celebs.append({"p": _cell_of(w[0], g.pawns[w[0]][w[1]]), "t": 0.0, "seat": int(w[0])})
                _redraw()
                await get_tree().create_timer(CROWN_WAIT).timeout
            "swap":
                # R35.1 · troca (J): as duas peças brilham e cruzam o tabuleiro em arco, no ritmo do andar
                var a: Array = e.pawn
                var b: Array = e.target
                var ka := _key(a)
                var kb := _key(b)
                var pa: Vector2 = _cell_of(a[0], g.pawns[a[0]][a[1]])     # destino de a (= onde b estava)
                var pb: Vector2 = _cell_of(b[0], g.pawns[b[0]][b[1]])     # destino de b (= onde a estava)
                swap_glow = [a, b]
                anim[ka] = pb
                anim[kb] = pa
                _redraw()
                await get_tree().create_timer(0.35).timeout          # as duas brilham antes de sair
                _cue("swap")
                var dur := clampf(pa.distance_to(pb) / 65.0 * STEP_TIME, SWAP_MIN, SWAP_MAX)
                var tt := 0.0
                while tt < dur:
                    await get_tree().process_frame
                    tt += get_process_delta_time()
                    var f := clampf(tt / dur, 0.0, 1.0)
                    var ee := f * f * (3.0 - 2.0 * f)
                    var lift := Vector2(0, -70.0 * sin(PI * f))
                    anim[ka] = pb.lerp(pa, ee) + lift
                    anim[kb] = pa.lerp(pb, ee) + lift
                    _redraw()
                anim.erase(ka)
                anim.erase(kb)
                _redraw()
                await get_tree().create_timer(0.35).timeout
                swap_glow = []
            "discard":
                if String(e.type) != "discard": _cue(String(e.type))
                _redraw()
                await get_tree().create_timer(0.18).timeout
    anim.clear()
    _origin = {}
    _redraw()

## Onde o peão estava antes desta jogada (a casa anterior ao 1º passo). O motor já moveu o peão;
## para o "move", a origem é a posição de antes: guardada em _origin pelo _play (ou a 1ª casa do caminho).
var _origin := {}
func _prev_cell(w: Array, e: Dictionary) -> Dictionary:
    var k := _key(w)
    if _origin.has(k): return _origin[k]
    return e.path[0]

## Pulinho suave de uma casa para outra: posição com aceleração e freio (smoothstep) e arco (seno).
func _tween_hop(key: String, a: Vector2, b: Vector2, dur: float, h: float):
    var tt := 0.0
    while tt < dur:
        await get_tree().process_frame
        tt += get_process_delta_time()
        var f := clampf(tt / dur, 0.0, 1.0)
        var ee := f * f * (3.0 - 2.0 * f)
        anim[key] = a.lerp(b, ee) + Vector2(0, -h * sin(PI * f))
        _redraw()
    anim[key] = b
    _redraw()

static func _key(w: Array) -> String:
    return "%d_%d" % [w[0], w[1]]

func _cell_of(seat: int, p: Dictionary) -> Vector2:
    match String(p.zone):
        "track": return Layout.track_cell(int(p.pos))
        "lane": return Layout.lane_cell(seat, int(p.pos))
    return Layout.home_cell(seat, int(p.pos))

## Onde cada peão é desenhado (coordenadas da arte do tabuleiro).
func pawn_point(s: int, i: int) -> Vector2:
    var key := "%d_%d" % [s, i]
    if anim.has(key): return anim[key]
    return _cell_of(s, g.pawns[s][i])

# ---------------------------------------------------------------- toques
# ---------------------------------------------------------------- R37 · cartão de perfil
var _hover_seat := -1
func _popup():
    return stage.get("profile_popup") if stage != null else null

func _popup_close():
    var pp = _popup()
    if pp != null: pp.close()
    _hover_seat = -1

## R41 · Identidade pública (selo/título/moldura) de quem está no lugar `seat`. Bots: {}.
func seat_look(seat: int) -> Dictionary:
    if seat == 0: return PlayerPortrait.self_info(hub)
    if online and seat < players.size() and not bool(players[seat].get("bot", false)): return players[seat]
    return {}

## Avatar do amigo humano na mesa online (null = usar o retrato do bot).
func seat_avatar(seat: int) -> Texture2D:
    if not online or seat >= players.size() or bool(players[seat].get("bot", false)): return null
    if hub == null or not hub.has_method("avatar_texture"): return null
    if hub.has_method("avatar_texture_for"): return hub.avatar_texture_for(players[seat])   # R150 · foto do amigo
    var av := String(players[seat].get("avatar", ""))
    return hub.avatar_texture(av) if not av.is_empty() else hub.avatar_texture("warrior")

## Dados do jogador da placa `seat` para o cartão (você, bot ou amigo da mesa online).
func seat_info(seat: int) -> Dictionary:
    var acc = stage.get("account") if stage != null else null
    var info := {"name": String(names[seat]), "mode": "marcha", "mode_label": "MARCHA REAL",
        "subtitle": KINGDOM_LABEL[seat] + (" · ALIADO" if seat == 2 else (" · VOCÊ" if seat == 0 else " · ADVERSÁRIO"))}
    if online and seat < players.size():
        var pl: Dictionary = players[seat]
        info.user_id = String(pl.get("user_id", ""))
        info.bot = bool(pl.get("bot", false))
        if hub != null and hub.has_method("avatar_texture") and not info.bot: info.avatar = (hub.avatar_texture_for(pl) if hub.has_method("avatar_texture_for") else hub.avatar_texture(String(pl.get("avatar", "")))) if seat != 0 else (my_portrait if my_portrait != null else portraits.voce)
        if not info.bot: info.merge(seat_look(seat))
        else: info.avatar = portraits[BOTS[seat].portrait] if BOTS.has(seat) else null
    elif seat == 0:
        info.user_id = String(acc.user_id) if acc != null and acc.has_profile() else ""
        info.bot = false
        info.avatar = my_portrait if my_portrait != null else portraits.voce
    else:
        info.bot = true
        info.avatar = portraits[BOTS[seat].portrait]
    return info

func _seat_screen_rect(seat: int) -> Rect2:
    for h in hits:
        if String(h.id) == "seat_%d" % seat:
            var r: Rect2 = h.rect
            return Rect2(origin + r.position * k, r.size * k)
    return Rect2()

var hover_id := ""
func on_hover(p: Vector2):
    # R57 · botões da arte clareiam com o mouse por cima
    var hid := ""
    for h in range(hits.size() - 1, -1, -1):
        if Rect2(hits[h].rect).has_point(p):
            hid = String(hits[h].id)
            break
    if hid != hover_id:
        hover_id = hid
        if view != null: view.queue_redraw()
    var pp = _popup()
    if pp == null: return
    var seat := -1
    if mode in ["game", "over"] and tut_page < 0 and not menu_open and not choice_open:
        for h in hits:
            if String(h.id).begins_with("seat_") and Rect2(h.rect).has_point(p): seat = int(String(h.id).substr(5))
    if seat == _hover_seat: return
    if _hover_seat >= 0: pp.unhover("marcha_seat_%d" % _hover_seat)
    _hover_seat = seat
    if seat >= 0: pp.hover("marcha_seat_%d" % seat, seat_info(seat), _seat_screen_rect(seat))

## R88 · celular em pé: microfone e fone GRANDES; R90 · na linha de baixo do tabuleiro, do mesmo tamanho do painel
## SUA VEZ: microfone à esquerda (com o fone dividindo o espaço quando a voz está ligada) e CHAT à direita.
func _row_ok() -> bool:
    return portrait and not portrait_game.is_empty() and portrait_row.size() == 3

func _voice_pair() -> bool:
    var vo = voice()
    return vo != null and vo.in_match() and vo.available() and vo.active()

func mic_rect() -> Rect2:
    if _row_ok():
        var l: Rect2 = portrait_row[0]
        return Rect2(l.position, Vector2((l.size.x - 10.0) / 2.0, l.size.y)) if _voice_pair() else l
    return rr(Rect2(1230, 12, 54, 53))

func ear_rect() -> Rect2:
    if _row_ok():
        var m := mic_rect()
        return Rect2(m.end.x + 10.0, m.position.y, m.size.x, m.size.y)
    return rr(Rect2(1162, 12, 54, 53))

func chat_dock() -> Rect2:
    if wide_land and not portrait: return wide_chat
    if not _row_ok(): return Rect2()
    return portrait_row[2]

func _sync_chat_dock():
    var pc = stage.get("party_chat") if stage != null else null
    if pc == null or not pc.has_method("set_dock"): return
    var d := chat_dock() if (online and mode == "game" and visible) else Rect2()
    pc.set_dock(Rect2(origin + d.position * k, d.size * k) if d.size.x > 0.0 else Rect2())

## R95 · CHAT da mesa escondido enquanto o menu, o tutorial, a tela de VITÓRIA/DERROTA ou o painel de fim
## estiverem abertos (ele fica numa camada acima da Marcha e cobria essas telas).
func chat_blocked() -> bool:
    return menu_open or tut_page >= 0 or overlay_wait or mode != "game"

func _sync_chat_block():
    var pc = stage.get("party_chat") if stage != null else null
    if pc != null and pc.has_method("set_blocked"): pc.set_blocked(chat_blocked())

## R88 · retângulo (em pixels de tela) da área de toque com este id — para abrir o volume junto do ícone
func _hit_screen_rect(id: String) -> Rect2:
    for h in hits:
        if String(h.id) == id: return Rect2(origin + Rect2(h.rect).position * k, Rect2(h.rect).size * k)
    return Rect2(get_viewport().get_visible_rect().size.x - 80, 10, 60, 60)

func on_press(p: Vector2):
    # tutorial e menu ficam por cima de tudo
    for h in range(hits.size() - 1, -1, -1):
        var hit: Dictionary = hits[h]
        if Rect2(hit.rect).has_point(p):
            _on_hit(String(hit.id))
            return
    if mode == "game" and tut_page < 0 and not menu_open and g != null and g.turn == 0 and not busy and sel_card >= 0:
        var br := board_rect()
        var bp := (p - br.position) / (br.size.x / BOARD_UNITS)
        var best := []
        var best_d := 44.0
        for w in candidate_pawns():
            var d := pawn_point(w[0], w[1]).distance_to(bp)
            var d2 := (pawn_point(w[0], w[1]) - Vector2(0, 28)).distance_to(bp)
            d = minf(d, d2)
            if d < best_d:
                best_d = d
                best = w
        if not best.is_empty(): pick_pawn(best)

var cues_played: Array = []      # testes: últimos efeitos pedidos
var _sfx := {}
func _cue(kind: String, pitch := 1.0, from_pos := 0.0):
    cues_played.append(kind)
    if cues_played.size() > 60: cues_played.pop_front()
    var path = SFX_R50.get(kind, SFX.get(kind))   # R89 · sons carregados na 1ª vez e soltos ao fechar
    var st: AudioStream = null
    if path != null:
        if not _sfx.has(kind): _sfx[kind] = load(String(path))
        st = _sfx[kind]
    if st != null: Sound.play(stage, st, float(SFX_DB.get(kind, -8.0)), pitch, from_pos)

const DOUBLE_CLICK_MS := 450
var _last_card_click := -1
var _last_card_ms := 0
func _on_hit(id: String):
    var audio = stage.get_node_or_null("GameAudio") if stage != null else null
    if audio != null and audio.has_method("play_cue"): audio.play_cue("ui")
    if id.begins_with("card_"):
        var ci := int(id.substr(5))
        var now := Time.get_ticks_msec()
        # R69 · duplo clique/toque na carta = JOGAR CARTA (o mesmo que o botão)
        if ci == _last_card_click and now - _last_card_ms <= DOUBLE_CLICK_MS and sel_card == ci:
            _last_card_click = -1
            if can_play(): confirm()
            _redraw()
            return
        _last_card_click = ci
        _last_card_ms = now
        pick_card(ci)
        return
    if id.begins_with("choice_"):
        if id == "choice_cancel": cancel()
        else: choose_function(id.substr(7))
        _redraw()
        return
    if id.begins_with("seat_"):
        var pp = _popup()
        var seat := int(id.substr(5))
        if pp != null: pp.toggle("marcha_seat_%d" % seat, seat_info(seat), _seat_screen_rect(seat))
        return
    if id.begins_with("split_"):
        pick_split(int(id.substr(6)))
        return
    match id:
        "play": confirm()
        "discard_all": discard_all()
        "cancel": cancel()
        "help": tut_page = 0
        "mute_music": Sound.volume_popup(hub, "music", _hit_screen_rect("mute_music"))   # R88 · controle de volume
        "mute_fx": Sound.volume_popup(hub, "fx", _hit_screen_rect("mute_fx"))
        "fullscreen":
            var sm = screen_mode()
            if sm != null: sm.toggle()
        "voice":
            var vo = voice()
            if vo != null: vo.press()
        "voice_off":
            var vo = voice()
            if vo != null: vo.leave("user")
        "voice_info":
            _flash("A voz funciona nas partidas online com outros jogadores.")
        "voice_ear":
            var vo = voice()
            if vo != null: vo.toggle_speaker()
        "menu": menu_open = not menu_open
        "menu_close": menu_open = false
        "menu_tutorial":
            menu_open = false
            tut_page = 0
        "menu_quit":
            menu_open = false
            if mode == "game": _record_history("abandon")
            if online: _online_leave()
            mode = "lobby"
            g = null
            access.refresh()
        "lobby_bots": if mode == "lobby": start_game()   # R145 · botões direto na tela
        "lobby_online":
            if mode == "lobby":
                var err: String = stage.party_online_queue("marcha") if stage != null and stage.has_method("party_online_queue") else "Indisponível."
                if not err.is_empty(): _flash(err)
        "lobby_play":   # R144 · CONTRA BOTS ou JOGAR ONLINE (só no lobby: o 2º toque/clique emulado não reabre)
            if mode != "lobby": pass
            elif stage != null and stage.has_method("party_choose"): stage.party_choose("marcha")
            else: start_game()
        "lobby_tutorial": tut_page = 0
        "lobby_invite": invite_friend()
        "lobby_back", "over_back": close()
        "lobby_club":
            close()
            if hub != null and hub.has_method("open_club"): hub.open_club()
        "over_again":
            online = false
            mode = "lobby"
            g = null
            access.refresh()
        "tut_prev": tut_page = maxi(0, tut_page - 1)
        "tut_next":
            if tut_page >= TUTORIAL.size() - 1:
                tut_page = -1
                Access.mark_tutorial_seen()
            else: tut_page += 1
        "tut_close":
            tut_page = -1
            Access.mark_tutorial_seen()
    _redraw()

# ---------------------------------------------------------------- layout (coordenadas de referência)
func board_rect() -> Rect2:
    if desk: return rr(LayoutR57.ART_RECT)
    return Rect2(30, 430, 1020, 1020) if portrait else Rect2(480, 103, 955, 955)

# ---------------------------------------------------------------- R57 · coordenadas das referências finais
## px da referência da partida (1672x941) -> tela de desenho (1920x1080)
## R74 · celular EM PÉ (tela 1080x1920): a mesma arte, em BLOCOS reposicionados (título, ícones, placas dos
## perfis, tabuleiro, mão, relógio/JOGAR CARTA, ajuda da jogada). Cada bloco = [retângulo na arte, destino].
## As placas dos perfis ficam numa faixa "virtual" da arte (x >= 3000), lado a lado, iguais.
const R57_VSEAT_X := 3000.0
var portrait_game: Array = []
var view_seat := 0                # R92 · cor real (reino) de quem está jogando nesta tela: 0 Marfim, 1 Rubi, 2 Ônix, 3 Esmeralda
var wide_chat := Rect2()          # R91.3 · lugar do CHAT no celular deitado
var portrait_row: Array = []      # R90 · [microfone, SUA VEZ, CHAT] lado a lado (celular em pé)
## R75.1 · em pé a tela usa a ALTURA INTEIRA do aparelho (design 1080 x altura proporcional). De cima para baixo:
## título/ícones, placas dos perfis, TABULEIRO (centralizado no espaço livre), faixa da ajuda da jogada (só aparece
## quando há algo a escolher), linha SUA VEZ + JOGAR CARTA (compacta, lado a lado) e as CARTAS rentes ao fim da tela.
func _portrait_layout():
    # R87 · em pé como a referência do dono: tabuleiro quase na largura toda, painel SUA VEZ grande logo abaixo
    # e as cartas RETAS e grandes lado a lado; espaços curtos entre os blocos (o que sobrar fica dividido em volta).
    var H: float = design.y
    var top := 262.0
    var ch := 352.0                              # cartas (4 lado a lado, ~248 de largura)
    # R90 · linha única de ponta a ponta: MICROFONE | SUA VEZ + JOGAR CARTA | CHAT, os três do mesmo tamanho
    # (a altura vem da arte do painel 330x280 na largura de 1/3 da tela). Mais baixa que o painel antigo:
    # o que sobra vai para o TABULEIRO.
    var gx := 14.0
    var sw: float = (1080.0 - 24.0 - 2.0 * gx) / 3.0
    var ph: float = sw * PANEL_LOW_SRC.size.y / PANEL_LOW_SRC.size.x   # R90.1 · painel sem a faixa da coroa (mais baixo)
    var bottom_pad := 12.0
    var min_gap := 14.0
    var bw := 1076.0                             # R90.1 · tabuleiro de ponta a ponta
    var bh: float = BOARD_SRC.size.y * bw / BOARD_SRC.size.x
    var maxb: float = H - top - ph - ch - bottom_pad - 4.0 * min_gap
    if bh > maxb:                                # aparelho baixo: encolhe as cartas e só então o tabuleiro
        ch = maxf(280.0, ch - (bh - maxb))
        maxb = H - top - ph - ch - bottom_pad - 4.0 * min_gap
        if bh > maxb:
            bh = maxb
            bw = BOARD_SRC.size.x * bh / BOARD_SRC.size.y
    # R90.2 · celular alto: o tabuleiro já está na largura toda; a altura que sobra vai para as CARTAS (crescem e
    # encostam umas nas outras, sobrepondo até 30%) e o resto é dividido igual entre os blocos (sem faixa vazia).
    var spare: float = H - top - bh - ph - ch - bottom_pad - 4.0 * min_gap
    if spare > 0.0:
        var ch_max: float = (1060.0 / (4.0 - 3.0 * CARD_OVERLAP_MAX)) * R57_CARD.y / R57_CARD.x
        ch += clampf(spare, 0.0, maxf(0.0, ch_max - ch))
    var gap: float = maxf(min_gap, (H - top - bh - ph - ch - bottom_pad) / 4.0)
    var y0: float = top + gap
    var board := Rect2((1080.0 - bw) / 2.0, y0, bw, bh)
    var panel := Rect2(12.0 + sw + gx, board.end.y + gap, sw, ph)
    portrait_row = [Rect2(12.0, panel.position.y, sw, ph), panel, Rect2(panel.end.x + gx, panel.position.y, sw, ph)]
    var cards := Rect2(20.0, panel.end.y + gap, 1040.0, ch)
    # ajuda da jogada: só quando há algo a escolher, por cima das placas, longe do tabuleiro
    var help := Rect2(8, 140, 1064, 104)
    portrait_game = [
        [Rect2(0, 0, 500, 95), Rect2(0, 0, 525, 99.75)],               # 0 título
        [Rect2(1150, 0, 500, 80), Rect2(547, 8, 525, 84)],              # 1 ícones (+ microfone/fone da voz, à esquerda)
        [Rect2(3000, 0, 740, 108), Rect2(8, 114, 1064, 155.3)],         # 2 placas (faixa virtual)
        [BOARD_SRC, board],                                             # 3 tabuleiro (justo na moldura)
        [Rect2(520, 735, 640, 206), cards],                             # 4 mão
        [PANEL_LOW_SRC, panel],                                         # 5 SUA VEZ + JOGAR CARTA (moldura, sem a coroa)
        [PANEL_LOW_SRC, panel],                                         # 6
        [Rect2(22, 504, 326, 132), help],                               # 7 ajuda da jogada / CANCELAR
    ]

## R90.1 · painel SUA VEZ do celular em pé sem a faixa da coroa: a arte painel_vez_baixo.png tira as linhas 17..77
## do painel (330x280 → 330x220); na arte da mesa o que sobra começa 60 px abaixo (só a borda de cima é colada).
const PANEL_LOW_SRC := Rect2(30, 700, 330, 220)
## R86 · moldura dourada do tabuleiro na arte da mesa (medida no PNG): só ela entra no celular em pé
const BOARD_SRC := Rect2(486, 117, 711, 637)

## salão (1494x834) em pé: título, ícones, painel do modo, tabuleiro de amostra e botões, um embaixo do outro
## R82 · celular DEITADO (tela larga): tabuleiro no meio com a altura toda; à esquerda título, perfis (em coluna)
## e SUA VEZ/JOGAR CARTA; à direita ícones e a mão. Usa a mesma lista de blocos do celular em pé.
func _wide_layout():
    var W: float = design.x
    var H := 1080.0
    var bh := 1044.0
    var bw: float = 730.0 * bh / 657.0
    var side: float = (W - bw) / 2.0
    if side < 620.0:                                             # colunas com folga para perfis e cartas grandes
        bw = W - 1240.0
        bh = 657.0 * bw / 730.0
        side = 620.0
    var board := Rect2((W - bw) / 2.0, (H - bh) / 2.0, bw, bh)
    var lw: float = side - 32.0
    # ESQUERDA: título e os três perfis ocupando a coluna inteira
    var tw: float = minf(lw, 500.0)
    var title := Rect2(16, 8, tw, tw * 95.0 / 500.0)
    var top_p: float = title.end.y + 20.0
    var ph: float = H - 20.0 - top_p
    var pw: float = minf(lw, ph * 240.0 / 344.0)
    ph = pw * 344.0 / 240.0
    var plates := Rect2(16 + (lw - pw) / 2.0, top_p + (H - 20.0 - top_p - ph) / 2.0, pw, ph)
    var help := Rect2(16, H - 16.0 - 150.0, lw, 150)          # controles do 7/10/descartar (só quando há escolha)
    # DIREITA: ícones; painel SUA VEZ + JOGAR CARTA (a arte inteira, com a moldura); cartas maiores embaixo
    var rx: float = board.end.x + 16.0
    var iw: float = minf(lw, 500.0)
    var icons := Rect2(W - 16.0 - iw, 10, iw, iw * 80.0 / 500.0)
    var cw: float = minf(lw, 1000.0)
    var ch: float = cw * 203.0 / 582.0
    var room: float = H - icons.end.y - 30.0
    var pnw: float = minf(lw * 0.82, 520.0)
    var pnh: float = pnw * 280.0 / 330.0
    if ch + pnh + 30.0 > room:                                   # falta altura: o painel encolhe primeiro (as cartas são o foco)
        pnh = maxf(room - ch - 30.0, 200.0)
        pnw = pnh * 330.0 / 280.0
        if ch + pnh + 30.0 > room:
            var f: float = room / (ch + pnh + 30.0)
            cw *= f; ch *= f; pnw *= f; pnh *= f
    var gap: float = (room - ch - pnh) / 3.0
    var panel := Rect2(rx + (lw - pnw) / 2.0, icons.end.y + 10.0 + gap, pnw, pnh)
    var cards := Rect2(rx + (lw - cw) / 2.0, panel.end.y + gap, cw, ch)
    # R91.3 · celular deitado: CHAT (mesa online) no espaço livre embaixo das cartas, sem cobrir o JOGAR CARTA
    var chh: float = clampf(H - cards.end.y - 18.0, 0.0, 96.0)
    wide_chat = Rect2(cards.end.x - 240.0, H - 10.0 - chh, 240.0, chh) if chh >= 54.0 else Rect2()
    portrait_game = [
        [Rect2(0, 0, 500, 95), title],
        [Rect2(1150, 0, 500, 80), icons],
        [Rect2(3000, 0, 240, 344), plates],          # placas em coluna (faixa virtual)
        [Rect2(480, 110, 730, 657), board],
        [Rect2(548, 738, 582, 203), cards],          # recorte justo nas 4 cartas (ficam maiores)
        [Rect2(30, 640, 330, 280), panel],           # SUA VEZ + JOGAR CARTA com a moldura da arte (sem recorte)
        [Rect2(30, 640, 330, 280), panel],
        [Rect2(22, 504, 326, 132), help],
    ]

var PORTRAIT_LOBBY: Array = []
func _portrait_lobby_layout():
    var H: float = design.y
    var btn := Rect2(48, H - 376.0 - 40.0, 984, 376)
    var info := Rect2(20, 128, 1040, 693.3)
    var room: float = btn.position.y - info.end.y
    var bs: float = clampf((room - 40.0) / 435.0, 1.1, 1.7)
    var prev := Rect2((1080.0 - 465.0 * bs) / 2.0, info.end.y + (room - 435.0 * bs) / 2.0, 465.0 * bs, 435.0 * bs)
    PORTRAIT_LOBBY = [
        [Rect2(110, 0, 430, 85), Rect2(0, 4, 473, 93.5)],
        [Rect2(1158, 6, 310, 62), Rect2(725, 12, 341, 68.2)],
        [Rect2(180, 135, 660, 440), info],
        [Rect2(845, 135, 465, 435), prev],
        [Rect2(440, 575, 615, 235), btn],
    ]

func _block_at(blocks: Array, p: Vector2) -> Array:
    for b in blocks:
        if (b[0] as Rect2).grow(1.0).has_point(p): return b
    return blocks[3] if blocks.size() > 3 else blocks[0]

func _bmap(blocks: Array, r: Rect2) -> Rect2:
    var b: Array = _block_at(blocks, r.get_center() if r.size != Vector2.ZERO else r.position)
    var sc: float = (b[1] as Rect2).size.x / (b[0] as Rect2).size.x
    return Rect2((b[1] as Rect2).position + (r.position - (b[0] as Rect2).position) * sc, r.size * sc)

## escala da arte no ponto (para o tamanho das letras): no PC é uma só; em pé, a do bloco
func r57_s_at(p: Vector2, lobby := false) -> float:
    if lobby and not portrait: return lobby_s()
    if not blk: return lobby_s() if lobby else r57_s()
    var b: Array = _block_at(PORTRAIT_LOBBY if lobby else portrait_game, p)
    return (b[1] as Rect2).size.x / (b[0] as Rect2).size.x

func r57_s() -> float:
    if blk: return r57_s_at(Vector2(845, 400))
    return design.y / R57_SIZE.y

func rp(p: Vector2) -> Vector2:
    if blk: return _bmap(portrait_game, Rect2(p, Vector2.ZERO)).position
    return Vector2((design.x - R57_SIZE.x * r57_s()) / 2.0, 0) + p * r57_s()

func rr(r: Rect2) -> Rect2:
    if blk: return _bmap(portrait_game, r)
    return Rect2(rp(r.position), r.size * r57_s())

## px da referência do salão (1494x834) -> tela de desenho
func lobby_s() -> float:
    if portrait: return r57_s_at(Vector2(500, 300), true)
    return design.y / R57_LOBBY.y

func lp(p: Vector2) -> Vector2:
    if portrait: return _bmap(PORTRAIT_LOBBY, Rect2(p, Vector2.ZERO)).position
    return Vector2((design.x - R57_LOBBY.x * lobby_s()) / 2.0, 0) + p * lobby_s()

func lr(r: Rect2) -> Rect2:
    if portrait: return _bmap(PORTRAIT_LOBBY, r)
    return Rect2(lp(r.position), r.size * lobby_s())

## perfis da referência (só avatar + nome): caixa, retrato, x do nome, linha de base, altura das maiúsculas, fim
const R57_SEATS := {
    0: {"box": Rect2(1312, 790, 333, 107), "av": Rect2(1342, 807, 78, 79), "x": 1440.0, "base": 855.0, "cap": 20.0, "end": 1628.0},
}
## R72 · as três placas dos outros jogadores são iguais (placa_perfil_N.png, 240x108 na escala da arte), cada uma
## no seu lado da mesa: esquerda (ReiDoBlitz), topo (Lady Torre) e direita (Cavalo_Louco) — no PC e no celular deitado.
const R57_PLATE := Vector2(240, 108)
const R57_PLATE_POS := {1: Vector2(374, 433), 2: Vector2(846, 54), 3: Vector2(1335.5, 433)}   # centros
const R57_PLATE_S := 0.92

func r57_seat(seat: int) -> Dictionary:
    if seat == 0: return R57_SEATS[0]
    var sc: float = R57_PLATE_S
    var c: Vector2 = R57_PLATE_POS[seat]
    if portrait:   # R74 · em pé: as três lado a lado no topo (faixa virtual da arte → bloco das placas)
        sc = 1.0
        c = Vector2(R57_VSEAT_X + 120.0 + (seat - 1) * 250.0, 54.0)
    elif wide_land:   # R82 · deitado: as três em coluna, à esquerda
        sc = 1.0
        c = Vector2(R57_VSEAT_X + 120.0, 54.0 + (seat - 1) * 118.0)
    var b := Rect2(c - R57_PLATE * sc / 2.0, R57_PLATE * sc)
    return {"box": b, "av": Rect2(b.position + Vector2(36, 15) * sc, Vector2(81, 75) * sc),
        "x": b.position.x + 128.0 * sc, "base": b.position.y + 63.5 * sc, "cap": 19.0 * sc, "end": b.position.x + 229.0 * sc}
const R57_ICONS := [["fullscreen", Rect2(1300, 12, 54, 53)], ["mute_music", Rect2(1370, 12, 54, 53)], ["mute_fx", Rect2(1440, 12, 54, 53)], ["help", Rect2(1510, 12, 54, 53)], ["menu", Rect2(1577, 12, 54, 53)]]
const R57_TIMER := Rect2(62, 720, 265, 107)
const R57_PLAY := Rect2(62, 840, 273, 62)
const R57_CARD := Vector2(138, 195)
const CARD_OVERLAP_MAX := 0.20     # R90.2 · em pé as cartas podem se sobrepor até 20% (o texto da carta continua inteiro)

func card_rect(i: int, n: int) -> Rect2:
    if desk and portrait and not portrait_game.is_empty():
        # R87 · em pé: cartas retas, grandes e lado a lado (como na referência)
        var cb: Rect2 = portrait_game[4][1]
        var cw: float = cb.size.y * R57_CARD.x / R57_CARD.y
        var gp := 14.0
        if n > 1:
            gp = minf(14.0, (cb.size.x - n * cw) / float(n - 1))
            if n >= 5 and gp < 14.0:                 # 5 cartas (3ª rodada): diminuem, sem sobrepor
                gp = 14.0
                cw = (cb.size.x - (n - 1) * gp) / float(n)
            elif gp < -cw * CARD_OVERLAP_MAX:        # nem sobrepondo cabe: a carta diminui
                gp = -cw * CARD_OVERLAP_MAX
                cw = cb.size.x / (n - (n - 1) * CARD_OVERLAP_MAX)
                gp = -cw * CARD_OVERLAP_MAX
        cw = minf(cw, cb.size.x)
        var chh: float = cw * R57_CARD.y / R57_CARD.x
        var tot: float = n * cw + (n - 1) * gp
        return Rect2(cb.position.x + (cb.size.x - tot) / 2.0 + i * (cw + gp), cb.end.y - chh, cw, chh)
    if desk:
        # R57 · mão aberta embaixo do tabuleiro, como na referência — cartas inteiras à vista
        # R91.2 · cartas 10% menores e mais baixas: a bandeja não cobre mais a borda de baixo do tabuleiro
        var gap := 126.0 if n <= 4 else 108.0
        var sz: Vector2 = R57_CARD * (0.83 if n <= 4 else 0.75)
        var cx := 838.5 + (i - (n - 1) / 2.0) * gap
        return rr(Rect2(cx - sz.x / 2.0, 931.0 - sz.y, sz.x, sz.y))
    # R38.3 · 3ª rodada do ciclo do baralho: 5 cartas na mão (menores, para caber no mesmo espaço)
    if n >= 5:
        if portrait: return Rect2(238.0 + i * 166.0, 1548.0, 152, 214)
        var cw := 124.0
        var ch := 175.0
        if i < 3: return Rect2(1484.0 + i * 137.0, 266.0, cw, ch)
        return Rect2(1552.0 + (i - 3) * 137.0, 458.0, cw, ch)
    if portrait:
        var xs := [265.0, 445.0, 612.0, 778.0]
        var ys := [1515.0, 1545.0, 1545.0, 1550.0]
        var span := 4.0 / maxf(1.0, n)
        return Rect2(xs[mini(i, 3)] + (span - 1.0) * 30.0, ys[mini(i, 3)], 180, 252)
    var col := i % 2
    var row := i / 2
    return Rect2(1490.0 + col * 200.0, 266.0 + row * 280.0, 183, 258)

# ---------------------------------------------------------------- tutorial
## R67 · COMO JOGAR com as regras ATUAIS (marcha-real-10), em itens: cada página tem "rows" [chave, texto] e,
## nas páginas de cartas, [valor da carta, nome, texto] (o PC desenha a carta de verdade ao lado). "intro"/"outro"
## são frases soltas. kind: "rules" (losango dourado), "steps" (número) ou "cards" (cartas).
const TUTORIAL := [
    {"title": "BEM-VINDO À MARCHA REAL", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png", "kind": "rules",
        "intro": "Quatro reinos correm com seus peões ao redor da mesa.",
        "rows": [["SUA DUPLA", "Você é o MARFIM (embaixo) e joga junto com o ÔNIX (em cima)."],
            ["ADVERSÁRIOS", "RUBI e ESMERALDA, também em dupla."],
            ["A VEZ", "Gira no sentido ANTI-horário (os peões andam no horário). Cada jogador tem 15 segundos."],
            ["OBJETIVO", "Coroar os 8 peões da sua dupla antes da outra dupla."]]},
    {"title": "O CAMINHO", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png", "kind": "steps", "marks": true,
        "rows": [["PÁTIO", "Onde seus 4 peões começam."],
            ["PORTÃO", "A casa de saída do seu reino."],
            ["MURALHA", "A trilha de 76 casas, no sentido horário."],
            ["ENTRADA DO SALÃO", "A casa de onde o peão entra no Salão."],
            ["SALÃO DO TRONO", "4 casas. O peão que entra é COROADO."]]},
    {"title": "AS CARTAS (1/2)", "img": "res://marcha/art/tutorial/cartas_todas.png", "kind": "cards",
        "intro": "52 cartas, em rodadas de 4, 4 e 5. Quem tem peão no Pátio sempre recebe um A ou um K. Na sua vez, jogue UMA carta.",
        "rows": [["A", "ÁS", "Você escolhe: tira um peão do Pátio, anda 11 casas ou anda 1 casa."],
            ["K", "REI", "Só tira um peão do Pátio."],
            ["Q", "DAMA", "Anda 12 casas."],
            ["J", "VALETE", "Troca um peão SEU de lugar com qualquer outra peça da mesa. Depois de coroar os 4, vale para os peões do aliado."]]},
    {"title": "AS CARTAS (2/2)", "img": "res://marcha/art/simbolos_de_acao.png", "kind": "cards",
        "rows": [["10", "DEZ", "Anda 10 casas OU faz o próximo jogador descartar 1 carta (sorteada)."],
            ["9 8 6 3 2", "NÚMEROS", "9, 8, 6, 3 e 2: andam o número de casas da carta."],
            ["7", "SETE", "Divide 7 casas entre até 2 peões seus (ex.: 4 + 3) ou anda 7 com um só."],
            ["5", "CINCO", "Anda 5 casas com QUALQUER peça da mesa."],
            ["4", "MENOS 4", "O peão VOLTA 4 casas. Saindo do Portão, cai perto da sua Entrada (atalho)."]],
        "outro": "Sem jogada possível? Descarte uma carta."},
    {"title": "CAPTURA E PROTEÇÃO", "img": "res://marcha/art/tutorial/tabuleiro_jogada_em_destaque.png", "kind": "rules",
        "rows": [["CAPTURA", "Cair na casa de outro peão manda ele de volta ao Pátio (vale até para o aliado)."],
            ["PORTÃO PROTEGIDO", "Peão parado no PRÓPRIO Portão (escudo) bloqueia a casa: ninguém passa, cai nela ou troca com ele."],
            ["ENTRADA TRANCADA", "Peão da outra dupla parado na Entrada de um reino tranca a entrada até sair. Cair nele captura."]]},
    {"title": "COROAÇÃO E VITÓRIA", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png", "kind": "rules",
        "rows": [["COROAÇÃO", "Da Entrada, o peão entra no Salão do Trono. O número precisa caber, sem passar do fundo nem pular peões seus."],
            ["AJUDE O ALIADO", "Quem coroar os 4 peões passa a jogar com os peões do aliado."],
            ["VITÓRIA", "Vence a dupla que coroar os 8 peões."]]},
    {"title": "COMO JOGAR NA TELA", "img": "res://marcha/art/tutorial/tabuleiro_jogada_em_destaque.png", "kind": "steps",
        "rows": [["ESCOLHA", "Toque numa carta: ela sobe e a linha de ajuda diz o que ela faz."],
            ["JOGUE", "Toque em JOGAR CARTA."],
            ["MOVA", "Toque na peça marcada (no 7, escolha a divisão; no A e no 10, a opção). CANCELAR devolve a carta."],
            ["TEMPO", "Se o tempo acabar, o jogo faz uma jogada por você."]]},
]

## Texto corrido da página (celular e testes): intro, itens "CHAVE: texto" e outro.
static func tutorial_text(page: Dictionary) -> String:
    var parts := []
    if page.has("intro"): parts.append(String(page.intro))
    var i := 0
    for row in page.get("rows", []):
        i += 1
        var key: String = String(row[1]) if row.size() > 2 else String(row[0])
        var pre := ("%d " % i) if String(page.get("kind", "")) == "steps" else ""
        parts.append(pre + key + ": " + String(row[row.size() - 1]))
    if page.has("outro"): parts.append(String(page.outro))
    return "\n".join(parts)

# ================================================================= desenho
class TableView extends Control:
    const Crisp := preload("res://ui_v022/crisp_tex.gd")
    # No celular o toque já chega também como clique emulado: tratar os dois = jogada dupla.
    static var EMULATED_MOUSE: bool = bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))
    var ui
    var tex_cache := {}
    func _init():
        mouse_filter = Control.MOUSE_FILTER_STOP
        # R69 · filtro linear: as cartas (giradas e reduzidas) e os peões ficavam serrilhados com o NEAREST do projeto
        texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    # R78 · SEGURAR a carta = ela aparece grande no meio da tela (para ler a função); soltar = some
    const HOLD_MS := 380
    var _hold_card := -1
    var _hold_t0 := 0
    var _hold_pos := Vector2.ZERO
    func _process(_d):
        if ui == null or _hold_card < 0 or ui.peek_card >= 0: return
        if Time.get_ticks_msec() - _hold_t0 >= HOLD_MS:
            ui.peek_card = _hold_card
            queue_redraw()
    func _hold_end():
        _hold_card = -1
        if ui.peek_card >= 0:
            ui.peek_card = -1
            queue_redraw()
    func _gui_input(event):
        if event is InputEventMouseMotion or event is InputEventScreenDrag:
            var mp: Vector2 = (event.position - ui.origin) / ui.k
            if _hold_card >= 0 and ui.peek_card < 0 and mp.distance_to(_hold_pos) > 30.0: _hold_card = -1
            if event is InputEventMouseMotion: ui.on_hover(mp)
            return
        var released: bool = (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
            or (event is InputEventScreenTouch and not event.pressed and not EMULATED_MOUSE)
        if released:
            _hold_end()
            return
        var pos := Vector2.INF
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
        elif event is InputEventScreenTouch and event.pressed and not EMULATED_MOUSE: pos = event.position
        if pos == Vector2.INF: return
        accept_event()
        var dp: Vector2 = (pos - ui.origin) / ui.k
        _hold_card = -1
        for h in range(ui.hits.size() - 1, -1, -1):
            if Rect2(ui.hits[h].rect).has_point(dp):
                var hid := String(ui.hits[h].id)
                if hid.begins_with("card_") and ui.tut_page < 0 and not ui.menu_open:
                    _hold_card = int(hid.substr(5)); _hold_t0 = Time.get_ticks_msec(); _hold_pos = dp
                break
        ui.on_press(dp)

    func _draw_peek():
        var g = ui.g
        if g == null or ui.peek_card < 0 or ui.peek_card >= g.hands[0].size(): return
        draw_rect(Rect2(-ui.origin / ui.k, size / ui.k), Color(0.02, 0.01, 0.04, 0.72))
        var d: Vector2 = ui.design
        var h: float = minf(d.y * 0.62, d.x * 0.72 * 1.4)
        var sz := Vector2(h / 1.4, h)
        var r := Rect2((d - sz) / 2.0, sz)
        for gl in 6: draw_rect(r.grow(4 + gl * 4), Color(1.0, 0.8, 0.3, 0.2 - gl * 0.03), false, 4.0)
        draw_texture_rect(Crisp.at(ui.cards[g.hands[0][ui.peek_card]], sz * ui.k), r, false)
    func tex(path: String) -> Texture2D:
        if not tex_cache.has(path): tex_cache[path] = load(path)
        return tex_cache[path]
    func _draw():
        if ui == null: return
        ui.hits.clear()
        var vs := size
        if ui.desk and (ui.portrait or (ui.wide_land and ui.mode != "lobby")):
            _portrait_bg(vs)
            if ui.mode != "lobby": _draw_bats([Rect2(Vector2.ZERO, vs)])     # R83 · atrás do tabuleiro e dos painéis
        elif ui.desk:
            # R65 · janela fora de 16:9: a arte CONTINUA nas sobras (as bordas dela, espelhadas, coladas na própria
            # arte) — antes uma cópia inteira escurecida e ampliada ficava atrás e parecia um fundo duplicado.
            var lob: bool = ui.mode == "lobby"
            var ps: Vector2 = ui.R57_LOBBY if lob else ui.R57_SIZE
            var art_tex: Texture2D = ui.r57.salao if lob else ui.r57.mesa
            var wide_tex: Texture2D = ui.r57.salao_wide if lob else ui.r57.mesa_wide
            var dr: Rect2 = ui.lr(Rect2(Vector2.ZERO, ps)) if lob else ui.rr(Rect2(Vector2.ZERO, ps))
            _fill_sides(art_tex, wide_tex, Rect2(ui.origin + dr.position * ui.k, dr.size * ui.k), vs)
        else:
            draw_texture_rect(ui.BG, Rect2(Vector2.ZERO, vs), false)
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        match ui.mode:
            "lobby":
                if ui.desk: _draw_lobby_r57()
                else: _draw_lobby()
            "game", "over":
                if ui.desk: _draw_game_r57()
                else: _draw_game()
                _draw_flies()
        if ui.mode == "over" and not ui.overlay_wait: _draw_over()
        if ui.choice_open and ui.mode == "game" and not ui.menu_open: _draw_choice()
        if ui.menu_open: _draw_menu()
        if ui.tut_page >= 0: _draw_tutorial()
        if ui.peek_card >= 0 and ui.mode == "game": _draw_peek()
        if not ui.flash.is_empty(): _draw_flash()
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    ## Preenche as sobras da janela em volta de `a` (onde a arte é desenhada): nas laterais, a versão larga da
    ## mesma arte (tools/marcha_wide_r65.py: cenário limpo da borda, sem painéis); em cima/embaixo (janela mais
    ## alta que 16:9), a linha da borda esticada e escurecida. Nada de segunda cópia da arte por trás.
    func _fill_sides(t: Texture2D, wide: Texture2D, a: Rect2, vs: Vector2):
        var ts := t.get_size()
        var s := a.size.x / ts.x
        if s <= 0.0: return
        if a.position.x > 0.5 or vs.x - a.end.x > 0.5:
            var pad := (wide.get_width() - ts.x) / 2.0
            var wr := Rect2(a.position.x - pad * s, a.position.y, wide.get_width() * s, a.size.y)
            draw_texture_rect(wide, wr, false)
            # R82 · tela mais larga que a arte larga (celular deitado com a barra do navegador): espelha a borda
            var gl: float = wr.position.x
            var gr: float = vs.x - wr.end.x
            if gl > 0.5:
                var sw: float = minf(gl, wr.size.x) / s
                draw_texture_rect_region(wide, Rect2(wr.position.x, a.position.y, -sw * s, a.size.y), Rect2(0, 0, sw, wide.get_height()))
            if gr > 0.5:
                var sw2: float = minf(gr, wr.size.x) / s
                draw_texture_rect_region(wide, Rect2(wr.end.x + sw2 * s, a.position.y, -sw2 * s, a.size.y), Rect2(wide.get_width() - sw2, 0, sw2, wide.get_height()))
        var deep := Color(0.055, 0.03, 0.07)
        if a.position.y > 0.5: _band_v(Rect2(0, 0, vs.x, a.position.y), deep, true)
        if vs.y - a.end.y > 0.5: _band_v(Rect2(0, a.end.y, vs.x, vs.y - a.end.y), deep, false)

    ## R83 · MORCEGOS: de vez em quando um bando pequeno (1 a 3) atravessa o fundo roxo, batendo as asas.
    ## Desenhados em coordenadas de tela, dentro das regiões dadas (somem suavemente nas bordas delas).
    var bats: Array = []
    var _bat_next := 2.5
    var _bat_t := -1.0
    func _draw_bats(regions: Array):
        if regions.is_empty(): return
        var now: float = ui.t
        var dt: float = clampf(now - _bat_t, 0.0, 0.1) if _bat_t >= 0.0 else 0.0
        _bat_t = now
        _bat_next -= dt
        var k: float = ui.k
        if _bat_next <= 0.0 and bats.size() < 4:
            _bat_next = randf_range(5.0, 12.0)
            var reg: Rect2 = regions[randi() % regions.size()]
            if reg.size.x > 60.0 and reg.size.y > 60.0:
                var ltr := randf() < 0.5
                var n := randi_range(1, 3)
                var y0 := randf_range(reg.position.y + reg.size.y * 0.15, reg.position.y + reg.size.y * 0.8)
                var sp := randf_range(150.0, 240.0) * maxf(k, 0.4)
                for i in n:
                    bats.append({"reg": reg, "p": Vector2((reg.position.x - 40.0 * (i + 1)) if ltr else (reg.end.x + 40.0 * (i + 1)), y0 + randf_range(-30, 30) * k),
                        "v": Vector2(sp * (1.0 if ltr else -1.0) * randf_range(0.9, 1.1), -sp * randf_range(0.05, 0.25)),
                        "ph": randf() * TAU, "fr": randf_range(9.0, 13.0), "sz": randf_range(18.0, 28.0) * maxf(k, 0.45), "wob": randf_range(0.8, 1.6)})
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        var keep := []
        for b in bats:
            b.p += b.v * dt
            b.p.y += sin(now * b.wob * 3.0 + b.ph) * 22.0 * dt * maxf(k, 0.4)
            var reg2: Rect2 = b.reg
            if not reg2.grow(80.0).has_point(b.p): continue
            keep.append(b)
            var edge := minf(minf(b.p.x - reg2.position.x, reg2.end.x - b.p.x), minf(b.p.y - reg2.position.y, reg2.end.y - b.p.y))
            var al := clampf(edge / 40.0, 0.0, 1.0)
            if al <= 0.0: continue
            _bat_shape(b.p, b.sz, sin(now * b.fr + b.ph), signf(b.v.x), al)
        bats = keep
        if not bats.is_empty() or _bat_next < 0.5: queue_redraw()

    func _bat_shape(c: Vector2, s: float, flap: float, dir: float, al: float):
        var col := Color(0.04, 0.02, 0.06, 0.92 * al)
        var up := flap * 0.9                      # -1 asas para baixo · +1 asas para cima
        for side in [-1.0, 1.0]:
            var tip := c + Vector2(side * s * 1.9, -up * s * 1.1)
            var mid := c + Vector2(side * s * 1.0, -up * s * 0.55 - s * 0.25)
            var pts := PackedVector2Array([
                c + Vector2(side * s * 0.25, -s * 0.15), mid, tip,
                tip + Vector2(-side * s * 0.35, s * 0.45),
                c + Vector2(side * s * 1.2, -up * s * 0.35 + s * 0.35),
                c + Vector2(side * s * 0.85, -up * s * 0.2 + s * 0.15),
                c + Vector2(side * s * 0.55, s * 0.35),
                c + Vector2(side * s * 0.2, s * 0.25)])
            draw_colored_polygon(pts, col)
        draw_circle(c + Vector2(0, s * 0.05), s * 0.32, col)
        var hd := c + Vector2(dir * s * 0.12, -s * 0.28)
        draw_circle(hd, s * 0.22, col)
        draw_colored_polygon(PackedVector2Array([hd + Vector2(-s * 0.2, -s * 0.05), hd + Vector2(-s * 0.12, -s * 0.38), hd + Vector2(-s * 0.02, -s * 0.12)]), col)
        draw_colored_polygon(PackedVector2Array([hd + Vector2(s * 0.2, -s * 0.05), hd + Vector2(s * 0.12, -s * 0.38), hd + Vector2(s * 0.02, -s * 0.12)]), col)

    ## R74 · fundo do celular em pé: a parede do salão (lado esquerdo da mesa larga, sem painéis) repetida na
    ## altura da tela e escurecida, com a faixa escura do topo atrás do título e dos ícones
    func _portrait_bg(vs: Vector2):
        var wide: Texture2D = ui.r57.mesa_wide
        var src := Rect2(0, 90, 740, 550)            # parede do salão sem painéis (lado esquerdo da arte larga)
        if ui.portrait:
            var sc: float = maxf(vs.x / src.size.x, vs.y / src.size.y)
            var dst := Rect2((vs - src.size * sc) / 2.0, src.size * sc)
            draw_texture_rect_region(wide, dst, src)    # uma cópia só (sem repetir o cenário)
        else:
            # R82 · deitado: a mesma parede à esquerda e espelhada à direita (o tabuleiro cobre o meio)
            var half := Vector2(vs.x / 2.0 + 1.0, vs.y)
            var sc2: float = maxf(half.x / src.size.x, half.y / src.size.y)
            var sz: Vector2 = src.size * sc2
            draw_texture_rect_region(wide, Rect2(Vector2(half.x - sz.x, (vs.y - sz.y) / 2.0), sz), src)
            draw_set_transform(Vector2(vs.x, 0), 0.0, Vector2(-1, 1))     # espelho: a mesma parede do lado direito
            draw_texture_rect_region(wide, Rect2(Vector2(half.x - sz.x, (vs.y - sz.y) / 2.0), sz), src)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        if not ui.portrait:
            draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.01, 0.05, 0.62))
            return
        # R86 · em pé: a cena aparece mais (menos escura) e escurece aos poucos para cima e para baixo,
        # sem a faixa preta reta no topo — os painéis ficam "dentro" do salão
        draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.01, 0.05, 0.42))
        var tb: float = ui.origin.y + 280.0 * ui.k
        var n := 24
        for i in n:
            var f := float(i) / n
            draw_rect(Rect2(0, tb * f, vs.x, tb / n + 1.0), Color(0.04, 0.02, 0.06, 0.88 * (1.0 - f * f)))
        var bb: float = vs.y * 0.22
        for i in n:
            var f := float(i) / n
            draw_rect(Rect2(0, vs.y - bb * (1.0 - f) - bb / n, vs.x, bb / n + 1.0), Color(0.03, 0.01, 0.05, 0.55 * (1.0 - f) * (1.0 - f)))
        # vinheta nas laterais
        for i in 10:
            var w: float = 6.0 * ui.k * (i + 1)
            draw_rect(Rect2(0, 0, w, vs.y), Color(0, 0, 0, 0.035))
            draw_rect(Rect2(vs.x - w, 0, w, vs.y), Color(0, 0, 0, 0.035))

    ## R86 · sombra suave em volta de um bloco (tabuleiro/painel), para ele assentar no cenário em vez de parecer colado
    func _soft_shadow(r: Rect2):
        for i in 7:
            draw_rect(r.grow(4.0 + i * 7.0), Color(0.0, 0.0, 0.0, 0.10 - i * 0.012), false, 7.0)
        draw_rect(r.grow(2.0), Color(0.95, 0.72, 0.3, 0.12), false, 3.0)

    ## faixa de cima/baixo: roxo profundo do salão, com uma luz dourada fraca junto da arte
    func _band_v(r: Rect2, deep: Color, toward_bottom: bool):
        draw_rect(r, deep)
        var n := 16
        for i in n:
            var f := float(i) / n
            var h := minf(r.size.y, 90.0) / n
            var y := (r.end.y - (i + 1) * h) if toward_bottom else (r.position.y + i * h)
            draw_rect(Rect2(r.position.x, y, r.size.x, h + 0.5), Color(0.85, 0.62, 0.25, 0.10 * (1.0 - f)))
        var ly := r.end.y - 1.5 if toward_bottom else r.position.y + 0.5
        draw_line(Vector2(r.position.x, ly), Vector2(r.end.x, ly), Color(0.85, 0.66, 0.31, 0.55), 2.0)

    func _ellipse(c: Vector2, r: Vector2, col: Color):
        var pts := PackedVector2Array()
        for i in 24: pts.append(c + Vector2(cos(TAU * i / 24.0) * r.x, sin(TAU * i / 24.0) * r.y))
        draw_colored_polygon(pts, col)

    # ------------------------------------------------------------ primitivas
    func text(s: String, pos: Vector2, font_key: String, fs: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0, ocol := Color.BLACK):
        if outline > 0: draw_string_outline(ui.fonts[font_key], pos, s, align, width, fs, outline, ocol)
        draw_string(ui.fonts[font_key], pos, s, align, width, fs, col)
    func text_w(s: String, font_key: String, fs: int) -> float:
        return ui.fonts[font_key].get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    func fit(s: String, font_key: String, fs: int, room: float) -> int:
        var f := fs
        while f > 10 and text_w(s, font_key, f) > room: f -= 1
        return f
    func panel(r: Rect2, glow := false, fill: Color = Color("15213b")):
        if ui.desk:
            _panel_r57(r, glow)
            return
        if glow:
            for i in 4: draw_rect(r.grow(2 + i * 3), Color(1.0, 0.8, 0.35, 0.16 - i * 0.035), false, 3.0)
        draw_rect(r, fill)
        draw_rect(r, Color("c99a45") if not glow else Color("ffd770"), false, 3.0)
        draw_rect(r.grow(-6), Color(0.79, 0.6, 0.27, 0.35), false, 1.0)
    func gold_button(r: Rect2, label: String, fs: int, id: String, enabled := true):
        var top := Color("ffd65c") if enabled else Color("8a7a4a")
        var bot := Color("e9a417") if enabled else Color("6b5a2c")
        for i in int(r.size.y):
            var f := float(i) / r.size.y
            draw_line(r.position + Vector2(0, i), r.position + Vector2(r.size.x, i), top.lerp(bot, f), 1.0)
        draw_rect(r, Color("5a3b06"), false, 2.0)
        draw_rect(r.grow(-3), Color(1, 0.95, 0.75, 0.45), false, 1.0)
        draw_line(r.position + Vector2(3, r.size.y - 4), r.end - Vector2(3, 4), Color(0.45, 0.28, 0.02, 0.6), 2.0)
        var f2 := fit(label, "bold_sp", fs, r.size.x - 24)
        text(label, Vector2(r.position.x, r.get_center().y + f2 * 0.36), "bold_sp", f2, Color("2a1a04") if enabled else Color("3a3220"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        if enabled: ui.hits.append({"rect": r, "id": id})
    ## R65 · tema da mesa nova (PC): roxo profundo do salão, ouro envelhecido, cantos com losango.
    const R57_FILL := Color("150a1d")
    const R57_FILL2 := Color("241030")
    const R57_GOLD := Color("d9aa4f")
    const R57_GOLD_HI := Color("ffd98a")
    func _panel_r57(r: Rect2, glow := false):
        if glow:
            for i in 4: draw_rect(r.grow(2 + i * 3), Color(1.0, 0.78, 0.35, 0.14 - i * 0.03), false, 3.0)
        var steps := 24
        for i in steps:
            var f := float(i) / steps
            draw_rect(Rect2(r.position + Vector2(0, r.size.y * f), Vector2(r.size.x, r.size.y / steps + 1.0)), R57_FILL2.lerp(R57_FILL, f))
        draw_rect(r, R57_GOLD, false, 3.0)
        draw_rect(r.grow(-7), Color(0.85, 0.66, 0.31, 0.55), false, 1.5)
        draw_rect(r.grow(-11), Color(0.85, 0.66, 0.31, 0.18), false, 1.0)
        for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y)]:
            _diamond(c, 9.0, R57_GOLD_HI, Color("5a3b06"))
    func _diamond(c: Vector2, s: float, fill: Color, line: Color):
        var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
        draw_colored_polygon(pts, fill)
        draw_polyline(pts + PackedVector2Array([pts[0]]), line, 1.5)
    func dark_button(r: Rect2, label: String, fs: int, id: String, enabled := true):
        if ui.desk:
            draw_rect(r, Color("1d0d28") if enabled else Color("140a1a"))
            draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(1, 1, 1, 0.04))
            draw_rect(r, R57_GOLD if enabled else Color("4a3d30"), false, 2.0)
            draw_rect(r.grow(-5), Color(0.85, 0.66, 0.31, 0.3), false, 1.0)
            var fr := fit(label, "bold_sp", fs, r.size.x - 20)
            text(label, Vector2(r.position.x, r.get_center().y + fr * 0.36), "bold_sp", fr, Color("f4ead2") if enabled else Color("6b6060"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, Color(0.05, 0.02, 0.06, 0.8))
            if enabled: ui.hits.append({"rect": r, "id": id})
            return
        draw_rect(r, Color("0a0f18"))
        draw_rect(r, Color("c99a45") if enabled else Color("4a4030"), false, 2.0)
        draw_rect(r.grow(-5), Color(0.79, 0.6, 0.27, 0.25), false, 1.0)
        var f2 := fit(label, "bold_sp", fs, r.size.x - 20)
        text(label, Vector2(r.position.x, r.get_center().y + f2 * 0.36), "bold_sp", f2, ui.CREAM if enabled else Color("6b6656"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        if enabled: ui.hits.append({"rect": r, "id": id})
    func square_button(r: Rect2, glyph: String, id: String):
        draw_rect(r, Color("0e141f"))
        draw_rect(r, ui.GOLD, false, 2.0)
        if glyph == "?":
            text("?", Vector2(r.position.x, r.get_center().y + 11), "bold", 30, ui.GOLD, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        else:
            for i in 3: draw_line(r.get_center() + Vector2(-9, -6 + i * 6), r.get_center() + Vector2(9, -6 + i * 6), ui.GOLD, 2.5)
        ui.hits.append({"rect": r, "id": id})
    func fullscreen_button(r: Rect2, on: bool):
        draw_rect(r, Color("0e141f"))
        draw_rect(r, ui.GOLD, false, 2.0)
        ui.FullscreenControl.draw_glyph(self, r.grow(-6), on, ui.GOLD, 2.5)
        ui.hits.append({"rect": r, "id": "fullscreen"})
    func sound_button(r: Rect2, kind: String):
        var off: bool = ui.Sound.music_muted(ui.hub) if kind == "music" else ui.Sound.effects_muted(ui.hub)
        draw_rect(r, Color("0e141f"))
        draw_rect(r, ui.GOLD, false, 2.0)
        ui.Sound.glyph(self, r.grow(-6), kind, off, ui.GOLD if not off else Color("6b6656"))
        ui.hits.append({"rect": r, "id": "mute_music" if kind == "music" else "mute_fx"})
    func diamond(c: Vector2, rr: float, col: Color, filled := true):
        var pts := PackedVector2Array([c + Vector2(0, -rr), c + Vector2(rr, 0), c + Vector2(0, rr), c + Vector2(-rr, 0)])
        if filled: draw_colored_polygon(pts, col)
        else:
            pts.append(pts[0])
            draw_polyline(pts, col, 2.0)

    # ------------------------------------------------------------ barra do modo
    func _draw_bar():
        var w: float = ui.design.x
        draw_rect(Rect2(0, 0, w, 82 if not ui.portrait else 116), Color(0.029, 0.043, 0.071, 0.55))
        var by := 82.0 if not ui.portrait else 116.0
        draw_line(Vector2(0, by), Vector2(w, by), ui.GOLD_LINE, 2.0)
        var ty := 44.0 if not ui.portrait else 58.0
        text("MARCHA REAL", Vector2(28, ty), "title", 40 if not ui.portrait else 46, Color("e9b94a"))
        var sub := "MODO DE CARTAS E CORRIDA"
        if ui.g != null:
            sub = "RODADA %d · %d X %d PEÕES COROADOS" % [ui.g.round_no, ui.g.team_crowned(0), ui.g.team_crowned(1)]
        text(sub, Vector2(28, by - 12 if not ui.portrait else by - 22), "semi_sp2", 17 if not ui.portrait else 21, Color("d9a441"))
        var bs := 50.0 if not ui.portrait else 64.0
        var gap := 64.0 if not ui.portrait else 78.0
        var right := w - (78.0 if not ui.portrait else 92.0)
        var top := 16.0 if not ui.portrait else 26.0
        if ui.mode == "game":
            square_button(Rect2(right - gap, top, bs, bs), "?", "help")
            square_button(Rect2(right, top, bs, bs), "=", "menu")
            right -= gap * 2
        # MÚSICA / EFEITOS: no salão e na partida
        sound_button(Rect2(right - gap, top, bs, bs), "music")
        sound_button(Rect2(right, top, bs, bs), "fx")
        # R43 · TELA CHEIA (o mesmo botão da Home), à esquerda da música
        var sm = ui.screen_mode()
        if sm != null and sm.supported(): fullscreen_button(Rect2(right - gap * 2, top, bs, bs), sm.on_cached())
        # R45 · FRAIHA Voice: só na partida online com outro humano (no navegador)
        var vo = ui.voice()
        if ui.mode == "game" and vo != null and vo.in_match() and vo.available():
            var vr := Rect2(right - gap * 3, top, bs, bs)
            draw_rect(vr, Color("0e141f"))
            draw_rect(vr, ui.GOLD, false, 2.0)
            ui.VoiceGlyph.draw_mic(self, vr.grow(-6), vo.state, ui.GOLD, vo.is_speaking(vo.my_uid))
            ui.hits.append({"rect": vr, "id": "voice"})
            if vo.active() or vo.state == "ERROR": ui.hits.append({"rect": ui.VoiceGlyph.draw_leave_badge(self, vr), "id": "voice_off"})
            var text_right := vr.position.x - 12
            if vo.active():
                # ÁUDIO RECEBIDO (fone): ouvir / não ouvir os outros, sem sair da sala nem mexer no microfone
                var er := Rect2(right - gap * 4, top, bs, bs)
                draw_rect(er, Color("0e141f"))
                draw_rect(er, ui.GOLD, false, 2.0)
                ui.VoiceGlyph.draw_headphones(self, er.grow(-7), vo.speaker_muted, ui.GOLD)
                ui.hits.append({"rect": er, "id": "voice_ear"})
                text_right = er.position.x - 12
            if not ui.portrait: ui.VoiceGlyph.draw_status(self, text_right, vr.get_center().y, 330, vo.status_text(), 18, Color("e8dcc0"))

    # ------------------------------------------------------------ placas dos jogadores
    ## R41 · moldura (Club / Fundador) e selo do jogador humano sobre o retrato da placa.
    func _look(pr: Rect2, look: Dictionary):
        if look.is_empty(): return
        match ui.Cosmetics.public_frame(look):
            "club":
                draw_rect(pr.grow(3), Color("e9b94a"), false, 4.0)
                draw_rect(pr.grow(-1), Color("fff1c0"), false, 1.0)
            "fundador":
                draw_rect(pr.grow(4), Color("1b150e"), false, 5.0)
                draw_rect(pr.grow(2), Color("d9a441"), false, 2.0)
        var tex: Texture2D = ui.Cosmetics.badge_texture(ui.Cosmetics.public_badge(look))
        if tex != null:
            var side := clampf(pr.size.x * 0.42, 16.0, 44.0)
            draw_texture_rect(tex, Rect2(pr.end - Vector2(side * 0.8, side * 0.8), Vector2(side, side)), false)

    func _plate(r: Rect2, seat: int, big := false):
        ui.hits.append({"rect": r, "id": "seat_%d" % seat})     # R37: cartão de perfil (mouse / toque)
        var g = ui.g
        var lit: bool = g != null and g.turn == seat and ui.mode == "game"
        panel(r, lit or (seat == 0 and not ui.portrait), ui.PANEL)
        var narrow: bool = ui.portrait and r.size.x < 300.0
        var ps := r.size.y - (32.0 if narrow else 22.0)
        var pr := Rect2(r.position + (Vector2(10, 13) if narrow else Vector2(11, 11)), Vector2(ps, ps))
        var tex: Texture2D
        if seat == 0:
            # "Você": retrato Marfim da referência
            draw_texture_rect(ui.portraits.voce, pr, false)
            if ui.my_portrait != null:
                draw_texture_rect(ui.my_portrait, pr.grow(-ps * 0.075), false)
        else:
            var friend: Texture2D = ui.seat_avatar(seat)   # R41 · amigo online: o avatar dele
            draw_texture_rect(friend if friend != null else ui.portraits[ui.BOTS[seat].portrait], pr, false)
        _look(pr, ui.seat_look(seat))
        if ui.online: ui.VoiceGlyph.draw_seat_voice(self, pr, ui.voice(), seat)   # R46 · quem está na voz / falando
        var x := pr.end.x + (10.0 if narrow else 12.0)
        # placas estreitas (celular em retrato): a referência usa letras e marcadores menores
        var sc := 0.8 if r.size.x < 300.0 else 1.0
        var avail := r.end.x - x - 10.0
        var nm: String = ui.names[seat]
        var nfs := fit(nm, "bold", 27 if narrow else 30, avail - (92.0 if seat == 2 else 0.0))
        text(nm, Vector2(x, r.position.y + (36.0 if ui.portrait else 40.0)), "bold", nfs, ui.CREAM)
        if seat == 2:
            var tw := text_w("ALIADO", "bold_sp", 15) + 16
            var tr := Rect2(Vector2(x + text_w(nm, "bold", nfs) + 12, r.position.y + 20), Vector2(tw, 24))
            draw_rect(tr, Color("f0c44c"))
            text("ALIADO", Vector2(tr.position.x, tr.position.y + 18), "bold_sp", 15, Color("1c1405"), tr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        var n: int = g.hands[seat].size() if g != null else 4
        var home: int = g.in_home(seat) if g != null else 4
        if ui.portrait:
            # celular em retrato (tela_celular): losango cheio com contorno dourado, nome do reino sem
            # espaçamento largo, versos de carta sobrepostos e bolinhas maiores
            var kyp := r.position.y + 58.0
            if seat != 2: diamond(Vector2(x + 10, kyp), 10, ui.KINGDOM_COLOR[seat])
            diamond(Vector2(x + 10, kyp), 10, Color("d9b45e"), false)
            var klp: String = ui.KINGDOM_LABEL[seat]
            text(klp, Vector2(x + 26, kyp + 9), "bold", fit(klp, "bold", 25, avail - 26), ui.KINGDOM_COLOR[seat].lightened(0.25))
            for c in n:
                var crp := Rect2(Vector2(x + c * 14, r.position.y + 72), Vector2(24, 33))
                if ui.card_back != null: draw_texture_rect(ui.card_back, crp, false)
                draw_rect(crp, Color(0, 0, 0, 0.5), false, 1.0)
            var dxp := x + (maxi(n, 1) - 1) * 14 + 24 + 23
            for d in 4:
                var cp := Vector2(dxp + d * 19, r.position.y + 89)
                if d < home: draw_circle(cp, 6.0, ui.KINGDOM_DOT[seat])
                draw_arc(cp, 6.0, 0, TAU, 20, Color("cfd3cf") if d >= home else Color(1, 1, 1, 0.6), 1.5)
            return
        var ky := r.position.y + 61.0
        diamond(Vector2(x + 9, ky), 8, ui.KINGDOM_COLOR[seat], seat != 2)
        if seat == 2: diamond(Vector2(x + 9, ky), 8, ui.KINGDOM_COLOR[seat], false)
        var kl: String = ui.KINGDOM_LABEL[seat]
        text(kl, Vector2(x + 22, ky + 8), "semi_sp2", fit(kl, "semi_sp2", 20, avail - 22), ui.KINGDOM_COLOR[seat])
        # cartas na mão (versos) e peões ainda no Pátio
        for c in n:
            var cr := Rect2(Vector2(x + c * 17, r.position.y + 84), Vector2(16, 24))
            draw_rect(cr, Color("253962"))
            draw_rect(cr, Color("b8892f"), false, 1.0)
            diamond(cr.get_center(), 3, Color("d9b45e"))
        var dx := x + maxf(n, 3) * 17 + 18
        for d in 4:
            var c := Vector2(dx + d * 21, r.position.y + 96)
            if d < home: draw_circle(c, 6.5, ui.KINGDOM_DOT[seat])
            draw_arc(c, 6.5, 0, TAU, 20, Color("cfd3cf") if d >= home else Color(1, 1, 1, 0.6), 1.5)

    # ------------------------------------------------------------ tabuleiro, peões e descarte
    ## R92 · mesa online: cada jogador se vê no canto de baixo (lugar 0), mas com a SUA cor de verdade. A arte tem as cores
    ## fixas (Marfim embaixo, Rubi à esquerda, Ônix em cima, Esmeralda à direita); aqui a base, a pista de chegada e a
    ## marca de saída de cada lugar são trocadas pelas da cor real de quem está ali (recortes em r57/cores).
    const VIEW_PARTS := {
        "base": [Vector2(476.4, 1133.2), Vector2(297.2, 383.4), Vector2(1151.5, 251.2), Vector2(1309.3, 1008.2)],
        "saida": [Vector2(678.1, 1324.3), Vector2(98.6, 560.0), Vector2(931.5, 84.2), Vector2(1499.2, 816.4)],
    }
    ## pista de chegada de cada lugar (px da arte, medida): cada uma tem tamanho próprio na arte; a peça trocada
    ## (r57/cores/pista_l<lugar>_c<cor>.png) já vem girada e no tamanho exato deste retângulo (+1 px de folga)
    const VIEW_LANES := [Rect2(828, 573, 38, 125), Rect2(543, 405, 130, 45), Rect2(827, 163, 40, 120), Rect2(1016, 405, 128, 45)]
    func _draw_view_colors(br: Rect2, s: float):
        var art_k := 730.0 / 1600.0           # px da arte por unidade do tabuleiro
        var art0 := Vector2(480, 110)          # canto do tabuleiro na arte (ART_RECT)
        for seat in 4:
            var f: int = (seat + ui.view_seat) % 4
            if f == seat: continue
            # pista: retângulo exato do lugar
            var lt: Texture2D = ui._mt("res://marcha/art/r57/cores/pista_l%d_c%d.png" % [seat, f])
            if lt != null:
                var lr: Rect2 = VIEW_LANES[seat].grow(1.0)
                var p0: Vector2 = br.position + (lr.position - art0) / art_k * s
                draw_set_transform(ui.origin + p0 * ui.k, 0.0, Vector2(ui.k, ui.k))
                draw_texture_rect(lt, Rect2(Vector2.ZERO, lr.size / art_k * s), false)
            for kind in ["base", "saida"]:
                var tex: Texture2D = ui._mt("res://marcha/art/r57/cores/%s_%d.png" % [kind, f])
                if tex == null: continue
                var c: Vector2 = br.position + Vector2(VIEW_PARTS[kind][seat]) * s
                var sc: float = s / art_k
                draw_set_transform(ui.origin + c * ui.k, 0.0, Vector2(ui.k * sc, ui.k * sc))
                draw_texture(tex, -tex.get_size() / 2.0)
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

    func _draw_board():
        var br: Rect2 = ui.board_rect()
        if not ui.desk: draw_texture_rect(ui.BOARD, br, false)     # R57: no PC o tabuleiro já está na placa da mesa
        var s: float = br.size.x / ui.BOARD_UNITS
        if ui.view_seat != 0: _draw_view_colors(br, s)
        var g = ui.g
        if g == null: return
        draw_set_transform(ui.origin + br.position * ui.k, 0.0, Vector2(ui.k * s, ui.k * s))
        # descarte sobre o emblema central
        var n: int = ui.pile.size()
        var rots := [-0.21, 0.13, -0.06]
        for j in range(maxi(0, n - 3), n):
            var it: Dictionary = ui.pile[j]
            var rank: String = it.rank
            var a: float = rots[(j - maxi(0, n - 3)) % 3]
            var cs := Vector2(270, 378)
            draw_set_transform(ui.origin + (br.position + ui.pile_center() * s) * ui.k, a, Vector2(ui.k * s, ui.k * s))
            # R37.3 · carta descartada sem jogada: cinza-avermelhada (diferente das cartas jogadas)
            var mod := Color(0.55, 0.47, 0.47) if bool(it.dead) else Color.WHITE
            draw_texture_rect(Crisp.at(ui.cards[rank], cs * s * ui.k), Rect2(-cs / 2.0, cs), false, mod)
            if bool(it.dead):
                draw_line(Vector2(-cs.x * 0.36, -cs.y * 0.3), Vector2(cs.x * 0.36, cs.y * 0.3), Color(0.55, 0.06, 0.06, 0.75), 14.0)
                draw_line(Vector2(cs.x * 0.36, -cs.y * 0.3), Vector2(-cs.x * 0.36, cs.y * 0.3), Color(0.55, 0.06, 0.06, 0.75), 14.0)
        # R38.2 · carta JOGADA esperando a peça: fica por cima do monte, com brilho dourado
        if ui.card_played and ui.sel_card >= 0 and ui.sel_card < g.hands[0].size():
            var cs2 := Vector2(270, 378)
            draw_set_transform(ui.origin + (br.position + ui.pile_center() * s) * ui.k, 0.04, Vector2(ui.k * s, ui.k * s))
            var lr := Rect2(-cs2 / 2.0, cs2)
            var pz := 0.5 + 0.5 * sin(ui.t * 5.0)
            for gl in 5: draw_rect(lr.grow(4 + gl * 5), Color(1.0, 0.82, 0.3, (0.30 - gl * 0.05) * (0.6 + 0.4 * pz)), false, 5.0)
            draw_texture_rect(Crisp.at(ui.cards[String(g.hands[0][ui.sel_card])], cs2 * s * ui.k), lr, false)
        draw_set_transform(ui.origin + br.position * ui.k, 0.0, Vector2(ui.k * s, ui.k * s))
        # R82/R83 · Entrada do Salão TRANCADA: peão da outra dupla PARADO nela → a casa fica vermelha (só depois que
        # ele pousa: enquanto anda, nada) e ganha um X preto ao lado do peão (desenhado com os peões, mais abaixo)
        var blocked := _blocked_entries(g)
        for ec in blocked:
            # casa escurecida em vermelho e um X VERMELHO dentro do círculo (fica embaixo do peão)
            draw_circle(ec, 29.0, Color(0.30, 0.02, 0.03, 0.85))
            draw_arc(ec, 27.5, 0.0, TAU, 40, Color(0.85, 0.08, 0.10), 3.0)
            for d in [Vector2(1, 1), Vector2(1, -1)]:
                draw_line(ec - d * 19.0, ec + d * 19.0, Color(0.95, 0.12, 0.14, 0.9), 11.0)   # contorno vermelho
                draw_line(ec - d * 18.0, ec + d * 18.0, Color(0.02, 0.01, 0.01), 7.0)           # X PRETO
        # caminho da jogada escolhida
        var dots: Array = []
        var dest: Array = []
        var pd: Dictionary = ui.pending
        if not pd.is_empty() and not ui.busy and g.turn == 0:
            _collect_path(g, pd, dots, dest)
        # R37 · todas as casas que a peça vai andar ficam acesas e o destino brilha;
        # se o destino tem peão adversário: ABATER (vermelho); peão do aliado: CUIDADO.
        var caps: Dictionary = ui.captures_of(pd) if not pd.is_empty() and not ui.busy and g.turn == 0 else {"enemy": [], "ally": [], "crown": []}
        var pul2 := 0.5 + 0.5 * sin(ui.t * 6.0)
        # R70 · sem números: as casas do caminho ACENDEM (luz dourada suave) e a casa onde o peão cai acende forte
        for j in dots.size():
            var p: Vector2 = dots[j]
            var pz := 0.85 + 0.15 * sin(ui.t * 5.0 - j * 0.5)          # acende em onda, do peão até o destino
            draw_circle(p, 25.0, Color(1.0, 0.72, 0.15, 0.30 * pz))
            draw_circle(p, 19.0, Color(1.0, 0.76, 0.22, 0.62 * pz))
            draw_arc(p, 19.5, 0, TAU, 28, Color(1.0, 0.95, 0.68, 0.95), 2.5)
        for p in dest:
            var hit_enemy := false
            var hit_ally := false
            for w in caps.enemy: if ui.pawn_point(w[0], w[1]).distance_to(p) < 6.0: hit_enemy = true
            for w in caps.ally: if ui.pawn_point(w[0], w[1]).distance_to(p) < 6.0: hit_ally = true
            var col := Color("e8323a") if hit_enemy else (Color("ff9a2e") if hit_ally else Color("ffd660"))
            for gl in 4: draw_circle(p, 26.0 + gl * 7.0 + 4.0 * pul2, Color(col.r, col.g, col.b, 0.22 - gl * 0.05))
            draw_circle(p, 21.0, Color(col.r, col.g, col.b, 0.62))
            draw_arc(p, 22.0, 0, TAU, 36, Color("fff2c2"), 3.0)
            if hit_enemy or hit_ally: _tag(p + Vector2(0, -118), "ABATER!" if hit_enemy else "CUIDADO: ALIADO", col)
            elif not caps.crown.is_empty() and p == dest[dest.size() - 1]: _tag(p + Vector2(0, -118), "CHEGADA!", Color("2f9e57"))
        # peões (de cima para baixo, para a base de baixo ficar na frente)
        var order: Array = []
        for st in 4:
            for i in 4: order.append([st, i])
        order.sort_custom(func(a, b): return ui.pawn_point(a[0], a[1]).y < ui.pawn_point(b[0], b[1]).y)
        var cands: Array = ui.candidate_pawns()
        var pulse := 0.5 + 0.5 * sin(ui.t * 5.0)
        for w in order:
            var c: Vector2 = ui.pawn_point(w[0], w[1])
            var lift := 0.0
            var key := "%d_%d" % [w[0], w[1]]
            var alpha: float = ui.anim_alpha.get(key, 1.0)
            var glowing: bool = ui.swap_glow.has(w) or (ui.sel_card >= 0 and ui.g.hands[0].size() > ui.sel_card and ui.g.hands[0][ui.sel_card] == "J" and (w == ui.sel_pawn or w == ui.sel_target))
            if glowing:
                # R35.1 · peças da troca brilhando (aura dourada pulsando)
                for gl in 5: draw_circle(c + Vector2(0, -14), 30.0 + gl * 8.0 + pulse * 6.0, Color(1.0, 0.84, 0.36, 0.22 - gl * 0.04))
                draw_arc(c + Vector2(0, 2), 28.0 + pulse * 3.0, 0, TAU, 40, Color(1.0, 0.93, 0.6, 0.95), 4.0)
            if cands.has(w):
                draw_arc(c + Vector2(0, 2), 25.0, 0, TAU, 36, Color(1.0, 0.82, 0.32, 0.55 + 0.45 * pulse), 3.0)
            if w == ui.sel_pawn or w == ui.sel_target or w == ui.sel_second:
                draw_arc(c + Vector2(0, 2), 26.0, 0, TAU, 36, Color(1, 1, 1, 0.95), 5.0)
                lift = 6.0
            var crowned: bool = g.pawns[w[0]][w[1]].zone == "lane"
            var tx: Texture2D = ui.pawn_tex[w[0]]      # R70: coroado continua peão, com a COROA na cabeça (arte do dono)
            var sz: Vector2 = tx.get_size() * (0.34 if ui.desk else ui.PAWN_SCALE)     # R57: peões do tamanho da arte final
            if ui.desk:   # R66/R68: no Pátio do tamanho da casa; na Muralha e no Salão menor, do tamanho da conta
                var hp: float = ui.DESK_PAWN_H if g.pawns[w[0]][w[1]].zone == "home" else ui.DESK_PAWN_H_TRACK
                sz = tx.get_size() * (hp / tx.get_height())
            var rr := Rect2(Vector2(c.x - sz.x / 2.0, c.y + ui.PAWN_BASE - sz.y - lift), sz)
            if ui.desk:
                # R67 · acabamento: sombra macia sob o peão e arte em alta reduzida (Lanczos) para o tamanho real na tela
                var foot := Vector2(c.x, c.y + ui.PAWN_BASE - 2.0)
                for i in 3: _ellipse(foot, Vector2(sz.x * (0.50 - i * 0.08), sz.x * (0.17 - i * 0.03)), Color(0, 0, 0, (0.14 + i * 0.07) * alpha))
                tx = Crisp.at(tx, sz * ui.k * s)
            if ui.anim_rot.has(key):
                # R38.3 · peão abatido girando em volta do próprio centro, a caminho da base
                var th: float = ui.anim_rot[key]
                var piv := rr.get_center()
                var o0: Vector2 = ui.origin + br.position * ui.k
                var sc0: float = ui.k * s
                draw_set_transform(o0 + sc0 * (piv - piv.rotated(th)), th, Vector2(sc0, sc0))
                draw_texture_rect(tx, rr, false, Color(1, 1, 1, alpha))
                draw_set_transform(o0, 0.0, Vector2(sc0, sc0))
            else: draw_texture_rect(tx, rr, false, Color(1, 1, 1, alpha))
            if crowned and not ui.anim_rot.has(key):
                var cw: float = rr.size.x * 1.05
                var crr := Rect2(Vector2(rr.get_center().x - cw / 2.0, rr.position.y - cw * 0.62), Vector2(cw, cw))
                draw_texture_rect(Crisp.at(ui.CROWN_TEX, crr.size * ui.k * s) if ui.desk else ui.CROWN_TEX, crr, false, Color(1, 1, 1, alpha))
            var pw: Dictionary = g.pawns[w[0]][w[1]]
            if pw.zone == "track" and int(pw.pos) == ui.Layout.gate_index(w[0]) and not ui.anim.has(key):
                # R37 · peão no PRÓPRIO Portão: escudo — bloqueia a casa (ninguém passa nem cai nela)
                var sc2 := c + Vector2(26, -14)
                var col2: Color = ui.KINGDOM_COLOR[int(w[0])]
                var sh := PackedVector2Array([sc2 + Vector2(-15, -16), sc2 + Vector2(15, -16), sc2 + Vector2(15, 3), sc2 + Vector2(0, 19), sc2 + Vector2(-15, 3)])
                draw_colored_polygon(sh, Color("2a1a05"))
                var sh2 := PackedVector2Array()
                for v in sh: sh2.append(sc2 + (v - sc2) * 0.78)
                draw_colored_polygon(sh2, col2)
                var sh3 := sh.duplicate()
                sh3.append(sh[0])
                draw_polyline(sh3, Color("f3c757"), 2.5)
                draw_rect(Rect2(sc2 + Vector2(-4, -3), Vector2(8, 7)), Color("f3c757"))
                draw_arc(sc2 + Vector2(0, -3), 3.5, PI, TAU, 8, Color("f3c757"), 2.0)
        _draw_celebs()
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

    ## Casas de Entrada trancadas agora (peão da outra dupla parado nela, sem estar andando)
    func _blocked_entries(g) -> Array:
        var out := []
        for seat in 4:
            var ei: int = ui.Layout.entrance_index(seat)
            var o: Array = g.occupant(ei)
            if o.is_empty() or g.team_of(o[0]) == g.team_of(seat): continue
            if ui.anim.has("%d_%d" % [o[0], o[1]]): continue
            out.append(ui.Layout.track_cell(ei))
        return out

    ## R83 · COROAÇÃO (opção D aprovada): o BRASÃO do reino surge grande no centro do tabuleiro girando como uma
    ## moeda, assenta com a coroa e "COROADO" em ouro, depois encolhe e voa em arco até o peão (brilho ao pousar).
    func _draw_celebs():
        if ui.celebs.is_empty(): return
        var br: Rect2 = ui.board_rect()
        var bs: float = br.size.x / ui.BOARD_UNITS
        var o0: Vector2 = ui.origin + br.position * ui.k
        var sc: float = ui.k * bs
        var center: Vector2 = ui.pile_center()
        for c in ui.celebs:
            var k: float = clampf(c.t / ui.CELEB_T, 0.0, 1.0)
            var col: Color = ui.KINGDOM_COLOR[int(c.seat)]
            var dest: Vector2 = c.p + Vector2(0, -60)
            # fases: surge girando (0–.30) · fica (.30–.70) · voa até o peão (.70–.92) · brilho no peão (.92–1)
            var appear := clampf(k / 0.30, 0.0, 1.0)
            var fly := clampf((k - 0.70) / 0.22, 0.0, 1.0)
            var fe := fly * fly * (3.0 - 2.0 * fly)
            var pop := 1.0 + 0.12 * sin(PI * clampf(appear * 1.3, 0.0, 1.0)) if appear < 1.0 else 1.0
            var size := lerpf(1.8, 0.16, fe) * (1.0 - pow(1.0 - appear, 3.0)) * pop
            var pos := center.lerp(dest, fe) + Vector2(0, -260.0 * sin(PI * fe))
            var spin := (1.0 - appear) * (1.0 - appear) * TAU * 2.5      # gira rápido e freia até parar de frente
            var fx := cos(spin)
            if size <= 0.01: continue
            # R83.3 · EMBLEMA da arte de referência do dono (escudo, coroa e o brilho roxo já vêm na arte)
            var et: Texture2D = ui.CROWN_EMBLEM
            var ew: float = 600.0 * size
            var eh: float = ew * et.get_height() / et.get_width()
            var hold := clampf(appear * 3.0, 0.0, 1.0) * (1.0 - fe)
            if hold > 0.0:
                # cinema: o tabuleiro escurece enquanto o emblema está no centro
                draw_set_transform(o0, 0.0, Vector2(sc, sc))
                draw_rect(Rect2(Vector2.ZERO, br.size / bs), Color(0.02, 0.0, 0.05, 0.55 * hold))
                draw_set_transform(o0 + pos * sc, 0.0, Vector2(sc, sc))
                for gl in 4: draw_circle(Vector2.ZERO, (eh * 0.42 + gl * 40.0), Color(0.45, 0.12, 0.75, (0.10 - gl * 0.022) * hold))
            draw_set_transform(o0 + pos * sc, 0.0, Vector2(sc * maxf(absf(fx), 0.04), sc))
            draw_texture_rect(et, Rect2(Vector2(-ew, -eh) / 2.0, Vector2(ew, eh)), false, Color(1, 1, 1) if fx >= 0.0 else Color(0.45, 0.35, 0.5))
            draw_set_transform(o0, 0.0, Vector2(sc, sc))
            # COROADO em ouro sob o brasão
            var ta := clampf((k - 0.22) / 0.10, 0.0, 1.0) * (1.0 - clampf((k - 0.66) / 0.08, 0.0, 1.0))
            if ta > 0.0:
                # R83.2 · letreiro em PIXEL ART (tools/coroado_pixel_r83.py): entra batendo (grande → tamanho certo,
                # com um tremor curto) e fica pulsando de leve
                var tin := clampf((k - 0.22) / 0.07, 0.0, 1.0)
                var slam: float = lerpf(1.7, 1.0, 1.0 - pow(1.0 - tin, 3.0))
                var shake := Vector2(sin(ui.t * 70.0), cos(ui.t * 63.0)) * 6.0 * clampf(1.0 - (k - 0.29) / 0.06, 0.0, 1.0) if k > 0.29 else Vector2.ZERO
                var bob := 1.0 + 0.025 * sin(ui.t * 6.0)
                var lt: Texture2D = ui.CROWN_TITLE
                var lw: float = 800.0 * slam * bob
                var lh: float = lw * lt.get_height() / lt.get_width()
                var lc := Vector2(pos.x, pos.y + eh * 0.47 + lw * 0.09) + shake
                draw_texture_rect(lt, Rect2(lc - Vector2(lw, lh) / 2.0, Vector2(lw, lh)), false, Color(1, 1, 1, ta))
            # brilho ao pousar no peão
            var land := clampf((k - 0.90) / 0.10, 0.0, 1.0)
            if land > 0.0:
                for gl in 3: draw_arc(dest + Vector2(0, 40), (30.0 + 70.0 * land + gl * 10.0), 0, TAU, 40, Color(0.75, 0.45, 1.0, (1.0 - land) * (0.8 - gl * 0.2)), 4.0)
        draw_set_transform(o0, 0.0, Vector2(sc, sc))

    ## Etiqueta (ABATER / CUIDADO) presa acima de uma casa do tabuleiro, pulsando.
    ## R37.3 · cartas voando da mão / da placa até o monte (arco, giro e encolhendo).
    func _draw_flies():
        if ui.flies.is_empty(): return
        var to: Rect2 = ui.pile_rect()
        for f in ui.flies:
            var k: float = clampf(float(f.t) / ui.CARD_FLY, 0.0, 1.0)
            if f.t < 0.0: continue
            var e := 1.0 - pow(1.0 - k, 3.0)
            var fr: Rect2 = f.from
            var c: Vector2 = fr.get_center().lerp(to.get_center(), e) + Vector2(0, -120.0 * sin(PI * k))
            var sz: Vector2 = fr.size.lerp(to.size, e)
            var rot := lerpf(0.0, 0.13, e) + sin(PI * k) * 0.35
            draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
            draw_rect(Rect2(-sz / 2.0 + Vector2(10, 14), sz), Color(0, 0, 0, 0.35))
            draw_texture_rect(Crisp.at(ui.cards[String(f.rank)], sz * ui.k), Rect2(-sz / 2.0, sz), false)
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

    func _tag(p: Vector2, label: String, col: Color):
        var fs := 46
        var w := text_w(label, "bold_sp", fs) + 44.0
        var sc := 1.0 + 0.06 * sin(ui.t * 7.0)
        var r := Rect2(p - Vector2(w, 66) * sc / 2.0, Vector2(w, 66) * sc)
        draw_colored_polygon(PackedVector2Array([Vector2(p.x - 10, r.end.y - 1), Vector2(p.x + 10, r.end.y - 1), Vector2(p.x, r.end.y + 14)]), col.darkened(0.25))
        draw_rect(r.grow(3), Color(0.12, 0.02, 0.02, 0.85))
        draw_rect(r, col.darkened(0.15))
        draw_rect(r.grow(-3), Color(1, 0.9, 0.8, 0.5), false, 1.5)
        text(label, Vector2(r.position.x, r.get_center().y + fs * 0.36), "bold_sp", fs, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER, 4, Color(0.2, 0.0, 0.0))

    func _collect_path(g, mv: Dictionary, dots: Array, dest: Array):
        var parts := []
        match String(mv.kind):
            "move": parts.append([mv.pawn, g.forward_path(mv.pawn[0], mv.pawn[1], int(mv.steps), g.move_enters(0, mv))])
            "back": parts.append([mv.pawn, g.backward_path(mv.pawn[0], mv.pawn[1], 4)])
            "split":
                for p in mv.parts: parts.append([p.pawn, g.forward_path(p.pawn[0], p.pawn[1], int(p.steps))])
            "exit": dest.append(ui.Layout.track_cell(ui.Layout.gate_index(mv.pawn[0])))
            "swap":
                dest.append(ui.pawn_point(mv.target[0], mv.target[1]))
                dest.append(ui.pawn_point(mv.pawn[0], mv.pawn[1]))
        for pr in parts:
            var r: Dictionary = pr[1]
            if not r.get("ok", false): continue
            var path: Array = r.path
            for j in path.size():
                var c: Vector2 = ui._cell_of(pr[0][0], path[j])
                if j == path.size() - 1: dest.append(c)
                else: dots.append(c)

    # ------------------------------------------------------------ mão e botões
    ## R91 · PC: bandeja das cartas por cima do tapete roxo/verde da arte (as curvas douradas e as faixas verdes
    ## atrás da mão ficavam estranhas): veludo escuro com moldura dourada dupla e cravos nos cantos.
    func _draw_card_tray():
        var r: Rect2 = ui.rr(Rect2(560, 760, 557, 200))   # R91.2 · começa abaixo da moldura do tabuleiro (y 754)
        var s: float = ui.r57_s()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("1b0f24")
        sb.border_color = Color("3a2412")
        sb.set_border_width_all(int(maxf(4.0, 9.0 * s)))
        sb.corner_radius_top_left = int(26.0 * s)
        sb.corner_radius_top_right = int(26.0 * s)
        sb.shadow_color = Color(0, 0, 0, 0.55)
        sb.shadow_size = int(18.0 * s)
        sb.shadow_offset = Vector2(0, -4.0 * s)
        draw_style_box(sb, r)
        # veludo: leve degradê de cima (mais claro) para baixo
        var inner := r.grow(-9.0 * s)
        for i in 8:
            var t := float(i) / 8.0
            draw_rect(Rect2(inner.position.x, inner.position.y + inner.size.y * t, inner.size.x, inner.size.y / 8.0 + 1.0), Color(0.24, 0.12, 0.30, 0.22 * (1.0 - t)))
        var gold := Color("d9a441")
        var line := StyleBoxFlat.new()
        line.draw_center = false
        line.border_color = gold
        line.set_border_width_all(int(maxf(2.0, 3.0 * s)))
        line.corner_radius_top_left = int(20.0 * s)
        line.corner_radius_top_right = int(20.0 * s)
        draw_style_box(line, r.grow(-7.0 * s))
        var line2: StyleBoxFlat = line.duplicate()
        line2.border_color = Color(gold.r, gold.g, gold.b, 0.35)
        line2.set_border_width_all(int(maxf(1.0, 1.5 * s)))
        draw_style_box(line2, r.grow(-15.0 * s))
        for c in [Vector2(r.position.x + 24.0 * s, r.position.y + 24.0 * s), Vector2(r.end.x - 24.0 * s, r.position.y + 24.0 * s)]:
            draw_circle(c, 6.0 * s, Color("6b4a14"))
            draw_circle(c, 4.5 * s, gold)
            draw_circle(c - Vector2(1.5, 1.5) * s, 1.6 * s, Color("fff1c2"))

    func _draw_hand():
        var g = ui.g
        var hand: Array = g.hands[0] if g != null else []
        var n := hand.size()
        if ui.desk and not ui.blk and ui.mode == "game": _draw_card_tray()
        for i in n:
            if ui.fly_hide.has(i): continue          # R37.3: esta carta está voando para a mesa
            if ui.card_played and i == ui.sel_card: continue     # R38.2: já foi jogada (está na mesa)
            var r: Rect2 = ui.card_rect(i, n)
            var selected: bool = i == ui.sel_card
            var rot := 0.0
            if ui.portrait: rot = 0.0   # R87 · cartas retas em pé
            # R145 · PC também reto: inclinadas, as bordas e as letras das cartas serrilhavam (filtro NEAREST)
            if selected:
                # R57 · no PC a carta sobe pouco: não pode cobrir as casas de baixo do tabuleiro
                r = r.grow(4 if ui.desk else 6)
                r.position.y -= 18 if ui.portrait else (6 if ui.desk else 4)
            var c := r.get_center()
            draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
            var local := Rect2(-r.size / 2.0, r.size)
            if selected:
                for gl in 5: draw_rect(local.grow(3 + gl * 3), Color(1.0, 0.8, 0.3, 0.22 - gl * 0.04), false, 3.0)
            # R37.2 · reduzida com Lanczos para o tamanho real na tela (o projeto usa filtro NEAREST)
            draw_texture_rect(Crisp.at(ui.cards[hand[i]], local.size * ui.k), local, false, Color.WHITE if (g.turn == 0 or selected) else Color(0.85, 0.85, 0.85))
            if ui.mode == "game" and not ui.busy:
                # R37 · avisos da carta: ABATER (derruba peão adversário) e CHEGADA (entra no Salão)
                var tags := []
                if ui.card_can_capture(i): tags.append(["ABATER", Color("c4161f")])
                if ui.card_can_crown(i): tags.append(["CHEGADA", Color("23824a")])
                var pz := 0.5 + 0.5 * sin(ui.t * 6.0)
                for ti in tags.size():
                    var br := Rect2(local.position.x + 8, local.position.y + (8.0 if ui.desk else -16.0) + ti * 38, local.size.x - 16, 34)
                    var tc: Color = tags[ti][1]
                    draw_rect(br.grow(2 + pz * 2), Color(tc.r, tc.g, tc.b, 0.35))
                    draw_rect(br, tc)
                    draw_rect(br.grow(-2), Color(1, 0.92, 0.8, 0.6), false, 1.5)
                    text(String(tags[ti][0]), Vector2(br.position.x, br.get_center().y + 9), "bold_sp", 24, Color.WHITE, br.size.x, HORIZONTAL_ALIGNMENT_CENTER, 3, tc.darkened(0.7))
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
            ui.hits.append({"rect": r, "id": "card_%d" % i})

    func _draw_turn_box(r: Rect2):
        var g = ui.g
        var mine: bool = g != null and g.turn == 0 and ui.mode == "game"
        var top := Color("ffd65c") if mine else Color("374765")
        var bot := Color("e9a417") if mine else Color("1e2b45")
        for i in int(r.size.y):
            draw_line(r.position + Vector2(0, i), r.position + Vector2(r.size.x, i), top.lerp(bot, float(i) / r.size.y), 1.0)
        draw_rect(r, Color("5a3b06") if mine else Color("c99a45"), false, 2.0)
        var label := ""
        if mine:
            var secs := int(ceil(ui.turn_left_ms / 1000.0))
            label = "SUA VEZ  0:%02d" % secs
        elif g != null:
            label = "VEZ DE " + String(ui.names[g.turn]).to_upper()
        var fs := fit(label, "bold_sp", 34 if not ui.portrait else 30, r.size.x - 20)
        text(label, Vector2(r.position.x, r.get_center().y + fs * 0.36), "bold_sp", fs, Color("2a1a04") if mine else ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

    func _draw_help(r: Rect2):
        var s: String = ui.help_line().to_upper()
        var fs := 24
        var f = ui.fonts.semi_sp
        var lines := _wrap(s, "semi_sp", fs, r.size.x)
        for li in lines.size():
            draw_string(f, Vector2(r.position.x, r.position.y + 26 + li * 30), lines[li], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color("e9c46e"))

    func _wrap(s: String, fk: String, fs: int, w: float) -> Array:
        var out := []
        var cur := ""
        for word in s.split(" "):
            var t2 := word if cur.is_empty() else cur + " " + word
            if text_w(t2, fk, fs) > w and not cur.is_empty():
                out.append(cur)
                cur = word
            else: cur = t2
        if not cur.is_empty(): out.append(cur)
        return out

    func _draw_ten(at: Vector2, w: float):
        text("CARTA 10:", at + Vector2(0, -10), "semi_sp", 20, Color("e9c46e"))
        var burn_on: bool = not ui.pending.is_empty() and ui.pending.kind == "burn"
        var tgt: String = ui.names[ui.g.burn_target(0)]
        var items := [["ten_move", "ANDAR 10", not burn_on], ["ten_burn", "%s DESCARTA" % tgt.to_upper(), burn_on]]
        var bw := (w - 8) / 2.0
        for i in 2:
            var r := Rect2(Vector2(at.x + i * (bw + 8), at.y), Vector2(bw, 40))
            var on: bool = items[i][2]
            draw_rect(r, Color("f0c44c") if on else Color("0e141f"))
            draw_rect(r, ui.GOLD, false, 2.0)
            var f := fit(items[i][1], "bold", 20, r.size.x - 10)
            text(items[i][1], Vector2(r.position.x, r.position.y + 28), "bold", f, Color("1c1405") if on else ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
            ui.hits.append({"rect": r, "id": items[i][0]})

    ## R88 · celular: DIVIDIR O 7 com botões grandes (o toque acerta fácil) e CANCELAR na mesma faixa
    func _draw_split_big(area: Rect2, choosing: bool):
        var opts: Array = ui.split_options()
        var pr := area
        if ui.portrait: pr = Rect2(8, 104, 1064, 196)
        draw_rect(pr.grow(6), Color(0, 0, 0, 0.45))
        draw_rect(pr, Color(0.05, 0.02, 0.08, 0.95))
        draw_rect(pr, Color("c99a45"), false, 3.0)
        draw_rect(pr.grow(-6), Color(0.79, 0.6, 0.27, 0.35), false, 1.5)
        var head_h: float = clampf(pr.size.y * 0.24, 28.0, 46.0)
        text("DIVIDIR O 7 — casas do 1º peão + do 2º", Vector2(pr.position.x, pr.position.y + head_h * 0.95), "semi_sp", int(head_h * 0.62), Color("e9c46e"), pr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        var n: int = opts.size() + (1 if choosing else 0)
        var gap := 10.0
        var top: float = pr.position.y + head_h + 10.0
        var h: float = pr.end.y - top - 12.0
        var w: float = (pr.size.x - 24.0 - gap * (n - 1)) / n
        var x: float = pr.position.x + 12.0
        for a in opts:
            var cap := "7" if a == 7 else "%d+%d" % [a, 7 - a]
            var r := Rect2(x, top, w, h)
            var on: bool = ui.split_first == a
            draw_rect(r, Color("f0c44c") if on else Color("162035"))
            draw_rect(r, ui.GOLD, false, 3.0)
            var fs := fit(cap, "bold", int(h * 0.5), r.size.x - 10)
            text(cap, Vector2(r.position.x, r.get_center().y + fs * 0.36), "bold", fs, Color("1c1405") if on else ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
            ui.hits.append({"rect": r, "id": "split_%d" % a})
            x += w + gap
        if choosing:
            var cr := Rect2(x, top, w, h)
            draw_rect(cr, Color("3a0d12"))
            draw_rect(cr, Color("c99a45"), false, 2.0)
            var fs2 := fit("CANCELAR", "bold", int(h * 0.3), cr.size.x - 8)
            text("CANCELAR", Vector2(cr.position.x, cr.get_center().y + fs2 * 0.36), "bold", fs2, ui.CREAM, cr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
            ui.hits.append({"rect": cr, "id": "cancel"})

    func _draw_split(at: Vector2, chip := 66.0):
        if ui.ten_choice():
            _draw_ten(at, 800.0 if chip > 60 else 394.0)
            return
        var opts: Array = ui.split_options()
        if opts.size() <= 1: return
        var label := "DIVIDIR O 7:"
        text(label, at + Vector2(0, -10), "semi_sp", 20, Color("e9c46e"))
        var x := at.x
        var y := at.y
        for a in opts:
            var cap := "7" if a == 7 else "%d+%d" % [a, 7 - a]
            var r := Rect2(Vector2(x, y), Vector2(chip, 40))
            var on: bool = ui.split_first == a
            draw_rect(r, Color("f0c44c") if on else Color("0e141f"))
            draw_rect(r, ui.GOLD, false, 2.0)
            text(cap, Vector2(r.position.x, r.position.y + 29), "bold", 22 if chip > 60 else 19, Color("1c1405") if on else ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
            ui.hits.append({"rect": r, "id": "split_%d" % a})
            x += chip + 6

    func _draw_game():
        _draw_bar()
        var g = ui.g
        if ui.portrait:
            _plate(Rect2(360, 138, 360, 124), 2)
            _plate(Rect2(20, 278, 272, 116), 1)
            _plate(Rect2(788, 278, 272, 116), 3)
            _draw_board()
            if ui.can_discard_all(): gold_button(Rect2(140, 1458, 800, 66), "DESCARTAR TODAS (%d) · SEM JOGADA" % g.hands[0].size(), 30, "discard_all")
            elif ui.split_options().size() <= 1 and not ui.ten_choice(): _draw_help(Rect2(140, 1462, 800, 60))
            else: _draw_split(Vector2(150, 1478), 66.0)
            # meu retrato + SUA VEZ
            var pr := Rect2(20, 1563, 130, 130)
            draw_texture_rect(ui.portraits.voce, pr, false)
            if ui.my_portrait != null: draw_texture_rect(ui.my_portrait, pr.grow(-10), false)
            _draw_turn_box(Rect2(20, 1700, 212, 60))
            _draw_hand()
            dark_button(Rect2(20, 1810, 330, 86), "CANCELAR", 34, "cancel", not ui.pending.is_empty() or ui.sel_card >= 0)
            gold_button(Rect2(370, 1810, 690, 86), "DESCARTAR CARTA" if ui.pending.get("kind", "") == "discard" else "JOGAR CARTA", 38, "play", ui.can_play())
        else:
            _plate(Rect2(40, 120, 390, 122), 2)
            _plate(Rect2(40, 262, 390, 122), 1)
            _plate(Rect2(40, 404, 390, 122), 3)
            # últimas jogadas
            var lr := Rect2(40, 556, 390, 316)
            draw_rect(lr, Color(0.028, 0.052, 0.099, 0.75))
            draw_rect(lr, Color("6f5524"), false, 1.5)
            text("ÚLTIMAS JOGADAS", Vector2(62, 596), "semi_sp2", 18, Color("d9a441"))
            if g != null:
                for li in mini(7, g.log.size()):
                    var line: String = g.log[li]
                    var fs := fit(line, "semi", 21, lr.size.x - 40)
                    text(line, Vector2(62, 634 + li * 33), "semi", fs, ui.CREAM)
            _plate(Rect2(40, 898, 390, 124), 0)
            _draw_board()
            _draw_turn_box(Rect2(1482, 120, 398, 66))
            _draw_help(Rect2(1482, 186, 398, 70))
            _draw_hand()
            _draw_split(Vector2(1484, 836), 50.0)
            if ui.can_discard_all(): dark_button(Rect2(1482, 812, 398, 58), "DESCARTAR TODAS (%d)" % g.hands[0].size(), 28, "discard_all")
            gold_button(Rect2(1482, 880, 398, 86), "DESCARTAR CARTA" if ui.pending.get("kind", "") == "discard" else "JOGAR CARTA", 40, "play", ui.can_play())
            dark_button(Rect2(1482, 985, 398, 64), "CANCELAR", 30, "cancel", not ui.pending.is_empty() or ui.sel_card >= 0)

    # ------------------------------------------------------------ R57 · PC: partida e salão das referências finais
    ## texto em px da referência da partida (pos = linha de base; fs = tamanho na referência)
    func rtext(s: String, pos: Vector2, fk: String, fs: float, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT, room := -1.0, outline := 0, ocol := Color.BLACK, lobby := false):
        var S: float = ui.r57_s_at(pos, lobby)
        var size := int(round(fs * S))
        if room > 0.0:
            while size > 9 and text_w(s, fk, size) > room * S: size -= 1
        var p: Vector2 = ui.lp(pos) if lobby else ui.rp(pos)
        text(s, p, fk, size, col, width * S if width > 0.0 else -1.0, align, outline, ocol)

    func cover(tex: Texture2D, dst: Rect2):
        if tex == null: return
        var ts := tex.get_size()
        var want := dst.size.x / dst.size.y
        var src := Rect2(Vector2.ZERO, ts)
        if ts.x / ts.y > want: src = Rect2((ts.x - ts.y * want) / 2.0, 0, ts.y * want, ts.y)
        else: src = Rect2(0, (ts.y - ts.x / want) / 2.0, ts.x, ts.x / want)
        draw_texture_rect_region(tex, dst, src)

    ## botão que já está na arte: área de toque + brilho no hover (a própria arte mais clara)
    func art_button(plate: Texture2D, ref_r: Rect2, dst: Rect2, id: String, enabled := true):
        if enabled and ui.hover_id == id:
            draw_texture_rect_region(plate, dst, ref_r, Color(1.22, 1.18, 1.1))
        if not enabled:
            draw_rect(dst.grow(-3), Color(0.03, 0.01, 0.06, 0.32))
            return
        ui.hits.append({"rect": dst, "id": id})

    ## ícones do canto (tela cheia, música, efeitos, ajuda, menu) — os da arte
    func _r57_icons(plate: Texture2D, icons: Array, lobby: bool):
        for it in icons:
            var id: String = it[0]
            var rref: Rect2 = it[1]
            var dst: Rect2 = ui.lr(rref) if lobby else ui.rr(rref)
            if id == "fullscreen":
                var sm = ui.screen_mode()
                if sm == null or not sm.supported():
                    draw_rect(dst.grow(-4), Color(0.03, 0.01, 0.06, 0.6))
                    continue
            art_button(plate, rref, dst, id)
            var off := false
            if id == "mute_music": off = ui.Sound.music_muted(ui.hub)
            elif id == "mute_fx": off = ui.Sound.effects_muted(ui.hub)
            if off:
                draw_rect(dst.grow(-5), Color(0.03, 0.01, 0.06, 0.5))
                draw_line(dst.position + Vector2(9, 9), dst.end - Vector2(9, 9), Color("e0503c"), 4.0)
        # FRAIHA Voice (partida online com outro humano): à esquerda dos ícones, no mesmo estilo
        var vo = ui.voice()
        var voice_on: bool = vo != null and vo.in_match() and vo.available()
        if not lobby and ui.mode == "game" and not voice_on and ui.online:   # R176.2 · contra bots: sem microfone
            # R77 · o microfone fica SEMPRE no lugar dele na partida; sem voz (bots, navegador sem suporte) fica
            # apagado e o toque explica onde a voz funciona
            var dr: Rect2 = ui.mic_rect()
            _voice_box(dr, false)
            ui.VoiceGlyph.draw_mic(self, _glyph_rect(dr), "DISCONNECTED", Color(0.85, 0.66, 0.31, 0.45))
            ui.hits.append({"rect": dr, "id": "voice_info"})
        if not lobby and ui.mode == "game" and voice_on:
            var vr: Rect2 = ui.mic_rect()
            _voice_box(vr, true)
            ui.VoiceGlyph.draw_mic(self, _glyph_rect(vr), vo.state, ui.GOLD, vo.is_speaking(vo.my_uid))
            ui.hits.append({"rect": vr, "id": "voice"})
            if vo.active() or vo.state == "ERROR": ui.hits.append({"rect": ui.VoiceGlyph.draw_leave_badge(self, vr), "id": "voice_off"})
            var tx := vr.position.x - 10
            if vo.active():
                var er: Rect2 = ui.ear_rect()
                _voice_box(er, true)
                ui.VoiceGlyph.draw_headphones(self, _glyph_rect(er), vo.speaker_muted, ui.GOLD)
                ui.hits.append({"rect": er, "id": "voice_ear"})
                tx = er.position.x - 10
            if not ui.blk:   # em pé/deitado no celular não cabe o texto ao lado (o título está ali); o ícone já mostra o estado
                ui.VoiceGlyph.draw_status(self, tx, vr.get_center().y, 300, vo.status_text(), 17, Color("e8dcc0"))

    ## R90 · caixa do microfone/fone: no celular em pé fica na linha do SUA VEZ, roxa com borda dourada como o CHAT
    func _voice_box(r: Rect2, on: bool):
        if ui._row_ok():
            var sb := StyleBoxFlat.new()
            sb.bg_color = Color("3d1c57") if on else Color("261338")
            sb.border_color = Color("d9a441") if on else Color(0.85, 0.66, 0.31, 0.6)
            sb.set_border_width_all(3)
            sb.set_corner_radius_all(12)
            sb.shadow_color = Color(0, 0, 0, 0.45)
            sb.shadow_size = 8
            draw_style_box(sb, r)
            return
        draw_rect(r, Color("0a0612"))
        draw_rect(r, ui.GOLD if on else Color(0.85, 0.66, 0.31, 0.45), false, 2.0)

    func _glyph_rect(r: Rect2) -> Rect2:
        if not ui._row_ok(): return r.grow(-8)
        var s: float = minf(r.size.x, r.size.y) * 0.58
        return Rect2(r.get_center() - Vector2(s, s) / 2.0, Vector2(s, s))

    func _draw_game_r57():
        ui._sync_chat_dock()   # R88 · CHAT no lugar reservado (celular em pé)
        var g = ui.g
        var plate: Texture2D = ui.r57.mesa
        if ui.blk:
            for i in [0, 3, 5, 6]:
                if i == 6 and ui.portrait_game[6][0] == ui.portrait_game[5][0]: continue
                if ui.portrait and i == 3: _soft_shadow(ui.portrait_game[i][1])   # R86 · assenta no cenário
                if ui.portrait and i == 5:
                    # R86 · painel SUA VEZ recortado da arte com fundo transparente (sem pedaço de parede em volta)
                    var pr: Rect2 = ui.portrait_game[5][1]
                    _soft_shadow(pr.grow(-pr.size.x * 0.03))
                    draw_texture_rect(tex("res://marcha/art/r86/painel_vez_baixo.png"), pr, false)
                    continue
                draw_texture_rect_region(plate, ui.portrait_game[i][1], ui.portrait_game[i][0])
            var icons_src := Rect2(1290, 0, 360, 80)   # só os ícones da arte; à esquerda fica o lugar do microfone
            draw_texture_rect_region(plate, ui.rr(icons_src), icons_src)
        else:
            draw_texture_rect(plate, ui.rr(Rect2(Vector2.ZERO, ui.R57_SIZE)), false)
            # R83 · PC: os morcegos voam só nas janelas roxas dos lados (o tabuleiro está na própria arte)
            var bs: Rect2 = ui.rr(ui.LayoutR57.ART_RECT_FULL)
            var l0: float = ui.origin.x + (bs.position.x - 30.0) * ui.k
            var r0: float = ui.origin.x + (bs.end.x + 30.0) * ui.k
            var hh: float = ui.origin.y + ui.rp(Vector2(0, 560)).y * ui.k
            _draw_bats([Rect2(0, 0, l0, hh), Rect2(r0, 0, size.x - r0, hh)])
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        var sub := "MODO DE CARTAS E CORRIDA"
        if g != null: sub = "RODADA %d - %d X %d PEÕES COROADOS" % [g.round_no, g.team_crowned(0), g.team_crowned(1)]
        rtext(sub, Vector2(187, 64), "r57_head", 17.6, Color("f2c94c"), -1.0, HORIZONTAL_ALIGNMENT_LEFT, 305.0)
        if ui.mode == "game": _r57_icons(plate, ui.R57_ICONS, false)
        else: _r57_icons(plate, ui.R57_ICONS.slice(0, 3), false)
        for seat in [1, 2, 3]: _r57_seat(seat)   # R69: o painel "Você" saiu da mesa
        _draw_board()
        _r57_timer()
        _r57_play(plate)
        _draw_hand()
        _r57_context()

    ## perfil: só avatar + nome (a moldura é da arte); brilho dourado em quem está na vez
    func _r57_seat(seat: int):
        var g = ui.g
        var d: Dictionary = ui.r57_seat(seat)
        var box: Rect2 = ui.rr(Rect2(d.box))
        if seat > 0: draw_texture_rect(ui.r57["placa_perfil_%d" % seat], box, false)
        ui.hits.append({"rect": box, "id": "seat_%d" % seat})
        if g != null and g.turn == seat and ui.mode == "game":
            var pz := 0.65 + 0.35 * sin(ui.t * 4.0)
            for i in 4: draw_rect(box.grow(1.0 + i * 3.0), Color(1.0, 0.84, 0.38, (0.42 - i * 0.1) * pz), false, 3.0)
        var av: Rect2 = ui.rr(Rect2(d.av))
        # os retratos da arte JÁ são os bots (ReiDoBlitz, Lady Torre, Cavalo_Louco) e o cavalo branco do "Você";
        # só um avatar de verdade (o seu, ou o de um amigo online) entra por cima
        var tex: Texture2D = ui.my_portrait if seat == 0 else ui.seat_avatar(seat)
        if tex != null: cover(tex, av)
        _look(av, ui.seat_look(seat))
        if ui.online: ui.VoiceGlyph.draw_seat_voice(self, av, ui.voice(), seat)
        var gone: bool = ui.online and seat < ui.players.size() and (bool(ui.players[seat].get("left", false)) or not bool(ui.players[seat].get("connected", true)))
        var nm: String = ui.names[seat]
        rtext(nm, Vector2(d.x, d.base), "r57_name", _seat_name_fs(), Color("8a8478") if gone else Color("f4efe6"), -1.0, HORIZONTAL_ALIGNMENT_LEFT, float(d.end) - float(d.x))

    ## R72 · as três placas do topo são iguais: o nome usa o MESMO tamanho nas três (o maior que cabe em todas)
    func _seat_name_fs() -> float:
        var S: float = ui.r57_s_at(Vector2(ui.r57_seat(1).x, ui.r57_seat(1).base))
        var fs: float = float(ui.r57_seat(1).cap) / 0.81
        for seat in [1, 2, 3]:
            var d: Dictionary = ui.r57_seat(seat)
            var room: float = (float(d.end) - float(d.x)) * S
            while fs > 10.0 and text_w(String(ui.names[seat]), "r57_name", int(round(fs * S))) > room: fs -= 0.5
        return fs

    ## SUA VEZ + tempo (a ampulheta e o pergaminho são da arte)
    func _r57_timer():
        var g = ui.g
        if g == null: return
        var ink := Color("1a1208")
        if g.turn == 0 and ui.mode == "game":
            var secs := int(ceil(ui.turn_left_ms / 1000.0))
            rtext("SUA VEZ", Vector2(155, 760), "r57_bold", 27.8, ink)
            rtext("0:%02d" % secs, Vector2(62, 815), "r57_bold", 50.6, ink, 265.0, HORIZONTAL_ALIGNMENT_CENTER)
        else:
            rtext("VEZ DE" if ui.mode == "game" else "FIM", Vector2(155, 760), "r57_bold", 27.8, ink)
            if ui.mode == "game":
                rtext(String(ui.names[g.turn]).to_upper(), Vector2(62, 810), "r57_bold", 36.0, ink, 265.0, HORIZONTAL_ALIGNMENT_CENTER, 240.0)

    ## JOGAR CARTA da arte (DESCARTAR CARTA quando é descarte; escurecido quando não dá para jogar)
    func _r57_play(plate: Texture2D):
        var rref: Rect2 = ui.R57_PLAY
        var dst: Rect2 = ui.rr(rref)
        if ui.pending.get("kind", "") == "discard":
            draw_texture_rect(ui.r57.botao_jogar_vazio, dst, false)
            rtext("DESCARTAR CARTA", Vector2(rref.position.x + 72, 882.5), "r57_name", 21.0, Color("f4efe6"), rref.size.x - 84, HORIZONTAL_ALIGNMENT_CENTER, rref.size.x - 90)
        art_button(plate, rref, dst, "play", ui.mode == "game" and ui.can_play())

    ## ajuda da carta escolhida, divisão do 7, opções do 10, descartar todas e CANCELAR — só quando há algo a fazer
    ## R78 · sem o texto de ajuda da carta (o COMO JOGAR explica; ele cobria o tabuleiro no celular). O painel só
    ## aparece quando há um controle a usar: dividir o 7, escolher o 10 ou descartar todas (+ CANCELAR). Para trocar
    ## de carta, basta tocar em outra.
    func _r57_context():
        var g = ui.g
        if g == null or ui.mode != "game": return
        var choosing: bool = ui.sel_card >= 0 or not ui.pending.is_empty()
        # R84 · sem jogada (sem Ás/Rei e sem peão na pista): botão grande DESCARTAR TODAS — no PC do lado direito,
        # no celular no lugar do JOGAR CARTA (que fica sem uso nessa hora)
        if ui.can_discard_all():
            var dr: Rect2 = ui.rr(ui.R57_PLAY) if ui.blk else ui.rr(Rect2(1335, 600, 300, 76))
            var pz := 0.5 + 0.5 * sin(ui.t * 4.0)
            for gl in 4: draw_rect(dr.grow(3 + gl * 4 + pz * 3), Color(1.0, 0.78, 0.3, 0.20 - gl * 0.045), false, 4.0)
            gold_button(dr, "DESCARTAR TODAS (%d)" % g.hands[0].size(), int(dr.size.y * 0.42), "discard_all")
            return
        var extra: bool = ui.ten_choice() or ui.split_options().size() > 1
        if not extra: return
        var S: float = 1.15 if ui.blk else ui.r57_s()
        var pr: Rect2 = ui.rr(Rect2(22, 560, 326, 70))
        if ui.blk: pr = ui.portrait_game[7][1]
        if ui.blk and ui.split_options().size() > 1 and not ui.ten_choice():
            _draw_split_big(pr, choosing)   # R88 · celular: botões grandes para dividir o 7
            return
        draw_rect(pr, Color(0.05, 0.02, 0.08, 0.92))
        draw_rect(pr, Color("c99a45"), false, 2.0)
        draw_rect(pr.grow(-5), Color(0.79, 0.6, 0.27, 0.3), false, 1.0)
        var row_y: float = pr.get_center().y - 19 * S
        if ui.ten_choice():
            _draw_ten(Vector2(pr.position.x + 12, row_y + 4 * S), 214.0 * S)
        elif ui.split_options().size() > 1:
            _draw_split(Vector2(pr.position.x + 12, row_y + 4 * S), 46.0 * S)
        if choosing:
            dark_button(Rect2(pr.end.x - 96 * S, row_y, 86 * S, 38 * S), "CANCELAR", int(15 * S), "cancel")

    func _draw_lobby_r57():
        var plate: Texture2D = ui.r57.salao
        if ui.portrait:
            for i in ui.PORTRAIT_LOBBY.size():
                var b: Array = ui.PORTRAIT_LOBBY[i]
                # R149 · bloco dos botões: placas recortadas (sem o tapete verde em volta do CONVIDAR AMIGO)
                if i == 4 and ui.r57.get("salao_botoes_cel") != null: draw_texture_rect(ui.r57.salao_botoes_cel, b[1], false)
                else: draw_texture_rect_region(plate, b[1], b[0])
        else: draw_texture_rect(plate, ui.lr(Rect2(Vector2.ZERO, ui.R57_LOBBY)), false)
        _r57_icons(plate, [["fullscreen", Rect2(1165, 12, 50, 50)], ["mute_music", Rect2(1222, 12, 50, 50)], ["mute_fx", Rect2(1282, 12, 50, 50)], ["lobby_tutorial", Rect2(1342, 12, 50, 50)], ["lobby_back", Rect2(1409, 12, 51, 50)]], true)
        # acesso (Club / partida grátis do dia): uma linha discreta no rodapé do painel
        var info: Dictionary = ui.gate_info
        var ok: bool = bool(info.get("can_play", false))
        var badge := String(info.get("label", "VERIFICANDO ACESSO…"))
        var note := String(info.get("note", ""))
        var line := badge if ok or note.is_empty() else badge + " · " + note
        rtext(line, Vector2(232, 538), "semi_sp", 15.0, Color("9fe3b5") if ok else Color("f2b27a"), 586.0, HORIZONTAL_ALIGNMENT_CENTER, 580.0, 0, Color.BLACK, true)
        var jr := Rect2(485, 580, 525, 80)
        if ok:
            # R145 · CONTRA BOTS e JOGAR ONLINE direto na tela (a arte tem duas placas no lugar do JOGAR AGORA)
            for bt in [["lobby_bots", Rect2(441, 576, 319, 89), "CONTRA BOTS"], ["lobby_online", Rect2(770, 576, 279, 89), "JOGAR ONLINE"]]:   # R146 · alinhadas com COMO JOGAR / VOLTAR
                var br: Rect2 = bt[1]
                art_button(plate, br, ui.lr(br), bt[0])
                rtext(bt[2], Vector2(br.position.x + 30, br.position.y + 56), "title", 24.0, Color("f2c75a"), br.size.x - 60, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 3, Color("2a0508"), true)   # mesmo tamanho nas duas
        elif bool(info.get("checking", false)) or info.is_empty():
            # R176.8c · enquanto verifica o acesso não aparece nada no lugar (antes piscava CONHECER CLUB FRAIHA)
            pass
        else:
            draw_texture_rect(ui.r57.botao_jogar_agora_vazio, ui.lr(jr), false)
            rtext("CONHECER CLUB FRAIHA", Vector2(jr.position.x + 70, 634), "title", 34.0, Color("f2c75a"), jr.size.x - 140, HORIZONTAL_ALIGNMENT_CENTER, jr.size.x - 150, 3, Color("2a1a04"), true)
            art_button(plate, jr, ui.lr(jr), "lobby_club")
        for b in [["lobby_tutorial", Rect2(445, 672, 320, 63)], ["lobby_back", Rect2(775, 672, 275, 63)], ["lobby_invite", Rect2(535, 740, 425, 63)]]:
            art_button(plate, b[1], ui.lr(b[1]), b[0])

    # ------------------------------------------------------------ lobby
    func _draw_lobby():
        _draw_bar()
        var w: float = ui.design.x
        var info: Dictionary = ui.gate_info
        var pr := Rect2(w / 2.0 - 430, 160, 860, 300) if not ui.portrait else Rect2(60, 180, 960, 380)
        if ui.portrait:
            draw_texture_rect(tex("res://marcha/art/tutorial/tabuleiro_com_pecas.png"), Rect2(140, 600, 800, 800), false)
        else:
            draw_texture_rect(tex("res://marcha/art/tutorial/tabuleiro_com_pecas.png"), Rect2(1210, 130, 660, 660), false)
            pr = Rect2(70, 150, 1080, 520)
        panel(pr, true)
        var x := pr.position.x + 40
        var y := pr.position.y + 70
        text("MARCHA REAL", Vector2(x, y), "title", 54 if not ui.portrait else 50, Color("e9b94a"))
        text("NOVO MODO · CARTAS E CORRIDA", Vector2(x, y + 42), "semi_sp2", 20, Color("d9a441"))
        var desc := "Quatro reinos disputam uma corrida de peões ao redor de uma mesa de pedra esculpida. Cada peão que chega ao fim do caminho vira DAMA. Você e seu aliado contra dois reinos rivais."
        var lines := _wrap(desc, "semi", 25, pr.size.x - 80)
        for li in lines.size(): text(lines[li], Vector2(x, y + 92 + li * 34), "semi", 25, ui.CREAM)
        var sy := y + 110 + lines.size() * 34
        var badge := String(info.get("label", "VERIFICANDO ACESSO…"))
        var ok: bool = bool(info.get("can_play", false))
        var bw := text_w(badge, "bold_sp", 18) + 30
        var brr := Rect2(Vector2(x, sy), Vector2(bw, 36))
        draw_rect(brr, Color("254587") if ok else Color("5a2a1a"))
        draw_rect(brr, Color("8fe0a8") if ok else Color("f2a070"), false, 2.0)
        text(badge, Vector2(brr.position.x, brr.position.y + 26), "bold_sp", 18, Color("eafff0") if ok else Color("ffe2c8"), brr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        var note := String(info.get("note", ""))
        if not note.is_empty():
            var nl := _wrap(note, "semi", 21, pr.size.x - 80)
            for li in nl.size(): text(nl[li], Vector2(x, sy + 70 + li * 28), "semi", 21, Color("c9c2a8"))
        # botões
        if ui.portrait:
            var by := 1450.0
            if ok:
                gold_button(Rect2(60, by, 470, 100), "CONTRA BOTS", 40, "lobby_bots")
                gold_button(Rect2(550, by, 470, 100), "JOGAR ONLINE", 40, "lobby_online")
            elif not (bool(info.get("checking", false)) or info.is_empty()): gold_button(Rect2(60, by, 960, 100), "CONHECER CLUB FRAIHA", 40, "lobby_club")
            dark_button(Rect2(60, by + 120, 470, 84), "COMO JOGAR", 32, "lobby_tutorial")
            gold_button(Rect2(550, by + 120, 470, 84), "CONVIDAR AMIGO", 32, "lobby_invite")
            dark_button(Rect2(60, by + 222, 960, 84), "VOLTAR", 34, "lobby_back")
        else:
            var by2 := 700.0
            if ok:
                gold_button(Rect2(70, by2, 255, 96), "CONTRA BOTS", 30, "lobby_bots")
                gold_button(Rect2(335, by2, 255, 96), "JOGAR ONLINE", 30, "lobby_online")
            elif not (bool(info.get("checking", false)) or info.is_empty()): gold_button(Rect2(70, by2, 520, 96), "CONHECER CLUB FRAIHA", 36, "lobby_club")
            dark_button(Rect2(620, by2 + 8, 300, 80), "COMO JOGAR", 30, "lobby_tutorial")
            dark_button(Rect2(950, by2 + 8, 200, 80), "VOLTAR", 30, "lobby_back")
            # R35.1 · jogar com um amigo (vocês em dupla contra 2 bots, mesa online)
            gold_button(Rect2(70, by2 + 120, 520, 80), "CONVIDAR AMIGO", 34, "lobby_invite")
            text("Vocês dois em dupla contra 2 bots · online", Vector2(620, by2 + 170), "semi", 22, Color("d9c79a"))

    # ------------------------------------------------------------ fim, menu, tutorial, aviso
    func _shade():
        draw_rect(Rect2(Vector2.ZERO, ui.design), Color(0, 0, 0, 0.62))
        ui.hits.clear()   # nada por baixo recebe toque

    func _draw_over():
        _shade()
        var g = ui.g
        var won: bool = g != null and g.winner == 0
        var r := Rect2(ui.design.x / 2.0 - 380, ui.design.y / 2.0 - 230, 760, 460)
        var ot: float = ui.over_t
        if won: _draw_victory_fx(r, ot)
        # o painel entra crescendo (com um leve passo além) — R35
        var pk := clampf(ot / 0.55, 0.0, 1.0)
        var sc := 1.0 + 2.70158 * pow(pk - 1.0, 3.0) + 1.70158 * pow(pk - 1.0, 2.0)
        sc = maxf(0.05, sc)
        var cc := r.get_center()
        draw_set_transform(ui.origin + cc * ui.k * (1.0 - sc), 0.0, Vector2(ui.k * sc, ui.k * sc))
        panel(r, true)
        text("VITÓRIA!" if won else "DERROTA", Vector2(r.position.x, r.position.y + 100), "title", 64, Color("ffd770") if won else Color("f2a070"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        var sub := "Sua dupla coroou os 8 peões." if won else "A dupla rival coroou os 8 peões primeiro."
        text(sub, Vector2(r.position.x, r.position.y + 160), "semi", 26, ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        if g != null:
            text("PEÕES COROADOS  %d  X  %d" % [g.team_crowned(0), g.team_crowned(1)], Vector2(r.position.x, r.position.y + 210), "semi_sp2", 24, Color("d9a441"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        gold_button(Rect2(r.position.x + 60, r.position.y + 270, r.size.x - 120, 80), "VOLTAR AO SALÃO DA MARCHA", 32, "over_again")
        dark_button(Rect2(r.position.x + 60, r.position.y + 366, r.size.x - 120, 64), "SAIR DO MODO", 28, "over_back")
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        if won and ot < 3.0:
            # coroa dourada descendo sobre o painel
            var ck := clampf(ot / 0.8, 0.0, 1.0)
            var cy := r.position.y - 30.0 - 120.0 * (1.0 - ck * ck)
            _draw_crown(Vector2(cc.x, cy), 1.0, clampf(ot * 2.0, 0.0, 1.0))
        elif won:
            _draw_crown(Vector2(cc.x, r.position.y - 30.0), 1.0 + 0.04 * sin(ot * 3.0), 1.0)

    ## Raios de luz girando atrás do painel + chuva de confetes nas cores dos 4 reinos e ouro.
    func _draw_victory_fx(r: Rect2, ot: float):
        var cc := r.get_center()
        var grow := clampf(ot / 0.8, 0.0, 1.0)
        for i in 18:
            var a := ot * 0.35 + TAU * i / 18.0
            var len := (420.0 + 120.0 * (i % 3)) * grow
            var w := 0.07
            var pts := PackedVector2Array([cc, cc + Vector2.from_angle(a - w) * len, cc + Vector2.from_angle(a + w) * len])
            draw_colored_polygon(pts, Color(1.0, 0.84, 0.35, 0.10 + 0.05 * (i % 2)))
        draw_circle(cc, 300.0 * grow, Color(1.0, 0.8, 0.3, 0.10))
        var cols := [Color("ffd770"), Color("f3ead2"), Color("e3283a"), Color("35c27c"), Color("d6dde3"), Color("e9a417")]
        var d: Vector2 = ui.design
        for i in 90:
            var h1 := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
            var h2 := fposmod(sin(i * 78.233) * 12345.678, 1.0)
            var speed := 160.0 + 220.0 * h2
            var y := fposmod(-60.0 - h2 * d.y + ot * speed, d.y + 80.0) - 40.0
            if ot * speed < 60.0 + h2 * d.y - 40.0 and y > d.y * 0.9: continue
            var x := h1 * d.x + 26.0 * sin(ot * (1.5 + h2) + i)
            var rot := ot * (2.0 + 4.0 * h1) + i
            var sz := Vector2(10 + 8 * h2, 6 + 4 * h1)
            var c: Color = cols[i % cols.size()]
            var u := Vector2.from_angle(rot) * sz.x * 0.5
            var v := Vector2.from_angle(rot + PI / 2) * sz.y * 0.5 * absf(sin(ot * 5.0 + i))
            draw_colored_polygon(PackedVector2Array([Vector2(x, y) - u - v, Vector2(x, y) + u - v, Vector2(x, y) + u + v, Vector2(x, y) - u + v]), c)

    func _draw_crown(at: Vector2, sc: float, alpha: float):
        var w := 150.0 * sc
        var h := 92.0 * sc
        var base := at + Vector2(-w / 2.0, 0)
        var pts := PackedVector2Array([base, base + Vector2(0, -h * 0.75), base + Vector2(w * 0.25, -h * 0.35), base + Vector2(w * 0.5, -h),
            base + Vector2(w * 0.75, -h * 0.35), base + Vector2(w, -h * 0.75), base + Vector2(w, 0)])
        for gl in 4: draw_circle(at + Vector2(0, -h * 0.45), (70.0 + gl * 16.0) * sc, Color(1.0, 0.82, 0.3, 0.08 * alpha))
        draw_colored_polygon(pts, Color(0.95, 0.72, 0.18, alpha))
        draw_polyline(pts + PackedVector2Array([base]), Color(0.42, 0.25, 0.02, alpha), 4.0)
        draw_rect(Rect2(base + Vector2(0, -2), Vector2(w, 18 * sc)), Color(0.85, 0.6, 0.12, alpha))
        draw_rect(Rect2(base + Vector2(0, -2), Vector2(w, 18 * sc)), Color(0.42, 0.25, 0.02, alpha), false, 3.0)
        for j in 3:
            draw_circle(base + Vector2(w * (0.25 + 0.25 * j), 7 * sc), 5.0 * sc, [Color("e3283a"), Color("35c27c"), Color("e3283a")][j] * Color(1, 1, 1, alpha))
        for j in [0.0, 0.5, 1.0]:
            draw_circle(base + Vector2(w * j, -h * (1.0 if j == 0.5 else 0.75)), 7.0 * sc, Color(1.0, 0.95, 0.7, alpha))

    func _draw_menu():
        _shade()
        var r := Rect2(ui.design.x / 2.0 - 300, ui.design.y / 2.0 - 190, 600, 380)
        panel(r, true)
        text("MENU", Vector2(r.position.x, r.position.y + 64), "title", 40, Color("e9b94a"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        gold_button(Rect2(r.position.x + 50, r.position.y + 100, 500, 70), "CONTINUAR", 30, "menu_close")
        dark_button(Rect2(r.position.x + 50, r.position.y + 190, 500, 62), "COMO JOGAR", 28, "menu_tutorial")
        dark_button(Rect2(r.position.x + 50, r.position.y + 272, 500, 62), "SAIR DA PARTIDA", 28, "menu_quit")

    func _draw_tutorial():
        _shade()
        var page: Dictionary = ui.TUTORIAL[ui.tut_page]
        var d: Vector2 = ui.design
        var r := Rect2(60, 140, d.x - 120, d.y - 260) if not ui.portrait else Rect2(30, 150, d.x - 60, d.y - 260)
        panel(r, true, ui.PANEL_DARK)
        text("COMO JOGAR · %d / %d" % [ui.tut_page + 1, ui.TUTORIAL.size()], Vector2(r.position.x + 36, r.position.y + 44), "semi_sp2", 18, Color("d9a441"))
        text(String(page.title), Vector2(r.position.x + 36, r.position.y + 96), "title", 40 if not ui.portrait else 38, Color("e9b94a") if not ui.desk else R57_GOLD_HI, -1, HORIZONTAL_ALIGNMENT_LEFT, 3 if ui.desk else 0, Color(0.05, 0.02, 0.06, 0.8))
        if ui.desk:   # páginas: losangos acesos
            for i in ui.TUTORIAL.size():
                _diamond(Vector2(r.end.x - 40 - (ui.TUTORIAL.size() - 1 - i) * 26, r.position.y + 38), 7.0, R57_GOLD_HI if i == ui.tut_page else Color(0.45, 0.33, 0.18), Color("5a3b06"))
        var img: Texture2D = _tut_image(String(page.img))
        var ir: Rect2
        var tr: Rect2
        if ui.portrait:
            var iw: float = r.size.x - 72
            var ih: float = minf(iw * img.get_size().y / img.get_size().x, 760.0)
            iw = ih * img.get_size().x / img.get_size().y
            ir = Rect2(Vector2(r.get_center().x - iw / 2.0, r.position.y + 130), Vector2(iw, ih))
            tr = Rect2(r.position.x + 36, ir.end.y + 30, r.size.x - 72, r.end.y - ir.end.y - 150)
        else:
            var ih2: float = r.size.y - 260
            var iw2: float = minf(ih2 * img.get_size().x / img.get_size().y, r.size.x * 0.55)
            ih2 = iw2 * img.get_size().y / img.get_size().x
            ir = Rect2(Vector2(r.position.x + 36, r.position.y + 130), Vector2(iw2, ih2))
            tr = Rect2(ir.end.x + 40, r.position.y + 140, r.end.x - ir.end.x - 76, r.size.y - 260)
        if ui.desk and String(page.get("kind", "")) == "cards":
            ir = Rect2(r.position.x + 36, r.position.y + 128, 0, 0)
            tr = Rect2(r.position.x + 36, r.position.y + 128, r.size.x - 72, r.size.y - 250)
            img = null
        if img != null:
            draw_texture_rect(img, ir, false)
        if img != null: draw_rect(ir, Color("c99a45") if not ui.desk else R57_GOLD, false, 2.0)
        if ui.desk and img != null: draw_rect(ir.grow(5), Color(0.85, 0.66, 0.31, 0.4), false, 1.0)
        if page.get("marks", false) and img != null: _tutorial_marks(ir)
        if ui.desk:
            _tut_rows(page, tr)
        else:
            var y := tr.position.y + 26
            for para in ui.tutorial_text(page).split("\n"):
                for ln in _wrap(para, "semi", 25, tr.size.x):
                    text(ln, Vector2(tr.position.x, y), "semi", 25, ui.CREAM)
                    y += 34
                y += 6 if para.is_empty() else 4
        var by: float = r.end.y - 96
        dark_button(Rect2(r.position.x + 36, by, 220, 66), "ANTERIOR", 26, "tut_prev", ui.tut_page > 0)
        dark_button(Rect2(r.get_center().x - 110, by, 220, 66), "FECHAR", 26, "tut_close")
        gold_button(Rect2(r.end.x - 316, by, 280, 66), "COMEÇAR" if ui.tut_page == ui.TUTORIAL.size() - 1 else "PRÓXIMO", 28, "tut_next")

    ## R65 · no PC o tutorial mostra o tabuleiro da mesa nova (recorte da própria arte da partida).
    var _tut_board: AtlasTexture
    func _tut_image(path: String) -> Texture2D:
        if ui.desk and path.begins_with("res://marcha/art/tutorial/tabuleiro") and not ui.r57.is_empty():
            if _tut_board == null:
                _tut_board = AtlasTexture.new()
                _tut_board.atlas = ui.r57.mesa
                _tut_board.region = ui.LayoutR57.ART_RECT_FULL
            return _tut_board
        return tex(path)

    ## R67 · itens da página (PC): caixas com marcador (losango ou número) ou com a carta de verdade ao lado.
    func _tut_rows(page: Dictionary, tr: Rect2):
        var kind := String(page.get("kind", "rules"))
        var y := tr.position.y
        if page.has("intro"):
            for ln in _wrap(String(page.intro), "semi", 23, tr.size.x):
                text(ln, Vector2(tr.position.x, y + 24), "semi", 23, Color(0.93, 0.86, 0.72), -1, HORIZONTAL_ALIGNMENT_LEFT, 2, Color(0.05, 0.02, 0.06, 0.8))
                y += 31
            y += 14
        var rows: Array = page.get("rows", [])
        if kind == "cards":
            _tut_card_rows(rows, Rect2(tr.position.x, y, tr.size.x, tr.end.y - y), page.get("outro", ""))
            return
        var gap := 12.0
        var room: float = tr.end.y - y
        var hh: float = minf(118.0, (room - gap * (rows.size() - 1)) / maxf(1.0, rows.size()))
        for i in rows.size():
            var row: Array = rows[i]
            var box := Rect2(tr.position.x, y, tr.size.x, hh)
            _row_box(box)
            var mc := Vector2(box.position.x + 38, box.get_center().y)
            if kind == "steps":
                draw_circle(mc, 21, Color("5a3b06"))
                draw_circle(mc, 19, R57_GOLD_HI)
                draw_circle(mc, 15, Color("e9b94a"))
                text(str(i + 1), Vector2(mc.x - 20, mc.y + 9), "bold", 25, Color("2a1704"), 40, HORIZONTAL_ALIGNMENT_CENTER)
            else:
                _diamond(mc, 15.0, R57_GOLD_HI, Color("5a3b06"))
                _diamond(mc, 7.0, Color("7a1f2b"), Color(0, 0, 0, 0))
            var tx := box.position.x + 76
            var tw := box.end.x - tx - 18
            text(String(row[0]), Vector2(tx, box.position.y + 34), "bold_sp", 22, R57_GOLD_HI, -1, HORIZONTAL_ALIGNMENT_LEFT, 2, Color(0.05, 0.02, 0.06, 0.8))
            var ly := box.position.y + 66
            for ln in _wrap(String(row[1]), "semi", 21, tw):
                if ly > box.end.y - 4: break
                text(ln, Vector2(tx, ly), "semi", 21, ui.CREAM)
                ly += 27
            y += hh + gap

    func _row_box(box: Rect2):
        draw_rect(box, Color(0.16, 0.08, 0.2, 0.85))
        draw_rect(Rect2(box.position, Vector2(box.size.x, box.size.y * 0.5)), Color(1, 1, 1, 0.025))
        draw_rect(box, Color(0.85, 0.66, 0.31, 0.55), false, 1.5)
        draw_rect(Rect2(box.position, Vector2(5, box.size.y)), R57_GOLD)

    ## Cartas: 2 colunas; cada item = a carta (ou um leque de cartas) + nome + o que faz.
    func _tut_card_rows(rows: Array, area: Rect2, outro: String):
        var cols := 2
        var gap := 16.0
        var nrow := int(ceil(rows.size() / float(cols)))
        var reserve := 46.0 if outro != "" else 0.0
        var cw := (area.size.x - gap) / cols
        var ch := minf(196.0, (area.size.y - reserve - gap * (nrow - 1)) / nrow)
        for i in rows.size():
            var row: Array = rows[i]
            var box := Rect2(area.position.x + (i % cols) * (cw + gap), area.position.y + (i / cols) * (ch + gap), cw, ch)
            if rows.size() % 2 == 1 and i == rows.size() - 1: box.size.x = area.size.x   # último sozinho: linha inteira
            _row_box(box)
            var card_h := box.size.y - 20.0
            var card_w := card_h * 0.70
            var ranks := String(row[0]).split(" ")
            var n := ranks.size()
            var step := minf(26.0, card_w * 0.32) if n > 1 else 0.0
            var cx0 := box.position.x + 18
            for k in n:
                var tex: Texture2D = ui.cards.get(String(ranks[k]))
                if tex == null: continue
                var cr := Rect2(cx0 + k * step, box.position.y + 10, card_w, card_h)
                draw_rect(cr.grow(2), Color(0, 0, 0, 0.35))
                draw_texture_rect(Crisp.at(tex, cr.size * ui.k), cr, false)
            var tx := cx0 + card_w + (n - 1) * step + 22
            var tw := box.end.x - tx - 16
            text(String(row[1]), Vector2(tx, box.position.y + 40), "title", 26, R57_GOLD_HI, -1, HORIZONTAL_ALIGNMENT_LEFT, 3, Color(0.05, 0.02, 0.06, 0.8))
            var ly := box.position.y + 74
            for ln in _wrap(String(row[2]), "semi", 21, tw):
                if ly > box.end.y - 6: break
                text(ln, Vector2(tx, ly), "semi", 21, ui.CREAM)
                ly += 27
        if outro != "":
            var oy := area.position.y + nrow * (ch + gap) + 6
            _diamond(Vector2(area.position.x + 14, oy + 8), 8.0, R57_GOLD_HI, Color("5a3b06"))
            text(outro, Vector2(area.position.x + 32, oy + 16), "semi", 22, Color(0.93, 0.86, 0.72))

    ## Números dos componentes sobre o tabuleiro (como na página 03 do conceito).
    func _tutorial_marks(ir: Rect2):
        var LS = ui.LayoutR57 if ui.desk else ui.LayoutStd   # PC: tabuleiro da mesa nova; celular: o antigo
        var s: float = ir.size.x / (LS.SIZE if ui.desk else ui.BOARD_UNITS)
        var marks := [[LS.home_center(0), "1"], [LS.track_cell(0), "2"], [LS.track_cell(9), "3"], [LS.track_cell(74), "4"], [LS.lane_cell(0, 2), "5"]]
        for m in marks:
            var c: Vector2 = ir.position + Vector2(m[0]) * s + Vector2(26, -26)
            draw_circle(c, 17, Color("f0c44c"))
            draw_arc(c, 17, 0, TAU, 24, Color("2a1a04"), 2.0)
            text(String(m[1]), Vector2(c.x - 17, c.y + 9), "bold", 24, Color("1c1405"), 34, HORIZONTAL_ALIGNMENT_CENTER)

    ## R35.1 · caixa de escolha das cartas de 2 funções (A e 10).
    func _draw_choice():
        var opts: Array = ui.two_choices()
        if opts.is_empty(): return
        _shade()
        var d: Vector2 = ui.design
        var w := 820.0 if not ui.portrait else 960.0
        var hgt := 250.0 + opts.size() * 112.0
        var r := Rect2(d.x / 2.0 - w / 2.0, d.y / 2.0 - hgt / 2.0, w, hgt)
        panel(r, true)
        var rank: String = ui.g.hands[0][ui.sel_card]
        text(ui.Rules.card_label(rank).to_upper(), Vector2(r.position.x, r.position.y + 70), "title", 44, Color("ffd770"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        text(ui.choice_title(), Vector2(r.position.x, r.position.y + 118), "semi_sp", 26, ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        for i in opts.size():
            var br := Rect2(r.position.x + 50, r.position.y + 146 + i * 112, r.size.x - 100, 96)
            var able: bool = bool(opts[i][3])
            var bb := Rect2(br.position, Vector2(br.size.x, 62))
            gold_button(bb, String(opts[i][1]), 32, "choice_" + String(opts[i][0]), able)
            var oid := String(opts[i][0])
            if oid.begins_with("seat"):
                # 5: peão da cor, à esquerda do botão
                var tx: Texture2D = ui.pawn_tex[int(oid.substr(4))]
                var ps := tx.get_size() * (54.0 / tx.get_size().y)
                draw_texture_rect(tx, Rect2(bb.position + Vector2(18, 4), ps), false, Color(1, 1, 1, 1.0 if able else 0.45))
            text(String(opts[i][2]), Vector2(br.position.x, br.position.y + 88), "semi", 21, Color("d9c79a") if able else Color("8f8a78"), br.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        dark_button(Rect2(r.position.x + 50, r.end.y - 80, r.size.x - 100, 56), "CANCELAR", 26, "choice_cancel")

    func _draw_flash():
        var w := text_w(ui.flash, "semi", 26) + 60
        var r := Rect2(Vector2(ui.design.x / 2.0 - w / 2.0, ui.design.y * (0.88 if not ui.portrait else 0.18)), Vector2(w, 56))
        draw_rect(r, Color(0.071, 0.085, 0.113, 0.94))
        draw_rect(r, ui.GOLD, false, 2.0)
        text(ui.flash, Vector2(r.position.x, r.position.y + 37), "semi", 26, ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


# ================================================================ R35 · ONLINE COM AMIGO
## Mesa criada pelo servidor (convite aceito). msg = party_start: jogadores e estado já girados
## para você ficar no lugar 0 (embaixo). As regras locais servem só para mostrar as jogadas
## possíveis; quem valida e aplica é o servidor.
func start_online(msg: Dictionary):
    _load_art()   # R89
    var resumed := bool(msg.get("resumed", false)) and online and room_id == String(msg.get("room_id", ""))
    online = true
    room_id = String(msg.get("room_id", ""))
    if not resumed: pile = []
    players = msg.get("players", []) if msg.get("players") is Array else []
    var pc = stage.get("party_chat") if stage != null else null
    if pc != null: pc.bind(room_id, "marcha", names)     # R37.3 · chat da mesa
    names = DEFAULT_NAMES.duplicate()
    for i in mini(4, players.size()):
        if i > 0: names[i] = String(players[i].get("name", names[i]))
    if not visible:
        visible = true
        root.visible = true
        Sound.music_on(stage, MUSIC)
    tut_page = -1
    menu_open = false
    if not resumed:
        g = Rules.new()
        g.setup(0)
        started_at = Time.get_ticks_msec()
        started_unix = int(Time.get_unix_time_from_system())
        plays = 0
        recorded = false
        celebs.clear()
    ev_queue.clear()
    ev_running = false
    waiting_server = false
    mode = "game"
    _apply_snapshot(msg.get("snapshot", {}))
    _clear_selection()
    busy = not _my_turn()
    if bool(msg.get("ended", false)): _finish()
    elif _my_turn(): _cue("your_turn")
    _relayout()

func _my_turn() -> bool:
    return g != null and g.turn == 0 and g.winner < 0

static func _ints(a) -> Array:
    var out := []
    if a is Array:
        for x in a: out.append(int(x))
    return out

## R92 · troca a cor real de quem está nesta tela (peões; o tabuleiro troca as bases/pistas em _draw_view_colors)
func _set_view_seat(v: int):
    v = posmod(v, 4)
    if v == view_seat: return
    view_seat = v
    if not pawn_tex.is_empty():
        for s in 4:
            var fc: String = PAWN_FILES[(s + view_seat) % 4]
            pawn_tex[s] = load("res://marcha/art/pawns/peao_" + fc + ".png")
            pawn_tex[s + 10] = load("res://marcha/art/pawns/peao_" + fc + "_dama.png")
    _redraw()

func _apply_snapshot(snap: Dictionary):
    if g == null or snap.is_empty(): return
    if snap.has("view_seat"): _set_view_seat(int(snap.view_seat))
    var pw: Array = snap.get("pawns", [])
    if pw.size() == 4:
        for s in 4:
            for i in 4:
                var p: Dictionary = pw[s][i]
                g.pawns[s][i] = {"zone": String(p.get("zone", "home")), "pos": int(p.get("pos", i))}
    var counts: Array = snap.get("hand_counts", [4, 4, 4, 4])
    g.hands[0] = (snap.get("my_hand", []) as Array).map(func(c): return String(c))
    for s in range(1, 4):
        var h := []
        for k in int(counts[s]): h.append("2")       # cartas dos outros: só a quantidade (o servidor esconde)
        g.hands[s] = h
    g.turn = int(snap.get("turn", 0))
    g.round_no = int(snap.get("round_no", 1))
    g.winner = int(snap.get("winner", -1))
    var me := String(players[0].get("name", "")) if not players.is_empty() else ""
    g.log = (snap.get("log", []) as Array).map(func(x): return ("Você" + String(x).substr(me.length())) if not me.is_empty() and String(x).begins_with(me + " ") else String(x))
    for s in 4: g.names[s] = "Você" if s == 0 else names[s]
    if snap.has("turn_left_ms"):
        turn_left_ms = int(snap.turn_left_ms) if bool(snap.get("my_turn", false)) else TURN_MS
        turn_deadline = Time.get_ticks_msec() + turn_left_ms   # prazo do servidor convertido para o relógio local
    var conn: Array = snap.get("players_connected", [])
    for i in mini(conn.size(), players.size()): players[i]["connected"] = bool(conn[i])

## Mensagens party_* do servidor (repassadas pelo stage).
func on_party_message(msg: Dictionary):
    if not online or String(msg.get("room_id", room_id)) != room_id: return
    match String(msg.get("type", "")):
        "party_event":
            ev_queue.append(msg)
            if not ev_running: _drain_events()
        "party_error":
            waiting_server = false
            if msg.has("snapshot"): _apply_snapshot(msg.snapshot)
            busy = not _my_turn()
            _clear_selection()
            _flash(String(msg.get("message", "Jogada recusada.")))
            _redraw()

func _drain_events():
    ev_running = true
    while not ev_queue.is_empty() and online:
        var msg: Dictionary = ev_queue.pop_front()
        await _run_event(msg)
    ev_running = false

func _run_event(msg: Dictionary):
    var snap: Dictionary = msg.get("snapshot", {})
    match String(msg.get("ev", "")):
        "move":
            busy = true
            waiting_server = false
            var mv: Dictionary = msg.get("move", {})
            var staged := card_played and int(msg.get("seat", 0)) == 0
            _clear_selection()
            _snap_origin()          # R37: posições de antes (a animação sai daqui, em pulinhos)
            var seat_ev := int(msg.get("seat", 0))
            var rank_ev := String(mv.get("rank", ""))
            var flown: Array = [rank_ev]
            var idxs_ev: Array = [int(mv.get("card", 0))]
            if String(mv.get("kind", "")) == "discard_all":
                flown = []
                for e in msg.get("events", []): if String(e.get("type", "")) == "discard": flown.append(String(e.rank))
                idxs_ev = range(flown.size())
            if seat_ev != 0 or idxs_ev.any(func(q): return int(q) >= g.hands[0].size()): idxs_ev = []
            await _fly_cards(seat_ev, flown, idxs_ev, staged)
            _apply_snapshot(snap)
            plays += 1
            _cue("discard" if String(mv.get("kind", "")) in ["discard", "discard_all"] else "card")
            var evs := []
            for e in msg.get("events", []):
                var o: Dictionary = (e as Dictionary).duplicate(true)
                if o.has("pawn"): o.pawn = _ints(o.pawn)
                if o.has("target"): o.target = _ints(o.target)
                if o.has("seat"): o.seat = int(o.seat)
                if o.has("path"): o.path = (o.path as Array).map(func(q): return {"zone": String(q.zone), "pos": int(q.pos)})
                evs.append(o)
            _pile_add(evs, mv, rank_ev)
            await _animate(evs)
            if String(msg.get("reason", "")) == "timeout" and int(msg.get("seat", -1)) == 0: _flash("Tempo esgotado: o servidor jogou por você.")
        "turn":
            _apply_snapshot(snap)
            _clear_selection()
            busy = not _my_turn()
            if _my_turn():
                _cue("your_turn")
                if not g.has_any_move(0): _flash("Sem jogada possível: escolha uma carta para descartar.")
        "left":
            _apply_snapshot(snap)
            var who := int(msg.get("who", -1))
            if who > 0 and who < players.size():
                players[who]["left"] = true
                _flash("%s saiu da partida — um bot joga no lugar." % names[who])
        "presence":
            _apply_snapshot(snap)
        "end":
            _apply_snapshot(snap)
            if mode == "game": _finish()
    _redraw()

## Pede a jogada ao servidor (coordenadas já na mesa girada; o servidor desfaz o giro e valida).
func _online_send(mv: Dictionary):
    if waiting_server: return
    var out := {"kind": String(mv.get("kind", "")), "card": int(mv.get("card", 0))}
    for key in ["steps", "target_seat"]:
        if mv.has(key): out[key] = int(mv[key])
    for key in ["pawn", "target"]:
        if mv.has(key): out[key] = _ints(mv[key])
    if mv.has("parts"):
        out["parts"] = (mv.parts as Array).map(func(p): return {"pawn": _ints(p.pawn), "steps": int(p.steps)})
    var acc = stage.get("account") if stage != null else null
    if acc == null or not acc.has_method("send_server") or not acc.send_server({"type": "party_action", "room_id": room_id, "action": out}):
        _flash("Sem conexão com o servidor. Tentando de novo…")
        return
    waiting_server = true
    busy = true
    _redraw()

func _chat_unbind():
    var pc = stage.get("party_chat") if stage != null else null
    if pc != null: pc.unbind()

func _online_leave():
    var acc = stage.get("account") if stage != null else null
    _chat_unbind()
    if acc != null and acc.has_method("send_server"): acc.send_server({"type": "party_leave", "room_id": room_id})
    online = false
    ev_queue.clear()

## O servidor reiniciou / a partida não existe mais.
func online_lost(text: String):
    if not online: return
    _chat_unbind()
    online = false
    ev_queue.clear()
    if mode == "game":
        mode = "lobby"
        g = null
    _flash(text)
    _redraw()


## R35.1 · CONVIDAR AMIGO de dentro do modo: abre a lista de amigos (Amigos) já no convite da MARCHA REAL.
func invite_friend():
    var social = stage.get("social_ui") if stage != null else null
    var acc = stage.get("account") if stage != null else null
    if acc == null or not acc.has_profile():
        _flash("Entre na sua conta para convidar amigos.")
        return
    if social != null and social.has_method("open_invite_picker"): social.open_invite_picker("marcha")
