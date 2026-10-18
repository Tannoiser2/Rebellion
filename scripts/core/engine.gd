class_name RBEngine
extends Node
## Motore della partita: preparazione, round (Assegnazione, Comando, Ripristino), movimento,
## missioni, costruzione e schieramento. Le regole delle singole carte stanno in RBCards,
## il combattimento in RBCombat.
## Ogni scelta passa da decide(): l'IA risponde subito, per le persone si emette
## `decision_requested` e si aspetta `provide_decision()`; online la scelta passa dal registro
## delle mosse (OnlineSession) e, con lo stesso seme, ogni dispositivo ottiene la stessa partita.

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(winner: String, text: String)
signal fx(kind: String, data: Dictionary)

var st := RBState.new()
var cards: RBCards
var combat: RBCombat
var combat_cine = null         # combattimento cinematografico (Ascesa dell'Impero)
var ais := {}
var players := {"R": {"ai": false, "level": 1}, "I": {"ai": true, "level": 1}}
var ai_delay := 0.0
var headless := false
var abort := false
var online = null
var log_lines: Array = []
var game_over := false
var waiting_for := ""          # fazione a cui si sta chiedendo una scelta
var viewer := "R"              # fazione di chi guarda lo schermo (per i testi nascosti)


func _init() -> void:
	RB.load_all()
	cards = RBCards.new(self)
	combat = RBCombat.new(self)
	combat_cine = RBCombatCine.new(self)


func setup(config: Dictionary) -> void:
	st.rng.seed = int(config.get("seed", 12345))
	st.opt = {
		"rote": bool(config.get("rote", true)),
		"rote_units": bool(config.get("rote_units", config.get("rote", true))),
		"set_R": config.get("set_R", "base"),
		"set_I": config.get("set_I", "base"),
		"cinematic": bool(config.get("cinematic", false)),
	}
	if not st.opt["rote"]:
		st.opt["rote_units"] = false
		st.opt["set_R"] = "base"
		st.opt["set_I"] = "base"
		st.opt["cinematic"] = false
	players = config.get("players", players).duplicate(true)
	ai_delay = float(config.get("ai_delay", 0.0))
	for f in RB.FACTIONS:
		var a := RBAI.new()
		a.level = int(players[f].get("level", 1))
		a.rng.seed = st.rng.seed + (17 if f == "R" else 31)
		ais[f] = a


func rote() -> bool:
	return bool(st.opt.get("rote", false))


func cinematic() -> bool:
	return bool(st.opt.get("cinematic", false))


func any_local_human() -> bool:
	if online != null:
		return true
	return not players["R"]["ai"] or not players["I"]["ai"]


# ------------------------------------------------------------------ cronaca

func say(t: String) -> void:
	st.say(t)
	_sync()


func _sync() -> void:
	for t in st.log:
		log_lines.append(t)
		log_added.emit(t)
	st.log.clear()
	changed.emit()


func pause(sec: float) -> void:
	if headless or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if ai_delay <= 0.0 and not any_local_human():
		return
	await get_tree().create_timer(sec).timeout


func emit_fx(kind: String, data: Dictionary) -> void:
	if headless:
		return
	if online != null and online.catchup:
		return
	fx.emit(kind, data)


# ------------------------------------------------------------------ decisioni

func decide(f: String, req: Dictionary):
	req["f"] = f
	waiting_for = f
	_sync()
	var r
	if abort:
		r = ais[f].decide(self, f, req)
	elif online != null:
		r = await online.decide(self, f, req)
	elif players[f]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		r = ais[f].decide(self, f, req)
	else:
		decision_requested.emit(req)
		r = await decision_provided
	waiting_for = ""
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


## Scelta fra opzioni: [{v, l, d?, card?, sys?}]. Restituisce il valore scelto.
func ask(f: String, title: String, options: Array, ctx: String, extra := {}):
	if options.is_empty():
		return null
	if options.size() == 1 and not extra.get("confirm", false):
		return options[0]["v"]
	var req := {"k": "choice", "t": title, "opts": options, "ctx": ctx}
	req.merge(extra)
	var r = await decide(f, req)
	for o in options:
		if o["v"] == r:
			return r
	return options[0]["v"]


func ask_yes(f: String, title: String, ctx: String, yes := "Sì", no := "No", extra := {}) -> bool:
	var r = await ask(f, title, [{"v": true, "l": yes}, {"v": false, "l": no}], ctx, extra.merged({"confirm": true}))
	return bool(r)


## Scelta di un sistema (anche sulla mappa). Con allow_none si può rinunciare: restituisce "".
func ask_system(f: String, title: String, systems: Array, ctx: String, allow_none := false, extra := {}) -> String:
	if systems.is_empty():
		return ""
	if systems.size() == 1 and not allow_none and not extra.get("confirm", false):
		return systems[0]
	var req := {"k": "system", "t": title, "opts": systems, "ctx": ctx, "none": allow_none}
	req.merge(extra)
	var r = await decide(f, req)
	if r is String and (r in systems or (allow_none and r == "")):
		return r
	return "" if allow_none else systems[0]


## Scelta di alcuni elementi da una lista (leader, unità, carte): restituisce un array.
func ask_pick(f: String, kind: String, title: String, opts: Array, mn: int, mx: int, ctx: String, extra := {}) -> Array:
	if opts.is_empty():
		return []
	mx = min(mx, opts.size())
	mn = min(mn, mx)
	if mn == mx and mn == opts.size() and not extra.get("confirm", false):
		return opts.duplicate()
	var req := {"k": kind, "t": title, "opts": opts, "min": mn, "max": mx, "ctx": ctx}
	req.merge(extra)
	var r = await decide(f, req)
	var out := []
	if r is Array:
		for x in r:
			if x in opts and not x in out and out.size() < mx:
				out.append(x)
	while out.size() < mn:
		for x in opts:
			if not x in out:
				out.append(x)
				break
	return out


# ------------------------------------------------------------------ preparazione

func run() -> void:
	await _setup_game()
	if abort:
		return
	while not st.check_victory() and not abort:
		await _assignment_phase()
		if _over():
			break
		await _command_phase()
		if _over():
			break
		await _refresh_phase()
		if _over():
			break
	_finish()


func _over() -> bool:
	return abort or st.check_victory()


func _finish() -> void:
	if game_over:
		return
	game_over = true
	st.phase = "end"
	if st.winner != "":
		say("[b]%s vince![/b] %s" % [RBState.fname(st.winner), st.win_text])
	_sync()
	game_ended.emit(st.winner, st.win_text)


func _setup_game() -> void:
	st.phase = "setup"
	for s in RB.SYS:
		st.sys[s] = {"loy": "", "subj": false, "sab": false, "dest": false}
	st.sys["CORUSCANT"]["loy"] = "I"
	# leader
	for n in RB.LEADERS:
		var L: Dictionary = RB.LEADERS[n]
		if L["set"] == "rote" and not rote():
			continue
		st.leaders[n] = {"f": L["fazione"], "home": L["fazione"], "st": "pool" if L["iniziale"] else "box", "loc": "", "ring": "", "det": false}
	# mazzi di carte
	_build_decks()
	say("[b]Inizio della partita.[/b] %s." % ("Gioco base con L'Ascesa dell'Impero" if rote() else "Gioco base"))
	# fedeltà iniziale con le carte sonda
	var probe: Array = st.deck["probe"]
	var reb_found := []
	var imp_found := []
	var keep := []
	while reb_found.size() < 3 or imp_found.size() < 5:
		var p: String = probe.pop_front()
		var tag: String = RB.PROBES[p]["lealta_iniziale"]
		if tag == "R" and reb_found.size() < 3:
			reb_found.append(p)
			keep.append(p)
		elif tag == "I" and imp_found.size() < 5:
			imp_found.append(p)
		else:
			keep.append(p)
	for s in reb_found:
		st.sys[s]["loy"] = "R"
	for i in imp_found.size():
		var s: String = imp_found[i]
		if i < 2:
			st.sys[s]["subj"] = true
		else:
			st.sys[s]["loy"] = "I"
	probe.append_array(keep)
	st.shuffle(probe)
	say("Sistemi ribelli: %s. Sistemi imperiali: %s (%s e %s sottomessi)." % [_names(reb_found), _names(imp_found), RB.sys_name(imp_found[0]), RB.sys_name(imp_found[1])])
	_sync()
	# unità iniziali
	await _place_starting_units()
	if abort:
		return
	# carte azione iniziali (prima i Ribelli)
	for f in ["R", "I"]:
		for i in 2:
			var c = st.draw("start_" + f)
			if c != null:
				st.acts[f].append(c)
	for f in ["R", "I"]:
		for c in st.acts[f].duplicate():
			if RB.card(c).get("momento_en", "") == "Immediate":
				await cards.immediate_action(f, c)
	# base ribelle
	await _choose_base()
	# mani iniziali
	for f in ["R", "I"]:
		for c in st.deck["start_mis_" + f]:
			st.hand[f].append(c)
		st.deck["start_mis_" + f].clear()
		for i in 2:
			var c = st.draw("mis_" + f, "mis_dis_" + f)
			if c != null:
				st.hand[f].append(c)
	await cards.draw_objective()
	st.round = 1
	st.rep = 14
	say("La partita comincia: segnalino tempo su 1, reputazione su 14.")
	_sync()


func _names(a: Array) -> String:
	var out := []
	for s in a:
		out.append(RB.sys_name(s))
	return ", ".join(out)


func _cards_where(kind: String, f: String, filter: Callable) -> Array:
	var out := []
	for id in RB.CARDS:
		var c: Dictionary = RB.CARDS[id]
		if c["tipo"] != kind:
			continue
		if f != "" and c["fazione"] != f:
			continue
		if c["set"] == "rote" and not rote():
			continue
		if filter.call(c):
			out.append(id)
	out.sort()
	return out


const REPLACED_BY_ROTE := ["sabotage", "construct_super_star_destroyer", "good_intel", "son_of_skywalker"]


func _replaced(c: Dictionary) -> bool:
	return rote() and c["set"] == "base" and c["base"] in REPLACED_BY_ROTE


func _build_decks() -> void:
	var d := st.deck
	for f in ["R", "I"]:
		var use_rote: bool = rote() and st.opt["set_" + f] == "rote"
		d["start_mis_" + f] = _cards_where("missione", f, func(c): return c["iniziale"] and not _replaced(c))
		d["mis_" + f] = _cards_where("missione", f, func(c):
			if c["iniziale"] or c["progetto"] or _replaced(c):
				return false
			if c["ritratto"] != null:
				return true
			return c["vader"] if use_rote else not c["vader"])
		st.shuffle(d["mis_" + f])
		d["mis_dis_" + f] = []
		d["act_" + f] = _cards_where("azione", f, func(c): return not c["iniziale"] and not _replaced(c))
		st.shuffle(d["act_" + f])
		d["start_" + f] = _cards_where("azione", f, func(c): return c["iniziale"] and not _replaced(c))
		st.shuffle(d["start_" + f])
		if cinematic():
			d["atac_spazio_" + f] = _cards_where("tattica_av", f, func(c): return c["teatro"] == "spazio")
			d["atac_terra_" + f] = _cards_where("tattica_av", f, func(c): return c["teatro"] == "terra")
			d["atac_dis_spazio_" + f] = []
			d["atac_dis_terra_" + f] = []
	d["proj"] = _cards_where("missione", "I", func(c): return c["progetto"] and not _replaced(c))
	st.shuffle(d["proj"])
	d["proj_dis"] = []
	d["tac_spazio"] = _cards_where("tattica", "", func(c): return c["teatro"] == "spazio")
	d["tac_terra"] = _cards_where("tattica", "", func(c): return c["teatro"] == "terra")
	st.shuffle(d["tac_spazio"])
	st.shuffle(d["tac_terra"])
	d["tac_dis_spazio"] = []
	d["tac_dis_terra"] = []
	# obiettivi
	var stages := {"I": [], "II": [], "III": []}
	for id in _cards_where("obiettivo", "R", func(c): return true):
		stages[RB.card(id)["stadio"]].append(id)
	for k in stages:
		st.shuffle(stages[k])
	if rote():
		var dsp2 := ""
		var dsp3 := ""
		for id in stages["II"]:
			if RB.base_id(id) == "ob_death_star_plans":
				dsp2 = id
		for id in stages["III"]:
			if RB.base_id(id) == "ob_death_star_plans":
				dsp3 = id
		stages["II"].erase(dsp2)
		stages["III"].erase(dsp3)
		var s3: Array = stages["III"].slice(0, 4)
		s3.append(dsp3)
		st.shuffle(s3)
		var s2: Array = stages["II"].slice(0, 4)
		s2.append(dsp2)
		st.shuffle(s2)
		var s1: Array = stages["I"].slice(0, 5)
		d["obj"] = s1 + s2 + s3
	else:
		d["obj"] = stages["I"] + stages["II"] + stages["III"]
	d["obj_dis"] = []
	# sonde
	d["probe"] = RB.PROBES.keys()
	d["probe"].sort()
	st.shuffle(d["probe"])
	d["probe_box"] = []


func _place_starting_units() -> void:
	var imp_sys := []
	for s in st.sys:
		if st.is_imperial_sys(s) and s != "CORUSCANT":
			imp_sys.append(s)
	imp_sys.sort()
	var imp_units := {}
	var reb_units := {}
	if st.opt["rote_units"]:
		st.queue["I"][2].append("Death Star")
		var remotes := []
		for s in st.sys:
			if st.is_remote(s):
				remotes.append(s)
		remotes.sort()
		var ds := await ask_system("I", "Scegli il sistema remoto dove si costruisce la Morte Nera (4 Caccia TIE, 1 Assaltatore e la Morte Nera in Costruzione).", remotes, "setup_dsuc")
		st.add_unit("Death Star Under Construction", "I", ds)
		for i in 4:
			st.add_unit("TIE Fighter", "I", ds)
		st.add_unit("Stormtrooper", "I", ds)
		st.deck["probe"].erase(ds)
		st.deck["probe_box"].append(ds)
		say("La Morte Nera è in costruzione su %s; la seconda Morte Nera è nella casella 3 della coda." % RB.sys_name(ds))
		imp_units = {"TIE Fighter": 8, "Assault Carrier": 3, "Star Destroyer": 3, "TIE Striker": 2, "Stormtrooper": 12, "AT-ST": 4, "Assault Tank": 2, "AT-AT": 1}
		reb_units = {"X-Wing": 1, "Y-Wing": 1, "U-Wing": 1, "Rebel Transport": 1, "Corellian Corvette": 1, "Rebel Trooper": 5, "Airspeeder": 2, "Rebel Vanguard": 1}
	else:
		imp_units = {"Star Destroyer": 3, "Assault Carrier": 3, "TIE Fighter": 12, "Stormtrooper": 12, "AT-ST": 5, "AT-AT": 1, "Death Star": 1}
		reb_units = {"Corellian Corvette": 1, "Rebel Transport": 1, "X-Wing": 2, "Y-Wing": 2, "Rebel Trooper": 6, "Airspeeder": 2}
	# l'Impero dispone le sue unità
	var allowed_i: Array = imp_sys.duplicate()
	allowed_i.append("CORUSCANT")
	allowed_i.sort()
	var pl = await decide("I", {"k": "place", "t": "Disponi le unità imperiali nei sistemi imperiali (almeno 1 unità terrestre in ogni sistema imperiale).", "units": imp_units, "opts": allowed_i, "need_ground": imp_sys, "ctx": "setup_imp"})
	pl = _valid_placement(pl, imp_units, allowed_i, imp_sys, "I")
	for s in pl:
		for t in pl[s]:
			st.add_unit(t, "I", s)
	say("L'Impero ha disposto la sua flotta e le sue truppe.")
	_sync()
	# i Ribelli: casella Base Ribelle e/o un solo sistema senza unità imperiali
	var allowed_r := ["BASE"]
	for s in st.sys:
		if not st.has_units(s, "I") and not st.sys[s]["dest"]:
			allowed_r.append(s)
	var pr = await decide("R", {"k": "place", "t": "Disponi le unità ribelli nella casella Base Ribelle e/o in UN solo sistema senza unità imperiali.", "units": reb_units, "opts": allowed_r, "one_system": true, "ctx": "setup_reb"})
	pr = _valid_placement(pr, reb_units, allowed_r, [], "R")
	for s in pr:
		for t in pr[s]:
			st.add_unit(t, "R", s)
	say("L'Alleanza ha nascosto le sue forze.")
	st.update_all_subjugation()
	_sync()


func _valid_placement(pl, units: Dictionary, allowed: Array, need_ground: Array, f: String) -> Dictionary:
	## Controlla una disposizione iniziale; se non va bene ne costruisce una automatica.
	var ok := pl is Dictionary
	var count := {}
	var others := []
	if ok:
		for s in pl:
			if not s in allowed or not pl[s] is Array:
				ok = false
				break
			if s != "BASE" and not pl[s].is_empty():
				others.append(s)
			for t in pl[s]:
				count[t] = count.get(t, 0) + 1
	if ok:
		for t in units:
			if count.get(t, 0) != units[t]:
				ok = false
		for t in count:
			if not units.has(t):
				ok = false
		for s in need_ground:
			var g := false
			for t in pl.get(s, []):
				if RB.is_ground(t):
					g = true
			if not g:
				ok = false
		if f == "R" and others.size() > 1:
			ok = false
	if ok:
		return pl
	return RBAI.auto_place(self, f, units, allowed, need_ground)


func _choose_base() -> void:
	var opts := []
	for s in st.deck["probe"]:
		if not st.has_units(s, "I"):
			opts.append(s)
	opts.sort()
	var b := await ask_system("R", "Scegli in segreto il sistema della base ribelle.", opts, "base", false, {"secret": true, "confirm": true})
	st.base = b
	st.deck["probe"].erase(b)
	st.shuffle(st.deck["probe"])
	say("I Ribelli hanno scelto in segreto il sistema della loro base.")
	_sync()


# ------------------------------------------------------------------ fase di assegnazione

func _assignment_phase() -> void:
	st.phase = "assign"
	say("[b]Round %d — Fase di Assegnazione.[/b]" % st.round)
	st.assign = {"R": [], "I": []}
	st.flags.erase("misdirection")
	st.flags.erase("blindside")
	for f in ["R", "I"]:
		await _assign_for(f)
		if _over():
			return
	# fine dell'assegnazione: "Ordini Falsi"
	for c in st.acts["R"].duplicate():
		if RB.base_id(c) == "false_orders":
			await cards.false_orders(c)
	_sync()


func _assign_for(f: String) -> void:
	while not abort:
		var opts := []
		if not st.leader_pool(f).is_empty():
			for c in st.hand[f]:
				opts.append({"v": "m:" + c, "l": "Assegna: " + RB.card_name(c), "card": c})
			for c in st.acts[f]:
				if cards.action_timing(c) == "Assignment" and cards.can_use_action(f, c, "assign"):
					opts.append({"v": "a:" + c, "l": "Usa carta azione: " + RB.card_name(c), "card": c})
		opts.append({"v": "done", "l": "Fine delle assegnazioni"})
		var r: String = await ask(f, "%s: assegna i leader alle missioni." % RBState.fshort(f), opts, "assign", {"confirm": true})
		if r == "done":
			return
		if r.begins_with("m:"):
			var c := r.substr(2)
			var ls := await ask_pick(f, "leaders", "Scegli 1 o 2 leader per «%s»." % RB.card_name(c), st.leader_pool(f), 1, 2, "assign_leaders", {"card": c, "confirm": true})
			if ls.is_empty():
				continue
			st.hand[f].erase(c)
			st.assign[f].append({"card": c, "leaders": ls, "rev": false})
			for n in ls:
				st.leaders[n]["st"] = "mission"
			say("%s assegna %s a una missione." % [RBState.fshort(f), _leader_names(ls)])
		elif r.begins_with("a:"):
			await cards.use_action(f, r.substr(2), "assign")
		_sync()
		if _over():
			return


func _leader_names(ls: Array) -> String:
	var out := []
	for n in ls:
		out.append(RB.leader_it(n))
	return " e ".join(out)


# ------------------------------------------------------------------ fase di comando

func _command_phase() -> void:
	st.phase = "command"
	st.passed = {"R": false, "I": false}
	say("[b]Fase di Comando.[/b]")
	var f := "R"
	var safety := 0
	while not (st.passed["R"] and st.passed["I"]) and safety < 200:
		safety += 1
		if not st.passed[f]:
			st.current = f
			await _command_turn(f)
			if _over():
				return
		f = RBState.other(f)
	# fine della fase di comando
	await cards.end_of_command()
	for f2 in ["R", "I"]:
		for a in st.assign[f2]:
			st.hand[f2].append(a["card"])
			for n in a["leaders"]:
				if st.leaders[n]["st"] == "mission":
					st.to_pool(n)
		st.assign[f2].clear()
	_sync()


func _command_turn(f: String) -> void:
	# abilità "all'inizio del tuo turno"
	await cards.start_of_turn(f)
	if _over():
		return
	var opts := []
	if f == "R" and not st.base_revealed:
		opts.append({"v": "base", "l": "Rivela la base ribelle (%s)" % RB.sys_name(st.base)})
	var act_leaders := []
	for n in st.leader_pool(f):
		if RB.has_tactics(n):
			act_leaders.append(n)
	if not act_leaders.is_empty():
		opts.append({"v": "activate", "l": "Attiva un sistema"})
	for i in st.assign[f].size():
		var a: Dictionary = st.assign[f][i]
		if a["rev"]:
			continue
		if cards.can_reveal(f, i):
			opts.append({"v": "mission:%d" % i, "l": "Rivela: " + RB.card_name(a["card"]), "card": a["card"]})
	opts.append({"v": "pass", "l": "Passa"})
	var r: String = await ask(f, "%s: è il tuo turno nella Fase di Comando." % RBState.fshort(f), opts, "command", {"confirm": true})
	if r == "base":
		await reveal_base("I Ribelli rivelano la loro base")
		if _over():
			return
		# dopo la rivelazione il turno continua
		await _command_turn_after_reveal(f)
		return
	await _do_command(f, r)


func _command_turn_after_reveal(f: String) -> void:
	var opts := []
	for n in st.leader_pool(f):
		if RB.has_tactics(n):
			opts.append({"v": "activate", "l": "Attiva un sistema"})
			break
	for i in st.assign[f].size():
		if not st.assign[f][i]["rev"] and cards.can_reveal(f, i):
			opts.append({"v": "mission:%d" % i, "l": "Rivela: " + RB.card_name(st.assign[f][i]["card"]), "card": st.assign[f][i]["card"]})
	opts.append({"v": "pass", "l": "Passa"})
	var r: String = await ask(f, "La base è rivelata: continua il tuo turno.", opts, "command", {"confirm": true})
	await _do_command(f, r)


func _do_command(f: String, r: String) -> void:
	if r == "pass":
		st.passed[f] = true
		say("%s passa." % RBState.fshort(f))
	elif r == "activate":
		await activate(f)
	elif r.begins_with("mission:"):
		await cards.reveal_mission(f, int(r.substr(8)))
	_sync()


# ------------------------------------------------------------------ attivare un sistema e muovere

## Sistemi da cui si possono muovere unità verso `target` (adiacenti, e per i Ribelli la casella Base).
func move_sources(f: String, target: String) -> Array:
	var out := []
	if target == "BASE":
		if f != "R" or st.base_revealed:
			return []
		var cand := [st.base]
		cand.append_array(RB.SYS[st.base]["adiacenti"])
		for s in cand:
			out.append(s)
	else:
		out.append_array(RB.SYS[target]["adiacenti"])
		if f == "R" and not st.base_revealed and (target == st.base or RB.adjacent(st.base, target)):
			out.append("BASE")
	var res := []
	for s in out:
		if s == target:
			continue
		if not st.leaders_at(s, f).is_empty():
			continue  # un leader della propria fazione blocca le unità
		var ok := false
		for id in st.units_at(s, f):
			if not RB.UNITS[st.units[id]["t"]]["immobile"]:
				ok = true
				break
		if ok:
			res.append(s)
	return res


func activate(f: String) -> void:
	var ls := []
	for n in st.leader_pool(f):
		if RB.has_tactics(n):
			ls.append(n)
	var n: String = (await ask_pick(f, "leaders", "Scegli il leader che attiva il sistema.", ls, 1, 1, "activate_leader"))[0]
	var targets := st.all_systems()
	if f == "R" and not st.base_revealed:
		targets.append("BASE")
	targets.sort()
	var t := await ask_system(f, "Scegli il sistema da attivare con %s." % RB.leader_it(n), targets, "activate_target", false, {"leader": n})
	st.place_leader(n, t)
	say("%s attiva %s con %s." % [RBState.fshort(f), RB.sys_name(t), RB.leader_it(n)])
	emit_fx("leader", {"n": n, "sys": t})
	_sync()
	var target: String = st.leaders[n]["loc"]
	var sources := move_sources(f, target)
	var moved := await move_units(f, target, sources, "activate_move", {})
	await after_move(f, target, moved, sources)


## Chiede quali unità spostare verso target dalle sorgenti indicate e le sposta.
## opts: ignore_transport, only_ships, only_ground, max, max_health, types (Dictionary tipo→max)
func move_units(f: String, target: String, sources: Array, ctx: String, opts: Dictionary) -> Array:
	var cand := []
	for s in sources:
		for id in st.units_at(s, f):
			var t: String = st.units[id]["t"]
			if RB.UNITS[t]["immobile"]:
				continue
			if opts.get("only_ships", false) and not RB.is_ship(t):
				continue
			if opts.get("only_ground", false) and not RB.is_ground(t):
				continue
			if opts.has("types") and not opts["types"].has(t):
				continue
			cand.append(id)
	if cand.is_empty():
		return []
	var req := {"k": "move", "t": "Scegli le unità da spostare in %s." % RB.sys_name(target), "opts": cand, "target": target, "ctx": ctx,
		"ignore_transport": opts.get("ignore_transport", false), "max": opts.get("max", 999),
		"max_health": opts.get("max_health", 0), "types": opts.get("types", {}), "min": 0}
	var r = await decide(f, req)
	var sel := []
	if r is Array:
		for x in r:
			if x in cand and not x in sel:
				sel.append(x)
	sel = valid_move(sel, opts)
	for id in sel:
		st.move_unit(id, target)
	if not sel.is_empty():
		say("%s sposta %s in %s." % [RBState.fshort(f), units_text(sel), RB.sys_name(target)])
		emit_fx("move", {"ids": sel, "to": target})
	_sync()
	return sel


## Toglie dalla selezione le unità che non possono muoversi (trasporto, limiti della carta).
func valid_move(sel: Array, opts: Dictionary) -> Array:
	var out := []
	var by_src := {}
	for id in sel:
		var src_loc: String = st.units[id]["loc"]
		if not by_src.has(src_loc):
			by_src[src_loc] = []
		by_src[src_loc].append(id)
	for s in by_src:
		var ids: Array = by_src[s]
		if opts.get("ignore_transport", false):
			out.append_array(ids)
			continue
		var cap := 0
		var need := []
		for id in ids:
			cap += int(RB.UNITS[st.units[id]["t"]]["trasporto"])
			if st.needs_transport(id):
				need.append(id)
			else:
				out.append(id)
		# unità terrestri e Caccia TIE solo se c'è posto sulle navi che partono
		need.sort_custom(func(a, b): return RB.health(st.units[a]["t"]) > RB.health(st.units[b]["t"]))
		for i in min(cap, need.size()):
			out.append(need[i])
	var mx := int(opts.get("max", 999))
	if out.size() > mx:
		out = out.slice(0, mx)
	if opts.get("max_health", 0) > 0:
		var tot := 0
		var keep := []
		for id in out:
			var h := RB.health(st.units[id]["t"])
			if tot + h <= int(opts["max_health"]):
				keep.append(id)
				tot += h
		out = keep
	if opts.has("types") and not opts["types"].is_empty():
		var cnt := {}
		var keep2 := []
		for id in out:
			var t: String = st.units[id]["t"]
			cnt[t] = cnt.get(t, 0) + 1
			if cnt[t] <= int(opts["types"].get(t, 0)):
				keep2.append(id)
		out = keep2
	return out


func units_text(ids: Array) -> String:
	var cnt := {}
	for id in ids:
		var t: String = st.units[id]["t"] if st.units.has(id) else "?"
		cnt[t] = cnt.get(t, 0) + 1
	var parts := []
	for t in cnt:
		parts.append("%d %s" % [cnt[t], RB.unit_it(t)])
	return ", ".join(parts)


## Dopo uno spostamento: rivelazione della base, combattimento, sottomissione.
func after_move(f: String, target: String, moved: Array, sources: Array, fight := true) -> void:
	if target == "BASE":
		return
	if f == "I" and not st.base_revealed and target == st.base:
		for id in moved:
			if RB.is_ground(st.units[id]["t"]):
				await reveal_base("Le truppe imperiali sbarcano su %s" % RB.sys_name(target))
				break
	if f == "I" and not st.base_revealed:
		for id in moved:
			if st.units.has(id) and RB.is_ground(st.units[id]["t"]):
				if not target in st.known["I_not_base"]:
					st.known["I_not_base"].append(target)
				break
	if _over():
		return
	if fight and combat.needs_combat(target):
		await combat.resolve(target, f, sources)
	st.update_subjugation(target)
	_sync()


## La base ribelle viene rivelata: le unità e i leader della casella Base passano nel sistema.
func reveal_base(why: String) -> void:
	if st.base_revealed:
		return
	st.base_revealed = true
	for id in st.units.keys():
		if st.units[id]["loc"] == "BASE":
			st.units[id]["loc"] = st.base
	for n in st.leaders:
		if st.leaders[n]["st"] == "board" and st.leaders[n]["loc"] == "BASE":
			st.leaders[n]["loc"] = st.base
	st.update_subjugation(st.base)
	say("[b]%s: la base ribelle è su %s![/b]" % [why, RB.sys_name(st.base)])
	emit_fx("base", {"sys": st.base})
	_sync()
	if st.check_victory():
		return
	if combat.needs_combat(st.base):
		await combat.resolve(st.base, st.current, [])


# ------------------------------------------------------------------ fase di ripristino

func _refresh_phase() -> void:
	st.phase = "refresh"
	say("[b]Fase di Ripristino.[/b]")
	await cards.start_of_refresh()
	if _over():
		return
	# 1. i leader tornano nella riserva
	for n in st.leaders:
		var l: Dictionary = st.leaders[n]
		if l["st"] == "board" and not st.is_captured(n):
			if l["det"]:
				l["det"] = false
				continue
			st.to_pool(n)
		elif l["st"] == "mission":
			st.to_pool(n)
	_sync()
	# 2. missioni
	for f in ["R", "I"]:
		for i in 2:
			var c = st.draw("mis_" + f, "mis_dis_" + f)
			if c != null:
				st.hand[f].append(c)
		await _discard_to_ten(f)
	# 3. sonde
	for i in 2:
		var p = st.draw("probe")
		if p != null:
			st.probes.append(p)
			if not p in st.known["I_not_base"]:
				st.known["I_not_base"].append(p)
	say("L'Impero lancia due droidi sonda.")
	# 4. obiettivo
	await cards.draw_objective()
	if _over():
		return
	# 5. avanza il tempo
	st.round += 1
	say("[b]Il segnalino tempo avanza a %d.[/b]" % st.round)
	emit_fx("time", {"round": st.round})
	_sync()
	if st.check_victory():
		return
	if st.round in RB.RECRUIT:
		await _recruit()
	if st.round in RB.BUILD:
		await _build()
	# 6. schieramento
	await _deploy()
	await _check_leader_limit()
	_sync()


func _discard_to_ten(f: String) -> void:
	var extra: int = st.hand[f].size() - 10
	if extra <= 0:
		return
	var disc := []
	for c in st.hand[f]:
		if not st.is_starting_mission(c):
			disc.append(c)
	var sel := await ask_pick(f, "cards", "Hai più di 10 missioni: scartane %d." % extra, disc, extra, extra, "discard_missions")
	for c in sel:
		st.hand[f].erase(c)
		_discard_mission(f, c)


func _discard_mission(f: String, c: String) -> void:
	if RB.card(c).get("progetto", false):
		st.deck["proj_dis"].append(c)
	else:
		st.deck["mis_dis_" + f].append(c)


func _recruit() -> void:
	say("Reclutamento: ogni giocatore pesca 2 carte azione e recluta un leader.")
	var picks := {}
	for f in ["R", "I"]:
		var drawn := []
		for i in 2:
			var c = st.draw("act_" + f)
			if c != null:
				drawn.append(c)
		# se nessuno dei leader è reclutabile si pesca ancora
		var guard := 0
		while not _any_recruitable(drawn) and not st.deck["act_" + f].is_empty() and guard < 20:
			guard += 1
			drawn.append(st.draw("act_" + f))
		picks[f] = drawn
	for f in ["R", "I"]:
		var drawn: Array = picks[f]
		if drawn.is_empty():
			continue
		var opts := []
		for c in drawn:
			var ls := []
			for n in RB.card(c).get("leader", []):
				if st.leaders.has(n) and st.leaders[n]["st"] == "box":
					ls.append(n)
			if ls.is_empty():
				opts.append({"v": c + "|", "l": RB.card_name(c) + " (nessun leader da reclutare)", "card": c})
			for n in ls:
				opts.append({"v": c + "|" + n, "l": "Recluta %s (%s)" % [RB.leader_it(n), RB.card_name(c)], "card": c, "leader": n})
		var r: String = await ask(f, "Reclutamento: scegli una carta azione e il leader da reclutare.", opts, "recruit", {"confirm": true})
		var c := r.get_slice("|", 0)
		var n := r.get_slice("|", 1)
		for x in drawn:
			if x != c:
				st.deck["act_" + f].append(x)
		if n != "":
			st.leaders[n]["st"] = "pool"
			say("%s recluta %s." % [RBState.fshort(f), RB.leader_it(n)])
		else:
			say("%s prende una carta azione senza reclutare." % RBState.fshort(f))
		st.acts[f].append(c)
		_sync()
		if RB.card(c).get("momento_en", "") == "Immediate":
			await cards.immediate_action(f, c)


func _any_recruitable(drawn: Array) -> bool:
	for c in drawn:
		for n in RB.card(c).get("leader", []):
			if st.leaders.has(n) and st.leaders[n]["st"] == "box":
				return true
	return false


func _check_leader_limit() -> void:
	if not rote():
		return
	for f in ["R", "I"]:
		var pool := st.leader_pool(f)
		var lim: int = st.leader_limit[f]
		if pool.size() > lim:
			# "Ambizioni di Potere" alza il limite
			for c in st.acts[f].duplicate():
				if RB.base_id(c) == "ambitions_of_power":
					if await ask_yes(f, "Hai più di %d leader: usi «Ambizioni di Potere» per alzare il limite di 1?" % lim, "use_ambitions"):
						st.acts[f].erase(c)
						st.leader_limit[f] += 1
						lim += 1
			while st.leader_pool(f).size() > lim:
				var n: String = (await ask_pick(f, "leaders", "Hai più di %d leader nella riserva: scegline uno da eliminare." % lim, st.leader_pool(f), 1, 1, "eliminate_leader"))[0]
				st.leaders[n]["st"] = "elim"
				say("%s elimina %s (limite della riserva)." % [RBState.fshort(f), RB.leader_it(n)])


# ------------------------------------------------------------------ costruzione e schieramento

## Icone risorsa che una fazione usa in un sistema per costruire (vuoto se non può).
func build_icons(f: String, s: String) -> Array:
	if s == "BASE":
		if f != "R":
			return []
		if st.base_revealed and (st.has_units(st.base, "I") or st.sys[st.base]["loy"] == "I"):
			return []
		return ["BT", "OT"]
	if not st.is_populous(s) or st.sys[s]["sab"]:
		return []
	if st.has_units(s, RBState.other(f)):
		return []
	var icons: Array = RB.SYS[s]["icone"]
	if f == "R":
		if st.is_rebel_sys(s):
			return icons.duplicate()
		return []
	if st.sys[s]["loy"] == "I":
		return icons.duplicate()
	if st.sys[s]["subj"]:
		return [icons[0]] if not icons.is_empty() else []
	return []


func _build() -> void:
	say("Costruzione: ogni giocatore mette nuove unità nella coda di costruzione.")
	for f in ["R", "I"]:
		var places := []
		for s in st.all_systems():
			if not build_icons(f, s).is_empty():
				places.append(s)
		if f == "R":
			places.append("BASE")
		places.sort()
		var added := []
		for s in places:
			var icons := build_icons(f, s)
			var space: int = 1 if s == "BASE" else int(RB.SYS[s]["coda"])
			for ic in icons:
				var t := await choose_build_type(f, ic, s)
				if t != "":
					st.queue[f][space - 1].append(t)
					added.append(t)
		if not added.is_empty():
			say("%s costruisce: %s." % [RBState.fshort(f), _types_text(added)])
		_sync()


func _types_text(types: Array) -> String:
	var cnt := {}
	for t in types:
		cnt[t] = cnt.get(t, 0) + 1
	var parts := []
	for t in cnt:
		parts.append("%d %s" % [cnt[t], RB.unit_it(t)])
	return ", ".join(parts)


## Sceglie quale unità costruire per un'icona (i Ribelli hanno più modelli per la stessa icona).
func choose_build_type(f: String, icon: String, s: String) -> String:
	var types := []
	for t in RB.buildable(f, icon, st.opt["rote_units"]):
		if st.supply(t) > 0:
			types.append(t)
	if types.is_empty():
		return ""
	if types.size() == 1:
		return types[0]
	var opts := []
	for t in types:
		opts.append({"v": t, "l": RB.unit_it(t), "unit": t})
	return await ask(f, "Icona %s di %s: quale unità costruisci?" % [_icon_name(icon), RB.sys_name(s)], opts, "build_type", {"icon": icon})


func _icon_name(ic: String) -> String:
	var shape: String = {"T": "triangolo", "C": "cerchio", "S": "quadrato"}.get(ic.substr(1, 1), "?")
	return "%s %s" % [shape, "blu" if ic.begins_with("B") else "arancione"]


## Coda di costruzione: le unità avanzano; quelle che escono si schierano.
func _deploy() -> void:
	for f in ["R", "I"]:
		var q: Array = st.queue[f]
		var ready: Array = q[0].duplicate()
		q[0] = q[1].duplicate()
		q[1] = q[2].duplicate()
		q[2] = []
		if ready.is_empty():
			continue
		var back := await deploy_units(f, ready, 2)
		q[0].append_array(back)
		_sync()


## Sistemi dove una fazione può schierare unità.
func deploy_targets(f: String, t := "") -> Array:
	var out := []
	for s in st.all_systems():
		if st.sys[s]["sab"] or not st.is_populous(s) and not _bunker_remote(f, s):
			continue
		if st.has_units(s, RBState.other(f), "spazio") or st.has_units(s, RBState.other(f), "terra"):
			continue
		if f == "R" and st.is_rebel_sys(s):
			out.append(s)
		elif f == "I" and (st.is_imperial_sys(s) or _bunker_remote(f, s)):
			out.append(s)
	if f == "R" and not st.base_revealed:
		out.append("BASE")
	if f == "I" and t == "Shield Bunker":
		for s in st.all_systems():
			if not s in out and st.has_units(s, "I", "terra") and not st.has_units(s, "R") and not st.sys[s]["sab"]:
				out.append(s)
	if t == "Death Star":
		# la Morte Nera va solo nel sistema della Morte Nera in Costruzione
		var dsuc := []
		for id in st.units:
			if st.units[id]["t"] == "Death Star Under Construction":
				dsuc.append(st.units[id]["loc"])
		if not dsuc.is_empty():
			return dsuc
	out.sort()
	return out


func _bunker_remote(f: String, s: String) -> bool:
	return f == "I" and st.is_remote(s) and st.count_type(s, "Shield Bunker", "I") > 0 and not st.has_units(s, "R")


## Schiera le unità indicate (al massimo `per_sys` per sistema). Restituisce quelle non schierate.
func deploy_units(f: String, types: Array, per_sys: int) -> Array:
	var placed := {}
	var back := []
	var rest := types.duplicate()
	rest.sort_custom(func(a, b): return RB.health(a) > RB.health(b))
	for t in rest:
		var targets := []
		for s in deploy_targets(f, t):
			if placed.get(s, 0) < per_sys or t == "Death Star":
				targets.append(s)
		if targets.is_empty():
			back.append(t)
			continue
		var s := await ask_system(f, "Dove schieri %s? (puoi lasciarla nella casella 1 della coda)" % RB.unit_it(t), targets, "deploy", true, {"unit": t})
		if s == "":
			back.append(t)
			continue
		if t == "Death Star":
			for id in st.units.keys():
				if st.units[id]["t"] == "Death Star Under Construction" and st.units[id]["loc"] == s:
					st.remove_unit(id)
		st.add_unit(t, f, s)
		placed[s] = placed.get(s, 0) + 1
		say("%s schiera %s in %s." % [RBState.fshort(f), RB.unit_it(t), RB.sys_name(s) if s != "BASE" else "Base Ribelle"])
	return back
