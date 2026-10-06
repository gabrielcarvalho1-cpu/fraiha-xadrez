# FRAIHA Voice v1 — voz entre jogadores humanos (R45)

Áudio em tempo real **só entre humanos**, **só em partida online ativa**:
Casual, Ranked, desafio de amigo (convite), MARCHA REAL online e XEQUE online.
Nunca contra bot, offline, local, treino ou análise. Bots nunca entram na voz.
Sem vídeo, sem gravação, sem armazenamento, sem transcrição, sem IA sobre conversas.

## Arquitetura

```
modo de jogo (stage.voice_context / marcha_ui / xeque_ui)
   └─ FraihaVoice            voice/fraiha_voice.gd        (estado, regras, UI de texto)
        └─ VoiceProvider     voice/voice_provider.gd      (interface)
             ├─ AgoraVoiceProvider  voice/agora_voice_provider.gd  (Web, JavaScriptBridge)
             │     └─ web/voice/fraiha-voice-bridge-v1.js  →  web/voice/AgoraRTC_N-4.24.8.js
             └─ MockVoiceProvider   voice/mock_voice_provider.gd   (testes headless)
servidor: online_v021/voice/service.js (+ agora_token.js)  ← voice_join / voice_renew / voice_leave
```

- Nenhum modo chama a Agora. Trocar de provedor = novo `VoiceProvider` + nova ponte; os modos não mudam.
- A voz **segue** a partida: `stage.voice_context()` diz qual partida PvP humana está ativa
  (Ranked/Casual pelo controlador; Marcha/XEQUE pela mesa online com ≥ 2 humanos). Sem contexto → sai da voz.
- Voz **nunca** é autoridade: não lê nem escreve lance, relógio, resultado, ranking, fila ou peças.
  Falha de RTC só muda o estado da voz; a partida segue.

## Servidor (autorização)

`voice_join {kind, match_id}` / `voice_renew {match_id}` → `voice_granted` ou `voice_denied`.

Antes de dar token o servidor confere: conta autenticada (convidado não entra) + sessão válida
(hardening R42) + a partida existe + está ativa + é PvP humano + o usuário ainda é participante
(na Marcha/XEQUE: assento humano que não saiu, e pelo menos 2 humanos na mesa → senão `solo`).

- Canal: `fx_<ranked|casual|marcha|xeque>_<match_id>` (≤ 64 bytes).
- uid na Agora = **assento** (xadrez: brancas 1, pretas 2; mesa: 1–4). Nenhum id de conta vai para a Agora.
- Token: AccessToken2 ("007"), só `JoinChannel` + `PublishAudio`, **TTL 600 s** (env opcional
  `FRAIHA_VOICE_TOKEN_TTL`, 120–3600). Renovação (`voice_renew`) revalida tudo: partida acabou → recusa.
- `voice_peer {match_id, uid, name, joined}`: avisa os outros humanos que alguém entrou/saiu da voz.
- Recusas: `not_configured`, `auth_required`, `not_in_match`, `match_over`, `solo`, `rate_limited` (12/min),
  `bad_request`, `token_error`.
- Logs `[voice] …` só com match_id curto (8), assento, motivo. **Nunca** token, certificado ou áudio.
- Implementação do token sem dependência (crypto + zlib), igual **byte a byte** ao pacote oficial
  `agora-token` 2.0.6 (vetor fixo em `tests/server/voice_test.cjs`).

## Cliente — estados

`DISCONNECTED → REQUESTING_PERMISSION → CONNECTING → CONNECTED ⇄ MUTED`, `RECONNECTING`, `ERROR`.

| Estado | Timeout | Sai por |
| --- | --- | --- |
| REQUESTING_PERMISSION | 45 s | microfone pronto / negado / timeout |
| CONNECTING (token) | 12 s | voice_granted / voice_denied / timeout |
| CONNECTING (canal) | 20 s | joined / erro / timeout |
| RECONNECTING | 30 s | volta a CONNECTED / cai → ERROR |

Ordem do join: suporte → contexto seguro → SDK → permissão → microfone/trilha → **token** → join → publish → listeners → UI.
Saída: unpublish → stop/close da trilha → leave → remover listeners → limpar participantes → estado → UI.
`leave` aborta na hora um join pendurado (rede sem rota) — o microfone nunca fica ligado.

- Join idempotente/serializado por `seq`: toques repetidos não duplicam; eventos atrasados de tentativa antiga são descartados.
- Começa **desligada**: só entra quando o jogador toca no microfone (gesto do usuário para microfone/autoplay e para não gastar minutos).
- Mudo: `setMuted` da trilha. Única coisa salva em disco: preferência "entrar mudo" (`user://voice.cfg`).
- Microfone perdido/permissão revogada (track-ended) → fica MUDO e continua **ouvindo**; tocar tenta recriar.
- Troca de microfone do sistema → passa para o padrão. Autoplay bloqueado → "Toque na tela para ouvir".
- F5/fechar aba → `pagehide` solta microfone e canal. Logout/fim/abandono/voltar à Home → sai da voz.
- Desktop nativo (Windows) e HTTP sem TLS: sem suporte → botão não aparece.

## UI

- Xadrez (desktop): microfone + "×" (sair da voz) + estado ao lado no HUD da partida.
- Xadrez (celular): na coluna de ações; deitado mostra o estado embaixo; em pé só o ícone (a linha não comporta texto).
- Marcha/XEQUE: botão na barra (ao lado da tela cheia) + "×" no canto + estado ao lado (paisagem/desktop).
  Erros de voz também aparecem no aviso da mesa.
- Ícone: cinza = fora; dourado + ponto verde = falando/aberto; risco vermelho = mudo; pontinhos = conectando; "!" = erro.

## Configuração (Render — só NOMES)

| Variável | Onde | Obrigatória |
| --- | --- | --- |
| `FRAIHA_AGORA_APP_ID` | Render → serviço do servidor → Environment | sim |
| `FRAIHA_AGORA_APP_CERTIFICATE` | Render → serviço do servidor → Environment | sim |
| `FRAIHA_VOICE_TOKEN_TTL` | idem | não (padrão 600) |

Sem as duas primeiras o servidor responde `not_configured` e o jogo funciona normalmente sem voz.
Na Agora Console: criar projeto com **App Certificate** (modo seguro / token). Não ativar Cloud Recording,
transcrição, vídeo, streaming nem add-ons pagos.

## Build Web

A pasta `voice/` vai ao lado do `index.html` (como `engines/`):
`voice/AgoraRTC_N-4.24.8.js` (MIT, sem alterações), `voice/fraiha-voice-bridge-v1.js`, `voice/LEIA-ME-VOZ.txt`.
O SDK só é baixado quando alguém toca no microfone. Fallback: jsDelivr (mesma versão).

## Custo (verificado em fonte oficial em 2026-10-05 — reverificar a cada nova etapa)

- Agora: 10.000 minutos grátis por mês por conta, contados por participante (2 pessoas × 10 min = 20 min).
- Passou do grátis sem cartão → conta pode ser suspensa; com cartão, áudio ~US$ 0,99 / 1.000 min.
- Por isso a voz começa desligada e Marcha/XEQUE com só 1 humano não abre canal.

## Testes

| Teste | O que prova |
| --- | --- |
| `tests/server/voice_test.cjs` | token igual ao oficial; autorização por partida/assento; fim → recusa; bots/solo; convidado; rate limit; logs sem segredo |
| `tests/server/voice_e2e_test.cjs` | mesmo fluxo pelo `server.js` real (WebSocket) |
| `tests/voice_client_test.gd` | máquina de estados com provedor mock: todos os caminhos de erro/timeout/cleanup |
| `tests/run_voice_stage.sh` | jogo inteiro + servidor real + amigo automático: Casual por convite, Ranked, Marcha, XEQUE; bot/local sem voz; falha de RTC não mexe na partida; `--mobile-test` |
| `tests/web/qa_gate/run_voice_gate.sh` | Chromium real com microfone falso: ponte + SDK 4.24.8 + permissão + trilha + join recusado limpo + cleanup; permissão negada |

**Não testado (exige credenciais + 2 aparelhos):** áudio real entre duas pessoas na Agora, renovação real
do token na Agora, reconexão real, Safari/iOS, Android, Edge real, fone/eco.
