extends Node
## Web no celular: tocar num LineEdit desenhado no canvas do Godot não abre o teclado virtual
## (não existe campo de texto real no DOM, e o navegador só abre o teclado ao focar um campo
## HTML dentro do próprio toque). Este ajudante coloca um <input> HTML de verdade exatamente
## sobre o LineEdit enquanto ele está visível: o toque cai nele, o navegador foca e abre o
## teclado (também no iOS). O texto é espelhado no LineEdit (que continua sendo a fonte usada
## pelo jogo) e Enter vira text_submitted. Fora da Web mobile não faz nada.
##
## R90 · modo CHAT (attach(line, true)): ao tocar no campo, ele vira uma barra fixa EMBAIXO da área
## visível (logo acima do teclado no iPhone e no Android; R151 — antes ficava no topo da tela) com um botão ENVIAR próprio, em HTML. Tocar no
## ENVIAR não tira o foco do campo (o teclado fica aberto e nada na tela pula), então o toque nunca se
## perde e dá para mandar várias mensagens seguidas. Tocar fora fecha o teclado e a barra volta ao lugar.
const Mobile = preload("res://ui_v022/mobile_layout.gd")
static var _next_id := 0
var field: LineEdit
var chat := false
var el: JavaScriptObject
var bar: JavaScriptObject
var win: JavaScriptObject
var dom_id := ""
var _last := ""
var _shown := false
var _was_docked := false

static func attach(line: LineEdit, chat_mode := false) -> Node:
    var helper = load("res://ui_v022/web_text_field.gd").new()
    helper.name = "WebTextField"
    helper.field = line
    helper.chat = chat_mode
    line.add_child(helper, false, Node.INTERNAL_MODE_BACK)
    return helper

## R152 · janelas por cima (convite, confirmação…): o campo HTML fica SEMPRE acima do canvas do jogo, então
## enquanto alguma janela cobre a tela os campos de baixo somem (antes o "Buscar jogador" aparecia por cima
## do cartão de convite). Cada janela marca/desmarca a si mesma; o campo dela mesma continua aparecendo.
static var _covers := {}
static func set_covered(owner: Object, on: bool) -> void:
    var id := owner.get_instance_id()
    if on: _covers[id] = owner
    else: _covers.erase(id)
static func _covered_for(f: Control) -> bool:
    for id in _covers.keys():
        var o = _covers[id]
        if not is_instance_valid(o):
            _covers.erase(id)
            continue
        if o is Node and (o as Node).is_ancestor_of(f): continue   # campo da própria janela
        return true
    return false

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
            const id = %s, chat = %s;
            const el = document.createElement('input');
            el.id = id; el.type = %s; el.maxLength = %d;
            el.autocomplete = 'off'; el.autocapitalize = 'sentences'; el.spellcheck = true;
            el.placeholder = %s; el.enterKeyHint = 'send';
            el.style.cssText = 'position:fixed;display:none;z-index:20;margin:0;border:0;outline:none;' +
                'background:transparent;color:#f2e6c6;caret-color:#f4ce7f;font:16px Georgia,"Times New Roman",serif;' +
                'padding:0 10px;box-sizing:border-box;-webkit-appearance:none;border-radius:6px';
            el.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); el.dataset.submit = '1'; } });
            if (!document.getElementById('fraiha-text-style')) {
                const st = document.createElement('style'); st.id = 'fraiha-text-style';
                st.textContent = 'input[id^=fraiha-text-]::placeholder{color:#b9ad8e;opacity:1}' +
                    '.fraiha-chat-bar{position:fixed;left:0;right:0;z-index:30;display:none;gap:8px;align-items:center;' +
                    'padding:8px 10px;box-sizing:border-box;background:rgba(14,10,8,.97);border-top:2px solid #c99a45;' +
                    'box-shadow:0 -4px 14px rgba(0,0,0,.55)}' +
                    '.fraiha-chat-bar button{flex:0 0 auto;height:46px;padding:0 16px;border-radius:8px;border:2px solid #7a5512;' +
                    'background:#e9b23a;color:#2a1a04;font:bold 16px Georgia,serif;letter-spacing:1px;touch-action:manipulation}' +
                    '.fraiha-chat-bar button:active{background:#ffd56a}';
                document.head.appendChild(st);
            }
            document.body.appendChild(el);
            if (!chat) return;
            // Barra do chat: faixa fixa no topo da área visível, com o ENVIAR à direita. O campo NÃO é movido
            // de lugar no DOM (mover um campo focado tira o foco): só muda de posição/estilo por cima da barra.
            const bar = document.createElement('div');
            bar.id = id + '-bar'; bar.className = 'fraiha-chat-bar';
            bar.style.justifyContent = 'flex-end';
            const send = document.createElement('button');
            send.type = 'button'; send.textContent = 'ENVIAR';
            const fire = () => { const t = Date.now(); if (t - (+el.dataset.ts || 0) < 400) return; el.dataset.ts = String(t); el.dataset.submit = '1'; };
            // pointerdown/touchstart/mousedown sem ação padrão: o campo continua focado e o teclado não fecha
            for (const ev of ['pointerdown', 'touchstart', 'mousedown']) send.addEventListener(ev, e => e.preventDefault(), {passive: false});
            send.addEventListener('touchend', e => { e.preventDefault(); fire(); }, {passive: false});
            send.addEventListener('click', e => { e.preventDefault(); fire(); });
            bar.appendChild(send);
            document.body.appendChild(bar);
            const vv = window.visualViewport;
            // R151 · barra EMBAIXO da área visível (logo acima do teclado), não no topo da tela: antes ficavam
            // duas faixas (a do topo com o campo e a do teclado embaixo) e parecia ter duas caixas de mensagem.
            const place = () => {
                const vtop = (vv && vv.offsetTop) || 0, vh = (vv && vv.height) || window.innerHeight;
                const h = bar.offsetHeight || 62;
                const top = Math.max(vtop, vtop + vh - h);
                bar.style.top = top + 'px';
                if (el.dataset.docked === '1') el.style.top = (top + 8) + 'px';
            };
            const dock = () => {
                if (el.dataset.docked === '1') return;
                el.dataset.docked = '1';
                el._geo = {left: el.style.left, top: el.style.top, width: el.style.width, height: el.style.height, fontSize: el.style.fontSize};
                bar.style.display = 'flex';
                setTimeout(place, 50); setTimeout(place, 300);   // o teclado ainda está subindo
                Object.assign(el.style, {left: '10px', width: 'calc(100%% - 132px)', height: '46px', fontSize: '16px', zIndex: '31',
                    background: '#1d1510', border: '1px solid #84754b'});
                place();
            };
            const undock = () => {
                if (el.dataset.docked !== '1') return;
                el.dataset.docked = '';
                bar.style.display = 'none';
                Object.assign(el.style, el._geo || {}, {zIndex: '20', background: 'transparent', border: '0'});
            };
            el.addEventListener('focus', dock);
            // o toque no ENVIAR não tira o foco (acima); qualquer outro blur (toque fora, teclado fechado) desencaixa
            el.addEventListener('blur', () => setTimeout(() => { if (document.activeElement !== el) undock(); }, 60));
            if (vv) { vv.addEventListener('resize', place); vv.addEventListener('scroll', place); }
        })()
    """ % [JSON.stringify(dom_id), "true" if chat else "false", JSON.stringify(kind), field.max_length if field.max_length > 0 else 512, JSON.stringify(field.placeholder_text)])
    var doc = JavaScriptBridge.get_interface("document")
    el = doc.getElementById(dom_id)
    if chat: bar = doc.getElementById(dom_id + "-bar")
    win = JavaScriptBridge.get_interface("window")
    # O LineEdit continua existindo (moldura e texto usados pelo jogo), mas quem mostra o texto é o campo HTML.
    for c in ["font_color", "font_placeholder_color", "caret_color"]:
        field.add_theme_color_override(c, Color(0, 0, 0, 0))
    # R90 · o LineEdit do Godot não pode pegar o foco: senão o Godot abre o PRÓPRIO teclado escondido e
    # disputa o foco com o campo HTML (no Android o texto ia para um, o toque para o outro).
    field.focus_mode = Control.FOCUS_NONE
    field.virtual_keyboard_enabled = false
    field.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _exit_tree():
    if el != null:
        el.blur()
        el.remove()
        el = null
    if bar != null:
        bar.remove()
        bar = null

## R155 · o campo HTML fica por cima de tudo e não é cortado pela rolagem do Godot: se o LineEdit está fora da
## parte visível de uma lista que rola (ex.: EXCLUIR CONTA, embaixo do texto), o campo aparecia solto em cima da
## barra de baixo — e tocar nele no iPhone fazia a página inteira pular (tela verde gigante). Só mostra quando o
## campo está (quase) todo dentro da área visível de todos os pais que cortam o conteúdo.
func _inside_clip() -> bool:
    var r := field.get_global_rect()
    var p := field.get_parent()
    while p != null:
        if p is Control and (p as Control).clip_contents:
            var c := (p as Control).get_global_rect()
            var i := c.intersection(r)
            if i.size.y < r.size.y * 0.8 or i.size.x < r.size.x * 0.5: return false
        if p is CanvasLayer: break
        p = p.get_parent()
    return true

func docked() -> bool:
    return el != null and str(el.dataset.docked) == "1"

func _process(_delta):
    if el == null: return
    var show := field.is_visible_in_tree() and field.editable and not _covered_for(field) and (docked() or _inside_clip())
    if show != _shown:
        _shown = show
        if not show:
            el.blur()
            if bar != null: bar.style.display = "none"
        el.style.display = "block" if show else "none"
    if not show: return
    # R104.1 · com o teclado aberto o campo vai para a barra de cima do teclado (com o próprio ENVIAR): a linha do jogo
    # (caixa vazia + ENVIAR) some enquanto isso — antes apareciam DOIS lugares para digitar. O espaço fica
    # reservado (só fica transparente), então nada na tela pula quando o teclado abre ou fecha.
    if chat:
        var d := docked()
        if d != _was_docked:
            _was_docked = d
            var row := field.get_parent() as CanvasItem
            if row != null: row.modulate.a = 0.0 if d else 1.0
    if not docked():
        # Posição: coordenadas do viewport → pixels CSS da página (o canvas ocupa a janela).
        var xf := field.get_global_transform_with_canvas()
        var vp := field.get_viewport().get_visible_rect().size
        var css := Vector2(float(win.innerWidth), float(win.innerHeight))
        var k := Vector2(css.x / maxf(1.0, vp.x), css.y / maxf(1.0, vp.y))
        var pos := xf.origin * k
        var size := field.size * xf.get_scale() * k
        el.style.left = "%dpx" % roundi(pos.x)
        el.style.top = "%dpx" % roundi(pos.y)
        el.style.width = "%dpx" % roundi(size.x)
        el.style.height = "%dpx" % roundi(size.y)
        el.style.fontSize = "%dpx" % clampi(roundi(size.y * 0.42), 16, 28)   # 16 px no mínimo: o iPhone não dá zoom
    # Senha: o botão de mostrar/ocultar do jogo troca também o tipo do campo HTML.
    if field.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_PASSWORD:
        var want := "password" if field.secret else "text"
        if str(el.type) != want: el.type = want
    if str(el.placeholder) != field.placeholder_text: el.placeholder = field.placeholder_text
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
