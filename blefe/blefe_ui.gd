extends CanvasLayer
## BLEFE REAL — tela do modo (tutorial/salão, partida, XEQUE, Relógio de Xeque, XEQUE-MATE e resultado).
## As artes aprovadas do pacote (mesa, cartas, relógio, coroas, botões e fontes) são usadas como
## camadas; placas, painéis, textos, áreas de toque e estados são desenhados por cima, nas posições
## medidas das telas de referência (PC 1920x1080, celular retrato 1080x1920, celular paisagem 1950x900).
## A interface NÃO decide regra: toda ação é pedida ao motor (blefe/rules.gd). Os bots recebem só o
## estado público e a própria mão (blefe/ai.gd). A animação nunca é a autoridade do estado.
signal closed

const Rules := preload("res://blefe/rules.gd")
const AI := preload("res://blefe/ai.gd")
const SCENE := preload("res://blefe/art/mesa/mesa_cena_com_tapete.png")
const CARD_BACK := preload("res://blefe/art/cartas/carta_verso.png")
const CROWN := preload("res://blefe/art/interface/coroa.png")
const CROWN_LOST := preload("res://blefe/art/interface/coroa_perdida.png")
const BTN_GOLD := preload("res://blefe/art/interface/botao_dourado.png")
const BTN_DARK := preload("res://blefe/art/interface/botao_escuro.png")
const GOLD_PIECES := preload("res://cosmetics/v025/gold_pieces.png")
const FONT_UI := preload("res://blefe/art/fontes/Jersey20-Regular.woff2")
const FONT_TITLE := preload("res://blefe/art/fontes/Jacquard24-Regular.woff2")
const TUTORIAL_BG := preload("res://blefe/art/telas/tutorial_fundo.png")
const RESULT_BG := preload("res://blefe/art/telas/resultado_fundo.png")
## peças douradas do conjunto Ouro do jogo (as mesmas desenhadas nas cartas)
const PIECE_REGION := {"rei": Rect2(1524, 15, 197, 399), "rainha": Rect2(1227, 59, 198, 354), "cavalo": Rect2(623, 69, 220, 345), "peao": Rect2(63, 148, 170, 265)}

# paleta do pacote (marcha_real.json)
const GOLD := Color("e8b242")
const GOLD_LIGHT := Color("ffeea5")
const WINE := Color("7d0f1c")
const PANEL := Color("0f2a1e")
const PANEL_TOP := Color("154031")
const IVORY := Color("f6ecd2")
const DANGER := Color("e02a36")
const MAGIC := Color("b068ff")
const BOT_BLUE := Color("6fb4ee")
const YOUR_TURN := Color("ffd257")
const OUTLINE := Color("120a06")
const GREY := Color("6b6f72")

const TURN_MS := 30000
const LOW_TIME_MS := 8000
const BOT_DELAY_MIN := 1.0
const BOT_DELAY_MAX := 2.2
## lugares: 0 você (embaixo), 1 esquerda, 2 cima, 3 direita (sentido horário)
const SEAT_NAMES := ["Você", "Dama de Ferro", "Sir Gambito", "Torre Velha"]
const SEAT_PROFILE := ["", "cauteloso", "equilibrado", "blefador"]
const SEAT_AVATAR := ["", "res://profile/avatars/ferro_reward.png", "res://profile/avatars/ouro_reward.png", "res://profile/avatars/bronze_reward.png"]
const DEFAULT_YOU := "res://profile/avatars/prata_reward.png"

var hub = null
var stage = null
var root: Control
var view: Control
var g: Rules = null
var mode := "tutorial"            # tutorial | game | over
var tutorial_from_game := false
var menu_open := false
var confirm_quit := false
var layout := "desktop"           # desktop | portrait | landscape
var design := Vector2(1920, 1080)
var k := 1.0
var origin := Vector2.ZERO
var fonts := {}
var cards := {}
var avatars := []
var pieces := {}
var clock_tex := {}
var xeque_tex := {}
# ---- jogada humana
var selected: Array = []          # índices na mão
var input_locked := false         # depois de JOGAR / XEQUE, até o próximo turno
var turn_left_ms := TURN_MS
var bot_wait := -1.0
# ---- apresentação (não é autoridade: o motor já resolveu tudo)
var bubble := {}                  # {seat, text}
var fly: Array = []               # cartas voando para o centro: {from, t}
var phase := ""                   # "" | reveal | clock | safe | mate | elim
var phase_t := 0.0
var result := {}                  # último resultado de XEQUE (do motor)
var xeque_caller := -1
var hits: Array = []
var hover_id := ""
var pressed_id := ""
var t := 0.0
var started_unix := 0
var started_ms := 0
var recorded := false
var flash := ""
var flash_t := 0.0
var rng := RandomNumberGenerator.new()
var seed_override := 0            # testes: semente fixa

const PHASE_TIME := {"reveal": 1.7, "clock": 1.4, "safe": 1.4, "mate": 2.6, "elim": 1.6}

func _init():
    layer = 64
    name = "BlefeReal"
    rng.randomize()

func setup(p_hub, p_stage):
    hub = p_hub
    stage = p_stage

func _ready():
    for n in ["rei", "rainha", "cavalo", "peao"]: cards[n] = load("res://blefe/art/cartas/carta_%s.png" % n)
    for s in ["neutro", "pulsando", "perigo", "quase", "disparado"]: clock_tex[s] = load("res://blefe/art/relogio/relogio_%s.png" % s)
    for s in ["normal", "hover", "pressionado", "desabilitado", "ativado"]: xeque_tex[s] = load("res://blefe/art/interface/botao_xeque_%s.png" % s)
    for n in PIECE_REGION:
        var a := AtlasTexture.new()
        a.atlas = GOLD_PIECES
        a.region = PIECE_REGION[n]
        pieces[n] = a
    for pair in [["ui", FONT_UI, 0], ["ui_sp", FONT_UI, 2], ["ui_sp4", FONT_UI, 4], ["title", FONT_TITLE, 0]]:
        var fv := FontVariation.new()
        fv.base_font = pair[1]
        fv.spacing_glyph = pair[2]
        fonts[pair[0]] = fv
    root = Control.new()
    root.name = "BlefeRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    view = preload("res://blefe/blefe_view.gd").new()
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
    mode = "tutorial"
    tutorial_from_game = false
    menu_open = false
    confirm_quit = false
    g = null
    _load_avatars()
    _relayout()

func close():
    visible = false
    root.visible = false
    mode = "tutorial"
    g = null
    phase = ""
    closed.emit()

func is_open() -> bool:
    return visible

func _load_avatars():
    avatars = [null, null, null, null]
    var mine = hub.avatar_texture() if hub != null and hub.has_method("avatar_texture") else null
    avatars[0] = mine if mine != null else load(DEFAULT_YOU)
    for s in range(1, 4): avatars[s] = load(SEAT_AVATAR[s])

func _input(event):
    if not visible: return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        if confirm_quit: confirm_quit = false
        elif menu_open: menu_open = false
        elif mode == "tutorial" and tutorial_from_game: _resume_from_tutorial()
        elif mode == "game": menu_open = true
        elif mode == "tutorial" or mode == "over": close()
        _redraw()

func _relayout():
    if root == null: return
    var vs := root.get_viewport_rect().size
    if vs.y > vs.x * 1.15: layout = "portrait"
    elif vs.x / maxf(1.0, vs.y) >= 1.95: layout = "landscape"
    else: layout = "desktop"
    design = {"desktop": Vector2(1920, 1080), "portrait": Vector2(1080, 1920), "landscape": Vector2(1950, 900)}[layout]
    k = minf(vs.x / design.x, vs.y / design.y)
    origin = (vs - design * k) / 2.0
    _redraw()

func _redraw():
    # áreas de toque da moldura anterior deixam de valer até o próximo desenho
    hits.clear()
    if view != null: view.queue_redraw()

# ---------------------------------------------------------------- partida
func start_game():
    if mode == "game" and g != null and g.state != Rules.MATCH_END: return
    g = Rules.new()
    var names := SEAT_NAMES.duplicate()
    g.setup(seed_override if seed_override != 0 else 0, names)
    if seed_override != 0: rng.seed = seed_override * 31
    mode = "game"
    menu_open = false
    confirm_quit = false
    tutorial_from_game = false
    phase = ""
    result = {}
    bubble = {}
    fly = []
    recorded = false
    started_unix = int(Time.get_unix_time_from_system())
    started_ms = Time.get_ticks_msec()
    _begin_turn()

func _begin_turn():
    if g == null or mode != "game": return
    selected = []
    input_locked = false
    turn_left_ms = TURN_MS
    bot_wait = -1.0
    if g.state != Rules.TURN_WAITING:
        _redraw()
        return
    if g.turn != 0: bot_wait = rng.randf_range(BOT_DELAY_MIN, BOT_DELAY_MAX)
    _redraw()

func _process(delta):
    if not visible: return
    t += delta
    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0: flash = ""
    for f in fly: f.t += delta * 3.2
    fly = fly.filter(func(f): return f.t < 1.0)
    if mode == "game" and g != null and not menu_open and not confirm_quit:
        if phase != "":
            phase_t += delta
            if phase_t >= PHASE_TIME[phase]: _advance_phase()
        elif g.state == Rules.TURN_WAITING:
            if g.turn == 0:
                if not input_locked:
                    turn_left_ms -= int(delta * 1000.0)
                    if turn_left_ms <= 0:
                        turn_left_ms = 0
                        _timeout()
            elif bot_wait >= 0.0:
                bot_wait -= delta
                if bot_wait < 0.0: _bot_act()
    _redraw()

## Tempo esgotado: o motor joga 1 carta da mão (escolha cega); nunca XEQUE.
func _timeout():
    if input_locked or g.turn != 0: return
    input_locked = true
    var pub := g.timeout_action(0)
    _flash("Tempo esgotado: uma carta foi jogada por você.")
    _after_play(0, pub)

func _bot_act():
    var s := g.turn
    var d := AI.decide(g.public_state(s), g.private_hand(s), SEAT_PROFILE[s], rng)
    if d.action == "challenge" and g.can_challenge(s):
        _on_challenge(g.challenge(s), s)
        return
    var pub := g.play(s, d.get("idx", [0]))
    if pub.is_empty(): pub = g.timeout_action(s)   # nunca deve acontecer: o motor recusou; joga 1 carta
    _after_play(s, pub)

func _after_play(seat: int, pub: Dictionary):
    if pub.is_empty():
        _begin_turn()
        return
    bubble = {"seat": seat, "count": int(pub.count), "target": g.target}
    fly.append({"from": seat, "t": 0.0, "count": int(pub.count)})
    _cue("card")
    if pub.has("forced"):
        _on_challenge(pub.forced, int(pub.forced.caller))
        return
    _begin_turn()

# ---------------------------------------------------------------- jogada humana
func toggle_card(i: int):
    if mode != "game" or g == null or g.turn != 0 or input_locked or phase != "" or g.state != Rules.TURN_WAITING: return
    if i < 0 or i >= g.hands[0].size(): return
    if i in selected: selected.erase(i)
    elif selected.size() < Rules.MAX_PLAY: selected.append(i)
    _cue("ui")
    _redraw()

func can_human_play() -> bool:
    return mode == "game" and g != null and phase == "" and not input_locked and g.state == Rules.TURN_WAITING and g.turn == 0 and selected.size() >= 1 and selected.size() <= Rules.MAX_PLAY

func can_human_challenge() -> bool:
    return mode == "game" and g != null and phase == "" and not input_locked and g.can_challenge(0)

func human_play():
    if not can_human_play(): return
    input_locked = true                # trava toque/clique duplo
    var idx := selected.duplicate()
    selected = []
    _after_play(0, g.play(0, idx))

func human_challenge():
    if not can_human_challenge(): return
    input_locked = true
    _on_challenge(g.challenge(0), 0)

# ---------------------------------------------------------------- XEQUE → relógio → xeque-mate
func _on_challenge(r: Dictionary, caller: int):
    if r.is_empty():
        _begin_turn()
        return
    result = r
    xeque_caller = caller
    input_locked = true
    selected = []
    phase = "reveal"
    phase_t = 0.0
    _cue("xeque")
    _redraw()

func _advance_phase():
    phase_t = 0.0
    match phase:
        "reveal":
            phase = "clock"
            _cue("clock")
        "clock":
            phase = "mate" if bool(result.mate) else "safe"
            _cue("mate" if bool(result.mate) else "safe")
        "safe", "mate":
            if bool(result.get("eliminated", false)): phase = "elim"
            else: _end_resolution()
        "elim":
            _end_resolution()
    _redraw()

func _end_resolution():
    phase = ""
    bubble = {}
    if g.state == Rules.MATCH_END:
        _finish()
        return
    g.next_round()
    _begin_turn()

## Pula a apresentação (testes / jogador apressado): o estado já é o do motor.
func skip_presentation():
    while phase != "": _advance_phase()

func _finish():
    mode = "over"
    phase = ""
    _record_history("win" if g.winner == 0 else "loss")
    _cue("victory" if g.winner == 0 else "defeat")
    _redraw()

# ---------------------------------------------------------------- histórico comum
func _record_history(res: String) -> Dictionary:
    if g == null or recorded or started_unix <= 0: return {}
    var mh = stage.get("match_history") if stage != null else null
    if mh == null or not mh.has_method("add_entry"): return {}
    recorded = true
    var final := []
    for s in Rules.SEATS:
        final.append({"seat": s, "name": g.names[s], "lives": g.lives[s], "placement": g.placement(s), "eliminated_round": g.eliminated_round[s], "bot": s != 0})
    var place := g.placement(0)
    if res == "abandon":
        place = g.alive_seats().size()      # sai no lugar em que estava
    return mh.add_entry({
        "mode_id": Rules.MODE_ID, "ruleset_version": Rules.RULESET_VERSION, "mode": "blefe",
        "result": res, "reason": "abandono" if res == "abandon" else "xeque-mate",
        "player": "Você", "opponent": "%s, %s e %s" % [g.names[1], g.names[2], g.names[3]],
        "started_at": started_unix, "finished_at": int(Time.get_unix_time_from_system()),
        "duration_s": int((Time.get_ticks_msec() - started_ms) / 1000), "players": Rules.SEATS,
        "placement": place, "plies": g.round_no,
        "data": {"rounds": g.round_no, "placement": place, "winner_player_id": g.winner, "winner_name": g.names[g.winner] if g.winner >= 0 else "", "final": final},
    })

## Sair da partida (confirmado): registra abandono e encerra o estado local.
func quit_match():
    if mode == "game" and g != null and g.state != Rules.MATCH_END: _record_history("abandon")
    g = null
    phase = ""
    menu_open = false
    confirm_quit = false
    mode = "tutorial"
    close()

func _resume_from_tutorial():
    mode = "game"
    tutorial_from_game = false
    _redraw()

# ---------------------------------------------------------------- toques
func on_press(p: Vector2):
    for h in range(hits.size() - 1, -1, -1):
        var hit: Dictionary = hits[h]
        if Rect2(hit.rect).has_point(p):
            _on_hit(String(hit.id))
            return

func on_hover(p: Vector2):
    var id := ""
    for h in range(hits.size() - 1, -1, -1):
        if Rect2(hits[h].rect).has_point(p):
            id = String(hits[h].id)
            break
    if id != hover_id:
        hover_id = id
        _redraw()

func _on_hit(id: String):
    if id.begins_with("card_"):
        toggle_card(int(id.substr(5)))
        return
    _cue("ui")
    match id:
        "play": human_play()
        "play_empty": _flash("Escolha de 1 a 3 cartas da sua mão.")
        "xeque": human_challenge()
        "help":
            tutorial_from_game = true
            mode = "tutorial"
        "menu": menu_open = true
        "menu_continue": menu_open = false
        "menu_tutorial":
            menu_open = false
            tutorial_from_game = true
            mode = "tutorial"
        "menu_quit":
            menu_open = false
            confirm_quit = true
        "quit_yes": quit_match()
        "quit_no": confirm_quit = false
        "tut_back":
            if tutorial_from_game: _resume_from_tutorial()
            else: close()
        "tut_play", "again": start_game()
        "over_tutorial":
            tutorial_from_game = false
            mode = "tutorial"
        "over_menu": close()
    _redraw()

func _flash(text: String):
    flash = text
    flash_t = 3.0

func _cue(kind: String):
    var audio = stage.get_node_or_null("GameAudio") if stage != null else null
    if audio != null and audio.has_method("play_cue"):
        audio.play_cue({"card": "wood", "xeque": "check", "clock": "bell", "safe": "ui", "mate": "mate", "victory": "win", "defeat": "loss"}.get(kind, "ui"))

# ---------------------------------------------------------------- consultas para o desenho
func clock_visual(seat: int) -> String:
    if seat < 0 or g == null: return "neutro"
    if phase == "mate" and int(result.loser) == seat: return "disparado"
    if phase == "clock" and int(result.loser) == seat: return "pulsando"
    var left := g.clock_left(seat)
    if phase in ["reveal", "clock"] and int(result.get("loser", -1)) == seat:
        left = int(result.clock_left_before)
    return {3: "neutro", 2: "perigo", 1: "quase"}.get(left, "neutro")

## De quem é o relógio mostrado no centro e no medidor.
func clock_focus() -> int:
    if g == null: return 0
    if phase != "" and not result.is_empty(): return int(result.loser)
    return g.turn if g.turn >= 0 else 0

func seat_status(s: int) -> Dictionary:
    if g == null: return {"text": "AGUARDANDO", "id": "aguardando"}
    if not g.alive(s) and not (phase in ["reveal", "clock", "mate"] and int(result.get("loser", -1)) == s):
        return {"text": "ELIMINADO", "id": "eliminado"}
    if phase != "" and not result.is_empty():
        if int(result.loser) == s:
            if phase == "mate" or phase == "elim": return {"text": "XEQUE-MATE!", "id": "xeque_mate"}
            if phase == "clock": return {"text": "COM O RELÓGIO", "id": "com_o_relogio"}
        if s == 0 and int(result.caller) == 0: return {"text": "VOCÊ DUVIDOU", "id": "aguardando"}
    if phase == "" and g.state == Rules.TURN_WAITING and g.turn == s:
        return {"text": "SUA VEZ", "id": "sua_vez"} if s == 0 else {"text": "PENSANDO...", "id": "pensando"}
    if not bubble.is_empty() and int(bubble.seat) == s:
        var said := "JOGOU %d" % int(bubble.count) if layout == "portrait" else "DISSE: " + g.declared_text(int(bubble.count), String(bubble.target))
        return {"text": said, "id": "declarou"}
    if g.lives[s] == 1: return {"text": "EM RISCO", "id": "em_risco"}
    if s == 0 and layout == "portrait": return {"text": "AGUARDE", "id": "aguardando"}
    return {"text": "AGUARDANDO", "id": "aguardando"}

func help_text() -> Array:
    # [linha1, linha2] com destaques entre * *
    if g == null or mode != "game": return ["", ""]
    if phase != "": return ["", ""]
    if g.turn == 0:
        if selected.is_empty():
            return ["Escolha de *1 a 3* cartas", "ou duvide com *XEQUE*"] if g.can_challenge(0) else ["Escolha de *1 a 3* cartas", "e baixe viradas para baixo"]
        return ["Você vai dizer: *%s*" % g.declared_text(selected.size()), "toque em *JOGAR CARTAS*"]
    return ["Vez de *%s*" % g.names[g.turn], "aguarde a jogada"]
