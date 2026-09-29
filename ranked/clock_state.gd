extends RefCounted
## Lógica do relógio no cliente: guarda o último valor OFICIAL do servidor e só
## interpola para exibição. Nunca decide tempo esgotado (quem decide é o servidor).
var white_ms := 0
var black_ms := 0
var active := ""
var received_at := 0

func apply_snapshot(snapshot: Dictionary):
    white_ms = int(snapshot.get("w_ms", 0))
    black_ms = int(snapshot.get("b_ms", 0))
    active = String(snapshot.get("active", ""))
    received_at = Time.get_ticks_msec()

func remaining_ms(color: String) -> int:
    var base = white_ms if color == "w" else black_ms
    if color == active: base -= Time.get_ticks_msec() - received_at
    return maxi(0, base)

static func format(ms: int) -> String:
    var total = int(ceil(ms / 1000.0))
    return "%02d:%02d" % [total / 60, total % 60]
