extends "res://tests/dm_jitter_test.gd"
## R52f · FIXTURE QUE DEVE FALHAR: prova que o gate do dm_jitter_test sai com código != 0 quando há FAIL.
## Usa o teste de verdade; só faz a caixa "andar" 1 px a cada medição (simula o tremor que o teste detecta).
## Uso: SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/fixtures/gate_fail_dm_jitter.gd ; echo $?   (esperado: 1)
var _jig := 0

func _rects() -> Array:
    var r: Array = super._rects()
    if r.is_empty(): return r
    _jig += 1
    return [Rect2(r[0].position + Vector2(_jig % 2, 0), r[0].size), r[1]]
