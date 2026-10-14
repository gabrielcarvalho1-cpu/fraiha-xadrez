"""Testes do empacotamento Web (rodar: python3 tools/web_release/test_pack_web_release.py)."""
import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "pack_web_release.py")
INDEX = ["index.html", "index.js", "index.wasm", "index.pck", "index.png", "index.icon.png",
         "index.apple-touch-icon.png", "index.audio.worklet.js", "index.audio.position.worklet.js"]


HTML = ('<html><head><link rel="icon" href="index.icon.png"/><style>#s{background:url("index.png")}</style></head>'
        '<body><img id="status-splash" src="index.png"><script src="index.js"></script><script>\n'
        'const GODOT_CONFIG = {"args":[],"executable":"index","fileSizes":{"index.pck":%d,"index.wasm":%d},"gdextensionLibs":[]};\n'
        'const engine = new Engine(GODOT_CONFIG);</script></body></html>')


CFG = ('[online]\nserver_url="wss://fraiha-xadrez.onrender.com"\n\n[accounts]\nsupabase_url=""\n\n'
       '[staging]\nserver_url="wss://fraiha-xadrez-staging.onrender.com"\n')


# R94 · index.js mínimo com os trechos do runtime Emscripten que a correção dos IDs WebGL troca.
FAKE_JS = ("var GL={counter:1,buffers:[],textures:[],vaos:[],"
           "getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret},};"
           + "".join("function d_%s(id){GL.%s[id]=null}" % (t, t) for t in
                     ["buffers", "framebuffers", "programs", "queries", "renderbuffers", "shaders", "syncs", "textures"])
           + "var _glDeleteVertexArrays=(n,vaos)=>{for(var i=0;i<n;i++){var id=vaos[i];GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null}};"
           # R99 · trechos do runtime de áudio que a liberação de amostras exige
           + "".join(__import__("audio_samples_release").DEPENDE) + __import__("audio_samples_release").CREATE_ORIG)


def make_pck(features="staging", cfg=CFG, pad=b""):
    """PCK mínimo do Godot 4 (formato 3) com project.binary (_custom_features) + online.cfg + um arquivo de enchimento."""
    import struct
    pb = b""
    if features is not None:
        k, v = b"_custom_features", features.encode()
        val = struct.pack("<II", 4, len(v)) + v + b"\0" * (-len(v) % 4)
        pb = struct.pack("<I", 1) + struct.pack("<I", len(k)) + k + struct.pack("<I", len(val)) + val
    files = [("res://project.binary", pb), ("res://online.cfg", cfg.encode()), ("res://pad.bin", pad)]
    base = 4 + 4 * 4 + 4 + 8 + 8 + 16 * 4
    data, entries, off = b"", [], 0
    for path, content in files:
        entries.append((path, off, len(content)))
        data += content
        off += len(content)
    d = struct.pack("<I", len(files))
    for path, o, n in entries:
        pe = path.encode(); pe += b"\0" * (-len(pe) % 4)
        d += struct.pack("<I", len(pe)) + pe + struct.pack("<QQ", o, n) + b"\0" * 16 + struct.pack("<I", 0)
    head = b"GDPC" + struct.pack("<IIIIIQQ", 3, 4, 5, 1, 2, base, base + len(data)) + b"\0" * 64
    return head + data + d


def fake_tree(base, with_voice=True, big=False, pck_bytes=None, features="staging", cfg=CFG):
    exp, web = os.path.join(base, "export"), os.path.join(base, "web")
    os.makedirs(exp); os.makedirs(os.path.join(web, "engines"))
    pck = make_pck(features, cfg, pck_bytes if pck_bytes is not None else (os.urandom(19922944 * 2 + 5) if big else b"index.pck"))
    for n in INDEX:
        with open(os.path.join(exp, n), "wb") as f:
            f.write(pck if n == "index.pck" else (HTML % (len(pck), len(b"index.wasm"))).encode() if n == "index.html"
                    else FAKE_JS.encode() if n == "index.js" else n.encode())
    for n in ["stockfish-19-lite-single.js", "stockfish-19-lite-single.wasm", "COPYING-GPLv3.txt"]:
        open(os.path.join(web, "engines", n), "w").write(n)
    os.makedirs(os.path.join(web, "gl_recovery"))
    with open(os.path.join(HERE, "../../web/gl_recovery/fraiha-gl-recovery.js"), encoding="utf-8") as f:
        open(os.path.join(web, "gl_recovery", "fraiha-gl-recovery.js"), "w", encoding="utf-8").write(f.read())
    if with_voice:
        os.makedirs(os.path.join(web, "voice"))
        for n in ["AgoraRTC_N-4.24.8.js", "fraiha-voice-bridge-v1.js", "LEIA-ME-VOZ.txt"]:
            open(os.path.join(web, "voice", n), "w").write(n)
    return exp, web


class PackTest(unittest.TestCase):
    def run_pack(self, base, exp, web, *extra, out="OUT"):
        out = os.path.join(base, out)
        if not any(e.startswith("--ambiente") or e == "--sem-ambiente" for e in extra):
            extra = extra + ("--ambiente=staging",)
        extra = tuple(e for e in extra if e != "--sem-ambiente")
        return out, subprocess.run([sys.executable, PACK, exp, web, out, "RTEST", "abc123", *extra], capture_output=True, text=True)

    # ---- AMBIENTE (QA/staging × produção): conferido no próprio PCK, fail-closed
    def test_ambiente_staging_marcado(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t))
            self.assertEqual(r.returncode, 0, r.stderr)
            man = open(os.path.join(out, "ARQUIVOS-SHA256.txt"), encoding="utf-8").read()
            self.assertIn("# AMBIENTE staging - servidor wss://fraiha-xadrez-staging.onrender.com\n", man)
            self.assertIn('<meta name="fraiha-ambiente" content="staging">', open(os.path.join(out, "index.html"), encoding="utf-8").read())
            self.assertIn("STAGING", r.stdout)

    def test_ambiente_producao_marcado(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, features="production"), "--ambiente=producao")
            self.assertEqual(r.returncode, 0, r.stderr)
            man = open(os.path.join(out, "ARQUIVOS-SHA256.txt"), encoding="utf-8").read()
            self.assertIn("# AMBIENTE producao - servidor wss://fraiha-xadrez.onrender.com\n", man)
            self.assertIn('<meta name="fraiha-ambiente" content="producao">', open(os.path.join(out, "index.html"), encoding="utf-8").read())

    def test_ambiente_falha_fechado(self):
        stg = CFG.replace("fraiha-xadrez.onrender.com", "fraiha-xadrez-staging.onrender.com")
        casos = [
            ("staging pedido como produção", dict(features="staging"), "--ambiente=producao", "PCK é de STAGING"),
            ("produção pedida como staging", dict(features="production"), "--ambiente=staging", "PCK é de PRODUCAO"),
            ("produção com [online] = staging", dict(features="production", cfg=stg), "--ambiente=producao", "PRODUÇÃO apontando para STAGING"),
            ("produção com outro servidor", dict(features="production", cfg=CFG.replace("fraiha-xadrez.onrender.com", "outro.example.com")), "--ambiente=producao", "o oficial é"),
            ("staging e produção juntos", dict(features="staging,production"), "--ambiente=producao", "staging E produção"),
            ("sem feature de ambiente", dict(features=None), "--ambiente=producao", "sem feature de ambiente".replace("sem feature de ambiente", "não tem feature de ambiente")),
            ("ambiente não informado", dict(), "--sem-ambiente", "informe o ambiente"),
            ("ambiente inválido", dict(), "--ambiente=prod", "ambiente declarado inválido"),
            ("sem online.cfg no PCK", dict(cfg=None), "--ambiente=staging", "online.cfg ausente"),
        ]
        for nome, kw, flag, msg in casos:
            with self.subTest(nome), tempfile.TemporaryDirectory() as t:
                if kw.get("cfg", "") is None:
                    exp, web = fake_tree(t)
                    raw = open(os.path.join(exp, "index.pck"), "rb").read().replace(b"res://online.cfg", b"res://online.xyz")
                    open(os.path.join(exp, "index.pck"), "wb").write(raw)
                else:
                    exp, web = fake_tree(t, **kw)
                out, r = self.run_pack(t, exp, web, flag)
                self.assertNotEqual(r.returncode, 0, nome)
                self.assertIn(msg, r.stdout + r.stderr, nome)
                self.assertFalse(os.path.exists(out), nome)

    def test_presets_staging_e_producao(self):
        """export_presets.cfg: "Web Alpha" = staging e "Web Producao" = production, com as MESMAS opções."""
        import configparser
        cp = configparser.RawConfigParser(strict=False)
        cp.read(os.path.join(HERE, "../../export_presets.cfg"), encoding="utf-8")
        web = {cp.get(s, "name").strip('"'): s for s in cp.sections() if s.count(".") == 1 and cp.get(s, "platform").strip('"') == "Web"}
        self.assertEqual(sorted(web), ["Web Alpha", "Web Producao"])
        a, p = web["Web Alpha"], web["Web Producao"]
        self.assertEqual(cp.get(a, "custom_features"), '"staging"')
        self.assertEqual(cp.get(p, "custom_features"), '"production"')
        for sec in ("", ".options"):
            da, dp = dict(cp.items(a + sec)), dict(cp.items(p + sec))
            for k in ("name", "custom_features"):
                da.pop(k, None); dp.pop(k, None)
            self.assertEqual(da, dp, "os presets Web divergem em " + (sec or "preset"))

    def test_sem_voice_nao_gera(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, with_voice=False))
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("voice/fraiha-voice-bridge-v1.js", r.stdout + r.stderr)
            self.assertFalse(os.path.exists(out))

    def test_manifesto_lista_voice_e_partes(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, big=True), "--legado")
            self.assertEqual(r.returncode, 0, r.stderr)
            rows = [l for l in open(os.path.join(out, "ARQUIVOS-SHA256.txt"), encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
            rels = [l.split()[0] for l in rows]
            self.assertEqual(len(rows), 15)
            for v in ["voice/AgoraRTC_N-4.24.8.js", "voice/fraiha-voice-bridge-v1.js", "voice/LEIA-ME-VOZ.txt", "engines/stockfish-19-lite-single.wasm"]:
                self.assertIn(v, rels)
            self.assertTrue(os.path.isfile(os.path.join(out, "voice", "fraiha-voice-bridge-v1.js")))
            self.assertTrue(os.path.isfile(os.path.join(out, "index.pck.part02")))
            self.assertFalse(os.path.exists(os.path.join(out, "index.pck")))
            # PNG vai em base64 e decodifica para os mesmos bytes do manifesto
            import base64, hashlib
            self.assertFalse(os.path.exists(os.path.join(out, "index.icon.png")))
            raw = base64.b64decode(open(os.path.join(out, "index.icon.png.b64"), encoding="ascii").read())
            row = [l for l in rows if l.split()[0] == "index.icon.png"][0].split()
            self.assertEqual((len(raw), hashlib.sha256(raw).hexdigest().upper()), (int(row[1]), row[2]))
            for n in ["MONTAR-UPLOAD-RTEST.ps1", "MONTAR-UPLOAD-RTEST.cmd", "CONFERIR-SITE-RTEST.ps1", "CONFERIR-SITE-RTEST.cmd"]:
                self.assertTrue(os.path.isfile(os.path.join(out, n)), n)
            self.assertNotIn("__TAG__", open(os.path.join(out, "MONTAR-UPLOAD-RTEST.ps1"), encoding="utf-8-sig").read())

    def test_nomes_com_sha256(self):
        import base64, hashlib, json, re
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, big=True))
            self.assertEqual(r.returncode, 0, r.stderr)
            man = open(os.path.join(out, "ARQUIVOS-SHA256.txt"), encoding="utf-8").read()
            self.assertIn("# R55.5 ", man)                       # o MONTAR-UPLOAD separa o index.html por isso
            rows = [l.split() for l in man.splitlines() if l and not l.startswith("#")]
            rels = [x[0] for x in rows]
            self.assertEqual(len(rows), 15)
            for legado in ["index.pck", "index.wasm", "index.js", "index.png", "index.audio.worklet.js"]:
                self.assertNotIn(legado, rels)                 # nada com nome fixo de motor/pacote
            pck = [x for x in rels if re.fullmatch(r"index-p[0-9a-f]{16}\.pck", x)]
            exe = sorted(x for x in rels if re.fullmatch(r"index-e[0-9a-f]{16}\..+", x))
            self.assertEqual(len(pck), 1)
            self.assertEqual([x.split(".", 1)[1] for x in exe], ["audio.position.worklet.js", "audio.worklet.js", "js", "wasm"])
            raw = open(os.path.join(t, "export", "index.pck"), "rb").read()
            self.assertEqual(pck[0], "index-p%s.pck" % hashlib.sha256(raw).hexdigest()[:16])
            self.assertTrue(os.path.isfile(os.path.join(out, pck[0] + ".part02")))
            html = open(os.path.join(out, "index.html"), encoding="utf-8").read()
            cfg = json.loads(re.search(r"const GODOT_CONFIG = (\{.*?\});", html).group(1))
            e = exe[0].split(".")[0]
            self.assertEqual((cfg["executable"], cfg["mainPack"]), (e, pck[0]))
            self.assertEqual(cfg["fileSizes"], {pck[0]: len(raw), e + ".wasm": len(b"index.wasm")})
            self.assertIn('<script src="%s.js"></script>' % e, html)
            self.assertNotIn('src="index.js"', html)
            self.assertNotIn('"index.png"', html)
            self.assertIn('id="fraiha-asset-cache"', html)
            self.assertIn(pck[0], html.split('id="fraiha-asset-cache"')[1].split("</script>")[0])
            row = [x for x in rows if x[0] == "index.html"][0]
            self.assertEqual(row[2], hashlib.sha256(html.encode("utf-8")).hexdigest().upper())

    def test_release_novo_muda_so_o_pacote(self):
        import re
        names = []
        for pck in [b"versao-1" * 100, b"versao-2" * 100]:
            with tempfile.TemporaryDirectory() as t:
                out, r = self.run_pack(t, *fake_tree(t, pck_bytes=pck))
                self.assertEqual(r.returncode, 0, r.stderr)
                names.append(sorted(l.split()[0] for l in open(os.path.join(out, "ARQUIVOS-SHA256.txt"), encoding="utf-8") if l.startswith("index-")))
        motor = lambda ns: [n for n in ns if n.startswith("index-e")]
        pacote = lambda ns: [n for n in ns if n.startswith("index-p")]
        self.assertEqual(motor(names[0]), motor(names[1]))       # mesmo Godot: WASM continua em cache
        self.assertNotEqual(pacote(names[0]), pacote(names[1]))  # jogo novo: PCK com nome novo

    def test_recuperacao_webgl_nos_dois_modos(self):
        for extra in ([], ["--legado"]):
            with tempfile.TemporaryDirectory() as t:
                out, r = self.run_pack(t, *fake_tree(t), *extra)
                self.assertEqual(r.returncode, 0, r.stderr)
                html = open(os.path.join(out, "index.html"), encoding="utf-8").read()
                self.assertEqual(html.count('<script id="fraiha-gl-recovery">'), 1, extra)
                # vem antes de qualquer outro script (o ouvinte em captura precisa existir antes do Godot)
                self.assertLess(html.index('id="fraiha-gl-recovery"'), html.index("<script src="), extra)
                self.assertIn("webglcontextlost", html)

    def test_sem_recuperacao_webgl_nao_gera(self):
        with tempfile.TemporaryDirectory() as t:
            exp, web = fake_tree(t)
            os.remove(os.path.join(web, "gl_recovery", "fraiha-gl-recovery.js"))
            out, r = self.run_pack(t, exp, web)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("fraiha-gl-recovery.js", r.stdout + r.stderr)
            self.assertFalse(os.path.exists(out))

    def test_html_inesperado_falha_fechado(self):
        with tempfile.TemporaryDirectory() as t:
            exp, web = fake_tree(t)
            open(os.path.join(exp, "index.html"), "w").write("<html>sem config</html>")
            out, r = self.run_pack(t, exp, web)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("GODOT_CONFIG", r.stdout + r.stderr)
            self.assertFalse(os.path.exists(out))


if __name__ == "__main__":
    unittest.main()
