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
