extends CanvasLayer
## Menus stay responsive while the world is paused by Main.

const ArtTheme = preload("res://scripts/art_theme.gd")
const MenuEffects = preload("res://scripts/menu_effects.gd")

var game
var screen: Control
var column: VBoxContainer
var page := "home"
var back_page := "home"
var status: Label
var panel: PanelContainer
var home_effects: Control
var _application_suspended := false
var _focus_lost := false


func _ready() -> void:
	layer = 20
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen.theme = ArtTheme.theme()
	add_child(screen)
	visibility_changed.connect(_menu_visibility_changed)
	var graphics = game.get("graphics")
	if graphics != null:
		graphics.changed.connect(_refresh_home_effects)
	set_process(false)


func _process(dt: float) -> void:
	if _can_animate():
		home_effects.advance(dt)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_application_suspended = true
		NOTIFICATION_APPLICATION_RESUMED:
			_application_suspended = false
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focus_lost = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focus_lost = false
		_:
			return
	set_process(_can_animate())


func _can_animate() -> bool:
	return visible and page == "home" and is_instance_valid(home_effects) and not _application_suspended and not _focus_lost


func _menu_visibility_changed() -> void:
	if not visible:
		_release_home_effects()
	elif page == "home":
		_refresh_home_effects()


func _release_home_effects() -> void:
	set_process(false)
	if is_instance_valid(home_effects):
		home_effects.restore_hero()
		home_effects.get_parent().remove_child(home_effects)
		home_effects.queue_free()
	home_effects = null


func _refresh_home_effects() -> void:
	_release_home_effects()
	if not is_instance_valid(screen) or not visible or page != "home":
		return
	var graphics = game.get("graphics")
	var level: int = graphics.effects_level if graphics != null else 2
	var background := screen.get_node_or_null("MenuBackground") as TextureRect
	if level == 0 or background == null or background.texture == null:
		return
	home_effects = MenuEffects.new()
	screen.add_child(home_effects)
	# Both candles and dust belong to the painted room, behind the hero, shade and controls.
	screen.move_child(home_effects, background.get_index() + 1)
	home_effects.configure(level, screen.get_node_or_null("MenuDevil") as TextureRect)
	set_process(_can_animate())


func _backdrop() -> void:
	if page == "home":
		var background_path := _ui_art("menu_background.png")
		var devil_path := _ui_art("menu_devil.png")
		var background := TextureRect.new()
		background.name = "MenuBackground"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(background_path):
			background.texture = load(background_path)
		screen.add_child(background)
		# The gradient supplies a legible menu region and a quiet fallback before art imports.
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.05, 0.075, 0.073, 0.32))
		gradient.set_color(1, Color(0.025, 0.04, 0.04, 0.80))
		var gradient_texture := GradientTexture2D.new()
		gradient_texture.gradient = gradient
		var overlay := TextureRect.new()
		overlay.name = "MenuShade"
		overlay.texture = gradient_texture
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(overlay)
		if ResourceLoader.exists(devil_path):
			var devil := TextureRect.new()
			devil.name = "MenuDevil"
			devil.texture = load(devil_path)
			devil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			devil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			devil.anchor_left = 0.06
			devil.anchor_right = 0.48
			devil.anchor_top = 0.07
			devil.anchor_bottom = 0.96
			devil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			screen.add_child(devil)
		_refresh_home_effects()
	else:
		var shade := ColorRect.new()
		shade.color = Color(0.025, 0.038, 0.036, 0.82)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.add_child(shade)


func _ui_art(filename: String) -> String:
	var graphics = game.get("graphics")
	if graphics != null:
		var path: String = graphics.texture_root.path_join("ui").path_join(filename)
		if ResourceLoader.exists(path):
			return path
	return "res://assets/hd/ui/" + filename


func _base(title: String) -> void:
	_release_home_effects()
	for child in screen.get_children():
		screen.remove_child(child)
		child.queue_free()
	_backdrop()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if page == "home":
		center.anchor_left = 0.51
		center.anchor_right = 0.97
	else:
		center.offset_left = 32
		center.offset_right = -32
	center.offset_top = 26
	center.offset_bottom = -26
	screen.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 710 if page == "home" else 860
	var style := ArtTheme.panel(Color(0.065, 0.085, 0.079, 0.92), ArtTheme.EDGE, 36)
	style.content_margin_top = 34
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_override("font", ArtTheme.TITLE_FONT)
	heading.add_theme_font_size_override("font_size", 66 if page == "home" else 48)
	heading.add_theme_color_override("font_color", Color("e3c58e"))
	column.add_child(heading)
	ArtTheme.decorate(panel)
	status = null


func _text(value: String, size := 28) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 638 if page == "home" else 788
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ArtTheme.MUTED)
	column.add_child(label)
	return label


func _button(text: String, action: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 76
	button.disabled = disabled
	button.pressed.connect(func():
		game.sound.effect("click")
		action.call())
	column.add_child(button)
	return button


func show_page(next_page: String) -> void:
	if next_page in ["settings", "credits", "help", "confirm_new"] and page in ["home", "pause"]:
		back_page = page
	page = next_page
	visible = true
	match page:
		"home":
			_base("ЛОВЕЦ ДУШ")
			var subtitle := _text("Три души. Одна сделка.", 25)
			subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			subtitle.custom_minimum_size.y = 46
			_button(game.G.strings[0], game.continue_game, not game.has_save())
			_button(game.G.strings[1], _request_new)
			_button(game.G.strings[3], func(): show_page("settings"))
			_button(game.G.strings[2], func(): show_page("help"))
			_button(game.G.strings[4], func(): show_page("credits"))
			_button(game.G.strings[5], game.quit_game)
		"pause":
			_base("Пауза")
			_text("Собрано душ: %d из 3" % game.souls.size()).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_button("Вернуться в игру", game.resume_game)
			_button("Сохранить игру", func():
				var ok: bool = game.save_game()
				message("Игра сохранена" if ok else "Не удалось сохранить игру"))
			_button("Настройки", func(): show_page("settings"))
			_button("Помощь", func(): show_page("help"))
			_button("Главное меню", game.return_home)
		"settings":
			_base("Настройки")
			for key in ["music", "effects", "voice"]:
				_volume(key, {"music": "Музыка", "effects": "Звуки и атмосфера", "voice": "Голоса"}[key])
			_text("0% — выключить звук. Изменения сохраняются сразу.", 23)
			_button("Качество графики", func(): show_page("graphics"), game.get("graphics") == null)
			_button("Назад", back)
		"graphics":
			_base("Качество графики")
			var graphics = game.get("graphics")
			if graphics != null:
				for preset_id in ["maximum", "high", "economy"]:
					var button := _button(graphics.PROFILES[preset_id].label, _select_graphics.bind(preset_id))
					button.toggle_mode = true
					button.button_pressed = graphics.preset == preset_id
					if button.button_pressed:
						button.add_theme_color_override("font_pressed_color", ArtTheme.BRASS)
					_text({
						"maximum": "Самые детальные изображения, все эффекты и плавные края.",
						"high": "Изображения Full HD, умеренные эффекты и плавные края.",
						"economy": "Изображения Full HD, минимум эффектов. Меньше нагрузка.",
					}[preset_id], 25)
			_text("2К — детализация изображений. Игра выводится в разрешении экрана.", 23)
			_button("Назад", back)
		"credits":
			_base("Об авторах")
			_text("Оригинальная игра «Ловец душ»\nDynamic Pixels, 2007\n\nНеофициальный ремейк для Android\nАртём · Godot Engine\n\nСюжет, персонажи и тексты — из оригинала.\nНовая графика — с помощью ИИ.\nОзвучка — ElevenLabs Eleven v4.\nМузыка и эффекты созданы для ремейка.")
			_button("Назад", back)
		"help":
			_base("Как играть")
			_text("Найди три души, выполняя поручения обитателей монастыря.\n\nНажми на землю, чтобы идти. Нажми на персонажа или предмет, чтобы подойти и взаимодействовать. Стрелки обозначают переходы.\n\nВ карманах помещаются два предмета. Нажми на предмет справа, чтобы прочитать описание. «Положить» под слотом оставляет его на земле.\n\nНажатие на экран листает диалог. ☰ или «Назад» открывает паузу. Игра сохраняется автоматически.", 27)
			_button("Назад", back)
		"confirm_new":
			_base("Новая игра")
			_text("Начать сначала? Текущее сохранение будет заменено.")
			_button("Начать заново", game.new_game)
			_button("Отмена", back)
	# Keyboard/controller focus also makes desktop testing convenient.
	for child in column.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break


func _request_new() -> void:
	if game.has_save() or game.in_game:
		show_page("confirm_new")
	else:
		game.new_game()


func _select_graphics(preset_id: String) -> void:
	var graphics = game.get("graphics")
	if graphics == null:
		return
	var saved: bool = graphics.set_preset(preset_id)
	show_page("graphics")
	if not saved:
		message("Не удалось сохранить настройки графики. Попробуй ещё раз.")


func _volume(key: String, title: String) -> void:
	var label := _text("%s  %d%%" % [title, roundi(game.sound.settings[key] * 100)])
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = game.sound.settings[key] * 100
	slider.custom_minimum_size = Vector2(0, 58)
	slider.add_theme_constant_override("grabber_area", 32)
	slider.value_changed.connect(func(value):
		game.sound.set_volume(key, value / 100)
		label.text = "%s  %d%%" % [title, int(value)])
	column.add_child(slider)


func back() -> void:
	if page == "graphics":
		show_page("settings")
	elif page in ["settings", "credits", "help", "confirm_new"]:
		show_page(back_page)
	elif page == "pause":
		game.resume_game()
	# Android Back in the main menu stays in the app; Exit is explicit.


func message(text: String) -> void:
	if status == null:
		status = _text(text, 23)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_color_override("font_color", ArtTheme.BRASS)
	else:
		status.text = text
