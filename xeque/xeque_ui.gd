extends CanvasLayer
## XEQUE — tela do modo (tutorial/salão, partida, XEQUE, Relógio de Xeque, XEQUE-MATE e resultado).
## As artes aprovadas do pacote (mesa, cartas, relógio, coroas, botões e fontes) são usadas como
## camadas; placas, painéis, textos, áreas de toque e estados são desenhados por cima, nas posições
## medidas das telas de referência (PC 1920x1080, celular retrato 1080x1920, celular paisagem 1950x900).
## A interface NÃO decide regra: toda ação é pedida ao motor (xeque/rules.gd). Os bots recebem só o
## estado público e a própria mão (xeque/ai.gd). A animação nunca é a autoridade do estado.
signal closed

const Rules := preload("res://xeque/rules.gd")
const AI := preload("res://xeque/ai.gd")
const SCENE := preload("res://xeque/art/mesa/mesa_cena_com_tapete.png")
const CARD_BACK := preload("res://xeque/art/cartas/carta_verso.png")
const CROWN := preload("res://xeque/art/interface/coroa.png")
const CROWN_LOST := preload("res://xeque/art/interface/coroa_perdida.png")
const BTN_GOLD := preload("res://xeque/art/interface/botao_dourado.png")
const BTN_DARK := preload("res://xeque/art/interface/botao_escuro.png")
const GOLD_PIECES := preload("res://cosmetics/v025/gold_pieces.png")
const Sound := preload("res://ui_v022/mode_sound.gd")
const MUSIC := "res://xeque/audio/musica_xeque.mp3"      # música enviada pelo dono do projeto (loop)
const SFX := {
    "card_1": preload("res://xeque/audio/carta_baixar_1.wav"), "card_2": preload("res://xeque/audio/carta_baixar_2.wav"),
    "card_3": preload("res://xeque/audio/carta_baixar_3.wav"), "your_turn": preload("res://xeque/audio/sua_vez.wav"),
    "xeque": preload("res://xeque/audio/xeque.wav"), "reveal": preload("res://xeque/audio/revelar.wav"),
    "clock": preload("res://xeque/audio/relogio.wav"), "safe": preload("res://xeque/audio/seguro.wav"),
    "mate": preload("res://xeque/audio/xeque_mate.wav"), "elim": preload("res://xeque/audio/eliminado.wav"),
    "victory": preload("res://xeque/audio/vitoria.wav"), "defeat": preload("res://xeque/audio/derrota.wav"),
    # R35.1 · vozes (tools/xeque_voice.py): "XEQUE!" a cada desafio, "XEQUE-MATE!" quando alguém cai
    "voice_xeque": preload("res://xeque/audio/voz_xeque.wav"), "voice_mate": preload("res://xeque/audio/voz_xeque_mate.wav"),
    # R36 · efeitos mais fortes (tools/xeque_sfx_r36.py)
    "xeque_hit": preload("res://xeque/audio/xeque_impacto.wav"), "flip": preload("res://xeque/audio/virar_carta.wav"),
    "clock_tension": preload("res://xeque/audio/relogio_tensao.wav"), "relief": preload("res://xeque/audio/seguro_alivio.wav"),
    "mate_boom": preload("res://xeque/audio/xeque_mate_boom.wav"), "defeat_final": preload("res://xeque/audio/derrota_final.wav"),
    "victory_final": preload("res://marcha/audio/vitoria_final.wav"), "deck_intro": preload("res://xeque/audio/baralho_intro.wav"),
}
const SFX_DB := {"xeque_hit": -2.0, "mate_boom": 0.0, "clock_tension": -4.0, "relief": -5.0, "victory_final": -4.0, "defeat_final": -4.0, "deck_intro": -6.0, "flip": -6.0, "voice_xeque": -1.0, "voice_mate": 0.0, "your_turn": -9.0, "xeque": -6.0, "mate": -3.0, "victory": -7.0, "defeat": -7.0, "elim": -6.0}
const FONT_UI := preload("res://xeque/art/fontes/Jersey20-Regular.woff2")
const FONT_TITLE := preload("res://xeque/art/fontes/Jacquard24-Regular.woff2")
const TUTORIAL_BG := preload("res://xeque/art/telas/tutorial_fundo.png")
const RESULT_BG := preload("res://xeque/art/telas/resultado_fundo.png")
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
const BOT_DELAY_MIN := 1.6       # R36: ritmo mais calmo (antes 1,0–2,2 s)
const BOT_DELAY_MAX := 3.0
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
var rng := RandomNumberGenerator.new()           # ritmo dos bots (gameplay local)
var fx_rng := RandomNumberGenerator.new()        # R36: só cosmético (partículas); nunca mexe no sorteio do jogo
var seed_override := 0            # testes: semente fixa
# ---- R35 · partida ONLINE com amigo (o servidor é a autoridade; aqui só pedimos ações e animamos)
var online := false
var room_id := ""
var players: Array = []           # [{name, bot, connected, left}] já girados (você = 0)
var ev_queue: Array = []

const PHASE_TIME := {"reveal": 2.6, "clock": 2.4, "safe": 2.0, "mate": 3.8, "elim": 2.0}   # R36: mais tempo para cada momento
## R36 · atrasos dos efeitos dentro de cada fase (segundos) e força do tremor — tudo num lugar só.
## Espelho no servidor: online_v021/modes/party.js (T.revealMs/clockMs/safeMs/mateMs/introMs/mesaMs).
const FX_DELAY := {"flip": 0.55, "voice_xeque": 0.12, "voice_mate": 0.45, "mate_red_flash": 0.12}
const FX_SHAKE := {"xeque": 18.0, "clock": 4.0, "mate": 38.0}
## R36 · efeitos de tela (motion): tremor, clarão, partículas e o "carimbo" de texto grande
var shake_amp := 0.0
var flash_col := Color(1, 1, 1, 0)
var particles: Array = []         # {p, v, life, max, col, size, kind}
var slam := {}                    # {text, sub, t, col}
var over_t := 0.0
## apresentação do baralho antes da 1ª rodada (quantas cartas de cada peça existem)
const INTRO_T := 3.2
var intro_anim := -1.0

func fx_shake(amp: float):
    shake_amp = maxf(shake_amp, amp)

func fx_flash(col: Color):
    flash_col = col

func fx_burst(at: Vector2, n: int, cols: Array, speed: float, size := 8.0, gravity := 900.0, kind := "shard", life := 1.4):
    for i in n:
        var a := fx_rng.randf_range(0, TAU)
        var sp := fx_rng.randf_range(speed * 0.35, speed)
        particles.append({"p": at, "v": Vector2.from_angle(a) * sp + Vector2(0, -speed * 0.25), "life": life * fx_rng.randf_range(0.6, 1.0), "max": life,
            "col": cols[i % cols.size()], "size": size * fx_rng.randf_range(0.5, 1.4), "kind": kind, "rot": fx_rng.randf_range(0, TAU), "spin": fx_rng.randf_range(-9, 9), "g": gravity})

func fx_slam(txt: String, sub: String, col: Color):
    slam = {"text": txt, "sub": sub, "t": 0.0, "col": col}

func shake_offset() -> Vector2:
    if shake_amp <= 0.05: return Vector2.ZERO
    return Vector2(sin(t * 73.0) + sin(t * 31.0) * 0.5, cos(t * 59.0) + cos(t * 23.0) * 0.5) * shake_amp

func _init():
    layer = 64
    name = "Xeque"
    rng.randomize()

func setup(p_hub, p_stage):
    hub = p_hub
    stage = p_stage

func _ready():
    for n in ["rei", "rainha", "cavalo", "peao"]: cards[n] = load("res://xeque/art/cartas/carta_%s.png" % n)
    for s in ["neutro", "pulsando", "perigo", "quase", "disparado"]: clock_tex[s] = load("res://xeque/art/relogio/relogio_%s.png" % s)
    for s in ["normal", "hover", "pressionado", "desabilitado", "ativado"]: xeque_tex[s] = load("res://xeque/art/interface/botao_xeque_%s.png" % s)
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
    root.name = "XequeRoot"
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(root)
    view = preload("res://xeque/xeque_view.gd").new()
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
    mode = "tutorial"
    tutorial_from_game = false
    menu_open = false
    confirm_quit = false
    g = null
    _load_avatars()
    _relayout()

func close():
    _popup_close()
    if online:
        if mode == "game" and g != null and g.state != Rules.MATCH_END: _record_history("abandon")
        _online_leave()
    visible = false
    root.visible = false
    Sound.music_off(stage)
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
    online = false
    g = Rules.new()
    var names := SEAT_NAMES.duplicate()
    g.setup(seed_override if seed_override != 0 else 0, names)
    if seed_override != 0:
        rng.seed = seed_override * 31
        fx_rng.seed = seed_override * 7
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
    mesa_round = -1
    particles = []
    slam = {}
    _start_intro()
    _begin_turn()

## R36 · antes da 1ª rodada: o baralho é apresentado (quantidades lidas de Rules.DECK_COUNTS)
func _start_intro():
    intro_anim = 0.0
    _cue("deck_intro")

## R34.1: a cada rodada nova a carta da MESA aparece grande no centro e voa para o painel A MESA PEDE.
const MESA_T := 1.9
var mesa_anim := -1.0             # segundos da animação (-1 = parada)
## R35.1 · rodada nova: primeiro as cartas são DISTRIBUÍDAS (voam do centro para cada jogador, uma a uma),
## depois a carta da MESA aparece. O tempo da vez e os bots esperam as duas.
const DEAL_T := 2.4                # R36: distribuição mais lenta (antes 1,8 s)
const DEAL_FLIGHT := 0.38         # cada carta leva 0,38 s do centro até o jogador
var deal_anim := -1.0
var deal_order: Array = []        # [{seat, slot}] na ordem em que as cartas saem
var mesa_round := -1
func _begin_turn():
    if g == null or mode != "game": return
    if g.round_no != mesa_round and g.state == Rules.TURN_WAITING:
        mesa_round = g.round_no
        _start_deal()
    selected = []
    input_locked = false
    turn_left_ms = TURN_MS
    bot_wait = -1.0
    if g.state != Rules.TURN_WAITING:
        _redraw()
        return
    if online:
        # o servidor decide a vez e o tempo; bots também rodam no servidor
        input_locked = g.turn != 0
        turn_left_ms = online_turn_ms if g.turn == 0 else TURN_MS
        if g.turn == 0: _cue("your_turn")
        last_tick_s = -1
        _redraw()
        return
    if g.turn != 0: bot_wait = rng.randf_range(BOT_DELAY_MIN, BOT_DELAY_MAX)
    else: _cue("your_turn")       # aviso sonoro: é a sua vez
    last_tick_s = -1
    _redraw()

var last_tick_s := -1
func _process(delta):
    if not visible: return
    t += delta
    if flash_t > 0.0:
        flash_t -= delta
        if flash_t <= 0.0: flash = ""
    for f in fly: f.t += delta * 1.1      # R36: cartas jogadas voam para a mesa sem pressa (~0,9 s)
    fly = fly.filter(func(f): return f.t < 1.0)
    # efeitos de tela
    shake_amp = maxf(0.0, shake_amp - delta * maxf(8.0, shake_amp * 2.2))
    flash_col.a = maxf(0.0, flash_col.a - delta * 1.6)
    for q in particles:
        q.life -= delta
        q.v.y += float(q.g) * delta
        q.v *= 1.0 - minf(0.9, delta * (2.5 if q.kind == "smoke" else 0.6))
        q.p += q.v * delta
        q.rot += float(q.spin) * delta
    particles = particles.filter(func(q): return q.life > 0.0)
    if not slam.is_empty():
        slam.t += delta
        if slam.t > 1.6: slam = {}
    if mode == "over":
        over_t += delta
        # R36 · fim de partida: chuva de confete (vitória) ou de cinzas (derrota) por alguns segundos
        if g != null and over_t < 7.0:
            var won: bool = g.winner == 0
            var rate := (90.0 if over_t < 2.5 else 35.0) if won else 22.0
            var n := int(rate * delta + fx_rng.randf())
            for i in n:
                var cols := [Color("ffd257"), Color("f3ead2"), Color("e3283a"), Color("35c27c"), Color("6fb4ee")] if won else [Color(0.35, 0.3, 0.28), Color(0.55, 0.2, 0.15), Color(0.2, 0.18, 0.17)]
                particles.append({"p": Vector2(fx_rng.randf_range(0, design.x), -30), "v": Vector2(fx_rng.randf_range(-60, 60), fx_rng.randf_range(180, 360) * (1.0 if won else 0.45)),
                    "life": 6.0, "max": 6.0, "col": cols[i % cols.size()], "size": fx_rng.randf_range(10, 20) if won else fx_rng.randf_range(5, 10),
                    "kind": "confetti" if won else "ash", "rot": fx_rng.randf_range(0, TAU), "spin": fx_rng.randf_range(-7, 7), "g": 40.0 if won else 10.0})
    if intro_anim >= 0.0:
        intro_anim += delta
        if intro_anim >= INTRO_T: intro_anim = -1.0
        _redraw()
        return
    if deal_anim >= 0.0:
        var before := deal_landed(0)
        deal_anim += delta
        if deal_landed(0) > before: _cue("card_1")
        if deal_anim >= DEAL_T:
            deal_anim = -1.0
            mesa_anim = 0.0
            _cue("reveal")
    elif mesa_anim >= 0.0:
        mesa_anim += delta
        if mesa_anim >= MESA_T: mesa_anim = -1.0
    if mode == "game" and g != null and not menu_open and not confirm_quit and mesa_anim < 0.0 and deal_anim < 0.0:
        if phase != "":
            phase_t += delta
            if phase_t >= PHASE_TIME[phase]: _advance_phase()
        elif g.state == Rules.TURN_WAITING:
            if g.turn == 0:
                if not input_locked:
                    turn_left_ms -= int(delta * 1000.0)
                    # últimos 5 segundos: tique a cada segundo
                    var secs := int(ceil(turn_left_ms / 1000.0))
                    if secs <= 5 and secs >= 1 and secs != last_tick_s:
                        last_tick_s = secs
                        _cue("tick")
                    if turn_left_ms <= 0:
                        turn_left_ms = 0
                        if not online: _timeout()     # online: o servidor joga 1 carta por você
            elif bot_wait >= 0.0:
                bot_wait -= delta
                if bot_wait < 0.0: _bot_act()
    _redraw()

func _start_deal():
    deal_order = []
    var counts := []
    for s in Rules.SEATS: counts.append(g.hands[s].size() if g.alive(s) else 0)
    var mx: int = counts.max()
    for k in mx:
        for i in Rules.SEATS:
            var s := (g.turn + i) % Rules.SEATS
            if k < counts[s]: deal_order.append({"seat": s, "slot": k})
    deal_anim = 0.0 if not deal_order.is_empty() else -1.0
    mesa_anim = -1.0
    if deal_anim < 0.0:
        mesa_anim = 0.0
        _cue("reveal")

## Saída da k-ésima carta da distribuição (segundos desde o início).
func deal_start(k: int) -> float:
    return float(k) * (DEAL_T - DEAL_FLIGHT) / maxf(1.0, deal_order.size() - 1)

## Quantas cartas do jogador `seat` já chegaram (a mão aparece carta a carta).
func deal_landed(seat: int) -> int:
    if deal_anim < 0.0: return 999
    var n := 0
    for k in deal_order.size():
        if int(deal_order[k].seat) == seat and deal_anim >= deal_start(k) + DEAL_FLIGHT: n += 1
    return n

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
    _cue("card_%d" % clampi(int(pub.count), 1, 3))
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
    if online:
        _online_send({"kind": "play", "idx": idx})
        return
    _after_play(0, g.play(0, idx))

func human_challenge():
    if not can_human_challenge(): return
    input_locked = true
    if online:
        _online_send({"kind": "challenge"})
        return
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
    get_tree().create_timer(FX_DELAY.flip).timeout.connect(func(): if phase == "reveal": _cue("flip"))
    phase_t = 0.0
    _cue("xeque_hit")
    # R36 · XEQUE! com impacto: tremor, clarão e o carimbo grande na tela
    fx_shake(FX_SHAKE.xeque)
    fx_flash(Color(1, 0.95, 0.85, 0.65))
    fx_slam("XEQUE!", ("DE " + String(g.names[caller]).to_upper()) if g != null and caller >= 0 and caller < g.names.size() else "", Color("ff4a3a"))
    get_tree().create_timer(FX_DELAY.voice_xeque).timeout.connect(func(): if phase == "reveal": _cue("voice_xeque"))
    last_tick_s = -1
    _redraw()

func _advance_phase():
    phase_t = 0.0
    match phase:
        "reveal":
            phase = "clock"
            _cue("clock_tension")
            fx_shake(FX_SHAKE.clock)
        "clock":
            phase = "mate" if bool(result.mate) else "safe"
            if bool(result.mate):
                # R36 · o relógio ESTOURA: clarão branco → vermelho, tremor forte, estilhaços, fumaça e onda de choque
                _cue("mate_boom")
                fx_shake(FX_SHAKE.mate)
                fx_flash(Color(1, 1, 1, 1.0))
                var mc: Vector2 = view.L().mate_clock[0] if view != null else design / 2.0
                fx_burst(mc, 90, [Color("2a2420"), Color("6b5a44"), Color("e8b242"), Color("ff5a3a"), Color("ffd257")], 1300.0, 10.0, 1100.0, "shard", 1.8)
                fx_burst(mc, 26, [Color(0.25, 0.22, 0.2, 0.7), Color(0.4, 0.33, 0.28, 0.6)], 420.0, 60.0, -60.0, "smoke", 2.2)
                fx_burst(mc, 40, [Color("fff1a8"), Color("ffb347")], 900.0, 5.0, 300.0, "spark", 0.9)
                get_tree().create_timer(FX_DELAY.voice_mate).timeout.connect(func(): if phase == "mate": _cue("voice_mate"))
                get_tree().create_timer(FX_DELAY.mate_red_flash).timeout.connect(func(): if phase == "mate": fx_flash(Color(1.0, 0.12, 0.06, 0.75)))
            else:
                _cue("relief")
                fx_flash(Color(0.45, 1.0, 0.6, 0.35))
                var cc: Vector2 = view.L().clock[0] if view != null else design / 2.0
                fx_burst(cc, 36, [Color("ffd257"), Color("fff1c2"), Color("7cf0a0")], 520.0, 6.0, 260.0, "spark", 1.1)
        "safe", "mate":
            if phase == "mate" and bool(result.get("eliminated", false)): _cue("elim")
            # com 1 vida o XEQUE-MATE já diz "eliminado": não precisa de outra tela
            if bool(result.get("eliminated", false)) and Rules.LIVES > 1: phase = "elim"
            else: _end_resolution()
        "elim":
            _end_resolution()
    _redraw()

func _end_resolution():
    phase = ""
    bubble = {}
    if online:
        _drain_events()               # rodada nova / fim chegam do servidor
        _redraw()
        return
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
    over_t = 0.0
    particles = []
    _cue("victory_final" if g.winner == 0 else "defeat_final")
    _redraw()

# ---------------------------------------------------------------- histórico comum
func _record_history(res: String) -> Dictionary:
    if g == null or recorded or started_unix <= 0: return {}
    var mh = stage.get("match_history") if stage != null else null
    if mh == null or not mh.has_method("add_entry"): return {}
    recorded = true
    var final := []
    for s in Rules.SEATS:
        final.append({"seat": s, "name": g.names[s], "lives": g.lives[s], "placement": g.placement(s), "eliminated_round": g.eliminated_round[s], "bot": (bool(players[s].get("bot", true)) if online and s < players.size() else s != 0)})
    var place := g.placement(0)
    if res == "abandon":
        place = g.alive_seats().size()      # sai no lugar em que estava
    return mh.add_entry({
        "mode_id": Rules.MODE_ID, "ruleset_version": Rules.RULESET_VERSION, "mode": "xeque", "online": online, "room_id": room_id,
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
    _hover_profile(int(id.substr(5)) if id.begins_with("seat_") and mode == "game" else -1)
    if id != hover_id:
        hover_id = id
        _redraw()

# ---------------------------------------------------------------- R37 · cartão de perfil
var _hover_seat := -1
func _popup():
    return stage.get("profile_popup") if stage != null else null

func _hover_profile(seat: int):
    var pp = _popup()
    if pp == null or seat == _hover_seat: return
    if _hover_seat >= 0: pp.unhover("xeque_seat_%d" % _hover_seat)
    _hover_seat = seat
    if seat >= 0: pp.hover("xeque_seat_%d" % seat, seat_info(seat), _seat_screen_rect(seat))

## Dados do jogador da placa `seat` para o cartão (você, bot ou amigo da mesa online).
func seat_info(seat: int) -> Dictionary:
    var acc = stage.get("account") if stage != null else null
    var nm: String = String(g.names[seat]) if g != null else String(SEAT_NAMES[seat])
    var info := {"name": nm, "mode": "xeque", "mode_label": "XEQUE", "avatar": avatars[seat] if seat < avatars.size() else null,
        "subtitle": "VOCÊ" if seat == 0 else ""}
    if online and seat < players.size():
        info.user_id = String(players[seat].get("user_id", ""))
        info.bot = bool(players[seat].get("bot", false))
        if not info.bot and seat != 0: info.subtitle = "AMIGO"
    elif seat == 0:
        info.user_id = String(acc.user_id) if acc != null and acc.has_profile() else ""
        info.bot = false
    else:
        info.bot = true
    return info

func _seat_screen_rect(seat: int) -> Rect2:
    for h in hits:
        if String(h.id) == "seat_%d" % seat:
            var r: Rect2 = h.rect
            return Rect2(origin + r.position * k, r.size * k)
    return Rect2()

func _popup_close():
    var pp = _popup()
    if pp != null: pp.close()
    _hover_seat = -1

func _on_hit(id: String):
    if id.begins_with("seat_"):
        var pp = _popup()
        var seat := int(id.substr(5))
        if pp != null: pp.toggle("xeque_seat_%d" % seat, seat_info(seat), _seat_screen_rect(seat))
        return
    if id.begins_with("card_"):
        toggle_card(int(id.substr(5)))
        return
    _cue("ui")
    match id:
        "play": human_play()
        "play_empty": _flash("Escolha de 1 a 3 cartas da sua mão.")
        "xeque": human_challenge()
        "mute_music": Sound.toggle_music(hub)
        "mute_fx": Sound.toggle_effects(hub)
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
        "quit_yes": quit_match()     # online: close() avisa o servidor (party_leave)
        "quit_no": confirm_quit = false
        "tut_back":
            if tutorial_from_game: _resume_from_tutorial()
            else: close()
        "tut_play", "again":
            if online and mode == "tutorial" and tutorial_from_game: _resume_from_tutorial()
            else: start_game()
        "tut_invite": invite_friend()
        "over_tutorial":
            tutorial_from_game = false
            mode = "tutorial"
        "over_menu": close()
    _redraw()

func _flash(text: String):
    flash = text
    flash_t = 3.0

var cues_played: Array = []      # testes: últimos efeitos pedidos
func _cue(kind: String):
    cues_played.append(kind)
    if cues_played.size() > 40: cues_played.pop_front()
    if SFX.has(kind):
        Sound.play(stage, SFX[kind], float(SFX_DB.get(kind, -8.0)))
        return
    var audio = stage.get_node_or_null("GameAudio") if stage != null else null
    if audio != null and audio.has_method("play_cue"): audio.play_cue("ui")

# ---------------------------------------------------------------- consultas para o desenho
## Etiqueta do lugar: "BOT" (contra bots) ou "AMIGO" (jogador humano na mesa online).
func seat_tag(seat: int) -> String:
    if online and seat > 0 and seat < players.size() and not bool(players[seat].get("bot", true)) and not bool(players[seat].get("left", false)): return "AMIGO"
    return "BOT"

func clock_visual(seat: int) -> String:
    if seat < 0 or g == null: return "neutro"
    if phase == "mate" and int(result.loser) == seat: return "disparado"
    if phase == "clock" and int(result.loser) == seat: return "pulsando"
    var left := g.clock_left(seat)
    if phase in ["reveal", "clock"] and int(result.get("loser", -1)) == seat:
        left = int(result.clock_left_before)
    # mesmo mapa da especificação do pacote: 0 apertos = neutro, 1–2 pulsando, 3 perigo, 4–5 quase
    return {6: "neutro", 5: "pulsando", 4: "pulsando", 3: "perigo", 2: "quase", 1: "quase"}.get(left, "neutro")

## De quem é o relógio mostrado no centro e no medidor. R37: fora do XEQUE é sempre o SEU relógio
## (antes seguia a vez e parecia "aleatório"); cada jogador tem o próprio relógio na placa dele.
func clock_focus() -> int:
    if g == null: return 0
    if phase != "" and not result.is_empty(): return int(result.loser)
    return 0

## Apertos que este jogador já sobreviveu no relógio atual (cada XEQUE perdido = 1 pauzinho).
## Durante a revelação/relógio do próprio jogador mostra o valor de ANTES (o motor já resolveu).
func clock_used(seat: int) -> int:
    if g == null or seat < 0: return 0
    if phase in ["reveal", "clock"] and int(result.get("loser", -1)) == seat:
        return Rules.CLOCK_SLOTS - int(result.clock_left_before)
    return Rules.CLOCK_SLOTS - g.clock_left(seat)

## Chance do próximo aperto deste jogador (o mesmo valor que o motor usa: Rules.CLOCK_CHANCES).
func clock_next_chance(seat: int) -> float:
    return float(Rules.CLOCK_CHANCES[clampi(clock_used(seat), 0, Rules.CLOCK_SLOTS - 1)])

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
    if g.clock_left(s) <= 2: return {"text": "EM RISCO", "id": "em_risco"}   # chance de 1/2 ou mais
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


# ================================================================ R35 · ONLINE COM AMIGO
var online_turn_ms := TURN_MS
## Mesa criada pelo servidor (convite aceito). Tudo já vem girado: você é o lugar 0 (embaixo).
## O espelho local (g) só guarda o que é PÚBLICO + a sua mão; as mãos dos outros e a ordem dos
## relógios nunca chegam aqui.
func start_online(msg: Dictionary):
    var resumed := bool(msg.get("resumed", false)) and online and room_id == String(msg.get("room_id", "")) and g != null
    online = true
    room_id = String(msg.get("room_id", ""))
    players = msg.get("players", []) if msg.get("players") is Array else []
    if not visible:
        visible = true
        root.visible = true
        Sound.music_on(stage, MUSIC)
        _load_avatars()
    menu_open = false
    confirm_quit = false
    tutorial_from_game = false
    ev_queue.clear()
    if not resumed:
        g = Rules.new()
        phase = ""
        result = {}
        bubble = {}
        fly = []
        recorded = false
        started_unix = int(Time.get_unix_time_from_system())
        started_ms = Time.get_ticks_msec()
        mesa_round = -1
        particles = []
        slam = {}
        if int(msg.get("snapshot", {}).get("round", 1)) <= 1: _start_intro()
    mode = "game"
    _apply_snapshot(msg.get("snapshot", {}))
    if bool(msg.get("ended", false)) or g.state == Rules.MATCH_END: _finish()
    else: _begin_turn()
    _relayout()

static func _ints(a) -> Array:
    var out := []
    if a is Array:
        for x in a: out.append(int(x))
    return out

func _apply_snapshot(snap: Dictionary):
    if g == null or snap.is_empty(): return
    g.state = String(snap.get("state", g.state))
    g.round_no = int(snap.get("round", g.round_no))
    g.target = String(snap.get("target", g.target))
    g.turn = int(snap.get("turn", -1))
    g.lives = _ints(snap.get("lives", [1, 1, 1, 1]))
    var counts := _ints(snap.get("hand_counts", [0, 0, 0, 0]))
    var clk := _ints(snap.get("clock_left", [6, 6, 6, 6]))
    g.hands = []
    g.clocks = []
    for s in Rules.SEATS:
        if s == 0: g.hands.append((snap.get("my_hand", []) as Array).map(func(c): return String(c)))
        else:
            var h := []
            for k in counts[s]: h.append("?")          # cartas dos outros: só a quantidade
            g.hands.append(h)
        var c := []
        for k in clk[s]: c.append(Rules.PENDING)       # níveis restantes (o sorteio é do servidor)
        g.clocks.append(c)
    var lp: Dictionary = snap.get("last_play", {})
    g.last_play = {} if lp.is_empty() else {"seat": int(lp.seat), "count": int(lp.count), "cards": []}
    g.plays = (snap.get("plays_this_round", []) as Array).map(func(p): return {"seat": int(p.seat), "count": int(p.count), "cards": []})
    g.reveals = (snap.get("reveals", []) as Array).map(func(r): return {"seat": int(r.seat), "cards": (r.cards as Array).map(func(c): return String(c)), "target": String(r.target), "truthful": bool(r.truthful), "round": int(r.get("round", 0))})
    g.winner = int(snap.get("winner", -1))
    g.eliminated_round = _ints(snap.get("eliminated_round", [-1, -1, -1, -1]))
    g.finish_order = _ints(snap.get("finish_order", []))
    g.next_starter = int(snap.get("next_starter", -1))
    g.public_log = (snap.get("public_log", []) as Array).map(func(x): return String(x))
    var nm: Array = snap.get("names", [])
    if nm.size() == Rules.SEATS:
        g.names = nm.map(func(x): return String(x))
        g.names[0] = SEAT_NAMES[0]
    if bool(snap.get("my_turn", false)): online_turn_ms = int(snap.get("turn_left_ms", TURN_MS))
    var conn: Array = snap.get("players_connected", [])
    for i in mini(conn.size(), players.size()): players[i]["connected"] = bool(conn[i])

static func _result(r: Dictionary) -> Dictionary:
    var o := r.duplicate(true)
    for key in ["caller", "accused", "loser", "winner", "next_starter", "clock_left_before", "lives_after", "round"]:
        if o.has(key): o[key] = int(o[key])
    for key in ["cards", "false_cards"]:
        if o.has(key): o[key] = (o[key] as Array).map(func(c): return String(c))
    return o

## Mensagens party_* do servidor (repassadas pelo stage).
func on_party_message(msg: Dictionary):
    if not online or String(msg.get("room_id", room_id)) != room_id: return
    match String(msg.get("type", "")):
        "party_event":
            ev_queue.append(msg)
            _drain_events()
        "party_error":
            if msg.has("snapshot"): _apply_snapshot(msg.snapshot)
            input_locked = g == null or g.turn != 0
            _flash(String(msg.get("message", "Ação recusada.")))
            _redraw()

## Aplica os eventos em ordem; durante a apresentação do XEQUE (revelar → relógio) os próximos esperam.
func _drain_events():
    while not ev_queue.is_empty() and online and phase == "":
        _run_event(ev_queue.pop_front())

func _run_event(msg: Dictionary):
    var snap: Dictionary = msg.get("snapshot", {})
    match String(msg.get("ev", "")):
        "play":
            var pub: Dictionary = msg.get("play", {})
            var seat := int(pub.get("seat", -1))
            var target_before := g.target
            _apply_snapshot(snap)
            input_locked = true
            selected = []
            bubble = {"seat": seat, "count": int(pub.get("count", 1)), "target": target_before}
            fly.append({"from": seat, "t": 0.0, "count": int(pub.get("count", 1))})
            _cue("card_%d" % clampi(int(pub.get("count", 1)), 1, 3))
            if String(msg.get("reason", "")) == "timeout" and seat == 0: _flash("Tempo esgotado: uma carta foi jogada por você.")
            if pub.has("forced") and pub.forced is Dictionary:
                var r := _result(pub.forced)
                _on_challenge(r, int(r.caller))
        "challenge":
            _apply_snapshot(snap)
            var r := _result(msg.get("result", {}))
            _on_challenge(r, int(r.get("caller", -1)))
        "round", "turn", "presence":
            _apply_snapshot(snap)
            _begin_turn()
        "left":
            _apply_snapshot(snap)
            var who := int(msg.get("who", -1))
            if who > 0 and who < players.size():
                players[who]["left"] = true
                _flash("%s saiu da partida — um bot joga no lugar." % g.names[who])
        "end":
            _apply_snapshot(snap)
            if mode == "game": _finish()
    _redraw()

func _online_send(action: Dictionary):
    var acc = stage.get("account") if stage != null else null
    if acc == null or not acc.has_method("send_server") or not acc.send_server({"type": "party_action", "room_id": room_id, "action": action}):
        input_locked = false
        _flash("Sem conexão com o servidor. Tente de novo.")
    _redraw()

func _online_leave():
    var acc = stage.get("account") if stage != null else null
    if acc != null and acc.has_method("send_server"): acc.send_server({"type": "party_leave", "room_id": room_id})
    online = false
    ev_queue.clear()

func online_lost(text: String):
    if not online: return
    online = false
    ev_queue.clear()
    if mode == "game":
        mode = "tutorial"
        g = null
        phase = ""
    _flash(text)
    _redraw()


## R35.1 · CONVIDAR (amigo) na tela inicial do XEQUE: lista de amigos já no convite do XEQUE.
func invite_friend():
    var social = stage.get("social_ui") if stage != null else null
    var acc = stage.get("account") if stage != null else null
    if acc == null or not acc.has_profile():
        _flash("Entre na sua conta para convidar amigos.")
        return
    if social != null and social.has_method("open_invite_picker"): social.open_invite_picker("xeque")
