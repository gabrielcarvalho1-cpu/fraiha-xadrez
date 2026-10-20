# R171 · SEC-011 — CSP do site do jogo (jogar.fraihaxadrez.com)

Estado: **pronto, em modo RELATÓRIO (report-only)**. Ele não bloqueia nada. Não está publicado.

## O que é

O CSP diz ao navegador de onde a página pode carregar scripts e com quais servidores pode conversar. Se um script estranho entrar na página (extensão, injeção, link malicioso), ele não consegue mandar dados para fora nem carregar código de outro lugar.

No modo **report-only** o navegador só **avisa** o que bloquearia. Os avisos chegam ao servidor em `POST /csp-report` e aparecem no log do Render como `[csp-report] {"directive":…,"blocked":…}`. O aviso traz só a regra e o host bloqueado: sem caminho, sem consulta, sem dado do jogador. Há limite de 20 avisos por minuto por IP e 300 no total, e avisos iguais entram 1 vez a cada 10 min.

## Política

A política está em `web/cdn/fraiha-web-worker.mjs`, na constante `CSP_POLICY`. O teste `tests/server/csp_r171_test.cjs` garante que não há curinga solto.

| Diretiva | Liberado | Por quê |
|---|---|---|
| `script-src` | `'self'` `'unsafe-inline'` `'unsafe-eval'` `'wasm-unsafe-eval'`, Agora no jsDelivr (só o caminho `agora-rtc-sdk-ng@4.24.8/`), SDK do Mercado Pago, `*.mercadopago.com` `*.mercadolibre.com` `*.mlstatic.com`, beacon do Cloudflare | Godot com `<script>` inline no shell e `JavaScriptBridge.eval` (usa `eval`), WebAssembly (Godot e Stockfish), voz, cartão |
| `worker-src` | `'self'` `blob:` | Motor de análise (Stockfish em Worker), Agora |
| `connect-src` | `'self'`, servidor FRAIHA (wss/https, produção e staging), Supabase do projeto, `*.agora.io` `*.sd-rtn.com` (wss/https), Mercado Pago, beacon do Cloudflare | Jogo online, contas, fotos, voz, pagamento |
| `img-src` | `'self'` `data:` `blob:`, Supabase, Mercado Pago | Fotos do perfil, bandeiras do cartão |
| `media-src` | `'self'` `data:` `blob:` `mediastream:` | Música, voz |
| `font-src` / `style-src` | `'self'` (+ `'unsafe-inline'` no style), Mercado Pago | Formulário do cartão |
| `frame-src` | domínios do Mercado Pago / Mercado Livre | Campos seguros do cartão (iframes) |
| `object-src` | `'none'` | Sem plugins |
| `base-uri` | `'self'` | Ninguém troca a base dos links |
| `form-action` | `'self'`, Mercado Pago | |
| `frame-ancestors` | `'self'` | Ninguém põe o jogo dentro de outro site para enganar cliques. **Se o jogo for embutido em outro portal (itch.io, etc.), incluir o domínio aqui antes de ativar.** |

**Limite honesto:** `'unsafe-inline'` e `'unsafe-eval'` no `script-src` são necessários hoje, porque o Godot depende deles. Por isso o ganho principal **não** é bloquear script injetado. O ganho está em:

- `connect-src`: dados não saem para servidores estranhos;
- `object-src`, `base-uri`, `frame-src`: fecham caminhos de ataque;
- `frame-ancestors`: evita clickjacking.

## Teste com o build real (Chromium, CSP em modo de BLOQUEIO)

`tests/web/csp_e2e.py` sobe o export Web R169 com engines/, voice/ e gl_recovery/, aplica a política **bloqueando** (mais rígido que o report-only) e confere:

| Item | Resultado |
|---|---|
| Godot carrega e mostra a tela de entrar (print conferido) | OK |
| Stockfish em Worker (WASM) responde `uciok` | OK |
| SDK de voz Agora 4.24.8 carrega, cria cliente e microfone | OK |
| Campo HTML (teclado do celular) recebe foco | OK |
| Áudio (AudioContext) | running |
| `eval` (JavaScriptBridge) | OK |
| WebSocket para o servidor FRAIHA | não bloqueado pelo CSP (falhou só por rede do ambiente de teste) |
| `fetch` para domínio estranho | **bloqueado** (1 violação, a esperada) |
| SDK do Mercado Pago | **não verificado**: sem internet no ambiente de teste. Por isso o report-only vem primeiro |

## Como publicar (quando aprovado)

Escolha **uma** das opções:

1. **Regra no Cloudflare (sem código)**: Rules → Transform Rules → Modify Response Header → hostname `jogar.fraihaxadrez.com` e caminho `/` ou `/index.html` → **Set** `Content-Security-Policy-Report-Only` = valor de `CSP_POLICY`.
2. **Worker** `web/cdn/fraiha-web-worker.mjs`, que já põe o cabeçalho só no `index.html`. Observação: esse Worker é a PROPOSTA R55.5 e ainda não está publicado.

O servidor R171 precisa estar no ar para receber os avisos em `/csp-report`.

Depois, olhe o log do Render por 1–2 semanas e jogue tudo:

- online;
- voz;
- PIX;
- cartão;
- análise;
- foto.

Sem avisos legítimos, troque o nome do cabeçalho para `Content-Security-Policy`, o que liga o bloqueio. Para desfazer, basta apagar a regra ou o cabeçalho.
