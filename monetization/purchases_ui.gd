extends RefCounted
## R107 · MINHAS COMPRAS — o que a conta já comprou (payment_history do servidor), a situação de cada pedido,
## o que está ativo agora (Fundador #N, Club até DD/MM) e como pedir reembolso (7 dias, pelo contato dos Termos).
const Art := preload("res://monetization/premium_art.gd")
const Catalog := preload("res://monetization/monetization_catalog.gd")
const Legal := preload("res://ui_v022/legal_text.gd")

const STATUS := {
	"paid": ["PAGO", "ok"],
	"refunded": ["REEMBOLSADO", "info"],
	"pending": ["AGUARDANDO PAGAMENTO", "new"],
	"cancelled": ["CANCELADO", "soon"],
	"sold_out": ["VAGAS ESGOTADAS · REEMBOLSO", "info"],   # R171 · pago depois de as vagas do Fundador acabarem
}
const NAMES := {"founder": "Pacote Fundador", "founder_legend": "Fundador Lendário", "club_monthly": "Club FRAIHA · 30 dias", "club_yearly": "Club FRAIHA · 1 ano"}
const METHOD := {"pix": "PIX", "card": "Cartão"}

static func _date(iso: String) -> String:
	if iso.length() < 16: return ""
	var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) - 3 * 3600   # horário de Brasília
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%02d/%02d/%04d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]

static func _age_s(iso: String) -> int:
	if iso.length() < 19: return 0
	return int(Time.get_unix_time_from_system()) - int(Time.get_unix_time_from_datetime_string(iso.substr(0, 19)))

## Pedidos que aparecem: pagos e reembolsados sempre; PIX pendente só nos primeiros 30 min; cancelados não.
static func visible_items(items: Array) -> Array:
	var out := []
	for it in items:
		if not (it is Dictionary): continue
		var st := String(it.get("status", ""))
		if st in ["paid", "refunded", "sold_out"] or (st == "pending" and _age_s(String(it.get("created_at", ""))) < 1800):
			out.append(it)
	return out

static func build(hub, parent: VBoxContainer):
	var head := Art.Frame.new("founder", int(26 * hub.k))
	head.name = "PurchasesHero"
	parent.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", int(8 * hub.k))
	head.add_child(hv)
	var t := Art.label(hv, "MINHAS COMPRAS", hub.fs(44), Art.GOLD, Art.FONT_BOLD)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.0, 0.95))
	# o que está ativo agora
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	hv.add_child(chips)
	if hub.founder_owned():
		var n: int = hub.founder_number()
		chips.add_child(Art.Stamp.new(("FUNDADOR LENDÁRIO" if hub.legend_owned() else "FUNDADOR DO REINO") + (" #%d" % n if n > 0 else ""), "ok", 14))
	if hub.club_real():
		var exp := String(hub.main_hub.entitlements.club_expires_at()) if hub.main_hub != null else ""
		chips.add_child(Art.Stamp.new("CLUB ATIVO" + (" ATÉ %s/%s/%s" % [exp.substr(8, 2), exp.substr(5, 2), exp.substr(0, 4)] if exp.length() >= 10 else ""), "ok", 14))
	if chips.get_child_count() == 0:
		chips.add_child(Art.Stamp.new("NENHUMA VANTAGEM ATIVA", "soon", 14))
	var acc = hub._account()
	if acc == null or not acc.has_method("has_profile") or not acc.has_profile():
		Art.label(hv, "Entre na sua conta para ver as suas compras.", hub.fs(19), Art.CREAM)
		return
	var list := Art.Frame.new("dark", int(20 * hub.k))
	list.name = "PurchasesList"
	parent.add_child(list)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", int(10 * hub.k))
	list.add_child(lv)
	if not hub.purchases_loaded:
		Art.label(lv, "Carregando as suas compras…", hub.fs(18), Art.MUTED)
	else:
		var items := visible_items(hub.purchases)
		if items.is_empty():
			var e := Art.label(lv, "Você ainda não fez nenhuma compra. Quando fizer, ela aparece aqui com a data, a forma de pagamento e a situação.", hub.fs(18), Art.MUTED)
			e.name = "PurchasesEmpty"
		for it in items:
			lv.add_child(_row(hub, it))
	# reembolso
	var help := Art.label(parent, "Arrependeu? Até 7 dias depois da compra você pode pedir o reembolso integral pelo e-mail %s, informando o seu nome de jogador. As vantagens daquela compra são retiradas." % Legal.CONTATO, hub.fs(15), Art.MUTED)
	help.name = "PurchasesRefundHelp"

static func _row(hub, it: Dictionary) -> Control:
	var row: BoxContainer = VBoxContainer.new() if hub.narrow else HBoxContainer.new()
	row.name = "Purchase_" + String(it.get("product_id", "")).validate_node_name()
	row.add_theme_constant_override("separation", 10)
	var pid := String(it.get("product_id", ""))
	var g := Art.Glyph.new("crown" if pid.begins_with("founder") else "book", 40 * maxf(hub.k, 0.8), Art.GOLD, true)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not hub.narrow: row.add_child(g)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	Art.label(col, String(NAMES.get(pid, it.get("title", pid))), hub.fs(22), Art.CREAM, Art.FONT_BOLD)
	var when := _date(String(it.get("paid_at", "") if it.get("paid_at") != null else "")) if String(it.get("status", "")) == "paid" else ""
	if when.is_empty(): when = _date(String(it.get("created_at", "")))
	Art.label(col, "%s  ·  %s  ·  %s" % [when, METHOD.get(String(it.get("method", "")), "—"), Catalog.brl(int(it.get("amount_cents", 0)))], hub.fs(16), Art.MUTED)
	var st: Array = STATUS.get(String(it.get("status", "")), [String(it.get("status", "")).to_upper(), "soon"])
	var stamp := Art.Stamp.new(st[0], st[1], 13)
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stamp)
	return row
