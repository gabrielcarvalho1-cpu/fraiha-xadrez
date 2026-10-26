extends CanvasLayer
## Telas de conta (entrar, criar conta, Google, recuperar senha, nickname).
## Apenas coleta dados e chama AccountService; não guarda senha.
## Visual: a arte de referência aprovada (account/art/login_art.png — moldura, cavalos, brasão,
## estandartes, campos, botões e links) é a própria tela de ENTRAR; os controles interativos
## ficam exatamente sobre os elementos pintados. As outras páginas usam a mesma moldura sem o
## interior (login_art_blank.png) com os componentes recortados da arte (login_skin.gd).
signal closed
signal guest_chosen   # R181 · tocou em JOGAR COMO CONVIDADO
signal ready_for_ranked
const Mobile = preload("res://ui_v022/mobile_layout.gd")
const GOLD = Color("f4ce7f")
const Art = preload("res://account/login_art.gd")
const LoginSkin = preload("res://account/login_skin.gd")
const WebTextField = preload("res://ui_v022/web_text_field.gd")
## R87 · memória: as duas artes do login (6 MB cada) só ficam carregadas enquanto a tela de conta está aberta
const ART_FULL_PATH := "res://account/art/login_art.png"
const ART_BLANK_PATH := "res://account/art/login_art_blank.png"
const REF := Vector2(1122, 1402)            # tamanho da arte de referência
const INNER := Rect2(196, 430, 738, 825)    # interior útil (abaixo da faixa do título)
const TITLE_BAND := Rect2(222, 300, 678, 90)
const BODY_W := 1002.0                       # largura do corpo do painel na arte
# Posições dos elementos já pintados na arte de ENTRAR (coords da referência)
const SLOT_EMAIL := Rect2(196, 445, 738, 120)
const SLOT_PASSWORD := Rect2(196, 560, 738, 120)
const SLOT_ENTER := Rect2(196, 688, 738, 150)
const SLOT_GOOGLE := Rect2(196, 846, 738, 104)
const SLOT_LINKS := [Rect2(290, 993, 550, 72), Rect2(290, 1065, 550, 72), Rect2(290, 1138, 550, 72)]   # PC (congelado)
## R181 · JOGAR COMO CONVIDADO é o botão PRINCIPAL (7 de 13 pessoas do anúncio saíram nesta tela sem tocar em nada):
## placa azul do próprio jogo (a mesma do ENTRAR) com brilho dourado, por cima das 2 primeiras linhas de links;
## "Criar conta" e "Esqueci minha senha" ficam menores, lado a lado, na última linha. A arte não muda.
const SLOT_GUEST := Rect2(196, 986, 738, 144)
const SLOT_SMALL := [Rect2(228, 1140, 268, 66), Rect2(500, 1140, 272, 66)]   # seta pintada em x≈795
const SLOT_STATUS := Rect2(230, 1212, 662, 40)

var account
var open_legal: Callable          # R97 · abre TERMOS E PRIVACIDADE (hub.open_legal)
var dim: ColorRect
var scroll: ScrollContainer
var panel: Control            # escala = k; filhos em coordenadas da referência
var art: TextureRect
var box: VBoxContainer        # páginas secundárias (também guarda labels para testes)
var title_label: Label
var status_label: Label
var page := ""
var message := ""
var return_to_ranked := false
var fields := {}
var k := 1.0
var frame                      # compat: antes era a moldura desenhada; hoje aponta para `art`

func setup(service):
    account = service
    layer = 60
    preload("res://ui_v022/esc_stack.gd").register(self)   # R129 · ESC em tudo
    dim = ColorRect.new()
    dim.name = "AccountDim"
    dim.color = Color(0.029, 0.038, 0.057, 0.78)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)
    scroll = ScrollContainer.new()
    scroll.name = "AccountScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    preload("res://ui_v022/touch_scroll.gd").attach(scroll)
    add_child(scroll)
    var holder := Control.new()      # ocupa o tamanho da arte escalada para o scroll medir
    holder.name = "AccountHolder"
    holder.mouse_filter = Control.MOUSE_FILTER_PASS
    scroll.add_child(holder)
    panel = Control.new()
    panel.name = "AccountPanel"
    panel.size = REF
    panel.mouse_filter = Control.MOUSE_FILTER_PASS
    holder.add_child(panel)
    art = TextureRect.new()
    art.name = "LoginArt"
    art.texture = null
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_SCALE
    art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    art.size = REF
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(art)
    frame = art
    title_label = Label.new()
    title_label.name = "Title"
    title_label.position = TITLE_BAND.position
    title_label.size = TITLE_BAND.size
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title_label.add_theme_font_override("font", Art.FONT_BOLD)
    title_label.add_theme_font_size_override("font_size", 62)
    title_label.add_theme_color_override("font_color", Color("f3d58c"))
    title_label.add_theme_color_override("font_outline_color", Color("3a2408"))
    title_label.add_theme_constant_override("outline_size", 8)
    title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
    title_label.add_theme_constant_override("shadow_offset_y", 4)
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(title_label)
    box = VBoxContainer.new()
    box.name = "AccountBox"
    box.position = INNER.position + Vector2(0, 16)
    box.size = Vector2(INNER.size.x, INNER.size.y - 16)
    box.add_theme_constant_override("separation", 18)
    panel.add_child(box)
    status_label = _make_status()
    panel.add_child(status_label)
    account.changed.connect(_on_account_changed)
    account.notice.connect(_on_notice)
    account.recovery_started.connect(func(): open("new_password"))
    account.google_blocked.connect(func(app, os_name): inapp_app = app; inapp_os = os_name; open("inapp"))   # R181
    get_viewport().size_changed.connect(_layout)
    hide_ui()

func is_open() -> bool:
    return dim.visible

## R129 · ESC = o "Voltar" da página (criar conta/esqueci a senha → Entrar; definir senha → Sua conta);
## o nome de jogador é obrigatório (ESC não pula); no resto, fecha como CONTINUAR / Jogar como convidado.
func esc_open() -> bool:
    return is_open()

func esc_close():
    match page:
        "signup", "recover": _show("login")
        "set_password": _show("account")
        "nickname": pass
        _: close()

func open(target := "", info := "", for_ranked := false):
    return_to_ranked = for_ranked
    message = info
    if target.is_empty(): target = _natural_page()
    _show(target)
    dim.show(); scroll.show()
    _layout()

func hide_ui():
    dim.hide(); scroll.hide()
    if is_instance_valid(art): art.texture = null   # R87 · solta a arte do login

## R181 · convidado: conecta ao servidor JÁ no clique (antes só conectava ao abrir o Online Casual, e o convidado
## que jogava contra bots nunca aparecia no Admin → Sessões).
## R181 · REGRA DO DONO: mudança de visual/letra/botão só no celular (web mobile e app). PC congelado.
func _mobile() -> bool:
    return is_inside_tree() and Mobile.active(get_viewport())

func _fx_teste_convidado():
    if dim.visible: play_as_guest()

func play_as_guest():
    preload("res://telemetry/web_track.gd").login("guest", "start")
    preload("res://telemetry/web_track.gd").pixel("EntrouConvidado")
    if account != null:
        account.ensure_online(true)
    guest_chosen.emit()
    close()

func close():
    hide_ui()
    closed.emit()

func _natural_page() -> String:
    if not account.configured(): return "unavailable"
    if not account.signed_in(): return "login"
    if not account.server_ready: return "waiting"
    if account.needs_nickname: return "nickname"
    return "account"

func _on_account_changed():
    if not is_open(): return
    if account.has_profile() and return_to_ranked:
        return_to_ranked = false
        hide_ui()
        ready_for_ranked.emit()
        return
    if account.has_profile() and page in ["login", "signup", "nickname", "waiting"]:
        close()
        return
    var natural = _natural_page()
    if page in ["login", "signup", "nickname", "account", "waiting"] and natural != page:
        _show("waiting" if account.signed_in() and not account.server_ready else natural)
    elif page == "waiting" and account.server_ready:
        _show(natural)

func _on_notice(text: String, is_error: bool):
    if not is_open(): return
    status_label.text = text
    status_label.add_theme_color_override("font_color", Color("ff9d86") if is_error else Color("b9e3a6"))

func _process(_delta):
    if scroll.visible: _layout()

# ---------------------------------------------------------------- layout (escala única)
func _layout():
    var mobile = Mobile.active(get_viewport())
    var vr = get_viewport().get_visible_rect()
    var area = Mobile.safe_rect(get_viewport()) if mobile else vr
    dim.position = Vector2.ZERO
    dim.size = vr.size
    # A arte inteira (cavalos incluídos) cabe na altura; em telas baixas (celular deitado)
    # limita a redução e deixa rolar.
    # Largura útil = corpo do painel (x 60..1062 da arte); as bordas de floresta podem sair da tela.
    k = minf((area.size.y - 8.0) / REF.y, (area.size.x - 8.0) / BODY_W)
    var min_k := 0.5 if mobile else 0.42
    if k < min_k: k = minf(min_k, (area.size.x - 8.0) / BODY_W)
    panel.scale = Vector2.ONE * k
    var holder: Control = panel.get_parent()
    holder.custom_minimum_size = REF * k
    scroll.position = area.position
    scroll.size = area.size
    var free: Vector2 = area.size - REF * k
    panel.position = Vector2(free.x / 2.0, maxf(0.0, free.y / 2.0))
    holder.custom_minimum_size = Vector2(area.size.x, maxf(REF.y * k, area.size.y))

# ---------------------------------------------------------------- construção
func _clear():
    fields.clear()
    for child in box.get_children():
        box.remove_child(child)
        child.queue_free()
    for child in panel.get_children():
        if child.has_meta("slot"):
            panel.remove_child(child)
            child.queue_free()

func _make_status() -> Label:
    var l := Label.new()
    l.name = "Status"
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    l.add_theme_font_size_override("font_size", 22)
    l.add_theme_color_override("font_color", Color("c9c2a8"))
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l

func _label(text: String, size := 16, color := Color("e8e0c8")) -> Label:
    var l = Label.new()
    l.text = text
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", int(size * 1.6))
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    l.add_theme_constant_override("shadow_offset_y", 2)
    box.add_child(l)
    return l

## Campo: `slot` = posição fixa sobre a arte de ENTRAR (baked); senão entra no box.
func _input_field(key: String, placeholder: String, secret := false, slot := Rect2()) -> LineEdit:
    var holder = LoginSkin.Field.new()
    holder.name = "Field_" + key
    holder.big = _mobile()   # R181 · letra maior só no celular
    holder.baked = slot.size.x > 0.0
    holder.setup("lock" if secret else ("mail" if key == "email" else "person_add"), secret)
    var e: LineEdit = holder.line
    e.placeholder_text = placeholder
    if key == "email": e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
    if secret: e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
    _place(holder, slot)
    WebTextField.attach(e)   # Web no celular: campo HTML real por cima para o teclado virtual abrir
    fields[key] = e
    return e

func _button(text: String, action: Callable, primary := false, slot := Rect2()) -> Button:
    var b = LoginSkin.SkinButton.new()
    b.text = text
    b.primary = primary
    b.baked = slot.size.x > 0.0
    b.font_size = 64 if primary else 40
    b.custom_minimum_size = Vector2(738, 150 if primary else 104)
    if "GOOGLE" in text: b.icon_kind = "google"
    b.pressed.connect(action)
    _place(b, slot)
    return b

const LINK_ICONS = {"Criar conta": "person", "Esqueci minha senha": "key", "Jogar como convidado": "persons"}

func _link(text: String, action: Callable, slot := Rect2()) -> Button:
    var b = LoginSkin.SkinLink.new()
    b.text = text
    b.big = _mobile() and slot.size.x > 0.0   # R181 · texto maior só no celular, na tela de entrar (arte com as linhas)
    b.icon_kind = LINK_ICONS.get(text, "")
    b.baked = slot.size.x > 0.0
    b.pressed.connect(action)
    if slot.size.x > 0.0: _place(b, slot)
    else:
        if links_box == null:
            var center = CenterContainer.new()
            box.add_child(center)
            links_box = VBoxContainer.new()
            links_box.add_theme_constant_override("separation", 0)
            center.add_child(links_box)
        links_box.add_child(b)
        if _mobile():   # R181 · celular: linha mais larga e texto maior e igual para todos (o rodapé da linha estica)
            b.custom_minimum_size = Vector2(700, 76)
            _fit_box_links()
    return b

## R181 · celular: o maior tamanho em que TODOS os links da tela cabem antes da seta da linha
func _fit_box_links() -> void:
    if links_box == null: return
    var f: Font = preload("res://account/login_art.gd").FONT_SEMI
    var fs := 42
    for l in links_box.get_children():
        while fs > 18 and f.get_string_size(String(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.custom_minimum_size.x - 130.0 - 70.0: fs -= 1
    for l in links_box.get_children():
        l.fixed_fs = fs
        l.queue_redraw()

var links_box: VBoxContainer = null

## R100 · "Li e aceito os Termos de Uso e a Política de Privacidade" — caixinha obrigatória para criar conta
## (cadastro por e-mail e escolha do nome, que é o passo de TODA conta nova, inclusive pelo Google).
var terms_check: Button = null
func _terms_check() -> Button:
    var b := TermsCheck.new()
    b.name = "TermsCheck"
    b.button_pressed = account.terms_accepted
    b.toggled.connect(func(on): account.terms_accepted = on)
    var center := CenterContainer.new()
    box.add_child(center)
    center.add_child(b)
    terms_check = b
    return b

func _terms_ok() -> bool:
    if account.terms_accepted: return true
    _on_notice("Para criar a conta, marque que leu e aceita os Termos de Uso e a Política de Privacidade.", true)
    if is_instance_valid(terms_check): terms_check.flash()
    return false


## R176.2 · o conteúdo da página tem que caber DENTRO da moldura (CRIAR CONTA no celular deixava os links
## soltos embaixo, fora do painel): primeiro aperta o espaçamento, depois encolhe o bloco inteiro, centralizado.
## os textos com quebra de linha só sabem a altura depois do 1º layout: mede no quadro seguinte
func _fit_box_later():
    var pg := page
    await get_tree().process_frame
    await get_tree().process_frame
    if page != pg or not is_instance_valid(box): return
    _fit_box()
    status_label.position = Vector2(SLOT_STATUS.position.x, INNER.position.y + 16.0 + box.get_combined_minimum_size().y * box.scale.y + 12.0)

func _fit_box():
    var room := INNER.size.y - 16.0 - 56.0   # sobra para a linha de status
    box.scale = Vector2.ONE
    box.position = INNER.position + Vector2(0, 16)
    box.add_theme_constant_override("separation", 18)
    var h := box.get_combined_minimum_size().y
    if h > room:
        box.add_theme_constant_override("separation", 8)
        h = box.get_combined_minimum_size().y
    if h > room:
        var s := room / h
        box.scale = Vector2(s, s)
        box.position.x = INNER.position.x + INNER.size.x * (1.0 - s) / 2.0
    box.size = Vector2(INNER.size.x, maxf(h, INNER.size.y - 16.0))

func _divider():
    links_box = null
    var d = LoginSkin.Divider.new()
    d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    box.add_child(d)
    return d

func _place(c: Control, slot: Rect2):
    if slot.size.x > 0.0:
        c.set_meta("slot", true)
        c.position = slot.position
        c.size = slot.size
        panel.add_child(c)
    else:
        c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        box.add_child(c)

func _value(key: String) -> String:
    return fields[key].text if fields.has(key) else ""

## Senha: vai direto para o Supabase (account.update_password); os campos são limpos logo após o envio.
func _save_password():
    var pwd := _value("password")
    var confirm := _value("password_confirm")
    for k in ["password", "password_confirm"]:
        if fields.has(k): fields[k].text = ""
    account.update_password(pwd, confirm)

var inapp_app := ""
var inapp_os := ""
func _show(target: String):
    page = target
    _clear()
    links_box = null
    var titles := {"login":"ENTRAR NO FRAIHA", "signup":"CRIAR CONTA", "recover":"RECUPERAR SENHA",
        "new_password":"NOVA SENHA", "set_password":"SENHA DA CONTA", "nickname":"ESCOLHA SEU NOME", "account":"SUA CONTA",
        "waiting":"CONECTANDO…", "unavailable":"CONTAS", "inapp":"QUASE LÁ!"}
    var baked := target == "login"
    art.texture = load(ART_FULL_PATH if baked else ART_BLANK_PATH)
    title_label.text = String(titles.get(target, "CONTA"))
    title_label.visible = not baked    # na arte de ENTRAR o título já está pintado
    box.visible = not baked
    status_label.text = ""
    status_label.position = SLOT_STATUS.position
    status_label.size = SLOT_STATUS.size
    if not message.is_empty() and not baked: _label(message, 16, Color("f0d9a0"))
    match target:
        "login":
            _input_field("email", "E-mail", false, SLOT_EMAIL)
            _input_field("password", "Senha", true, SLOT_PASSWORD).text_submitted.connect(func(_t): account.sign_in(_value("email"), _value("password")))
            _button("ENTRAR", func(): account.sign_in(_value("email"), _value("password")), true, SLOT_ENTER)
            _button("CONTINUAR COM GOOGLE", func(): account.sign_in_google("ranked" if return_to_ranked else ""), false, SLOT_GOOGLE)
            if not _mobile():   # PC congelado: exatamente o layout original (só o clique do convidado agora conecta ao servidor)
                _link("Criar conta", func(): _show("signup"), SLOT_LINKS[0])
                _link("Esqueci minha senha", func(): _show("recover"), SLOT_LINKS[1])
                _link("Jogar como convidado", play_as_guest, SLOT_LINKS[2]).name = "GuestButton"
            else:   # R181 · celular: JOGAR COMO CONVIDADO é o botão PRINCIPAL; os outros dois menores, lado a lado
                var guest = _button("Jogar como convidado", play_as_guest, true, SLOT_GUEST)   # minúsculas = versalete, como o "Entrar" da arte
                guest.name = "GuestButton"
                guest.baked = false   # a placa é desenhada (a arte tem só as linhas dos links aqui)
                guest.glow = true
                guest.entrar_style = true
                guest.veil = true
                guest.font_size = 58
                guest.side = 300.0
                # R187e · teste automático no iPhone virtual do Codemagic (o simulador não toca na tela):
                # com "-- --fx-teste-convidado" o app entra sozinho como convidado depois de 4 s. Sem a opção, nada muda.
                if "--fx-teste-convidado" in OS.get_cmdline_user_args() and not get_meta("fx_teste_feito", false):
                    set_meta("fx_teste_feito", true)
                    get_tree().create_timer(4.0).timeout.connect(_fx_teste_convidado)
                var sl = _link("Criar conta", func(): _show("signup"), SLOT_SMALL[0])
                sl.small = true
                sl.halo = true
                sl.custom_minimum_size = Vector2.ZERO
                sl.size = SLOT_SMALL[0].size
                var sr = _link("Esqueci minha senha", func(): _show("recover"), SLOT_SMALL[1])
                sr.small = true
                sr.custom_minimum_size = Vector2.ZERO
                sr.size = SLOT_SMALL[1].size
            if not message.is_empty():
                status_label.text = message
                status_label.add_theme_color_override("font_color", Color("f0d9a0"))
        "signup":
            _input_field("nickname", "Nome de jogador (3 a 16)")
            _input_field("email", "E-mail")
            _input_field("password", "Senha (mín. 8 caracteres)", true)
            _terms_check()
            _button("CRIAR CONTA", func(): if _terms_ok(): account.sign_up(_value("email"), _value("password"), _value("nickname")), true)
            _button("CONTINUAR COM GOOGLE", func(): if _terms_ok(): account.sign_in_google("ranked" if return_to_ranked else ""))
            _link("Ler os Termos e a Privacidade", func(): if open_legal.is_valid(): open_legal.call("termos"))
            _divider()
            _link("Já tenho conta — Entrar", func(): _show("login"))
            _link("Jogar como convidado", close)
        "recover":
            _label("Enviaremos um link para criar uma nova senha.", 15)
            _input_field("email", "E-mail da conta")
            _button("ENVIAR LINK", func(): account.recover(_value("email")), true)
            _divider()
            _button("VOLTAR", func(): _show("login"))   # R176.2 · botão no padrão (antes um link solto)
        "new_password":
            _input_field("password", "Nova senha (mín. 8 caracteres)", true)
            _input_field("password_confirm", "Confirmar nova senha", true)
            _button("SALVAR NOVA SENHA", _save_password, true)
            _divider()
            _button("FECHAR", close)   # R176.2
        "set_password":
            if account.provider != "email":
                _label("Crie uma senha para entrar também com e-mail e senha. O login com Google continua funcionando na mesma conta.", 15)
            _label(account.email, 14, Color("b8b19c"))
            _input_field("password", "Nova senha (mín. 8 caracteres)", true)
            _input_field("password_confirm", "Confirmar nova senha", true).text_submitted.connect(func(_t): _save_password())
            _button("SALVAR SENHA", _save_password, true)
            _divider()
            _button("VOLTAR", func(): _show("account"))   # R176.2
        "nickname":
            _label("É assim que os adversários verão você. Seu e-mail nunca é mostrado.", 15)
            _input_field("nickname", "Nome de jogador (3 a 16)").text_submitted.connect(func(t): if _terms_ok(): account.create_profile(t))
            _terms_check()   # R100 · toda conta nova passa aqui (inclusive pelo Google): aceite obrigatório
            _button("CONFIRMAR NOME", func(): if _terms_ok(): account.create_profile(_value("nickname")), true)
            _link("Ler os Termos e a Privacidade", func(): if open_legal.is_valid(): open_legal.call("termos"))
            _divider()
            _link("Sair da conta", account.sign_out)
        "account":
            _label("Jogador: " + account.nickname(), 18)
            _label(account.email, 14, Color("b8b19c"))
            if not account.persistent_backend:
                _label("Servidor em modo de teste: progresso Ranked NÃO é permanente.", 14, Color("ff9d86"))
            _button("VOLTAR", close, true)   # R155 · antes CONTINUAR (confundia: o botão só volta para a Home)
            _button("DEFINIR SENHA" if account.provider != "email" else "ALTERAR SENHA", func(): _show("set_password"))
            _button("SAIR DA CONTA", account.sign_out)
            _link("Termos, privacidade e excluir conta", func(): if open_legal.is_valid(): open_legal.call("termos"))
        "inapp":   # R181 · Google dentro do Instagram/Facebook/TikTok: o Google não deixa terminar o login aqui
            var app_name := inapp_app if not inapp_app.is_empty() else "este app"
            _label("O %s não deixa entrar com Google aqui dentro. Abra o FRAIHA no navegador do celular e entre com Google por lá — leva 5 segundos." % app_name, 16)
            if inapp_os == "ios":
                _button("ABRIR NO SAFARI", account.open_external_browser, true).side = 340.0
                _label("Se não abrir: toque em ⋯ (no canto de cima) e escolha \"Abrir no navegador externo\".", 14, Color("f0d9a0"))
            else:
                _button("ABRIR NO CHROME" if inapp_os == "android" else "ABRIR NO NAVEGADOR", account.open_external_browser, true).side = 340.0
                _label("Se não abrir: toque em ⋮ (no canto de cima) e escolha \"Abrir no Chrome\" ou \"Abrir no navegador\".", 14, Color("f0d9a0"))
            _button("COPIAR LINK DO JOGO", account.copy_game_link)
            _button("CRIAR CONTA COM E-MAIL", func(): _show("signup"))
            _divider()
            _link("Já tenho conta: entrar", func(): _show("login"))
            _link("Tentar Google aqui mesmo", func(): account.sign_in_google(account.google_then, true))
            _link("Jogar como convidado", close)
        "waiting":
            _label("Conectando sua conta ao servidor FRAIHA…", 16)
            _divider()
            _link("Jogar como convidado", close)
        "unavailable":
            _label("As contas FRAIHA ainda não foram ativadas nesta versão. Você pode jogar Local, Bot e Online Casual como convidado.", 16)
            _button("JOGAR COMO CONVIDADO", close, true)
    if not baked:
        # status abaixo do conteúdo do box
        var spacer := Control.new()
        spacer.custom_minimum_size.y = 4
        box.add_child(spacer)
        box.scale = Vector2.ONE
        box.position = INNER.position + Vector2(0, 16)
        _fit_box_later()
    message = ""
    if not fields.is_empty() and not Mobile.active(get_viewport()):
        fields.values()[0].grab_focus.call_deferred()
    _layout.call_deferred()

class TermsCheck extends Button:
    const GOLD := Color("e9c46a")
    const CREAM := Color("f1e6c8")
    const WARN := Color("ff9d86")
    const PX := 34
    const LINES := ["Li e aceito os Termos de Uso", "e a Política de Privacidade"]
    var warn := false
    var _flash := 0.0
    func _font() -> Font: return preload("res://ui_kit/fonts/Alegreya-Bold.woff")
    func _init():
        toggle_mode = true
        flat = true
        focus_mode = Control.FOCUS_NONE
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]: add_theme_stylebox_override(st, StyleBoxEmpty.new())
        var w := 0.0
        for l in LINES: w = maxf(w, _font().get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, PX).x)
        custom_minimum_size = Vector2(60 + 22 + w + 8, 128)   # caixa + texto: centralizado de verdade
        toggled.connect(func(on):
            if on: warn = false
            queue_redraw())
    func flash():
        warn = true
        _flash = 1.0
        queue_redraw()
    func _process(d):
        if _flash > 0.0:
            _flash = maxf(0.0, _flash - d * 1.2)
            queue_redraw()
    func _draw():
        var f := _font()
        var top := 6.0
        var box := Rect2(Vector2(4, top + 12), Vector2(56, 56))
        var border := WARN if warn else GOLD
        if _flash > 0.0: draw_rect(box.grow(8.0 * _flash), Color(WARN.r, WARN.g, WARN.b, 0.35 * _flash))
        draw_rect(box, Color(0.057, 0.071, 0.099, 0.95))
        draw_rect(box, border, false, 4.0)
        if button_pressed:
            var a := box.position
            draw_polyline(PackedVector2Array([a + Vector2(11, 29), a + Vector2(24, 42), a + Vector2(46, 14)]), Color("8fe07a"), 7.0, true)
        for i in LINES.size():
            var pos := Vector2(box.end.x + 22, top + PX + 2 + i * (PX + 6))
            draw_string_outline(f, pos, LINES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, PX, 5, Color(0, 0, 0, 0.8))
            draw_string(f, pos, LINES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, PX, CREAM)
        if warn:
            var t := "Marque para criar a conta"
            var pos := Vector2(box.end.x + 22, top + PX * 3 + 14)
            draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 4, Color(0, 0, 0, 0.8))
            draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, WARN)
