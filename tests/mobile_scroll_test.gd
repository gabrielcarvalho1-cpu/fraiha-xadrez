extends SceneTree
## JOGAR ONLINE no celular: arrastar o dedo em cima dos cartões rola a lista até o fim
## (Convencional 20 min alcançável), arrastar não aciona botão, toque simples aciona, e
## VOLTAR fica sempre visível. Rodar com: -- --mobile-test [--size LxA]
var checks := 0
var failures := 0
var stage

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
    checks += 1
    if ok: print("PASS ", label)
    else:
        failures += 1
        print("FAIL ", label)

func touch(pos: Vector2, pressed: bool):
    var e = InputEventScreenTouch.new()
    e.index = 0
    e.position = pos
    e.pressed = pressed
    Input.parse_input_event(e)

func drag(pos: Vector2, rel: Vector2):
    var e = InputEventScreenDrag.new()
    e.index = 0
    e.position = pos
    e.relative = rel
    Input.parse_input_event(e)

func frames(n := 2):
    for i in n: await process_frame

func center(c: Control) -> Vector2:
    return c.get_global_rect().get_center()

func visible_in(c: Control, area: Rect2) -> bool:
    var r = c.get_global_rect()
    return area.grow(1).encloses(r)

func run():
    var args = OS.get_cmdline_user_args()
    var size = Vector2i(390, 600)
    var i = args.find("--size")
    if i >= 0:
        var p = args[i + 1].split("x")
        size = Vector2i(int(p[0]), int(p[1]))
    root.mode = Window.MODE_WINDOWED
    root.size = size
    root.content_scale_size = size
    await process_frame
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(10)
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    stage._open_casual()
    await frames(6)
    var ui = stage.casual_ui
    var screen = root.get_visible_rect()
    var back: Button = ui.footer.find_child("BackButton", true, false)
    check(back != null and back.is_visible_in_tree() and visible_in(back, screen), "VOLTAR fixo e visível (%dx%d)" % [size.x, size.y])
    var bar = ui.scroll.get_v_scroll_bar()
    check(bar.max_value > bar.page, "lista maior que a tela: precisa rolar")
    # Cartões habilitados para testar toque/arrasto sem servidor.
    var pressed := {}
    for id in ["casual_3min", "casual_20min"]:
        var b: Button = ui.box.find_child("Queue_" + id, true, false)
        b.disabled = false
        for c in b.pressed.get_connections(): b.pressed.disconnect(c.callable)
        b.pressed.connect(func(): pressed[id] = int(pressed.get(id, 0)) + 1)
    var first: Button = ui.box.find_child("Queue_casual_3min", true, false)
    var last: Button = ui.box.find_child("Queue_casual_20min", true, false)
    # Arrasto começando em cima do primeiro cartão. R53 · no celular deitado o cartão é mais alto que a lista
    # visível: o botão dele começa ABAIXO da área de rolagem (embaixo do VOLTAR fixo). O dedo começa então na parte
    # do cartão que está na tela (centro do botão quando ele aparece; senão, centro da parte visível do cartão).
    var view0 = ui.scroll.get_global_rect()
    var card: Control = first
    while card.get_parent() != null and not (card.get_parent() is HBoxContainer): card = card.get_parent()
    var vis_btn: Rect2 = first.get_global_rect().intersection(view0)
    var vis_card: Rect2 = card.get_global_rect().intersection(view0)
    var start = vis_btn.get_center() if vis_btn.size.y >= 20.0 else vis_card.get_center()
    touch(start, true)
    await frames()
    var pos = start
    for step in 12:
        pos += Vector2(0, -40)
        drag(pos, Vector2(0, -40))
        await frames(1)
    touch(pos, false)
    await frames(3)
    check(ui.scroll.scroll_vertical > 0, "arrastar em cima do cartão rola a lista (%d px)" % ui.scroll.scroll_vertical)
    check(not pressed.has("casual_3min"), "arrasto não aciona o botão tocado")
    check(ui.scroll.scroll_vertical >= bar.max_value - bar.page - 1, "chega ao fim da lista")
    var view = ui.scroll.get_global_rect()
    check(visible_in(last, view), "CONVENCIONAL 20 min totalmente visível")
    # Toque simples ainda funciona.
    touch(center(last), true)
    await frames()
    touch(center(last), false)
    await frames(3)
    check(int(pressed.get("casual_20min", 0)) == 1, "toque simples aciona ENTRAR NA FILA do Convencional")
    # Rolar de volta para cima.
    start = center(last)
    touch(start, true)
    await frames()
    pos = start
    for step in 12:
        pos += Vector2(0, 40)
        drag(pos, Vector2(0, 40))
        await frames(1)
    touch(pos, false)
    await frames(3)
    check(ui.scroll.scroll_vertical == 0, "arrastar para baixo volta ao topo")
    check(not pressed.has("casual_3min") and int(pressed.get("casual_20min", 0)) == 1, "nenhum clique fantasma depois dos arrastos")
    # VOLTAR por toque volta para a Home.
    touch(center(back), true)
    await frames()
    touch(center(back), false)
    await frames(4)
    check(stage.mode == "home" and not ui.panel_open(), "VOLTAR por toque retorna à Home")
    print("MOBILE_SCROLL_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
