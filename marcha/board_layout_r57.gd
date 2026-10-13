extends RefCounted
## R57 · MARCHA REAL no PC: casas medidas na arte final do dono (tools/ui_ref/r57/marcha_partida.png).
## GERADO por tools/visual_final_r57.py — não editar à mão. Mesma API e mesma topologia de board_layout.gd
## (76 casas na Muralha, 19 por reino; 4 no Salão e 4 no Pátio de cada reino; sentido horário).
## Coordenadas em unidades do tabuleiro: largura 1600 (o recorte da arte tem 730 x 635 px).
const SIZE := 1600.0
const HEIGHT := 1391.8
const TRACK_LEN := 76
const ARM := 19
const CELL_RADIUS := 18.0
const CENTER := Vector2(800.0, 697.0)
## recorte da arte (px da referência 1672x941) que corresponde ao tabuleiro
const ART_RECT := Rect2(480, 110, 730, 635)
const ART_RECT_FULL := Rect2(480, 110, 730, 657)   # R82: com a barra de baixo (desceu 20 px) — recortes da arte
const TRACK := [Vector2(678.1, 1324.3), Vector2(677.9, 1264.0), Vector2(677.0, 1204.8), Vector2(677.0, 1146.5), Vector2(677.5, 1088.2), Vector2(676.6, 1027.7), Vector2(626.6, 985.0), Vector2(580.4, 944.9), Vector2(534.4, 901.9), Vector2(488.3, 860.3), Vector2(437.7, 819.1), Vector2(371.5, 819.1), Vector2(305.1, 818.6), Vector2(239.8, 819.1), Vector2(172.9, 818.4), Vector2(98.0, 819.3), Vector2(98.0, 754.2), Vector2(98.8, 690.4), Vector2(98.2, 629.5), Vector2(98.6, 560.0), Vector2(173.4, 564.8), Vector2(239.6, 565.0), Vector2(305.3, 564.8), Vector2(370.8, 564.8), Vector2(437.3, 565.0), Vector2(488.3, 526.2), Vector2(535.0, 485.9), Vector2(581.0, 442.7), Vector2(627.1, 402.6), Vector2(677.0, 369.3), Vector2(677.3, 311.5), Vector2(677.7, 254.7), Vector2(677.3, 198.1), Vector2(677.3, 138.7), Vector2(678.1, 80.4), Vector2(745.9, 80.7), Vector2(809.9, 81.3), Vector2(871.9, 80.4), Vector2(931.5, 84.2), Vector2(927.1, 139.6), Vector2(926.9, 198.8), Vector2(927.1, 255.6), Vector2(926.9, 311.9), Vector2(928.7, 369.3), Vector2(979.1, 403.1), Vector2(1024.9, 443.2), Vector2(1071.1, 485.5), Vector2(1118.2, 526.7), Vector2(1167.6, 565.5), Vector2(1233.1, 564.8), Vector2(1298.6, 564.6), Vector2(1365.0, 565.5), Vector2(1430.1, 564.8), Vector2(1497.4, 564.6), Vector2(1497.0, 629.3), Vector2(1497.4, 691.1), Vector2(1497.6, 754.6), Vector2(1499.2, 816.4), Vector2(1429.0, 818.8), Vector2(1364.8, 819.1), Vector2(1299.5, 818.2), Vector2(1232.7, 819.3), Vector2(1167.1, 818.8), Vector2(1117.8, 860.3), Vector2(1070.7, 901.7), Vector2(1025.1, 944.7), Vector2(977.1, 985.0), Vector2(928.0, 1027.1), Vector2(926.9, 1088.2), Vector2(926.9, 1146.1), Vector2(927.1, 1204.2), Vector2(927.1, 1263.8), Vector2(926.0, 1328.2), Vector2(868.6, 1324.7), Vector2(806.1, 1324.9), Vector2(744.3, 1324.9)]
const LANES := [[Vector2(802.2, 1234.4), Vector2(802.2, 1179.0), Vector2(802.2, 1123.5), Vector2(802.2, 1068.3)], [Vector2(175.3, 692.6), Vector2(241.1, 692.6), Vector2(306.8, 692.6), Vector2(372.6, 692.6)], [Vector2(801.1, 154.3), Vector2(801.1, 210.6), Vector2(801.1, 267.4), Vector2(801.1, 323.3)], [Vector2(1424.7, 692.6), Vector2(1358.9, 692.6), Vector2(1293.2, 692.6), Vector2(1227.4, 692.6)]]
## R66 · Pátio em grade 2x2 (tools/marcha_board_r66.py)
const HOMES := [[Vector2(427.8, 1105.2), Vector2(524.9, 1105.2), Vector2(427.8, 1194.5), Vector2(524.9, 1194.5)], [Vector2(245.3, 354.7), Vector2(349.1, 354.7), Vector2(245.3, 448.1), Vector2(349.1, 448.1)], [Vector2(1101.9, 223.1), Vector2(1201.2, 223.1), Vector2(1101.9, 313.3), Vector2(1201.2, 313.3)], [Vector2(1261.5, 980.3), Vector2(1357.0, 980.3), Vector2(1261.5, 1069.5), Vector2(1357.0, 1069.5)]]
const HOME_CENTERS := [Vector2(476.4, 1133.2), Vector2(297.2, 383.4), Vector2(1151.5, 251.2), Vector2(1309.3, 1008.2)]

static func track_cell(abs_index: int) -> Vector2:
    return TRACK[posmod(abs_index, TRACK_LEN)]

static func lane_cell(seat: int, k: int) -> Vector2:
    return LANES[posmod(seat, 4)][clampi(k, 0, 3)]

static func home_cell(seat: int, slot: int) -> Vector2:
    return HOMES[posmod(seat, 4)][slot % 4]

static func home_center(seat: int) -> Vector2:
    return HOME_CENTERS[posmod(seat, 4)]

static func gate_index(seat: int) -> int:
    return seat * ARM

static func entrance_index(seat: int) -> int:
    return posmod(seat * ARM - 2, TRACK_LEN)
