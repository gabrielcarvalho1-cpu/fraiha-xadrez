extends Node
## Histórico de análises — base do CLUB FRAIHA (estatísticas, relatório semanal, histórico detalhado,
## treinos e desafios; ver analysis/club_insights.gd).
## Local: user://analysis_history.json (últimas 50, resumos). R31: o relatório COMPLETO das últimas
## REPORTS_MAX análises fica em user://analysis_reports/<arquivo>.json para REVER a análise e treinar
## os erros depois. Servidor: envia um resumo compacto (analysis_record) quando há conta — a tabela
## analysis_history (0005) guarda no banco.
signal changed

const FILE := "user://analysis_history.json"
const REPORTS_DIR := "user://analysis_reports/"
const REPORTS_MAX := 20
const MAX := 50
const MISTAKES := ["blunder", "missed", "mistake", "inaccuracy"]
var entries: Array = []
var file := FILE
var reports_dir := REPORTS_DIR

func _ready():
    load_local()

func load_local():
    if not FileAccess.file_exists(file): return
    var txt := FileAccess.get_file_as_string(file)
    var data = JSON.parse_string(txt)
    if data is Array: entries = data

func save_local():
    var f := FileAccess.open(file, FileAccess.WRITE)
    if f != null: f.store_string(JSON.stringify(entries))

## Fase do jogo de uma posição (FEN): abertura (até o 10º lance), final (pouco material) ou meio-jogo.
static func phase_of(ply: int, fen: String) -> String:
    var board := fen.get_slice(" ", 0)
    var heavy := 0
    for ch in board:
        if ch in ["q", "r", "b", "n", "Q", "R", "B", "N"]: heavy += 1
    if heavy <= 6: return "end"
    if ply < 20: return "opening"
    return "middle"

## Resumo compacto de uma análise concluída.
static func summarize(record, report: Dictionary) -> Dictionary:
    var human: String = String(report.get("human_color", "w"))
    var me: Dictionary = report.get("players", {}).get(human if human != "" else "w", {})
    var compact := []
    var phases := {"opening": 0, "middle": 0, "end": 0}
    for m in report.get("moves", []):
        compact.append({"u": m.uci, "c": m.class, "l": snappedf(float(m.loss), 0.1), "b": m.best})
        if (human == "" or String(m.get("color", "")) == human) and String(m.class) in MISTAKES:
            phases[phase_of(int(m.get("ply", 0)), String(m.get("fen_before", "")))] += 1
    return {
        "match_id": String(record.match_id), "mode": String(record.mode), "played_at": int(record.started_at),
        "analyzed_at": int(Time.get_unix_time_from_system()), "color": human, "result": String(record.result),
        "accuracy": snappedf(float(me.get("accuracy", 0.0)), 0.01), "counts": me.get("counts", {}),
        "critical_ply": int(me.get("critical", -1)), "best_ply": int(me.get("best_moment", -1)),
        "moves": compact, "engine": String(report.get("engine", "")), "depth": int(report.get("depth", 0)),
        "marked": Array(record.marked), "phases": phases, "opponent": String(record.opponent_name),
        "plies": int(record.moves.size()),
    }

func record(rec, report: Dictionary, account = null):
    if rec == null or report.is_empty(): return
    var s := summarize(rec, report)
    s["report_file"] = _store_report(rec, report, s)
    entries.push_front(s)
    if entries.size() > MAX: entries.resize(MAX)
    _prune_reports()
    save_local()
    changed.emit()
    if account != null and account.has_profile() and account.server_ready:
        var sent := s.duplicate()
        sent.erase("report_file")
        account.send_server({"type": "analysis_record", "summary": sent})

func _store_report(rec, report: Dictionary, s: Dictionary) -> String:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(reports_dir) if reports_dir.begins_with("user://") else reports_dir)
    var name := "%d_%d.json" % [int(s.analyzed_at), randi() % 100000]
    var f := FileAccess.open(reports_dir + name, FileAccess.WRITE)
    if f == null: return ""
    f.store_string(JSON.stringify({"record": rec.to_dict(), "report": report}))
    return name

## Só os REPORTS_MAX mais recentes guardam o relatório completo (o resumo continua no histórico).
func _prune_reports():
    var kept := 0
    for e in entries:
        var fname := String(e.get("report_file", ""))
        if fname.is_empty(): continue
        kept += 1
        if kept > REPORTS_MAX:
            DirAccess.remove_absolute(reports_dir + fname)
            e.erase("report_file")

func has_report(e: Dictionary) -> bool:
    var fname := String(e.get("report_file", ""))
    return not fname.is_empty() and FileAccess.file_exists(reports_dir + fname)

## {record, report} completos de uma entrada (ou {} se não houver).
func load_report(e: Dictionary) -> Dictionary:
    if not has_report(e): return {}
    var data = JSON.parse_string(FileAccess.get_file_as_string(reports_dir + String(e.report_file)))
    if not (data is Dictionary) or not (data.get("report") is Dictionary): return {}
    return {"record": preload("res://analysis/match_record.gd").from_dict(data.get("record", {})), "report": _fix_types(data.report)}

## JSON devolve números como float: o relatório usa ply/mate inteiros como índice.
static func _fix_types(rep: Dictionary) -> Dictionary:
    for m in rep.get("moves", []):
        for key in ["ply", "mate_in"]:
            if m.has(key): m[key] = int(m[key])
    return rep

## Erros do jogador nas análises guardadas, para o TREINE MEUS ERROS do Club.
## phase "" = todas. Devolve movimentos do relatório (com fen_before, best, win_*…) + "move_no".
func mistakes(limit := 10, phase := "") -> Array:
    var out: Array = []
    for e in entries:
        if out.size() >= limit: break
        var full := load_report(e)
        if full.is_empty(): continue
        var rep: Dictionary = full.report
        var human := String(rep.get("human_color", "w"))
        var per := 0
        for cls in MISTAKES:
            for m in rep.get("moves", []):
                if out.size() >= limit or per >= 3: break
                if String(m.class) != cls or (human != "" and String(m.color) != human): continue
                if not phase.is_empty() and phase_of(int(m.ply), String(m.fen_before)) != phase: continue
                var x: Dictionary = m.duplicate(true)
                x["move_no"] = int(m.ply) / 2 + 1
                x["source"] = String(e.get("opponent", ""))
                out.append(x)
                per += 1
    return out

func recent(n := 10) -> Array:
    return entries.slice(0, n)
