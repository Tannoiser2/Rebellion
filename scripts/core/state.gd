class_name RBState
extends RefCounted
## Stato completo di una partita di Rebellion: galassia, unità, leader, mazzi e mani.
## Qui stanno solo dati, domande sullo stato e modifiche immediate; tutte le decisioni dei
## giocatori le chiede il motore (RBEngine). Lo stato è fatto di dizionari e array semplici,
## così si copia al volo (per l'IA) e si confronta fra dispositivi diversi.

const FIELDS := ["opt", "round", "rep", "phase", "winner", "win_text", "sys", "units", "uid", "queue",
	"leaders", "base", "base_revealed", "deck", "hand", "acts", "objs", "obj_play", "probes", "assign",
	"passed", "tac", "flags", "current", "used_objective", "known", "leader_limit", "markers"]

var rng := RandomNumberGenerator.new()
var opt := {}
var round := 1                 # posizione del segnalino tempo
var rep := 14                  # posizione del segnalino reputazione
var phase := "setup"
var winner := ""
var win_text := ""
var sys := {}                  # sistema → {loy, subj, sab, dest}
var units := {}                # id → {id, t, f, loc, dmg}
var uid := 1
var queue := {"R": [[], [], []], "I": [[], [], []]}
var leaders := {}              # nome → {f, home, st, loc, ring, det}
var base := ""                 # sistema della base ribelle
var base_revealed := false
var deck := {}
var hand := {"R": [], "I": []}
var acts := {"R": [], "I": []}
var objs: Array = []
var obj_play: Array = []       # obiettivi in gioco con i loro segnalini bersaglio
var probes: Array = []         # carte sonda in mano all'Impero
var assign := {"R": [], "I": []}
var passed := {"R": false, "I": false}
var tac := {"R": [], "I": []}
var flags := {}
var current := "R"
var used_objective := false
var known := {"I_not_base": []}  # informazioni pubbliche per l'IA imperiale
var leader_limit := {"R": 8, "I": 8}
var markers := {}              # segnalini bersaglio: id → sistema
var log: Array = []


# ------------------------------------------------------------------ copia

func snapshot() -> Dictionary:
	var d := {}
	for f in FIELDS:
		var v = get(f)
		d[f] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	d["rng_state"] = rng.state
	d["rng_seed"] = rng.seed
	return d


func restore(d: Dictionary) -> void:
	for f in FIELDS:
		var v = d[f]
		set(f, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	rng.seed = d["rng_seed"]
	rng.state = d["rng_state"]


func clone() -> RBState:
	var s := RBState.new()
	s.restore(snapshot())
	return s


func say(t: String) -> void:
	log.append(t)


static func other(f: String) -> String:
	return "I" if f == "R" else "R"


static func fname(f: String) -> String:
	return "Alleanza Ribelle" if f == "R" else "Impero Galattico"


static func fshort(f: String) -> String:
	return "Ribelli" if f == "R" else "Impero"


# ------------------------------------------------------------------ mazzi

func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func draw(key: String, discard_key := ""):
	if deck[key].is_empty() and discard_key != "" and not deck.get(discard_key, []).is_empty():
		deck[key] = deck[discard_key].duplicate()
		deck[discard_key].clear()
		shuffle(deck[key])
	if deck[key].is_empty():
		return null
	return deck[key].pop_front()


func roll(n: int, green := 0) -> Array:
	## Tira n dadi (rossi o neri: per le missioni il colore non conta).
	## Facce: 0 vuoto, 1 colpo, 2 colpo diretto, 3 speciale.
	var out := []
	for i in n:
		out.append(_face())
	for i in green:
		out.append(green_face())
	return out


## Dado verde dell'Ascesa dell'Impero: 2 facce con colpo diretto, 4 vuote.
func green_face() -> int:
	return 2 if rng.randi_range(0, 5) < 2 else 0


func _face() -> int:
	# dado rosso o nero di Rebellion: 2 vuoti, 2 colpi, 1 colpo diretto, 1 speciale
	var r := rng.randi_range(0, 5)
	return [0, 0, 1, 1, 2, 3][r]


static func successes(dice: Array) -> int:
	var n := 0
	for d in dice:
		if d is Dictionary:
			d = d["v"]
		match int(d):
			1, 2: n += 1
			3: n += 2
	return n


# ------------------------------------------------------------------ sistemi

func is_populous(s: String) -> bool:
	return RB.SYS.has(s) and RB.SYS[s]["popolato"] and not sys[s]["dest"]


func is_remote(s: String) -> bool:
	return RB.SYS.has(s) and not RB.SYS[s]["popolato"] and not sys[s]["dest"]


func loyalty(s: String) -> String:
	return sys[s]["loy"] if sys.has(s) else ""


func is_subjugated(s: String) -> bool:
	return sys.has(s) and sys[s]["subj"]


func is_rebel_sys(s: String) -> bool:
	return sys.has(s) and sys[s]["loy"] == "R" and not sys[s]["subj"]


func is_imperial_sys(s: String) -> bool:
	return sys.has(s) and (sys[s]["loy"] == "I" or sys[s]["subj"])


func is_neutral(s: String) -> bool:
	return sys.has(s) and sys[s]["loy"] == ""


func has_loyalty(f: String, s: String) -> bool:
	return sys.has(s) and sys[s]["loy"] == f


func all_systems() -> Array:
	return RB.SYS.keys()


## Fedeltà guadagnata: 1 sposta di un passo (avversario → neutrale → proprio), 2 arriva in fondo.
func gain_loyalty(f: String, s: String, n := 1) -> void:
	if not is_populous(s) or s == "CORUSCANT":
		return
	for i in n:
		var cur: String = sys[s]["loy"]
		if cur == f:
			break
		if cur == "":
			sys[s]["loy"] = f
		else:
			sys[s]["loy"] = ""
	update_subjugation(s)


func lose_loyalty(f: String, s: String) -> void:
	if sys.has(s) and sys[s]["loy"] == f and s != "CORUSCANT":
		sys[s]["loy"] = ""


func update_subjugation(s: String) -> void:
	if not sys.has(s):
		return
	var imp_ground := false
	for id in units:
		var u: Dictionary = units[id]
		if u["loc"] == s and u["f"] == "I" and RB.is_ground(u["t"]):
			imp_ground = true
			break
	if imp_ground and sys[s]["loy"] != "I" and is_populous(s):
		sys[s]["subj"] = true
	elif not imp_ground:
		sys[s]["subj"] = false
	if sys[s]["loy"] == "I":
		sys[s]["subj"] = false


func update_all_subjugation() -> void:
	for s in sys:
		update_subjugation(s)


## Sistema reale indicato dalla casella "Base Ribelle" (se la base è rivelata è il suo sistema).
func base_loc() -> String:
	return base if base_revealed else "BASE"


# ------------------------------------------------------------------ unità

func add_unit(t: String, f: String, loc: String) -> int:
	if loc == "BASE" and base_revealed:
		loc = base
	var id := uid
	uid += 1
	units[id] = {"id": id, "t": t, "f": f, "loc": loc, "dmg": 0}
	if loc != "BASE" and RB.SYS.has(loc):
		update_subjugation(loc)
	return id


func remove_unit(id: int) -> void:
	if not units.has(id):
		return
	var loc: String = units[id]["loc"]
	units.erase(id)
	if RB.SYS.has(loc):
		update_subjugation(loc)


func move_unit(id: int, loc: String) -> void:
	if loc == "BASE" and base_revealed:
		loc = base
	var old: String = units[id]["loc"]
	units[id]["loc"] = loc
	if RB.SYS.has(old):
		update_subjugation(old)
	if RB.SYS.has(loc):
		update_subjugation(loc)


func units_at(loc: String, f := "", theater := "") -> Array:
	var out := []
	for id in units:
		var u: Dictionary = units[id]
		if u["loc"] != loc:
			continue
		if f != "" and u["f"] != f:
			continue
		if theater != "" and RB.UNITS[u["t"]]["teatro"] != theater:
			continue
		out.append(id)
	out.sort()
	return out


func count_type(loc: String, t: String, f := "") -> int:
	var n := 0
	for id in units:
		var u: Dictionary = units[id]
		if u["loc"] == loc and u["t"] == t and (f == "" or u["f"] == f):
			n += 1
	return n


func has_units(loc: String, f: String, theater := "") -> bool:
	for id in units:
		var u: Dictionary = units[id]
		if u["loc"] == loc and u["f"] == f and (theater == "" or RB.UNITS[u["t"]]["teatro"] == theater):
			return true
	return false


func systems_with_units(f: String) -> Array:
	var out := {}
	for id in units:
		var u: Dictionary = units[id]
		if u["f"] == f and u["loc"] != "BASE":
			out[u["loc"]] = true
	return out.keys()


## Pezzi di un tipo ancora disponibili nella riserva (i componenti sono limitati).
func supply(t: String) -> int:
	var used := 0
	for id in units:
		if units[id]["t"] == t:
			used += 1
	for f in queue:
		for sp in queue[f]:
			for x in sp:
				if x == t:
					used += 1
	return int(RB.UNITS[t]["massimo"]) - used


func unit_name(id: int) -> String:
	return RB.unit_it(units[id]["t"])


## Capacità di trasporto delle navi di una fazione in un luogo, e unità che ne hanno bisogno.
func transport_capacity(ids: Array) -> int:
	var c := 0
	for id in ids:
		c += int(RB.UNITS[units[id]["t"]]["trasporto"])
	return c


func needs_transport(id: int) -> bool:
	return bool(RB.UNITS[units[id]["t"]]["serve_trasporto"])


# ------------------------------------------------------------------ leader

func leader_pool(f: String) -> Array:
	var out := []
	for n in leaders:
		var l: Dictionary = leaders[n]
		if l["f"] == f and l["st"] == "pool":
			out.append(n)
	out.sort()
	return out


func leaders_at(loc: String, f := "", include_captured := false) -> Array:
	var out := []
	for n in leaders:
		var l: Dictionary = leaders[n]
		if l["st"] != "board" or l["loc"] != loc:
			continue
		if f != "" and l["f"] != f:
			continue
		if not include_captured and is_captured(n):
			continue
		out.append(n)
	out.sort()
	return out


func captured_at(loc: String) -> Array:
	var out := []
	for n in leaders:
		var l: Dictionary = leaders[n]
		if l["st"] == "board" and l["loc"] == loc and is_captured(n):
			out.append(n)
	out.sort()
	return out


func captured_leaders() -> Array:
	var out := []
	for n in leaders:
		if leaders[n]["st"] == "board" and is_captured(n):
			out.append(n)
	out.sort()
	return out


func is_captured(n: String) -> bool:
	return leaders.has(n) and leaders[n]["ring"] in ["captured", "carbonite"]


func recruited(n: String) -> bool:
	return leaders.has(n) and leaders[n]["st"] in ["pool", "board", "mission"]


func leader_count(f: String) -> int:
	var c := 0
	for n in leaders:
		if leaders[n]["f"] == f and leaders[n]["st"] in ["pool", "board", "mission"]:
			c += 1
	return c


func place_leader(n: String, loc: String) -> void:
	if loc == "BASE" and base_revealed:
		loc = base
	leaders[n]["st"] = "board"
	leaders[n]["loc"] = loc


func to_pool(n: String) -> void:
	leaders[n]["st"] = "pool"
	leaders[n]["loc"] = ""


func leader_skill(n: String, sk: String, count_all := false) -> int:
	## Icone abilità di un leader per una missione (anche minori e anelli).
	var v := 0
	if count_all:
		for k in RB.SKILLS:
			v += RB.leader_skill(n, k)
		if leaders[n]["ring"] == "k2so":
			v += 2
		return v
	v = RB.leader_skill(n, sk)
	if leaders[n]["ring"] == "k2so" and sk in ["opspec", "intel"]:
		v += 1
	return v


func leader_minor(n: String, sk: String, count_all := false) -> int:
	var v := 0
	if count_all:
		for k in RB.SKILLS:
			v += RB.leader_minor(n, k)
	else:
		v = RB.leader_minor(n, sk)
	if leaders[n]["ring"] == "k2so" and (count_all or sk in ["opspec", "intel"]):
		v += 2 if count_all else 1
	return v


func tactic_value(loc: String, f: String, theater: String) -> int:
	var best := 0
	for n in leaders_at(loc, f):
		best = max(best, int(RB.LEADERS[n]["spazio" if theater == "spazio" else "terra"]))
	return best


func has_tactic_leader(loc: String, f: String) -> bool:
	for n in leaders_at(loc, f):
		if RB.has_tactics(n):
			return true
	return false


# ------------------------------------------------------------------ carte

func hand_count(f: String) -> int:
	return hand[f].size()


func is_starting_mission(id: String) -> bool:
	return RB.card(id).get("iniziale", false)


func assigned_leaders(f: String) -> Array:
	var out := []
	for a in assign[f]:
		out.append_array(a["leaders"])
	return out


# ------------------------------------------------------------------ vittoria

func check_victory() -> bool:
	if winner != "":
		return true
	if rep <= round:
		winner = "R"
		win_text = "La reputazione dell'Alleanza ha raggiunto il segnalino tempo: la galassia si solleva!"
		return true
	if base_revealed:
		var imp := has_units(base, "I")
		var reb := has_units(base, "R")
		if imp and not reb:
			winner = "I"
			win_text = "L'Impero ha occupato il sistema della base ribelle: la Ribellione è schiacciata."
			return true
	return false
