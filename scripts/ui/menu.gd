extends Control
## Menu principale: le due fazioni (Umano / IA), livello e velocità dell'IA, contenuti
## (gioco base o con L'Ascesa dell'Impero, mazzi di missioni, unità iniziali, combattimento),
## suoni e gioco online.

var main
var mode := {"R": 0, "I": 1}          # 0 umano, 1 IA
var level := 1
var speed := 1
var opts := {"rote": true, "set_R": "rote", "set_I": "rote", "rote_units": true, "cinematic": false}
var msg: Label
var fac_btns := {}
var rote_box: VBoxContainer


func _ready() -> void:
	size = Vector2(1920, 1080)
	if main.menu_state.has("mode"):
		mode = main.menu_state["mode"].duplicate()
		level = main.menu_state["level"]
		speed = main.menu_state["speed"]
		opts = main.menu_state["opts"].duplicate()
	# il tabellone della galassia sullo sfondo, sfumato
	var art := TextureRect.new()
	art.texture = UI.tex("res://assets/board/tabellone.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(820, 120)
	art.size = Vector2(1100, 560)
	art.modulate = Color(1, 1, 1, 0.55)
	add_child(art)
	var fade := TextureRect.new()
	var fg := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(UI.BG, 1.0))
	g2.set_color(1, Color(UI.BG, 0.0))
	fg.gradient = g2
	fg.fill_from = Vector2(0, 0)
	fg.fill_to = Vector2(1, 0)
	fade.texture = fg
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(820, 120)
	fade.size = Vector2(420, 560)
	add_child(fade)

	var t1 := UI.label("GUERRE STELLARI", 30, UI.GOLD, UI.font_title)
	t1.position = Vector2(64, 34)
	add_child(t1)
	var t2 := UI.label("REBELLION", 96, UI.TEXT, load("res://assets/fonts/Orbitron-Black.woff2"))
	t2.position = Vector2(56, 64)
	add_child(t2)
	var tag := UI.label("La guerra civile galattica: l'Impero dà la caccia alla base ribelle, l'Alleanza conquista i cuori della galassia.", 21, UI.DIM, UI.font_italic)
	tag.position = Vector2(64, 186)
	add_child(tag)

	var box := UI.panel(26)
	box.position = Vector2(48, 228)
	box.custom_minimum_size = Vector2(900, 0)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	vb.add_child(UI.title("Le fazioni", 30, UI.HOLO))
	vb.add_child(_faction_row("R"))
	vb.add_child(_faction_row("I"))
	vb.add_child(UI.hsep())
	vb.add_child(_segmented("Astuzia dell'IA", ["Recluta", "Veterano", "Grand'ammiraglio"], level, func(k): level = k))
	vb.add_child(_segmented("Velocità dell'IA", ["Lenta", "Normale", "Veloce", "Subito"], speed, func(k): speed = k))
	vb.add_child(UI.hsep())
	vb.add_child(_segmented("Contenuto", ["Gioco base", "Con L'Ascesa dell'Impero"], 1 if opts["rote"] else 0, func(k):
		opts["rote"] = k == 1
		_refresh_rote()))
	rote_box = VBoxContainer.new()
	rote_box.add_theme_constant_override("separation", 10)
	vb.add_child(rote_box)
	rote_box.add_child(_segmented("Missioni ribelli", ["Base", "Ascesa"], 1 if opts["set_R"] == "rote" else 0, func(k): opts["set_R"] = "rote" if k == 1 else "base"))
	rote_box.add_child(_segmented("Missioni imperiali", ["Base", "Ascesa"], 1 if opts["set_I"] == "rote" else 0, func(k): opts["set_I"] = "rote" if k == 1 else "base"))
	rote_box.add_child(_segmented("Unità iniziali", ["Base", "Ascesa"], 1 if opts["rote_units"] else 0, func(k): opts["rote_units"] = k == 1))
	rote_box.add_child(_segmented("Combattimento", ["Base", "Cinematografico"], 1 if opts["cinematic"] else 0, func(k): opts["cinematic"] = k == 1))
	var note := UI.wrap("Missioni «Ascesa»: i mazzi con il simbolo di Vader (insieme alle missioni con ritratto). Combattimento cinematografico: tattiche avanzate e round con iniziativa, come nell'espansione.", 17, 840, UI.DIM)
	rote_box.add_child(note)
	vb.add_child(UI.hsep())
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	var sl := UI.label("Suoni", 22, UI.TEXT, UI.font_bold)
	sl.custom_minimum_size = Vector2(230, 0)
	srow.add_child(sl)
	srow.add_child(Audio.toggle_button("music", 190, 44))
	srow.add_child(Audio.toggle_button("sfx", 190, 44))
	vb.add_child(srow)
	_refresh_rote()

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(48, 978)
	add_child(btns)
	var b_start := _big_button("Inizia la partita", 420, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 220)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 170)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)

	msg = UI.label("", 22, UI.BAD, UI.font_bold)
	msg.position = Vector2(980, 1000)
	add_child(msg)

	# gioco online
	var on_box := UI.panel(24)
	on_box.position = Vector2(1400, 740)
	on_box.custom_minimum_size = Vector2(460, 0)
	add_child(on_box)
	var ovb := VBoxContainer.new()
	ovb.add_theme_constant_override("separation", 8)
	on_box.add_child(ovb)
	ovb.add_child(UI.title("Online", 30, UI.HOLO))
	ovb.add_child(UI.wrap("Ognuno dal suo dispositivo: crea una stanza e condividi il codice di 4 lettere.", 19, 410, UI.DIM))
	var b_online := UI.primary(_big_button("Gioca online", 410))
	b_online.pressed.connect(_online_panel)
	ovb.add_child(b_online)
	if not main.lobby.is_empty():
		_online_panel.call_deferred()

	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · Star Wars: Rebellion di Corey Konieczka · © Fantasy Flight Games, Asmodee · Star Wars © Lucasfilm Ltd. · F11 schermo intero", 15, UI.DIM)
	credits.position = Vector2(48, 1054)
	add_child(credits)
	_refresh_factions()


func _store() -> void:
	main.menu_state = {"mode": mode.duplicate(), "level": level, "speed": speed, "opts": opts.duplicate()}


func _refresh_rote() -> void:
	rote_box.modulate = Color.WHITE if opts["rote"] else Color(1, 1, 1, 0.35)
	for c in rote_box.get_children():
		_set_disabled(c, not opts["rote"])


func _set_disabled(n: Node, d: bool) -> void:
	if n is Button:
		(n as Button).disabled = d
	for c in n.get_children():
		_set_disabled(c, d)


func _faction_row(f: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var em := UI.icon_rect(UI.tex("res://assets/tokens/%s.png" % ("lealta_ribelle" if f == "R" else "lealta_imperiale")), Vector2(56, 56))
	row.add_child(em)
	var nm := UI.title(RBState.fname(f), 26, UI.fcolor(f))
	nm.custom_minimum_size = Vector2(420, 0)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	var bs := []
	for k in 2:
		var b := UI.button(["Umano", "IA"][k], 170, 48, 21)
		b.pressed.connect(func():
			mode[f] = k
			msg.text = ""
			_refresh_factions())
		row.add_child(b)
		bs.append(b)
	fac_btns[f] = bs
	return row


func _refresh_factions() -> void:
	for f in fac_btns:
		for k in 2:
			var b: Button = fac_btns[f][k]
			if k == mode[f]:
				UI.tint(b, UI.fcolor(f) if k == 0 else UI.HOLO)
			else:
				UI.tint(b, UI.STEEL_L)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 21, UI.TEXT, UI.font_bold)
	l.custom_minimum_size = Vector2(230, 0)
	hb.add_child(l)
	var btns := []
	var w := 620.0 / items.size() - 6
	for k in range(items.size()):
		var b := UI.button(items[k], w, 42, 19)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			UI.tint(btns[k], UI.HOLO if k == sel else UI.STEEL_L)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 62)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia all'altro dispositivo).
func _config() -> Dictionary:
	var speeds := [1.4, 0.7, 0.25, 0.0]
	var players := {}
	for f in ["R", "I"]:
		players[f] = {"ai": mode[f] == 1, "level": level}
	var cfg := {"players": players, "ai_delay": speeds[speed], "rote": opts["rote"], "seed": 1 + randi() % 2000000000}
	if opts["rote"]:
		cfg["set_R"] = opts["set_R"]
		cfg["set_I"] = opts["set_I"]
		cfg["rote_units"] = opts["rote_units"]
		cfg["cinematic"] = opts["cinematic"]
	return cfg


func _on_start() -> void:
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var on_side := "R"


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.03, 0.84)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := UI.panel(34)
	box.position = Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 42, UI.HOLO))
	vb.add_child(UI.wrap("Chi crea la stanza sceglie la sua fazione e, nel menu, contenuti e combattimento: valgono per tutti e due. L'amico entra con il codice e prende l'altra fazione.", 20, 740, UI.DIM))
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", 10)
	var sl := UI.label("Giochi con", 22, UI.TEXT, UI.font_bold)
	sl.custom_minimum_size = Vector2(160, 0)
	side_row.add_child(sl)
	var side_btns := []
	for f in ["R", "I"]:
		var b := UI.button(RBState.fname(f), 290, 50, 20)
		side_row.add_child(b)
		side_btns.append(b)
	var paint := func():
		for i in 2:
			var f2: String = ["R", "I"][i]
			UI.tint(side_btns[i], UI.fcolor(f2) if on_side == f2 else UI.STEEL_L)
	for i in 2:
		var f3: String = ["R", "I"][i]
		side_btns[i].pressed.connect(func():
			on_side = f3
			paint.call())
	paint.call()
	vb.add_child(side_row)
	var b_create := UI.primary(UI.button("Crea una stanza", 0, 58, 24))
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.primary(UI.button("Entra", 200, 58, 24))
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.wrap("", 21, 740)
	on_lbl.custom_minimum_size.y = 110
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Si comincia!", 360, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 260)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 58)
	le.add_theme_font_size_override("font_size", 26)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in [0, 1]:
		var k := str(idx)
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [RBState.fname(OnlineSession.FACTION_OF[idx]), who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var mine: int = OnlineSession.SEAT_OF[on_side]
	var code := await net.create_room(nm, [mine, 1 - mine])
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": mine}
	net.remember_room(code, mine)
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice al tuo avversario.\n%s.\nQuando c'è anche lui premi Si comincia! (se il posto resta libero gioca l'IA)." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] con %s.\n%s.\nAspetta che chi l'ha creata avvii la partita." % [code, RBState.fname(OnlineSession.FACTION_OF[int(main.lobby["seat"])]), _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: contenuti, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	for idx in [0, 1]:
		var f: String = OnlineSession.FACTION_OF[idx]
		var k := str(idx)
		var human: bool = seats_db.has(k) and seats_db[k] is Dictionary
		cfg["players"][f]["ai"] = not human
		cfg["players"][f]["name"] = str(seats_db[k].get("name", "")) if human else "IA"
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
