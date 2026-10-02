extends RefCounted
## CLUB FRAIHA — números REAIS a partir do histórico de análises (analysis_history.entries).
## Só leitura e cálculo: estatísticas avançadas, relatório semanal e desafios Club da semana.
## Nada aqui mexe em PL, Ranked ou resultado (análise é sempre pós-partida).
const MISTAKES := ["blunder", "missed", "mistake", "inaccuracy"]
const PHASE_NAMES := {"opening": "Abertura", "middle": "Meio-jogo", "end": "Final"}
const MODE_NAMES := {"bot": "Contra o computador", "casual": "Online casual", "ranked": "Ranqueado", "local": "Local", "friend": "Contra amigo"}
const PROGRESS_FILE := "user://club_progress.cfg"
const WEEK := 604800
## Segunda-feira 00:00 UTC de referência (05/01/1970 era segunda).
const MONDAY0 := 345600

static func when(e: Dictionary) -> int:
    var p := int(e.get("played_at", 0))
    return p if p > 0 else int(e.get("analyzed_at", 0))

static func week_key(t: int) -> int:
    return int(floor(float(t - MONDAY0) / WEEK))

static func week_start(t: int) -> int:
    return MONDAY0 + week_key(t) * WEEK

static func mistakes_of(e: Dictionary) -> int:
    var n := 0
    var c: Dictionary = e.get("counts", {})
    for k in MISTAKES: n += int(c.get(k, 0))
    return n

static func _avg(vals: Array) -> float:
    if vals.is_empty(): return 0.0
    var s := 0.0
    for v in vals: s += float(v)
    return s / vals.size()

## Estatísticas avançadas.
static func stats(entries: Array) -> Dictionary:
    var out := {"games": entries.size(), "wins": 0, "losses": 0, "draws": 0, "accuracy": 0.0, "best_accuracy": 0.0,
        "by_mode": {}, "by_color": {"w": {"games": 0, "accuracy": 0.0}, "b": {"games": 0, "accuracy": 0.0}},
        "phases": {"opening": 0, "middle": 0, "end": 0}, "per_game": {}, "trend": 0.0, "streak": 0,
        "weakest_phase": "", "strongest_phase": ""}
    if entries.is_empty(): return out
    var accs: Array = []
    var by_mode := {}
    var by_color := {"w": [], "b": []}
    var totals := {}
    for k in MISTAKES: totals[k] = 0
    totals["best"] = 0
    totals["brilliant"] = 0
    for e in entries:
        var acc := float(e.get("accuracy", 0.0))
        accs.append(acc)
        out.best_accuracy = maxf(out.best_accuracy, acc)
        match String(e.get("result", "")):
            "win": out.wins += 1
            "loss": out.losses += 1
            "draw": out.draws += 1
        var mode := String(e.get("mode", ""))
        if not by_mode.has(mode): by_mode[mode] = {"games": 0, "acc": [], "wins": 0}
        by_mode[mode].games += 1
        by_mode[mode].acc.append(acc)
        if String(e.get("result", "")) == "win": by_mode[mode].wins += 1
        var col := String(e.get("color", ""))
        if by_color.has(col): by_color[col].append(acc)
        var ph: Dictionary = e.get("phases", {})
        for p in out.phases: out.phases[p] += int(ph.get(p, 0))
        var c: Dictionary = e.get("counts", {})
        for k in totals: totals[k] += int(c.get(k, 0)) + (int(c.get("legendary", 0)) if k == "brilliant" else 0)
    out.accuracy = _avg(accs)
    for m in by_mode: out.by_mode[m] = {"games": by_mode[m].games, "accuracy": _avg(by_mode[m].acc), "wins": by_mode[m].wins}
    for col in ["w", "b"]: out.by_color[col] = {"games": by_color[col].size(), "accuracy": _avg(by_color[col])}
    for k in totals: out.per_game[k] = float(totals[k]) / entries.size()
    # tendência: média das 5 mais recentes − média das 5 anteriores (entries[0] = mais recente)
    if entries.size() >= 4:
        var half := mini(5, entries.size() / 2)
        out.trend = _avg(accs.slice(0, half)) - _avg(accs.slice(half, half * 2))
    for e in entries:
        if String(e.get("result", "")) != "win": break
        out.streak += 1
    var has_phase := false
    for p in out.phases:
        if int(out.phases[p]) > 0: has_phase = true
    if has_phase:
        var worst := ""
        var best := ""
        for p in ["opening", "middle", "end"]:
            if worst.is_empty() or out.phases[p] > out.phases[worst]: worst = p
            if best.is_empty() or out.phases[p] < out.phases[best]: best = p
        out.weakest_phase = worst
        out.strongest_phase = best
    return out

## Relatório da semana (segunda a domingo, UTC) comparado com a semana anterior.
static func weekly(entries: Array, now: int) -> Dictionary:
    var start := week_start(now)
    var this_week: Array = []
    var last_week: Array = []
    var days := [0, 0, 0, 0, 0, 0, 0]
    for e in entries:
        var t := when(e)
        if t >= start and t < start + WEEK:
            this_week.append(e)
            days[clampi(int((t - start) / 86400), 0, 6)] += 1
        elif t >= start - WEEK and t < start:
            last_week.append(e)
    var s := stats(this_week)
    var prev := stats(last_week)
    var mistakes := 0
    for e in this_week: mistakes += mistakes_of(e)
    return {"start": start, "games": this_week.size(), "wins": s.wins, "losses": s.losses, "draws": s.draws,
        "accuracy": s.accuracy, "prev_accuracy": prev.accuracy, "prev_games": last_week.size(), "days": days,
        "mistakes": mistakes, "focus_phase": s.weakest_phase, "training": mini(10, mistakes)}

# ---------------------------------------------------------------- desafios Club (semanais)
static func trained_this_week(now: int, path := PROGRESS_FILE) -> int:
    var cfg := ConfigFile.new()
    if cfg.load(path) != OK: return 0
    return int(cfg.get_value("training", str(week_key(now)), 0))

## Chamado pelo treino: +n posições resolvidas nesta semana.
static func add_training_solved(n := 1, now := -1, path := PROGRESS_FILE):
    if now < 0: now = int(Time.get_unix_time_from_system())
    var cfg := ConfigFile.new()
    cfg.load(path)
    var key := str(week_key(now))
    cfg.set_value("training", key, int(cfg.get_value("training", key, 0)) + n)
    cfg.save(path)

## Desafios da semana, acompanhados automaticamente: [{id, title, desc, progress, goal, done}].
static func challenges(entries: Array, now: int, trained := -1) -> Array:
    var start := week_start(now)
    var week: Array = []
    for e in entries:
        var t := when(e)
        if t >= start and t < start + WEEK: week.append(e)
    var high := 0
    var clean := 0
    var wins := 0
    for e in week:
        if float(e.get("accuracy", 0.0)) >= 80.0: high += 1
        if int(e.get("counts", {}).get("blunder", 0)) == 0 and int(e.get("plies", 30)) >= 20: clean += 1
        if String(e.get("result", "")) == "win": wins += 1
    if trained < 0: trained = trained_this_week(now)
    var list := [
        {"id": "analyst", "title": "ANALISTA DA SEMANA", "desc": "Analise 3 partidas.", "progress": week.size(), "goal": 3},
        {"id": "precision", "title": "PRECISÃO DE MESTRE", "desc": "Termine uma partida analisada com 80% de precisão ou mais.", "progress": high, "goal": 1},
        {"id": "clean", "title": "SEM ERROS GRAVES", "desc": "Uma partida (20+ lances) sem nenhum erro grave.", "progress": clean, "goal": 1},
        {"id": "win", "title": "VITÓRIA ESTUDADA", "desc": "Analise 2 vitórias suas.", "progress": wins, "goal": 2},
        {"id": "training", "title": "TREINO EM DIA", "desc": "Resolva 5 posições no Treine Meus Erros.", "progress": trained, "goal": 5},
    ]
    for c in list:
        c.progress = mini(int(c.progress), int(c.goal))
        c["done"] = int(c.progress) >= int(c.goal)
    return list
