# Publicação Web: conferência forte e rollback

Estado: **IMPLEMENTADO LOCALMENTE + TESTADO LOCAL**. A simulação usa duas entregas reais do empacotador, um site HTTP local e os scripts PowerShell de verdade. Sem deploy, sem push e sem mudança no Worker.

## Dois tipos de arquivo

| Tipo | Arquivos | Como muda entre versões |
|---|---|---|
| **Fingerprint** (SHA-256 no nome) | `index-p<h>.pck`, `index-s<h>.png` (h = SHA-256 do próprio arquivo); `index-e<h>.js/.wasm/.audio*.js` (h = SHA-256 do motor inteiro) | Nome novo a cada conteúdo novo. A versão anterior continua no bucket enquanto ninguém apagar. |
| **URL estável** | `index.html`, `index.icon.png`, `index.apple-touch-icon.png`, `engines/*`, `voice/*` (e `reload_diag.js`, se houver) | Mesmo endereço em toda versão: subir a nova **sobrescreve** a anterior. |

Por isso, rollback só com o `index.html` não basta. Se um arquivo de URL estável mudou (exemplo: `voice/`), a versão anterior volta com o arquivo da nova.

## Fluxo de publicação (kit da entrega)

1. **`ROLLBACK-ANTES-DE-PUBLICAR-<TAG>.cmd`**. Só lê o site.
   - Baixa a versão que está **no ar**: o `index.html`, tudo o que ele cita (motor, pacote e splash, lidos do `GODOT_CONFIG`) e todos os arquivos de URL estável.
   - Confere cada um. Pacote e splash precisam ter o conteúdo igual ao nome.
   - Guarda tudo em `ROLLBACK-<data>/`:
     - `ARQUIVOS-SHA256.txt`: manifesto da versão anterior (`# ROLLBACK …`);
     - `UPLOAD/` e `UPLOAD-2-POR-ULTIMO/index.html`: cópia completa, pronta para voltar;
     - `CONFERIR-SITE-<TAG>.cmd`: confere o rollback no site;
     - `LEIA-ME-ROLLBACK.txt`, com três listas: **PRESERVAR NO BUCKET** (os fingerprints da versão anterior), **URL ESTÁVEL QUE ESTA ENTREGA VAI SOBRESCREVER** (comparando o SHA-256 do que está no ar com o da entrega) e os estáveis idênticos.
   - Site vazio conta como primeira publicação: registra isso e segue.
   - Qualquer falha encerra com exit 1, apaga a pasta parcial e avisa "NÃO publique sem ele".
2. **`MONTAR-UPLOAD-<TAG>.cmd`**. **Recusa montar** se não houver uma pasta `ROLLBACK-*` válida. O resto é o de antes: SHA-256 de cada arquivo da entrega e ambiente.
3. Subir `UPLOAD` inteiro. Só quando chegar a 100%, subir o `index.html`.
4. **`CONFERIR-SITE-<TAG>.cmd`**, a conferência forte.
   - Baixa **cada arquivo** do site, com `?conferir=<ticks>` e `Cache-Control: no-cache`, aceitando gzip.
   - Compara **tamanho e SHA-256** com o manifesto da entrega e lista por grupo (fingerprint × URL estável).
   - O `index.html` público precisa ser o da entrega e citar só motor e pacote da entrega.
   - Arquivo faltando, diferente (inclusive com o **mesmo tamanho**), inacessível, ou index citando arquivo de fora: exit 1, lista dos problemas e "NÃO CONFERE".
   - **"TUDO NO AR" só aparece com 100% dos arquivos com o SHA-256 da entrega.**
   - Cache-Control sem `immutable` continua sendo só aviso (Worker).

Custo: a conferência baixa a build inteira, incluindo o PCK de ~190 MB. É o preço de provar o SHA-256 do que está publicado.

## Rollback (se a nova der problema)

1. Abrir `ROLLBACK-<data>/LEIA-ME-ROLLBACK.txt`.
2. Subir **todo** o `UPLOAD` desta pasta. Isso repõe os estáveis que a entrega sobrescreveu e os fingerprints, caso alguém os tenha apagado.
3. Depois, subir o `index.html` de `UPLOAD-2-POR-ULTIMO`.
4. Rodar `CONFERIR-SITE-<TAG>.cmd` **de dentro da pasta ROLLBACK**: tem que dar "TUDO NO AR" com o SHA-256 da versão anterior.

## Simulação (`tools/web_release/test_publicacao_rollback.py`, 11/11)

| Caso | Resultado |
|---|---|
| Primeira publicação (site vazio) | rollback "primeira publicação"; v1 publicada e conferida |
| Rollback antes da v2 | preservar = fingerprints da v1; sobrescreve = `voice/LEIA-ME-VOZ.txt` (mesmo tamanho, conteúdo novo); cópia completa salva |
| Sem rollback | MONTAR-UPLOAD recusa |
| Publicação completa | TUDO NO AR (fingerprint 6, URL estável 9); o conferidor do rollback acusa diferença |
| Upload interrompido | NÃO CONFERE (faltando no site) |
| Index novo com assets antigos | NÃO CONFERE (pacote novo faltando) |
| Assets novos com index antigo | NÃO CONFERE (index.html diferente e citando arquivos de fora da entrega) |
| Arquivo estável alterado | NÃO CONFERE ("MESMO tamanho, conteúdo diferente") |
| Arquivo público incorreto (PCK corrompido, mesmo tamanho) | NÃO CONFERE |
| Rollback completo | conferidor do rollback: TUDO NO AR; conferidor da v2: NÃO CONFERE |
| Rollback só com `index.html` | NÃO CONFERE (o estável da v2 ficou) |
| Site inacessível | NÃO CONFERE |
