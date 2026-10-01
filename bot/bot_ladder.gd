extends RefCounted
## Escada de bots por liga (Madeira → Challenger). Fonte única: res://bot/bot_ladder.json
## (o servidor Node lê o MESMO arquivo para validar vitórias e recompensas).
## Motor: Stockfish (instância role="bot", separada da análise). Cada nível = um PERFIL:
##   skill   → setoption Skill Level (0–20)
##   elo     → setoption UCI_LimitStrength true + UCI_Elo (1320–3190)
##   go      → limite por lance: depth | nodes | movetime
##   multipv + random_chance + error → camada de erro CONTROLADA (só níveis baixos):
##       random_chance: joga um lance legal qualquer;
##       error.chance:  joga um dos lances do MultiPV que perca no máximo error.max_loss cp.
##   think_ms → tempo mínimo exibido antes do lance (sensação de "pensar"; não muda a força).
##   fallback → dificuldade do motor interno (bot/search.gd) se o Stockfish não carregar.
const PATH := "res://bot/bot_ladder.json"
const ANALYSIS_NOTE := "A análise usa analysis/engine.gd role=analysis com depth/movetime próprios (analysis_ui.gd)."
static var _data: Dictionary = {}

static func data() -> Dictionary:
    if _data.is_empty():
        # .json é recurso do Godot (JSON) → entra no export sem mexer em export_presets.cfg.
        var parsed = null
        var res = load(PATH)
        if res is JSON: parsed = res.data
        if not (parsed is Dictionary): parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
        _data = parsed if parsed is Dictionary else {"bots": []}
    return _data

static func bots() -> Array:
    return data().get("bots", [])

static func ids() -> PackedStringArray:
    var out := PackedStringArray()
    for b in bots(): out.append(String(b.id))
    return out

static func index_of(id: String) -> int:
    return ids().find(id)

static func is_bot_id(id: String) -> bool:
    return index_of(id) >= 0

static func bot(id: String) -> Dictionary:
    for b in bots():
        if String(b.id) == id: return b
    return {}

## Opções UCI do perfil (sempre o conjunto completo: a instância pode ter jogado outro nível antes).
static func uci_options(id: String) -> Dictionary:
    var e: Dictionary = bot(id).get("engine", {})
    var opts := {"Hash": 16, "MultiPV": int(e.get("multipv", 1))}
    if e.has("elo"):
        opts["UCI_LimitStrength"] = "true"
        opts["UCI_Elo"] = clampi(int(e.elo), 1320, 3190)
        opts["Skill Level"] = 20
    else:
        opts["UCI_LimitStrength"] = "false"
        opts["Skill Level"] = clampi(int(e.get("skill", 20)), 0, 20)
    return opts

static func go_command(id: String) -> String:
    var g: Dictionary = bot(id).get("engine", {}).get("go", {})
    if g.has("depth"): return "go depth %d" % int(g.depth)
    if g.has("nodes"): return "go nodes %d" % int(g.nodes)
    return "go movetime %d" % int(g.get("movetime", 100))

## Camada de erro: a partir do resultado do Stockfish {bestmove, lines} escolhe o lance final.
## Devolve {"move": uci, "kind": "engine" | "suboptimal" | "random"}.
static func pick(id: String, result: Dictionary, legal_uci: PackedStringArray, rng: RandomNumberGenerator) -> Dictionary:
    var e: Dictionary = bot(id).get("engine", {})
    var best := String(result.get("bestmove", ""))
    var r := rng.randf()
    var rc := float(e.get("random_chance", 0.0))
    if rc > 0.0 and r < rc and not legal_uci.is_empty():
        return {"move": legal_uci[rng.randi_range(0, legal_uci.size() - 1)], "kind": "random"}
    var err: Dictionary = e.get("error", {})
    if not err.is_empty() and r < rc + float(err.get("chance", 0.0)):
        var lines: Dictionary = result.get("lines", {})
        if lines.has(1):
            var top: int = _score(lines[1])
            var pool: Array = []
            for k in lines:
                if int(k) == 1: continue
                var ln: Dictionary = lines[k]
                if String(ln.move) != best and top - _score(ln) <= int(err.get("max_loss", 100)): pool.append(String(ln.move))
            if not pool.is_empty(): return {"move": pool[rng.randi_range(0, pool.size() - 1)], "kind": "suboptimal"}
    return {"move": best, "kind": "engine"}

static func _score(line: Dictionary) -> int:
    var m := int(line.get("mate", 0))
    if m > 0: return 100000 - m
    if m < 0: return -100000 - m
    return int(line.get("cp", 0))

static func reward(id: String) -> Dictionary:
    return bot(id).get("reward", {})
