extends CanvasLayer
## R37 · CARTÃO DE PERFIL durante a partida (Ranked, Casual online, Marcha Real e Xeque).
## Passar o mouse (ou tocar, no celular) no avatar/placa de um jogador abre este cartão ao lado:
## foto, nome, selo, o placar NAQUELE modo (vitórias, derrotas, % de vitória e % de derrota) e o botão
## ADICIONAR AMIGO. Tudo vem do servidor (social_card); o cliente só mostra. Bots: cartão de bot, sem placar.
##
## Uso (qualquer modo):  stage.profile_popup.hover(key, info, rect_tela)   →  abre depois de um instante
##                       stage.profile_popup.unhover(key)                  →  fecha (se o mouse não entrou no cartão)
##                       stage.profile_popup.toggle(key, info, rect_tela)  →  toque no celular
## info = {"user_id", "name", "bot": bool, "avatar": Texture2D, "mode": "ranked_5min"|"casual"|"marcha"|"xeque",
##         "mode_label": "MARCHA REAL", "subtitle": "RUBI · ALIADO"}
const GOLD := Color("f4ce7f")
const CREAM := Color("f4edda")
const MUTED := Color("c4cbbd")
const WIN := Color("6fd58b")
const LOSS := Color("ef5a5a")
const OPEN_DELAY := 0.22
const CLOSE_DELAY := 0.35
const SIZE := Vector2(360, 258)
const FONT := preload("res://marcha/art/fonts/oswald-latin-600-normal.woff")
const FONT_B := preload("res://marcha/art/fonts/oswald-latin-700-normal.woff")
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const ClubFrame := preload("res://monetization/club_frame.gd")

var account                       # account_service (social_card / social_request / social_accept)
var view: Control
var info := {}
var key := ""
var card := {}                    # resposta do servidor
var state := "idle"               # idle | loading | ready | missing | offline | guest
var notice := ""
var anchor := Rect2()
var _want_key := ""
var _want_info := {}
var _want_rect := Rect2()
var _open_in := -1.0
var _close_in := -1.0
var _btn := Rect2()
var _inside := false
var _frame_node: Control          # R41 · moldura Club/Fundador sobre a foto
var _seal_node: TextureRect       # R41 · selo no canto da foto

func _init():
    layer = 96
    name = "ProfilePopup"

func _ready():
    view = Control.new()
    view.name = "ProfileCard"
    view.size = SIZE
    view.mouse_filter = Control.MOUSE_FILTER_STOP
    view.visible = false
    view.draw.connect(_draw_card)
    view.gui_input.connect(_on_input)
    view.mouse_entered.connect(func(): _inside = true; _close_in = -1.0)
    view.mouse_exited.connect(func(): _inside = false; _close_in = CLOSE_DELAY)
    add_child(view)

func bind(acc):
    account = acc
    if account != null and account.has_signal("server_message"): account.server_message.connect(_on_message)

func is_open() -> bool:
    return view != null and view.visible

# ---------------------------------------------------------------- abrir / fechar
func hover(k: String, p_info: Dictionary, rect: Rect2):
    _close_in = -1.0
    if is_open() and k == key: return
    if k == _want_key and _open_in >= 0.0: return
    _want_key = k
    _want_info = p_info
    _want_rect = rect
    _open_in = OPEN_DELAY

func unhover(k: String):
    if k == _want_key: _open_in = -1.0
    if is_open() and k == key and not _inside: _close_in = CLOSE_DELAY

var _last_toggle_key := ""
var _last_toggle_ms := -100000

func toggle(k: String, p_info: Dictionary, rect: Rect2):
    # R46 · no celular UM toque chega duas vezes (InputEventScreenTouch + clique emulado do mouse):
    # sem isso o cartão abria e fechava no mesmo toque ("toco na foto e nada acontece").
    var now := Time.get_ticks_msec()
    if k == _last_toggle_key and now - _last_toggle_ms < 350: return
    _last_toggle_key = k
    _last_toggle_ms = now
    if is_open() and k == key:
        close()
        return
    show_card(k, p_info, rect)

func close():
    _open_in = -1.0
    _close_in = -1.0
    _want_key = ""
    key = ""
    if view != null: view.visible = false

func show_card(k: String, p_info: Dictionary, rect: Rect2):
    key = k
    info = p_info
    anchor = rect
    card = {}
    notice = ""
    var uid := String(info.get("user_id", ""))
    if bool(info.get("bot", false)) or uid.is_empty(): state = "bot" if bool(info.get("bot", false)) else "missing"
    elif account == null or not account.has_profile(): state = "guest"
    elif account.send_server({"type": "social_card", "user_id": uid, "mode": String(info.get("mode", ""))}): state = "loading"
    else: state = "offline"
    _place()
    view.visible = true
    view.queue_redraw()

## Ao lado do avatar, sempre dentro da tela.
func _place():
    var vs: Vector2 = get_viewport().get_visible_rect().size
    var s := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.75, 1.6)
    view.scale = Vector2(s, s)
    var w := SIZE * s
    var p := Vector2(anchor.end.x + 10, anchor.position.y)
    if p.x + w.x > vs.x - 8: p.x = anchor.position.x - w.x - 10
    if p.x < 8: p.x = clampf(anchor.get_center().x - w.x / 2.0, 8, vs.x - w.x - 8)
    if p.x < 8 or (anchor.position.x - w.x - 10 < 8 and anchor.end.x + 10 + w.x > vs.x - 8):
        p = Vector2(clampf(anchor.get_center().x - w.x / 2.0, 8, vs.x - w.x - 8), anchor.end.y + 8)
    p.y = clampf(p.y, 8, vs.y - w.y - 8)
    view.position = p

func _process(delta):
    if _open_in >= 0.0:
        _open_in -= delta
        if _open_in < 0.0: show_card(_want_key, _want_info, _want_rect)
    if _close_in >= 0.0:
        _close_in -= delta
        if _close_in < 0.0 and not _inside: close()
    if is_open() and state == "loading": view.queue_redraw()

# ---------------------------------------------------------------- servidor
func _on_message(msg: Dictionary):
    var t := String(msg.get("type", ""))
    var uid := String(info.get("user_id", ""))
    if t == "social_card" and String(msg.get("user_id", "")) == uid and is_open():
        if bool(msg.get("missing", false)): state = "missing"
        else:
            card = msg.get("card", {}) if msg.get("card") is Dictionary else {}
            state = "ready"
        view.queue_redraw()
    elif t == "social_ok" and String(msg.get("user_id", "")) == uid and is_open():
        card["relation"] = String(msg.get("relation", card.get("relation", "")))
        notice = "Pedido de amizade enviado!" if card.relation == "request_sent" else ("Agora vocês são amigos!" if card.relation == "friend" else "")
        view.queue_redraw()
    elif t == "social_error" and is_open() and state in ["loading", "ready"]:
        if state == "loading":
            state = "guest" if String(msg.get("code", "")) == "auth_required" else "offline"
        notice = String(msg.get("message", ""))
        view.queue_redraw()

func _on_input(event: InputEvent):
    var pos := Vector2.INF
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
    elif event is InputEventScreenTouch and event.pressed: pos = event.position
    if pos == Vector2.INF: return
    view.accept_event()
    if _btn.has_point(pos): press_button()

## Botão do cartão: ADICIONAR AMIGO / ACEITAR PEDIDO.
func press_button():
    if state != "ready" or account == null: return
    var rel := String(card.get("relation", ""))
    var uid := String(info.get("user_id", ""))
    if rel == "none": account.send_server({"type": "social_request", "user_id": uid})
    elif rel == "request_received": account.send_server({"type": "social_accept", "user_id": uid})

func button_label() -> String:
    if state != "ready": return ""
    match String(card.get("relation", "")):
        "none": return "ADICIONAR AMIGO"
        "request_sent": return "PEDIDO ENVIADO"
        "request_received": return "ACEITAR PEDIDO"
        "friend": return "AMIGOS ✓"
        "self": return "VOCÊ"
    return ""

## Placar do modo: {"wins","losses","draws","win_pct","loss_pct","games"} ou {} se não houver.
func stats_line() -> Dictionary:
    if state != "ready" or not bool(card.get("stats_ready", false)) or not (card.get("stats") is Dictionary): return {}
    var s: Dictionary = card.stats
    var w := int(s.get("wins", 0))
    var l := int(s.get("losses", 0))
    var d := int(s.get("draws", 0))
    var n := w + l + d
    return {"wins": w, "losses": l, "draws": d, "games": n,
        "win_pct": roundi(100.0 * w / n) if n > 0 else 0, "loss_pct": roundi(100.0 * l / n) if n > 0 else 0}

# ---------------------------------------------------------------- desenho
func _txt(s: String, p: Vector2, fs: int, col: Color, bold := false, w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT):
    view.draw_string(FONT_B if bold else FONT, p, s, align, w, fs, col)

func _height() -> float:
    return SIZE.y if (not button_label().is_empty() or not stats_line().is_empty() or not notice.is_empty()) else 178.0

func _draw_card():
    view.size = Vector2(SIZE.x, _height())
    var r := Rect2(Vector2.ZERO, view.size)
    view.draw_rect(r.grow(4), Color(0, 0, 0, 0.45))
    view.draw_rect(r, Color("0d241a"))
    view.draw_rect(r, GOLD, false, 2.0)
    view.draw_rect(r.grow(-5), Color(0.85, 0.7, 0.37, 0.35), false, 1.0)
    # foto
    var pr := Rect2(16, 16, 72, 72)
    view.draw_rect(pr.grow(3), Color("2a1a05"))
    var tex: Texture2D = info.get("avatar", null)
    if tex != null: view.draw_texture_rect(tex, pr, false)
    else: view.draw_rect(pr, Color("17382a"))
    view.draw_rect(pr.grow(1), GOLD, false, 2.0)
    _decorate_photo.call_deferred(pr)   # mexe em nós filhos: fora do desenho
    var name := String(card.get("nickname", info.get("name", "")))
    _txt(name, Vector2(102, 44), 26, CREAM, true, SIZE.x - 114)
    var sub := String(info.get("subtitle", ""))
    if state == "bot": sub = "BOT DO FRAIHA" + ((" · " + sub) if not sub.is_empty() else "")
    elif not Cosmetics.public_title(card).is_empty(): sub = Cosmetics.title_text(Cosmetics.public_title(card)).to_upper() + ((" · " + sub) if not sub.is_empty() else "")
    _txt(sub, Vector2(102, 70), 14, GOLD, false, SIZE.x - 114)
    var ml := String(info.get("mode_label", ""))
    _txt(("PLACAR · " + ml) if not ml.is_empty() else "PLACAR", Vector2(16, 116), 14, MUTED, true)
    var st := stats_line()
    if not st.is_empty():
        _txt("%d VITÓRIAS" % st.wins, Vector2(16, 142), 20, WIN, true)
        _txt("%d DERROTAS" % st.losses, Vector2(180, 142), 20, LOSS, true)
        # barra vitória / derrota
        var bar := Rect2(16, 152, SIZE.x - 32, 10)
        view.draw_rect(bar, Color("2b3a33"))
        if st.games > 0:
            view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * st.win_pct / 100.0, bar.size.y)), WIN)
            view.draw_rect(Rect2(bar.position + Vector2(bar.size.x * (1.0 - st.loss_pct / 100.0), 0), Vector2(bar.size.x * st.loss_pct / 100.0, bar.size.y)), LOSS)
        var pct := "%d%% de vitória · %d%% de derrota" % [st.win_pct, st.loss_pct] if st.games > 0 else "Ainda sem partidas neste modo"
        if st.draws > 0: pct += " · %d empate%s" % [st.draws, "s" if st.draws > 1 else ""]
        _txt(pct, Vector2(16, 182), 15, CREAM)
    else:
        var why := ""
        match state:
            "loading": why = "Carregando" + ".".repeat(1 + int(Time.get_ticks_msec() / 300) % 3)
            "bot": why = "Bots não têm placar nem lista de amigos."
            "guest": why = "Entre na sua conta para ver o placar e adicionar amigos."
            "offline": why = "Sem conexão com o servidor agora."
            "missing": why = "Perfil indisponível."
            _: why = "Placar deste modo ainda não disponível."
        _txt(why, Vector2(16, 146), 15, CREAM, false, SIZE.x - 32)
    # botão
    _btn = Rect2()
    var bl := button_label()
    if not bl.is_empty():
        var active := bl in ["ADICIONAR AMIGO", "ACEITAR PEDIDO"]
        _btn = Rect2(16, SIZE.y - 46, SIZE.x - 32, 34)
        view.draw_rect(_btn, Color("e9b23a") if active else Color("173a2a"))
        view.draw_rect(_btn, GOLD if active else Color("4c6b58"), false, 1.5)
        _txt(bl, Vector2(_btn.position.x, _btn.position.y + 24), 18, Color("2a1a04") if active else MUTED, true, _btn.size.x, HORIZONTAL_ALIGNMENT_CENTER)
    if not notice.is_empty():
        _txt(notice, Vector2(16, SIZE.y - 54), 13, Color("9fe0a8") if notice.begins_with("Pedido") or notice.begins_with("Agora") else LOSS, false, SIZE.x - 32)

## R41 · Moldura (Club / Fundador) e selo do jogador sobre a foto do cartão. Vêm do servidor (card),
## já filtrados pelos direitos dele; antes da resposta usa o que a partida já sabe (info).
func _decorate_photo(pr: Rect2):
    var src: Dictionary = card if not card.is_empty() else info
    var fr := "liga" if state == "bot" else Cosmetics.public_frame(src)
    if fr == "club" or fr == "fundador":
        if _frame_node == null:
            _frame_node = ClubFrame.new()
            _frame_node.fill_parent = false
            _frame_node.name = "CardFrame"
            view.add_child(_frame_node)
        _frame_node.position = pr.position
        _frame_node.size = pr.size
        _frame_node.style = fr
        _frame_node.visible = true
    elif _frame_node != null:
        _frame_node.visible = false
    var tex := Cosmetics.badge_texture("" if state == "bot" else Cosmetics.public_badge(src))
    if _seal_node == null:
        _seal_node = TextureRect.new()
        _seal_node.name = "CardBadge"
        _seal_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _seal_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _seal_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
        view.add_child(_seal_node)
    _seal_node.texture = tex
    _seal_node.visible = tex != null
    _seal_node.size = Vector2(32, 32)
    _seal_node.position = pr.end - Vector2(24, 24)
    if _frame_node != null: view.move_child(_seal_node, view.get_child_count() - 1)

