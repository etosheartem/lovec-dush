extends SceneTree
## Menu-only fixtures never read or write player saves/settings and never start audio.
## Add --screenshots=/tmp/menu_fx to a rendered run for visual evidence.

const GameMenu = preload("res://scripts/game_menu.gd")
const MenuEffects = preload("res://scripts/menu_effects.gd")
var checks := 0
var failures := 0
var screenshots := ""


class GraphicsFixture extends RefCounted:
	signal changed
	var effects_level := 2
	var texture_root := "res://assets/hd"
	func select(level: int) -> void:
		effects_level = level
		changed.emit()


class AudioFixture extends RefCounted:
	func effect(_key: String) -> void:
		pass


class GameFixture extends RefCounted:
	var graphics = GraphicsFixture.new()
	var sound = AudioFixture.new()
	var G := {"strings": ["Продолжить", "Новая игра", "Помощь", "Настройки", "Об авторах", "Выход"]}
	var in_game := false
	func has_save() -> bool:
		return false
	func continue_game() -> void:
		pass
	func new_game() -> void:
		pass
	func quit_game() -> void:
		pass


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL menu effects: ", message)


func start() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	if not screenshots.is_empty():
		DirAccess.make_dir_recursive_absolute(screenshots)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var menu = GameMenu.new()
	menu.game = GameFixture.new()
	viewport.add_child(menu)
	menu.show_page("home")
	menu.set_process(false)
	await process_frame
	check(menu.home_effects != null, "home creates its decorative layer")
	var fx = menu.home_effects
	check(fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "decorative layer ignores clicks")
	check(fx.get_index() < menu.screen.get_node("MenuDevil").get_index(), "effects remain in the room behind hero and panel")
	check(fx.get_child_count() == 0 and not fx.is_processing(), "no emitter nodes or independent clocks")
	check(fx.art_point(Vector2(128, 325)).is_equal_approx(Vector2(160, 406.25)), "candle position follows aspect-cover art")
	var hero: TextureRect = menu.screen.get_node("MenuDevil")
	var hero_origin := hero.position
	var hero_size := hero.size
	var panel_rect: Rect2 = menu.panel.get_global_rect()
	var button: Button = menu.column.get_child(2)
	var button_rect := button.get_global_rect()
	var button_text := button.text
	menu._process(1.4)
	check(is_equal_approx(fx.elapsed, 1.4), "active home advances explicit time")
	check(hero.position != hero_origin and hero.size.is_equal_approx(hero_size), "hero translates rigidly without deformation")
	check(menu.panel.get_global_rect() == panel_rect and button.get_global_rect() == button_rect and button.text == button_text,
		"panel, button and label remain stationary")
	fx.advance(0)
	fx.advance(-1)
	fx.advance(NAN)
	check(is_equal_approx(fx.elapsed, 1.4), "invalid time does not animate")
	menu.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	menu._process(3)
	check(is_equal_approx(fx.elapsed, 1.4) and not menu.is_processing(), "application pause freezes animation and processing")
	menu.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	menu.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	menu._process(3)
	check(is_equal_approx(fx.elapsed, 1.4) and not menu.is_processing(), "lost focus / minimized application freezes animation")
	menu.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	menu.set_process(false)
	menu._process(0.2)
	check(is_equal_approx(fx.elapsed, 1.6), "resume continues without a wall-clock jump")
	menu.hide()
	check(menu.home_effects == null and not menu.is_processing(), "hidden home releases effects and processing")
	check(hero.position.is_equal_approx(hero_origin) and hero.modulate == Color.WHITE, "hide restores all hero properties")
	await process_frame
	check(not is_instance_valid(fx), "hidden effects node is freed")
	menu.show()
	menu.set_process(false)
	check(menu.home_effects != null and menu.home_effects.elapsed == 0, "show recreates one fresh effect layer")
	menu.show_page("credits")
	check(menu.home_effects == null and not menu.is_processing(), "leaving home stops and releases effects")
	menu.show_page("home")
	menu.set_process(false)
	var child_count: int = menu.screen.get_child_count()
	for index in 8:
		menu.show_page("credits")
		menu.show_page("home")
		menu.set_process(false)
		check(menu.screen.get_child_count() == child_count, "page changes never accumulate effect nodes: %d" % index)
	for level in [0, 1, 2]:
		menu.game.graphics.select(level)
		menu.set_process(false)
		check((menu.home_effects == null) == (level == 0), "economy removes the effect layer: %d" % level)
		if level > 0:
			check(menu.home_effects.quality == level, "quality change applies immediately: %d" % level)
			var origin: Vector2 = menu.screen.get_node("MenuDevil").position
			menu._process(1)
			check((menu.screen.get_node("MenuDevil").position != origin) == (level == 2), "rigid hero motion is maximum only: %d" % level)
	if DisplayServer.get_name() != "headless":
		await check_pixels(viewport, menu)
	else:
		print("MENU EFFECTS: pixel checks skipped in headless mode")
	menu.hide()
	viewport.queue_free()
	await process_frame
	print("MENU EFFECTS OK: %d checks" % checks if failures == 0 else "MENU EFFECTS FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)


func capture(viewport: SubViewport, name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	if not screenshots.is_empty() and not name.is_empty():
		picture.save_png(screenshots.path_join(name + ".png"))
	return picture


func check_pixels(viewport: SubViewport, menu: CanvasLayer) -> void:
	var profiles := []
	for level in [0, 1, 2]:
		menu.game.graphics.select(level)
		menu.set_process(false)
		if level > 0:
			menu.home_effects.advance(2.0)
		profiles.append(await capture(viewport, "home_quality_%d" % level))
	check(profiles[0].get_data() != profiles[1].get_data(), "candle light actually renders at quality 1")
	check(profiles[1].get_data() != profiles[2].get_data(), "maximum decoration actually renders")
	menu.home_effects.restore_hero()
	var dust := await capture(viewport, "")
	menu.home_effects.configure(1)
	var no_dust := await capture(viewport, "")
	check(dust.get_data() != no_dust.get_data(), "dust particles render independently of hero movement and candle light")
	menu.home_effects.configure(2, menu.screen.get_node("MenuDevil"))
	menu.home_effects.advance(0.01)
	# The unobscured outer-left flame demonstrates real candle flicker, independently of hero motion.
	var before := await capture(viewport, "")
	menu.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(0.15).timeout
	var paused := await capture(viewport, "home_paused")
	check(before.get_data() == paused.get_data(), "application pause freezes every rendered pixel")
	menu.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	menu.set_process(false)
	menu.home_effects.advance(2.3)
	var moved := await capture(viewport, "home_advanced")
	check(before.get_data() != moved.get_data(), "explicit advance animates actual pixels")
	check(before.get_region(Rect2i(65, 410, 75, 90)).get_data() != moved.get_region(Rect2i(65, 410, 75, 90)).get_data(),
		"painted candle light visibly changes at its real location")
	menu.game.graphics.select(0)
	menu.set_process(false)
	var economy := await capture(viewport, "")
	await create_timer(0.15).timeout
	check(economy.get_data() == (await capture(viewport, "")).get_data(), "economy renders a genuinely static menu")
	menu.game.graphics.select(2)
	menu.set_process(false)
	viewport.size = Vector2i(2400, 1080)
	await process_frame
	check(menu.home_effects.art_point(Vector2(128, 325)).is_equal_approx(Vector2(200, 372.8125)), "wide-screen candle anchors account for vertical crop")
	var wide := await capture(viewport, "home_20x9")
	check(wide.get_size() == Vector2i(2400, 1080), "wide screen renders at native viewport size")
	viewport.size = Vector2i(960, 540)
	await process_frame
	check(menu.home_effects.art_point(Vector2(128, 325)).is_equal_approx(Vector2(80, 203.125)), "half-size candles follow background resize")
	await capture(viewport, "home_half_size")
	# Both packs share the same composition; anchor math is independent of texture resolution.
	menu.game.graphics.texture_root = "res://assets/hd"
	menu.show_page("home")
	menu.set_process(false)
	check(menu.screen.get_node("MenuBackground").texture.get_width() == 2560, "maximum pack loads real QHD menu art")
	viewport.size = Vector2i(1920, 1080)
	await capture(viewport, "home_qhd")
