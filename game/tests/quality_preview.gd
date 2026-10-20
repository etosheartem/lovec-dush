extends SceneTree
## Render production Main at physical 2560x1440 with its unchanged 1920x1080 canvas.
## godot --path game --rendering-method mobile --script res://tests/quality_preview.gd
## Optional output: -- --screenshots=/tmp/lovec_qhd

const PIXELS := Vector2i(2560, 1440)
const CANVAS := Vector2i(1920, 1080)
var viewport: SubViewport
var game
var screenshots := "/tmp/lovec_qhd"
var failures := 0
var checks := 0


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL quality preview: ", message)


func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture.get_size() == PIXELS, name + " is rendered at 2560x1440 pixels")
	check(game.get_viewport_rect().size == Vector2(CANVAS), name + " retains the 1920x1080 logical canvas")
	check(is_equal_approx(game.KX * game.ROOM_W * game.S, CANVAS.x), name + " retains logical room geometry")
	check(picture.save_png(screenshots.path_join(name + ".png")) == OK, "save " + name)
	print("QHD PREVIEW: ", screenshots.path_join(name + ".png"))


func enter_scene(key: String) -> void:
	game.cur_key = key
	game.menu_open = false
	game.in_game = true
	game.menus.hide()
	# Clean scene previews contain the production world, actors and effects without HUD labels.
	game.game_layer.hide()
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
	var background: Texture2D = game._bg(key)
	check(background.resource_path == "res://assets/hd/scenes/" + key.replace(",", "_") + ".png",
		key + " uses the 2K asset pack")
	check(background.get_size() == Vector2(PIXELS), key + " uses a native 2560x1440 background")


func start() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Quality preview requires a rendering display; omit --headless.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	check(DirAccess.make_dir_recursive_absolute(screenshots) == OK, "create screenshot directory")
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.size_2d_override = CANVAS
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	game.save_path = "user://quality_preview_unused_%d.json" % OS.get_process_id()
	game.settings_path = "user://quality_preview_unused_%d.cfg" % OS.get_process_id()
	viewport.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	check(game.graphics.preset == "maximum", "maximum is the fresh default")
	check(viewport.msaa_2d == Viewport.MSAA_4X, "maximum enables 4x smoothing on the 2K target")
	check(game.menus.screen.get_node("MenuBackground").texture.resource_path == "res://assets/hd/ui/menu_background.png",
		"home uses the 2K background")
	await capture("home")
	enter_scene("9,2")
	await capture("9_2")
	enter_scene("3,2")
	game.scene_effects.advance(2.25)
	await capture("3_2")
	game.pause_game()
	game.menus.show_page("settings")
	game.menus.show_page("graphics")
	await capture("graphics")
	check(Rect2(Vector2.ZERO, CANVAS).encloses(game.menus.panel.get_global_rect()), "graphics panel fits the logical canvas")
	await create_timer(0.5).timeout
	game.sound.shutdown()
	await create_timer(0.5).timeout
	check(not FileAccess.file_exists(game.save_path), "preview does not write progress")
	check(not FileAccess.file_exists(game.settings_path), "preview does not write settings")
	game.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("QUALITY PREVIEW OK: %d checks" % checks if failures == 0 else "QUALITY PREVIEW FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
