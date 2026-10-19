extends SceneTree
## Regression coverage for menus, mobile lifecycle, inventory and persistence.
## godot --headless --path game --script res://tests/systems.gd
## Every file lives in a unique temporary directory; real progress is never read.

const SaveStore = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var test_dir: String
var serial := 0
var retired: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL systems: " + message)
	return condition


func fresh(save_file := "", settings_file := ""):
	serial += 1
	var game = load("res://main.tscn").instantiate()
	game.save_path = test_dir + ("/save_%d.json" % serial if save_file.is_empty() else "/" + save_file)
	game.settings_path = test_dir + ("/settings_%d.cfg" % serial if settings_file.is_empty() else "/" + settings_file)
	game.persistence_enabled = false
	root.add_child(game)
	game.set_process(false)
	return game


func idle(game) -> void:
	game.new_game()
	game.ev = -1
	game.ev_wait = 0
	game.dialog_lines.clear()
	game.ui_dialog.hide()
	game.devil.anim = -1
	game.devil.play(0)
	game._refresh_inv()


func snapshot(game) -> Dictionary:
	# Normalize JSON numbers and detach all dictionaries, including target refs.
	return JSON.parse_string(JSON.stringify(SaveStore.capture(game)))


func write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if check(file != null, "open test fixture " + path):
		file.store_string(value)
		file.close()


func persist(game, label: String) -> bool:
	game.persistence_enabled = true
	var ok: bool = game.save_game()
	game.persistence_enabled = false
	return check(ok, label)


func advance(game, seconds := 3.0) -> void:
	for _i in ceili(seconds / game.TICK):
		game._process(game.TICK)


func _run() -> void:
	test_dir = "user://systems_regression_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not check(DirAccess.make_dir_recursive_absolute(test_dir) == OK, "create isolated save directory"):
		quit(1)
		return
	test_menu_and_lifecycle()
	test_drop_slots()
	test_round_trip()
	test_mid_action_saves()
	test_backup()
	test_malformed_saves()
	test_debug_paths()
	test_grave_tap()
	test_stats()
	# Let AudioServer commit play/stop commands before releasing looping streams.
	await create_timer(0.15).timeout
	for game in retired:
		game.sound.shutdown()
	await create_timer(0.2).timeout
	for game in retired:
		game.queue_free()
	retired.clear()
	await process_frame
	cleanup()
	if failures:
		printerr("SYSTEMS FAILED: %d / %d checks" % [failures, checks])
		quit(1)
	else:
		print("SYSTEMS OK: %d checks" % checks)
		quit(0)


func test_menu_and_lifecycle() -> void:
	var game = fresh()
	check(game.menu_open and not game.in_game and game.menus.page == "home", "boot shows main menu")
	check(not game.has_save(), "fresh isolated profile has no Continue save")
	var continue_button = game.menus.column.get_child(2)
	check(continue_button is Button and continue_button.disabled, "Continue is disabled without a save")
	var before := snapshot(game)
	advance(game, 2)
	check(snapshot(game) == before, "main menu does not start intro or animate the world")
	game._back()
	check(game.menus.page == "home" and not game.in_game, "Back on home stays on home")
	idle(game)
	check(game.in_game and not game.menu_open and not game.menus.visible and game.game_layer.visible,
		"New Game enters world and hides main menu")
	check(not FileAccess.file_exists(game.save_path), "disabled persistence writes no save")
	game.target = {kind = "walk", x = 100.0}
	var start_x: float = game.devil.x
	game._process(game.TICK)
	check(game.devil.x > start_x, "movement runs during active gameplay")
	game._back()
	check(game.menu_open and game.menus.page == "pause", "Back in game opens pause")
	before = snapshot(game)
	advance(game, 2)
	check(snapshot(game) == before, "pause freezes movement, actors, timers and event state")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(700, 500)
	game._unhandled_input(click)
	check(snapshot(game) == before, "paused world ignores pointer input")
	game.menus.show_page("settings")
	game._back()
	check(game.menu_open and game.menus.page == "pause", "settings Back returns to pause")
	game._back()
	check(not game.menu_open and game.in_game, "Back from pause resumes game")
	game._process(game.TICK)
	check(game.devil.x > before.devil.x, "movement resumes after pause")
	game._say({lines = [game._line(44), game._line(45)]})
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	before = snapshot(game)
	game._unhandled_input(click)
	check(snapshot(game) == before, "Android Back pauses without advancing dialogue")
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(game.menu_open and game.sound.suspended, "Android background event pauses game and audio")
	before = snapshot(game)
	advance(game, 2)
	check(snapshot(game) == before, "background state remains frozen")
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(game.menu_open and not game.sound.suspended and game.sound.voice.stream_paused,
		"Android resume leaves gameplay and voice paused until explicit resume")
	game._back()
	check(not game.menu_open and not game.sound.voice.stream_paused, "explicit resume releases voice pause")
	game.pause_game()
	game.menus._request_new()
	check(game.menus.page == "confirm_new" and game.in_game,
		"New Game requests confirmation before discarding active progress")
	game.menus.back()
	check(game.menus.page == "pause" and game.in_game, "cancel New Game preserves paused session")
	game.return_home()
	check(game.menu_open and not game.in_game and game.menus.page == "home", "return to main menu ends active session")
	game.inv = [15]
	game.souls = {e = true}
	game.scenes["9,2"].exits[1].open = true
	game.new_game()
	check(game.inv.is_empty() and game.souls.is_empty() and not game.scenes["9,2"].exits[1].open
		and game.ev == 25 and game.cur_key == "3,2", "New Game resets progress, world changes and intro")
	retire(game)


func test_drop_slots() -> void:
	var game = fresh()
	for slot in [0, 1]:
		idle(game)
		game.inv = [15, 22]
		game._refresh_inv()
		check(not game.drop_buttons[0].disabled and not game.drop_buttons[1].disabled,
			"both occupied slots allow dropping")
		game.target = {kind = "walk", x = 180.0}
		game._drop_item(slot)
		check(game.inv == [15, 22] and game.pending_pick == -1 and not game.devil.free,
			"drop slot %d waits for bending animation" % slot)
		check(game.target.is_empty() and game.drop_slot == slot, "drop selects requested slot and cancels walking")
		game._drop_item(1 - slot)
		check(game.drop_slot == slot, "second drop is rejected while animation is running")
		advance(game)
		var expected_item := 15 if slot == 0 else 22
		check(game.inv == ([22] if slot == 0 else [15]), "drop removes only selected inventory slot %d" % slot)
		check(game.scenes[game.cur_key].floor_items.size() == 1
			and game.scenes[game.cur_key].floor_items[0].item == expected_item,
			"dropped slot %d appears once on current room floor" % slot)
		check(game.pending_pick == -2 and game.drop_slot == -1, "completed drop clears pending action")
		check(game.drop_buttons[1].disabled, "empty slot drop button is disabled")
		game.pending_pick = 0
		game._do_pick()
		check(game.inv.has(expected_item) and game.scenes[game.cur_key].floor_items.is_empty(),
			"dropped item can be picked back up")
		check(game.drop_buttons[0].disabled and game.drop_buttons[1].disabled,
			"item description blocks dropping")
		var before := snapshot(game)
		game._drop_item(0)
		check(snapshot(game) == before, "drop request during dialogue has no effect")
	retire(game)


func test_round_trip() -> void:
	var game = fresh("round_trip.json")
	idle(game)
	game.inv = [19]
	var caretaker: Dictionary = game._npc("7,2", 0)
	game._interact(caretaker)
	game._next_free(caretaker)
	check(caretaker.free_dialogs[0].used, "quest dialogue fixture has consumed its once-only line")
	game.cur_key = "8,1"
	game.devil.x = 123
	game.devil.y = 178
	game.devil.flip = true
	game.inv = [15, 22]
	game.souls = {d = true, e = true}
	game.burn_msg = 46
	game.scenes["9,2"].exits[1].open = true
	game.scenes["9,2"].floor_items.remove_at(0)
	game._run_event(11) # Dialogue replacement used by the actual quest.
	var npc: Dictionary = game._npc("8,1", 1)
	npc.blocker = false
	npc.interactions[0].done = true
	npc.frames = [5]
	npc.actor.play(5)
	var speaker: Dictionary = game._npc("9,2", 0)
	speaker.free_dialogs[0].once = true
	speaker.free_dialogs[0].used = true
	speaker.p = 1
	game.target = {kind = "npc", npc = npc, x = 135.0}
	game._say({lines = [game._line(44), game._line(45), {item = 15}]})
	game._advance_dialog()
	var before := snapshot(game)
	if persist(game, "save complete quest/dialogue snapshot"):
		var restored = fresh("round_trip.json")
		check(restored.has_save(), "fresh instance finds Continue save")
		if check(restored.continue_game(), "fresh instance loads saved game"):
			check(snapshot(restored) == before, "all rooms, actor poses, inventory, souls and dialogue index round trip")
			var restored_caretaker: Dictionary = restored._npc("7,2", 0)
			restored_caretaker.p = 0
			var next_dialog: Dictionary = restored._next_free(restored_caretaker)
			check(not next_dialog.once, "used once-only NPC dialogue stays skipped after Continue")
			restored_caretaker.free_dialogs[0].used = false
			check(not restored_caretaker.interactions[0].then_free_dialogs[0].used,
				"restored active NPC dialogues share once flags with their interaction source")
			check(restored.ui_dialog.visible and restored.ui_text.text == game.G.strings[45],
				"Continue restores current visible dialogue line")
			var saved_npc: Dictionary = restored._npc("8,1", 1)
			restored.target.npc.radius = 17
			check(saved_npc.radius == 17, "target NPC references rebuilt live world dictionary")
			check(npc.radius != 17, "restored NPC is independent of old game instance")
			restored._advance_dialog()
			check(restored.ui_name.text == restored.G.items[15].name, "restored dialogue advances to item description")
		retire(restored)
	game.dialog_lines.clear()
	game.cur_key = "9,2"
	game.target = {kind = "exit", exit = game.scenes["9,2"].exits[1], x = 58.0, then_x = 111.0}
	if persist(game, "save in-flight exit target"):
		var restored = fresh("round_trip.json")
		if check(restored.continue_game(), "restore in-flight exit target"):
			restored.target.exit.open = false
			check(not restored.scenes["9,2"].exits[1].open and restored.target.then_x == 111,
				"target exit references live world and preserves follow-up movement")
		retire(restored)
	retire(game)


func test_mid_action_saves() -> void:
	var game = fresh("mid_action.json")
	idle(game)
	game.cur_key = "2,2"
	game._run_event(1) # Executioner throws devil: saved pose is needed by events 2/3.
	game._process(0.05)
	check(game.ev == 2 and game.saved.size() == 3 and not game.devil.free, "fixture is mid-executioner animation")
	var before := snapshot(game)
	if persist(game, "save during multi-stage event"):
		var restored = fresh("mid_action.json")
		if check(restored.continue_game(), "load during multi-stage event"):
			check(snapshot(restored) == before, "event phase, saved pose and animation frame round trip")
			advance(restored, 15)
			check(restored.cur_key == "3,2" and restored.burn_msg == 45 and not restored.dialog_lines.is_empty(),
				"loaded event completes throw/respawn chain exactly once")
		retire(restored)
	idle(game)
	game.cur_key = "1,0"
	game._arrive({kind = "item", i = 0})
	game._process(0.05)
	if persist(game, "save during item pickup animation"):
		var restored = fresh("mid_action.json")
		if check(restored.continue_game(), "load during item pickup animation"):
			advance(restored)
			check(restored.inv == [15] and restored.scenes["1,0"].floor_items.is_empty()
				and restored.pending_pick == -2, "loaded pickup transfers item exactly once")
			advance(restored)
			check(restored.inv == [15], "further frames do not repeat loaded pickup")
		retire(restored)
	idle(game)
	game.inv = [15, 22]
	game._drop_item(0)
	game._process(0.05)
	if persist(game, "save during selected-slot drop animation"):
		var restored = fresh("mid_action.json")
		if check(restored.continue_game(), "load during selected-slot drop animation"):
			advance(restored)
			check(restored.inv == [22] and restored.scenes["3,2"].floor_items.size() == 1
				and restored.scenes["3,2"].floor_items[0].item == 15,
				"loaded drop retains selected slot and leaves one item")
		retire(restored)
	retire(game)


func test_backup() -> void:
	var game = fresh("backup.json")
	idle(game)
	game.inv = [15]
	var first := snapshot(game)
	persist(game, "write first backup generation")
	game.inv = [22]
	persist(game, "write second backup generation")
	check(FileAccess.file_exists(game.save_path + ".bak"), "second save creates backup")
	write_text(game.save_path, "{interrupted-save")
	var restored = fresh("backup.json")
	if check(restored.continue_game(), "corrupt primary falls back to valid backup"):
		check(snapshot(restored) == first, "backup restores the previous complete state")
	retire(restored)
	game.inv = [10]
	persist(game, "save repairs corrupted primary")
	write_text(game.save_path, "null")
	restored = fresh("backup.json")
	if check(restored.continue_game(), "valid backup survives repair of corrupt primary"):
		check(snapshot(restored) == first, "repair never overwrites valid backup with corrupt primary")
	retire(restored)
	retire(game)


func test_malformed_saves() -> void:
	var game = fresh("malformed.json")
	idle(game)
	game.inv = [15]
	game.target = {kind = "walk", x = 99.0}
	var before := snapshot(game)
	var fixtures := {}
	fixtures["unsupported version"] = before.duplicate(true)
	fixtures["unsupported version"].version = 999
	fixtures["missing state field"] = before.duplicate(true)
	fixtures["missing state field"].erase("souls")
	fixtures["invalid inventory id"] = before.duplicate(true)
	fixtures["invalid inventory id"].inv = [999]
	fixtures["invalid room"] = before.duplicate(true)
	fixtures["invalid room"].cur_key = "99,99"
	fixtures["invalid NPC target"] = before.duplicate(true)
	fixtures["invalid NPC target"].target = {kind = "npc", ref = 999, x = 10}
	fixtures["invalid animation frame"] = before.duplicate(true)
	fixtures["invalid animation frame"].devil.f = 999
	fixtures["incomplete throw event"] = before.duplicate(true)
	fixtures["incomplete throw event"].ev = 2
	fixtures["invalid saved throw animation"] = before.duplicate(true)
	fixtures["invalid saved throw animation"].ev = 2
	fixtures["invalid saved throw animation"].saved = [999, 120, 178]
	fixtures["invalid floor item"] = before.duplicate(true)
	fixtures["invalid floor item"].rooms["3,2"].floor_items = [{item = 15, tx = "bad", ty = 2}]
	fixtures["invalid dialogue"] = before.duplicate(true)
	fixtures["invalid dialogue"].dialog_lines = [{speaker = 4, text = "broken", avatar = 3}]
	fixtures["invalid NPC animation"] = before.duplicate(true)
	fixtures["invalid NPC animation"].rooms["8,1"].npcs[1].actor.anim = 999
	fixtures["invalid NPC dialogue"] = before.duplicate(true)
	fixtures["invalid NPC dialogue"].rooms["9,2"].npcs[0].free_dialogs = [{once = "bad", lines = []}]
	fixtures["invalid soul"] = before.duplicate(true)
	fixtures["invalid soul"].souls = {e = false}
	for label in fixtures:
		write_text(game.save_path, JSON.stringify(fixtures[label]))
		check(not game.continue_game(), "reject " + label)
		check(snapshot(game) == before and game.in_game and not game.menu_open,
			"rejected %s leaves live world unchanged" % label)
	for bad_json in ["{truncated", "null", "[]", '"string"']:
		write_text(game.save_path, bad_json)
		check(not game.continue_game(), "reject invalid JSON root " + bad_json)
		check(snapshot(game) == before, "invalid JSON root leaves world unchanged")
	retire(game)


func test_debug_paths() -> void:
	var game = fresh("", "debug_paths.cfg")
	check(not "debug_open_paths" in game, "wall-walk test mode is removed")
	idle(game)
	game.cur_key = "8,1"
	var guard: Dictionary = game._npc("8,1", 1)
	check(guard.blocker and game._blocked(guard.x), "normal gameplay respects the abbot's passage block")
	game.cur_key = "9,2"
	var gate: Dictionary = game.scenes["9,2"].exits[1]
	var doorway: Vector2 = game._exit_rect(gate).get_center()
	check(not gate.open and not game._exit_open(gate), "normal gate availability uses its saved locked state")
	check(game._hit(doorway).kind != "exit", "locked gate cannot be selected in normal gameplay")
	retire(game)


func test_grave_tap() -> void:
	var game = fresh("", "grave_tap.cfg")
	idle(game)
	game.cur_key = "6,2"
	var anna: Dictionary = game._npc("6,2", 3)
	var hit: Dictionary = game._hit(Vector2(195, 100))  # тап по кресту на могиле
	check(hit.kind == "npc" and hit.npc == anna, "Anna's grave is tappable while her sprite frame is empty")
	for p in [Vector2(176, 120), Vector2(181, 67)]:  # крест и глазок над ним на HD-фоне
		hit = game._hit(p)
		check(hit.kind == "npc" and hit.npc == anna, "HD cross at %s leads to Anna" % p)
	retire(game)


func test_stats() -> void:
	var game = fresh()
	var st = game.stats
	check(not st.enabled, "tests never send stats")
	check(st.id.length() == 32 and st.id.is_valid_hex_number(), "stats id is 32 hex chars")
	var before: float = st.play
	st.tick(st.EVERY - 1, 0)
	check(is_equal_approx(st.play - before, st.EVERY - 1) and st.since_ping > 0, "play time accumulates")
	st.tick(2, 1)
	check(st.since_ping == 0, "ping timer resets after five minutes of play")
	var cert := X509Certificate.new()
	check(cert.load_from_string(st.CERT) == OK, "pinned stats certificate parses")
	retire(game)


func retire(game) -> void:
	game.hide()
	game.game_layer.hide()
	game.menus.hide()
	retired.append(game)


func cleanup() -> void:
	var dir := DirAccess.open(test_dir)
	if dir:
		for file in dir.get_files():
			DirAccess.remove_absolute(test_dir + "/" + file)
		DirAccess.remove_absolute(test_dir)
