extends Node
## Histórico de análises (estrutura para estatísticas, relatório semanal e treinador no futuro).
## Local: user://analysis_history.json (últimas 50). Servidor: envia um resumo compacto
## (analysis_record) quando há conta — a tabela analysis_history (0005) guarda no banco.
const FILE := "user://analysis_history.json"
const MAX := 50
var entries: Array = []

func _ready():
    load_local()

func load_local():
    if not FileAccess.file_exists(FILE): return
    var txt := FileAccess.get_file_as_string(FILE)
    var data = JSON.parse_string(txt)
    if data is Array: entries = data

func save_local():
    var f := FileAccess.open(FILE, FileAccess.WRITE)
    if f != null: f.store_string(JSON.stringify(entries))

## Resumo compacto de uma análise concluída.
static func summarize(record, report: Dictionary) -> Dictionary:
    var human: String = String(report.get("human_color", "w"))
    var me: Dictionary = report.get("players", {}).get(human if human != "" else "w", {})
    var compact := []
    for m in report.get("moves", []):
        compact.append({"u": m.uci, "c": m.class, "l": snappedf(float(m.loss), 0.1), "b": m.best})
    return {
        "match_id": String(record.match_id), "mode": String(record.mode), "played_at": int(record.started_at),
        "analyzed_at": int(Time.get_unix_time_from_system()), "color": human, "result": String(record.result),
        "accuracy": snappedf(float(me.get("accuracy", 0.0)), 0.01), "counts": me.get("counts", {}),
        "critical_ply": int(me.get("critical", -1)), "best_ply": int(me.get("best_moment", -1)),
        "moves": compact, "engine": String(report.get("engine", "")), "depth": int(report.get("depth", 0)),
        "marked": Array(record.marked),
    }

func record(rec, report: Dictionary, account = null):
    if rec == null or report.is_empty(): return
    var s := summarize(rec, report)
    entries.push_front(s)
    if entries.size() > MAX: entries.resize(MAX)
    save_local()
    if account != null and account.has_profile() and account.server_ready:
        account.send_server({"type": "analysis_record", "summary": s})

## Padrões simples para o futuro "erros recorrentes": classes por fase (abertura/meio/final).
func recent(n := 10) -> Array:
    return entries.slice(0, n)
