extends RefCounted
## Shared, scalable stone-and-brass interface; all geometry remains crisp on mobile.

const INK := Color("171b1b")
const EDGE := Color("776144")
const BRASS := Color("c7a465")
const PAPER := Color("eee3cb")
const MUTED := Color("b5b1a2")
# Extracted from the original J2ME resources; gold, edging and transparency are retained.
const TITLE_FONT = preload("res://assets/fonts/original.fnt")


static func panel(fill := INK, border := EDGE, margin := 28) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	return style


static func theme() -> Theme:
	var result := Theme.new()
	TITLE_FONT.set_generate_mipmaps(true)
	result.default_font = TITLE_FONT
	result.default_font_size = 32
	result.set_color("font_color", "Label", PAPER)
	result.set_constant("line_spacing", "Label", 4)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := Color("242927")
		var border := EDGE
		if state == "hover":
			fill = Color("353b33")
			border = BRASS
		elif state == "pressed":
			fill = Color("484334")
			border = Color("e8c786")
		elif state == "disabled":
			fill = Color("1d2221")
			border = Color("474b43")
		var style := panel(fill, border, 18)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 3)
		style.content_margin_top = 9
		style.content_margin_bottom = 9
		result.set_stylebox(state, "Button", style)
		result.set_color("font_%s_color" % state, "Button", PAPER)
	result.set_color("font_color", "Button", PAPER)
	# Color glyphs retain their original RGB; alpha still marks unavailable actions.
	result.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.4))
	var focus := panel(Color.TRANSPARENT, BRASS, 0)
	focus.set_border_width_all(3)
	focus.expand_margin_left = 4
	focus.expand_margin_top = 4
	focus.expand_margin_right = 4
	focus.expand_margin_bottom = 4
	focus.shadow_size = 0
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("focus", "CheckButton", focus)
	result.set_constant("h_separation", "CheckButton", 24)
	result.set_color("font_color", "CheckButton", PAPER)
	result.set_color("font_hover_color", "CheckButton", PAPER)
	result.set_color("font_pressed_color", "CheckButton", PAPER)
	result.set_icon("checked", "CheckButton", preload("res://assets/ui/toggle_on.svg"))
	result.set_icon("unchecked", "CheckButton", preload("res://assets/ui/toggle_off.svg"))
	var track := panel(Color("0d1111"), Color("62614f"), 0)
	track.set_corner_radius_all(4)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	track.shadow_size = 0
	result.set_stylebox("slider", "HSlider", track)
	var progress := panel(Color("a78a56"), BRASS, 0)
	progress.set_border_width_all(0)
	progress.set_corner_radius_all(4)
	progress.content_margin_top = 5
	progress.content_margin_bottom = 5
	progress.shadow_size = 0
	result.set_stylebox("grabber_area", "HSlider", progress)
	result.set_stylebox("grabber_area_highlight", "HSlider", progress)
	result.set_icon("grabber", "HSlider", preload("res://assets/ui/slider_knob.svg"))
	result.set_icon("grabber_highlight", "HSlider", preload("res://assets/ui/slider_knob.svg"))
	return result


static func decorate(control: Control, inset := 10.0, corners_only := false) -> void:
	control.draw.connect(func(): _draw_trim(control, inset, corners_only))
	control.resized.connect(control.queue_redraw)


static func _draw_trim(control: Control, inset: float, corners_only: bool) -> void:
	var extent := control.size
	var edge := Color("8f764d")
	for corner in [Vector2(inset, inset), Vector2(extent.x - inset, inset),
			Vector2(inset, extent.y - inset), extent - Vector2(inset, inset)]:
		var dx := 1.0 if corner.x < extent.x * 0.5 else -1.0
		var dy := 1.0 if corner.y < extent.y * 0.5 else -1.0
		control.draw_line(corner, corner + Vector2(dx * 25, 0), edge, 1.5, true)
		control.draw_line(corner, corner + Vector2(0, dy * 25), edge, 1.5, true)
		var p: Vector2 = corner + Vector2(dx * 4, dy * 4)
		control.draw_circle(p, 2.3, Color("c7a465"), true, -1, true)
	if not corners_only and extent.x > 300:
		var c := Vector2(extent.x * 0.5, inset)
		control.draw_line(c - Vector2(62, 0), c - Vector2(12, 0), edge, 1.5, true)
		control.draw_line(c + Vector2(12, 0), c + Vector2(62, 0), edge, 1.5, true)
		control.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0),
			c + Vector2(0, 4), c + Vector2(-4, 0)]), Color("c7a465"))
