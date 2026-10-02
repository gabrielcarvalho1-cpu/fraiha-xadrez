extends RefCounted
## MARCHA REAL · coordenadas das casas na arte do tabuleiro (marcha/art/board.png, 1600x1600).
## Medidas tiradas da própria arte enviada (tabuleiro_vazio.png): 76 casas na Muralha (19 por reino),
## 4 encaixes no Pátio e 4 no Salão do Trono de cada reino. Sentido da marcha: horário.
## Reinos (assento): 0 Marfim (embaixo, você) · 1 Rubi (esquerda) · 2 Ônix (em cima, aliado) · 3 Esmeralda (direita).
const SIZE := 1600.0
const TRACK_LEN := 76
const ARM := 19
const CELL_RADIUS := 18.0

## Braço do Marfim (19 casas a partir do Portão, sentido horário); os outros são rotações de 90°.
const ARM0 := [
    Vector2(670, 1484),
    Vector2(670, 1419), Vector2(670, 1354), Vector2(670, 1289), Vector2(670, 1224), Vector2(670, 1159),
    Vector2(624, 1113), Vector2(578, 1067), Vector2(532, 1021), Vector2(486, 975),
    Vector2(440, 929), Vector2(375, 929), Vector2(310, 929), Vector2(245, 929), Vector2(180, 929), Vector2(115, 929),
    Vector2(115, 864), Vector2(115, 799), Vector2(115, 734),
]
## Salão do Trono do Marfim (da entrada para o fundo; o último tem a coroa gravada).
const LANE0 := [Vector2(800, 1419), Vector2(800, 1354), Vector2(800, 1289), Vector2(800, 1224)]
## Pátio do Marfim: placa reenquadrada (centro da placa ±60 px) — ver tools/marcha_board_fix.py.
const HOME_CENTER0 := Vector2(469.9, 1300.3)
const HOME_OFFSETS := [Vector2(0, -60.5), Vector2(-60.5, 0), Vector2(60.5, 0), Vector2(0, 60.5)]

## Gira um ponto 90° no sentido horário k vezes em torno do centro da arte.
static func rot(p: Vector2, k: int) -> Vector2:
    var q := p
    for i in range(posmod(k, 4)):
        q = Vector2(SIZE - q.y, q.x)
    return q

## Marfim fica embaixo; Rubi à esquerda = Marfim girado 90° horário; Ônix 180°; Esmeralda 270°.
static func track_cell(abs_index: int) -> Vector2:
    var i := posmod(abs_index, TRACK_LEN)
    return rot(ARM0[i % ARM], i / ARM)

static func lane_cell(seat: int, k: int) -> Vector2:
    return rot(LANE0[clampi(k, 0, 3)], seat)

static func home_cell(seat: int, slot: int) -> Vector2:
    return rot(HOME_CENTER0 + HOME_OFFSETS[slot % 4], seat)

static func home_center(seat: int) -> Vector2:
    return rot(HOME_CENTER0, seat)

## Portão (casa de saída) e Entrada do Salão de cada reino, em índice absoluto da Muralha.
static func gate_index(seat: int) -> int:
    return seat * ARM

static func entrance_index(seat: int) -> int:
    return posmod(seat * ARM - 2, TRACK_LEN)
