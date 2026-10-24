# R181 · Rastreamento da visita (Admin → Sessões / Funil)

## Por que nada aparecia (R180)
1. **Telas e aparelho nunca eram enviados.** O rastreador do jogo esperava `acct_state`/`guest_state` pelo sinal
   `server_message`, que o serviço de conta não repassa para essas mensagens → `_ready_id` nunca ficava verdadeiro.
2. **Quem saía na tela de entrada não existia.** O jogo só conectava ao servidor ao entrar na conta ou abrir o Casual.
3. **Convidado só aparecia se abrisse o Online Casual.** "Jogar como convidado" só fechava a janela.

## Como funciona agora
- `web/telemetry/fraiha-track.js` (no `<head>` de cada preset Web, montado por
  `tools/web_release/montar_rastreio_head.py`, com o servidor do ambiente do preset) registra desde o 1º segundo:
  visitante (código aleatório do navegador), utm/fbclid, carregamento (início, 100% com segundos, erro, lento),
  telas, cliques, login (método, sucesso, código do erro), partidas, saída (sendBeacon em visibilitychange/pagehide).
- Envia em lotes para `POST /t` (texto JSON). O servidor (`online_v021/admin/visit_http.js`) valida tudo:
  só campos conhecidos; nome de tela/botão só se existir no jogo (`online_v021/admin/ui_names.json`, gerado por
  `tools/gerar_nomes_ui.py`); corpo ≤ 8 KB; ≤ 40 eventos; por IP 120/min; por visitante 60/min; 30 visitantes
  novos por IP/hora; CORS só para os endereços do jogo; acima disso, descarta.
- Ao conectar (convidado ou conta), o jogo manda `ui_link {sid}`: a visita vira a sessão da pessoa (mesma linha
  do tempo). "Jogar como convidado" agora conecta na hora.
- Painel: ▸ telas, ★ cliques ("Botão — Tela"), ✓ ações, ◆ respostas, • entrada/carregamento/saída; tempo em cada
  tela; aparelho (Android/iPhone/PC, sistema, navegador, Instagram/Facebook); origem (anúncio).
- Funil por dia (`GET /admin/api/funnel?days=14&ads=1&hide_test=1`): abriu → carregou → passou da entrada →
  jogou 1 partida → voltou outro dia. "Esconder testes" usa `FRAIHA_TEST_NICKS` (padrão `SextoSentro,DaSilva`) e
  esconde também os navegadores que já usaram esses apelidos.

## Banco
`supabase/migrations/0031_fraiha_sessoes_visitantes.sql` (vid, utm, flags, kind 'visitor'). Sem ela o servidor
continua gravando (sem essas colunas; visitante entra como 'guest').

## Meta Conversions API (opcional)
Variáveis do servidor (Render): `META_CAPI_TOKEN` (obrigatória para ligar), `META_PIXEL_ID` (padrão 1131165439457023),
`META_CAPI_TEST_CODE` (código do "Testar eventos"). Só envia com o aceite de cookies; mesmo `event_id` do pixel
do navegador (a Meta deduplica). O token nunca vai no jogo, no código ou em log.
