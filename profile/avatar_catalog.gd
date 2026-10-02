extends RefCounted
## Coleção de avatares do FRAIHA (galeria de progressão do Perfil).
## FONTE DA PROGRESSÃO: bot/bot_ladder.json — cada bot tem reward {type:"avatar", id}. A ordem e os IDs
## vêm de lá; aqui ficam nome e arte. Desbloqueio dos de bot = bot_progress.avatar_unlocked() (derivado da
## escada; para conta a autoridade é o servidor). Sem tabela própria.
##
## R30: as 11 recompensas da escada usam as artes oficiais das ligas (res://profile/avatars/<id>.png, 512px).
## Mago e Paladino (recompensas antigas de Madeira/Ferro) saíram da coleção — quem os usava volta ao Guerreiro;
## as texturas continuam só para exibir perfis antigos de outros jogadores.
## Avatar FUNDADOR: exclusivo de quem tem o Pacote Fundador (entitlements.founder(): servidor is_founder ou
## simulação de dev). Não é competitivo.
const Ladder = preload("res://bot/bot_ladder.gd")
const ART_DIR := "res://profile/avatars/"
const INITIAL := ["warrior", "archer", "peao_branco", "peao_negro"]   # gratuitos (todo jogador)
const FOUNDER := "fundador"
## R31 · Club FRAIHA: 3 avatares exclusivos de quem tem o Club ativo (entitlements.club_active()).
const CLUB := ["club_avatar_a", "club_avatar_b", "club_avatar_c"]

const NAMES := {
    "warrior": "Guerreiro", "archer": "Arqueira", "mage": "Mago", "paladin": "Paladino",
    "madeira_reward": "Rei de Madeira", "ferro_reward": "Torre de Ferro",
    "bronze_reward": "Cavalo de Bronze", "prata_reward": "Cavaleiro de Prata",
    "ouro_reward": "Rei Dourado", "platina_reward": "Rainha de Platina",
    "esmeralda_reward": "Druida Esmeralda", "diamante_reward": "Torre de Diamante",
    "mestre_reward": "Cavaleiro Mestre", "grande_mestre_reward": "Rei Grão-Mestre",
    "challenger_reward": "O Desafiante",
    "fundador": "Fundador do Reino",
    "club_avatar_a": "Rainha Erudita", "club_avatar_b": "Bispo Estrategista", "club_avatar_c": "Cavaleiro Esmeralda",
    "peao_branco": "Peão Branco", "peao_negro": "Peão Negro",
}
const FIXED_ART := {
    "warrior": "res://ui_v022/assets/profile_avatar.png",
    "paladin": "res://profile/paladin.png",
}

## Todos os avatares, na ordem da coleção: iniciais, recompensas na ordem da escada e o do Fundador.
## Cada item: {id, name, source ("initial" | bot_id | "founder" | "club"), league}
static func entries() -> Array:
    var out: Array = []
    for id in INITIAL: out.append({"id": id, "name": NAMES.get(id, id), "source": "initial", "league": ""})
    for b in Ladder.bots():
        var r: Dictionary = b.get("reward", {})
        if String(r.get("type", "")) != "avatar": continue
        var id := String(r.get("id", ""))
        out.append({"id": id, "name": NAMES.get(id, "Avatar " + String(b.get("name", "")).replace("BOT ", "")), "source": String(b.id), "league": String(b.get("league", b.id))})
    out.append({"id": FOUNDER, "name": NAMES[FOUNDER], "source": "founder", "league": ""})
    for id in CLUB: out.append({"id": id, "name": NAMES[id], "source": "club", "league": ""})
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
    return String(NAMES.get(id, entry(id).get("name", id)))

static func is_founder_avatar(id: String) -> bool:
    return id == FOUNDER

static func is_club_avatar(id: String) -> bool:
    return id in CLUB

## Caminho da arte de um avatar.
static func art_path(id: String) -> String:
    return FIXED_ART.get(id, ART_DIR + id + ".png")

## Existe arte para este avatar? (archer/mage vêm do atlas cosmetics/v025/avatars.png)
static func has_art(id: String) -> bool:
    if id in ["archer", "mage"] or FIXED_ART.has(id): return true
    return ResourceLoader.exists(art_path(id))

## Avatares da coleção cuja arte ainda precisa ser adicionada (para o relatório).
static func missing_art() -> PackedStringArray:
    var out := PackedStringArray()
    for e in entries():
        if not has_art(String(e.id)): out.append(String(e.id))
    return out
