// R36 · uma fonte da verdade: as constantes do XEQUE no Godot (rules.gd / xeque_ui.gd), no servidor
// (xeque_rules.js / party.js) e na arte das cartas (tools/xeque_card_counts.py) precisam bater.
// Sem rede, sem servidor: só lê os arquivos.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
for (const k of Object.keys(process.env)) if (k.startsWith('FRAIHA_PARTY_')) delete process.env[k];   // padrões de produção
const X = require(path.join(ROOT, 'online_v021/modes/xeque_rules.js'));
const { T } = require(path.join(ROOT, 'online_v021/modes/party.js'));
const { rngFrom } = require(path.join(ROOT, 'online_v021/modes/rng.js'));

let pass = 0, fail = 0;
const check = (ok, msg) => { if (ok) pass++; else { fail++; console.log('FAIL: ' + msg); } };
const gd = read('xeque/rules.gd'), ui = read('xeque/xeque_ui.gd'), js = read('online_v021/modes/xeque_rules.js'), art = read('tools/xeque_card_counts.py');
const nums = (s) => s.split(',').map(Number);

const gdChances = nums(gd.match(/const CLOCK_CHANCES := \[([^\]]+)\]/)[1]);
check(JSON.stringify(gdChances) === JSON.stringify(X.CLOCK_CHANCES), `CLOCK_CHANCES Godot ${gdChances} = servidor ${X.CLOCK_CHANCES}`);
check(gdChances[0] <= 0.15 && gdChances[gdChances.length - 1] === 1 && gdChances.every((c, i) => i === 0 || c > gdChances[i - 1]), '1º nível ≤ 15%, crescente, último = 100%');
check(gd.match(/const RULESET_VERSION := "(\d+)"/)[1] === X.RULESET_VERSION, 'RULESET_VERSION igual');

const gdDeck = {};
for (const [, k, n] of gd.match(/const DECK_COUNTS := \{([^}]+)\}/)[1].matchAll(/(\w+): (\d+)/g)) gdDeck[{ KING: 'rei', QUEEN: 'rainha', KNIGHT: 'cavalo', JOKER: 'peao' }[k]] = +n;
const artDeck = JSON.parse(art.match(/COUNTS\s*=\s*(\{[^}]+\})/)[1]);
check(JSON.stringify(gdDeck) === JSON.stringify({ rei: 6, rainha: 6, cavalo: 6, peao: 2 }), 'baralho do motor 6/6/6/2: ' + JSON.stringify(gdDeck));
check(JSON.stringify(artDeck) === JSON.stringify(gdDeck), 'números impressos nas cartas = baralho do motor');
const g = new X.Xeque(rngFrom(7)); g.setup();
const jsDeck = {}; for (const h of g.hands) for (const c of h) jsDeck[c] = (jsDeck[c] || 0) + 1;
check(Object.values(jsDeck).reduce((a, b) => a + b, 0) === 20 && Object.entries(jsDeck).every(([k, n]) => n <= gdDeck[k]), 'servidor distribui do mesmo baralho de 20');

const phase = {}; for (const [, k, v] of ui.match(/const PHASE_TIME := \{([^}]+)\}/)[1].matchAll(/"(\w+)": ([\d.]+)/g)) phase[k] = Math.round(+v * 1000);
check(phase.reveal === T.revealMs && phase.clock === T.clockMs && phase.safe === T.safeMs && phase.mate === T.mateMs, 'tempos das fases cliente = servidor ' + JSON.stringify(phase));
const f = (name) => Math.round(+ui.match(new RegExp(`const ${name} := ([\\d.]+)`))[1] * 1000);
check(f('INTRO_T') === T.introMs, 'apresentação do baralho cliente = servidor');
check(f('DEAL_T') + f('MESA_T') <= T.mesaMs, 'servidor espera distribuição + MESA do cliente');
check(f('BOT_DELAY_MIN') === T.xequeBotMin && f('BOT_DELAY_MAX') === T.xequeBotMax, 'ritmo dos bots cliente = servidor');

// sorteio do relógio: mesma semente → mesma sequência (testável)
const run = (sd) => { const a = new X.Xeque(rngFrom(sd)); a.setup(); const out = []; for (let i = 0; i < 40; i++) { a.resetClock(0); out.push(a.pullClock(0)); } return out.join(''); };
check(run(99) === run(99) && run(99) !== run(100), 'sorteio do relógio reproduzível com semente');

console.log(`xeque_sync_test ${pass}/${pass + fail} ${fail ? 'FAIL' : 'OK'}`);
process.exit(fail ? 1 : 0);
