extends SceneTree
## Tela de conta com a arte de referência: páginas, campos, botões e links continuam funcionando.
## Uso: godot --path . -s tests/login_screen_test.gd [-- --mobile-test]
var checks := 0
var failures := 0
func check(ok: bool, label: String):
    checks += 1
    print(("PASS " if ok else "FAIL ") + label)
    if not ok: failures += 1
func _initialize(): call_deferred("run")
func run():
    var args = OS.get_cmdline_user_args()
    var mobile: bool = "--mobile-test" in args
    root.mode = Window.MODE_WINDOWED
    root.size = Vector2i(390, 844) if mobile else Vector2i(1920, 1080)
    root.content_scale_size = root.size if mobile else Vector2i(1920, 1080)
    await process_frame
    var stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    for i in range(6): await process_frame
    var ui = stage.account_ui
    ui.open("login")
    for i in range(4): await process_frame
    check(ui.is_open() and ui.page == "login", "abre em ENTRAR")
    check(ui.art.texture == ui.ART_FULL and not ui.title_label.visible, "ENTRAR usa a arte completa (título pintado)")
    check(ui.fields.has("email") and ui.fields.has("password"), "campos e-mail e senha")
    var fe = ui.panel.get_node_or_null("Field_email")
    var fp = ui.panel.get_node_or_null("Field_password")
    check(fe != null and fp != null and fe.baked and fp.baked and fe.position == ui.SLOT_EMAIL.position, "campos posicionados sobre a arte")
    var eye = fp.get_node_or_null("ShowPassword")
    check(eye != null and ui.fields.password.secret, "senha oculta com olho")
    eye.pressed.emit()
    check(not ui.fields.password.secret, "olho mostra a senha")
    var btns := []
    for c in ui.panel.get_children():
        if c is Button and c.has_meta("slot"): btns.append(c.text)
    check("ENTRAR" in btns and "CONTINUAR COM GOOGLE" in btns and "Criar conta" in btns and "Esqueci minha senha" in btns and "Jogar como convidado" in btns, "ENTRAR, Google e os três links existem: %s" % [btns])
    var vs = ui.get_viewport().get_visible_rect().size
    var art_h: float = ui.REF.y * ui.k
    check(ui.k > 0.2 and (art_h <= vs.y + 1.0 or mobile), "arte escalada cabe na tela (k=%.2f, altura %.0f de %.0f)" % [ui.k, art_h, vs.y])
    # navegação pelos links
    for c in ui.panel.get_children():
        if c is Button and c.text == "Criar conta": c.pressed.emit()
    for i in range(2): await process_frame
    check(ui.page == "signup" and ui.art.texture == ui.ART_BLANK and ui.title_label.visible and ui.title_label.text == "CRIAR CONTA", "Criar conta → página com moldura vazia e título")
    check(ui.fields.has("nickname") and ui.fields.has("email") and ui.fields.has("password"), "campos de criar conta")
    var kinds := []
    for c in ui.box.find_children("*", "Button", true, false): kinds.append(c.text)
    check("CRIAR CONTA" in kinds and "CONTINUAR COM GOOGLE" in kinds and "Jogar como convidado" in kinds, "botões de criar conta: %s" % [kinds])
    ui._show("recover")
    check(ui.page == "recover" and ui.fields.has("email"), "recuperar senha")
    ui._show("login")
    for i in range(2): await process_frame
    check(ui.page == "login" and ui.fields.has("email"), "volta a ENTRAR")
    ui.message = "Entre para jogar Ranked."
    ui._show("login")
    check(ui.status_label.text == "Entre para jogar Ranked.", "mensagem de contexto aparece no rodapé da arte")
    # convidado fecha
    var closed := [false]
    ui.closed.connect(func(): closed[0] = true)
    for c in ui.panel.get_children():
        if c is Button and c.text == "Jogar como convidado": c.pressed.emit()
    check(closed[0] and not ui.is_open(), "Jogar como convidado fecha")
    print("LOGIN_SCREEN_CHECKS=%d FAILURES=%d" % [checks, failures])
    print("RESULT " + ("OK" if failures == 0 else "FAIL"))
    quit()
