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

func open(public_key: String, amount_cents: int, email: String, title: String, price: String):
    if not available(): return
    release_game_focus(get_viewport())
    if _cb == null:
        _cb = JavaScriptBridge.create_callback(_on_js)
        JavaScriptBridge.get_interface("window").fraihaCardCb = _cb
    is_open = true
    var cfg := {"pk": public_key, "amount": amount_cents / 100.0, "email": email, "title": title, "price": price, "sdk": SDK_URL}
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
    const ov = D.createElement('div'); ov.id = 'fraiha-card-overlay';
    ov.style.cssText = 'position:fixed;inset:0;z-index:60;background:rgba(3,9,5,.82);display:flex;align-items:flex-start;justify-content:center;padding:16px;box-sizing:border-box;overflow-y:auto;-webkit-overflow-scrolling:touch;';
    const box = D.createElement('div'); box.id = 'fraiha-card-box';
    box.style.cssText = 'width:100%;max-width:520px;margin:auto 0;background:#0e2618;border:2px solid #c99a44;border-radius:10px;box-shadow:0 12px 48px rgba(0,0,0,.65);padding:14px 16px 12px;box-sizing:border-box;color:#f2e6c6;font-family:Georgia,"Times New Roman",serif;';
    const head = D.createElement('div'); head.style.cssText = 'display:flex;align-items:center;gap:8px;margin-bottom:8px;';
    const badge = D.createElement('span'); badge.textContent = 'PAGAMENTO SEGURO · MERCADO PAGO';
    badge.style.cssText = 'font:700 11px Arial,sans-serif;letter-spacing:.05em;color:#9be89a;border:1px solid #3f9b4c;border-radius:4px;padding:4px 7px;';
    const gap = D.createElement('span'); gap.style.flex = '1';
    const x = D.createElement('button'); x.id = 'fraiha-card-close'; x.type = 'button'; x.textContent = '✕'; x.setAttribute('aria-label', 'Fechar');
    x.style.cssText = 'width:40px;height:40px;border-radius:8px;border:1px solid #c99a44;background:#14301f;color:#f4ce7f;font:20px Arial,sans-serif;cursor:pointer;';
    head.append(badge, gap, x);
    const title = D.createElement('div'); title.id = 'fraiha-card-title'; title.textContent = cfg.title;
    title.style.cssText = 'font-weight:700;font-size:22px;color:#f4ce7f;letter-spacing:.02em;';
    const price = D.createElement('div'); price.id = 'fraiha-card-price'; price.textContent = cfg.price;
    price.style.cssText = 'font-size:16px;color:#fff1c0;margin:2px 0 10px;';
    const msg = D.createElement('div'); msg.id = 'fraiha-card-msg';
    msg.style.cssText = 'display:none;font:600 15px Arial,sans-serif;line-height:1.35;padding:9px 11px;margin:0 0 10px;border:1px solid #c99a44;border-radius:6px;background:rgba(0,0,0,.25);';
    const load = D.createElement('div'); load.id = 'fraiha-card-loading'; load.textContent = 'Carregando o formulário seguro do Mercado Pago…';
    load.style.cssText = 'font:15px Arial,sans-serif;color:#ffe6a0;text-align:center;padding:26px 0;';
    const host = D.createElement('div'); host.id = 'fraihaCardBrick';
    const foot = D.createElement('div'); foot.textContent = 'Os dados do cartão vão direto para o Mercado Pago. O FRAIHA nunca vê o número nem o código de segurança. Pagamento à vista (1x).';
    foot.style.cssText = 'font:12px Arial,sans-serif;color:#b9ab86;text-align:center;margin-top:10px;line-height:1.35;';
    box.append(head, title, price, msg, load, host, foot); ov.appendChild(box); D.body.appendChild(ov);
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
                customization: { visual: { style: { theme: 'dark' }, hideFormTitle: true },
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
