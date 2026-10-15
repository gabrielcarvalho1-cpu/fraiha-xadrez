extends "res://ui_v022/home_modal.gd"
## R104 · aviso importante na moldura do jogo (ex.: CONTA SUSPENSA). Título na placa, texto no meio e ENTENDI.

var text_label: Label

func setup(p_hub, title: String):
	build(p_hub, title)
	text_label = label("", 18, CREAM, true)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.name = "NoticeText"
	body.add_child(text_label)
	var ok := button("ENTENDI", 18, true)
	ok.name = "NoticeOk"
	ok.custom_minimum_size.y = 52
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size.x = 260
	ok.pressed.connect(close)
	body.add_child(ok)

func show_notice(title: String, text: String):
	title_label.text = title
	text_label.text = text
	open()
