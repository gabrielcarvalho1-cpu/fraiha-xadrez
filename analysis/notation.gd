extends RefCounted
## Conversões entre o modelo FRAIHA (Vector2i, y=0 = 8ª fileira) e notação padrão:
## FEN, lances UCI ("e2e4", "e7e8q") e SAN curto ("Cxe5", "O-O", "e8=D+") em português.
## Só leitura; nunca altera a posição recebida.
const Rules := preload("res://chess/rules.gd")
## Peças em português (padrão brasileiro): Rei, Dama, Torre, Bispo, Cavalo.
const PT := {"K": "R", "Q": "D", "R": "T", "B": "B", "N": "C", "P": ""}

static func square_name(p: Vector2i) -> String:
    return "%s%d" % ["abcdefgh"[p.x], 8 - p.y]

static func parse_square(s: String) -> Vector2i:
    if s.length() < 2: return Rules.EMPTY
    var x := "abcdefgh".find(s[0])
    var rank := int(s.substr(1, 1))
    if x < 0 or rank < 1 or rank > 8: return Rules.EMPTY
    return Vector2i(x, 8 - rank)

static func move_to_uci(move: Dictionary) -> String:
    var s := square_name(move.from) + square_name(move.to)
    if move.has("promo_applies") and move.promo_applies: s += String(move.get("promotion", "Q")).to_lower()
    return s

## "e7e8q" → {from,to,promotion}. A promoção só é relevante se a peça for peão chegando à última fileira.
static func uci_to_move(uci: String) -> Dictionary:
    if uci.length() < 4: return {}
    var fr := parse_square(uci.substr(0, 2))
    var to := parse_square(uci.substr(2, 2))
    if fr == Rules.EMPTY or to == Rules.EMPTY: return {}
    var promo := "Q"
    if uci.length() >= 5: promo = uci.substr(4, 1).to_upper()
    if promo not in ["Q", "R", "B", "N"]: promo = "Q"
    return {"from": fr, "to": to, "promotion": promo}

## UCI do lance JOGADO numa posição (acrescenta a promoção só quando há promoção).
static func uci_of(pos, move: Dictionary) -> String:
    var code: String = pos.piece(move.from)
    var s := square_name(move.from) + square_name(move.to)
    if code.length() == 2 and code[1] == "P" and move.to.y in [0, 7]: s += String(move.get("promotion", "Q")).to_lower()
    return s

static func fen(pos) -> String:
    var rows := PackedStringArray()
    for y in 8:
        var row := ""
        var empty := 0
        for x in 8:
            var code: String = pos.piece(Vector2i(x, y))
            if code.is_empty():
                empty += 1
            else:
                if empty > 0:
                    row += str(empty)
                    empty = 0
                row += code[1] if code[0] == "w" else code[1].to_lower()
        if empty > 0: row += str(empty)
        rows.append(row)
    var rights: String = pos.rights if not String(pos.rights).is_empty() else "-"
    var ep := "-"
    if pos.ep != Rules.EMPTY: ep = square_name(pos.ep)
    return "%s %s %s %s %d %d" % ["/".join(rows), pos.turn, rights, ep, int(pos.halfmove), int(pos.ply) / 2 + 1]

## Carrega um FEN numa posição Rules nova.
static func from_fen(text: String):
    var pos = Rules.new()
    var parts := text.strip_edges().split(" ")
    if parts.size() < 2: return null
    pos.board.clear()
    var y := 0
    for row in parts[0].split("/"):
        var x := 0
        for ch in row:
            if ch.is_valid_int():
                x += int(ch)
            else:
                var upper := ch.to_upper()
                if upper in ["K", "Q", "R", "B", "N", "P"] and x < 8 and y < 8:
                    pos.board[Vector2i(x, y)] = ("w" if ch == upper else "b") + upper
                x += 1
        y += 1
    pos.turn = "w" if parts[1] == "w" else "b"
    pos.rights = parts[2] if parts.size() > 2 and parts[2] != "-" else ""
    pos.ep = parse_square(parts[3]) if parts.size() > 3 and parts[3] != "-" else Rules.EMPTY
    pos.halfmove = int(parts[4]) if parts.size() > 4 else 0
    var fullmove := int(parts[5]) if parts.size() > 5 else 1
    pos.ply = (fullmove - 1) * 2 + (1 if pos.turn == "b" else 0)
    pos.repetitions = {pos.position_key(): 1}
    return pos

## SAN curto em português da jogada `move` na posição `pos` (antes do lance).
static func san(pos, move: Dictionary) -> String:
    var code: String = pos.piece(move.from)
    if code.is_empty(): return "?"
    var kind := code[1]
    var fr: Vector2i = move.from
    var to: Vector2i = move.to
    var out := ""
    if kind == "K" and absi(to.x - fr.x) == 2:
        out = "O-O" if to.x > fr.x else "O-O-O"
    else:
        var capture: bool = not pos.piece(to).is_empty() or (kind == "P" and to == pos.ep and fr.x != to.x)
        if kind == "P":
            if capture: out = "abcdefgh"[fr.x] + "x"
        else:
            out = PT[kind]
            # desambiguação: outra peça igual que também pode ir para `to`
            var others: Array = []
            for sq in pos.board:
                if sq == fr or pos.board[sq] != code: continue
                if to in pos.legal_from(sq): others.append(sq)
            if not others.is_empty():
                var same_file := others.any(func(o): return o.x == fr.x)
                var same_rank := others.any(func(o): return o.y == fr.y)
                if not same_file: out += "abcdefgh"[fr.x]
                elif not same_rank: out += str(8 - fr.y)
                else: out += square_name(fr)
            if capture: out += "x"
        out += square_name(to)
        if kind == "P" and to.y in [0, 7]: out += "=" + PT[String(move.get("promotion", "Q"))]
    var after = pos.copy_position()
    after.apply_unchecked({"from": fr, "to": to, "promotion": move.get("promotion", "Q")}, false)
    if after.in_check(after.turn):
        out += "#" if after.legal_moves().is_empty() else "+"
    return out
