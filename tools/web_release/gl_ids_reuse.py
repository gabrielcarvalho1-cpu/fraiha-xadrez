#!/usr/bin/env python3
"""R94 · Reaproveitamento dos IDs WebGL no runtime Web do Godot (Emscripten) — memória em sessão longa.

PROBLEMA (medido pelo Orca na R93, 20 ciclos Marcha/XEQUE): o runtime Emscripten do export Web dá a cada
objeto WebGL um ID novo de um contador GLOBAL que só cresce (`GL.getNewId`: ret=GL.counter++) e, ao
apagar, só deixa `GL.<tabela>[id]=null`. Pior: cada tabela (textures, buffers, syncs, vaos...) é
preenchida com null até o maior ID. Com poucos objetos vivos (~100 syncs, ~130 texturas), as tabelas
passaram de 1,5 milhão de posições: ~30 MiB de heap JS a mais no ciclo 20, crescendo sem parar.
No iPhone (limite de memória por aba bem menor) isso é candidato forte aos reloads de sessão longa.

CORREÇÃO: IDs apagados voltam para uma pilha global e são reaproveitados — o que o OpenGL nativo já faz
(o Godot é escrito para glGen* reaproveitar nomes). Proteções:
  - pilha GLOBAL (não por tabela): um ID só fica vivo em UMA tabela por vez, como no contador original;
  - `idInUse` confere TODAS as tabelas antes de devolver um ID à pilha e antes de reaproveitá-lo
    (se algo estiver vivo com aquele ID, ele é ignorado e sai um ID novo do contador — nunca colide);
  - `freeIdSet` impede devolver o mesmo ID duas vezes;
  - ID 0 nunca entra; contexts nunca são liberados (não entram na pilha);
  - perda de contexto WebGL: a recuperação do FRAIHA recarrega a página, então a pilha nasce vazia.

COMO FICA PERMANENTE: o `pack_web_release.py` chama `garantir()` no index.js do export ANTES de calcular
os nomes com SHA-256. Sem a correção aplicável, o empacotamento PARA (fail-closed): um export novo não
sai sem ela por esquecimento. Os trechos são trocados por correspondência EXATA (cada um deve aparecer
uma única vez); se uma versão nova do Godot/Emscripten mudar esse código, a build para e a correção
precisa ser revista (não é aplicada às cegas).

Uso manual: python3 tools/web_release/gl_ids_reuse.py <export_dir>   (idempotente)
"""
import hashlib, os, sys

MARCA = "fraihaGlIdReuse:1,"

TABELAS = ["buffers", "framebuffers", "programs", "queries", "renderbuffers", "shaders", "syncs", "textures"]

GETNEWID_ORIG = "getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret},"

# Todas as tabelas de objetos do runtime (as ausentes são ignoradas pelo `T[k]&&`).
_TODAS = "[GL.buffers,GL.framebuffers,GL.programs,GL.queries,GL.renderbuffers,GL.shaders,GL.syncs,GL.textures,GL.vaos,GL.samplers,GL.transformFeedbacks,GL.contexts]"

GETNEWID_NOVO = (
    MARCA +
    "freeIds:[],freeIdSet:new Set,"
    "idInUse:id=>{var T=" + _TODAS + ";for(var k=0;k<T.length;k++){if(T[k]&&T[k][id])return true}return false},"
    "releaseId:id=>{if(!id||GL.freeIdSet.has(id)||GL.idInUse(id))return;GL.freeIdSet.add(id);GL.freeIds.push(id)},"
    "getNewId:table=>{var ret=0;while(GL.freeIds.length){var c=GL.freeIds.pop();GL.freeIdSet.delete(c);"
    "if(!GL.idInUse(c)){ret=c;break}}if(!ret)ret=GL.counter++;"
    "for(var i=table.length;i<ret;i++){table[i]=null}return ret},"
)

VAO_ORIG = "GLctx.deleteVertexArray(GL.vaos[id]);GL.vaos[id]=null}"
VAO_NOVO = "var vao=GL.vaos[id];GLctx.deleteVertexArray(vao);GL.vaos[id]=null;if(vao)GL.releaseId(id)}"


def _trocas():
    t = [(GETNEWID_ORIG, GETNEWID_NOVO)]
    for nome in TABELAS:
        t.append(("GL.%s[id]=null" % nome, "GL.%s[id]=null;GL.releaseId(id)" % nome))
    t.append((VAO_ORIG, VAO_NOVO))
    return t


class Erro(Exception):
    pass


def aplicar(js):
    """Devolve o JS corrigido. Levanta Erro se algum trecho não aparecer EXATAMENTE uma vez."""
    if MARCA in js:
        raise Erro("o index.js já tem a correção")
    for velho, novo in _trocas():
        n = js.count(velho)
        if n != 1:
            raise Erro("trecho do runtime encontrado %d vezes (esperado 1): %s" % (n, velho[:70]))
        js = js.replace(velho, novo, 1)
    return js


def ja_aplicado(js):
    """True se o JS tem a correção completa (cada trecho novo exatamente uma vez, nenhum antigo)."""
    if js.count(MARCA) != 1:
        return False
    for velho, novo in _trocas():
        if js.count(novo) != 1:
            return False
    return js.count(GETNEWID_ORIG) == 0 and js.count(VAO_ORIG) == 0


def _sha(b):
    return hashlib.sha256(b).hexdigest().upper()


def garantir(export_dir):
    """Aplica a correção no <export_dir>/index.js (uma vez). Devolve dict com SHA antes/depois. Fail-closed."""
    path = os.path.join(export_dir, "index.js")
    with open(path, "rb") as f:
        raw = f.read()
    js = raw.decode("utf-8")
    if MARCA in js:
        if not ja_aplicado(js):
            raise SystemExit("ERRO GL IDs: index.js com a marca da correção mas incompleto — refaça o export")
        return {"estado": "ja_aplicada", "sha_antes": None, "sha_depois": _sha(raw)}
    try:
        novo = aplicar(js)
    except Erro as e:
        raise SystemExit("ERRO GL IDs: %s. O runtime Web mudou (versão do Godot?): revise tools/web_release/gl_ids_reuse.py antes de publicar." % e)
    if not ja_aplicado(novo):
        raise SystemExit("ERRO GL IDs: verificação pós-correção falhou")
    data = novo.encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)
    return {"estado": "aplicada", "sha_antes": _sha(raw), "sha_depois": _sha(data)}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    r = garantir(sys.argv[1])
    print("OK: correção GL IDs %s · index.js %s" % (r["estado"], r["sha_depois"]))
