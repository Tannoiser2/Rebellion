extends SceneTree
## Prova visiva: apre il menu, poi una partita con i Ribelli umani e l'Impero IA; a ogni decisione
## fotografa lo schermo (la prima di ogni tipo) e risponde con l'IA. Le immagini vanno in
## RB_SHOTS (cartella) — uso: xvfb-run godot --rendering-driver opengl3 --script tests/shots.gd

var out := ""
var main
var seen := {}
var n := 0
var frames := 0
var gv


func _initialize() -> void:
	out = OS.get_environment("RB_SHOTS")
	if out == "":
		out = "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var scene: PackedScene = load("res://scenes/Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	_run()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [out, n, name])
	n += 1
	print("foto ", name)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	await _wait(1.0)
	await _shot("menu")
	main.show_rules()
	await _wait(0.5)
	await _shot("regole")
	var cfg := {"players": {"R": {"ai": false, "level": 1}, "I": {"ai": true, "level": 1}}, "ai_delay": 0.0,
		"rote": OS.get_environment("RB_ROTE") != "0", "seed": 4242, "set_R": "rote", "set_I": "rote", "rote_units": true, "cinematic": OS.get_environment("RB_CINE") == "1"}
	main.start_game(cfg)
	gv = main.current
	gv.engine.decision_requested.connect(_on_req)
	var limit := float(OS.get_environment("RB_SECS")) if OS.get_environment("RB_SECS") != "" else 90.0
	await _wait(limit)
	await _shot("fine")
	quit()


func _on_req(req: Dictionary) -> void:
	var key := "%s_%s" % [req["k"], req.get("ctx", "")]
	var r = gv.engine.ais[req["f"]].decide(gv.engine, req["f"], req)
	if not seen.has(key) and seen.size() < 40:
		seen[key] = true
		await _wait(0.4)
		if req["k"] == "choice" and req.get("ctx", "") == "assign":
			gv.show_zoom(str(gv.st.hand["R"][0]) if not gv.st.hand["R"].is_empty() else "")
		await _shot(key)
		gv.hide_zoom()
	else:
		await process_frame
	if gv.pending.is_empty():
		return
	gv._answer(r)
