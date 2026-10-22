extends CanvasLayer
## Chat da partida online (Casual e Ranked). Texto puro; o servidor valida, limita e distribui.
## Desktop: painel fixo ao lado do tabuleiro. Mobile: abre/fecha pelo botão "Chat".
## Silenciar é só local: este jogador deixa de ver as mensagens do adversário.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const MAX_LEN = 200
signal layout_needed
var account
var controller
var match_id := ""
var my_color := ""
var muted := false
var reported := false
var open_mobile := false
var unread := 0
var messages: Array = []
var panel: PanelContainer
var title: Label
var mute_button: Button
var report_button: Button
var close_button: Button
var scroll: ScrollContainer
var list: VBoxContainer
var input: LineEdit
var send_button: Button
var status: Label
var toggle_button: Button
var minimize_button: Button
var minimized := false   # desktop: chat recolhido num botão "CHAT"
var restore_button: Button
## R119 · EMOTES: os de graça + os comprados na Loja de Coroas (premium_cosmetics.shop_owned)
const ShopCatalog := preload("res://economy/crown_store_catalog.gd")
const Cosmetics := preload("res://profile/premium_cosmetics.gd")
const EmotePrefs := preload("res://social/emote_prefs.gd")      # R176
const EmoteBanner := preload("res://social/emote_banner.gd")    # R176
var emote_button: Button
var emote_row: HFlowContainer
var bubble_layer: Control
## R169 · CHAT CONTRA O COMPUTADOR (fase de testes): o mesmo chat e os mesmos EMOTES funcionam na partida contra
## o bot, só no aparelho (nada vai ao servidor). O bot responde com um emote de vez em quando.
var local_mode := false
var local_name := "Computador"
class LocalMarker extends RefCounted:
    pass

## R176 · campo vazio e sem foco: um cursor dourado pisca no começo do campo e a borda brilha de leve,
## para a pessoa ver onde digitar. Com foco, o cursor do próprio LineEdit assume.
class InputHint extends Control:
    var edit: LineEdit
    var _t := 0.0
    func _init():
        mouse_filter = Control.MOUSE_FILTER_IGNORE
    func _process(d):
        _t += d
        if is_visible_in_tree(): queue_redraw()
    func _draw():
        if edit == null or not edit.editable: return
        var empty := edit.text.is_empty()
        var focused := edit.has_focus()
        var pulse := 0.5 + 0.5 * sin(_t * TAU / 1.6)
        # borda: dourada suave (mais forte com foco)
        var bc := Color(0.96, 0.81, 0.50, (0.85 if focused else 0.28 + 0.22 * pulse))
        draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), bc, false, 2.0 if focused else 1.5)
        if empty and not focused and fmod(_t, 1.1) < 0.6:
            var sb := edit.get_theme_stylebox("normal")
            var x0: float = (sb.get_margin(SIDE_LEFT) if sb != null else 8.0) - 3.0
            var fs := edit.get_theme_font_size("font_size")
            var hh := clampf(fs * 1.05, 12.0, size.y - 10.0)
            draw_rect(Rect2(x0, (size.y - hh) / 2.0, 2.0, hh), Color("f4ce7f"))

func setup(service):
    account = service
    layer = 46
    account.server_message.connect(_on_message)
    panel = PanelContainer.new()
    panel.name = "MatchChat"
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var style = StyleBoxFlat.new()
    style.bg_color = Color(0.042, 0.075, 0.141, 0.88)
    style.border_color = Color("c99a45")
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    style.shadow_color = Color(0, 0, 0, 0.4)
    style.shadow_size = 8
    for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 12)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    var col = VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    panel.add_child(col)
    # R157.1 · os botões do topo quebram linha quando o painel é estreito (celular deitado: chat na coluna da direita)
    var head = HFlowContainer.new()
    head.add_theme_constant_override("h_separation", 6)
    head.add_theme_constant_override("v_separation", 6)
    col.add_child(head)
    title = Label.new()
    title.text = "CHAT"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.clip_text = true
    title.add_theme_color_override("font_color", GOLD)
    title.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
    head.add_child(title)
    emote_button = _small(head, "EMOTES", _toggle_emotes)
    emote_button.name = "ChatEmotes"
    emote_button.tooltip_text = "Reações rápidas (as da Loja de Coroas aparecem aqui depois de compradas)"
    mute_button = _small(head, "SILENCIAR", _toggle_mute)
    mute_button.tooltip_text = "Deixar de ver as mensagens do adversário (só para você)"
    report_button = _small(head, "DENUNCIAR", _report)
    report_button.tooltip_text = "Denunciar o adversário (chat e voz). A equipe recebe as mensagens dele para análise."
    close_button = _small(head, "FECHAR", func(): set_mobile_open(false))
    minimize_button = _small(head, "—", func(): set_minimized(true))
    minimize_button.tooltip_text = "Minimizar o chat"
    scroll = ScrollContainer.new()
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    col.add_child(scroll)
    list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 4)
    scroll.add_child(list)
    emote_row = HFlowContainer.new()
    emote_row.name = "EmoteRow"
    emote_row.add_theme_constant_override("h_separation", 6)
    emote_row.add_theme_constant_override("v_separation", 6)
    emote_row.hide()
    col.add_child(emote_row)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    status.add_theme_color_override("font_color", Color("ff9d86"))
    status.hide()
    col.add_child(status)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    col.add_child(row)
    input = LineEdit.new()
    input.name = "ChatInput"
    input.placeholder_text = "Digite sua mensagem…"
    input.max_length = MAX_LEN
    input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    input.text_submitted.connect(func(_t): send_current())
    # R176 · o campo não pode parecer apagado: cursor dourado piscando (também antes do clique) e dica mais clara
    input.caret_blink = true
    input.caret_blink_interval = 0.55
    input.add_theme_color_override("caret_color", GOLD)
    input.add_theme_constant_override("caret_width", 2)
    input.add_theme_color_override("font_placeholder_color", Color(0.93, 0.89, 0.80, 0.78))
    var hint := InputHint.new()
    hint.name = "InputHint"
    hint.edit = input
    hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    input.add_child(hint)
    row.add_child(input)
    # Web no celular: campo HTML real sobre o LineEdit para o teclado virtual abrir ao tocar.
    preload("res://ui_v022/web_text_field.gd").attach(input, true)   # R90 · barra de envio acima do teclado
    send_button = _small(row, "ENVIAR", send_current)
    send_button.name = "ChatSend"
    toggle_button = Button.new()
    toggle_button.name = "ChatToggle"
    toggle_button.text = "Chat"
    toggle_button.pressed.connect(func(): set_mobile_open(not open_mobile))
    # Desktop: com o chat minimizado, um botão "CHAT" dourado traz o painel de volta.
    restore_button = _small(self, "CHAT", func(): set_minimized(false))
    restore_button.name = "ChatRestore"
    restore_button.tooltip_text = "Abrir o chat"
    var rs: StyleBoxFlat = restore_button.get_theme_stylebox("normal").duplicate()
    rs.bg_color = Color(0.069, 0.119, 0.220, 0.92)
    rs.border_color = Color("c99a45")
    rs.set_border_width_all(2)
    rs.set_corner_radius_all(10)
    rs.shadow_color = Color(0, 0, 0, 0.45)
    rs.shadow_size = 6
    restore_button.add_theme_stylebox_override("normal", rs)
    var rh: StyleBoxFlat = rs.duplicate()
    rh.bg_color = Color(0.120, 0.196, 0.347, 0.95)
    rh.border_color = Color("f4ce7f")
    for state in ["hover", "pressed"]: restore_button.add_theme_stylebox_override(state, rh)
    restore_button.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
    restore_button.add_theme_color_override("font_color", GOLD)
    restore_button.add_theme_color_override("font_hover_color", Color("ffe6a0"))
    restore_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    restore_button.hide()
    panel.hide()

func _small(parent: Node, text: String, action: Callable) -> Button:
    var b = Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    var st = StyleBoxFlat.new()
    st.bg_color = Color("1c222f")
    st.border_color = Color("84754b")
    st.set_border_width_all(1)
    st.set_corner_radius_all(4)
    st.content_margin_left = 8
    st.content_margin_right = 8
    b.add_theme_stylebox_override("normal", st)
    var hi = st.duplicate()
    hi.bg_color = Color("333b4c")
    for state in ["hover", "pressed"]: b.add_theme_stylebox_override(state, hi)
    b.add_theme_color_override("font_color", Color("efe3c4"))
    b.pressed.connect(action)
    parent.add_child(b)
    return b

# ---------- Ciclo de vida ----------
func bind_local(bot_name: String, human_color: String):
    local_mode = true
    local_name = bot_name if not bot_name.is_empty() else "Computador"
    controller = LocalMarker.new()
    match_id = "local_%d" % Time.get_ticks_msec()
    my_color = human_color
    muted = false
    unread = 0
    messages.clear()
    _rebuild()
    status.hide()
    report_button.hide()
    mute_button.text = "SILENCIAR"
    open_mobile = false
    panel.show()
    _local_receive({"from_color": "b" if my_color == "w" else "w", "nickname": local_name, "text": "Boa partida! (chat de teste: só no seu aparelho)"})
    layout_needed.emit()

func _local_receive(m: Dictionary):
    var msg := m.duplicate()
    msg["type"] = "chat_msg"
    msg["match_id"] = match_id
    _on_message(msg)

## o que eu mando contra o bot: aparece na hora; o bot responde com um emote às vezes
func _local_post(text: String, emote_id := ""):
    var m := {"from_color": my_color, "nickname": "Você", "text": text}
    if not emote_id.is_empty(): m["emote"] = emote_id
    _local_receive(m)
    if randf() < (0.8 if not emote_id.is_empty() else 0.4):
        var mid := match_id
        var replies: Array = ShopCatalog.FREE_EMOTES
        var r: Dictionary = replies[randi() % replies.size()]
        get_tree().create_timer(1.4).timeout.connect(func():
            if local_mode and match_id == mid:
                _local_receive({"from_color": "b" if my_color == "w" else "w", "nickname": local_name, "text": String(r.text), "emote": String(r.id)}))

func bind(ranked_controller):
    local_mode = false
    report_button.show()
    controller = ranked_controller
    var new_id = String(controller.match_id)
    if new_id != match_id:
        match_id = new_id
        muted = false
        reported = false
        unread = 0
        messages.clear()
        _rebuild()
    my_color = String(controller.human_color)
    status.hide()
    mute_button.text = "SILENCIAR"
    report_button.disabled = reported
    report_button.text = "DENUNCIAR"
    open_mobile = false
    panel.show()
    _refresh_toggle()
    account.send_server({"type": "chat_sync", "match_id": match_id})

func unbind():
    controller = null
    local_mode = false
    open_mobile = false
    panel.hide()
    if restore_button != null: restore_button.hide()
    if input.has_focus(): input.release_focus()

func active() -> bool:
    return controller != null

# ---------- Envio ----------
func send_current():
    var text = input.text.strip_edges()
    if text.is_empty() or match_id.is_empty(): return
    if text.length() > MAX_LEN:
        _show_status("Mensagem longa demais (máx. %d caracteres)." % MAX_LEN)
        return
    if local_mode:
        _local_post(text)
        input.clear()
        return
    if account.send_server({"type": "chat_send", "match_id": match_id, "text": text}):
        input.clear()
        status.hide()
    else:
        _show_status("Sem conexão. Tente de novo em instantes.")

func _toggle_emotes():
    emote_row.visible = not emote_row.visible
    if emote_row.visible: _fill_emotes()

func _fill_emotes():
    for c in emote_row.get_children(): c.queue_free()
    if emote_row.top_level and not emote_row.has_meta("bg"):   # tabuleiro com arte (PC): abre por cima da lista, com fundo
        emote_row.set_meta("bg", true)
        emote_row.draw.connect(func(): emote_row.draw_rect(Rect2(Vector2(-6, -6), emote_row.size + Vector2(12, 12)), Color(0.03, 0.05, 0.10, 0.95)))
    for e in ShopCatalog.my_emotes(Cosmetics.shop_owned):
        var eid := String(e.id)
        var b := _small(emote_row, String(e.text), func(): send_emote(eid))
        b.name = "Emote_" + eid
        var fxi = preload("res://social/emote_fx.gd").make(eid, 30.0)   # R169 · prévia animada do emote no botão
        fxi.position = Vector2(6, 6)
        b.add_child(fxi)
        b.add_theme_font_override("font", preload("res://account/fonts/Cinzel-Bold.woff"))
        b.add_theme_font_size_override("font_size", 15 if Mobile.active(get_viewport()) else 18)
        b.custom_minimum_size.y = 42
        for pair in [["normal", 0.0], ["hover", 0.12], ["pressed", -0.1]]:   # botão azul com borda dourada (padrão do jogo)
            var st := StyleBoxFlat.new()
            st.bg_color = Color("16306a").lightened(maxf(0.0, pair[1])).darkened(maxf(0.0, -pair[1]))
            st.border_color = Color("c99a45") if pair[0] == "normal" else GOLD
            st.set_border_width_all(2)
            st.set_corner_radius_all(6)
            st.content_margin_left = 42
            st.content_margin_right = 12
            b.add_theme_stylebox_override(pair[0], st)
        b.add_theme_color_override("font_color", GOLD)
        b.add_theme_color_override("font_hover_color", Color("ffe6a0"))

func send_emote(id: String):
    if match_id.is_empty(): return
    if local_mode:
        var t := ""
        for e in ShopCatalog.my_emotes(Cosmetics.shop_owned):
            if String(e.id) == id: t = String(e.text)
        if not t.is_empty(): _local_post(t, id)
        emote_row.hide()
        return
    if account.send_server({"type": "chat_emote", "match_id": match_id, "id": id}):
        emote_row.hide()
        status.hide()
    else:
        _show_status("Sem conexão. Tente de novo em instantes.")

## R176 · faixa do emote (padrão da referência), pequena, AO LADO DA FOTO de quem mandou (2,5 s). Nunca no meio
## do tabuleiro. Desligado em Configurações/opções da partida → não aparece. Uma faixa por lado (a nova troca a antiga).
var avatar_rect: Callable   # (mine: bool) -> Rect2 da foto na tela (o stage liga; vazio = canto da tela)
var card_texts: Callable    # (mine: bool) -> [CanvasItem] textos do cartão que a faixa cobre (somem enquanto ela aparece)
func show_bubble(text: String, mine: bool, who: String, emote_id := ""):
    if not EmotePrefs.enabled(): return
    if bubble_layer == null:
        bubble_layer = Control.new()
        bubble_layer.name = "EmoteBubbles"
        bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bubble_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bubble_layer)
    var nm := "EmoteBubble_" + ("me" if mine else "opp")
    for c in bubble_layer.get_children():
        if c.name == nm or c.is_queued_for_deletion():
            bubble_layer.remove_child(c)
            c.queue_free()
    var vs := get_viewport().get_visible_rect().size
    var a := Rect2()
    if avatar_rect.is_valid(): a = avatar_rect.call(mine)
    var mob := Mobile.active(get_viewport())
    if not a.has_area():   # sem foto na tela: canto direito (em cima = adversário, embaixo = você)
        var s := 64.0 if mob else 84.0
        a = Rect2(Vector2(vs.x - s * 3.9, vs.y * (0.72 if mine else 0.1)), Vector2(s, s))
    var h := clampf(a.size.y * 0.86, 44.0, 84.0)   # menor que a foto: não cobre o relógio nem o tabuleiro
    var p: Control = EmoteBanner.make(text, "Você" if mine else who, emote_id, h)
    p.name = nm
    var w := p.size.x
    var x := a.end.x + 6.0
    if x + w > vs.x - 4.0: x = a.position.x - w - 6.0   # não cabe à direita: vai à esquerda da foto
    x = clampf(x, 4.0, maxf(4.0, vs.x - w - 4.0))
    # alinhada ao topo da foto: cobre o nome do cartão por inteiro (nada aparece "vazando" por cima da faixa)
    var y := clampf(a.position.y + a.size.y * 0.04, 4.0, maxf(4.0, vs.y - h - 4.0))
    p.position = Vector2(floorf(x), floorf(y))
    bubble_layer.add_child(p)
    p.pivot_offset = Vector2(0, h / 2.0)
    p.modulate.a = 0.0
    p.scale = Vector2(0.92, 0.92)
    # textos do cartão debaixo da faixa (nome, liga) somem enquanto ela está na tela: nada "vaza" por cima
    var under: Array = card_texts.call(mine) if card_texts.is_valid() else []
    for n in under:
        if is_instance_valid(n): n.self_modulate.a = 0.0
    p.tree_exiting.connect(func():
        for n in under:
            if is_instance_valid(n): n.self_modulate.a = 1.0)
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(p, "modulate:a", 1.0, 0.15)
    tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.chain().tween_interval(2.3)
    tw.chain().tween_property(p, "modulate:a", 0.0, 0.4)
    tw.chain().tween_callback(p.queue_free)

## Preferência mudou (Configurações / opções da partida): desligar some com as faixas na hora.
func emotes_pref_changed():
    if bubble_layer != null and not EmotePrefs.enabled():
        for c in bubble_layer.get_children(): c.queue_free()

func _toggle_mute():
    muted = not muted
    mute_button.text = "REATIVAR" if muted else "SILENCIAR"
    _rebuild()

func _report():
    if reported or match_id.is_empty(): return
    account.send_server({"type": "chat_report", "match_id": match_id})

# ---------- Mensagens do servidor ----------
func _on_message(msg: Dictionary):
    var type = String(msg.get("type", ""))
    if not type.begins_with("chat_") or String(msg.get("match_id", match_id)) != match_id: return
    match type:
        "chat_msg":
            messages.append(msg)
            if messages.size() > 80: messages.pop_front()
            if not (muted and String(msg.get("from_color", "")) != my_color):
                _add_line(msg)
                if msg.has("emote"):   # R119
                    show_bubble(String(msg.get("text", "")), String(msg.get("from_color", "")) == my_color, String(msg.get("nickname", "")), String(msg.get("emote", "")))
                if String(msg.get("from_color", "")) != my_color and not _visible_now():
                    unread += 1
                    _refresh_toggle()
        "chat_history":
            messages = Array(msg.get("messages", [])) if msg.get("messages") is Array else []
            _rebuild()
        "chat_error":
            _show_status(String(msg.get("message", "Não foi possível enviar.")))
        "chat_report_ok":
            reported = true
            report_button.disabled = true
            report_button.text = "DENUNCIADO"
            _show_status("Denúncia enviada. Obrigado!", Color("c4cbbd"))

func _visible_now() -> bool:
    if Mobile.active(get_viewport()): return panel.visible and open_mobile
    return panel.visible and not minimized

func _show_status(text: String, color := Color("ff9d86")):
    status.text = text
    status.add_theme_color_override("font_color", color)
    status.show()

func _rebuild():
    for child in list.get_children():
        list.remove_child(child)
        child.queue_free()
    var hidden = 0
    for m in messages:
        if muted and String(m.get("from_color", "")) != my_color:
            hidden += 1
            continue
        _add_line(m, false)
    if muted:
        var note = Label.new()
        note.text = "Adversário silenciado (%d mensagem(ns) oculta(s))." % hidden
        note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        note.add_theme_color_override("font_color", Color("a9b2a4"))
        list.add_child(note)
    _scroll_end()

func _add_line(m: Dictionary, scroll_now := true):
    var mine = String(m.get("from_color", "")) == my_color
    var line = Label.new()
    # Label comum (sem BBCode): o texto do jogador nunca vira formatação.
    line.text = "%s: %s" % [("Você" if mine else String(m.get("nickname", "Adversário"))), String(m.get("text", ""))]
    if m.has("emote"):   # R119 · emote: destacado em azul claro, entre aspas
        line.text = "%s: “%s”" % [("Você" if mine else String(m.get("nickname", "Adversário"))), String(m.get("text", ""))]
        line.add_theme_color_override("font_color", Color("bcd4ff"))
        line.set_meta("emote", true)
    line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if not line.has_meta("emote"): line.add_theme_color_override("font_color", GOLD if mine else Color("efe3c4"))
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    list.add_child(line)
    if scroll_now: _scroll_end()

func _scroll_end():
    await get_tree().process_frame
    if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# ---------- Layout ----------
func set_minimized(value: bool):
    minimized = value
    if value:
        if input.has_focus(): input.release_focus()
    else:
        unread = 0
    _refresh_toggle()
    layout_needed.emit()

func set_mobile_open(value: bool):
    open_mobile = value
    if value:
        unread = 0
    elif input.has_focus():
        input.release_focus()
    _refresh_toggle()
    layout_needed.emit()

func _refresh_toggle():
    var t := ("CHAT (%d)" % unread) if unread > 0 else "CHAT"
    toggle_button.text = t
    if restore_button != null: restore_button.text = t

## Desktop: painel à esquerda do tabuleiro (coordenadas 1920x1080). Mobile: folha sobre a parte de baixo.
func layout(board: Rect2, mobile: bool, safe: Rect2):
    if not active():
        panel.hide()
        restore_button.hide()
        return
    var fonts = 15 if mobile else 20
    for node in [title, emote_button, mute_button, report_button, close_button, input, send_button, status]:
        node.add_theme_font_size_override("font_size", fonts)
    for child in list.get_children(): child.add_theme_font_size_override("font_size", fonts)
    # R123 · celular: os 4 botões do topo cabem na largura (antes FECHAR e ENVIAR saíam cortados da tela)
    for node in [emote_button, mute_button, report_button, close_button, send_button]:
        node.add_theme_font_size_override("font_size", 12 if mobile else fonts)
        for stn in ["normal", "hover", "pressed"]:
            var sb = node.get_theme_stylebox(stn)
            if sb != null:
                sb.content_margin_left = 5 if mobile else 8
                sb.content_margin_right = 5 if mobile else 8
    close_button.visible = mobile
    title.visible = not mobile   # R119 · celular: sem espaço para o título com EMOTES na mesma linha (o painel já é o chat)
    minimize_button.visible = not mobile
    input.custom_minimum_size.y = 44 if mobile else 48
    send_button.custom_minimum_size = Vector2(0, 44 if mobile else 48)
    if mobile:
        restore_button.hide()
        panel.visible = open_mobile
        var h = minf(safe.size.y * 0.62, 460.0)
        panel.position = Vector2(safe.position.x, safe.end.y - h - 52.0)
        panel.size = Vector2(safe.size.x, h)
        return
    # Desktop minimizado: só o botão CHAT no canto do tabuleiro.
    restore_button.visible = minimized
    if minimized:
        panel.visible = false
        restore_button.add_theme_font_size_override("font_size", 20)
        restore_button.size = Vector2(170, 52)
        restore_button.position = Vector2(maxf(safe.position.x + 8.0, board.position.x - 190.0), board.end.y - 52.0)
        return
    panel.visible = true
    var left_space = board.position.x - safe.position.x - 36.0
    if left_space >= 260.0:
        var width = minf(440.0, left_space)
        panel.position = Vector2(board.position.x - width - 28.0, board.position.y)
        panel.size = Vector2(width, board.size.y)
        return
    # Tela estreita/quadrada: usa a faixa abaixo (ou acima) do tabuleiro.
    var below = safe.end.y - board.end.y - 90.0
    var above = board.position.y - safe.position.y - 16.0
    var h = maxf(below, above)
    panel.size = Vector2(minf(board.size.x, 560.0), clampf(h, 120.0, 320.0))
    panel.position = Vector2(board.get_center().x - panel.size.x / 2.0, (board.end.y + 12.0) if below >= above else (board.position.y - panel.size.y - 8.0))
