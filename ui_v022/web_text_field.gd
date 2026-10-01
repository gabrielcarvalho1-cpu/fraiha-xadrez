extends Node
## Web no celular: tocar num LineEdit desenhado no canvas do Godot não abre o teclado virtual
## (não existe campo de texto real no DOM, e o navegador só abre o teclado ao focar um campo
## HTML dentro do próprio toque). Este ajudante coloca um <input> HTML de verdade exatamente
## sobre o LineEdit enquanto ele está visível: o toque cai nele, o navegador foca e abre o
## teclado (também no iOS). O texto é espelhado no LineEdit (que continua sendo a fonte usada
## pelo jogo) e Enter vira text_submitted. Fora da Web mobile não faz nada.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
static var _next_id := 0
var field: LineEdit
var el: JavaScriptObject
var dom_id := ""
var _last := ""
var _shown := false

static func attach(line: LineEdit) -> Node:
    var helper = load("res://ui_v022/web_text_field.gd").new()
    helper.name = "WebTextField"
    helper.field = line
    line.add_child(helper, false, Node.INTERNAL_MODE_BACK)
    return helper

static func wanted(viewport: Viewport) -> bool:
    return OS.has_feature("web") and Mobile.active(viewport)

func _ready():
    if not wanted(get_viewport()):
        set_process(false)
        return
    _next_id += 1
    dom_id = "fraiha-text-%d" % _next_id
    var kind := "email" if field.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS else ("password" if field.secret else "text")
    JavaScriptBridge.eval("""
        (() => {
            const el = document.createElement('input');
            el.id = %s; el.type = %s; el.maxLength = %d;
            el.autocomplete = 'off'; el.autocapitalize = 'sentences'; el.spellcheck = true;
            el.placeholder = %s; el.enterKeyHint = 'send';
            el.style.cssText = 'position:fixed;display:none;z-index:20;margin:0;border:0;outline:none;' +
                'background:transparent;color:#f2e6c6;caret-color:#f4ce7f;font:16px Georgia,"Times New Roman",serif;' +
                'padding:0 10px;box-sizing:border-box;-webkit-appearance:none;border-radius:6px';
            el.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); el.dataset.submit = '1'; } });
            if (!document.getElementById('fraiha-text-style')) {
                const st = document.createElement('style'); st.id = 'fraiha-text-style';
                st.textContent = 'input[id^=fraiha-text-]::placeholder{color:#b9ad8e;opacity:1}';
                document.head.appendChild(st);
            }
            document.body.appendChild(el);
        })()
    """ % [JSON.stringify(dom_id), JSON.stringify(kind), field.max_length if field.max_length > 0 else 512, JSON.stringify(field.placeholder_text)])
    el = JavaScriptBridge.get_interface("document").getElementById(dom_id)
    # O LineEdit continua existindo (moldura e texto usados pelo jogo), mas quem mostra o texto é o campo HTML.
    for c in ["font_color", "font_placeholder_color", "caret_color"]:
        field.add_theme_color_override(c, Color(0, 0, 0, 0))

func _exit_tree():
    if el != null:
        el.blur()
        el.remove()
        el = null

func _process(_delta):
    if el == null: return
    var show := field.is_visible_in_tree() and field.editable
    if show != _shown:
        _shown = show
        el.style.display = "block" if show else "none"
        if not show: el.blur()
    if not show: return
    # Posição: coordenadas do viewport → pixels CSS da página (o canvas ocupa a janela).
    var xf := field.get_global_transform_with_canvas()
    var vp := field.get_viewport().get_visible_rect().size
    var css := Vector2(float(JavaScriptBridge.eval("window.innerWidth")), float(JavaScriptBridge.eval("window.innerHeight")))
    var k := Vector2(css.x / maxf(1.0, vp.x), css.y / maxf(1.0, vp.y))
    var pos := xf.origin * k
    var size := field.size * xf.get_scale() * k
    el.style.left = "%dpx" % roundi(pos.x)
    el.style.top = "%dpx" % roundi(pos.y)
    el.style.width = "%dpx" % roundi(size.x)
    el.style.height = "%dpx" % roundi(size.y)
    el.style.fontSize = "%dpx" % clampi(roundi(size.y * 0.42), 14, 28)   # acompanha a escala do campo do jogo
    # Senha: o botão de mostrar/ocultar do jogo troca também o tipo do campo HTML.
    if field.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_PASSWORD:
        var want := "password" if field.secret else "text"
        if str(el.type) != want: el.type = want
    # Espelha o texto nos dois sentidos (o jogo limpa o campo depois de enviar).
    var dom := str(el.value)
    if dom != _last:
        field.text = dom
        field.caret_column = dom.length()
        field.text_changed.emit(dom)
    elif field.text != _last:
        el.value = field.text
    _last = field.text
    if str(el.dataset.submit) == "1":
        el.dataset.submit = ""
        field.text_submitted.emit(field.text)
        _last = field.text
        el.value = field.text
