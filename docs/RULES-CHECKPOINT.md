# Checkpoint do motor de regras isolado

Revisão e reexecução local: 21/09/2026, Godot 4.5.1 stable.

## Escopo entregue

`chess/rules.gd` é um modelo de posição independente, baseado em `RefCounted`. Não cria nós, desenha interface nem abre conexões. Mantém tabuleiro, vez, direitos de roque, alvo de en passant, contador de meios-lances e histórico de repetições. Oferece cópia isolada de posição, geração de lances legais, aplicação de lances e identificação de resultados.

O motor **não está integrado ao jogo atual**. Na revisão deste checkpoint, apenas `tests/rules_test.gd` referencia `res://chess/rules.gd`. O cliente legado, a cena de apresentação e o servidor continuam usando as implementações já existentes. Este checkpoint não modifica o protocolo Node/WebSocket, a configuração do Render ou o servidor publicado.

## Verificações confirmadas

| Verificação | Resultado | Evidência |
| --- | --- | --- |
| Motor isolado | 40 verificações, 0 falhas; reexecutado nesta revisão | `work/v024/rules-checkpoint-rerun.log`, resumo `RULES_CHECKS=40 FAILURES=0` |
| Cliente legado | 11 verificações aprovadas, 0 falhas; reexecutado nesta revisão | `work/v024/legacy-checkpoint-rerun.log`, resumo `LEGACY_FAILURES=0` |
| Multiplayer público | Log anterior confirmado: 12 verificações, 0 falhas | `work/v024/online-test.log`, endpoint `wss://fraiha-xadrez.onrender.com` |

Os caminhos de log acima são relativos ao diretório de trabalho da tarefa; os logs não fazem parte do código de produção. O teste WSS desta tabela foi executado anteriormente: a revisão deste checkpoint confirma a evidência existente e não afirma uma nova execução de rede.

As 40 verificações cobrem posições iniciais e cópias independentes; rejeição de lances ilegais, turno incorreto e promoção inválida; perft inicial até profundidade 3 (20 / 400 / 8.902); Kiwipete até profundidade 2 (48 / 2.039); final de torres/peões até profundidade 3 (191 em profundidade 2 e 2.812 em profundidade 3); roque e perda de direitos; en passant e exposição do próprio rei; peça cravada; quatro promoções; mate, afogamento, material insuficiente, limite de 50 lances, repetição e chave de posição sem en passant irrelevante.

As 11 verificações legadas cobrem posição inicial, movimentos do peão, seleção por turno, entrada e alternância de vez, captura, mate do louco, cravada, escolha de promoção, reinício e carregamento da cena atual com os nós `World` e `Online`.

O teste WSS usa **dois clientes de protocolo independentes**, não duas janelas gráficas do jogo. Verifica criação de sala, entrada por código, cores opostas, rejeição de lance fora da vez, quatro lances com tabuleiros idênticos, captura, reconexão, revanche por consenso e desistência. Não imprime credenciais de reconexão e fecha os clientes ao terminar.

## Política atual de empate e limites conhecidos

- `outcome()` devolve `repetition` a partir da terceira ocorrência e `fifty_moves` a partir de 100 meios-lances sem captura ou movimento de peão. São resultados automáticos no modelo atual; não há fluxo de reivindicação de empate, regra separada de cinco repetições ou de 75 lances. Essa política precisa ser decidida explicitamente antes de uma integração competitiva.
- Mate e afogamento têm prioridade na avaliação de resultado, seguidos por material insuficiente, 50 lances e repetição.
- Material insuficiente reconhece reis sozinhos, um único bispo ou cavalo além dos reis e posições apenas com bispos na mesma cor de casas. Não pretende resolver toda posição morta possível. Dois cavalos não são declarados automaticamente insuficientes.
- `play()` verifica a legalidade do lance na posição, mas não bloqueia por si só a continuação após um resultado de empate. A camada que futuramente controlar a partida deverá consultar `outcome()` e impor seu ciclo de encerramento.
- O modelo espera posições coerentes e coordenadas tipadas. Não valida entradas arbitrárias de rede, número de reis ou estados montados externamente. `apply_unchecked()` é uma operação interna que pressupõe lance válido. Não deve ser exposta diretamente ao protocolo.
- A leitura FEN disponível pertence ao teste e não é uma API pública do motor. Também não há persistência, relógio, notação PGN/SAN, bot ou ranking nesta entrega.
- Os testes perft são regressões úteis, mas não equivalem a uma prova exaustiva de todas as regras em todas as posições.

## Avisos do ambiente e do legado

Ambos os testes Godot terminaram com código 0. O ambiente de execução isolado emitiu `Failed to read the root certificate store`; isso não impediu os testes locais, que não abrem WSS. Portanto esses testes locais não validam o caminho TLS do cliente Godot.

O teste legado também emitiu, após todas as verificações aprovadas, avisos de `ObjectDB instances leaked at exit` e um recurso ainda em uso. Esses avisos já aparecem no log anterior, são reproduzíveis no encerramento do teste e não foram corrigidos neste checkpoint. O motor isolado não produziu esses avisos de encerramento. Não afirmar ausência completa de avisos ou vazamentos do cliente legado.

## Como reproduzir

Executar a partir da raiz desta cópia do projeto, usando Godot 4.5.1:

```text
godot --headless --path . --script res://tests/rules_test.gd
godot --headless --path . --script res://tests/legacy_client_test.gd
node tests/online_smoke.cjs wss://fraiha-xadrez.onrender.com
```

O teste Node requer Node 22+ e acesso à rede. Ele cria uma sala efêmera e joga nela; não faz deploy. Para testar um servidor local, passar `ws://127.0.0.1:PORTA` como argumento. Nos testes desta revisão, `APPDATA` e `LOCALAPPDATA` foram direcionados para `work/v024/test-profile/AppData/Roaming` e `work/v024/test-profile/AppData/Local`, respectivamente, sem usar o perfil real do jogo.

## Continuidade segura

1. Registrar somente o motor, seus testes e esta documentação em uma branch separada. Não publicar nem alterar `main` de produção.
2. Trabalhar a Home V0.22 de forma isolada e preservar a implementação atual do cliente multiplayer.
3. Antes de integrar este motor ao cliente ou ao servidor, definir a política de empate/encerramento e criar testes de equivalência com posições e partidas do legado. Essa integração não é requisito da Home e não deve ser introduzida implicitamente.
4. Antes de Bot/Ranked, obter a revisão visual e funcional da Home e de sua build Windows de teste.
