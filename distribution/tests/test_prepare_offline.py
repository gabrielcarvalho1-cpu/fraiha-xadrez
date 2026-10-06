"""Auditoria R46 · prepare-real-exports.ps1 respeita o CONTRATO OFFLINE DEV do online.cfg.
Contrato: o online.cfg dos exports DEV é exatamente "[online]\\nserver_url=\\"\\"\\n" (UTF-8 sem BOM);
um online.cfg pré-existente com outro conteúdo (ex.: endpoint) é RECUSADO (exit != 0), não é sobrescrito
e nada novo é fixado nos pins. Roda o script de verdade (pwsh) numa CÓPIA temporária (não toca em .local).
Rodar: PWSH=/caminho/pwsh python3 distribution/tests/test_prepare_offline.py"""
import hashlib, os, shutil, subprocess, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "prepare-real-exports.ps1")
PWSH = os.environ.get("PWSH") or shutil.which("pwsh") or shutil.which("powershell")
OFFLINE = b'[online]\nserver_url=""\n'
OFFLINE_SHA = "ffaee9060a72096d914fc15346a3021d316c2ace6e9f36b780c956c7d325606e"
ONLINE = b'[online]\nserver_url="wss://fraiha-xadrez.onrender.com"\n'


def sha(b):
    return hashlib.sha256(b).hexdigest()


@unittest.skipUnless(PWSH, "pwsh/powershell não encontrado: testes PULADOS")
class PrepareOffline(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.t, True)
        self.task = os.path.join(self.t, "distribution")
        os.makedirs(self.task)
        shutil.copy(SCRIPT, self.task)
        self.src = {}
        for x, pck in (("A", b"PCK-A"), ("B", b"PCK-B")):
            d = os.path.join(self.t, "exp" + x)
            os.makedirs(d)
            open(os.path.join(d, "FRAIHA.exe"), "wb").write(b"EXE")
            open(os.path.join(d, "FRAIHA.pck"), "wb").write(pck)
            self.src[x] = d
        self.pins = os.path.join(self.task, ".local", "bin", "dev-reviewed-exports.txt")

    def run_prepare(self):
        return subprocess.run([PWSH, "-NoProfile", "-File", os.path.join(self.task, "prepare-real-exports.ps1"),
                               "-ExportA", self.src["A"], "-ExportB", self.src["B"]], capture_output=True, text=True, timeout=120)

    def cfg(self, x):
        return os.path.join(self.task, ".local", "real-%s-dev-export" % x, "online.cfg")

    def test_G_preparacao_valida_sai_0_e_fixa_so_o_perfil_offline(self):
        r = self.run_prepare()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        for x in "AB":
            self.assertEqual(open(self.cfg(x), "rb").read(), OFFLINE)
        cfg_pins = [l.split()[1] for l in open(self.pins).read().splitlines() if l.startswith("cfg ")]
        self.assertEqual(cfg_pins, [OFFLINE_SHA])
        self.assertEqual(sha(OFFLINE), OFFLINE_SHA)
        r2 = self.run_prepare()   # idempotente: rodar de novo com o perfil offline já presente continua OK
        self.assertEqual(r2.returncode, 0, r2.stdout + r2.stderr)

    def test_F_online_cfg_com_endpoint_e_recusado_sem_sobrescrever_nem_fixar(self):
        dest = os.path.dirname(self.cfg("B"))
        os.makedirs(dest)
        open(self.cfg("B"), "wb").write(ONLINE)
        r = self.run_prepare()
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertIn("perfil offline", r.stdout + r.stderr)
        self.assertEqual(open(self.cfg("B"), "rb").read(), ONLINE, "não sobrescreve (preserva para investigar)")
        self.assertFalse(os.path.exists(self.pins), "nenhum pin gerado")

    def test_F2_pins_antigos_nao_sao_atualizados_com_cfg_online(self):
        self.assertEqual(self.run_prepare().returncode, 0)
        before = open(self.pins).read()
        open(self.cfg("A"), "wb").write(ONLINE)          # alguém troca o cfg depois
        r = self.run_prepare()
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertEqual(open(self.pins).read(), before, "pins anteriores intactos; cfg online nunca fixado")
        self.assertNotIn(sha(ONLINE), before)

    def test_cfg_vazio_ou_com_bom_tambem_e_recusado(self):
        os.makedirs(os.path.dirname(self.cfg("A")))
        open(self.cfg("A"), "wb").write(b"\xef\xbb\xbf" + OFFLINE)
        self.assertNotEqual(self.run_prepare().returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
