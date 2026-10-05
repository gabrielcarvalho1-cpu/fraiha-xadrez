extends SceneTree

class Gate:
    extends RefCounted
    signal resolved

class RaceEngine:
    extends "res://analysis/engine.gd"
    var denied := false
    var startup_gate: Gate
    var result_gate: Gate
    var commands: Array[String] = []
    var searches := 0
    var completed_result := false
    var result: Dictionary = {}

    func blocked() -> bool:
        return denied

    func start() -> String:
        await startup_gate.resolved
        engine_ready = true
        transport = "builtin"
        return "test"

    func _evaluate_builtin(_fen: String, _depth: int, _max_ms: int) -> Dictionary:
        searches += 1
        await result_gate.resolved
        return {"bestmove": "e2e4", "cp": 30}

    func _send(command: String):
        commands.append(command)
        if command == "stop": _lines.append("bestmove e2e4")

    func run_evaluation():
        result = await evaluate("test", 1, 1000)
        completed_result = true

    func run_search():
        result = await search_move("test", "go depth 1", 1000)
        completed_result = true

var failures := 0
var checks := 0

func _initialize():
    call_deferred("run")

func check(condition: bool, label: String):
    checks += 1
    if not condition: failures += 1
    print(("PASS " if condition else "FAIL ") + label)

func engine() -> RaceEngine:
    var instance := RaceEngine.new()
    root.add_child(instance)
    return instance

func wait_result(instance: RaceEngine):
    for frame in 100:
        if instance.completed_result: return
        await process_frame
    check(false, "job completed within frame bound")

func run():
    var instance := engine()
    instance.startup_gate = Gate.new()
    instance.run_evaluation()
    await process_frame
    instance.denied = true
    instance.startup_gate.resolved.emit()
    await wait_result(instance)
    check(instance.result.is_empty() and instance.searches == 0, "PvP during startup dispatches no search")
    instance.queue_free()

    instance = engine()
    instance.engine_ready = true
    instance.transport = "builtin"
    instance._busy = true
    instance.run_evaluation()
    await process_frame
    instance.denied = true
    instance._busy = false
    await wait_result(instance)
    check(instance.result.is_empty() and instance.searches == 0, "PvP while waiting for busy engine dispatches no search")
    instance.queue_free()

    instance = engine()
    instance.engine_ready = true
    instance.transport = "builtin"
    instance.result_gate = Gate.new()
    instance.run_evaluation()
    await process_frame
    instance.denied = true
    await process_frame
    instance.result_gate.resolved.emit()
    await wait_result(instance)
    check(instance.result.is_empty() and instance._cancel, "fallback result in flight is suppressed during PvP")
    instance.queue_free()

    instance = engine()
    instance.engine_ready = true
    instance.transport = "web"
    instance.run_search()
    await process_frame
    instance.denied = true
    await wait_result(instance)
    check(instance.result.is_empty() and "stop" in instance.commands, "UCI search in flight receives stop and returns no hint")
    instance.queue_free()
    var controller = load("res://bot/controller.gd").new()
    root.add_child(controller)
    controller.active = true
    controller.guard = func() -> bool: return true
    controller.completed = {"from": Vector2i(4, 6), "to": Vector2i(4, 4)}
    controller._process(0.0)
    check(not controller.active and controller.completed.is_empty(), "bot fallback pending work is discarded before presentation")
    controller.queue_free()
    print("ANALYSIS_ENGINE_RACES CHECKS=%d FAILURES=%d" % [checks, failures])
    quit(1 if failures else 0)
