# R152 · laterais extras da Home (celular deitado bem largo): folhagem pixel art emendada nas bordas da arte larga
import numpy as np
from PIL import Image
W=np.asarray(Image.open('ui_v022/assets/home_forest_v9_wide.png').convert('RGB')).astype(float)
F=np.asarray(Image.open('ui_v022/assets/home_side_foliage.png').convert('RGB')).astype(float)
H=W.shape[0]; EXT=360; OV=90
def side_strip(left):
    # pedaço da folhagem do lado certo (folhas grandes perto da borda de fora)
    s=F[:, :EXT+OV] if left else F[:, -(EXT+OV):]
    # casa cor/brilho com a borda da arte
    edge=W[:, :OV] if left else W[:, -OV:]
    fe=s[:, -OV:] if left else s[:, :OV]
    k=(edge.reshape(-1,3).mean(0)+1)/(fe.reshape(-1,3).mean(0)+1)
    s=np.clip(s*k*0.97,0,255)
    return s
L=side_strip(True); R=side_strip(False)
out=np.zeros((H, W.shape[1]+2*EXT, 3))
out[:, EXT:EXT+W.shape[1]]=W
out[:, :EXT]=L[:, :EXT]
out[:, -EXT:]=R[:, -EXT:]
# emenda suave (OV px dentro da arte)
t=np.linspace(0,1,OV)[None,:,None]
a=W[:, :OV]; b=L[:, EXT:EXT+OV]
out[:, EXT:EXT+OV]=b*(1-t)+a*t
a=W[:, -OV:]; b=R[:, :OV]
out[:, EXT+W.shape[1]-OV:EXT+W.shape[1]]=a*(1-t)+b*t
# um pouco mais escuro para fora (foco no meio), sem preto
g=np.ones(out.shape[1]); n=EXT
g[:n]=0.78+0.22*np.linspace(0,1,n)**0.8; g[-n:]=g[:n][::-1]
out=out*g[None,:,None]
Image.fromarray(out.clip(0,255).astype(np.uint8)).save('/tmp/claude-0/r152/xwide.png')
im=Image.fromarray(out.clip(0,255).astype(np.uint8)); im.thumbnail((1400,1400)); im.save('/tmp/claude-0/r152/xwide_prev.png')

o=out.clip(0,255).astype(np.uint8)
Image.fromarray(o[:, :EXT+OV]).save('ui_v022/assets/home_forest_v9_side_l.png')
Image.fromarray(o[:, -(EXT+OV):]).save('ui_v022/assets/home_forest_v9_side_r.png')
