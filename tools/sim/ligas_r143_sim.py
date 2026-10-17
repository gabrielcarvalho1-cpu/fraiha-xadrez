import numpy as np, math, copy, json, sys
from glicko import update, pw
L=['Madeira','Ferro','Bronze','Prata','Ouro','Platina','Esmeralda','Diamante','Mestre','Grão-Mestre','Challenger']
TOP=10; DEMOTE=75
BASE=[(20,8),(18,9),(17,10),(16,11),(15,12),(14,12),(13,13),(11,11),(8,8),(6,6),(6,6)]
CH_N=int(sys.argv[1]) if len(sys.argv)>1 else 40
SCALE=float(sys.argv[2]) if len(sys.argv)>2 else 1.15
def exp_f(R): return 750+R*SCALE      # posição visível → Força esperada
def points(f,R,league,out,fo):
    bw,bl=BASE[league]
    d=f-exp_f(R)
    cap=1.8 if league<=5 else 1.25          # da Esmeralda para cima o bônus por ser 'melhor que a liga' é pequeno
    m=float(np.clip(1+d/350,0.5,cap)); n=float(np.clip(1-d/350,0.5,1.8))
    w=bw*m; l=bl*n
    if out=='win': return int(round(w))
    if out=='loss': return -int(round(l))
    e=pw(f,fo); return int(round((0.5-e)*(w+l)))
class S:
    def __init__(s,N,seed):
        s.rng=np.random.default_rng(seed)
        s.skill=np.clip(s.rng.normal(1150,350,N),300,2900)
        s.f=np.full(N,1200.0); s.rd=np.full(N,350.0)
        s.lg=np.zeros(N,int); s.pl=np.zeros(N,int); s.games=np.zeros(N,int)
        s.act=s.rng.choice([1,2,4,8],N,p=[.4,.3,.2,.1]); s.reach={}
    def add(s,skill,act):
        k=len(skill)
        s.skill=np.append(s.skill,skill); s.f=np.append(s.f,[1200.]*k); s.rd=np.append(s.rd,[350.]*k)
        s.lg=np.append(s.lg,[0]*k); s.pl=np.append(s.pl,[0]*k); s.games=np.append(s.games,[0]*k); s.act=np.append(s.act,[act]*k)
        return list(range(len(s.skill)-k,len(s.skill)))
    def apply(s,i,j,o):
        R=s.lg[i]*100+s.pl[i]; ch=points(s.f[i],R,s.lg[i],o,s.f[j])
        lg,pl=s.lg[i],s.pl[i]+ch
        if o=='loss' and s.pl[i]==0 and 0<lg<TOP: lg-=1; pl=DEMOTE
        pl=max(pl,0)
        while pl>=100 and lg<TOP-1: pl-=100; lg+=1
        if lg==TOP-1: pl=min(pl,100)        # Grão-Mestre trava em 100 PL: Challenger só pelo ranking
        if lg==TOP: pl=min(pl,999)
        s.lg[i],s.pl[i]=lg,pl
    def day(s):
        for r in range(int(s.act.max())):
            a=np.where(s.act>r)[0]
            key=s.f[a]+s.rng.normal(0,50,len(a)); o=a[np.argsort(key)]
            for t in range(0,len(o)-1,2):
                i,j=o[t],o[t+1]
                p=pw(s.skill[i],s.skill[j]); dr=0.08*(1-abs(p-.5)*1.6); u=s.rng.random()
                if u<dr: oi,oj,sc='draw','draw',.5
                elif u<dr+(1-dr)*p: oi,oj,sc='win','loss',1.
                else: oi,oj,sc='loss','win',0.
                fi,rdi,fj,rdj=s.f[i],s.rd[i],s.f[j],s.rd[j]
                s.apply(i,j,oi); s.apply(j,i,oj)
                s.f[i],s.rd[i]=update(fi,rdi,fj,rdj,sc); s.f[j],s.rd[j]=update(fj,rdj,fi,rdi,1-sc)
                s.games[i]+=1; s.games[j]+=1
                for x in (i,j):
                    if x in s.reach:
                        for l in range(s.lg[x]+1): s.reach[x].setdefault(l,int(s.games[x]))
            s.ranking()
    def ranking(s):
        # Challenger = os CH_N melhores entre quem completou o Grão-Mestre (100 PL) ou já é Challenger
        cand=np.where((s.lg==TOP)|((s.lg==TOP-1)&(s.pl>=100)))[0]
        if len(cand)==0: return
        score=np.where(s.lg[cand]==TOP,1000+s.pl[cand],100)+s.f[cand]/10000
        order=cand[np.argsort(-score)]
        top=order[:CH_N]; rest=order[CH_N:]
        newc=top[s.lg[top]!=TOP]; s.lg[newc]=TOP; s.pl[newc]=0
        out=rest[s.lg[rest]==TOP]; s.lg[out]=TOP-1; s.pl[out]=100
def dist(s): return (100*np.bincount(s.lg,minlength=11)/len(s.lg)).round(1).tolist()
s=S(4000,7); snaps={}; chcount={}
TYPES={'Profissional (nível ~2600)':2600,'Muito forte (~2000)':2000,'Bom (~1600)':1600,'Médio (~1150)':1150,'Fraco (~800)':800}
ids={}
for d in range(1,366):
    if d==1:
        for n,v in TYPES.items(): ids[n]=s.add([v]*1,6)   # 1 de cada tipo desde o lançamento, 6 partidas/dia
        for n in ids:
            for x in ids[n]: s.reach[x]={0:0}
    s.day()
    if d in (30,60,90,180,270,365): snaps[d]=dist(s); chcount[d]=int((s.lg==TOP).sum())
for d,v in snaps.items(): print(d,'Ch=',chcount[d],' '.join(f'{L[i][:4]}:{x}' for i,x in enumerate(v)))
res={}
for n,ix in ids.items():
    x=ix[0]; r=s.reach[x]
    res[n]={L[l]:r[l] for l in r}
    print(n,'| fim:',L[s.lg[x]],s.pl[x],'| partidas até:',{L[l][:5]:r[l] for l in sorted(r)})
json.dump({'snaps':snaps,'ch':chcount,'types':res},open(f'res2_{CH_N}_{SCALE}.json','w'),ensure_ascii=False)
