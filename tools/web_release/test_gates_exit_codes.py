"""Auditoria R46 · gates de empacotamento Web FAIL-CLOSED: sucesso = exit 0, qualquer falha = exit != 0.
Roda os scripts PowerShell GERADOS de verdade (MONTAR-UPLOAD / CONFERIR-SITE) com o PowerShell (pwsh).
Rodar: PWSH=/caminho/pwsh python3 tools/web_release/test_gates_exit_codes.py
Sem pwsh no ambiente os casos de execução são PULADOS (e o motivo é impresso) — os estáticos rodam sempre."""
import functools, hashlib, http.server, os, shutil, subprocess, sys, tempfile, threading, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_pack_web_release import fake_tree, PACK  # noqa: E402

PWSH = os.environ.get("PWSH") or shutil.which("pwsh") or shutil.which("powershell")
NEED = unittest.skipUnless(PWSH, "pwsh/powershell não encontrado: casos de execução PULADOS")


def build(base, big=True):
    exp, web = fake_tree(base, big=big)
    out = os.path.join(base, "OUT")
    r = subprocess.run([sys.executable, PACK, exp, web, out, "RT", "abc123"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    return out


def ps(script, *args):
    env = dict(os.environ, FRAIHA_NO_EXPLORER="1")
    return subprocess.run([PWSH, "-NoProfile", "-File", script, *args], capture_output=True, text=True, env=env, timeout=180)


class Static(unittest.TestCase):
    def test_cmd_wrapper_devolve_codigo(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t, big=False)
            for n in ("MONTAR-UPLOAD-RT.cmd", "CONFERIR-SITE-RT.cmd"):
                txt = open(os.path.join(out, n)).read()
                self.assertIn('set "RC=%ERRORLEVEL%"', txt, n)
                self.assertIn("exit /b %RC%", txt, n)
                self.assertLess(txt.index("set \"RC="), txt.index("pause"), n + ": código lido ANTES do pause")

    def test_scripts_terminam_com_exit(self):
        for n in ("MONTAR-UPLOAD.ps1", "CONFERIR-SITE.ps1"):
            txt = open(os.path.join(HERE, n), encoding="utf-8").read()
            self.assertIn("exit 1", txt.replace("exit $rc", "exit 1"), n)
        qa = open(os.path.join(HERE, "../../distribution/qa/RUN-QA.ps1"), encoding="utf-8").read()
        self.assertTrue(qa.rstrip().endswith("exit $rc"), "RUN-QA termina com exit $rc")
        self.assertIn("$rc = 0", qa)


@NEED
class Montar(unittest.TestCase):
    def montar(self, out):
        return ps(os.path.join(out, "MONTAR-UPLOAD-RT.ps1"))

    def test_B_valido_sai_0_e_upload_confere(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t)
            r = self.montar(out)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("CONFERIDO", r.stdout)
            up = os.path.join(out, "UPLOAD")
            self.assertTrue(os.path.isfile(os.path.join(up, "voice", "fraiha-voice-bridge-v1.js")))
            self.assertTrue(os.path.isfile(os.path.join(up, "index.pck")))

    def test_C_manifesto_ausente_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t, big=False)
            os.remove(os.path.join(out, "ARQUIVOS-SHA256.txt"))
            r = self.montar(out)
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertIn("ARQUIVOS-SHA256.txt", r.stdout)
            self.assertFalse(os.path.exists(os.path.join(out, "UPLOAD")))

    def test_D_arquivo_obrigatorio_ausente_falha(self):
        for rel in (("voice", "LEIA-ME-VOZ.txt"), ("engines", "stockfish-19-lite-single.wasm"), ("index.html",)):
            with tempfile.TemporaryDirectory() as t:
                out = build(t, big=False)
                os.remove(os.path.join(out, *rel))
                r = self.montar(out)
                self.assertNotEqual(r.returncode, 0, "/".join(rel) + " ausente: " + r.stdout)
                self.assertIn("FALTANDO", r.stdout)
                self.assertFalse(os.path.exists(os.path.join(out, "UPLOAD")), "UPLOAD parcial removido")

    def test_D2_parte_ausente_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t)
            os.remove(os.path.join(out, "index.pck.part01"))
            r = self.montar(out)
            self.assertNotEqual(r.returncode, 0, r.stdout)

    def test_E_hash_errado_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t, big=False)
            f = os.path.join(out, "voice", "fraiha-voice-bridge-v1.js")
            data = bytearray(open(f, "rb").read()); data[0] ^= 1          # mesmo tamanho, bytes diferentes
            open(f, "wb").write(bytes(data))
            r = self.montar(out)
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertIn("corrompido", r.stdout)

    def test_E_tamanho_errado_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t, big=False)
            with open(os.path.join(out, "index.js"), "ab") as f:
                f.write(b"x")
            r = self.montar(out)
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertIn("tamanho errado", r.stdout)

    def test_manifesto_incompleto_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out = build(t, big=False)
            m = os.path.join(out, "ARQUIVOS-SHA256.txt")
            lines = open(m, encoding="utf-8").read().splitlines()
            open(m, "w", encoding="utf-8").write("\n".join(l for l in lines if "voice/" not in l) + "\n")
            r = self.montar(out)
            self.assertNotEqual(r.returncode, 0, r.stdout)


@NEED
class Conferir(unittest.TestCase):
    def serve(self, root):
        h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
        h.log_message = lambda *a: None
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), h)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.shutdown)
        return "http://127.0.0.1:%d" % srv.server_address[1]

    def site_ok(self, t):
        out = build(t)
        self.assertEqual(ps(os.path.join(out, "MONTAR-UPLOAD-RT.ps1")).returncode, 0)
        return out, os.path.join(out, "UPLOAD")

    def test_tudo_no_ar_sai_0(self):
        with tempfile.TemporaryDirectory() as t:
            out, up = self.site_ok(t)
            r = ps(os.path.join(out, "CONFERIR-SITE-RT.ps1"), "-Site", self.serve(up))
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_faltando_no_site_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out, up = self.site_ok(t)
            os.remove(os.path.join(up, "voice", "fraiha-voice-bridge-v1.js"))   # o incidente do R45
            r = ps(os.path.join(out, "CONFERIR-SITE-RT.ps1"), "-Site", self.serve(up))
            self.assertNotEqual(r.returncode, 0, r.stdout)
            self.assertIn("FALTANDO NO SITE", r.stdout)

    def test_manifesto_ausente_falha(self):
        with tempfile.TemporaryDirectory() as t:
            out, up = self.site_ok(t)
            os.remove(os.path.join(out, "ARQUIVOS-SHA256.txt"))
            r = ps(os.path.join(out, "CONFERIR-SITE-RT.ps1"), "-Site", self.serve(up))
            self.assertNotEqual(r.returncode, 0, r.stdout)


if __name__ == "__main__":
    if not PWSH:
        print("AVISO: pwsh não encontrado — só os testes estáticos rodam; os de execução ficam PULADOS.")
    unittest.main(verbosity=2)
