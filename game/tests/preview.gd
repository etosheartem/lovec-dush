extends SceneTree
## Render representative screens without touching real saves/settings.
var m

func _initialize() -> void:
	start.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/lovec_" + name + ".png")

func start() -> void:
	m = load("res://main.tscn").instantiate()
	m.persistence_enabled = false
	m.save_path = "user://preview_unused.json"
	m.settings_path = "user://preview_%d.cfg" % OS.get_process_id()
	root.add_child(m)
	await shot("menu")
	m.new_game()
	for i in 150:
		while not m.dialog_lines.is_empty(): m._advance_dialog()
		m._process(0.05)
	m.inv = [15, 22]
	m._refresh_inv()
	await shot("game")
	m._say({lines = [m._line(42, 33, 5)]})
	await shot("dialogue")
	m.pause_game()
	await shot("pause")
	m.menus.show_page("settings")
	await shot("settings")
	m.resume_game()
	m.dialog_lines.clear()
	m.ui_dialog.hide()
	m.cur_key = "9,2"
	m.devil.x = 120
	m.devil.y = 196
	await shot("debug")
	m.set_process(false)
	await create_timer(0.5).timeout
	m.sound.shutdown()
	await create_timer(0.5).timeout
	DirAccess.remove_absolute(m.settings_path)
	m.queue_free()
	await process_frame
	quit()
