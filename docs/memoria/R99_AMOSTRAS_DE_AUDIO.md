# R99 · Vazamento de amostras de áudio Web (GodotAudio.samples)

Origem: auditoria do Orca na R94 (`REPORT_R94_MEMORY.md`). Correção aplicada sobre a R98 (`3df053f`).

## Ciclo de vida real (Godot 4.5.1, export Web sem threads)

- **Quem registra:** ao tocar um `AudioStreamPlayer` com `playback_type = SAMPLE`, o motor pergunta ao navegador se
  o stream já tem amostra (`godot_audio_sample_stream_is_registered` → `GodotAudio.samples.get(id) != null`). Se não
  tem, copia o PCM (float32, 2 canais) para um `AudioBuffer` e grava em `GodotAudio.samples` com a chave = **ID do
  objeto AudioStream**.
- **Quem cria `SampleNode`:** cada `play()` cria um `SampleNode` (`GodotAudio.sampleNodes`), com `streamObjectId`
  apontando para a amostra. Ele sai do mapa quando a reprodução termina ou é parada.
- **Compartilhamento:** sim — reproduções simultâneas do mesmo stream (ex.: 2 dos 4 players) usam a MESMA amostra.
- **O vazamento:** o motor nunca remove a amostra quando o AudioStream é liberado (comprovado no teste Web: 5 streams
  tocados e soltos = 5 amostras a mais). O XEQUE e a Marcha carregam os efeitos ao entrar e soltam ao sair; na volta,
  `load()` cria outro objeto (ID novo) → amostra nova a cada ciclo. Não há `unregister_stream_as_sample` no GDScript.

## Correção

1. `tools/web_release/audio_samples_release.py` (aplicado pelo `pack_web_release.py`, fail-closed, trecho exato):
   acrescenta `GodotAudio.Sample.fraihaRelease(ids)` e `fraihaStats()` e expõe `globalThis.fraihaGodotAudio`.
   `fraihaRelease` só chama `sample.clear()` quando **nenhum `SampleNode` ativo** usa aquele stream; as que ainda
   tocam ficam pendentes e são conferidas a cada 0,5 s até terminarem.
2. `audio_v025/game_audio.gd`: guarda os IDs dos streams tocados pelos modos (`play_stream`), exceto os sons padrão
   (`streams`, sempre registrados), e pede a liberação ao sair/trocar de modo (`release_mode_samples`, chamado por
   `set_music_override` e pelo `close()` do XEQUE e da Marcha via `ModeSound.release_samples`).
3. Se um stream liberado tocar de novo, o motor registra outra vez (a pergunta ao mapa é feita a cada play) — o som
   nunca é cortado nem fica sem amostra.

## Medição (Chromium headless, SwiftShader, 390×844 DPR 2, UA iPhone, export real)

Roteiro por ciclo (`tests/web_audio/ciclos_audio.cjs` + `ciclo_driver.gd`): Home → Bot → Home → XEQUE (rajada de 6
efeitos simultâneos) → Home → Marcha (rajada incl. promoção/troca + vitória/derrota alternadas) → resultado → Home;
a cada 3 ciclos sai do XEQUE com som tocando; a cada 4 sai do resultado com a fanfarra tocando e entra de novo na
hora; rotação retrato/paisagem a cada 5.

| Ciclo 20 | R98 (sem correção) | R99 |
|---|---:|---:|
| `GodotAudio.samples` | 276 amostras / 222,8 MiB | 2 / 0,78 MiB |
| `partition_alloc/array_buffer` | 306,0 MiB (boot 67,2) | 68,0 MiB (boot 67,1) |
| Renderer privado | 794 MiB | 567 MiB |
| Heap JS (após GC) | 8,81 MiB | 8,72 MiB |
| WASM | 198,75 MiB | 198,75 MiB |
| `partition_alloc/buffer` | 194,0 MiB | 193,8 MiB (investigação separada) |
| Reproduções sem amostra (`start_sample` com amostra ausente) | 0 | 0 |

R99 em 40 ciclos: amostras 2 / 0,78 MiB do ciclo 5 ao 40; `array_buffer` 67,1 → 67,8 → 68,0 → 71,7 MiB (platô);
625+ efeitos tocados, nenhum sem amostra, nenhum erro de página. Perda de contexto WebGL + recarga: o áudio volta
(35 efeitos, 0 sem amostra), música do modo trocando certo (XEQUE/Marcha/Home).

O renderer privado oscila no SwiftShader e soma o `buffer` (que continua crescendo até ~194 MiB e estabiliza perto
do ciclo 20, igual nas duas builds) — não é métrica da correção de áudio. Não é Safari nem iPhone físico.

Arquivos: `docs/memoria/r99/*.json`.
