#!/usr/bin/env python3
"""R52 · Telas do PC como PAINEL/MODAL próprio (padrão aprovado na tela de Ligas, R51d).
As referências novas do dono (tools/ui_ref/*_v2.png) já vêm recortadas: fundo transparente, só moldura e miolo.
Nada do cenário entra. Daqui saem o fundo do painel (sem o que é vivo) e as peças que o jogo reaproveita
(abas, linhas, botões, ícones). O jogo abre o painel centralizado por cima da Home escurecida, com fade.
Uso: python3 tools/ref_pages_v2.py"""
import os, sys
import numpy as np
import cv2
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_pages_build import REF, OUT, lum, flat_fill, cut_icon

def load_rgba(n):
    a = np.array(Image.open(os.path.join(REF, n + '.png')).convert('RGBA')).astype(np.float64)
    al = a[..., 3].copy()
    al[al >= 240] = 255
    return a[..., :3], al

def save_rgba(rgb, al, n):
    Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), np.clip(al, 0, 255).astype(np.uint8)]), 'RGBA').save(os.path.join(OUT, n + '.png'))

def save_piece(rgb, n):
    save_rgba(rgb, np.full(rgb.shape[:2], 255.0), n)

def erase(a, box, thr=80, sat_thr=999, grow=2, sigma=7, keep=None, lo=-1):
    """Tira texto/ícone claro da caixa preservando o fundo (degradê, tom, textura leve): só os pixels do
    traço (+ borda) são trocados pelo fundo vizinho (convolução normalizada, sem emenda)."""
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    l = sub.mean(axis=2)
    sat = sub.max(axis=2) - sub.min(axis=2)
    m = ((l > thr) | (sat > sat_thr)).astype(np.uint8)
    if keep is not None: m &= ~keep[y0:y1, x0:x1].astype(np.uint8) & 1
    if grow: m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
    pad = sigma * 4
    X0, Y0, X1, Y1 = max(0, x0 - pad), max(0, y0 - pad), min(a.shape[1], x1 + pad), min(a.shape[0], y1 + pad)
    big = np.zeros((Y1 - Y0, X1 - X0), np.uint8)
    big[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0] = m
    crop = a[Y0:Y1, X0:X1].astype(np.float64)
    cl = crop.mean(axis=2)
    w = ((big == 0) & (cl <= thr) & (cl > lo)).astype(np.float64)
    k = sigma * 6 + 1
    num = cv2.GaussianBlur(crop * w[..., None], (k, k), sigma)
    den = cv2.GaussianBlur(w, (k, k), sigma)[..., None]
    est = num / np.maximum(den, 1e-6)
    soft = cv2.GaussianBlur(big.astype(np.float64), (3, 3), 0)[..., None]
    out = a.astype(np.float64).copy()
    out[Y0:Y1, X0:X1] = crop * (1 - soft) + est * soft
    return out

def fill_smooth(a, box, ring=10, thr=60, sigma=None, feather=2, noise=0.8, lo=-1, green=False):
    """Troca a caixa inteira por um fundo liso que acompanha o entorno (cor e degradê), sem marcas:
    convolução normalizada só com o anel escuro em volta (dourados e textos não entram)."""
    x0, y0, x1, y1 = box
    h, w = a.shape[:2]
    if sigma is None: sigma = max(6, min(x1 - x0, y1 - y0) // 3)
    pad = sigma * 3 + ring
    X0, Y0, X1, Y1 = max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad)
    crop = a[Y0:Y1, X0:X1].astype(np.float64)
    wt = np.zeros(crop.shape[:2])
    wt[max(0, y0 - ring - Y0):y1 + ring - Y0, max(0, x0 - ring - X0):x1 + ring - X0] = 1
    wt[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0] = 0
    cm = crop.mean(axis=2)
    wt *= (cm <= thr) & (cm > lo)
    if green: wt *= (crop[..., 1] >= crop[..., 0] + 4)   # só o fundo verde do painel (sem dourado/marrom)
    # escala reduzida: rápido mesmo com sigma grande
    f = max(1, sigma // 6)
    sh, sw = max(2, crop.shape[0] // f), max(2, crop.shape[1] // f)
    cs = cv2.resize(crop * wt[..., None], (sw, sh), interpolation=cv2.INTER_AREA)
    ws = cv2.resize(wt, (sw, sh), interpolation=cv2.INTER_AREA)
    # escalas crescentes: onde o anel não alcança com o sigma pedido, completa com um mais largo (nada fica preto)
    est_s = np.zeros_like(cs); done = np.zeros(ws.shape, bool)
    ss = max(1.0, sigma / f)
    for _ in range(7):
        k = int(ss * 6) | 1
        num = cv2.GaussianBlur(cs, (k, k), ss)
        den = cv2.GaussianBlur(ws, (k, k), ss)
        ok = (den > 0.04) & ~done
        est_s[ok] = num[ok] / den[ok][..., None]
        done |= ok
        if done.all(): break
        ss *= 2
    if not done.all(): est_s[~done] = (cs.sum(axis=(0, 1)) / max(ws.sum(), 1e-6))
    est_s = cv2.GaussianBlur(est_s, (5, 5), 0)
    est = cv2.resize(est_s, (crop.shape[1], crop.shape[0]), interpolation=cv2.INTER_CUBIC)
    m = np.zeros(crop.shape[:2])
    m[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0] = 1
    if feather: m = cv2.GaussianBlur(m, (feather * 2 + 1, feather * 2 + 1), 0)
    rng = np.random.default_rng(x0 * 31 + y0)
    est = est + rng.normal(0, noise, crop.shape[:2])[..., None]
    out = a.astype(np.float64).copy()
    out[Y0:Y1, X0:X1] = crop * (1 - m[..., None]) + est * m[..., None]
    return out

def fill_separable(a, box, ref_y, ref_x, smooth=9, noise=0.6):
    """Fundo liso de faixa: perfil horizontal de uma linha limpa (ref_y) x perfil vertical de uma coluna
    limpa (ref_x). Mantém sombra/degradê da faixa sem fantasmas do que foi tirado."""
    x0, y0, x1, y1 = box
    R = a[ref_y, x0:x1].astype(np.float64)
    C = a[y0:y1, ref_x].astype(np.float64)
    if smooth > 1:
        R = cv2.blur(R[None], (smooth, 1))[0]
        C = cv2.blur(C[:, None], (1, smooth))[:, 0]
    C0 = np.maximum(a[ref_y, ref_x].astype(np.float64), 1.0)
    est = R[None, :, :] * (C[:, None, :] + 1.0) / (C0[None, None, :] + 1.0)
    rng = np.random.default_rng(x0 + y0 * 7)
    est = est + rng.normal(0, noise, est.shape[:2])[..., None]
    out = a.astype(np.float64).copy()
    out[y0:y1, x0:x1] = est
    return out

def icon_from(a, box, thr=70):
    x0, y0, x1, y1 = box
    return cut_icon(np.clip(a, 0, 255).astype(np.uint8), box, thr)

def save_icon(ic, n):
    Image.fromarray(ic.astype(np.uint8), 'RGBA').save(os.path.join(OUT, n + '.png'))

# ======================================================================= HISTÓRICO
H_TABS = [(67, 289), (301, 532), (544, 717), (729, 956), (968, 1144), (1156, 1374), (1386, 1603)]
H_TAB_Y = (206, 276)
H_ICONS = ['ico_todas', 'ico_computador', 'ico_online', 'ico_ranqueada', 'ico_local', 'ico_marcha', 'ico_xeque']

def tab_icon_box(a, x0, x1, y0, y1):
    sub = a[y0 + 12:y1 - 12, x0 + 18:x1 - 14]
    l = sub.mean(axis=2)
    cols = np.where((l > 110).any(axis=0))[0]
    groups = []
    s = p = cols[0]
    for c in cols[1:]:
        if c > p + 10: groups.append((s, p)); s = c
        p = c
    groups.append((s, p))
    gx0, gx1 = groups[0]
    return (x0 + 18 + gx0 - 2, y0 + 10, x0 + 18 + gx1 + 3, y1 - 10)

def build_historico():
    a, al = load_rgba('historico_v2')
    out = a.copy()
    # ícones das abas (também usados nas linhas)
    for i, (x0, x1) in enumerate(H_TABS):
        save_icon(icon_from(a, tab_icon_box(a, x0, x1, *H_TAB_Y), 90), H_ICONS[i])
    # peões e lupa das linhas
    save_icon(icon_from(a, (806, 312, 862, 378), 90), 'ico_peao_branco')
    save_icon(icon_from(a, (806, 518, 862, 584), 40), 'ico_peao_preto')
    # moldura das abas: comum (COMPUTADOR) e escolhida (TODAS), sem ícone/texto
    y0, y1 = H_TAB_Y
    for (x0, x1, n) in [(301, 533, 'hist_tab'), (67, 290, 'hist_tab_sel')]:
        t = fill_smooth(a, (x0 + 14, y0 + 12, x1 - 14, y1 - 12), ring=4, thr=70, sigma=10)
        save_piece(t[y0 - 2:y1 + 3, x0 - 2:x1 + 3], n)
    # linhas: derrota (1ª) e vitória (4ª); ficam escudo, faixa colorida, moldura e o botão com a lupa
    def row(ry0, n):
        r = a.copy()
        r = fill_separable(r, (178, ry0 + 8, 428, ry0 + 89), ry0 + 9, 424)        # DERROTA / RANQUEADA
        r = fill_separable(r, (436, ry0 + 8, 1330, ry0 + 89), ry0 + 9, 1200)      # ícone, vs, data, peão, lances
        r = fill_separable(r, (1404, ry0 + 24, 1546, ry0 + 74), ry0 + 23, 1540, smooth=3)  # texto ANALISAR (a lupa fica)
        save_piece(r[ry0:ry0 + 96, 68:1574], n)
    row(296, 'hist_row_loss')
    row(606, 'hist_row_win')
    # fundo: abas e lista saem (o jogo desenha); barra de rolagem e VOLTAR ficam
    out = fill_smooth(out, (62, 200, 1612, 284), ring=10, thr=50, sigma=40)
    out = fill_smooth(out, (64, 290, 1578, 810), ring=10, thr=50, sigma=90)
    save_rgba(out, al, 'hist_bg')
    print('historico v2 ok')

# ======================================================================= CONFIGURAÇÕES
C_TRACKS = [(545, 580, 488, 546), (660, 696, 540, 600)]   # (borda de cima, borda de baixo, x0 e x1 do botão esmeralda)

def build_config():
    a, al = load_rgba('config_v2')
    out = a.copy()
    # peças do slider: preenchimento dourado e o botão esmeralda (da MÚSICA)
    save_piece(a[543:582, 300:312], 'slider_fill')
    kn = a[526:600, 484:548].copy()
    l = kn.mean(axis=2); sat = kn.max(axis=2) - kn.min(axis=2)
    ka = np.where((l > 62) | (sat > 70), 255.0, 0.0)
    ka = cv2.morphologyEx(ka.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)).astype(np.float64)
    ys, xs = np.where(ka > 0)
    kn = kn[ys.min():ys.max() + 1, xs.min():xs.max() + 1]; ka = ka[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    save_rgba(kn, ka, 'slider_knob')
    # trilhos vazios: o dourado e o botão saem (repete um trecho vazio do próprio trilho, sem os losangos)
    for (t0, t1, k0, k1) in C_TRACKS:
        y0, y1 = t0 - 20, t1 + 22
        for x in range(243, k1 + 6):
            sx = 940 + ((x - 243) % 210)
            out[y0:y1, x] = a[y0:y1, sx]
    # textos vivos saem: MÚSICA · 22%, EFEITOS SONOROS · 28%, PRÉ-MOVE: LIGADO / Jogue na vez…, versão
    for box in [(224, 494, 484, 541), (224, 608, 664, 655), (332, 796, 744, 894), (1022, 978, 1330, 1022)]:
        out = erase(out, box, thr=62, grow=4, sigma=6, lo=14)
    save_rgba(out, al, 'config_bg')
    print('config v2 ok')

# ======================================================================= CONTRA O COMPUTADOR (Desafio das Ligas)
B_R1 = [(100, 332), (347, 581), (596, 828), (842, 1075), (1090, 1322), (1336, 1572)]
B_R2 = [(100, 380), (395, 680), (695, 977), (993, 1277), (1292, 1572)]
B_Y1 = (215, 517)
B_Y2 = (531, 807)

def first_blob(a, box, thr=110, sat=90):
    x0, y0, x1, y1 = box
    sub = a[y0:y1, x0:x1]
    m = (sub.mean(axis=2) > thr) | ((sub.max(axis=2) - sub.min(axis=2)) > sat)
    cols = np.where(m.any(axis=0))[0]
    s = p = cols[0]
    for c in cols[1:]:
        if c > p + 5: break
        p = c
    return (x0 + s - 1, y0, x0 + p + 2, y1)

def const_cols(a, box, ref_x):
    x0, y0, x1, y1 = box
    out = a.copy()
    out[y0:y1, x0:x1] = a[y0:y1, ref_x:ref_x + 1]
    return out

def build_bots():
    a, al = load_rgba('bots_v2')
    out = a.copy()
    # ícones do estado: ✓ (Madeira), espadas (Prata), cadeado (Ouro)
    save_icon(icon_from(a, first_blob(a, (130, 400, 330, 428), 120, 80), 60), 'ico_check')
    save_icon(icon_from(a, first_blob(a, (870, 398, 1070, 430), 120, 80), 70), 'ico_espadas_ouro')
    save_icon(icon_from(a, first_blob(a, (1120, 398, 1320, 430), 90, 999), 60), 'ico_cadeado')
    # botões (moldura + miolo, sem texto): JOGAR DE NOVO, DESAFIAR, BLOQUEADO
    for (x0, x1, n, rx) in [(112, 321, 'btn_jogar_de_novo', 120), (856, 1062, 'btn_desafiar', 866), (1102, 1310, 'btn_bloqueado', 1110)]:
        b = const_cols(a, (x0 + 12, 466, x1 - 12, 500), rx)
        save_piece(b[458:508, x0:x1], n)
    # cartão da Prata (destacado na arte): vira cartão comum — moldura do Bronze (246 px à esquerda) + escudo da Prata
    out[203:530, 838:1080] = a[203:530, 592:834]
    out[203:530, 826:844] = a[203:530, 579:597]       # vão à esquerda (sem o brilho): copia o vão Ferro|Bronze
    out[203:530, 1073:1092] = a[203:530, 1320:1339]   # vão à direita: copia o vão Platina|Ouro
    sub = a[222:348, 880:1040]
    l = sub.mean(axis=2); sat = sub.max(axis=2) - sub.min(axis=2)
    bgc = np.median(a[360:380, 860:870].reshape(-1, 3), axis=0)
    keep = ((l > 75) | (sat > 70)) & (np.abs(sub - bgc).sum(axis=2) > 90)
    keep = cv2.morphologyEx(keep.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)) > 0
    # tira antes o escudo do Bronze que veio junto e põe o da Prata
    out = fill_smooth(out, (856, 222, 1062, 348), ring=4, thr=55, sigma=12, lo=8)
    tgt = out[222:348, 880:1040]
    tgt[keep] = sub[keep]
    out[222:348, 880:1040] = tgt
    # textos e botões de todos os cartões saem (o jogo desenha)
    for (cols, (y0, y1), ty) in [(B_R1, B_Y1, 346), (B_R2, B_Y2, 646)]:
        for (x0, x1) in cols:
            out = fill_smooth(out, (x0 + 12, ty, x1 - 12, y1 - 10), ring=3, thr=50, sigma=14, lo=6)
    # nota do rodapé: "Progresso salvo na sua conta." sai (o ícone ⓘ fica)
    out = erase(out, (784, 846, 1100, 884), thr=70, grow=3, sigma=6, lo=8)
    save_rgba(out, al, 'bots_bg')
    print('bots v2 ok')

# ======================================================================= CONHEÇA O FRAIHA
A_NAV = [(220, 286), (296, 360), (371, 436), (445, 510), (521, 585), (595, 661)]
A_ICONS = ['about_ico_projeto', 'about_ico_como', 'about_ico_ligas', 'about_ico_modos', 'about_ico_perso', 'about_ico_comunidade']

def gold_icon(a, box):
    x0, y0, x1, y1 = box
    b = a[y0:y1, x0:x1].copy()
    r, g, bl = b[..., 0], b[..., 1], b[..., 2]
    al = np.where(((r > 110) & (r > bl + 45)) | (b.mean(axis=2) > 170), 255, 0).astype(np.uint8)
    al = cv2.morphologyEx(al, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(al, 8)
    for k in range(1, n):
        if stats[k, cv2.CC_STAT_AREA] < 12: al[lab == k] = 0
    # contorno escuro do desenho entra junto (fica igual ao da arte)
    al = cv2.dilate(al, np.ones((3, 3), np.uint8)) & np.where((b.mean(axis=2) < 40) | (al > 0), 255, 0).astype(np.uint8)
    ys, xs = np.where(al > 0)
    b = b[ys.min():ys.max() + 1, xs.min():xs.max() + 1]; al = al[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    return np.dstack([b, al])

def build_conheca():
    a, al = load_rgba('conheca_v2')
    out = a.copy()
    for i, (y0, y1) in enumerate(A_NAV):
        save_icon(gold_icon(a, (148, y0 + 12, 210, y1 - 12)), A_ICONS[i])
    save_icon(gold_icon(a, (626, 248, 716, 343)), 'about_ico_projeto_big')
    # moldura dos tópicos: comum (COMO JOGAR) e escolhido (O PROJETO); a seta › fica, ícone e texto saem
    for (y0, y1, x0, x1, n) in [(294, 363, 121, 554, 'about_btn'), (217, 290, 117, 558, 'about_btn_sel')]:
        b = const_cols(a, (x0 + 18, y0 + 8, 492, y1 - 8), 480)
        save_piece(b[y0:y1, x0:x1], n)
    # fundo: os 6 tópicos saem (o jogo desenha); conteúdo do tópico sai; o castelo pintado e a moldura do ícone ficam
    out = fill_smooth(out, (112, 214, 564, 668), ring=8, thr=45, sigma=60, lo=4)
    out = fill_smooth(out, (612, 242, 726, 346), ring=3, thr=95, sigma=30, lo=28)      # peão do quadro azul
    out = fill_smooth(out, (758, 250, 1090, 326), ring=6, thr=45, sigma=24, lo=6)      # título do tópico
    out = fill_smooth(out, (612, 386, 1150, 442), ring=6, thr=45, sigma=24, lo=6)      # frase de abertura
    out = fill_smooth(out, (610, 468, 1170, 674), ring=6, thr=45, sigma=40, lo=6)      # corpo (parte lisa)
    out = erase(out, (1160, 468, 1440, 674), thr=95, grow=3, sigma=7, lo=6)             # corpo sobre a pintura
    save_rgba(out, al, 'about_bg')
    print('conheca v2 ok')

# ======================================================================= AMIGOS
def ring_piece(a, cx, cy, r_in, r_out, n):
    x0, y0, x1, y1 = int(cx - r_out - 2), int(cy - r_out - 2), int(cx + r_out + 3), int(cy + r_out + 3)
    c = a[y0:y1, x0:x1].copy()
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(yy - cy, xx - cx)
    al = np.clip((d - r_in) * 255.0, 0, 255) * np.clip((r_out - d) * 255.0, 0, 255) / 255.0
    save_rgba(c, al, n)

def build_amigos():
    a, al = load_rgba('amigos_v2')
    out = a.copy()
    # ícones
    for (box, n, thr) in [((112, 350, 154, 392), 'fr_ico_online', 60), ((102, 504, 156, 556), 'fr_ico_partida', 70),
                          ((112, 668, 156, 710), 'fr_ico_offline', 60), ((768, 762, 830, 820), 'fr_ico_balao', 80),
                          ((1096, 766, 1158, 816), 'fr_ico_convidar', 80), ((116, 248, 170, 302), 'fr_ico_lupa', 80),
                          ((256, 798, 294, 832), 'fr_ico_dot_off', 50)]:
        save_icon(gold_icon(a, box) if n in ('fr_ico_balao', 'fr_ico_convidar') else icon_from(a, box, thr), n)
    # moldura do retrato (anel dourado) — o avatar entra no meio
    ring_piece(a, 177.5, 792.5, 41.5, 57, 'fr_anel')
    # peças 9-slice (sem texto/ícone)
    save_piece(const_cols(a, (106, 238, 1062, 308), 1062)[228:317, 89:1075], 'fr_campo')
    save_piece(const_cols(a, (1104, 238, 1348, 308), 1104)[228:317, 1094:1360], 'fr_btn_verde')
    save_piece(const_cols(a, (756, 758, 1018, 826), 1006)[748:834, 730:1041], 'fr_btn_azul')
    save_piece(fill_smooth(a, (108, 410, 1342, 476), ring=4, thr=45, sigma=20, lo=4)[400:485, 92:1358], 'fr_caixa_vazia')
    save_piece(fill_smooth(a, (106, 346, 1346, 396), ring=3, thr=45, sigma=16, lo=4)[338:404, 88:1362], 'fr_caixa_secao')
    r = fill_smooth(a, (110, 742, 1342, 843), ring=4, thr=45, sigma=24, lo=4)
    r = fill_smooth(r, (108, 737, 250, 848), ring=3, thr=45, sigma=20, lo=4)
    save_piece(r[731:853, 92:1358], 'fr_caixa_linha')
    # fundo: abaixo do cabeçalho (VOLTAR + placa AMIGOS + bandeira ficam) tudo sai — o jogo desenha
    out = fill_smooth(out, (74, 222, 1376, 1004), ring=8, thr=40, sigma=90, lo=4)
    save_rgba(out, al, 'amigos_bg')
    # peças do kit vão para ui_kit/art (Kit.tex)
    art = os.path.join(os.path.dirname(OUT), 'art')
    for f in os.listdir(OUT):
        if f.startswith('fr_'): os.replace(os.path.join(OUT, f), os.path.join(art, f))
    print('amigos v2 ok')

# ======================================================================= PERFIL DO JOGADOR
def build_perfil():
    a, al = load_rgba('perfil_v2')
    out = a.copy()
    # ícones das abas
    save_icon(gold_icon(a, (108, 238, 162, 302)), 'pf_ico_avatares')
    save_icon(gold_icon(a, (108, 342, 164, 402)), 'pf_ico_icones')
    # abas (moldura sem ícone/texto): escolhida (AVATARES) e comum (ÍCONES)
    t = fill_smooth(a, (102, 238, 304, 298), ring=3, thr=70, sigma=14, lo=6)
    save_piece(t[226:311, 89:318], 'pf_tab_sel')
    t = fill_smooth(a, (102, 342, 300, 400), ring=3, thr=45, sigma=14, lo=4, green=True)
    save_piece(t[331:412, 89:314], 'pf_tab')
    # cartões: comum (ARQUEIRA), escolhido (GUERREIRO, com o brilho) e bloqueado (CAVALO DE BRONZE)
    for (x0, y0, x1, y1, n) in [(338, 224, 502, 430, 'pf_card_sel'), (677, 435, 833, 627, 'pf_card_locked')]:
        c = fill_smooth(a, (x0 + 8, y0 + 8, x1 - 8, y1 - 8), ring=4, thr=45, sigma=18, lo=4, green=True)
        save_piece(c[y0:y1, x0:x1], n)
        if n == 'pf_card_locked':
            # cartão comum: a mesma moldura fina, em dourado (o retrato tem a moldura dourada do jogo)
            g = c[y0:y1, x0:x1].copy()
            l = g.mean(axis=2)
            frame = (np.abs(g[..., 0] - g[..., 2]) < 30) & (l > 40)
            gold = np.stack([l * 1.15, l * 0.86, l * 0.42], axis=2)
            g[frame] = np.clip(gold[frame], 0, 255)
            save_piece(g, 'pf_card')
    # botões: APLICAR AVATAR (verde), SALVAR NOME (azul) e o campo do nome — sem texto
    save_piece(const_cols(a, (1438, 320, 1642, 356), 1440)[310:364, 1422:1658], 'pf_btn_aplicar')
    save_piece(const_cols(a, (1524, 438, 1678, 472), 1526)[428:481, 1510:1690], 'pf_btn_salvar')
    save_piece(const_cols(a, (1080, 438, 1488, 472), 1480)[428:481, 1068:1499], 'pf_field')
    # anel do retrato do detalhe (o avatar entra no meio, recortado em círculo)
    ring_piece(a, 1166.5, 284.5, 68.5, 77, 'pf_anel')
    # fundo: o que é vivo sai (o jogo desenha); molduras, barra de rolagem e os 3 botões de baixo ficam
    out[224:414, 82:98] = a[430:620, 82:98]                                              # borda da coluna (sem as abas)
    out[224:414, 308:324] = a[430:620, 308:324]
    out = fill_smooth(out, (98, 222, 308, 416), ring=6, thr=40, sigma=40, lo=4, green=True)    # abas
    out = erase(out, (480, 196, 830, 222), thr=80, grow=3, sigma=6, lo=4)                 # "6 de 19 avatares…"
    out = fill_smooth(out, (334, 224, 1006, 834), ring=6, thr=40, sigma=60, lo=4, green=True)  # cartões
    out = fill_smooth(out, (1076, 200, 1676, 370), ring=6, thr=40, sigma=40, lo=4, green=True)  # detalhe
    out = fill_smooth(out, (1064, 386, 1694, 550), ring=6, thr=40, sigma=40, lo=4)       # nome público
    for box in [(1112, 562, 1364, 664), (1418, 562, 1684, 664), (1112, 676, 1364, 762), (1418, 676, 1684, 762)]:
        out = fill_smooth(out, box, ring=4, thr=40, sigma=20, lo=4)                       # estatísticas
    save_rgba(out, al, 'perfil_bg')
    print('perfil v2 ok')

# ======================================================================= BUSCANDO ADVERSÁRIO
def build_buscando():
    a, al = load_rgba('buscando_v2')
    out = a.copy()
    # ficam título, molduras e CANCELAR; saem o ritmo e o contador (o jogo escreve e atualiza)
    out = fill_smooth(out, (498, 676, 952, 734), ring=6, thr=70, sigma=18, lo=10, green=True)
    out = fill_smooth(out, (654, 746, 798, 800), ring=6, thr=70, sigma=18, lo=10, green=True)
    save_rgba(out, al, 'buscando_bg')
    print('buscando v2 ok')

# ======================================================================= ESCOLHA SEU LADO
def build_lado():
    a, al = load_rgba('lado_v2')
    out = a.copy()
    # "Adversário: BOT BRONZE" sai (o jogo escreve o bot escolhido); o resto é a arte
    out = fill_smooth(out, (300, 436, 822, 484), ring=6, thr=70, sigma=18, lo=8, green=True)
    save_rgba(out, al, 'lado_bg')
    print('lado v2 ok')

if __name__ == '__main__':
    which = sys.argv[1:] or ['historico']
    for w in which: globals()['build_' + w]()
