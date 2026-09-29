extends Node
## Adaptador do World para Ranked: mesma interface do controlador do Bot.
## O cliente só PEDE jogadas; posição, relógio e resultado vêm do servidor.
signal queued(msg: Dictionary)
signal cancelled
signal found(msg: Dictionary)
signal state_changed
signal finished(msg: Dictionary)
signal problem(text: String)
const Rules = preload("res://chess/rules.gd")
const ClockState = preload("res://ranked/clock_state.gd")
var account
var game
var rules = Rules.new()
var clock = ClockState.new()
var match_id := ""
var mode := ""
var mode_name := ""
var human_color := "w"
var status := ""
var white: Dictionary = {}
var black: Dictionary = {}
var searching := false
var pending := false
var paused := false
var active := false
var starts_in_ms := 0
var state_at := 0
var promotion_choices: Array = []
var last_result: Dictionary = {}
var opponent: Dictionary = {}

func setup(service, world):
    account = service
    game = world
    account.server_message.connect(_on_message)

func queue(which: String):
    if searching or in_match(): return
    last_result = {}
    if not account.send_server({"type": "ranked_queue", "mode": which}):
        problem.emit("Sem conexão com o servidor. Tente novamente.")

func cancel_queue():
    account.send_server({"type": "ranked_cancel"})
    searching = false
    cancelled.emit()

func resign():
    if in_match(): account.send_server({"type": "ranked_resign", "match_id": match_id})

func in_match() -> bool:
    return not match_id.is_empty() and status != "finished"

func attach():
    game.online = null
    game.bot = self
    active = true
    game.game_started = true
    game.settings_open = false
    game.particles.clear()
    game.captured_white.clear()
    game.captured_black.clear()

func detach():
    active = false
    if is_instance_valid(game) and game.bot == self:
        game.bot = null
        game.promotion_pending = false
        game.cancel_drag()

# ----- Interface usada pelo World (igual ao Bot) -----
func restart(): pass
func stop(): detach()
func set_paused(value: bool): paused = value

func can_interact() -> bool:
    return active and not paused and not pending and status == "playing" and rules.turn == human_color and not game.game_over and not game.settings_open

func legal_from(cell: Vector2i) -> Array[Vector2i]:
    var moves: Array[Vector2i] = []
    if can_interact(): moves.assign(rules.legal_from(cell))
    return moves

func request_move(from: Vector2i, to: Vector2i) -> bool:
    if not can_interact(): return false
    var candidates: Array = []
    for move in rules.legal_moves():
        if move.from == from and move.to == to: candidates.append(move)
    if candidates.is_empty(): return false
    if candidates.size() > 1:
        promotion_choices = candidates
        game.promotion_pending = true
        game.promotion_color = human_color
        game.promotion_cell = to
        game.selected = Vector2i(-1, -1)
        game.legal_moves.clear()
        game.cancel_drag()
        game.queue_redraw()
        return true
    return _send_move(candidates[0])

func promote(kind: String) -> bool:
    for move in promotion_choices:
        if move.promotion == kind:
            promotion_choices.clear()
            game.promotion_pending = false
            return _send_move(move)
    return false

func _send_move(move: Dictionary) -> bool:
    pending = true
    game.selected = Vector2i(-1, -1)
    game.legal_moves.clear()
    return account.send_server({"type": "ranked_move", "match_id": match_id, "from": [move.from.x, move.from.y],
        "to": [move.to.x, move.to.y], "promotion": move.promotion})

# ----- Mensagens do servidor -----
func _on_message(msg: Dictionary):
    var type = String(msg.get("type", ""))
    match type:
        "ranked_queued":
            searching = true
            queued.emit(msg)
        "ranked_cancelled":
            searching = false
        "ranked_found":
            searching = false
            match_id = String(msg.match_id)
            mode = String(msg.mode)
            mode_name = String(msg.get("mode_name", ""))
            human_color = String(msg.you)
            opponent = msg.get("opponent", {}) if msg.get("opponent") is Dictionary else {}
            status = "starting"
            found.emit(msg)
        "ranked_state":
            if String(msg.get("match_id", "")) == match_id: _apply_state(msg)
        "ranked_result":
            if String(msg.get("match_id", "")) == match_id:
                status = "finished"
                last_result = msg
                game.game_over = true
                game.status = {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}.get(String(msg.get("outcome", "")), "FIM DE JOGO")
                game.queue_redraw()
                finished.emit(msg)
        "ranked_error":
            pending = false
            if String(msg.get("code", "")) != "move_rejected": problem.emit(String(msg.get("message", "")))
        "link_lost":
            pending = false
            if in_match(): problem.emit("Conexão perdida. Reconectando — o relógio oficial continua no servidor.")
            searching = false
        "acct_error":
            if String(msg.get("code", "")) == "auth_required": problem.emit(String(msg.get("message", "")))

func _apply_state(msg: Dictionary):
    pending = false
    status = String(msg.status)
    white = msg.white
    black = msg.black
    starts_in_ms = int(msg.get("starts_in_ms", 0))
    state_at = Time.get_ticks_msec()
    clock.apply_snapshot(msg.clock)
    var p: Dictionary = msg.position
    rules.board.clear()
    for item in p.board: rules.board[Vector2i(int(item[0]), int(item[1]))] = String(item[2])
    rules.turn = String(p.turn)
    rules.rights = String(p.rights)
    rules.ep = Vector2i(int(p.ep[0]), int(p.ep[1]))
    rules.halfmove = int(p.halfmove)
    rules.ply = int(p.ply)
    if not active: return
    var last = msg.get("last_move")
    # Efeito de captura só para o lance novo (não ao reconectar).
    if last is Dictionary and rules.ply == game.move_count + 1:
        var captured = String(last.get("captured", ""))
        if not captured.is_empty():
            if captured[0] == "w": game.captured_white.append(captured)
            else: game.captured_black.append(captured)
            game._spawn_capture(game.square_center(Vector2i(int(last.to[0]), int(last.to[1]))), captured)
    if last is Dictionary:
        game.last_from = Vector2i(int(last.from[0]), int(last.from[1]))
        game.last_to = Vector2i(int(last.to[0]), int(last.to[1]))
    game.pieces = rules.board.duplicate()
    game.turn = rules.turn
    game.move_count = rules.ply
    game.promotion_pending = not promotion_choices.is_empty()
    if promotion_choices.is_empty(): game.promotion_cell = Vector2i(-1, -1)
    game.cancel_drag()
    game.game_over = status == "finished"
    if status == "starting": game.status = "A PARTIDA VAI COMEÇAR"
    elif status == "playing":
        var check = "XEQUE! " if bool(msg.get("in_check", false)) else ""
        game.status = check + ("SUA VEZ" if rules.turn == human_color else "VEZ DO ADVERSÁRIO")
    game.queue_redraw()
    state_changed.emit()

func player(color: String) -> Dictionary:
    return white if color == "w" else black
