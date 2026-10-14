"""Testes da liberação segura das amostras de áudio Web (rodar: python3 tools/web_release/test_audio_samples_release.py).
Opcional: FRAIHA_EXPORT_JS=<index.js de um export real> confere o patch no runtime de verdade (Godot 4.5.1)."""
import json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audio_samples_release as A

# GodotAudio mínimo com os MESMOS trechos do runtime (Sample.create/clear, SampleNode.streamObjectId).
MINI = (
    "var GodotAudio={samples:new Map(),sampleNodes:new Map(),"
    "Sample:class Sample{static getSampleOrNull(id){return GodotAudio.samples.get(id)??null}"
    + A.CREATE_ORIG +
    "static delete(id){GodotAudio.samples.delete(id)}constructor(p){this.id=p.id;this._audioBuffer=p.audioBuffer}"
    "setAudioBuffer(v){this._audioBuffer=v}clear(){this.setAudioBuffer(null);GodotAudio.Sample.delete(this.id)}},"
    "SampleNode:class N{constructor(params){this.streamObjectId=params.streamObjectId;}}};"
    "/*deps*/var _y='return Number(GodotAudio.Sample.getSampleOrNull(streamObjectId)!=null)';"
    "var _z='sampleNodes:null,SampleNode:class SampleNode{';"
)

SIM = r"""
%s
const G = globalThis.fraihaGodotAudio === undefined ? null : globalThis.fraihaGodotAudio;
const buf = n => ({ length: n, numberOfChannels: 2 });
const reg = id => GodotAudio.Sample.create({ id, audioBuffer: buf(1000) });
const out = {};
reg('1'); reg('2'); reg('3');
out.exposed = globalThis.fraihaGodotAudio === GodotAudio;
GodotAudio.sampleNodes.set('p1', new GodotAudio.SampleNode({ streamObjectId: '2' }));   // '2' tocando
GodotAudio.sampleNodes.set('p2', new GodotAudio.SampleNode({ streamObjectId: '2' }));   // e outra reprodução dele
let r = GodotAudio.Sample.fraihaRelease(['1', '2', '99']);
out.first = r;
out.after1 = [...GodotAudio.samples.keys()];
GodotAudio.sampleNodes.delete('p1');
r = GodotAudio.Sample.fraihaRelease([]);
out.second = r; out.after2 = [...GodotAudio.samples.keys()];
GodotAudio.sampleNodes.delete('p2');
r = GodotAudio.Sample.fraihaRelease([]);
out.third = r; out.after3 = [...GodotAudio.samples.keys()];
out.stats = GodotAudio.Sample.fraihaStats();
clearTimeout(GodotAudio.fraihaTimer);
console.log(JSON.stringify(out));
"""


def node(js):
    d = tempfile.mkdtemp()
    try:
        p = os.path.join(d, "t.js")
        open(p, "w").write(js)
        return subprocess.run(["node", p], capture_output=True, text=True, timeout=30)
    finally:
        shutil.rmtree(d)


class T(unittest.TestCase):
    def test_aplica_uma_vez_e_idempotente(self):
        js = A.aplicar(MINI)
        self.assertTrue(A.ja_aplicado(js))
        with self.assertRaises(A.Erro):
            A.aplicar(js)          # trecho original já não existe: não aplica duas vezes

    def test_fail_closed_sem_dependencia(self):
        with self.assertRaises(A.Erro):
            A.aplicar(MINI.replace("streamObjectId=params.streamObjectId;", ""))
        with self.assertRaises(A.Erro):
            A.aplicar(MINI.replace(A.CREATE_ORIG, "static create(){}"))

    def test_so_libera_sem_reproducao_ativa(self):
        r = node(SIM % A.aplicar(MINI))
        self.assertEqual(r.returncode, 0, r.stderr)
        o = json.loads(r.stdout.strip().splitlines()[-1])
        self.assertTrue(o["exposed"])
        self.assertEqual(o["first"]["released"], 1)          # '1' livre; '99' não existe; '2' tocando
        self.assertEqual(o["first"]["pending"], 1)
        self.assertEqual(sorted(o["after1"]), ["2", "3"])     # '3' não foi pedido: fica
        self.assertEqual(o["second"]["released"], 0)          # ainda há uma reprodução de '2'
        self.assertEqual(sorted(o["after2"]), ["2", "3"])
        self.assertEqual(o["third"]["released"], 1)           # as duas acabaram: sai
        self.assertEqual(o["after3"], ["3"])
        self.assertEqual(o["stats"]["released"], 2)
        self.assertEqual(o["stats"]["pending"], 0)

    def test_garantir_em_pasta(self):
        d = tempfile.mkdtemp()
        try:
            open(os.path.join(d, "index.js"), "w").write(MINI)
            self.assertEqual(A.garantir(d)["estado"], "aplicada")
            self.assertEqual(A.garantir(d)["estado"], "ja_aplicada")
        finally:
            shutil.rmtree(d)

    @unittest.skipUnless(os.environ.get("FRAIHA_EXPORT_JS"), "sem export real")
    def test_runtime_real(self):
        js = open(os.environ["FRAIHA_EXPORT_JS"], encoding="utf-8").read()
        if A.MARCA not in js:
            js = A.aplicar(js)
        self.assertTrue(A.ja_aplicado(js))


if __name__ == "__main__":
    unittest.main()
