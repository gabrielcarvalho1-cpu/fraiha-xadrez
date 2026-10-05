extends Control
## R41 · RETRATO PÚBLICO de um jogador: avatar + moldura (Club / Fundador) + selo no canto.
## Usado onde OUTROS jogadores aparecem (faixa da partida, "adversário encontrado", cartão de perfil,
## mesa da MARCHA REAL / XEQUE online, convites). Os dados vêm do SERVIDOR (já filtrados pelos direitos
## do dono: Club vencido → sem moldura/selo do Club). Só aparência: não muda nada na partida.
##   info = {avatar_id, badge, frame, title, founder, club}; self_info(hub) monta o do próprio jogador.
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const ClubFrame := preload("res://monetization/club_frame.gd")

var hub
var info := {}
var mine := false             # retrato do próprio jogador (usa a foto/avatar local do hub)
var show_seal := true         # false onde o selo já aparece ao lado do nome (faixa da partida)
var avatar_rect: TextureRect
var frame_node: Control
var seal_rect: TextureRect
var _key := ""

static func make(owner_hub, data: Dictionary, side: float, is_self := false) -> Control:
    var p = load("res://profile/player_portrait.gd").new()
    p.hub = owner_hub
    p.mine = is_self
    p.custom_minimum_size = Vector2(side, side)
    p.size = Vector2(side, side)
    p.set_info(data)
    return p

## Identidade do próprio jogador no mesmo formato que o servidor manda para os outros.
static func self_info(owner_hub) -> Dictionary:
    if owner_hub == null or not owner_hub.has_method("current_badge"): return {}
    return {"badge": owner_hub.current_badge(), "title": owner_hub.current_title(), "frame": owner_hub.current_frame()}

func _init():
    name = "PlayerPortrait"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    var bg := Panel.new()
    bg.name = "PortraitBg"
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color("0c1712")
    sb.border_color = Color("5d6b58")
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(4)
    bg.add_theme_stylebox_override("panel", sb)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    avatar_rect = TextureRect.new()
    avatar_rect.name = "PortraitAvatar"
    avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    avatar_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    avatar_rect.clip_contents = true
    add_child(avatar_rect)
    seal_rect = TextureRect.new()
    seal_rect.name = "PortraitBadge"
    seal_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    seal_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    seal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    seal_rect.visible = false
    add_child(seal_rect)
    resized.connect(_place_seal)

func set_info(data: Dictionary):
    info = data.duplicate()
    var av := String(info.get("avatar_id", info.get("avatar", "")))
    var fr := public_frame()
    var bd := Cosmetics.public_badge(info)
    var key := "%s|%s|%s|%s|%s" % [av, fr, bd, mine, hub != null]
    if key == _key: return
    _key = key
    # avatar
    var tex: Texture2D = null
    if hub != null and hub.has_method("avatar_texture"):
        tex = hub.avatar_texture() if mine else (hub.avatar_texture(av) if not av.is_empty() else null)
        if tex == null: tex = hub.avatar_texture("warrior")
    avatar_rect.texture = tex
    # moldura premium (a "liga" fica com a borda simples do fundo)
    if fr == "club" or fr == "fundador":
        if frame_node == null:
            frame_node = ClubFrame.new()
            add_child(frame_node)
            move_child(frame_node, seal_rect.get_index())
        frame_node.style = fr
        frame_node.compact = custom_minimum_size.x < 60.0
        frame_node.visible = true
        frame_node.queue_redraw()
    elif frame_node != null:
        frame_node.visible = false
    # selo no canto inferior direito
    seal_rect.texture = Cosmetics.badge_texture(bd)
    seal_rect.visible = show_seal and seal_rect.texture != null
    _place_seal()

func public_frame() -> String:
    return Cosmetics.public_frame(info)

func _place_seal():
    var s := maxf(size.x, custom_minimum_size.x)
    var side := clampf(s * 0.42, 14.0, 40.0)
    seal_rect.size = Vector2(side, side)
    seal_rect.position = Vector2(s - side * 0.78, s - side * 0.78)
