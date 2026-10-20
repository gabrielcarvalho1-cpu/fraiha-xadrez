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
## R163 · 34 avatares novos (AVATARES_FRAIHA_34_5) divididos por função. O servidor (online_v021/accounts/cosmetics.js
## e economy/store_catalog.js) tem as MESMAS listas e é quem decide o que cada conta pode usar.
const FREE_NEW := ["av_peao_dourado", "av_torre_marmore", "av_bispo_marmore", "av_cavalo_marmore", "av_heroi", "av_principe_dourado"]
const SHOP := ["av_cavalo_dourado", "av_rainha_marmore", "av_rainha_ametista", "av_rei_rubi", "av_bispo_safira", "av_rei_luz", "av_cavaleiro_real", "av_cavaleiro_escarlate", "av_guardiao_torre", "av_rainha_sombria"]   # Loja de Coroas (preço em economy/crown_store_catalog.gd)
const PASS_FREE := ["av_rei_onix", "av_rainha_onix", "av_torre_onix", "av_cavalo_onix"]   # Passe: faixa grátis, nível 25 (um por temporada, em rodízio)
const PASS_CLUB := ["av_principe_sombras", "av_principe_esmeralda", "av_aristocrata"]   # Passe: faixa Club, nível 25 (um por temporada, em rodízio)
const FOUNDER_MORE := ["av_mestre_dourado", "av_mestre_sombras", "av_grao_mestre", "av_rainha_invernal"]
const LEGEND := ["av_lenda_mistica"]   # só Fundador Lendário
const FOUNDER := "fundador"
## R31 · Club FRAIHA: 3 avatares exclusivos de quem tem o Club ativo (entitlements.club_active()).
const CLUB := ["club_avatar_a", "club_avatar_b", "club_avatar_c", "av_rainha_purpura", "av_dama_esmeralda", "av_dama_bispo", "av_dama_torre", "av_mestre_purpura", "av_rainha_neon"]

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
    "av_peao_dourado": "Peão Dourado",
    "av_torre_marmore": "Torre de Mármore",
    "av_bispo_marmore": "Bispo de Mármore",
    "av_cavalo_marmore": "Cavalo de Mármore",
    "av_heroi": "Herói do Tabuleiro",
    "av_principe_dourado": "Príncipe Dourado",
    "av_cavalo_dourado": "Cavalo Dourado",
    "av_rainha_marmore": "Rainha de Mármore",
    "av_rainha_ametista": "Rainha de Ametista",
    "av_rei_rubi": "Rei de Rubi",
    "av_bispo_safira": "Bispo de Safira",
    "av_rei_luz": "Rei da Luz Dourada",
    "av_cavaleiro_real": "Cavaleiro Real",
    "av_cavaleiro_escarlate": "Cavaleiro Escarlate",
    "av_guardiao_torre": "Guardião da Torre",
    "av_rainha_sombria": "Rainha Sombria",
    "av_rei_onix": "Rei de Ônix",
    "av_rainha_onix": "Rainha de Ônix",
    "av_torre_onix": "Torre de Ônix",
    "av_cavalo_onix": "Cavalo de Ônix",
    "av_principe_sombras": "Príncipe das Sombras",
    "av_principe_esmeralda": "Príncipe Esmeralda",
    "av_aristocrata": "Aristocrata do Relógio",
    "av_rainha_purpura": "Rainha Púrpura",
    "av_dama_esmeralda": "Dama Esmeralda",
    "av_dama_bispo": "Dama do Bispo",
    "av_dama_torre": "Dama da Torre",
    "av_mestre_purpura": "Mestre Púrpura",
    "av_rainha_neon": "Rainha Neon",
    "av_mestre_dourado": "Mestre Dourado",
    "av_mestre_sombras": "Mestre das Sombras",
    "av_grao_mestre": "Grão-Mestre Real",
    "av_rainha_invernal": "Rainha Invernal",
    "av_lenda_mistica": "Lenda Mística",
}
const FIXED_ART := {
    "warrior": "res://ui_v022/assets/profile_avatar.png",
    "paladin": "res://profile/paladin.png",
}

## Todos os avatares, na ordem da coleção: iniciais, recompensas na ordem da escada e o do Fundador.
## Cada item: {id, name, source ("initial" | bot_id | "founder" | "club"), league}
static func entries() -> Array:
    var out: Array = []
    for id in INITIAL + FREE_NEW: out.append({"id": id, "name": NAMES.get(id, id), "source": "initial", "league": ""})
    for b in Ladder.bots():
        var r: Dictionary = b.get("reward", {})
        if String(r.get("type", "")) != "avatar": continue
        var id := String(r.get("id", ""))
        out.append({"id": id, "name": NAMES.get(id, "Avatar " + String(b.get("name", "")).replace("BOT ", "")), "source": String(b.id), "league": String(b.get("league", b.id))})
    for id in SHOP: out.append({"id": id, "name": NAMES[id], "source": "shop", "league": ""})
    for id in PASS_FREE + PASS_CLUB: out.append({"id": id, "name": NAMES[id], "source": "pass", "league": ""})
    for id in CLUB: out.append({"id": id, "name": NAMES[id], "source": "club", "league": ""})
    out.append({"id": FOUNDER, "name": NAMES[FOUNDER], "source": "founder", "league": ""})
    for id in FOUNDER_MORE + LEGEND: out.append({"id": id, "name": NAMES[id], "source": "founder", "league": ""})
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
    return id == FOUNDER or id in FOUNDER_MORE or id in LEGEND

static func is_legend_avatar(id: String) -> bool:
    return id in LEGEND

## R163 · comprados na Loja de Coroas ou ganhos no Passe: ficam na conta para sempre (crown_items)
static func is_owned_avatar(id: String) -> bool:
    return id in SHOP or id in PASS_FREE or id in PASS_CLUB

static func is_pass_avatar(id: String) -> bool:
    return id in PASS_FREE or id in PASS_CLUB

static func is_club_avatar(id: String) -> bool:
    return id in CLUB

## Caminho da arte de um avatar.
static func art_path(id: String) -> String:
    if FIXED_ART.has(id): return FIXED_ART[id]
    if id.begins_with("av_"): return ART_DIR + id + ".webp"   # R163 · avatares novos em WebP (leves)
    return ART_DIR + id + ".png"

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
