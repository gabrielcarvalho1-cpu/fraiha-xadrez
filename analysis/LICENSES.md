# Licenças — motores de análise do FRAIHA Xadrez

## Stockfish (motor de análise)

- **Projeto:** Stockfish — https://github.com/official-stockfish/Stockfish
- **Licença:** GNU General Public License v3.0 (GPLv3). Cópia integral em `web/engines/COPYING-GPLv3.txt`.
- **Build Web usada:** Stockfish.js 19 (Lite, single-thread, WASM) — pacote npm `stockfish` 19.0.0,
  por Nathan Rugg / Chess.com, LLC, GPLv3 — https://github.com/nmrugg/stockfish.js
  - `web/engines/stockfish-19-lite-single.js`  (sha256 d3344124ab067fb0b90ee77873bb8e9fbf5fc01bc525fe714b0f942581e889e6)
  - `web/engines/stockfish-19-lite-single.wasm` (sha256 57ac2d72312aba346760e3f173f687a8c211208e97a87268436f7f0e10bb5387)
  - Origem: tarball oficial do npm `https://registry.npmjs.org/stockfish/-/stockfish-19.0.0.tgz`
    (sha256 b1579b00ca456768c637bd5e5313830fb535ade04e87a5da53182c0a5eb6e05d). Rede neural "lite"
    embutida no .wasm (nn-61e7af4bb97d, por Chris Bao/sscg13, via projeto Stockfish).
- **Build Windows (nativa):** NÃO é distribuída com o FRAIHA. O jogador/operador coloca um
  `stockfish.exe` oficial (https://stockfishchess.org/download/) em `user://engines/` ou aponta
  `FRAIHA_STOCKFISH`. Ver `ENGINE.md`.

### Obrigações da GPLv3 que o FRAIHA cumpre e precisa continuar cumprindo

1. **Programa separado.** O Stockfish roda como processo (Windows) ou Web Worker (Web) e
   conversa com o jogo só por texto UCI. O FRAIHA não linka nem incorpora código do Stockfish;
   o jogo continua com a sua própria licença. Mantenha essa separação (não compilar o Stockfish
   dentro do executável do jogo, não copiar fonte do Stockfish para o projeto).
2. **Aviso e licença.** Toda distribuição que inclua os arquivos `web/engines/*` deve levar junto
   `COPYING-GPLv3.txt` e este aviso (nome, versão, origem, licença). A tela "Conheça o FRAIHA" /
   créditos deve mencionar "Análise pelo motor Stockfish 19 (GPLv3)". *(Pendente: texto nos
   créditos do jogo.)*
3. **Código-fonte correspondente.** Para a build WASM distribuída, o fonte é o repositório
   `nmrugg/stockfish.js` na tag `v19.0.0` (e o Stockfish oficial que ele embute). Se um dia o
   FRAIHA modificar/recompilar o motor, precisa publicar as modificações sob GPLv3 e oferecer o
   fonte correspondente (por exemplo no mesmo site da build Web).
4. **Sem restrições extras.** Não acrescentar termos (EULA, DRM) que limitem os direitos GPL
   sobre os arquivos do motor. A assinatura Club limita o uso do *serviço de análise do FRAIHA*
   (cota), não o uso do Stockfish em si.
5. **Marca.** "Stockfish" é nome do projeto; o FRAIHA não deve sugerir endosso oficial.

## Motor interno FRAIHA (fallback)

`bot/search.gd` — código próprio do FRAIHA, sem dependência externa. Usado quando nenhum
Stockfish está disponível (ou enquanto o WASM carrega). Nenhuma obrigação adicional.

## Peças, fontes e demais assets

Não mudam nesta fase. Fonte Cinzel: SIL OFL (ver `account/fonts/OFL-Cinzel.txt`).
