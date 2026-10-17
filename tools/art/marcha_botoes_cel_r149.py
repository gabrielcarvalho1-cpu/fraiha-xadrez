import numpy as np,cv2
from PIL import Image
S=np.asarray(Image.open('/home/claude/fx-web-r53/marcha/art/r57/salao.png').convert('RGBA'))
x0,y0,x1,y1=440,575,1055,810
C=S[y0:y1,x0:x1].copy()
hv=cv2.cvtColor(np.ascontiguousarray(C[...,:3]),cv2.COLOR_RGB2HSV)
gold=((hv[...,0]>=8)&(hv[...,0]<=35)&(hv[...,2]>95)).astype(np.uint8)
gold=cv2.morphologyEx(gold,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
free=(1-gold).astype(np.uint8)
h,w=free.shape
n,lab=cv2.connectedComponents(free,connectivity=4)
border=set(np.unique(np.concatenate([lab[0],lab[-1],lab[:,0],lab[:,-1]])))-{0}
# componentes de fundo = tocam a borda E não são o miolo de uma placa
bg=np.isin(lab,list(border))
for c in border:
    m=lab==c
    if m.sum()>2000 and m[h//2-20:h//2+20, :].any() and False: pass
fg=(~bg).astype(np.uint8)
n2,l2,st2,_=cv2.connectedComponentsWithStats(fg,connectivity=8)
big=np.zeros_like(fg)
for i in range(1,n2):
    if st2[i,4]>3000: big[l2==i]=1
keep=cv2.dilate(big,np.ones((5,5),np.uint8))
_unused=((~bg).astype(np.uint8),np.ones((5,5),np.uint8))
a=cv2.GaussianBlur(keep.astype(np.float32),(3,3),0)
a[:,611:]=0; a[0:92,320:329]=0
C[...,3]=(np.minimum(C[...,3]/255.0,a)*255).astype(np.uint8)
Image.fromarray(C).save('/tmp/claude-0/r149/salao_botoes_cel.png')
v=Image.new('RGBA',(w,h),(60,60,200,255)); v.alpha_composite(Image.fromarray(C)); v.resize((w*2,h*2)).save('/tmp/claude-0/r149/prev.png')
print(bg.mean())
