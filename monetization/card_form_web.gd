extends Node
## R40 · CARTÃO DENTRO DO JOGO (Web): o formulário seguro do Mercado Pago (Card Payment Brick) aparece
## numa janela por cima do jogo. Os campos de número/validade/CVV são do próprio Mercado Pago (iframes
## seguros): o FRAIHA só recebe um TOKEN de uso único, que o servidor usa para criar o pagamento.
## Fora da Web (desktop), ou se o formulário não carregar, quem usa cai na página do Mercado Pago.
##
## Fluxo: open() → [form_ready] → jogador preenche → [submitted(dados)] → o jogo manda ao servidor →
##        resolve_ok() / resolve_reject(mensagem) → (o formulário libera para tentar de novo) → close().
signal form_ready
signal submitted(data: Dictionary)
signal closed
signal failed(reason: String)        # o formulário não carregou: usar a página do Mercado Pago

const SDK_URL := "https://sdk.mercadopago.com/js/v2"
var _cb: JavaScriptObject
var is_open := false

static func available() -> bool:
    return OS.has_feature("web")

## Tira o foco de qualquer campo do jogo antes de abrir o formulário. Com um LineEdit focado, o Godot
## Web mantém o campo de texto interno dele (IME) ativo e devolve o foco para ele a cada 100 ms —
## aí o que o jogador digitasse no formulário do Mercado Pago iria para o jogo (visto no Chromium).
static func release_game_focus(vp: Viewport):
    if vp != null: vp.gui_release_focus()
    if DisplayServer.has_feature(DisplayServer.FEATURE_IME): DisplayServer.window_set_ime_active(false)
    if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()

func open(public_key: String, amount_cents: int, email: String, title: String, price: String, club := false):
    if not available(): return
    release_game_focus(get_viewport())
    if _cb == null:
        _cb = JavaScriptBridge.create_callback(_on_js)
        JavaScriptBridge.get_interface("window").fraihaCardCb = _cb
    is_open = true
    var cfg := {"pk": public_key, "amount": amount_cents / 100.0, "email": email, "title": title, "price": price, "sdk": SDK_URL, "club": club}
    JavaScriptBridge.eval(JS_OPEN.replace("__CFG__", JSON.stringify(cfg)))

## Pagamento aprovado/pendente: libera o formulário (some o "processando").
func resolve_ok():
    if available(): JavaScriptBridge.eval("(() => { const s = window.__fraihaCard; if (s && s.res) { const r = s.res; s.res = s.rej = null; r(); } })()")

## Cartão recusado: o formulário volta a aceitar dados e a mensagem aparece em vermelho no topo.
func resolve_reject(message: String):
    if not available(): return
    JavaScriptBridge.eval("(() => { const s = window.__fraihaCard; if (s && s.rej) { const r = s.rej; s.res = s.rej = null; r(); } })()")
    show_message(message, "error")

func show_message(text: String, kind := "info"):
    if not available(): return
    JavaScriptBridge.eval("(() => { const m = document.getElementById('fraiha-card-msg'); if (!m) return; m.textContent = %s; m.style.display = %s; m.style.color = %s; m.style.borderColor = %s; })()" % [
        JSON.stringify(text), JSON.stringify("none" if text.is_empty() else "block"),
        JSON.stringify("#ffb08a" if kind == "error" else "#ffe6a0"), JSON.stringify("#b5532f" if kind == "error" else "#c99a44")])

func close():
    if not is_open: return
    is_open = false
    if available(): JavaScriptBridge.eval(JS_CLOSE)

func _exit_tree():
    close()

## O navegador chama fraihaCardCb(tipo, dados) com 2 strings (dados = JSON achatado).
func _on_js(args: Array):
    var kind := str(args[0]) if args.size() > 0 else ""
    var data := str(args[1]) if args.size() > 1 else ""
    match kind:
        "ready": form_ready.emit()
        "submit":
            var d = JSON.parse_string(data)
            if d is Dictionary: submitted.emit(d)
            else: resolve_reject("Não foi possível ler os dados do formulário. Tente de novo.")
        "close":
            close()
            closed.emit()
        "load_failed":
            close()
            failed.emit(data)
        "error":
            var e = JSON.parse_string(data)
            # Erros "críticos" impedem o formulário de funcionar → página do Mercado Pago.
            if e is Dictionary and String(e.get("type", "")) == "critical":
                close()
                failed.emit(String(e.get("cause", "critical")))

const JS_CLOSE := """
(() => {
    const s = window.__fraihaCard || {};
    if (s.ctrl) { try { s.ctrl.unmount(); } catch (e) {} s.ctrl = null; }
    s.res = s.rej = null;
    if (s.onKey) { document.removeEventListener('keydown', s.onKey, true); s.onKey = null; }
    const o = document.getElementById('fraiha-card-overlay'); if (o) o.remove();
})()
"""

const JS_OPEN := """
(() => {
    const W = window, D = document, cfg = __CFG__;
    const s = W.__fraihaCard = W.__fraihaCard || {};
    const cb = (k, v) => { try { W.fraihaCardCb(k, v || ''); } catch (e) {} };
    if (s.ctrl) { try { s.ctrl.unmount(); } catch (e) {} s.ctrl = null; }
    const old = D.getElementById('fraiha-card-overlay'); if (old) old.remove();
    // R176 · mesma arte das telas de pagamento do jogo (PIX): moldura escura com losangos, borda dourada dupla,
    // gemas nos cantos, selo azul PAGAMENTO SEGURO, títulos em Cinzel dourado. Nada de verde.
    const gem = cfg.club ? ['#7fb6ff', '#1d4c99'] : ['#ff5a4a', '#8a1712'];
    const bgTop = cfg.club ? '#12141a' : '#1c140a', bgBot = cfg.club ? '#050608' : '#080503';
    if (!D.getElementById('fraiha-cinzel')) {
        const lf = D.createElement('link'); lf.id = 'fraiha-cinzel'; lf.rel = 'stylesheet';
        lf.href = 'https://fonts.googleapis.com/css2?family=Cinzel:wght@600;700&display=swap'; D.head.appendChild(lf);
    }
    const CIN = '"Cinzel",Georgia,"Times New Roman",serif';
    const ov = D.createElement('div'); ov.id = 'fraiha-card-overlay';
    ov.style.cssText = 'position:fixed;inset:0;z-index:60;background:rgba(2,3,6,.84);display:flex;align-items:flex-start;justify-content:center;padding:max(14px,env(safe-area-inset-top)) max(12px,env(safe-area-inset-right)) max(14px,env(safe-area-inset-bottom)) max(12px,env(safe-area-inset-left));box-sizing:border-box;overflow-y:auto;-webkit-overflow-scrolling:touch;';
    const box = D.createElement('div'); box.id = 'fraiha-card-box';
    box.style.cssText = 'position:relative;width:100%;max-width:520px;margin:auto 0;box-sizing:border-box;padding:18px 18px 14px;color:#f4e8c8;font-family:Georgia,"Times New Roman",serif;'
        + 'background:repeating-linear-gradient(45deg,rgba(201,154,69,.06) 0 1px,transparent 1px 26px),repeating-linear-gradient(-45deg,rgba(201,154,69,.06) 0 1px,transparent 1px 26px),linear-gradient(180deg,' + bgTop + ',' + bgBot + ');'
        + 'border:3px solid #c99a45;border-radius:4px;box-shadow:inset 0 0 0 2px #6e4b18,inset 0 0 0 3px rgba(241,213,138,.55),0 14px 50px rgba(0,0,0,.7);';
    const mkGem = (css) => { const g = D.createElement('span');
        g.style.cssText = 'position:absolute;width:12px;height:12px;transform:rotate(45deg);background:radial-gradient(circle at 35% 35%,#fff6 0 18%,' + gem[0] + ' 20% 60%,' + gem[1] + ' 100%);border:2px solid #d9b25a;box-shadow:0 0 6px rgba(0,0,0,.6);' + css; return g; };
    box.append(mkGem('left:-9px;top:-9px'), mkGem('right:-9px;top:-9px'), mkGem('left:-9px;bottom:-9px'), mkGem('right:-9px;bottom:-9px'), mkGem('left:calc(50% - 8px);top:-9px'));
    const head = D.createElement('div'); head.style.cssText = 'display:flex;align-items:center;gap:10px;margin-bottom:10px;';
    const badge = D.createElement('span'); badge.append('PAGAMENTO SEGURO', D.createElement('br'), 'MERCADO PAGO');
    badge.style.cssText = 'font:700 13px/1.2 ' + CIN + ';letter-spacing:.03em;color:#f4e8c8;text-align:center;padding:7px 18px;background:linear-gradient(180deg,#2a4ba3,#172d6b);border:2px solid #d9b25a;clip-path:polygon(9px 0,calc(100% - 9px) 0,100% 50%,calc(100% - 9px) 100%,9px 100%,0 50%);';
    const gap = D.createElement('span'); gap.style.flex = '1';
    const x = D.createElement('button'); x.id = 'fraiha-card-close'; x.type = 'button'; x.textContent = '✕'; x.setAttribute('aria-label', 'Fechar');
    x.style.cssText = 'width:42px;height:42px;flex:none;border-radius:4px;border:2px solid #c99a45;background:linear-gradient(180deg,#3a1610,#160806);color:#f1d58a;font:20px Arial,sans-serif;cursor:pointer;animation:fraihaBackPulse 2s ease-in-out infinite;';
    // R176 · botão de sair avermelhado "respirando" devagar (igual aos VOLTAR/SAIR do jogo)
    if (!D.getElementById('fraiha-back-pulse-css')) {
        const st = D.createElement('style'); st.id = 'fraiha-back-pulse-css';
        st.textContent = '@keyframes fraihaBackPulse{0%,100%{box-shadow:inset 0 0 0 1px #6e4b18,0 0 2px rgba(220,40,30,.25)}50%{box-shadow:inset 0 0 0 1px #6e4b18,inset 0 0 14px rgba(220,40,30,.45),0 0 10px rgba(220,40,30,.55)}}';
        D.head.appendChild(st);
    }
    head.append(badge, gap, x);
    const title = D.createElement('div'); title.id = 'fraiha-card-heading'; title.textContent = 'PAGUE COM CARTÃO';
    title.style.cssText = 'font:700 24px ' + CIN + ';color:#f1d58a;text-align:center;letter-spacing:.02em;text-shadow:0 2px 0 #000;margin-top:4px;';
    const sub = D.createElement('div'); sub.id = 'fraiha-card-title'; sub.textContent = cfg.title;
    sub.style.cssText = 'font:600 14px ' + CIN + ';color:#c9c2a8;text-align:center;margin-top:2px;';
    const price = D.createElement('div'); price.id = 'fraiha-card-price'; price.textContent = cfg.price;
    price.style.cssText = 'font:600 15px ' + CIN + ';color:#fff1c0;text-align:center;margin:6px 0 12px;';
    const msg = D.createElement('div'); msg.id = 'fraiha-card-msg';
    msg.style.cssText = 'display:none;font:600 15px Arial,sans-serif;line-height:1.35;padding:9px 11px;margin:0 0 10px;border:1px solid #c99a44;border-radius:4px;background:rgba(0,0,0,.3);';
    const load = D.createElement('div'); load.id = 'fraiha-card-loading'; load.textContent = 'Carregando o formulário seguro do Mercado Pago…';
    load.style.cssText = 'font:15px Arial,sans-serif;color:#ffe6a0;text-align:center;padding:26px 0;';
    const host = D.createElement('div'); host.id = 'fraihaCardBrick';
    host.style.cssText = 'border:1px solid rgba(201,154,69,.55);border-radius:4px;box-shadow:inset 0 0 0 1px rgba(0,0,0,.6);overflow:hidden;';
    const foot = D.createElement('div'); foot.textContent = 'Os dados do cartão vão direto para o Mercado Pago. O FRAIHA nunca vê o número nem o código de segurança. Pagamento à vista (1x).';
    foot.style.cssText = 'font:12px Arial,sans-serif;color:#c9c2a8;text-align:center;margin-top:12px;line-height:1.35;';
    box.append(head, title, sub, price, msg, load, host, foot); ov.appendChild(box); D.body.appendChild(ov);
    x.addEventListener('click', () => cb('close'));
    s.onKey = (e) => { if (e.key === 'Escape' && D.getElementById('fraiha-card-overlay')) { e.stopPropagation(); cb('close'); } };
    D.addEventListener('keydown', s.onKey, true);
    // As teclas digitadas nos campos não podem ir para o jogo por baixo.
    ov.addEventListener('keydown', (e) => e.stopPropagation());
    const go = () => {
        try {
            const mp = new W.MercadoPago(cfg.pk, { locale: 'pt-BR' });
            mp.bricks().create('cardPayment', 'fraihaCardBrick', {
                initialization: { amount: cfg.amount, payer: { email: cfg.email } },
                // R176 · cores do jogo no formulário do Mercado Pago (campos escuros, botão dourado, contornos dourados)
                customization: { visual: { hideFormTitle: true, style: { theme: 'dark', customVariables: {
                        formBackgroundColor: '#0d0a06', inputBackgroundColor: '#07060a',
                        textPrimaryColor: '#f4e8c8', textSecondaryColor: '#c9c2a8',
                        baseColor: '#d9b25a', baseColorFirstVariant: '#f1d58a', baseColorSecondVariant: '#8a6224',
                        buttonTextColor: '#1a1208', outlinePrimaryColor: '#c99a45', outlineSecondaryColor: '#6e4b18',
                        errorColor: '#ff9a7a', successColor: '#8fd88a',
                        borderRadiusSmall: '3px', borderRadiusMedium: '4px', borderRadiusLarge: '6px', borderRadiusFull: '6px',
                        inputFocusedBoxShadow: '0 0 0 2px rgba(241,213,138,.45)' } } },
                    paymentMethods: { maxInstallments: 1, minInstallments: 1 } },
                callbacks: {
                    onReady: () => { load.style.display = 'none'; cb('ready'); },
                    onSubmit: (fd, extra) => new Promise((res, rej) => {
                        s.res = res; s.rej = rej;
                        const p = (fd && fd.payer) || {}, id = p.identification || {};
                        cb('submit', JSON.stringify({ token: fd.token || '', payment_method_id: fd.payment_method_id || '', issuer_id: String(fd.issuer_id || ''),
                            id_type: id.type || '', id_number: id.number || '', device_id: W.MP_DEVICE_SESSION_ID || '' }));
                    }),
                    onError: (e) => cb('error', JSON.stringify({ type: (e && e.type) || '', cause: (e && e.cause) || '', message: (e && e.message) || '' })),
                },
            }).then((c) => { s.ctrl = c; if (!D.getElementById('fraiha-card-overlay')) { try { c.unmount(); } catch (e) {} } })
              .catch((e) => cb('load_failed', String((e && e.message) || e)));
        } catch (e) { cb('load_failed', String((e && e.message) || e)); }
    };
    if (W.MercadoPago) { go(); return; }
    let sc = D.getElementById('fraiha-mp-sdk');
    if (!sc) { sc = D.createElement('script'); sc.id = 'fraiha-mp-sdk'; sc.src = W.__FRAIHA_MP_SDK || cfg.sdk; sc.async = true; D.head.appendChild(sc); }
    const t = setTimeout(() => cb('load_failed', 'timeout'), 15000);
    sc.addEventListener('load', () => { clearTimeout(t); if (W.MercadoPago) go(); else cb('load_failed', 'sdk'); });
    sc.addEventListener('error', () => { clearTimeout(t); sc.remove(); cb('load_failed', 'script'); });
})()
"""
