extends RefCounted
## Registro de uma partida para análise posterior: lista de lances (UCI) a partir da posição
## inicial, quem é o humano, modo, resultado e as posições "MARCAR PARA REVISAR".
## NUNCA chama engine: só guarda dados. A engine entra depois que a partida termina.
const Rules := preload("res://chess/rules.gd")
const Notation := preload("res://analysis/notation.gd")

var mode := ""              # "bot" | "casual" | "ranked" | "local" | "friend"
var human_color := "w"      # lado do jogador ("" em partida local)
var opponent_name := ""
var player_name := ""
var moves: Array = []       # UCI por lance ("e2e4")
var marked: Array = []      # plies marcados para revisar (índice do lance, 0 = primeiro lance)
var result := ""            # "win" | "loss" | "draw" | "" (do ponto de vista do humano)
var result_reason := ""
var started_at := 0
var finished_at := 0
var match_id := ""
var finished := false
var start_fen := ""         # "" = posição inicial; senão a partida registrada começa deste FEN (reconexão)

func start(p_mode: String, p_human: String, p_player: String, p_opponent: String, p_match_id := ""):
    mode = p_mode
    human_color = p_human
    player_name = p_player
    opponent_name = p_opponent
    match_id = p_match_id
    moves.clear()
    marked.clear()
    result = ""
    result_reason = ""
    finished = false
    started_at = int(Time.get_unix_time_from_system())
    finished_at = 0

## Sincroniza com o histórico de lances conhecido (lista UCI). Nunca remove lances já jogados.
func sync_moves(uci_list: Array):
    if uci_list.size() >= moves.size(): moves = uci_list.duplicate()

func add_move(uci: String):
    moves.append(uci)

## MARCAR PARA REVISAR: só guarda o índice do lance atual (sem engine, sem avaliação).
func mark_current():
    var idx := moves.size() - 1
    if idx >= 0 and idx not in marked: marked.append(idx)

func is_marked(idx: int) -> bool:
    return idx in marked

func finish(p_result: String, p_reason := ""):
    result = p_result
    result_reason = p_reason
    finished = true
    finished_at = int(Time.get_unix_time_from_system())

func ply_count() -> int:
    return moves.size()

## Posição de partida do registro (inicial ou start_fen).
func start_position():
    if start_fen.is_empty():
        var pos = Rules.new()
        pos.reset()
        return pos
    return Notation.from_fen(start_fen)

## Reconstrói a posição após `n` lances (0 = inicial). Devolve null se algum lance for inválido.
func position_after(n: int):
    var pos = start_position()
    if pos == null: return null
    for i in mini(n, moves.size()):
        var m := Notation.uci_to_move(String(moves[i]))
        if m.is_empty() or not pos.play(m): return null
    return pos

func to_dict() -> Dictionary:
    return {"mode": mode, "human_color": human_color, "player_name": player_name, "opponent_name": opponent_name,
        "moves": moves.duplicate(), "marked": marked.duplicate(), "result": result, "result_reason": result_reason,
        "started_at": started_at, "finished_at": finished_at, "match_id": match_id, "finished": finished, "start_fen": start_fen}

static func from_dict(d: Dictionary):
    var r = new()
    r.mode = String(d.get("mode", ""))
    r.human_color = String(d.get("human_color", "w"))
    r.player_name = String(d.get("player_name", ""))
    r.opponent_name = String(d.get("opponent_name", ""))
    r.moves = Array(d.get("moves", []))
    r.marked = Array(d.get("marked", []))
    r.result = String(d.get("result", ""))
    r.result_reason = String(d.get("result_reason", ""))
    r.started_at = int(d.get("started_at", 0))
    r.finished_at = int(d.get("finished_at", 0))
    r.match_id = String(d.get("match_id", ""))
    r.finished = bool(d.get("finished", false))
    r.start_fen = String(d.get("start_fen", ""))
    return r
