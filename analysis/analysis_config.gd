extends RefCounted
## Regras numéricas da análise FRAIHA: expectativa de vitória, classificação dos lances e
## precisão. Tudo centralizado e ajustável aqui. Documentação em analysis/ANALISE.md.
##
## 1) EXPECTATIVA DE VITÓRIA (win%) — converte centipeões em "chance de vitória" (0..100):
##      win% = 50 + 50 * (2 / (1 + exp(-K * cp)) - 1),  K = 0.00368208
##    (curva logística; cp do ponto de vista de quem acabou de jogar). Mate = 100 / 0.
##    Usar win% em vez de cp bruto faz +300 → +600 valer pouco (já ganho) e 0 → -300 valer muito.
##
## 2) PERDA (loss) de um lance = win%(melhor lance) − win%(lance jogado), ambos avaliados
##    pela engine na mesma profundidade, do ponto de vista de quem jogou. loss >= 0.
##
## 3) CLASSIFICAÇÃO (ordem de verificação; a primeira que valer, vale):
##    - TEÓRICO: posição ainda no livro de aberturas do FRAIHA (analysis/opening_book.gd).
##    - LENDÁRIO: era o ÚNICO lance que mantinha a posição (2º melhor perde >= LEGENDARY_GAP de win%),
##                a posição era difícil (avaliação do adversário antes do lance >= -1.0 peão, ou seja,
##                não era "ganho fácil"), o lance é um sacrifício (entrega material >= 2 peões que a
##                engine confirma) e a perda é 0. Raríssimo por construção.
##    - EXTRAORDINÁRIO: único lance bom (2º melhor perde >= BRILLIANT_GAP), perda 0, e a posição não
##                era já completamente ganha (win% antes <= 90). Raro.
##    - MELHOR LANCE: perda 0 (lance = bestmove da engine, ou mesma avaliação).
##    - EXCELENTE: perda < EXCELLENT.
##    - BOM: perda < GOOD.
##    - IMPRECISÃO: perda < INACCURACY.
##    - OPORTUNIDADE PERDIDA: havia mate forçado (ou vantagem decisiva win% >= 85) e o lance
##                deixou de converter (win% caiu >= MISSED_DROP) sem virar derrota.
##    - ERRO: perda < MISTAKE.
##    - ERRO GRAVE: perda >= MISTAKE (ou entregou mate / jogou para mate).
##    Mate: entrar em mate forçado contra si = ERRO GRAVE; perder um mate seu = OPORTUNIDADE PERDIDA.
##
## 4) PRECISÃO (0–100) por jogador:
##      precisão = média ponderada de (100 − loss_i) por lance, com peso maior nos lances
##      jogados fora de posições já decididas (|win% − 50| < 45 → peso 1.0; senão 0.5).
##      Lances TEÓRICOS contam como perda 0. Não é "centipawn loss" bruto.
const K := 0.00368208

const EXCELLENT := 2.0       # perda de win% < 2  → EXCELENTE
const GOOD := 5.0            # < 5  → BOM
const INACCURACY := 10.0     # < 10 → IMPRECISÃO
const MISTAKE := 20.0        # < 20 → ERRO; >= 20 → ERRO GRAVE
const MISSED_DROP := 15.0    # queda mínima para "oportunidade perdida" numa posição decisiva
const DECISIVE := 85.0       # win% a partir do qual a posição é "decisiva"
const BRILLIANT_GAP := 12.0  # 2º melhor lance perde pelo menos isto → lance "único"
const LEGENDARY_GAP := 20.0
const SACRIFICE_CP := 200    # material entregue para contar como sacrifício (em cp)
const MATE_CP := 10000

const LABELS := {
    "legendary": "LENDÁRIO", "brilliant": "EXTRAORDINÁRIO", "best": "MELHOR LANCE", "excellent": "EXCELENTE",
    "good": "BOM", "book": "TEÓRICO", "inaccuracy": "IMPRECISÃO", "mistake": "ERRO",
    "missed": "OPORTUNIDADE PERDIDA", "blunder": "ERRO GRAVE",
}
const GLYPHS := {
    "legendary": "👑", "brilliant": "✨", "best": "⚔", "excellent": "💎", "good": "✓", "book": "📖",
    "inaccuracy": "⚠", "mistake": "❌", "missed": "🎯", "blunder": "💀",
}
const COLORS := {
    "legendary": Color("ffd76a"), "brilliant": Color("7fe0ff"), "best": Color("9de5a0"), "excellent": Color("6fd6c8"),
    "good": Color("c9d8b0"), "book": Color("d8c9a0"), "inaccuracy": Color("f2c56b"), "mistake": Color("f2924f"),
    "missed": Color("e7a4ff"), "blunder": Color("ff6b5c"),
}
## Quais classes viram exercício em TREINE MEUS ERROS (em ordem de prioridade).
const TRAIN_CLASSES := ["blunder", "missed", "mistake", "inaccuracy"]

## cp (ponto de vista de quem joga) → win% 0..100. mate: +N = eu dou mate, -N = levo mate.
static func win_percent(cp: int, mate: int = 0) -> float:
    if mate > 0: return 100.0
    if mate < 0: return 0.0
    return 50.0 + 50.0 * (2.0 / (1.0 + exp(-K * float(clampi(cp, -MATE_CP, MATE_CP)))) - 1.0)

## Avaliação "assinada" para o gráfico: positivo = Brancas melhor, em peões, mate = ±MATE_CP/100.
static func signed_pawns(cp: int, mate: int, side_to_move: String) -> float:
    var v := float(cp) / 100.0
    if mate != 0: v = (MATE_CP / 100.0) * (1.0 if mate > 0 else -1.0)
    return v if side_to_move == "w" else -v

## Texto curto da avaliação: "+0.8", "-1.7", "M3", "-M2".
static func eval_text(cp: int, mate: int, side_to_move: String) -> String:
    var sign_flip := side_to_move == "b"
    if mate != 0:
        var m := -mate if sign_flip else mate
        return ("M%d" % absi(m)) if m > 0 else ("-M%d" % absi(m))
    var v := (-cp if sign_flip else cp) / 100.0
    return "%+.1f" % v if absf(v) < 100.0 else ("+99" if v > 0 else "-99")

## Classifica um lance. Entradas do ponto de vista de QUEM JOGOU:
##   best_win: win% do melhor lance; played_win: win% do lance jogado; second_win: win% do 2º melhor
##   (ou -1 se desconhecido); in_book; sacrificed_cp (material entregue, 0 se não);
##   played_is_best; played_mate_against: o lance jogado permitiu mate forçado contra si;
##   best_was_mate: o melhor lance dava mate forçado.
static func classify(best_win: float, played_win: float, second_win: float, in_book: bool, sacrificed_cp: int, played_is_best: bool, played_mate_against: bool, best_was_mate: bool) -> String:
    if in_book: return "book"
    var loss: float = maxf(0.0, best_win - played_win)
    if played_mate_against and loss >= INACCURACY: return "blunder"
    if played_is_best or loss < 0.05:
        var unique := second_win >= 0.0 and (best_win - second_win) >= BRILLIANT_GAP
        if unique and sacrificed_cp >= SACRIFICE_CP and best_win <= 97.0 and (best_win - second_win) >= LEGENDARY_GAP: return "legendary"
        if unique and best_win <= 90.0: return "brilliant"
        return "best"
    if loss < EXCELLENT: return "excellent"
    if loss < GOOD: return "good"
    if loss < INACCURACY: return "inaccuracy"
    # posição decisiva (ou mate seu) que deixou de ser convertida sem virar derrota
    if (best_was_mate or best_win >= DECISIVE) and loss >= MISSED_DROP and played_win >= 50.0: return "missed"
    if loss < MISTAKE: return "mistake"
    return "blunder"

## Precisão 0..100 de uma lista de perdas (win%) com os win% "antes" para o peso.
static func accuracy(losses: Array, before_wins: Array) -> float:
    if losses.is_empty(): return 100.0
    var num := 0.0
    var den := 0.0
    for i in losses.size():
        var w := 1.0 if absf(float(before_wins[i]) - 50.0) < 45.0 else 0.5
        num += w * clampf(100.0 - float(losses[i]) * 2.2, 0.0, 100.0)
        den += w
    return clampf(num / maxf(0.001, den), 0.0, 100.0)
