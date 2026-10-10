# R55.6 · Recuperação de perda de contexto WebGL (Web)

Estado: **IMPLEMENTADO LOCALMENTE + TESTADO LOCAL** (Chromium com build real `65a9c39`). Sem push e sem deploy.

## Problema (achado do Orca, reproduzido)

Quando o navegador derruba o contexto WebGL (falta de memória de GPU, aba em segundo plano no celular, driver), o Godot 4.5 Web faz só `alert("WebGL context lost, please reload the page")`. Esse alert trava a página, e no celular costuma ser suprimido. O jogo continua rodando por baixo, mas o canvas fica **vazio para sempre**. Reproduzido com `WEBGL_lose_context`: alert e página em branco, sem reload.

## Decisão: restaurar no lugar não é um caminho suportado

O Godot 4.5 Web (e o Emscripten exportado) não tem tratamento de `webglcontextrestored`: texturas, shaders e buffers não são recriados. Mesmo que o navegador devolva o contexto, o render continua quebrado. Por isso a recuperação é sempre um **reload controlado**. O `webglcontextrestored` serve só como sinal de que a GPU voltou, o que deixa o reload mais rápido.

## O que foi feito

`web/gl_recovery/fraiha-gl-recovery.js` entra **inline** no começo do `<head>` do `index.html`, colocado pelo empacotador (`pack_web_release.py`, nos dois modos). O empacotamento falha (fail-closed) se o arquivo faltar.

1. **Ouvinte em captura no `document`.** Recebe `webglcontextlost` do `#canvas` antes do Godot.
   - Faz `preventDefault()`, o que permite ao navegador devolver o contexto.
   - Faz `stopPropagation()`, o que impede o alert bloqueante do Godot.
2. **Tela de recuperação imediata.** Cobre o canvas vazio, com o texto "Os gráficos do jogo foram interrompidos pelo navegador. Recarregando…".
3. **Reload controlado da mesma URL**, em uma destas situações:
   - a aba está visível e online: espera até 3 s pelo contexto voltar (1,2 s se o `restored` chegar) e recarrega;
   - a aba está em segundo plano: espera o `visibilitychange` para visível;
   - está offline: mostra "sem internet… recarrega quando a conexão voltar" e espera o evento `online`, sem recarregar para uma página de erro.
4. **Anti-loop:** no máximo **2 reloads automáticos em 5 min** por aba, contados em `sessionStorage` (`fraiha_gl_reload_v1`).
   - Na 3ª perda, ou sem `sessionStorage`, não recarrega sozinho: mostra "Os gráficos falharam de novo… toque em Recarregar".
   - O reload manual não entra na contagem.
5. **Saída da página:** perdas durante pagehide/beforeunload (reload ou navegação do próprio usuário) são ignoradas.
6. **Sessão e estado:** login e preferências ficam no armazenamento do jogo (`user://`, gravado pelo Godot quando cada arquivo é fechado). Partida online volta pela reconexão normal do servidor. Com o R55.5, o PCK vem do cache local, então o reload é rápido.
7. **reload_diag (`?diag=1`):**
   - `tools/diag/reload_diag.js` agora expõe `window.fraihaDiagLog`.
   - A recuperação registra `gl_lost_handled`, `gl_restored_signal`, `gl_wait_online`, `gl_online`, `gl_reload_go`, `gl_loop_blocked`, `gl_reload_manual` e `gl_no_storage`.
   - Na abertura seguinte, a caixa do diagnóstico diz "reload AUTOMÁTICO da recuperação de gráficos (R55.6)" ou "reload automático bloqueado (anti-loop)".
8. **Estado de depuração:** `window.__fraihaGl` (`state`, `events`).

Não mexe em gameplay, regras, backend, protocolo, Android nativo nem na estratégia de cache. O empacotador só ganhou a injeção do script.

## Validação (`tests/web/gl/gl_recovery_test.cjs`, Chromium + build real + simulador local): 22/22 PASS

| Cenário | Resultado |
|---|---|
| A · Web desktop normal | sem tela de recuperação; canvas desenhando |
| B · `loseContext()` | tela na hora, sem alert; reload em ~2,9 s; jogo de volta; contador = 1; canvas desenhando; reload_diag registrou e explicou |
| C · `loseContext()` + `restoreContext()` | sinal `restored` registrado; reload em ~2,0 s |
| D · 3ª perda em < 5 min | **sem** reload automático (anti-loop); botão Recarregar funciona e não soma no contador |
| E · offline | espera sem recarregar; ao voltar online, reload em ~3,3 s e jogo de volta |
| F · aba em segundo plano | espera; ao ficar visível, reload em ~3,3 s |
| G · reload normal do usuário | sem recuperação, sem contagem, canvas desenhando |
| Todo o teste | nenhum `alert()` |

Antes × depois com celular em retrato (390×844) e PC: antes = alert e página branca para sempre; depois = tela de recuperação e Home de volta em ~3 s.

Também passaram:

- `tools/web_release/test_pack_web_release.py` (7/7): injeção nos dois modos, antes de qualquer outro script, e fail-closed sem o arquivo;
- `test_gates_exit_codes.py` com PowerShell (15/15).

## Limites

- Não há restauração sem reload: limitação do Godot 4.5 Web, decidida acima.
- `sessionStorage` bloqueado (raro): nunca recarrega sozinho, só pelo botão. É o lado seguro.
- Estado de jogo local que não foi salvo (por exemplo, uma partida contra o bot no meio) recomeça como em qualquer reload; o servidor reconecta só as partidas online.
- O teste usa `WEBGL_lose_context` no Chromium. Perdas reais em iPhone e Android ainda precisam do QA em aparelho (com `?diag=1` para o registro).

## Como publicar

Nada muda no fluxo do R55.5: o `pack_web_release.py` já injeta o script. Para QA com diagnóstico, rode `tools/diag/inject_reload_diag.py <export>` **antes** do empacotamento.
