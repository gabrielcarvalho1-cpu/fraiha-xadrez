"""Testes da correção dos IDs WebGL (rodar: python3 tools/web_release/test_gl_ids_reuse.py).
Opcional: FRAIHA_EXPORT_JS=<index.js de um export real> confere a correção no runtime de verdade."""
import json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gl_ids_reuse as G

TABS = G.TABELAS

# Runtime mínimo com os MESMOS trechos do Emscripten (criar = getNewId; apagar = os trechos trocados).
MINI = ("var GL={counter:1,buffers:[],framebuffers:[],programs:[],queries:[],renderbuffers:[],shaders:[],syncs:[],"
        "textures:[],vaos:[],contexts:[],"
        "getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret},};"
        "var GLctx={deleteVertexArray(){}};"
        + "".join("var del_%s=id=>{GL.%s[id]=null};" % (t, t) for t in TABS)
        + "var _glDeleteVertexArrays=(n,vaos)=>{for(var i=0;i<n;i++){var id=vaos[i];GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null}};")

SIM = r"""
%s
// simulação: muitos frames criando e apagando objetos de tipos diferentes (como syncs/texturas por frame)
var kinds=%s.concat(["vaos"]), live={}, rnd=1;
function r(n){rnd=(rnd*1103515245+12345)&0x7fffffff;return rnd%%n}
kinds.forEach(k=>live[k]=[]);
var ctx=GL.getNewId(GL.contexts);GL.contexts[ctx]={};
for(var f=0;f<%d;f++){
  for(var j=0;j<6;j++){var k=kinds[r(kinds.length)];var id=GL.getNewId(GL[k]);
    if(GL[k][id])throw new Error("REUSO_DE_ID_VIVO "+k+" "+id);
    GL[k][id]={k:k};live[k].push(id)}
  for(var j=0;j<6;j++){var k=kinds[r(kinds.length)];if(live[k].length>20){var id=live[k].splice(r(live[k].length),1)[0];
    if(k==="vaos")_glDeleteVertexArrays(1,[id]);else eval("del_"+k)(id)}}
  // nenhum ID vivo em duas tabelas
  if(f%%500===0){var seen={};kinds.concat(["contexts"]).forEach(k=>GL[k].forEach((v,i)=>{if(v){if(seen[i])throw new Error("COLISAO "+i);seen[i]=k}}))}
}
var maxLen=Math.max.apply(null,kinds.map(k=>GL[k].length));
var vivos=kinds.reduce((n,k)=>n+live[k].length,0);
console.log(JSON.stringify({counter:GL.counter,maxLen:maxLen,vivos:vivos,livres:GL.freeIds?GL.freeIds.length:0}));
"""


def node(js):
    d = tempfile.mkdtemp()
    try:
        p = os.path.join(d, "t.js")
        open(p, "w").write(js)
        out = subprocess.run(["node", p], capture_output=True, text=True, timeout=120)
        if out.returncode:
            raise AssertionError(out.stderr)
        return json.loads(out.stdout.strip().splitlines()[-1])
    finally:
        shutil.rmtree(d)


class GlIdsTest(unittest.TestCase):
    def test_aplica_e_e_idempotente(self):
        novo = G.aplicar(MINI)
        self.assertTrue(G.ja_aplicado(novo))
        with self.assertRaises(G.Erro):
            G.aplicar(novo)

    def test_runtime_desconhecido_para(self):
        with self.assertRaises(G.Erro):
            G.aplicar(MINI.replace("var ret=GL.counter++", "var ret=++GL.counter"))
        with self.assertRaises(G.Erro):
            G.aplicar(MINI + "GL.textures[id]=null")      # trecho duplicado: ambíguo

    def test_garantir_no_export(self):
        d = tempfile.mkdtemp()
        try:
            p = os.path.join(d, "index.js")
            open(p, "w").write(MINI)
            r1 = G.garantir(d)
            r2 = G.garantir(d)
            self.assertEqual((r1["estado"], r2["estado"]), ("aplicada", "ja_aplicada"))
            self.assertEqual(r1["sha_depois"], r2["sha_depois"])
            open(p, "w").write(open(p).read().replace(G.VAO_NOVO, G.VAO_ORIG))   # correção pela metade
            with self.assertRaises(SystemExit):
                G.garantir(d)
            open(p, "w").write("var x=1;")
            with self.assertRaises(SystemExit):
                G.garantir(d)
        finally:
            shutil.rmtree(d)

    def test_platô_sem_colisao(self):
        frames = 20000
        orig = node(SIM % (MINI, json.dumps(TABS), frames))
        novo = node(SIM % (G.aplicar(MINI), json.dumps(TABS), frames))
        # original: contador cresce com o total de objetos criados; corrigido: fica perto do máximo de vivos
        self.assertGreater(orig["counter"], frames * 5)
        self.assertLess(novo["counter"], 2000)
        self.assertLess(novo["maxLen"], 2000)
        self.assertGreater(orig["maxLen"], frames * 5)

    @unittest.skipUnless(os.environ.get("FRAIHA_EXPORT_JS"), "sem FRAIHA_EXPORT_JS")
    def test_runtime_real(self):
        js = open(os.environ["FRAIHA_EXPORT_JS"], encoding="utf-8").read()
        if G.MARCA in js:
            self.assertTrue(G.ja_aplicado(js))
        else:
            self.assertTrue(G.ja_aplicado(G.aplicar(js)))


if __name__ == "__main__":
    unittest.main()
