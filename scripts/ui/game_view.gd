extends Control
## Vista di gioco: la galassia in 3D al centro; a sinistra la plancia della fazione (leader, carte
## in mano, missioni assegnate, obiettivi o sonde); a destra il dettaglio del sistema scelto e la
## cronaca; in basso il pannello delle decisioni. I sistemi da scegliere si illuminano sul tabellone.
## Le informazioni segrete (base ribelle, carte in mano) si vedono solo dal lato di chi le possiede;
## in due sullo stesso dispositivo una tenda chiede di passarsi il dispositivo.

const LX := 10.0
const LW := 410.0
const RX := 1520.0
const RW := 390.0
const MX := LX + LW + 10.0
const MW := RX - MX - 10.0

var main
var config: Dictionary
var engine: RBEngine
var st: RBState
var online = null
var humans: Array = []
var viewer := ""                   # "" = si vede tutto (partita fra IA)
var board: Board3D
var pending: Dictionary = {}
var sel: Array = []
var tab := "R"
var info_sys := ""

# nodi
var top_round: Label
var top_rep: Label
var top_phase: Label
var top_turn: Label
var left_box: VBoxContainer
var tab_btns := {}
var info_box: VBoxContainer
var info_panel: PanelContainer
var log_lbl: RichTextLabel
var dec_panel: PanelContainer
var dec_title: RichTextLabel
var dec_body: VBoxContainer
var zoom_layer: Control
var banner: PanelContainer
var banner_box: VBoxContainer
var banner_t := 0.0
var modal: Control
var online_lbl: Label
var place_state := {}
var dmg_state := {}
var order_state: Array = []
var target_cb := {}                # sistema → Callable
var _last_f := ""
var _refresh_queued := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = config.get("online", null)

	engine = RBEngine.new()
	add_child(engine)
	engine.setup(config)
	st = engine.st
	if online != null:
		humans = [online.faction]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for f in ["R", "I"]:
			if not engine.players[f]["ai"]:
				humans.append(f)
	if humans.size() == 1:
		viewer = humans[0]
	elif humans.size() == 2:
		viewer = "R"
	tab = viewer if viewer != "" else "R"
	engine.viewer = viewer if viewer != "" else "R"

	board = Board3D.new()
	board.eng = engine
	board.viewer = viewer
	add_child(board)
	board.target_clicked.connect(_on_target)
	board.system_clicked.connect(_on_system_clicked)

	_build_top()
	_build_left()
	_build_right()
	_build_decision()
	_build_banner()
	modal = Control.new()
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	zoom_layer = Control.new()
	zoom_layer.size = Vector2(1920, 1080)
	zoom_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zoom_layer)
	_build_online_label()

	engine.changed.connect(_queue_refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
		Audio.suspended = true
	engine.run.call_deferred()


func _exit_tree() -> void:
	Audio.suspended = false
	if engine != null:
		engine.abort = true
		if not pending.is_empty():
			engine.provide_decision(null)


func _process(dt: float) -> void:
	if banner_t > 0.0:
		banner_t -= dt
		if banner_t <= 0.0:
			banner.visible = false


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func():
		_refresh_queued = false
		refresh()).call_deferred()


## Si vedono i segreti di questa fazione?
func can_see(f: String) -> bool:
	return viewer == "" or viewer == f or st.phase == "end"


# =================================================================== costruzione

func _panel(pos: Vector2, sz: Vector2, margin := 14.0) -> PanelContainer:
	var p := UI.panel(margin)
	p.position = pos
	p.size = sz
	p.custom_minimum_size = sz
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _build_top() -> void:
	var p := _panel(Vector2(MX, 8), Vector2(MW, 66), 10)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	top_round = UI.label("", 22, UI.GOLD, UI.font_title)
	top_round.tooltip_text = "Segnalino tempo: avanza di una casella a ogni round. Quando raggiunge la reputazione vincono i Ribelli."
	top_round.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(top_round)
	top_rep = UI.label("", 22, UI.REBEL, UI.font_title)
	top_rep.tooltip_text = "Reputazione ribelle: scende con gli obiettivi completati e con le missioni che la riducono."
	top_rep.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(top_rep)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_phase = UI.label("", 18, UI.HOLO, UI.font_bold)
	top_phase.clip_text = true
	top_phase.custom_minimum_size.x = 120
	top_turn = UI.label("", 17, UI.DIM)
	top_turn.clip_text = true
	top_turn.custom_minimum_size.x = 120
	vb.add_child(top_phase)
	vb.add_child(top_turn)
	hb.add_child(vb)
	var b2d := UI.button("2D", 60, 44, 18)
	b2d.tooltip_text = "Vista dall'alto piatta / vista 3D"
	b2d.pressed.connect(func():
		board.set_flat(not board.flat)
		b2d.text = "3D" if board.flat else "2D")
	hb.add_child(b2d)
	var bc := UI.button("◎", 50, 44, 20)
	bc.tooltip_text = "Rimetti la visuale (anche doppio clic sul tabellone)"
	bc.pressed.connect(board.reset_view)
	hb.add_child(bc)
	var bm := UI.button("♪", 50, 44, 20)
	bm.tooltip_text = "Musica sì/no"
	bm.pressed.connect(func(): Audio.set_music(not Audio.music_enabled()))
	hb.add_child(bm)
	var bmenu := UI.button("Menu", 90, 44, 18)
	bmenu.pressed.connect(_ask_quit)
	hb.add_child(bmenu)


func _build_left() -> void:
	var p := _panel(Vector2(LX, 8), Vector2(LW, 1064), 12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for f in ["R", "I"]:
		var b := UI.button(RBState.fshort(f), 186, 44, 20)
		b.pressed.connect(func():
			tab = f
			refresh())
		tabs.add_child(b)
		tab_btns[f] = b
	vb.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left_box.custom_minimum_size = Vector2(LW - 40, 0)
	sc.add_child(left_box)


func _build_right() -> void:
	info_panel = _panel(Vector2(RX, 8), Vector2(RW, 420), 12)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(sc)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	info_box.custom_minimum_size = Vector2(RW - 40, 0)
	sc.add_child(info_box)
	var lp := _panel(Vector2(RX, 436), Vector2(RW, 636), 12)
	var vb := VBoxContainer.new()
	lp.add_child(vb)
	vb.add_child(UI.title("Cronaca", 20, UI.HOLO))
	log_lbl = RichTextLabel.new()
	log_lbl.bbcode_enabled = true
	log_lbl.scroll_following = true
	log_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_lbl.add_theme_font_size_override("normal_font_size", 16)
	log_lbl.add_theme_font_size_override("bold_font_size", 16)
	log_lbl.add_theme_color_override("default_color", Color("#c9d6e3"))
	vb.add_child(log_lbl)


func _build_decision() -> void:
	dec_panel = UI.panel(16)
	dec_panel.add_theme_stylebox_override("panel", UI.holo(16, UI.HOLO))
	dec_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dec_panel.position = Vector2(MX, 700)
	dec_panel.custom_minimum_size = Vector2(MW, 0)
	add_child(dec_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	dec_panel.add_child(vb)
	dec_title = UI.rich("", 21, MW - 40)
	vb.add_child(dec_title)
	dec_body = VBoxContainer.new()
	dec_body.add_theme_constant_override("separation", 8)
	vb.add_child(dec_body)
	dec_panel.visible = false
	dec_panel.resized.connect(_place_decision)


func _place_decision() -> void:
	var h := minf(dec_panel.size.y, 640.0)
	dec_panel.position = Vector2(MX, 1072 - h)


func _build_banner() -> void:
	banner = UI.panel(14)
	banner.position = Vector2(MX + 80, 86)
	banner.custom_minimum_size = Vector2(MW - 160, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner_box = VBoxContainer.new()
	banner_box.add_theme_constant_override("separation", 6)
	banner.add_child(banner_box)
	banner.visible = false


func show_banner(title: String, rows: Array, secs := 3.5, col := UI.HOLO) -> void:
	for c in banner_box.get_children():
		banner_box.remove_child(c)
		c.queue_free()
	banner.size = Vector2(MW - 160, 0)
	var t := UI.rich("[center]%s[/center]" % title, 21, MW - 200)
	banner_box.add_child(t)
	for r in rows:
		banner_box.add_child(r)
	banner.add_theme_stylebox_override("panel", UI.holo(14, col))
	banner.visible = true
	banner.reset_size()
	banner_t = secs


# =================================================================== aggiornamento

func refresh() -> void:
	if not is_inside_tree():
		return
	board.viewer = viewer
	board.refresh()
	top_round.text = "TEMPO %d" % st.round
	top_rep.text = "REPUTAZIONE %d" % st.rep
	var ph := {"setup": "Preparazione", "assign": "Fase di Assegnazione", "command": "Fase di Comando", "refresh": "Fase di Ripristino", "end": "Partita finita"}
	top_phase.text = "Round %d · %s" % [st.round, ph.get(st.phase, st.phase)]
	if engine.waiting_for != "":
		var who := RBState.fname(engine.waiting_for)
		var you := engine.waiting_for in humans and (viewer == "" or engine.waiting_for == viewer)
		top_turn.text = ("Tocca a te (%s)" % who) if you else ("Sta decidendo: %s" % who)
	else:
		top_turn.text = ""
	for f in tab_btns:
		UI.tint(tab_btns[f], UI.fcolor(f) if tab == f else UI.STEEL_L)
	_refresh_left()
	_refresh_info()


func _section(t: String, col := UI.HOLO) -> void:
	var l := UI.label(t.to_upper(), 16, col, UI.font_title)
	left_box.add_child(l)


func _refresh_left() -> void:
	for c in left_box.get_children():
		c.queue_free()
	var f := tab
	var o := RBState.other(f)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UI.icon_rect(UI.tex("res://assets/tokens/%s.png" % ("lealta_ribelle" if f == "R" else "lealta_imperiale")), Vector2(44, 44)))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -4)
	hv.add_child(UI.title(RBState.fname(f), 22, UI.fcolor(f)))
	var who := "IA" if engine.players[f]["ai"] else ("tu" if f == viewer or humans.size() == 2 else "avversario")
	if online != null:
		who = "tu" if f == online.faction else str(engine.players[f].get("name", "avversario"))
	hv.add_child(UI.label("Giocata da: %s · sistemi fedeli: %d" % [who, _count_loyal(f)], 15, UI.DIM))
	head.add_child(hv)
	left_box.add_child(head)
	# leader in riserva
	var pool := st.leader_pool(f)
	_section("Leader in riserva (%d)" % pool.size())
	left_box.add_child(_leader_grid(pool, 4))
	# missioni assegnate
	if not st.assign[f].is_empty():
		_section("Missioni assegnate")
		for a in st.assign[f]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			if a["rev"] or can_see(f):
				row.add_child(_card_thumb(a["card"], 78))
			else:
				row.add_child(_back_thumb(f, 78))
			var lv := VBoxContainer.new()
			var nm := RB.card_name(a["card"]) if (a["rev"] or can_see(f)) else "Missione coperta"
			lv.add_child(UI.wrap(nm + (" (rivelata)" if a["rev"] else ""), 15, 250, UI.TEXT))
			lv.add_child(_leader_grid(a["leaders"], 3, 54))
			row.add_child(lv)
			left_box.add_child(row)
	# leader sul tabellone
	var on_board := []
	for n in st.leaders:
		var L: Dictionary = st.leaders[n]
		if L["f"] == f and L["st"] == "board":
			on_board.append(n)
	if not on_board.is_empty():
		_section("Leader sul tabellone")
		for n in on_board:
			var L2: Dictionary = st.leaders[n]
			var loc: String = L2["loc"]
			var where := "casella Base" if loc == "BASE" else RB.sys_name(loc)
			var extra := ""
			if L2["ring"] != "":
				extra = " · " + str(RB.RING_IT.get(L2["ring"], L2["ring"]))
			left_box.add_child(UI.label("%s — %s%s" % [RB.leader_it(n), where, extra], 15, UI.TEXT))
	# carte in mano
	if can_see(f):
		_section("Carte missione (%d)" % st.hand[f].size())
		left_box.add_child(_card_grid(st.hand[f], 4))
		if not st.acts[f].is_empty():
			_section("Carte azione (%d)" % st.acts[f].size())
			left_box.add_child(_card_grid(st.acts[f], 4))
		if f == "R":
			_section("Obiettivi (%d)" % st.objs.size(), UI.GOLD)
			left_box.add_child(_card_grid(st.objs, 4))
			if st.base != "":
				left_box.add_child(UI.label("Base ribelle: %s%s" % [RB.sys_name(st.base), " (rivelata)" if st.base_revealed else " (segreta)"], 17, UI.REBEL, UI.font_bold))
		else:
			_section("Carte sonda (%d)" % st.probes.size(), UI.GOLD)
			left_box.add_child(_card_grid(st.probes, 4))
	else:
		_section("Carte coperte")
		var t := "Missioni in mano: %d · carte azione: %d" % [st.hand[f].size(), st.acts[f].size()]
		t += "\n" + ("Obiettivi: %d" % st.objs.size() if f == "R" else "Carte sonda: %d" % st.probes.size())
		left_box.add_child(UI.wrap(t, 16, LW - 40, UI.DIM))
	# tattiche in combattimento
	if not st.tac[f].is_empty() and can_see(f):
		_section("Carte tattica")
		left_box.add_child(_card_grid(st.tac[f], 4))
	# coda di costruzione
	_section("Coda di costruzione")
	for i in 3:
		var q: Array = st.queue[f][i]
		left_box.add_child(UI.wrap("Casella %d: %s" % [i + 1, _types_text(q) if not q.is_empty() else "—"], 15, LW - 40, UI.TEXT))
	var ob: Array = st.obj_play
	if f == "R" and not ob.is_empty():
		_section("Obiettivi in gioco", UI.GOLD)
		var ids := []
		for x in ob:
			ids.append(x if x is String else str(x.get("id", "")) if x is Dictionary else str(x))
		left_box.add_child(_card_grid(ids, 4))
	if o == "":
		pass


func _count_loyal(f: String) -> int:
	var n := 0
	for s in st.sys:
		if f == "R" and st.is_rebel_sys(s):
			n += 1
		elif f == "I" and st.is_imperial_sys(s):
			n += 1
	return n


func _types_text(types: Array) -> String:
	var cnt := {}
	for t in types:
		cnt[t] = cnt.get(t, 0) + 1
	var parts := []
	for t in cnt:
		parts.append("%d %s" % [cnt[t], RB.unit_it(t)])
	return ", ".join(parts)


# =================================================================== carte e leader

func card_img(id: String) -> Texture2D:
	var c := RB.card(id)
	if not c.is_empty():
		return UI.tex(c["img"])
	if RB.PROBES.has(id):
		return UI.tex(RB.PROBES[id]["img"])
	return null


func card_title(id: String) -> String:
	if RB.CARDS.has(id):
		return RB.card_name(id)
	if RB.PROBES.has(id):
		return "Sonda: " + RB.sys_name(id)
	return id


func _card_thumb(id: String, w := 86.0) -> Control:
	var t := card_img(id)
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(w, w * 1.53)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.tooltip_text = ""
	r.mouse_entered.connect(func(): show_zoom(id))
	r.mouse_exited.connect(hide_zoom)
	if t == null:
		var l := UI.wrap(card_title(id), 13, w, UI.TEXT)
		r.add_child(l)
	return r


func _back_thumb(f: String, w := 86.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, w * 1.53)
	p.add_theme_stylebox_override("panel", UI.box(UI.fcolor_d(f), UI.fcolor(f), 2, 6, 4))
	var l := UI.label("?", 40, UI.fcolor(f), UI.font_title)
	l.position = Vector2(w / 2 - 14, w * 0.5)
	p.add_child(l)
	return p


func _card_grid(ids: Array, cols := 4, w := 86.0) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for id in ids:
		g.add_child(_card_thumb(str(id), w))
	return g


func _leader_grid(ls: Array, cols := 4, w := 80.0) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for n in ls:
		g.add_child(_leader_tile(n, w))
	return g


func leader_text(n: String) -> String:
	var L: Dictionary = RB.LEADERS[n]
	var parts := []
	for sk in RB.SKILLS:
		var v := int(L["abilita"][sk])
		if v > 0:
			parts.append("%s %d" % [RB.SKILL_NAME[sk], v])
	var t := RB.leader_it(n) + "\n" + (", ".join(parts) if not parts.is_empty() else "nessuna abilità")
	var tac := []
	if int(L["spazio"]) > 0:
		tac.append("tattica spaziale %d" % int(L["spazio"]))
	if int(L["terra"]) > 0:
		tac.append("tattica terrestre %d" % int(L["terra"]))
	if not tac.is_empty():
		t += "\n" + ", ".join(tac)
	else:
		t += "\nnon può attivare sistemi"
	if st.leaders.has(n) and st.leaders[n]["ring"] != "":
		t += "\nAnello: " + str(RB.RING_IT.get(st.leaders[n]["ring"], st.leaders[n]["ring"]))
	return t


func _leader_tile(n: String, w := 80.0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = leader_text(n)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var f: String = RB.LEADERS[n]["fazione"]
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(UI.fcolor_d(f), UI.fcolor(f), 2, 4, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var img := UI.icon_rect(UI.leader_tex(n), Vector2(w, w * 1.15))
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(img)
	box.add_child(frame)
	var L: Dictionary = RB.LEADERS[n]
	var sk := ""
	for k in RB.SKILLS:
		var v := int(L["abilita"][k])
		if v > 0:
			sk += "[color=#%s]%s[/color]" % [UI.SKILL_COLOR[k].to_html(false), "●".repeat(v)]
	var tac := ""
	if int(L["spazio"]) > 0 or int(L["terra"]) > 0:
		tac = " [color=#9fb4c8]%d/%d[/color]" % [int(L["spazio"]), int(L["terra"])]
	var r := UI.rich("[center]%s%s[/center]" % [sk, tac], 13, w)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(r)
	return box


## Carta ingrandita al centro del tabellone, con il testo italiano accanto.
func show_zoom(id: String) -> void:
	hide_zoom()
	var t := card_img(id)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if t != null:
		var r := UI.icon_rect(t, Vector2(330, 505))
		hb.add_child(r)
	var c := RB.card(id)
	if not c.is_empty():
		var p := UI.panel(14)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		p.add_child(vb)
		vb.add_child(UI.wrap(str(c["nome"]), 22, 340, UI.GOLD))
		var tipo := {"missione": "Missione", "azione": "Carta azione", "obiettivo": "Obiettivo", "tattica": "Carta tattica", "tattica_av": "Tattica avanzata"}
		var sub := str(tipo.get(c["tipo"], c["tipo"]))
		if c.has("abilita") and c["abilita"] != null and str(c["abilita"]) != "":
			sub += " · %s %s" % [RB.SKILL_NAME.get(str(c["abilita"]), str(c["abilita"])), str(int(c["livello"])) if c.get("livello") != null else ""]
		if c.get("ritratto") != null:
			sub += " · ritratto: " + RB.leader_it(str(c["ritratto"]))
		if c.has("stadio"):
			sub += " · stadio " + str(c["stadio"])
		if c.get("set", "") == "rote":
			sub += " · L'Ascesa dell'Impero"
		vb.add_child(UI.wrap(sub, 15, 340, UI.DIM))
		var rt := UI.rich(UI.card_text(str(c["testo"])), 18, 340)
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(rt)
		hb.add_child(p)
	elif RB.PROBES.has(id):
		hb.add_child(UI.label(card_title(id), 22, UI.GOLD))
	hb.position = Vector2(MX + 60, 120)
	zoom_layer.add_child(hb)


func hide_zoom() -> void:
	for c in zoom_layer.get_children():
		c.queue_free()


# =================================================================== dettaglio del sistema

func _on_system_clicked(s: String) -> void:
	info_sys = s
	_refresh_info()


func _refresh_info() -> void:
	for c in info_box.get_children():
		c.queue_free()
	var s := info_sys
	if s == "":
		info_box.add_child(UI.title("Galassia", 20, UI.HOLO))
		info_box.add_child(UI.wrap("Clic su un sistema per vederne le unità, i leader e la fedeltà.\nTrascina per ruotare, rotella per lo zoom, tasto destro per spostare.", 16, RW - 40, UI.DIM))
		_objective_summary()
		return
	if s == "BASE":
		info_box.add_child(UI.title("Casella Base Ribelle", 20, UI.REBEL))
		if can_see("R") and st.base != "":
			info_box.add_child(UI.label("Sistema: " + RB.sys_name(st.base), 17, UI.REBEL))
	else:
		var d: Dictionary = RB.SYS[s]
		var info: Dictionary = st.sys[s]
		info_box.add_child(UI.title(RB.sys_name(s), 22, UI.HOLO))
		var loy := "neutrale"
		if info["dest"]:
			loy = "DISTRUTTO"
		elif info["subj"]:
			loy = "sottomesso all'Impero"
		elif info["loy"] == "R":
			loy = "fedele ai Ribelli"
		elif info["loy"] == "I":
			loy = "fedele all'Impero"
		var kind := "popolato" if d["popolato"] else "remoto"
		info_box.add_child(UI.wrap("%s · %s · %s%s" % [kind, loy, RB.REGION_NAME.get(int(d["regione"]), ""), " · sabotato" if info["sab"] else ""], 16, RW - 40, UI.DIM))
		if not d["icone"].is_empty():
			info_box.add_child(UI.wrap("Risorse: %s (coda %d)" % [_icons_text(d["icone"]), int(d["coda"])], 15, RW - 40, UI.TEXT))
		var adj := []
		for a in d["adiacenti"]:
			adj.append(RB.sys_name(a))
		info_box.add_child(UI.wrap("Adiacenti: " + ", ".join(adj), 14, RW - 40, UI.DIM))
		if st.base == s and can_see("R"):
			info_box.add_child(UI.label("Qui c'è la base ribelle", 17, UI.REBEL, UI.font_bold))
	for f in ["R", "I"]:
		var ids := st.units_at(s, f)
		if ids.is_empty():
			continue
		info_box.add_child(UI.label(RBState.fname(f), 17, UI.fcolor(f), UI.font_bold))
		var cnt := {}
		var dmg := {}
		for id in ids:
			var t: String = st.units[id]["t"]
			cnt[t] = cnt.get(t, 0) + 1
			dmg[t] = dmg.get(t, 0) + int(st.units[id]["dmg"])
		for t in cnt:
			var u: Dictionary = RB.UNITS[t]
			var line := "%d × %s  [color=#9fb4c8](salute %d %s, dadi %s)[/color]" % [cnt[t], RB.unit_it(t), int(u["salute"]), "rossa" if u["colore_salute"] == "rosso" else "nera", _dice_desc(u)]
			if dmg[t] > 0:
				line += " [color=#ff8a7a]danni %d[/color]" % dmg[t]
			info_box.add_child(UI.rich(line, 15, RW - 40))
	var ls := st.leaders_at(s, "R") + st.leaders_at(s, "I")
	var caps := st.captured_at(s)
	for n in caps:
		if not n in ls:
			ls.append(n)
	if not ls.is_empty():
		info_box.add_child(UI.label("Leader", 17, UI.GOLD, UI.font_bold))
		info_box.add_child(_leader_grid(ls, 4, 66))


func _objective_summary() -> void:
	info_box.add_child(UI.hsep())
	info_box.add_child(UI.label("Obiettivi ribelli: %d in mano" % st.objs.size(), 16, UI.GOLD))
	info_box.add_child(UI.label("Carte sonda dell'Impero: %d" % st.probes.size(), 16, UI.EMPIRE))
	if engine.rote() and engine.cinematic():
		info_box.add_child(UI.label("Combattimento cinematografico", 15, UI.DIM))


func _icons_text(ic: Array) -> String:
	var names := {"OT": "triangolo arancio", "OS": "quadrato arancio", "OC": "cerchio arancio", "BT": "triangolo blu", "BS": "quadrato blu", "BC": "cerchio blu"}
	var out := []
	for i in ic:
		out.append(str(names.get(i, i)))
	return ", ".join(out)


func _dice_desc(u: Dictionary) -> String:
	var parts := []
	if int(u["rossi"]) > 0:
		parts.append("%d rossi" % int(u["rossi"]))
	if int(u["neri"]) > 0:
		parts.append("%d neri" % int(u["neri"]))
	if int(u.get("verdi", 0)) > 0:
		parts.append("%d verdi" % int(u["verdi"]))
	return ", ".join(parts) if not parts.is_empty() else "nessuno"


# =================================================================== cronaca

func _on_log(t: String) -> void:
	if online != null and online.catchup:
		return
	log_lbl.append_text(_hide_secrets(t) + "\n")


## Nella cronaca il nome del sistema della base non compare a chi non deve saperlo.
func _hide_secrets(t: String) -> String:
	return t


# =================================================================== effetti

func _on_fx(kind: String, d: Dictionary) -> void:
	match kind:
		"move":
			board.flash(str(d["to"]), Color(0.5, 0.8, 1.0, 0.6), 1.0, 0.7)
			Audio.play("hyper", -8.0)
		"leader":
			Audio.play("beep", -6.0)
		"combat_start":
			board.highlight[str(d["sys"])] = Color(1, 0.3, 0.2, 0.9)
			board.look_at_system(str(d["sys"]), 12.0)
			Audio.play("alarm", -10.0)
			show_banner("[b]Combattimento a %s[/b]" % RB.sys_name(str(d["sys"])), [], 2.5, UI.BAD)
		"combat_end":
			board.highlight.erase(str(d["sys"]))
			board.refresh()
		"battle":
			pass
		"combat_dice":
			var f: String = d["f"]
			show_banner("%s tira (%s)" % [RBState.fname(f), "spazio" if d["th"] == "spazio" else "terra"], [_dice_row(d["dice"])], 3.0, UI.fcolor(f))
			Audio.play("dice")
		"damage":
			Audio.play("blaster", -4.0)
		"destroy":
			board.flash(str(d["sys"]), Color(1.0, 0.55, 0.2, 0.8), 1.2, 0.9)
			Audio.play("explosion", -6.0)
		"deathstar_boom", "superlaser":
			board.flash(str(d["sys"]), Color(0.4, 1.0, 0.4, 0.9), 2.5, 1.6)
			Audio.play("explosion")
			show_banner("[b]%s[/b]" % ("Il superlaser distrugge %s!" % RB.sys_name(str(d["sys"])) if kind == "superlaser" else "La Morte Nera esplode!"), [], 3.5, UI.GOOD)
		"base":
			board.flash(str(d["sys"]), Color(1, 0.3, 0.2, 0.9), 2.0, 1.4)
			board.look_at_system(str(d["sys"]), 12.0)
			Audio.play("alarm")
			show_banner("[b]La base ribelle è su %s![/b]" % RB.sys_name(str(d["sys"])), [], 4.0, UI.REBEL)
		"newbase":
			Audio.play("hyper")
		"capture":
			Audio.play("capture")
			show_banner("%s è stato catturato!" % RB.leader_it(str(d["n"])), [], 2.5, UI.EMPIRE)
		"rescue":
			Audio.play("success", -4.0)
			show_banner("%s è libero!" % RB.leader_it(str(d["n"])), [], 2.5, UI.REBEL)
		"mission_dice":
			var c: String = d["card"]
			var ok: bool = int(d["a"]) > int(d["o"])
			var rows := [_dice_row(d["mine"], "Tentativo: %d successi" % int(d["a"]))]
			if not (d["theirs"] as Array).is_empty():
				rows.append(_dice_row(d["theirs"], "Opposizione: %d successi" % int(d["o"])))
			show_banner("%s · %s" % [RB.card_name(c), "[color=#71e38d]RIUSCITA[/color]" if ok else "[color=#ff6b5e]FALLITA[/color]"], rows, 3.5, UI.fcolor(str(d["f"])))
			Audio.play("dice")
			Audio.play("success" if ok else "fail", -6.0)
		"dice":
			show_banner("Dadi", [_dice_row(d["dice"])], 3.0)
			Audio.play("dice")
		"card":
			var f2: String = d.get("f", "")
			Audio.play("card")
			if f2 != viewer and RB.CARDS.has(str(d["id"])):
				show_banner("%s gioca «%s»" % [RBState.fname(f2), RB.card_name(str(d["id"]))], [], 3.0, UI.fcolor(f2))
		"time":
			Audio.play("turn", -6.0)
		"rep":
			Audio.play("beep", -6.0)
	refresh()


## Riga di dadi colorati con il simbolo della faccia.
func _dice_row(dice: Array, label := "") -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	if label != "":
		hb.add_child(UI.label(label + "  ", 17, UI.TEXT))
	for d in dice:
		var v := 0
		var col := "rosso"
		var spent := false
		if d is Dictionary:
			v = int(d["v"])
			col = str(d.get("c", "rosso"))
			spent = d.get("spent", false)
		else:
			v = int(d)
			col = "nero"
		hb.add_child(_die(col, v, spent))
	return hb


func _die(col: String, v: int, spent := false) -> Control:
	var p := PanelContainer.new()
	var bg := Color("#a8261c") if col == "rosso" else (Color("#2b8a3e") if col == "verde" else Color("#202428"))
	p.add_theme_stylebox_override("panel", UI.box(bg, Color(1, 1, 1, 0.5), 1, 6, 2))
	p.custom_minimum_size = Vector2(40, 40)
	var g: String = ["", "✸", "✸✸", "✦"][clampi(v, 0, 3)]
	var l := UI.label(g, 18 if v == 2 else 22, Color("#ffe6a0"), UI.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.tooltip_text = ["vuoto", "colpo", "colpo diretto", "speciale"][clampi(v, 0, 3)]
	if spent:
		p.modulate = Color(1, 1, 1, 0.35)
	return p


# =================================================================== decisioni

func _on_decision(req: Dictionary) -> void:
	var f: String = req["f"]
	if humans.size() == 2 and online == null and f != viewer:
		await _curtain(f)
		if not is_inside_tree():
			return
	_last_f = f
	pending = req
	sel = []
	Audio.play("beep", -10.0)
	refresh()
	_render()


func _curtain(f: String) -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 1.0)
	shade.size = layer.size
	layer.add_child(shade)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	vb.position = Vector2(560, 380)
	vb.custom_minimum_size = Vector2(800, 0)
	layer.add_child(vb)
	var t := UI.title("Tocca a: " + RBState.fname(f), 46, UI.fcolor(f))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var l := UI.wrap("Passa il dispositivo: le carte e i segreti dell'altra fazione sono nascosti.", 22, 800, UI.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var b := UI.tint(UI.button("Sono pronto", 0, 70, 28), UI.fcolor(f))
	vb.add_child(b)
	viewer = ""
	viewer = f
	tab = f
	refresh()
	await b.pressed
	layer.queue_free()


func _clear_body() -> void:
	for c in dec_body.get_children():
		dec_body.remove_child(c)
		c.queue_free()
	dec_panel.visible = false
	dec_panel.size = Vector2(MW, 0)
	board.clear_targets()
	target_cb.clear()


func _answer(r) -> void:
	if pending.is_empty():
		return
	pending = {}
	sel = []
	_clear_body()
	hide_zoom()
	engine.provide_decision(r)


func _render() -> void:
	_clear_body()
	var req := pending
	if req.is_empty():
		return
	dec_panel.visible = true
	dec_panel.add_theme_stylebox_override("panel", UI.holo(16, UI.fcolor(req["f"])))
	var head := "[color=#%s][b]%s[/b][/color] · %s" % [UI.fcolor(req["f"]).to_html(false), RBState.fshort(req["f"]), req.get("t", "")]
	dec_title.text = head
	match str(req["k"]):
		"choice":
			_r_choice(req)
		"system":
			_r_system(req)
		"systems":
			_r_systems(req)
		"leaders":
			_r_leaders(req)
		"cards":
			_r_cards(req)
		"units", "move":
			_r_units(req)
		"place":
			_r_place(req)
		"damage":
			_r_damage(req)
		"dice_pick":
			_r_dice_pick(req)
		"order":
			_r_order(req)
		"queue_pick":
			_r_queue_pick(req)
		_:
			var b := UI.button("Continua (IA)", 260, 46)
			b.pressed.connect(func(): _answer(engine.ais[req["f"]].decide(engine, req["f"], req)))
			dec_body.add_child(b)
	dec_panel.reset_size()
	(func():
		dec_panel.reset_size()
		_place_decision()).call_deferred()


func _row() -> HFlowContainer:
	var r := HFlowContainer.new()
	r.add_theme_constant_override("h_separation", 8)
	r.add_theme_constant_override("v_separation", 8)
	r.custom_minimum_size = Vector2(MW - 40, 0)
	dec_body.add_child(r)
	return r


func _confirm_row(cb: Callable, text := "Conferma", extra: Array = []) -> Button:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	for e in extra:
		hb.add_child(e)
	var b := UI.primary(UI.button(text, 220, 50, 21))
	b.pressed.connect(cb)
	hb.add_child(b)
	dec_body.add_child(hb)
	return b


func _ai_button(req: Dictionary) -> Button:
	var b := UI.button("Scelta automatica", 0, 50, 18)
	b.tooltip_text = "Lascia scegliere all'IA"
	b.pressed.connect(func(): _answer(engine.ais[req["f"]].decide(engine, req["f"], req)))
	return b


## Scelta fra opzioni: le carte come miniature, il resto come pulsanti.
func _r_choice(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	# la carta di cui si parla (es. abilità delle tattiche avanzate), con il testo
	if req.has("card") and RB.CARDS.has(str(req["card"])):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		hb.add_child(_card_thumb(str(req["card"]), 80))
		var cc := RB.card(str(req["card"]))
		var txt := str(cc["testo"])
		if cc.has("sopra"):
			txt = "[b]In alto[/b]%s: %s\n[b]In basso[/b]%s: %s" % [_req_unit(cc.get("sopra_unita")), cc["sopra"], _req_unit(cc.get("sotto_unita")), cc["sotto"]]
		hb.add_child(UI.rich(UI.card_text(txt), 17, MW - 160))
		dec_body.add_child(hb)
	var with_card := []
	var plain := []
	for o in opts:
		if o.has("card"):
			with_card.append(o)
		else:
			plain.append(o)
	if not with_card.is_empty():
		var r := _row()
		for o in with_card:
			var v = o["v"]
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 2)
			var th := _card_thumb(str(o["card"]), 100)
			th.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_answer(v))
			vb.add_child(th)
			var lb := UI.button(_short(str(o["l"])), 100, 34, 13)
			lb.tooltip_text = str(o["l"])
			lb.clip_text = true
			lb.pressed.connect(func(): _answer(v))
			vb.add_child(lb)
			r.add_child(vb)
	if not plain.is_empty():
		var r2 := _row()
		var sys_keys := []
		for o in plain:
			var v2 = o["v"]
			var b := UI.button(UI.plain_text(str(o["l"])), 0, 48, 19)
			if o.has("d"):
				b.tooltip_text = UI.plain_text(str(o["d"]))
			if o.has("unit") and st.units.has(int(o["unit"])):
				b.icon = UI.unit_icon(st.units[int(o["unit"])]["t"])
				b.expand_icon = false
			if str(v2) in ["pass", "done", "false"] or v2 == null:
				UI.tint(b, UI.STEEL_L)
			elif plain.size() <= 4:
				UI.primary(b)
			b.pressed.connect(func(): _answer(v2))
			r2.add_child(b)
			if o.has("sys"):
				var s: String = o["sys"]
				sys_keys.append(s)
				target_cb[s] = func(): _answer(v2)
		if not sys_keys.is_empty():
			board.set_targets(sys_keys)


func _req_unit(v) -> String:
	if v == null or str(v) == "":
		return ""
	var names := []
	for t in str(v).split(" OR "):
		names.append(RB.unit_it(t.strip_edges()))
	return " (serve: %s)" % " o ".join(names)


func _short(t: String) -> String:
	for p in ["Assegna: ", "Usa carta azione: ", "Rivela: "]:
		if t.begins_with(p):
			return {"Assegna: ": "Assegna", "Usa carta azione: ": "Usa", "Rivela: ": "Rivela"}[p]
	return t


## Scelta di un sistema: sul tabellone o dall'elenco.
func _r_system(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	board.set_targets(opts)
	for s in opts:
		var s2: String = s
		target_cb[s2] = func(): _answer(s2)
	dec_body.add_child(UI.label("Clic su un sistema illuminato oppure scegli dall'elenco:", 16, UI.DIM))
	var r := _row()
	var sorted := opts.duplicate()
	sorted.sort_custom(func(a, b): return _sname(a) < _sname(b))
	for s in sorted:
		var s3: String = s
		var b := UI.button(_sname(s3), 0, 40, 17)
		b.pressed.connect(func(): _answer(s3))
		b.mouse_entered.connect(func(): info_sys = s3; _refresh_info())
		r.add_child(b)
	if req.get("none", false):
		var bn := UI.tint(UI.button("Nessuno / rinuncia", 0, 40, 17), UI.STEEL_L)
		bn.pressed.connect(func(): _answer(""))
		r.add_child(bn)


func _sname(s: String) -> String:
	return "Casella Base Ribelle" if s == "BASE" else RB.sys_name(s)


func _on_target(k: String) -> void:
	if target_cb.has(k):
		var cb: Callable = target_cb[k]
		cb.call()
	else:
		_on_system_clicked(k)


## Più sistemi (min..max).
func _r_systems(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 1))
	var mx := int(req.get("max", 1))
	var btns := {}
	var status := UI.label("", 17, UI.DIM)
	var paint := func():
		for s in btns:
			UI.tint(btns[s], UI.HOLO if s in sel else UI.STEEL_L)
		board.set_targets(opts, "", _sel_labels())
		status.text = "Scelti %d (da %d a %d)" % [sel.size(), mn, mx]
	var toggle := func(s: String):
		if s in sel:
			sel.erase(s)
		elif sel.size() < mx:
			sel.append(s)
		paint.call()
	var r := _row()
	var sorted := opts.duplicate()
	sorted.sort_custom(func(a, b): return _sname(a) < _sname(b))
	for s in sorted:
		var s2: String = s
		var b := UI.button(_sname(s2), 0, 40, 17)
		b.pressed.connect(func(): toggle.call(s2))
		r.add_child(b)
		btns[s2] = b
		target_cb[s2] = func(): toggle.call(s2)
	dec_body.add_child(status)
	_confirm_row(func():
		if sel.size() >= mn:
			_answer(sel.duplicate()), "Conferma", [_ai_button(req)])
	paint.call()


func _sel_labels() -> Dictionary:
	var d := {}
	for i in sel.size():
		d[sel[i]] = "✓"
	return d


## Scelta di leader (ritratti selezionabili).
func _r_leaders(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 1))
	var mx := int(req.get("max", 1))
	if req.has("card"):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		hb.add_child(_card_thumb(str(req["card"]), 90))
		var c := RB.card(str(req["card"]))
		if not c.is_empty():
			hb.add_child(UI.rich(UI.card_text(str(c["testo"])), 16, MW - 180))
		dec_body.add_child(hb)
	var tiles := {}
	var status := UI.label("", 17, UI.DIM)
	var paint := func():
		for n in tiles:
			var t: Control = tiles[n]
			t.modulate = Color(1, 1, 1) if n in sel else Color(0.6, 0.65, 0.7)
			t.get_child(0).add_theme_stylebox_override("panel", UI.box(UI.HOLO_D if n in sel else UI.PANEL2, UI.HOLO if n in sel else UI.STEEL, 2, 4, 6))
		status.text = "Scelti %d (da %d a %d)%s" % [sel.size(), mn, mx, _skill_hint(req)]
	var r := _row()
	for n in opts:
		var n2: String = n
		var wrap := VBoxContainer.new()
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		pc.add_child(_leader_tile(n2, 86))
		wrap.add_child(pc)
		var nm := UI.label(RB.leader_it(n2), 13, UI.TEXT)
		nm.custom_minimum_size.x = 96
		nm.clip_text = true
		wrap.add_child(nm)
		pc.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if n2 in sel:
					sel.erase(n2)
				elif mx == 1:
					sel = [n2]
				elif sel.size() < mx:
					sel.append(n2)
				paint.call())
		r.add_child(wrap)
		tiles[n2] = wrap
	dec_body.add_child(status)
	var extra := [_ai_button(req)]
	if mn == 0 or req.get("confirm", false):
		var bc := UI.tint(UI.button("Annulla", 0, 50, 18), UI.STEEL_L)
		bc.pressed.connect(func(): _answer([]))
		if mn == 0 or str(req.get("ctx", "")) == "assign_leaders":
			extra.append(bc)
	_confirm_row(func():
		if sel.size() >= mn:
			_answer(sel.duplicate()), "Conferma", extra)
	paint.call()


## Per l'assegnazione mostra le icone dell'abilità richiesta dalla missione.
func _skill_hint(req: Dictionary) -> String:
	if not req.has("card"):
		return ""
	var c := RB.card(str(req["card"]))
	var sk := str(c.get("abilita", ""))
	if sk == "" or not RB.SKILL_NAME.has(sk):
		return ""
	var tot := 0
	for n in sel:
		tot += RB.leader_skill(n, sk)
	return " · %s: %d" % [RB.SKILL_NAME[sk], tot]


## Scelta di carte (min..max).
func _r_cards(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 1))
	var mx := int(req.get("max", 1))
	var thumbs := {}
	var status := UI.label("", 17, UI.DIM)
	var paint := func():
		for id in thumbs:
			(thumbs[id] as Control).modulate = Color(1, 1, 1) if id in sel else Color(0.55, 0.6, 0.65)
		status.text = "Scelte %d (da %d a %d)" % [sel.size(), mn, mx]
	var r := _row()
	for id in opts:
		var id2 := str(id)
		var th := _card_thumb(id2, 100)
		th.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if id2 in sel:
					sel.erase(id2)
				elif mx == 1:
					sel = [id2]
				elif sel.size() < mx:
					sel.append(id2)
				paint.call())
		r.add_child(th)
		thumbs[id2] = th
	dec_body.add_child(status)
	_confirm_row(func():
		if sel.size() >= mn:
			_answer(sel.duplicate()), "Conferma", [_ai_button(req)])
	paint.call()


func _unit_label(id: int) -> String:
	var u: Dictionary = st.units[id]
	var t := RB.unit_it(u["t"])
	if int(u["dmg"]) > 0:
		t += " (danni %d)" % int(u["dmg"])
	return t


## Scelta di unità (anche il movimento): raggruppate per sistema di partenza.
func _r_units(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 0 if req["k"] == "move" else 1))
	var mx := int(req.get("max", opts.size()))
	var is_move: bool = req["k"] == "move"
	var by_loc := {}
	for id in opts:
		var iid := int(id)
		if not st.units.has(iid):
			continue
		var loc: String = st.units[iid]["loc"]
		if not by_loc.has(loc):
			by_loc[loc] = []
		by_loc[loc].append(iid)
	if is_move:
		board.set_targets([req["target"]], req["target"])
		board.look_at_system(str(req["target"]), 15.0)
	var btns := {}
	var status := UI.rich("", 16, MW - 40)
	var paint := func():
		for id in btns:
			UI.tint(btns[id], UI.fcolor(req["f"]) if id in sel else UI.STEEL_L)
		var t := "Scelte %d" % sel.size()
		if is_move:
			var ok := engine.valid_move(sel, req)
			if ok.size() < sel.size():
				t += " · [color=#ff8a7a]%d non possono muoversi (trasporto o limiti della carta)[/color]" % (sel.size() - ok.size())
		elif req.has("dmg"):
			t += " · %d dann%s ciascuna" % [int(req["dmg"]), "o" if int(req["dmg"]) == 1 else "i"]
		status.text = t
	for loc in by_loc:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var ll := UI.label(_sname(loc) + ":", 16, UI.HOLO, UI.font_bold)
		ll.custom_minimum_size = Vector2(170, 0)
		hb.add_child(ll)
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 6)
		fl.add_theme_constant_override("v_separation", 6)
		fl.custom_minimum_size = Vector2(MW - 230, 0)
		var ids: Array = by_loc[loc]
		ids.sort_custom(func(a, b): return RB.health(st.units[a]["t"]) > RB.health(st.units[b]["t"]))
		for id in ids:
			var id2: int = id
			var b := UI.button(_unit_label(id2), 0, 38, 15)
			var ic := UI.unit_icon(st.units[id2]["t"])
			if ic != null:
				b.icon = ic
				b.expand_icon = false
				b.add_theme_constant_override("icon_max_width", 26)
			b.pressed.connect(func():
				if id2 in sel:
					sel.erase(id2)
				elif mx == 1:
					sel = [id2]
				elif sel.size() < mx:
					sel.append(id2)
				paint.call())
			fl.add_child(b)
			btns[id2] = b
		hb.add_child(fl)
		dec_body.add_child(hb)
		if is_move:
			var all := UI.button("tutte da " + _sname(loc), 0, 32, 14)
			all.pressed.connect(func():
				for id3 in by_loc[loc]:
					if not id3 in sel and sel.size() < mx:
						sel.append(id3)
				paint.call())
			hb.add_child(all)
	dec_body.add_child(status)
	var extra := [_ai_button(req)]
	if mn == 0:
		var bn := UI.tint(UI.button("Nessuna", 0, 50, 18), UI.STEEL_L)
		bn.pressed.connect(func(): _answer([]))
		extra.append(bn)
	_confirm_row(func():
		if sel.size() >= mn:
			_answer(sel.duplicate()), "Sposta" if is_move else "Conferma", extra)
	paint.call()


## Disposizione iniziale delle unità.
func _r_place(req: Dictionary) -> void:
	var units: Dictionary = req["units"]
	var allowed: Array = req["opts"]
	if place_state.get("ctx", "") != req["ctx"]:
		place_state = {"ctx": req["ctx"], "pl": {}, "cur": allowed[0] if req["f"] == "I" else "BASE"}
	var pl: Dictionary = place_state["pl"]
	var left := units.duplicate()
	for s in pl:
		for t in pl[s]:
			left[t] = int(left[t]) - 1
	var cur: String = place_state["cur"]
	var help := "Scegli un sistema (sul tabellone o dall'elenco), poi aggiungi o togli unità con + e −."
	if req.has("need_ground"):
		help += " Serve almeno 1 unità terrestre in ogni sistema imperiale."
	if req.get("one_system", false):
		help += " Oltre alla casella Base Ribelle puoi usare UN solo sistema."
	dec_body.add_child(UI.wrap(help, 16, MW - 40, UI.DIM))
	board.set_targets(allowed, cur, _place_labels(pl))
	for s in allowed:
		var s2: String = s
		target_cb[s2] = func():
			place_state["cur"] = s2
			_render()
	var r := _row()
	for s in allowed:
		var s3: String = s
		var n := (pl.get(s3, []) as Array).size()
		var b := UI.button("%s%s" % [_sname(s3), " (%d)" % n if n > 0 else ""], 0, 36, 15)
		UI.tint(b, UI.fcolor(req["f"]) if s3 == cur else (UI.HOLO_D if n > 0 else UI.STEEL_L))
		b.pressed.connect(func():
			place_state["cur"] = s3
			_render())
		r.add_child(b)
	dec_body.add_child(UI.label("In %s:" % _sname(cur), 18, UI.HOLO, UI.font_bold))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for t in units:
		var t2: String = t
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		var here := 0
		for x in pl.get(cur, []):
			if x == t2:
				here += 1
		var lbl := UI.label("%s: %d  (da mettere %d)" % [RB.unit_it(t2), here, int(left[t2])], 15, UI.TEXT)
		lbl.custom_minimum_size = Vector2(250, 0)
		var minus := UI.button("−", 34, 32, 18)
		minus.disabled = here == 0
		minus.pressed.connect(func():
			(pl[cur] as Array).erase(t2)
			_render())
		var plus := UI.button("+", 34, 32, 18)
		plus.disabled = int(left[t2]) <= 0
		plus.pressed.connect(func():
			if not pl.has(cur):
				pl[cur] = []
			(pl[cur] as Array).append(t2)
			_render())
		hb.add_child(minus)
		hb.add_child(plus)
		hb.add_child(lbl)
		grid.add_child(hb)
	dec_body.add_child(grid)
	var rest := 0
	for t in left:
		rest += int(left[t])
	var auto := UI.button("Disposizione automatica", 0, 50, 18)
	auto.pressed.connect(func():
		var a := RBAI.auto_place(engine, req["f"], units, allowed, req.get("need_ground", []))
		place_state["pl"] = a.duplicate(true)
		_render())
	var clear := UI.tint(UI.button("Svuota", 0, 50, 18), UI.STEEL_L)
	clear.pressed.connect(func():
		place_state["pl"] = {}
		_render())
	var err := _place_error(req, pl, rest)
	var st_lbl := UI.label(err if err != "" else "Tutto a posto: conferma.", 16, UI.BAD if err != "" else UI.GOOD)
	dec_body.add_child(st_lbl)
	var conf := _confirm_row(func():
		if _place_error(req, pl, rest) == "":
			var out := {}
			for s in pl:
				if not (pl[s] as Array).is_empty():
					out[s] = (pl[s] as Array).duplicate()
			place_state = {}
			_answer(out), "Conferma", [auto, clear])
	conf.disabled = err != ""


func _place_labels(pl: Dictionary) -> Dictionary:
	var d := {}
	for s in pl:
		if not (pl[s] as Array).is_empty():
			d[s] = str((pl[s] as Array).size())
	return d


func _place_error(req: Dictionary, pl: Dictionary, rest: int) -> String:
	if rest > 0:
		return "Restano %d unità da disporre." % rest
	for s in req.get("need_ground", []):
		var g := false
		for t in pl.get(s, []):
			if RB.is_ground(t):
				g = true
		if not g:
			return "Manca un'unità terrestre in %s." % RB.sys_name(s)
	if req.get("one_system", false):
		var used := 0
		for s in pl:
			if s != "BASE" and not (pl[s] as Array).is_empty():
				used += 1
		if used > 1:
			return "Oltre alla Base puoi usare un solo sistema."
	return ""


## Assegnazione dei danni dei dadi: per ogni dado utile si sceglie l'unità colpita.
func _r_damage(req: Dictionary) -> void:
	var dice: Array = req["dice"]
	var targets: Array = req["opts"]
	if dmg_state.get("key", null) != req.hash():
		var auto = engine.ais[req["f"]].decide(engine, req["f"], req)
		dmg_state = {"key": req.hash(), "a": auto if auto is Dictionary else {}}
	var a: Dictionary = dmg_state["a"]
	dec_body.add_child(UI.wrap("I colpi (✸) vanno solo alle unità con salute del colore del dado; i colpi diretti (✸✸) a qualsiasi unità. Già proposta l'assegnazione dell'IA: cambiala se vuoi.", 16, MW - 40, UI.DIM))
	var pend: Dictionary = req.get("pending", {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for i in dice.size():
		var d: Dictionary = dice[i]
		var v := int(d["v"])
		if d.get("spent", false) or not (v == 1 or v == 2):
			continue
		grid.add_child(_die(str(d["c"]), v))
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(420, 40)
		ob.add_theme_font_size_override("font_size", 16)
		ob.add_item("— nessuna —", -1)
		var idx := 1
		var selected := 0
		for id in targets:
			var iid := int(id)
			if not engine.combat._can_take(d, iid):
				continue
			var u: Dictionary = st.units[iid]
			var extra := int(pend.get(iid, 0))
			ob.add_item("%s (salute %d, danni %d)" % [RB.unit_it(u["t"]), RB.health(u["t"]), int(u["dmg"]) + extra], iid)
			if a.has(i) and int(a[i]) == iid:
				selected = idx
			idx += 1
		ob.select(selected)
		var i2 := i
		ob.item_selected.connect(func(k):
			var id_sel := ob.get_item_id(k)
			if id_sel < 0:
				a.erase(i2)
			else:
				a[i2] = id_sel)
		grid.add_child(ob)
	dec_body.add_child(grid)
	_confirm_row(func():
		var out: Dictionary = (dmg_state["a"] as Dictionary).duplicate()
		dmg_state = {}
		_answer(out), "Assegna i danni")


## Dadi da ritirare.
func _r_dice_pick(req: Dictionary) -> void:
	var dice: Array = req["dice"]
	var opts: Array = req["opts"]
	var mx := int(req.get("max", 1))
	var r := _row()
	var boxes := {}
	var paint := func():
		for i in boxes:
			(boxes[i] as Control).modulate = Color(1, 1, 1) if i in sel else Color(0.5, 0.5, 0.5)
	for i in opts:
		var i2 := int(i)
		var d: Dictionary = dice[i2]
		var die := _die(str(d["c"]), int(d["v"]))
		die.mouse_filter = Control.MOUSE_FILTER_STOP
		die.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if i2 in sel:
					sel.erase(i2)
				elif sel.size() < mx:
					sel.append(i2)
				paint.call())
		r.add_child(die)
		boxes[i2] = die
	dec_body.add_child(UI.label("Clic sui dadi da ritirare (al massimo %d)." % mx, 16, UI.DIM))
	_confirm_row(func(): _answer(sel.duplicate()), "Ritira", [_ai_button(req)])
	paint.call()


## Ordine di carte: si cliccano nell'ordine voluto (la prima va in cima).
func _r_order(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var r := _row()
	for id in opts:
		var id2 := str(id)
		var vb := VBoxContainer.new()
		var th := _card_thumb(id2, 100)
		var pos := sel.find(id2)
		var lab := UI.label("%d°" % (pos + 1) if pos >= 0 else "—", 18, UI.GOLD if pos >= 0 else UI.DIM, UI.font_title)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		th.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if id2 in sel:
					sel.erase(id2)
				else:
					sel.append(id2)
				_render())
		vb.add_child(th)
		vb.add_child(lab)
		r.add_child(vb)
	dec_body.add_child(UI.label("Clic sulle carte nell'ordine voluto: le scelte vanno in cima, le altre in fondo.", 16, UI.DIM))
	_confirm_row(func(): _answer(sel.duplicate()), "Conferma", [_ai_button(req)])


## Unità della coda di costruzione (indici).
func _r_queue_pick(req: Dictionary) -> void:
	var opts: Array = req["opts"]
	var mx := int(req.get("max", opts.size()))
	var btns := {}
	var paint := func():
		for i in btns:
			UI.tint(btns[i], UI.HOLO if i in sel else UI.STEEL_L)
	var r := _row()
	for i in opts.size():
		var i2 := i
		var t := str(opts[i])
		var b := UI.button(RB.unit_it(t) if RB.UNITS.has(t) else t, 0, 40, 16)
		b.pressed.connect(func():
			if i2 in sel:
				sel.erase(i2)
			elif sel.size() < mx:
				sel.append(i2)
			paint.call())
		r.add_child(b)
		btns[i2] = b
	_confirm_row(func(): _answer(sel.duplicate()), "Conferma", [_ai_button(req)])
	paint.call()


# =================================================================== fine e menu

func _on_game_end(winner: String, text: String) -> void:
	_clear_body()
	pending = {}
	if online != null:
		online.finish()
	Audio.play("win")
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var p := UI.panel(34)
	p.position = Vector2(560, 300)
	p.custom_minimum_size = Vector2(800, 0)
	p.add_theme_stylebox_override("panel", UI.holo(34, UI.fcolor(winner) if winner != "" else UI.HOLO))
	layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	p.add_child(vb)
	var t := UI.title(("Vince: " + RBState.fname(winner)) if winner != "" else "Partita interrotta", 44, UI.fcolor(winner) if winner != "" else UI.TEXT)
	vb.add_child(t)
	vb.add_child(UI.rich(text, 21, 730))
	vb.add_child(UI.label("Round %d · reputazione %d · base: %s" % [st.round, st.rep, RB.sys_name(st.base) if st.base != "" else "—"], 18, UI.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var b1 := UI.primary(UI.button("Torna al menu", 260, 58, 22))
	b1.pressed.connect(func(): main.show_menu())
	hb.add_child(b1)
	var b2 := UI.button("Guarda il tabellone", 280, 58, 22)
	b2.pressed.connect(func(): layer.queue_free())
	hb.add_child(b2)
	vb.add_child(hb)
	refresh()


func _ask_quit() -> void:
	var layer := Control.new()
	layer.size = Vector2(1920, 1080)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0.02, 0.7)
	shade.size = layer.size
	layer.add_child(shade)
	var p := UI.panel(30)
	p.position = Vector2(660, 380)
	p.custom_minimum_size = Vector2(600, 0)
	layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	p.add_child(vb)
	vb.add_child(UI.title("Abbandonare la partita?", 30))
	if online != null:
		vb.add_child(UI.wrap("Online potrai rientrare con lo stesso codice di stanza.", 18, 540, UI.DIM))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var b1 := UI.tint(UI.button("Sì, al menu", 240, 54, 21), UI.BAD)
	b1.pressed.connect(func(): main.show_menu())
	hb.add_child(b1)
	var b2 := UI.primary(UI.button("Continua a giocare", 260, 54, 21))
	b2.pressed.connect(func(): layer.queue_free())
	hb.add_child(b2)
	vb.add_child(hb)


# =================================================================== online

func _build_online_label() -> void:
	var p := UI.panel(10)
	p.position = Vector2(MX + 10, 84)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_lbl = UI.label("", 19, UI.HOLO, UI.font_bold)
	p.add_child(online_lbl)
	add_child(p)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	(online_lbl.get_meta("box") as Control).visible = t != ""


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, RBState.fname(OnlineSession.FACTION_OF[seat])]
	if is_slow:
		t += " (sta pensando da più di un minuto)"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	Audio.suspended = false
	log_lbl.clear()
	for t in engine.log_lines:
		log_lbl.append_text(t + "\n")
	refresh()


## L'IA ha già giocato al posto di questo giocatore: si chiude il dialogo aperto.
func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_body()
	refresh()
	online_status(t)
