class_name Board3D
extends Node3D
## La galassia sul tavolo: il tabellone di Rebellion con le miniature 3D del modulo TTS
## (una miniatura per tipo di unità con il numero accanto), le sagome dei leader, i segnalini
## di fedeltà, sabotaggio e distruzione, la coda di costruzione, il tempo e la reputazione.
## Trascina per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare.
## Clic su un sistema: lo sceglie (se è un bersaglio luminoso) oppure ne mostra il dettaglio.

signal target_clicked(key: String)
signal system_clicked(key: String)
signal target_hovered(key: String)

const W := 32.0                    # larghezza del tabellone in unità (4096 px)
const H := 16.0
const PX := 4096.0 / 32.0          # pixel del tabellone per unità

var eng: RBEngine
var st: RBState
var viewer := "R"                  # chi guarda: decide cosa si vede della base ribelle
var cam: Camera3D
var yaw := 0.0
const PITCH0 := 62.0
const DIST0 := 29.0
const FOCUS0 := Vector3(0, 0, 3.4)
var pitch := PITCH0
var dist := DIST0
var focus := FOCUS0
var _yaw_t := 0.0
var _pitch_t := PITCH0
var _dist_t := DIST0
var _focus_t := FOCUS0
var flat := false

var meshes := {}                   # tipo → [Mesh, Transform3D normalizzata]
var mats := {}
var dyn: Node3D
var fx_root: Node3D
var targets := {}
var rings := {}
var hover_key := ""
var hint_key := ""
var highlight := {}                # sistema → colore (combattimento, selezione)
var _dirty := true
var _drag := false
var _drag_moved := 0.0
var _pan := false
var _touches := {}
var _pinch_d := 0.0
var _t := 0.0


## Coordinate del tabellone (pixel dell'immagine 4096×2048) → mondo.
static func px(x: float, y: float) -> Vector3:
	return Vector3(x / PX - W / 2.0, 0.0, y / PX - H / 2.0)


static func sys_pos(s: String) -> Vector3:
	if s == "BASE":
		return px(150, 420)
	var p: Array = RB.SYS[s]["pos"]
	return Vector3((float(p[0]) - 0.5) * W, 0.0, (float(p[1]) - 0.5) * H)


## Casella n (1..16) della traccia del tempo.
static func time_pos(n: int) -> Vector3:
	n = clampi(n, 1, 16)
	if n % 2 == 0:
		return px(46, 704 + (16 - n) * 56.1)
	return px(112, 755 + (15 - n) * 55.1)


## Casella i (0..2) della coda di costruzione di una fazione.
static func queue_pos(f: String, i: int) -> Vector3:
	var ys_r := [184.0, 530.0, 857.0]
	var ys_i := [1836.0, 1510.0, 1178.0]
	return px(3990, ys_r[i] if f == "R" else ys_i[i])


func _ready() -> void:
	st = eng.st
	_build_env()
	_build_board()
	dyn = Node3D.new()
	add_child(dyn)
	fx_root = Node3D.new()
	add_child(fx_root)
	_apply_cam()
	refresh()


func _process(delta: float) -> void:
	_t += delta
	var k := minf(1.0, delta * 9.0)
	yaw = lerpf(yaw, _yaw_t, k)
	pitch = lerpf(pitch, _pitch_t, k)
	dist = lerpf(dist, _dist_t, k)
	focus = focus.lerp(_focus_t, k)
	_apply_cam()
	var pulse := 0.65 + 0.35 * sin(_t * 5.0)
	for key in rings:
		var r: MeshInstance3D = rings[key]
		var s := (1.18 if key == hover_key else 1.0) * (0.96 + 0.06 * sin(_t * 5.0))
		r.scale = Vector3(s, 1, s)
		var m: StandardMaterial3D = r.material_override
		m.albedo_color.a = pulse
	if _dirty:
		_dirty = false
		_rebuild()


# ================================================================== scena

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#020308")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#b8c8e0")
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -25, 0)
	sun.light_energy = 0.85
	sun.light_color = Color("#fff4e6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 160, 0)
	fill.light_energy = 0.3
	fill.light_color = Color("#9ec4ff")
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	# stelle lontane sotto e intorno al tabellone
	var stars := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 4
	sm.rings = 2
	mm.mesh = sm
	mm.instance_count = 700
	var g := RandomNumberGenerator.new()
	g.seed = 77
	for i in mm.instance_count:
		var p := Vector3(g.randf_range(-90, 90), g.randf_range(-40, -6), g.randf_range(-70, 70))
		var sc := g.randf_range(0.5, 2.2)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), p))
	stars.multimesh = mm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.9, 1.0)
	stars.material_override = smat
	add_child(stars)


func _build_board() -> void:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W + 0.3, 0.2, H + 0.3)
	body.mesh = bm
	body.material_override = _mat(Color("#1a2230"), 0.6)
	body.position = Vector3(0, -0.11, 0)
	root.add_child(body)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, H)
	top.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/board/tabellone.jpg")
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	top.material_override = m
	top.position = Vector3(0, 0.001, 0)
	root.add_child(top)
	add_child(root)


func _mat(c: Color, rough := 0.55, unshaded := false) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [c.to_html(), rough, unshaded]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats[key] = m
	return m


func _tex_mat(path: String, alpha := true, unshaded := false) -> StandardMaterial3D:
	var key := path + str(alpha) + str(unshaded)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = UI.tex(path)
	m.roughness = 0.7
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mats[key] = m
	return m


## Dimensione (lato più lungo) delle miniature, per categoria.
func _target_size(t: String) -> float:
	if t == "Death Star" or t == "Death Star Under Construction":
		return 0.85
	if t == "Super Star Destroyer":
		return 1.1
	if RB.is_structure(t):
		return 0.42
	if RB.is_capital(t):
		return 0.82 if t in ["Star Destroyer", "Mon Cala Cruiser", "Interdictor"] else 0.7
	if RB.is_fighter(t):
		return 0.46
	if RB.is_ship(t):
		return 0.6
	if t in ["AT-AT"]:
		return 0.62
	if t in ["AT-ST", "Assault Tank", "Airspeeder"]:
		return 0.5
	return 0.42


## Mesh della miniatura, scalata e appoggiata sul tabellone (base al centro, y = 0).
func _model(t: String) -> Array:
	if meshes.has(t):
		return meshes[t]
	var info: Dictionary = RB.MODELS.get(t, {})
	var mesh: Mesh = load(info["mesh"]) if info.has("mesh") and ResourceLoader.exists(info["mesh"]) else null
	if mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.2, 0.3)
		meshes[t] = [bm, Transform3D(), null]
		return meshes[t]
	var aabb := mesh.get_aabb()
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var sc := _target_size(t) * 1.35 / maxf(longest, 0.001)
	var c := aabb.get_center()
	var off := Vector3(-c.x, -aabb.position.y, -c.z) * sc
	var tr := Transform3D(Basis().scaled(Vector3.ONE * sc), off)
	var mat: StandardMaterial3D = null
	if info.has("tex") and ResourceLoader.exists(info["tex"]):
		mat = StandardMaterial3D.new()
		mat.albedo_texture = load(info["tex"])
		mat.roughness = 0.6
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	meshes[t] = [mesh, tr, mat]
	return meshes[t]


# ================================================================== aggiornamento

func refresh() -> void:
	_dirty = true


func _rebuild() -> void:
	for c in dyn.get_children():
		c.queue_free()
	var by_loc := {}
	for id in st.units:
		var u: Dictionary = st.units[id]
		var loc: String = u["loc"]
		if not by_loc.has(loc):
			by_loc[loc] = {"R": {}, "I": {}}
		var g: Dictionary = by_loc[loc][u["f"]]
		g[u["t"]] = g.get(u["t"], 0) + 1
	for loc in by_loc:
		if loc == "BASE" or RB.SYS.has(loc):
			_place_units(loc, by_loc[loc])
	_place_markers()
	_place_leaders()
	_place_queue()
	_place_tracks()


## Miniature di un sistema: navi nella fila in alto, unità terrestri sul pianeta;
## i Ribelli a sinistra, l'Impero a destra (o al centro se c'è una fazione sola).
func _place_units(loc: String, groups: Dictionary) -> void:
	var c := sys_pos(loc)
	var both: bool = not groups["R"].is_empty() and not groups["I"].is_empty()
	for f in ["R", "I"]:
		var g: Dictionary = groups[f]
		if g.is_empty():
			continue
		var space := []
		var ground := []
		var keys: Array = g.keys()
		keys.sort_custom(func(a, b): return RB.health(a) > RB.health(b))
		for t in keys:
			if RB.is_ship(t):
				space.append(t)
			else:
				ground.append(t)
		var side := 0.0
		if both:
			side = -0.75 if f == "R" else 0.75
		_row(c + Vector3(side, 0, -0.95), space, g, f, both)
		_row(c + Vector3(side, 0, -0.1), ground, g, f, both)


func _row(center: Vector3, types: Array, g: Dictionary, f: String, half: bool) -> void:
	if types.is_empty():
		return
	var per := 3 if half else 5
	var step := 0.5
	for i in types.size():
		var t: String = types[i]
		var r := i / per
		var k := i % per
		var n_in_row := mini(per, types.size() - r * per)
		var x := (k - (n_in_row - 1) / 2.0) * step
		var p := center + Vector3(x, 0, r * 0.5)
		_mini(t, p, f, int(g[t]))


func _mini(t: String, p: Vector3, f: String, count: int) -> void:
	var node := Node3D.new()
	node.position = p
	dyn.add_child(node)
	# dischetto colorato della fazione
	var d := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.21
	cm.bottom_radius = 0.22
	cm.height = 0.025
	cm.radial_segments = 20
	d.mesh = cm
	d.material_override = _mat(UI.fcolor(f).darkened(0.25), 0.4)
	d.position.y = 0.013
	node.add_child(d)
	var md := _model(t)
	var mi := MeshInstance3D.new()
	mi.mesh = md[0]
	mi.transform = md[1]
	if md[2] != null:
		mi.material_override = md[2]
	mi.position.y += 0.03
	# le navi «volano»: un po' sollevate sopra il dischetto
	if RB.is_ship(t) and not RB.is_station(t):
		mi.position.y += 0.06
	if f == "I":
		mi.rotation.y = PI
	node.add_child(mi)
	if count > 1:
		_label(str(count), Vector3(0.2, 0.32, 0.12), 54, Color.WHITE, UI.fcolor(f).darkened(0.6), node)


func _label(text: String, pos: Vector3, size := 48, col := Color.WHITE, outline := Color(0, 0, 0), parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font_title
	l.font_size = size
	l.pixel_size = 0.005
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = outline
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	(parent if parent != null else dyn).add_child(l)
	return l


func _quad(path: String, pos: Vector3, w: float, h: float, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	mi.mesh = pm
	mi.material_override = _tex_mat(path)
	mi.position = pos
	(parent if parent != null else dyn).add_child(mi)
	return mi


func _token(path: String, pos: Vector3, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.04
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = _mat(Color(0.08, 0.1, 0.14), 0.5)
	mi.position = pos + Vector3(0, 0.02, 0)
	dyn.add_child(mi)
	_quad(path, pos + Vector3(0, 0.045, 0), r * 2.0, r * 2.0)
	return mi


func _place_markers() -> void:
	for s in st.sys:
		var info: Dictionary = st.sys[s]
		var c := sys_pos(s)
		var hexp := c + Vector3(0.61, 0, 0.3)
		if info["dest"]:
			_quad("res://assets/tokens/distrutto.png", c + Vector3(0, 0.03, -0.05), 1.5, 1.5)
		elif info["subj"]:
			_token("res://assets/tokens/lealta_imperiale.png", hexp, 0.24)
			_label("sottomesso", hexp + Vector3(0, 0.22, 0.3), 20, Color("#ffb0a0"), Color(0.2, 0, 0))
		elif info["loy"] == "R":
			_token("res://assets/tokens/lealta_ribelle.png", hexp, 0.24)
		elif info["loy"] == "I":
			_token("res://assets/tokens/lealta_imperiale.png", hexp, 0.24)
		if info["sab"]:
			_token("res://assets/tokens/sabotaggio.png", c + Vector3(-0.62, 0, 0.32), 0.2)
		if highlight.has(s):
			_glow_ring(c, 1.05, highlight[s])
	# segnalini bersaglio degli obiettivi
	var mk := 0
	for id in st.markers:
		var s2: String = st.markers[id]
		if RB.SYS.has(s2):
			var n := clampi(int(str(id).right(1)) if str(id).right(1).is_valid_int() else mk + 1, 1, 4)
			_token("res://assets/tokens/segnalino_bersaglio_%d.png" % n, sys_pos(s2) + Vector3(-0.2, 0, 0.62), 0.17)
		mk += 1
	# sistemi che l'Impero sa non essere la base (sonde in mano o scartate)
	if viewer == "I" and not st.base_revealed:
		for s3 in _probed():
			_token("res://assets/tokens/sondato.png", sys_pos(s3) + Vector3(0.25, 0, 0.62), 0.15)
	# base ribelle: la vede solo chi gioca i Ribelli (o tutti quando è rivelata)
	if st.base != "" and (viewer == "R" or st.base_revealed):
		var bp := sys_pos(st.base)
		_glow_ring(bp, 0.85, Color(1.0, 0.35, 0.2, 0.9))
		_label("BASE RIBELLE" + ("" if st.base_revealed else " (segreta)"), bp + Vector3(0, 0.5, 0.95), 34, Color("#ffcfb8"), Color(0.3, 0.05, 0))


func _probed() -> Array:
	var out := []
	for p in st.probes:
		out.append(p)
	for p in st.deck.get("probe_dis", []):
		out.append(p)
	for p in st.known.get("I_not_base", []):
		if not p in out:
			out.append(p)
	return out


func _glow_ring(c: Vector3, rad: float, col: Color) -> void:
	var r := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = rad * 0.93
	tm.outer_radius = rad
	tm.rings = 48
	r.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = 1.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r.material_override = m
	r.position = c + Vector3(0, 0.03, 0)
	dyn.add_child(r)


## Sagome dei leader sul tabellone (quelli che hanno attivato un sistema o vi sono prigionieri).
func _place_leaders() -> void:
	var at := {}
	for n in st.leaders:
		var L: Dictionary = st.leaders[n]
		if L["st"] != "board":
			continue
		var loc: String = L["loc"]
		if not at.has(loc):
			at[loc] = []
		at[loc].append(n)
	for loc in at:
		if loc != "BASE" and not RB.SYS.has(loc):
			continue
		var c := sys_pos(loc)
		var list: Array = at[loc]
		for i in list.size():
			var n: String = list[i]
			var L: Dictionary = st.leaders[n]
			var p := c + Vector3(-0.95 + (i % 2) * 0.32, 0, 0.55 - (i / 2) * 0.35)
			_standee(n, L, p)


func _standee(n: String, L: Dictionary, p: Vector3) -> void:
	var node := Node3D.new()
	node.position = p
	dyn.add_child(node)
	var f: String = L["f"]
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.14
	cm.height = 0.04
	base.mesh = cm
	base.material_override = _mat(UI.fcolor(f).darkened(0.3), 0.4)
	base.position.y = 0.02
	node.add_child(base)
	# ritratto su una tessera verticale che guarda la telecamera
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.36, 0.5)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = UI.leader_tex(n)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material_override = m
	q.position.y = 0.3
	node.add_child(q)
	var frame := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(0.4, 0.54)
	frame.mesh = fm
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = UI.fcolor(f)
	m2.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame.material_override = m2
	frame.position.y = 0.3
	frame.position.z = -0.005
	frame.sorting_offset = -1
	node.add_child(frame)
	if L["ring"] == "captured" or L["ring"] == "carbonite":
		_label("PRIGIONIERO", Vector3(0, 0.66, 0), 26, Color("#ffd27a"), Color(0.25, 0.1, 0), node)


## Coda di costruzione: miniature nelle caselle 1, 2 e 3 di ciascuna fazione.
func _place_queue() -> void:
	for f in ["R", "I"]:
		for i in 3:
			var cnt := {}
			for t in st.queue[f][i]:
				var tt: String = t if t is String else str(t)
				cnt[tt] = cnt.get(tt, 0) + 1
			var keys := cnt.keys()
			var c := queue_pos(f, i)
			for k in keys.size():
				var col := k % 2
				var row := k / 2
				_mini(keys[k], c + Vector3(-0.22 + col * 0.44, 0, -0.75 + row * 0.42), f, int(cnt[keys[k]]))


## Segnalini del tempo e della reputazione sulla traccia a sinistra.
func _place_tracks() -> void:
	var tp := time_pos(st.round)
	_token("res://assets/tokens/tempo.png", tp + Vector3(0.05, 0, 0), 0.2)
	var rp := time_pos(st.rep)
	var off := Vector3(0, 0.05, 0) if st.rep != st.round else Vector3(0.1, 0.06, 0.12)
	_token("res://assets/tokens/reputazione.png", rp + off, 0.18)


# ================================================================== effetti

## Lampo luminoso su un sistema (combattimento, distruzione, salto nell'iperspazio).
func flash(s: String, col: Color, rad := 1.2, dur := 0.9) -> void:
	if s != "BASE" and not RB.SYS.has(s):
		return
	var r := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = rad
	sm.height = rad * 0.6
	r.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	r.material_override = m
	r.position = sys_pos(s) + Vector3(0, 0.2, 0)
	r.scale = Vector3.ONE * 0.2
	fx_root.add_child(r)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector3.ONE, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(r.queue_free)


## Scia nell'iperspazio da un sistema all'altro.
func streak(from: String, to: String, col: Color) -> void:
	if (from != "BASE" and not RB.SYS.has(from)) or (to != "BASE" and not RB.SYS.has(to)):
		return
	var a := sys_pos(from) + Vector3(0, 0.5, 0)
	var b := sys_pos(to) + Vector3(0, 0.5, 0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	bm.size = Vector3(0.06, 0.06, len)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	fx_root.add_child(mi)
	mi.position = (a + b) / 2.0
	if len > 0.01:
		mi.look_at_from_position(mi.position, b, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(mi.queue_free)


# ================================================================== bersagli

## Bersagli cliccabili: chiave (sistema o "BASE") → etichetta facoltativa.
func set_targets(keys: Array, hint := "", labels := {}) -> void:
	for k in rings:
		rings[k].queue_free()
	rings.clear()
	targets = {}
	hover_key = ""
	hint_key = hint
	for k in keys:
		var pos := sys_pos(k)
		targets[k] = pos
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.82
		tm.outer_radius = 0.95
		tm.rings = 48
		r.mesh = tm
		var m := StandardMaterial3D.new()
		var good: bool = k == hint
		var col := Color(0.5, 1.0, 0.6) if good else UI.HOLO
		m.albedo_color = Color(col.r, col.g, col.b, 0.9)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r.material_override = m
		r.position = pos + Vector3(0, 0.06, 0)
		add_child(r)
		rings[k] = r
		if labels.has(k):
			var l := Label3D.new()
			l.text = str(labels[k])
			l.font = UI.font_bold
			l.font_size = 52
			l.pixel_size = 0.006
			l.outline_size = 14
			l.modulate = Color.WHITE
			l.outline_modulate = Color(0, 0.1, 0.2)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.position = Vector3(0, 0.7, 0)
			r.add_child(l)


func clear_targets() -> void:
	set_targets([])


## Sistema sotto il puntatore (fra i bersagli se ce ne sono, altrimenti fra tutti).
func _pick(pos: Vector2, only_targets := true) -> String:
	var best := ""
	var bd := 60.0
	var pool: Dictionary = targets
	if not only_targets:
		pool = {}
		for s in RB.SYS:
			pool[s] = sys_pos(s)
		pool["BASE"] = sys_pos("BASE")
	for k in pool:
		var p3: Vector3 = pool[k]
		if cam.is_position_behind(p3):
			continue
		var sp := cam.unproject_position(p3)
		var dd := sp.distance_to(pos)
		# soglia in pixel proporzionale allo zoom: un pianeta occupa circa un'unità di raggio
		var rad := cam.unproject_position(p3 + Vector3(0.9, 0, 0)).distance_to(sp)
		if dd < maxf(rad, 24.0) and dd < bd + rad:
			if best == "" or dd < bd:
				bd = dd
				best = k
	return best


# ================================================================== telecamera

func _apply_cam() -> void:
	if cam == null:
		return
	if flat:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = dist * 0.72
		cam.position = focus + Vector3(0, 60, 0)
		cam.look_at(focus, Vector3(0, 0, -1))
		return
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var p := deg_to_rad(pitch)
	var yw := deg_to_rad(yaw)
	var off := Vector3(sin(yw) * cos(p), sin(p), cos(yw) * cos(p)) * dist
	cam.position = focus + off
	if pitch > 88.5:
		cam.look_at(focus, Vector3(-sin(yw), 0, -cos(yw)))
	else:
		cam.look_at(focus, Vector3.UP)


func set_flat(on: bool) -> void:
	flat = on
	if flat:
		_dist_t = clampf(_dist_t, 6.0, 30.0)


func reset_view() -> void:
	_yaw_t = _near_yaw(0.0)
	_pitch_t = PITCH0
	_dist_t = DIST0
	_focus_t = FOCUS0


func look_at_point(p: Vector3, d := 11.0) -> void:
	_focus_t = Vector3(p.x, 0, p.z)
	_dist_t = d


func look_at_system(s: String, d := 11.0) -> void:
	if s == "BASE" or RB.SYS.has(s):
		look_at_point(sys_pos(s) + Vector3(0, 0, 0.6), d)


func _near_yaw(a: float) -> float:
	while a - _yaw_t > 180.0:
		a -= 360.0
	while _yaw_t - a > 180.0:
		a += 360.0
	return a


func zoom(f: float) -> void:
	_dist_t = clampf(_dist_t * f, 4.0, 34.0)


func _pan_by(rel: Vector2) -> void:
	var yw := 0.0 if flat else deg_to_rad(yaw)
	var right := Vector3(cos(yw), 0, -sin(yw))
	var fwd := Vector3(-sin(yw), 0, -cos(yw))
	var f := dist * (0.0011 if flat else 0.0016)
	_focus_t += (-right * rel.x + fwd * rel.y) * f
	_focus_t.x = clampf(_focus_t.x, -17, 17)
	_focus_t.z = clampf(_focus_t.z, -10, 11)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.double_click and _pick(mb.position) == "":
				reset_view()
			if mb.pressed:
				_drag = true
				_drag_moved = 0.0
			else:
				if _drag and _drag_moved < 8.0:
					var k := _pick(mb.position)
					if k != "":
						target_clicked.emit(k)
					else:
						var s := _pick(mb.position, false)
						if s != "":
							system_clicked.emit(s)
				_drag = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = mb.pressed
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _touches.size() >= 2:
			return
		if _drag and not mm.shift_pressed and not flat:
			_drag_moved += mm.relative.length()
			_yaw_t -= mm.relative.x * 0.3
			_pitch_t = clampf(_pitch_t + mm.relative.y * 0.25, 22.0, 89.0)
		elif _pan or (_drag and (mm.shift_pressed or flat)):
			_drag_moved += mm.relative.length()
			_pan_by(mm.relative)
		else:
			var k2 := _pick(mm.position)
			if k2 != hover_key:
				hover_key = k2
				target_hovered.emit(k2)
	elif ev is InputEventScreenTouch:
		var stt := ev as InputEventScreenTouch
		if stt.pressed:
			_touches[stt.index] = stt.position
		else:
			_touches.erase(stt.index)
		_pinch_d = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var ks := _touches.keys()
			var d2: float = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				_dist_t = clampf(_dist_t * _pinch_d / maxf(1.0, d2), 4.0, 34.0)
			_pinch_d = d2
			_drag_moved = 99.0
	elif ev is InputEventMagnifyGesture:
		zoom(1.0 / (ev as InputEventMagnifyGesture).factor)
	elif ev is InputEventPanGesture:
		_pan_by((ev as InputEventPanGesture).delta * 12.0)
