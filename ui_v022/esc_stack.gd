extends RefCounted
## R129 · ESC EM TUDO: toda janela/painel por cima do jogo se registra aqui (grupo "esc_closable"). O ESC fecha
## SÓ a de cima (maior camada de tela; empate = a aberta por último na árvore). Sem nenhuma aberta, o ESC segue o
## caminho de sempre (stage: página da Home volta, partida pede para sair, etc.).
## Cada janela responde: esc_open() -> bool (está aberta?) e esc_close() (o que o VOLTAR/FECHAR dela faz).
## Sem esses métodos: usa is_open()/close() (ou visible/hide).
const GROUP := "esc_closable"

static func register(n: Node):
	if not n.is_in_group(GROUP): n.add_to_group(GROUP)

static func is_open(n: Node) -> bool:
	if not is_instance_valid(n) or not n.is_inside_tree(): return false
	if n.has_method("esc_open"): return bool(n.esc_open())
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree(): return false
	if n.has_method("is_open"): return bool(n.is_open())
	if n is CanvasLayer: return (n as CanvasLayer).visible
	return n is CanvasItem

static func layer_of(n: Node) -> int:
	if n.has_method("esc_layer"): return int(n.esc_layer())
	var p: Node = n
	while p != null:
		if p is CanvasLayer: return (p as CanvasLayer).layer
		p = p.get_parent()
	return 0

## A janela aberta mais de cima (ou null).
static func top(tree: SceneTree) -> Node:
	var best: Node = null
	var best_layer: int = -1000000000
	for n in tree.get_nodes_in_group(GROUP):
		if not is_open(n): continue
		var l := layer_of(n)
		if best == null or l > best_layer or (l == best_layer and n.is_greater_than(best)):
			best = n
			best_layer = l
	return best

static func close(n: Node):
	if n.has_method("esc_close"): n.esc_close()
	elif n.has_method("close"): n.close()
	elif n is CanvasItem: (n as CanvasItem).hide()
	elif n is CanvasLayer: (n as CanvasLayer).hide()

## Trata um ESC: fecha a janela de cima. true = consumido.
static func handle(tree: SceneTree) -> bool:
	var t := top(tree)
	if t == null: return false
	close(t)
	return true
