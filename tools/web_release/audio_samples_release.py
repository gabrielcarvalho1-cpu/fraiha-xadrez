#!/usr/bin/env python3
"""R99 · Liberação segura das amostras de áudio Web (GodotAudio.samples) — memória em sessão longa.

PROBLEMA (Orca, R94, Chrome, 20 ciclos Home→Bot→XEQUE→Marcha→resultado): no export Web, cada AudioStream
tocado como SAMPLE vira um AudioBuffer PCM (float32, 2 canais) guardado em `GodotAudio.samples`, chaveado
pelo ID do objeto AudioStream. Os efeitos do XEQUE/Marcha são carregados ao entrar no modo e soltos ao sair;
na volta, o `load()` cria OUTRO AudioStream (ID novo) → amostra nova, e a antiga nunca sai do mapa (o motor
não remove a amostra quando o stream é liberado). ~6 amostras / ~7 MiB por ciclo, +143 MiB em 20 ciclos.

CORREÇÃO (duas partes):
  1) este patch no index.js do export acrescenta à classe `GodotAudio.Sample` o método `fraihaRelease(ids)`
     e expõe `globalThis.fraihaGodotAudio` (na 1ª amostra criada). O jogo (audio_v025/game_audio.gd) chama
     `fraihaRelease` com os IDs dos streams de um modo quando o modo fecha;
  2) `fraihaRelease` só libera uma amostra quando NENHUM `SampleNode` ativo usa aquele stream
     (`GodotAudio.sampleNodes[*].streamObjectId`). As que ainda tocam ficam pendentes e são conferidas de novo
     a cada 0,5 s até terminarem — o som nunca é cortado.

POR QUE É SEGURO: o motor decide se precisa registrar a amostra perguntando ao próprio mapa
(`godot_audio_sample_stream_is_registered` = `GodotAudio.samples.get(id) != null`) antes de tocar. Uma amostra
liberada de um stream que ainda existe é registrada de novo no próximo play (custo: uma cópia do PCM, só
nesse play). Comprovado no teste Web (tests/web_audio/): tocar → liberar → tocar de novo funciona.

COMO FICA PERMANENTE: o `pack_web_release.py` chama `garantir()` antes dos nomes com SHA-256; trechos trocados
por correspondência EXATA (uma vez cada). Se o runtime do Godot mudar, o empacotamento PARA (fail-closed).

Uso manual: python3 tools/web_release/audio_samples_release.py <export_dir>   (idempotente)
"""
import hashlib, os, sys

MARCA = "fraihaRelease(ids){"

CREATE_ORIG = ("static create(params,options={}){const sample=new GodotAudio.Sample(params,options);"
               "GodotAudio.samples.set(params.id,sample);return sample}")

RELEASE = (
    "static fraihaRelease(ids){const G=GodotAudio;if(G.samples==null)return{released:0,pending:0,samples:0,nodes:0};"
    "const pend=G.fraihaPending||(G.fraihaPending=new Set());for(const id of ids||[])pend.add(String(id));"
    # streams com reprodução ativa (SampleNode vivo) não podem perder a amostra
    "const busy=new Set();if(G.sampleNodes!=null){for(const n of G.sampleNodes.values()){busy.add(String(n.streamObjectId))}}"
    "let released=0,bytes=0;for(const id of [...pend]){const s=G.samples.get(id);if(s==null){pend.delete(id);continue}"
    "if(busy.has(id))continue;const b=s._audioBuffer;if(b!=null)bytes+=b.length*b.numberOfChannels*4;"
    "s.clear();pend.delete(id);released++}"
    "if(pend.size>0&&G.fraihaTimer==null){G.fraihaTimer=setTimeout(()=>{G.fraihaTimer=null;G.Sample.fraihaRelease([])},500)}"
    "G.fraihaReleased=(G.fraihaReleased||0)+released;G.fraihaReleasedBytes=(G.fraihaReleasedBytes||0)+bytes;"
    "return{released:released,bytes:bytes,pending:pend.size,samples:G.samples.size,nodes:G.sampleNodes!=null?G.sampleNodes.size:0}}"
    "static fraihaStats(){const G=GodotAudio;let bytes=0;if(G.samples!=null){for(const s of G.samples.values()){const b=s._audioBuffer;"
    "if(b!=null)bytes+=b.length*b.numberOfChannels*4}}return{samples:G.samples!=null?G.samples.size:0,bytes:bytes,"
    "nodes:G.sampleNodes!=null?G.sampleNodes.size:0,pending:G.fraihaPending?G.fraihaPending.size:0,"
    "released:G.fraihaReleased||0,releasedBytes:G.fraihaReleasedBytes||0}}"
)

CREATE_NOVO = (RELEASE +
               "static create(params,options={}){globalThis.fraihaGodotAudio=GodotAudio;"
               "const sample=new GodotAudio.Sample(params,options);GodotAudio.samples.set(params.id,sample);return sample}")

# partes do runtime das quais a correção depende (conferidas antes de aplicar)
DEPENDE = [
    "streamObjectId=params.streamObjectId;",
    "clear(){this.setAudioBuffer(null);GodotAudio.Sample.delete(this.id)}",
    "return Number(GodotAudio.Sample.getSampleOrNull(streamObjectId)!=null)",
    "sampleNodes:null,SampleNode:class SampleNode{",
]


class Erro(Exception):
    pass


def _sha(b):
    return hashlib.sha256(b).hexdigest()


def aplicar(js):
    if js.count(CREATE_ORIG) != 1:
        raise Erro("trecho Sample.create encontrado %d vezes (esperado 1)" % js.count(CREATE_ORIG))
    for d in DEPENDE:
        if js.count(d) != 1:
            raise Erro("dependência do runtime ausente/duplicada: %r" % d[:60])
    return js.replace(CREATE_ORIG, CREATE_NOVO)


def ja_aplicado(js):
    return js.count(MARCA) == 1 and js.count("globalThis.fraihaGodotAudio=GodotAudio;") == 1 and CREATE_ORIG not in js


def garantir(export_dir):
    """Aplica no <export_dir>/index.js (uma vez). Fail-closed."""
    path = os.path.join(export_dir, "index.js")
    with open(path, "rb") as f:
        raw = f.read()
    js = raw.decode("utf-8")
    if MARCA in js:
        if not ja_aplicado(js):
            raise SystemExit("ERRO ÁUDIO: index.js com a marca da correção mas incompleto — refaça o export")
        return {"estado": "ja_aplicada", "sha_antes": None, "sha_depois": _sha(raw)}
    try:
        novo = aplicar(js)
    except Erro as e:
        raise SystemExit("ERRO ÁUDIO: %s. O runtime Web mudou (versão do Godot?): revise tools/web_release/audio_samples_release.py antes de publicar." % e)
    if not ja_aplicado(novo):
        raise SystemExit("ERRO ÁUDIO: verificação pós-correção falhou")
    data = novo.encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)
    return {"estado": "aplicada", "sha_antes": _sha(raw), "sha_depois": _sha(data)}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    r = garantir(sys.argv[1])
    print("OK: liberação de amostras de áudio %s · index.js %s" % (r["estado"], r["sha_depois"]))
