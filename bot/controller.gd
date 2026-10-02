extends Node
## Bridges the isolated rules/search to the existing World presentation.
## Scene nodes are only read/written on the main thread.
const Rules = preload("res://chess/rules.gd")
const Search = preload("res://bot/search.gd")
const Ladder = preload("res://bot/bot_ladder.gd")
const Notation = preload("res://analysis/notation.gd")
const EngineScript = preload("res://analysis/engine.gd")
var game
var rules = Rules.new()
var active := false
var local_mode := false
var paused := false
var difficulty := "easy"
var human_color := "w"
var thinking := false
var epoch := 0
var job_epoch := -1
var worker: Thread
var search
var completed := {}
var promotion_choices: Array = []
var think_delay := 0.0
var last_search_metrics := {}
var coop_search          # busca cooperativa em andamento (sem threads)
var _threads_ok := true
# Bots por liga (Stockfish). bot_id vazio = níveis antigos (fácil/médio/…) no motor interno.
var bot_id := ""
var sf_engine                   # analysis/engine.gd role="bot" (instância própria, nunca a da análise)
var engine_mode := ""           # "STOCKFISH" | "FALLBACK"
var guard: Callable             # fair play (definido pelo stage)
var move_log: Array = []        # [{ms, kind}] para medição/QA
var _sf_job := -1
var _rng := RandomNumberGenerator.new()

func start(world: Node, level: String, side: String):
    stop()
    game = world
    local_mode = false
    bot_id = level if Ladder.is_bot_id(level) else ""
    difficulty = Search.normalize_difficulty(String(Ladder.bot(bot_id).get("fallback", "easy")) if not bot_id.is_empty() else level)
    move_log.clear()
    _rng.randomize()
    engine_mode = ""
    if not bot_id.is_empty(): _prepare_stockfish(epoch + 1)
    human_color = ("w" if randi()%2 == 0 else "b") if side == "random" else side
    if human_color not in ["w","b"]: human_color = "w"
    game.online = null
    game.bot = self
    active = true
    restart()

func start_local(world: Node):
    start(world,"easy","w")
    local_mode = true
    thinking = false
    _sync_view()

func restart():
    if not active: return
    epoch += 1
    if coop_search != null:
        coop_search.abort()
        coop_search = null
    completed.clear()
    promotion_choices.clear()
    rules.reset()
    game.particles.clear()
    game.captured_white.clear()
    game.captured_black.clear()
    game.clear_last_move()
    game.flash = 0.0
    game.settings_open = false
    game.game_started = true
    paused = false
    thinking = not local_mode and rules.turn != human_color
    think_delay = 0.25
    _sync_view()

func stop():
    epoch += 1
    active = false
    paused = false
    thinking = false
    completed.clear()
    promotion_choices.clear()
    if is_instance_valid(game) and game.bot == self:
        game.bot = null
        game.promotion_pending = false
        game.cancel_drag()
    if coop_search != null:
        coop_search.abort()
        coop_search = null
    if sf_engine != null and _sf_job >= 0: sf_engine.cancel()
    _sf_job = -1
    # In-flight work is invalidated, never synchronously awaited on navigation.
    # The bounded worker is collected by _process when it finishes.

func set_paused(value: bool):
    paused = value
    if value and is_instance_valid(game): game.cancel_drag()

func can_interact() -> bool:
    return active and not paused and not thinking and not game.settings_open and not game.game_over and (local_mode or rules.turn == human_color)

func legal_from(cell: Vector2i) -> Array[Vector2i]:
    var moves: Array[Vector2i] = []
    if can_interact(): moves.assign(rules.legal_from(cell))
    return moves

func request_move(from: Vector2i, to: Vector2i) -> bool:
    if not can_interact() or not promotion_choices.is_empty(): return false
    var candidates: Array = []
    for move in rules.legal_moves():
        if move.from == from and move.to == to: candidates.append(move)
    if candidates.is_empty(): return false
    # Multiple legal choices for the same route come from the engine's promotion
    # expansion; the UI does not reimplement pawn or promotion rules.
    if candidates.size() > 1:
        promotion_choices = candidates
        game.promotion_pending = true
        game.promotion_color = rules.turn
        game.promotion_cell = to
        game.selected = Vector2i(-1,-1)
        game.legal_moves.clear()
        game.cancel_drag()
        game.queue_redraw()
        return true
    return _apply(candidates[0])

func promote(kind: String) -> bool:
    if not can_interact(): return false
    for move in promotion_choices:
        if move.promotion == kind:
            promotion_choices.clear()
            return _apply(move)
    return false

func _apply(move: Dictionary) -> bool:
    if not active or game.game_over: return false
    var before: Dictionary = rules.board.duplicate()
    var moving_color: String = rules.turn
    if not rules.play(move): return false
    # Removed enemy sprites are derived from the authoritative engine result,
    # which also accounts for en passant, castling and promotions.
    for square in before:
        var code: String = before[square]
        if code[0] != moving_color and rules.piece(square) != code:
            if code[0] == "w": game.captured_white.append(code)
            else: game.captured_black.append(code)
            game._spawn_capture(game.square_center(square), code)
    thinking = not local_mode and rules.turn != human_color
    think_delay = 0.25
    _sync_view()
    # Apresentação: anima o lance (o bot e, na partida local, os dois lados recebem o destaque forte).
    game.show_move(before, move.from, move.to, local_mode or moving_color != human_color)
    return true

func _sync_view():
    game.pieces = rules.board.duplicate()
    game.turn = rules.turn
    game.move_count = rules.ply
    game.selected = Vector2i(-1,-1)
    game.legal_moves.clear()
    game.cancel_drag()
    game.promotion_pending = false
    game.promotion_cell = Vector2i(-1,-1)
    var result: String = rules.outcome()
    game.game_over = not result.is_empty()
    if game.game_over:
        thinking = false
        match result:
            "mate": game.status = "XEQUE-MATE! " + ("BRANCAS VENCEM" if rules.turn == "b" else "PRETAS VENCEM")
            "stalemate": game.status = "EMPATE — AFOGAMENTO"
            "material": game.status = "EMPATE — MATERIAL INSUFICIENTE"
            "fifty_moves": game.status = "EMPATE — REGRA DOS 50 LANCES"
            "repetition": game.status = "EMPATE — REPETIÇÃO"
    elif local_mode:
        game.status = ("XEQUE! " if rules.in_check(rules.turn) else "") + ("BRANCAS JOGAM" if rules.turn == "w" else "PRETAS JOGAM")
    elif thinking:
        game.status = "%s PENSANDO…" % (String(Ladder.bot(bot_id).get("name", "BOT")) if not bot_id.is_empty() else "BOT " + Search.difficulty_label(difficulty))
    else:
        game.status = ("XEQUE! " if rules.in_check(human_color) else "") + "SUA VEZ · " + ("BRANCAS" if human_color == "w" else "PRETAS")
    game.queue_redraw()

func _process(delta: float):
    if worker != null and worker.is_started() and not worker.is_alive():
        var result = worker.wait_to_finish()
        worker = null
        if active and job_epoch == epoch and result is Dictionary:
            completed = result
            last_search_metrics = search.last_metrics.duplicate()
        search = null
    if not active or local_mode or paused or game.settings_open or game.game_over: return
    if rules.turn == human_color: return
    think_delay = maxf(0.0, think_delay-delta)
    if think_delay > 0: return
    if not completed.is_empty():
        var move = completed.duplicate()
        completed.clear()
        # A worker never mutates the live position. Revalidate before display.
        if not _apply(move):
            push_error("Bot returned a move rejected by the rules engine")
        return
    if worker != null or coop_search != null or _sf_job == epoch: return
    if not bot_id.is_empty() and engine_mode == "": return   # Stockfish ainda carregando
    thinking = true
    job_epoch = epoch
    if engine_mode == "STOCKFISH":
        _run_stockfish(epoch)
        return
    var snapshot = rules.copy_position()
    var settings := Search.profile(difficulty)
    if not threads_available():
        _run_cooperative(snapshot, int(settings.budget_ms), int(settings.max_depth))
        return
    search = Search.new()
    worker = Thread.new()
    var err = worker.start(search.choose.bind(snapshot,difficulty,int(settings.budget_ms),int(settings.max_depth)))
    if err != OK or not worker.is_started():
        # Sem thread (ex.: Web exportada sem suporte a threads): busca fatiada no próprio quadro.
        worker = null
        search = null
        _threads_ok = false
        _run_cooperative(snapshot, int(settings.budget_ms), int(settings.max_depth))

## Web sem SharedArrayBuffer/threads não consegue iniciar Thread: a busca roda em fatias
## curtas entre quadros (a tela, a música e os cliques continuam respondendo).
func threads_available() -> bool:
    if not _threads_ok: return false
    if OS.has_feature("web") and not OS.has_feature("threads"): return false
    return true

func _run_cooperative(snapshot, budget_ms: int, max_depth: int):
    var job := Search.new()
    coop_search = job
    var my_epoch := job_epoch
    var result = await job.choose_async(snapshot, difficulty, budget_ms, max_depth)
    if coop_search == job: coop_search = null
    if active and my_epoch == epoch and job_epoch == my_epoch and result is Dictionary:
        completed = result
        last_search_metrics = job.last_metrics.duplicate()

# ---------------------------------------------------------------- Stockfish (bots por liga)
func _ensure_engine():
    if sf_engine != null: return
    sf_engine = EngineScript.new("bot")
    sf_engine.name = "BotEngine"
    sf_engine.allow_builtin = false
    sf_engine.guard = func() -> bool: return guard.is_valid() and bool(guard.call())
    add_child(sf_engine)

func _prepare_stockfish(for_epoch: int):
    _ensure_engine()
    await sf_engine.start()
    var ok: bool = sf_engine.engine_ready and sf_engine.transport != "builtin"
    if ok: ok = await sf_engine.configure(Ladder.uci_options(bot_id))
    if epoch != for_epoch and active: return
    engine_mode = "STOCKFISH" if ok else "FALLBACK"
    print("BOT ENGINE = %s · %s · %s" % [engine_mode, bot_id, ("%s %s" % [JSON.stringify(Ladder.uci_options(bot_id)), Ladder.go_command(bot_id)]) if ok else "motor interno (%s)" % difficulty])

func _run_stockfish(my_epoch: int):
    _sf_job = my_epoch
    var t0 := Time.get_ticks_msec()
    var snapshot = rules.copy_position()
    var legal := PackedStringArray()
    var by_uci := {}
    for m in snapshot.legal_moves():
        var u: String = Notation.uci_of(snapshot, m)
        legal.append(u)
        by_uci[u] = m
    var result: Dictionary = await sf_engine.search_move(Notation.fen(snapshot), Ladder.go_command(bot_id))
    if not active or epoch != my_epoch:
        if _sf_job == my_epoch: _sf_job = -1
        return
    var choice := Ladder.pick(bot_id, result, legal, _rng) if not result.is_empty() else {}
    var move: Dictionary = by_uci.get(String(choice.get("move", "")), {})
    if move.is_empty():
        # Stockfish não respondeu (ou lance inesperado): esta partida segue no motor interno.
        if _sf_job == my_epoch: _sf_job = -1
        engine_mode = "FALLBACK"
        print("BOT ENGINE = FALLBACK · %s · Stockfish não respondeu" % bot_id)
        return
    var wait_ms := int(Ladder.bot(bot_id).get("think_ms", 0)) - (Time.get_ticks_msec() - t0)
    if wait_ms > 0: await get_tree().create_timer(wait_ms / 1000.0).timeout
    if _sf_job == my_epoch: _sf_job = -1   # só libera depois de entregar o lance (evita 2ª busca no mesmo turno)
    if not active or epoch != my_epoch: return
    move_log.append({"ms": int(result.get("ms", 0)), "kind": String(choice.kind)})
    print("BOT MOVE · %s · %s · %s · engine %d ms · total %d ms" % [bot_id, String(choice.move), String(choice.kind), int(result.get("ms", 0)), Time.get_ticks_msec() - t0])
    last_search_metrics = {"engine": "stockfish", "bot": bot_id, "ms": int(result.get("ms", 0)), "kind": String(choice.kind)}
    completed = move

func _exit_tree():
    stop()
    if worker != null and worker.is_started():
        worker.wait_to_finish()
    worker = null
    search = null
