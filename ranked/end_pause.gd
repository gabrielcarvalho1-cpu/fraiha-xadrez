extends RefCounted
## R176 · fim de partida: segundos para VER a posição final (o mate) antes da animação/painel de resultado,
## como no chess.com. Testes antigos rodam sem pausa com FRAIHA_END_PAUSE=0.
const DEFAULT := 2.2

static func secs() -> float:
	var e := OS.get_environment("FRAIHA_END_PAUSE")
	return float(e) if e.is_valid_float() else DEFAULT
