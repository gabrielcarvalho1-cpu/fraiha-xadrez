extends SceneTree
## JOGAR ONLINE no celular: arrastar o dedo em cima dos cartões rola a lista até o fim
## (Convencional 20 min alcançável), arrastar não aciona botão, toque simples aciona, e
## VOLTAR fica sempre visível. Rodar com: -- --mobile-test [--size LxA]
## R177b · o JOGAR ONLINE do celular agora usa a arte do Ranqueado (RankedArtScroll): o teste rola a arte e toca
## os botões BUSCAR PARTIDA / VOLTAR desenhados nela (eles acionam os botões reais da lista).
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
    OS.set_environment("FRAIHA_SERVER_URL", "")   # R127 · sem servidor (como o mobile_pages_test): a lista não se remonta no meio do teste quando a conexão cai
    await process_frame
    stage = load("res://presentation_v019/stage.tscn").instantiate()
    root.add_child(stage)
    await frames(10)
    if stage.account_ui.is_open(): stage.account_ui.hide_ui()
    stage._open_casual()
    await frames(6)
    var ui = stage.casual_ui
    var screen = root.get_visible_rect()
    var scroll: ScrollContainer = ui.find_child("RankedArtScroll", true, false)
    check(scroll != null and scroll.is_visible_in_tree(), "JOGAR ONLINE na arte do Ranqueado")
    if scroll == null:
        print("MOBILE_SCROLL_CHECKS=", checks, " FAILURES=", failures)
        quit(failures)
        return
    var hits: Array = []
    var back: Button = null
    for b in scroll.find_children("*", "Button", true, false):
        if b.text.begins_with("BUSCAR casual_"): hits.append(b)
        elif b.text == "VOLTAR": back = b
    hits.sort_custom(func(a, b): return a.position.y < b.position.y)
    check(hits.size() == 4, "4 ritmos (%d)" % hits.size())
    var bar = scroll.get_v_scroll_bar()
    check(bar.max_value > bar.page, "lista maior que a tela: precisa rolar")
    # Cartões habilitados para testar toque/arrasto sem servidor.
    var pressed := {}
    for id in ["casual_3min", "casual_20min"]:
        var b: Button = ui.box.find_child("Queue_" + id, true, false)
        b.disabled = false
        for c in b.pressed.get_connections(): b.pressed.disconnect(c.callable)
        b.pressed.connect(func(): pressed[id] = int(pressed.get(id, 0)) + 1)
    var first: Button = hits[0]
    var last: Button = hits[hits.size() - 1]
    var view0 = scroll.get_global_rect()
    var start = first.get_global_rect().intersection(view0).get_center()
    touch(start, true)
    await frames()
    var pos = start
    for step in 16:
        pos += Vector2(0, -40)
        drag(pos, Vector2(0, -40))
        await frames(1)
    touch(pos, false)
    await frames(3)
    check(scroll.scroll_vertical > 0, "arrastar em cima do cartão rola a lista (%d px)" % scroll.scroll_vertical)
    check(not pressed.has("casual_3min"), "arrasto não aciona o botão tocado")
    scroll.scroll_vertical = int(bar.max_value)
    await frames(3)
    var view = scroll.get_global_rect()
    check(visible_in(last, view), "CONVENCIONAL 20 min totalmente visível")
    # Toque simples ainda funciona.
    touch(center(last), true)
    await frames()
    touch(center(last), false)
    await frames(3)
    check(int(pressed.get("casual_20min", 0)) == 1, "toque simples aciona BUSCAR PARTIDA do Convencional")
    check(not pressed.has("casual_3min"), "nenhum clique fantasma depois dos arrastos")
    # VOLTAR por toque volta para a Home.
    if back != null:
        scroll.ensure_control_visible(back)
        await frames(3)
        touch(center(back), true)
        await frames()
        touch(center(back), false)
        await frames(4)
    check(back != null and stage.mode == "home" and not ui.panel_open(), "VOLTAR por toque retorna à Home")
    print("MOBILE_SCROLL_CHECKS=", checks, " FAILURES=", failures)
    quit(failures)
