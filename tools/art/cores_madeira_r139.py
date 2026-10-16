# R139 · CORES DO TABULEIRO E DAS PEÇAS sobre a arte da Madeira (a arte não muda, só a cor).
# Casas: a mesma conta roda no jogo em cosmetics/board_colors.gdshader (aqui serve para as prévias).
# Peças: gera cosmetics/cores_pecas/<id>/<arquivo>.png para cada paleta de peças do catálogo (cosmetics/board_colors.gd).
# Uso: python3 tools/art/cores_madeira_r139.py
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import os
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..'))+'/'
casas=np.asarray(Image.open(ROOT+'visual_v018/casas_madeira.png').convert('RGB')).astype(np.float32)/255
def hexc(h): return np.array([int(h[i:i+2],16) for i in (1,3,5)],np.float32)/255
def lum(a): return a[...,0]*0.299+a[...,1]*0.587+a[...,2]*0.114
# estatística de luz de cada tipo de casa (claras = areia, escuras = grama)
cell=80
light_mask=np.zeros((640,640),bool)
for y in range(8):
  for x in range(8):
    if (x+y)%2==0: light_mask[y*cell:(y+1)*cell,x*cell:(x+1)*cell]=True
L=lum(casas)
def stats(m):
  v=L[m]; return np.percentile(v,3),np.percentile(v,50),np.percentile(v,97)
SL=stats(light_mask); SD=stats(~light_mask)
def grad(t, c_lo, c_mid, c_hi):
  t=t[...,None]
  lo=np.clip(t*2,0,1); hi=np.clip(t*2-1,0,1)
  a=c_lo+(c_mid-c_lo)*lo
  return np.where(t<0.5, a, c_mid+(c_hi-c_mid)*hi)
def shade(c, k): return np.clip(c*k,0,1)
BL=0.86; BH=1.06
def board(light, dark, strength=1.0):
  if light is None: return (casas*255).astype(np.uint8)
  out=np.zeros_like(casas)
  for m,S,c in ((light_mask,SL,hexc(light)),(~light_mask,SD,hexc(dark))):
    t=np.clip((L-S[0])/(S[2]-S[0]+1e-6),0,1)
    # mantém o meio no tom escolhido: reescala para que a mediana caia em 0.5
    med=(S[1]-S[0])/(S[2]-S[0]+1e-6)
    t=np.where(t<med, t/med*0.5, 0.5+(t-med)/(1-med)*0.5)
    g=grad(t, shade(c,BL), c, np.clip(c*BH+0.02,0,1))
    out[m]=g[m]
  return (out*255).astype(np.uint8)
FN={'torre':('torre_branca','torre_preta'),'cavalo':('cavalo_branco','cavalo_preto'),'bispo':('bispo_branco','bispo_preto'),'dama':('dama_branca','dama_preta'),'rei':('rei_branco','rei_preto'),'peao':('peao_branco','peao_preto')}
_pc={}
PL=0.42
def piece(name, white, col=None):
  p=np.asarray(Image.open(ROOT+'ranked/pecas/%s.png'%FN[name][0 if white else 1]).convert('RGBA')).astype(np.float32)/255
  if col is None: return Image.fromarray((p*255).astype(np.uint8))
  rgb=p[...,:3]; a=p[...,3]
  l=lum(rgb)
  vis=a>0.5
  lo,hi=np.percentile(l[vis],8),np.percentile(l[vis],99)
  t=np.clip((l-lo)/(hi-lo+1e-6),0,1)
  c=hexc(col)
  g=grad(t, np.clip(c*PL,0,1), c, np.clip(c*0.75+0.27,0,1))
  # contorno bem escuro fica como está; detalhes dourados (amarelo saturado) ficam como estão
  mx=rgb.max(-1); mn=rgb.min(-1); sat=(mx-mn)/(mx+1e-6)
  r,gg,b=rgb[...,0],rgb[...,1],rgb[...,2]
  gold=(sat>0.45)&(r>gg)&(gg>b)&(mx>0.45)
  keep=(l<0.10)|gold
  out=np.where(keep[...,None], rgb, g)
  return Image.fromarray((np.dstack([out,a])*255).astype(np.uint8))
NAMES=['torre','cavalo','bispo','dama','rei','bispo','cavalo','torre']
def full(light=None, dark=None, wcol=None, bcol=None):
  b=Image.fromarray(board(light,dark))
  for i,n in enumerate(NAMES):
    for (nm,w,y) in ((n,False,0),('peao',False,1),('peao',True,6),(n,True,7)):
      p=piece(nm,w,wcol if w else bcol)
      b.paste(p,(i*80+(80-p.width)//2,y*80+(80-p.height)//2),p)
  return b


PIECE_SETS = {   # id: (cor das brancas, cor das pretas) — igual a cosmetics/board_colors.gd
    "branco_preto": ("#f2f2ee", "#2e2e30"),
    "creme_marrom": ("#efe0c4", "#5a3a24"),
    "branco_azul": ("#f2f2ee", "#2c4a7a"),
    "branco_vermelho": ("#f2f2ee", "#7a2a2a"),
    "fundador": ("#f6e7b8", "#1d1a17"),
    "club": ("#f2efe2", "#123a2c"),
}
if __name__ == "__main__":
    out = ROOT + "cosmetics/cores_pecas/"
    for sid, (wc, bc) in PIECE_SETS.items():
        os.makedirs(out + sid, exist_ok=True)
        for name, (fw, fb) in FN.items():
            piece(name, True, wc).save(out + sid + "/" + fw + ".png", optimize=True)
            piece(name, False, bc).save(out + sid + "/" + fb + ".png", optimize=True)
        print(sid)
    print("SL", [round(float(x), 4) for x in SL], "SD", [round(float(x), 4) for x in SD])
