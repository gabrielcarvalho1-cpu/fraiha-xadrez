extends RefCounted
## Coleção de avatares do FRAIHA (galeria de progressão do Perfil).
## FONTE DA PROGRESSÃO: bot/bot_ladder.json — cada bot tem reward {type:"avatar", id}. A ordem e os IDs
## vêm de lá; aqui só ficam nome, arte e o briefing visual. Desbloqueio = bot_progress.avatar_unlocked()
## (derivado do progresso da escada, cuja autoridade para conta é o servidor). Sem tabela própria.
##
## Arte: os 4 retratos existentes têm caminho fixo. Os avatares de Bronze → Challenger usam
## res://profile/avatars/<id>.png quando o arquivo existir (512x512 ou maior, quadrado). Enquanto não
## existir, a galeria mostra a silhueta + brasão da liga com "ARTE EM BREVE" e o avatar não é selecionável.
const Ladder = preload("res://bot/bot_ladder.gd")
const ART_DIR := "res://profile/avatars/"
const INITIAL := ["warrior", "archer"]

const NAMES := {
    "warrior": "Guerreiro", "archer": "Arqueira", "mage": "Mago", "paladin": "Paladino",
    "bronze_reward": "Escudeiro de Bronze", "prata_reward": "Cavaleira de Prata",
    "ouro_reward": "Guardião Dourado", "platina_reward": "Arquimaga de Platina",
    "esmeralda_reward": "Druida Esmeralda", "diamante_reward": "Lâmina de Diamante",
    "mestre_reward": "Estrategista Mestre", "grande_mestre_reward": "Soberana Grão-Mestre",
    "challenger_reward": "O Desafiante",
}
## Briefing para a arte (progressão de riqueza + variedade de pose). Usado no handoff e no tooltip DEV.
const ART_BRIEF := {
    "bronze_reward": "Couro e placas de bronze simples, pouca ornamentação. Pose frontal, olhar firme.",
    "prata_reward": "Armadura de metal polido, capa curta, detalhes nobres discretos. 3/4 para a esquerda.",
    "ouro_reward": "Armadura dourada ornamentada, ombreiras gravadas, presença de personagem importante. Perfil.",
    "platina_reward": "Vestes e metal raros (platina fosca), acabamento sofisticado. Olhando por cima do ombro.",
    "esmeralda_reward": "Gemas verdes incrustadas, tecidos ricos, aura sutil. Perspectiva levemente baixa.",
    "diamante_reward": "Cristais e luz mágica, brilho frio, presença muito rara. 3/4 para a direita, mão erguida.",
    "mestre_reward": "Comandante estrategista, manto pesado, mapa/peça de xadrez na mão. Pose estratégica.",
    "grande_mestre_reward": "Realeza: coroa, manto de arminho, cetro. Pose régia frontal, queixo erguido.",
    "challenger_reward": "Recompensa máxima: armadura lendária, aura dourada/esmeralda, efeitos de energia. Pose heroica baixa.",
}
const FIXED_ART := {
    "warrior": "res://ui_v022/assets/profile_avatar.png",
    "paladin": "res://profile/paladin.png",
}

## Todos os avatares, na ordem da coleção: iniciais e depois as recompensas na ordem da escada.
## Cada item: {id, name, source ("initial" | bot_id), league}
static func entries() -> Array:
    var out: Array = []
    for id in INITIAL: out.append({"id": id, "name": NAMES.get(id, id), "source": "initial", "league": ""})
    for b in Ladder.bots():
        var r: Dictionary = b.get("reward", {})
        if String(r.get("type", "")) != "avatar": continue
        var id := String(r.get("id", ""))
        out.append({"id": id, "name": NAMES.get(id, "Avatar " + String(b.get("name", "")).replace("BOT ", "")), "source": String(b.id), "league": String(b.get("league", b.id))})
    return out

static func ids() -> PackedStringArray:
    var out := PackedStringArray()
    for e in entries(): out.append(String(e.id))
    return out

static func entry(id: String) -> Dictionary:
    for e in entries():
        if String(e.id) == id: return e
    return {}

static func display_name(id: String) -> String:
    return String(entry(id).get("name", id))

## Caminho da arte de um avatar de recompensa (pode não existir ainda).
static func art_path(id: String) -> String:
    return FIXED_ART.get(id, ART_DIR + id + ".png")

## Existe arte para este avatar? (archer/mage vêm do atlas cosmetics/v025/avatars.png)
static func has_art(id: String) -> bool:
    if id in ["archer", "mage"] or FIXED_ART.has(id): return true
    return ResourceLoader.exists(art_path(id))

## Avatares cuja arte ainda precisa ser adicionada (para o relatório).
static func missing_art() -> PackedStringArray:
    var out := PackedStringArray()
    for e in entries():
        if not has_art(String(e.id)): out.append(String(e.id))
    return out
