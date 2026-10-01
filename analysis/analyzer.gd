extends Node
## Análise pós-partida FRAIHA: percorre a partida lance a lance, avalia cada posição com o
## motor (assíncrono, sem travar), classifica, calcula precisão e produz o relatório.
## Só roda em partidas TERMINADAS (ver fair_play.gd). Pode ser cancelada a qualquer momento.
signal progress(done: int, total: int, last_move: Dictionary)
signal finished(report: Dictionary)
signal cancelled

const Rules := preload("res://chess/rules.gd")
const Notation := preload("res://analysis/notation.gd")
const Config := preload("res://analysis/analysis_config.gd")
const Book := preload("res://analysis/opening_book.gd")
const Search := preload("res://bot/search.gd")

var engine                 # analysis/engine.gd
var depth := 14
var max_ms_per_pos := 1800
var running := false
var _cancel := false

func _init(p_engine):
    engine = p_engine

## Cada entrada de `report.moves`:
##   ply, uci, san, fen_before, fen_after, color, best (uci), best_san, pv (uci[]),
##   eval_before {cp,mate} / eval_after {cp,mate} (ponto de vista de quem jogou),
##   win_before, win_after, loss, class, mate_in, marked, signed_before/signed_after (para o gráfico)
func analyze(record) -> Dictionary:
    if running: return {}
    running = true
    _cancel = false
    var total: int = record.moves.size()
    var out := {"moves": [], "players": {}, "mode": record.mode, "human_color": record.human_color,
        "result": record.result, "engine": engine.engine_name, "depth": depth, "total": total}
    var pos = record.start_position()
    if pos == null:
        running = false
        return {}
    # Avaliação da posição inicial (para quem joga).
    var cur := await _eval(Notation.fen(pos))
    if _cancel:
        running = false
        cancelled.emit()
        return {}
    var seq: Array = []
    var prev_cp := 0
    for i in total:
        var uci := String(record.moves[i])
        var move := Notation.uci_to_move(uci)
        if move.is_empty(): break
        var color: String = pos.turn
        var fen_before := Notation.fen(pos)
        var san := Notation.san(pos, move)
        seq.append(uci)
        var in_book: bool = String(record.start_fen).is_empty() and Book.is_book(seq)
        # Melhor lance e 2º melhor (para "único") vêm da avaliação `cur` (feita na posição antes do lance).
        var best_uci := String(cur.get("bestmove", ""))
        var best_win := Config.win_percent(int(cur.get("cp", 0)), int(cur.get("mate", 0)))
        var best_was_mate := int(cur.get("mate", 0)) > 0
        var sacrificed := _sacrifice_cp(pos, move)
        var played_is_best := best_uci == uci or (best_uci.length() >= 4 and uci.begins_with(best_uci.substr(0, 4)) and best_uci.length() == 4)
        if not pos.play(move): break
        var fen_after := Notation.fen(pos)
        var after := {}
        var terminal: String = pos.outcome()
        if terminal == "mate":
            after = {"cp": 0, "mate": -1, "pv": [], "bestmove": "", "terminal": "mate"}   # quem ficou para jogar está em mate
        elif not terminal.is_empty():
            after = {"cp": 0, "mate": 0, "pv": [], "bestmove": "", "terminal": terminal}
        else:
            after = await _eval(fen_after)
        if _cancel:
            running = false
            cancelled.emit()
            return {}
        # `after` é do ponto de vista do ADVERSÁRIO (quem joga agora). Inverte para quem jogou.
        var played_cp := -int(after.get("cp", 0))
        var played_mate := -int(after.get("mate", 0))
        var played_win := Config.win_percent(played_cp, played_mate)
        var second_win := -1.0
        if played_is_best and i + 1 <= total:
            # Para "único": avalia a 2ª melhor opção pedindo o melhor lance EXCLUINDO o jogado.
            var alt := await _eval_excluding(fen_before, uci)
            if not alt.is_empty(): second_win = Config.win_percent(int(alt.get("cp", 0)), int(alt.get("mate", 0)))
            if _cancel:
                running = false
                cancelled.emit()
                return {}
        var played_mate_against := played_mate < 0
        var cls := Config.classify(best_win, played_win, second_win, in_book, sacrificed, played_is_best, played_mate_against, best_was_mate)
        var loss := maxf(0.0, best_win - played_win)
        if cls == "book" or played_is_best: loss = 0.0   # mesmo lance da engine: diferença é só ruído de profundidade
        if played_is_best: played_win = maxf(played_win, best_win)
        var best_san := ""
        if not best_uci.is_empty():
            var bpos = Notation.from_fen(fen_before)
            var bm := Notation.uci_to_move(best_uci)
            if bpos != null and not bm.is_empty() and bpos.piece(bm.from) != "": best_san = Notation.san(bpos, bm)
        var entry := {
            "ply": i, "uci": uci, "san": san, "color": color, "fen_before": fen_before, "fen_after": fen_after,
            "best": best_uci, "best_san": best_san, "pv": Array(cur.get("pv", [])).slice(0, 6),
            "eval_before": {"cp": int(cur.get("cp", 0)), "mate": int(cur.get("mate", 0))},
            "eval_after": {"cp": played_cp, "mate": played_mate},
            "win_before": best_win, "win_after": played_win, "loss": loss, "class": cls,
            "mate_in": played_mate, "marked": record.is_marked(i), "in_book": in_book,
            "signed_before": Config.signed_pawns(int(cur.get("cp", 0)), int(cur.get("mate", 0)), color),
            "signed_after": Config.signed_pawns(played_cp, played_mate, color),
            "text_before": Config.eval_text(int(cur.get("cp", 0)), int(cur.get("mate", 0)), color),
            "text_after": Config.eval_text(played_cp, played_mate, color),
        }
        out.moves.append(entry)
        progress.emit(i + 1, total, entry)
        cur = after
        prev_cp = played_cp
    _summarize(out)
    running = false
    finished.emit(out)
    return out

func cancel():
    _cancel = true
    if engine != null: engine.cancel()

func _eval(fen: String) -> Dictionary:
    var r: Dictionary = await engine.evaluate(fen, depth, max_ms_per_pos)
    if r.is_empty() and not _cancel: r = {"cp": 0, "mate": 0, "pv": [], "bestmove": ""}
    return r

## Melhor lance excluindo `uci`: só com motor UCI (searchmoves); no interno, pula (-1).
func _eval_excluding(fen: String, uci: String) -> Dictionary:
    if engine.transport == "builtin": return {}
    var pos = Notation.from_fen(fen)
    if pos == null: return {}
    var others := PackedStringArray()
    for m in pos.legal_moves():
        var u := Notation.uci_of(pos, m)
        if u != uci and u not in others: others.append(u)
    if others.is_empty(): return {}
    return await engine.evaluate_searchmoves(fen, mini(depth, 12), 900, others)

## Material entregue pelo lance (cp): peça movida para casa atacada sem recaptura compensadora,
## ou captura de peça menor por maior. Aproximação estática; a engine confirma pela avaliação.
static func _sacrifice_cp(pos, move: Dictionary) -> int:
    var code: String = pos.piece(move.from)
    if code.is_empty(): return 0
    var val := int(Search.PIECE_VALUES.get(code[1], 0))
    var captured: String = pos.piece(move.to)
    var cap_val := int(Search.PIECE_VALUES.get(captured[1], 0)) if not captured.is_empty() else 0
    var after = pos.copy_position()
    after.apply_unchecked({"from": move.from, "to": move.to, "promotion": move.get("promotion", "Q")}, false)
    var attacked: bool = after.attacked(move.to, after.turn)
    if not attacked: return 0
    var defended: bool = after.attacked(move.to, Rules.other(after.turn))
    var net := val - cap_val
    if defended: net = val - cap_val - _lowest_attacker_value(after, move.to)
    return maxi(0, net)

static func _lowest_attacker_value(pos, sq: Vector2i) -> int:
    var best := 900
    for fr in pos.board:
        var code: String = pos.board[fr]
        if code[0] != pos.turn: continue
        if sq in pos.pseudo(fr): best = mini(best, int(Search.PIECE_VALUES.get(code[1], 0)))
    return best if best < 900 else 0

func _summarize(out: Dictionary):
    for color in ["w", "b"]:
        var losses: Array = []
        var befores: Array = []
        var counts := {}
        for k in Config.LABELS: counts[k] = 0
        var best_moment := -1
        var best_gain := -1.0
        var critical := -1
        var worst := -1.0
        for e in out.moves:
            if e.color != color: continue
            losses.append(e.loss)
            befores.append(e.win_before)
            counts[e.class] += 1
            if e.class in ["legendary", "brilliant", "best", "excellent"]:
                var gain: float = e.win_after - 50.0
                if gain > best_gain and e.class != "best":
                    best_gain = gain
                    best_moment = e.ply
                elif best_moment < 0 and e.class == "best" and e.loss == 0.0 and gain > best_gain:
                    best_gain = gain
                    best_moment = e.ply
            if e.loss > worst:
                worst = e.loss
                critical = e.ply
        out.players[color] = {"accuracy": Config.accuracy(losses, befores), "counts": counts,
            "best_moment": best_moment, "critical": critical, "moves": losses.size()}
