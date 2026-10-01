extends Node
## Observa a partida em curso e registra os lances (UCI) num match_record — SEM engine.
## Funciona para bot, local, casual, ranked e amigo: deriva o lance de last_from/last_to e da
## peça resultante (promoção). Em reconexão (posição chega "pronta" com vários lances), o registro
## reinicia daquela posição (start_fen). Também guarda MARCAR PARA REVISAR.
const Record := preload("res://analysis/match_record.gd")
const Notation := preload("res://analysis/notation.gd")
const Rules := preload("res://chess/rules.gd")

var stage
var game
var record = null
var _prev_count := -1
var _prev_mode := ""
var _prev_board := {}
var _prev_turn := "w"

func setup(p_stage):
    stage = p_stage
    game = p_stage.game
    set_process(true)

## Começa um registro novo para a partida atual.
func begin(mode: String, human_color: String, player_name: String, opponent: String, match_id := ""):
    record = Record.new()
    record.start(mode, human_color, player_name, opponent, match_id)
    _prev_count = int(game.move_count)
    _prev_board = game.pieces.duplicate()
    _prev_turn = String(game.turn)
    if _prev_count > 0:
        # já começou no meio (reconexão): parte da posição atual
        record.start_fen = _fen_from_game()

func mark_for_review():
    if record != null and not record.finished: record.mark_current()

func finish(result: String, reason := ""):
    if record != null and not record.finished: record.finish(result, reason)

func current():
    return record

## FEN da posição atual. Só afirma roque/en passant quando o estado EXATO existe (regras do
## controlador: Casual/Ranked vêm do servidor; bot/local do motor local). Sem isso, o FEN é
## conservador: roque "-" e en passant "-" (nunca deduzidos pela posição — rei/torre podem ter
## ido e voltado) e o registro fica marcado como reconstruído/incompleto.
func _fen_from_game() -> String:
    var ctrl = game.bot
    if ctrl != null and ctrl.get("rules") != null:
        var r = ctrl.rules
        if r.board.size() == game.pieces.size() and String(r.turn) == String(game.turn):
            record.start_fen_approx = false
            return Notation.fen(r)
    var pos = Rules.new()
    pos.board = game.pieces.duplicate()
    pos.turn = String(game.turn)
    pos.rights = ""          # desconhecido → "-" no FEN
    pos.ep = Rules.EMPTY     # desconhecido → "-"
    pos.halfmove = 0
    pos.ply = int(game.move_count)
    record.start_fen_approx = true
    return Notation.fen(pos)

func _process(_d):
    if record == null or record.finished or game == null: return
    var count := int(game.move_count)
    if count == _prev_count + 1:
        var fr: Vector2i = game.last_from
        var to: Vector2i = game.last_to
        if fr != Vector2i(-1, -1) and to != Vector2i(-1, -1):
            var moved_before := String(_prev_board.get(fr, ""))
            var after := String(game.pieces.get(to, ""))
            var uci := Notation.square_name(fr) + Notation.square_name(to)
            if moved_before.ends_with("P") and after.length() == 2 and not after.ends_with("P") and to.y in [0, 7]:
                uci += after.substr(1, 1).to_lower()
            record.add_move(uci)
        _prev_count = count
        _prev_board = game.pieces.duplicate()
    elif count != _prev_count:
        # salto (reconexão/estado novo): reinicia o registro a partir da posição atual
        record.moves.clear()
        record.marked.clear()
        record.start_fen = _fen_from_game()
        _prev_count = count
        _prev_board = game.pieces.duplicate()
    if bool(game.game_over) and not record.finished:
        var human: String = record.human_color
        var status: String = String(game.status)
        var result := "draw"
        if "VITÓRIA" in status: result = "win"
        elif "DERROTA" in status: result = "loss"
        elif "MATE" in status:
            result = "loss" if String(game.turn) == human else "win"
        elif "VENC" in status:
            var winner := "w" if "BRANCAS" in status else "b"
            result = "win" if winner == human else "loss"
        if human == "": result = "draw" if "EMPATE" in status else ("w" if ("BRANCAS" in status) else "b")
        record.finish(result, status)
