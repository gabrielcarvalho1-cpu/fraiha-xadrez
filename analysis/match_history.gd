extends Node
## R32 · HISTÓRICO DE PARTIDAS: toda partida de xadrez terminada (contra o computador, online casual,
## ranqueada, local e contra amigo) fica guardada NESTE aparelho com os lances, para rever a análise
## (se já foi analisada) ou analisar depois (usa a cota de análise; Club = ilimitado).
## user://match_history.json — últimas MAX partidas. Não é placar oficial: PL/Ranked continuam no servidor.
signal changed

const FILE := "user://match_history.json"
const MAX := 60
const Record := preload("res://analysis/match_record.gd")

var entries: Array = []
var file := FILE

func _ready():
    load_local()

func load_local():
    entries = []
    if not FileAccess.file_exists(file): return
    var data = JSON.parse_string(FileAccess.get_file_as_string(file))
    if data is Array: entries = data

func save_local():
    var f := FileAccess.open(file, FileAccess.WRITE)
    if f != null: f.store_string(JSON.stringify(entries))

## Chamado quando o registrador termina uma partida (sinal match_recorder.finished).
func add(rec) -> Dictionary:
    if rec is Dictionary: rec = Record.from_dict(rec)
    if rec == null or not (rec is Object) or rec.get("moves") == null or rec.moves.is_empty(): return {}
    var e := {
        "mode": String(rec.mode), "opponent": String(rec.opponent_name), "player": String(rec.player_name),
        "result": String(rec.result), "reason": String(rec.result_reason), "color": String(rec.human_color),
        "started_at": int(rec.started_at), "finished_at": int(rec.finished_at), "plies": rec.moves.size(),
        "match_id": String(rec.match_id), "record": rec.to_dict(),
    }
    # a mesma partida não entra duas vezes (fim reportado de novo após reconexão)
    for old in entries:
        if int(old.get("started_at", -1)) == e.started_at and String(old.get("mode", "")) == e.mode:
            return old
    entries.push_front(e)
    if entries.size() > MAX: entries.resize(MAX)
    save_local()
    changed.emit()
    return e

func record_of(e: Dictionary):
    var d = e.get("record")
    return Record.from_dict(d) if d is Dictionary else null

static func mode_name(mode: String) -> String:
    return {"bot": "Contra o computador", "casual": "Online casual", "ranked": "Ranqueada", "local": "Local", "friend": "Contra amigo"}.get(mode, mode)

static func result_name(result: String, mode: String) -> String:
    if mode == "local": return "PARTIDA LOCAL"
    return {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE"}.get(result, "PARTIDA")
