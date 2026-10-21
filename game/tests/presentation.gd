extends SceneTree
## Viewport, touch, typography and silhouette regression checks.
## Headless: godot --headless --path game --script res://tests/presentation.gd
## With pixel checks and PNGs: godot --path game --rendering-method gl_compatibility \
##   --script res://tests/presentation.gd -- --screenshots=/tmp/lovec_presentation

const WIDTHS := [1920, 2400, 2520] # 16:9, 20:9, 21:9 at the same physical world height.
const HEIGHT := 1080
var checks := 0
var failures := 0
var viewport: SubViewport
var game
var screenshots := ""
var can_render := false
var silhouette_reference := {}


class ActorProbe extends "res://main.gd":
	var subject

	func _ready() -> void:
		# Only the actual production actor drawing and viewport fitting are needed here.
		G = JSON.parse_string(FileAccess.get_file_as_string("res://assets/game.json"))
		SPR = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sprites/sprites.json"))
		_reset_world()
		hd = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hd/hd.json"))
		cam = Camera2D.new()
		add_child(cam)
		get_viewport().size_changed.connect(_fit_room_to_viewport)
		_fit_room_to_viewport()
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)

	func _draw() -> void:
		if subject:
			_draw_actor(subject, _room().x * ROOM_W)


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL presentation: ", message)


func settle_layout() -> void:
	await process_frame
	await process_frame


func capture(name: String) -> Image:
	if not can_render:
		return null
	await settle_layout()
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if not screenshots.is_empty():
		check(picture.save_png(screenshots.path_join(name + ".png")) == OK, "write screenshot " + name)
	return picture


func start() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	can_render = DisplayServer.get_name() != "headless"
	if not screenshots.is_empty():
		check(DirAccess.make_dir_recursive_absolute(screenshots) == OK, "create screenshot directory")
		check(can_render, "screenshots require a rendering display, omit --headless")
	viewport = SubViewport.new()
	viewport.size = Vector2i(WIDTHS[0], HEIGHT)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	game.save_path = "user://presentation_unused_%d.json" % OS.get_process_id()
	game.settings_path = "user://presentation_unused_%d.cfg" % OS.get_process_id()
	viewport.add_child(game)
	game.set_process(false)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/voice/manifest.json"))
	for width in WIDTHS:
		viewport.size = Vector2i(width, HEIGHT)
		await settle_layout()
		await check_world(width)
		await check_pages(width)
		await check_dialogues(width, manifest)
	# Do not let scene processing enqueue more sounds while the audio thread drains.
	game.set_process(false)
	await create_timer(0.5).timeout
	game.sound.shutdown()
	await create_timer(0.5).timeout
	game.queue_free()
	await process_frame
	if can_render:
		await check_silhouettes()
	else:
		print("PRESENTATION: pixel silhouette checks skipped in headless mode")
	viewport.queue_free()
	await process_frame
	if failures:
		printerr("PRESENTATION FAILED: %d / %d checks" % [failures, checks])
	else:
		print("PRESENTATION OK: %d checks, 16:9 / 20:9 / 21:9" % checks)
	quit(1 if failures else 0)


func enter_scene(key: String) -> void:
	game.cur_key = key
	game.menu_open = false
	game.in_game = true
	game.menus.hide()
	game.game_layer.show()
	game.dialog_lines.clear()
	game.ui_dialog.hide()
	game.ev = -1
	game.pending_pick = -2
	game.target = {}
	game.devil.x = 120
	game.devil.y = 196
	game.devil.play(0)
	game._process(0.0)
	game.cam.force_update_scroll()
	await settle_layout()


func check_world(width: int) -> void:
	check(is_equal_approx(game.KX * game.ROOM_W * game.S, width), "room follows viewport width %d" % width)
	for key in ["3,2", "5,2", "8,1", "9,2", "0,0"]:
		await enter_scene(key)
		var room_x: float = game._room().x * game.ROOM_W
		var transform: Transform2D = game.get_canvas_transform()
		var left: Vector2 = transform * Vector2(room_x * game.KX * game.S, 0)
		var right: Vector2 = transform * Vector2((room_x + game.ROOM_W) * game.KX * game.S, HEIGHT)
		check(left.distance_to(Vector2.ZERO) < 0.02, "room left/top covers viewport %s at %d: %s" % [key, width, left])
		check(right.is_equal_approx(Vector2(width, HEIGHT)), "room right/bottom covers viewport %s at %d" % [key, width])
		if key in ["3,2", "5,2"]:
			for exit in game.scenes[key].exits:
				# Screen fractions are independent of the camera's inverse transform implementation.
				var pixel := Vector2(clampf(exit.x, 8, 232) / 240.0 * width, (exit.y - 40) / 210.0 * HEIGHT)
				var click := InputEventMouseButton.new()
				click.pressed = true
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = pixel
				game._unhandled_input(click)
				check(game.target.get("kind") == "exit" and game.target.get("exit", {}).get("to") == exit.to,
					"screen tap reaches %s side exit %s at %d" % [key, exit.to, width])
		if key == "3,2":
			var ground := InputEventMouseButton.new()
			ground.pressed = true
			ground.button_index = MOUSE_BUTTON_LEFT
			ground.position = Vector2(width * 0.6, HEIGHT * 0.5)
			game._unhandled_input(ground)
			check(game.target.get("kind") == "walk" and is_equal_approx(game.target.x, 144),
				"ground tap maps to original world coordinates at %d" % width)
		if key == "9,2":
			check_entrances(width)
		if key != "5,2":
			await capture("%d_scene_%s" % [width, key.replace(",", "_")])


func check_entrances(width: int) -> void:
	# Samples cover the painted openings: low cellar grille and recessed right entrance.
	# These screen taps deliberately do not call the production hit-rectangle helper.
	var samples := [
		[Vector2(38, 120), Vector2(76, 120), Vector2(38, 151), Vector2(76, 151), Vector2(58, 140)],
		[Vector2(204, 70), Vector2(234, 70), Vector2(204, 176), Vector2(234, 176), Vector2(219, 120)]
	]
	for index in [1, 2]:
		var entrance: Dictionary = game.scenes["9,2"].exits[index]
		var original_open: bool = entrance.open
		var door_spot: Dictionary = game.scenes["9,2"].npcs[index - 1]  # хотспот на этой двери
		for unlocked in [false, true]:
			entrance.open = unlocked
			for a in door_spot.interactions:  # дверь открывается только его же действием (ключ от подвала)
				a.done = unlocked
			for point in samples[index - 1]:
				var click := InputEventMouseButton.new()
				click.pressed = true
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = Vector2(point.x / 240.0 * width, point.y / 210.0 * HEIGHT)
				game._unhandled_input(click)
				if unlocked:
					check(game.target.get("kind") == "exit" and game.target.get("exit", {}).get("to") == entrance.to,
						"open entrance %d tap %s at %d" % [index, point, width])
				else:
					check(game.target.get("kind") == "npc" and game.target.get("npc", {}).get("x") == (58 if index == 1 else 210),
						"closed entrance %d tap %s at %d" % [index, point, width])
		entrance.open = original_open
		for a in door_spot.interactions:
			a.done = false


func check_pages(width: int) -> void:
	game.menus.update = {version = "9.99", url = ""}
	game.menus.choice_options = ["«...А нечего было шутить!»", "«...Так я ж её и рассказываю!»", "«...Повесить ещё раз!»"]
	game.menus.choice_question = "Черт: Приходит висельник к королю: «Помилуйте, ваше величество!» — «А за что тебя повесили?» — «За шутку о вас». — «Ну-ка, расскажи...» А висельник ему..."
	game.menus._update_shown = true
	for page in ["home", "pause", "settings", "credits", "help", "confirm_new", "update", "sequel", "choice"]:
		game.menus.show_page(page)
		game.menus.message("Не удалось сохранить игру. Проверь свободное место.")
		await settle_layout()
		var available := Rect2(Vector2.ZERO, viewport.size)
		check(available.encloses(game.menus.panel.get_global_rect()), "menu/status fits: %s at %d" % [page, width])
		if page == "home":
			var devil: TextureRect = game.menus.screen.get_node("MenuDevil")
			check(devil.get_global_rect().end.x < game.menus.panel.get_global_rect().position.x,
				"home character has room beside menu at %d" % width)
			check(devil.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
				"home character preserves silhouette at %d" % width)
		if page in ["home", "settings"]:
			await capture("%d_%s" % [width, page])


func check_dialogues(width: int, manifest: Dictionary) -> void:
	await enter_scene("3,2")
	game.ui_avatar.texture = game._tex("avatars/5")
	var longest := ""
	for line in manifest.values():
		game.ui_name.text = line.speaker
		game.ui_text.text = line.text
		game.ui_dialog.show()
		await settle_layout()
		var hint: Label = game.ui_dialog.get_children().back()
		check(game.ui_text.get_global_rect().end.y <= hint.get_global_rect().position.y,
			"dialogue remains above tap hint at %d: %s" % [width, line.text.left(32)])
		check(Rect2(Vector2.ZERO, viewport.size).encloses(game.ui_dialog.get_global_rect()),
			"dialogue panel fits viewport at %d: %s" % [width, line.text.left(32)])
		if line.text.length() > longest.length():
			longest = line.text
	game.ui_name.text = "Алхимик"
	game.ui_text.text = longest
	await capture("%d_long_dialogue" % width)


func check_silhouettes() -> void:
	viewport.transparent_bg = true
	var probe := ActorProbe.new()
	viewport.add_child(probe)
	var actors := {"devil": probe.devil}
	for scene in probe.scenes.values():
		for npc in scene.npcs:
			if npc.has("actor") and npc.sheet != "objects":
				actors[npc.sheet] = npc.actor
	for width in WIDTHS:
		viewport.size = Vector2i(width, HEIGHT)
		await settle_layout()
		probe.cam.force_update_scroll()
		for actor_name in actors:
			probe.subject = actors[actor_name]
			probe.subject.x = 120
			probe.subject.y = 196
			probe.queue_redraw()
			var picture: Image = await capture("%d_actor_%s" % [width, actor_name])
			var bounds := picture.get_used_rect()
			check(bounds.has_area(), "rendered %s silhouette at %d" % [actor_name, width])
			check(bounds.position.x > 0 and bounds.end.x < width and bounds.position.y >= 0 and bounds.end.y <= HEIGHT,
				"whole %s silhouette is visible at %d" % [actor_name, width])
			if not silhouette_reference.has(actor_name):
				silhouette_reference[actor_name] = bounds
			else:
				var reference: Rect2i = silhouette_reference[actor_name]
				check(bounds.size == reference.size and bounds.position.y == reference.position.y,
					"%s head, feet and width unchanged at %d: %s vs %s" % [actor_name, width, bounds, reference])
	probe.queue_free()
	await process_frame
