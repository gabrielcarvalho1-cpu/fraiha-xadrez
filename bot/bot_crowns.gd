extends RefCounted
## R184e · COROAS da 1ª vitória contra cada bot do Desafio das Ligas (proposta: Madeira 50, +25 por bot, Challenger 300).
## O SERVIDOR é quem paga (online_v021/bots/service.js, mesma tabela); aqui é só para mostrar na tela.
const ENABLED := true   # R184e · aprovado pelo dono
const BASE := 50
const STEP := 25

static func for_bot(bot_id: String) -> int:
	if not ENABLED: return 0
	var i: int = preload("res://bot/bot_ladder.gd").index_of(bot_id)
	if i < 0: return 0
	return BASE + STEP * i
