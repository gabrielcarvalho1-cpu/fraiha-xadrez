// FRAIHA R55.5 · R2 falso (pasta local) com a mesma interface que o Worker usa: get(onlyIf/range), head,
// httpEtag, uploaded, writeHttpMetadata. Usado pelo simulador e pelo teste do Worker.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { Readable } from "node:stream";

const etagCache = new Map();

function etagOf(file, st) {
  const k = file + ":" + st.size + ":" + st.mtimeMs;
  if (!etagCache.has(k)) etagCache.set(k, crypto.createHash("md5").update(fs.readFileSync(file)).digest("hex"));
  return etagCache.get(k);
}

// R2 falso: mesma interface usada pelo Worker (get com onlyIf/range, head, httpEtag, writeHttpMetadata)
export class FakeR2 {
  constructor(dir) { this.dir = dir; }
  _stat(key) {
    const file = path.join(this.dir, ...key.split("/"));
    if (!file.startsWith(path.resolve(this.dir))) return null;
    let st; try { st = fs.statSync(file); } catch { return null; }
    if (!st.isFile()) return null;
    const etag = etagOf(file, st);
    return { file, size: st.size, etag, httpEtag: `"${etag}"`, uploaded: new Date(Math.floor(st.mtimeMs / 1000) * 1000), writeHttpMetadata() {} };
  }
  async head(key) { return this._stat(key); }
  async get(key, opts = {}) {
    const o = this._stat(key);
    if (!o) return null;
    const h = opts.onlyIf;
    if (h) {
      const inm = h.get("if-none-match");
      if (inm && inm.split(",").map((s) => s.trim().replace(/^W\//, "").replace(/"/g, "")).some((t) => t === "*" || t === o.etag)) return o;
      const ims = h.get("if-modified-since");
      if (!inm && ims && o.uploaded <= new Date(ims)) return o;
      const im = h.get("if-match");
      if (im && !im.split(",").map((s) => s.trim().replace(/"/g, "")).some((t) => t === "*" || t === o.etag)) return o;
    }
    let start = 0, end = o.size - 1;
    const rh = opts.range && opts.range.get("range");
    if (rh) {
      const m = /^bytes=(\d*)-(\d*)$/.exec(rh.trim());
      if (m) {
        if (m[1] === "") { const n = Number(m[2]); start = Math.max(0, o.size - n); o.range = { suffix: n }; }
        else { start = Number(m[1]); end = m[2] === "" ? o.size - 1 : Math.min(Number(m[2]), o.size - 1); o.range = { offset: start, length: end - start + 1 }; }
      }
    }
    o.body = Readable.toWeb(fs.createReadStream(o.file, { start, end }));
    return o;
  }
}
