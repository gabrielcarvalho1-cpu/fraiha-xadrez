'use strict';
// R35 · MARCHA REAL e XEQUE online com amigo (servidor real, FRAIHA_DEV_AUTH + MemoryStore).
// Convite → mesa de 4 (quem convidou no lugar 0, amigo no lugar 2, bots em 1 e 3) → partida inteira
// jogada pelos clientes de teste com o motor do servidor. Tempos de animação encurtados por env.
const { startServer, client, check, summary } = require('./helpers.cjs');
const { Marcha, chooseAI, posmod } = require('../../online_v021/modes/marcha_rules');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ENV = { FRAIHA_DEV_AUTH: '1', FRAIHA_PARTY_TURN_MS: '1500', FRAIHA_PARTY_MARCHA_BOT_MS: '5', FRAIHA_PARTY_XEQUE_BOT_MIN_MS: '5', FRAIHA_PARTY_XEQUE_BOT_MAX_MS: '10',
  FRAIHA_PARTY_AWAY_MS: '30', FRAIHA_PARTY_STEP_MS: '0', FRAIHA_PARTY_EXIT_MS: '0', FRAIHA_PARTY_CARD_FLY_MS: '0', FRAIHA_PARTY_CAPTURE_MS: '0', FRAIHA_PARTY_CROWN_MS: '0', FRAIHA_PARTY_SWAP_MS: '5', FRAIHA_PARTY_MESA_MS: '5', FRAIHA_PARTY_INTRO_MS: '5', FRAIHA_PARTY_REVEAL_MS: '5', FRAIHA_PARTY_CLOCK_MS: '5', FRAIHA_PARTY_SAFE_MS: '5', FRAIHA_PARTY_MATE_MS: '5' };
async function login(port, name) {
  const c = client(port); await c.open();
  c.send({ type: 'acct_auth', access_token: 'dev:' + name });
  let st = await c.next('acct_state', 5000);
  if (st.needs_nickname) { c.send({ type: 'acct_create_profile', nickname: name }); st = await c.next('acct_state', 5000); }
  c.id = st.user_id; c.nick = name; return c;
}
const pause = () => sleep(70);
async function social(c, type, user_id) { await pause(); c.send({ type, user_id }); return c.next(m => m.type === 'social_ok' || m.type === 'social_error', 5000); }
const drain = (...cs) => cs.forEach(c => c.inbox.splice(0));
// próximo party_event de qualquer um dos clientes (sem deixar espera pendurada que roube mensagens)
async function nextEvent(list, ms = 8000) {
  const t = Date.now();
  while (Date.now() - t < ms) {
    for (const [who, c] of list) { const i = c.inbox.findIndex(m => m.type === 'party_event'); if (i >= 0) return [who, c.inbox.splice(i, 1)[0]]; }
    await sleep(3);
  }
  return null;
}
// mesa local a partir da visão do jogador (girada: ele é o lugar 0)
function mirror(snap) {
  const g = new Marcha();
  g.pawns = snap.pawns.map(r => r.map(p => ({ ...p })));
  g.hands = snap.hand_counts.map((n, s) => (s === 0 ? snap.my_hand.slice() : Array(n).fill('2')));
  g.turn = snap.turn; g.winner = snap.winner; g.round_no = snap.round_no;
  return g;
}
async function startParty(A, B, game) {
  drain(A, B);
  await pause(); A.send({ type: 'invite_send', user_id: B.id, game });
  const sent = await A.next(m => m.type === 'invite_sent' || m.type === 'invite_error', 5000);
  const rec = await B.next('invite_received', 5000);
  await pause(); B.send({ type: 'invite_accept', invite_id: rec.invite.id });
  const sa = await A.next('party_start', 5000), sb = await B.next('party_start', 5000);
  return { sent, rec, sa, sb };
}

(async () => {
  const s = await startServer(ENV);
  const A = await login(s.port, 'AnaParty'), B = await login(s.port, 'BiaParty'), C = await login(s.port, 'CaioParty');
  await social(A, 'social_request', B.id); await social(B, 'social_accept', A.id);
  drain(A, B, C);
  // validações do convite
  await pause(); A.send({ type: 'invite_send', user_id: B.id, game: 'poker' });
  check((await A.next('invite_error', 4000)).code === 'bad_mode', 'modo desconhecido é recusado');
  await pause(); A.send({ type: 'invite_send', user_id: C.id, game: 'marcha' });
  check((await A.next('invite_error', 4000)).code === 'not_friends', 'só amigos recebem convite de MARCHA REAL');

  // ================= MARCHA REAL =================
  const { sent, rec, sa, sb } = await startParty(A, B, 'marcha');
  check(sent.invite.game === 'marcha' && rec.invite.mode_name === 'MARCHA REAL' && rec.invite.minutes === 0, 'convite de MARCHA REAL chega com o nome do modo');
  check(sa.game === 'marcha' && sb.game === 'marcha' && sa.room_id === sb.room_id, 'aceitar cria UMA mesa de MARCHA REAL para os dois');
  check(sa.players[0].name === 'AnaParty' && sa.players[2].name === 'BiaParty' && sa.players[1].bot && sa.players[3].bot, 'Ana vê: ela embaixo, Bia como aliada (em cima), bots dos lados');
  check(sb.players[0].name === 'BiaParty' && sb.players[2].name === 'AnaParty' && sb.players[1].bot && sb.players[3].bot, 'Bia vê a mesa girada: ela embaixo, Ana como aliada');
  check(!('hands' in sa.snapshot) && sa.snapshot.my_hand.length === 4 && sa.snapshot.hand_counts.every(n => n === 4), 'cada um recebe só a própria mão (as outras: só a quantidade)');
  // rotação coerente: o peão de Ana visto por Bia fica no lugar 2, com a casa girada 38
  const room = sa.room_id;
  // outro jogador não mexe; jogada fora da vez é recusada
  await pause(); C.send({ type: 'party_action', room_id: room, action: { kind: 'discard', card: 0 } });
  check((await C.next('party_error', 4000)).code === 'not_player', 'quem não está na mesa não joga');
  // marcha_status: a partida com amigo não consome a grátis do dia
  await pause(); A.send({ type: 'marcha_status' });
  const ms = await A.next('marcha_state', 4000);
  check(ms.used === 0, 'partida com amigo não consome a partida grátis do dia');
  // A ocupada: não entra em fila nem recebe outro convite
  await pause(); C.send({ type: 'social_request', user_id: A.id }); await C.next(m => m.type === 'social_ok' || m.type === 'social_error', 4000);
  await pause(); A.send({ type: 'social_accept', user_id: C.id }); await A.next(m => m.type === 'social_ok' || m.type === 'social_error', 4000);
  await pause(); C.send({ type: 'invite_send', user_id: A.id, game: 'xeque' });
  check((await C.next(m => m.type === 'invite_error' || m.type === 'invite_sent', 4000)).code === 'target_in_match', 'durante a mesa online o jogador aparece como em partida');
  // jogar a partida inteira (cada cliente joga quando é a vez dele; uma vez erra de propósito)
  let illegalTried = false, rejected = false, outOfTurn = false, moves = 0, viewsOk = true, ended = null, hiddenOk = true, burnSeen = false;
  let lastA = sa.snapshot, lastB = sb.snapshot;
  const play = async (c, snap, who) => {
    const g = mirror(snap);
    if (!illegalTried && who === 'A') {
      illegalTried = true;
      c.send({ type: 'party_action', room_id: room, action: { kind: 'move', card: 0, pawn: [0, 0], steps: 99 } });
      const e = await c.next(m => m.type === 'party_error', 4000).catch(() => null);
      rejected = !!e && e.code === 'illegal';
      await pause();
    }
    const mv = chooseAI(g, 0, null);
    c.send({ type: 'party_action', room_id: room, action: mv });
  };
  const t0 = Date.now();
  while (!ended && Date.now() - t0 < 240000) {
    const m = await nextEvent([['A', A], ['B', B]]);
    if (!m) break;
    const [who, ev] = m;
    const snap = ev.snapshot;
    if (who === 'A') lastA = snap; else lastB = snap;
    if (JSON.stringify(Object.keys(snap)).includes('"hands"')) hiddenOk = false;
    if (ev.ev === 'move') { moves++; if (ev.events.some(e => e.type === 'burn')) burnSeen = true; }
    if (ev.ev === 'end') { ended = ev; break; }
    if (ev.ev === 'turn' && snap.my_turn && snap.turn === 0) {
      if (!outOfTurn) {
        outOfTurn = true;
        const other = who === 'A' ? B : A;
        other.send({ type: 'party_action', room_id: room, action: { kind: 'discard', card: 0 } });
        const e = await other.next('party_error', 4000).catch(() => null);
        if (!e || e.code !== 'not_your_turn') outOfTurn = 'fail';
      }
      await play(who === 'A' ? A : B, snap, who);
    }
    // visões coerentes (a casa absoluta do peão de Ana: Ana vê no lugar 0, Bia vê no lugar 2 girado 38 casas)
    if (who === 'B' && lastA.ver === lastB.ver) {
      const pa = lastA.pawns[0], pb = lastB.pawns[2];
      for (let i = 0; i < 4; i++) {
        if (pa[i].zone !== pb[i].zone) viewsOk = false;
        if (pa[i].zone === 'track' && posmod(pa[i].pos - 38, 76) !== pb[i].pos) viewsOk = false;
      }
    }
  }
  check(rejected, 'jogada inválida é recusada pelo servidor (o motor valida)');
  check(outOfTurn === true, 'jogar fora da vez é recusado');
  check(hiddenOk, 'nenhuma mensagem leva as mãos dos outros');
  check(viewsOk, 'as duas visões giradas mostram o mesmo tabuleiro');
  check(!!ended && moves > 20, `MARCHA REAL online termina (${moves} jogadas, servidor anima e passa a vez)`);
  if (ended) {
    const w = ended.snapshot.winner, wb = lastB.winner;
    check((w === 0 || w === 1) && w === (ended.snapshot.winner), `vencedor anunciado (${w === 0 ? 'dupla de Ana e Bia' : 'bots'})`);
  }
  console.log('burn visto:', burnSeen);
  await sleep(200);
  drain(A, B, C);

  // ================= XEQUE =================
  const X = await startParty(A, B, 'xeque');
  check(X.sa.game === 'xeque' && X.sa.players[2].name === 'BiaParty' && X.sb.players[2].name === 'AnaParty', 'XEQUE: mesa de 4 (Ana, Bia e 2 bots), cada um vê a mesa girada');
  check(X.sa.snapshot.my_hand.length === 5 && !('clocks' in X.sa.snapshot) && X.sa.snapshot.clock_left.every(n => n === 6), 'XEQUE: só a própria mão; relógio público (6 posições), ordem escondida');
  const xroom = X.sa.room_id;
  let xEnded = null, plays = 0, challenges = 0, rounds = 0, timeoutSeen = false, leftOk = null, leaveDone = false;
  const t1 = Date.now();
  while (!xEnded && Date.now() - t1 < 120000) {
    const m = await nextEvent(leaveDone ? [['A', A]] : [['A', A], ['B', B]]);
    if (!m) break;
    const [who, ev] = m;
    const snap = ev.snapshot;
    if (ev.ev === 'play') { plays++; if (ev.reason === 'timeout') timeoutSeen = true; }
    if (ev.ev === 'challenge') challenges++;
    if (ev.ev === 'round') rounds++;
    if (ev.ev === 'left' && who === 'A') leftOk = ev.who === 2;
    if (ev.ev === 'end') { if (who === 'A') xEnded = ev; continue; }
    if (ev.ev === 'turn' && snap.my_turn && snap.turn === 0) {
      const c = who === 'A' ? A : B;
      if (who === 'B' && rounds >= 1 && !leaveDone) {
        // Bia deixa o tempo acabar uma vez e depois sai: o lugar dela passa a ser jogado pelo bot
        if (!timeoutSeen) continue;
        leaveDone = true; c.send({ type: 'party_leave', room_id: xroom }); await c.next('party_left', 4000); continue;
      }
      if (snap.can_challenge && Math.random() < 0.3) c.send({ type: 'party_action', room_id: xroom, action: { kind: 'challenge' } });
      else c.send({ type: 'party_action', room_id: xroom, action: { kind: 'play', idx: [0] } });
    }
  }
  check(plays > 3 && challenges >= 1, `XEQUE online: jogadas (${plays}) e XEQUE (${challenges}) resolvidos no servidor`);
  check(timeoutSeen, 'XEQUE: tempo esgotado → o servidor joga 1 carta pelo jogador');
  check(leftOk === true, 'XEQUE: amiga saiu → os outros são avisados e o lugar segue com bot');
  check(!!xEnded && (xEnded.snapshot.winner >= 0), 'XEQUE online termina com vencedor');
  // reconexão: depois do fim, party_sync responde sem mesa ativa
  await pause(); A.send({ type: 'party_sync' });
  const ps = await A.next(m => m.type === 'party_none' || m.type === 'party_start', 4000);
  check(ps.type === 'party_none' || ps.ended === true, 'partida encerrada não volta como ativa');

  // ================= reconexão no meio da partida =================
  drain(A, B);
  const R = await startParty(A, B, 'marcha');
  A.close(); await sleep(300);
  const A2 = await login(s.port, 'AnaParty');
  const resumed = await A2.next(m => m.type === 'party_start', 5000).catch(() => null);
  check(!!resumed && resumed.resumed === true && resumed.room_id === R.sa.room_id, 'reconectar devolve a mesa em andamento (party_start resumed)');
  await pause(); A2.send({ type: 'party_leave', room_id: R.sa.room_id }); await A2.next('party_left', 4000);
  await pause(); B.send({ type: 'party_leave', room_id: R.sa.room_id }); await B.next('party_left', 4000).catch(() => null);
  A2.close(); B.close(); C.close(); s.stop();
  summary('PARTY');
})().catch(e => { console.error(e); process.exitCode = 1; });
