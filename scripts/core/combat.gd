class_name RBCombat
extends RefCounted
## Combattimento: battaglia spaziale e terrestre, dadi, carte tattica, danni, ritirata.
## Due regolamenti: quello del gioco base (carte tattica condivise) e il combattimento
## cinematografico dell'Ascesa dell'Impero (carte tattica avanzate di ciascuna fazione).

var e: RBEngine
var c := {}            # stato del combattimento in corso

var st: RBState:
	get:
		return e.st


func _init(engine: RBEngine) -> void:
	e = engine


func say(t: String) -> void:
	e.say(t)


static func th_name(th: String) -> String:
	return "spaziale" if th == "spazio" else "terrestre"


func needs_combat(s: String) -> bool:
	if not RB.SYS.has(s):
		return false
	if st.has_units(s, "R", "spazio") and st.has_units(s, "I", "spazio"):
		return true
	if not st.sys[s]["dest"] and st.has_units(s, "R", "terra") and st.has_units(s, "I", "terra"):
		return true
	return false


func _both(th: String) -> bool:
	var s: String = c["sys"]
	if th == "terra" and st.sys[s]["dest"]:
		return false
	return st.has_units(s, "R", th) and st.has_units(s, "I", th)


# ================================================================== combattimento

func resolve(s: String, attacker: String, from_sources: Array) -> void:
	if not needs_combat(s) or not c.is_empty():
		return
	var defender := RBState.other(attacker)
	c = {"sys": s, "att": attacker, "def": defender, "round": 0, "from": from_sources,
		"start_th": {},
		"killed": {"R": [], "I": []},     # tipi di unità distrutte
		"won": {"R": {}, "I": {}}, "objective": false, "flags": {}, "retreated": {"R": false, "I": false},
		"cinematic": e.cinematic(), "minus_health": false, "ready_for_action": []}
	c["start_th"] = {"spazio": _both("spazio"), "terra": _both("terra")}
	c["was_subjugated"] = st.is_subjugated(s)
	c["vader_here"] = not (st.leaders_at(s, "I").filter(func(n): return n == "Darth Vader" or n == "Emperor Palpatine")).is_empty()
	say("[b]Combattimento su %s![/b] Attacca: %s." % [RB.sys_name(s), RBState.fname(attacker)])
	e.emit_fx("combat_start", {"sys": s})
	st.flags["in_combat"] = s
	e._sync()
	await e.pause(0.6)
	# 1. aggiungere un leader
	for f in [attacker, defender]:
		if st.has_tactic_leader(s, f):
			continue
		var pool := []
		for n in st.leader_pool(f):
			if RB.has_tactics(n):
				pool.append(n)
		if pool.is_empty():
			continue
		var opts := [{"v": "", "l": "Nessun leader"}]
		for n in pool:
			var L: Dictionary = RB.LEADERS[n]
			opts.append({"v": n, "l": "%s (spazio %d, terra %d)" % [RB.leader_it(n), L["spazio"], L["terra"]], "leader": n})
		var r = await e.ask(f, "Combattimento su %s: aggiungi un leader dalla riserva?" % RB.sys_name(s), opts, "combat_leader", {"confirm": true, "sys": s})
		if r != null and r != "":
			st.place_leader(r, s)
			say("%s aggiunge %s al combattimento." % [RBState.fshort(f), RB.leader_it(r)])
	e._sync()
	# carte azione "Inizio del Combattimento"
	for f in [attacker, defender]:
		await _start_of_combat_actions(f)
		if e._over():
			_end()
			return
	if not needs_combat(s):
		await _finish()
		return
	# 2. carte tattica
	if not c["cinematic"]:
		for f in [attacker, defender]:
			for th in ["spazio", "terra"]:
				if _both(th):
					var k := st.tactic_value(s, f, th) + int(c["flags"].get("draw3_" + f + th, 0))
					_draw_tactics(f, th, k)
	# 3. round di combattimento
	while not e._over():
		c["round"] += 1
		c.erase("rolled_ground_R")
		c.erase("rolled_ground_I")
		if _both("spazio"):
			await _battle("spazio")
			if e._over():
				break
			await _death_star_plans()
			if e._over():
				break
		if _both("terra"):
			await _battle("terra")
			if e._over():
				break
		await _structures_check()
		await _retreat_step()
		if e._over():
			break
		if c["cinematic"] and e.combat_cine != null:
			await e.combat_cine.after_retreat(self)
		if not (_both("spazio") or _both("terra")):
			break
		if c["round"] > 30:
			break
	await _finish()


func _end() -> void:
	c = {}
	st.flags.erase("in_combat")


func _finish() -> void:
	var s: String = c["sys"]
	# vittorie nelle battaglie
	for th in ["spazio", "terra"]:
		if not c["start_th"][th]:
			continue
		var r := st.has_units(s, "R", th)
		var i := st.has_units(s, "I", th)
		if r and not i:
			c["won"]["R"][th] = true
		elif i and not r:
			c["won"]["I"][th] = true
	for th in c["flags"].get("won_by_retreat", {}):
		c["won"][c["flags"]["won_by_retreat"][th]][th] = true
	await _combat_objectives_end()
	# fine: carte tattica e danni
	if not c["cinematic"]:
		for f in ["R", "I"]:
			for card in st.tac[f]:
				var th2: String = RB.card(card)["teatro"]
				st.deck["tac_dis_" + th2].append(card)
			st.tac[f].clear()
		for th3 in ["spazio", "terra"]:
			st.deck["tac_" + th3].append_array(st.deck["tac_dis_" + th3])
			st.deck["tac_dis_" + th3].clear()
			st.shuffle(st.deck["tac_" + th3])
	for id in st.units:
		st.units[id]["dmg"] = 0
	for n in c["ready_for_action"]:
		if st.leaders[n]["st"] == "board":
			st.to_pool(n)
	# "Qualcosa per cui combattere" (Jyn Erso)
	for th4 in c["won"]["R"]:
		for a in st.acts["R"].duplicate():
			if RB.base_id(a) == "something_to_fight_for" and _leader_here("Jyn Erso", "R") and not st.deck["obj_dis"].is_empty():
				if await e.ask_yes("R", "Hai vinto una battaglia: usi «Qualcosa per cui combattere» per rimettere in cima al mazzo un obiettivo scartato?", "use_something"):
					st.acts["R"].erase(a)
					var o: String = (await e.ask_pick("R", "cards", "Scegli l'obiettivo dalla pila degli scarti.", st.deck["obj_dis"].duplicate(), 1, 1, "pick_discard_obj", {"objectives": true}))[0]
					st.deck["obj_dis"].erase(o)
					st.deck["obj"].push_front(o)
		break
	say("Il combattimento su %s è finito." % RB.sys_name(s))
	e.emit_fx("combat_end", {"sys": s})
	st.update_subjugation(s)
	c = {}
	st.flags.erase("in_combat")
	await e.cards.auto_rescue()
	e._sync()


func _leader_here(n: String, f: String) -> bool:
	return n in st.leaders_at(c["sys"], f)


func _draw_tactics(f: String, th: String, k: int) -> void:
	for i in k:
		var card = st.draw("tac_" + th, "tac_dis_" + th)
		if card != null:
			st.tac[f].append(card)
	if k > 0:
		say("%s pesca %d carte tattica %s." % [RBState.fshort(f), k, "spaziali" if th == "spazio" else "terrestri"])


# ================================================================== carte azione di inizio combattimento

func _start_of_combat_actions(f: String) -> void:
	var s: String = c["sys"]
	while true:
		var opts := []
		for a in st.acts[f]:
			if RB.card(a).get("momento_en", "") != "Start of Combat":
				continue
			if not _action_leader_present(f, a):
				continue
			if not _start_action_useful(f, a):
				continue
			opts.append({"v": a, "l": "Usa «%s»" % RB.card_name(a), "card": a})
		if opts.is_empty():
			return
		opts.append({"v": "", "l": "Nessuna (continua)"})
		var r = await e.ask(f, "Inizio del combattimento: vuoi usare una carta azione?", opts, "start_combat_action", {"confirm": true})
		if r == null or r == "":
			return
		await _use_start_action(f, r)
		if e._over() or not needs_combat(s):
			return


func _action_leader_present(f: String, a: String) -> bool:
	var ls: Array = RB.card(a).get("leader", [])
	if ls.is_empty():
		return true
	var b := RB.base_id(a)
	if b == "ready_for_action":
		for n in ls:
			if n in st.leader_pool(f):
				return true
		return false
	for n in ls:
		if _leader_here(n, f):
			return true
	return false


func _start_action_useful(f: String, a: String) -> bool:
	var s: String = c["sys"]
	match RB.base_id(a):
		"target_the_generator":
			for id in st.units_at(s, "R"):
				if RB.is_structure(st.units[id]["t"]):
					return true
			return false
		"fully_operational":
			return (st.count_type(s, "Death Star", "I") + st.count_type(s, "Death Star Under Construction", "I")) > 0 and st.has_units(s, "R", "spazio")
		"its_a_trap", "target_the_star_destroyers":
			return _both("spazio")
		"keep_them_from_escaping":
			return true
	return true


func _use_start_action(f: String, a: String) -> void:
	var s: String = c["sys"]
	st.acts[f].erase(a)
	say("%s usa [b]%s[/b]." % [RBState.fshort(f), RB.card_name(a)])
	e.emit_fx("card", {"id": a, "f": f})
	match RB.base_id(a):
		"its_a_trap":
			c["flags"]["no_space_tactics_I_r1"] = true
		"good_intel", "good_intel_rote":
			c["flags"]["good_intel"] = true
		"more_dangerous_than_you_realize":
			var th = await e.ask(f, "Più pericoloso di quanto credi: quali carte tattica peschi?", [{"v": "spazio", "l": "3 carte tattica spaziali"}, {"v": "terra", "l": "3 carte tattica terrestri"}], "mdtyr")
			if c["cinematic"]:
				var key := "atac_dis_%s_%s" % [th, f]
				var back := 0
				while back < 3 and not st.deck[key].is_empty():
					st.deck["atac_%s_%s" % [th, f]].append(st.deck[key].pop_back())
					back += 1
			else:
				_draw_tactics(f, th, 3)
		"ready_for_action":
			var cand := []
			for n in RB.card(a).get("leader", []):
				if n in st.leader_pool(f):
					cand.append(n)
			if not cand.is_empty():
				var n2: String = (await e.ask_pick(f, "leaders", "Chi entra in azione?", cand, 1, 1, "action_leader"))[0]
				st.place_leader(n2, s)
				c["ready_for_action"].append(n2)
				c["flags"]["no_retreat_leader"] = n2
				say("%s entra nel combattimento." % RB.leader_it(n2))
		"target_the_generator":
			var structs := []
			for id in st.units_at(s, "R"):
				if RB.is_structure(st.units[id]["t"]):
					structs.append(id)
			if not structs.is_empty():
				var r = await e.decide(f, {"k": "units", "t": "Scegli la struttura da distruggere.", "opts": structs, "min": 1, "max": 1, "ctx": "destroy_structure"})
				var id2: int = r[0] if r is Array and not r.is_empty() and r[0] in structs else structs[0]
				_kill(id2)
		"point_blank_assault":
			c["minus_health"] = true
		"fully_operational":
			var ships := st.units_at(s, "R", "spazio")
			if not ships.is_empty():
				var r2 = await e.decide(f, {"k": "units", "t": "Scegli l'unità navale ribelle da distruggere.", "opts": ships, "min": 1, "max": 1, "ctx": "destroy_ship"})
				var id3: int = r2[0] if r2 is Array and not r2.is_empty() and r2[0] in ships else ships[0]
				_kill(id3)
		"keep_them_from_escaping":
			c["flags"]["rebels_no_retreat"] = true
		"according_to_my_design":
			c["flags"]["design"] = true
		"target_the_star_destroyers":
			c["flags"]["target_sd"] = true
		"bazes_loyalty":
			var cand2 := st.units_at(s, "I")
			var r3 = await e.decide(f, {"k": "units", "t": "La lealtà di Baze: scegli unità imperiali per un valore di salute fino a 2 da distruggere.", "opts": cand2, "min": 0, "max": cand2.size(), "max_health": 2, "ctx": "destroy", "enemy": "I", "sys": s})
			var tot := 0
			if r3 is Array:
				for id in r3:
					if id in cand2:
						var h := RB.health(st.units[id]["t"])
						if h > 0 and tot + h <= 2:
							tot += h
							_kill(id)
	_flush_kills()
	e._sync()


# ================================================================== distruzione e salute

func health_of(id: int) -> int:
	var h := RB.health(st.units[id]["t"])
	if c.get("minus_health", false):
		h = max(1, h - 1)
	return h


func _kill(id: int) -> void:
	if not st.units.has(id):
		return
	var u: Dictionary = st.units[id]
	c["killed"][u["f"]].append(u["t"])
	if u["t"] == "Death Star Under Construction":
		# la Morte Nera nella coda viene distrutta con la sua struttura
		for sp in 3:
			if "Death Star" in st.queue["I"][sp]:
				st.queue["I"][sp].erase("Death Star")
				say("La Morte Nera in costruzione è perduta, e con lei quella nella coda.")
				break
	if not c.has("pending_kill"):
		c["pending_kill"] = []
	c["pending_kill"].append(id)


func _flush_kills() -> void:
	var ids: Array = c.get("pending_kill", [])
	if ids.is_empty():
		return
	say("Distrutte: %s." % e.units_text(ids))
	e.emit_fx("destroy", {"ids": ids.duplicate(), "sys": c["sys"]})
	for id in ids:
		st.remove_unit(id)
	c["pending_kill"] = []
	# unità terrestri senza trasporto in un sistema distrutto
	e._sync()


# ================================================================== una battaglia (spaziale o terrestre)

func _battle(th: String) -> void:
	var att: String = c["att"]
	var def: String = c["def"]
	say("Round %d: battaglia %s." % [c["round"], th_name(th)])
	e.emit_fx("battle", {"th": th, "round": c["round"]})
	if c["cinematic"] and e.combat_cine != null:
		await e.combat_cine.round_of_battle(self, th)
		return
	# generatori di scudo: 1 carta tattica terrestre all'inizio di ogni battaglia terrestre
	if th == "terra":
		var k := st.count_type(c["sys"], "Shield Generator", "R")
		if k > 0:
			_draw_tactics("R", "terra", k)
	var order := [att, def]
	for f in order:
		if not st.has_units(c["sys"], f, th):
			continue
		await _attack(f, th)
		if e._over():
			return
	_flush_kills()
	await _combat_objectives_now()


## Dadi che una fazione tira in un attacco: [{c: "rosso"|"nero"|"verde", v: faccia}].
func attack_dice(f: String, th: String) -> Dictionary:
	var s: String = c["sys"]
	var red := 0
	var black := 0
	var green := 0
	for id in st.units_at(s, f, th):
		var u: Dictionary = RB.UNITS[st.units[id]["t"]]
		red += int(u["rossi"])
		black += int(u["neri"])
		green += int(u["verdi"])
	# Cannoni a Ioni: l'Impero tira 2 dadi rossi in meno per ogni cannone nella battaglia spaziale
	if th == "spazio" and f == "I":
		red -= 2 * st.count_type(s, "Ion Cannon", "R")
	if c["flags"].get("design", false) and f == "R" and c["round"] == 1:
		red -= 1
		black -= 2
	return {"rossi": clamp(red, 0, 5), "neri": clamp(black, 0, 5), "verdi": clamp(green, 0, 3)}


func roll_attack(f: String, th: String) -> Array:
	var n := attack_dice(f, th)
	var dice := []
	for i in n["rossi"]:
		dice.append({"c": "rosso", "v": st._face()})
	for i in n["neri"]:
		dice.append({"c": "nero", "v": st._face()})
	for i in n["verdi"]:
		dice.append({"c": "verde", "v": st.green_face()})
	return dice


func _attack(f: String, th: String) -> void:
	var s: String = c["sys"]
	var o := RBState.other(f)
	var dice := roll_attack(f, th)
	if dice.is_empty():
		return
	if th == "terra" and e.rote():
		c["rolled_ground_" + f] = true
	e.emit_fx("combat_dice", {"f": f, "dice": dice.duplicate(true), "th": th})
	say("%s tira %d dadi: %s." % [RBState.fshort(f), dice.size(), dice_text(dice)])
	await e.pause(0.9)
	c["pending"] = {}    # id → danni di questo attacco
	c["step_flags"] = {}
	# azioni di combattimento: pescare e giocare carte tattica
	var guard := 0
	while guard < 30:
		guard += 1
		var opts := _combat_actions(f, th, dice)
		if opts.size() <= 1:
			break
		var r = await e.ask(f, "%s: azioni di combattimento (dadi: %s)." % [RBState.fshort(f), dice_text(dice)], opts, "combat_action", {"confirm": true, "th": th, "dice": dice.duplicate(true)})
		if r == null or r == "done":
			break
		if r == "draw":
			_spend_special(dice)
			_draw_tactics(f, th, 1)
		elif r == "sd":
			c["step_flags"]["sd_done"] = true
		else:
			await _play_tactic(f, r, th, dice)
		e._sync()
	# "Puntate agli Star Destroyer": fino a 2 colpi neri valgono come rossi
	if f == "R" and th == "spazio" and c["flags"].get("target_sd", false):
		var k := 0
		for d in dice:
			if d["c"] == "nero" and d["v"] == 1 and k < 2 and not d.get("spent", false):
				d["c"] = "rosso"
				k += 1
	# assegnare i danni dei dadi
	await _assign_dice(f, th, dice)
	# l'avversario blocca
	await _block(o, th)
	# applicare
	for id in c["pending"]:
		if not st.units.has(id):
			continue
		st.units[id]["dmg"] += int(c["pending"][id])
		if st.units[id]["dmg"] >= health_of(id) and RB.health(st.units[id]["t"]) > 0:
			if not id in c.get("pending_kill", []):
				_kill(id)
	c["pending"] = {}
	e._sync()


static func dice_text(dice: Array) -> String:
	var parts := []
	for d in dice:
		if d.get("spent", false):
			continue
		var face: String = ["vuoto", "colpo", "colpo diretto", "speciale"][int(d["v"])]
		parts.append("%s %s" % [face, d["c"]])
	return ", ".join(parts) if not parts.is_empty() else "nessuno"


func _spend_special(dice: Array) -> bool:
	for d in dice:
		if int(d["v"]) == 3 and not d.get("spent", false):
			d["spent"] = true
			return true
	return false


func _has_special(dice: Array) -> bool:
	for d in dice:
		if int(d["v"]) == 3 and not d.get("spent", false):
			return true
	return false


func _combat_actions(f: String, th: String, dice: Array) -> Array:
	var opts := []
	var o := RBState.other(f)
	var blocked: bool = c["flags"].get("no_space_tactics_I_r1", false) and f == "I" and th == "spazio" and c["round"] == 1
	if not blocked:
		for card in st.tac[f]:
			var info := RB.card(card)
			if info["teatro"] != th:
				continue
			var b := RB.base_id(card)
			if b.ends_with("defensive_formation") or b.ends_with("outmaneuver") or b.ends_with("dig_in"):
				continue   # si giocano quando si bloccano i danni
			if info.get("speciale", false) and not _has_special(dice):
				continue
			if b.ends_with("no_escape") or b.ends_with("escape_plan") or b.ends_with("unstoppable_assault") or b.ends_with("brilliant_strategy") or b.ends_with("concentrate_fire") or b.ends_with("bombardment") or b.ends_with("critical_hit") or b.ends_with("onslaught") or b.ends_with("take_it_down"):
				if b.ends_with("bombardment") and _best_red_ship(f) == 0:
					continue
				if b.ends_with("escape_plan") and st.leaders_at(c["sys"], f).is_empty():
					continue
				opts.append({"v": card, "l": "Gioca «%s»" % RB.card_name(card), "card": card})
	if _has_special(dice) and not blocked:
		opts.append({"v": "draw", "l": "Spendi un risultato speciale per pescare 1 carta tattica %s" % ("spaziale" if th == "spazio" else "terrestre")})
	opts.append({"v": "done", "l": "Assegna i danni"})
	return opts


func _best_red_ship(f: String) -> int:
	var best := 0
	for id in st.units_at(c["sys"], f, "spazio"):
		best = max(best, int(RB.UNITS[st.units[id]["t"]]["rossi"]))
	return best


func _play_tactic(f: String, card: String, th: String, dice: Array) -> void:
	var b := RB.base_id(card).substr(3)
	var info := RB.card(card)
	if info.get("speciale", false):
		_spend_special(dice)
	st.tac[f].erase(card)
	st.deck["tac_dis_" + th].append(card)
	say("%s gioca la tattica [b]%s[/b]." % [RBState.fshort(f), RB.card_name(card)])
	e.emit_fx("card", {"id": card, "f": f})
	var o := RBState.other(f)
	match b:
		"unstoppable_assault":
			c["step_flags"]["no_block"] = true
		"no_escape":
			c["flags"]["no_retreat_round_" + o] = c["round"]
		"escape_plan":
			c["flags"]["escape_plan_" + f] = c["round"]
		"brilliant_strategy":
			var r = await e.ask(f, "Strategia geniale: quali carte peschi?", [{"v": "ss", "l": "2 carte spaziali"}, {"v": "tt", "l": "2 carte terrestri"}, {"v": "st", "l": "1 spaziale e 1 terrestre"}], "brilliant")
			match r:
				"ss": _draw_tactics(f, "spazio", 2)
				"tt": _draw_tactics(f, "terra", 2)
				_:
					_draw_tactics(f, "spazio", 1)
					_draw_tactics(f, "terra", 1)
		"concentrate_fire":
			var idx := []
			for i in dice.size():
				if not dice[i].get("spent", false):
					idx.append(i)
			var r2 = await e.decide(f, {"k": "dice_pick", "t": "Concentrare il fuoco: scegli fino a 2 dadi da ritirare.", "dice": dice.duplicate(true), "opts": idx, "max": 2, "ctx": "reroll"})
			var k := 0
			if r2 is Array:
				for i in r2:
					if i in idx and k < 2:
						dice[i]["v"] = st.green_face() if dice[i]["c"] == "verde" else st._face()
						k += 1
			say("Nuovi dadi: %s." % dice_text(dice))
			e.emit_fx("combat_dice", {"f": f, "dice": dice.duplicate(true), "th": th})
		"critical_hit":
			await _card_damage(f, th, 1, 1)
		"onslaught":
			await _card_damage(f, th, 2, 1, true)
		"take_it_down":
			await _card_damage(f, th, 1, 2)
		"bombardment":
			await _card_damage(f, "terra", 1, _best_red_ship(f))


## Danni inflitti da una carta: n bersagli (diversi se distinct), k danni ciascuno.
func _card_damage(f: String, th: String, n: int, k: int, distinct := false) -> void:
	var o := RBState.other(f)
	var cand := []
	for id in st.units_at(c["sys"], o, th):
		if RB.health(st.units[id]["t"]) > 0:
			cand.append(id)
	if cand.is_empty() or k <= 0:
		return
	var r = await e.decide(f, {"k": "units", "t": "Scegli %s a cui infliggere %d dann%s." % ["fino a %d unità diverse" % n if n > 1 else "l'unità", k, "o" if k == 1 else "i"], "opts": cand, "min": 1, "max": n, "ctx": "card_damage", "dmg": k, "sys": c["sys"]})
	var sel := []
	if r is Array:
		for id in r:
			if id in cand and not id in sel and sel.size() < n:
				sel.append(id)
	if sel.is_empty():
		sel.append(cand[0])
	for id in sel:
		c["pending"][id] = int(c["pending"].get(id, 0)) + k
		say("%d dann%s a %s." % [k, "o" if k == 1 else "i", st.unit_name(id)])


## Chi tira assegna i danni dei dadi alle unità avversarie dello stesso teatro.
func _assign_dice(f: String, th: String, dice: Array) -> void:
	var o := RBState.other(f)
	var targets := []
	for id in st.units_at(c["sys"], o, th):
		if RB.health(st.units[id]["t"]) > 0:
			targets.append(id)
	var useful := []
	for i in dice.size():
		var d: Dictionary = dice[i]
		if d.get("spent", false):
			continue
		if int(d["v"]) == 1 or int(d["v"]) == 2:
			useful.append(i)
	if useful.is_empty() or targets.is_empty():
		return
	var r = await e.decide(f, {"k": "damage", "t": "Assegna i danni alle unità avversarie.", "dice": dice.duplicate(true), "opts": targets, "ctx": "assign_damage", "th": th, "sys": c["sys"], "pending": c["pending"].duplicate()})
	var assigned := {}
	if r is Dictionary:
		for k in r:
			var i := int(k)
			var id := int(r[k])
			if i in useful and id in targets and _can_take(dice[i], id):
				assigned[i] = id
	# i dadi non assegnati che potevano esserlo vengono assegnati automaticamente
	for i in useful:
		if assigned.has(i):
			continue
		for id in targets:
			if _can_take(dice[i], id):
				assigned[i] = id
				break
	for i in assigned:
		var id2: int = assigned[i]
		c["pending"][id2] = int(c["pending"].get(id2, 0)) + 1
	if not assigned.is_empty():
		var hit := {}
		for i in assigned:
			hit[assigned[i]] = hit.get(assigned[i], 0) + 1
		var parts := []
		for id3 in hit:
			parts.append("%s %d" % [st.unit_name(id3), hit[id3]])
		say("Danni: %s." % ", ".join(parts))
		e.emit_fx("damage", {"hits": hit})


func _can_take(d: Dictionary, id: int) -> bool:
	var v := int(d["v"])
	if v == 2:
		return true
	if v != 1:
		return false
	var hc := RB.health_color(st.units[id]["t"])
	if d["c"] == "verde":
		return true
	return hc == d["c"]


## L'avversario gioca le carte che bloccano i danni di questo attacco.
func _block(o: String, th: String) -> void:
	if c["step_flags"].get("no_block", false):
		return
	var guard := 0
	while guard < 10 and not c["pending"].is_empty():
		guard += 1
		var opts := []
		for card in st.tac[o]:
			var b := RB.base_id(card)
			if RB.card(card)["teatro"] != th:
				continue
			if b.ends_with("defensive_formation"):
				opts.append({"v": card, "l": "Gioca «%s» (blocca 1 danno)" % RB.card_name(card), "card": card})
			elif (b.ends_with("outmaneuver") or b.ends_with("dig_in")) and _other_tactic(o, th, card) != "":
				opts.append({"v": card, "l": "Gioca «%s» (scarta un'altra carta tattica, blocca fino a 2 danni)" % RB.card_name(card), "card": card})
		if opts.is_empty():
			return
		opts.append({"v": "", "l": "Non bloccare"})
		var r = await e.ask(o, "Blocchi dei danni? (danni in arrivo: %s)" % _pending_text(), opts, "block", {"confirm": true, "pending": c["pending"].duplicate(), "th": th})
		if r == null or r == "":
			return
		var k := 1
		st.tac[o].erase(r)
		st.deck["tac_dis_" + th].append(r)
		if not RB.base_id(r).ends_with("defensive_formation"):
			var other := _other_tactic(o, th, r)
			st.tac[o].erase(other)
			st.deck["tac_dis_" + th].append(other)
			k = 2
		say("%s gioca [b]%s[/b] e blocca %d dann%s." % [RBState.fshort(o), RB.card_name(r), k, "o" if k == 1 else "i"])
		for i in k:
			if c["pending"].is_empty():
				break
			var ids: Array = c["pending"].keys()
			var r2 = await e.decide(o, {"k": "units", "t": "Da quale unità togli un danno?", "opts": ids, "min": 1, "max": 1, "ctx": "block_target", "pending": c["pending"].duplicate()})
			var id: int = r2[0] if r2 is Array and not r2.is_empty() and r2[0] in ids else ids[0]
			c["pending"][id] = int(c["pending"][id]) - 1
			if int(c["pending"][id]) <= 0:
				c["pending"].erase(id)
		e._sync()


func _other_tactic(o: String, th: String, except: String) -> String:
	for card in st.tac[o]:
		if card != except and RB.card(card)["teatro"] == th:
			return card
	return ""


func _pending_text() -> String:
	var parts := []
	for id in c["pending"]:
		if st.units.has(id):
			parts.append("%s %d" % [st.unit_name(id), c["pending"][id]])
	return ", ".join(parts)


# ================================================================== strutture, Morte Nera

func _structures_check() -> void:
	var s: String = c["sys"]
	for f in ["R", "I"]:
		var o := RBState.other(f)
		if not st.has_units(s, o, "terra"):
			continue
		var mine := st.units_at(s, f, "terra")
		if mine.is_empty():
			continue
		var only_struct := true
		for id in mine:
			if not RB.is_structure(st.units[id]["t"]):
				only_struct = false
		if only_struct and not c.get("rolled_ground_" + f, false):
			for id in mine:
				_kill(id)
			say("Le strutture rimaste senza difesa su %s vengono distrutte." % RB.sys_name(s))
	# Morte Nera in costruzione da sola contro navi ribelli
	var imp_ships := st.units_at(s, "I", "spazio")
	if imp_ships.size() > 0 and st.has_units(s, "R", "spazio"):
		var only_dsuc := true
		for id in imp_ships:
			if st.units[id]["t"] != "Death Star Under Construction":
				only_dsuc = false
		if only_dsuc and st.count_type(s, "Shield Bunker", "I") == 0:
			for id in imp_ships:
				_kill(id)
	_flush_kills()


func _death_star_plans() -> void:
	var s: String = c["sys"]
	if c["objective"]:
		return
	var ds := []
	for id in st.units_at(s, "I", "spazio"):
		if st.units[id]["t"] == "Death Star" or st.units[id]["t"] == "Death Star Under Construction":
			ds.append(id)
	if ds.is_empty():
		return
	if st.count_type(s, "Shield Bunker", "I") > 0:
		return
	for m in st.markers:
		if RB.base_id(m.get_slice("@", 0)) == "secure_the_plans":
			return
	var fighters := false
	for id in st.units_at(s, "R", "spazio"):
		if RB.is_fighter(st.units[id]["t"]):
			fighters = true
	if not fighters:
		return
	for o in st.objs.duplicate():
		if RB.base_id(o) != "ob_death_star_plans":
			continue
		if not await e.ask_yes("R", "Hai caccia nel sistema della Morte Nera: riveli «Piani della Morte Nera» e tiri 3 dadi?", "use_dsp"):
			return
		var dice := st.roll(3)
		e.emit_fx("dice", {"dice": dice, "f": "R"})
		# "Uno su un milione": un colpo diretto garantito
		if not 2 in dice:
			for a in st.acts["R"].duplicate():
				if RB.base_id(a) == "one_in_a_million" and (_leader_here("Luke Skywalker", "R") or _leader_here("Luke Skywalker (Jedi)", "R") or _leader_here("Wedge Antilles", "R")):
					if await e.ask_yes("R", "Usi «Uno su un milione» per ottenere il colpo diretto?", "use_one_in_a_million"):
						st.acts["R"].erase(a)
						dice[0] = 2
		if 2 in dice:
			var target: int = ds[0]
			for id in ds:
				if st.units[id]["t"] == "Death Star":
					target = id
			say("[b]Un colpo da un milione: la %s esplode![/b]" % st.unit_name(target))
			e.emit_fx("deathstar_boom", {"sys": s})
			_kill(target)
			_flush_kills()
			st.objs.erase(o)
			st.deck["obj_dis"].append(o)
			c["objective"] = true
			e.cards.gain_rep(int(RB.card(o)["reputazione"]))
		else:
			say("I caccia ribelli mancano il condotto di scarico: «Piani della Morte Nera» torna in mano.")
		return


# ================================================================== obiettivi di combattimento

func _initiated_by_rebels() -> bool:
	return c["att"] == "R"


func _killed_health(f: String, th: String) -> int:
	var h := 0
	for t in c["killed"][f]:
		if RB.UNITS[t]["teatro"] == th:
			h += RB.health(t)
	return h


func _combat_objectives_now() -> void:
	if c["objective"]:
		return
	var avail := []
	for o in st.objs:
		var b := RB.base_id(o)
		var ok := false
		match b:
			"ob_rebel_assault":
				ok = _initiated_by_rebels() and ("Star Destroyer" in c["killed"]["I"] or "Super Star Destroyer" in c["killed"]["I"])
			"ob_crippling_blow":
				ok = _initiated_by_rebels() and _killed_health("I", "terra") >= 3
			"ob_major_victory":
				ok = _initiated_by_rebels() and _killed_health("I", "spazio") >= 3
		if ok:
			avail.append(o)
	await _offer_objectives(avail)


func _combat_objectives_end() -> void:
	if c["objective"]:
		return
	var s: String = c["sys"]
	var won: Dictionary = c["won"]["R"]
	var avail := []
	for o in st.objs:
		var b := RB.base_id(o)
		var ok := false
		match b:
			"ob_rebel_assault":
				ok = _initiated_by_rebels() and ("Star Destroyer" in c["killed"]["I"] or "Super Star Destroyer" in c["killed"]["I"])
			"ob_crippling_blow":
				ok = _initiated_by_rebels() and _killed_health("I", "terra") >= 3
			"ob_major_victory":
				ok = _initiated_by_rebels() and _killed_health("I", "spazio") >= 3
			"ob_liberation":
				ok = won.get("terra", false) and (st.is_subjugated(s) or c.get("was_subjugated", false))
			"ob_return_of_the_jedi":
				ok = not won.is_empty() and (c.get("vader_here", false) or _leader_here("Darth Vader", "I") or _leader_here("Emperor Palpatine", "I"))
			"ob_decisive_victory":
				ok = won.get("terra", false) and won.get("spazio", false)
			"ob_seize_control":
				ok = not won.is_empty() and st.sys[s]["sab"]
			"ob_raid_imperial_factory":
				ok = _initiated_by_rebels() and not won.is_empty() and ("BS" in RB.SYS[s]["icone"] or "OS" in RB.SYS[s]["icone"])
		if ok:
			avail.append(o)
	await _offer_objectives(avail)


func _offer_objectives(avail: Array) -> void:
	if avail.is_empty():
		return
	var opts := [{"v": "", "l": "Non giocare obiettivi"}]
	for o in avail:
		opts.append({"v": o, "l": "Gioca: " + RB.card_name(o), "card": o})
	var r = await e.ask("R", "Puoi giocare un obiettivo di combattimento.", opts, "combat_objective", {"confirm": true})
	if r == null or r == "":
		return
	c["objective"] = true
	var b := RB.base_id(r)
	await e.cards.play_objective(r)
	var s: String = c["sys"]
	if b == "ob_return_of_the_jedi" and _leader_here("Luke Skywalker (Jedi)", "R"):
		var imps := st.leaders_at(s, "I")
		if not imps.is_empty():
			var n: String = (await e.ask_pick("R", "leaders", "Il ritorno dello Jedi: scegli un leader imperiale da eliminare.", imps, 1, 1, "rotj_who"))[0]
			st.leaders[n]["st"] = "elim"
			say("[b]%s viene eliminato.[/b]" % RB.leader_it(n))
	if b == "ob_seize_control" and st.sys[s]["sab"]:
		if await e.ask_yes("R", "Rimuovi il segnalino sabotaggio da %s?" % RB.sys_name(s), "seize_remove"):
			st.sys[s]["sab"] = false


# ================================================================== ritirata

func _retreat_step() -> void:
	var s: String = c["sys"]
	for f in [c["att"], c["def"]]:
		if not needs_combat(s) and not _transport_alone(f):
			continue
		if c["retreated"][f]:
			continue
		await _maybe_retreat(f)
		if e._over():
			return
	# trasporti ribelli soli contro navi imperiali: distrutti
	if _transport_alone("R"):
		for id in st.units_at(s, "R", "spazio"):
			_kill(id)
		say("I Trasporti Ribelli senza scorta vengono distrutti.")
		_flush_kills()


func _transport_alone(f: String) -> bool:
	if f != "R":
		return false
	var s: String = c["sys"]
	var ships := st.units_at(s, "R", "spazio")
	if ships.is_empty() or not st.has_units(s, "I", "spazio"):
		return false
	for id in ships:
		if st.units[id]["t"] != "Rebel Transport":
			return false
	return true


func retreat_destinations(f: String) -> Array:
	var s: String = c["sys"]
	var o := RBState.other(f)
	var adj: Array = RB.SYS[s]["adiacenti"]
	var allowed := []
	for x in adj:
		if st.has_units(x, o):
			continue
		if x in c["from"] and f == c["def"]:
			continue
		allowed.append(x)
	var preferred := []
	for x in allowed:
		if st.has_units(x, f) or st.has_loyalty(f, x):
			preferred.append(x)
	return preferred if not preferred.is_empty() else allowed


func _maybe_retreat(f: String) -> void:
	var s: String = c["sys"]
	if not st.has_units(s, RBState.other(f)):
		return
	if f == "R" and c["flags"].get("rebels_no_retreat", false):
		return
	if c["flags"].get("no_retreat_round_" + f, -1) == c["round"]:
		return
	if f == "R" and st.count_type(s, "Interdictor", "I") > 0:
		return
	if f == "I" and (st.count_type(s, "Death Star", "I") + st.count_type(s, "Death Star Under Construction", "I")) > 0:
		return
	var ls := st.leaders_at(s, f)
	ls.erase(c["flags"].get("no_retreat_leader", ""))
	if ls.is_empty():
		return
	var mobile := []
	for id in st.units_at(s, f):
		if not RB.UNITS[st.units[id]["t"]]["immobile"]:
			mobile.append(id)
	if mobile.is_empty():
		return
	var dests := retreat_destinations(f)
	if dests.is_empty():
		return
	var forced := _transport_alone(f)
	var opts := [{"v": "", "l": "Resta a combattere" if not forced else "Resta (i Trasporti saranno distrutti)"}]
	for x in dests:
		opts.append({"v": x, "l": "Ritirati in %s" % RB.sys_name(x), "sys": x})
	var r = await e.ask(f, "Fase di ritirata su %s: vuoi ritirarti?" % RB.sys_name(s), opts, "retreat", {"confirm": true, "sys": s})
	if r == null or r == "":
		return
	var dest: String = r
	var n: String = ls[0]
	if ls.size() > 1:
		n = (await e.ask_pick(f, "leaders", "Quale leader guida la ritirata?", ls, 1, 1, "retreat_leader"))[0]
	# si devono portare via tutte le navi; unità terrestri e Caccia TIE a scelta
	var ships := []
	var optional := []
	for id in mobile:
		var t: String = st.units[id]["t"]
		if RB.is_ship(t) and not st.needs_transport(id):
			ships.append(id)
		else:
			optional.append(id)
	var take := []
	if not optional.is_empty():
		var cap := st.transport_capacity(ships)
		var ignore: bool = c["flags"].get("escape_plan_" + f, -1) == c["round"]
		var r2 = await e.decide(f, {"k": "units", "t": "Quali unità terrestri e caccia TIE porti via? (capacità di trasporto: %s)" % ("illimitata" if ignore else str(cap)), "opts": optional, "min": 0, "max": optional.size() if ignore else min(cap, optional.size()), "ctx": "retreat_units", "sys": s})
		if r2 is Array:
			for id in r2:
				if id in optional and (ignore or take.size() < cap):
					take.append(id)
	var moving := ships + take
	for id in moving:
		st.move_unit(id, dest)
	st.place_leader(n, dest)
	c["retreated"][f] = true
	say("%s si ritira in %s con %s." % [RBState.fshort(f), RB.sys_name(dest), e.units_text(moving) if not moving.is_empty() else "nessuna unità"])
	e.emit_fx("move", {"ids": moving, "to": dest})
	# chi resta senza unità in un teatro dopo la ritirata perde quella battaglia
	for th in ["spazio", "terra"]:
		if c["start_th"][th] and not st.has_units(s, f, th) and st.has_units(s, RBState.other(f), th):
			if not c["flags"].has("won_by_retreat"):
				c["flags"]["won_by_retreat"] = {}
			c["flags"]["won_by_retreat"][th] = RBState.other(f)
	# "Seguili" (Track Them): l'Impero richiama un leader dopo la ritirata ribelle
	if f == "R":
		for a in st.acts["I"].duplicate():
			if RB.base_id(a) == "track_them":
				var imps := st.leaders_at(s, "I")
				if imps.is_empty():
					break
				if await e.ask_yes("I", "I Ribelli si sono ritirati: usi «Seguili» per riportare un leader imperiale nella riserva?", "use_track_them"):
					st.acts["I"].erase(a)
					var who: String = (await e.ask_pick("I", "leaders", "Quale leader torna nella riserva?", imps, 1, 1, "track_who"))[0]
					st.to_pool(who)
					say("%s torna nella riserva («Seguili»)." % RB.leader_it(who))
	e._sync()
