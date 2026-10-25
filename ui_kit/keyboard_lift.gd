extends Node
## R185 · APP ANDROID: o teclado do celular cobria o campo de digitar (chat da mesa, chat geral, mensagens,
## login…), e às vezes o campo ficava solto no meio da tela. No app (tela cheia) a janela não encolhe quando o
## teclado abre; então, enquanto um campo de texto está em foco e o teclado aparece, a CAMADA dele sobe só o
## necessário para o campo ficar logo acima do teclado — e volta ao lugar quando o teclado fecha.
## Web e PC: não faz nada (na Web o campo HTML já cuida disso: ui_v022/web_text_field.gd).

const GAP := 14.0
var _moved: Object = null          # CanvasLayer (ou a Viewport) que foi deslocada
var _orig := 0.0                    # deslocamento original dela
var _shift := 0.0

static func wanted() -> bool:
	return OS.has_feature("android") and not OS.has_feature("web")

func _ready():
	name = "KeyboardLift"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(wanted())

func _process(_d: float):
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner()
	var kb := float(DisplayServer.virtual_keyboard_get_height())
	var typing := (f is LineEdit or f is TextEdit) and f.is_visible_in_tree() and kb > 0.0
	if not typing:
		_restore()
		return
	var vs := vp.get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var kb_vp := kb * vs.y / maxf(1.0, win.y)   # teclado em pixels da tela → unidades do jogo
	var layer := _layer_of(f)
	var target: Object = layer if layer != null else vp
	if _moved != null and _moved != target: _restore()
	if _moved == null:
		_moved = target
		_orig = (layer.offset.y if layer != null else vp.canvas_transform.origin.y)
		_shift = 0.0
	# fundo do campo na tela, SEM o deslocamento que já aplicamos
	var bottom: float = (f as Control).get_global_rect().end.y + _orig
	var want := minf(0.0, (vs.y - kb_vp - GAP) - bottom)   # negativo = subir
	if absf(want - _shift) < 1.0: return
	_shift = want
	_apply(_orig + _shift)

func _layer_of(n: Node) -> CanvasLayer:
	var p := n.get_parent()
	while p != null:
		if p is CanvasLayer: return p
		p = p.get_parent()
	return null

func _apply(y: float):
	if _moved is CanvasLayer:
		var l := _moved as CanvasLayer
		l.offset = Vector2(l.offset.x, y)
	elif _moved is Viewport:
		var v := _moved as Viewport
		var t := v.canvas_transform
		t.origin.y = y
		v.canvas_transform = t

func _restore():
	if _moved == null: return
	if is_instance_valid(_moved): _apply(_orig)
	_moved = null
	_shift = 0.0
