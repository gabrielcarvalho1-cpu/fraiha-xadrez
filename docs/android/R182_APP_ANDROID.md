# R182 · App Android (1ª versão de teste)

Branch `r182/android-app`, a partir da R181 (`7625dc7`). Reaproveita a Android 01 (`dev/android-alpha`: preset, Voltar,
safe area, Stockfish fora do Android, compras) e a Android 02 do Codex (renovar token ao voltar do segundo plano).

## O que é
App Android nativo (export do Godot, não é site dentro de um app). Mesmo jogo da Web no celular: mesmas telas,
mesmo servidor (staging, o do jogo público), mesmas contas, Ranked, Casual, XEQUE, Marcha Real, bots, chat.

| Item | Valor |
|---|---|
| Pacote | `com.fraihaxadrez.app` (definitivo depois do 1º envio à Play; até lá pode mudar) |
| Nome no celular | FRAIHA Xadrez |
| Versão | 1.0.0-teste (código 1) |
| Android | 7.0+ (minSdk 24), ARM 64 e ARM 32 |
| Tela | cheia (imersiva), retrato e paisagem |
| Permissões | só INTERNET |
| Ícone | rei e rainha dourados da tela de abertura (`branding/android/`) |
| Abertura | versão em retrato da arte de carregamento (`boot_splash/image.android`) |
| Assinatura | chave de TESTE (não é a da Play) |

## Mudanças só do app (Web e PC iguais)
- `telemetry/app_track.gd`: o rastreamento da visita (Admin → Sessões/Funil) também no app: visitante, telas, cliques,
  carregamento, login, partidas, saída. Manda para `POST /t` com `x-fraiha-app: android`.
- Login com Google no app: navegador do celular + PKCE. O servidor só guarda o código de uso único
  (`online_v021/accounts/app_login.js`, rotas `/app-login/done` e `/app-login/claim`); quem troca pela sessão é o app.
- Compras: aviso "EM BREVE NO APP" (o que a pessoa já tem na conta vale no app).
- Sem botão de tela cheia; Voltar do Android = ESC (fecha janela, volta à Home, pede confirmação em partida).
- Exportar partida (texto) copia para a área de transferência.
- Volta sozinho para a tela cheia depois do Voltar / de voltar de outro app.

## Servidor (precisa publicar para funcionar no app)
- `/t`: aparelho "APP Android" + versão do Android no Admin (sem isso a visita aparece como aparelho desconhecido).
- `/app-login/*`: login com Google no app.

## Supabase (1 ajuste no painel, para o Google no app)
Authentication → URL Configuration → Redirect URLs → adicionar
`https://fraiha-xadrez-staging.onrender.com/app-login/done**`
Sem isso o Google devolve o navegador para o site do jogo e o app não recebe o login.

## Testado (emulador Android 15 no PC do dono)
Abertura, ícone, login (campos e teclado), convidado, Home, bot Madeira (lances), Voltar (fecha login, pede
confirmação em partida), fila Casual → rival de IA aos 30 s, desistência e tela de resultado, Marcha Real,
Seja Membro → "EM BREVE NO APP", paisagem, Google abre o navegador com o PKCE.
Não testado: celular físico, voz, foto de perfil, login Google até o fim (depende do servidor + Supabase).

## Pendências (próximas etapas)
- Pagamentos na Play: no Brasil a Play ainda não libera cobrança própria dentro do app (previsão 2027); por enquanto
  o app não vende. Decidir: Play Billing (taxa) ou só pelo site.
- Voz (Agora) no app: precisa de plugin nativo.
- Play Console: conta de desenvolvedor, chave de upload (gerada pelo dono), AAB, política de privacidade, classificação.
- Stockfish no Android (hoje a análise usa o motor interno).
