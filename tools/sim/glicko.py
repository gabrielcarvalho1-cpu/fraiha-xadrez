import numpy as np, math
q=math.log(10)/400
def g(rd): return 1/math.sqrt(1+3*q*q*rd*rd/math.pi**2)
def E(r,rj,rdj): return 1/(1+10**(-g(rdj)*(r-rj)/400))
def update(r,rd,rj,rdj,s):
    e=E(r,rj,rdj); gg=g(rdj)
    d2=1/(q*q*gg*gg*e*(1-e))
    nrd=math.sqrt(1/(1/rd**2+1/d2))
    nr=r+q/(1/rd**2+1/d2)*gg*(s-e)
    return nr,max(nrd,45.0)
def pw(a,b): return 1/(1+10**((b-a)/400))
