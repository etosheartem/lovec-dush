extends SceneTree
## Isolated graphics persistence and live asset/profile integration checks.
## godot --headless --path game --script res://tests/graphics.gd

const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const SaveStore = preload("res://scripts/save_store.gd")
var checks := 0
var failures := 0
var test_dir: String
var emissions := 0


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL graphics: ", message)


func fresh(filename: String):
	var settings = GraphicsSettings.new()
	settings.settings_path = test_dir.path_join(filename)
	root.add_child(settings)
	return settings


func start() -> void:
	test_dir = "user://graphics_regression_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(test_dir) == OK, "create isolated settings directory")
	check_profiles_and_persistence()
	await check_live_game()
	var directory := DirAccess.open(test_dir)
	if directory:
		for filename in directory.get_files():
			DirAccess.remove_absolute(test_dir.path_join(filename))
		DirAccess.remove_absolute(test_dir)
	if failures:
		printerr("GRAPHICS FAILED: %d / %d checks" % [failures, checks])
	else:
		print("GRAPHICS OK: %d checks" % checks)
	quit(1 if failures else 0)


func check_profiles_and_persistence() -> void:
	var settings = fresh("quality.cfg")
	check(settings.preset == "maximum", "new profile defaults to maximum")
	check(settings.texture_root == "res://assets/hd" and settings.effects_level == 2 and settings.msaa_2d == Viewport.MSAA_4X,
		"maximum selects 2K assets, full effects and 4x edge smoothing")
	check(not FileAccess.file_exists(settings.settings_path), "loading defaults does not write a settings file")
	settings.changed.connect(func(): emissions += 1)
	check(settings.set_preset("high", false), "select high without persisting")
	check(settings.texture_root == "res://assets/hd" and settings.effects_level == 1 and settings.msaa_2d == Viewport.MSAA_2X,
		"high selects HD assets, moderate effects and 2x edge smoothing")
	check(emissions == 1 and not FileAccess.file_exists(settings.settings_path), "one change signal and no write for transient profile")
	check(settings.set_preset("high", false) and emissions == 1, "selecting current profile does not emit a false change")
	check(not settings.set_preset("ultra", false) and settings.preset == "high" and emissions == 1,
		"unknown profile is rejected without changing active quality")
	var existing := ConfigFile.new()
	existing.set_value("audio", "music", 0.37)
	existing.set_value("audio", "voice", 0.62)
	existing.set_value("debug", "open_paths", true)
	existing.set_value("other", "keep", "untouched")
	check(existing.save(settings.settings_path) == OK, "create mixed settings fixture")
	check(settings.set_preset("economy"), "persist economy")
	check(settings.texture_root == "res://assets/hd" and settings.effects_level == 0 and settings.msaa_2d == Viewport.MSAA_DISABLED,
		"economy actually disables optional effects and edge smoothing")
	var saved := ConfigFile.new()
	check(saved.load(settings.settings_path) == OK, "read persisted settings")
	check(saved.get_value("audio", "music") == 0.37 and saved.get_value("audio", "voice") == 0.62,
		"graphics write preserves audio levels")
	check(saved.get_value("debug", "open_paths") == true and saved.get_value("other", "keep") == "untouched",
		"graphics write preserves debug and unrelated sections")
	var restored = fresh("quality.cfg")
	check(restored.preset == "economy" and restored.effects_level == 0, "quality survives reload")
	for malformed in ["unknown_profile", 12, true]:
		saved.set_value("graphics", "preset", malformed)
		saved.save(settings.settings_path)
		check(not restored.load_settings() and restored.preset == "maximum", "invalid stored profile defaults to maximum: %s" % malformed)
		check(restored.texture_root == "res://assets/hd" and restored.effects_level == 2,
			"invalid stored profile cannot desynchronize assets/effects")
	check(restored.save_settings(), "explicit save persists a normalized profile")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	for preset_id in ["maximum", "high", "economy"]:
		restored.set_preset(preset_id, false)
		restored.apply_viewport(viewport)
		check(viewport.msaa_2d == restored.msaa_2d, "viewport applies %s edge smoothing" % preset_id)
		check(viewport.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			and restored.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "mipmap filtering applies for %s" % preset_id)
		check(viewport.size == Vector2i(1920, 1080), "quality never changes canvas size for %s" % preset_id)
	viewport.free()
	settings.free()
	restored.free()


func check_live_game() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	game.save_path = test_dir.path_join("unused_progress.json")
	game.settings_path = test_dir.path_join("integration.cfg")
	viewport.add_child(game)
	game.set_process(false)
	var graphics = game.get("graphics")
	check(graphics != null, "main exposes its graphics settings")
	if graphics != null:
		check(graphics.preset == "maximum", "live game defaults to maximum quality")
		check(game.menus.screen.get_node("MenuBackground").texture.resource_path == "res://assets/hd/ui/menu_background.png",
			"home loads the actual 2K background by default")
		var expected_geometry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hd/hd.json"))
		game.new_game()
		game.inv = [15, 22]
		game._refresh_inv()
		game._say({lines = [game._line(42, 33, 5)]})
		await process_frame
		await process_frame
		var original_lines: Array = game.dialog_lines.duplicate(true)
		var original_state: Dictionary = SaveStore.capture(game)
		var original_voice_id: int = game.sound.voice.get_stream_playback().get_instance_id() if game.sound.voice.playing else 0
		check(original_voice_id != 0, "dialogue voice is actively playing before quality changes")
		# Opening settings pauses a live voice. Keep that state while loading large textures.
		game.sound.pause_voice(true)
		for preset_id in ["high", "maximum", "economy"]:
			check(graphics.set_preset(preset_id), "live switch to " + preset_id)
			await process_frame
			await process_frame
			var expected_root: String = "res://assets/hd"  # один набор 2К на все режимы
			check(viewport.msaa_2d == graphics.msaa_2d, "live viewport smoothing updates for " + preset_id)
			check(game.scene_effects.quality == graphics.effects_level and game.actor_shadows.quality == graphics.effects_level,
				"live ambience and actor shadows apply the selected effects level for " + preset_id)
			check(viewport.size == Vector2i(1920, 1080), "live switch preserves logical canvas for " + preset_id)
			check(game.hd == expected_geometry, "asset packs preserve every actor canvas and anchor for " + preset_id)
			check(SaveStore.capture(game) == original_state, "quality switch preserves all progression and actor state for " + preset_id)
			check(game.ui_slots[0].texture_normal.resource_path == expected_root + "/artifacts/15.png",
				"occupied inventory reloads correct asset pack for " + preset_id)
			check(game.ui_avatar.texture.resource_path == expected_root + "/avatars/5.png",
				"visible dialogue portrait reloads correct asset pack for " + preset_id)
			var background: Texture2D = game._bg("3,2")
			check(background.resource_path == expected_root + "/scenes/3_2.png",
				"room reloads correct asset pack for " + preset_id)
			check(background.get_size() == Vector2(2560, 1440),
				"room uses the advertised pixel dimensions for " + preset_id)
			check(game.ui_dialog.visible and game.dialog_lines == original_lines, "quality switch preserves active dialogue for " + preset_id)
			# A paused AudioStreamPlayer reports playing=false while retaining its playback.
			var voice_id: int = game.sound.voice.get_stream_playback().get_instance_id() if game.sound.voice.has_stream_playback() else 0
			check(voice_id == original_voice_id and voice_id != 0, "quality switch does not restart the voice playback for " + preset_id)
			check(game.sound.voice.stream_paused, "quality switch preserves settings-menu voice pause for " + preset_id)
		game._go([5, 2], [25, 178])
		game._bg("5,2")
		check(not game.tex_cache.has("res://assets/hd/scenes/3_2.png") and game.tex_cache.has("res://assets/hd/scenes/5_2.png"),
			"travelling releases the previous room's texture cache entry")
		var room_paths: Array = game.tex_cache.keys().filter(func(path): return str(path).contains("/scenes/"))
		check(room_paths.size() == 1, "only the active room stays in the large background cache")
		check(game.tex_cache.has("res://assets/hd/artifacts/15.png"), "room cache eviction preserves inventory textures")
		game.menus.show_page("home")
		game.menus.show_page("settings")
		game.menus.show_page("graphics")
		game.menus.back()
		check(game.menus.page == "settings", "Back from quality returns to settings")
		game.menus.back()
		check(game.menus.page == "home", "nested quality page preserves home return target")
		for page in ["settings", "graphics"]:
			game.menus.show_page(page)
			game.menus.message("Не удалось сохранить настройки. Попробуй ещё раз.")
			await process_frame
			await process_frame
			check(Rect2(Vector2.ZERO, viewport.size).encloses(game.menus.panel.get_global_rect()),
				"quality controls and errors fit 1080-high " + page)
	game.set_process(false)
	await create_timer(0.5).timeout
	game.sound.shutdown()
	await create_timer(0.5).timeout
	game.queue_free()
	await process_frame
	check(not FileAccess.file_exists(test_dir.path_join("unused_progress.json")), "integration never writes player progress")
	viewport.queue_free()
	await process_frame
