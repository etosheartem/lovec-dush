extends SceneTree
## Original glyph coverage, bitmap metrics and actual HD/QHD UI integration.
## godot --headless --path game --script res://tests/font_check.gd
## Render specimens: godot --path game --rendering-method mobile --script res://tests/font_check.gd \
##   -- --screenshots=/tmp/lovec_font

const ArtTheme = preload("res://scripts/art_theme.gd")
const FONT = ArtTheme.TITLE_FONT
const CANVAS := Vector2i(1920, 1080)
var checks := 0
var failures := 0
var screenshots := ""
var viewport: SubViewport
var game


func _initialize() -> void:
	start.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL font: ", message)


func collect_text(value, characters: Dictionary) -> void:
	if value is String:
		for character in value:
			if character not in ["\n", "\r", "\t"]:
				characters[character] = true
	elif value is Dictionary:
		for nested in value.values():
			collect_text(nested, characters)
	elif value is Array:
		for nested in value:
			collect_text(nested, characters)


func check_font() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fonts/original_font.json"))
	var native_size: int = manifest.font_size
	check(ArtTheme.theme().default_font == FONT, "the original font is used for all themed controls")
	check(FONT.resource_path == "res://assets/fonts/original.fnt", "font is the extracted bitmap, not a replacement TTF")
	check(FONT.fixed_size == native_size and FONT.fixed_size_scale_mode == TextServer.FIXED_SIZE_SCALE_ENABLED,
		"original bitmap metrics scale to fractional HD/QHD sizes")
	check(FONT.get_generate_mipmaps(), "font downsampling has mipmaps")
	var originals := 0
	for character in manifest.glyphs:
		var glyph: int = FONT.get_glyph_index(native_size, character.unicode_at(0), 0)
		check(glyph != 0, "font owns glyph U+%04X %s" % [character.unicode_at(0), character])
		var details: Dictionary = manifest.glyphs[character]
		check(is_equal_approx(FONT.get_glyph_advance(0, native_size, glyph).x, float(details.width) * manifest.atlas_scale),
			"original advance retained for " + character)
		if details.has("source"):
			originals += 1
	check(originals == 155, "all 155 distinct original glyphs are retained")
	var alphabet := "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя"
	for character in alphabet + "0123456789.,!?;:()[]{}—–-«»\"'…·%©☰":
		check(manifest.glyphs.has(character) and FONT.get_glyph_index(native_size, character.unicode_at(0), 0) != 0,
			"Russian, numbers and punctuation do not need another font: " + character)
	var game_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/game.json"))
	var characters := {}
	collect_text(game_data, characters)
	for character in characters:
		check(manifest.glyphs.has(character), "every original game text character is in the atlas: " + character)
	for size in [19, 23, 26, 28, 30, 32, 48, 66]:
		check(absf(FONT.get_height(size) - float(manifest.line_height) * size / native_size) < 1.0,
			"line metrics scale predictably at %d" % size)
	check(FONT.get_string_size("iii", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x < FONT.get_string_size("WWW", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x,
		"original proportional widths are retained")
	var texture: Image = FONT.get_texture_image(0, Vector2i(native_size, 0), 0)
	check(texture != null and texture.get_format() == Image.FORMAT_RGBA8, "font retains its colored transparent atlas")
	if texture:
		check(texture.get_pixel(0, 0).a == 0.0, "atlas padding remains transparent")


func capture(name: String) -> void:
	if screenshots.is_empty():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(picture.get_size() == viewport.size, "render has the requested physical pixels: " + name)
	check(picture.save_png(screenshots.path_join(name + ".png")) == OK, "save specimen " + name)


func specimen() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 30
	viewport.add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color("151c19")
	panel.size = CANVAS
	panel.theme = ArtTheme.theme()
	layer.add_child(panel)
	var rows := [
		["Оригинальный шрифт «Ловца душ»", 48],
		["АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ", 38],
		["абвгдеёжзийклмнопрстуфхцчшщъыьэюя", 38],
		["ABCDEFGHIJKLMNOPQRSTUVWXYZ", 38],
		["abcdefghijklmnopqrstuvwxyz 0123456789", 38],
		[".,!?;:()[]{} +−= /\\ — – - «» “ ” „ ' … · %© ☰", 38],
		["Ёж съел ещё этих мягких французских булок, да выпил чаю. Йод. ПОДЪЁМ.", 32],
		["Качество графики · Максимальное · 2К · Высокое · Full HD · Экономное", 28],
		["Музыка 50%     Звуки 70%     Голоса 100%     Далее ›", 23],
	]
	var y := 60.0
	for row in rows:
		var label := Label.new()
		label.text = row[0]
		label.position = Vector2(60, y)
		label.add_theme_font_size_override("font_size", row[1])
		panel.add_child(label)
		y += 105 if row[1] >= 38 else 80
	return layer


func check_live_ui() -> void:
	viewport = SubViewport.new()
	viewport.size = CANVAS
	viewport.size_2d_override = CANVAS
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	game.save_path = "user://font_test_unused_%d.json" % OS.get_process_id()
	game.settings_path = "user://font_test_unused_%d.cfg" % OS.get_process_id()
	viewport.add_child(game)
	game.set_process(false)
	check(game.ui_text.get_theme_font("font") == FONT and game.ui_name.get_theme_font("font") == FONT,
		"dialogue speaker and body use the original font")
	check(game.drop_buttons[0].get_theme_font("font") == FONT, "inventory action uses the original font")
	check(game.hud_status.get_theme_font("font") == FONT,
		"test mode and save-status text also use the original font")
	for control in game.menus.column.get_children():
		if control is Label or control is Button:
			check(control.get_theme_font("font") == FONT, "home text uses the original font: " + control.text)
	var card := specimen()
	for physical in [CANVAS, Vector2i(2560, 1440)]:
		viewport.size = physical
		await capture("%d_glyphs" % physical.y)
	card.free()
	game.new_game()
	game.cur_key = "3,2"
	game.ev = -1
	game.devil.x = 145
	game.devil.y = 196
	game.devil.play(0)
	game._process(0.0)
	game.cam.force_update_scroll()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/voice/manifest.json"))
	var longest := ""
	for line in manifest.values():
		if line.text.length() > longest.length():
			longest = line.text
	for physical in [CANVAS, Vector2i(2560, 1440)]:
		viewport.size = physical
		for long_line in [false, true]:
			game._say({lines = [{speaker = "Чёрт", avatar = 3,
				text = longest if long_line else "Ёж съел ещё этих мягких французских булок, да выпил чаю. Йод. ПОДЪЁМ — 100%."}]})
			await process_frame
			await process_frame
			check(Rect2(Vector2.ZERO, CANVAS).encloses(game.ui_dialog.get_global_rect()), "dialogue fits at physical height %d" % physical.y)
			var hint: Label = game.ui_dialog.get_children().back()
			check(game.ui_text.get_global_rect().end.y <= hint.get_global_rect().position.y,
				"original font does not overlap the tap hint at height %d" % physical.y)
			await capture("%d_%s_dialogue" % [physical.y, "long" if long_line else "short"])
	await create_timer(0.5).timeout
	game.sound.shutdown()
	await create_timer(0.5).timeout
	check(not FileAccess.file_exists(game.save_path) and not FileAccess.file_exists(game.settings_path), "font test does not write user progress/settings")
	game.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame


func start() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	if not screenshots.is_empty():
		if DisplayServer.get_name() == "headless":
			printerr("Font screenshots require a display; omit --headless.")
			quit(1)
			return
		check(DirAccess.make_dir_recursive_absolute(screenshots) == OK, "create specimen directory")
	check_font()
	await check_live_ui()
	print("FONT OK: %d checks" % checks if failures == 0 else "FONT FAILED: %d/%d" % [failures, checks])
	quit(1 if failures else 0)
