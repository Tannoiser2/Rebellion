class_name RBCombatCine
extends RefCounted
## Combattimento cinematografico dell'Ascesa dell'Impero.
## Prima di ogni round di battaglia ciascuno sceglie in segreto una carta tattica avanzata del suo
## mazzo (che non si mescola mai) e ne risolve l'abilità in alto o in basso. Poi si attacca: i danni
## si accumulano e le unità sono distrutte solo alla fine del round di battaglia. Come azione di
## combattimento si può ritirare tanti dadi quanto il valore tattico del leader (una volta per
## attacco) e spendere uno speciale per togliere 1 danno a una propria unità del colore del dado.

var e: RBEngine
var cb: RBCombat
var r := {}                     # effetti del round di battaglia in corso

var st: RBState:
	get:
		return e.st

var c: Dictionary:
	get:
		return cb.c


func _init(engine: RBEngine) -> void:
	e = engine


func say(t: String) -> void:
	e.say(t)


func _deck(f: String, th: String) -> String:
	return "atac_%s_%s" % [th, f]


func _dis(f: String, th: String) -> String:
	return "atac_dis_%s_%s" % [th, f]


# ================================================================== un round di battaglia

func round_of_battle(combat: RBCombat, th: String) -> void:
	cb = combat
	var s: String = c["sys"]
	var att: String = c["att"]
	var def: String = c["def"]
	r = {"prevent": {"R": {"rosso": 0, "nero": 0, "dh": 0}, "I": {"rosso": 0, "nero": 0, "dh": 0}},
		"no_remove": {"R": false, "I": false}, "no_remove_ids": [], "after": {"R": [], "I": []},
		"tractor": false, "confront": "", "imp_ground_start": st.has_units(s, "I", "terra"), "removed": []}
	# Generatore di scudo: recupera 1 carta tattica terrestre per generatore prima della scelta
	if th == "terra":
		var k := st.count_type(s, "Shield Generator", "R")
		if k > 0:
			await retrieve("R", th, k)
	# 1-2. scelta segreta e rivelazione
	var chosen := {}
	for f in [att, def]:
		if not st.has_units(s, f, th):
			continue
		if int(c["flags"].get("noplay_%s_%s" % [f, th], -1)) == int(c["round"]):
			say("%s non può giocare una carta tattica %s in questo round." % [RBState.fshort(f), "spaziale" if th == "spazio" else "terrestre"])
			continue
		var card := await _choose(f, th, "Scegli in segreto la carta tattica avanzata per questo round di battaglia %s." % ("spaziale" if th == "spazio" else "terrestre"))
		if card != "":
			chosen[f] = card
	for f in chosen:
		say("%s gioca la tattica avanzata [b]%s[/b]." % [RBState.fshort(f), RB.card_name(chosen[f])])
		e.emit_fx("card", {"id": chosen[f], "f": f})
	e._sync()
	await e.pause(0.6)
	# 3. risoluzione: prima il giocatore di turno, salvo che il difensore annulli
	var order := [att, def]
	var side := {}
	var canceled := {}
	if chosen.has(def) and _has_cancel(chosen[def]) and usable(def, chosen[def], "top"):
		side[def] = await _ask_side(def, chosen[def])
		if side[def] == "top":
			order = [def, att]
	for f in order:
		if not chosen.has(f):
			continue
		var card2: String = chosen[f]
		if canceled.get(f, false):
			say("La carta «%s» è annullata." % RB.card_name(card2))
			_discard(f, card2, th)
			continue
		var sd: String = side[f] if side.has(f) else await _ask_side(f, card2)
		if sd != "none":
			await _resolve(f, card2, sd, th, canceled, true)
		if not card2 in r["removed"]:
			_discard(f, card2, th)
		if e._over():
			return
	cb._flush_kills()
	e._sync()
	# 4. attacchi (l'ordine può essere invertito dalle carte)
	var first := att
	var after = c["flags"].get("after_" + th, "")
	if after == att:
		first = def
	for f2 in [first, RBState.other(first)]:
		if st.has_units(s, f2, th) and st.has_units(s, RBState.other(f2), th):
			await _attack(f2, th)
			if e._over():
				return
	# 5. fine del round: si distruggono le unità con danni pari o superiori alla salute
	for id in st.units_at(s, "", th):
		var u: Dictionary = st.units[id]
		if RB.health(u["t"]) > 0 and int(u["dmg"]) >= cb.health_of(id):
			cb._kill(id)
	cb._flush_kills()
	# Confronto: l'ultima unità terrestre imperiale è caduta in questo round
	if r["confront"] != "":
		var card3: String = r["confront"]
		var imps := st.leaders_at(s, "I")
		if r["imp_ground_start"] and not st.has_units(s, "I", "terra") and not imps.is_empty():
			var n: String = (await e.ask_pick("R", "leaders", "Confronto: scegli il leader imperiale che sarà eliminato alla fine della Fase di Comando.", imps, 1, 1, "confront_who"))[0]
			if not st.flags.has("confront"):
				st.flags["confront"] = []
			st.flags["confront"].append(n)
			say("Confronto: %s sarà eliminato alla fine della Fase di Comando. La carta esce dal gioco." % RB.leader_it(n))
		else:
			_discard("R", card3, "terra")
	# Raggio traente
	if r["tractor"] and not st.has_units(s, "R", "spazio") and st.count_type(s, "Star Destroyer", "I") > 0:
		var cand := []
		for n2 in st.leaders_at(s, "R"):
			if not st.is_captured(n2):
				cand.append(n2)
		if not cand.is_empty():
			cand.push_front("")
			var opts := [{"v": "", "l": "Nessuno"}]
			for n3 in cand:
				if n3 != "":
					opts.append({"v": n3, "l": "Cattura " + RB.leader_it(n3), "leader": n3})
			var who = await e.ask("I", "Raggio traente: vuoi catturare un leader ribelle?", opts, "tractor_beam", {"confirm": true, "ai_best": opts[1]["v"]})
			if who != null and who != "":
				await e.cards.capture(who, " (Raggio traente)")
	await cb._combat_objectives_now()
	e._sync()


## Dopo la fase di ritirata: «Rogue One».
func after_retreat(combat: RBCombat) -> void:
	cb = combat
	if c.is_empty():
		return
	if int(c["flags"].get("rogue_one_round", -1)) != int(c["round"]) or not c["retreated"]["R"]:
		return
	c["flags"].erase("rogue_one_round")
	var s: String = c["sys"]
	var opts := [{"v": "", "l": "Niente"}]
	for n in st.captured_at(s):
		opts.append({"v": "r:" + n, "l": "Libera " + RB.leader_it(n), "leader": n})
	for m in st.markers:
		if st.markers[m] == s:
			opts.append({"v": "m:" + str(m), "l": "Rimuovi il segnalino bersaglio da %s" % RB.sys_name(s)})
	if opts.size() <= 1:
		return
	var x = await e.ask("R", "Rogue One: ti sei ritirato, cosa fai?", opts, "rogue_one", {"confirm": true, "ai_best": opts[1]["v"]})
	if x is String and x.begins_with("r:"):
		await e.cards.rescue(x.substr(2), [])
	elif x is String and x.begins_with("m:"):
		e.cards.remove_marker(x.substr(2))
	e._sync()


# ================================================================== mazzi

func _choose(f: String, th: String, title: String) -> String:
	var key := _deck(f, th)
	if not st.deck.has(key):
		return ""
	if st.deck[key].is_empty():
		st.deck[key].append_array(st.deck[_dis(f, th)])
		st.deck[_dis(f, th)].clear()
	if st.deck[key].is_empty():
		return ""
	var opts: Array = st.deck[key].duplicate()
	var best := _best_card(f, opts)
	var pick := await e.ask_pick(f, "cards", title, opts, 1, 1, "cine_tactic", {"th": th, "ai_best": [best], "secret": true})
	var card: String = pick[0]
	st.deck[key].erase(card)
	return card


func _discard(f: String, card: String, th: String) -> void:
	st.deck[_dis(f, th)].append(card)
	# finito il mazzo, gli scarti tornano nel mazzo (tranne la carta appena risolta)
	if st.deck[_deck(f, th)].is_empty():
		for x in st.deck[_dis(f, th)]:
			if x != card:
				st.deck[_deck(f, th)].append(x)
		st.deck[_dis(f, th)] = [card]


## «Pescare» carte tattica: si recuperano carte a scelta dagli scarti.
func retrieve(f: String, th: String, k: int) -> void:
	var dis: Array = st.deck.get(_dis(f, th), [])
	if dis.is_empty() or k <= 0:
		return
	var best := []
	var sorted := dis.duplicate()
	sorted.sort_custom(func(a, b): return card_value(f, a) > card_value(f, b))
	best = sorted.slice(0, k)
	var pick := await e.ask_pick(f, "cards", "Recupera fino a %d carte tattica dagli scarti." % k, dis.duplicate(), 0, k, "cine_retrieve", {"ai_best": best, "confirm": true})
	for x in pick:
		dis.erase(x)
		st.deck[_deck(f, th)].append(x)
	if not pick.is_empty():
		say("%s recupera %d carte tattica avanzate." % [RBState.fshort(f), pick.size()])


# ================================================================== abilità

func _units_req(card: String, side: String) -> String:
	var v = RB.card(card).get("sopra_unita" if side == "top" else "sotto_unita")
	return "" if v == null else str(v)


## L'abilità si può usare (c'è almeno un'unità del tipo richiesto nel sistema)?
func usable(f: String, card: String, side: String) -> bool:
	var req := _units_req(card, side)
	if req == "":
		return true
	for t in req.split(" OR "):
		if st.count_type(c["sys"], t.strip_edges(), f) > 0:
			return true
	return false


func _has_cancel(card: String) -> bool:
	return RB.base_id(card) in ["av_i_air_superiority", "av_i_entrapment", "av_r_outrun_them"]


func _ask_side(f: String, card: String) -> String:
	var C := RB.card(card)
	var opts := []
	if usable(f, card, "top"):
		opts.append({"v": "top", "l": "In alto: " + str(C["sopra"]), "card": card})
	else:
		opts.append({"v": "top_no", "l": "In alto (serve: %s)" % RB.unit_it(_units_req(card, "top").get_slice(" OR ", 0)), "d": str(C["sopra"])})
	if usable(f, card, "bottom"):
		opts.append({"v": "bottom", "l": "In basso: " + str(C["sotto"])})
	opts.append({"v": "none", "l": "Nessuna abilità (scarta)"})
	var playable := []
	for o in opts:
		if o["v"] != "top_no":
			playable.append(o)
	var best := "none"
	var bv := 0.0
	for sd in ["top", "bottom"]:
		if usable(f, card, sd):
			var v := side_value(f, card, sd)
			if v > bv:
				bv = v
				best = sd
	var x = await e.ask(f, "«%s»: quale abilità risolvi?" % RB.card_name(card), playable, "cine_side", {"confirm": true, "ai_best": best, "card": card})
	return str(x) if x != null else "none"


func _resolve(f: String, card: String, side: String, th: String, canceled: Dictionary, can_cancel: bool) -> void:
	var o := RBState.other(f)
	var s: String = c["sys"]
	var top := side == "top"
	say("%s risolve «%s» (%s)." % [RBState.fshort(f), RB.card_name(card), "in alto" if top else "in basso"])
	match RB.base_id(card):
		# ---------------------------------------------------------------- Impero, terra
		"av_i_air_superiority":
			if top:
				if can_cancel:
					canceled[o] = true
			else:
				_no_play(o, "terra")
		"av_i_armored_patrol":
			_prevent(f, 2 if top else 1, 2 if top else 1, 0)
		"av_i_armored_position":
			if top:
				r["after"][f].append("bunker")
			else:
				c["flags"]["after_terra"] = f
		"av_i_bombardment":
			if top:
				if st.count_type(s, "Shield Generator", "R") == 0:
					await _deal(f, "terra", 2, "nero")
			else:
				await _deal(f, "terra", 1)
		"av_i_imposing_presence":
			if top:
				r["no_remove"]["R"] = true
			else:
				await _extra(f, th)
		"av_i_overrun":
			await _deal(f, "terra", 2 if top else 1)
		"av_i_support_of_the_501st", "av_r_hold_them_back":
			if top:
				await _destroy(f, "terra", func(id): return RB.UNITS[st.units[id]["t"]]["icona"] == "OT")
			else:
				await _deal(f, "terra", 1, "nero")
		"av_i_target_the_generator":
			if top:
				await _destroy(f, "terra", func(id): return RB.is_structure(st.units[id]["t"]))
			else:
				await _deal(f, "terra", 1, "rosso")
		# ---------------------------------------------------------------- Impero, spazio
		"av_i_energy_shield":
			if top:
				r["after"][f].append("ships2")
			else:
				c["flags"]["after_spazio"] = f
		"av_i_entrapment":
			if top:
				if can_cancel:
					canceled[o] = true
				await _extra(f, th)
			else:
				_no_play(o, "spazio")
		"av_i_intercept":
			if top:
				await _destroy(f, "terra", func(id): return RB.UNITS[st.units[id]["t"]]["icona"] == "OT")
			else:
				r["no_remove"]["R"] = true
		"av_i_overwhelming_presence":
			_prevent(f, 2, 0, 1 if top else 0)
		"av_i_reinforcements":
			if top:
				_gain(f, ["TIE Fighter"])
			_prevent(f, 0, 2, 0)
		"av_i_superlaser_blast":
			if top:
				await _deal(f, "spazio", 5, "", true, func(id): return RB.is_capital(st.units[id]["t"]))
			else:
				await _deal(f, "spazio", 1)
		"av_i_swarm_tactics":
			if top:
				if _fighters(s, "I") > _fighters(s, "R"):
					await _deal(f, "spazio", 2)
			else:
				await _deal(f, "spazio", 1, "nero")
		"av_i_tractor_beam":
			if top:
				r["tractor"] = true
			else:
				await _deal(f, "spazio", 1, "rosso")
		# ---------------------------------------------------------------- Ribelli, spazio
		"av_r_bombing_run":
			await _deal(f, "spazio", 2 if top else 1, "rosso")
		"av_r_rogue_squadron_support":
			await _deal(f, "spazio", 2 if top else 1, "nero")
		"av_r_deployment":
			if top:
				_gain(f, ["Rebel Trooper", "Rebel Vanguard"])
			else:
				r["no_remove"]["I"] = true
		"av_r_draw_their_fire":
			if top:
				r["after"][f].append("ships2_nonebulon")
			else:
				c["flags"]["after_spazio"] = f
		"av_r_escort":
			if top:
				_prevent(f, 1, 1, 1)
			else:
				_prevent(f, 0, 2, 0)
		"av_r_fleet_logistics":
			_prevent(f, 2, 0, 0)
			if top:
				await _extra(f, th)
		"av_r_ion_blast":
			if top:
				var ids := await _deal(f, "spazio", 1, "", true, func(id): return RB.is_capital(st.units[id]["t"]))
				r["no_remove_ids"].append_array(ids)
			else:
				await _deal(f, "spazio", 1)
		"av_r_outrun_them":
			if top:
				if can_cancel:
					canceled[o] = true
			else:
				_no_play(o, "spazio")
		# ---------------------------------------------------------------- Ribelli, terra
		"av_r_confrontation":
			if top:
				r["confront"] = card
				r["removed"].append(card)
			else:
				await _extra(f, th)
		"av_r_escape_plan":
			if top:
				c["flags"]["escape_plan_R"] = c["round"]
				await cb._maybe_retreat("R")
				if c["retreated"]["R"] and can_cancel:
					canceled[o] = true
			else:
				_no_play(o, "terra")
		"av_r_planetary_shield":
			if top:
				r["after"][f].append("generator")
			else:
				c["flags"]["after_terra"] = f
		"av_r_rogue_one":
			if top:
				c["flags"]["rogue_one_round"] = c["round"]
			else:
				r["no_remove"]["I"] = true
		"av_r_take_cover":
			_prevent(f, 2 if top else 1, 2 if top else 1, 0)
		"av_r_take_it_down":
			await _deal(f, "terra", 2 if top else 1, "rosso")
		"av_r_tow_cables":
			if top:
				await _deal(f, "terra", 4, "", true, func(id): return st.units[id]["t"] in ["AT-AT", "AT-ST"])
			else:
				await _deal(f, "terra", 1)
	e._sync()


func _no_play(o: String, th: String) -> void:
	c["flags"]["noplay_%s_%s" % [o, th]] = int(c["round"]) + 1


func _prevent(f: String, red: int, black: int, dh: int) -> void:
	r["prevent"][f]["rosso"] += red
	r["prevent"][f]["nero"] += black
	r["prevent"][f]["dh"] += dh


func _fighters(s: String, f: String) -> int:
	var n := 0
	for id in st.units_at(s, f, "spazio"):
		if RB.is_fighter(st.units[id]["t"]):
			n += 1
	return n


func _gain(f: String, types: Array) -> void:
	for t in types:
		if st.supply(t) > 0:
			st.add_unit(t, f, c["sys"])
			say("%s ottiene 1 %s nel sistema." % [RBState.fshort(f), RB.unit_it(t)])
			return


## Una carta tattica aggiuntiva: non si può annullare e non annulla.
func _extra(f: String, th: String) -> void:
	var key := _deck(f, th)
	if st.deck[key].is_empty():
		return
	var card := await _choose(f, th, "Puoi giocare una carta tattica aggiuntiva.")
	if card == "":
		return
	say("%s gioca anche [b]%s[/b]." % [RBState.fshort(f), RB.card_name(card)])
	e.emit_fx("card", {"id": card, "f": f})
	var sd := await _ask_side(f, card)
	if sd != "none":
		await _resolve(f, card, sd, th, {}, false)
	if not card in r["removed"]:
		_discard(f, card, th)


## Infligge n danni alle unità avversarie del teatro (eventualmente di un colore o a una sola unità).
## I danni restano sulle unità: si contano alla fine del round di battaglia.
func _deal(f: String, th: String, n: int, color := "", one := false, filter := Callable()) -> Array:
	var o := RBState.other(f)
	var s: String = c["sys"]
	var hit := []
	var left := n
	while left > 0:
		var cand := []
		for id in st.units_at(s, o, th):
			var t: String = st.units[id]["t"]
			if RB.health(t) <= 0:
				continue
			if color != "" and RB.health_color(t) != color:
				continue
			if filter.is_valid() and not filter.call(id):
				continue
			cand.append(id)
		if cand.is_empty():
			break
		var k := left if one else 1
		var best := _best_target(cand, k)
		var pick := await e.ask_pick(f, "units", "Infliggi %d dann%s%s%s." % [k, "o" if k == 1 else "i", (" " + ("rosso" if color == "rosso" else "nero") + ("" if k == 1 else "")) if color != "" else "", " (ne restano %d)" % left if not one and left > 1 else ""], cand, 1, 1, "card_damage", {"dmg": k, "sys": s, "ai_best": [best]})
		var id2: int = pick[0]
		st.units[id2]["dmg"] = int(st.units[id2]["dmg"]) + k
		say("%d dann%s a %s." % [k, "o" if k == 1 else "i", st.unit_name(id2)])
		e.emit_fx("damage", {"hits": {id2: k}})
		hit.append(id2)
		left -= k
	e._sync()
	return hit


func _best_target(cand: Array, k: int) -> int:
	var best: int = cand[0]
	var bv := -99.0
	for id in cand:
		var t: String = st.units[id]["t"]
		var rest := cb.health_of(id) - int(st.units[id]["dmg"])
		var v := RBAI.unit_power(t) + RB.health(t) * 0.3
		if rest <= k:
			v += 3.0 + RB.health(t)
		else:
			v -= rest * 0.2
		if v > bv:
			bv = v
			best = id
	return best


func _destroy(f: String, th: String, filter: Callable) -> void:
	var o := RBState.other(f)
	var cand := []
	for id in st.units_at(c["sys"], o, th):
		if filter.call(id) and not id in c.get("pending_kill", []):
			cand.append(id)
	if cand.is_empty():
		return
	cand.sort_custom(func(a, b): return RBAI.unit_power(st.units[a]["t"]) + RB.health(st.units[a]["t"]) > RBAI.unit_power(st.units[b]["t"]) + RB.health(st.units[b]["t"]))
	var pick := await e.ask_pick(f, "units", "Scegli l'unità da distruggere.", cand, 1, 1, "destroy", {"ai_best": [cand[0]]})
	cb._kill(pick[0])


# ================================================================== attacco

func _attack(f: String, th: String) -> void:
	var s: String = c["sys"]
	var o := RBState.other(f)
	var dice := cb.roll_attack(f, th)
	if dice.is_empty():
		return
	e.emit_fx("combat_dice", {"f": f, "dice": dice.duplicate(true), "th": th})
	say("%s tira %d dadi: %s." % [RBState.fshort(f), dice.size(), RBCombat.dice_text(dice)])
	await e.pause(0.9)
	c["pending"] = {}
	c["step_flags"] = {}
	var rerolled := false
	var guard := 0
	while guard < 20:
		guard += 1
		var opts := []
		var tv := st.tactic_value(s, f, th)
		var blanks := 0
		for d in dice:
			if int(d["v"]) == 0 and not d.get("spent", false):
				blanks += 1
		if not rerolled and tv > 0:
			opts.append({"v": "reroll", "l": "Ritira fino a %d dadi (valore tattico del leader)" % tv})
		var heal := _heal_options(f, th, dice)
		opts.append_array(heal)
		if opts.is_empty():
			break
		opts.append({"v": "done", "l": "Fine delle azioni: assegna i danni"})
		var best := "done"
		if not heal.is_empty():
			best = heal[0]["v"]
		elif not rerolled and tv > 0 and blanks > 0:
			best = "reroll"
		var x = await e.ask(f, "%s: azioni di combattimento (dadi: %s)." % [RBState.fshort(f), RBCombat.dice_text(dice)], opts, "cine_action", {"confirm": true, "th": th, "dice": dice.duplicate(true), "ai_best": best})
		if x == null or x == "done":
			break
		if x == "reroll":
			rerolled = true
			var idx := []
			for i in dice.size():
				if not dice[i].get("spent", false):
					idx.append(i)
			var aib := []
			for i in idx:
				if int(dice[i]["v"]) == 0 and aib.size() < tv:
					aib.append(i)
			var rr = await e.decide(f, {"k": "dice_pick", "t": "Scegli fino a %d dadi da ritirare (tutti insieme)." % tv, "dice": dice.duplicate(true), "opts": idx, "max": tv, "ctx": "reroll", "ai_best": aib})
			var k := 0
			if rr is Array:
				for i in rr:
					if i in idx and k < tv:
						dice[i]["v"] = st.green_face() if dice[i]["c"] == "verde" else st._face()
						k += 1
			say("Dadi ritirati: %s." % RBCombat.dice_text(dice))
			e.emit_fx("combat_dice", {"f": f, "dice": dice.duplicate(true), "th": th})
		elif str(x).begins_with("heal:"):
			var parts := str(x).split(":")
			var di := int(parts[1])
			var uid := int(parts[2])
			if st.units.has(uid) and int(st.units[uid]["dmg"]) > 0:
				st.units[uid]["dmg"] = int(st.units[uid]["dmg"]) - 1
				dice[di]["spent"] = true
				say("%s spende uno speciale: tolto 1 danno a %s." % [RBState.fshort(f), st.unit_name(uid)])
		e._sync()
	# l'avversario previene i colpi con la sua carta
	var prev: Dictionary = r["prevent"][o]
	var stopped := 0
	for d in dice:
		if d.get("spent", false):
			continue
		var v := int(d["v"])
		if v == 1 and d["c"] in ["rosso", "nero"] and int(prev[d["c"]]) > 0:
			prev[d["c"]] = int(prev[d["c"]]) - 1
			d["spent"] = true
			stopped += 1
		elif v == 2 and int(prev["dh"]) > 0:
			prev["dh"] = int(prev["dh"]) - 1
			d["spent"] = true
			stopped += 1
	if stopped > 0:
		say("%s previene %d colpi." % [RBState.fshort(o), stopped])
	await cb._assign_dice(f, th, dice)
	# effetti «dopo che l'avversario ha assegnato i danni»
	for eff in r["after"][o]:
		_after_assign(o, eff)
	for id in c["pending"]:
		if st.units.has(id):
			st.units[id]["dmg"] = int(st.units[id]["dmg"]) + int(c["pending"][id])
	if not c["pending"].is_empty():
		var parts2 := []
		for id3 in c["pending"]:
			if st.units.has(id3):
				parts2.append("%s %d" % [st.unit_name(id3), int(c["pending"][id3])])
		say("Danni: %s." % ", ".join(parts2))
		e.emit_fx("damage", {"hits": c["pending"].duplicate()})
	c["pending"] = {}
	e._sync()


func _heal_options(f: String, th: String, dice: Array) -> Array:
	var out := []
	if r["no_remove"][f]:
		return out
	var s: String = c["sys"]
	var done_colors := {}
	for i in dice.size():
		var d: Dictionary = dice[i]
		if d.get("spent", false) or int(d["v"]) != 3:
			continue
		if done_colors.has(d["c"]):
			continue
		done_colors[d["c"]] = true
		var ids := st.units_at(s, f, th)
		ids.sort_custom(func(a, b): return RB.health(st.units[a]["t"]) > RB.health(st.units[b]["t"]))
		for id in ids:
			var t: String = st.units[id]["t"]
			if int(st.units[id]["dmg"]) <= 0 or RB.health_color(t) != d["c"] or id in r["no_remove_ids"]:
				continue
			out.append({"v": "heal:%d:%d" % [i, id], "l": "Speciale %s: togli 1 danno a %s" % [d["c"], st.unit_name(id)], "unit": id})
	return out


func _after_assign(f: String, eff: String) -> void:
	var p: Dictionary = c["pending"]
	match eff:
		"ships2", "ships2_nonebulon":
			var left := 2
			for id in p.keys():
				if left <= 0:
					break
				var t: String = st.units[id]["t"] if st.units.has(id) else ""
				if t == "" or not RB.is_ship(t) or st.units[id]["f"] != f:
					continue
				if eff == "ships2_nonebulon" and t == "Nebulon-B Frigate":
					continue
				var k: int = min(left, int(p[id]))
				p[id] = int(p[id]) - k
				left -= k
				if int(p[id]) <= 0:
					p.erase(id)
			if left < 2:
				say("%s toglie %d danni alle sue navi." % [RBState.fshort(f), 2 - left])
		"bunker", "generator":
			var st_type := "Shield Bunker" if eff == "bunker" else "Shield Generator"
			var structs := []
			for id2 in st.units_at(c["sys"], f, "terra"):
				if st.units[id2]["t"] == st_type:
					structs.append(id2)
			if structs.is_empty():
				return
			var target: int = structs[0]
			var moved := 0
			for id3 in p.keys():
				if moved >= 3:
					break
				if id3 == target or not st.units.has(id3) or st.units[id3]["f"] != f or not RB.is_ground(st.units[id3]["t"]):
					continue
				var k2: int = min(3 - moved, int(p[id3]))
				p[id3] = int(p[id3]) - k2
				moved += k2
				if int(p[id3]) <= 0:
					p.erase(id3)
			if moved > 0:
				p[target] = int(p.get(target, 0)) + moved
				say("%s devia %d danni su %s." % [RBState.fshort(f), moved, RB.unit_it(st_type)])


# ================================================================== valutazioni per l'IA

func _best_card(f: String, opts: Array) -> String:
	var best: String = opts[0]
	var bv := -99.0
	for x in opts:
		var v: float = card_value(f, x) + e.ais[f].rng.randf_range(0.0, 0.3)
		if v > bv:
			bv = v
			best = x
	return best


func card_value(f: String, card: String) -> float:
	var v := 0.0
	for sd in ["top", "bottom"]:
		if c.is_empty() or usable(f, card, sd):
			v = maxf(v, side_value(f, card, sd))
	return v


## Valore approssimativo di un'abilità (danni attesi, colpi prevenuti, carte annullate…).
func side_value(f: String, card: String, side: String) -> float:
	var top := side == "top"
	match RB.base_id(card):
		"av_i_air_superiority", "av_i_entrapment", "av_r_outrun_them":
			return 2.2 if top else 1.0
		"av_i_armored_patrol", "av_r_take_cover":
			return 3.0 if top else 1.6
		"av_i_bombardment", "av_r_bombing_run", "av_r_rogue_squadron_support", "av_r_take_it_down", "av_i_overrun":
			return 2.0 if top else 1.0
		"av_i_superlaser_blast", "av_r_tow_cables":
			return 4.0 if top else 1.0
		"av_i_support_of_the_501st", "av_r_hold_them_back", "av_i_target_the_generator", "av_i_intercept":
			return 2.4 if top else 1.0
		"av_i_swarm_tactics":
			if top and not c.is_empty() and _fighters(c["sys"], "I") > _fighters(c["sys"], "R"):
				return 2.0
			return 0.9
		"av_i_overwhelming_presence":
			return 2.6 if top else 1.8
		"av_r_escort":
			return 2.6 if top else 1.8
		"av_r_fleet_logistics", "av_i_reinforcements":
			return 2.8 if top else 1.8
		"av_i_energy_shield", "av_r_draw_their_fire", "av_i_armored_position", "av_r_planetary_shield":
			return 1.8 if top else 0.4
		"av_r_ion_blast":
			return 1.4 if top else 1.0
		"av_i_tractor_beam":
			return 1.5 if top else 1.0
		"av_i_imposing_presence", "av_r_confrontation":
			return 0.8 if top else 1.5
		"av_r_deployment":
			return 1.3 if top else 0.6
		"av_r_escape_plan":
			return 0.7 if top else 1.0
		"av_r_rogue_one":
			return 0.6 if top else 0.6
	return 0.5
