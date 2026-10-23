extends RefCounted
## R31 · Identidade premium do jogador: ÍCONE (selo ao lado do nome), TÍTULO e MOLDURA.
## Só aparência — nunca altera PL, matchmaking, tempo, regras ou chances (FRAIHA não é pay-to-win).
## A escolha fica nas preferências do aparelho e é enviada ao servidor (acct_set_cosmetics),
## que revalida pelos direitos da conta e a mostra aos outros jogadores (Destaque social).
## Escolha guardada mas sem direito ativo (ex.: Club venceu) → não aparece, sem apagar a preferência.

## Ícones (selos). "" = nenhum.
const BADGES := ["", "fundador", "club_a", "club_b", "club_c"]
const BADGE_NAMES := {"": "Nenhum", "fundador": "Selo Fundador", "club_a": "Club · Rainha", "club_b": "Club · Bispo", "club_c": "Club · Cavalo"}
const BADGE_ART := {
    "fundador": "res://monetization/art/founder_badge.png",
    "club_a": "res://monetization/art/club_badge_a.png",
    "club_b": "res://monetization/art/club_badge_b.png",
    "club_c": "res://monetization/art/club_badge_c.png",
}
const BADGE_ART_SMALL := {
    "fundador": "res://monetization/art/founder_badge_small.png",
    "club_a": "res://monetization/art/club_badge_a_small.png",
    "club_b": "res://monetization/art/club_badge_b_small.png",
    "club_c": "res://monetization/art/club_badge_c_small.png",
}
## Títulos exibidos sob o nome. "" = nenhum.
## R116 · depois dos títulos de direito, os da LOJA DE COROAS (economy/crown_store_catalog.gd; comprados = para sempre).
const TITLES := ["", "fundador", "lendario", "club",
	"estrategista", "mestre_tatico", "rei_do_blitz", "guardiao", "dama_de_ferro", "cavaleiro", "gambito", "lenda_xeque", "senhor_marcha", "imperador"]
const TITLE_TEXT := {"": "", "fundador": "Fundador do Reino", "lendario": "Fundador Lendário", "club": "Membro do Club FRAIHA",
	"estrategista": "Estrategista", "mestre_tatico": "Mestre Tático", "rei_do_blitz": "Rei do Blitz", "guardiao": "Guardião do Reino",
	"dama_de_ferro": "Dama de Ferro", "cavaleiro": "Cavaleiro da Coroa", "gambito": "Mestre do Gambito", "lenda_xeque": "Lenda do XEQUE",
	"senhor_marcha": "Senhor da Marcha", "imperador": "Imperador do Tabuleiro"}
## R176.9 · cada título tem COR PRÓPRIA (e brilho, title_tag.gd): cartão do adversário no início da partida,
## CHAT GLOBAL, cartão do lobby e a aba TÍTULOS do Perfil.
const TITLE_COLOR := {"fundador": Color("ffcf5a"), "lendario": Color("ff8a4a"), "club": Color("5fe39a"),
	"estrategista": Color("7fc8ff"), "mestre_tatico": Color("9ea8ff"), "rei_do_blitz": Color("ffe066"), "guardiao": Color("8ce0c8"),
	"dama_de_ferro": Color("d7dde8"), "cavaleiro": Color("f2b866"), "gambito": Color("ff9db0"), "lenda_xeque": Color("ff6b6b"),
	"senhor_marcha": Color("c9a2ff"), "imperador": Color("ffd84a")}
static func title_color(id: String) -> Color:
    return TITLE_COLOR.get(id, Color("f6d27a"))
const ShopCatalog := preload("res://economy/crown_store_catalog.gd")
## R116 · itens da Loja de Coroas que esta conta já tem (o servidor manda em store_state; economy/crowns_client.gd guarda).
static var shop_owned: Array = []
## Molduras do retrato. "liga" = moldura da liga atual (padrão de todo jogador).
## R116 · + molduras da LOJA DE COROAS (o id é o estilo de monetization/club_frame.gd)
## R166 · molduras de ARTE: as de ELO (liberadas ao ALCANÇAR a liga no Ranked; a maior liga já alcançada) e as da
## Loja de Coroas (pacote novo). As antigas desenhadas da Loja (prata, rubi…) saíram.
const ELO_FRAMES := ["elo_madeira", "elo_ferro", "elo_bronze", "elo_prata", "elo_ouro", "elo_platina", "elo_esmeralda", "elo_diamante", "elo_mestre", "elo_grande_mestre", "elo_challenger"]
const LEAGUE_NAMES := ["Madeira", "Ferro", "Bronze", "Prata", "Ouro", "Platina", "Esmeralda", "Diamante", "Mestre", "Grande Mestre", "Challenger"]
const FRAMES := ["liga", "club", "fundador", "elo_madeira", "elo_ferro", "elo_bronze", "elo_prata", "elo_ouro", "elo_platina", "elo_esmeralda", "elo_diamante", "elo_mestre", "elo_grande_mestre", "elo_challenger",
	"m_noite_estrelada", "m_chama_eterna"]
## R167 · só 2 molduras na Loja (as mais bonitas, 10.000 Coroas: prêmio de quem joga muito). As outras 8 artes
## continuam no jogo (monetization/frames) guardadas para Passe/torneio/evento, mas não podem ser usadas por ninguém.
const FRAME_NAMES := {"liga": "Moldura da Liga", "club": "Moldura Club", "fundador": "Moldura Fundador",
	"elo_madeira": "Elo Madeira", "elo_ferro": "Elo Ferro", "elo_bronze": "Elo Bronze", "elo_prata": "Elo Prata", "elo_ouro": "Elo Ouro", "elo_platina": "Elo Platina",
	"elo_esmeralda": "Elo Esmeralda", "elo_diamante": "Elo Diamante", "elo_mestre": "Elo Mestre", "elo_grande_mestre": "Elo Grande Mestre", "elo_challenger": "Elo Challenger",
	"m_safira_real": "Safira Real", "m_ametista_real": "Ametista Real", "m_esmeralda_real": "Esmeralda Real", "m_rubi_real": "Rubi Real", "m_brasa": "Brasa de Lava",
	"m_diamante_prata": "Diamante de Prata", "m_marmore_esmeralda": "Mármore Esmeralda", "m_diamante_dourado": "Diamante Dourado", "m_noite_estrelada": "Noite Estrelada", "m_chama_eterna": "Chama Eterna"}
## maior liga já alcançada pela conta (0 = Madeira … 10 = Challenger); o hub atualiza (main_hub.current_frame)
static var highest_league := 0
static func elo_index(id: String) -> int:
    return ELO_FRAMES.find(id)

## Que direito cada item exige: "" (todos) | "founder" | "legend" (R103 · Fundador Lendário) | "club".
static func requirement(kind: String, id: String) -> String:
    if id.is_empty() or id == "liga": return ""
    if kind == "frame" and id in ELO_FRAMES: return "league"
    var shop := ShopCatalog.item(id)
    if not shop.is_empty() and String(shop.kind) == kind: return "shop"
    if id == "lendario": return "legend"
    if id == "fundador": return "founder"
    if kind == "badge" and id.begins_with("club_"): return "club"
    if id == "club": return "club"
    return ""

static func allowed(kind: String, id: String, founder: bool, club: bool, legend := false) -> bool:
    match requirement(kind, id):
        "founder": return founder
        "legend": return founder and legend
        "club": return club
        "shop": return id in shop_owned
        "league": return highest_league >= elo_index(id)
    return true

static func lock_hint(kind: String, id: String) -> String:
    match requirement(kind, id):
        "founder": return "Exclusivo do Pacote Fundador"
        "legend": return "Exclusivo do Fundador Lendário"
        "club": return "Exclusivo do Club FRAIHA"
        "shop": return "Loja de Coroas · %d Coroas" % int(ShopCatalog.item(id).get("price", 0))
        "league": return "Alcance a liga %s no Ranked" % LEAGUE_NAMES[maxi(0, elo_index(id))]
    return ""

## Escolha automática (preferência vazia): o melhor item que o jogador possui.
static func auto_badge(founder: bool, club: bool) -> String:
    if founder: return "fundador"
    if club: return "club_a"
    return ""

static func auto_title(founder: bool, club: bool, legend := false) -> String:
    if founder and legend: return "lendario"
    if founder: return "fundador"
    if club: return "club"
    return ""

static func auto_frame(founder: bool, club: bool) -> String:
    if club: return "club"          # comportamento das versões anteriores (Club = moldura dourada)
    if founder: return "fundador"
    return "liga"

## Preferência ("auto" = automático) → item efetivo, respeitando os direitos atuais.
static func effective(kind: String, pref: String, founder: bool, club: bool, legend := false) -> String:
    if pref == "auto" or (kind == "frame" and pref.is_empty()):
        match kind:
            "badge": return auto_badge(founder, club)
            "title": return auto_title(founder, club, legend)
            _: return auto_frame(founder, club)
    if kind == "frame" and pref not in FRAMES: return auto_frame(founder, club)   # R166 · moldura antiga que saiu
    if not allowed(kind, pref, founder, club, legend):
        return "liga" if kind == "frame" else ""
    return pref

static var _tex_cache := {}
static func badge_texture(id: String, small := true) -> Texture2D:
    var table: Dictionary = BADGE_ART_SMALL if small else BADGE_ART
    var path := String(table.get(id, ""))
    if path.is_empty() or not ResourceLoader.exists(path): return null
    if not _tex_cache.has(path): _tex_cache[path] = load(path) as Texture2D
    return _tex_cache[path]

static func title_text(id: String) -> String:
    return String(TITLE_TEXT.get(id, ""))

## Selo público de outro jogador (dados do servidor: badge já validado pelos direitos dele).
static func public_badge(p: Dictionary) -> String:
    var b := String(p.get("badge", ""))
    return b if b in BADGES else ""

## R41 · Título e moldura públicos de outro jogador (dados do servidor, já validados pelos direitos dele).
static func public_title(p: Dictionary) -> String:
    var t := String(p.get("title", ""))
    return t if t in TITLES else ""

static func public_frame(p: Dictionary) -> String:
    var f := String(p.get("frame", "liga"))
    return f if f in FRAMES else "liga"

