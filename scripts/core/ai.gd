class_name RBAI
extends RefCounted
## Giocatore artificiale. Prende ogni decisione del motore con regole di buon senso:
## l'Impero cerca la base ribelle (senza guardarla: usa solo sonde e informazioni pubbliche),
## schiaccia le forze ribelli e sottomette i sistemi; l'Alleanza nasconde la base, espande la
## fedeltà, colpisce dove l'Impero è debole e gioca gli obiettivi.
## level: 0 facile (scelte più casuali), 1 normale, 2 esperto.

var level := 1
var rng := RandomNumberGenerator.new()
var e: RBEngine
var st: RBState


func decide(engine: RBEngine, f: String, req: Dictionary):
	e = engine
	st = engine.st
	var k: String = req.get("k", "choice")
	# alcune richieste portano già la scelta consigliata (calcolata da chi chiede, es. combattimento cinematografico)
	if req.has("ai_best"):
		return req["ai_best"]
	match k:
		"choice":
			return _choice(f, req)
		"system":
			return _system(f, req)
		"leaders":
			return _leaders(f, req)
		"cards":
			return _cards(f, req)
		"systems":
			return _systems(f, req)
		"units":
			return _units(f, req)
		"move":
			return _move(f, req)
		"place":
			return auto_place(engine, f, req["units"], req["opts"], req.get("need_ground", []))
		"damage":
			return _damage(f, req)
		"dice_pick":
			return _dice_pick(f, req)
		"order":
			return _order(f, req)
		"queue_pick":
			return _queue_pick(f, req)
	return null


func _noise(x: float) -> float:
	var amp := 0.5 if level == 0 else (0.15 if level == 1 else 0.05)
	return x * (1.0 + rng.randf_range(-amp, amp)) + rng.randf_range(0.0, amp)


# ================================================================== valutazioni

## Valore militare (danni attesi per attacco) di un insieme di unità.
static func unit_power(t: String) -> float:
	var u: Dictionary = RB.UNITS[t]
	return 0.5 * (int(u["rossi"]) + int(u["neri"])) + 0.33 * int(u["verdi"])


func power(ids: Array) -> float:
	var p := 0.0
	for id in ids:
		if st.units.has(id):
			p += unit_power(st.units[id]["t"]) + 0.35 * RB.health(st.units[id]["t"])
	return p


func power_at(s: String, f: String, th := "") -> float:
	return power(st.units_at(s, f, th))


## Sistemi dove la base ribelle potrebbe ancora essere, dal punto di vista dell'Impero.
func possible_bases() -> Array:
	if st.base_revealed:
		return [st.base]
	if st.flags.has("base_known"):
		return [st.flags["base_known"]]
	var out := []
	for s in st.all_systems():
		if s == "CORUSCANT" or st.sys[s]["dest"]:
			continue
		if s in st.known["I_not_base"] or s in st.probes:
			continue
		if st.flags.has("base_region") and RB.region_of(s) != int(st.flags["base_region"]):
			continue
		if st.flags.has("three_systems") and not s in st.flags["three_systems"]:
			continue
		out.append(s)
	if out.is_empty():
		for s in st.all_systems():
			if not s in st.probes and s != "CORUSCANT" and not st.sys[s]["dest"]:
				out.append(s)
	return out


## Pericolo per la base ribelle (dal punto di vista ribelle: conosce la base).
func base_threat() -> float:
	if st.base == "":
		return 0.0
	var thr := power_at(st.base, "I")
	for a in RB.SYS[st.base]["adiacenti"]:
		thr += 0.8 * power_at(a, "I")
	return thr


# ================================================================== scelte generiche

func _opt_values(req: Dictionary) -> Array:
	var out := []
	for o in req["opts"]:
		out.append(o["v"])
	return out


func _choice(f: String, req: Dictionary):
	var ctx: String = req.get("ctx", "")
	var opts: Array = req["opts"]
	var vals := _opt_values(req)
	match ctx:
		"assign":
			return _assign_choice(f, opts)
		"command":
			return _command_choice(f, opts)
		"recruit":
			return _recruit_choice(f, opts)
		"build_type":
			return _build_type(f, vals)
		"oppose":
			return _oppose(f, req)
		"combat_leader":
			return _best_combat_leader(f, vals)
		"start_combat_action":
			for v in vals:
				if v != "":
					return v
			return ""
		"combat_action":
			return _combat_action(f, req)
		"block":
			for v in vals:
				if v != "":
					return v
			return ""
		"retreat":
			return _retreat_choice(f, req)
		"refresh_objective", "combat_objective":
			for v in vals:
				if v != "":
					return v
			return ""
		"mission_leader":
			return vals[0]
		"rapid_mob":
			return _rapid_mob(f, vals)
		"discredit":
			return "roll" if _count_sab() >= 2 else "remove"
		"false_orders":
			for v in vals:
				if v is int and v >= 0:
					return v
			return -1
		"mon_cal":
			return "ship" if st.has_loyalty("R", "MON CALAMARI") else "loy"
		"rnd":
			return "sab" if "sab" in vals else "draw2"
		"mdtyr":
			var s: String = e.combat.c.get("sys", "")
			if s != "" and st.has_units(s, "R", "spazio") and st.has_units(s, "I", "spazio"):
				return "spazio"
			return "terra"
		"brilliant":
			var s2: String = e.combat.c.get("sys", "")
			if s2 != "" and st.has_units(s2, "R", "terra") and st.has_units(s2, "I", "terra"):
				return "st"
			return "ss"
		"tactic_deck":
			return "spazio"
		"sabotage_choice":
			return "sab" if "sab" in vals else vals[0]
		"radar_where":
			return "bottom"
		"heist":
			return "obj" if "obj" in vals else vals[0]
		"early_choice":
			return "rec" if "rec" in vals and f == "I" else "card"
		"old_friend":
			return vals[0]
	# sì/no
	if vals.size() == 2 and vals[0] is bool:
		return _yes_no(f, ctx, req)
	# di base: la prima opzione utile (non "nessuna")
	for v in vals:
		if v != "" and v != "none" and v != "done":
			return v
	return vals[0]


func _yes_no(f: String, ctx: String, req: Dictionary) -> bool:
	match ctx:
		"use_subversion":
			return true
		"use_wookiee_guardian", "use_c3po", "use_yoda", "use_one_in_a_million", "use_falcon", "use_destiny", "use_post_bounty", "use_noble_sacrifice", "use_son_of_skywalker", "use_dsp", "use_track_them", "use_something", "use_ambitions", "use_facility", "use_sweep", "aggressive_destroy", "seize_remove":
			return true
		"use_radar":
			return base_threat() > 3.0
		"rebel_cell":
			return st.objs.size() >= 3
		"use_undercover":
			return true
	return true


func _count_sab() -> int:
	var n := 0
	for s in st.sys:
		if st.sys[s]["sab"]:
			n += 1
	return n


# ================================================================== assegnazione delle missioni

## Valore di una missione per l'IA (0 = inutile adesso).
func mission_value(f: String, c: String) -> float:
	var b := RB.base_id(c)
	var tg := e.cards.targets(f, c, [])
	if tg.is_empty() and b != "contingency_plan" and b != "rapid_mobilization":
		return 0.0
	var v := 1.0
	match b:
		"rule_by_fear", "trade_negotiations", "build_alliance", "display_of_power", "message_from_high_command", "regional_aid":
			v = 2.5
		"capture_rebel_operative", "collect_bounty":
			v = 3.0
		"gather_intel", "probe_droid_initiative", "intercept_transmission", "long_range_probe", "interrogation_droid", "break_their_will", "stolen_intel":
			v = 3.0 if not st.base_revealed else 0.3
		"lure_of_the_dark_side", "carbon_freezing", "make_an_example":
			v = 3.5
		"retrieve_the_plans", "exploit_weakness", "interrogation":
			v = 2.0
		"superlaser_online":
			v = 0.7
			var pb := possible_bases()
			for x in tg:
				if pb.size() <= 3 and x["sys"] in pb:
					v = 9.0
				elif st.has_loyalty("R", x["sys"]) or st.has_units(x["sys"], "R"):
					v = max(v, 1.8)
		"construct_death_star", "construct_super_star_destroyer", "construct_super_star_destroyer_rote", "interdictor_development":
			v = 2.5
		"research_and_development", "secret_weapons_research":
			v = 2.0 if st.deck["proj"].size() > 0 else 0.0
		"construct_factory", "address_delays", "deployment":
			v = 2.0
		"double_our_efforts", "oversee_project", "imperial_might":
			var q := 0
			for sp in 3:
				q += st.queue["I"][sp].size()
			v = 2.0 if q > 0 else 0.0
		"hunt_them_down", "planetary_conquest":
			v = 2.2
		"imperial_propaganda", "fear_will_keep_them_in_line":
			v = 2.5
		"detained", "homing_beacon", "draw_them_out", "secure_the_plans", "single_reactor_ignition", "were_the_bait", "discredit_rebellion", "hire_mercenaries", "promotion":
			v = 2.0
		# Ribelli
		"sabotage", "sabotage_rote":
			v = 2.5
		"daring_rescue", "for_the_greater_good", "critical_rescue", "aggressive_negotiations":
			v = 4.0
		"hit_and_run", "wookiee_uprising", "plant_explosives", "assault":
			v = 2.2
		"infiltration", "stolen_plans", "covert_operation":
			v = 2.5
		"rapid_mobilization":
			v = 1.0 + base_threat() * 0.6
		"hidden_fleet", "lead_the_strike_team", "plan_the_assault", "behind_enemy_lines":
			v = 1.2
		"incite_rebellion", "public_uprising":
			v = 2.2
		"establish_trade_relations", "support_of_mon_calamari":
			v = 3.0
		"base_defenses":
			v = 1.5 if base_threat() > 2.0 else 0.8
		"seek_yoda":
			v = 3.0
		"rogue_squadron_raid", "demolition":
			v = 1.5
		"plant_false_lead":
			v = 1.5 if st.probes.size() >= 3 else 0.4
		"misdirection":
			v = 0.6
		"reconnaissance", "secret_mission", "safe_haven", "my_only_hope", "heist", "prepare_for_battle":
			v = 1.8
		"contingency_plan":
			v = 1.0
		"subversion":
			v = 1.5
	return v


func _assign_choice(f: String, opts: Array):
	var pool := st.leader_pool(f)
	var total := st.leader_count(f)
	var reserve := 1 if total >= 4 else 0
	if level >= 1:
		reserve = 2 if total >= 6 else (1 if total >= 3 else 0)
		# l'Impero deve dare la caccia alla base: tiene più leader per attivare sistemi
		if f == "I" and not st.base_revealed:
			reserve = max(reserve, 3 if total >= 5 else (2 if total >= 3 else 1))
	# tieni nella riserva i leader con i valori tattici migliori
	var tactical := 0
	for n in pool:
		if RB.has_tactics(n):
			tactical += 1
	var best = "done"
	var best_v := 0.8
	for o in opts:
		var v0: String = o["v"]
		if v0 == "done":
			continue
		if v0.begins_with("a:"):
			var vv := _noise(action_value(f, v0.substr(2)))
			if vv > best_v:
				best_v = vv
				best = v0
			continue
		var c := v0.substr(2)
		var mv := mission_value(f, c)
		if mv <= 0.0:
			continue
		var ls := best_leaders_for(f, c, pool)
		if ls.is_empty():
			continue
		mv = _noise(mv)
		if mv > best_v:
			best_v = mv
			best = v0
	if best != "done" and (pool.size() <= reserve or tactical <= reserve):
		return "done"
	return best


func action_value(f: String, c: String) -> float:
	match RB.base_id(c):
		"start_the_evacuation":
			return 3.0 if base_threat() > 4.0 else 0.0
		"rebel_planning", "temporary_alliance", "brilliant_administrator", "independent_operation":
			return 2.0
		"our_most_desperate_hour", "trust_in_the_force", "an_old_friend":
			return 2.6
		"proceeding_as_planned":
			return 2.0
		"local_rumors":
			return 2.5 if not st.base_revealed else 0.0
		"ambush":
			for s in st.all_systems():
				var h := 0
				for id in st.units_at(s, "I", "terra"):
					h += RB.health(st.units[id]["t"])
				if h > 0 and h <= 3:
					return 2.2
			return 0.0
		"public_support":
			return 1.4
		"catch_them_by_surprise", "scouting_mission", "boba_fett_where":
			return 1.0
	return 1.0


## Leader della riserva che soddisfano la missione col minimo spreco.
func best_leaders_for(f: String, c: String, pool: Array) -> Array:
	var sk := e.cards.mission_skill(c)
	var info := RB.card(c)
	var lvl := int(info.get("livello", 1)) if info.get("livello") != null else 0
	if sk == "" or sk == "<null>":
		return [pool[0]] if not pool.is_empty() else []
	var portrait = info.get("ritratto")
	var cand := pool.duplicate()
	cand.sort_custom(func(a, b): return _leader_fit(a, sk, portrait) > _leader_fit(b, sk, portrait))
	var out := []
	var tot := 0
	for n in cand:
		var s := st.leader_skill(n, sk)
		if s <= 0:
			continue
		out.append(n)
		tot += s
		if tot >= lvl:
			break
		if out.size() >= 2:
			break
	if tot < lvl:
		return []
	return out


func _leader_fit(n: String, sk: String, portrait) -> float:
	var v := float(st.leader_skill(n, sk))
	if portrait != null and e.cards._portrait_match(str(portrait), n):
		v += 3.0
	# chi ha buoni valori tattici è prezioso per attivare e combattere
	v -= 0.25 * (int(RB.LEADERS[n]["spazio"]) + int(RB.LEADERS[n]["terra"]))
	return v


func _leaders(f: String, req: Dictionary) -> Array:
	var ctx: String = req.get("ctx", "")
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 1))
	var mx := int(req.get("max", 1))
	match ctx:
		"assign_leaders":
			var ls := best_leaders_for(f, req.get("card", ""), opts)
			if ls.is_empty():
				return [opts[0]]
			return ls
		"activate_leader":
			return [_activation_leader(f, opts)]
		"eliminate_leader":
			var worst = opts[0]
			var wv := 99.0
			for n in opts:
				var v := _leader_worth(n)
				if v < wv:
					wv = v
					worst = n
			return [worst]
		"rescue_return":
			return opts.duplicate()
		"retreat_leader":
			return [opts[0]]
		"destiny_who", "bounty_who", "sweep_who", "draw_out_who", "rotj_who":
			var best = opts[0]
			var bv := -1.0
			for n in opts:
				var v2 := _leader_worth(n)
				if v2 > bv:
					bv = v2
					best = n
			return [best]
	var out := []
	for i in max(mn, min(mx, 1)):
		if i < opts.size():
			out.append(opts[i])
	return out


func _leader_worth(n: String) -> float:
	var L: Dictionary = RB.LEADERS[n]
	var v := float(int(L["spazio"]) + int(L["terra"]))
	for k in RB.SKILLS:
		v += float(L["abilita"][k]) + 0.5 * float(L["minori"][k])
	return v


func _activation_leader(f: String, opts: Array) -> String:
	var plan: Dictionary = st.flags.get("ai_plan_" + f, {})
	if plan.has("leader") and plan["leader"] in opts:
		return plan["leader"]
	var best = opts[0]
	var bv := -1.0
	for n in opts:
		var v := float(int(RB.LEADERS[n]["spazio"]) + int(RB.LEADERS[n]["terra"])) - 0.3 * float(RB.leader_skill(n, "diplomazia") + RB.leader_skill(n, "intel") + RB.leader_skill(n, "opspec") + RB.leader_skill(n, "logistica"))
		if v > bv:
			bv = v
			best = n
	return best


func _recruit_choice(f: String, opts: Array):
	var best = opts[0]["v"]
	var bv := -1.0
	for o in opts:
		var n: String = o.get("leader", "")
		var v := 0.5 if n == "" else _leader_worth(n)
		v = _noise(v)
		if v > bv:
			bv = v
			best = o["v"]
	return best


func _build_type(f: String, vals: Array):
	# un po' di varietà, con preferenza per le unità più forti
	var best = vals[0]
	var bv := -1.0
	for t in vals:
		var v := unit_power(t) + 0.4 * RB.health(t) + float(RB.UNITS[t]["trasporto"]) * 0.3
		if t == "Rebel Transport" and st.count_type("BASE", "Rebel Transport", "R") > 0:
			v -= 1.0
		v = _noise(v)
		if v > bv:
			bv = v
			best = t
	return best


func _oppose(f: String, req: Dictionary):
	var vals := _opt_values(req)
	var c: String = req.get("card", "")
	var sk := e.cards.mission_skill(c)
	var best = ""
	var bv := 0.0
	for v in vals:
		if v == "":
			continue
		var sc := float(st.leader_skill(v, sk)) if sk != "" and sk != "<null>" else 1.0
		# non sprecare leader con buoni valori tattici se non serve
		sc -= 0.15 * (int(RB.LEADERS[v]["spazio"]) + int(RB.LEADERS[v]["terra"]))
		if sc > bv:
			bv = sc
			best = v
	# contrastare vale la pena per le missioni importanti
	var imp := mission_value(RBState.other(f), c)
	if bv <= 0.5 and imp < 2.5:
		return ""
	if best == "" and imp >= 3.0 and level >= 1:
		# anche senza icone il leader obbliga a tirare i dadi
		for v in vals:
			if v != "":
				return v
	return best


func _best_combat_leader(f: String, vals: Array):
	var s: String = e.combat.c.get("sys", "")
	var best = ""
	var bv := 0.0
	for v in vals:
		if v == "":
			continue
		var L: Dictionary = RB.LEADERS[v]
		var sc := 0.0
		if s != "" and st.has_units(s, "R", "spazio") and st.has_units(s, "I", "spazio"):
			sc += int(L["spazio"])
		if s != "" and st.has_units(s, "R", "terra") and st.has_units(s, "I", "terra"):
			sc += int(L["terra"])
		if sc > bv:
			bv = sc
			best = v
	# un leader serve anche per ritirarsi
	if best == "" and not vals.is_empty() and vals.size() > 1:
		best = vals[1]
	return best


# ================================================================== fase di comando

func _command_choice(f: String, opts: Array):
	var vals := _opt_values({"opts": opts})
	# rivelare la base conviene solo in casi particolari
	var missions := []
	for o in opts:
		if str(o["v"]).begins_with("mission:"):
			missions.append(o["v"])
	# prima le missioni importanti
	var best_m = null
	var best_mv := 0.0
	for m in missions:
		var idx := int(str(m).substr(8))
		var c: String = st.assign[f][idx]["card"]
		var mv := mission_value(f, c)
		if mv > best_mv:
			best_mv = mv
			best_m = m
	var act := _plan_activation(f) if "activate" in vals else {}
	var act_v: float = act.get("score", 0.0)
	if best_m != null and best_mv >= act_v:
		return best_m
	if act_v > 1.0:
		st.flags["ai_plan_" + f] = act
		return "activate"
	if best_m != null:
		return best_m
	return "pass"


## Cerca il sistema migliore da attivare: restituisce {target, leader, score}.
func _plan_activation(f: String) -> Dictionary:
	var o := RBState.other(f)
	var leaders := []
	for n in st.leader_pool(f):
		if RB.has_tactics(n):
			leaders.append(n)
	if leaders.is_empty():
		return {}
	var best := {}
	var best_score := 0.0
	var possible := possible_bases() if f == "I" else []
	for t in st.all_systems():
		var srcs := e.move_sources(f, t)
		if srcs.is_empty():
			continue
		var my_power := 0.0
		var my_ground := 0.0
		var my_ships := 0.0
		for s in srcs:
			var ids := _movable(f, s)
			for id in ids:
				var p := unit_power(st.units[id]["t"]) + 0.35 * RB.health(st.units[id]["t"])
				my_power += p
				if RB.is_ground(st.units[id]["t"]):
					my_ground += p
				else:
					my_ships += p
		if my_power <= 0.0:
			continue
		var here_mine := power_at(t, f)
		var enemy := power_at(t, o)
		var total := my_power + here_mine
		var score := 0.0
		var known_base: bool = f == "I" and possible.size() == 1 and t == possible[0]
		if f == "I" and st.base_revealed and t == st.base:
			known_base = true
		if enemy > 0.0:
			var ratio: float = total / maxf(enemy, 0.5)
			if ratio < (1.0 if known_base else 1.3):
				# la base nota ma ancora troppo difesa: avvicinare le forze senza attaccare
				continue
			score = 2.0 + min(enemy, 6.0) * 0.6
			if known_base:
				score += 12.0
		else:
			# spostamenti senza combattimento
			if f == "I":
				# truppe trasportabili davvero (le unità terrestri viaggiano solo sulle navi)
				var landable := _landable_ground(f, srcs)
				var near := 0
				for x in RB.SYS[t]["adiacenti"]:
					if x in possible:
						near += 1
				if t in possible and landable > 0 and not st.base_revealed:
					score = 4.2 + 4.0 / max(1.0, float(possible.size()))
				elif st.is_populous(t) and not st.is_imperial_sys(t) and landable > 0:
					score = 1.8 + (0.6 if st.is_rebel_sys(t) else 0.0) + 0.25 * near
				elif not st.base_revealed and near > 0 and my_ships > 0.0 and not t in possible:
					# avvicinarsi ai sistemi dove la base potrebbe essere
					score = 1.1 + 0.35 * near
				# pochi sistemi possibili (o base rivelata): avvicinare il grosso della flotta
				if possible.size() <= 3 or st.base_revealed:
					var goals: Array = [st.base] if st.base_revealed else possible
					var dmin := 99
					for b in goals:
						dmin = min(dmin, RB.dist(t, b))
					var src_d := 99
					for x in srcs:
						if x == "BASE":
							continue
						for b in goals:
							src_d = min(src_d, RB.dist(x, b))
					if dmin < src_d:
						var hunt := 2.6 + 2.0 / float(max(1, dmin)) + 0.15 * minf(my_power, 12.0)
						if dmin == 0 and landable == 0:
							hunt -= 2.0
						score = maxf(score, hunt)
			else:
				if st.is_populous(t) and st.is_subjugated(t) == false and not st.has_units(t, "R") and st.is_rebel_sys(t):
					score = 0.6
				if st.base != "" and (t == st.base or t == "BASE") and base_threat() > 4.0:
					score = 2.5
		score = _noise(score)
		if score > best_score:
			best_score = score
			best = {"target": t, "score": score}
	if best.is_empty():
		return {}
	# il leader con i valori tattici più alti per il teatro principale
	var bl = leaders[0]
	var blv := -1.0
	for n in leaders:
		var v := float(int(RB.LEADERS[n]["spazio"]) + int(RB.LEADERS[n]["terra"])) - 0.2 * _skill_sum(n)
		if v > blv:
			blv = v
			bl = n
	best["leader"] = bl
	return best


## Unità terrestri imperiali che le navi delle sorgenti possono portare in un sistema.
func _landable_ground(f: String, srcs: Array) -> int:
	var n := 0
	for s in srcs:
		var ships := []
		var ground := 0
		for id in _movable(f, s):
			var t: String = st.units[id]["t"]
			if RB.is_ground(t):
				ground += 1
			elif RB.is_ship(t) and not st.needs_transport(id):
				ships.append(id)
		n += min(ground, st.transport_capacity(ships))
	return n


func _skill_sum(n: String) -> float:
	var v := 0.0
	for k in RB.SKILLS:
		v += float(RB.leader_skill(n, k))
	return v


func _movable(f: String, s: String) -> Array:
	var out := []
	for id in st.units_at(s, f):
		if not RB.UNITS[st.units[id]["t"]]["immobile"]:
			out.append(id)
	return out


# ================================================================== sistemi

func _system(f: String, req: Dictionary) -> String:
	var ctx: String = req.get("ctx", "")
	var opts: Array = req["opts"]
	var allow_none: bool = req.get("none", false)
	match ctx:
		"activate_target":
			var plan: Dictionary = st.flags.get("ai_plan_" + f, {})
			st.flags.erase("ai_plan_" + f)
			if plan.has("target") and plan["target"] in opts:
				return plan["target"]
			return opts[rng.randi_range(0, opts.size() - 1)]
		"base":
			return _choose_base_system(opts)
		"new_base":
			var best := ""
			var bd := -1.0
			for s in opts:
				var d := 0.0
				for x in st.systems_with_units("I"):
					d += min(RB.dist(s, x), 4)
				if d > bd:
					bd = d
					best = s
			return best
		"deploy":
			return _deploy_target(f, req)
		"mission_sys":
			return _mission_system(f, req.get("card", ""), opts)
		"setup_dsuc":
			return opts[rng.randi_range(0, opts.size() - 1)]
		"evacuation":
			var best_e = opts[0]
			var bev := -99.0
			for s in opts:
				var v := (2.0 if st.is_rebel_sys(s) else 0.0)
				for x in st.systems_with_units("I"):
					v += 0.3 * min(RB.dist(s, x), 4)
				if v > bev:
					bev = v
					best_e = s
			return best_e
		"loyalty", "temp_alliance", "administrator", "public_support", "trust_force", "indep_op", "marker_place", "promotion_place", "homing_place":
			return _best_loyalty_target(f, opts, ctx)
		"region_probe":
			var poss := possible_bases()
			var best_s = opts[0]
			var best_n := 99
			for s in opts:
				var reg := RB.region_of(s)
				var n := 0
				for x in poss:
					if RB.region_of(x) == reg:
						n += 1
				var bal: int = abs(n * 2 - poss.size())
				if n > 0 and bal < best_n:
					best_n = bal
					best_s = s
			return best_s
		"local_rumors", "ambush", "surprise", "scouting", "boba_where", "conquest_src", "rapid_src", "indep_dest":
			return _generic_target(f, opts, ctx)
	if allow_none and opts.is_empty():
		return ""
	return opts[rng.randi_range(0, opts.size() - 1)] if level == 0 else _generic_target(f, opts, ctx)


func _choose_base_system(opts: Array) -> String:
	## Un sistema lontano dall'Impero, possibilmente remoto e con pochi vicini.
	var best = opts[0]
	var bv := -99.0
	for s in opts:
		var d := 0.0
		for x in st.systems_with_units("I"):
			d += min(RB.dist(s, x), 5)
		var v := d * 0.3
		if st.is_remote(s):
			v += 1.0
		if st.is_rebel_sys(s):
			v += 0.8
		v -= 0.2 * RB.SYS[s]["adiacenti"].size()
		v = _noise(v)
		if v > bv:
			bv = v
			best = s
	return best


func _deploy_target(f: String, req: Dictionary) -> String:
	var opts: Array = req["opts"]
	var t: String = req.get("unit", "")
	if opts.is_empty():
		return ""
	var best = opts[0]
	var bv := -99.0
	for s in opts:
		var v := 0.0
		if f == "R":
			if s == "BASE":
				v = 1.5 + base_threat() * 0.2
			else:
				v = 0.5 + (1.0 if st.has_units(s, "R") else 0.0)
				var near_imp := 0.0
				for a in RB.SYS[s]["adiacenti"]:
					near_imp += power_at(a, "I")
				v -= near_imp * 0.1
		else:
			var poss := possible_bases()
			var close := 99
			for p in poss:
				close = min(close, RB.dist(s, p))
			v = 2.0 - 0.4 * close
			if st.has_units(s, "I"):
				v += 0.5
			for a in RB.SYS[s]["adiacenti"]:
				if st.has_units(a, "R"):
					v += 0.4
		v = _noise(v)
		if v > bv:
			bv = v
			best = s
	return best


func _mission_system(f: String, c: String, opts: Array) -> String:
	var b := RB.base_id(c)
	var best = opts[0]
	var bv := -99.0
	var poss := possible_bases() if f == "I" else []
	for s in opts:
		var v := 0.0
		match b:
			"rule_by_fear", "trade_negotiations", "display_of_power", "message_from_high_command":
				v = (2.0 if st.has_loyalty("R", s) else 1.0) + (1.0 if st.is_subjugated(s) else 0.0) + 0.3 * RB.SYS[s]["icone"].size()
			"build_alliance", "establish_trade_relations", "regional_aid":
				v = (2.0 if st.has_loyalty("I", s) else 1.0) + 0.4 * RB.SYS[s]["icone"].size() - (1.0 if st.is_subjugated(s) else 0.0)
			"sabotage", "sabotage_rote":
				v = 0.5 * RB.SYS[s]["icone"].size() + (1.0 if st.is_imperial_sys(s) else -1.0) + (-5.0 if st.sys[s]["sab"] else 0.0)
			"hit_and_run", "hunt_them_down", "plant_explosives":
				v = power_at(s, RBState.other(f))
			"long_range_probe":
				v = 1.0 if s in poss else -1.0
			"gather_intel", "intercept_transmission", "stolen_intel":
				v = 1.0
			"superlaser_online":
				v = (5.0 if s in poss else 0.0) + (2.0 if st.has_loyalty("R", s) else 0.0)
			_:
				v = rng.randf()
		# meno opposizione = meglio
		v -= 0.3 * st.leaders_at(s, RBState.other(f)).size()
		v = _noise(v)
		if v > bv:
			bv = v
			best = s
	return best


func _best_loyalty_target(f: String, opts: Array, ctx: String) -> String:
	var best = opts[0]
	var bv := -99.0
	for s in opts:
		var v := 0.0
		if RB.SYS.has(s):
			v = 0.3 * RB.SYS[s]["icone"].size()
			if st.has_loyalty(RBState.other(f), s):
				v += 1.0
			if f == "R" and ctx == "homing_place" and s != st.base:
				v += 0.5
		v = _noise(v)
		if v > bv:
			bv = v
			best = s
	return best


func _generic_target(f: String, opts: Array, ctx: String) -> String:
	var o := RBState.other(f)
	var best = opts[0]
	var bv := -99.0
	for s in opts:
		var v := power_at(s, o) - 0.5 * power_at(s, f)
		if ctx == "local_rumors":
			var poss := possible_bases()
			v = 0.0
			for p in poss:
				if RB.region_of(p) == RB.region_of(s):
					v += 1.0
			v = -abs(v - poss.size() / 2.0)
		elif ctx == "conquest_src" or ctx == "rapid_src" or ctx == "indep_dest":
			v = power_at(s, f)
		v = _noise(v)
		if v > bv:
			bv = v
			best = s
	return best


func _systems(f: String, req: Dictionary) -> Array:
	var opts: Array = req["opts"].duplicate()
	var mx := int(req.get("max", 1))
	var ctx: String = req.get("ctx", "")
	if ctx == "three_systems":
		# nomina sistemi plausibili, vicini alla base, per confondere
		opts.sort_custom(func(a, b): return RB.dist(a, st.base) < RB.dist(b, st.base))
		return opts.slice(0, mx)
	if ctx == "fear_systems":
		opts.sort_custom(func(a, b): return int(st.has_loyalty("R", a)) > int(st.has_loyalty("R", b)))
		return opts.slice(0, mx)
	opts.shuffle()
	return opts.slice(0, mx)


# ================================================================== carte

func _cards(f: String, req: Dictionary) -> Array:
	var ctx: String = req.get("ctx", "")
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 1))
	var mx := int(req.get("max", 1))
	var scored := []
	for c in opts:
		var v := 0.0
		match ctx:
			"discard_missions":
				v = -mission_value(f, c)
			"keep_project", "pick_mission", "pick_project", "secret_mission_keep", "recon_pick", "contingency_pick":
				v = mission_value(f, c) if RB.card(c).get("tipo", "") == "missione" else 1.0
			"bottom_objective":
				v = float(RB.card(c).get("reputazione", 1))
			"infiltration", "covert_keep", "pick_discard_obj":
				v = float(RB.card(c).get("reputazione", 1)) + (2.0 if e.cards.objective_ok(c) else 0.0)
			"long_war_discard", "rebel_cell_discard":
				v = -float(RB.card(c).get("reputazione", 1)) - (2.0 if e.cards.objective_ok(c) else 0.0)
			"stolen_intel":
				v = mission_value("R", c)
			"probe_under":
				v = 1.0 if st.has_units(c, "R") else 0.0
			"radar_keep":
				v = 1.0
			_:
				v = rng.randf()
		scored.append([_noise(v + 0.01), c])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for i in max(mn, 1 if mx >= 1 else 0):
		if i < scored.size() and out.size() < mx:
			out.append(scored[i][1])
	if mn > out.size():
		for x in scored:
			if out.size() >= mn:
				break
			if not x[1] in out:
				out.append(x[1])
	return out


func _order(f: String, req: Dictionary) -> Array:
	var opts: Array = req["opts"].duplicate()
	var ctx: String = req.get("ctx", "")
	if ctx == "false_lead":
		# le carte dei sistemi vicini alla base vanno in fondo: in cima quelle lontane
		opts.sort_custom(func(a, b): return RB.dist(a, st.base) > RB.dist(b, st.base))
		return opts.slice(0, opts.size() / 2)
	if ctx == "order_objectives":
		opts.sort_custom(func(a, b): return _obj_rank(f, a) > _obj_rank(f, b))
		return opts
	return opts


func _obj_rank(f: String, o: String) -> float:
	var v := float(RB.card(o).get("reputazione", 1)) + (2.0 if e.cards.objective_ok(o) else 0.0)
	return v if f == "R" else -v


func _queue_pick(f: String, req: Dictionary) -> Array:
	var opts: Array = req["opts"]
	var mx := int(req.get("max", 1))
	var mh := int(req.get("max_health", 0))
	var idx := []
	for i in opts.size():
		idx.append(i)
	var typ = func(i):
		var x: String = opts[i]
		return x.get_slice("|", 1) if x.contains("|") else x
	idx.sort_custom(func(a, b): return RB.health(typ.call(a)) > RB.health(typ.call(b)))
	var out := []
	var tot := 0
	for i in idx:
		if out.size() >= mx:
			break
		var h := RB.health(typ.call(i))
		if mh > 0 and tot + h > mh:
			continue
		out.append(i)
		tot += h
	return out


# ================================================================== unità

func _units(f: String, req: Dictionary) -> Array:
	var ctx: String = req.get("ctx", "")
	var opts: Array = req["opts"]
	var mn := int(req.get("min", 0))
	var mx := int(req.get("max", opts.size()))
	var mh := int(req.get("max_health", 0))
	var ids := opts.duplicate()
	match ctx:
		"destroy", "destroy_structure", "destroy_ship", "bait":
			# il più possibile e i pezzi più forti
			ids.sort_custom(func(a, b): return unit_power(st.units[a]["t"]) + RB.health(st.units[a]["t"]) > unit_power(st.units[b]["t"]) + RB.health(st.units[b]["t"]))
			return _greedy_health(ids, mx, mh)
		"card_damage":
			var dmg := int(req.get("dmg", 1))
			ids.sort_custom(func(a, b): return _kill_value(a, dmg) > _kill_value(b, dmg))
			return ids.slice(0, mx)
		"block_target":
			var pend: Dictionary = req.get("pending", {})
			ids.sort_custom(func(a, b): return _saved_value(a, pend) > _saved_value(b, pend))
			return [ids[0]]
		"retreat_units":
			ids.sort_custom(func(a, b): return RB.health(st.units[a]["t"]) > RB.health(st.units[b]["t"]))
			return ids.slice(0, mx)
	var out := ids.slice(0, max(mn, min(mx, 1)))
	return out


func _greedy_health(ids: Array, mx: int, mh: int) -> Array:
	var out := []
	var tot := 0
	for id in ids:
		if out.size() >= mx:
			break
		var h := RB.health(st.units[id]["t"])
		if mh > 0 and tot + h > mh:
			continue
		out.append(id)
		tot += h
	return out


func _kill_value(id: int, dmg: int) -> float:
	var t: String = st.units[id]["t"]
	var left := RB.health(t) - int(st.units[id]["dmg"]) - int(e.combat.c.get("pending", {}).get(id, 0))
	var v := unit_power(t)
	if left <= dmg:
		v += 3.0 + RB.health(t)
	return v


func _saved_value(id: int, pend: Dictionary) -> float:
	var t: String = st.units[id]["t"]
	var left := RB.health(t) - int(st.units[id]["dmg"])
	var p := int(pend.get(id, 0))
	if p >= left and p - 1 < left:
		return 10.0 + unit_power(t) + RB.health(t)
	return unit_power(t)


# ================================================================== movimento

func _move(f: String, req: Dictionary) -> Array:
	var target: String = req["target"]
	var cand: Array = req["opts"]
	var ctx: String = req.get("ctx", "")
	var o := RBState.other(f)
	var ignore: bool = req.get("ignore_transport", false)
	var mx := int(req.get("max", 999))
	# per ogni sorgente: navi + quanto possono trasportare
	var by_src := {}
	for id in cand:
		var sl: String = st.units[id]["loc"]
		if not by_src.has(sl):
			by_src[sl] = []
		by_src[sl].append(id)
	var enemy := power_at(target, o) if target != "BASE" else 0.0
	# caccia alla base: basta un distaccamento (una nave che trasporta truppe), il resto della
	# flotta resta libero per altre attivazioni
	if f == "I" and ctx == "activate_move" and enemy <= 0.0 and not st.base_revealed and level >= 1 and target in possible_bases() and possible_bases().size() > 3:
		var det := _detachment(by_src)
		if not det.is_empty():
			return det
	var out := []
	for s in by_src:
		var ids: Array = by_src[s]
		# non sguarnire la base ribelle nascosta se è minacciata
		if f == "R" and (s == "BASE" or s == st.base) and target != "BASE" and target != st.base and base_threat() > 2.5 and ctx == "activate_move":
			continue
		var ships := []
		var need := []
		var other := []
		for id in ids:
			var t: String = st.units[id]["t"]
			if st.needs_transport(id):
				need.append(id)
			elif RB.is_ship(t):
				ships.append(id)
			else:
				other.append(id)
		# lasciare qualcosa a difesa dei sistemi imperiali (una unità terrestre)
		if f == "I" and s != "BASE" and st.is_imperial_sys(s) and enemy <= 0.0:
			var ground := []
			for id in need:
				if RB.is_ground(st.units[id]["t"]):
					ground.append(id)
			if ground.size() <= 1 and not ground.is_empty():
				need.erase(ground[0])
		out.append_array(ships)
		out.append_array(other)
		var cap := 999 if ignore else st.transport_capacity(ships)
		need.sort_custom(func(a, b): return unit_power(st.units[a]["t"]) > unit_power(st.units[b]["t"]))
		for i in min(cap, need.size()):
			out.append(need[i])
	if out.size() > mx:
		out.sort_custom(func(a, b): return unit_power(st.units[a]["t"]) + RB.health(st.units[a]["t"]) > unit_power(st.units[b]["t"]) + RB.health(st.units[b]["t"]))
		out = out.slice(0, mx)
	# se l'attacco è troppo debole, meglio non muovere
	if ctx == "activate_move" and enemy > 0.0 and power(out) + power_at(target, f) < enemy * 1.1 and level >= 1:
		return []
	return out


## La nave con più capacità di trasporto e le unità terrestri che porta (preferendo le più deboli).
func _detachment(by_src: Dictionary) -> Array:
	var best := []
	var best_v := 0.0
	for s in by_src:
		var ships := []
		var ground := []
		for id in by_src[s]:
			var t: String = st.units[id]["t"]
			if RB.is_ground(t):
				ground.append(id)
			elif RB.is_ship(t) and not st.needs_transport(id) and int(RB.UNITS[t]["trasporto"]) > 0:
				ships.append(id)
		if ships.is_empty() or ground.is_empty():
			continue
		ships.sort_custom(func(a, b): return int(RB.UNITS[st.units[a]["t"]]["trasporto"]) > int(RB.UNITS[st.units[b]["t"]]["trasporto"]))
		var ship: int = ships[0]
		var cap := int(RB.UNITS[st.units[ship]["t"]]["trasporto"])
		ground.sort_custom(func(a, b): return RB.health(st.units[a]["t"]) < RB.health(st.units[b]["t"]))
		# lasciare almeno un'unità terrestre nei sistemi imperiali
		if st.is_imperial_sys(s) and ground.size() <= 1:
			continue
		var take := ground.slice(0, min(cap, 2))
		var v := float(take.size()) + 0.1 * cap
		if v > best_v:
			best_v = v
			best = [ship] + take
	return best


# ================================================================== combattimento

func _combat_action(f: String, req: Dictionary):
	var vals := _opt_values(req)
	for v in vals:
		if v == "draw":
			continue
		if v != "done":
			var b := RB.base_id(v)
			if b.ends_with("concentrate_fire"):
				var blanks := 0
				for d in req.get("dice", []):
					if int(d["v"]) == 0 and not d.get("spent", false):
						blanks += 1
				if blanks < 2:
					continue
			if b.ends_with("escape_plan") or b.ends_with("no_escape"):
				continue
			return v
	if "draw" in vals:
		return "draw"
	return "done"


func _damage(f: String, req: Dictionary) -> Dictionary:
	var dice: Array = req["dice"]
	var targets: Array = req["opts"]
	var pend: Dictionary = req.get("pending", {}).duplicate()
	var out := {}
	# prima i colpi semplici (vincolati dal colore), poi i colpi diretti
	var order := []
	for i in dice.size():
		var d: Dictionary = dice[i]
		if d.get("spent", false):
			continue
		if int(d["v"]) == 1:
			order.append(i)
	for i in dice.size():
		var d2: Dictionary = dice[i]
		if not d2.get("spent", false) and int(d2["v"]) == 2:
			order.append(i)
	for i in order:
		var d3: Dictionary = dice[i]
		var best := -1
		var bv := -99.0
		for id in targets:
			if not e.combat._can_take(d3, id):
				continue
			var t: String = st.units[id]["t"]
			var left := e.combat.health_of(id) - int(st.units[id]["dmg"]) - int(pend.get(id, 0))
			if left <= 0:
				continue
			var v := unit_power(t) / float(left) + (2.0 if left == 1 else 0.0)
			if v > bv:
				bv = v
				best = id
		if best < 0:
			for id in targets:
				if e.combat._can_take(d3, id):
					best = id
					break
		if best >= 0:
			out[i] = best
			pend[best] = int(pend.get(best, 0)) + 1
	return out


func _dice_pick(f: String, req: Dictionary) -> Array:
	var dice: Array = req["dice"]
	var out := []
	for i in req["opts"]:
		if int(dice[i]["v"]) == 0 and out.size() < int(req.get("max", 2)):
			out.append(i)
	return out


func _retreat_choice(f: String, req: Dictionary):
	var s: String = req.get("sys", "")
	var vals := _opt_values(req)
	var o := RBState.other(f)
	var mine := power_at(s, f)
	var theirs := power_at(s, o)
	var ratio: float = mine / maxf(theirs, 0.1)
	var limit := 0.55 if level >= 1 else 0.4
	if f == "I" and st.base_revealed and s == st.base:
		limit = 0.25
	if f == "R" and s == st.base and st.base_revealed:
		limit = 0.2
	if ratio < limit or e.combat._transport_alone(f):
		for v in vals:
			if v != "":
				return v
	return ""


func _rapid_mob(f: String, vals: Array):
	if "base" in vals and (base_threat() > 3.0 or st.base_revealed):
		return "base"
	if "move" in vals:
		return "move"
	return vals[0]


# ================================================================== disposizione iniziale

static func auto_place(engine: RBEngine, f: String, units: Dictionary, allowed: Array, need_ground: Array) -> Dictionary:
	var st: RBState = engine.st
	var out := {}
	for s in allowed:
		out[s] = []
	var pool := []
	for t in units:
		for i in int(units[t]):
			pool.append(t)
	if f == "R":
		# quasi tutto alla base nascosta, qualcosa in un sistema ribelle per espandersi
		var sys2 := ""
		for s in allowed:
			if s != "BASE" and st.is_rebel_sys(s):
				sys2 = s
				break
		for t in pool:
			if sys2 != "" and (t == "Rebel Trooper" and out[sys2].size() < 2):
				out[sys2].append(t)
			else:
				out["BASE"].append(t)
		return out
	# Impero: almeno un'unità terrestre in ogni sistema imperiale, poi flotte con truppe
	var ground := []
	var ships := []
	var tie := []
	for t in pool:
		if t == "TIE Fighter" or t == "TIE Striker":
			tie.append(t)
		elif RB.is_ground(t):
			ground.append(t)
		else:
			ships.append(t)
	ground.sort_custom(func(a, b): return RB.health(a) < RB.health(b))
	for s in need_ground:
		if not ground.is_empty():
			out[s].append(ground.pop_front())
	# flotte: ogni nave capitale porta truppe e caccia nel sistema dove sta
	var fleet_sys := need_ground.duplicate()
	if fleet_sys.is_empty():
		fleet_sys = allowed.duplicate()
	var i := 0
	for t in ships:
		var s: String = fleet_sys[i % fleet_sys.size()]
		out[s].append(t)
		var cap := int(RB.UNITS[t]["trasporto"])
		while cap > 0 and (not ground.is_empty() or not tie.is_empty()):
			if not tie.is_empty() and (cap % 2 == 0 or ground.is_empty()):
				out[s].append(tie.pop_back())
			else:
				out[s].append(ground.pop_back())
			cap -= 1
		i += 1
	# il resto a Coruscant o nei sistemi imperiali
	var rest_sys: Array = allowed.duplicate()
	var j := 0
	for t in ground + tie:
		out[rest_sys[j % rest_sys.size()]].append(t)
		j += 1
	return out
