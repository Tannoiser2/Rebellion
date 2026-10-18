class_name RB
extends RefCounted
## Dati fissi del gioco: sistemi della galassia, unità, leader e carte.
## Vengono da assets/data/*.json, generati da tools/prepara_asset.py a partire dal modulo
## Tabletop Simulator e dalle scansioni delle carte italiane.

static var _ok := false
static var SYS := {}          # nome → {nome, regione, popolato, icone, coda, adiacenti, pos}
static var UNITS := {}        # tipo → statistiche
static var LEADERS := {}      # nome → statistiche
static var CARDS := {}        # id istanza → carta
static var PROBES := {}       # sistema → carta sonda
static var MODELS := {}
static var RECRUIT: Array = []
static var BUILD: Array = []
static var _dist := {}

const FACTIONS := ["R", "I"]
const SKILLS := ["diplomazia", "intel", "logistica", "opspec"]
const SKILL_NAME := {"diplomazia": "Diplomazia", "intel": "Intelligence", "logistica": "Logistica", "opspec": "Operazioni speciali"}
## Le regioni non hanno un nome sul tabellone: le chiamiamo col sistema più noto.
const REGION_NAME := {1: "regione di Coruscant", 2: "regione di Mygeeto", 3: "regione di Kashyyyk", 4: "regione di Mon Calamari", 5: "regione di Nal Hutta", 6: "regione di Geonosis", 7: "regione di Utapau", 8: "regione di Bespin"}

## Nomi italiani delle unità (quelli delle carte italiane quando esistono).
const UNIT_IT := {
	"Stormtrooper": "Assaltatore", "AT-ST": "AT-ST", "AT-AT": "AT-AT", "TIE Fighter": "Caccia TIE",
	"Assault Carrier": "Portacaccia d'Assalto", "Star Destroyer": "Star Destroyer",
	"Super Star Destroyer": "Super Star Destroyer", "Death Star": "Morte Nera",
	"Death Star Under Construction": "Morte Nera in Costruzione",
	"Rebel Trooper": "Soldato Ribelle", "Airspeeder": "Airspeeder", "X-Wing": "X-wing", "Y-Wing": "Y-wing",
	"Corellian Corvette": "Corvetta Corelliana", "Rebel Transport": "Trasporto Ribelle",
	"Mon Cala Cruiser": "Incrociatore Mon Calamari", "Shield Generator": "Generatore di Scudo",
	"Ion Cannon": "Cannone a Ioni",
	"TIE Striker": "TIE Striker", "Assault Tank": "Carro d'Assalto", "Shield Bunker": "Bunker Scudo",
	"Interdictor": "Interdictor", "U-Wing": "U-wing", "Rebel Vanguard": "Avanguardia Ribelle",
	"Nebulon-B Frigate": "Fregata Nebulon-B", "Golan Arms Turret": "Torretta Golan Arms",
}

## Nomi italiani dei leader con il grado (i nomi propri restano uguali).
const LEADER_IT := {
	"Emperor Palpatine": "Imperatore Palpatine", "Grand Moff Tarkin": "Gran Moff Tarkin",
	"Darth Vader": "Darth Vader", "General Tagge": "Generale Tagge", "Soontir Fel": "Soontir Fel",
	"Admiral Piett": "Ammiraglio Piett", "Admiral Ozzel": "Ammiraglio Ozzel", "Janus Greejatus": "Janus Greejatus",
	"Moff Jerjerrod": "Moff Jerjerrod", "Colonel Yularen": "Colonnello Yularen", "General Veers": "Generale Veers",
	"Boba Fett": "Boba Fett", "Admiral Motti": "Ammiraglio Motti", "Director Krennic": "Direttore Krennic",
	"Krennic's Finest": "I migliori di Krennic", "Jabba the Hutt": "Jabba the Hutt",
	"Princess Leia": "Principessa Leia", "Mon Mothma": "Mon Mothma", "General Rieekan": "Generale Rieekan",
	"Jan Dodonna": "Jan Dodonna", "Luke Skywalker (Jedi)": "Luke Skywalker (Jedi)", "Wedge Antilles": "Wedge Antilles",
	"Obi-Wan Kenobi": "Obi-Wan Kenobi", "Luke Skywalker": "Luke Skywalker", "General Madine": "Generale Madine",
	"Han Solo": "Han Solo", "Lando Calrissian": "Lando Calrissian", "Chewbacca": "Chewbacca",
	"Admiral Ackbar": "Ammiraglio Ackbar", "Saw Gerrera": "Saw Gerrera", "Cassian Andor": "Cassian Andor",
	"Jyn Erso": "Jyn Erso", "Chirrut Imwe": "Chirrut Îmwe",
}

const RING_IT := {
	"captured": "Catturato", "carbonite": "Grafite", "lure": "Richiamo del Lato Oscuro", "bounty": "Taglia",
	"r2d2": "R2-D2", "c3po": "C-3PO", "falcon": "Millennium Falcon", "yoda": "Maestro Yoda", "k2so": "K-2SO",
}


static func load_all() -> void:
	if _ok:
		return
	_ok = true
	var m: Dictionary = _json("res://assets/data/mondo.json")
	SYS = m["sistemi"]
	UNITS = m["unita"]
	LEADERS = m["leader"]
	RECRUIT = m["reclutamento"]
	BUILD = m["costruzione"]
	for c in _json("res://assets/data/carte.json"):
		CARDS[c["id"]] = c
	for p in _json("res://assets/data/sonde.json"):
		PROBES[p["sistema"]] = p
	var mm = _json("res://assets/data/modelli.json")
	if mm is Dictionary:
		MODELS = mm
	_compute_distances()


static func _json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("manca " + path)
		return {}
	return JSON.parse_string(f.get_as_text())


static func _compute_distances() -> void:
	for a in SYS:
		var d := {a: 0}
		var front := [a]
		while not front.is_empty():
			var nx := []
			for s in front:
				for b in SYS[s]["adiacenti"]:
					if not d.has(b):
						d[b] = d[s] + 1
						nx.append(b)
			front = nx
		_dist[a] = d


static func dist(a: String, b: String) -> int:
	if not _dist.has(a) or not _dist[a].has(b):
		return 99
	return _dist[a][b]


static func adjacent(a: String, b: String) -> bool:
	return SYS.has(a) and b in SYS[a]["adiacenti"]


static func sys_name(s: String) -> String:
	if s == "BASE":
		return "Base Ribelle"
	if SYS.has(s):
		return SYS[s]["nome"]
	return s.capitalize()


static func region_systems(r: int) -> Array:
	var out := []
	for s in SYS:
		if int(SYS[s]["regione"]) == r:
			out.append(s)
	return out


static func region_of(s: String) -> int:
	return int(SYS[s]["regione"]) if SYS.has(s) else 0


static func unit_it(t: String) -> String:
	return UNIT_IT.get(t, t)


static func leader_it(n: String) -> String:
	return LEADER_IT.get(n, n)


static func card(id: String) -> Dictionary:
	return CARDS.get(id, {})


## Id del modello di carta, senza il numero di copia ("hidden_fleet#2" → "hidden_fleet").
static func base_id(id: String) -> String:
	return id.get_slice("#", 0)


static func card_name(id: String) -> String:
	var c := card(id)
	return c.get("nome", id) if not c.is_empty() else id


static func is_ship(t: String) -> bool:
	return UNITS[t]["teatro"] == "spazio"


static func is_ground(t: String) -> bool:
	return UNITS[t]["teatro"] == "terra"


static func is_structure(t: String) -> bool:
	return bool(UNITS[t]["struttura"])


static func health(t: String) -> int:
	return int(UNITS[t]["salute"])


static func health_color(t: String) -> String:
	return UNITS[t]["colore_salute"]


static func is_capital(t: String) -> bool:
	return is_ship(t) and health_color(t) == "rosso"


static func is_fighter(t: String) -> bool:
	return is_ship(t) and health_color(t) == "nero" and t != "Death Star Under Construction"


static func is_station(t: String) -> bool:
	return t == "Death Star" or t == "Death Star Under Construction"


## Tipi di unità che una fazione può costruire con un'icona risorsa ("BT", "OC", …).
static func buildable(f: String, icon: String, rote: bool) -> Array:
	var out := []
	for t in UNITS:
		var u: Dictionary = UNITS[t]
		if u["fazione"] == f and u["icona"] == icon and (rote or u["set"] == "base"):
			out.append(t)
	return out


static func leader_skill(n: String, sk: String, minor := true) -> int:
	if not LEADERS.has(n):
		return 0
	var v := int(LEADERS[n]["abilita"].get(sk, 0))
	if minor:
		v += int(LEADERS[n]["minori"].get(sk, 0))
	return v


static func leader_minor(n: String, sk: String) -> int:
	return int(LEADERS[n]["minori"].get(sk, 0)) if LEADERS.has(n) else 0


static func has_tactics(n: String) -> bool:
	return LEADERS.has(n) and (int(LEADERS[n]["spazio"]) > 0 or int(LEADERS[n]["terra"]) > 0)
