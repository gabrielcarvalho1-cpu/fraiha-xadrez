extends Control
## R176 · BOTÕES DE VOLTAR / SAIR / DESISTIR / FECHAR / CANCELAR / INÍCIO em TODO o jogo: um leve tom avermelhado
## que "respira" devagar (nada brusco), para quem não conhece o jogo achar a saída rápido.
## Não muda a arte nem o clique: é uma camada por cima do botão (ignora o mouse), também nos botões "fantasma"
## que ficam sobre a arte pintada (INÍCIO do tabuleiro, VOLTAR À HOME das Configurações…).
## Ligado uma vez no stage (watch): todo botão que entra na árvore é conferido pelo texto e pelo nome.

const PERIOD := 2.0                  # segundos por "respiração"
const FILL_MIN := 0.10
const FILL_MAX := 0.24
const EDGE_MIN := 0.40
const EDGE_MAX := 0.85
const RED := Color(0.86, 0.16, 0.12)
const RED_EDGE := Color(1.0, 0.36, 0.28)

## textos de saída (começo do texto, sem acento/maiúscula)
const WORDS := ["voltar", "sair", "desistir", "fechar", "cancelar", "inicio", "não", "nao", "← voltar", "‹ voltar", "< voltar"]
## nomes de nó de botões de saída (fim do nome)
const NAME_ENDS := ["Back", "Cancel", "Close", "Resign", "Leave", "Exit", "BackText", "ResignText"]
const NAME_EXACT := ["HomeButton", "home", "MenuResign", "VoiceLeave", "PaymentCancelOpen", "PaymentCancelRetry"]
const SKIP_META := "no_back_pulse"   # botão que NÃO deve piscar (set_meta(SKIP_META, true))

var _t := 0.0
var radius := 6.0

static func watch(tree: SceneTree) -> void:
	if tree.has_meta("back_pulse_watch"): return
	tree.set_meta("back_pulse_watch", true)
	tree.node_added.connect(func(n: Node):
		if n is BaseButton:
			# o texto costuma ser preenchido logo depois do add_child: confere no fim do quadro e de novo depois
			(func(): _check(n)).call_deferred()
			tree.create_timer(0.25).timeout.connect(func(): _check(n)))
	# o que já estava na árvore antes de ligar (cena principal, Home)
	(func(): _sweep(tree.root)).call_deferred()
	tree.create_timer(1.0).timeout.connect(func(): _sweep(tree.root))

static func _sweep(n: Node) -> void:
	if not is_instance_valid(n): return
	for b in n.find_children("*", "BaseButton", true, false): _check(b)

static func is_exit(b: BaseButton) -> bool:
	if b.has_meta(SKIP_META): return false
	var nm := String(b.name)
	if nm.begins_with("RefNav_"): return false   # abas da barra de baixo do celular (INÍCIO = a própria Home)
	if nm in NAME_EXACT: return true
	for e in NAME_ENDS:
		if nm.ends_with(e) and not nm.ends_with("Backdrop"): return true
	var texts: Array = []
	if b is Button: texts.append(String((b as Button).text))
	if b.has_meta("title"): texts.append(String(b.get_meta("title")))
	# botões de arte com o texto num Label filho (barra de baixo do celular, cartões de página…)
	for c in b.get_children():
		if c is Label: texts.append(String(c.text))
		for cc in c.get_children():
			if cc is Label: texts.append(String(cc.text))
	for raw in texts:
		var t := String(raw).strip_edges().to_lower().replace("í", "i").replace("à", "a").replace("Í", "i")
		if t.is_empty(): continue
		if t == "✕" or t == "x" or t == "×": return true
		for w in WORDS:
			if t.begins_with(w): return true
	return false

static func _check(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree(): return
	var b := n as BaseButton
	if b == null or b.has_node("BackPulse") or not is_exit(b): return
	attach(b)

static func attach(c: Control) -> Control:
	if c.has_node("BackPulse"): return c.get_node("BackPulse")
	var p = load("res://ui_kit/back_pulse.gd").new()
	p.name = "BackPulse"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.show_behind_parent = false
	c.add_child(p)
	return p

func _ready():
	_t = randf() * 0.3

func _process(d):
	if not is_visible_in_tree(): return
	_t += d
	queue_redraw()

func _draw():
	var par := get_parent() as Control
	if par == null or size.x < 4.0 or size.y < 4.0: return
	if par is BaseButton and (par as BaseButton).disabled: return
	var w := 0.5 - 0.5 * cos(_t * TAU / PERIOD)          # 0 → 1 → 0 suave
	var r := minf(radius, minf(size.x, size.y) * 0.25)
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var fill := RED
	fill.a = lerpf(FILL_MIN, FILL_MAX, w)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(r))
	sb.border_color = Color(RED_EDGE.r, RED_EDGE.g, RED_EDGE.b, lerpf(EDGE_MIN, EDGE_MAX, w))
	sb.set_border_width_all(2)
	sb.shadow_color = Color(RED.r, RED.g, RED.b, lerpf(0.0, 0.30, w))
	sb.shadow_size = int(lerpf(2.0, 9.0, w))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
