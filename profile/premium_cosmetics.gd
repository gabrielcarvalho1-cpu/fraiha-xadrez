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
const TITLES := ["", "fundador", "club"]
const TITLE_TEXT := {"": "", "fundador": "Fundador do Reino", "club": "Membro do Club FRAIHA"}
## Molduras do retrato. "liga" = moldura da liga atual (padrão de todo jogador).
const FRAMES := ["liga", "club", "fundador"]
const FRAME_NAMES := {"liga": "Moldura da Liga", "club": "Moldura Club", "fundador": "Moldura Fundador"}

## Que direito cada item exige: "" (todos) | "founder" | "club".
static func requirement(kind: String, id: String) -> String:
    if id.is_empty() or id == "liga": return ""
    if id == "fundador": return "founder"
    if kind == "badge" and id.begins_with("club_"): return "club"
    if id == "club": return "club"
    return ""

static func allowed(kind: String, id: String, founder: bool, club: bool) -> bool:
    match requirement(kind, id):
        "founder": return founder
        "club": return club
    return true

static func lock_hint(kind: String, id: String) -> String:
    match requirement(kind, id):
        "founder": return "Exclusivo do Pacote Fundador"
        "club": return "Exclusivo do Club FRAIHA"
    return ""

## Escolha automática (preferência vazia): o melhor item que o jogador possui.
static func auto_badge(founder: bool, club: bool) -> String:
    if founder: return "fundador"
    if club: return "club_a"
    return ""

static func auto_title(founder: bool, club: bool) -> String:
    if founder: return "fundador"
    if club: return "club"
    return ""

static func auto_frame(founder: bool, club: bool) -> String:
    if club: return "club"          # comportamento das versões anteriores (Club = moldura dourada)
    if founder: return "fundador"
    return "liga"

## Preferência ("auto" = automático) → item efetivo, respeitando os direitos atuais.
static func effective(kind: String, pref: String, founder: bool, club: bool) -> String:
    if pref == "auto" or (kind == "frame" and pref.is_empty()):
        match kind:
            "badge": return auto_badge(founder, club)
            "title": return auto_title(founder, club)
            _: return auto_frame(founder, club)
    if not allowed(kind, pref, founder, club):
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
