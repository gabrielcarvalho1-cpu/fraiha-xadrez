extends Node
## R32 · HISTÓRICO DE PARTIDAS: toda partida de xadrez terminada (contra o computador, online casual,
## ranqueada, local e contra amigo) fica guardada NESTE aparelho com os lances, para rever a análise
## (se já foi analisada) ou analisar depois (usa a cota de análise; Club = ilimitado).
## user://match_history.json — últimas MAX partidas. Não é placar oficial: PL/Ranked continuam no servidor.
## Camada COMUM a todos os modos: cada registro tem mode_id (xadrez = "chess", "marcha_real", "xeque"…),
## ruleset_version e os dados próprios do modo (xadrez: "record" com os lances, para análise).
signal changed

const FILE := "user://match_history.json"
const MAX := 60
const Record := preload("res://analysis/match_record.gd")
const CHESS_MODE_ID := "chess"
const CHESS_RULESET := "chess-fide-1"

var entries: Array = []
var file := FILE

func _ready():
    load_local()

func load_local():
    entries = []
    if not FileAccess.file_exists(file): return
    var data = JSON.parse_string(FileAccess.get_file_as_string(file))
    if data is Array:
        for e in data:
            if not (e is Dictionary): continue
            # registros antigos (antes do mode_id) são todos de xadrez
            if not e.has("mode_id"): e["mode_id"] = CHESS_MODE_ID
            if not e.has("ruleset_version"): e["ruleset_version"] = CHESS_RULESET if e.mode_id == CHESS_MODE_ID else ""
            entries.append(e)

func save_local():
    var f := FileAccess.open(file, FileAccess.WRITE)
    if f != null: f.store_string(JSON.stringify(entries))

## Chamado quando o registrador termina uma partida (sinal match_recorder.finished).
func add(rec) -> Dictionary:
    if rec is Dictionary: rec = Record.from_dict(rec)
    if rec == null or not (rec is Object) or rec.get("moves") == null or rec.moves.is_empty(): return {}
    var e := {
        "mode_id": CHESS_MODE_ID, "ruleset_version": CHESS_RULESET,
        "mode": String(rec.mode), "opponent": String(rec.opponent_name), "player": String(rec.player_name),
        "result": String(rec.result), "reason": String(rec.result_reason), "color": String(rec.human_color),
        "started_at": int(rec.started_at), "finished_at": int(rec.finished_at), "plies": rec.moves.size(),
        "match_id": String(rec.match_id), "record": rec.to_dict(),
    }
    return _insert(e)

## Modos especiais (ex.: Marcha Real): o modo entrega o registro já montado.
## Obrigatórios: mode_id, ruleset_version, mode, result, started_at. Dados do modo vão em "data".
func add_entry(e: Dictionary) -> Dictionary:
    for k in ["mode_id", "ruleset_version", "mode", "result", "started_at"]:
        if not e.has(k) or str(e[k]).is_empty() or str(e[k]) == "0": return {}
    if String(e.mode_id) == CHESS_MODE_ID: return {}   # xadrez entra por add() (com os lances)
    return _insert(e.duplicate(true))

func _insert(e: Dictionary) -> Dictionary:
    # a mesma partida não entra duas vezes (fim reportado de novo após reconexão)
    for old in entries:
        if int(old.get("started_at", -1)) == int(e.started_at) and String(old.get("mode", "")) == String(e.mode) and String(old.get("mode_id", CHESS_MODE_ID)) == String(e.mode_id):
            return old
    entries.push_front(e)
    if entries.size() > MAX: entries.resize(MAX)
    save_local()
    changed.emit()
    return e

func record_of(e: Dictionary):
    if String(e.get("mode_id", CHESS_MODE_ID)) != CHESS_MODE_ID: return null
    var d = e.get("record")
    return Record.from_dict(d) if d is Dictionary else null

static func mode_name(mode: String) -> String:
    return {"bot": "Contra o computador", "casual": "Online casual", "ranked": "Ranqueada", "local": "Local", "friend": "Contra amigo", "marcha": "Marcha Real", "xeque": "Xeque"}.get(mode, mode)

static func result_name(result: String, mode: String) -> String:
    if mode == "local": return "PARTIDA LOCAL"
    return {"win": "VITÓRIA", "loss": "DERROTA", "draw": "EMPATE", "abandon": "ABANDONADA"}.get(result, "PARTIDA")
