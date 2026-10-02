extends GridContainer
## R32 · Galeria de ÍCONES (selos) do Perfil — separada da galeria de avatares.
## Ícone ≠ avatar: o ícone é o selo ao lado do nome (Fundador / Club). Tocar num ícone só o INSPECIONA;
## quem aplica é o botão APLICAR ÍCONE da área de detalhe (main_hub / mobile_hub).
signal inspected(id: String)

const Cosmetics = preload("res://profile/premium_cosmetics.gd")
const Gallery = preload("res://profile/avatar_gallery.gd")
const GOLD := Color("ffd98a")
const MUTED := Color("9c9886")
const EMERALD := Color("49d17a")
const OPTIONS := ["auto", "", "fundador", "club_a", "club_b", "club_c"]

var hub
var card_size := Vector2(128, 166)
var cards := {}
var focus_id := ""

func setup(p_hub, p_columns: int, p_card: Vector2):
    hub = p_hub
    columns = p_columns
    card_size = p_card
    add_theme_constant_override("h_separation", 10)
    add_theme_constant_override("v_separation", 10)
    for c in get_children():
        remove_child(c)
        c.queue_free()
    cards.clear()
    for id in OPTIONS:
        var card := BadgeCard.new()
        card.gallery = self
        card.badge = id
        card.custom_minimum_size = card_size
        card.pressed.connect(func():
            focus_id = id
            update_states()
            inspected.emit(id))
        add_child(card)
        cards[id] = card
        Cosmetics.badge_texture(id, false)   # carrega antes do 1º desenho (senão sai o quadrado provisório)
    update_states()
    update_states.call_deferred()

func update_states():
    for id in cards: cards[id].queue_redraw()

static func display_name(id: String) -> String:
    if id == "auto": return "Automático"
    return String(Cosmetics.BADGE_NAMES.get(id, id))

func unlocked(id: String) -> bool:
    if hub == null: return false
    if id == "auto" or id.is_empty(): return true
    return Cosmetics.allowed("badge", id, hub.is_founder(), hub.club_active())

## "selected" (é a preferência atual) | "unlocked" | "locked"
func state_of(id: String) -> String:
    if not unlocked(id): return "locked"
    return "selected" if hub != null and String(hub.cosmetic_pref("badge")) == id else "unlocked"

func hint(id: String) -> String:
    return Cosmetics.lock_hint("badge", id)

class BadgeCard extends Button:
    var gallery
    var badge := ""
    func _init():
        flat = true
        focus_mode = Control.FOCUS_ALL
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for s in ["normal", "hover", "pressed", "focus", "disabled"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
    func _ready():
        mouse_entered.connect(queue_redraw)
        mouse_exited.connect(queue_redraw)
        resized.connect(queue_redraw)
    func _draw():
        if gallery == null: return
        var st: String = gallery.state_of(badge)
        var focused: bool = gallery.focus_id == badge
        var r := Rect2(Vector2.ZERO, size)
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("10241a") if st != "locked" else Color("0c1511")
        sb.set_corner_radius_all(6)
        sb.set_border_width_all(3 if st == "selected" or focused else 2)
        sb.border_color = EMERALD if st == "selected" else (Color("fff0b8") if focused else (GOLD if st == "unlocked" else Color("3a4038")))
        if st == "selected":
            sb.shadow_color = Color(0.3, 0.9, 0.5, 0.45)
            sb.shadow_size = 10
        elif is_hovered() or focused:
            sb.shadow_color = Color(1.0, 0.85, 0.45, 0.30)
            sb.shadow_size = 6
        draw_style_box(sb, r)
        var side := minf(size.x - 16.0, size.y - 46.0)
        var pr := Rect2(Vector2((size.x - side) / 2.0, 8), Vector2(side, side))
        var tex: Texture2D = Cosmetics.badge_texture(badge, false) if not (badge in ["auto", ""]) else null
        if tex != null:
            draw_texture_rect(tex, pr, false, Color(0.45, 0.45, 0.45, 0.9) if st == "locked" else Color.WHITE)
        else:
            var c := pr.get_center()
            draw_circle(c, side * 0.30, Color("0a120e"))
            draw_arc(c, side * 0.30, 0, TAU, 40, GOLD if badge == "auto" else MUTED, 2.0)
            var f0 := get_theme_default_font()
            draw_string(f0, c + Vector2(-side * 0.3, 6), "AUTO" if badge == "auto" else "—", HORIZONTAL_ALIGNMENT_CENTER, side * 0.6, 16, GOLD if badge == "auto" else MUTED)
        if st == "locked":
            var lc := pr.position + Vector2(pr.size.x - 16, 16)
            draw_circle(lc, 13, Color(0, 0, 0, 0.7))
            draw_arc(lc + Vector2(0, -3), 5.0, PI, TAU, 12, Color("e6d6a8"), 2.0)
            draw_rect(Rect2(lc + Vector2(-6, -2), Vector2(12, 9)), Color("e6d6a8"))
        var font := get_theme_default_font()
        var title: String = gallery.display_name(badge).to_upper()
        var fs := 13
        while fs > 9 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 8: fs -= 1
        var y := pr.end.y + 16
        draw_string(font, Vector2(4, y), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, fs, GOLD if st != "locked" else MUTED)
        var sub: String = {"locked": "BLOQUEADO", "selected": "EM USO", "unlocked": "Disponível"}[st]
        draw_string(font, Vector2(4, y + 15), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 11, Color("e89a7a") if st == "locked" else (EMERALD if st == "selected" else MUTED))
        tooltip_text = title + ("  ·  BLOQUEADO · " + gallery.hint(badge) if st == "locked" else "")
