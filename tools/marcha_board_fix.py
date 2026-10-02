# Reenquadra as 4 placas do Pátio do tabuleiro enviado (sem redesenhar):
# reconstrói a ponta escondida pela trilha (espelho da própria placa), tira a placa do lugar
# e a assenta inteira, afastada da trilha. Resto da arte intacto.
import numpy as np, cv2
from PIL import Image
SRC='/tmp/claude-0/mr/tabuleiro_vazio.png'
W=1600
CX,CY=298.7,513.9      # centro da placa vermelha (referência)
S,R=113.0,44.0         # meia-largura (eixos girados 45°) e raio do canto
SHIFT=(0,-44)          # sobe a placa para longe da fileira da trilha
cells=[(670,1484)]+[(670,y) for y in (1419,1354,1289,1224,1159)]+[(624,1113),(578,1067),(532,1021),(486,975)]+[(x,929) for x in (440,375,310,245,180,115)]+[(115,864),(115,799),(115,734)]
# trilha completa por simetria de rotação
def rot(p,k):
    x,y=p
    for _ in range(k): x,y=(W-1-y),x   # 90° horário
    return (x,y)
track=[rot(p,k) for k in range(4) for p in cells]
def rounded_mask(h,w,cx,cy,s=S,r=R,pad=0.0):
    yy,xx=np.mgrid[0:h,0:w].astype(float)
    dx=xx-cx; dy=yy-cy
    u=np.abs((dx+dy)/np.sqrt(2)); v=np.abs((dx-dy)/np.sqrt(2))
    s=s+pad
    qx=np.maximum(u-(s-r),0); qy=np.maximum(v-(s-r),0)
    d=np.sqrt(qx*qx+qy*qy)-r+np.minimum(np.maximum(u-(s-r),v-(s-r)),0)
    return np.clip(0.5-d,0,1)    # alfa com 1 px de suavização
def track_mask(width):
    m=np.zeros((W,W),np.uint8)
    pts=track+[track[0]]
    for a,b in zip(pts,pts[1:]):
        cv2.line(m,(int(a[0]),int(a[1])),(int(b[0]),int(b[1])),255,width)
    return m>0
TM=track_mask(84)      # onde a placa estava escondida (para reconstruir)
KEEP=track_mask(76)    # o canal visível da trilha (nunca muda)
def process(img):
    a=img.astype(np.float32)
    h,w,_=a.shape
    full=rounded_mask(h,w,CX,CY)
    # 1) reconstrói a placa: pixels cobertos pela trilha vêm do espelho vertical da própria placa
    plaque=a.copy()
    yy=np.arange(h)[:,None]*np.ones((1,w))
    covered=(full>0)&(TM|(yy>CY+92))      # a ponta inferior inteira vem do espelho da ponta superior
    ys,xs=np.nonzero(covered)
    my=np.clip(np.round(2*CY-ys).astype(int),0,h-1)
    plaque[ys,xs]=a[my,xs]
    # 2) apaga a placa antiga (fora da trilha) e preenche a laje
    old=((full>0)&~KEEP).astype(np.uint8)
    old=cv2.dilate(old,np.ones((7,7),np.uint8))&(~KEEP).astype(np.uint8)
    # cor da laje por convolução normalizada (sem puxar o canal escuro nem restos da placa)
    valid=((old==0)&~TM&(full==0)).astype(np.float32)
    num=cv2.GaussianBlur(a*valid[...,None],(0,0),18)
    den=cv2.GaussianBlur(valid,(0,0),18)[...,None]+1e-4
    base=np.where(old[...,None]>0,num/den,a)
    # textura da laje: ruído fino de uma área limpa próxima, repetido
    patch=a[150:300,130:280]
    noise=patch-cv2.GaussianBlur(patch,(0,0),6)
    tile=np.tile(noise,(h//150+1,w//150+1,1))[:h,:w]
    base=np.where(old[...,None]>0,base+tile,base)
    # 3) assenta a placa inteira deslocada
    M=np.float32([[1,0,SHIFT[0]],[0,1,SHIFT[1]]])
    moved=cv2.warpAffine(plaque,M,(w,h),flags=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
    alpha=rounded_mask(h,w,CX+SHIFT[0],CY+SHIFT[1],pad=0.5)[...,None]
    # sombra suave sob a placa (como a original sobre a laje)
    sh=rounded_mask(h,w,CX+SHIFT[0]+2,CY+SHIFT[1]+4,pad=3)[...,None]
    sh=cv2.GaussianBlur(sh[...,0],(0,0),3)[...,None]*0.45
    base=base*(1-sh)
    out=base*(1-alpha)+moved*alpha
    # a trilha continua por cima de tudo (nunca muda)
    out=np.where(KEEP[...,None],a,out)
    return np.clip(out,0,255).astype(np.uint8)
img=np.array(Image.open(SRC).convert('RGB'))
for k in range(4):
    # gira para trazer a placa k à posição da vermelha, processa, desfaz o giro (sem perda)
    r=np.rot90(img,k)          # anti-horário k vezes
    r=process(np.ascontiguousarray(r))
    img=np.rot90(r,-k)
Image.fromarray(np.ascontiguousarray(img)).save('/home/claude/fx/marcha/art/board.png')
print('ok')

# cantos fora da moldura arredondada ficam transparentes (a mesa verde aparece, como na tela de referência)
from PIL import ImageDraw
_im = Image.open('/home/claude/fx/marcha/art/board.png').convert('RGBA')
_m = Image.new('L', _im.size, 0)
ImageDraw.Draw(_m).rounded_rectangle([10, 10, 1589, 1589], radius=52, fill=255)
_a = np.array(_im); _a[..., 3] = np.minimum(_a[..., 3], np.array(_m))
Image.fromarray(_a).save('/home/claude/fx/marcha/art/board.png')
