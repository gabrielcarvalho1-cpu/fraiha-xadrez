extends RefCounted
## R51 · Relógio LOCAL das partidas contra o computador (10 minutos para cada lado, sem acréscimo).
## Mesmo formato do ranked/clock_state.gd (remaining_ms / active), para os cartões do Ranked lerem igual.
## Aqui o próprio aparelho decide o tempo esgotado (não há servidor na partida contra o bot).
const BOT_MS := 600000
var white_ms := BOT_MS
var black_ms := BOT_MS
var active := ""          # "w" | "b" | "" (parado)

func reset(ms := BOT_MS):
    white_ms = ms
    black_ms = ms
    active = ""

func start(color: String):
    active = color

func stop():
    active = ""

func tick(delta: float):
    if active == "": return
    var d := int(round(delta * 1000.0))
    if active == "w": white_ms = maxi(0, white_ms - d)
    else: black_ms = maxi(0, black_ms - d)

func remaining_ms(color: String) -> int:
    return white_ms if color == "w" else black_ms

func flagged() -> String:
    if active == "w" and white_ms <= 0: return "w"
    if active == "b" and black_ms <= 0: return "b"
    return ""
