class_name RBCards
extends RefCounted
## Le regole delle carte: missioni (anche progetti), carte azione, obiettivi e anelli.
## Ogni effetto è una funzione che può chiedere decisioni ai giocatori tramite il motore.

var e: RBEngine

var st: RBState:
	get:
		return e.st


func _init(engine: RBEngine) -> void:
	e = engine


static func bid(c: String) -> String:
	return RB.base_id(c)


func say(t: String) -> void:
	e.say(t)


func fs(f: String) -> String:
	return RBState.fshort(f)


# ================================================================== bersagli delle missioni

## Sistemi (o leader) in cui una missione può essere tentata o risolta.
## Restituisce un array di {"sys": sistema, "leader": nome o ""}.
func targets(f: String, c: String, assigned: Array) -> Array:
	var b := bid(c)
	var out := []
	var all := st.all_systems()
	var against := ""   # "", "rebel_imp_unit", "rebel_any", "captured", "captured_remote"
	match b:
		"construct_super_star_destroyer", "construct_super_star_destroyer_rote", "interdictor_development":
			for s in all:
				if st.is_imperial_sys(s) and "BS" in RB.SYS[s]["icone"] and not st.sys[s]["dest"]:
					out.append(s)
		"construct_factory", "secret_weapons_research", "address_delays", "double_our_efforts", "promotion":
			for s in all:
				if st.is_imperial_sys(s):
					out.append(s)
		"superlaser_online", "single_reactor_ignition":
			for s in all:
				if st.count_type(s, "Death Star", "I") > 0:
					out.append(s)
		"research_and_development":
			for s in all:
				if st.has_loyalty("I", s):
					out.append(s)
		"gather_intel", "intercept_transmission", "stolen_intel":
			for s in all:
				if st.is_rebel_sys(s):
					out.append(s)
		"capture_rebel_operative":
			against = "rebel_imp_unit"
		"rule_by_fear":
			for s in all:
				if st.is_populous(s) and st.has_units(s, "I"):
					out.append(s)
		"trade_negotiations", "display_of_power", "build_alliance", "message_from_high_command":
			for s in all:
				if st.is_populous(s) and s != "CORUSCANT":
					out.append(s)
		"carbon_freezing", "interrogation", "homing_beacon", "interrogation_droid", "retrieve_the_plans", "lure_of_the_dark_side", "break_their_will", "exploit_weakness", "were_the_bait":
			against = "captured"
		"make_an_example":
			against = "captured_remote"
		"planetary_conquest", "long_range_probe", "hunt_them_down", "hit_and_run", "lead_the_strike_team", "regional_aid", "plant_explosives", "sabotage_rote":
			for s in all:
				out.append(s)
		"sabotage":
			for s in all:
				if st.is_populous(s):
					out.append(s)
		"collect_bounty", "detained":
			against = "rebel_any"
		"oversee_project":
			for s in all:
				if st.has_units(s, "I") and not st.has_units(s, "R") and not st.sys[s]["sab"]:
					out.append(s)
		"construct_death_star":
			for s in all:
				if st.is_remote(s) and not st.has_units(s, "R"):
					out.append(s)
		"probe_droid_initiative":
			for s in all:
				if st.count_type(s, "Star Destroyer", "I") + st.count_type(s, "Super Star Destroyer", "I") > 0:
					out.append(s)
		"imperial_propaganda":
			for s in all:
				if st.is_imperial_sys(s):
					out.append(s)
		"fear_will_keep_them_in_line":
			for s in all:
				if st.count_type(s, "Death Star", "I") + st.count_type(s, "Star Destroyer", "I") + st.count_type(s, "Super Star Destroyer", "I") > 0:
					out.append(s)
		"daring_rescue", "for_the_greater_good", "aggressive_negotiations", "critical_rescue":
			for s in all:
				if not st.captured_at(s).is_empty():
					out.append(s)
		"base_defenses":
			for s in all:
				if st.is_rebel_sys(s):
					out.append(s)
		"misdirection", "plant_false_lead", "stolen_plans", "infiltration", "covert_operation", "heist":
			for s in all:
				if st.has_units(s, "I"):
					out.append(s)
		"hidden_fleet":
			for s in all:
				if not st.has_units(s, "I"):
					out.append(s)
		"incite_rebellion", "public_uprising", "assault", "prepare_for_battle":
			for s in all:
				if st.is_subjugated(s):
					out.append(s)
		"wookiee_uprising":
			out.append("KASHYYYK")
		"establish_trade_relations":
			for s in all:
				if not st.sys[s]["sab"]:
					out.append(s)
		"rapid_mobilization":
			out.append("BASE" if not st.base_revealed else st.base)
		"plan_the_assault":
			for s in all:
				if st.has_units(s, "I", "spazio"):
					out.append(s)
		"rogue_squadron_raid", "demolition", "reconnaissance":
			for s in all:
				if st.is_imperial_sys(s):
					out.append(s)
		"seek_yoda":
			out.append("DAGOBAH")
		"support_of_mon_calamari":
			out.append("MON CALAMARI")
		"deployment":
			for s in all:
				if not st.has_units(s, "R") and not st.has_loyalty("R", s):
					out.append(s)
		"discredit_rebellion":
			for s in all:
				if st.sys[s]["sab"]:
					out.append(s)
		"draw_them_out":
			if not st.leader_pool("R").is_empty():
				for s in all:
					if not st.has_units(s, "R"):
						out.append(s)
		"hire_mercenaries":
			if _box_leaders("I", false).size() > 0:
				for s in all:
					if st.is_remote(s):
						out.append(s)
		"imperial_might":
			for s in all:
				if not st.has_units(s, "R") and (st.count_type(s, "Death Star", "I") + st.count_type(s, "Death Star Under Construction", "I") + st.count_type(s, "Shield Bunker", "I") > 0):
					out.append(s)
		"secure_the_plans":
			for s in all:
				if st.is_remote(s):
					out.append(s)
		"behind_enemy_lines":
			for s in all:
				if st.is_subjugated(s) or st.is_rebel_sys(s):
					out.append(s)
		"my_only_hope":
			if not _my_only_hope_leaders().is_empty():
				for s in all:
					if st.is_remote(s):
						out.append(s)
		"safe_haven":
			for s in all:
				if st.is_rebel_sys(s) and not st.has_units(s, "I"):
					out.append(s)
		"secret_mission":
			for s in all:
				if st.is_rebel_sys(s):
					out.append(s)
		_:
			pass
	var res := []
	if against == "":
		for s in out:
			res.append({"sys": s, "leader": ""})
		return res
	for n in st.leaders:
		var l: Dictionary = st.leaders[n]
		if l["st"] != "board" or l["home"] != "R":
			continue
		var s: String = l["loc"]
		match against:
			"rebel_imp_unit":
				if l["f"] == "R" and not st.is_captured(n) and l["ring"] != "lure" and RB.SYS.has(s) and st.has_units(s, "I"):
					res.append({"sys": s, "leader": n})
			"rebel_any":
				if l["f"] == "R" and not st.is_captured(n) and l["ring"] != "lure":
					res.append({"sys": s, "leader": n})
			"captured":
				if st.is_captured(n):
					res.append({"sys": s, "leader": n})
			"captured_remote":
				if st.is_captured(n) and st.is_remote(s):
					res.append({"sys": s, "leader": n})
	return res


func _box_leaders(f: String, with_tactics: bool) -> Array:
	var out := []
	for n in st.leaders:
		if st.leaders[n]["st"] == "box" and st.leaders[n]["home"] == f and RB.has_tactics(n) == with_tactics:
			out.append(n)
	out.sort()
	return out


func _my_only_hope_leaders() -> Array:
	var out := []
	for n in ["Luke Skywalker", "Obi-Wan Kenobi", "Han Solo", "Chirrut Imwe", "Jyn Erso"]:
		if st.leaders.has(n) and st.leaders[n]["st"] == "box":
			out.append(n)
	return out


## Abilità richiesta e livello di una missione; "tutte" se conta tutte le icone.
func mission_skill(c: String) -> String:
	return str(RB.card(c).get("abilita", ""))


func counts_all(c: String) -> bool:
	return bid(c) in ["interrogation_droid", "lure_of_the_dark_side", "break_their_will", "make_an_example"]


func requirement_met(f: String, c: String, leaders: Array) -> bool:
	var info := RB.card(c)
	var lvl := int(info.get("livello", 0)) if info.get("livello") != null else 0
	var sk := mission_skill(c)
	if sk == "" or sk == "<null>":
		return true
	var tot := 0
	for n in leaders:
		tot += st.leader_skill(n, sk)
	return tot >= lvl


func can_reveal(f: String, idx: int) -> bool:
	var a: Dictionary = st.assign[f][idx]
	var c: String = a["card"]
	var b := bid(c)
	if b == "subversion":
		return false  # si rivela solo durante una missione avversaria
	if b == "contingency_plan":
		return not _starting_in_hand(f).is_empty()
	if not requirement_met(f, c, a["leaders"]):
		return false
	var t := targets(f, c, a["leaders"])
	# "Boba Fett? Dove?": i leader ribelli non tentano missioni in quel sistema
	if f == "R" and st.flags.has("boba_where"):
		var t2 := []
		for x in t:
			if x["sys"] != st.flags["boba_where"] or RB.card(c).get("risolvi", false):
				t2.append(x)
		t = t2
	return not t.is_empty()


func _starting_in_hand(f: String) -> Array:
	var out := []
	for c in st.hand[f]:
		if st.is_starting_mission(c):
			out.append(c)
	return out


# ================================================================== rivelare una missione

func reveal_mission(f: String, idx: int) -> void:
	var a: Dictionary = st.assign[f][idx]
	a["rev"] = true
	var c: String = a["card"]
	var b := bid(c)
	var ls: Array = a["leaders"]
	say("%s rivela la missione [b]%s[/b] (%s)." % [fs(f), RB.card_name(c), e._leader_names(ls)])
	e.emit_fx("card", {"id": c, "f": f})
	if b == "contingency_plan":
		await _contingency_plan(f, a)
		return
	var tg := targets(f, c, ls)
	if f == "R" and st.flags.has("boba_where") and not RB.card(c).get("risolvi", false):
		var t2 := []
		for x in tg:
			if x["sys"] != st.flags["boba_where"]:
				t2.append(x)
		tg = t2
	var tgt: Dictionary = await _choose_target(f, c, tg)
	var s: String = tgt["sys"]
	for n in ls:
		st.place_leader(n, s)
	e.emit_fx("leader", {"n": ls[0], "sys": s})
	e._sync()
	var success := true
	var resolve: bool = RB.card(c).get("risolvi", false)
	if not resolve:
		success = await attempt(f, c, ls, tgt)
	await _effect(f, c, tgt, ls, success, resolve)
	if e._over():
		return
	if success and not resolve:
		await _after_success(f, c, tgt, ls)
	if not success:
		await _after_failure(f, c, tgt, ls)
	_dispose(f, c, success, ls)
	e._sync()


func _choose_target(f: String, c: String, tg: Array) -> Dictionary:
	if tg.size() == 1:
		return tg[0]
	if tg[0]["leader"] != "":
		var opts := []
		for x in tg:
			opts.append({"v": x["leader"], "l": "%s (%s)" % [RB.leader_it(x["leader"]), RB.sys_name(x["sys"])], "sys": x["sys"], "leader": x["leader"]})
		var n = await e.ask(f, "«%s»: scegli il leader bersaglio." % RB.card_name(c), opts, "mission_leader", {"card": c})
		for x in tg:
			if x["leader"] == n:
				return x
		return tg[0]
	var systems := []
	for x in tg:
		systems.append(x["sys"])
	var s := await e.ask_system(f, "«%s»: scegli il sistema." % RB.card_name(c), systems, "mission_sys", false, {"card": c})
	return {"sys": s, "leader": ""}


func _dispose(f: String, c: String, success: bool, ls: Array) -> void:
	var b := bid(c)
	for i in st.assign[f].size():
		if st.assign[f][i]["card"] == c:
			st.assign[f].remove_at(i)
			break
	if st.is_starting_mission(c):
		st.hand[f].append(c)
		return
	if not success and b in ["break_their_will", "critical_rescue"]:
		st.hand[f].append(c)
		say("«%s» torna in mano." % RB.card_name(c))
		return
	if b == "interdictor_development" and ls.size() >= 2:
		st.hand[f].append(c)
		return
	if RB.card(c).get("progetto", false):
		st.deck["proj_dis"].append(c)
	else:
		st.deck["mis_dis_" + f].append(c)


# ================================================================== tentare una missione

## Missioni in cui si tirano i dadi anche senza opposizione.
func _roll_unopposed(c: String) -> bool:
	return bid(c) in ["assault", "plant_explosives"]


func attempt(f: String, c: String, ls: Array, tgt: Dictionary) -> bool:
	var o := RBState.other(f)
	var s: String = tgt["sys"]
	var sk := mission_skill(c)
	var all_sk := counts_all(c)
	st.flags["mission_diff"] = 0
	# "Guardiano Wookiee": una missione di operazioni speciali fallisce subito
	if f == "I" and sk == "opspec":
		for a in st.acts["R"].duplicate():
			if bid(a) == "wookiee_guardian" and _leader_in_play("Chewbacca", "R"):
				if await e.ask_yes("R", "Usi «Guardiano Wookiee» per far fallire la missione di operazioni speciali «%s»?" % RB.card_name(c), "use_wookiee_guardian"):
					st.acts["R"].erase(a)
					say("Chewbacca protegge: la missione fallisce automaticamente («Guardiano Wookiee»).")
					return false
	# "Sovversione": i leader assegnati alla Sovversione contrastano la missione
	var subversion_bonus := 0
	if e.rote():
		for i in st.assign[o].size():
			var a2: Dictionary = st.assign[o][i]
			if bid(a2["card"]) == "subversion" and not a2["rev"]:
				if await e.ask_yes(o, "Riveli «Sovversione» per contrastare «%s» in %s con %s?" % [RB.card_name(c), RB.sys_name(s), e._leader_names(a2["leaders"])], "use_subversion"):
					a2["rev"] = true
					for n in a2["leaders"]:
						st.place_leader(n, s)
					subversion_bonus = 1
					say("%s rivela «Sovversione»: %s contrastano la missione." % [fs(o), e._leader_names(a2["leaders"])])
					_dispose(o, a2["card"], true, a2["leaders"])
					break
	# l'avversario può mandare un leader dalla riserva
	var blocked := false
	if f == "R" and st.flags.get("misdirection", "") in ls:
		blocked = true
	if st.flags.get("blindside", []).has(c):
		blocked = true
	if not blocked:
		var pool := st.leader_pool(o)
		if not pool.is_empty():
			var opts := [{"v": "", "l": "Non contrastare"}]
			for n in pool:
				opts.append({"v": n, "l": "Contrasta con %s" % RB.leader_it(n), "leader": n})
			var n = await e.ask(o, "%s tenta «%s» in %s: mandi un leader dalla riserva a contrastarla?" % [fs(f), RB.card_name(c), RB.sys_name(s)], opts, "oppose", {"card": c, "sys": s, "confirm": true})
			if n != null and n != "":
				st.place_leader(n, s)
				say("%s manda %s a contrastare la missione." % [fs(o), RB.leader_it(n)])
				e.emit_fx("leader", {"n": n, "sys": s})
	# "In incognito": i Ribelli spostano Lando o Obi-Wan nel sistema della missione
	if f == "I":
		for a in st.acts["R"].duplicate():
			if bid(a) == "undercover":
				var cand := []
				for n in ["Lando Calrissian", "Obi-Wan Kenobi"]:
					if st.leaders.has(n) and st.leaders[n]["st"] == "board" and st.leaders[n]["f"] == "R" and not st.is_captured(n) and st.leaders[n]["loc"] != s:
						if not (st.flags.has("boba_where") and st.flags["boba_where"] == s):
							cand.append(n)
				if not cand.is_empty():
					var opts2 := [{"v": "", "l": "No"}]
					for n in cand:
						opts2.append({"v": n, "l": "Sposta %s in %s" % [RB.leader_it(n), RB.sys_name(s)]})
					var r = await e.ask("R", "Usi «In incognito» per spostare un leader nel sistema della missione?", opts2, "use_undercover", {"confirm": true})
					if r != null and r != "":
						st.acts["R"].erase(a)
						st.place_leader(r, s)
						say("%s si presenta in incognito su %s («In incognito»)." % [RB.leader_it(r), RB.sys_name(s)])
	e._sync()
	# chi partecipa
	var mine := st.leaders_at(s, f)
	var theirs := st.leaders_at(s, o)
	var target_captured := ""
	if tgt["leader"] != "" and st.is_captured(tgt["leader"]):
		target_captured = tgt["leader"]
		if not target_captured in theirs:
			theirs.append(target_captured)
	if theirs.is_empty() and not _roll_unopposed(c):
		say("Nessuno contrasta la missione: riesce automaticamente.")
		return true
	# dadi
	var my_dice := _mission_dice(mine, sk, all_sk)
	var my_bonus := 0
	for n in ls:
		if RB.card(c).get("ritratto") != null and _portrait_match(RB.card(c)["ritratto"], n):
			my_bonus += 2
	if bid(c) == "build_alliance" and st.has_units(s, "R"):
		my_dice["n"] += 2
	if st.flags.get("contingency_lando", false) and "Lando Calrissian" in ls:
		my_bonus += 2
	var op_dice := _mission_dice(theirs, sk, all_sk)
	op_dice["n"] += subversion_bonus
	var mine_roll := st.roll(min(my_dice["n"], 10), min(my_dice["g"], 3))
	var their_roll := st.roll(min(op_dice["n"], 10), min(op_dice["g"], 3)) if not theirs.is_empty() else []
	# anelli e carte che cambiano i dadi
	mine_roll = await _dice_tricks(f, s, mine_roll, their_roll, true)
	their_roll = await _dice_tricks(o, s, their_roll, mine_roll, false)
	var a_succ := RBState.successes(mine_roll) + my_bonus
	var o_succ := RBState.successes(their_roll)
	e.emit_fx("mission_dice", {"f": f, "mine": mine_roll, "theirs": their_roll, "a": a_succ, "o": o_succ, "card": c})
	say("Dadi: %s %d successi, %s %d successi." % [fs(f), a_succ, fs(o), o_succ])
	await e.pause(1.2)
	var ok := a_succ > o_succ
	st.flags["mission_diff"] = a_succ - o_succ
	# C-3PO: una missione di diplomazia fallita riesce comunque
	if not ok and f == "R" and sk == "diplomazia":
		for n in st.leaders_at(s, "R"):
			if st.leaders[n]["ring"] == "c3po":
				if await e.ask_yes("R", "La missione di diplomazia è fallita: scarti l'anello di C-3PO (%s) per farla riuscire?" % RB.leader_it(n), "use_c3po"):
					st.leaders[n]["ring"] = ""
					say("C-3PO trova le parole giuste: la missione riesce.")
					ok = true
				break
	say("La missione %s." % ("[color=#7CFC9A]riesce[/color]" if ok else "[color=#ff7766]fallisce[/color]"))
	return ok


func _portrait_match(portrait: String, n: String) -> bool:
	var p := portrait.to_lower()
	var m := n.to_lower()
	if p == m:
		return true
	# i ritratti a volte hanno solo il cognome o il nome ("Carlist Rieekan", "Leia Organa")
	for w in p.split(" "):
		if w.length() > 3 and m.find(w) >= 0:
			return true
	return false


func _mission_dice(ls: Array, sk: String, all_sk: bool) -> Dictionary:
	var n := 0
	var g := 0
	for x in ls:
		var tot := st.leader_skill(x, sk, all_sk)
		var mi := st.leader_minor(x, sk, all_sk)
		n += tot - mi
		g += mi
	return {"n": n, "g": g}


func _leader_in_play(n: String, f: String) -> bool:
	return st.leaders.has(n) and st.leaders[n]["f"] == f and st.leaders[n]["st"] in ["pool", "board", "mission"] and not st.is_captured(n)


## Anelli e carte che cambiano i dadi di una missione: R2-D2, Maestro Yoda, "Uno su un milione".
func _dice_tricks(f: String, s: String, own: Array, opp: Array, attacker: bool) -> Array:
	if f == "R":
		# Yoda: ritira 1 dado
		for n in st.leaders_at(s, "R"):
			if st.leaders[n]["ring"] == "yoda" and not st.flags.get("yoda_used", false) and not own.is_empty():
				var worst := -1
				for i in own.size():
					if int(own[i]) == 0:
						worst = i
						break
				if worst >= 0 and await e.ask_yes("R", "Maestro Yoda (%s): ritiri un dado vuoto?" % RB.leader_it(n), "use_yoda"):
					own[worst] = st._face()
					st.flags["yoda_used"] = true
					say("Il Maestro Yoda guida %s: un dado viene ritirato." % RB.leader_it(n))
		# "Uno su un milione": 2 dadi con il risultato scelto (speciale = 2 successi)
		for a in st.acts["R"].duplicate():
			if bid(a) == "one_in_a_million" and (_present(s, "Luke Skywalker") or _present(s, "Luke Skywalker (Jedi)") or _present(s, "Wedge Antilles")) and own.size() > 0:
				if await e.ask_yes("R", "Usi «Uno su un milione»: 2 dei tuoi dadi mostrano il risultato che vuoi?", "use_one_in_a_million"):
					st.acts["R"].erase(a)
					var k := 0
					for i in own.size():
						if k < 2 and int(own[i]) != 3:
							own[i] = 3
							k += 1
					say("Uno su un milione: due dadi diventano speciali.")
	return own


func _present(s: String, n: String) -> bool:
	return st.leaders.has(n) and st.leaders[n]["st"] == "board" and st.leaders[n]["loc"] == s and not st.is_captured(n)


## R2-D2: dopo che l'Impero ha tirato in una missione nel sistema di R2-D2, un suo dado diventa vuoto.
func r2d2_check(s: String, imp_roll: Array) -> Array:
	return imp_roll


func _after_success(f: String, c: String, tgt: Dictionary, ls: Array) -> void:
	var s: String = tgt["sys"]
	if f == "R":
		# "Figlio di Skywalker"
		for a in st.acts["R"].duplicate():
			var b := bid(a)
			if (b == "son_of_skywalker" or b == "son_of_skywalker_rote") and (_present(s, "Luke Skywalker") or _present(s, "Luke Skywalker (Jedi)")):
				var wanted := ["seek_yoda", "daring_rescue"]
				if b == "son_of_skywalker_rote":
					wanted.append("critical_rescue")
				var found := []
				for m in st.deck["mis_R"]:
					if bid(m) in wanted:
						found.append(m)
				if not found.is_empty() and await e.ask_yes("R", "Usi «Figlio di Skywalker» per prendere una missione dal mazzo?", "use_son_of_skywalker"):
					st.acts["R"].erase(a)
					var opts := []
					for m in found:
						opts.append({"v": m, "l": RB.card_name(m), "card": m})
					var m = await e.ask("R", "Scegli la missione da prendere.", opts, "pick_mission")
					st.deck["mis_R"].erase(m)
					st.hand["R"].append(m)
					st.shuffle(st.deck["mis_R"])
					say("Luke cerca il suo destino: i Ribelli prendono una missione dal mazzo.")
		# Millennium Falcon: libera un leader catturato nel sistema
		for n in st.leaders_at(s, "R"):
			if st.leaders[n]["ring"] == "falcon":
				var caps := st.captured_at(s)
				if not caps.is_empty() and await e.ask_yes("R", "Scarti l'anello del Millennium Falcon per liberare un leader catturato in %s?" % RB.sys_name(s), "use_falcon"):
					st.leaders[n]["ring"] = ""
					var who: String = caps[0]
					if caps.size() > 1:
						var opts2 := []
						for x in caps:
							opts2.append({"v": x, "l": RB.leader_it(x)})
						who = await e.ask("R", "Chi liberi?", opts2, "rescue_who")
					await rescue(who, ls)


func _after_failure(f: String, c: String, tgt: Dictionary, ls: Array) -> void:
	# "Metti una taglia": dopo che un leader fallisce una missione nel sistema di Jabba
	var s: String = tgt["sys"]
	if not e.rote():
		return
	for a in st.acts["I"].duplicate():
		if bid(a) == "post_bounty" and _present(s, "Jabba the Hutt"):
			var cand := []
			for n in st.leaders_at(s, "R"):
				if st.leaders[n]["ring"] == "":
					cand.append(n)
			if cand.is_empty():
				continue
			if await e.ask_yes("I", "Usi «Metti una taglia» su un leader ribelle in %s?" % RB.sys_name(s), "use_post_bounty"):
				st.acts["I"].erase(a)
				var n: String = (await e.ask_pick("I", "leaders", "Su chi metti la taglia?", cand, 1, 1, "bounty_who"))[0]
				st.leaders[n]["ring"] = "bounty"
				say("Jabba mette una taglia su %s." % RB.leader_it(n))


# ================================================================== catturare e liberare

func capture(n: String, why := "") -> void:
	if not st.leaders.has(n) or st.is_captured(n):
		return
	# "Nobile sacrificio": Obi-Wan viene eliminato invece di essere catturato
	if n == "Obi-Wan Kenobi":
		for a in st.acts["R"].duplicate():
			if bid(a) == "noble_sacrifice":
				if await e.ask_yes("R", "Obi-Wan sta per essere catturato: usi «Nobile sacrificio» (viene eliminato e guadagni 1 reputazione)?", "use_noble_sacrifice"):
					st.acts["R"].erase(a)
					st.leaders[n]["st"] = "elim"
					say("Obi-Wan Kenobi si sacrifica: diventa più potente di quanto si possa immaginare.")
					gain_rep(1)
					return
	var had_bounty: bool = st.leaders[n]["ring"] == "bounty"
	# l'Impero ha un solo anello "catturato": il prigioniero precedente viene liberato
	for x in st.leaders:
		if x != n and st.leaders[x]["ring"] == "captured" and st.leaders[x]["st"] == "board":
			say("L'Impero ha un solo anello di cattura: %s viene liberato." % RB.leader_it(x))
			await rescue(x, [])
	st.leaders[n]["ring"] = "captured"
	st.leaders[n]["det"] = false
	say("[b]%s viene catturato[/b]%s." % [RB.leader_it(n), why])
	e.emit_fx("capture", {"n": n})
	if had_bounty:
		say("La taglia è riscossa: i Ribelli perdono 1 reputazione.")
		lose_rep(1)
	# "È il tuo destino" non serve qui
	e._sync()


func rescue(n: String, with_leaders: Array) -> void:
	if not st.is_captured(n):
		return
	st.leaders[n]["ring"] = ""
	st.place_leader(n, "BASE")
	say("[b]%s viene liberato[/b] e torna alla base ribelle." % RB.leader_it(n))
	e.emit_fx("rescue", {"n": n})
	# i leader della missione possono tornare alla base con lui
	var back := []
	for l in with_leaders:
		if st.leaders[l]["st"] == "board" and st.leaders[l]["f"] == "R":
			back.append(l)
	if not back.is_empty():
		var sel := await e.ask_pick("R", "leaders", "Quali leader della missione tornano alla base con lui?", back, 0, back.size(), "rescue_return")
		for l in sel:
			st.place_leader(l, "BASE")
	# "È il tuo destino": Darth Vader cattura uno dei leader della missione
	if not with_leaders.is_empty():
		for a in st.acts["I"].duplicate():
			if bid(a) == "it_is_your_destiny" and _leader_in_play("Darth Vader", "I"):
				var cand := []
				for l in with_leaders:
					if st.leaders[l]["f"] == "R" and not st.is_captured(l) and st.leaders[l]["st"] == "board":
						cand.append(l)
				if cand.is_empty():
					break
				if await e.ask_yes("I", "Usi «È il tuo destino» per catturare uno dei leader che hanno liberato %s?" % RB.leader_it(n), "use_destiny"):
					st.acts["I"].erase(a)
					var who: String = (await e.ask_pick("I", "leaders", "Chi catturi?", cand, 1, 1, "destiny_who"))[0]
					await capture(who, " da Darth Vader («È il tuo destino»)")
	e._sync()


## Libera i leader catturati in sistemi dove non ci sono più unità imperiali.
func auto_rescue() -> void:
	for n in st.captured_leaders():
		var s: String = st.leaders[n]["loc"]
		if RB.SYS.has(s) and not st.has_units(s, "I"):
			await rescue(n, [])


func gain_rep(n: int) -> void:
	for i in n:
		st.rep -= 1
		if st.check_victory():
			break
	say("La reputazione ribelle sale (segnalino su %d)." % st.rep)
	e.emit_fx("rep", {"rep": st.rep})


func lose_rep(n: int) -> void:
	st.rep = min(st.rep + n, 16)
	say("La reputazione ribelle scende (segnalino su %d)." % st.rep)
	e.emit_fx("rep", {"rep": st.rep})


# ================================================================== utilità per gli effetti

## Distrugge unità nemiche fino a un valore di salute totale (sceglie chi gioca la carta).
func destroy_health(chooser: String, s: String, enemy: String, max_health: int, filter := "", max_units := 99) -> Array:
	var cand := []
	for id in st.units_at(s, enemy):
		var t: String = st.units[id]["t"]
		if RB.is_station(t) and t == "Death Star":
			continue
		if filter == "ground" and not RB.is_ground(t):
			continue
		if filter == "ship" and not RB.is_ship(t):
			continue
		if filter.begins_with("type:") and t != filter.substr(5):
			continue
		if filter == "triangle_ground" and not (RB.is_ground(t) and RB.UNITS[t]["icona"].ends_with("T")):
			continue
		if RB.health(t) <= max_health:
			cand.append(id)
	if cand.is_empty():
		return []
	var r = await e.decide(chooser, {"k": "units", "t": "Scegli le unità da distruggere in %s (salute totale fino a %d)." % [RB.sys_name(s), max_health],
		"opts": cand, "min": 0, "max": min(max_units, cand.size()), "max_health": max_health, "ctx": "destroy", "enemy": enemy, "sys": s})
	var sel := []
	var tot := 0
	if r is Array:
		for id in r:
			if id in cand and not id in sel and sel.size() < max_units:
				var h := RB.health(st.units[id]["t"])
				if tot + h <= max_health:
					sel.append(id)
					tot += h
	if not sel.is_empty():
		say("Distrutte in %s: %s." % [RB.sys_name(s), e.units_text(sel)])
		e.emit_fx("destroy", {"ids": sel, "sys": s})
		for id in sel:
			st.remove_unit(id)
	e._sync()
	return sel


func gain_unit(f: String, t: String, s: String) -> bool:
	if st.supply(t) <= 0:
		return false
	st.add_unit(t, f, s)
	return true


## Mette unità nella coda di costruzione con le icone risorsa e il numero del sistema.
func queue_from_icons(f: String, s: String) -> void:
	var added := []
	for ic in RB.SYS[s]["icone"]:
		var t := await e.choose_build_type(f, ic, s)
		if t != "":
			st.queue[f][int(RB.SYS[s]["coda"]) - 1].append(t)
			added.append(t)
	if not added.is_empty():
		say("%s mette nella coda di costruzione: %s." % [fs(f), e._types_text(added)])


func _choose_one(f: String, title: String, opts: Array, ctx: String):
	return await e.ask(f, title, opts, ctx, {"confirm": true})


## Il giocatore Ribelle sceglie un sistema per una informazione sulla base: restituisce la risposta vera.
func base_in_systems(systems: Array) -> bool:
	return st.base in systems


func reveal_objectives(why: String) -> void:
	var names := []
	for o in st.objs:
		names.append(RB.card_name(o))
	say("%s: i Ribelli rivelano i loro obiettivi: %s." % [why, ", ".join(names) if not names.is_empty() else "nessuno"])
	e.emit_fx("reveal_objs", {"ids": st.objs.duplicate()})


func remove_markers_at(s: String) -> void:
	for m in st.markers.keys():
		if st.markers[m] == s:
			await remove_marker(m)


func remove_marker(m: String) -> void:
	if not st.markers.has(m):
		return
	var s: String = st.markers[m]
	st.markers.erase(m)
	say("Rimosso il segnalino bersaglio di «%s» da %s." % [RB.card_name(m.get_slice("@", 0)), RB.sys_name(s)])
	var card_id := m.get_slice("@", 0)
	if bid(card_id) == "ob_raid_outposts":
		gain_rep(1)
	# un obiettivo in gioco resta finché ha almeno un segnalino
	var still := false
	for x in st.markers:
		if x.get_slice("@", 0) == card_id:
			still = true
	if not still and card_id in st.obj_play:
		st.obj_play.erase(card_id)
		st.deck["obj_dis"].append(card_id)


func destroy_system(s: String) -> void:
	st.sys[s]["dest"] = true
	st.sys[s]["loy"] = ""
	st.sys[s]["subj"] = false
	st.sys[s]["sab"] = false
	say("[b]%s viene distrutto dalla Morte Nera![/b]" % RB.sys_name(s))
	e.emit_fx("superlaser", {"sys": s})
	for id in st.units_at(s, "R", "terra"):
		st.remove_unit(id)
	if st.base == s:
		st.winner = "I"
		st.win_text = "La Morte Nera ha distrutto il sistema della base ribelle."
		return
	# le unità imperiali che non trovano posto sulle navi sono perse
	var ships := st.units_at(s, "I", "spazio")
	var cap := st.transport_capacity(ships)
	var need := []
	for id in st.units_at(s, "I"):
		if st.needs_transport(id):
			need.append(id)
	while need.size() > cap:
		st.remove_unit(need.pop_back())
	for id in st.units_at(s, "R"):
		if st.needs_transport(id) and RB.is_ground(st.units[id]["t"]):
			st.remove_unit(id)
	await remove_markers_at(s)


# ================================================================== effetti delle missioni

func _effect(f: String, c: String, tgt: Dictionary, ls: Array, ok: bool, resolve: bool) -> void:
	var s: String = tgt["sys"]
	var n: String = tgt["leader"]
	var b := bid(c)
	if not ok and not b in ["aggressive_negotiations", "assault", "plant_explosives"]:
		return
	match b:
		# ---------------------------------------------- Impero
		"construct_super_star_destroyer", "construct_super_star_destroyer_rote":
			if st.supply("Super Star Destroyer") > 0:
				var sp := 1 if (b.ends_with("_rote") and ls.size() >= 2) else 2
				st.queue["I"][sp].append("Super Star Destroyer")
				say("Un Super Star Destroyer entra nella casella %d della coda di costruzione." % (sp + 1))
		"construct_factory":
			if st.sys[s]["sab"]:
				st.sys[s]["sab"] = false
				say("Il segnalino sabotaggio su %s viene rimosso." % RB.sys_name(s))
			await queue_from_icons("I", s)
		"address_delays":
			await queue_from_icons("I", s)
		"superlaser_online":
			var reg := RB.region_of(s)
			await destroy_system(s)
			if e._over():
				return
			var opts := []
			for x in RB.region_systems(reg):
				if st.is_populous(x) and x != "CORUSCANT" and not st.has_loyalty("I", x):
					opts.append(x)
			if not opts.is_empty():
				var t := await e.ask_system("I", "Ottieni 1 fedeltà in un sistema popolato della regione.", opts, "loyalty")
				st.gain_loyalty("I", t)
				say("L'Impero ottiene 1 fedeltà su %s." % RB.sys_name(t))
		"research_and_development":
			var opts2 := [{"v": "draw2", "l": "Pesca 2 carte progetto e tienine 1"}]
			if st.sys[s]["sab"]:
				opts2.append({"v": "sab", "l": "Rimuovi il sabotaggio da %s e pesca 1 carta progetto" % RB.sys_name(s)})
			var r = await _choose_one("I", "Ricerca e Sviluppo: scegli un effetto.", opts2, "rnd")
			if r == "sab":
				st.sys[s]["sab"] = false
				var p = st.draw("proj", "proj_dis")
				if p != null:
					st.hand["I"].append(p)
				say("L'Impero rimuove il sabotaggio da %s e pesca un progetto." % RB.sys_name(s))
			else:
				var drawn := []
				for i in 2:
					var p = st.draw("proj", "proj_dis")
					if p != null:
						drawn.append(p)
				if not drawn.is_empty():
					var keep: String = (await e.ask_pick("I", "cards", "Scegli il progetto da tenere (l'altro va in fondo al mazzo).", drawn, 1, 1, "keep_project"))[0]
					st.hand["I"].append(keep)
					for p in drawn:
						if p != keep:
							st.deck["proj"].append(p)
					say("L'Impero sviluppa un nuovo progetto segreto.")
		"secret_weapons_research":
			for i in 2:
				var p = st.draw("proj", "proj_dis")
				if p != null:
					st.hand["I"].append(p)
			say("L'Impero pesca 2 carte progetto.")
		"gather_intel":
			var nreb := st.units_at(st.base_loc(), "R").size()
			var k: int = max(1, nreb / 4)
			_draw_probes(k)
		"capture_rebel_operative":
			await capture(n)
		"rule_by_fear", "trade_negotiations", "message_from_high_command":
			st.gain_loyalty("I", s)
			say("L'Impero ottiene 1 fedeltà su %s." % RB.sys_name(s))
			if b == "message_from_high_command":
				for l in ls:
					if st.leaders[l]["st"] == "board":
						st.to_pool(l)
				say("I leader della missione tornano nella riserva.")
		"display_of_power":
			st.gain_loyalty("I", s, 2)
			say("L'Impero ottiene 2 fedeltà su %s." % RB.sys_name(s))
		"carbon_freezing":
			st.leaders[n]["ring"] = "carbonite"
			say("%s viene ibernato nella grafite. I Ribelli perdono 1 reputazione." % RB.leader_it(n))
			lose_rep(1)
		"intercept_transmission":
			var got := []
			var back := []
			for i in 8:
				var p = st.draw("probe")
				if p == null:
					break
				if st.has_units(p, "I"):
					got.append(p)
				else:
					back.append(p)
			st.probes.append_array(got)
			for p in got:
				if not p in st.known["I_not_base"]:
					st.known["I_not_base"].append(p)
			st.deck["probe"].append_array(back)
			st.shuffle(st.deck["probe"])
			say("L'Impero intercetta le trasmissioni e ottiene %d carte sonda." % got.size())
		"planetary_conquest":
			var srcs := []
			for x in st.all_systems():
				if x != s and (st.count_type(x, "AT-AT", "I") + st.count_type(x, "AT-ST", "I") + st.count_type(x, "Stormtrooper", "I")) > 0 and st.leaders_at(x, "I").is_empty():
					srcs.append(x)
			if not srcs.is_empty():
				var src := await e.ask_system("I", "Da quale sistema arrivano le truppe?", srcs, "conquest_src")
				var moved := await e.move_units("I", s, [src], "move_special", {"ignore_transport": true, "types": {"AT-AT": 1, "AT-ST": 1, "Stormtrooper": 2}})
				await e.after_move("I", s, moved, [src], st.has_units(s, "R", "terra"))
		"collect_bounty":
			await capture(n)
			var dest := _closest_with_imperial(st.leaders[n]["loc"])
			if dest != "":
				st.place_leader(n, dest)
				for l in ls:
					st.place_leader(l, dest)
				say("Boba Fett consegna %s su %s." % [RB.leader_it(n), RB.sys_name(dest)])
		"oversee_project":
			var opts3 := []
			for sp in [0, 1]:
				for t in st.queue["I"][sp]:
					var key := "%d|%s" % [sp, t]
					var already := false
					for o in opts3:
						if o["v"] == key:
							already = true
					if not already:
						opts3.append({"v": key, "l": "%s (casella %d)" % [RB.unit_it(t), sp + 1], "unit": t})
			if not opts3.is_empty():
				var r2 = await _choose_one("I", "Scegli un'unità della coda (casella 1 o 2) da schierare in %s." % RB.sys_name(s), opts3, "oversee")
				var sp2 := int(r2.get_slice("|", 0))
				var t2: String = r2.get_slice("|", 1)
				if t2 == "Death Star" and st.count_type(s, "Death Star Under Construction", "I") == 0:
					say("La Morte Nera si può schierare solo dove c'è la Morte Nera in Costruzione.")
				else:
					st.queue["I"][sp2].erase(t2)
					if t2 == "Death Star":
						for id in st.units_at(s, "I"):
							if st.units[id]["t"] == "Death Star Under Construction":
								st.remove_unit(id)
								break
					st.add_unit(t2, "I", s)
					say("L'Impero schiera %s in %s." % [RB.unit_it(t2), RB.sys_name(s)])
		"construct_death_star":
			if st.supply("Death Star") > 0 and st.supply("Death Star Under Construction") > 0:
				st.add_unit("Death Star Under Construction", "I", s)
				st.queue["I"][2].append("Death Star")
				say("Inizia la costruzione di una Morte Nera su %s." % RB.sys_name(s))
		"interrogation":
			reveal_objectives("Interrogatorio")
		"probe_droid_initiative":
			var k2 := 2
			if "Admiral Ozzel" in ls:
				k2 = 4
			_draw_probes(k2)
		"homing_beacon":
			await rescue_homing(n)
		"double_our_efforts":
			var times := 2 if "Moff Jerjerrod" in ls else 1
			for i in times:
				var opts4 := []
				for sp in [1, 2]:
					for t in st.queue["I"][sp]:
						var key2 := "%d|%s" % [sp, t]
						var dup := false
						for o in opts4:
							if o["v"] == key2:
								dup = true
						if not dup:
							opts4.append({"v": key2, "l": "%s (casella %d → %d)" % [RB.unit_it(t), sp + 1, sp], "unit": t})
				if opts4.is_empty():
					break
				var r3 = await _choose_one("I", "Scegli un'unità della coda da far avanzare di 1 casella.", opts4, "double_efforts")
				var sp3 := int(r3.get_slice("|", 0))
				var t3: String = r3.get_slice("|", 1)
				st.queue["I"][sp3].erase(t3)
				st.queue["I"][sp3 - 1].append(t3)
				say("%s avanza nella coda di costruzione." % RB.unit_it(t3))
		"interrogation_droid":
			var three := await _rebel_names_three()
			say("Il droide da interrogatorio estorce tre nomi: %s. Uno di questi nasconde la base." % e._names(three))
			st.flags["three_systems"] = three
		"detained":
			st.leaders[n]["det"] = true
			say("%s è trattenuto: non tornerà nella riserva al prossimo ripristino." % RB.leader_it(n))
		"retrieve_the_plans":
			reveal_objectives("Recuperare i piani")
			if not st.objs.is_empty():
				var o: String = (await e.ask_pick("I", "cards", "Scegli l'obiettivo da mettere in fondo al mazzo degli obiettivi.", st.objs.duplicate(), 1, 1, "bottom_objective", {"objectives": true}))[0]
				st.objs.erase(o)
				st.deck["obj"].append(o)
				say("«%s» finisce in fondo al mazzo degli obiettivi." % RB.card_name(o))
		"imperial_propaganda":
			var reg2 := RB.region_of(s)
			for x in RB.region_systems(reg2):
				if st.has_loyalty("R", x):
					st.lose_loyalty("R", x)
			say("La propaganda imperiale rende neutrali i sistemi ribelli della %s." % RB.REGION_NAME[reg2])
		"lure_of_the_dark_side":
			st.leaders[n]["ring"] = "lure"
			st.leaders[n]["f"] = "I"
			say("[b]%s cede al lato oscuro[/b] e diventa un leader imperiale." % RB.leader_it(n))
			if n.begins_with("Luke Skywalker"):
				lose_rep(1)
		"long_range_probe":
			var yes := st.base == s
			say("Sonda a lungo raggio su %s: la base ribelle %s lì." % [RB.sys_name(s), "[b]è[/b]" if yes else "non è"])
			if not yes and not s in st.known["I_not_base"]:
				st.known["I_not_base"].append(s)
			if yes:
				st.flags["base_known"] = s
		"hunt_them_down":
			await destroy_health("I", s, "R", 2)
		"fear_will_keep_them_in_line":
			var reg3 := RB.region_of(s)
			var opts5 := []
			for x in RB.region_systems(reg3):
				if st.is_populous(x) and x != "CORUSCANT" and not st.has_loyalty("I", x):
					opts5.append(x)
			var picked := await e.ask_pick("I", "systems", "Scegli fino a 2 sistemi della regione dove ottenere 1 fedeltà.", opts5, min(2, opts5.size()), 2, "fear_systems")
			for x in picked:
				st.gain_loyalty("I", x)
			if not picked.is_empty():
				say("La paura tiene in riga %s." % e._names(picked))
		# ---------------------------------------------- Ribelli
		"daring_rescue", "critical_rescue", "aggressive_negotiations":
			if ok:
				var caps := st.captured_at(s)
				if not caps.is_empty():
					var who: String = caps[0]
					if caps.size() > 1:
						who = (await e.ask_pick("R", "leaders", "Chi liberi?", caps, 1, 1, "rescue_who"))[0]
					await rescue(who, ls)
			elif b == "aggressive_negotiations":
				var tri := []
				for id in st.units_at(s, "I", "terra"):
					if RB.UNITS[st.units[id]["t"]]["icona"].ends_with("T"):
						tri.append(id)
				if not tri.is_empty() and await e.ask_yes("R", "La missione è fallita: distruggi 1 unità terrestre [triangolo] in %s?" % RB.sys_name(s), "aggressive_destroy"):
					await destroy_health("R", s, "I", 99, "triangle_ground", 1)
		"for_the_greater_good":
			var caps2 := st.captured_at(s)
			if not caps2.is_empty():
				var who2: String = caps2[0]
				if caps2.size() > 1:
					who2 = (await e.ask_pick("R", "leaders", "Chi liberi?", caps2, 1, 1, "rescue_who"))[0]
				await rescue(who2, [])
			await draw_objective()
		"hit_and_run":
			await destroy_health("R", s, "I", 2)
		"base_defenses":
			gain_unit("R", "Ion Cannon", "BASE")
			gain_unit("R", "Shield Generator", "BASE")
			say("I Ribelli rafforzano le difese della base: 1 Cannone a Ioni e 1 Generatore di Scudo.")
		"misdirection":
			var mine := []
			for a in st.assign["R"]:
				if not a["rev"]:
					mine.append_array(a["leaders"])
			if not mine.is_empty():
				var who3: String = (await e.ask_pick("R", "leaders", "Scegli il leader la cui missione non potrà essere contrastata dalla riserva imperiale.", mine, 1, 1, "misdirection"))[0]
				st.flags["misdirection"] = who3
				say("Depistaggio: i leader imperiali della riserva non potranno contrastare la missione di %s." % RB.leader_it(who3))
		"plant_false_lead":
			await plant_false_lead()
		"hidden_fleet":
			if not st.base_revealed:
				var moved2 := await e.move_units("R", s, ["BASE"], "move_special", {})
				await e.after_move("R", s, moved2, ["BASE"])
		"incite_rebellion":
			var k3 := 0
			for i in 3:
				if gain_unit("R", "Rebel Trooper", s):
					k3 += 1
			say("Insurrezione su %s: %d Soldati Ribelli." % [RB.sys_name(s), k3])
			await e.after_move("R", s, [], [])
		"wookiee_uprising":
			st.gain_loyalty("R", s)
			await destroy_health("R", s, "I", 4)
		"establish_trade_relations":
			st.gain_loyalty("R", s)
			say("I Ribelli ottengono 1 fedeltà su %s." % RB.sys_name(s))
			if st.is_populous(s):
				await queue_from_icons("R", s)
		"lead_the_strike_team":
			if not st.base_revealed or true:
				var moved3 := await e.move_units("R", s, [st.base_loc()], "move_special", {"only_ground": true, "max": 4, "ignore_transport": true})
				await e.after_move("R", s, moved3, [st.base_loc()], st.has_units(s, "I", "terra"))
		"stolen_plans":
			await reorder_objectives(4, "R", false)
		"sabotage":
			st.sys[s]["sab"] = true
			say("Sabotaggio su %s!" % RB.sys_name(s))
		"sabotage_rote":
			var opts6 := []
			if st.count_type(s, "Shield Bunker", "I") > 0:
				opts6.append({"v": "bunker", "l": "Distruggi un Bunker Scudo"})
			if st.is_populous(s):
				opts6.append({"v": "sab", "l": "Metti un segnalino sabotaggio"})
			if not opts6.is_empty():
				var r4 = await _choose_one("R", "Sabotaggio: scegli.", opts6, "sabotage_choice")
				if r4 == "bunker":
					for id in st.units_at(s, "I"):
						if st.units[id]["t"] == "Shield Bunker":
							st.remove_unit(id)
							say("Il Bunker Scudo su %s salta in aria." % RB.sys_name(s))
							break
				else:
					st.sys[s]["sab"] = true
					say("Sabotaggio su %s!" % RB.sys_name(s))
		"rapid_mobilization":
			st.flags["rapid_mob"] = st.flags.get("rapid_mob", [])
			st.flags["rapid_mob"].append(ls.size())
			say("Mobilitazione rapida: si risolverà alla fine della Fase di Comando.")
		"infiltration":
			var top := []
			for i in 2:
				var o = st.draw("obj")
				if o != null:
					top.append(o)
			if top.size() == 2:
				var keep: String = (await e.ask_pick("R", "cards", "Infiltrazione: scegli l'obiettivo da lasciare IN CIMA al mazzo (l'altro va in fondo).", top, 1, 1, "infiltration", {"objectives": true}))[0]
				st.deck["obj"].push_front(keep)
				for o in top:
					if o != keep:
						st.deck["obj"].append(o)
			elif top.size() == 1:
				st.deck["obj"].push_front(top[0])
			say("I Ribelli sbirciano il mazzo degli obiettivi.")
		"plan_the_assault":
			if not st.base_revealed:
				var moved4 := await e.move_units("R", s, ["BASE"], "move_special", {"only_ships": true})
				await e.after_move("R", s, moved4, ["BASE"])
			else:
				await e.after_move("R", s, [], [])
		"rogue_squadron_raid":
			await destroy_queue("R", "I", 4)
		"seek_yoda":
			var l0: String = ls[0]
			if ls.size() > 1:
				l0 = (await e.ask_pick("R", "leaders", "A chi va l'anello del Maestro Yoda?", ls, 1, 1, "yoda_who"))[0]
			if l0 == "Luke Skywalker" and st.leaders.has("Luke Skywalker (Jedi)"):
				var loc: String = st.leaders[l0]["loc"]
				st.leaders[l0]["st"] = "elim"
				st.leaders["Luke Skywalker (Jedi)"]["st"] = "board"
				st.leaders["Luke Skywalker (Jedi)"]["loc"] = loc
				st.leaders["Luke Skywalker (Jedi)"]["f"] = "R"
				say("[b]Luke Skywalker completa l'addestramento: ora è un Jedi.[/b]")
				var other := []
				for x in ls:
					if x != l0:
						other.append(x)
				if not other.is_empty():
					st.leaders[other[0]]["ring"] = "yoda"
					say("Il Maestro Yoda accompagna %s." % RB.leader_it(other[0]))
			else:
				st.leaders[l0]["ring"] = "yoda"
				say("Il Maestro Yoda accompagna %s." % RB.leader_it(l0))
		"public_uprising":
			for icon in ["C", "T", "T"]:
				var types := []
				for ic in ["B" + icon, "O" + icon]:
					for t in RB.buildable("R", ic, st.opt["rote_units"]):
						if st.supply(t) > 0 and not RB.is_structure(t):
							types.append(t)
				if types.is_empty():
					continue
				var opts7 := []
				for t in types:
					opts7.append({"v": t, "l": RB.unit_it(t), "unit": t})
				var t4 = await _choose_one("R", "Rivolta popolare: scegli un'unità %s." % ("[cerchio]" if icon == "C" else "[triangolo]"), opts7, "uprising_unit")
				gain_unit("R", t4, s)
			say("Rivolta popolare su %s!" % RB.sys_name(s))
			await e.after_move("R", s, [], [])
		"demolition":
			for ic in RB.SYS[s]["icone"]:
				var found := -1
				for sp in 3:
					for t in st.queue["I"][sp]:
						if RB.UNITS[t]["icona"] == ic:
							found = sp
							st.queue["I"][sp].erase(t)
							say("Demolizione: %s distrutta nella coda di costruzione." % RB.unit_it(t))
							break
					if found >= 0:
						break
		"support_of_mon_calamari":
			var r5 = await _choose_one("R", "Supporto dei Mon Calamari: scegli.", [{"v": "loy", "l": "Ottieni 2 fedeltà su Mon Calamari"}, {"v": "ship", "l": "Metti 1 Incrociatore Mon Calamari nella casella 3 della coda"}], "mon_cal")
			if r5 == "loy":
				st.gain_loyalty("R", s, 2)
				say("Mon Calamari si unisce all'Alleanza.")
			elif st.supply("Mon Cala Cruiser") > 0:
				st.queue["R"][2].append("Mon Cala Cruiser")
				say("Un Incrociatore Mon Calamari è in costruzione.")
		"build_alliance", "regional_aid":
			st.gain_loyalty("R", s)
			say("I Ribelli ottengono 1 fedeltà su %s." % RB.sys_name(s))
			if b == "regional_aid":
				var opts8 := []
				for x in RB.region_systems(RB.region_of(s)):
					if x != s and st.is_populous(x) and x != "CORUSCANT" and not st.has_loyalty("R", x):
						opts8.append(x)
				if not opts8.is_empty():
					var x2 := await e.ask_system("R", "Aiuti regionali: scegli un altro sistema della regione.", opts8, "loyalty")
					st.gain_loyalty("R", x2)
					say("I Ribelli ottengono 1 fedeltà su %s." % RB.sys_name(x2))
		"covert_operation":
			var drawn2 := []
			for i in 2:
				var o2 = st.draw("obj")
				if o2 != null:
					drawn2.append(o2)
			if not drawn2.is_empty():
				var keep2: String = (await e.ask_pick("R", "cards", "Operazione segreta: scegli l'obiettivo da tenere (l'altro va in fondo al mazzo).", drawn2, 1, 1, "covert_keep", {"objectives": true}))[0]
				for o2 in drawn2:
					if o2 != keep2:
						st.deck["obj"].append(o2)
				await _gain_objective(keep2)
		# ---------------------------------------------- Ascesa dell'Impero
		"break_their_will":
			var all := st.all_systems()
			var sys2 := await e.ask_system("I", "Scegli un sistema: i Ribelli devono dirti se la base è nella sua regione.", all, "region_probe")
			var reg4 := RB.region_of(sys2)
			var yes2 := RB.region_of(st.base) == reg4
			say("Spezzare la volontà: la base ribelle %s nella %s." % ["[b]è[/b]" if yes2 else "non è", RB.REGION_NAME[reg4]])
			_record_region(reg4, yes2)
		"deployment":
			var types2 := []
			for t in RB.buildable("I", "OT", st.opt["rote_units"]):
				if st.supply(t) > 0:
					types2.append({"v": t, "l": RB.unit_it(t), "unit": t})
			if not types2.is_empty():
				var t5 = await _choose_one("I", "Schieramento: scegli l'unità terrestre [triangolo].", types2, "deployment_unit")
				gain_unit("I", t5, s)
				say("L'Impero ottiene %s su %s." % [RB.unit_it(t5), RB.sys_name(s)])
		"discredit_rebellion":
			var dice := 2 if "Admiral Motti" in ls else 1
			var r6 = await _choose_one("R", "Screditare la Ribellione: togli tutti i segnalini sabotaggio, oppure tira %d dad%s (con almeno un risultato speciale perdi 1 reputazione)." % [dice, "i" if dice > 1 else "o"], [{"v": "remove", "l": "Togli tutti i sabotaggi"}, {"v": "roll", "l": "Tira i dadi"}], "discredit")
			if r6 == "remove":
				for x in st.sys:
					st.sys[x]["sab"] = false
				say("I Ribelli ritirano tutti i sabotaggi.")
			else:
				var rr := st.roll(dice)
				e.emit_fx("dice", {"dice": rr, "f": "R"})
				if 3 in rr:
					say("Le accuse colpiscono nel segno: i Ribelli perdono 1 reputazione.")
					lose_rep(1)
				else:
					say("I Ribelli superano lo scandalo.")
		"draw_them_out":
			var pool := st.leader_pool("R")
			if not pool.is_empty():
				var who4: String = (await e.ask_pick("I", "leaders", "Stanarli: scegli un leader ribelle della riserva da portare in %s." % RB.sys_name(s), pool, 1, 1, "draw_out_who"))[0]
				st.place_leader(who4, s)
				say("%s viene attirato su %s." % [RB.leader_it(who4), RB.sys_name(s)])
		"exploit_weakness":
			if not st.objs.is_empty():
				var o3: String = st.objs[st.rng.randi_range(0, st.objs.size() - 1)]
				st.objs.erase(o3)
				st.deck["obj"].push_front(o3)
				say("I Ribelli rivelano «%s» e lo rimettono in cima al mazzo degli obiettivi." % RB.card_name(o3))
		"hire_mercenaries", "promotion":
			var cand := _box_leaders("I", b == "promotion")
			if not cand.is_empty():
				var who5: String = (await e.ask_pick("I", "leaders", "Scegli il leader da reclutare e mettere in %s." % RB.sys_name(s), cand, 1, 1, "recruit_place"))[0]
				st.place_leader(who5, s)
				say("L'Impero recluta %s su %s." % [RB.leader_it(who5), RB.sys_name(s)])
		"imperial_might":
			var q: Array = st.queue["I"][0]
			if not q.is_empty():
				var items := []
				for i in q.size():
					items.append(i)
				var r7 = await e.decide("I", {"k": "queue_pick", "t": "Potenza imperiale: scegli fino a 4 unità della casella 1 da schierare in %s." % RB.sys_name(s), "opts": q.duplicate(), "max": 4, "ctx": "imperial_might"})
				var chosen := []
				if r7 is Array:
					for x in r7:
						if x is int and x >= 0 and x < q.size() and not x in chosen and chosen.size() < 4:
							chosen.append(x)
				chosen.sort()
				chosen.reverse()
				for i in chosen:
					var t6: String = q[i]
					q.remove_at(i)
					if t6 == "Death Star":
						for id in st.units_at(s, "I"):
							if st.units[id]["t"] == "Death Star Under Construction":
								st.remove_unit(id)
								break
					st.add_unit(t6, "I", s)
				if not chosen.is_empty():
					say("Potenza imperiale: %d unità schierate su %s." % [chosen.size(), RB.sys_name(s)])
			if ls.size() >= 2:
				for l in ls:
					st.place_leader(l, "CORUSCANT")
				say("I leader della missione tornano su Coruscant.")
		"interdictor_development":
			if st.supply("Interdictor") > 0:
				var sp4 := 0 if ls.size() >= 2 else 1
				st.queue["I"][sp4].append("Interdictor")
				say("Un Interdictor entra nella casella %d della coda di costruzione." % (sp4 + 1))
		"make_an_example":
			st.leaders[n]["st"] = "elim"
			st.leaders[n]["ring"] = ""
			say("[b]%s viene giustiziato come esempio.[/b]" % RB.leader_it(n))
		"secure_the_plans":
			st.markers[c + "@1"] = s
			say("I piani della Morte Nera sono al sicuro su %s: finché c'è il segnalino, i Ribelli non possono giocare «Piani della Morte Nera»." % RB.sys_name(s))
		"single_reactor_ignition":
			if st.base == s and not st.base_revealed:
				await e.reveal_base("Accensione di un solo reattore")
			for id in st.units_at(s, "R", "terra"):
				st.remove_unit(id)
			await remove_markers_at(s)
			say("Un solo reattore: le forze di terra ribelli su %s sono annientate." % RB.sys_name(s))
		"stolen_intel":
			_draw_probes(1)
			var disc := []
			for m in st.hand["R"]:
				if not st.is_starting_mission(m):
					disc.append(m)
			if not disc.is_empty():
				var m2: String = (await e.ask_pick("I", "cards", "Informazioni rubate: scegli una missione ribelle da scartare.", disc, 1, 1, "stolen_intel", {"show_rebel_hand": true}))[0]
				st.hand["R"].erase(m2)
				st.deck["mis_dis_R"].append(m2)
				say("L'Impero fa scartare ai Ribelli «%s»." % RB.card_name(m2))
		"were_the_bait":
			var at_base := st.units_at(st.base_loc(), "R")
			if not at_base.is_empty():
				var r8 = await e.decide("I", {"k": "units", "t": "Siamo l'esca: scegli unità della base ribelle per un valore di salute fino a 4: vengono attirate qui.", "opts": at_base, "min": 0, "max": at_base.size(), "max_health": 4, "ctx": "bait", "sys": s})
				var sel := []
				var tot := 0
				if r8 is Array:
					for id in r8:
						if id in at_base and not RB.UNITS[st.units[id]["t"]]["immobile"]:
							var h := RB.health(st.units[id]["t"])
							if tot + h <= 4:
								sel.append(id)
								tot += h
				for id in sel:
					st.move_unit(id, s)
				if not sel.is_empty():
					say("Le forze ribelli cadono nella trappola su %s: %s." % [RB.sys_name(s), e.units_text(sel)])
				await e.after_move("I", s, [], [])
		"assault":
			var diff: int = min(3, st.flags.get("mission_diff", 0))
			if diff > 0:
				var k4 := 0
				for id in st.units_at(s, "I", "terra"):
					if st.units[id]["t"] == "Stormtrooper" and k4 < diff:
						st.remove_unit(id)
						k4 += 1
				if k4 > 0:
					say("Assalto: %d Assaltatori distrutti su %s." % [k4, RB.sys_name(s)])
		"plant_explosives":
			var diff2: int = st.flags.get("mission_diff", 0)
			if diff2 > 0:
				await destroy_health("R", s, "I", diff2, "ground", 3)
		"behind_enemy_lines":
			if not st.base_revealed:
				var moved5 := await e.move_units("R", s, ["BASE"], "move_special", {"max": 5})
				await e.after_move("R", s, moved5, ["BASE"])
		"heist":
			var opts9 := []
			for m in st.markers:
				if st.markers[m] == s:
					opts9.append({"v": m, "l": "Rimuovi il segnalino di «%s»" % RB.card_name(m.get_slice("@", 0))})
			if st.count_type(s, "Death Star", "I") + st.count_type(s, "Death Star Under Construction", "I") > 0:
				opts9.append({"v": "obj", "l": "Pesca la prima carta del mazzo degli obiettivi"})
			if not opts9.is_empty():
				var r9 = await _choose_one("R", "Colpo grosso: scegli.", opts9, "heist")
				if r9 == "obj":
					var o4 = st.draw("obj")
					if o4 != null:
						await _gain_objective(o4)
				else:
					await remove_marker(r9)
		"my_only_hope":
			var cand2 := _my_only_hope_leaders()
			if not cand2.is_empty():
				var who6: String = (await e.ask_pick("R", "leaders", "Sei la mia unica speranza: scegli il leader da reclutare.", cand2, 1, 1, "recruit_place"))[0]
				st.place_leader(who6, s)
				say("I Ribelli reclutano %s su %s." % [RB.leader_it(who6), RB.sys_name(s)])
		"prepare_for_battle":
			for l in ls:
				if st.leaders[l]["st"] == "board":
					st.to_pool(l)
			say("I leader della missione tornano nella riserva.")
			if e.cinematic():
				var dis := []
				for th in ["spazio", "terra"]:
					dis.append_array(st.deck["atac_dis_%s_R" % th])
				if not dis.is_empty():
					for th in ["spazio", "terra"]:
						st.deck["atac_%s_R" % th].append_array(st.deck["atac_dis_%s_R" % th])
						st.deck["atac_dis_%s_R" % th].clear()
					say("I Ribelli recuperano le carte tattica avanzate scartate.")
			else:
				var th2 = await _choose_one("R", "Prepararsi alla battaglia: quale mazzo tattico guardi?", [{"v": "spazio", "l": "Tattiche spaziali"}, {"v": "terra", "l": "Tattiche terrestri"}], "tactic_deck")
				var key3 := "tac_" + str(th2)
				var top4 := []
				for i in 4:
					var x3 = st.draw(key3)
					if x3 != null:
						top4.append(x3)
				var order = await e.decide("R", {"k": "order", "t": "Ordina le carte: quelle che scegli vanno in cima (nell'ordine), le altre in fondo.", "opts": top4, "ctx": "tactic_order"})
				var keep3 := []
				if order is Array:
					for x4 in order:
						if x4 in top4 and not x4 in keep3:
							keep3.append(x4)
				for x4 in top4:
					if not x4 in keep3:
						st.deck[key3].append(x4)
				keep3.reverse()
				for x4 in keep3:
					st.deck[key3].push_front(x4)
		"reconnaissance":
			var dis2: Array = st.deck["mis_dis_R"]
			if not dis2.is_empty():
				var m3: String = (await e.ask_pick("R", "cards", "Ricognizione: scegli una missione dalla pila degli scarti da riprendere in mano.", dis2.duplicate(), 1, 1, "recon_pick"))[0]
				dis2.erase(m3)
				st.hand["R"].append(m3)
				say("I Ribelli riprendono in mano una missione scartata.")
		"safe_haven":
			var q2 := []
			for sp in 3:
				for t in st.queue["R"][sp]:
					q2.append("%d|%s" % [sp, t])
			if not q2.is_empty():
				var r10 = await e.decide("R", {"k": "queue_pick", "t": "Rifugio sicuro: scegli fino a 2 unità della tua coda di costruzione da schierare in %s." % RB.sys_name(s), "opts": q2, "max": 2, "ctx": "safe_haven"})
				var chosen2 := []
				if r10 is Array:
					for x in r10:
						if x is int and x >= 0 and x < q2.size() and not x in chosen2 and chosen2.size() < 2:
							chosen2.append(x)
				for i in chosen2:
					var sp5 := int(q2[i].get_slice("|", 0))
					var t7: String = q2[i].get_slice("|", 1)
					st.queue["R"][sp5].erase(t7)
					st.add_unit(t7, "R", s)
					say("I Ribelli schierano %s su %s." % [RB.unit_it(t7), RB.sys_name(s)])
		"secret_mission":
			var top6 := []
			for i in 6:
				var x5 = st.draw("mis_R", "mis_dis_R")
				if x5 != null:
					top6.append(x5)
			if not top6.is_empty():
				var k5 := 2 if "Cassian Andor" in ls else 1
				var keep4 := await e.ask_pick("R", "cards", "Missione segreta: scegli %d carta/e da tenere." % k5, top6, 1, k5, "secret_mission_keep")
				for x5 in top6:
					if x5 in keep4:
						st.hand["R"].append(x5)
					else:
						st.deck["mis_R"].append(x5)
				st.shuffle(st.deck["mis_R"])
				say("I Ribelli scelgono %d nuova/e missione/i dal loro mazzo." % keep4.size())
		_:
			say("(Effetto di «%s» non ancora gestito.)" % RB.card_name(c))
	e._sync()


func _draw_probes(k: int) -> void:
	var got := 0
	for i in k:
		var p = st.draw("probe")
		if p == null:
			break
		st.probes.append(p)
		got += 1
		if not p in st.known["I_not_base"]:
			st.known["I_not_base"].append(p)
	say("L'Impero pesca %d %s." % [got, "carta sonda" if got == 1 else "carte sonda"])


func _record_region(reg: int, yes: bool) -> void:
	if yes:
		st.flags["base_region"] = reg
	else:
		for x in RB.region_systems(reg):
			if not x in st.known["I_not_base"]:
				st.known["I_not_base"].append(x)


func _closest_with_imperial(from: String) -> String:
	var best := ""
	var bd := 99
	for s in st.all_systems():
		if st.has_units(s, "I"):
			var d := RB.dist(from, s)
			if d < bd:
				bd = d
				best = s
	return best


func _rebel_names_three() -> Array:
	var others := []
	for s in st.all_systems():
		if s != st.base:
			others.append(s)
	var r = await e.decide("R", {"k": "systems", "t": "Droide da interrogatorio: nomina 3 sistemi, uno dei quali deve essere quello della base (%s)." % RB.sys_name(st.base), "opts": others, "min": 2, "max": 2, "ctx": "three_systems", "secret": true})
	var out := [st.base]
	if r is Array:
		for x in r:
			if x in others and not x in out and out.size() < 3:
				out.append(x)
	while out.size() < 3:
		out.append(others[st.rng.randi_range(0, others.size() - 1)])
	out.sort()
	return out


func rescue_homing(n: String) -> void:
	st.leaders[n]["ring"] = ""
	var reg := RB.region_of(st.base)
	var opts := RB.region_systems(reg)
	opts.sort()
	var s := await e.ask_system("R", "Radiofaro: %s viene liberato e deve andare in un sistema della regione della base." % RB.leader_it(n), opts, "homing_place")
	st.place_leader(n, s)
	say("%s viene lasciato fuggire… fino a %s: la base è nella %s!" % [RB.leader_it(n), RB.sys_name(s), RB.REGION_NAME[reg]])
	st.flags["base_region"] = reg


func plant_false_lead() -> void:
	var taken := []
	var pool := st.probes.duplicate()
	st.shuffle(pool)
	for i in min(4, pool.size()):
		taken.append(pool[i])
		st.probes.erase(pool[i])
	if taken.is_empty():
		return
	var order = await e.decide("R", {"k": "order", "t": "Pista falsa: scegli le carte sonda da mettere IN CIMA al mazzo (nell'ordine); le altre vanno in fondo.", "opts": taken, "ctx": "false_lead", "probes": true})
	var top := []
	if order is Array:
		for x in order:
			if x in taken and not x in top:
				top.append(x)
	for x in taken:
		if not x in top:
			st.deck["probe"].append(x)
	top.reverse()
	for x in top:
		st.deck["probe"].push_front(x)
	# l'Impero non sa più dove si trovano queste carte, ma sa che quei sistemi non sono la base
	say("Pista falsa: i Ribelli rimettono %d carte sonda imperiali nel mazzo." % taken.size())


func reorder_objectives(k: int, f: String, show: bool) -> void:
	var top := []
	for i in k:
		var o = st.draw("obj")
		if o != null:
			top.append(o)
	if top.is_empty():
		return
	var order = await e.decide(f, {"k": "order", "t": "Ordina gli obiettivi da rimettere in cima al mazzo (il primo scelto sarà in cima).", "opts": top, "ctx": "order_objectives", "all": true, "objectives": true})
	var res := []
	if order is Array:
		for x in order:
			if x in top and not x in res:
				res.append(x)
	for x in top:
		if not x in res:
			res.append(x)
	res.reverse()
	for x in res:
		st.deck["obj"].push_front(x)
	say("%s riordina le prime %d carte del mazzo degli obiettivi." % [fs(f), top.size()])


func destroy_queue(chooser: String, f: String, max_health: int) -> void:
	var items := []
	for sp in 3:
		for t in st.queue[f][sp]:
			items.append("%d|%s" % [sp, t])
	if items.is_empty():
		return
	var r = await e.decide(chooser, {"k": "queue_pick", "t": "Scegli unità della coda di costruzione imperiale da distruggere (salute totale fino a %d)." % max_health, "opts": items, "max": items.size(), "max_health": max_health, "ctx": "destroy_queue"})
	var chosen := []
	var tot := 0
	if r is Array:
		for x in r:
			if x is int and x >= 0 and x < items.size() and not x in chosen:
				var t: String = items[x].get_slice("|", 1)
				var h := RB.health(t) if RB.health(t) > 0 else 99
				if tot + h <= max_health:
					chosen.append(x)
					tot += h
	for x in chosen:
		var sp := int(items[x].get_slice("|", 0))
		var t2: String = items[x].get_slice("|", 1)
		st.queue[f][sp].erase(t2)
		say("Distrutto nella coda: %s." % RB.unit_it(t2))


func _contingency_plan(f: String, a: Dictionary) -> void:
	var start := _starting_in_hand(f)
	if start.is_empty():
		_dispose(f, a["card"], true, a["leaders"])
		return
	var m: String = (await e.ask_pick(f, "cards", "Piano di emergenza: scegli la missione iniziale a cui assegnare Lando.", start, 1, 1, "contingency_pick"))[0]
	st.hand[f].erase(m)
	var ls: Array = a["leaders"]
	st.assign[f].append({"card": m, "leaders": ls.duplicate(), "rev": false})
	for n in ls:
		st.leaders[n]["st"] = "mission"
	if "Lando Calrissian" in ls:
		st.flags["contingency_lando"] = true
	say("Piano di emergenza: %s viene assegnato a «%s»." % [e._leader_names(ls), RB.card_name(m)])
	_dispose(f, a["card"], true, ls)


# ================================================================== obiettivi

func draw_objective() -> void:
	var o = st.draw("obj")
	if o == null:
		return
	await _gain_objective(o)


func _gain_objective(o: String) -> void:
	var info := RB.card(o)
	if info.get("momento_en", "") == "Immediate":
		say("Obiettivo immediato: [b]%s[/b]." % RB.card_name(o))
		await _immediate_objective(o)
		return
	st.objs.append(o)
	say("I Ribelli pescano una carta obiettivo.")
	e._sync()


func _immediate_objective(o: String) -> void:
	match bid(o):
		"ob_rebel_cell":
			var opts := []
			for s in st.all_systems():
				if st.is_rebel_sys(s):
					opts.append(s)
			if opts.is_empty():
				st.deck["obj_dis"].append(o)
				say("Cellula ribelle: non ci sono sistemi ribelli, la carta è scartata.")
				return
			var s := await e.ask_system("R", "Cellula ribelle: scegli il sistema ribelle dove mettere il segnalino.", opts, "marker_place")
			st.markers[o + "@1"] = s
			st.obj_play.append(o)
		"ob_raid_outposts":
			var rem := []
			for s in st.all_systems():
				if st.is_remote(s):
					rem.append(s)
			var sel := await e.ask_pick("I", "systems", "Razzie negli avamposti: scegli 2 sistemi remoti dove mettere i segnalini.", rem, 2, 2, "raid_outposts")
			for i in sel.size():
				st.markers["%s@%d" % [o, i + 1]] = sel[i]
			st.obj_play.append(o)
			say("I segnalini delle razzie sono su %s." % e._names(sel))
		_:
			st.objs.append(o)


## Obiettivi giocabili all'inizio della Fase di Ripristino.
func refresh_objectives() -> Array:
	var out := []
	for o in st.objs:
		if RB.card(o).get("momento_en", "") == "Start of Refresh Phase" and objective_ok(o):
			out.append(o)
	return out


func objective_ok(o: String) -> bool:
	var b := bid(o)
	match b:
		"ob_regional_support":
			for r in range(1, 9):
				var pops := []
				for s in RB.region_systems(r):
					if st.is_populous(s):
						pops.append(s)
				if pops.is_empty():
					continue
				var all_r := true
				for s in pops:
					if not st.has_loyalty("R", s):
						all_r = false
				if all_r:
					return true
			return false
		"ob_cut_supply_lines":
			var n := 0
			for s in st.all_systems():
				if st.is_imperial_sys(s) and (st.sys[s]["sab"] or st.has_units(s, "R")):
					n += 1
			return n >= 3
		"ob_defend_the_people":
			var n2 := 0
			for s in st.all_systems():
				if st.is_rebel_sys(s) and st.has_units(s, "R"):
					n2 += 1
			return n2 >= 4
		"ob_heart_of_the_empire":
			return st.has_units("CORUSCANT", "R") and not st.has_units("CORUSCANT", "I")
		"ob_popular_support":
			return _rebel_loyal_count() >= 6
		"ob_uprising":
			return _rebel_loyal_count() >= 9
		"ob_leave_no_one_behind":
			for n3 in st.leaders:
				if st.leaders[n3]["home"] == "R" and st.is_captured(n3):
					return false
			return true
		"ob_inspire_sympathy":
			for s in st.sys:
				if st.sys[s]["dest"]:
					return true
			return false
		"ob_establish_outposts":
			return st.systems_with_units("R").size() >= 5
		"ob_threaten_the_core":
			var n4 := 0
			for s in ["CORUSCANT"] + Array(RB.SYS["CORUSCANT"]["adiacenti"]):
				n4 += st.units_at(s, "R").size()
			return n4 >= 5
		"ob_defensive_position":
			for s in st.all_systems():
				var k := 0
				for id in st.units_at(s, "R"):
					if RB.is_structure(st.units[id]["t"]):
						k += 1
				if k >= 3:
					return true
			return false
		"ob_support_of_the_hutts":
			var n5 := 0
			for s in RB.region_systems(RB.region_of("NAL HUTTA")):
				if st.has_loyalty("R", s):
					n5 += 1
			return n5 >= 3
		"ob_the_long_war":
			return st.objs.size() >= 3
		"ob_a_time_for_peace":
			var cnt := {"T": 0, "C": 0, "S": 0}
			for sp in 3:
				for t in st.queue["R"][sp]:
					var k2: String = RB.UNITS[t]["icona"].substr(1, 1)
					cnt[k2] = cnt.get(k2, 0) + 1
			return cnt["T"] >= 2 and cnt["C"] >= 1 and cnt["S"] >= 1
		"ob_show_no_fear":
			return true
	return false


func _rebel_loyal_count() -> int:
	var n := 0
	for s in st.sys:
		if st.sys[s]["loy"] == "R":
			n += 1
	return n


func play_objective(o: String) -> void:
	var info := RB.card(o)
	st.objs.erase(o)
	var b := bid(o)
	say("I Ribelli giocano l'obiettivo [b]%s[/b]." % RB.card_name(o))
	e.emit_fx("card", {"id": o, "f": "R"})
	match b:
		"ob_inspire_sympathy":
			var n := 0
			for s in st.sys:
				if st.sys[s]["dest"]:
					n += 1
			gain_rep(n)
			st.deck["obj_dis"].append(o)
		"ob_heart_of_the_empire":
			gain_rep(int(info["reputazione"]))
			st.objs.append(o)
			say("«Cuore dell'Impero» torna in mano.")
		"ob_the_long_war":
			var others := st.objs.duplicate()
			var sel := await e.ask_pick("R", "cards", "La lunga guerra: scarta 2 obiettivi.", others, 2, 2, "long_war_discard", {"objectives": true})
			for x in sel:
				st.objs.erase(x)
				st.deck["obj_dis"].append(x)
			gain_rep(int(info["reputazione"]))
			st.deck["obj_dis"].append(o)
		"ob_a_time_for_peace":
			for k in ["T", "T", "C", "S"]:
				var done := false
				for sp in 3:
					for t in st.queue["R"][sp]:
						if not done and RB.UNITS[t]["icona"].substr(1, 1) == k:
							st.queue["R"][sp].erase(t)
							done = true
							break
			gain_rep(int(info["reputazione"]))
			st.deck["obj_dis"].append(o)
		"ob_show_no_fear":
			var s := st.base
			st.markers[o + "@1"] = s
			st.obj_play.append(o)
			say("Il segnalino «Non avere paura» è nel sistema della base ribelle.")
		_:
			gain_rep(int(info["reputazione"]))
			st.deck["obj_dis"].append(o)
	st.used_objective = true
	e._sync()


# ================================================================== fasi

func start_of_refresh() -> void:
	# segnalini degli obiettivi in gioco (Ascesa dell'Impero)
	var used := false
	for m in st.markers.keys():
		var oid: String = str(m).get_slice("@", 0)
		match bid(oid):
			"ob_show_no_fear":
				if st.markers.get(m, "") == st.base:
					say("«Non avere paura»: la base resiste, +1 reputazione.")
					gain_rep(1)
			"ob_rebel_cell":
				if not st.objs.is_empty() and await e.ask_yes("R", "Cellula ribelle: scarti un obiettivo dalla mano per guadagnare 1 reputazione (al posto di giocare un obiettivo)?", "rebel_cell"):
					var x: String = (await e.ask_pick("R", "cards", "Quale obiettivo scarti?", st.objs.duplicate(), 1, 1, "rebel_cell_discard", {"objectives": true}))[0]
					st.objs.erase(x)
					st.deck["obj_dis"].append(x)
					gain_rep(1)
					used = true
	if e._over():
		return
	st.used_objective = used
	if not used:
		var ok := refresh_objectives()
		if not ok.is_empty():
			var opts := [{"v": "", "l": "Non giocare obiettivi"}]
			for o in ok:
				opts.append({"v": o, "l": "Gioca: " + RB.card_name(o), "card": o})
			var r = await e.ask("R", "Inizio della Fase di Ripristino: giochi un obiettivo?", opts, "refresh_objective", {"confirm": true})
			if r != null and r != "":
				await play_objective(r)
	st.flags.erase("boba_where")
	st.flags.erase("yoda_used")
	st.flags.erase("contingency_lando")


func end_of_command() -> void:
	# Mobilitazione rapida
	var rm: Array = st.flags.get("rapid_mob", [])
	st.flags.erase("rapid_mob")
	for nl in rm:
		await _rapid_mobilization(int(nl))
		if e._over():
			return
	# "Rastrellare la zona"
	for a in st.acts["I"].duplicate():
		if bid(a) == "sweep_the_area" and st.flags.has("sweep_" + a):
			var s: String = st.flags["sweep_" + a]
			var cand := st.leaders_at(s, "R")
			if not cand.is_empty() and await e.ask_yes("I", "Rastrellare la zona: riveli la sonda di %s per catturare un leader lì?" % RB.sys_name(s), "use_sweep"):
				st.acts["I"].erase(a)
				st.flags.erase("sweep_" + a)
				st.probes.append(s)
				var who: String = (await e.ask_pick("I", "leaders", "Chi catturi?", cand, 1, 1, "sweep_who"))[0]
				await capture(who, " (Rastrellare la zona)")
				var dest := _closest_with_imperial(s)
				if dest != "":
					st.place_leader(who, dest)
	# Confronto (tattica avanzata): eliminazione dei leader segnati
	for n in st.flags.get("confront", []):
		if st.leaders.has(n) and st.leaders[n]["st"] in ["board", "pool"]:
			st.leaders[n]["st"] = "elim"
			say("%s non sopravvive al confronto: viene eliminato." % RB.leader_it(n))
	st.flags.erase("confront")


func _rapid_mobilization(nl: int) -> void:
	var opts := []
	if not st.base_revealed:
		opts.append({"v": "move", "l": "Sposta fino a 5 unità da un sistema alla casella Base Ribelle"})
	opts.append({"v": "base", "l": "Stabilisci una nuova base ribelle"})
	opts.append({"v": "none", "l": "Nessun effetto"})
	var r = await e.ask("R", "Mobilitazione rapida: scegli.", opts, "rapid_mob", {"confirm": true})
	if r == "move":
		var srcs := []
		for s in st.systems_with_units("R"):
			if st.leaders_at(s, "R").is_empty():
				srcs.append(s)
		if srcs.is_empty():
			return
		var src := await e.ask_system("R", "Da quale sistema arrivano le unità?", srcs, "rapid_src")
		var moved := await e.move_units("R", "BASE", [src], "move_special", {"max": 5, "ignore_adjacency": true})
	elif r == "base":
		var k := 8 if nl >= 2 else 4
		var drawn := []
		for i in k:
			var p = st.draw("probe")
			if p != null:
				drawn.append(p)
		var ok := []
		for p in drawn:
			if not st.has_loyalty("I", p) and not st.has_units(p, "I") and not st.sys[p]["dest"]:
				ok.append(p)
		var nb := ""
		if not ok.is_empty():
			nb = await e.ask_system("R", "Nuova base ribelle: scegli in segreto il sistema (o rinuncia).", ok, "new_base", true, {"secret": true})
		for p in drawn:
			if p != nb:
				st.deck["probe"].append(p)
		if nb == "":
			say("I Ribelli rinunciano a spostare la base.")
			return
		var old := st.base
		# le unità e i leader della casella Base vanno nel vecchio sistema
		for id in st.units.keys():
			if st.units[id]["loc"] == "BASE":
				st.move_unit(id, old)
		for n in st.leaders:
			if st.leaders[n]["st"] == "board" and st.leaders[n]["loc"] == "BASE":
				st.leaders[n]["loc"] = old
		st.probes.append(old)
		# la nuova base viene dal mazzo delle sonde: l'Impero sa solo che non è nei sistemi
		# delle sonde che ha visto (gli sbarchi precedenti non valgono più)
		st.known["I_not_base"] = st.probes.duplicate()
		st.base = nb
		st.base_revealed = false
		st.flags.erase("base_known")
		st.flags.erase("base_region")
		st.flags.erase("three_systems")
		# "Non avere paura" perde il segnalino
		for m in st.markers.keys():
			if bid(m.get_slice("@", 0)) == "ob_show_no_fear":
				await remove_marker(m)
		say("[b]I Ribelli abbandonano la base su %s e ne stabiliscono una nuova in segreto.[/b]" % RB.sys_name(old))
		e.emit_fx("newbase", {"old": old})
	e._sync()


func start_of_turn(f: String) -> void:
	if f == "I":
		for a in st.acts["I"].duplicate():
			if bid(a) == "secret_facility" and st.flags.has("facility_" + a):
				var s: String = st.flags["facility_" + a]
				if await e.ask_yes("I", "Struttura segreta: riveli la sonda di %s per ottenere un'unità [triangolo] e un Bunker Scudo lì?" % RB.sys_name(s), "use_facility"):
					st.acts["I"].erase(a)
					st.flags.erase("facility_" + a)
					st.probes.append(s)
					var types := []
					for ic in ["BT", "OT"]:
						for t in RB.buildable("I", ic, true):
							if st.supply(t) > 0:
								types.append({"v": t, "l": RB.unit_it(t), "unit": t})
					if not types.is_empty():
						var t2 = await e.ask("I", "Scegli l'unità [triangolo].", types, "facility_unit")
						gain_unit("I", t2, s)
					gain_unit("I", "Shield Bunker", s)
					say("Una struttura segreta imperiale si attiva su %s." % RB.sys_name(s))
					await e.after_move("I", s, [], [])
	else:
		for a in st.acts["R"].duplicate():
			if bid(a) == "under_the_radar" and st.flags.has("radar_" + a):
				if await e.ask_yes("R", "Sotto i radar: rimetti in cima al mazzo delle sonde la carta nascosta?", "use_radar"):
					st.acts["R"].erase(a)
					st.deck["probe"].push_front(st.flags["radar_" + a])
					st.flags.erase("radar_" + a)
					say("I Ribelli rimettono una carta sonda in cima al mazzo.")


# ================================================================== carte azione

func action_timing(c: String) -> String:
	return RB.card(c).get("momento_en", "")


func can_use_action(f: String, c: String, when: String) -> bool:
	var b := bid(c)
	var pool := st.leader_pool(f)
	match b:
		"proceeding_as_planned":
			return ("Admiral Ozzel" in pool or "Moff Jerjerrod" in pool) and not st.deck["proj"].is_empty()
		"start_the_evacuation":
			return "General Rieekan" in pool and not st.base_revealed
		"our_most_desperate_hour":
			return "Princess Leia" in pool and not st.deck["mis_R"].is_empty()
		"rebel_planning":
			return "Jan Dodonna" in pool
		"temporary_alliance":
			return "Mon Mothma" in pool
		"ambush":
			return "General Madine" in pool
		"local_rumors":
			return "Colonel Yularen" in pool
		"public_support":
			return "Janus Greejatus" in pool
		"an_old_friend":
			return "Han Solo" in pool and ((st.leaders.has("Lando Calrissian") and st.leaders["Lando Calrissian"]["st"] == "box") or (st.leaders.has("Chewbacca") and st.leaders["Chewbacca"]["st"] == "box"))
		"catch_them_by_surprise":
			return "Admiral Ozzel" in pool
		"boba_fett_where":
			return "Boba Fett" in pool
		"scouting_mission":
			return "Soontir Fel" in pool
		"independent_operation":
			if not "Lando Calrissian" in pool:
				return false
			for s in st.all_systems():
				if st.is_subjugated(s):
					return true
			return false
		"brilliant_administrator":
			return "Grand Moff Tarkin" in pool
		"trust_in_the_force":
			if not ("Jyn Erso" in pool or "Chirrut Imwe" in pool):
				return false
			for s in st.all_systems():
				if st.is_subjugated(s):
					return true
			return false
	return false


func _pick_card_leader(f: String, c: String, pool_only := true) -> String:
	var cand := []
	for n in RB.card(c).get("leader", []):
		if pool_only and n in st.leader_pool(f):
			cand.append(n)
	if cand.is_empty():
		return ""
	if cand.size() == 1:
		return cand[0]
	return (await e.ask_pick(f, "leaders", "Quale leader usa «%s»?" % RB.card_name(c), cand, 1, 1, "action_leader"))[0]


func use_action(f: String, c: String, when: String) -> void:
	var b := bid(c)
	st.acts[f].erase(c)
	say("%s usa la carta azione [b]%s[/b]." % [fs(f), RB.card_name(c)])
	e.emit_fx("card", {"id": c, "f": f})
	var n := await _pick_card_leader(f, c)
	match b:
		"proceeding_as_planned":
			var proj: Array = st.deck["proj"]
			var m: String = (await e.ask_pick(f, "cards", "Scegli il progetto a cui assegnare %s." % RB.leader_it(n), proj.duplicate(), 1, 1, "pick_project"))[0]
			proj.erase(m)
			st.shuffle(proj)
			st.assign[f].append({"card": m, "leaders": [n], "rev": false})
			st.leaders[n]["st"] = "mission"
		"our_most_desperate_hour":
			var deck: Array = st.deck["mis_R"]
			var m2: String = (await e.ask_pick(f, "cards", "Scegli la missione a cui assegnare la Principessa Leia.", deck.duplicate(), 1, 1, "pick_mission"))[0]
			deck.erase(m2)
			st.shuffle(deck)
			st.assign[f].append({"card": m2, "leaders": [n], "rev": false})
			st.leaders[n]["st"] = "mission"
		"start_the_evacuation":
			var opts := []
			for s in st.all_systems():
				if not st.has_units(s, "I"):
					opts.append(s)
			var s := await e.ask_system(f, "Iniziare l'evacuazione: scegli il sistema.", opts, "evacuation")
			st.place_leader(n, s)
			var moved := await e.move_units("R", s, ["BASE"], "move_special", {})
			await e.after_move("R", s, moved, ["BASE"])
		"rebel_planning":
			st.place_leader(n, "BASE")
			await draw_objective()
		"temporary_alliance":
			var opts2 := []
			for s in st.all_systems():
				if st.is_neutral(s) and st.is_populous(s):
					opts2.append(s)
			if not opts2.is_empty():
				var s2 := await e.ask_system(f, "Alleanza temporanea: scegli un sistema neutrale.", opts2, "temp_alliance")
				st.place_leader(n, s2)
				await queue_from_icons("R", s2)
		"ambush":
			var s3 := await e.ask_system(f, "Imboscata: scegli il sistema.", st.all_systems(), "ambush")
			st.place_leader(n, s3)
			await destroy_health("R", s3, "I", 3, "ground")
		"local_rumors":
			var opts3 := []
			for s in st.all_systems():
				if st.has_units(s, "I"):
					opts3.append(s)
			var s4 := await e.ask_system(f, "Voci locali: scegli il sistema.", opts3, "local_rumors")
			st.place_leader(n, s4)
			var reg := RB.region_of(s4)
			var yes := RB.region_of(st.base) == reg
			say("Voci locali: la base ribelle %s nella %s." % ["[b]è[/b]" if yes else "non è", RB.REGION_NAME[reg]])
			_record_region(reg, yes)
		"public_support":
			var opts4 := []
			for s in st.all_systems():
				if st.is_imperial_sys(s) and not st.has_units(s, "R", "terra"):
					opts4.append(s)
			if not opts4.is_empty():
				var s5 := await e.ask_system(f, "Sostegno pubblico: scegli il sistema imperiale.", opts4, "public_support")
				st.place_leader(n, s5)
				for i in 3:
					gain_unit("I", "Stormtrooper", s5)
				st.flags["public_support"] = n
				say("Tre Assaltatori arrivano su %s." % RB.sys_name(s5))
		"an_old_friend":
			var opts5 := []
			if st.leaders.has("Lando Calrissian") and st.leaders["Lando Calrissian"]["st"] == "box":
				opts5.append({"v": "BESPIN", "l": "Bespin: recluta Lando Calrissian"})
			if st.leaders.has("Chewbacca") and st.leaders["Chewbacca"]["st"] == "box":
				opts5.append({"v": "KASHYYYK", "l": "Kashyyyk: recluta Chewbacca"})
			var r = await _choose_one(f, "Un vecchio amico: dove va Han Solo?", opts5, "old_friend")
			st.place_leader(n, r)
			var who := "Lando Calrissian" if r == "BESPIN" else "Chewbacca"
			st.place_leader(who, r)
			say("Han Solo ritrova un vecchio amico: %s si unisce all'Alleanza." % RB.leader_it(who))
		"catch_them_by_surprise":
			var s6 := await e.ask_system(f, "Coglierli di sorpresa: scegli il sistema.", st.all_systems(), "surprise")
			st.place_leader(n, s6)
			var srcs := []
			for x in RB.SYS[s6]["adiacenti"]:
				if st.leaders_at(x, "I").is_empty() and st.has_units(x, "I"):
					srcs.append(x)
			var moved2 := await e.move_units("I", s6, srcs, "activate_move", {})
			await e.after_move("I", s6, moved2, srcs)
		"boba_fett_where":
			var opts6 := []
			for s in st.all_systems():
				if st.is_imperial_sys(s):
					opts6.append(s)
			var s7 := await e.ask_system(f, "Boba Fett? Dove?: scegli il sistema imperiale.", opts6, "boba_where")
			st.place_leader(n, s7)
			st.flags["boba_where"] = s7
			say("Nessun leader ribelle oserà agire su %s in questa Fase di Comando." % RB.sys_name(s7))
		"scouting_mission":
			var s8 := await e.ask_system(f, "Missione esplorativa: scegli il sistema.", st.all_systems(), "scouting")
			st.place_leader(n, s8)
			var srcs2 := []
			for x in st.all_systems():
				if x != s8 and st.count_type(x, "TIE Fighter", "I") > 0:
					srcs2.append(x)
			var moved3 := await e.move_units("I", s8, srcs2, "move_special", {"ignore_transport": true, "types": {"TIE Fighter": 4}})
			await e.after_move("I", s8, moved3, srcs2, st.has_units(s8, "R", "spazio"))
		"independent_operation":
			var opts7 := []
			for s in st.all_systems():
				if st.is_subjugated(s):
					opts7.append(s)
			var s9 := await e.ask_system(f, "Operazione indipendente: scegli il sistema sottomesso.", opts7, "indep_op")
			st.place_leader(n, s9)
			var dests := []
			for x in st.all_systems():
				if st.is_imperial_sys(x) and x != s9 and not st.has_units(x, "R", "terra"):
					dests.append(x)
			if not dests.is_empty():
				var d := await e.ask_system("I", "Operazione indipendente: dove sposti le tue unità terrestri da %s?" % RB.sys_name(s9), dests, "indep_dest")
				for id in st.units_at(s9, "I", "terra"):
					if not RB.UNITS[st.units[id]["t"]]["immobile"]:
						st.move_unit(id, d)
				say("Le truppe imperiali lasciano %s per %s." % [RB.sys_name(s9), RB.sys_name(d)])
				st.update_subjugation(s9)
		"brilliant_administrator":
			var opts8 := []
			for s in st.all_systems():
				if st.is_imperial_sys(s):
					opts8.append(s)
			var s10 := await e.ask_system(f, "Amministratore brillante: scegli il sistema imperiale.", opts8, "administrator")
			st.place_leader(n, s10)
			await queue_from_icons("I", s10)
		"trust_in_the_force":
			var opts9 := []
			for s in st.all_systems():
				if st.is_subjugated(s):
					opts9.append(s)
			var s11 := await e.ask_system(f, "Fidati della Forza: scegli il sistema sottomesso.", opts9, "trust_force")
			st.place_leader(n, s11)
			st.gain_loyalty("R", s11)
			await destroy_health("R", s11, "I", 99, "triangle_ground", 1)
		_:
			say("(Carta azione non gestita.)")
	e._sync()


## Carte azione "Immediata" (si risolvono appena pescate).
func immediate_action(f: String, c: String) -> void:
	var b := bid(c)
	match b:
		"human_cyborg_relations", "resourceful_astromech", "he_means_well":
			var ring: String = {"human_cyborg_relations": "c3po", "resourceful_astromech": "r2d2", "he_means_well": "k2so"}[b]
			var cand := []
			for n in st.leaders:
				var l: Dictionary = st.leaders[n]
				if l["f"] == "R" and l["st"] in ["pool", "board", "mission"] and (l["ring"] == "" or b != "he_means_well") and not st.is_captured(n) and l["ring"] != "lure":
					cand.append(n)
			cand.sort()
			if cand.is_empty():
				return
			var n2: String = (await e.ask_pick(f, "leaders", "A quale leader aggiungi l'anello di %s?" % RB.RING_IT[ring], cand, 1, 1, "ring_who"))[0]
			st.leaders[n2]["ring"] = ring
			st.acts[f].erase(c)
			say("%s si unisce a %s." % [RB.RING_IT[ring], RB.leader_it(n2)])
		"the_millennium_falcon":
			var cand2 := []
			for n in ["Han Solo", "Chewbacca"]:
				if st.leaders.has(n) and st.recruited(n) and st.leaders[n]["f"] == "R" and not st.leaders[n]["ring"] in ["captured", "carbonite", "lure", "bounty"]:
					cand2.append(n)
			if cand2.is_empty():
				st.acts[f].erase(c)
				return
			var n3: String = (await e.ask_pick(f, "leaders", "Chi pilota il Millennium Falcon?", cand2, 1, 1, "ring_who"))[0]
			st.leaders[n3]["ring"] = "falcon"
			st.acts[f].erase(c)
			say("Il Millennium Falcon è pronto, ai comandi c'è %s." % RB.leader_it(n3))
		"early_promotion", "rebel_extremist":
			st.acts[f].erase(c)
			var who := "Admiral Motti" if b == "early_promotion" else "Saw Gerrera"
			var opts := [{"v": "card", "l": "Pesca 1 carta azione iniziale"}]
			if st.leaders.has(who) and st.leaders[who]["st"] == "box":
				opts.append({"v": "rec", "l": "Recluta %s%s" % [RB.leader_it(who), " (perdi 1 reputazione)" if b == "rebel_extremist" else ""]})
			var r = await _choose_one(f, "«%s»: scegli." % RB.card_name(c), opts, "early_choice")
			if r == "rec":
				if b == "early_promotion":
					var opts2 := []
					for s in st.all_systems():
						if st.is_imperial_sys(s):
							opts2.append(s)
					var s := await e.ask_system(f, "Dove metti l'Ammiraglio Motti e il Gran Moff Tarkin?", opts2, "promotion_place")
					st.place_leader(who, s)
					if st.leaders["Grand Moff Tarkin"]["st"] == "pool":
						st.place_leader("Grand Moff Tarkin", s)
					say("L'Ammiraglio Motti viene promosso e raggiunge Tarkin su %s." % RB.sys_name(s))
				else:
					st.leaders[who]["st"] = "pool"
					lose_rep(1)
					say("Saw Gerrera si unisce alla causa, a modo suo.")
			else:
				var x = st.draw("start_" + f)
				if x != null:
					st.acts[f].append(x)
					if action_timing(x) == "Immediate":
						await immediate_action(f, x)
		"lord_vaders_orders":
			st.acts[f].erase(c)
			await reorder_objectives(3, "I", false)
		"secret_facility", "sweep_the_area":
			if st.probes.is_empty():
				return
			var p: String = (await e.ask_pick(f, "cards", "Scegli una tua carta sonda da mettere sotto «%s»." % RB.card_name(c), st.probes.duplicate(), 1, 1, "probe_under", {"probes": true})).front()
			st.probes.erase(p)
			st.flags[("facility_" if b == "secret_facility" else "sweep_") + c] = p
			say("L'Impero mette in serbo una carta sonda per «%s»." % RB.card_name(c))
		"under_the_radar":
			var top := []
			for i in 4:
				var x2 = st.draw("probe")
				if x2 != null:
					top.append(x2)
			if top.is_empty():
				return
			var keep: String = (await e.ask_pick(f, "cards", "Sotto i radar: scegli la carta sonda da tenere nascosta.", top, 1, 1, "radar_keep", {"probes": true}))[0]
			st.flags["radar_" + c] = keep
			var others := []
			for x3 in top:
				if x3 != keep:
					others.append(x3)
			var r2 = await _choose_one(f, "Le altre carte sonda vanno in cima o in fondo al mazzo?", [{"v": "top", "l": "In cima"}, {"v": "bottom", "l": "In fondo"}], "radar_where")
			for x3 in others:
				if r2 == "top":
					st.deck["probe"].push_front(x3)
				else:
					st.deck["probe"].append(x3)
			say("I Ribelli nascondono una carta sonda sotto i radar.")
	e._sync()


func false_orders(c: String) -> void:
	var cand := []
	for i in st.assign["I"].size():
		var a: Dictionary = st.assign["I"][i]
		if a["leaders"].size() == 1:
			cand.append({"v": i, "l": "%s (%s)" % [RB.leader_it(a["leaders"][0]), "missione coperta"]})
	if cand.is_empty():
		return
	cand.append({"v": -1, "l": "Non usare «Ordini falsi»"})
	var r = await e.ask("R", "Ordini falsi: scegli un leader imperiale da solo su una missione: torna nella riserva.", cand, "false_orders", {"confirm": true})
	if r == null or int(r) < 0:
		return
	var a2: Dictionary = st.assign["I"][int(r)]
	st.acts["R"].erase(c)
	st.assign["I"].remove_at(int(r))
	st.hand["I"].append(a2["card"])
	st.to_pool(a2["leaders"][0])
	say("Ordini falsi! %s torna nella riserva e la sua missione in mano all'Impero." % RB.leader_it(a2["leaders"][0]))
	e._sync()
