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

static func attach(target: ScrollContainer) -> Node:
    var helper = load("res://ui_v022/touch_scroll.gd").new()
    helper.name = "TouchScroll"
    helper.scroll = target
    # A rolagem nativa por toque (só nos vãos) conflitaria com esta; a nossa cobre a área toda.
    target.scroll_deadzone = 1000000
    target.add_child(helper, false, Node.INTERNAL_MODE_BACK)
    return helper

func is_dragging() -> bool:
    return _dragging

func _input(event):
    if not is_instance_valid(scroll) or not scroll.is_visible_in_tree():
        _index = -1
        _dragging = false
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            if _index == -1 and _rect().has_point(event.position):
                _index = event.index
                _start = event.position
                _start_v = scroll.scroll_vertical
                _start_h = scroll.scroll_horizontal
                _dragging = false
        elif event.index == _index:
            _index = -1
            _dragging = false
    elif event is InputEventScreenDrag and event.index == _index:
        var delta: Vector2 = event.position - _start
        if not _dragging and delta.length() >= THRESHOLD:
            _dragging = true
            _cancel_press()
        if _dragging:
            var s := scroll.get_global_transform_with_canvas().get_scale()
            if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
                scroll.scroll_vertical = _start_v - int(delta.y / maxf(0.01, s.y))
            if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
                scroll.scroll_horizontal = _start_h - int(delta.x / maxf(0.01, s.x))
            get_viewport().set_input_as_handled()

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
