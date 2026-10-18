extends SceneTree
## Partite IA contro IA senza grafica: controlla che il motore arrivi in fondo senza errori.
## godot --headless --path . --script tests/sim.gd -- [partite] [seme] [rote 0/1] [cinematografico 0/1] [mazzi base/rote]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 3
	var seed := int(args[1]) if args.size() > 1 else 1
	var rote := (args[2] != "0") if args.size() > 2 else true
	var cine := args.size() > 3 and args[3] != "0"
	var sets := args[4] if args.size() > 4 else "rote"
	var wins := {"R": 0, "I": 0, "": 0}
	var rounds := 0
	for g in n:
		var e := RBEngine.new()
		e.headless = true
		root.add_child(e)
		if OS.get_environment("RB_VERBOSE") != "":
			e.log_added.connect(func(t): print("  ", t))
		e.setup({"seed": seed + g, "rote": rote, "cinematic": cine, "set_R": sets, "set_I": sets, "players": {"R": {"ai": true, "level": 1}, "I": {"ai": true, "level": 1}}})
		if g == 0:
			print("opzioni: ", e.st.opt)
		var t0 := Time.get_ticks_msec()
		await e.run()
		wins[e.st.winner] += 1
		print("  basi possibili a fine partita: %d, base %s, rivelata %s, leader I %d" % [e.ais["I"].possible_bases().size(), e.st.base, e.st.base_revealed, e.st.leader_count("I")])
		rounds += e.st.round
		print("partita %d: vince %s al round %d (rep %d) in %d ms — %s" % [g, e.st.winner, e.st.round, e.st.rep, Time.get_ticks_msec() - t0, e.st.win_text])
		e.queue_free()
	print("Ribelli %d, Impero %d, nessuno %d; round medio %.1f" % [wins["R"], wins["I"], wins[""], float(rounds) / max(1, n)])
	quit()
