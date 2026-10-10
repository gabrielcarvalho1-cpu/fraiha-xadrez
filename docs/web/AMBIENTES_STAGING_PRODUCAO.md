# Ambientes da build Web: QA/staging × produção

Estado: **IMPLEMENTADO LOCALMENTE + TESTADO LOCAL** (exports reais 4.5.1 + Chromium com servidores wss locais). Sem push e sem deploy.

## Endpoints

| Ambiente | Servidor (público, sem segredo) | Onde está |
|---|---|---|
| QA / staging | `wss://fraiha-xadrez-staging.onrender.com` | `online.cfg` `[staging]` |
| Produção | `wss://fraiha-xadrez.onrender.com` | `online.cfg` `[online]`, `admin/src/config.js` (production), docs do teste `online_smoke` |

## Por que a R57.1 usou staging

Só existia um preset Web: **"Web Alpha"**, com `custom_features="staging"`. O `online_v020/endpoint.gd` troca o `[online]` pelo `[staging]` quando a build tem essa feature. Por isso **toda** build Web, inclusive a R57.1, saía apontando para o staging. Não havia preset de produção nem conferência de ambiente no empacotamento.

## Como escolher agora

Escolha o preset no export. Não se edita URL.

| Preset (`export_presets.cfg`) | Feature | Servidor |
|---|---|---|
| `Web Alpha` | `staging` | `[staging]` → staging |
| `Web Producao` | `production` | `[online]` → produção (nunca lê `[staging]`) |

Os dois presets têm as mesmas opções; só o nome e a feature mudam, e um teste garante isso. O empacotamento declara o ambiente:

```
pack_web_release.py <export> web <saida> <TAG> <commit> --ambiente=staging     # QA
pack_web_release.py <export> web <saida> <TAG> <commit> --ambiente=producao    # produção
```

## Travas contra publicar staging como produção (fail-closed)

1. **`--ambiente` é obrigatório.** O `tools/web_release/ambiente_web.py` abre o `index.pck` exportado e lê duas coisas: a feature gravada no `project.binary` e o `online.cfg` empacotado. Com isso calcula o servidor efetivo. O empacotamento PARA, sem gerar nada, nestes casos:
   - o ambiente declarado é diferente do PCK;
   - uma build de produção aponta para o staging, ou para qualquer endereço diferente do oficial;
   - a build está marcada como staging e produção ao mesmo tempo, ou não tem feature de ambiente.
2. **Marca na entrega.** O ambiente vai para o `ARQUIVOS-SHA256.txt` (`# AMBIENTE … - servidor …`) e para o `index.html` (`<meta name="fraiha-ambiente">`).
3. **O `MONTAR-UPLOAD` mostra o ambiente em destaque** ("PRODUCAO (jogadores reais)" ou "STAGING (QA/testes) - NAO e producao"). Ele falha se:
   - faltar a marca;
   - a marca de produção apontar para staging;
   - o `index.html` for de outro ambiente.
4. **No próprio jogo** (`endpoint.gd`, `production_guard`): se uma build de produção cair no staging, ou ficar sem servidor, ela fica sem online. Nunca joga no ambiente errado.

Mudou o servidor oficial? Altere `online.cfg [online]` e `PRODUCAO_URL` em `ambiente_web.py` juntos, de propósito.

## Validação

- `tools/web_release/test_pack_web_release.py` 11/11 e `test_gates_exit_codes.py` 17/17 (PowerShell): ambiente marcado, 9 casos de falha e presets iguais.
- `tests/endpoint_ambiente_test.gd` 10/10.
- Exports reais dos dois presets, abertos no Chromium com os hosts do Render desviados para servidores wss locais "espiões":

  | Build | Fluxo | Conexões |
  |---|---|---|
  | `Web Alpha` | convidado → Casual | só o staging (`guest_auth`) |
  | `Web Alpha` | Ranqueada | só o staging (`guest_auth`) |
  | `Web Producao` | convidado → Casual | só a produção |
  | `Web Producao` | Ranqueada | só a produção |

  Nenhuma build tocou o outro servidor. Amigos, pagamentos, voz e progresso de bots usam o mesmo socket (`account_service`, `endpoint.gd`). XEQUE e Marcha Real são locais e não usam o servidor.
- Empacotamento real: staging→`--ambiente=producao` e produção→`--ambiente=staging` foram RECUSADOS. O `MONTAR-UPLOAD` real mostrou o ambiente certo nos dois casos.
