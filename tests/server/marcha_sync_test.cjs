// R37 · MARCHA REAL: uma fonte da verdade entre o Godot (rules.gd / marcha_ui.gd) e o servidor
// (marcha_rules.js / party.js): versão das regras, funções do Ás e do Rei, e os tempos de animação
// que o servidor espera antes da próxima vez. Sem rede: só lê os arquivos.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
for (const k of Object.keys(process.env)) if (k.startsWith('FRAIHA_PARTY_')) delete process.env[k];
const M = require(path.join(ROOT, 'online_v021/modes/marcha_rules.js'));
const { T } = require(path.join(ROOT, 'online_v021/modes/party.js'));
const gd = read('marcha/rules.gd'), ui = read('marcha/marcha_ui.gd'), js = read('online_v021/modes/marcha_rules.js');
let pass = 0, fail = 0;
const check = (ok, msg) => { if (ok) pass++; else { fail++; console.log('FAIL: ' + msg); } };
check(gd.match(/const RULESET_VERSION := "([^"]+)"/)[1] === M.RULESET_VERSION, 'RULESET_VERSION igual (' + M.RULESET_VERSION + ')');
const ace = (s) => s.match(/ACE_STEPS\s*:?=\s*\[([^\]]+)\]/)[1].replace(/\s/g, '');
check(ace(gd) === ace(js), 'Ás anda o mesmo nas duas pontas: ' + ace(gd));
check(!/"K":\s*13/.test(gd) && !/K:\s*13/.test(js), 'Rei não anda (sem 13) nas duas pontas');
const sec = (name) => Math.round(+ui.match(new RegExp(`const ${name} := ([\\d.]+)`))[1] * 1000);
check(sec('STEP_TIME') === T.stepMs, `passo por casa cliente ${sec('STEP_TIME')} = servidor ${T.stepMs}`);
check(sec('CARD_FLY') === T.cardFlyMs, 'voo da carta cliente = servidor');
check(sec('EXIT_TIME') === T.exitMs && sec('CAPTURE_TIME') === T.captureMs && sec('CROWN_WAIT') === T.crownMs, 'saída / abatido / chegada: cliente = servidor');
// R37.2 · 5 no peão adversário perto da Entrada dele: passa e dá a volta (servidor igual ao Godot)
{
  const g = new M.Marcha(); g.setup(52);
  for (let s = 0; s < 4; s++) for (let i = 0; i < 4; i++) g.pawns[s][i] = { zone: 'home', pos: i };
  const e1 = M.entranceIndex(1);
  g.pawns[1][0] = { zone: 'track', pos: M.posmod(e1 - 3, M.TRACK) };
  g.hands[0] = ['5'];
  const mv = g.legalMoves(0, 0).find(m => m.pawn[0] === 1 && m.pawn[1] === 0);
  g.apply(0, mv);
  check(g.pawns[1][0].zone === 'track' && g.pawns[1][0].pos === M.posmod(e1 + 2, M.TRACK), 'servidor: 5 no adversário passa da Entrada e dá a volta');
}
console.log(`marcha_sync_test ${pass}/${pass + fail} ${fail ? 'FAIL' : 'OK'}`);
process.exit(fail ? 1 : 0);
