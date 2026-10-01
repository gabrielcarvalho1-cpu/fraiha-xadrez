extends RefCounted
## FAIR PLAY — regra absoluta: NENHUMA engine durante partida humana ativa.
## Única porta para decidir se a análise pode rodar. A interface e o analyzer consultam aqui.
## Casos:
##   • Ranked / Casual / partida com amigo (modo "ranked", "casual", "online", "friend"):
##     só depois que a partida TERMINOU (record.finished = true e o controlador não está em partida).
##   • Bot / treino: também só pós-partida nesta fase (prioridade do produto).
##   • "Marcar para revisar" nunca chama engine: só grava o índice do lance.
const HUMAN_MODES := ["ranked", "casual", "online", "friend", "local"]

## A análise desta partida pode começar agora?
static func can_analyze(record, stage) -> bool:
    if record == null or not record.finished: return false
    if stage != null:
        for c in [stage.get("ranked"), stage.get("casual")]:
            if c != null and c.has_method("in_match") and c.in_match(): return false
        var mode := String(stage.get("mode"))
        if mode in ["ranked", "casual", "online", "local"] and not stage.game.game_over: return false
    return true

## Durante partida humana ativa a interface não pode mostrar NADA de engine.
static func engine_hidden(stage) -> bool:
    if stage == null: return false
    var mode := String(stage.get("mode"))
    if mode not in HUMAN_MODES: return false
    return not stage.game.game_over

## Porta ÚNICA para qualquer consulta de engine (análise OU bot). true = proibido agora.
##   • Partida humana em andamento (Ranked, Casual, online/desafio, local 2 jogadores): sempre bloqueia.
##   • role "bot": além disso, só pode responder quando o modo atual é "bot".
static func engine_blocked(stage, role: String) -> bool:
    if stage == null: return false
    for c in [stage.get("ranked"), stage.get("casual")]:
        if c != null and c.has_method("in_match") and c.in_match(): return true
    var mode := String(stage.get("mode"))
    var game = stage.get("game")
    var over: bool = game != null and bool(game.get("game_over"))
    if mode in HUMAN_MODES and not over: return true
    if role == "bot" and mode != "bot": return true
    return false
