extends Node
## Motor de análise do FRAIHA — cliente UCI assíncrono com três transportes:
##   • "process": Stockfish nativo (Windows/Linux/macOS) via OS.execute_with_pipe, se o
##     executável existir em user://engines/ (ver analysis/ENGINE.md). GPLv3: distribuído
##     separado, com licença e fonte indicados em analysis/LICENSES.md.
##   • "web": Stockfish 19 Lite WASM (stockfish.js, GPLv3) num Web Worker, via JavaScriptBridge.
##   • "builtin": busca própria do FRAIHA (bot/search.gd) — sempre disponível, mais fraca.
## A interface nunca fala com o transporte: usa evaluate(fen, depth) e recebe {cp|mate, pv, bestmove}.
## FAIR PLAY: este nó só é usado DEPOIS da partida (analyzer/training). Nada aqui roda durante
## partida humana ativa — ver analysis/fair_play.gd.
signal ready_changed(engine_ready: bool)

const Notation := preload("res://analysis/notation.gd")
const Search := preload("res://bot/search.gd")
const ENGINE_DIR := "user://engines"

var transport := ""          # "process" | "web" | "builtin"
var engine_name := ""
var engine_ready := false
var _proc: Dictionary = {}   # execute_with_pipe
var _lines: Array = []
var _web_cb: JavaScriptObject
var _web_id := 0
var _buffer := ""
var _busy := false
var _cancel := false
var _builtin: RefCounted

func _ready():
    set_process(false)

# ---------------------------------------------------------------- inicialização
## Tenta o melhor transporte disponível. Retorna o nome do motor.
func start() -> String:
    if engine_ready: return engine_name
    if OS.has_feature("web"):
        if await _start_web(): return engine_name
    else:
        var exe := _find_native()
        if not exe.is_empty() and await _start_process(exe): return engine_name
    _start_builtin()
    return engine_name

func _find_native() -> String:
    var names := ["stockfish.exe", "stockfish"] if OS.get_name() == "Windows" else ["stockfish"]
    for dir in [ENGINE_DIR, "user://"]:
        for n in names:
            var p: String = dir.path_join(n)
            if FileAccess.file_exists(p): return ProjectSettings.globalize_path(p)
    var env := OS.get_environment("FRAIHA_STOCKFISH")
    if not env.is_empty() and FileAccess.file_exists(env): return env
    return ""

func _start_process(exe: String) -> bool:
    _proc = OS.execute_with_pipe(exe, [], false)
    if _proc.is_empty() or not _proc.has("stdio"): return false
    transport = "process"
    _send("uci")
    var ok := await _wait_for("uciok", 4.0)
    if not ok:
        stop()
        return false
    engine_name = "Stockfish (nativo)"
    for l in _lines:
        if String(l).begins_with("id name "): engine_name = String(l).substr(8)
    _send("setoption name Threads value %d" % clampi(OS.get_processor_count() / 2, 1, 4))
    _send("setoption name Hash value 64")
    _send("isready")
    await _wait_for("readyok", 4.0)
    engine_ready = true
    ready_changed.emit(true)
    return true

func _start_web() -> bool:
    if _web_cb == null:
        _web_cb = JavaScriptBridge.create_callback(_on_web_line)
        JavaScriptBridge.get_interface("window").fraihaEngineCb = _web_cb
    var started = JavaScriptBridge.eval("""
    (() => {
        try {
            if (window.fraihaEngine) return true;
            const w = new Worker('engines/stockfish-19-lite-single.js');
            w.onmessage = (e) => { window.fraihaEngineCb([String(e.data)]); };
            w.onerror = (e) => { window.fraihaEngineCb(['__error ' + (e.message || 'worker')]); };
            window.fraihaEngine = w;
            return true;
        } catch (e) { return false; }
    })()
    """)
    if started != true: return false
    transport = "web"
    _send("uci")
    var ok := await _wait_for("uciok", 15.0)
    if not ok:
        stop()
        return false
    engine_name = "Stockfish 19 Lite (WASM)"
    _send("isready")
    await _wait_for("readyok", 10.0)
    engine_ready = true
    ready_changed.emit(true)
    return true

func _start_builtin():
    transport = "builtin"
    engine_name = "Motor FRAIHA (interno)"
    _builtin = Search.new()
    engine_ready = true
    ready_changed.emit(true)

func stop():
    if transport == "process" and not _proc.is_empty():
        _send("quit")
        OS.kill(int(_proc.get("pid", 0)))
        _proc = {}
    elif transport == "web":
        JavaScriptBridge.eval("if (window.fraihaEngine) { window.fraihaEngine.terminate(); window.fraihaEngine = null; }")
    engine_ready = false
    transport = ""
    _lines.clear()
    ready_changed.emit(false)

func _exit_tree():
    if engine_ready: stop()

# ---------------------------------------------------------------- transporte
func _send(cmd: String):
    match transport:
        "process":
            var f: FileAccess = _proc.get("stdio")
            if f != null:
                f.store_line(cmd)
                f.flush()
        "web":
            JavaScriptBridge.eval("window.fraihaEngine && window.fraihaEngine.postMessage(%s)" % JSON.stringify(cmd))

func _on_web_line(args: Array):
    if args.is_empty(): return
    _lines.append(String(args[0]))

func _pump():
    if transport != "process": return
    var f: FileAccess = _proc.get("stdio")
    if f == null: return
    while f.get_length() > 0:
        var chunk := f.get_buffer(mini(f.get_length(), 65536)).get_string_from_utf8()
        if chunk.is_empty(): break
        _buffer += chunk
    var nl := _buffer.find("\n")
    while nl >= 0:
        _lines.append(_buffer.substr(0, nl).strip_edges())
        _buffer = _buffer.substr(nl + 1)
        nl = _buffer.find("\n")

func _wait_for(token: String, timeout: float) -> bool:
    var end := Time.get_ticks_msec() + int(timeout * 1000.0)
    while Time.get_ticks_msec() < end:
        _pump()
        for l in _lines:
            if String(l).begins_with(token): return true
        await get_tree().process_frame
    return false

# ---------------------------------------------------------------- avaliação
## Avalia um FEN até `depth`. Resultado (do ponto de vista de quem joga, como no UCI):
## {"cp": int, "mate": int(0 = não), "bestmove": "e2e4", "pv": ["e2e4", ...], "depth": int}
## Vazio se cancelado. Nunca trava a interface: aguarda quadro a quadro.
func evaluate(fen: String, depth: int, max_ms := 4000) -> Dictionary:
    if not engine_ready: await start()
    if not engine_ready: return {}
    while _busy: await get_tree().process_frame
    _busy = true
    _cancel = false
    var result := {}
    if transport == "builtin":
        result = await _evaluate_builtin(fen, depth, max_ms)
    else:
        _lines.clear()
        _send("position fen " + fen)
        _send("go depth %d movetime %d" % [depth, max_ms])
        var last := {}
        var end := Time.get_ticks_msec() + max_ms + 3000
        while Time.get_ticks_msec() < end:
            _pump()
            var done := false
            for l in _lines:
                var s := String(l)
                if s.begins_with("info ") and " pv " in s and " score " in s:
                    last = _parse_info(s)
                elif s.begins_with("bestmove"):
                    var parts := s.split(" ")
                    last["bestmove"] = parts[1] if parts.size() > 1 else ""
                    done = true
                elif s.begins_with("__error"):
                    done = true
            _lines.clear()
            if done or _cancel:
                if _cancel and not done:
                    _send("stop")
                    await _wait_for("bestmove", 2.0)
                    _lines.clear()
                break
            await get_tree().process_frame
        if not _cancel and not last.is_empty():
            if not last.has("bestmove") and last.has("pv") and not last.pv.is_empty(): last["bestmove"] = last.pv[0]
            result = last
    _busy = false
    return result

## Igual a evaluate(), mas restrito a `moves` (UCI "searchmoves"). Só nos transportes UCI.
func evaluate_searchmoves(fen: String, depth: int, max_ms: int, moves: PackedStringArray) -> Dictionary:
    if transport == "builtin" or not engine_ready or moves.is_empty(): return {}
    while _busy: await get_tree().process_frame
    _busy = true
    _lines.clear()
    _send("position fen " + fen)
    _send("go depth %d movetime %d searchmoves %s" % [depth, max_ms, " ".join(moves)])
    var last := {}
    var end := Time.get_ticks_msec() + max_ms + 3000
    while Time.get_ticks_msec() < end:
        _pump()
        var done := false
        for l in _lines:
            var s := String(l)
            if s.begins_with("info ") and " pv " in s and " score " in s: last = _parse_info(s)
            elif s.begins_with("bestmove") or s.begins_with("__error"): done = true
        _lines.clear()
        if done or _cancel:
            if _cancel and not done:
                _send("stop")
                await _wait_for("bestmove", 2.0)
                _lines.clear()
            break
        await get_tree().process_frame
    _busy = false
    return {} if _cancel else last

func cancel():
    _cancel = true
    if _builtin != null and _builtin.has_method("abort"): _builtin.abort()

static func _parse_info(line: String) -> Dictionary:
    var out := {"cp": 0, "mate": 0, "pv": [], "depth": 0}
    var parts := line.split(" ")
    var i := 0
    while i < parts.size():
        match parts[i]:
            "depth": out.depth = int(parts[i + 1]); i += 1
            "score":
                if parts[i + 1] == "cp": out.cp = int(parts[i + 2])
                elif parts[i + 1] == "mate": out.mate = int(parts[i + 2])
                i += 2
            "pv":
                out.pv = Array(parts.slice(i + 1))
                i = parts.size()
        i += 1
    return out

## Motor interno: usa a busca do bot (síncrona em thread no desktop; fatiada na Web).
func _evaluate_builtin(fen: String, depth: int, max_ms: int) -> Dictionary:
    var pos = Notation.from_fen(fen)
    if pos == null: return {}
    var outcome: String = pos.outcome()
    if outcome == "mate": return {"cp": 0, "mate": -1, "pv": [], "depth": 0, "bestmove": "", "terminal": "mate"}   # quem joga está em mate
    if not outcome.is_empty(): return {"cp": 0, "mate": 0, "pv": [], "depth": 0, "bestmove": "", "terminal": outcome}
    if _builtin == null or _builtin._abort: _builtin = Search.new()   # depois de cancelar, busca nova
    var search: RefCounted = _builtin
    var move: Dictionary
    if OS.has_feature("web") or not OS.has_feature("threads"):
        move = await search.choose_async(pos, "expert", max_ms, mini(depth, 8))
    else:
        var th := Thread.new()
        th.start(func(): return search.choose(pos, "expert", max_ms, mini(depth, 10)))
        while th.is_alive(): await get_tree().process_frame
        move = th.wait_to_finish()
    if move.is_empty(): return {}
    var m: Dictionary = search.last_metrics
    var score := int(m.get("score", 0))
    var out := {"cp": score, "mate": 0, "pv": [Notation.uci_of(pos, move)], "depth": int(m.get("depth", 0)), "bestmove": Notation.uci_of(pos, move)}
    if absi(score) >= Search.MATE_SCORE - 200:
        var plies := Search.MATE_SCORE - absi(score)
        out.mate = (plies + 1) / 2 * (1 if score > 0 else -1)
        out.cp = 0
    return out
