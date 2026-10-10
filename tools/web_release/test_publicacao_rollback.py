"""Publicação Web: conferência FORTE (SHA-256 no site) e ROLLBACK antes de publicar — simulação completa.

Duas entregas reais do empacotador (v1 e v2: pacote diferente E um arquivo de URL estável alterado com o mesmo
tamanho) servidas por um site HTTP local. Roda os scripts PowerShell de verdade.
  PWSH=<pwsh> python3 tools/web_release/test_publicacao_rollback.py
"""
import functools, glob, http.server, os, shutil, sys, tempfile, threading, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_pack_web_release import fake_tree, PACK  # noqa: E402
from test_gates_exit_codes import PWSH, ps, named  # noqa: E402
import subprocess  # noqa: E402

NEED = unittest.skipUnless(PWSH, "pwsh/powershell não encontrado")
STABLE = os.path.join("voice", "LEIA-ME-VOZ.txt")


def entrega(base, nome, pck, voz):
    """Entrega empacotada (staging) com pacote `pck` e voice/LEIA-ME-VOZ.txt = `voz`."""
    os.makedirs(os.path.join(base, nome))
    exp, web = fake_tree(os.path.join(base, nome), pck_bytes=pck)
    open(os.path.join(web, STABLE), "w").write(voz)
    out = os.path.join(base, nome, "OUT")
    r = subprocess.run([sys.executable, PACK, exp, web, out, "RT", nome, "--ambiente=staging"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    return out


def copiar(src, dst):
    for p in glob.glob(os.path.join(src, "**", "*"), recursive=True):
        if os.path.isfile(p):
            d = os.path.join(dst, os.path.relpath(p, src))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copyfile(p, d)


@NEED
class Publicacao(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.site = os.path.join(cls.tmp, "site")
        os.makedirs(cls.site)
        h = functools.partial(http.server.SimpleHTTPRequestHandler, directory=cls.site)
        h.log_message = lambda *a: None
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), h)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.url = "http://127.0.0.1:%d" % cls.srv.server_address[1]
        cls.v1 = entrega(cls.tmp, "v1", b"PACOTE-VERSAO-1" * 50, "voz versao A\n")
        cls.v2 = entrega(cls.tmp, "v2", b"PACOTE-VERSAO-2" * 50, "voz versao B\n")   # estável: MESMO tamanho, conteúdo novo
        # v1: rollback com site vazio (primeira publicação) → montar → publicar
        r = ps(os.path.join(cls.v1, "ROLLBACK-ANTES-DE-PUBLICAR-RT.ps1"), "-Site", cls.url)
        assert r.returncode == 0 and "primeira publicacao" in r.stdout, r.stdout
        assert ps(os.path.join(cls.v1, "MONTAR-UPLOAD-RT.ps1")).returncode == 0
        cls.publicar(cls.v1)
        # v2: rollback ANTES de publicar (site está na v1)
        cls.rb = ps(os.path.join(cls.v2, "ROLLBACK-ANTES-DE-PUBLICAR-RT.ps1"), "-Site", cls.url)
        assert ps(os.path.join(cls.v2, "MONTAR-UPLOAD-RT.ps1")).returncode == 0
        cls.v1_site = os.path.join(cls.tmp, "v1_site")
        shutil.copytree(cls.site, cls.v1_site)

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def publicar(cls, out, index=True, assets=True):
        if assets:
            copiar(os.path.join(out, "UPLOAD"), cls.site)
        if index:
            shutil.copyfile(os.path.join(out, "UPLOAD-2-POR-ULTIMO", "index.html"), os.path.join(cls.site, "index.html"))

    def site_v1(self):
        shutil.rmtree(self.site)
        shutil.copytree(self.v1_site, self.site)

    def conferir(self, out):
        return ps(os.path.join(out, "CONFERIR-SITE-RT.ps1"), "-Site", self.url)

    def rollback_dir(self):
        ds = sorted(p for p in glob.glob(os.path.join(self.v2, "ROLLBACK-*")) if os.path.isdir(p))
        self.assertEqual(len(ds), 1)
        return ds[0]

    # ---------- rollback gerado ANTES de publicar ----------
    def test_0_rollback_lista_preservar_e_sobrescrever(self):
        self.assertEqual(self.rb.returncode, 0, self.rb.stdout)
        d = self.rollback_dir()
        leia = open(os.path.join(d, "LEIA-ME-ROLLBACK.txt"), encoding="utf-8-sig").read()
        man = open(os.path.join(d, "ARQUIVOS-SHA256.txt")).read()
        pre = leia.split("PRESERVAR NO BUCKET")[1].split("URL ESTAVEL QUE")[0]
        for n in (named(self.v1, "index-p", ".pck"), named(self.v1, "index-e", ".wasm"), named(self.v1, "index-s", ".png")):
            self.assertIn(n, pre, "fingerprint da versão anterior precisa ser preservado")
        sob = leia.split("VAI SOBRESCREVER")[1].split("URL ESTAVEL IDENTICA")[0]
        self.assertIn("voice/LEIA-ME-VOZ.txt", sob, "estável alterado precisa aparecer como sobrescrito")
        self.assertNotIn("engines/", sob)
        self.assertIn("# ROLLBACK ", man)
        self.assertTrue(os.path.isfile(os.path.join(d, "UPLOAD-2-POR-ULTIMO", "index.html")))
        self.assertEqual(open(os.path.join(d, "UPLOAD", "voice", "LEIA-ME-VOZ.txt")).read(), "voz versao A\n")
        self.assertTrue(os.path.isfile(os.path.join(d, "CONFERIR-SITE-RT.ps1")))

    def test_0b_sem_rollback_nao_monta(self):
        with tempfile.TemporaryDirectory() as t:
            out = entrega(t, "vx", b"X" * 100, "voz\n")
            r = ps(os.path.join(out, "MONTAR-UPLOAD-RT.ps1"))
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("ROLLBACK ainda nao foi gerado", r.stdout)

    # ---------- simulações ----------
    def test_1_publicacao_completa(self):
        self.site_v1(); self.publicar(self.v2)
        r = self.conferir(self.v2)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("TUDO NO AR", r.stdout)
        self.assertIn("fingerprint 6 | URL estavel 9", r.stdout)
        self.assertNotEqual(self.conferir(self.rollback_dir()).returncode, 0, "site novo não confere com o rollback")

    def test_2_upload_interrompido(self):
        self.site_v1()
        copiar(os.path.join(self.v2, "UPLOAD"), self.site)
        os.remove(os.path.join(self.site, named(self.v2, "index-p", ".pck")))   # parou antes do pacote
        os.remove(os.path.join(self.site, "voice", "LEIA-ME-VOZ.txt"))
        r = self.conferir(self.v2)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("TUDO NO AR", r.stdout)
        self.assertIn("FALTANDO NO SITE", r.stdout)

    def test_3_index_novo_com_assets_antigos(self):
        self.site_v1(); self.publicar(self.v2, assets=False)
        r = self.conferir(self.v2)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("TUDO NO AR", r.stdout)
        self.assertIn("FALTANDO NO SITE  " + named(self.v2, "index-p", ".pck"), r.stdout)

    def test_4_assets_novos_com_index_antigo(self):
        self.site_v1(); self.publicar(self.v2, index=False)
        r = self.conferir(self.v2)
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("TUDO NO AR", r.stdout)
        self.assertIn("SHA-256 DIFERENTE  index.html", r.stdout)
        self.assertIn("INDEX CITA ARQUIVO FORA DA ENTREGA", r.stdout)

    def test_5_arquivo_estavel_alterado(self):
        self.site_v1(); self.publicar(self.v2)
        open(os.path.join(self.site, "voice", "LEIA-ME-VOZ.txt"), "w").write("voz versao A\n")   # mesmo tamanho
        r = self.conferir(self.v2)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("SHA-256 DIFERENTE  voice/LEIA-ME-VOZ.txt  (MESMO tamanho", r.stdout)

    def test_6_arquivo_publico_incorreto(self):
        self.site_v1(); self.publicar(self.v2)
        p = os.path.join(self.site, named(self.v2, "index-p", ".pck"))
        b = bytearray(open(p, "rb").read()); b[10] ^= 0xFF
        open(p, "wb").write(bytes(b))                                    # corrompido, mesmo tamanho
        r = self.conferir(self.v2)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("SHA-256 DIFERENTE  " + named(self.v2, "index-p", ".pck"), r.stdout)

    def test_7_rollback_completo(self):
        self.site_v1(); self.publicar(self.v2)
        d = self.rollback_dir()
        self.publicar(d)                                                 # UPLOAD do rollback, depois o index.html
        r = self.conferir(d)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("TUDO NO AR", r.stdout)
        self.assertNotEqual(self.conferir(self.v2).returncode, 0)

    def test_8_rollback_so_com_index_nao_basta(self):
        self.site_v1(); self.publicar(self.v2)
        d = self.rollback_dir()
        shutil.copyfile(os.path.join(d, "UPLOAD-2-POR-ULTIMO", "index.html"), os.path.join(self.site, "index.html"))
        r = self.conferir(d)
        self.assertNotEqual(r.returncode, 0, "rollback só do index.html deixa o estável da versão nova")
        self.assertIn("SHA-256 DIFERENTE  voice/LEIA-ME-VOZ.txt", r.stdout)

    def test_9_site_inacessivel(self):
        r = ps(os.path.join(self.v2, "CONFERIR-SITE-RT.ps1"), "-Site", "http://127.0.0.1:9", "-TimeoutSec", "5")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("TUDO NO AR", r.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
