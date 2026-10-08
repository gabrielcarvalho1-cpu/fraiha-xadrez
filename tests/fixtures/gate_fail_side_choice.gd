extends "res://tests/side_choice_shots.gd"
## R52f · FIXTURE QUE DEVE FALHAR: prova que o gate do side_choice_shots sai com código != 0 quando há FAIL.
## Usa o teste de verdade; só inverte UMA verificação ("painel centralizado") para ela falhar.
## Uso: SHOT_DIR=/tmp SHOT_SIZE=1672x941 xvfb-run godot --rendering-driver opengl3 --path <proj> -s tests/fixtures/gate_fail_side_choice.gd ; echo $?   (esperado: 1)

func check(ok: bool, label: String):
    super.check(ok if label != "painel centralizado" else not ok, label + (" [fixture: forçado a falhar]" if label == "painel centralizado" else ""))
