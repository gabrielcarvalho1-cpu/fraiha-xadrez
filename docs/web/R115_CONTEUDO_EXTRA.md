# R115 · Carregamento mais rápido (Web)

A build Web sai em **dois pacotes**:

| Pacote | Tamanho (R115) | Quando baixa |
|---|---|---|
| principal `index-p….pck` | ~25 MB (antes ~51 MB) | ao abrir o jogo |
| conteúdo extra `index-p….pck` | ~28 MB | sozinho, 2,5 s depois da Home; fica guardado no aparelho |

Conteúdo extra = XEQUE e MARCHA (artes e sons; as fontes ficam no principal), cenários/peças das ligas
Bronze → Challenger e as músicas Ferro/Bronze/Prata/Ouro. Lista em `tools/web_release/conteudo_extra.py`.

- Abrir XEQUE/MARCHA antes de chegar: tela "PREPARANDO O XEQUE… N%" e o modo abre quando termina.
- Tema de liga salvo: mostra Madeira até chegar e volta sozinho (theme_manager.revalidate); música idem.
- Segunda visita: o pacote extra está em `user://conteudo` (IndexedDB) — nenhum download.
- Fora da Web (PC, editor, testes) nada muda: tudo está num pacote só.

## Gerar a build Web
1. `python3 tools/web_release/texture_quality.py`
2. `python3 tools/web_release/conteudo_extra.py` (atualiza os presets; `--check` só confere)
3. `--export-release "Web Alpha" <exp>/index.html` (ou "Web Producao")
4. `--export-pack "Web Conteudo" <exp>/conteudo.pck`
5. `inject_reload_diag.py` e `pack_web_release.py` como antes — o empacotador PARA se faltar o conteudo.pck
   ou se o pacote principal ainda tiver conteúdo extra.

O nome do pacote extra vai no index.html: `<meta name="fraiha-conteudo" content="index-p….pck" data-size="N">`.
Cloudflare: nada muda (os dois `index-p…` são arquivos com SHA-256 no nome, cache immutable).
