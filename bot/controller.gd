extends Node
## Bridges the isolated rules/search to the existing World presentation.
## Scene nodes are only read/written on the main thread.
const Rules = preload("res://chess/rules.gd")
const Search = preload("res://bot/search.gd")
var game
var rules = Rules.new()
var active := false
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

func start(world: Node, level: String, side: String):
    stop()
    game = world
    difficulty = Search.normalize_difficulty(level)
    human_color = ("w" if randi()%2 == 0 else "b") if side == "random" else side
    if human_color not in ["w","b"]: human_color = "w"
    game.online = null
    game.bot = self
    active = true
    restart()

func restart():
    if not active: return
    epoch += 1
    completed.clear()
    promotion_choices.clear()
    rules.reset()
    game.particles.clear()
    game.captured_white.clear()
    game.captured_black.clear()
    game.last_from = Vector2i(-1,-1)
    game.last_to = Vector2i(-1,-1)
    game.flash = 0.0
    game.settings_open = false
    game.game_started = true
    paused = false
    thinking = rules.turn != human_color
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
    # In-flight work is invalidated, never synchronously awaited on navigation.
    # The bounded worker is collected by _process when it finishes.

func set_paused(value: bool):
    paused = value
    if value and is_instance_valid(game): game.cancel_drag()

func can_interact() -> bool:
    return active and not paused and not thinking and not game.settings_open and not game.game_over and rules.turn == human_color

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
        game.promotion_color = human_color
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
    game.last_from = move.from
    game.last_to = move.to
    thinking = rules.turn != human_color
    think_delay = 0.25
    _sync_view()
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
    elif thinking:
        game.status = "BOT %s PENSANDO…" % Search.difficulty_label(difficulty)
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
    if not active or paused or game.settings_open or game.game_over: return
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
    if worker != null: return
    thinking = true
    job_epoch = epoch
    search = Search.new()
    worker = Thread.new()
    var snapshot = rules.copy_position()
    var settings := Search.profile(difficulty)
    var err = worker.start(search.choose.bind(snapshot,difficulty,int(settings.budget_ms),int(settings.max_depth)))
    if err != OK:
        worker = null
        # Easy selection is a legal fallback if the operating system cannot
        # start a worker. This path never runs a minimax search on the UI thread.
        completed = Search.new().choose(snapshot,"easy",10,1)

func _exit_tree():
    stop()
    if worker != null and worker.is_started():
        worker.wait_to_finish()
    worker = null
    search = null
