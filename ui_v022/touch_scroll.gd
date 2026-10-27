extends Node
## Rolagem por arrasto com o dedo em QUALQUER ponto de um ScrollContainer, inclusive começando
## em cima de botões e cartões (que no Godot "seguram" o toque e impedem a rolagem nativa).
## Só reage a toque (InputEventScreenTouch/Drag); mouse e roda do mouse seguem o padrão.
## Se o dedo andar mais que THRESHOLD, o toque vira rolagem e o botão tocado NÃO é acionado.
const THRESHOLD := 12.0
var scroll: ScrollContainer
var _index := -1
var _start := Vector2.ZERO
var _start_v := 0
var _start_h := 0
var _dragging := false
# R86 · rolagem com inércia: soltou o dedo rápido, a lista continua deslizando e vai parando (como no celular)
const FRICTION := 3.2          # quanto maior, mais rápido para
const MIN_SPEED := 30.0        # px/s (do conteúdo) abaixo disso para
const MAX_SPEED := 6000.0
var _vel := Vector2.ZERO       # velocidade do conteúdo (px/s)
var _pos := Vector2.ZERO       # posição em float (scroll_* é inteiro)
var _last_t := 0
var _last_p := Vector2.ZERO

static func attach(target: ScrollContainer) -> Node:
    var helper = load("res://ui_v022/touch_scroll.gd").new()
    helper.name = "TouchScroll"
    helper.scroll = target
    # A rolagem nativa por toque (só nos vãos) conflitaria com esta; a nossa cobre a área toda.
    target.scroll_deadzone = 1000000
    target.add_child(helper, false, Node.INTERNAL_MODE_BACK)
    return helper

func _ready():
    # Celular: sem barra de rolagem visível (arrastar com o dedo já basta); a rolagem continua.
    if preload("res://ui_v022/mobile_layout.gd").active(get_viewport()):
        if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO: scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
        if scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO: scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

func is_dragging() -> bool:
    return _dragging

func _input(event):
    if not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
        _index = -1
        _dragging = false
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            # R199 · rolagem desligada nas duas direções (ex.: painel de AMIGOS, onde só a lista de dentro rola):
            # não pega o dedo — antes ele "segurava" o toque e a lista de dentro não rolava
            var off := scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
            if _index == -1 and not off and _rect().has_point(event.position) and not _covered():
                _vel = Vector2.ZERO
                _index = event.index
                _last_t = Time.get_ticks_usec()
                _last_p = event.position
                _start = event.position
                _start_v = scroll.scroll_vertical
                _start_h = scroll.scroll_horizontal
                _dragging = false
        elif event.index == _index:
            _index = -1
            # dedo parado antes de soltar (mais de 0,1 s): sem inércia
            if _dragging and Time.get_ticks_usec() - _last_t < 100000 and _vel.length() > MIN_SPEED:
                _pos = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
                if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED: _vel.y = 0.0
                if scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED: _vel.x = 0.0
            else:
                _vel = Vector2.ZERO
            _dragging = false
    elif event is InputEventScreenDrag and event.index == _index:
        var delta: Vector2 = event.position - _start
        # Arrasto mais horizontal que vertical é do controle tocado (ex.: barra de volume).
        if not _dragging and delta.length() >= THRESHOLD and absf(delta.x) > absf(delta.y) and scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
            _index = -1
            return
        if not _dragging and delta.length() >= THRESHOLD:
            _dragging = true
            _cancel_press()
        if _dragging:
            var s := scroll.get_global_transform_with_canvas().get_scale()
            var now := Time.get_ticks_usec()
            var dt := float(now - _last_t) / 1000000.0
            if dt > 0.001:
                var v: Vector2 = -(event.position - _last_p) / dt / Vector2(maxf(0.01, s.x), maxf(0.01, s.y))
                _vel = (_vel * 0.35 + v * 0.65).clamp(Vector2(-MAX_SPEED, -MAX_SPEED), Vector2(MAX_SPEED, MAX_SPEED))
                _last_t = now
                _last_p = event.position
            if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
                scroll.scroll_vertical = _start_v - int(delta.y / maxf(0.01, s.y))
            if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
                scroll.scroll_horizontal = _start_h - int(delta.x / maxf(0.01, s.x))
            get_viewport().set_input_as_handled()

func _process(delta: float):
    if _vel == Vector2.ZERO or _index != -1: return
    if not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
        _vel = Vector2.ZERO
        return
    _pos += _vel * delta
    _vel *= exp(-FRICTION * delta)
    var before := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
    if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: scroll.scroll_vertical = int(round(_pos.y))
    if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: scroll.scroll_horizontal = int(round(_pos.x))
    var after := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
    # chegou no começo/fim (o Godot segurou o valor) ou ficou lento: para
    if _vel.length() < MIN_SPEED or (after == before and (absf(_pos.y - after.y) > 2.0 or absf(_pos.x - after.x) > 2.0)):
        _vel = Vector2.ZERO

## R142 · um painel (TABULEIRO E PEÇAS etc.) aberto por cima: o dedo é dele, a lista de trás não rola
func _covered() -> bool:
    for m in get_tree().get_nodes_in_group("fraiha_modal"):
        if m.has_method("is_open") and m.is_open() and not m.is_ancestor_of(scroll): return true
    return false

func _rect() -> Rect2:
    var xf := scroll.get_global_transform_with_canvas()
    return Rect2(xf.origin, scroll.size * xf.get_scale())

# O toque virou rolagem: solta o botão que estava sendo pressionado FORA dele, para que
# não dispare quando o dedo sair da tela e para a interface não ficar "presa" nele.
func _cancel_press():
    var vp := get_viewport()
    var away := Vector2(-10000, -10000)
    var motion := InputEventMouseMotion.new()
    motion.position = away
    motion.global_position = away
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    vp.push_input(motion, true)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.position = away
    release.global_position = away
    vp.push_input(release, true)
