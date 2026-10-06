"""Testes do empacotamento Web (rodar: python3 tools/web_release/test_pack_web_release.py)."""
import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "pack_web_release.py")
INDEX = ["index.html", "index.js", "index.wasm", "index.pck", "index.png", "index.icon.png",
         "index.apple-touch-icon.png", "index.audio.worklet.js", "index.audio.position.worklet.js"]


def fake_tree(base, with_voice=True, big=False):
    exp, web = os.path.join(base, "export"), os.path.join(base, "web")
    os.makedirs(exp); os.makedirs(os.path.join(web, "engines"))
    for n in INDEX:
        with open(os.path.join(exp, n), "wb") as f:
            f.write(os.urandom(19922944 * 2 + 5) if (big and n == "index.pck") else n.encode())
    for n in ["stockfish-19-lite-single.js", "stockfish-19-lite-single.wasm", "COPYING-GPLv3.txt"]:
        open(os.path.join(web, "engines", n), "w").write(n)
    if with_voice:
        os.makedirs(os.path.join(web, "voice"))
        for n in ["AgoraRTC_N-4.24.8.js", "fraiha-voice-bridge-v1.js", "LEIA-ME-VOZ.txt"]:
            open(os.path.join(web, "voice", n), "w").write(n)
    return exp, web


class PackTest(unittest.TestCase):
    def run_pack(self, base, exp, web):
        out = os.path.join(base, "OUT")
        return out, subprocess.run([sys.executable, PACK, exp, web, out, "RTEST", "abc123"], capture_output=True, text=True)

    def test_sem_voice_nao_gera(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, with_voice=False))
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("voice/fraiha-voice-bridge-v1.js", r.stdout + r.stderr)
            self.assertFalse(os.path.exists(out))

    def test_manifesto_lista_voice_e_partes(self):
        with tempfile.TemporaryDirectory() as t:
            out, r = self.run_pack(t, *fake_tree(t, big=True))
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


if __name__ == "__main__":
    unittest.main()
