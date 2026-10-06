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

**Áudio-only de verdade (auditoria R45-V07):** o token só dá privilégio de entrar + publicar ÁUDIO, mas a Agora
só faz valer privilégios por tipo (áudio/vídeo/dados) com **Co-host token authentication** ligada no projeto
(Agora Console → projeto → Features/Security). Sem isso, um cliente adulterado poderia tentar publicar vídeo.
Status: **desligado** no projeto principal (conferido pelo dono em 2026-10-06). Tokens do servidor são
compatíveis (AccessToken2, privilégios relativos: join + publicar áudio). **ATENÇÃO: a Agora NÃO permite
desligar depois de ligar.** Ligar primeiro num projeto de TESTE apontado pelo staging, testar RTC real
(2 aparelhos, renovação de token ~12 min, mute, sair) e só então ligar no projeto principal.

**Janela residual do token (auditoria R45-V06):** fim de partida/logout fazem o servidor **recusar** renovação,
mas um token já entregue continua válido até expirar (padrão 600 s; `FRAIHA_VOICE_TOKEN_TTL`, 120–3600).
O cliente oficial sai sozinho; um cliente adulterado poderia ficar no canal até o token vencer.
Decisão de produto pendente: aceitar (padrão) ou reduzir o TTL (ex.: 300) — a revogação imediata exigiria
API de controle da Agora (não implementada).

## Build Web

A pasta `voice/` vai ao lado do `index.html` (como `engines/`):
`voice/AgoraRTC_N-4.24.8.js` (MIT, sem alterações), `voice/fraiha-voice-bridge-v1.js`, `voice/LEIA-ME-VOZ.txt`.
O SDK só é baixado quando alguém toca no microfone. Fallback: jsDelivr (mesma versão).

## Custo (verificado em fonte oficial em 2026-10-05 — reverificar a cada nova etapa)

- Agora: 10.000 minutos grátis por mês por conta, contados por participante (2 pessoas × 10 min = 20 min).
- Passou do grátis sem cartão → conta pode ser suspensa; com cartão, áudio ~US$ 0,99 / 1.000 min.
- Por isso a voz começa desligada e Marcha/XEQUE com só 1 humano não abre canal.

## Três controles independentes (R46)

| Controle | Efeito | O que NÃO faz |
| --- | --- | --- |
| **Microfone** (ícone do microfone) | mudo = ninguém me ouve; aberto = os outros me ouvem | não para de ouvir, não sai da sala |
| **Voz recebida** (ícone do fone) | silenciado = eu não ouço ninguém da sala | não sai da sala, não fecha meu microfone |
| **Sair da voz** ("×") | desconecta do RTC, para de ouvir e transmitir, libera microfone/trilha/listeners | não mexe na partida |

- Música, efeitos e áudio do jogo (barramentos do Godot) **não** controlam a voz. O áudio da voz toca pelo
  WebRTC/WebAudio do navegador (fora do Godot), e o teste confere que mudar música/efeitos não chama o provedor.
- Voz recebida muda: as trilhas remotas param de tocar (`stop()`), mas a inscrição no canal continua (voltar a
  ouvir é imediato). Quem entra na sala enquanto está mudo também não toca.
- Fica só na sessão (não vai para disco), para ninguém entrar "surdo" depois sem perceber. O microfone mudo
  continua salvo como antes.
- **Mute por participante** já existe no provedor/ponte (`set_participant_muted(assento)` →
  `FraihaVoiceBridge.setRemoteMuted`): silencia só aquela pessoa, só para mim. Hoje Marcha/XEQUE online têm no
  máximo 2 humanos (você + 1 amigo), então não há tela para isso ainda; quando houver 3+ humanos é só ligar a UI.

## Níveis de teste (não confundir)

| Nível | O que foi provado | Onde |
| --- | --- | --- |
| **TESTADO COM MOCK** | máquina de estados, erros, timeouts, cleanup, renovação, áudio recebido x microfone x sair, mute por participante | `tests/voice_client_test.gd`, `tests/run_voice_stage.sh` |
| **TESTADO COM SDK FALSO NO CHROMIUM** | a ponte JS: trilhas remotas tocam/param certo, microfone intocado, saída limpa | `tests/web/voice_bridge/run_test.py` |
| **TESTADO EM BUILD REAL** | build Web real no Chromium com microfone falso: SDK 4.24.8 carrega de `voice/`, permissão, trilha, join recusado limpo, permissão negada | `tests/web/voice_bridge/run_lifecycle_test.py` | captura REAL (getUserMedia sintético): Agora travada não segura o microfone; cancelamentos; mute real; trilha perdida; participante fantasma (auditoria R45) |
| `tests/web/qa_gate/run_voice_gate.sh` |
| **TESTADO COM RTC REAL** | **R45**: o dono do projeto testou voz real entre pessoas na Agora (staging com `FRAIHA_AGORA_APP_ID` / `FRAIHA_AGORA_APP_CERTIFICATE`) nos 3 modos testados — funcionou | teste manual do usuário |

O controle de **voz recebida (R46)** ainda **não** foi testado com RTC real: precisa de 2 aparelhos (roteiro abaixo).

### Roteiro RTC real (2 aparelhos, de preferência com fone)

1. A e B na mesma partida online, os dois na voz.
2. A muta o microfone → A continua ouvindo B; B não ouve A. A abre o microfone → B volta a ouvir A.
3. A silencia a voz recebida (fone) → A não ouve B; B continua ouvindo A (microfone de A aberto). A reativa → volta a ouvir.
4. A muda música/efeitos do jogo → a voz não muda.
5. A toca no "×" → sai da voz (B vê que A saiu); a partida segue.

## Incidente de publicação do R45 (resolvido)

A build pedia `voice/fraiha-voice-bridge-v1.js`, mas a pasta `voice/` não tinha sido enviada ao R2 → 404 →
`BRIDGE_LOAD` → "Não foi possível carregar a voz.". Depois de enviar os 3 arquivos de `voice/` a voz funcionou.
Prevenção (R46): `tools/web_release/pack_web_release.py` sempre inclui `voice/` e `engines/` e se recusa a gerar
sem eles; o `MONTAR-UPLOAD` confere tamanho+SHA256 de **cada** arquivo (15) e para se faltar algum; o
`CONFERIR-SITE` (novo) consulta o site publicado e aponta qualquer arquivo faltando (ex.: 404 em `voice/`).

## Auditoria Voice R45 (independente, 2026-10-06) — correções R46

Relatório: 0 BLOCKER, 1 HIGH, 6 MEDIUM, 2 LOW, sobre o snapshot `b389849`. Comparado com o HEAD atual e
reproduzido com `tests/web/voice_bridge/run_lifecycle_test.py` (captura REAL getUserMedia + SDK falso):
13 falhas no código antigo, 0 depois da correção.

| ID | Sev. | Estado | O que mudou |
| --- | --- | --- | --- |
| V01 | HIGH | **corrigido** | sair/fim/F5/erro param a CAPTURA na hora (stop+close síncronos, inclusive a MediaStreamTrack crua); unpublish/leave da Agora depois, em segundo plano, com limite (2 s / 5 s); a saída antiga nunca fecha uma tentativa nova |
| V02 | MEDIUM | **corrigido** | o evento `muted` traz o estado REAL da trilha; falha vira `MUTE_FAILED` com aviso; "entrar mudo" que falha entra só ouvindo (não publica); o ícone no Godot só muda com a confirmação |
| V03 | MEDIUM | **corrigido** | a geração (seq) muda na CHAMADA; toda espera (SDK, permissão, join, mute, publish) é cancelável; trilha que chega depois do cancelamento é fechada |
| V04 | MEDIUM | **corrigido** | trilha encerrada é descartada e despublicada; desmutar (gesto) recria e publica |
| V05 | MEDIUM | **corrigido** | limite por conta+partida (16/min somando abas) além do por conexão (12); presença idempotente: aviso "entrou" só na 1ª conexão, "saiu" só na última; leave repetido não gera aviso; conexão fechada/logout avisa 1x |
| V06 | MEDIUM | **aceito/documentado** | janela residual do token (ver Configuração); decisão de TTL com o dono do produto |
| V07 | MEDIUM | **documentado** | pré-requisito Co-host token authentication na Console (ver Configuração) — falta verificar |
| V08 | LOW | **corrigido** | geração por participante: subscribe atrasado de quem saiu/despublicou é descartado e não toca |
| V09 | LOW | **corrigido no R46** | pacote Web confere nome+tamanho+SHA256 dos 3 arquivos de `voice/` (e `engines/`) e PARA se faltar; PNG em base64 |

Não testado: microfone físico, RTC real com a correção (repetir o roteiro abaixo), Safari/iOS/Android.

## Testes

| Teste | O que prova |
| --- | --- |
| `tests/server/voice_test.cjs` | token igual ao oficial; autorização por partida/assento; fim → recusa; bots/solo; convidado; rate limit; logs sem segredo |
| `tests/server/voice_e2e_test.cjs` | mesmo fluxo pelo `server.js` real (WebSocket) |
| `tests/voice_client_test.gd` | máquina de estados com provedor mock: todos os caminhos de erro/timeout/cleanup |
| `tests/run_voice_stage.sh` | jogo inteiro + servidor real + amigo automático: Casual por convite, Ranked, Marcha, XEQUE; bot/local sem voz; falha de RTC não mexe na partida; `--mobile-test` |
| `tests/web/voice_bridge/run_lifecycle_test.py` | captura REAL (getUserMedia sintético): Agora travada não segura o microfone; cancelamentos; mute real; trilha perdida; participante fantasma (auditoria R45) |
| `tests/web/qa_gate/run_voice_gate.sh` | Chromium real com microfone falso: ponte + SDK 4.24.8 + permissão + trilha + join recusado limpo + cleanup; permissão negada |

**Não testado (exige credenciais + 2 aparelhos):** áudio real entre duas pessoas na Agora, renovação real
do token na Agora, reconexão real, Safari/iOS, Android, Edge real, fone/eco.
