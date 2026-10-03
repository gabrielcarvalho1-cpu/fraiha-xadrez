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
const Layout := preload("res://marcha/board_layout.gd")
const Access := preload("res://marcha/marcha_access.gd")
const Sound := preload("res://ui_v022/mode_sound.gd")
const MUSIC := "res://marcha/audio/musica_marcha.mp3"    # música enviada pelo dono do projeto (loop)
const SFX := {
    "card": preload("res://marcha/audio/carta.wav"), "discard": preload("res://marcha/audio/descarte.wav"),
    "step": preload("res://marcha/audio/passo.wav"), "exit": preload("res://marcha/audio/saida.wav"),
    "capture": preload("res://marcha/audio/captura.wav"), "swap": preload("res://marcha/audio/troca.wav"),
    "crown": preload("res://marcha/audio/coroa.wav"), "your_turn": preload("res://marcha/audio/sua_vez.wav"),
    "victory": preload("res://marcha/audio/vitoria.wav"), "defeat": preload("res://marcha/audio/derrota.wav"),
    "arrive": preload("res://marcha/audio/chegada.wav"), "victory_final": preload("res://marcha/audio/vitoria_final.wav"),
}
const SFX_DB := {"arrive": -6.0, "victory_final": -5.0, "step": -12.0, "your_turn": -9.0, "crown": -7.0, "victory": -7.0, "defeat": -7.0, "capture": -6.0}

const BOARD := preload("res://marcha/art/board.png")
const BG := preload("res://marcha/art/table_bg.png")
const SYMBOLS := preload("res://marcha/art/simbolos_de_acao.png")
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
const PANEL := Color("0f2b20")
const PANEL_DARK := Color("0a1d16")
const TURN_MS := 30000
const BOT_DELAY := 0.95
const STEP_TIME := 0.18           # R35: 0,18 s por casa (antes 0,11 — rápido demais para acompanhar)
## Bots da mesa (nomes e retratos da tela de referência).
const BOTS := {1: {"name": "ReiDoBlitz", "portrait": "rei_do_blitz"}, 2: {"name": "Lady Torre", "portrait": "lady_torre"}, 3: {"name": "Cavalo_Louco", "portrait": "cavalo_louco"}}
const PAWN_SCALE := 0.24          # peão PNG (211x279) sobre a casa da arte 1600x1600
const PAWN_BASE := 11.0           # a base do peão assenta 11 px abaixo do centro da casa

var hub = null
var stage = null
var access = null
var root: Control
var view: TableView
var g = null
var mode := "lobby"               # lobby | game | over
var tut_page := -1                # tutorial aberto (página) ou -1
var menu_open := false
var portrait := false
var design := Vector2(1920, 1080)
var k := 1.0
var origin := Vector2.ZERO
var names := ["Você", "ReiDoBlitz", "Lady Torre", "Cavalo_Louco"]
var cards := {}
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
var busy := false                 # animando ou bot pensando
var anim := {}                    # [seat,i] -> posição desenhada (coordenadas do tabuleiro) durante animação
var anim_alpha := {}
var celebs: Array = []            # R35 · festa de chegada ao Salão: [{"p": Vector2 (tabuleiro), "t", "seat"}]
const CELEB_T := 1.7
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

func _ready():
    for r in CARD_FILES: cards[r] = load("res://marcha/art/cards/" + CARD_FILES[r] + ".png")
    card_back = load("res://marcha/art/cards/carta_verso.png")
    for s in 4:
        pawn_tex[s] = load("res://marcha/art/pawns/peao_" + PAWN_FILES[s] + ".png")
        pawn_tex[s + 10] = load("res://marcha/art/pawns/peao_" + PAWN_FILES[s] + "_promovido.png")
    for key in ["lady_torre", "rei_do_blitz", "cavalo_louco", "voce"]: portraits[key] = load("res://marcha/art/portraits/" + key + ".png")
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
func open():
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
    visible = false
    root.visible = false
    Sound.music_off(stage)
    mode = "lobby"
    g = null
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
    design = Vector2(1080, 1920) if portrait else Vector2(1920, 1080)
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
    _starting = true
    var ok: bool = await access.request_start()
    _starting = false
    if not ok:
        _flash("Você já jogou sua partida grátis de hoje.")
        mode = "lobby"
        _redraw()
        return
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
    if g == null or mode != "game": return
    turn_left_ms = TURN_MS
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

func _play(seat: int, mv: Dictionary):
    busy = true
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
    _cue("discard" if String(mv.get("kind", "")) == "discard" else "card")
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
    _cue("victory_final" if g.winner == 0 else "defeat")
    _record_history("win" if g.winner == 0 else "loss")
    _redraw()

## Histórico comum (o mesmo das partidas de xadrez), com mode_id e versão das regras.
func _record_history(result: String) -> Dictionary:
    if g == null or recorded or started_unix <= 0: return {}
    var mh = stage.get("match_history") if stage != null else null
    if mh == null or not mh.has_method("add_entry"): return {}
    recorded = true
    return mh.add_entry({
        "mode_id": "marcha_real", "ruleset_version": Rules.RULESET_VERSION, "mode": "marcha",
        "result": result, "reason": "abandono" if result == "abandon" else "coroação",
        "player": "Você", "ally": String(g.names[2]), "opponent": "%s e %s" % [g.names[1], g.names[3]],
        "started_at": started_unix, "finished_at": int(Time.get_unix_time_from_system()), "plies": plays,
        "data": {"rounds": g.round_no, "crowned": [g.team_crowned(0), g.team_crowned(1)], "seat": 0, "log": g.log.slice(-12)},
    })

func _process(delta):
    if not visible: return
    t += delta
    for c in celebs: c.t += delta
    celebs = celebs.filter(func(c): return c.t < CELEB_T)
    if mode == "over": over_t += delta
    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0: flash = ""
    if mode == "game" and g != null and g.turn == 0 and not busy and not menu_open and tut_page < 0:
        turn_left_ms -= int(delta * 1000.0)
        if turn_left_ms <= 0:
            turn_left_ms = 0
            _auto_play()
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

func my_moves() -> Array:
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
        if not sole_pawn().is_empty(): _auto_sole_pawn()
        elif opts.size() == 1: pending = opts.values()[0]
    _redraw()

## R34.2 · um peão só pode receber a carta (ex.: uma peça só rodando no tabuleiro) → ele já fica
## escolhido: não precisa tocar nele. Vale para toda carta que age sobre o peão (10 = ANDAR 10
## já marcado, J = só falta escolher a peça para trocar). Saída do Pátio conta como outra opção.
func sole_pawn() -> Array:
    var who := []
    for m in my_moves():
        if m.kind == "burn": continue
        if m.kind == "exit": return []
        var w: Array
        if m.kind == "split":
            if m.parts.size() != 1: return []
            w = m.parts[0].pawn
        else:
            w = m.pawn
        if who.is_empty(): who = w
        elif who != w: return []
    return who

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
    if g == null or sel_card < 0 or g.turn != 0 or g.hands[0][sel_card] != "10": return false
    var mv := my_moves()
    return mv.any(func(m): return m.kind == "burn") and mv.any(func(m): return m.kind != "burn")

func pick_burn():
    for m in my_moves():
        if m.kind == "burn":
            sel_pawn = []
            pending = m
    _redraw()

## Peões que podem receber o próximo toque (para os aros dourados).
func candidate_pawns() -> Array:
    var out := []
    if g == null or sel_card < 0 or g.turn != 0 or busy: return out
    var mv := my_moves()
    var rank: String = g.hands[0][sel_card]
    if rank == "J" and not sel_pawn.is_empty():
        for m in mv:
            if m.pawn == sel_pawn and not out.has(m.target): out.append(m.target)
        return out
    if rank == "7" and split_first > 0 and split_first < 7:
        for m in mv:
            if m.parts.size() == 2 and m.parts[0].pawn == sel_pawn and int(m.parts[0].steps) == split_first and not out.has(m.parts[1].pawn): out.append(m.parts[1].pawn)
        return out
    for m in mv:
        if m.kind == "burn": continue
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
    if g == null or sel_card < 0 or busy: return
    var rank: String = g.hands[0][sel_card]
    var mv := my_moves()
    if rank == "J" and not sel_pawn.is_empty() and sel_pawn != w:
        for m in mv:
            if m.pawn == sel_pawn and m.target == w:
                sel_target = w
                pending = m
        _redraw()
        return
    if rank == "7" and split_first > 0 and split_first < 7 and not sel_pawn.is_empty() and w != sel_pawn:
        for m in mv:
            if m.parts.size() == 2 and m.parts[0].pawn == sel_pawn and int(m.parts[0].steps) == split_first and m.parts[1].pawn == w:
                sel_second = w
                pending = m
        _redraw()
        return
    sel_pawn = w
    sel_target = []
    split_first = 0
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
    sel_second = []
    pending = {}
    if a == 7:
        for m in my_moves():
            if m.parts.size() == 1 and m.parts[0].pawn == sel_pawn: pending = m
    _redraw()

func confirm():
    if busy or pending.is_empty() or g == null or g.turn != 0: return
    var mv := pending
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
    if pending.get("kind", "") == "discard": return head + " · descartar"
    match rank:
        "A", "K":
            if not pending.is_empty() and pending.kind == "exit": return head + " · seu peão sai do pátio"
            return head + " · sai do pátio ou anda %d casas" % Rules.STEPS[rank]
        "J": return head + (" · troca de lugar com a peça escolhida" if not pending.is_empty() else " · escolha seu peão e a peça para trocar")
        "10":
            if not pending.is_empty() and pending.kind == "burn": return head + " · %s descarta uma carta" % names[int(pending.target_seat)]
            if ten_choice(): return head + " · anda 10 casas ou faz %s descartar" % names[g.burn_target(0)]
        "7":
            if split_first > 0 and split_first < 7: return head + " · %d casas + %d casas: escolha o 2º peão" % [split_first, 7 - split_first]
            return head + " · até 2 peças dividem 7 casas"
        "5": return head + " · qualquer peça anda 5 casas"
        "4": return head + " · seu peão volta 4 casas"
    return head + " · seu peão avança %d casas" % int(Rules.STEPS.get(rank, 0))

# ---------------------------------------------------------------- animação
func _animate(events: Array):
    for e in events:
        match String(e.type):
            "move":
                var w: Array = e.pawn
                var key := _key(w)
                var si := 0
                for step in e.path:
                    _cue("step", 0.92 + 0.04 * (si % 4))
                    si += 1
                    anim[key] = _cell_of(w[0], step)
                    _redraw()
                    await get_tree().create_timer(STEP_TIME).timeout
                anim.erase(key)
            "exit":
                _cue("exit")
                var w: Array = e.pawn
                var key := _key(w)
                var a: Vector2 = Layout.home_center(w[0])
                var b: Vector2 = Layout.track_cell(Layout.gate_index(w[0]))
                for i in range(1, 7):
                    anim[key] = a.lerp(b, i / 6.0)
                    _redraw()
                    await get_tree().create_timer(0.035).timeout
                anim.erase(key)
            "capture":
                _cue("capture")
                var key := _key(e.pawn)
                for i in range(6):
                    anim_alpha[key] = 1.0 - i / 6.0
                    _redraw()
                    await get_tree().create_timer(0.05).timeout
                anim_alpha.erase(key)
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
                await get_tree().create_timer(0.55).timeout
            "swap", "discard":
                if String(e.type) != "discard": _cue(String(e.type))
                _redraw()
                await get_tree().create_timer(0.18).timeout
    anim.clear()
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
func on_press(p: Vector2):
    # tutorial e menu ficam por cima de tudo
    for h in range(hits.size() - 1, -1, -1):
        var hit: Dictionary = hits[h]
        if Rect2(hit.rect).has_point(p):
            _on_hit(String(hit.id))
            return
    if mode == "game" and tut_page < 0 and not menu_open and g != null and g.turn == 0 and not busy and sel_card >= 0:
        var br := board_rect()
        var bp := (p - br.position) / (br.size.x / Layout.SIZE)
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
func _cue(kind: String, pitch := 1.0):
    cues_played.append(kind)
    if cues_played.size() > 60: cues_played.pop_front()
    if SFX.has(kind): Sound.play(stage, SFX[kind], float(SFX_DB.get(kind, -8.0)), pitch)

func _on_hit(id: String):
    var audio = stage.get_node_or_null("GameAudio") if stage != null else null
    if audio != null and audio.has_method("play_cue"): audio.play_cue("ui")
    if id.begins_with("card_"):
        pick_card(int(id.substr(5)))
        return
    if id == "ten_burn":
        pick_burn()
        return
    if id == "ten_move":
        pending = {} if pending.get("kind", "") == "burn" else pending
        if pending.is_empty(): _auto_sole_pawn()
        _redraw()
        return
    if id.begins_with("split_"):
        pick_split(int(id.substr(6)))
        return
    match id:
        "play": confirm()
        "cancel": cancel()
        "help": tut_page = 0
        "mute_music": Sound.toggle_music(hub)
        "mute_fx": Sound.toggle_effects(hub)
        "menu": menu_open = not menu_open
        "menu_close": menu_open = false
        "menu_tutorial":
            menu_open = false
            tut_page = 0
        "menu_quit":
            menu_open = false
            if mode == "game": _record_history("abandon")
            mode = "lobby"
            g = null
            access.refresh()
        "lobby_play": start_game()
        "lobby_tutorial": tut_page = 0
        "lobby_back", "over_back": close()
        "lobby_club":
            close()
            if hub != null and hub.has_method("open_club"): hub.open_club()
        "over_again":
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
    return Rect2(30, 430, 1020, 1020) if portrait else Rect2(480, 103, 955, 955)

func card_rect(i: int, n: int) -> Rect2:
    if portrait:
        var xs := [265.0, 445.0, 612.0, 778.0]
        var ys := [1515.0, 1545.0, 1545.0, 1550.0]
        var span := 4.0 / maxf(1.0, n)
        return Rect2(xs[mini(i, 3)] + (span - 1.0) * 30.0, ys[mini(i, 3)], 180, 252)
    var col := i % 2
    var row := i / 2
    return Rect2(1490.0 + col * 200.0, 266.0 + row * 280.0, 183, 258)

# ---------------------------------------------------------------- tutorial
const TUTORIAL := [
    {"title": "BEM-VINDO À MARCHA REAL", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png",
        "text": "Quatro reinos disputam uma corrida de peões ao redor da mesa de pedra. Você joga com o MARFIM (embaixo) ao lado do aliado ÔNIX (em cima), contra RUBI e ESMERALDA.\n\nCada peão que chega ao fim do caminho é COROADO, como na promoção do xadrez."},
    {"title": "O CAMINHO", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png", "marks": true,
        "text": "1 PÁTIO: onde seus 4 peões começam.\n2 PORTÃO: a casa de saída, com a seta do sentido.\n3 MURALHA: a trilha de 76 casas, no sentido horário.\n4 ENTRADA DO SALÃO: a casa com aro na sua cor.\n5 SALÃO DO TRONO: 4 casas; quem entra é coroado."},
    {"title": "AS CARTAS", "img": "res://marcha/art/tutorial/cartas_todas.png",
        "text": "Na sua vez você joga UMA carta da mão (4 cartas por rodada). A carta diz o que fazer na faixa de ação e na frase embaixo da ilustração: A e K tiram um peão do Pátio (ou andam 11 / 13), Q anda 12, 10, 9, 8, 6, 3 e 2 andam o número."},
    {"title": "CARTAS ESPECIAIS", "img": "res://marcha/art/simbolos_de_acao.png",
        "text": "J troca seu peão de lugar com outra peça.\n7 divide as 7 casas entre até 2 peões seus.\n5 move QUALQUER peça da mesa 5 casas.\n-4 só volta 4 casas (logo depois do Portão, volta para perto da Entrada do Salão).\nSem jogada possível: descarte uma carta."},
    {"title": "CAPTURA E PROTEÇÃO", "img": "res://marcha/art/tutorial/tabuleiro_jogada_em_destaque.png",
        "text": "Cair na casa de outro peão manda esse peão de volta ao Pátio (cuidado: vale até para o aliado).\n\nPeão parado no PRÓPRIO Portão protege a casa: ninguém passa por cima nem cai nela."},
    {"title": "COROAÇÃO E VITÓRIA", "img": "res://marcha/art/tutorial/tabuleiro_com_pecas.png",
        "text": "Na Entrada do Salão o peão entra no Salão do Trono e ganha a coroa — o número de casas precisa caber.\n\nQuem coroar os 4 peões passa a jogar com os peões do aliado. Vence a dupla que coroar os 8."},
    {"title": "COMO JOGAR NA TELA", "img": "res://marcha/art/tutorial/tabuleiro_jogada_em_destaque.png",
        "text": "1 Toque numa carta da mão: ela sobe e a linha de ajuda diz o que ela faz.\n2 Toque num peão com aro dourado: o caminho aparece em pontos de ouro.\n3 Toque em JOGAR CARTA. CANCELAR desfaz a escolha.\nVocê tem 30 segundos por vez."},
]

# ================================================================= desenho
class TableView extends Control:
    # No celular o toque já chega também como clique emulado: tratar os dois = jogada dupla.
    static var EMULATED_MOUSE: bool = bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))
    var ui
    var tex_cache := {}
    func _init():
        mouse_filter = Control.MOUSE_FILTER_STOP
    func _gui_input(event):
        var pos := Vector2.INF
        if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
        elif event is InputEventScreenTouch and event.pressed and not EMULATED_MOUSE: pos = event.position
        if pos == Vector2.INF: return
        accept_event()
        ui.on_press((pos - ui.origin) / ui.k)
    func tex(path: String) -> Texture2D:
        if not tex_cache.has(path): tex_cache[path] = load(path)
        return tex_cache[path]
    func _draw():
        if ui == null: return
        ui.hits.clear()
        var vs := size
        draw_texture_rect(ui.BG, Rect2(Vector2.ZERO, vs), false)
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
        match ui.mode:
            "lobby": _draw_lobby()
            "game", "over": _draw_game()
        if ui.mode == "over": _draw_over()
        if ui.menu_open: _draw_menu()
        if ui.tut_page >= 0: _draw_tutorial()
        if not ui.flash.is_empty(): _draw_flash()
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    # ------------------------------------------------------------ primitivas
    func text(s: String, pos: Vector2, font_key: String, fs: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT):
        draw_string(ui.fonts[font_key], pos, s, align, width, fs, col)
    func text_w(s: String, font_key: String, fs: int) -> float:
        return ui.fonts[font_key].get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
    func fit(s: String, font_key: String, fs: int, room: float) -> int:
        var f := fs
        while f > 10 and text_w(s, font_key, f) > room: f -= 1
        return f
    func panel(r: Rect2, glow := false, fill: Color = Color("0f2b20")):
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
    func dark_button(r: Rect2, label: String, fs: int, id: String, enabled := true):
        draw_rect(r, Color("07110c"))
        draw_rect(r, Color("c99a45") if enabled else Color("4a4030"), false, 2.0)
        draw_rect(r.grow(-5), Color(0.79, 0.6, 0.27, 0.25), false, 1.0)
        var f2 := fit(label, "bold_sp", fs, r.size.x - 20)
        text(label, Vector2(r.position.x, r.get_center().y + f2 * 0.36), "bold_sp", f2, ui.CREAM if enabled else Color("6b6656"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        if enabled: ui.hits.append({"rect": r, "id": id})
    func square_button(r: Rect2, glyph: String, id: String):
        draw_rect(r, Color("0a1611"))
        draw_rect(r, ui.GOLD, false, 2.0)
        if glyph == "?":
            text("?", Vector2(r.position.x, r.get_center().y + 11), "bold", 30, ui.GOLD, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        else:
            for i in 3: draw_line(r.get_center() + Vector2(-9, -6 + i * 6), r.get_center() + Vector2(9, -6 + i * 6), ui.GOLD, 2.5)
        ui.hits.append({"rect": r, "id": id})
    func sound_button(r: Rect2, kind: String):
        var off: bool = ui.Sound.music_muted(ui.hub) if kind == "music" else ui.Sound.effects_muted(ui.hub)
        draw_rect(r, Color("0a1611"))
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
        draw_rect(Rect2(0, 0, w, 82 if not ui.portrait else 116), Color(0.02, 0.05, 0.04, 0.55))
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

    # ------------------------------------------------------------ placas dos jogadores
    func _plate(r: Rect2, seat: int, big := false):
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
            draw_texture_rect(ui.portraits[ui.BOTS[seat].portrait], pr, false)
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
            draw_rect(cr, Color("1c4a35"))
            draw_rect(cr, Color("b8892f"), false, 1.0)
            diamond(cr.get_center(), 3, Color("d9b45e"))
        var dx := x + maxf(n, 3) * 17 + 18
        for d in 4:
            var c := Vector2(dx + d * 21, r.position.y + 96)
            if d < home: draw_circle(c, 6.5, ui.KINGDOM_DOT[seat])
            draw_arc(c, 6.5, 0, TAU, 20, Color("cfd3cf") if d >= home else Color(1, 1, 1, 0.6), 1.5)

    # ------------------------------------------------------------ tabuleiro, peões e descarte
    func _draw_board():
        var br: Rect2 = ui.board_rect()
        draw_texture_rect(ui.BOARD, br, false)
        var s: float = br.size.x / ui.Layout.SIZE
        var g = ui.g
        if g == null: return
        draw_set_transform(ui.origin + br.position * ui.k, 0.0, Vector2(ui.k * s, ui.k * s))
        # descarte sobre o emblema central
        var n: int = g.discard.size()
        var rots := [-0.21, 0.13, -0.06]
        for j in range(maxi(0, n - 3), n):
            var rank: String = g.discard[j]
            var a: float = rots[(j - maxi(0, n - 3)) % 3]
            var cs := Vector2(270, 378)
            draw_set_transform(ui.origin + (br.position + Vector2(800, 805) * s) * ui.k, a, Vector2(ui.k * s, ui.k * s))
            draw_texture_rect(ui.cards[rank], Rect2(-cs / 2.0, cs), false)
        draw_set_transform(ui.origin + br.position * ui.k, 0.0, Vector2(ui.k * s, ui.k * s))
        # caminho da jogada escolhida
        var dots: Array = []
        var dest: Array = []
        var pd: Dictionary = ui.pending
        if not pd.is_empty() and not ui.busy and g.turn == 0:
            _collect_path(g, pd, dots, dest)
        for p in dots: draw_circle(p, 7.0, Color("f1c24f"))
        for p in dest:
            draw_circle(p, 24.0, Color(1.0, 0.82, 0.3, 0.35))
            draw_circle(p, 19.0, Color("f3c757"))
            draw_arc(p, 19.0, 0, TAU, 32, Color("fff2c2"), 2.0)
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
            if cands.has(w):
                draw_arc(c + Vector2(0, 2), 25.0, 0, TAU, 36, Color(1.0, 0.82, 0.32, 0.55 + 0.45 * pulse), 3.0)
            if w == ui.sel_pawn or w == ui.sel_target or w == ui.sel_second:
                draw_arc(c + Vector2(0, 2), 26.0, 0, TAU, 36, Color(1, 1, 1, 0.95), 5.0)
                lift = 6.0
            var crowned: bool = g.pawns[w[0]][w[1]].zone == "lane"
            var tx: Texture2D = ui.pawn_tex[w[0] + (10 if crowned else 0)]
            var sz: Vector2 = tx.get_size() * ui.PAWN_SCALE
            var rr := Rect2(Vector2(c.x - sz.x / 2.0, c.y + ui.PAWN_BASE - sz.y - lift), sz)
            draw_texture_rect(tx, rr, false, Color(1, 1, 1, alpha))
        _draw_celebs()
        draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))

    ## R35 · peão chegou ao Salão: anel dourado que se abre, raios girando, faíscas e "COROADO!" subindo.
    func _draw_celebs():
        for c in ui.celebs:
            var k: float = clampf(c.t / ui.CELEB_T, 0.0, 1.0)
            var p: Vector2 = c.p + Vector2(0, -18)
            var z := 1.9                 # tamanho (coordenadas da arte do tabuleiro)
            var fade := 1.0 - k
            var col: Color = ui.KINGDOM_COLOR[int(c.seat)]
            var ease := 1.0 - pow(1.0 - minf(1.0, k * 2.2), 3.0)
            # clarão
            draw_circle(p, (34.0 + 30.0 * ease) * z, Color(1.0, 0.85, 0.4, 0.28 * fade))
            # anéis
            for ring in 2:
                var rk := clampf(k * 1.6 - ring * 0.25, 0.0, 1.0)
                if rk <= 0.0: continue
                draw_arc(p, (20.0 + 95.0 * rk) * z, 0, TAU, 48, Color(1.0, 0.86, 0.38, (1.0 - rk) * 0.95), (6.0 * (1.0 - rk) + 1.5) * z)
            draw_arc(p, (30.0 + 40.0 * ease) * z, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8 * fade), 3.0 * z)
            # raios
            for i in 12:
                var a: float = ui.t * 1.6 + TAU * i / 12.0
                var r0 := (28.0 + 20.0 * ease) * z
                var r1 := r0 + (38.0 if i % 2 == 0 else 22.0) * fade * z
                draw_line(p + Vector2.from_angle(a) * r0, p + Vector2.from_angle(a) * r1, Color(1.0, 0.92, 0.55, 0.85 * fade), 4.0 * z)
            # faíscas
            for i in 10:
                var a2 := TAU * i / 10.0 + 0.3
                var d := (24.0 + 110.0 * ease) * z
                var q := p + Vector2.from_angle(a2) * d + Vector2(0, 60.0 * k * k * z)
                draw_circle(q, (5.0 * fade + 1.0) * z, Color(1.0, 0.95, 0.7, fade))
            # texto subindo
            var ty := p.y - (70.0 + 50.0 * ease) * z
            var ta := clampf(fade * 1.6, 0.0, 1.0)
            text("COROADO!", Vector2(p.x - 300 + 4, ty + 4), "title", 76, Color(0.1, 0.05, 0.0, 0.7 * ta), 600, HORIZONTAL_ALIGNMENT_CENTER)
            text("COROADO!", Vector2(p.x - 300, ty), "title", 76, Color(1.0, 0.86, 0.36, ta), 600, HORIZONTAL_ALIGNMENT_CENTER)

    func _collect_path(g, mv: Dictionary, dots: Array, dest: Array):
        var parts := []
        match String(mv.kind):
            "move": parts.append([mv.pawn, g.forward_path(mv.pawn[0], mv.pawn[1], int(mv.steps))])
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
    func _draw_hand():
        var g = ui.g
        var hand: Array = g.hands[0] if g != null else []
        var n := hand.size()
        for i in n:
            var r: Rect2 = ui.card_rect(i, n)
            var selected: bool = i == ui.sel_card
            var rot := 0.0
            if ui.portrait: rot = [-0.05, 0.03, 0.03, 0.06][mini(i, 3)]
            if selected:
                r = r.grow(6)
                r.position.y -= 18 if ui.portrait else 4
            var c := r.get_center()
            draw_set_transform(ui.origin + c * ui.k, rot, Vector2(ui.k, ui.k))
            var local := Rect2(-r.size / 2.0, r.size)
            if selected:
                for gl in 5: draw_rect(local.grow(3 + gl * 3), Color(1.0, 0.8, 0.3, 0.22 - gl * 0.04), false, 3.0)
            draw_texture_rect(ui.cards[hand[i]], local, false, Color.WHITE if (g.turn == 0 or selected) else Color(0.85, 0.85, 0.85))
            draw_set_transform(ui.origin, 0.0, Vector2(ui.k, ui.k))
            ui.hits.append({"rect": r, "id": "card_%d" % i})

    func _draw_turn_box(r: Rect2):
        var g = ui.g
        var mine: bool = g != null and g.turn == 0 and ui.mode == "game"
        var top := Color("ffd65c") if mine else Color("2a4d3c")
        var bot := Color("e9a417") if mine else Color("163326")
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
            draw_rect(r, Color("f0c44c") if on else Color("0a1611"))
            draw_rect(r, ui.GOLD, false, 2.0)
            var f := fit(items[i][1], "bold", 20, r.size.x - 10)
            text(items[i][1], Vector2(r.position.x, r.position.y + 28), "bold", f, Color("1c1405") if on else ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
            ui.hits.append({"rect": r, "id": items[i][0]})

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
            draw_rect(r, Color("f0c44c") if on else Color("0a1611"))
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
            if ui.split_options().size() <= 1 and not ui.ten_choice(): _draw_help(Rect2(140, 1462, 800, 60))
            else: _draw_split(Vector2(150, 1478), 66.0)
            # meu retrato + SUA VEZ
            var pr := Rect2(20, 1563, 130, 130)
            draw_texture_rect(ui.portraits.voce, pr, false)
            if ui.my_portrait != null: draw_texture_rect(ui.my_portrait, pr.grow(-10), false)
            _draw_turn_box(Rect2(20, 1700, 212, 60))
            _draw_hand()
            dark_button(Rect2(20, 1810, 330, 86), "CANCELAR", 34, "cancel", not ui.pending.is_empty() or ui.sel_card >= 0)
            gold_button(Rect2(370, 1810, 690, 86), "DESCARTAR CARTA" if ui.pending.get("kind", "") == "discard" else "JOGAR CARTA", 38, "play", not ui.pending.is_empty() and g.turn == 0 and not ui.busy)
        else:
            _plate(Rect2(40, 120, 390, 122), 2)
            _plate(Rect2(40, 262, 390, 122), 1)
            _plate(Rect2(40, 404, 390, 122), 3)
            # últimas jogadas
            var lr := Rect2(40, 556, 390, 316)
            draw_rect(lr, Color(0.02, 0.07, 0.05, 0.75))
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
            gold_button(Rect2(1482, 880, 398, 86), "DESCARTAR CARTA" if ui.pending.get("kind", "") == "discard" else "JOGAR CARTA", 40, "play", not ui.pending.is_empty() and g.turn == 0 and not ui.busy)
            dark_button(Rect2(1482, 985, 398, 64), "CANCELAR", 30, "cancel", not ui.pending.is_empty() or ui.sel_card >= 0)

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
        var desc := "Quatro reinos disputam uma corrida de peões ao redor de uma mesa de pedra esculpida. Cada peão que chega ao fim do caminho é coroado. Você e seu aliado contra dois reinos rivais."
        var lines := _wrap(desc, "semi", 25, pr.size.x - 80)
        for li in lines.size(): text(lines[li], Vector2(x, y + 92 + li * 34), "semi", 25, ui.CREAM)
        var sy := y + 110 + lines.size() * 34
        var badge := String(info.get("label", "VERIFICANDO ACESSO…"))
        var ok: bool = bool(info.get("can_play", false))
        var bw := text_w(badge, "bold_sp", 18) + 30
        var brr := Rect2(Vector2(x, sy), Vector2(bw, 36))
        draw_rect(brr, Color("1d6b45") if ok else Color("5a2a1a"))
        draw_rect(brr, Color("8fe0a8") if ok else Color("f2a070"), false, 2.0)
        text(badge, Vector2(brr.position.x, brr.position.y + 26), "bold_sp", 18, Color("eafff0") if ok else Color("ffe2c8"), brr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
        var note := String(info.get("note", ""))
        if not note.is_empty():
            var nl := _wrap(note, "semi", 21, pr.size.x - 80)
            for li in nl.size(): text(nl[li], Vector2(x, sy + 70 + li * 28), "semi", 21, Color("c9c2a8"))
        # botões
        if ui.portrait:
            var by := 1450.0
            if ok: gold_button(Rect2(60, by, 960, 100), "JOGAR AGORA", 44, "lobby_play")
            else: gold_button(Rect2(60, by, 960, 100), "CONHECER CLUB FRAIHA", 40, "lobby_club")
            dark_button(Rect2(60, by + 120, 960, 84), "COMO JOGAR", 34, "lobby_tutorial")
            dark_button(Rect2(60, by + 222, 960, 84), "VOLTAR", 34, "lobby_back")
        else:
            var by2 := 700.0
            if ok: gold_button(Rect2(70, by2, 520, 96), "JOGAR AGORA", 42, "lobby_play")
            else: gold_button(Rect2(70, by2, 520, 96), "CONHECER CLUB FRAIHA", 36, "lobby_club")
            dark_button(Rect2(620, by2 + 8, 300, 80), "COMO JOGAR", 30, "lobby_tutorial")
            dark_button(Rect2(950, by2 + 8, 200, 80), "VOLTAR", 30, "lobby_back")

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
        text(String(page.title), Vector2(r.position.x + 36, r.position.y + 96), "title", 40 if not ui.portrait else 38, Color("e9b94a"))
        var img: Texture2D = tex(String(page.img))
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
        draw_texture_rect(img, ir, false)
        draw_rect(ir, Color("c99a45"), false, 2.0)
        if page.get("marks", false): _tutorial_marks(ir)
        var y := tr.position.y + 26
        for para in String(page.text).split("\n"):
            for ln in _wrap(para, "semi", 25, tr.size.x):
                text(ln, Vector2(tr.position.x, y), "semi", 25, ui.CREAM)
                y += 34
            y += 6 if para.is_empty() else 4
        var by: float = r.end.y - 96
        dark_button(Rect2(r.position.x + 36, by, 220, 66), "ANTERIOR", 26, "tut_prev", ui.tut_page > 0)
        dark_button(Rect2(r.get_center().x - 110, by, 220, 66), "FECHAR", 26, "tut_close")
        gold_button(Rect2(r.end.x - 316, by, 280, 66), "COMEÇAR" if ui.tut_page == ui.TUTORIAL.size() - 1 else "PRÓXIMO", 28, "tut_next")

    ## Números dos componentes sobre o tabuleiro (como na página 03 do conceito).
    func _tutorial_marks(ir: Rect2):
        var s: float = ir.size.x / ui.Layout.SIZE
        var marks := [[ui.Layout.home_center(0), "1"], [ui.Layout.track_cell(0), "2"], [ui.Layout.track_cell(9), "3"], [ui.Layout.track_cell(74), "4"], [ui.Layout.lane_cell(0, 2), "5"]]
        for m in marks:
            var c: Vector2 = ir.position + Vector2(m[0]) * s + Vector2(26, -26)
            draw_circle(c, 17, Color("f0c44c"))
            draw_arc(c, 17, 0, TAU, 24, Color("2a1a04"), 2.0)
            text(String(m[1]), Vector2(c.x - 17, c.y + 9), "bold", 24, Color("1c1405"), 34, HORIZONTAL_ALIGNMENT_CENTER)

    func _draw_flash():
        var w := text_w(ui.flash, "semi", 26) + 60
        var r := Rect2(Vector2(ui.design.x / 2.0 - w / 2.0, ui.design.y * (0.88 if not ui.portrait else 0.18)), Vector2(w, 56))
        draw_rect(r, Color(0.05, 0.08, 0.06, 0.94))
        draw_rect(r, ui.GOLD, false, 2.0)
        text(ui.flash, Vector2(r.position.x, r.position.y + 37), "semi", 26, ui.CREAM, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
